local _, Murgle = ...
local MarkedJunk = {}
Murgle.MarkedJunk = MarkedJunk
local events, activeReview
local generation, selling = 0, false
local POPUP = "MURGLE_SELL_MARKED"

local function integer(n)
    return type(n) == "number" and n >= 0 and n <= 9007199254740991 and n == math.floor(n)
end
local function enabled()
    return MurgleDB.lootVendors.markedJunk == true and type(MurgleDB.lootVendors.markedItems) == "table"
end
local function itemValue(item)
    if type(item) ~= "string" or item == "" then
        return
    end
    if
        not C_Item
        or type(C_Item.GetItemInfo) ~= "function"
        or type(C_Item.IsEquippableItem) ~= "function"
        or C_Item.IsEquippableItem(item) ~= false
    then
        return
    end
    local name, link, quality, _, _, _, _, _, equip, _, price, class, _, binding = C_Item.GetItemInfo(item)
    if
        type(name) ~= "string"
        or type(link) ~= "string"
        or not integer(quality)
        or quality > 2
        or equip ~= ""
        or not integer(price)
        or price == 0
        or binding ~= 0
        or not integer(class)
        or class == 1
        or class == 2
        or class == 4
        or class == 12
    then
        return
    end
    return name, link, price
end
function MarkedJunk.MarkCursor()
    if
        not enabled()
        or type(InCombatLockdown) ~= "function"
        or InCombatLockdown() ~= false
        or type(GetCursorInfo) ~= "function"
    then
        return false
    end
    local kind, id, link = GetCursorInfo()
    if kind ~= "item" or not integer(id) or id == 0 or type(link) ~= "string" or not itemValue(link) then
        return false
    end
    MurgleDB.lootVendors.markedItems[tostring(id)] = true
    activeReview = nil
    return true
end
function MarkedJunk.ClearMarks()
    MurgleDB.lootVendors.markedItems = {}
    activeReview = nil
end
function MarkedJunk.CountMarks()
    local count = 0
    for _, value in pairs(MurgleDB.lootVendors.markedItems or {}) do
        if value == true then
            count = count + 1
        end
    end
    return count
end
local function ready()
    return enabled()
        and type(InCombatLockdown) == "function"
        and InCombatLockdown() == false
        and type(IsShiftKeyDown) == "function"
        and IsShiftKeyDown() == false
        and type(GetCursorInfo) == "function"
        and GetCursorInfo() == nil
        and type(SpellIsTargeting) == "function"
        and SpellIsTargeting() == false
        and MerchantFrame
        and type(MerchantFrame.IsShown) == "function"
        and MerchantFrame:IsShown() == true
        and MerchantFrame.selectedTab == 1
        and type(UnitGUID) == "function"
        and type(UnitGUID("npc")) == "string"
        and C_Container
        and type(C_Container.GetContainerNumSlots) == "function"
        and type(C_Container.GetContainerItemInfo) == "function"
        and type(C_Container.GetContainerItemQuestInfo) == "function"
        and type(C_Container.GetContainerItemPurchaseInfo) == "function"
        and type(C_Container.UseContainerItem) == "function"
        and C_Item
        and type(C_Item.GetItemGUID) == "function"
        and ItemLocation
        and type(ItemLocation.CreateFromBagAndSlot) == "function"
        and integer(NUM_BAG_SLOTS)
        and NUM_BAG_SLOTS <= 5
