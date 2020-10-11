nemu
===

NEMU is a collection of related small LuaJIT libraries that aim to emulate a portion of the Noita Lua API.

This project **does not ever aim to reimplement any gameplay or actual functionality of the game**. Instead, it implements the bare essentials to "load" mods:

* Compatible virtual filesystem (`data.wak` support, Steam Workshop mod path redirection etc.)
* Alterations to the Lua standard library (weird `dofile` behavior, `dofile_once` etc)
* `Mod*` functions (`ModIsEnabled`, `ModTextFileSetContent` etc.)

The above features make it possible for external Lua code to load a mod, let it run its `init.lua` in full and possibly later inspect changes to engine state or the global environment (for example, `ModLuaFileAppend` use can be tracked through a `lua_appends` field on the `mod_manager` object).

loading modules
===

In order to make integrating in different Lua environments easier, every module listed below supports making use of a `NEMU_LOAD_MODULE` global function to load modules. This function will receive a canonical, forward-slashed path relative to the root directory of the entire nemu project. It should return the result of calling `dofile` with a path to the intended file.

example
===

Loads all enabled mods, executes them and then prints the list of Lua file appends done through the `ModLuaFileAppend` API function:

```lua
local nemu = {
    session = require("session")
    mod_manager = require("mod_manager")
    vfs = require("vfs")
    engine = require("engine")
}

local root = "/home/zatherz/.local/share/Steam/steamapps/common/Noita"
local session = nemu.session.new(root, root .. "/save00", root .. "/../../workshop/content/881100")
local vfs = nemu.vfs.new_noita(session)
local mod_manager = nemu.mod_manager.new(session, vfs)

vfs:import_mods(mod_manager)

print("SESSION: " .. tostring(s))
print("MOD MANAGER: " .. tostring(m))

local engine = nemu.engine.new(session, vfs, mod_manager, {
    report_stubs = true
})

mod_manager:load_all(engine)

print("LUA APPENDS")
for to_filename, from_list in pairs(m.lua_appends) do
    print("TARGET SCRIPT: " .. to_filename)
    for i, from_filename in ipairs(from_list) do
        print("- " .. from_filename)
    end
end
```

session.lua
===

Uses `luawak` (from `libs/`) internally.

Container for information about a Noita "session" or installation. More specifically - paths to various resources.

* **table** `session`
    * **function** `.new(root_path : string, save_path : string[, workshop_content_path : string])` **returns** `nemu.session`

      `root_path` points to Noita's root directory (the parent of `noita.exe`)  
      `save_path` points to the `save00` directory (usually in AppData)  
      `workshop_content_path` points to the `steamapps/workshop/content/881100` directory in the Steam installation and is optional, if not given, the session is considered to be non-Steam and workshop support will be disabled in other modules (e.g. `vfs.lua`)

* **table type** `nxml.session`
    * **function** `:expand_root_path(rel_path : string)` **returns** `string`

      expands `rel_path` in the context of the root Noita directory

    * **function** `:expand_save_path(rel_path : string)` **returns** `string`

      expands `rel_path` in the context of the save directory (`save00`)

    * **function** `:expand_workshop_path(rel_path ; string)` **returns** `string`

      expands `rel_path` in the context of the game's workshop content directory  
      if ran on a non-Steam session, it will always return `nil`

    * **field** `root_path` **of type** `string`

    * **field** `save_path` **of type** `string`

    * **field** `workshop_content_path` **of type** `string`

      `nil` if accessed on a non-Steam session

vfs.lua
===

Requires `session.lua`.
Noita VFS emulation requires `mod_manager.lua`.

Implements a Noita-like virtual file system.

* **table** `vfs`
    * **function** `.path_parent(path : string)` **returns** `string`

      utility function to get the parent directory of `path`

    * **function** `.path_append(path : string, part : string)` **returns** `string`

      utility function to combine a relative path to an absolute path, or two relative paths

    * **function** `.path_normalize(path : string)` **returns** `string`

      removes excess forward slashes from `path`, creating a canonical path that points to the same place

    * **function** `.path_as_child_of(path : string, parent : string)` **returns** `string`

      if `path` is a child of `parent`, then the part relative from `parent` is extracted from it
      otherwise, `nil` is returned

    * **function** `.path_exists(path : string)` **returns** `string`

      returns `true` if a file under `path` exists, or `false` if not

    * **function** `.new_virtual_file(tostring_info : string, func_impl : table{read : function(nemu.file) -> string}, instance_data : any)` **returns** `nemu.file`

      creates a new virtual file, where reading is implemented by the `read` function of `func_impl` which should return the full content of the file as a string  
      `instance_data` can be anything, and is attached onto the `nemu.file` under the `userdata` field
      `tostring_info` is used when passing the `nemu.file` instance to `tostring()` in order to provide more information about the object

    * **function** `.new_file(real_path : string, vfs_path : string)` **returns** `nemu.file`

      creates a new physical file, where `real_path` is the path on disk and `vfs_path` is the intended path within the virtual filesystem  
      content of physical files can be overriden through the `:set_virtual_file` function

    * **function** `.new(session : nemu.session)` **returns** `nemu.vfs`

      creates a new barebones virtual filesystem from the given `session`  
      note that this function does not apply any kind of special handling of `data.wak` or Steam Workshop mods

    * **function** `.new_noita(session : nemu.session)` **returns** `nemu.vfs`

      creates a new Noita-like virtual filesystem from the given `session`  
      this only registers handlers for `data.wak` overlay - to support Steam Workshop mods, call the `:import_mods` functoin on the newly created `nemu.vfs` table


