-- Forever Gethe pin eac30af597e5aaa43a60f6675ef5fdcea100375f:
-- ContainerFrame.UpdateQuestItem identifies offers by questID and not isActive;
-- Container/ItemDocumentation define GUID, item-use, spell and data-load APIs.
-- Direct offers without use spells only; live protected-use acceptance pending.
local _, Murgle = ...
local ItemOpening = {}
Murgle.ItemOpening = ItemOpening
local events, scanning, waiting, baseline, questEnabled
local requestedData = {}
local seen, pendingQuests, attemptedQuests, attemptedContainers = {}, {}, {}, {}
-- Use the native hasLoot flag for all carried loot containers, not an ID list.
-- openClams remains the saved key so existing user choices survive the rename.
local eventNames = {
    "BAG_UPDATE_DELAYED",
    "ITEM_DATA_LOAD_RESULT",
    "MODIFIER_STATE_CHANGED",
    "CURSOR_CHANGED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
    "LOOT_CLOSED",
    "QUEST_FINISHED",
    "UI_ERROR_MESSAGE",
    "MERCHANT_CLOSED",
    "MAIL_CLOSED",
    "TRADE_CLOSED",
    "BANKFRAME_CLOSED",
    "AUCTION_HOUSE_CLOSED",
    "GOSSIP_CLOSED",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UPDATE_STEALTH",
}
local interactions = {
    "MerchantFrame",
    "MailFrame",
    "TradeFrame",
    "BankFrame",
    "GuildBankFrame",
    "AuctionFrame",
    "AuctionHouseFrame",
    "GossipFrame",
    "QuestFrame",
    "LootFrame",
    "StaticPopup1",
    "StaticPopup2",
    "StaticPopup3",
    "StaticPopup4",
}
local function enabled()
    return MurgleDB.lootVendors.openClams == true or MurgleDB.automation.useQuestStarters == true
end
local function available()
    return type(CreateFrame) == "function"
        and type(InCombatLockdown) == "function"
        and type(IsShiftKeyDown) == "function"
        and type(IsStealthed) == "function"
        and type(UnitCastingInfo) == "function"
        and type(UnitChannelInfo) == "function"
        and type(SpellIsTargeting) == "function"
        and type(GetCursorInfo) == "function"
        and C_Secrets
        and type(C_Secrets.ShouldUnitSpellCastingBeSecret) == "function"
        and C_Container
        and type(C_Container.GetContainerNumSlots) == "function"
        and type(C_Container.GetContainerItemInfo) == "function"
        and type(C_Container.UseContainerItem) == "function"
        and C_Item
        and type(C_Item.GetItemGUID) == "function"
        and ItemLocation
        and type(ItemLocation.CreateFromBagAndSlot) == "function"
        and type(NUM_BAG_SLOTS) == "number"
        and NUM_BAG_SLOTS >= 0
        and NUM_BAG_SLOTS <= 5
end
local function safe()
    if
        not enabled()
        or InCombatLockdown() ~= false
        or IsShiftKeyDown() ~= false
        or IsStealthed() ~= false
        or SpellIsTargeting() ~= false
        or GetCursorInfo() ~= nil
        or C_Secrets.ShouldUnitSpellCastingBeSecret("player") ~= false
        or UnitCastingInfo("player") ~= nil
        or UnitChannelInfo("player") ~= nil
    then
        return false
    end
    for _, name in ipairs(interactions) do
        local frame = _G[name]
        if frame and (type(frame.IsShown) ~= "function" or frame:IsShown() ~= false) then
            return false
        end
    end
    return type(GetNumLootItems) == "function" and GetNumLootItems() == 0
end
local function guidAt(bag, slot)
    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local guid = location and C_Item.GetItemGUID(location)
    if type(guid) == "string" and guid ~= "" then
        return guid
    end
end
local function validCount(value)
    return type(value) == "number" and value >= 1 and value < math.huge and value == math.floor(value)
end
local function containerReady(info, guid, free)
    return MurgleDB.lootVendors.openClams == true
        and info.hasLoot == true
        and free >= 4
        and attemptedContainers[guid] ~= info.stackCount
        and type(GetCVarBool) == "function"
        and GetCVarBool("autoLootDefault") == true
        and type(IsModifiedClick) == "function"
        and IsModifiedClick("AUTOLOOTTOGGLE") == false
