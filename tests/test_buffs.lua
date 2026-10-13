local H = dofile("tests/helpers.lua")

local function withBuffs(fn)
    local state = { over = false, writes = 0, hooks = 0 }
    local button = H.newVisibilityFrame(true)
    button.alpha = 0.7
    function button:GetAlpha()
        return self.alpha
    end
    function button:SetAlpha(alpha)
        self.alpha = alpha
        state.writes = state.writes + 1
    end
    function button:HookScript(name, callback)
        self.scripts[name] = callback
        state.hooks = state.hooks + 1
    end
    function button:IsMouseOver()
        return state.over
    end
    H.withGlobals({
        MurgleDB = { interface = { buffTriangleMouseover = false } },
        BuffFrame = { CollapseAndExpandButton = button },
        MouseIsOver = false,
    }, function()
        local M = {}
        H.loadAddonFile("Modules/Buffs.lua", M)
        fn(M.Buffs, button, state)
    end)
end

test("buff triangle is inert when disabled and remains a native hit target on hover", function()
    withBuffs(function(B, button, state)
        B.Initialize()
        eq(state.hooks, 0)
        eq(state.writes, 0)
        MurgleDB.interface.buffTriangleMouseover = true
        B.ApplyAll()
        eq(button.alpha, 0)
        eq(button.shown, true)
        eq(state.hooks, 3)
        state.over = true
        button.scripts.OnEnter(button)
        eq(button.alpha, 0.7)
        state.over = false
        button.scripts.OnLeave(button)
        eq(button.alpha, 0)
        B.ApplyAll()
        eq(state.hooks, 3)
        MurgleDB.interface.buffTriangleMouseover = false
        B.ApplyAll()
        eq(button.alpha, 0.7)
        local writes = state.writes
        button.scripts.OnEnter(button)
        button.scripts.OnLeave(button)
        button.scripts.OnShow(button)
        eq(state.writes, writes)
    end)
end)

test("buff triangle restores only owned alpha and captures new value on reenable", function()
    withBuffs(function(B, button, state)
        MurgleDB.interface.buffTriangleMouseover = true
        state.over = true
        B.ApplyAll()
        eq(button.alpha, 0.7)
        button:SetAlpha(0.4)
        MurgleDB.interface.buffTriangleMouseover = false
        B.ApplyAll()
        eq(button.alpha, 0.4)
        MurgleDB.interface.buffTriangleMouseover = true
        state.over = false
        B.ApplyAll()
        eq(button.alpha, 0)
        MurgleDB.interface.buffTriangleMouseover = false
        B.ApplyAll()
        eq(button.alpha, 0.4)
    end)
end)

test("buff triangle skips absent protected and changed API targets", function()
    withBuffs(function(B, button, state)
        MurgleDB.interface.buffTriangleMouseover = true
        BuffFrame = nil
        B.ApplyAll()
        eq(state.hooks, 0)
        BuffFrame = { CollapseAndExpandButton = button }
        button.protected = true
        B.ApplyAll()
        eq(state.hooks, 0)
        button.protected = false
        local getAlpha = button.GetAlpha
        button.GetAlpha = nil
        B.ApplyAll()
        eq(state.hooks, 0)
        button.GetAlpha = getAlpha
        B.ApplyAll()
        eq(state.hooks, 3)
        button.protected = true
        state.over = true
        button.scripts.OnEnter(button)
        eq(button.alpha, 0)
    end)
end)
