local _, Murgle = ...
local Commerce = {}
Murgle.Commerce = Commerce

local events, restockButton, dialog, batch, pendingReview
local hooked = false
local advancing = false
local MAX_QUANTITY = 1000
local MAX_REQUESTS = 100

local function integer(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

local function settings()
    return MurgleDB and MurgleDB.lootVendors
end

local function enabled(key)
    local db = settings()
    return db and db[key] == true
end

local function allowed(key)
    return enabled(key) and InCombatLockdown() == false and MerchantFrame:IsShown() and MerchantFrame.selectedTab == 1
end

local function restore(session)
    if not session then
        return
    end
    if session.owner.SplitStack == session.wrapper then
        session.owner.SplitStack = session.original
    end
    if dialog == session then
        dialog = nil
    end
end

local function cancelDialog()
    local session = dialog
    local hide = session
        and StackSplitFrame.owner == session.owner
        and StackSplitFrame:IsShown()
        and session.owner.SplitStack == session.wrapper
    restore(session)
    if hide then
        StackSplitFrame:Hide()
    end
end

local function stop()
    batch = nil
    pendingReview = nil
end

local function item(index, owner)
    local info = C_MerchantFrame.GetItemInfo(index)
    local id = GetMerchantItemID(index)
    local link = GetMerchantItemLink(index)
    local limit = GetMerchantItemMaxStack(index)
    -- The native nonrefundable branch buys ordinary gold below the high-price
    -- threshold directly. Its flag alone is not evidence of an actual prompt;
    -- extended/currency/high-price offers are excluded below instead.
    local refundable = C_MerchantFrame.IsMerchantItemRefundable(index)
    if
        not info
        or not integer(id)
        or id == 0
        or type(link) ~= "string"
        or not integer(info.price)
        or info.price == 0
        or not integer(MERCHANT_HIGH_PRICE_COST)
        or info.price >= MERCHANT_HIGH_PRICE_COST
        or not integer(info.stackCount)
        or info.stackCount == 0
        or not integer(limit)
        or limit < info.stackCount
        or info.isPurchasable ~= true
        or info.hasExtendedCost ~= false
        or info.currencyID ~= nil
        or not (info.numAvailable == -1 or integer(info.numAvailable))
        or type(refundable) ~= "boolean"
        or (owner and (owner.extendedCost or owner.showNonrefundablePrompt ~= not refundable))
    then
        return
    end
    limit = math.floor(limit / info.stackCount) * info.stackCount
    return {
        index = index,
        id = id,
        link = link,
        price = info.price,
        pack = info.stackCount,
        limit = limit,
        stock = info.numAvailable,
    }
end

local function same(a, b)
    return a
        and b
        and a.id == b.id
        and a.link == b.link
        and a.price == b.price
        and a.pack == b.pack
        and a.limit == b.limit
end

local function carried(id)
    local count = C_Item.GetItemCount(id, false, false, false)
    return integer(count) and count or nil
end

local function capacity(product)
    -- Count generic empty carried-bag slots only. Never guess specialized bag
    -- eligibility, partial-stack capacity, bank contents or unique-item limits.
    local slots = 0
    for bag = 0, NUM_BAG_SLOTS do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if not integer(free) then
            return 0
        end
        if family == 0 then
            slots = slots + free
        end
    end
    return slots * product.limit
end

local function maximum(product)
    local money = GetMoney()
    if not integer(money) then
        return 0
    end
    local max = math.min(MAX_QUANTITY, capacity(product), math.floor(money / product.price) * product.pack)
    if product.stock >= 0 then
        max = math.min(max, product.stock)
    end
    return math.floor(max / product.pack) * product.pack
end

local function advance()
    if advancing or not batch then
        return
    end
    advancing = true
    local sent = 0
    while batch do
        local work = batch
        if not allowed(work.feature) then
            stop()
            break
        end
        local entry = work.entries[work.position]
        if not entry then
            stop()
            break
        end
        local current = item(entry.product.index)
        if not same(entry.product, current) then
            stop()
            break
        end
        if work.pending then
            local pending = work.pending
            local count, money = carried(current.id), GetMoney()
            if not count or not integer(money) then
                stop()
                break
            end
            local gained, spent = count - pending.count, pending.money - money
            local expectedCost = pending.quantity / current.pack * current.price
            local stockChanged = current.stock ~= pending.stock
            if
                gained < 0
                or gained > pending.quantity
                or (gained > 0 and gained < pending.quantity)
                or spent < 0
                or spent > expectedCost
                or (spent > 0 and spent < expectedCost)
                or (pending.stock >= 0 and stockChanged and current.stock ~= pending.stock - pending.quantity)
            then
                stop()
                break
            end
            if
                gained ~= pending.quantity
                or spent ~= expectedCost
                or (pending.stock >= 0 and current.stock ~= pending.stock - pending.quantity)
            then
                break
            end
            entry.remaining = entry.remaining - pending.quantity
            entry.expectedCount = count
            work.pending = nil
            if entry.remaining == 0 then
                work.position = work.position + 1
            end
        else
            local count = carried(current.id)
            local quantity = math.min(entry.remaining, current.limit)
            if
                not count
                or (work.feature == "restock" and count ~= entry.expectedCount)
                or quantity > maximum(current)
                or quantity % current.pack ~= 0
                or sent >= MAX_REQUESTS
                or work.requests >= MAX_REQUESTS
            then
                stop()
                break
            end
            -- Set the receipt snapshot before calling the API: native events may
            -- fire synchronously. Reentrant events only observe this snapshot.
            work.pending = { quantity = quantity, count = count, money = GetMoney(), stock = current.stock }
            work.requests = work.requests + 1
            sent = sent + 1
            BuyMerchantItem(current.index, quantity)
        end
    end
    advancing = false
end

local function begin(entries, feature)
    stop()
    if not allowed(feature) then
        return
    end
    batch = { entries = entries, position = 1, requests = 0, feature = feature }
    advance()
end

local function extend(owner)
    stop()
    restore(dialog)
    local target = enabled("restock") and IsAltKeyDown() == true and IsShiftKeyDown() == true
    local feature = target and "restock" or "bulkBuy"
    if not allowed(feature) or not StackSplitFrame:IsShown() or StackSplitFrame.owner ~= owner then
        return
    end
    local product = item(owner:GetID(), owner)
    if not product or type(owner.SplitStack) ~= "function" then
        return
    end
    local max = target and MAX_QUANTITY or maximum(product)
    max = math.floor(max / product.pack) * product.pack
    if max < product.pack then
        return
    end
    local session = { owner = owner, original = owner.SplitStack, product = product, feature = feature }
    session.wrapper = function(button, quantity)
        if
            session.used
            or dialog ~= session
            or button ~= owner
            or not session.closed
            or not allowed(feature)
            or StackSplitFrame.owner ~= owner
            or owner:GetID() ~= product.index
            or not same(product, item(product.index, owner))
            or not integer(quantity)
            or quantity == 0
            or quantity > max
            or quantity % product.pack ~= 0
        then
            restore(session)
            return
        end
        session.used = true
        restore(session)
        if target then
            settings().restockTargets[product.id] = quantity
        else
            begin({ { product = product, remaining = quantity } }, feature)
        end
    end
    dialog = session
    owner.SplitStack = session.wrapper
    StackSplitFrame:UpdateStackSplitFrame(max)
end

local function reviewRestock()
    stop()
    if not allowed("restock") then
        return
    end
    local entries, total, lines, seen = {}, 0, {}, {}
    local count = GetMerchantNumItems()
    if not integer(count) or count > 1000 then
        return
    end
    for index = 1, count do
        local product = item(index)
        if product then
            local target = settings().restockTargets[product.id]
            local count = carried(product.id)
            if seen[product.id] then
                -- Duplicate offers make the intended stock/price ambiguous.
                return
            end
            seen[product.id] = true
            if integer(target) and target > 0 and target <= MAX_QUANTITY and count then
                local quantity = math.floor(math.max(0, target - count) / product.pack) * product.pack
                if quantity > 0 then
                    if quantity > maximum(product) then
                        return
                    end
                    local cost = quantity / product.pack * product.price
                    total = total + cost
                    entries[#entries + 1] = {
                        product = product,
                        remaining = quantity,
                        count = count,
                        expectedCount = count,
                        target = target,
                    }
                    lines[#lines + 1] = product.link .. " x" .. quantity
                end
            end
        end
    end
    if #entries == 0 or total > GetMoney() then
        return
    end
    local review = { entries = entries }
    pendingReview = review
    local text = (Murgle.L.COMMERCE_RESTOCK_REVIEW or "Restock these items for %s?"):format(GetMoneyString(total))
        .. "\n\n"
        .. table.concat(lines, "\n")
    StaticPopup_ShowCustomGenericConfirmation({
        text = text,
        callback = function()
            if pendingReview ~= review or review.entries ~= entries or not allowed("restock") then
                return
            end
            review.entries = nil
            local money = GetMoney()
            if not integer(money) or money < total then
                return
            end
            for _, entry in ipairs(entries) do
                if
                    not same(entry.product, item(entry.product.index))
                    or carried(entry.product.id) ~= entry.count
                    or settings().restockTargets[entry.product.id] ~= entry.target
                then
                    return
                end
            end
            begin(entries, "restock")
        end,
    })
end

local function available()
    return type(CreateFrame) == "function"
        and type(hooksecurefunc) == "function"
        and type(InCombatLockdown) == "function"
        and type(GetMoney) == "function"
        and type(IsAltKeyDown) == "function"
        and type(IsShiftKeyDown) == "function"
        and type(GetMerchantItemID) == "function"
        and type(GetMerchantItemLink) == "function"
        and type(GetMerchantItemMaxStack) == "function"
        and type(GetMerchantNumItems) == "function"
        and type(MerchantItemButton_BuyMultipleStacks) == "function"
        and type(BuyMerchantItem) == "function"
        and type(GetMoneyString) == "function"
        and type(StaticPopup_ShowCustomGenericConfirmation) == "function"
        and C_Timer
        and type(C_Timer.After) == "function"
        and C_Item
        and type(C_Item.GetItemCount) == "function"
        and C_Container
        and type(C_Container.GetContainerNumFreeSlots) == "function"
        and C_MerchantFrame
        and type(C_MerchantFrame.GetItemInfo) == "function"
        and type(C_MerchantFrame.IsMerchantItemRefundable) == "function"
        and integer(NUM_BAG_SLOTS)
        and MerchantFrame
        and StackSplitFrame
        and type(StackSplitFrame.HookScript) == "function"
        and type(StackSplitFrame.UpdateStackSplitFrame) == "function"
end

function Commerce.ClearRestockTargets()
    stop()
    cancelDialog()
    if settings() then
        settings().restockTargets = {}
    end
end

function Commerce.ApplyAll()
    pendingReview = nil
    if not available() or (not enabled("bulkBuy") and not enabled("restock")) then
        stop()
        cancelDialog()
        if events then
            events:UnregisterAllEvents()
        end
        if restockButton then
            restockButton:Hide()
        end
        return
    end
    settings().restockTargets = type(settings().restockTargets) == "table" and settings().restockTargets or {}
    if not hooked then
        hooksecurefunc("MerchantItemButton_BuyMultipleStacks", extend)
        hooksecurefunc(StackSplitFrame, "OpenStackSplitFrame", function()
            stop()
            restore(dialog)
        end)
        StackSplitFrame:HookScript("OnHide", function()
            local session = dialog
            if session then
                session.closed = true
                -- Native OK hides first, then calls owner.SplitStack. One-shot
                -- cleanup preserves that call while cancel still restores next
                -- frame. This timer never purchases or advances a batch.
                C_Timer.After(0, function()
                    if dialog == session then
                        restore(session)
                    end
                end)
            end
        end)
        hooked = true
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", function(_, event)
            if event == "MERCHANT_CLOSED" or event == "PLAYER_REGEN_DISABLED" or event == "UI_ERROR_MESSAGE" then
                stop()
                cancelDialog()
            elseif event ~= "MERCHANT_SHOW" then
                advance()
            end
        end)
        restockButton = CreateFrame("Button", "MurgleRestockButton", MerchantFrame, "UIPanelButtonTemplate")
        restockButton:SetSize(88, 22)
        -- Native money/currency insets occupy the bottom 27 pixels. Keep this
        -- in the right footer above money, away from the left repair buttons.
        restockButton:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT", -8, 40)
        restockButton:SetText(Murgle.L.COMMERCE_RESTOCK or "Restock")
        restockButton:SetScript("OnClick", reviewRestock)
    end
    for _, event in ipairs({
        "MERCHANT_SHOW",
        "MERCHANT_CLOSED",
        "MERCHANT_UPDATE",
        "BAG_UPDATE_DELAYED",
        "PLAYER_MONEY",
        "PLAYER_REGEN_DISABLED",
        "UI_ERROR_MESSAGE",
    }) do
        events:RegisterEvent(event)
    end
    if batch and not enabled(batch.feature) then
        stop()
    end
    if dialog and not enabled(dialog.feature) then
        cancelDialog()
    end
    restockButton:SetShown(enabled("restock"))
end

function Commerce.Initialize()
    Commerce.ApplyAll()
end
