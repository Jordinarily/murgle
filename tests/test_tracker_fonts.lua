local H = dofile("tests/helpers.lua")
local UI = dofile("tests/ui_helpers.lua")

local function font(size)
    local f = { path = "native.ttf", size = size, flags = "OUTLINE", writes = 0 }
    function f:GetFont()
        return self.path, self.size, self.flags
    end
    function f:SetFont(path, value, flags)
        self.path, self.size, self.flags = path, value, flags
        self.writes = self.writes + 1
        return true
    end
    return f
end

local function withFonts(fn, size)
    local line, header = font(12), font(14)
    local manager = { updates = 0 }
    function manager:UpdateAll()
        self.updates = self.updates + 1
    end
    function manager:SetTextSize(value)
        if value < 12 or value > 20 then
            return
        end
        line:SetFont("native.ttf", value, "OUTLINE")
        header:SetFont("native.ttf", value + 2, "OUTLINE")
        self:UpdateAll()
    end
    H.withGlobals(
        { ObjectiveTrackerLineFont = line, ObjectiveTrackerHeaderFont = header, ObjectiveTrackerManager = manager },
        function()
            UI.withAddon(function(M, state)
                fn(M, state, line, header, manager)
            end, function(_, state)
                state.fontHooks = 0
                hooksecurefunc = function(target, method, callback)
                    state.fontHooks = state.fontHooks + 1
                    local original = target[method]
                    target[method] = function(self, ...)
                        original(self, ...)
                        callback(self, ...)
                    end
                end
                MurgleDB = { interface = { trackerFontSize = size } }
            end)
        end
    )
end

test("tracker default leaves fonts and native setter untouched", function()
    withFonts(function(M, state, line, header, manager)
        M.Interface.ApplyTrackerFontSize()
        eq(line.writes, 0)
        eq(header.writes, 0)
        eq(manager.updates, 0)
        eq(state.fontHooks, 0)
    end)
end)

test("tracker small fonts preserve face flags and restore both original sizes", function()
    withFonts(function(M, state, line, header, manager)
        eq(line.size, 9)
        eq(header.size, 11)
        eq(line.path, "native.ttf")
        eq(header.flags, "OUTLINE")
        M.Interface.ApplyTrackerFontSize()
        eq(line.writes, 1)
        eq(state.fontHooks, 1)
        MurgleDB.interface.trackerFontSize = 11
        M.Interface.ApplyTrackerFontSize()
        eq(line.size, 11)
        eq(header.size, 13)
        M.ResetDB()
        eq(line.size, 12)
        eq(header.size, 14)
        local updates = manager.updates
        manager:SetTextSize(16)
        eq(line.size, 16)
        eq(manager.updates, updates + 1)
    end, 9)
end)

test("tracker native text-size changes update restoration and retain selected size", function()
    withFonts(function(M, _, line, header, manager)
        manager:SetTextSize(18)
        eq(line.size, 10)
        eq(header.size, 12)
        MurgleDB.interface.trackerFontSize = "default"
        M.Interface.ApplyTrackerFontSize()
        eq(line.size, 18)
        eq(header.size, 20)
    end, 10)
end)

test("tracker font combat queue uses latest choice including reset", function()
    withFonts(function(M, state, line, header)
        state.combat = true
        MurgleDB.interface.trackerFontSize = 9
        M.Interface.ApplyTrackerFontSize()
        eq(line.size, 12)
        MurgleDB.interface.trackerFontSize = 11
        M.Interface.ApplyTrackerFontSize()
        state.combat = false
        local core = state.frames[1]
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(line.size, 11)
        state.combat = true
        M.ResetDB()
        eq(header.size, 13)
        state.combat = false
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(line.size, 12)
        eq(header.size, 14)
        eq(M.GetDeferredCount(), 0)
    end)
end)

test("tracker font missing API skips mutation and explicit apply can retry", function()
    withFonts(function(M, state, line, header, manager)
        local update = manager.UpdateAll
        manager.UpdateAll = nil
        MurgleDB.interface.trackerFontSize = 9
        M.Interface.ApplyTrackerFontSize()
        eq(line.size, 12)
        eq(state.fontHooks, 0)
        manager.UpdateAll = update
        M.Interface.ApplyTrackerFontSize()
        eq(line.size, 9)
        MurgleDB.interface.trackerFontSize = 99
        M.Interface.ApplyTrackerFontSize()
        eq(header.size, 14)
    end)
end)

test("tracker font controls persist size and reset restores default selection", function()
    withFonts(function(M, state, line)
        M.Settings.Show()
        local choice
        for _, frame in ipairs(state.frames) do
            if frame.kind == "Button" then
                for _, region in ipairs(frame.regions) do
                    if region.text == "9" then
                        choice = frame
                    end
                end
            end
        end
        assert(choice, "tracker font size choice exists")
        choice.scripts.OnClick(choice)
        eq(MurgleDB.interface.trackerFontSize, 9)
        eq(line.size, 9)
        M.ResetDB()
        eq(MurgleDB.interface.trackerFontSize, "default")
        eq(line.size, 12)
    end)
end)

test("tracker missing font object fails closed without partial writes", function()
    withFonts(function(M, state, line)
        ObjectiveTrackerHeaderFont = false
        MurgleDB.interface.trackerFontSize = 9
        M.Interface.ApplyTrackerFontSize()
        eq(line.writes, 0)
        eq(state.fontHooks, 0)
    end)
end)

test("tracker restores captured fonts before adopting replacement objects", function()
    withFonts(function(M, _, line, header)
        local nextLine, nextHeader = font(16), font(18)
        ObjectiveTrackerLineFont, ObjectiveTrackerHeaderFont = nextLine, nextHeader
        M.Interface.ApplyTrackerFontSize()
        eq(line.size, 12)
        eq(header.size, 14)
        eq(nextLine.size, 9)
        MurgleDB.interface.trackerFontSize = "default"
        M.Interface.ApplyTrackerFontSize()
        eq(nextLine.size, 16)
        eq(nextHeader.size, 18)
    end, 9)
end)

test("tracker pending disable preserves a newer native size during combat", function()
    withFonts(function(M, state, line, header, manager)
        state.combat = true
        MurgleDB.interface.trackerFontSize = "default"
        M.Interface.ApplyTrackerFontSize()
        manager:SetTextSize(18)
        state.combat = false
        local core = state.frames[1]
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(line.size, 18)
        eq(header.size, 20)
    end, 9)
end)
