local Helpers = dofile("tests/helpers.lua")

local function fixture(fn)
    local state =
        { money = 10000, count = 0, stock = -1, purchases = {}, timers = {}, hooks = {}, frames = {}, free = 10 }
    local function frame()
        local f = Helpers.newEventFrame()
        f.shown = true
        function f:UnregisterAllEvents()
            self.events = {}
        end
        function f:HookScript(name, callback)
            self.scripts[name] = callback
        end
        function f:IsShown()
            return self.shown
        end
        function f:Hide()
            self.shown = false
            if self.scripts.OnHide then
                self.scripts.OnHide(self)
            end
        end
        function f:Show()
            self.shown = true
        end
        function f:SetShown(value)
            self.shown = value
        end
        function f:SetPoint() end
        function f:SetSize() end
        function f:SetText(text)
            self.text = text
        end
        function f:Enable()
            self.enabled = true
        end
        function f:Disable()
            self.enabled = false
        end
        state.frames[#state.frames + 1] = f
        return f
    end
    local merchant, split = frame(), frame()
    merchant.selectedTab = 1
    split.shown = false
    function split:OpenStackSplitFrame(maximum, owner, _, _, pack)
        self.owner, self.maxStack, self.minSplit, self.split = owner, maximum, pack, pack
        self:Show()
        if state.hooks.OpenStackSplitFrame then
            state.hooks.OpenStackSplitFrame(self, maximum, owner)
        end
    end
    function split:UpdateStackSplitFrame(maximum)
        self.maxStack = maximum
    end
    local button = { showNonrefundablePrompt = false, price = 10 }
    function button:GetID()
        return state.index or 1
    end
    local original = function()
        state.native = (state.native or 0) + 1
    end
    button.SplitStack = original
    local M = { L = {} }
    local function event(name)
        for _, f in ipairs(state.frames) do
            if f.events[name] and f.scripts.OnEvent then
                f.scripts.OnEvent(f, name)
            end
        end
    end
    state.event = event
    function state:open(alt)
        self.alt = alt
        split:OpenStackSplitFrame(20, button, "BOTTOMLEFT", "TOPLEFT", 1)
        assert(self.hooks.MerchantItemButton_BuyMultipleStacks)(button)
    end
    function state:okay(quantity)
        split.split = quantity
        split:Hide()
        split.owner.SplitStack(split.owner, split.split)
    end
    function state:flush()
        local pending = self.timers
        self.timers = {}
        for _, callback in ipairs(pending) do
            callback()
        end
    end
    function state:ack(quantity)
        self.count = self.count + quantity
        self.money = self.money - quantity / (self.pack or 1) * (self.price or 10)
        if self.stock >= 0 then
            self.stock = self.stock - quantity
        end
        event("BAG_UPDATE_DELAYED")
        event("PLAYER_MONEY")
        event("MERCHANT_UPDATE")
    end
    Helpers.withGlobals({
        MerchantFrame = merchant,
        StackSplitFrame = split,
        MerchantItem1ItemButton = button,
        MERCHANT_HIGH_PRICE_COST = 1500000,
        NUM_BAG_SLOTS = 4,
        MurgleDB = { lootVendors = { bulkBuy = false, restock = false, restockTargets = {} } },
        CreateFrame = function()
            return frame()
        end,
        InCombatLockdown = function()
            return state.combat == true
        end,
        IsAltKeyDown = function()
            return state.alt == true
        end,
        IsShiftKeyDown = function()
            return true
        end,
        C_Timer = {
            After = function(_, callback)
                state.timers[#state.timers + 1] = callback
            end,
        },
        C_Container = {
            GetContainerNumFreeSlots = function(bag)
                return bag == 0 and state.free or 0, 0
            end,
        },
        C_Item = {
            GetItemCount = function()
                return state.count
            end,
        },
        C_MerchantFrame = {
            IsMerchantItemRefundable = function()
                return state.refundable ~= false
            end,
            GetItemInfo = function()
                return {
                    price = state.price or 10,
                    stackCount = state.pack or 1,
                    numAvailable = state.stock,
                    isPurchasable = true,
                    hasExtendedCost = state.extended == true,
                    currencyID = state.currency,
                }
            end,
        },
        GetMerchantItemID = function()
            return state.itemID or 42
        end,
        GetMerchantItemLink = function()
            return "item:" .. (state.itemID or 42)
        end,
        GetMerchantItemMaxStack = function()
            return 20
        end,
        GetMerchantNumItems = function()
            return 1
        end,
        GetMoney = function()
            return state.money
        end,
        GetMoneyString = function(amount)
            return tostring(amount)
        end,
        BuyMerchantItem = function(index, quantity)
            state.purchases[#state.purchases + 1] = { index, quantity }
            if state.duringBuy then
                state.duringBuy(quantity)
            end
        end,
        MerchantItemButton_BuyMultipleStacks = function() end,
        hooksecurefunc = function(name, callback, methodCallback)
            if type(name) == "table" then
                state.hooks[callback] = methodCallback
            else
                state.hooks[name] = callback
            end
        end,
        StaticPopup_ShowCustomGenericConfirmation = function(data)
            state.popup = data
        end,
    }, function()
        Helpers.loadAddonFile("Modules/Commerce.lua", M)
        M.Commerce.Initialize()
        fn(M, state, button, split, original, merchant)
    end)
end

local function enable(M, restock)
    MurgleDB.lootVendors.bulkBuy = true
    MurgleDB.lootVendors.restock = restock == true
    M.Commerce.ApplyAll()
end

test("commerce disabled is inert and opening merchant never spends", function()
    fixture(function(M, s)
        eq(next(s.hooks), nil)
        enable(M)
        s.event("MERCHANT_SHOW")
        eq(#s.purchases, 0)
    end)
end)

test("commerce native hide before callback buys bounded event-confirmed stacks", function()
    fixture(function(M, s, button, split, original)
        enable(M)
        s:open()
        eq(split.maxStack, 200)
        s:okay(45)
        eq(#s.purchases, 1)
        eq(s.purchases[1][2], 20)
        s:flush()
        eq(button.SplitStack, original)
        s.event("MERCHANT_UPDATE")
        eq(#s.purchases, 1)
        s.count = 20
        s.event("BAG_UPDATE_DELAYED")
        eq(#s.purchases, 1, "bag update alone must not confirm money")
        s.money = 9800
        s.event("PLAYER_MONEY")
        eq(#s.purchases, 2)
        s:ack(20)
        eq(#s.purchases, 3)
        eq(s.purchases[3][2], 5)
        s:ack(5)
        eq(#s.purchases, 3)
    end)
end)

test("commerce restores cancel disable and preserves foreign callbacks", function()
    fixture(function(M, s, button, split, original)
        enable(M)
        s:open()
        split:Hide()
        s:flush()
        eq(button.SplitStack, original)
        s:open()
        local foreign = function() end
        button.SplitStack = foreign
        split:Hide()
        s:flush()
        eq(button.SplitStack, foreign)
        button.SplitStack = original
        s:open()
        split:Hide()
        MurgleDB.lootVendors.bulkBuy = false
        M.Commerce.ApplyAll()
        eq(button.SplitStack, original)
        s:flush()
        eq(button.SplitStack, original)
    end)
end)

test("commerce old cleanup cannot restore over new dialog", function()
    fixture(function(M, s, button, split, original)
        enable(M)
        s:open()
        split:Hide()
        s:open()
        local current = button.SplitStack
        s:flush()
        eq(button.SplitStack, current)
        split:Hide()
        s:flush()
        eq(button.SplitStack, original)
    end)
end)

test("commerce rejects stale selection partial packs and protected purchases", function()
    fixture(function(M, s, button, split, original)
        enable(M)
        s:open()
        s.itemID = 43
        s:okay(40)
        s:flush()
        eq(#s.purchases, 0)
        s.itemID = 42
        s.pack = 5
        s:open()
        s:okay(22)
        s:flush()
        eq(#s.purchases, 0)
        s.extended = true
        s:open()
        eq(button.SplitStack, original)
        split:Hide()
        s.extended = false
        button.showNonrefundablePrompt = true
        s:open()
        eq(button.SplitStack, original)
    end)
end)

test("commerce aborts rejection partial receipt combat close and disabled batches", function()
    fixture(function(M, s, _, _, _, merchant)
        enable(M)
        s:open()
        s:okay(40)
        s:flush()
        s.count = 3
        s.event("BAG_UPDATE_DELAYED")
        s:ack(17)
        eq(#s.purchases, 1)
        s:open()
        s:okay(40)
        s:flush()
        s.event("UI_ERROR_MESSAGE")
        s:ack(20)
        eq(#s.purchases, 2)
        s:open()
        s:okay(40)
        s:flush()
        s.combat = true
        s.event("PLAYER_REGEN_DISABLED")
        s:ack(20)
        eq(#s.purchases, 3)
        s.combat = false
        s:open()
        s:okay(40)
        s:flush()
        merchant.shown = false
        s.event("MERCHANT_CLOSED")
        s:ack(20)
        eq(#s.purchases, 4)
    end)
end)

test("commerce finite stock waits for stock acknowledgement and reentrancy is bounded", function()
    fixture(function(M, s)
        enable(M)
        s.stock = 100
        s:open()
        s:okay(40)
        s:flush()
        s.count = 20
        s.money = 9800
        s.event("BAG_UPDATE_DELAYED")
        s.event("PLAYER_MONEY")
        eq(#s.purchases, 1)
        s.stock = 80
        s.event("MERCHANT_UPDATE")
        eq(#s.purchases, 2)
        s:ack(20)
        s.duringBuy = function(quantity)
            s:ack(quantity)
        end
        s:open()
        s:okay(40)
        s:flush()
        eq(#s.purchases, 4)
    end)
end)

test("commerce explicit restock targets save without buying and require cost review", function()
    fixture(function(M, s, _, split)
        enable(M, true)
        s:open(true)
        s:okay(50)
        s:flush()
        eq(MurgleDB.lootVendors.restockTargets[42], 50)
        eq(#s.purchases, 0)
        s.alt = false
        local restock = s.frames[#s.frames]
        assert(restock.scripts.OnClick)(restock)
        eq(#s.purchases, 0)
        assert(s.popup and s.popup.text:find("500", 1, true))
        s.popup.callback()
        eq(#s.purchases, 1)
        s:ack(20)
        s:ack(20)
        s:ack(10)
        eq(s.count, 50)
        M.Commerce.ClearRestockTargets()
        eq(next(MurgleDB.lootVendors.restockTargets), nil)
        eq(split.owner ~= nil, true)
    end)
end)

test("commerce disabling an open dialog closes extended quantities and cancels in-flight work", function()
    fixture(function(M, s, button, split, original)
        enable(M)
        s:open()
        MurgleDB.lootVendors.bulkBuy = false
        M.Commerce.ApplyAll()
        eq(split:IsShown(), false)
        eq(button.SplitStack, original)
        enable(M)
        s:open()
        s:okay(40)
        s:flush()
        MurgleDB.lootVendors.bulkBuy = false
        M.Commerce.ApplyAll()
        s:ack(20)
        eq(#s.purchases, 1)
    end)
end)

test("commerce empty generic bag space money stock and pack bounds fail closed", function()
    fixture(function(M, s, button, split, original)
        enable(M)
        s.free = 0
        s:open()
        eq(button.SplitStack, original)
        split:Hide()
        s.free = 10
        s.money = 99
        s.pack = 5
        s:open()
        eq(split.maxStack, 45)
        split:Hide()
        s:flush()
        s.money = 10000
        s.stock = 13
        s:open()
        eq(split.maxStack, 10)
        s:okay(15)
        s:flush()
        eq(#s.purchases, 0)
        s.currency = 1
        s:open()
        eq(button.SplitStack, original)
    end)
end)

test("commerce opening another native quantity dialog restores previous owner immediately", function()
    fixture(function(M, s, button, split, original)
        enable(M)
        s:open()
        local other = { SplitStack = function() end }
        split:OpenStackSplitFrame(5, other, "BOTTOMLEFT", "TOPLEFT", 1)
        eq(button.SplitStack, original)
        split:Hide()
        s:flush()
        eq(#s.purchases, 0)
    end)
end)

test("commerce restock review cannot spend after close reset disable or target changes", function()
    fixture(function(M, s)
        enable(M, true)
        MurgleDB.lootVendors.restockTargets[42] = 40
        local button = s.frames[#s.frames]
        button.scripts.OnClick(button)
        local old = s.popup.callback
        s.event("MERCHANT_CLOSED")
        s.event("MERCHANT_SHOW")
        old()
        eq(#s.purchases, 0)
        button.scripts.OnClick(button)
        old = s.popup.callback
        MurgleDB.lootVendors.restock = false
        M.Commerce.ApplyAll()
        MurgleDB.lootVendors.restock = true
        M.Commerce.ApplyAll()
        old()
        eq(#s.purchases, 0)
        button.scripts.OnClick(button)
        old = s.popup.callback
        MurgleDB.lootVendors.restockTargets[42] = 50
        old()
        eq(#s.purchases, 0)
        button.scripts.OnClick(button)
        old = s.popup.callback
        M.Commerce.ClearRestockTargets()
        old()
        eq(#s.purchases, 0)
    end)
end)

test("commerce restock rounds missing quantities down to whole vendor packs", function()
    fixture(function(M, s)
        enable(M, true)
        s.pack, s.count = 5, 3
        MurgleDB.lootVendors.restockTargets[42] = 50
        local button = s.frames[#s.frames]
        button.scripts.OnClick(button)
        s.popup.callback()
        s:ack(20)
        s:ack(20)
        s:ack(5)
        eq(s.count, 48)
        eq(#s.purchases, 3)
    end)
end)

test("commerce ordinary nonrefundable gold consumables follow native no-popup path", function()
    fixture(function(M, s, button)
        enable(M)
        s.refundable = false
        button.showNonrefundablePrompt = true
        s:open()
        s:okay(40)
        s:flush()
        eq(#s.purchases, 1)
        eq(s.popup, nil, "bulk quantities do not accept or manufacture a native purchase prompt")
        s:ack(20)
        s:ack(20)
        eq(#s.purchases, 2)
    end)
end)

test("commerce restock stops when a later queued item's count changes", function()
    fixture(function(M, s)
        local counts = { [42] = 0, [43] = 0 }
        C_Item.GetItemCount = function(id)
            return counts[id]
        end
        GetMerchantItemID = function(index)
            return 41 + index
        end
        GetMerchantItemLink = function(index)
            return "item:" .. (41 + index)
        end
        GetMerchantNumItems = function()
            return 2
        end
        enable(M, true)
        MurgleDB.lootVendors.restockTargets[42] = 20
        MurgleDB.lootVendors.restockTargets[43] = 20
        local button = s.frames[#s.frames]
        button.scripts.OnClick(button)
        s.popup.callback()
        eq(#s.purchases, 1)
        eq(s.purchases[1][1], 1)
        -- The owner acquires B while the server acknowledges purchase A.
        -- The reviewed B quantity is now stale and must never be submitted.
        counts[43] = 15
        counts[42] = 20
        s.money = s.money - 200
        s.event("BAG_UPDATE_DELAYED")
        s.event("PLAYER_MONEY")
        eq(#s.purchases, 1, "restock must stop before exceeding the later item's reviewed target")
        eq(counts[43], 15)
    end)
end)
