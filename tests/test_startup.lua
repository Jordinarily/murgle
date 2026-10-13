local UI = dofile("tests/ui_helpers.lua")
local H = dofile("tests/helpers.lua")

local function visibleFrame()
    local frame = { shown = true }
    function frame:IsShown()
        return self.shown
    end
    function frame:Show()
        self.shown = true
    end
    function frame:Hide()
        self.shown = false
    end
    return frame
end

test("manifest startup applies saved visibility choices without constructing settings", function()
    local menu, bags = visibleFrame(), visibleFrame()
    UI.withAddon(function(M, state)
        eq(menu.shown, false)
        eq(bags.shown, false)
        eq(#state.frames, 2)
        eq(next(state.frames[1].events), nil)
        eq(state.named.MurgleSettingsFrame, nil)
        M.ResetDB()
        eq(menu.shown, true)
        eq(bags.shown, true)
        eq(#state.frames, 2)
    end, function()
        MicroMenu, BagsBar = menu, bags
        MurgleDB = { interface = { hideMicroMenu = true, hideBagBar = true } }
    end)
end)

test("all visibility controls share combat deferral and reset restores mixed original states", function()
    local controls = {}
    UI.withAddon(function(M, state)
        local core = state.frames[1]
        eq(#controls, 13)
        eq(M.GetDeferredCount(), #controls)
        M.ApplyAllSettings()
        eq(M.GetDeferredCount(), #controls, "repeated application must replace queued requests")
        for i, control in ipairs(controls) do
            eq(control.changes, 0)
            eq(control.shown, i % 2 == 1)
        end
        state.combat = false
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        for _, control in ipairs(controls) do
            eq(control.shown, false)
        end
        eq(M.GetDeferredCount(), 0)
        eq(next(core.events), nil)

        state.combat = true
        M.ResetDB()
        eq(M.GetDeferredCount(), #controls)
        -- Re-enable one option after reset, before the deferred work executes.
        MurgleDB.minimap.hideCalendar = true
        M.Minimap.ApplyCalendar()
        eq(M.GetDeferredCount(), #controls)
        state.combat = false
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        for i, control in ipairs(controls) do
            eq(control.shown, control ~= GameTimeFrame and i % 2 == 1)
        end
        M.ResetDB()
        for i, control in ipairs(controls) do
            eq(control.shown, i % 2 == 1)
        end
        eq(M.GetDeferredCount(), 0)
        eq(next(core.events), nil)
        eq(core.scripts.OnUpdate, nil)
        eq(#state.frames, 2, "feature changes must reuse the one-shot startup frame")
    end, function(_, state)
        local function control()
            local frame = H.newVisibilityFrame(#controls % 2 == 0)
            controls[#controls + 1] = frame
            return frame
        end
        MicroMenu, BagsBar = control(), control()
        ObjectiveTrackerFrame = { Header = control() }
        QuestObjectiveTracker = { Header = control() }
        GameTimeFrame, TimeManagerClockButton = control(), control()
        MinimapCluster = { ZoneTextButton = control(), Tracking = { Button = control() } }
        Minimap = { ZoomIn = control(), ZoomOut = control() }
        ChatFrameMenuButton, ChatFrameChannelButton, ChatFrame2Tab = control(), control(), control()
        state.combat = true
        MurgleDB = {
            interface = { hideMicroMenu = true, hideBagBar = true, objectiveTrackerHeaders = true },
            minimap = {
                hideZoneText = true,
                hideClock = true,
                hideCalendar = true,
                hideTracking = true,
                hideZoomButtons = true,
            },
            chat = { hideButtons = true, hideCombatLog = true },
        }
    end)
end)

test("corrupt saved categories recover through manifest startup and every settings page", function()
    UI.withAddon(function(M, state)
        eq(type(MurgleDB.interface), "table")
        eq(type(MurgleDB.minimap), "table")
        eq(type(MurgleDB.chat), "table")
        eq(MurgleDB.future.keep, true)
        eq(M.GetDeferredCount(), 0)
        eq(next(state.frames[1].events), nil)
        eq(#state.frames, 1)
        M.Settings.Show()
        for _, category in ipairs({
            "Interface",
            "Minimap",
            "Quests",
            "Automation",
            "LootVendors",
            "Chat",
            "Tooltip",
            "ErrorsSound",
        }) do
            M.Settings.SelectCategory(category)
        end
        M.ResetDB()
        eq(M.GetDeferredCount(), 0)
        eq(next(state.frames[1].events), nil)
    end, function(_, state)
        state.combat = true
        MurgleDB = {
            interface = "broken",
            minimap = false,
            chat = 42,
            frames = true,
            automation = false,
            lootVendors = "broken",
            tooltip = 42,
            errors = false,
            sound = true,
            future = { keep = true },
        }
    end)
end)

test("startup during combat queues saved changes and reset cancels their effect", function()
    local menu, bags = visibleFrame(), visibleFrame()
    UI.withAddon(function(M, state)
        local core = state.frames[1]
        eq(M.GetDeferredCount(), 2)
        eq(menu.shown, true)
        eq(bags.shown, true)
        eq(core:IsEventRegistered("ADDON_LOADED"), false)
        M.ResetDB()
        state.combat = false
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(menu.shown, true)
        eq(bags.shown, true)
        eq(M.GetDeferredCount(), 0)
        eq(next(core.events), nil)
        eq(#state.frames, 2)
    end, function(_, state)
        state.combat = true
        MicroMenu, BagsBar = menu, bags
        MurgleDB = { interface = { hideMicroMenu = true, hideBagBar = true } }
    end)
end)

test("unavailable saved feature does not prevent startup or the other feature", function()
    local bags = visibleFrame()
    UI.withAddon(function(M, state)
        eq(bags.shown, false)
        eq(type(SlashCmdList.MURGLE), "function")
        eq(next(state.frames[1].events), nil)
        SlashCmdList.MURGLE("")
        eq(state.named.MurgleSettingsFrame:IsShown(), true)
        M.ResetDB()
        eq(bags.shown, true)
    end, function()
        MicroMenu, BagsBar = false, bags
        MurgleDB = { interface = { hideMicroMenu = true, hideBagBar = true } }
    end)
end)

test("login reapplies saved menu and bag visibility after native initialization", function()
    UI.withAddon(function(M, state)
        local startup
        for _, frame in ipairs(state.frames) do
            if frame.events.PLAYER_ENTERING_WORLD then
                startup = frame
            end
        end
        assert(startup, "saved visibility needs a one-shot login retry")
        MicroMenu:Show()
        BagsBar:Show()
        startup.scripts.OnEvent(startup, "PLAYER_ENTERING_WORLD")
        eq(MicroMenu.shown, false)
        eq(BagsBar.shown, false)
        eq(next(startup.events), nil)
        M.ResetDB()
        eq(MicroMenu.shown, true)
    end, function()
        MicroMenu, BagsBar = visibleFrame(), visibleFrame()
        MurgleDB = { interface = { hideMicroMenu = true, hideBagBar = true } }
    end)
end)
