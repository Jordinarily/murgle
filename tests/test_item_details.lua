local H = dofile("tests/helpers.lua")
local function setup(fn)
    local callback, calls = nil, 0
    local callbacks = {}
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
            AddTooltipPostCall = function(kind, cb)
                callbacks[kind] = cb
                callback = cb
                calls = calls + 1
            end,
        },
        Enum = { TooltipDataType = { Item = 0, Spell = 1 } },
        C_Item = {
            GetItemInfo = function()
                return "Item", "item:10", 1, 1, 1, "", "", 1, "", 1, 200
            end,
        },
        GetCoinTextureString = function(n)
            return tostring(n) .. "c"
        end,
    }, function()
        local M = {
            L = { ITEM_ID_LINE = "Item ID: %d", ITEM_VALUE_LINE = "Vendor each: %s", SPELL_ID_LINE = "Spell ID: %d" },
        }
        H.loadAddonFile("Modules/ItemDetails.lua", M)
        fn(M.ItemDetails, tip, lines, function()
            return callback, calls, callbacks
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

test("spell details remain independently opt-in and append a single native spell ID", function()
    setup(function(D, tip, lines, saved)
        D.ApplyAll()
        local _, count = saved()
        eq(count, 0)
        MurgleDB.tooltip.spellDetails = true
        D.ApplyAll()
        D.ApplyAll()
        local _, registrations, callbacks = saved()
        eq(registrations, 1)
        eq(type(callbacks[1]), "function")
        eq(callbacks[0], nil)
        callbacks[1](tip, { id = 17 })
        callbacks[1](tip, { id = 17 })
        eq(#lines, 1)
        eq(lines[1], "Spell ID: 17")
        MurgleDB.tooltip.spellDetails = false
        callbacks[1](tip, { id = 18 })
        eq(#lines, 1)
        MurgleDB.tooltip.itemDetails = true
        D.ApplyAll()
        local _, total, both = saved()
        eq(total, 2)
        both[0](tip, { id = 10 })
        eq(lines[2], "Item ID: 10")
        eq(lines[3], "Vendor each: 200c")
    end)
end)

test("spell details ignore foreign tooltips and malformed IDs and fail closed without native spell support", function()
    setup(function(D, tip, lines, saved)
        MurgleDB.tooltip.spellDetails = true
        Enum.TooltipDataType.Spell = nil
        D.ApplyAll()
        local _, count = saved()
        eq(count, 0)
        Enum.TooltipDataType.Spell = 1
        D.ApplyAll()
        local _, _, callbacks = saved()
        eq(type(callbacks[1]), "function")
        callbacks[1]({}, { id = 17 })
        for _, data in ipairs({
            {},
            { id = 0 },
            { id = -1 },
            { id = 1.5 },
            { id = math.huge },
            { id = "17" },
            { id = 0 / 0 },
        }) do
            callbacks[1](tip, data)
        end
        callbacks[1](tip, nil)
        eq(#lines, 0)
    end)
end)