end
local function questAt(bag, slot, info, guid)
    if
        MurgleDB.automation.useQuestStarters ~= true
        or not pendingQuests[guid]
        or type(C_Container.GetContainerItemQuestInfo) ~= "function"
        or type(C_Item.IsItemDataCachedByID) ~= "function"
        or type(C_Item.GetItemSpell) ~= "function"
        or not C_QuestLog
        or type(C_QuestLog.IsQuestFlaggedCompleted) ~= "function"
    then
        return
    end
    if C_Item.IsItemDataCachedByID(info.itemID) ~= true then
        if requestedData[info.itemID] == nil and type(C_Item.RequestLoadItemDataByID) == "function" then
            requestedData[info.itemID] = true
            C_Item.RequestLoadItemDataByID(info.itemID)
        end
        -- A cache hit may answer synchronously, while scanning blocks reentry.
        if C_Item.IsItemDataCachedByID(info.itemID) ~= true then
            return
        end
    end
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
    if
        type(quest) ~= "table"
        or not validCount(quest.questID)
        or quest.isActive ~= false
        or attemptedQuests[quest.questID]
        or C_QuestLog.IsQuestFlaggedCompleted(quest.questID) ~= false
    then
        return
    end
    -- Only direct quest-offer items. Spell-casting quest tools remain manual.
    local spellName, spellID = C_Item.GetItemSpell(info.itemID)
    if spellName ~= nil or spellID ~= nil then
        return
    end
    return quest.questID
end
local function scan()
    if scanning or not enabled() or not available() then
        return
    end
    scanning = true
    local current, candidates, free = {}, {}, 0
    for bag = 0, NUM_BAG_SLOTS do
        if type(C_Container.GetContainerNumFreeSlots) == "function" then
            local count, family = C_Container.GetContainerNumFreeSlots(bag)
            if type(count) == "number" and count >= 0 and count <= 1000 and family == 0 then
                free = free + count
            end
        end
        local slots = C_Container.GetContainerNumSlots(bag)
        if type(slots) == "number" and slots >= 0 and slots <= 1000 and slots == math.floor(slots) then
            for slot = 1, slots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if type(info) == "table" and validCount(info.itemID) and validCount(info.stackCount) then
                    local guid = guidAt(bag, slot)
                    if guid then
                        current[guid] = true
                        if questEnabled and not baseline and not seen[guid] then
                            pendingQuests[guid] = true
                        end
                        if info.isLocked == false and (info.hasLoot == true or pendingQuests[guid]) then
                            candidates[#candidates + 1] = { bag = bag, slot = slot, info = info, guid = guid }
                        end
                    end
                end
            end
        end
    end
    seen, baseline = current, false
    for guid in pairs(pendingQuests) do
        if not current[guid] then
            pendingQuests[guid] = nil
        end
    end
    for guid in pairs(attemptedContainers) do
        if not current[guid] then
            attemptedContainers[guid] = nil
        end
    end
    if waiting or not safe() then
        scanning = false
        return
    end
    for _, row in ipairs(candidates) do
        local questID = questAt(row.bag, row.slot, row.info, row.guid)
        local container = containerReady(row.info, row.guid, free)
        if container or questID then
            -- Re-read immediately before use; never act on a moved/replaced item.
            local info = C_Container.GetContainerItemInfo(row.bag, row.slot)
            if
                safe()
                and info
                and info.itemID == row.info.itemID
                and info.stackCount == row.info.stackCount
                and info.isLocked == false
                and (not container or info.hasLoot == true)
                and guidAt(row.bag, row.slot) == row.guid
            then
                if container then
                    attemptedContainers[row.guid] = info.stackCount
                end
                if questID then
                    attemptedQuests[questID], pendingQuests[row.guid] = true, nil
                end
                waiting = true
                -- Never cast spells, accept quests/confirmations, or retry failures.
                C_Container.UseContainerItem(row.bag, row.slot)
                break
            end
        end
    end
    scanning = false
end
local function onEvent(_, event, unit, success)
    if not enabled() then
        return
    end
    if event == "ITEM_DATA_LOAD_RESULT" then
        if requestedData[unit] ~= true then
            return
        end
        requestedData[unit] = false
        if success ~= true then
            return
        end
    elseif event == "MODIFIER_STATE_CHANGED" then
        if (unit ~= "LSHIFT" and unit ~= "RSHIFT") or success ~= 0 then
            return
        end
    end
    if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if unit ~= "player" then
            return
        end
    end
    if event == "UI_ERROR_MESSAGE" then
        waiting = nil
        return
    end
    if event == "LOOT_CLOSED" or event == "QUEST_FINISHED" or event == "PLAYER_ENTERING_WORLD" then
        waiting = nil
    end
    scan()
end
function ItemOpening.ApplyAll()
    local quests = MurgleDB.automation.useQuestStarters == true
    if quests and not questEnabled then
        baseline, pendingQuests = true, {}
    elseif not quests then
        pendingQuests = {}
    end
    questEnabled = quests
    if not enabled() or not available() then
        if events then
            for _, event in ipairs(eventNames) do
                events:UnregisterEvent(event)
            end
        end
        seen, pendingQuests, attemptedContainers, requestedData = {}, {}, {}, {}
        waiting, baseline = nil, true
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", onEvent)
        baseline = true
    end
    for _, event in ipairs(eventNames) do
        events:RegisterEvent(event)
    end
    scan()
end
ItemOpening.Initialize = ItemOpening.ApplyAll