* **table type** `nemu.vfs`
    * **function** `:add_dir_handler(name : string, dir : string, handler : function(vfs : nemu.vfs, full_path : string) -> nemu.file)`

      registers a directory handler `handler` with the name `name` for all child directories of `dir`  
      after this call, any access to paths that are children of `dir` will be delegated to the provided function, which should return a file or `nil` if the file doesn't exist or can't be accessed for other reasons

    * **function** `:open(path : string)` **returns** `nemu.file`

      opens and returns the file at `path` within the virtual filesystem  
      if the file doesn't exist or can't be accessed, an error will be raised with diagnostic info about where the handling of the file access was delegated to

    * **function** `:set_virtual_file(path : string, content : string)`

      creates a new virtual file filled with `content` at `path` if no file exists at that location  
      if a file already exists at that location, it will override it (the next `:read` on that file will
      return `content)

    * **function** `:import_mods(mod_manager : nemu.mod_manager)`

      registers `mods/.../` path handlers for Steam Workshop mods loaded by the `mod_manager`

* **table type** `nemu.file`

    * **function** `:read()` **returns** `string`

      returns the entire content of the file as a string
    
mod\_manager.lua
===

Requires `session.lua` and `vfs.lua`, as well as `luanxml` (from `libs/`) internally.  
Executing init scripts requires `engine.lua`.

Implements very primitive loading of mods.

* **table** `mod_manager`

    * **function** `.new(session : nemu.session, fs : nemu.vfs)` **returns** `nemu.mod_manager"

      creates a new mod manager

* **table type** `nemu.mod_manager`

    * **function** `:load_all(engine : nemu.engine)`

      runs through the list of loaded and enabled mods, reads all of their `mod.xml` files, executes all of their init scripts using the provided `engine`, then marks them as active

    * **function** `:is_enabled(id : string)` **returns** `boolean`

    * **function** `:get(id : string)` **returns** `table{enabled : boolean, active : boolean, workshop_id : number, name : string, physical_path : string, display_name : string, description : string, unrestrict : boolean, gamemode : table{...}}`

      returns a table with details about the mod with ID `id`

    * **function** `:add_lua_append(to : string, from : string)`

      registers the Lua script at path `from` to be loaded whenever one at path `to` is loaded  
      backing implementation of the `ModLuaFileAppend` API function

    * **function** `:set_file_content(filename : string, new_content : string)`

      overrides the content of the file `filename` within the virtual filesystem with `new_content`  
      backing implementation of the `ModTextFileSetContent` API function
      
    * **function** `:get_file_content(filename : string)`

      reads the content of the file at `filename` within the virtual filesystem, including any overrides
      done through the use of `:set_file_content`  
      backing implementation of the `ModTextFileGetContent` API function

    * **function** `:who_set_file_content(filename : string)`

      returns the ID of the mod that last ended up running `:set_file_content` with `filename` provided
      as the path  
      backing implementation of the `ModTextFileWhoSetContent` API function

engine.lua
===

Requires `session.lua`, `mod_manager.lua` and `vfs.lua`. Internally uses `luawak` and `luanxml` from `libs/`. Also has a hard dependency on the LuaJIT FFI library being available.

Implements the fake Noita Lua environment that allows for executing certain scripts.

* **table** `engine`

    * **function** `.setcwd(path : string)`

      sets the current working directory of the process to `path`

    * **function** `.getcwd()` **returns** `string`

      returns the current working directory of the process

    * **function** `.cstr_trim(str : string)` **returns** `string`

      if `str` contains a null byte, the result will terminate right before it - otherwise, the result will be equivalent to `str`  
      this function is used to emulate C string behavior of certain API functions in the Noita engine, which unintentionally trim strings at the first null byte

    * **function** `.new(session : nemu.session, fs : nemu.vfs, mod_manager : nemu.mod_manager, options : table{...})` **returns** `nemu.engine`

      creates a new engine based on the provided `session`, `fs` and `mod_manager`

      `options` can have the following fields:  
      * `name : string` - controls the name of the engine in diagnostic messages, default `NEMU`
      * `print_prefix : string` - if set, all text printed using `print()` or `print_error()` will be prefixed with this string
      * `report_stubs : boolean` - if `true`, diagnostic messages will be printed whenever a stubbed (unimplemented) function is called

* **table type** `nemu.engine`

    * **function** `:diag(text : string)`

      prints a diagnostic message

    * **function** `:error(reason : string)`

      prints a Noita error  
      note that this is not a Lua error - like in the actual game's API, you cannot catch these errors and they just get printed to the log

    * **function** `:stub()`

      when called within a function, produces a diagnostic message about a stub function being called with the name of the caller

    * **function** `:panic(reason : string)`

      produces an engine panic, which immediately quits the process  
      this emulates situations where Noita would crash natively, like calling `GlobalsSetValue` too early

    * **function** `:create_env(unrestrict : boolean)` **returns** `table{...}`

      creates a new environment  
      if `unrestrict` is `false`, then the environment will be sandboxed in the same way as Noita's, otherwise it will not be sandboxed at all  
      the result of this function is intended to be used with `setfenv`, although note that only doing that will likely break (due to the wrong working directory)  
      use `:run_in_root` with `setfenv` to ensure the working directory gets changed and restored correctly (or simply use `:execute`)

    * **function** `:run_in_root(f : function())`

      runs `f` with no arguments with the Noita root directory as the current working directory (for correct path resolution)
    * **function** `:execute(unrestrict : boolean, f : function())`

      runs `f` under a new environment created by calling `self:create_env(unrestrict)`

