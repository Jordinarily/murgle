local _, Murgle = ...
local Ammo = {}
Murgle.Ammo = Ammo
local events, label, owner
local eventNames =
    { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_INVENTORY_CHANGED" }

local function refresh()
    if label then
        label:Hide()
    end
    if
        MurgleDB.lootVendors.ammoCount ~= true
        or type(UnitUsesAmmo) ~= "function"
        or UnitUsesAmmo("player") ~= true
        or type(GetInventoryItemCount) ~= "function"
    then
        return
    end
    local button = MainMenuBarBackpackButton
    if not button or type(button.CreateFontString) ~= "function" then
        return
    end
    -- Native Camelot paper-doll ammo uses inventory slot zero's count.
    local count = GetInventoryItemCount("player", 0)
    if type(count) ~= "number" or not (count >= 0 and count < math.huge) or count ~= math.floor(count) then
        return
    end
    if button ~= owner then
        label = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        label:SetPoint("BOTTOM", button, "TOP", 0, 2)
        owner = button
    end
    label:SetText(string.format(Murgle.L.AMMO_COUNT_TEXT, count))
    label:Show()
end

function Ammo.ApplyAll()
    if
        MurgleDB.lootVendors.ammoCount ~= true
        or type(UnitUsesAmmo) ~= "function"
        or UnitUsesAmmo("player") ~= true
        or type(GetInventoryItemCount) ~= "function"
    then
        if events then
            for _, event in ipairs(eventNames) do
                events:UnregisterEvent(event)
            end
            events:UnregisterEvent("ADDON_LOADED")
        end
        if label then
            label:Hide()
        end
        return
    end
    if type(CreateFrame) ~= "function" or type(UnitUsesAmmo) ~= "function" then
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then
                return
            end
            if event == "ADDON_LOADED" and MainMenuBarBackpackButton then
                events:UnregisterEvent("ADDON_LOADED")
            end
            refresh()
        end)
    end
    for _, event in ipairs(eventNames) do
        events:RegisterEvent(event)
    end
    if not MainMenuBarBackpackButton then
        events:RegisterEvent("ADDON_LOADED")
    end
    refresh()
end
Ammo.Initialize = Ammo.ApplyAll
