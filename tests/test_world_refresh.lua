local H = dofile("tests/helpers.lua")
local UI = dofile("tests/ui_helpers.lua")
local key = "SHARD_TRANSFER_IMMINENT_EVENT"

local function withRefresh(fn, enabled)
    local s = { hooks = 0, accepted = 0, hides = 0 }
    local definition = {
        button1 = "Refresh Now",
        button2 = "Okay",
        OnButton1 = function() end,
        OnShow = function() end,
        GetExpirationText = function() end,
    }
    local popup = { which = key, dialogInfo = definition }
    function popup:IsVisible()
        return s.shown == true
    end
    function popup:IsProtected()
        return s.protected == true
    end
    function popup:Hide()
        s.hides = s.hides + 1
        s.shown = false
    end
    function popup:GetButton1()
        return {
            IsVisible = function()
                return true
            end,
            IsEnabled = function()
                return not s.disabled
            end,
        }
    end
    H.withGlobals({
        MurgleDB = { automation = { autoWorldRefresh = enabled == true, worldRefreshMode = "hideOnly" } },
        StaticPopupDialogs = { [key] = definition },
        SHARD_TRANSFER_NOW_BUTTON = "Refresh Now",
        OKAY = "Okay",
        StaticPopup_FindVisible = function(which)
            eq(which, key)
            return s.shown and popup
        end,
        InCombatLockdown = function()
            return s.combat == true
        end,
        IsShiftKeyDown = function()
            return s.shift == true
        end,
        C_PlayerInteractionManager = {
            ShardTransferConfirm = function()
                s.accepted = s.accepted + 1
                if s.onAccept then
                    s.onAccept()
                end
            end,
        },
        ShardTransferImminentFrame = false,
        ShardTransferImminentMinimizeButton = false,
        ShardTransferImminentMixin = false,
        ShardTransferImminentMinimizeMixin = false,
        GameEvent = {
            HandleShardTransferImminentEvent = function()
                s.shown = true
            end,
        },
        hooksecurefunc = function(object, method, callback)
            eq(object, GameEvent)
            eq(method, "HandleShardTransferImminentEvent")
            s.hooks = s.hooks + 1
            local original = object[method]
            object[method] = function(...)
                original(...)
                callback(...)
            end
        end,
        CreateFrame = function()
            error("World Refresh must not create event frames")
        end,
    }, function()
        local M = {}
        H.loadAddonFile("Modules/Automation.lua", M)
        fn(M.Automation, s, definition, popup)
    end)
end

test("World Refresh hide-only suppresses only the sourced warning without acceptance", function()
    withRefresh(function(A, s)
        A.Initialize()
        eq(s.hooks, 1)
        eq(s.accepted + s.hides, 0, "settings apply never acts on a prompt")
        GameEvent.HandleShardTransferImminentEvent()
        eq(s.hides, 1)
        eq(s.accepted, 0)
        A.ApplyAll()
        eq(s.hooks, 1)
    end, true)
end)

test("World Refresh disabled and invalid modes leave native prompts alone", function()
    withRefresh(function(A, s)
        A.Initialize()
        eq(s.hooks, 0)
        MurgleDB.automation.autoWorldRefresh = true
        MurgleDB.automation.worldRefreshMode = "bad"
        A.ApplyAll()
        eq(s.hooks, 0)
        MurgleDB.automation.worldRefreshMode = "hideOnly"
        A.ApplyAll()
        MurgleDB.automation.worldRefreshMode = "bad"
        GameEvent.HandleShardTransferImminentEvent()
        eq(s.shown, true)
        MurgleDB.automation.worldRefreshMode = "hideOnly"
        MurgleDB.automation.autoWorldRefresh = false
        GameEvent.HandleShardTransferImminentEvent()
        eq(s.hides + s.accepted, 0)
    end)
end)

test("World Refresh acceptance is explicit and synchronous reentry accepts once", function()
    withRefresh(function(A, s)
        MurgleDB.automation.worldRefreshMode = "acceptAndHide"
        A.ApplyAll()
        s.onAccept = function()
            GameEvent.HandleShardTransferImminentEvent()
        end
        GameEvent.HandleShardTransferImminentEvent()
        eq(s.accepted, 1)
        eq(s.hides, 1)
    end, true)
end)