end
local function candidate(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if
        not info
        or not integer(info.itemID)
        or MurgleDB.lootVendors.markedItems[tostring(info.itemID)] ~= true
        or info.isLocked ~= false
        or info.isBound ~= false
        or info.hasNoValue ~= false
        or not integer(info.stackCount)
        or info.stackCount == 0
    then
        return
    end
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
    if
        not quest
        or quest.isQuestItem ~= false
        or quest.isActive ~= false
        or quest.questID ~= nil
        or C_Container.GetContainerItemPurchaseInfo(bag, slot, false) ~= nil
    then
        return
    end
    local name, link, price = itemValue(info.hyperlink)
    if not name or link ~= info.hyperlink then
        return
    end
    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local guid = location and C_Item.GetItemGUID(location)
    local total = price * info.stackCount
    if type(guid) ~= "string" or guid == "" or not integer(total) then
        return
    end
    return {
        bag = bag,
        slot = slot,
        id = info.itemID,
        link = link,
        guid = guid,
        count = info.stackCount,
        total = total,
        name = name,
    }
end
local function matches(a, b)
    return a
        and b
        and a.id == b.id
        and a.link == b.link
        and a.guid == b.guid
        and a.count == b.count
        and a.total == b.total
end
function MarkedJunk.Review()
    activeReview = nil
    if selling or not ready() then
        return
    end
    local review = { items = {}, total = 0, merchant = MerchantFrame, npc = UnitGUID("npc"), generation = generation }
    for bag = 0, NUM_BAG_SLOTS do
        local count = C_Container.GetContainerNumSlots(bag)
        if not integer(count) or count > 100 then
            return
        end
        for slot = 1, count do
            local item = candidate(bag, slot)
            if item then
                -- Keep this review within the native buyback capacity.
                if #review.items == 12 then
                    activeReview = review
                    return review
                end
                review.items[#review.items + 1] = item
                review.total = review.total + item.total
                if not integer(review.total) then
                    return
                end
            end
        end
    end
    if #review.items == 0 then
        return
    end
    activeReview = review
    return review
end
function MarkedJunk.Sell(review)
    if selling or not review or review ~= activeReview then
        return false
    end
    activeReview = nil
    local function unchanged()
        return ready()
            and MerchantFrame == review.merchant
            and UnitGUID("npc") == review.npc
            and generation == review.generation
    end
    if not unchanged() then
        return false
    end
    selling = true
    for i, item in ipairs(review.items) do
        if not unchanged() then
            selling = false
            return false
        end
        -- Revalidate every remaining stack before each request, not just once.
        for j = i, #review.items do
            local remaining = review.items[j]
            if not matches(remaining, candidate(remaining.bag, remaining.slot)) then
                selling = false
                return false
            end
        end
        C_Container.UseContainerItem(item.bag, item.slot)
    end
    selling = false
    return true
end
function MarkedJunk.RequestSell()
    if not StaticPopupDialogs or type(StaticPopup_Show) ~= "function" or type(GetCoinTextureString) ~= "function" then
        return
    end
    local review = MarkedJunk.Review()
    if not review then
        return
    end
    local lines = {}
    for _, item in ipairs(review.items) do
        lines[#lines + 1] = string.format("%s x%d", item.name, item.count)
    end
    if not StaticPopupDialogs[POPUP] then
        StaticPopupDialogs[POPUP] = {
            text = "%s",
            button1 = Murgle.L.SELL_MARKED,
            button2 = Murgle.L.CANCEL,
            OnAccept = function(_, data)
                MarkedJunk.Sell(data)
            end,
            OnCancel = function(_, data)
                if activeReview == data then
                    activeReview = nil
                end
            end,
            timeout = 0,
            whileDead = false,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    local text = string.format(
        Murgle.L.SELL_MARKED_CONFIRM,
        #review.items,
        GetCoinTextureString(review.total),
        table.concat(lines, "\n")
    )
    StaticPopup_Show(POPUP, text, nil, review)
end
function MarkedJunk.ApplyAll()
    activeReview = nil
    generation = generation + 1
    if not enabled() then
        if events then
            events:UnregisterEvent("MERCHANT_SHOW")
            events:UnregisterEvent("MERCHANT_CLOSED")
        end
        return
    end
    if type(CreateFrame) ~= "function" then
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", function()
            generation = generation + 1
            activeReview = nil
        end)
    end
    events:RegisterEvent("MERCHANT_SHOW")
    events:RegisterEvent("MERCHANT_CLOSED")
end
MarkedJunk.Initialize = MarkedJunk.ApplyAll
