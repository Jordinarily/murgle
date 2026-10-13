local H = dofile("tests/helpers.lua")
local UI = dofile("tests/ui_helpers.lua")

local function fixture(_, state)
    TotemFrame = H.newVisibilityFrame(true)
    -- Native SetShown need not dispatch through Lua Show/Hide wrappers.
    function TotemFrame:SetShown(shown)
        self.shown = shown
        self.changes = self.changes + 1
    end
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

local function setHidden(M, value)
    MurgleDB.interface.hideTotemTimers = value
    M.Interface.ApplyTotemTimers()
end

test("totem timers are inert by default and restore latest native eligibility", function()
    UI.withAddon(function(M, state)
        eq(MurgleDB.interface.hideTotemTimers, false)
        eq(state.hooks, 0)
        eq(TotemFrame.changes, 0)
        setHidden(M, true)
        eq(TotemFrame.shown, false)
        TotemFrame:SetShown(false) -- last totem expires
        setHidden(M, false)
        eq(TotemFrame.shown, false)
        setHidden(M, true)
        TotemFrame:SetShown(true) -- a new totem appears
        eq(TotemFrame.shown, false)
        setHidden(M, false)
        eq(TotemFrame.shown, true)
        eq(state.hooks, 2, "re-enabling must not accumulate hooks")
        eq(#state.frames, 1)
        eq(next(state.frames[1].events), nil)
        TotemFrame:SetShown(false)
        TotemFrame:SetShown(true)
        eq(TotemFrame.shown, true, "disabled hooks leave native updates alone")
    end, fixture)
end)

test("totem restoration respects explicit native Hide while already suppressed", function()
    UI.withAddon(function(M)
        setHidden(M, true)
        TotemFrame:Hide() -- vehicle display explicitly suppresses the timers
        setHidden(M, false)
        eq(TotemFrame.shown, false)
    end, fixture)
end)

test("totem hide restores the captured frame without touching a replacement", function()
    UI.withAddon(function(M)
        local original = TotemFrame
        setHidden(M, true)
        TotemFrame = H.newVisibilityFrame(false)
        setHidden(M, false)
        eq(original.shown, true)
        eq(TotemFrame.changes, 0)
    end, fixture)
end)

test("totem settings defer combat changes and honor cancellation and reset", function()
    UI.withAddon(function(M, state)
        state.combat = true
        setHidden(M, true)
        setHidden(M, false)
        eq(state.hooks, 0)
        eq(TotemFrame.changes, 0)
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(TotemFrame.changes, 0)
        setHidden(M, true)
        state.combat = true
        M.ResetDB()
        eq(TotemFrame.shown, false)
        TotemFrame:SetShown(false)
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(TotemFrame.shown, false, "native expiry during deferred reset must survive")
        eq(M.GetDeferredCount(), 0)
        eq(next(state.frames[1].events), nil)
    end, fixture)
end)

test("totem suppression avoids protected combat mutations after ownership", function()
    UI.withAddon(function(M, state)
        setHidden(M, true)
        TotemFrame.protected = true
        state.combat = true
        TotemFrame:SetShown(true)
        eq(TotemFrame.shown, true, "do not hide a newly protected frame in combat")
        eq(M.GetDeferredCount(), 1)
        setHidden(M, false)
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(TotemFrame.shown, true)
        eq(M.GetDeferredCount(), 0)
    end, fixture)
end)

test("missing or protected totem integration fails closed and explicit changes can retry", function()
    UI.withAddon(function(M, state)
        local frame = TotemFrame
        TotemFrame = nil
        setHidden(M, true)
        TotemFrame = frame
        frame.protected = true
        setHidden(M, true)
        eq(state.hooks, 0)
        frame.protected = false
        local setShown = frame.SetShown
        frame.SetShown = nil
        setHidden(M, true)
        eq(frame.changes, 0)
        frame.SetShown = setShown
        setHidden(M, true)
        eq(frame.shown, false)
    end, fixture)
end)

test("saved totem suppression initializes without settings and checkbox resets", function()
    UI.withAddon(function(M, state)
        eq(TotemFrame.shown, false)
        eq(#state.frames, 1)
        M.Settings.Show()
        local checkbox
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                if region.text == M.L.HIDE_TOTEM_TIMERS then
                    checkbox = frame
                end
            end
        end
        assert(checkbox, "totem timer checkbox is available")
        eq(checkbox:GetChecked(), true)
        checkbox:SetChecked(false)
        checkbox.scripts.OnClick(checkbox)
        eq(MurgleDB.interface.hideTotemTimers, false)
        eq(TotemFrame.shown, true)
        setHidden(M, true)
        M.ResetDB()
        eq(TotemFrame.shown, true)
    end, function(M, state)
        fixture(M, state)
        MurgleDB = { interface = { hideTotemTimers = true } }
    end)
end)
