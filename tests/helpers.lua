local Helpers = {}

function Helpers.addonFiles()
    local paths = {}
    for line in io.lines("Murgle.toc") do
        local path = line:match("^%s*(.-)%s*$")
        if path ~= "" and path:sub(1, 1) ~= "#" then
            paths[#paths + 1] = path
        end
    end
    return paths
end

function Helpers.loadAddonFile(path, addonTable)
    local chunk = assert(loadfile(path))
    chunk("Murgle", addonTable)
end

function Helpers.newEventFrame()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event)
        self.events[event] = true
    end
    function frame:UnregisterEvent(event)
        self.events[event] = nil
    end
    function frame:SetScript(name, fn)
        self.scripts[name] = fn
    end
    function frame:IsEventRegistered(event)
        return self.events[event] == true
    end
    return frame
end

function Helpers.withGlobals(values, fn)
    local old, keys = {}, {}
    for key, value in pairs(values) do
        keys[#keys + 1] = key
        old[key] = { exists = _G[key] ~= nil, value = _G[key] }
        _G[key] = value
    end
    local ok, err = pcall(fn)
    for _, key in ipairs(keys) do
        if old[key].exists then
            _G[key] = old[key].value
        else
            _G[key] = nil
        end
    end
    if not ok then
        error(err, 0)
    end
end

function Helpers.newVisibilityFrame(shown)
    local frame = { shown = shown, changes = 0, scripts = {} }
    function frame:IsProtected()
        return self.protected == true
    end
    function frame:HookScript(name, fn)
        self.scripts[name] = fn
    end
    function frame:IsShown()
        return self.shown
    end
    function frame:Hide()
        self.shown = false
        self.changes = self.changes + 1
    end
    function frame:Show()
        local wasShown = self.shown
        self.shown = true
        self.changes = self.changes + 1
        if not wasShown and self.scripts.OnShow then
            self.scripts.OnShow(self)
        end
    end
    return frame
end

return Helpers
