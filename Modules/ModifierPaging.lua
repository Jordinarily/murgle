local _, Murgle = ...
local ModifierPaging = {}
Murgle.ModifierPaging = ModifierPaging
local controller, events, ownedButtons, indicator
local indicatorHooks = {}
local writingIndicator = false
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
        if button:GetAttribute("actionpage") ~= previous or button:GetAttribute("modifiers") ~= nil then conflict = true end
    end
    if self:GetFrameRef("bar"):GetAttribute("modifiers") ~= nil then conflict = true end
    local prefix = ""
    if IsShiftKeyDown() then prefix = "shift-" .. prefix end
    if IsControlKeyDown() then prefix = "ctrl-" .. prefix end
    if IsAltKeyDown() then prefix = "alt-" .. prefix end
    local page = newstate == "base" and 1 or tonumber(string.match(newstate, "^p(%d+)m%d+$"))
    local wrote = false
    if not conflict then
        for i = 1, 12 do
            self:GetFrameRef("button" .. i):SetAttribute("actionpage", page)
        end
        wrote = true
        if page then
            -- Use Blizzard's resolver, including custom modifiers and wildcard
            -- precedence, rather than reconstructing its attribute lookup.
            for i = 1, 12 do
                local button = self:GetFrameRef("button" .. i)
                for suffix = 1, 31 do
                    if button:GetEffectiveAttribute("actionpage", nil, prefix, suffix) ~= page then conflict = true end
                end
            end
        end
    end
    if conflict then
        for i = 1, 12 do
            local button = self:GetFrameRef("button" .. i)
            local owned = wrote and page or previous
            if button:GetAttribute("actionpage") == owned then
                button:SetAttribute("actionpage", nil)
            end
        end
        self:SetAttribute("conflict", true)
        self:SetAttribute("effective-page", nil)
        self:CallMethod("UpdatePageIndicator")
        return
    end
    self:SetAttribute("murgle-lastpage", page)
    self:SetAttribute("effective-page", page)
    if string.sub(newstate, 1, 1) == "p" then
        for i = 1, self:GetAttribute("binding-count") do
            self:SetBinding(false, self:GetAttribute("binding-key-" .. i), self:GetAttribute("binding-action-" .. i))
        end
    end
    self:CallMethod("UpdatePageIndicator")
]]

local function pageValue(value)
    return type(value) == "number" and value >= 0 and value <= 6 and value == math.floor(value)
end
local function buildDriver(settings)
    if
        not pageValue(settings.holdShiftPage)
        or not pageValue(settings.holdCtrlPage)
        or not pageValue(settings.holdAltPage)
    then
        return
    end
    local pages = { shift = settings.holdShiftPage, ctrl = settings.holdCtrlPage, alt = settings.holdAltPage }
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
            clauses[#clauses + 1] = "[" .. table.concat(conditions, ",") .. "] p" .. page .. "m" .. mask
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
        "[vehicleui][overridebar][possessbar][shapeshift][petbattle][bonusbar:1][bonusbar:2][bonusbar:3][bonusbar:4][bonusbar:5] native; "
    local manual = "[bar:2][bar:3][bar:4][bar:5][bar:6] native; "
    return native .. manual .. table.concat(clauses, "; ") .. "; [nomod] base; native", prefixes
end

local function hasPageOverrides(frame)
    if frame:GetAttribute("modifiers") ~= nil then
        return true
    end
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
local function refreshIndicator()
    if not indicator or writingIndicator then
        return
    end
    local page
    if active and controller:GetAttribute("conflict") ~= true then
        page = tonumber(controller:GetAttribute("effective-page"))
    end
    page = page or C_ActionBar.GetActionBarPage()
    if type(page) ~= "number" or not (page >= 1 and page <= 18) then
        return
    end
    if indicator:GetText() ~= tostring(page) then
        writingIndicator = true
        indicator:SetText(page)
        writingIndicator = false
    end
end

local function watchIndicator()
    indicator = MainActionBar.ActionBarPageNumber.Text
    if not indicatorHooks[indicator] then
        hooksecurefunc(indicator, "SetText", function(self)
            if active and self == indicator and not writingIndicator then
                refreshIndicator()
            end
        end)
        indicatorHooks[indicator] = true
    end
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
    active = false
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
    controller:SetAttribute("effective-page", nil)
    ownedButtons = nil
    refreshIndicator()
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
        and type(hooksecurefunc) == "function"
        and C_ActionBar
        and type(C_ActionBar.GetActionBarPage) == "function"
        and type(C_ActionBar.SetActionBarPage) == "function"
        and nativeButtons() ~= nil
        and MainActionBar.ActionBarPageNumber
        and MainActionBar.ActionBarPageNumber.Text
        and type(MainActionBar.ActionBarPageNumber.Text.SetText) == "function"
        and type(MainActionBar.ActionBarPageNumber.Text.GetText) == "function"
end
function ModifierPaging.IsActive()
    return active and controller:GetAttribute("conflict") ~= true
end
function ModifierPaging.ApplyAll()
    if applying then
        return
    end
    local settings = MurgleDB.interface
    if settings.holdActionPages ~= true and not active then
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
    local wasActive = active
    stop()
    local driver, prefixes = buildDriver(settings)
    if settings.holdActionPages ~= true or not driver or not ModifierPaging.Available() then
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
    watchIndicator()
    controller.UpdatePageIndicator = refreshIndicator
    if not wasActive then
        local ok = pcall(C_ActionBar.SetActionBarPage, 1)
        if not ok or C_ActionBar.GetActionBarPage() ~= 1 then
            applying = false
            return
        end
    end
    controller:SetFrameRef("bar", MainActionBar)
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
