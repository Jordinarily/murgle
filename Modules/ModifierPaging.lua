local _, Murgle = ...
local ModifierPaging = {}
Murgle.ModifierPaging = ModifierPaging
local controller, events, ownedButtons
local active, applying = false, false
local eventNames = { "UPDATE_BINDINGS", "PLAYER_ENTERING_WORLD" }

-- This runs only on secure driver state transitions. Never call protected
-- paging/binding functions from an insecure modifier event during combat.
local stateSnippet = [[
    self:ClearBindings()
    if self:GetAttribute("conflict") then return end
    local previous = tonumber(self:GetAttribute("murgle-lastpage"))
    local conflict = false
    for i = 1, 12 do
        local button = self:GetFrameRef("button" .. i)
        if button:GetAttribute("actionpage") ~= previous then conflict = true end
    end
    if conflict then
        for i = 1, 12 do
            local button = self:GetFrameRef("button" .. i)
            if button:GetAttribute("actionpage") == previous then
                button:SetAttribute("actionpage", nil)
            end
        end
        self:SetAttribute("conflict", true)
        return
    end
    local page = tonumber(newstate)
    for i = 1, 12 do
        self:GetFrameRef("button" .. i):SetAttribute("actionpage", page)
    end
    self:SetAttribute("murgle-lastpage", page)
    if page then
        for i = 1, self:GetAttribute("binding-count") do
            self:SetBinding(false, self:GetAttribute("binding-key-" .. i), self:GetAttribute("binding-action-" .. i))
        end
    end
]]

local function pageValue(value)
    return type(value) == "number" and value >= 0 and value <= 6 and value == math.floor(value)