test("World Refresh skips combat Shift protected disabled and altered prompts", function()
    withRefresh(function(A, s, definition, popup)
        MurgleDB.automation.worldRefreshMode = "acceptAndHide"
        A.ApplyAll()
        for _, flag in ipairs({ "combat", "shift", "protected", "disabled" }) do
            s[flag] = true
            GameEvent.HandleShardTransferImminentEvent()
            s[flag] = false
        end
        popup.which = "SHARD_TRANSFER_IMMEDIATE"
        GameEvent.HandleShardTransferImminentEvent()
        popup.which = key
        popup.customOnHideScript = function()
            error("unknown callback")
        end
        GameEvent.HandleShardTransferImminentEvent()
        popup.customOnHideScript = nil
        definition.OnHide = function()
            error("unknown callback")
        end
        GameEvent.HandleShardTransferImminentEvent()
        definition.OnHide = nil
        local original = definition.OnButton1
        definition.OnButton1 = function() end
        GameEvent.HandleShardTransferImminentEvent()
        definition.OnButton1 = original
        StaticPopupDialogs[key] = {}
        GameEvent.HandleShardTransferImminentEvent()
        eq(s.accepted + s.hides, 0)
    end, true)
end)

test("World Refresh action cannot hide a replacement dialog", function()
    withRefresh(function(A, s, _, popup)
        MurgleDB.automation.worldRefreshMode = "acceptAndHide"
        A.ApplyAll()
        s.onAccept = function()
            popup.which = "OTHER_CONFIRMATION"
        end
        GameEvent.HandleShardTransferImminentEvent()
        eq(s.accepted, 1)
        eq(s.hides, 0)
    end, true)
end)

test("World Refresh missing integration leaves native behavior and explicit apply retries", function()
    withRefresh(function(A, s)
        local confirm = C_PlayerInteractionManager.ShardTransferConfirm
        C_PlayerInteractionManager.ShardTransferConfirm = nil
        A.ApplyAll()
        eq(s.hooks, 0)
        C_PlayerInteractionManager.ShardTransferConfirm = confirm
        A.ApplyAll()
        eq(s.hooks, 1)
        C_PlayerInteractionManager.ShardTransferConfirm = nil
        MurgleDB.automation.worldRefreshMode = "acceptAndHide"
        GameEvent.HandleShardTransferImminentEvent()
        eq(s.accepted + s.hides, 0)
    end, true)
end)

test("World Refresh segmented choices preserve enable state and reset restores hide-only", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        M.Settings.SelectCategory("Automation")
        local choices = {}
        local toggle
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                if region.text == M.L.AUTO_WORLD_REFRESH then
                    toggle = frame
                elseif region.text == M.L.WORLD_REFRESH_HIDE_ONLY then
                    choices.hideOnly = frame
                elseif region.text == M.L.WORLD_REFRESH_ACCEPT_HIDE then
                    choices.acceptAndHide = frame
                end
                assert(region.text ~= M.L.WORLD_REFRESH_HARDCORE_NOTE)
                assert(region.text ~= M.L.WORLD_REFRESH_SCOPE_NOTE)
            end
        end
        assert(choices.hideOnly and choices.acceptAndHide)
        assert(toggle)
        eq(choices.acceptAndHide:IsShown(), true)
        choices.acceptAndHide.scripts.OnClick(choices.acceptAndHide)
        toggle:SetChecked(false)
        toggle.scripts.OnClick(toggle)
        eq(choices.acceptAndHide:IsShown(), false)
        eq(choices.hideOnly:IsShown(), false)
        eq(MurgleDB.automation.worldRefreshMode, "acceptAndHide")
        toggle:SetChecked(true)
        toggle.scripts.OnClick(toggle)
        eq(choices.acceptAndHide:IsShown(), true)
        eq(choices.hideOnly:IsShown(), true)
        eq(MurgleDB.automation.worldRefreshMode, "acceptAndHide")
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(MurgleDB.automation.worldRefreshMode, "hideOnly")
        eq(choices.hideOnly:IsShown(), true)
    end)
end)

local function toastFixture(s)
    local function make()
        local frame = H.newVisibilityFrame(false)
        function frame:Start()
            self:Show()
            self.timer = 300
        end
        function frame:OnClick() end
        function frame:IsVisible()
            return self.shown
        end
        function frame:IsEventRegistered(event)
            return event == "SHARD_TRANSFER_IMMINENT"
        end
        function frame:Fire(event)
            if event == "SHARD_TRANSFER_IMMINENT" then
                self:Start()
            else
                self:Hide()
            end
            if self.scripts.OnEvent then
                self.scripts.OnEvent(self, event)
            end
        end
        return frame
    end
    local main, toggle = make(), make()
    ShardTransferImminentFrame, ShardTransferImminentMinimizeButton = main, toggle
    ShardTransferImminentMixin = { Start = main.Start, OnClick = main.OnClick }
    ShardTransferImminentMinimizeMixin = { Start = toggle.Start, OnClick = toggle.OnClick }
    return main, toggle
