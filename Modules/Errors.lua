local _, Murgle = ...
local Errors = {}
Murgle.Errors = Errors

local modeApplied
local filterTable, priorFilters
local repetitive = {
    "LE_GAME_ERR_SPELL_OUT_OF_RANGE",
    "LE_GAME_ERR_OUT_OF_MANA",
    "LE_GAME_ERR_ITEM_COOLDOWN",
}

local function mode()
    local value = MurgleDB.errors.mode
    if value == "important" then
        return value
    end
    return "all"
end

local function restoreFilters()
    if not filterTable then
        return
    end
    for id, original in pairs(priorFilters) do
        -- Only restore a value still equal to the one Murgle installed.
        if filterTable[id] == true then
            filterTable[id] = original.value
        end
    end
    filterTable, priorFilters = nil, nil
end

function Errors.ApplyAll()
    local desired = mode()
    if modeApplied == desired then
        return
    end
    restoreFilters()
    modeApplied = nil
    if desired == "all" then
        modeApplied = desired
        return
    end
    local frame = UIErrorsFrame
    if not frame or type(frame.IsProtected) ~= "function" or frame:IsProtected() then
        return
    end
    if type(frame.SetMessageTypeEnabled) ~= "function" or type(BLACK_LISTED_MESSAGE_TYPES) ~= "table" then
        return
    end
    filterTable, priorFilters = BLACK_LISTED_MESSAGE_TYPES, {}
    for _, name in ipairs(repetitive) do
        local id = _G[name]
        if type(id) == "number" and id > 0 and id < math.huge and id == math.floor(id) then
            local original = filterTable[id]
            if original == nil or type(original) == "boolean" then
                priorFilters[id] = { value = original }
                frame:SetMessageTypeEnabled(id, false)
            end
        end
    end
    modeApplied = desired
end

function Errors.SetMode(value)
    MurgleDB.errors.mode = value == "important" and "important" or "all"
    Errors.ApplyAll()
end

function Errors.Initialize()
    Errors.ApplyAll()
end
