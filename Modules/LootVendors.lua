local _, Murgle = ...
local LootVendors = {}
Murgle.LootVendors = LootVendors

local hookedFrames = {}

local function moneyValue(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

local lootEvents
local lootAttempted, looting = false, false
local lootGeneration = 0

local function lootAPIsAvailable()
    local kinds = Enum and Enum.LootSlotType
    return type(InCombatLockdown) == "function"
        and type(GetCVarBool) == "function"
        and type(IsModifiedClick) == "function"
        and type(GetNumLootItems) == "function"
        and type(GetLootSlotInfo) == "function"
        and type(GetLootSlotType) == "function"
        and type(LootSlot) == "function"
        and kinds
        and type(kinds.Item) == "number"
        and type(kinds.Money) == "number"
        and type(kinds.Currency) == "number"
end

local function fastLootAllowed()
    if MurgleDB.lootVendors.fastLoot ~= true or not lootAPIsAvailable() or InCombatLockdown() ~= false then
        return false
    end
    local auto, modifier = GetCVarBool("autoLootDefault"), IsModifiedClick("AUTOLOOTTOGGLE")
    return type(auto) == "boolean" and type(modifier) == "boolean" and auto ~= modifier
end

local function lootOnEvent(_, event, autoLoot)
    if event == "LOOT_CLOSED" then
        lootGeneration = lootGeneration + 1
        lootAttempted = false
        return
    end
    if looting or lootAttempted or autoLoot ~= true or not fastLootAllowed() then
        return
    end
    local count = GetNumLootItems()
    if not moneyValue(count) or count == 0 then
        return
    end
    -- One synchronous reverse pass, following the Leatrix Forever event/slot
    -- approach. Never accept a loot confirmation or retry a locked slot.
    lootAttempted, looting = true, true
    local generation = lootGeneration
    local kinds = Enum.LootSlotType
    for slot = count, 1, -1 do
        if generation ~= lootGeneration or not fastLootAllowed() then
            break
        end
        local kind = GetLootSlotType(slot)
        local _, _, _, _, _, locked = GetLootSlotInfo(slot)
        if locked == false and (kind == kinds.Item or kind == kinds.Money or kind == kinds.Currency) then
            LootSlot(slot)
        end
    end
    looting = false
end

local function applyFastLoot()
    if MurgleDB.lootVendors.fastLoot ~= true or not lootAPIsAvailable() then
        if lootEvents then
            lootEvents:UnregisterEvent("LOOT_READY")
            lootEvents:UnregisterEvent("LOOT_CLOSED")
        end
        lootGeneration = lootGeneration + 1
        lootAttempted = false
        return
    end
    if not lootEvents then
        lootEvents = CreateFrame("Frame")
        lootEvents:SetScript("OnEvent", lootOnEvent)
    end
    lootEvents:RegisterEvent("LOOT_READY")
    lootEvents:RegisterEvent("LOOT_CLOSED")
end

local function merchantReady(frame)
    return frame == MerchantFrame
        and type(frame.IsShown) == "function"
        and frame:IsShown() == true
        and type(InCombatLockdown) == "function"
        and InCombatLockdown() == false
        and type(IsShiftKeyDown) == "function"
        and IsShiftKeyDown() == false
end

local function repairOnShow(frame)
    if MurgleDB.lootVendors.autoRepair ~= true then
        return
    end
    if
        not merchantReady(frame)
        or type(CanMerchantRepair) ~= "function"
        or CanMerchantRepair() ~= true
        or type(GetRepairAllCost) ~= "function"
        or type(GetMoney) ~= "function"
        or type(RepairAllItems) ~= "function"
    then
        return
    end
    local cost, canRepair = GetRepairAllCost()
    if canRepair ~= true or not moneyValue(cost) or cost == 0 then
        return
    end
    local money = GetMoney()
    if not moneyValue(money) then
        return
    end
    local guildFunds = 0
    if MurgleDB.lootVendors.guildRepair == true then
        if type(CanGuildBankRepair) ~= "function" then
            return
        end
        local allowed = CanGuildBankRepair()
        if allowed == true then
            if type(GetGuildBankWithdrawMoney) ~= "function" or type(GetGuildBankMoney) ~= "function" then
                return
            end
            local limit, bank = GetGuildBankWithdrawMoney(), GetGuildBankMoney()
            if not moneyValue(bank) or (limit ~= -1 and not moneyValue(limit)) then
                return
            end
            guildFunds = limit == -1 and bank or math.min(limit, bank)
        elseif allowed ~= false then
            return
        end
    end
    if guildFunds > 0 and money >= math.max(0, cost - guildFunds) then
        -- Native guild repair covers any remainder with personal funds. Submit
        -- one request only; server-side balances may change after these checks.
        RepairAllItems(true)
    elseif guildFunds == 0 and money >= cost then
        RepairAllItems()
    end
end

local selling = false

local function merchantOnShow(frame)
    if selling then
        return
    end
    repairOnShow(frame)
    if MurgleDB.lootVendors.sellJunk ~= true or not merchantReady(frame) then
        return
    end
    local api = C_Container
    local poor = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor
    if
        not api
        or type(api.GetContainerNumSlots) ~= "function"
        or type(api.GetContainerItemInfo) ~= "function"
        or type(api.UseContainerItem) ~= "function"
        or poor ~= 0
        or not moneyValue(NUM_BAG_SLOTS)
        or NUM_BAG_SLOTS > 5
    then
        return
    end
    -- Only carried bags, only during this merchant opening. Never retry or
    -- accept a confirmation. The native use operation retains normal buyback.
    selling = true
    for bag = 0, NUM_BAG_SLOTS do
        local count = api.GetContainerNumSlots(bag)
        if moneyValue(count) and count <= 100 then
            for slot = count, 1, -1 do
                if MurgleDB.lootVendors.sellJunk ~= true or not merchantReady(frame) then
                    selling = false
                    return
                end
                local item = api.GetContainerItemInfo(bag, slot)
                if
                    type(item) == "table"
                    and item.quality == poor
                    and item.isLocked == false
                    and item.hasNoValue == false
                    and moneyValue(item.itemID)
                    and item.itemID > 0
                    and moneyValue(item.stackCount)
                    and item.stackCount > 0
                then
                    api.UseContainerItem(bag, slot)
                end
            end
        end
    end
    selling = false
end

function LootVendors.ApplyAll()
    applyFastLoot()
    if MurgleDB.lootVendors.autoRepair ~= true and MurgleDB.lootVendors.sellJunk ~= true then
        return
    end
    local frame = MerchantFrame
    if not frame or type(frame.HookScript) ~= "function" or hookedFrames[frame] then
        return
    end
    -- Native OnShow updates repair state before this hook. Enabling mid-visit
    -- does not spend money; the next merchant opening is the action boundary.
    frame:HookScript("OnShow", merchantOnShow)
    hookedFrames[frame] = true
end

function LootVendors.Initialize()
    LootVendors.ApplyAll()
end
