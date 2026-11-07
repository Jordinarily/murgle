local H = dofile("tests/helpers.lua")
local P = {}
function P.withPaging(fn, initial)
    local state = {
        shift = false,
        ctrl = false,
        alt = false,
        special = false,
        form = false,
        bonus = 0,
        combat = false,
        page = initial or 1,
        frames = {},
        drivers = {},
        bindings = {},
        buttons = {},
        saved = { ["1"] = "ACTIONBUTTON1", ["SHIFT-1"] = "ACTIONPAGE1" },
    }
    local function rawFrame()
        local f = H.newEventFrame()
        f.attrs = {}
        f.refs = {}
        function f:GetAttribute(prefix, name, suffix)
            if not name then
                return self.attrs[prefix]
            end
            for _, key in ipairs({
                prefix .. name .. suffix,
                "*" .. name .. suffix,
                prefix .. name .. "*",
                "*" .. name .. "*",
                prefix .. name,
                name .. suffix,
                name,
            }) do
                if self.attrs[key] ~= nil then
                    return self.attrs[key]
                end
            end
        end
        function f:GetEffectiveAttribute(name, button, prefix, suffix)
            prefix = prefix
                or ((state.alt and "alt-" or "") .. (state.ctrl and "ctrl-" or "") .. (state.shift and "shift-" or ""))
            suffix = tostring(suffix or 1)
            local value = self:GetAttribute(prefix, name, suffix)
            if value == nil and self.attrs["useparent-" .. name] and self.bar then
                value = self.bar:GetEffectiveAttribute(name, button, prefix, suffix)
            end
            return value
        end
        function f:SetAttribute(name, value)
            if self.attrs[name] == value then
                return
            end
            self.attrs[name] = value
            if self.header and name == "state-page" and self.attrs["_onstate-page"] then
                -- Forever RestrictedExecution.lua BuildRestrictedClosure rejects
                -- these before compiling, even in a branch that never executes.
                -- Gethe pin eac30af597e5aaa43a60f6675ef5fdcea100375f,
                -- Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/RestrictedExecution.lua.
                local body = self.attrs["_onstate-page"]
                assert(not body:match("function"), "The function keyword is not permitted")
                assert(not body:match("[{}]"), "Direct table creation is not permitted")
                assert(loadstring("return function(self,stateid,newstate) " .. body .. " end"))()(self, "page", value)
            elseif self.UpdateAction then
                self:UpdateAction()
            end
        end
        function f:SetFrameRef(name, value)
            self.refs[name] = value
        end
        function f:GetFrameRef(name)
            return self.refs[name]
        end
        function f:GetName()
            return self.name
        end
        function f:GetID()
            return self.id
        end
        function f:ClearBindings()
            state.bindings = {}
        end
        function f:SetBinding(_, key, action)
            state.bindings[key] = action
        end
        function f:CallMethod(name, ...)
            self[name](self, ...)
        end
        return f
    end
    local bar = rawFrame()
    state.bar = bar
    bar.actionButtons = state.buttons
    bar.attrs.actionpage = state.page
    local label = { text = tostring(state.page) }
    function label:SetText(value)
        self.text = tostring(value)
    end
    function label:GetText()
        return self.text
    end
    bar.ActionBarPageNumber = { Text = label }
    -- Model the native child-attribute, then parent fallback calculation and
    -- automatic action/visual refresh, rather than only recording SetAttribute.
    local function calculate(button)
        local prefix = (state.alt and "alt-" or "")
            .. (state.ctrl and "ctrl-" or "")
            .. (state.shift and "shift-" or "")
        local page = button:GetAttribute(prefix, "actionpage", "1")
        if not page then
            page = bar:GetAttribute(prefix, "actionpage", "1") or state.page
        end
        return button.id + (page - 1) * 12
    end
    for i = 1, 12 do
        local b = rawFrame()
        b.name = "ActionButton" .. i
        b.id = i
        b.bar = bar
        b.CalculateAction = calculate
        b.attrs["useparent-actionpage"] = true
        function b:UpdateAction()
            self.action = self:CalculateAction()
            self.rendered = self.action
        end
        b:UpdateAction()
        state.buttons[i] = b
    end
    local function parse(driver)
        for clause in driver:gmatch("[^;]+") do
            local options, result = clause:match("^(.-)%s*([^%s%[%]]+)%s*$")
            if options and not options:find("%[") then
                return tonumber(result) or result
            end
            if options then
                for group in options:gmatch("%[([^%]]+)%]") do
                    local matches = true
                    for condition in group:gmatch("[^,]+") do
                        local mod = condition:match("^mod:(%w+)$")
                        local no = condition:match("^nomod:(%w+)$")
                        local page = condition:match("^bar:(%d+)$")
                        if mod then
                            matches = matches and state[mod] == true
                        elseif no then
                            matches = matches and state[no] ~= true
                        elseif page then
                            matches = matches and state.page == tonumber(page)
                        elseif condition == "nomod" then
                            matches = matches and not state.shift and not state.ctrl and not state.alt
                        elseif condition == "form" then
                            matches = matches and state.form
                        elseif condition == "overridebar" then
                            matches = matches and state.special
                        elseif condition:match("^bonusbar:%d+$") then
                            matches = matches and state.bonus == tonumber(condition:match("%d+"))
                        else
                            matches = false
                        end
                    end
                    if matches then
                        return tonumber(result) or result
                    end
                end
            end
        end
    end
    function state:drive()
        for frame, driver in pairs(self.drivers) do
            frame:SetAttribute("state-page", parse(driver))
        end
    end
    function state:modifiers(shift, ctrl, alt)
        self.shift, self.ctrl, self.alt = shift == true, ctrl == true, alt == true
        self:drive()
    end
    function state:press(key)
        local command = self.bindings[key] or self.saved[key]
        local button = command and command:match("^ACTIONBUTTON(%d+)$")
        return button and self.buttons[tonumber(button)]:CalculateAction(), command
    end
    H.withGlobals({
        MainActionBar = bar,
        SecureActionButtonMixin = { CalculateAction = calculate },
        IsShiftKeyDown = function()
            return state.shift
        end,
        IsControlKeyDown = function()
            return state.ctrl
        end,
        IsAltKeyDown = function()
            return state.alt
        end,
        InputUtil = {
            IsMKBUIEnabled = function()
                return true
            end,
        },
        UIParent = {},
        MurgleDB = { interface = { holdActionPages = false, holdShiftPage = 2, holdCtrlPage = 3, holdAltPage = 0 } },
        InCombatLockdown = function()
            return state.combat
        end,
        C_ActionBar = {
            GetActionBarPage = function()
                return state.page
            end,
            SetActionBarPage = function(page)
                assert(not state.combat, "insecure native page change during combat")
                state.page = page
                bar.attrs.actionpage = page
                for _, button in ipairs(state.buttons) do
                    button:UpdateAction()
                end
                for _, frame in ipairs(state.frames) do
                    if frame.events.ACTIONBAR_PAGE_CHANGED then
                        frame.scripts.OnEvent(frame, "ACTIONBAR_PAGE_CHANGED")
                    end
                end
                label:SetText(page)
            end,
        },
        CreateFrame = function(_, _, _, template)
            local f = rawFrame()
            f.header = template == "SecureHandlerStateTemplate"
            state.frames[#state.frames + 1] = f
            return f
        end,
        RegisterStateDriver = function(f, _, driver)
            state.drivers[f] = driver
            state:drive()
        end,
        UnregisterStateDriver = function(f)
            state.drivers[f] = nil
        end,
        ClearOverrideBindings = function(f)
            f:ClearBindings()
        end,
        GetBindingKey = function(command)
            if command == "ACTIONBUTTON1" then
                return "1"
            end
        end,
        hooksecurefunc = function(obj, name, hook)
            local original = obj[name]
            obj[name] = function(...)
                original(...)
                hook(...)
            end
            state.hooks = (state.hooks or 0) + 1
        end,
    }, function()
        local M = {
            DeferUntilOutOfCombat = function(_, callback)
                state.pending = callback
            end,
        }
        H.loadAddonFile("Modules/ModifierPaging.lua", M)
        fn(M.ModifierPaging, state, label)
    end)
end
return P
