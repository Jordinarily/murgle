local _, Murgle = ...
local ItemActions = {}
Murgle.ItemActions = ItemActions

local overlay, events, hovered, targetLink, targetBag, targetSlot, targetGUID
local installed = false
local enterRegistry
local ENTER_EVENT = "ContainerFrameItemButton.EnterButton"

local function enabled()
    return MurgleDB and MurgleDB.lootVendors and MurgleDB.lootVendors.disenchantClick == true
end

local function available()
    return type(CreateFrame) == "function"
        and EventRegistry
        and type(EventRegistry.RegisterCallback) == "function"
        and type(EventRegistry.UnregisterCallback) == "function"
        and type(RegisterAttributeDriver) == "function"
        and type(InCombatLockdown) == "function"
        and type(IsAltKeyDown) == "function"
        and type(IsControlKeyDown) == "function"
        and type(IsShiftKeyDown) == "function"
        and C_SpellBook
        and type(C_SpellBook.IsSpellKnown) == "function"
        and C_Container
        and type(C_Container.GetContainerItemInfo) == "function"
        and C_Item
        and type(C_Item.GetItemInfo) == "function"
        and type(C_Item.GetItemGUID) == "function"
        and ItemLocation
        and type(ItemLocation.CreateFromBagAndSlot) == "function"
        and ContainerFrameItemButtonMixin
        and type(ContainerFrameItemButtonMixin.GetBagID) == "function"
        and type(NUM_BAG_FRAMES) == "number"
end

local function clear()
    hovered, targetLink, targetBag, targetSlot, targetGUID = nil, nil, nil, nil, nil
    if overlay and InCombatLockdown() == false then
        overlay:Hide()
        overlay:SetAttribute("alt-type1", nil)
        overlay:SetAttribute("spell", nil)
        overlay:SetAttribute("target-bag", nil)
        overlay:SetAttribute("target-slot", nil)
        overlay:SetAttribute("_entered", false)
        overlay:ClearAllPoints()
    end
end

local function eligible(button)
    if
        not enabled()
        or not available()
        or InCombatLockdown() ~= false
        or not IsAltKeyDown()
        or IsControlKeyDown()
        or IsShiftKeyDown()
        or not button
        or button.GetBagID ~= ContainerFrameItemButtonMixin.GetBagID
        or type(button.GetID) ~= "function"
        or type(button.IsShown) ~= "function"
        or type(button.IsMouseOver) ~= "function"
        or not button:IsShown()
        or not button:IsMouseOver()
        or C_SpellBook.IsSpellKnown(13262) ~= true
    then
        return
    end
    local bag, slot = button:GetBagID(), button:GetID()
    if
        type(bag) ~= "number"
        or bag < 0
        or bag > NUM_BAG_FRAMES
        or bag ~= math.floor(bag)
        or type(slot) ~= "number"
        or slot < 1
        or slot ~= math.floor(slot)
    then
        return
    end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or info.isLocked ~= false or info.quality ~= 2 or type(info.hyperlink) ~= "string" then
        return
    end
    local _, link, quality, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(info.hyperlink)
    if link ~= info.hyperlink or quality ~= 2 or (classID ~= 2 and classID ~= 4) then
        return
    end
    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local guid = location and C_Item.GetItemGUID(location)
    if type(guid) ~= "string" or guid == "" then
        return
    end
    return bag, slot, link, guid
end

local function enter(button)
    if not enabled() or InCombatLockdown() ~= false then
        return
    end
    clear()
    if button and button.GetBagID == ContainerFrameItemButtonMixin.GetBagID then
        hovered = button
    end
    local bag, slot, link, guid = eligible(button)
    if not link then
        return
    end
    hovered, targetBag, targetSlot, targetLink, targetGUID = button, bag, slot, link, guid
    overlay:SetAttribute("spell", 13262)
    overlay:SetAttribute("target-bag", bag)
    overlay:SetAttribute("target-slot", slot)
    overlay:SetAttribute("alt-type1", "spell")
    overlay:SetAllPoints(button)
    overlay:SetAttribute("_entered", true)
    overlay:Show()
end

function ItemActions.IsLockpickAvailable()
    -- No authoritative per-item lock/skill data: never guess from tooltip text.
    return false
end

local function unregisterEnter()
    if enterRegistry then
        enterRegistry:UnregisterCallback(ENTER_EVENT, ItemActions)
        enterRegistry = nil
    end
end

function ItemActions.ApplyAll()
    -- Registry subscriptions are not protected. Remove them immediately even
    -- when secure overlay cleanup itself must wait until combat ends.
    if not enabled() or not available() then
        unregisterEnter()
    end
    if type(InCombatLockdown) ~= "function" then
        return
    end
    if InCombatLockdown() ~= false then
        if (enabled() or installed) and type(Murgle.DeferUntilOutOfCombat) == "function" then
            Murgle.DeferUntilOutOfCombat("items.apply", ItemActions.ApplyAll)
        end
        return
    end
    clear()
    if not enabled() or not available() then
        if events then
            events:UnregisterAllEvents()
        end
        return
    end
    if not installed then
        overlay = CreateFrame(
            "Button",
            nil,
            UIParent,
            "SecureActionButtonTemplate,SecureHandlerAttributeTemplate,SecureHandlerEnterLeaveTemplate"
        )
        overlay:Hide()
        overlay:SetFrameStrata("TOOLTIP")
        overlay:RegisterForClicks("LeftButtonUp")
        -- The driver only hides; it never re-arms a stale item on modifier press.
        overlay:SetAttribute(
            "_onattributechanged",
            [[
            if name == 'visibility' and value == 'hide' then
                self:Hide(); self:SetAttribute('alt-type1', nil)
                self:ClearAllPoints()
            end
        ]]
        )
        overlay:SetAttribute(
            "_onleave",
            [[
            self:Hide(); self:SetAttribute('alt-type1', nil); self:ClearAllPoints()
        ]]
        )
        RegisterAttributeDriver(overlay, "visibility", "[combat] hide; [mod:alt,nomod:ctrl,nomod:shift] show; hide")
        overlay:SetScript("PreClick", function(_, button)
            if InCombatLockdown() ~= false then
                return -- Secure driver has already removed the action in combat.
            end
            local bag, slot, link, guid = eligible(hovered)
            if
                button ~= "LeftButton"
                or not link
                or bag ~= targetBag
                or slot ~= targetSlot
                or link ~= targetLink
                or guid ~= targetGUID
            then
                clear()
            end
        end)
        overlay:SetScript("PostClick", function()
            if InCombatLockdown() == false then
                clear()
            end
        end)
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", function(_, event)
            if InCombatLockdown() ~= false then
                hovered, targetLink, targetBag, targetSlot, targetGUID = nil, nil, nil, nil, nil
                return
            end
            if event == "PLAYER_REGEN_ENABLED" then
                ItemActions:ApplyAll()
            elseif event == "MODIFIER_STATE_CHANGED" then
                local button = hovered
                clear()
                if button then
                    enter(button)
                end
            else
                clear()
            end
        end)
        installed = true
    end
    if enterRegistry ~= EventRegistry then
        unregisterEnter()
        -- The native mixin emits this after populating hover state. Registry
        -- callbacks receive their owner context first, then the native button.
        EventRegistry:RegisterCallback(ENTER_EVENT, function(_, button)
            enter(button)
        end, ItemActions)
        enterRegistry = EventRegistry
    end
    for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "MODIFIER_STATE_CHANGED" }) do
        events:RegisterEvent(event)
    end
end

function ItemActions.Initialize()
    ItemActions.ApplyAll()
end
