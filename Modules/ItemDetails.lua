local _, Murgle = ...
local ItemDetails = {}
Murgle.ItemDetails = ItemDetails
local itemInstalled, spellInstalled = false, false

local function addUnique(tooltip, text)
    local name = tooltip:GetName()
    if not name then
        return
    end
    for i = 1, tooltip:NumLines() do
        local region = _G[name .. "TextLeft" .. i]
        if region and region:GetText() == text then
            return
        end
    end
    tooltip:AddLine(text, 0.65, 0.75, 0.85)
end

local function augment(tooltip, data, spell)
    if
        MurgleDB.tooltip[spell and "spellDetails" or "itemDetails"] ~= true
        or tooltip ~= GameTooltip
        or type(data) ~= "table"
        or type(data.id) ~= "number"
        or not (data.id > 0 and data.id < math.huge)
        or data.id ~= math.floor(data.id)
        or type(tooltip.GetName) ~= "function"
        or type(tooltip.NumLines) ~= "function"
        or type(tooltip.AddLine) ~= "function"
    then
        return
    end
    if spell then
        addUnique(tooltip, string.format(Murgle.L.SPELL_ID_LINE, data.id))
        return
    end
    addUnique(tooltip, string.format(Murgle.L.ITEM_ID_LINE, data.id))
    if
        C_Item
        and type(C_Item.GetItemInfo) == "function"
        and type(GetCoinTextureString) == "function"
        and type(tooltip.GetItem) == "function"
    then
        local _, link = tooltip:GetItem()
        if type(link) ~= "string" or tonumber(link:match("item:(%d+)")) ~= data.id then
            return
        end
        local _, _, _, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(link)
        if type(price) == "number" and price > 0 and price < math.huge and price == math.floor(price) then
            addUnique(tooltip, string.format(Murgle.L.ITEM_VALUE_LINE, GetCoinTextureString(price)))
        end
    end
end

local function augmentSpell(tooltip, data)
    augment(tooltip, data, true)
end

function ItemDetails.ApplyAll()
    if MurgleDB.tooltip.itemDetails ~= true and MurgleDB.tooltip.spellDetails ~= true then
        return
    end
    if
        TooltipDataProcessor
        and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and Enum
        and Enum.TooltipDataType
    then
        -- Blizzard offers no removal API; disabled callbacks return at once.
        if
            MurgleDB.tooltip.itemDetails == true
            and not itemInstalled
            and type(Enum.TooltipDataType.Item) == "number"
        then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, augment)
            itemInstalled = true
        end
        if
            MurgleDB.tooltip.spellDetails == true
            and not spellInstalled
            and type(Enum.TooltipDataType.Spell) == "number"
        then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, augmentSpell)
            spellInstalled = true
        end
    end
end
ItemDetails.Initialize = ItemDetails.ApplyAll