end

test("World Refresh hides native toast and minimize button only at automatic warning", function()
    withRefresh(function(A, s)
        local main, toggle = toastFixture(s)
        A.ApplyAll()
        main:Fire("SHARD_TRANSFER_IMMINENT")
        toggle:Fire("SHARD_TRANSFER_IMMINENT")
        eq(main.shown, false)
        eq(toggle.shown, false)
        eq(s.accepted, 0)
        main:Show()
        eq(main.shown, true, "manual showing is not suppressed")
        MurgleDB.automation.autoWorldRefresh = false
        main:Fire("SHARD_TRANSFER_IMMINENT")
        eq(main.shown, true)
    end, true)
end)

test("World Refresh toast acceptance cannot duplicate popup or reentrant acceptance", function()
    withRefresh(function(A, s)
        local main, toggle = toastFixture(s)
        MurgleDB.automation.worldRefreshMode = "acceptAndHide"
        A.ApplyAll()
        s.onAccept = function()
            main:Fire("SHARD_TRANSFER_IMMINENT")
        end
        GameEvent.HandleShardTransferImminentEvent()
        main:Fire("SHARD_TRANSFER_IMMINENT")
        toggle:Fire("SHARD_TRANSFER_IMMINENT")
        eq(s.accepted, 1)
        eq(main.shown, false)
        eq(toggle.shown, false)
    end, true)
end)

test("World Refresh toast bypasses combat Shift changed paths and protected frames", function()
    withRefresh(function(A, s)
        local main = toastFixture(s)
        MurgleDB.automation.worldRefreshMode = "acceptAndHide"
        A.ApplyAll()
        for _, flag in ipairs({ "combat", "shift" }) do
            s[flag] = true
            main:Fire("SHARD_TRANSFER_IMMINENT")
            eq(main.shown, true)
            s[flag] = false
        end
        main.protected = true
        main:Fire("SHARD_TRANSFER_IMMINENT")
        eq(main.shown, true)
        main.protected = false
        main.Start = function(self)
            self:Show()
        end
        main:Fire("SHARD_TRANSFER_IMMINENT")
        eq(main.shown, true)
        eq(s.accepted, 0)
    end, true)
end)

test("World Refresh does not hide the old toast after action replaces the native global", function()
    withRefresh(function(A, s)
        local main = toastFixture(s)
        MurgleDB.automation.worldRefreshMode = "acceptAndHide"
        A.ApplyAll()
        s.onAccept = function()
            ShardTransferImminentFrame = H.newVisibilityFrame(true)
        end
        main:Fire("SHARD_TRANSFER_IMMINENT")
        eq(s.accepted, 1)
        eq(main.shown, true)
        eq(ShardTransferImminentFrame.shown, true)
    end, true)
end)

for _, change in ipairs({ "action", "start", "protected", "event", "global" }) do
    test("World Refresh preserves manual popup after toast integration changes: " .. change, function()
        withRefresh(function(A, s)
            local main = toastFixture(s)
            MurgleDB.automation.worldRefreshMode = "acceptAndHide"
            A.ApplyAll()
            if change == "action" then
                C_PlayerInteractionManager.ShardTransferConfirm = nil
            elseif change == "start" then
                main.Start = function(self)
                    self:Show()
                end
            elseif change == "protected" then
                main.protected = true
            elseif change == "event" then
                main.IsEventRegistered = function()
                    return false
                end
            else
                ShardTransferImminentFrame = H.newVisibilityFrame(true)
            end
            GameEvent.HandleShardTransferImminentEvent()
            main:Fire("SHARD_TRANSFER_IMMINENT")
            eq(s.accepted, 0)
            eq(s.hides, 0, "uncertain acceptance must preserve the manual popup")
            eq(s.shown, true)
            eq(main.shown, true)
        end, true)
    end)
end

test("World Refresh popup after handled toast hides without a second acceptance", function()
    withRefresh(function(A, s)
        local main = toastFixture(s)
        MurgleDB.automation.worldRefreshMode = "acceptAndHide"
        A.ApplyAll()
        main:Fire("SHARD_TRANSFER_IMMINENT")
        eq(main.shown, false)
        GameEvent.HandleShardTransferImminentEvent()
        eq(s.accepted, 1)
        eq(s.hides, 1)
    end, true)
end)
