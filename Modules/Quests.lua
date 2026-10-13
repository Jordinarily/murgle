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

local reputationFrame, gainPatterns
local watchingReputation = false

-- Only Blizzard's localized gain messages are accepted. Unsupported formatting
-- fails closed rather than interpreting arbitrary chat text as a reputation gain.
local function gainPattern(formatText)
    if type(formatText) ~= "string" then
        return
    end
    local pattern, captures, nextArgument = "^", {}, 1
    local cursor = 1
    while cursor <= #formatText do
        local character = formatText:sub(cursor, cursor)
        if character == "%" then
            local rest = formatText:sub(cursor)
            local token, position, kind = rest:match("^(%%(%d+)%$([sd]))")
            if not token then
                token, kind = rest:match("^(%%([sd]))")
                position = nextArgument
                nextArgument = nextArgument + 1
            end
            if not token then
                return
            end
            position = tonumber(position)
            if (kind == "s" and position ~= 1) or (kind == "d" and position ~= 2) then
                return
            end
            captures[#captures + 1] = kind
            pattern = pattern .. (kind == "s" and "(.+)" or "(%d+)")
            cursor = cursor + #token
        else
            pattern = pattern .. character:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
            cursor = cursor + 1
        end
    end
    if #captures < 1 or #captures > 2 then
        return
    end
    return { pattern = pattern .. "$", captures = captures }
end

local function reputationAvailable()
    return C_Reputation
        and type(C_Reputation.GetNumFactions) == "function"
        and type(C_Reputation.GetFactionDataByIndex) == "function"
        and type(C_Reputation.ExpandFactionHeader) == "function"
        and type(C_Reputation.CollapseFactionHeader) == "function"
        and type(C_Reputation.SetWatchedFactionByID) == "function"
end

function Quests.ReputationAvailable()
    return reputationAvailable()
        and (
            gainPattern(_G.FACTION_STANDING_INCREASED) ~= nil
            or gainPattern(_G.FACTION_STANDING_INCREASED_GENERIC) ~= nil
        )
end

local function reputationGain(_, _, message)
    if
        MurgleDB.quests.autoWatchReputation ~= true
        or watchingReputation
        or type(message) ~= "string"
        or not reputationAvailable()
        or (InCombatLockdown and InCombatLockdown())
    then
        return
    end
    local name
    for _, entry in ipairs(gainPatterns) do
        local first, second = message:match(entry.pattern)
        if first then
            local amount
            if entry.captures[1] == "s" then
                name, amount = first, second
            else
                name, amount = second, first
            end
            if amount and (not tonumber(amount) or tonumber(amount) <= 0) then
                return
            end
            break
        end
    end
    if not name or name == "" then
        return
    end
    watchingReputation = true
    local expanded, found, ambiguous, alreadyWatched = {}, nil, false, false
    local ok = pcall(function()
        local index = 1
        while index <= C_Reputation.GetNumFactions() do
            local data = C_Reputation.GetFactionDataByIndex(index)
            if not data then
                error("missing faction data")
            end
            if
                data.name == name
                and type(data.factionID) == "number"
                and data.factionID > 0
                and (not data.isHeader or data.isHeaderWithRep)
            then
                if found and found ~= data.factionID then
                    ambiguous = true
                end
                found = data.factionID
                alreadyWatched = data.isWatched == true
            end
            if data.isHeader and data.isCollapsed then
                expanded[#expanded + 1] = index
                C_Reputation.ExpandFactionHeader(index)
                local after = C_Reputation.GetFactionDataByIndex(index)
                if not after or after.isCollapsed then
                    error("header did not expand")
                end
            end
            index = index + 1
        end
    end)
    -- Reverse order keeps indices valid, including nested collapsed headers.
    for index = #expanded, 1, -1 do
        local restored, data = pcall(function()
            C_Reputation.CollapseFactionHeader(expanded[index])
            return C_Reputation.GetFactionDataByIndex(expanded[index])
        end)
        if not restored or not data or data.isCollapsed ~= true then
            ok = false
        end
    end
    if ok and found and not ambiguous and not alreadyWatched and MurgleDB.quests.autoWatchReputation == true then
        pcall(C_Reputation.SetWatchedFactionByID, found)
    end
    watchingReputation = false
end

local function applyReputation()
    if MurgleDB.quests.autoWatchReputation ~= true or not reputationAvailable() then
        if reputationFrame then
            reputationFrame:UnregisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
        end
        gainPatterns = nil
        return
    end
    gainPatterns = {}
    for _, key in ipairs({ "FACTION_STANDING_INCREASED", "FACTION_STANDING_INCREASED_GENERIC" }) do
        local pattern = gainPattern(_G[key])
        if pattern then
            gainPatterns[#gainPatterns + 1] = pattern
        end
    end
    if #gainPatterns == 0 then
        if reputationFrame then
            reputationFrame:UnregisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
        end
        return
    end
    if not reputationFrame then
        reputationFrame = CreateFrame("Frame")
        reputationFrame:SetScript("OnEvent", reputationGain)
    end
    reputationFrame:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
end

function Quests.ApplyAll()
    applyReputation()
    applySparkles()
end

function Quests.Initialize()
    Quests.ApplyAll()
end
