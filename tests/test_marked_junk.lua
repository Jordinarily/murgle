local H = dofile("tests/helpers.lua")
local function setup(fn)
    local slots = {
        [1] = {
            itemID = 10,
            hyperlink = "item:10",
            quality = 1,
            isLocked = false,
            hasNoValue = false,
            isBound = false,
            stackCount = 3,
            guid = "A",
        },
        [2] = {
            itemID = 20,
            hyperlink = "item:20",
            quality = 1,
            isLocked = false,
            hasNoValue = false,
            isBound = false,
            stackCount = 2,
            guid = "B",
        },
    }
    local sales, frames, combat, shift, cursor, quest, equip, price, onSale =
        {}, {}, false, false, nil, false, false, 100
    local merchant = {
        IsShown = function()
            return true
        end,
        selectedTab = 1,
    }
    H.withGlobals({
        MurgleDB = { lootVendors = { markedJunk = false, markedItems = {} } },
        MerchantFrame = merchant,
        NUM_BAG_SLOTS = 0,
        InCombatLockdown = function()
            return combat
        end,
        IsShiftKeyDown = function()
            return shift
        end,
        GetCursorInfo = function()
            if cursor then
                return "item", cursor, "item:" .. cursor
            end
        end,
        SpellIsTargeting = function()
            return false
        end,
        UnitGUID = function()
            return "Merchant-A"
        end,
        C_Item = {
            GetItemInfo = function(link)
                return "Item",
                    tostring(link):find("item:") and link or "item:" .. link,
                    1,
                    1,
                    1,
                    "",
                    "",
                    20,
                    "",
                    1,
                    price,
                    7,
                    0,
                    0
            end,
            IsEquippableItem = function()
                return equip
            end,
            GetItemGUID = function(loc)
                return slots[loc.slot] and slots[loc.slot].guid
            end,
        },
        C_Container = {
            GetContainerNumSlots = function()
                return 2
            end,
            GetContainerItemInfo = function(_, s)
                return slots[s]
            end,
            GetContainerItemQuestInfo = function()
                return { isQuestItem = quest, isActive = false }
            end,
            GetContainerItemPurchaseInfo = function() end,
            UseContainerItem = function(b, s)
                sales[#sales + 1] = s
                slots[s] = nil
                if onSale then
                    onSale()
                end
            end,
        },
        ItemLocation = {
            CreateFromBagAndSlot = function(_, b, s)
                return { bag = b, slot = s }
            end,
        },
        StaticPopupDialogs = {},
        StaticPopup_Show = function() end,
        GetCoinTextureString = function(n)
            return tostring(n)
        end,
        CreateFrame = function()
            local f = H.newEventFrame()
            f.SetSize = function() end
            f.SetPoint = function() end
            f.SetText = function() end
            f.Show = function(self)
                self.shown = true
            end
            f.Hide = function(self)
                self.shown = false
            end
            frames[#frames + 1] = f
            return f
        end,
    }, function()
        local M = {
            L = { SELL_MARKED = "Sell marked", SELL_MARKED_CONFIRM = "Sell %d stacks for %s?\n%s", CANCEL = "Cancel" },
        }
        H.loadAddonFile("Modules/MarkedJunk.lua", M)
        fn(M.MarkedJunk, slots, sales, frames, function(t)
            if t.combat ~= nil then
                combat = t.combat
            end
            if t.shift ~= nil then
                shift = t.shift
            end
            cursor = t.cursor
            quest = t.quest == true
            equip = t.equip == true
            price = t.price or 100
            onSale = t.onSale
        end)
    end)
end

test("marked junk startup is inert and cursor marking is explicit and conservative", function()
    setup(function(J, slots, sales, frames, state)
        J.ApplyAll()
        eq(#frames, 0)
        eq(J.MarkCursor(), false)
        MurgleDB.lootVendors.markedJunk = true
        state({ cursor = 10 })
        eq(J.MarkCursor(), true)
        eq(MurgleDB.lootVendors.markedItems["10"], true)
        state({ cursor = 20, equip = true })
        eq(J.MarkCursor(), false)
        J.ClearMarks()
        eq(next(MurgleDB.lootVendors.markedItems), nil)
        eq(#sales, 0)
    end)
end)
test("marked junk review totals marked stacks and acceptance revalidates exact identity", function()
    setup(function(J, slots, sales, frames, state)
        MurgleDB.lootVendors.markedJunk = true
        J.ApplyAll()
        state({ cursor = 10 })
        J.MarkCursor()
        state({})
        local review = J.Review()
        eq(review.total, 300)
        eq(#review.items, 1)
        slots[1].guid = "replacement"
        eq(J.Sell(review), false)
        eq(#sales, 0)
        review = J.Review()
        eq(J.Sell(review), true)
        eq(#sales, 1)
        eq(sales[1], 1)
    end)
end)
test("marked junk refuses quest items combat modifiers and held cursor", function()
    setup(function(J, slots, sales, frames, state)
        MurgleDB.lootVendors.markedJunk = true
        MurgleDB.lootVendors.markedItems["10"] = true
        J.ApplyAll()
        for _, t in ipairs({ { quest = true }, { combat = true }, { shift = true }, { cursor = 10 } }) do
            state(t)
            eq(J.Review(), nil)
        end
        state({ combat = false, shift = false })
        local r = J.Review()
        assert(r)
        state({ combat = true })
        eq(J.Sell(r), false)
        eq(#sales, 0)
    end)
end)
test("marked junk stops when a later item changes or merchant closes during sale", function()
    setup(function(J, slots, sales, frames, state)
        MurgleDB.lootVendors.markedJunk = true
        MurgleDB.lootVendors.markedItems = { ["10"] = true, ["20"] = true }
        J.ApplyAll()
        local r = J.Review()
        eq(#r.items, 2)
        state({
            onSale = function()
                slots[2].guid = "changed"
            end,
        })
        eq(J.Sell(r), false)
        eq(#sales, 1)
        MurgleDB.lootVendors.markedJunk = false
        J.ApplyAll()
        eq(next(frames[1].events), nil)
    end)
end)

test("marked junk invalidates reviews on merchant closure and never retries an accepted review", function()
    setup(function(J, slots, sales, frames, state)
        MurgleDB.lootVendors.markedJunk = true
        MurgleDB.lootVendors.markedItems["10"] = true
        J.ApplyAll()
        local r = J.Review()
        assert(r)
        frames[1].scripts.OnEvent(frames[1], "MERCHANT_CLOSED")
        eq(J.Sell(r), false)
        eq(#sales, 0)
        r = J.Review()
        eq(J.Sell(r), true)
        eq(J.Sell(r), false)
        eq(#sales, 1)
    end)
end)
test("marked junk skips refundable bound valuable and quest items", function()
    setup(function(J, slots, sales, frames, state)
        MurgleDB.lootVendors.markedJunk = true
        MurgleDB.lootVendors.markedItems["10"] = true
        J.ApplyAll()
        C_Container.GetContainerItemPurchaseInfo = function()
            return {}
        end
        eq(J.Review(), nil)
        C_Container.GetContainerItemPurchaseInfo = function() end
        local original = C_Item.GetItemInfo
        C_Item.GetItemInfo = function(link)
            local t = { original(link) }
            t[14] = 1
            return unpack(t)
        end
        eq(J.Review(), nil)
        C_Item.GetItemInfo = function(link)
            local t = { original(link) }
            t[3] = 3
            return unpack(t)
        end
        eq(J.Review(), nil)
        C_Item.GetItemInfo = original
        state({ quest = true })
        eq(J.Review(), nil)
    end)
end)

test("marked junk reviews the first twelve stacks when more are eligible", function()
    setup(function(J, slots, sales, frames, state)
        MurgleDB.lootVendors.markedJunk = true
        MurgleDB.lootVendors.markedItems["10"] = true
        J.ApplyAll()
        C_Container.GetContainerNumSlots = function()
            return 13
        end
        for i = 1, 13 do
            slots[i] = {
                itemID = 10,
                hyperlink = "item:10",
                isLocked = false,
                hasNoValue = false,
                isBound = false,
                stackCount = 1,
                guid = "stack" .. i,
            }
        end
        local r = J.Review()
        assert(r)
        eq(#r.items, 12)
        eq(r.total, 1200)
        eq(J.Sell(r), true)
        eq(#sales, 12)
        assert(slots[13])
    end)
end)

test("marked junk native popup reuse cannot cancel the new review", function()
    setup(function(J, slots, sales, frames, state)
        MurgleDB.lootVendors.markedJunk = true
        MurgleDB.lootVendors.markedItems["10"] = true
        J.ApplyAll()
        local shown, which
        StaticPopup_Show = function(key, text, _, data)
            if shown then
                StaticPopupDialogs[key].OnCancel(nil, shown)
            end
            shown, which = data, key
        end
        J.RequestSell()
        J.RequestSell()
        assert(shown)
        StaticPopupDialogs[which].OnAccept(nil, shown)
        eq(#sales, 1)
    end)
end)
test("marked junk stops a batch when the merchant closes during a request", function()
    setup(function(J, slots, sales, frames, state)
        MurgleDB.lootVendors.markedJunk = true
        MurgleDB.lootVendors.markedItems = { ["10"] = true, ["20"] = true }
        J.ApplyAll()
        local r = J.Review()
        state({
            onSale = function()
                frames[1].scripts.OnEvent(frames[1], "MERCHANT_CLOSED")
            end,
        })
        eq(J.Sell(r), false)
        eq(#sales, 1)
    end)
end)

test("marked junk rejects missing item links bound instances and unavailable safety APIs", function()
    setup(function(J, slots, sales, frames, state)
        MurgleDB.lootVendors.markedJunk = true
        MurgleDB.lootVendors.markedItems["10"] = true
        J.ApplyAll()
        local info = C_Item.IsEquippableItem
        C_Item.IsEquippableItem = function(link)
            assert(type(link) == "string")
            return info(link)
        end
        slots[1].hyperlink = nil
        eq(J.Review(), nil)
        slots[1].hyperlink = "item:10"
        slots[1].isBound = true
        eq(J.Review(), nil)
        C_Item.GetItemGUID = nil
        eq(J.Review(), nil)
        eq(#sales, 0)
    end)
end)
