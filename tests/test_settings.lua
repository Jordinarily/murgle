local UI = dofile("tests/ui_helpers.lua")

local function clickText(state, text)
    for _, frame in ipairs(state.frames) do
        if frame.kind == "Button" then
            for _, region in ipairs(frame.regions) do
                if region.text == text then
                    frame.scripts.OnClick(frame)
                    return
                end
            end
        end
    end
    error("button not found: " .. text)
end

test("settings create nothing at startup and toggle a reused window on demand", function()
    UI.withAddon(function(M, state)
        eq(#state.frames, 1)
        eq(next(StaticPopupDialogs), nil)
        eq(type(M.Settings.Toggle), "function")
        SlashCmdList.MURGLE("")
        local window = state.named.MurgleSettingsFrame
        eq(window:IsShown(), true)
        eq(UISpecialFrames[1], "MurgleSettingsFrame")
        local created = #state.frames
        SlashCmdList.MURGLE("")
        eq(window:IsShown(), false)
        SlashCmdList.MURGLE("")
        eq(window:IsShown(), true)
        eq(#state.frames, created)
        for _, frame in ipairs(state.frames) do
            eq(frame.scripts.OnUpdate, nil)
            eq(next(frame.events), nil)
        end
    end)
end)

test("interface checkbox and reset use the real combat queue and restore the frame", function()
    UI.withAddon(function(M, state)
        local menu = { shown = true }
        function menu:IsShown()
            return self.shown
        end
        function menu:Hide()
            self.shown = false
        end
        function menu:Show()
            self.shown = true
        end
        MicroMenu = menu
        M.Settings.Show()
        local checkbox
        for _, frame in ipairs(state.frames) do
            if frame.kind == "CheckButton" then
                checkbox = frame
                break
            end
        end
        assert(checkbox)
        local core = state.frames[1]
        state.combat = true
        checkbox:SetChecked(true)
        checkbox.scripts.OnClick(checkbox)
        eq(MurgleDB.interface.hideMicroMenu, true)
        eq(menu.shown, true)
        eq(M.GetDeferredCount(), 1)
        eq(core:IsEventRegistered("PLAYER_REGEN_ENABLED"), true)
        state.combat = false
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(menu.shown, false)
        eq(M.GetDeferredCount(), 0)
        eq(next(core.events), nil)
        state.combat = true
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(checkbox:GetChecked(), false)
        eq(menu.shown, false)
        eq(M.GetDeferredCount(), 1)
        state.combat = false
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(menu.shown, true)
        eq(M.GetDeferredCount(), 0)
        eq(next(core.events), nil)
    end)
end)

test("category navigation lazily creates one page then reuses it across reopen", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        local created = #state.frames
        clickText(state, "Minimap")
        assert(#state.frames > created)
        local pageCreated = #state.frames
        local minimapPage = state.frames[created + 1]
        eq(minimapPage:IsShown(), true)
        clickText(state, "Interface")
        eq(#state.frames, pageCreated)
        eq(minimapPage:IsShown(), false)
        clickText(state, "Minimap")
        M.Settings.Hide()
        M.Settings.Show()
        eq(minimapPage:IsShown(), true)
        eq(#state.frames, pageCreated)
        eq(MurgleDB.selectedCategory, nil)
        M.Settings.SelectCategory("unrecognized")
        eq(minimapPage:IsShown(), true)
        eq(#state.frames, pageCreated)
    end)
end)

test("close button hides the settings window without destroying its pages", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        local created = #state.frames
        clickText(state, "Close")
        eq(state.named.MurgleSettingsFrame:IsShown(), false)
        M.Settings.Show()
        eq(#state.frames, created)
    end)
end)

test("reset is lazy and changes nothing until explicitly accepted", function()
    UI.withAddon(function(M, state)
        MurgleDB.interface.hideTalkingHead = false
        local before = MurgleDB
        SlashCmdList.MURGLE("R")
        eq(#state.frames, 1, "reset command must not build the settings window")
        eq(#state.popups, 1)
        local popup = StaticPopupDialogs[state.popups[1]]
        eq(type(popup), "table")
        eq(popup.hideOnEscape, true)
        eq(MurgleDB, before)
        eq(MurgleDB.interface.hideTalkingHead, false)
        if popup.OnCancel then
            popup.OnCancel()
        end
        eq(MurgleDB, before)
        M.Settings.Show()
        popup.OnAccept()
        eq(MurgleDB == before, false)
        eq(MurgleDB.interface.hideTalkingHead, true)
        eq(state.named.MurgleSettingsFrame:IsShown(), true)
        SlashCmdList.MURGLE("reset")
        eq(StaticPopupDialogs[state.popups[2]], popup)
    end)
end)

test("interface checkboxes persist choices and reset refreshes cached controls", function()
    UI.withAddon(function(M, state)
        local menuCalls, bagCalls = 0, 0
        M.Interface = {
            IsBetaBuild = function()
                return false
            end,
            ApplyMicroMenu = function()
                menuCalls = menuCalls + 1
            end,
            ApplyBagBar = function()
                bagCalls = bagCalls + 1
            end,
            ApplyAll = function() end,
        }
        M.Settings.Show()
        local checks = {}
        for _, frame in ipairs(state.frames) do
            if frame.kind == "CheckButton" then
                checks[#checks + 1] = frame
            end
        end
        eq(#checks, 13)
        eq(checks[1]:GetChecked(), false)
        checks[1]:SetChecked(true)
        checks[1].scripts.OnClick(checks[1])
        eq(MurgleDB.interface.hideMicroMenu, true)
        eq(menuCalls, 1)
        checks[2]:SetChecked(true)
        checks[2].scripts.OnClick(checks[2])
        eq(MurgleDB.interface.hideBagBar, true)
        eq(bagCalls, 1)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(checks[1]:GetChecked(), false)
        eq(checks[2]:GetChecked(), false)
    end)
end)

test("XP checkbox persists hide choice and confirmed reset restores native display", function()
    UI.withAddon(function(M, state)
        local calls = 0
        M.Interface.ApplyXP = function()
            calls = calls + 1
        end
        M.Settings.Show()
        eq(MurgleDB.interface.hideXP, false)
        local control
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                if M.L.HIDE_XP and region.text == M.L.HIDE_XP then
                    control = frame
                end
            end
        end
        assert(control, "Hide XP bar checkbox exists")
        control:SetChecked(true)
        control.scripts.OnClick(control)
        eq(MurgleDB.interface.hideXP, true)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(MurgleDB.interface.hideXP, false)
        eq(control:GetChecked(), false)
    end)
end)

test("beta navigation is absent outside beta including direct selection", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        local count = #state.frames
        M.Settings.SelectCategory("Beta")
        eq(#state.frames, count)
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                assert(region.text ~= "Beta", "beta navigation on non-beta client")
                assert(region.text ~= "Performance", "removed category remains")
            end
        end
    end)
end)

test("bulk changes restore owned frames and last combat choice wins", function()
    UI.withAddon(function(M, state)
        local H = dofile("tests/helpers.lua")
        MicroMenu = H.newVisibilityFrame(true)
        M.Settings.Show()
        clickText(state, "Disable all")
        clickText(state, "Enable all")
        eq(MicroMenu.shown, false)
        state.combat = true
        clickText(state, "Disable all")
        clickText(state, "Enable all")
        clickText(state, "Disable all")
        eq(MicroMenu.shown, false)
        state.combat = false
        local core = state.frames[1]
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(MicroMenu.shown, true)
        eq(M.GetDeferredCount(), 0)
        eq(MurgleDB.lootVendors.sellJunk, false)
    end)
end)

test("removed reward values have no runtime module or settings control", function()
    UI.withAddon(function(M, state)
        eq(M.RewardValues, nil)
        eq(M.DEFAULTS.quests.rewardSellValues, nil)
        M.Settings.Show()
        M.Settings.SelectCategory("Quests")
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                assert(region.text ~= "Show reward sell values")
            end
        end
    end)
end)

test("settings header drags the window without making controls draggable", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        local window = state.named.MurgleSettingsFrame
        eq(window.movable, true)
        eq(window.clamped, true)
        local header
        for _, frame in ipairs(state.frames) do
            if frame.dragButton then
                header = frame
            end
            if frame.kind == "Button" or frame.kind == "CheckButton" then
                eq(frame.scripts.OnDragStart, nil)
            end
        end
        assert(header, "header drag surface missing")
        header.scripts.OnDragStart(header)
        eq(window.moving, true)
        header.scripts.OnDragStop(header)
        eq(window.moving, false)
        eq(window.scripts.OnUpdate, nil)
        eq(MurgleDB.position, nil)
    end)
end)

test("both page bulk buttons remain available after individual settings and reset", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        local function countBulk()
            local count = 0
            for _, frame in ipairs(state.frames) do
                if frame.kind == "Button" then
                    for _, region in ipairs(frame.regions) do
                        if region.text == "Enable all" or region.text == "Disable all" then
                            count = count + 1
                        end
                    end
                end
            end
            return count
        end
        eq(countBulk(), 2)
        clickText(state, "Disable all")
        eq(MurgleDB.automation.autoQuest, false)
        local menu = state.frames[1]
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                if region.text == M.L.HIDE_MICRO_MENU then
                    menu = frame
                end
            end
        end
        menu:SetChecked(true)
        menu.scripts.OnClick(menu)
        clickText(state, "Disable all")
        eq(MurgleDB.interface.hideMicroMenu, false)
        clickText(state, "Reset Murgle")
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        clickText(state, "Disable all")
        eq(MurgleDB.interface.hideTalkingHead, false)
        eq(countBulk(), 2)
    end)
end)

test("bulk sound action refreshes independent mutes and leaves automation untouched", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        M.Settings.SelectCategory("ErrorsSound")
        clickText(state, "Mute all listed")
        eq(MurgleDB.sound.muteFizzle, true)
        eq(MurgleDB.sound.muteTrains, true)
        eq(MurgleDB.sound.muteMechanicalSteps, true)
        eq(MurgleDB.sound.muteErrorSpeech, true)
        eq(MurgleDB.automation.autoQuest, false)
        clickText(state, "Unmute all listed")
        eq(MurgleDB.sound.muteFizzle, false)
        eq(MurgleDB.sound.muteTrains, false)
        eq(MurgleDB.sound.muteMechanicalSteps, false)
        eq(MurgleDB.sound.muteErrorSpeech, false)
    end)
end)

test("page bulk preserves mutually exclusive chat tab modes", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        clickText(state, "Disable all")
        M.Settings.SelectCategory("Chat")
        for _, choice in ipairs({ { "Fade", "mouseover" }, { "Hide", "hide" }, { "Default", "show" } }) do
            clickText(state, choice[1])
            eq(MurgleDB.chat.tabs, choice[2])
            clickText(state, "Enable all")
            eq(MurgleDB.chat.tabs, choice[2])
            clickText(state, "Disable all")
            eq(MurgleDB.chat.tabs, choice[2])
            eq(MurgleDB.automation.autoQuest, false)
        end
    end)
end)

test("expanded sound choices support independent controls bulk actions and reset", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        M.Settings.SelectCategory("ErrorsSound")
        clickText(state, "Disable all")
        local choices = {
            { "muteFootsteps", "MUTE_FOOTSTEPS" },
            { "muteHooves", "MUTE_HOOVES" },
            { "muteChimes", "MUTE_CHIMES" },
            { "muteInterface", "MUTE_INTERFACE" },
            { "muteReadyCheck", "MUTE_READY_CHECK" },
            { "muteCatYawns", "MUTE_CAT_YAWNS" },
            { "mutePiccolo", "MUTE_PICCOLO" },
            { "muteMechanostriders", "MUTE_MECHANOSTRIDERS" },
            { "muteZeppelins", "MUTE_ZEPPELINS" },
        }
        for _, choice in ipairs(choices) do
            eq(MurgleDB.sound[choice[1]], false)
            local control
            for _, frame in ipairs(state.frames) do
                if frame.kind == "CheckButton" then
                    for _, region in ipairs(frame.regions) do
                        if M.L[choice[2]] and region.text == M.L[choice[2]] then
                            control = frame
                        end
                    end
                end
            end
            assert(control, choice[1] .. " control missing")
            control:SetChecked(true)
            control.scripts.OnClick(control)
            eq(MurgleDB.sound[choice[1]], true)
            clickText(state, "Disable all")
            eq(control:GetChecked(), false)
        end
        clickText(state, "Mute all listed")
        for _, choice in ipairs(choices) do
            eq(MurgleDB.sound[choice[1]], true)
        end
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        for _, choice in ipairs(choices) do
            eq(MurgleDB.sound[choice[1]], false)
        end
    end)
end)

test("page bulk buttons change only independent current page booleans", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        MurgleDB.interface.objectiveTrackerVisibility = "ooc"
        MurgleDB.interface.trackerFontSize = 10
        MurgleDB.interface.spellQueueWindow = 230
        MurgleDB.sound.muteFizzle = true
        clickText(state, "Disable all")
        eq(MurgleDB.interface.hideTalkingHead, false)
        eq(MurgleDB.interface.objectiveTrackerVisibility, "ooc")
        eq(MurgleDB.interface.trackerFontSize, 10)
        eq(MurgleDB.interface.spellQueueWindow, 230)
        eq(MurgleDB.sound.muteFizzle, true)
        eq(MurgleDB.automation.autoWorldRefresh, true)
        clickText(state, "Enable all")
        eq(MurgleDB.interface.hideMicroMenu, true)
        M.Settings.SelectCategory("Automation")
        MurgleDB.automation.worldRefreshMode = "acceptAndHide"
        clickText(state, "Disable all")
        eq(MurgleDB.automation.autoWorldRefresh, false)
        eq(MurgleDB.automation.worldRefreshMode, "acceptAndHide")
        eq(MurgleDB.interface.hideMicroMenu, true)
        M.Settings.SelectCategory("Chat")
        MurgleDB.chat.tabs = "mouseover"
        clickText(state, "Enable all")
        eq(MurgleDB.chat.hideButtons, true)
        eq(MurgleDB.chat.tabs, "mouseover")
        clickText(state, "Disable all")
        eq(MurgleDB.chat.tabs, "mouseover")
    end)
end)

test("removed reporter and version UI stay absent even with legacy beta settings", function()
    UI.withAddon(function(M, state)
        eq(M.Interface.ApplyZoneBug, nil)
        eq(M.Interface.IsBetaBuild, nil)
        eq(M.L.HIDE_ISSUE_REPORTER, nil)
        M.Settings.Show()
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                assert(region.text ~= "Hide Issue Reporter")
                assert(region.text ~= M.GetVersion())
            end
        end
    end, function()
        IsBetaBuild = function()
            error("retired beta probe called")
        end
        MurgleDB = { interface = { hideZoneBug = true } }
    end)
end)

test("help stays behind tooltips and leaving another owner does not hide it", function()
    UI.withAddon(function(M, state)
        local tip = { hidden = 0 }
        function tip:SetOwner(owner)
            self.owner = owner
        end
        function tip:GetOwner()
            return self.owner
        end
        function tip:SetText(text)
            self.text = text
        end
        function tip:Show() end
        function tip:Hide()
            self.hidden = self.hidden + 1
        end
        GameTooltip = tip
        M.Settings.Show()
        for _, category in ipairs({ "Chat", "Tooltip", "Automation", "LootVendors", "Quests", "ErrorsSound" }) do
            M.Settings.SelectCategory(category)
        end
        local foundChat, foundWarning = false, false
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                assert(region.text ~= M.L.CHAT_TABS_MOUSEOVER_NOTE)
                assert(region.text ~= M.L.WORLD_REFRESH_HARDCORE_NOTE)
            end
            if frame.scripts.OnEnter then
                frame.scripts.OnEnter(frame)
                foundChat = foundChat or tip.text:find("Hover chat to reveal faded tabs.", 1, true) ~= nil
                foundWarning = foundWarning or tip.text:find(M.L.WORLD_REFRESH_HARDCORE_NOTE, 1, true) ~= nil
                tip.owner = {}
                local hidden = tip.hidden
                frame.scripts.OnLeave(frame)
                eq(tip.hidden, hidden)
                tip.owner = frame
                frame.scripts.OnLeave(frame)
                eq(tip.hidden, hidden + 1)
            end
        end
        eq(foundChat, true)
        eq(foundWarning, true)
    end)
end)

test("page bulk keeps tooltip error and nameplate modes while changing independent booleans", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        M.Settings.SelectCategory("Tooltip")
        MurgleDB.tooltip.anchor = "left"
        clickText(state, "Enable all")
        eq(MurgleDB.tooltip.cursorAnchor, true)
        eq(MurgleDB.tooltip.compact, nil)
        eq(MurgleDB.tooltip.anchor, "left")
        M.Settings.SelectCategory("ErrorsSound")
        MurgleDB.errors.mode = "important"
        clickText(state, "Enable all")
        eq(MurgleDB.sound.muteFizzle, true)
        eq(MurgleDB.errors.mode, "important")
        clickText(state, "Disable all")
        eq(MurgleDB.sound.muteFizzle, false)
        eq(MurgleDB.errors.mode, "important")
        M.Settings.SelectCategory("Frames")
        MurgleDB.frames.enemyNameplates = "combat"
        MurgleDB.frames.friendlyNameplates = "hidden"
        clickText(state, "Enable all")
        eq(MurgleDB.frames.hidePlayerName, true)
        clickText(state, "Disable all")
        eq(MurgleDB.frames.hidePlayerName, false)
        eq(MurgleDB.frames.enemyNameplates, "combat")
        eq(MurgleDB.frames.friendlyNameplates, "hidden")
        eq(MurgleDB.tooltip.cursorAnchor, true)
    end)
end)
