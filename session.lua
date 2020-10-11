local session = {}

local SESSION_FUNCS = {}
local SESSION_MT = {
    __index = SESSION_FUNCS,
    __tostring = function(self)
        if self.workshop_content_path then
            return "nemu.session(steam, root = '" .. self.root_path .. "', save = '" .. self.save_path .. "', workshop = '" .. self.workshop_content_path .. "')"
        else
            return "nemu.session(nonsteam, root = '" .. self.root_path .. "', save = '" .. self.save_path .. "')"
        end
    end
}

function session.new(root_path, save_path, workshop_content_path)
    return setmetatable({
        root_path = root_path,
        save_path = save_path,
        workshop_content_path = workshop_content_path
    }, SESSION_MT)
end

function SESSION_FUNCS:expand_root_path(rel_path)
    return self.root_path .. "/" .. rel_path
end

function SESSION_FUNCS:expand_save_path(rel_path)
    return self.save_path .. "/" .. rel_path
end

function SESSION_FUNCS:expand_workshop_path(rel_path)
    if not self.workshop_content_path then
        return nil
    end
    return self.workshop_content_path .. "/" .. rel_path
end

return session
