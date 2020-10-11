return function(engine, self, env)
    self.globals = {}

    function env.GlobalsSetValue(key, value)
        if type(key) ~= "string" then
            key = engine.string_param_error(self, "key", 1)
        end

        if type(value) ~= "string" then
            value = engine.string_param_error(self, "key", 2)
        end

        if not engine.globals then
            self:panic("Globals are not initialized at this stage")
        end

        self.globals[engine.cstr_trim(key)] = self.cstr_trim(value)
    end

    function env.GlobalsGetValue(key, default_value)
        if type(key) ~= "string" then
            key = engine.string_param_error(self, "key", 1)
        end

        if default_value and type(default_value) ~= "string" then
            default_value = engine.string_param_error(self, "default_value", 2)
        end

        if not engine.globals then
            self:panic("Globals are not initialized at this stage")
        end

        local entry = self.globals[engine.cstr_trim(key)]
        if not entry then return default_value or "" end

        return entry
    end
end