end
local function buildDriver(settings)
    if
        not pageValue(settings.pagingShift)
        or not pageValue(settings.pagingCtrl)
        or not pageValue(settings.pagingAlt)
    then
        return
    end
    local pages = { shift = settings.pagingShift, ctrl = settings.pagingCtrl, alt = settings.pagingAlt }
    local clauses, prefixes = {}, {}
    for mask = 7, 1, -1 do
        local held =
            { shift = mask % 2 == 1, ctrl = math.floor(mask / 2) % 2 == 1, alt = math.floor(mask / 4) % 2 == 1 }
        local valid = true
        for mod, down in pairs(held) do
            if down and pages[mod] == 0 then
                valid = false
            end
        end
        if valid then
            local conditions = {}
            for _, mod in ipairs({ "ctrl", "shift", "alt" }) do
                conditions[#conditions + 1] = (held[mod] and "mod:" or "nomod:") .. mod
            end
            local page = held.ctrl and pages.ctrl or held.shift and pages.shift or pages.alt
            clauses[#clauses + 1] = "[" .. table.concat(conditions, ",") .. "] " .. page
            local prefix = ""
            for _, mod in ipairs({ "alt", "ctrl", "shift" }) do
                if held[mod] then
                    prefix = prefix .. mod:upper() .. "-"
                end
            end
            prefixes[#prefixes + 1] = prefix
        end
    end
    if #prefixes == 0 then
        return
    end
    local native =
        "[vehicleui][overridebar][possessbar][shapeshift][form][petbattle][bonusbar:1][bonusbar:2][bonusbar:3][bonusbar:4][bonusbar:5] native; "
    return native .. table.concat(clauses, "; ") .. "; native", prefixes
end

local function hasPageOverrides(frame)
    -- SecureTemplates resolves modifier/button-specific attributes before the
    -- bare page. These must remain another owner's exclusive responsibility.
    for _, prefix in ipairs({
        "",
        "shift-",
        "ctrl-",
        "alt-",
        "ctrl-shift-",
        "alt-shift-",
        "alt-ctrl-",
        "alt-ctrl-shift-",
        "*",
    }) do
        if prefix ~= "" and frame:GetAttribute(prefix .. "actionpage") ~= nil then
            return true
        end
        if frame:GetAttribute(prefix .. "actionpage*") ~= nil then
            return true
        end
        for suffix = 1, 31 do
            if frame:GetAttribute(prefix .. "actionpage" .. suffix) ~= nil then
                return true
            end
        end
    end
    return false
end

local function nativeButtons()
    if
        not MainActionBar
        or type(MainActionBar.GetAttribute) ~= "function"
        or hasPageOverrides(MainActionBar)
        or type(MainActionBar.actionButtons) ~= "table"
        or #MainActionBar.actionButtons ~= 12
        or not SecureActionButtonMixin
        or type(SecureActionButtonMixin.CalculateAction) ~= "function"
        or not InputUtil
        or type(InputUtil.IsMKBUIEnabled) ~= "function"
        or InputUtil.IsMKBUIEnabled() ~= true
    then
        return
    end
    local buttons = {}
    for i = 1, 12 do
        local button = MainActionBar.actionButtons[i]
        if
            not button
            or type(button.GetName) ~= "function"
            or button:GetName() ~= "ActionButton" .. i
            or button.bar ~= MainActionBar
            or button.CalculateAction ~= SecureActionButtonMixin.CalculateAction
            or type(button.GetAttribute) ~= "function"
            or type(button.SetAttribute) ~= "function"
            or button:GetAttribute("useparent-actionpage") ~= true
            or button:GetAttribute("actionpage") ~= nil
            or hasPageOverrides(button)
        then
            return
        end
        buttons[i] = button
    end
    return buttons
end
local function stop()
    if events then
        for _, event in ipairs(eventNames) do
            events:UnregisterEvent(event)
        end
    end
    if not active then
        return
    end
    UnregisterStateDriver(controller, "page")
    ClearOverrideBindings(controller)
    local previous = tonumber(controller:GetAttribute("murgle-lastpage"))
    for _, button in ipairs(ownedButtons) do
        if previous and button:GetAttribute("actionpage") == previous then
            button:SetAttribute("actionpage", nil)
        end
    end
    controller:SetAttribute("_onstate-page", nil)
    controller:SetAttribute("murgle-lastpage", nil)
    controller:SetAttribute("state-page", nil)
    active, ownedButtons = false, nil
end
function ModifierPaging.Available()
    if active then
        return controller:GetAttribute("conflict") ~= true
    end
    return type(CreateFrame) == "function"
        and type(RegisterStateDriver) == "function"
        and type(UnregisterStateDriver) == "function"
        and type(ClearOverrideBindings) == "function"
        and type(GetBindingKey) == "function"
        and nativeButtons() ~= nil
end
function ModifierPaging.ApplyAll()
    if applying then
        return
    end
    local settings = MurgleDB.interface
    if settings.modifierPaging ~= true and not active then
        return
    end
    if type(InCombatLockdown) ~= "function" then
        return
    end
    if InCombatLockdown() ~= false then
        if type(Murgle.DeferUntilOutOfCombat) == "function" then
            Murgle.DeferUntilOutOfCombat("interface.modifierPaging", ModifierPaging.ApplyAll)
        end
        return
    end
    applying = true
    stop()
    local driver, prefixes = buildDriver(settings)
    if settings.modifierPaging ~= true or not driver or not ModifierPaging.Available() then
        applying = false
        return
    end
    local buttons = nativeButtons()
    if not controller then
        controller = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    end
    if type(controller.SetFrameRef) ~= "function" then
        applying = false
        return
    end
    controller:SetAttribute("conflict", nil)
    controller:SetAttribute("murgle-lastpage", nil)
    local count = 0
    for i, button in ipairs(buttons) do
        controller:SetFrameRef("button" .. i, button)
        local command = "ACTIONBUTTON" .. i
        for _, key in ipairs({ GetBindingKey(command) }) do
            -- Only unmodified keyboard/mouse bindings; never reinterpret an
            -- existing modified chord or a gamepad input as a base key.
            if type(key) == "string" and key ~= "" and not key:find("-", 1, true) and not key:match("^PAD") then
                for _, prefix in ipairs(prefixes) do
                    count = count + 1
                    controller:SetAttribute("binding-key-" .. count, prefix .. key)
                    controller:SetAttribute("binding-action-" .. count, command)
                end
            end
        end
    end
    controller:SetAttribute("binding-count", count)
    controller:SetAttribute("_onstate-page", stateSnippet)
    ownedButtons, active = buttons, true
    RegisterStateDriver(controller, "page", driver)
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", ModifierPaging.ApplyAll)
    end
    for _, event in ipairs(eventNames) do
        events:RegisterEvent(event)
    end
    applying = false
end
ModifierPaging.Initialize = ModifierPaging.ApplyAll
