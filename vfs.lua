local vfs = {}

local load_module = _G.NEMU_LOAD_MODULE
if not load_module then
    load_module = dofile
end

local nxml = load_module("libs/luanxml/nxml.lua")
local wak = load_module("libs/luawak/wak.lua")

local FILE_FUNCS = {}
local FILE_MT = {
    __index = FILE_FUNCS,
    __tostring = function(self)
        if self._virtual then
            if self._tostring_info then
                return "nemu.file(virtual, " .. self._tostring_info .. ")"
            end
            return "nemu.file(virtual, <anon>)"
        end

        return "nemu.file(physical, " .. self.vfs_path .. ")"
    end
}


local VFS_FUNCS = {}
local VFS_MT = {
    __index = VFS_FUNCS,
    __tostring = function(self)
        return "nemu.vfs(" .. (self.root or ".") .. ")"
    end
}

function vfs.path_parent(path)
    return string.match(path, "(.-)/+[^/]*$") or nil
end

function vfs.path_append(path, part)
    if not path then return part end

    return path .. "/" .. part
end

function vfs.path_normalize(path)
    local normalized = string.gsub(path, "/+", "/")
    local n = #normalized
    if normalized:sub(n, n) == "/" then return normalized:sub(1, -2) end
    return normalized
end

function vfs.path_as_child_of(path, parent)
    path = vfs.path_normalize(path)
    parent = vfs.path_normalize(parent)

    local n = #parent

    if path:sub(1, n) ~= parent then return nil end

    return path:sub(n + 2, #path)
end

function vfs.new(session)
    return setmetatable({
        root = session.root_path,
        session = session,
        _handler_list = {},
        _loaded_files = {}
    }, VFS_MT)
end

-- handler signature: (vfs : nemu.vfs, full_path : string) -> nemu.file
function VFS_FUNCS:add_dir_handler(name, dir, handler)
    local normalized = vfs.path_normalize(dir)
    self._handler_list[#self._handler_list + 1] = {
        name = name,
        pattern = normalized .. "/",
        func = handler
    }
end

local function acquire_handler(vfs, path)
    for i = 1, #vfs._handler_list do
        local data = vfs._handler_list[i]
        local n = #data.pattern

        if path:sub(1, n) == data.pattern then
            return data
        end
    end
end

function vfs.new_virtual_file(tostring_info, func_impl, instance_data)
    return setmetatable({
        _virtual = true,
        _read_impl = func_impl.read,
        userdata = instance_data,
        _tostring_info = tostring_info
    }, FILE_MT)
end

function vfs.new_file(real_path, vfs_path)
    return setmetatable({
        _virtual = false,
        _path = real_path,
        vfs_path = vfs_path,
        _content = nil,
    }, FILE_MT)
end

local function new_memory_file(vfs_path, content)
    return setmetatable({
        _virtual = true,
        vfs_path = vfs_path,
        _content = content,
        _tostring_info = "memory"
    }, FILE_MT)
end

function vfs.path_exists(path)
    return os.rename(path, path)
end

local function real_disk_path(self, path)
    if self.root then return self.root .. "/" .. path end
    return path
end

function VFS_FUNCS:open(path)
    path = vfs.path_normalize(path)

    local loaded = self._loaded_files[path]
    if loaded then return loaded end

    local handler = acquire_handler(self, path)
    if handler then
        local f = handler.func(self, path)

        if f then
            f.vfs_path = path
            self._loaded_files[path] = f
        else
            error("virtual file not found: " .. path .. " (handled by '" .. handler.name .. "' for all '" .. handler.pattern .. "' paths)")
        end

        return f
    end

    local disk_path = real_disk_path(self, path)

    if not vfs.path_exists(disk_path) then
        error("physical file not found: " .. path)
    end

    local f = vfs.new_file(disk_path, path)
    self._loaded_files[f.vfs_path] = f
    return f
end

function VFS_FUNCS:set_virtual_file(path, content)
    path = vfs.path_normalize(path)
    local loaded = self._loaded_files[path]
    if not loaded then
        loaded = new_memory_file(path, content)
        self._loaded_files[path] = loaded
    else
        loaded._content = content
    end
end

function FILE_FUNCS:read()
    if self._content then return self._content end

    if self._read_impl then 
        self._content = self._read_impl(self)
        return self._content
    end

    if not self._path then
        error("virtual file doesn't have a read implementation nor a physical path: " .. tostring(self))
    end

    local f = io.open(self._path, "rb")
    local data = f:read("*a")
    f:close()

    self._content = data

    return data
end

local DATA_WAK_VIRTUAL_DIR_IMPL = {
    read = function(file)
        local wak_f = file.userdata
        return wak_f:read()
    end,
}

local WORKSHOP_MOD_VIRTUAL_DIR_IMPL = {
    read = function(file)
        local workshop_path = file.userdata
        
        local f = io.open(workshop_path, "r")
        if not f then return nil end

        local content = f:read("*a")
        f:close()

        return content
    end
}

function vfs.new_noita(session)
    local fs = vfs.new(session)
    local wak = wak.open(session:expand_root_path("data/data.wak"))

    fs:add_dir_handler("data.wak overlay", "data/", function(fs, full_path)
        local real_path = session:expand_root_path(full_path)
        if vfs.path_exists(real_path) then
            return vfs.new_file(real_path, full_path)
        end

        local f = wak:open(full_path)
        if not f then return nil end
        return vfs.new_virtual_file("data.wak::" .. full_path, DATA_WAK_VIRTUAL_DIR_IMPL, f)
    end)

    return fs
end

function VFS_FUNCS:import_mods(mod_manager) 
    for id, mod in pairs(mod_manager.mods) do
        if mod.workshop_id ~= 0 then
            local workshop_mod_path = self.session:expand_workshop_path(tostring(mod.workshop_id))
            local mod_id_path = workshop_mod_path .. "/mod_id.txt"

            local mod_id
            local mod_id_f = io.open(mod_id_path, "r")
            if mod_id_f then
                mod_id = mod_id_f:read("*a")
                mod_id_f:close()
            else
                mod_id = elem.attr.name
            end

            local virtual_mods_path = "mods/" .. mod_id

            self:add_dir_handler("workshop overlay for " .. mod_id, virtual_mods_path, function(fs, full_path)
                local child_path = vfs.path_as_child_of(full_path, virtual_mods_path)
                if not child_path then return nil end

                local workshop_mod_child_path = workshop_mod_path .. "/" .. child_path

                if not vfs.path_exists(workshop_mod_child_path) then
                    return nil
                end

                return vfs.new_virtual_file("workshop(" .. mod_id .. ", " .. mod.workshop_id .. ")::" .. child_path, WORKSHOP_MOD_VIRTUAL_DIR_IMPL, workshop_mod_child_path)
            end)

        end
    end
end

return vfs
