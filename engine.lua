local engine = { }

local load_module = _G.NEMU_LOAD_MODULE
if not load_module then
    load_module = dofile
end

local func_lists = load_module("engine/func_lists.lua")
local vfs = load_module("vfs.lua")
local wak = load_module("libs/luawak/wak.lua")
local nxml = load_module("libs/luanxml/nxml.lua")
local ffi = require("ffi")

local ENGINE_FUNCS = {}
local ENGINE_MT = { __index = ENGINE_FUNCS }

local getcwd, chdir

if ffi.os == "Windows" then
    ffi.cdef[[
    char* _getcwd(char* buf, size_t size);
    int _chdir(const char* path);
    ]]

    getcwd = ffi.C._getcwd
    chdir = ffi.C._chdir
else
    ffi.cdef[[
    char* getcwd(char* buf, size_t size);
    int chdir(const char* path);
    ]]

    getcwd = ffi.C.getcwd
    chdir = ffi.C.chdir
end

function engine.setcwd(path)
    chdir(path)
end

function engine.getcwd(path)
    local size = 256
    local result = nil

    while result == nil do
        local buf = ffi.new("char[?]", size)
        result = getcwd(buf, size)
    end

    return ffi.string(result)
end

function engine.new(session, fs, mod_manager, options)
    options = options or {}
    local name = options.name or "NEMU"
    local print_prefix = options.print_prefix or ""

    return setmetatable({
        options = options,
        session = session,
        filesystem = fs,
        mod_manager = mod_manager,
        name = name,
        print_prefix = print_prefix or ""
    }, ENGINE_MT)
end

local function unimpl(name, info)
    error("API function " .. name .. " is not implemented: " .. info)
end

function engine.cstr_trim(str)
    return string.match(str, "[^%z]*")
end

if require then
    local ffi = nil
    pcall(function() ffi = require("ffi") end)

    if ffi then
        function engine.cstr_trim(str)
            return ffi.string(ffi.cast("const char*", str))
        end
    end
end

function ENGINE_FUNCS:diag(text)
    local caller = debug.getinfo(2, "Sn")

    print("=== ENGINE DIAGNOSTIC ===")
    print("Source: " .. self.name)
    print(text)
    print("=========================")
end

function ENGINE_FUNCS:error(reason)
    -- this is not a lua error - it is a noita error, i.e. you can't catch it in lua
    io.write(self.print_prefix .. reason)
end

function ENGINE_FUNCS:stub()
    if self.options.report_stubs then
        local name = debug.getinfo(1, "n").name
        self:diag("Stub called (" .. name .. ")\n" .. debug.traceback())
    end
end

function engine.string_param_error(self, name, index)
    self:error("LUA: LUA - " .. name .. " param " .. index .. " wasn't a string, string was expected\n")
    return ""
end

function engine.param_error(self, func_name, expected_count, passed_count)
    local caller_file = debug.getinfo(3, "S").source
    self:error("LUA Error in (" .. caller_file .. "): " .. func_name .. " requires " .. expected_count .. " params, only " .. passed_count .. " given\n")
end

function ENGINE_FUNCS:panic(reason)
    print("=== ENGINE PANIC ===")
    print("A panic represents a condition in which Noita would crash natively.")
    print("Source: " .. self.name)
    print("Reason: " .. reason)
    local traceback = debug.traceback()
    print(traceback)
    print("======================")
    os.exit(1)
end

local function openlib_base(env)
    env.coroutine = coroutine
    env.assert = assert
    env.tostring = tostring
    env.tonumber = tonumber
    env.rawget = rawget
    env.xpcall = xpcall
    env.ipairs = ipairs
    env.print = print
    env.pcall = pcall
    env.gcinfo = gcinfo
    env.setfenv = setfenv
    env.pairs = pairs
    env.error = error
    env.loadfile = loadfile
    env.rawequal = rawequal
    env._VERSION = _VERSION
    env.newproxy = newproxy
    env.collectgarbage = collectgarbage

    local later_def = function() unimpl("dofile", "Not defined by reason of later redefinition or removal") end

    env.dofile = later_def
    env.next = next
    env.loadstring = later_def
    env.load = later_def
    env.unpack = unpack
    env._G = env
    env.select = select
    env.rawset = rawset
    env.type = type
    env.getmetatable = getmetatable
    env.getfenv = getfenv
    env.setmetatable = setmetatable
end

local function openlib_package(env)
    env.module = module
    env.package = package
    env.require = require
end

local function openlib_string(env)
    env.string = string
end

local function openlib_table(env)
    env.table = table
end

local function openlib_math(env)
    env.math = math
end

local function openlib_io(env)
    env.io = io
end

local function openlib_os(env)
    env.os = os
end

local function openlib_debug(env)
    env.debug = debug
end

local function openlib_bit(env)
    env.bit = bit
