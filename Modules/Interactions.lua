local _, Murgle = ...
local Interactions = {}
Murgle.Interactions = Interactions

local gossipEvents, selectedOption
local popupHooked, rollHooked, disenchantRollHooked = false, false, false
local definitions = {}
local busy, generation = false, 0

local function integer(value)
    return type(value) == "number" and value == math.floor(value) and value >= 0 and value < 1000000
end

local function allowed()
    return type(InCombatLockdown) == "function"
        and not InCombatLockdown()
        and type(IsShiftKeyDown) == "function"
        and not IsShiftKeyDown()
end

local function gossip(_, event)
    if event == "GOSSIP_CLOSED" then
        selectedOption = nil
        return
    end
    if MurgleDB.automation.skipServiceGossip ~= true or busy or not allowed() then
        return
    end
    local api = C_GossipInfo
    local kinds = Enum and Enum.GossipOptionStatus
    if not api or not kinds or type(kinds.Available) ~= "number" then
        return
    end
    for _, name in ipairs({
        "GetNumAvailableQuests",
        "GetNumActiveQuests",
        "ForceGossip",
        "GetOptions",
        "SelectOptionByIndex",
    }) do
        if type(api[name]) ~= "function" then
            return
        end
    end
    if api.GetNumAvailableQuests() ~= 0 or api.GetNumActiveQuests() ~= 0 or api.ForceGossip() ~= false then
        return
    end
    local options = api.GetOptions()
    if type(options) ~= "table" or #options ~= 1 then
        return
    end
    local option = options[1]
    -- Native TaxiGossipIcon (132057) opens a route map; never choose a route,
    -- pay for travel, select quests, or accept arbitrary single-option gossip.
    if
        type(option) ~= "table"
        or option.icon ~= 132057
        or option.flags ~= 0
        or option.status ~= kinds.Available
        or option.selectOptionWhenOnlyOption ~= false
        or option.spellID ~= nil
        or type(option.rewards) ~= "table"
        or next(option.rewards) ~= nil
        or not integer(option.gossipOptionID)
        or option.gossipOptionID == 0
        or not integer(option.orderIndex)
        or option.orderIndex == 0
        or option.gossipOptionID == selectedOption
    then
        return
    end
    selectedOption = option.gossipOptionID
    busy = true
    api.SelectOptionByIndex(option.orderIndex)
    busy = false
end

local function dialog(which)
    if type(definitions[which]) ~= "table" or type(StaticPopup_FindVisible) ~= "function" then
        return
    end
    local frame = StaticPopup_FindVisible(which)
    if
        not frame
        or frame.which ~= which
        or frame.dialogInfo ~= definitions[which]
        or not StaticPopupDialogs
        or StaticPopupDialogs[which] ~= definitions[which]
        or type(frame.IsProtected) ~= "function"
        or frame:IsProtected()
        or type(frame.Hide) ~= "function"
    then
        return
    end
    return frame
end

local function accept(which, fn)
    local frame = dialog(which)
    if not frame then
        return
    end
    local current, data, data2 = generation, frame.data, frame.data2
    busy = true
    fn(frame)
    busy = false
    if current == generation and dialog(which) == frame and frame.data == data and frame.data2 == data2 then
        frame:Hide()
    end
end

local function popupShown(which)
    local settings = MurgleDB.automation
    if settings.confirmLootPickup ~= true then
        return
    end
    generation = generation + 1
    if busy or not allowed() then
        return
    end
    if which == "LOOT_BIND" and settings.confirmLootPickup == true then
        local frame = dialog(which)
        local kinds = Enum and Enum.LootSlotType
        local count = type(GetNumLootItems) == "function" and GetNumLootItems()
        if
            not frame
            or not kinds
            or not integer(frame.data)
            or frame.data == 0
            or not integer(count)
            or frame.data > count
            or type(GetLootSlotType) ~= "function"
            or GetLootSlotType(frame.data) ~= kinds.Item
            or type(GetLootSlotInfo) ~= "function"
            or select(6, GetLootSlotInfo(frame.data)) ~= false
            or type(ConfirmLootSlot) ~= "function"
        then
            return
        end
        accept(which, function(current)
            ConfirmLootSlot(current.data)
        end)
    end
end

local function confirmRoll(rollID, rollType)
    if MurgleDB.automation.confirmLootRolls ~= true then
        return
    end
    generation = generation + 1
    if
        busy
        or not allowed()
        or not integer(rollID)
        or rollID == 0
        or not integer(rollType)
        or rollType < 1
        or rollType > 3
        or type(ConfirmLootRoll) ~= "function"
    then
        return
    end
    local frame = dialog("CONFIRM_LOOT_ROLL")
    if frame and frame.data == rollID and frame.data2 == rollType then
        accept("CONFIRM_LOOT_ROLL", function()
            ConfirmLootRoll(rollID, rollType)
        end)
    end
end

function Interactions.OpenClickCasting()
    if
        type(InCombatLockdown) == "function"
        and not InCombatLockdown()
        and type(ToggleClickBindingFrame) == "function"
    then
        ToggleClickBindingFrame()
    end
end

function Interactions.ApplyAll()
    local settings = MurgleDB.automation
    if settings.skipServiceGossip == true then
        if not gossipEvents then
            gossipEvents = CreateFrame("Frame")
            gossipEvents:SetScript("OnEvent", gossip)
        end
        gossipEvents:RegisterEvent("GOSSIP_SHOW")
        gossipEvents:RegisterEvent("GOSSIP_CLOSED")
    elseif gossipEvents then
        gossipEvents:UnregisterEvent("GOSSIP_SHOW")
        gossipEvents:UnregisterEvent("GOSSIP_CLOSED")
        selectedOption = nil
    end
    if type(hooksecurefunc) ~= "function" then
        return
    end
    for _, which in ipairs({ "LOOT_BIND", "CONFIRM_LOOT_ROLL" }) do
        if not definitions[which] and StaticPopupDialogs and type(StaticPopupDialogs[which]) == "table" then
            definitions[which] = StaticPopupDialogs[which]
        end
    end
    if settings.confirmLootPickup == true and not popupHooked and type(StaticPopup_Show) == "function" then
        hooksecurefunc("StaticPopup_Show", popupShown)
        popupHooked = true
    end
    if settings.confirmLootRolls == true then
        -- These helpers finish assigning dialog.data/data2 AFTER StaticPopup_Show.
        -- Hook the completed native request, never choose or initiate a roll.
        if not rollHooked and type(ConfirmLootRollDialog_Show) == "function" then
            hooksecurefunc("ConfirmLootRollDialog_Show", confirmRoll)
            rollHooked = true
        end
        if not disenchantRollHooked and type(ConfirmDisenchantRollDialog_Show) == "function" then
            hooksecurefunc("ConfirmDisenchantRollDialog_Show", confirmRoll)
            disenchantRollHooked = true
        end
    end
end

Interactions.Initialize = Interactions.ApplyAll
