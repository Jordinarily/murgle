local H = dofile("tests/helpers.lua")
local function setup(fn)
    local callback, calls = nil, 0
    local lines = {}
    local tip = {
        GetItem = function()
            return "Item", "item:10:variant"
        end,
        NumLines = function()
            return #lines
        end,
        GetName = function()
            return "TestDetailsTip"
        end,
    }
    function tip:AddLine(text)
        lines[#lines + 1] = text
        _G["TestDetailsTipTextLeft" .. #lines] = {
            GetText = function()
                return text
            end,
        }
    end
    H.withGlobals({
        MurgleDB = { tooltip = { itemDetails = false } },
        GameTooltip = tip,
        TooltipDataProcessor = {
            AddTooltipPostCall = function(_, cb)
                callback = cb
                calls = calls + 1
            end,
        },
        Enum = { TooltipDataType = { Item = 0 } },
        C_Item = {
            GetItemInfo = function()
                return "Item", "item:10", 1, 1, 1, "", "", 1, "", 1, 200
            end,
        },
        GetCoinTextureString = function(n)
            return tostring(n) .. "c"
        end,
    }, function()
        local M = { L = { ITEM_ID_LINE = "Item ID: %d", ITEM_VALUE_LINE = "Vendor each: %s" } }
        H.loadAddonFile("Modules/ItemDetails.lua", M)
        fn(M.ItemDetails, tip, lines, function()
            return callback, calls
        end)
    end)
    for i = 1, #lines do
        _G["TestDetailsTipTextLeft" .. i] = nil
    end
end

test("item details disabled startup is inert and registers native callback only once", function()
    setup(function(D, tip, lines, saved)
        D.ApplyAll()
        local _, calls = saved()
        eq(calls, 0)
        MurgleDB.tooltip.itemDetails = true
        D.ApplyAll()
        D.ApplyAll()
        local cb, count = saved()
        eq(count, 1)
        cb(tip, { id = 10 })
        eq(#lines, 2)
        cb(tip, { id = 10 })
        eq(#lines, 2)
        MurgleDB.tooltip.itemDetails = false
        cb(tip, { id = 20 })
        eq(#lines, 2)
    end)
end)
test("item details reject missing IDs foreign tooltips and unavailable prices", function()
    setup(function(D, tip, lines, saved)
        MurgleDB.tooltip.itemDetails = true
        D.ApplyAll()
        local cb = saved()
        cb(tip, {})
        cb({}, { id = 10 })
        eq(#lines, 0)
        C_Item.GetItemInfo = function() end
        cb(tip, { id = 10 })
        eq(#lines, 1)
    end)
end)

test("item details use the hovered item variant for vendor value", function()
    setup(function(D, tip, lines, saved)
        MurgleDB.tooltip.itemDetails = true
        D.ApplyAll()
        local cb = saved()
        C_Item.GetItemInfo = function(link)
            eq(link, "item:10:variant")
            return "Item", link, 1, 1, 1, "", "", 1, "", 1, 300
        end
        cb(tip, { id = 10 })
        eq(lines[2], "Vendor each: 300c")
    end)
end)