end

local function openlib_jit(env)
    env.jit = jit
end

local function openlib_ffi(env)
    -- no changes to _G - ffi has to be require()'d from lua to be used
end

local function openlibs(env)
    openlib_base(env)
    openlib_package(env)
    openlib_string(env)
    openlib_table(env)
    openlib_math(env)
    openlib_io(env)
    openlib_os(env)
    openlib_debug(env)
    openlib_bit(env)
    openlib_jit(env)
end

local function init_env(env, unrestrict)
    if not unrestrict then
        openlib_base(env)
        openlib_math(env)
        openlib_string(env)
        openlib_table(env)
        openlib_bit(env)
        openlib_jit(env)

        env.load = nil
        env.loadfile = nil
        env.loadstring = nil
        env.gcinfo = nil
        env.collectgarbage = nil
    else
        openlibs(env)
    end
end

local function load_sub_api(name, engine_instance, env)
    local f = load_module("engine/" .. name .. ".lua")
    f(engine, engine_instance, env)
end

function ENGINE_FUNCS:create_env(unrestrict)
    local env = {}

    for i, v in ipairs(func_lists.INIT) do
        env[v] = function()
            return self:stub()
        end
    end

    for i, v in ipairs(func_lists.STANDARD) do
        env[v] = function()
            return self:stub()
        end
    end

    env._G = env

    init_env(env, unrestrict)

    env.print = function(str)
        if type(str) ~= "string" then
            str = engine.string_param_error(self, "print( ... )", 1)
        end

        print(self.print_prefix .. "LUA: " .. str)
    end

    env.print_error = function(str)
        if type(str) ~= "string" then
            str = engine.string_param_error(self, "print_error( ... )", 1)
        end

        io.stderr:write(self.print_prefix .. "LUA: " .. str .. "\n")
    end

    env.loadfile = function(path)
        local file = self.filesystem:open(path)
        local content = loadstring(file:read(), path)

        local f, err = loadfile(path)
        if not f then return f, err end

        setfenv(f, env)

        return f, nil
    end

    env.do_mod_appends = function(...)
        local n = select("#", ...)

        if self.mod_manager.lua_appends then
            if n < 1 then
                engine.param_error(self, "do_mod_appends( filename )", 1, n)
            end
        end

        local path = ...

        if type(path) ~= "string" then
            path = engine.string_param_error(self, "do_mod_appends( filename )", 1)
        end

        local append_list = self.mod_manager.lua_appends[path]

        if append_list then
            for i = 1, #append_list do
                local ok, err = pcall(function()
                    env.dofile(append_list[i])
                end)

                if not ok then
                    self:error("Lua error doing Mods_ApplyLuaAppends(" .. path .. ") - " .. err .. "\n")
                end
            end
        end
    end

    env.__loadonce = {}
    env.__loaded = {}

    function env.dofile(path)
        local f = env.__loaded[path]
        if f == nil then
            --@NOITABUG err is global
            f, env.err = env.loadfile(path)
            if f == nil then
                return f, env.err
            end

            env.__loaded[path] = f
        end

        local result = f()

        env.do_mod_appends(path)

        return result
    end

    function env.dofile_once(path)
        local result = nil
        local cached = env.__loadonce[path]
        if cached ~= nil then
            result = cached[1]
        else
            local f, err = env.loadfile(path)
            if f == nil then
                return f, err
            end

            result = f()
            env.__loadonce[path] = {result}

            env.do_mod_appends(path)
        end

        return result
    end

    load_sub_api("globals", self, env)
    load_sub_api("mods", self, env)

    return env
end

function ENGINE_FUNCS:run_in_root(f)
    local old_cwd = engine.getcwd()
    engine.setcwd(self.session.root_path)
    f()
    engine.setcwd(old_cwd)
end

function ENGINE_FUNCS:execute(unrestrict, f)
    local env = self:create_env(unrestrict)

    local old_cwd = engine.getcwd()
    engine.setcwd(self.session.root_path)

    local old_env = getfenv(f)
    setfenv(f, env)
    f()
    setfenv(f, old_env)

    engine.setcwd(old_cwd)
end

local root = "/home/zatherz/.local/share/Steam/steamapps/common/Noita"

local session = load_module("session.lua")
local s = session.new(root, root .. "/save00", root .. "/../../workshop/content/881100")

local mod_manager = load_module("mod_manager.lua")

local fs = vfs.new_noita(s)
local m = mod_manager.new(s, fs)

fs:import_mods(m)

print("SESSION: " .. tostring(s))
print("MOD MANAGER: " .. tostring(m))

local eng = engine.new(s, fs, m, {
    report_stubs = true
})

m:load_all(eng)

for k, v in pairs(m.lua_appends) do
    print(k)
    for i, v2 in ipairs(v) do
        print(v2)
    end
end

return engine
