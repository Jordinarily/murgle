local _, Murgle = ...
local Quests = {}
Murgle.Quests = Quests

-- Native sparkle needs both normal and raid outline rendering disabled.
local sparkleCVars = {
    { "outlineModeShowLootEffectWhenDisabled", "1" },
    { "graphicsOutlineMode", "0" },
    { "OutlineEngineMode", "0" },
    { "raidGraphicsOutlineMode", "0" },
    { "RAIDOutlineEngineMode", "0" },
}
local sparklePrior, sparkleRestoring

local function validValue(value)
    return type(value) == "string" and tonumber(value) ~= nil
end

local function readSparkleCVars()
    if not C_CVar or type(C_CVar.GetCVarInfo) ~= "function" or type(C_CVar.SetCVar) ~= "function" then
        return
    end
    local values = {}
    for _, entry in ipairs(sparkleCVars) do
        local name = entry[1]
        local value, _, _, _, locked, secure, readOnly = C_CVar.GetCVarInfo(name)
        if not validValue(value) or locked ~= false or secure ~= false or readOnly ~= false then
            return
        end
        values[name] = value
    end
    return values
end

function Quests.SparklesAvailable()
    return readSparkleCVars() ~= nil
end

local function applySparkles()
    local settings = MurgleDB.quests
    local enabled = settings.sparkles == true
    if not enabled and not sparklePrior and settings.sparkleRestore == nil then
        return
    end
    -- Recover ownership before preflight, so a reset followed by unavailable
    -- APIs and a reload cannot discard the only copy of the original settings.
    if not sparklePrior and type(settings.sparkleRestore) == "table" then
        sparklePrior = {}
        for _, entry in ipairs(sparkleCVars) do
            local name = entry[1]
            if validValue(settings.sparkleRestore[name]) then
                sparklePrior[name] = settings.sparkleRestore[name]
            end
        end
        sparkleRestoring = settings.sparkleRestoring == true
    end
    settings.sparkleRestore = sparklePrior
    settings.sparkleRestoring = sparkleRestoring or nil
    -- Some builds may restrict these to secure console actions. Never bypass
    -- that restriction or modify only the subset that passed preflight.
    local current = readSparkleCVars()
    if not current then
        return
    end
    sparklePrior = sparklePrior or {}
    for _, entry in ipairs(sparkleCVars) do
        local name = entry[1]
        if sparklePrior[name] == nil then
            sparklePrior[name] = current[name]
        end
    end
    if enabled then
        sparkleRestoring = nil
    elseif not sparkleRestoring then
        -- Plan restoration before writing: preset setters may change dependent
        -- engine CVars. Keep this plan through failed writes, reset and reload.
        for _, entry in ipairs(sparkleCVars) do
            local name, target = entry[1], entry[2]
            if current[name] ~= target then
                sparklePrior[name] = current[name]
            end
        end
        sparkleRestoring = true
    end
    settings.sparkleRestore = sparklePrior
    settings.sparkleRestoring = sparkleRestoring
    for _, entry in ipairs(sparkleCVars) do
        local name, target = entry[1], entry[2]
        local desired = enabled and target or sparklePrior[name]
        local actual = C_CVar.GetCVarInfo(name)
        if actual ~= desired and not C_CVar.SetCVar(name, desired) then
            return -- retain the restoration plan for an explicit retry
        end
    end
    if not enabled then
        sparklePrior, settings.sparkleRestore = nil, nil
        sparkleRestoring, settings.sparkleRestoring = nil, nil
    end
end

function Quests.ApplyAll()
    applySparkles()
end

function Quests.Initialize()
    Quests.ApplyAll()
end
