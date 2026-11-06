local H = dofile("tests/helpers.lua")
local function setup(fn)
    local frames, bindings, drivers, buttons = {}, {}, {}, {}
    local combat, pending = false, nil
    local calculate = function() end
    local bar = { actionButtons = buttons, attrs = {} }
    function bar:GetAttribute(name)
        return self.attrs[name]
    end
    for i = 1, 12 do
        local index = i
        local b = { attrs = { ["useparent-actionpage"] = true }, bar = bar, CalculateAction = calculate }
        function b:GetAttribute(name)
            return self.attrs[name]
        end
        function b:SetAttribute(name, value)
            self.attrs[name] = value
        end
        function b:GetName()
            return "ActionButton" .. index
        end
        buttons[i] = b
    end
    local function frame()
        local f = H.newEventFrame()
        f.attrs = {}
        f.refs = {}
        function f:GetAttribute(name)
            return self.attrs[name]
        end
        function f:SetAttribute(name, value)
            self.attrs[name] = value
        end
        function f:SetFrameRef(name, value)
            self.refs[name] = value
        end
        function f:GetFrameRef(name)
            return self.refs[name]
        end
        function f:ClearBindings()
            bindings = {}
        end
        function f:SetBinding(_, key, action)
            bindings[key] = action
        end
        function f:transition(value)
            self.attrs["state-page"] = value
            assert(loadstring("return function(self,newstate) " .. self.attrs["_onstate-page"] .. " end"))()(
                self,
                value
            )
        end
        frames[#frames + 1] = f
        return f
    end
    H.withGlobals({
        MurgleDB = { interface = { modifierPaging = false, pagingShift = 2, pagingCtrl = 3, pagingAlt = 0 } },
        MainActionBar = bar,
        SecureActionButtonMixin = { CalculateAction = calculate },
        InputUtil = {
            IsMKBUIEnabled = function()
                return true
            end,
        },
        InCombatLockdown = function()
            return combat
        end,
        CreateFrame = frame,
        RegisterStateDriver = function(f, state, condition)
            drivers[f] = condition
            f:transition("native")
        end,
        UnregisterStateDriver = function(f)
            drivers[f] = nil
        end,
        ClearOverrideBindings = function(f)
            f:ClearBindings()
        end,
        GetBindingKey = function(command)
            if command == "ACTIONBUTTON1" then
                return "1", "NUMPAD1"
            end
        end,
    }, function()
        local M = {
            DeferUntilOutOfCombat = function(_, callback)
                pending = callback
            end,
        }
        H.loadAddonFile("Modules/ModifierPaging.lua", M)
        fn(M.ModifierPaging, buttons, frames, function()
            return bindings, drivers, pending
        end, function(v)
            combat = v
        end)
    end)
end

test("modifier paging disabled startup creates no frames drivers or bindings", function()
    setup(function(P, buttons, frames, state)
        P.ApplyAll()
        eq(#frames, 0)
        local b, d = state()
        eq(next(b), nil)
        eq(next(d), nil)
    end)
end)
test("modifier paging uses native buttons and restores native pages and modified bindings on release", function()
    setup(function(P, buttons, frames, state)
        MurgleDB.interface.modifierPaging = true
        P.ApplyAll()
        local control = frames[1]
        assert(control.attrs["_onstate-page"])
        control:transition("2")
        for _, button in ipairs(buttons) do
            eq(button:GetAttribute("actionpage"), 2)
        end
        local b, d = state()
        eq(b["SHIFT-1"], "ACTIONBUTTON1")
        eq(b["CTRL-1"], "ACTIONBUTTON1")
        eq(b["CTRL-SHIFT-1"], "ACTIONBUTTON1")
        eq(b["ALT-1"], nil)
        control:transition("native")
        eq(buttons[1]:GetAttribute("actionpage"), nil)
        b = state()
        eq(next(b), nil)
        MurgleDB.interface.modifierPaging = false
        P.ApplyAll()
        b, d = state()
        eq(next(b), nil)
        eq(next(d), nil)
        for _, f in ipairs(frames) do
            eq(next(f.events), nil)
        end
    end)
end)
test("modifier paging driver preserves special states and defines exact priority combinations", function()
    setup(function(P, buttons, frames, state)
        MurgleDB.interface.modifierPaging = true
        P.ApplyAll()
        local _, d = state()
        local condition = d[frames[1]]
        assert(condition:find("[vehicleui]", 1, true))
        assert(condition:find("[shapeshift]", 1, true))
        assert(condition:find("[form]", 1, true))
        assert(condition:find("[mod:ctrl,mod:shift,nomod:alt] 3", 1, true))
        assert(condition:find("[nomod:ctrl,mod:shift,nomod:alt] 2", 1, true))
        MurgleDB.interface.pagingShift = 9
        P.ApplyAll()
        _, d = state()
        eq(next(d), nil)
    end)
end)
test("modifier paging setup and disable defer during combat using the latest setting", function()
    setup(function(P, buttons, frames, state, combat)
        combat(true)
        MurgleDB.interface.modifierPaging = true
        P.ApplyAll()
        eq(#frames, 0)
        local _, _, pending = state()
        eq(type(pending), "function")
        combat(false)
        pending()
        frames[1]:transition("2")
        combat(true)
        MurgleDB.interface.modifierPaging = false
        P.ApplyAll()
        eq(buttons[1]:GetAttribute("actionpage"), 2)
        _, _, pending = state()
        combat(false)
        pending()
        eq(buttons[1]:GetAttribute("actionpage"), nil)
    end)
end)
test("modifier paging refuses foreign pages and stops without overwriting another owner", function()
    setup(function(P, buttons, frames, state)
        MurgleDB.interface.modifierPaging = true
        buttons[2]:SetAttribute("actionpage", 4)
        P.ApplyAll()
        eq(#frames, 0)
        buttons[2]:SetAttribute("actionpage", nil)
        P.ApplyAll()
        frames[1]:transition("2")
        buttons[2]:SetAttribute("actionpage", 5)
        frames[1]:transition("3")
        eq(buttons[2]:GetAttribute("actionpage"), 5)
        eq(buttons[1]:GetAttribute("actionpage"), nil)
        local b = state()
        eq(next(b), nil)
        MurgleDB.interface.modifierPaging = false
        P.ApplyAll()
        eq(buttons[2]:GetAttribute("actionpage"), 5)
    end)
end)

test("modifier paging rejects modifier button-specific and wildcard page ownership", function()
    setup(function(P, buttons, frames, state)
        MurgleDB.interface.modifierPaging = true
        for _, name in ipairs({
            "shift-actionpage",
            "shift-actionpage1",
            "*actionpage1",
            "ctrl-actionpage*",
            "actionpage2",
        }) do
            buttons[1]:SetAttribute(name, 4)
            eq(P.Available(), false)
            P.ApplyAll()
            eq(#frames, 0)
            buttons[1]:SetAttribute(name, nil)
        end
    end)
end)
test("modifier paging is inert with missing APIs or all modifiers off", function()
    setup(function(P, buttons, frames, state)
        MurgleDB.interface.modifierPaging = true
        local register = RegisterStateDriver
        RegisterStateDriver = nil
        P.ApplyAll()
        eq(#frames, 0)
        RegisterStateDriver = register
        MurgleDB.interface.pagingShift = 0
        MurgleDB.interface.pagingCtrl = 0
        P.ApplyAll()
        eq(#frames, 0)
    end)
end)
test("modifier paging reapply and binding rebuild keep one driver and remove stale keys", function()
    setup(function(P, buttons, frames, state)
        MurgleDB.interface.modifierPaging = true
        P.ApplyAll()
        P.ApplyAll()
        eq(#frames, 2)
        local count = 0
        local _, drivers = state()
        for _ in pairs(drivers) do
            count = count + 1
        end
        eq(count, 1)
        frames[1]:transition("2")
        local b = state()
        eq(b["SHIFT-1"], "ACTIONBUTTON1")
        GetBindingKey = function(command)
            if command == "ACTIONBUTTON1" then
                return "Q"
            end
        end
        frames[2].scripts.OnEvent(frames[2], "UPDATE_BINDINGS")
        frames[1]:transition("2")
        b = state()
        eq(b["SHIFT-1"], nil)
        eq(b["SHIFT-Q"], "ACTIONBUTTON1")
    end)
end)
