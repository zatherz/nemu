return function(engine, self, env)
    function env.ModIsEnabled(id)
        return self.mod_manager:is_enabled(id)
    end

    function env.ModGetActiveModIDs()
        local ids = {}
        local n = 0

        for k, v in pairs(self.mod_manager.mods) do
            if v.active then
                n = n + 1
                ids[n] = v.name
            end
        end

        return ids
    end

    function env.ModGetAPIVersion()
        return self.mod_manager.api_version
    end

    function env.ModLuaFileAppend(to_filename, from_filename)
        self.mod_manager:add_lua_append(to_filename, from_filename)
    end

    function env.ModTextFileGetContent(filename)
        return self.mod_manager:get_file_content(filename)
    end

    function env.ModTextFileSetContent(filename, new_content)
        return self.mod_manager:set_file_content(filename, new_content)
    end

    function env.ModTextFileWhoSetContent(filename)
        return self.mod_manager:who_set_file_content(filename)
    end

    function env.ModMagicNumbersFileAdd(filename)
        self:stub()
    end

    function env.ModMaterialsFileAdd(filename)
        self:stub()
    end

    function env.ModRegisterAudioEventMappings(filename)
        self:stub()
    end

    function env.ModDevGenerateSpriteUVsForDirectory(dir)
        self:stub()
    end
end
