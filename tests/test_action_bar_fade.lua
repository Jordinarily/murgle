local H = dofile("tests/helpers.lua")

local function withBars(fn)
    local state = { combat = false, frames = {}, hooks = 0 }
    local bar = { alpha = 0.8 }
    function bar:GetAlpha()
        return self.alpha
    end
    function bar:SetAlpha(value)
        self.alpha = value
    end
    -- Only opacity is permitted: visibility, mouse handling and secure state
    -- mutations deliberately have no fake implementation.
    local manager = { editing = false }
    function manager:IsEditModeActive()
        return self.editing
    end
    function manager:EnterEditMode()
        self.editing = true
    end
    function manager:ExitEditMode()
        self.editing = false
    end
    function state:fire(event, ...)
        for _, frame in ipairs(self.frames) do
            if frame.events[event] then
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
    end
    H.withGlobals({
        MurgleDB = {},
        MainActionBar = bar,
        MultiBarBottomLeft = false,
        MultiBarBottomRight = false,
        MultiBarLeft = false,
        MultiBarRight = false,
        MultiBar5 = false,
        MultiBar6 = false,
        MultiBar7 = false,
        EditModeManagerFrame = manager,
        InCombatLockdown = function()
            return state.combat
        end,
        CreateFrame = function()
            local frame = H.newEventFrame()
            state.frames[#state.frames + 1] = frame
            return frame
        end,
        hooksecurefunc = function(object, method, callback)
            state.hooks = state.hooks + 1
            local original = object[method]
            object[method] = function(self, ...)
                original(self, ...)
                callback(self, ...)
            end
        end,
    }, function()
        local M = {}
        H.loadAddonFile("Defaults.lua", M)
        H.loadAddonFile("Modules/Interface.lua", M)
        MurgleDB = M.ApplyDefaults({})
        fn(M.Interface, state, bar, manager)
    end)
end

test("action bar fading is inert by default and restores on combat exit and disable", function()
    withBars(function(I, state, bar)
        assert(type(I.ApplyActionBarFade) == "function", "action bar fading is missing")
        I.ApplyActionBarFade()
        eq(#state.frames, 0)
        eq(state.hooks, 0)
        MurgleDB.interface.fadeActionBars = true
        MurgleDB.interface.actionBarCombatOpacity = 25
        I.ApplyActionBarFade()
        eq(bar.alpha, 0.8)
        state.combat = true
        state:fire("PLAYER_REGEN_DISABLED")
        eq(bar.alpha, 0.2)
        I.ApplyActionBarFade()
        eq(bar.alpha, 0.2, "reapply must not compound opacity")
        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        eq(bar.alpha, 0.8)
        state.combat = true
        state:fire("PLAYER_REGEN_DISABLED")
        MurgleDB.interface.fadeActionBars = false
        I.ApplyActionBarFade()
        eq(bar.alpha, 0.8)
        for _, frame in ipairs(state.frames) do
            eq(next(frame.events), nil)
            eq(frame.scripts.OnUpdate, nil)
        end
        bar:SetAlpha(0.6)
        eq(bar.alpha, 0.6)
    end)
end)

test("action bar opacity controls retain choices while disabled and reset to defaults", function()
    local UI = dofile("tests/ui_helpers.lua")
    UI.withAddon(function(M, state)
        M.Settings.Show()
        local toggle, hide
        for _, frame in ipairs(state.frames) do
            if frame.caption and frame.caption.text == M.L.FADE_ACTION_BARS then
                toggle = frame
            end
            if frame.kind == "Button" then
                for _, region in ipairs(frame.regions) do
                    if region.text == "0%" then
                        hide = frame
                    end
                end
            end
        end
        assert(toggle and hide, "combat opacity controls are missing")
        eq(hide:IsShown(), false)
        toggle:SetChecked(true)
        toggle.scripts.OnClick(toggle)
        eq(hide:IsShown(), true)
        hide.scripts.OnClick(hide)
        eq(MurgleDB.interface.actionBarCombatOpacity, 0)
        toggle:SetChecked(false)
        toggle.scripts.OnClick(toggle)
        eq(hide:IsShown(), false)
        eq(MurgleDB.interface.actionBarCombatOpacity, 0)
        toggle:SetChecked(true)
        toggle.scripts.OnClick(toggle)
        eq(hide:IsShown(), true)
        eq(MurgleDB.interface.actionBarCombatOpacity, 0)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(toggle:GetChecked(), false)
        eq(hide:IsShown(), false)
        eq(MurgleDB.interface.actionBarCombatOpacity, 25)
    end)
end)

test("action bar zero opacity survives native writes and restores their latest value", function()
    withBars(function(I, state, bar)
        MurgleDB.interface.fadeActionBars = true
        MurgleDB.interface.actionBarCombatOpacity = 0
        state.combat = true
        I.ApplyActionBarFade()
        eq(bar.alpha, 0)
        bar:SetAlpha(0.6)
        eq(bar.alpha, 0)
        MurgleDB.interface.actionBarCombatOpacity = 50
        I.ApplyActionBarFade()
        eq(bar.alpha, 0.3)
        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        eq(bar.alpha, 0.6)
    end)
end)

test("action bar fading yields to Edit Mode then resumes", function()
    withBars(function(I, state, bar, manager)
        MurgleDB.interface.fadeActionBars = true
        MurgleDB.interface.actionBarCombatOpacity = 0
        state.combat = true
        I.ApplyActionBarFade()
        manager:EnterEditMode()
        eq(bar.alpha, 0.8)
        manager:ExitEditMode()
        eq(bar.alpha, 0)
    end)
end)

test("action bar fading handles late frames and invalid saved opacity safely", function()
    withBars(function(I, state, bar)
        MainActionBar = nil
        MurgleDB.interface.fadeActionBars = true
        MurgleDB.interface.actionBarCombatOpacity = "bad"
        state.combat = true
        I.ApplyActionBarFade()
        MainActionBar = bar
        state:fire("PLAYER_ENTERING_WORLD")
        eq(bar.alpha, 0.8)
        MurgleDB.interface.actionBarCombatOpacity = 25
        I.ApplyActionBarFade()
        eq(bar.alpha, 0.2)
    end)
end)

test("late action bars and Edit Mode load independently and stop discovery when complete", function()
    withBars(function(I, state, bar, manager)
        EditModeManagerFrame = nil
        MurgleDB.interface.fadeActionBars = true
        MurgleDB.interface.actionBarCombatOpacity = 50
        state.combat = true
        I.ApplyActionBarFade()
        eq(bar.alpha, 0.4)
        local names = {
            "MultiBarBottomLeft",
            "MultiBarBottomRight",
            "MultiBarLeft",
            "MultiBarRight",
            "MultiBar5",
            "MultiBar6",
            "MultiBar7",
        }
        for _, name in ipairs(names) do
            _G[name] = {
                alpha = 0.6,
                GetAlpha = function(self)
                    return self.alpha
                end,
                SetAlpha = function(self, value)
                    self.alpha = value
                end,
            }
        end
        state:fire("ADDON_LOADED", "Blizzard_ActionBar")
        for _, name in ipairs(names) do
            eq(_G[name].alpha, 0.3)
        end
        EditModeManagerFrame = manager
        state:fire("ADDON_LOADED", "Blizzard_EditMode")
        for _, frame in ipairs(state.frames) do
            eq(frame:IsEventRegistered("ADDON_LOADED"), false)
        end
        manager:EnterEditMode()
        eq(bar.alpha, 0.8)
        for _, name in ipairs(names) do
            eq(_G[name].alpha, 0.6)
        end
        manager:ExitEditMode()
        eq(bar.alpha, 0.4)
        MurgleDB.interface.fadeActionBars = false
        I.ApplyActionBarFade()
        eq(bar.alpha, 0.8)
        for _, name in ipairs(names) do
            eq(_G[name].alpha, 0.6)
        end
    end)
end)
