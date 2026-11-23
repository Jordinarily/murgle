local _, Murgle = ...

Murgle.DEFAULTS = {
    schemaVersion = 1,
    interface = {
        hideMicroMenu = false,
        hideBagBar = false,
        hideStatusBar1 = false,
        moveBags = false,
        hideXP = false,
        buffTriangleMouseover = false,
        objectiveTrackerHeaders = false,
        objectiveTrackerVisibility = "always",
        hideTalkingHead = true,
        hideBossBanner = true,
        hideZoneText = true,
    },
    minimap = {
        cleanSquare = false,
        hideClock = false,
        hideTracking = false,
    },
    quests = {
        sparkles = false,
        rewardValues = false,
    },
    automation = {
        trainAll = false,
        skipServiceGossip = false,
        confirmLootPickup = false,
        confirmLootRolls = false,
        autoQuest = false,
        autoTurnIn = false,
        autoWorldRefresh = true,
        worldRefreshMode = "hideOnly",
    },
    lootVendors = {
        ammoCount = false,
        markedItems = {},
        bulkBuy = false,
        restockTargets = {},
        fastLoot = true,
        sellJunk = false,
        autoRepair = false,
        guildRepair = false,
    },
    chat = {
        cleanChat = false,
        tabs = "show",
        hideCombatLog = false,
    },
    frames = {
        hidePlayerName = false,
        hidePlayerFrame = false,
        compactFrames = false,
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
    -- Clean retired keys
    if db.interface then
        db.interface.holdActionPages = nil
        db.interface.holdShiftPage = nil
        db.interface.holdCtrlPage = nil
        db.interface.holdAltPage = nil
        db.interface.hideMacroNames = nil
        db.interface.fadeActionBars = nil
        db.interface.actionBarCombatOpacity = nil
        db.interface.hideTotemTimers = nil
        db.interface.blockHelpTips = nil
        db.interface.blockLootToasts = nil
        db.interface.trackerFontSize = nil
        if db.interface.objectiveTrackerVisibility == "combat" then
            db.interface.objectiveTrackerVisibility = "always"
        end
    end
    if db.minimap then
        db.minimap.hideCoordinates = nil
        db.minimap.coordinatesRestore = nil
        if db.minimap.cleanSquare == nil and db.minimap.square == true then
            db.minimap.cleanSquare = true
        end
        db.minimap.square = nil
        db.minimap.hideBorder = nil
        db.minimap.hideDayNight = nil
        db.minimap.hideZoneText = nil
        db.minimap.hideHeader = nil
        db.minimap.hideCalendar = nil
        db.minimap.hideAddonCompartment = nil
        db.minimap.hideZoomButtons = nil
    end
    if db.quests then
        db.quests.autoWatchReputation = nil
    end
    if db.automation then
        db.automation.useQuestStarters = nil
        db.automation.warnLowRank = nil
    end
    if db.lootVendors then
        db.lootVendors.openClams = nil
        db.lootVendors.markedJunk = nil
        db.lootVendors.restock = nil
        db.lootVendors.disenchantClick = nil
    end
    if db.chat then
        if db.chat.cleanChat == nil and (db.chat.hideButtons == true or db.chat.hideVoiceButtons == true) then
            db.chat.cleanChat = true
        end
        db.chat.hideButtons = nil
        db.chat.hideVoiceButtons = nil
    end
    if db.frames then
        if db.frames.compactFrames == nil and (db.frames.cleanPlayer == true or db.frames.cleanTarget == true) then
            db.frames.compactFrames = true
        end
        db.frames.cleanPlayer = nil
        db.frames.cleanTarget = nil
        db.frames.cleanTargetOfTarget = nil
        db.frames.enemyFactionOnly = nil
        db.frames.enemyNameplates = nil
        db.frames.friendlyNameplates = nil
        db.frames.friendlyNamesOnly = nil
    end
    if db.tooltip then
        db.tooltip.spellDetails = nil
        db.tooltip.compact = nil
        db.tooltip.itemDetails = nil
    end
    if db.errors and db.errors.mode == "hidden" then
        db.errors.mode = "all"
    end
    return db
end
