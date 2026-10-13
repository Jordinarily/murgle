local _, Murgle = ...

Murgle.DEFAULTS = {
    schemaVersion = 1,
    interface = {
        hideMicroMenu = false,
        hideBagBar = false,
        hideXP = false,
        buffTriangleMouseover = false,
        hideMacroNames = false,
        objectiveTrackerHeaders = false,
        trackerFontSize = "default",
        objectiveTrackerVisibility = "always",
        hideTalkingHead = true,
        hideBossBanner = true,
        hideZoneText = true,
        hideTotemTimers = false,
        blockHelpTips = false,
        blockLootToasts = false,
    },
    minimap = {
        square = false,
        hideBorder = false,
        hideDayNight = false,
        hideZoneText = false,
        hideClock = false,
        hideHeader = false,
        hideCalendar = false,
        hideTracking = false,
        hideAddonCompartment = false,
        hideZoomButtons = false,
    },
    quests = { sparkles = false, autoWatchReputation = false },
    automation = {
        autoQuest = false,
        autoTurnIn = false,
        autoWorldRefresh = true,
        worldRefreshMode = "hideOnly",
    },
    lootVendors = {
        fastLoot = true,
        sellJunk = false,
        autoRepair = false,
        guildRepair = false,
    },
    chat = {
        hideButtons = false,
        hideVoiceButtons = false,
        tabs = "show",
        hideCombatLog = false,
    },
    frames = {
        hidePlayerName = false,
        cleanPlayer = false,
        cleanTarget = false,
        cleanTargetOfTarget = false,
        enemyFactionOnly = false,
        enemyNameplates = "blizzard",
        friendlyNameplates = "blizzard",
        friendlyNamesOnly = false,
    },
    tooltip = {
        cursorAnchor = false,
        anchor = "right",
        hideInCombat = false,
    },
    errors = {
        mode = "important",
    },
    sound = {
        muteFizzle = false,
        muteFootsteps = false,
        muteHooves = false,
        muteChimes = false,
        muteInterface = false,
        muteReadyCheck = false,
        muteCatYawns = false,
        mutePiccolo = false,
        muteMechanostriders = false,
        muteZeppelins = false,

        muteTrains = false,
        muteMechanicalSteps = false,
        muteErrorSpeech = false,
    },
}

local function fill(target, defaults)
    for key, default in pairs(defaults) do
        if type(default) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            fill(target[key], default)
        elseif target[key] == nil then
            target[key] = default
        end
    end
end

function Murgle.ApplyDefaults(db)
    if type(db) ~= "table" then
        db = {}
    end
    fill(db, Murgle.DEFAULTS)
    db.tooltip.compact = nil
    -- Retired native duplicate: preserve the current game preference.
    db.minimap.hideCoordinates = nil
    db.minimap.coordinatesRestore = nil
    if db.interface.objectiveTrackerVisibility == "combat" then
        db.interface.objectiveTrackerVisibility = "always"
    end
    if db.errors.mode == "hidden" then
        db.errors.mode = "all"
    end
    return db
end
