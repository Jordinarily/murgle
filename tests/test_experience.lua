local H = dofile("tests/helpers.lua")

local function withXP(fn)
    local state = { hooks = 0, frames = {}, combat = false }
    local function region()
        local r = { alpha = 0.8 }
        function r:GetAlpha()
            return self.alpha
        end
        function r:SetAlpha(value)
            self.alpha = value
        end
        return r
    end
    local function container()
        local bar = region()
        bar.shown, bar.mouse, bar.scripts = true, true, {}
        function bar:IsProtected()
            return self.protected == true
        end
        function bar:IsShown()
            return self.shown
        end
        function bar:HookScript(name, fn)
            self.scripts[name] = fn
        end
        function bar:IsMouseEnabled()
            return self.mouse
        end
        function bar:EnableMouse(value)
            self.mouse = value
        end
        bar.isExpBar = true
        local tick = { mouse = true, scripts = {} }
        tick.IsProtected, tick.HookScript = bar.IsProtected, bar.HookScript
        tick.IsMouseEnabled, tick.EnableMouse = bar.IsMouseEnabled, bar.EnableMouse
        bar.ExhaustionTick = tick
        local c = { bars = { [4] = bar }, BarFrameTexture = region(), shownBarIndex = 4 }
        function c:IsProtected()
            return self.protected == true
        end
        function c:ApplyPendingBarToShow()
            self.shownBarIndex = self.pending
            bar.shown = self.pending == 4
        end
        return c
    end
    local main, secondary = container(), container()
    H.withGlobals({
        MurgleDB = { interface = {} },
        GameTooltip = false,
        StatusTrackingBarInfo = { BarsEnum = { Experience = 4 } },
        MainStatusTrackingBarContainer = main,
        SecondaryStatusTrackingBarContainer = secondary,
        MouseIsOver = function(bar)
            return bar.hover == true
        end,
        InCombatLockdown = function()
            return state.combat
        end,
        hooksecurefunc = function(object, method, fn)
            state.hooks = state.hooks + 1
            local original = object[method]
            object[method] = function(self, ...)
                original(self, ...)
                fn(self, ...)
            end
        end,
        CreateFrame = function()
            local f = H.newEventFrame()
            state.frames[#state.frames + 1] = f
            return f
        end,
    }, function()
        local M = {}
        H.loadAddonFile("Modules/Interface.lua", M)
        fn(M, main, secondary, state)
    end)
end

test("normal XP mode is inert", function()
    withXP(function(M, main, secondary, state)
        eq(type(M.Interface.ApplyXP), "function", "XP apply entry point")
        M.Interface.ApplyXP()
        eq(state.hooks, 0)
        eq(#state.frames, 0)
        eq(main.bars[4].alpha, 0.8)
    end)
end)

test("XP hide toggle suppresses both XP bars without changing other status bars", function()
    withXP(function(M, main, secondary, state)
        secondary.pending = 1
        secondary:ApplyPendingBarToShow()
        MurgleDB.interface.hideXP = true
        M.Interface.ApplyXP()
        eq(main.bars[4].alpha, 0)
        eq(main.BarFrameTexture.alpha, 0)
        eq(secondary.BarFrameTexture.alpha, 0.8)
        eq(main.bars[4].mouse, false)
        eq(main.bars[4].ExhaustionTick.mouse, false)
        eq(next(main.bars[4].scripts), nil, "no hover handlers")
        eq(#state.frames, 0, "no combat listeners")
        state.combat = true
        M.Interface.ApplyXP()
        eq(main.bars[4].alpha, 0)
        main.pending = 1
        main:ApplyPendingBarToShow()
        eq(main.BarFrameTexture.alpha, 0.8)
        MurgleDB.interface.hideXP = false
        M.Interface.ApplyXP()
        eq(main.bars[4].alpha, 0.8)
        eq(main.bars[4].mouse, true)
        eq(main.bars[4].shown, false, "show means native eligibility, not force-show")
    end)
end)

test("XP restores latest native alpha after suppression and repeated applies", function()
    withXP(function(M, main, secondary, state)
        MurgleDB.interface.hideXP = true
        M.Interface.ApplyXP()
        local hooks = state.hooks
        M.Interface.ApplyXP()
        eq(state.hooks, hooks)
        main.bars[4]:SetAlpha(0.6)
        main.BarFrameTexture:SetAlpha(0.7)
        eq(main.bars[4].alpha, 0)
        eq(main.BarFrameTexture.alpha, 0)
        MurgleDB.interface.hideXP = false
        M.Interface.ApplyXP()
        eq(main.bars[4].alpha, 0.6)
        eq(main.BarFrameTexture.alpha, 0.7)
        main.bars[4]:SetAlpha(0.4)
        eq(main.bars[4].alpha, 0.4)
    end)
end)

test("XP unavailable or protected integration leaves both containers untouched", function()
    withXP(function(M, main, secondary, state)
        secondary.bars[4].protected = true
        MurgleDB.interface.hideXP = true
        M.Interface.ApplyXP()
        eq(main.bars[4].alpha, 0.8)
        eq(state.hooks, 0)
        eq(#state.frames, 0)
    end)
    withXP(function(M, main, secondary, state)
        secondary.BarFrameTexture = nil
        MurgleDB.interface.hideXP = true
        M.Interface.ApplyXP()
        eq(main.bars[4].alpha, 0.8)
        eq(state.hooks, 0)
    end)
end)

test("XP invalid toggle restores native mouse settings and current alpha", function()
    withXP(function(M, main, secondary, state)
        local bar = main.bars[4]
        bar.mouse, bar.ExhaustionTick.mouse = false, false
        state.combat = true
        MurgleDB.interface.hideXP = true
        M.Interface.ApplyXP()
        MurgleDB.interface.hideXP = "invalid"
        M.Interface.ApplyXP()
        eq(bar.mouse, false)
        eq(bar.ExhaustionTick.mouse, false)
        eq(bar.alpha, 0.8)
        eq(#state.frames, 0)
        MurgleDB.interface.hideXP = true
        M.Interface.ApplyXP()
        MurgleDB.interface.hideXP = false
        M.Interface.ApplyXP()
        eq(bar.alpha, 0.8)
    end)
end)

test("XP hiding dismisses only an owned XP tooltip", function()
    withXP(function(M, main, secondary, state)
        local tooltip = { owner = main.bars[4], shown = true }
        function tooltip:GetOwner()
            return self.owner
        end
        function tooltip:Hide()
            self.shown = false
        end
        H.withGlobals({ GameTooltip = tooltip }, function()
            MurgleDB.interface.hideXP = true
            state.combat = true
            M.Interface.ApplyXP()
            eq(tooltip.shown, false)
            tooltip.owner, tooltip.shown = main.bars[4].ExhaustionTick, true
            M.Interface.ApplyXP()
            eq(tooltip.shown, false)
            tooltip.owner, tooltip.shown = {}, true
            M.Interface.ApplyXP()
            eq(tooltip.shown, true)
        end)
    end)
end)

test("XP can initialize after a temporarily missing container becomes available", function()
    withXP(function(M, main, secondary, state)
        MurgleDB.interface.hideXP = true
        SecondaryStatusTrackingBarContainer = nil
        M.Interface.ApplyXP()
        eq(main.bars[4].alpha, 0.8)
        SecondaryStatusTrackingBarContainer = secondary
        M.Interface.ApplyXP()
        eq(main.bars[4].alpha, 0)
        eq(secondary.bars[4].alpha, 0)
    end)
end)

test("saved XP choice retries once on entering world and releases startup listener", function()
    withXP(function(M, main, secondary, state)
        MurgleDB.interface.hideXP = true
        SecondaryStatusTrackingBarContainer = nil
        M.Interface.Initialize()
        local startup = state.frames[1]
        assert(startup, "startup listener missing")
        eq(startup.events.PLAYER_ENTERING_WORLD, true)
        SecondaryStatusTrackingBarContainer = secondary
        startup.scripts.OnEvent(startup, "PLAYER_ENTERING_WORLD")
        eq(main.bars[4].alpha, 0)
        eq(next(startup.events), nil)
    end)
end)

test("XP suppression includes native divider artwork and restores it for other bars", function()
    withXP(function(M, main)
        local function divider(alpha)
            local texture = { alpha = alpha }
            function texture:GetAlpha()
                return self.alpha
            end
            function texture:SetAlpha(value)
                self.alpha = value
            end
            return { BarDividerTexture = texture }
        end
        local first = divider(0.7)
        local active = { [first] = true }
        main.HorizontalDividersPool = {}
        function main.HorizontalDividersPool:EnumerateActive()
            return next, active, nil
        end
        function main:UpdateDividers(...)
            -- Native UpdateDividers releases all frames before reacquiring a subset.
            active = {}
            for _, frame in ipairs({ ... }) do
                active[frame] = true
            end
        end
        MurgleDB.interface.hideXP = true
        M.Interface.ApplyXP()
        eq(first.BarDividerTexture.alpha, 0)
        local second = divider(0.6)
        main:UpdateDividers(first, second)
        eq(first.BarDividerTexture.alpha, 0, "reacquired divider remains suppressed")
        eq(second.BarDividerTexture.alpha, 0)
        main:UpdateDividers(second)
        eq(second.BarDividerTexture.alpha, 0)
        main.pending = 1
        main:ApplyPendingBarToShow()
        eq(first.BarDividerTexture.alpha, 0.7)
        eq(second.BarDividerTexture.alpha, 0.6)
        main.pending = 4
        main:ApplyPendingBarToShow()
        eq(first.BarDividerTexture.alpha, 0.7, "released divider is restored")
        eq(second.BarDividerTexture.alpha, 0)
        MurgleDB.interface.hideXP = false
        M.Interface.ApplyXP()
        eq(first.BarDividerTexture.alpha, 0.7)
        eq(second.BarDividerTexture.alpha, 0.6)
    end)
end)

test("legacy XP visibility choices no longer activate hiding", function()
    withXP(function(M, main, secondary, state)
        MurgleDB.interface.xpVisibility = "combat"
        M.Interface.ApplyXP()
        eq(main.bars[4].alpha, 0.8)
        eq(state.hooks, 0)
        eq(#state.frames, 0)
    end)
end)
