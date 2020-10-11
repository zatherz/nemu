local mod_manager = {}

local load_module = _G.NEMU_LOAD_MODULE
if not load_module then
    load_module = dofile
end

local nxml = load_module("libs/luanxml/nxml.lua")

local MOD_MANAGER_FUNCS = {}
local MOD_MANAGER_MT = {
    __index = MOD_MANAGER_FUNCS,
    __tostring = function(self)
        return "nemu.mod_manager"
    end
}

function mod_manager.new(session, fs)
    local f = io.open(session.save_path .. "/mod_config.xml", "r")
    local xml = f:read("*a")
    f:close()

    local metadata = nxml.parse(xml)

    local mods = {}

    for child in metadata:each_child() do
        local real_path

        if child.attr.workshop_item_id == "0" then
            real_path = session:expand_root_path("mods/" .. child.attr.name)
        else
            if not session.workshop_content_path then
                error("tried to cache mod " .. child.attr.name .. ", but no workshop content path has been provided")
            end

            real_path = session:expand_workshop_path(child.attr.workshop_item_id)
        end

        mods[child.attr.name] = {
            enabled = child.attr.enabled == "1",
            active = false,
            workshop_id = tonumber(child.attr.workshop_item_id),
            name = child.attr.name,
            physical_path = real_path
        }
    end

    return setmetatable({
        mods = mods,
        filesystem = fs,
        lua_appends = {},
        current_init_mod = nil,
        last_text_file_changing_mods = {},
        api_version = 4
    }, MOD_MANAGER_MT)
end

function MOD_MANAGER_FUNCS:load_all(engine)
    for mod_name, mod in pairs(self.mods) do
        if mod.enabled then
            local mod_info_f, err = io.open(mod.physical_path .. "/mod.xml", "r")

            if not mod_info_f then
                error(err)
            end

            local mod_info = nxml.parse(mod_info_f:read("*a"))
            mod_info_f:close()

            mod.display_name = mod_info.attr.name
            mod.description = mod_info.attr.description
            mod.unrestrict = mod_info.attr.request_no_api_restrictions == "1"

            if mod_info.attr.is_game_mode == "1" then
                mod.gamemode = {}
                mod.gamemode.name_key = mod_info.attr.ui_newgame_name
                mod.gamemode.description_key = mod_info.attr.ui_newgame_description
                mod.gamemode.banner_bg = mod_info.attr.ui_newgame_gfx_banner_bg
                mod.gamemode.banner_fg = mod_info.attr.ui_newgame_gfx_banner_fg
            end

            local init_env = engine:create_env(mod.unrestrict)
            local init_path = mod.physical_path .. "/init.lua"

            if os.rename(init_path, init_path) then
                local init_script = loadfile(init_path)
                setfenv(init_script, init_env)
                engine:run_in_root(function()
                    init_script()
                end)
            end

            mod.active = true
        end
    end
end

function MOD_MANAGER_FUNCS:is_enabled(id)
    return self.mods[id] ~= nil and self.mods[id].enabled
end

function MOD_MANAGER_FUNCS:get(id)
    return self.mods[id]
end

function MOD_MANAGER_FUNCS:add_lua_append(to, from)
    self.lua_appends[to] = self.lua_appends[to] or {}
    table.insert(self.lua_appends[to], from)
end

function MOD_MANAGER_FUNCS:set_file_content(filename, new_content)
    self.filesystem:set_virtual_file(filename, new_content)
    
    if self.current_init_mod then
        self.last_text_file_changing_mods[filename] = self.current_init_mod
    end
end

function MOD_MANAGER_FUNCS:get_file_content(filename)
    return self.filesystem:open(filename):read()
end

function MOD_MANAGER_FUNCS:who_set_file_content(filename)
    return self.last_text_file_changing_mods[filename] or ""
end

return mod_manager
