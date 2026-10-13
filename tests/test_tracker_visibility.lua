local H = dofile("tests/helpers.lua")
local UI = dofile("tests/ui_helpers.lua")

local function fixture(_, state)
    ObjectiveTrackerFrame = H.newVisibilityFrame(true)
    state.hooks = 0
    hooksecurefunc = function(object, method, callback)
        state.hooks = state.hooks + 1
        local original = object[method]
        object[method] = function(self, ...)
            original(self, ...)
            callback(self, ...)
        end
    end
end

test("tracker default is inert and hidden mode respects subsequent native visibility", function()
    UI.withAddon(function(M, state)
        local frame = ObjectiveTrackerFrame
        eq(state.hooks, 0)
        eq(frame.changes, 0)
        MurgleDB.interface.objectiveTrackerVisibility = "hidden"
        M.Interface.ApplyTrackerVisibility()
        eq(frame.shown, false)
        frame:Show()
        eq(frame.shown, false)
        frame:Hide()
        MurgleDB.interface.objectiveTrackerVisibility = "always"
        M.Interface.ApplyTrackerVisibility()
        eq(frame.shown, false, "do not revive a tracker Blizzard no longer wants shown")
        frame:Show()
        eq(frame.shown, true)
        eq(#state.frames, 1, "hidden mode needs no event frame")
    end, fixture)
end)

test("tracker out of combat mode retains its existing transitions", function()
    UI.withAddon(function(M, state)
        local frame = ObjectiveTrackerFrame
        MurgleDB.interface.objectiveTrackerVisibility = "ooc"
        M.Interface.ApplyTrackerVisibility()
        eq(frame.shown, true)
        local events = state.frames[#state.frames]
        state.combat = true
        events.scripts.OnEvent()
        eq(frame.shown, false)
        state.combat = false
        events.scripts.OnEvent()
        eq(frame.shown, true)
        M.ResetDB()
        eq(next(events.events), nil)
        eq(frame.shown, true)
    end, fixture)
end)

test("retired tracker combat choice migrates to native visibility without listeners", function()
    UI.withAddon(function(M, state)
        eq(MurgleDB.interface.objectiveTrackerVisibility, "always")
        eq(ObjectiveTrackerFrame.shown, true)
        eq(state.hooks, 0)
        eq(#state.frames, 1)
        MurgleDB.interface.objectiveTrackerVisibility = "combat"
        M.Interface.ApplyTrackerVisibility()
        eq(ObjectiveTrackerFrame.shown, true)
        eq(state.hooks, 0)
        M.Settings.Show()
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                assert(region.text ~= M.L.COMBAT, "retired tracker Combat control is still present")
            end
        end
    end, function(M, state)
        fixture(M, state)
        MurgleDB = { interface = { objectiveTrackerVisibility = "combat" } }
    end)
end)

test("tracker refuses protected roots and invalid modes release ownership", function()
    UI.withAddon(function(M, state)
        ObjectiveTrackerFrame.protected = true
        MurgleDB.interface.objectiveTrackerVisibility = "hidden"
        M.Interface.ApplyTrackerVisibility()
        eq(ObjectiveTrackerFrame.shown, true)
        eq(state.hooks, 0)
        ObjectiveTrackerFrame.protected = false
        M.Interface.ApplyTrackerVisibility()
        eq(ObjectiveTrackerFrame.shown, false)
        MurgleDB.interface.objectiveTrackerVisibility = "invalid"
        M.Interface.ApplyTrackerVisibility()
        eq(ObjectiveTrackerFrame.shown, true)
    end, fixture)
end)
