local _, Murgle = ...
local Interface = {}
Murgle.Interface = Interface

local menuState, bagsState = {}, {}
local trackerHeaderState, questHeaderState = {}, {}
local zoneState = {}
local zoneEvents = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }
local bossState = {}
local bossEvents = { "BOSS_KILL", "ENCOUNTER_LOOT_RECEIVED" }
local talkingState = {}
local startupFrame

local function cancelUnusedStartupRetry()
    if not startupFrame then
        return
    end
    local settings = MurgleDB.interface
    if
        settings.hideXP ~= true
        and settings.hideMicroMenu ~= true
        and settings.hideBagBar ~= true
        and settings.objectiveTrackerHeaders ~= true
    then
        startupFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        startupFrame = nil
    end
end

-- Remember visibility only when taking ownership, so repeated applies cannot
-- replace the original state with Murgle's own hidden state.
local function applyVisibility(frame, state, hide)
    if state.unavailable then
        return
    end
    if not hide and state.shown == nil then
        return
    end
    -- Restore the frame we hid even if its global or parent reference changes.
    frame = state.frame or frame
    if
        not frame
        or type(frame.IsShown) ~= "function"
        or type(frame.Hide) ~= "function"
        or type(frame.Show) ~= "function"
    then
        return
    end
    if hide then
        if state.shown == nil then
            state.shown = frame:IsShown()
            state.frame = frame
        end
        frame:Hide()
    elseif state.shown ~= nil then
        local shown = state.shown
        if shown then
            frame:Show()
        else
            frame:Hide()
        end
        state.shown, state.frame = nil, nil
    end
end

local function applyMicroMenu()
    menuState.pending = nil
    applyVisibility(MicroMenu, menuState, MurgleDB.interface.hideMicroMenu == true)
end

local function applyBagBar()
    bagsState.pending = nil
    applyVisibility(BagsBar, bagsState, MurgleDB.interface.hideBagBar == true)
end

function Interface.ApplyMicroMenu()
    if menuState.unavailable then
        return
    end
    if MurgleDB.interface.hideMicroMenu ~= true and menuState.shown == nil and not menuState.pending then
        return
    end
    menuState.pending = true
    Murgle.DeferUntilOutOfCombat("interface.microMenu", applyMicroMenu)
end

function Interface.ApplyBagBar()
    if bagsState.unavailable then
        return
    end
    if MurgleDB.interface.hideBagBar ~= true and bagsState.shown == nil and not bagsState.pending then
        return
    end
    bagsState.pending = true
    Murgle.DeferUntilOutOfCombat("interface.bagBar", applyBagBar)
end

local function applyHeader(frame, state)
    state.pending = nil
    frame = state.frame or frame
    local hide = MurgleDB.interface.objectiveTrackerHeaders == true
    if frame and type(frame.IsProtected) == "function" and frame:IsProtected() then
        return
    end
    if hide and frame and type(frame.HookScript) == "function" and state.hooked ~= frame then
        -- Native tracker updates explicitly Show the root header. OnShow also
        -- covers sections revealed when their parent becomes visible at login.
        frame:HookScript("OnShow", function(self)
            if MurgleDB.interface.objectiveTrackerHeaders == true and state.frame == self then
                state.shown = true
                Interface.ApplyTrackerHeaders()
            end
        end)
        state.hooked = frame
    end
    applyVisibility(frame, state, hide)
end

local function applyTrackerHeader()
    applyHeader(ObjectiveTrackerFrame and ObjectiveTrackerFrame.Header, trackerHeaderState)
end

local function applyQuestHeader()
    applyHeader(QuestObjectiveTracker and QuestObjectiveTracker.Header, questHeaderState)
end

function Interface.ApplyTrackerHeaders()
    cancelUnusedStartupRetry()
    local hide = MurgleDB.interface.objectiveTrackerHeaders == true
    if
        not trackerHeaderState.unavailable and (hide or trackerHeaderState.shown ~= nil or trackerHeaderState.pending)
    then
        trackerHeaderState.pending = true
        Murgle.DeferUntilOutOfCombat("interface.trackerHeader", applyTrackerHeader)
    end
    if not questHeaderState.unavailable and (hide or questHeaderState.shown ~= nil or questHeaderState.pending) then
        questHeaderState.pending = true
        Murgle.DeferUntilOutOfCombat("interface.questHeader", applyQuestHeader)
    end
end

local function zoneFramesUsable(zone, subzone)
    return zone
        and subzone
        and type(zone.IsEventRegistered) == "function"
        and type(zone.RegisterEvent) == "function"
        and type(zone.UnregisterEvent) == "function"
        and type(zone.Hide) == "function"
        and type(subzone.Hide) == "function"
        and type(zone.IsProtected) == "function"
        and type(subzone.IsProtected) == "function"
        and not zone:IsProtected()
        and not subzone:IsProtected()
end

local function applyZoneText()
    zoneState.pending = nil
    local hide = MurgleDB.interface.hideZoneText == true
    if not hide and not zoneState.frame then
        return
    end
    local zone = zoneState.frame or ZoneTextFrame
    local subzone = zoneState.subzone or SubZoneTextFrame
    if not zoneFramesUsable(zone, subzone) then
        zoneState.unavailable = true
        return
    end
    if hide then
        if not zoneState.frame then
            zoneState.frame, zoneState.subzone = zone, subzone
            zoneState.events = {}
            for _, event in ipairs(zoneEvents) do
                if zone:IsEventRegistered(event) then
                    zoneState.events[event] = true
                    zone:UnregisterEvent(event)
                end
            end
        end
        zone:Hide()
        subzone:Hide()
    else
        for event in pairs(zoneState.events) do
            zone:RegisterEvent(event)
        end
        -- Resume future announcements without replaying stale transient text.
        zoneState.frame, zoneState.subzone, zoneState.events = nil, nil, nil
    end
end

function Interface.ApplyZoneText()
    if zoneState.unavailable then
        return
    end
    if MurgleDB.interface.hideZoneText ~= true and not zoneState.frame and not zoneState.pending then
        return
    end
    if not zoneFramesUsable(zoneState.frame or ZoneTextFrame, zoneState.subzone or SubZoneTextFrame) then
        zoneState.unavailable = true
        return
    end
    zoneState.pending = true
    Murgle.DeferUntilOutOfCombat("interface.zoneText", applyZoneText)
end

local function bossFrameUsable(frame)
    return frame
        and type(frame.IsProtected) == "function"
        and not frame:IsProtected()
        and type(frame.IsEventRegistered) == "function"
        and type(frame.RegisterEvent) == "function"
        and type(frame.UnregisterEvent) == "function"
        and type(frame.StopBanner) == "function"
end

local function applyBossBanner()
    bossState.pending = nil
    if MurgleDB.interface.hideBossBanner ~= true then
        if bossState.frame and bossFrameUsable(bossState.frame) then
            for event in pairs(bossState.events) do
                bossState.frame:RegisterEvent(event)
            end
            bossState.frame, bossState.events = nil, nil
        end
        return
    end
    if bossState.frame then
        return
    end
    local frame = BossBanner
    if
        not bossFrameUsable(frame)
        or type(TopBannerMgr) ~= "table"
        or type(TopBannerQueue) ~= "table"
        or type(TopBannerManager_BannerFinished) ~= "function"
    then
        bossState.unavailable = true
        return
    end
    local current = TopBannerMgr.currentBanner
    if current ~= nil and (type(current) ~= "table" or not current.frame) then
        bossState.unavailable = true
        return
    end
    for _, entry in ipairs(TopBannerQueue) do
        if type(entry) ~= "table" or not entry.frame then
            bossState.unavailable = true
            return
        end
        if entry.frame ~= frame then
            local kind = type(entry.frame)
            if (kind ~= "table" and kind ~= "userdata") or type(entry.frame.PlayBanner) ~= "function" then
                bossState.unavailable = true
                return
            end
        end
    end
    bossState.frame, bossState.events = frame, {}
    for _, event in ipairs(bossEvents) do
        if frame:IsEventRegistered(event) then
            bossState.events[event] = true
            frame:UnregisterEvent(event)
        end
    end
    -- Remove only this banner before advancing the shared manager's current item.
    for index = #TopBannerQueue, 1, -1 do
        if TopBannerQueue[index].frame == frame then
            table.remove(TopBannerQueue, index)
        end
    end
    if current and current.frame == frame then
        frame:StopBanner()
        TopBannerManager_BannerFinished()
    end
end

function Interface.ApplyBossBanner()
    if bossState.unavailable then
        return
    end
    if MurgleDB.interface.hideBossBanner ~= true and not bossState.frame and not bossState.pending then
        return
    end
    if not bossState.frame and not bossFrameUsable(BossBanner) then
        bossState.unavailable = true
        return
    end
    bossState.pending = true
    Murgle.DeferUntilOutOfCombat("interface.bossBanner", applyBossBanner)
end

local function talkingFrameUsable(frame)
    return frame
        and type(frame.IsProtected) == "function"
        and not frame:IsProtected()
        and type(frame.IsEventRegistered) == "function"
        and type(frame.RegisterEvent) == "function"
        and type(frame.UnregisterEvent) == "function"
        and type(frame.CloseImmediately) == "function"
end

local function applyTalkingHead()
    talkingState.pending = nil
    local hide = MurgleDB.interface.hideTalkingHead == true
    if not hide and not talkingState.frame then
        return
    end
    local frame = talkingState.frame or TalkingHeadFrame
    if not talkingFrameUsable(frame) then
        talkingState.unavailable = true
        return
    end
    if hide then
        if talkingState.frame then
            return
        end
        talkingState.frame = frame
        talkingState.registered = frame:IsEventRegistered("TALKINGHEAD_REQUESTED")
        if talkingState.registered then
            frame:UnregisterEvent("TALKINGHEAD_REQUESTED")
        end
        -- Let native cleanup cancel active voice/timers; leave idle Edit Mode alone.
        if frame.isPlaying == true then
            frame:CloseImmediately()
        end
    else
        if talkingState.registered then
            frame:RegisterEvent("TALKINGHEAD_REQUESTED")
        end
        talkingState.frame, talkingState.registered = nil, nil
    end
end

function Interface.ApplyTalkingHead()
    if talkingState.unavailable then
        return
    end
    if MurgleDB.interface.hideTalkingHead ~= true and not talkingState.frame and not talkingState.pending then
        return
    end
    if not talkingFrameUsable(talkingState.frame or TalkingHeadFrame) then
        talkingState.unavailable = true
        return
    end
    talkingState.pending = true
    Murgle.DeferUntilOutOfCombat("interface.talkingHead", applyTalkingHead)
end

local xpHidden = false
local xpStates

local function xpAlpha(region, value, state)
    state.changing = true
    region:SetAlpha(value)
    state.changing = nil
end

local function updateXPDividers(state, hidden)
    local pool = state.container.HorizontalDividersPool
    if hidden and pool and type(pool.EnumerateActive) == "function" then
        for divider in pool:EnumerateActive() do
            local texture = divider.BarDividerTexture
            if texture and type(texture.GetAlpha) == "function" and type(texture.SetAlpha) == "function" then
                if state.dividers[texture] == nil then
                    state.dividers[texture] = texture:GetAlpha()
                end
                texture:SetAlpha(0)
            end
        end
    else
        for texture, alpha in pairs(state.dividers) do
            texture:SetAlpha(alpha)
            state.dividers[texture] = nil
        end
    end
end

local function updateXP(state)
    local bar, container = state.bar, state.container
    if bar:IsProtected() or container:IsProtected() or state.tick:IsProtected() then
        return
    end
    local hidden = xpHidden
    xpAlpha(bar, hidden and 0 or state.alpha, state)
    xpAlpha(state.border, hidden and container.shownBarIndex == state.index and 0 or state.borderAlpha, state)
    updateXPDividers(state, hidden and container.shownBarIndex == state.index)
    -- Hidden XP must not retain an invisible tooltip target.
    if hidden then
        bar:EnableMouse(false)
        state.tick:EnableMouse(false)
        if GameTooltip and type(GameTooltip.GetOwner) == "function" and type(GameTooltip.Hide) == "function" then
            local owner = GameTooltip:GetOwner()
            if owner == bar or owner == state.tick then
                GameTooltip:Hide()
            end
        end
    else
        bar:EnableMouse(state.mouse)
        state.tick:EnableMouse(state.tickMouse)
    end
end

local function updateAllXP()
    for _, state in ipairs(xpStates) do
        updateXP(state)
    end
end

local function xpContainerUsable(container, index)
    local bar = container and type(container.bars) == "table" and container.bars[index]
    local border = container and container.BarFrameTexture
    local tick = bar and bar.ExhaustionTick
    return bar
        and bar.isExpBar == true
        and tick
        and type(tick.IsProtected) == "function"
        and not tick:IsProtected()
        and type(tick.IsMouseEnabled) == "function"
        and type(tick.EnableMouse) == "function"
        and border
        and type(container.IsProtected) == "function"
        and not container:IsProtected()
        and type(container.ApplyPendingBarToShow) == "function"
        and type(bar.IsProtected) == "function"
        and not bar:IsProtected()
        and type(bar.GetAlpha) == "function"
        and type(bar.SetAlpha) == "function"
        and type(bar.IsMouseEnabled) == "function"
        and type(bar.EnableMouse) == "function"
        and type(border.GetAlpha) == "function"
        and type(border.SetAlpha) == "function"
end

local function hookXP(container, index)
    local bar = container.bars[index]
    local state = {
        container = container,
        bar = bar,
        index = index,
        border = container.BarFrameTexture,
        tick = bar.ExhaustionTick,
        dividers = {},
    }
    hooksecurefunc(bar, "SetAlpha", function(_, value)
        if not xpHidden or state.changing then
            return
        end
        state.alpha = value
        updateXP(state)
    end)
    hooksecurefunc(state.border, "SetAlpha", function(_, value)
        if not xpHidden or state.changing then
            return
        end
        state.borderAlpha = value
        updateXP(state)
    end)
    hooksecurefunc(container, "ApplyPendingBarToShow", function()
        if not xpHidden then
            return
        end
        updateXP(state)
    end)
    if type(container.UpdateDividers) == "function" then
        hooksecurefunc(container, "UpdateDividers", function()
            if xpHidden then
                updateXP(state)
            end
        end)
    end
    return state
end

function Interface.ApplyXP()
    cancelUnusedStartupRetry()
    local hidden = MurgleDB.interface.hideXP == true
    if not hidden and not xpHidden then
        return
    end
    if not xpStates then
        local index = StatusTrackingBarInfo
            and StatusTrackingBarInfo.BarsEnum
            and StatusTrackingBarInfo.BarsEnum.Experience
        if
            type(index) ~= "number"
            or type(hooksecurefunc) ~= "function"
            or type(InCombatLockdown) ~= "function"
            or not xpContainerUsable(MainStatusTrackingBarContainer, index)
            or not xpContainerUsable(SecondaryStatusTrackingBarContainer, index)
        then
            return
        end
        -- Both containers own separate XP children; never hide the shared containers.
        xpStates = {
            hookXP(MainStatusTrackingBarContainer, index),
            hookXP(SecondaryStatusTrackingBarContainer, index),
        }
    end
    for _, state in ipairs(xpStates) do
        if not xpHidden then
            state.alpha = state.bar:GetAlpha()
            state.borderAlpha = state.border:GetAlpha()
            state.mouse = state.bar:IsMouseEnabled()
            state.tickMouse = state.tick:IsMouseEnabled()
        end
    end
    xpHidden = hidden
    updateAllXP()
end

local trackerVisibility = { mode = "always" }
local trackerEvents

local function updateTrackerVisibility()
    local state = trackerVisibility
    if not state.active then
        return
    end
    local frame = state.frame
    if frame:IsProtected() and InCombatLockdown() then
        Murgle.DeferUntilOutOfCombat("interface.trackerVisibility", updateTrackerVisibility)
        return
    end
    local combat = InCombatLockdown()
    local allowed = state.mode == "always" or state.mode == "ooc" and not combat
    state.changing = true
    if allowed and state.nativeShown then
        frame:Show()
    else
        frame:Hide()
    end
    state.changing = nil
    if state.mode == "always" then
        state.active = false
    end
end

function Interface.ApplyTrackerVisibility()
    local state = trackerVisibility
    local mode = MurgleDB.interface.objectiveTrackerVisibility
    if mode ~= "ooc" and mode ~= "hidden" then
        mode = "always"
    end
    state.mode = mode
    if trackerEvents and mode ~= "ooc" then
        trackerEvents:UnregisterEvent("PLAYER_REGEN_DISABLED")
        trackerEvents:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    if not state.active then
        if mode == "always" then
            return
        end
        local frame = ObjectiveTrackerFrame
        if
            not frame
            or type(frame.IsProtected) ~= "function"
            or frame:IsProtected()
            or type(frame.IsShown) ~= "function"
            or type(frame.Show) ~= "function"
            or type(frame.Hide) ~= "function"
            or type(hooksecurefunc) ~= "function"
            or type(InCombatLockdown) ~= "function"
        then
            return
        end
        state.frame, state.nativeShown, state.active = frame, frame:IsShown(), true
        if state.hooked ~= frame then
            -- Track native intent even when our own Hide already made it invisible.
            hooksecurefunc(frame, "Show", function()
                if not state.active or state.changing or state.frame ~= frame then
                    return
                end
                state.nativeShown = true
                updateTrackerVisibility()
            end)
            hooksecurefunc(frame, "Hide", function()
                if not state.active or state.changing or state.frame ~= frame then
                    return
                end
                state.nativeShown = false
            end)
            state.hooked = frame
        end
    end
    if mode == "ooc" then
        if not trackerEvents then
            trackerEvents = CreateFrame("Frame")
            trackerEvents:SetScript("OnEvent", updateTrackerVisibility)
        end
        trackerEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
        trackerEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    updateTrackerVisibility()
end

local totemState = {}
local totemHooks = {}

local function applyTotemTimers()
    local state = totemState
    state.pending = nil
    local hide = MurgleDB.interface.hideTotemTimers == true
    if not state.active then
        if not hide then
            return
        end
        local frame = TotemFrame
        if
            not frame
            or type(frame.IsProtected) ~= "function"
            or frame:IsProtected()
            or type(frame.IsShown) ~= "function"
            or type(frame.SetShown) ~= "function"
            or type(frame.Hide) ~= "function"
            or type(hooksecurefunc) ~= "function"
        then
            return
        end
        state.frame, state.nativeShown, state.active = frame, frame:IsShown(), true
        if not totemHooks[frame] then
            -- Totem Update uses SetShown; vehicle display explicitly uses Hide.
            -- Observe even redundant calls so expired totems never reappear on reset.
            hooksecurefunc(frame, "SetShown", function(_, shown)
                if not state.active or state.changing or state.frame ~= frame then
                    return
                end
                state.nativeShown = not not shown
                if frame:IsProtected() and InCombatLockdown() then
                    Interface.ApplyTotemTimers()
                    return
                end
                state.changing = true
                frame:Hide()
                state.changing = nil
            end)
            hooksecurefunc(frame, "Hide", function()
                if not state.active or state.changing or state.frame ~= frame then
                    return
                end
                state.nativeShown = false
            end)
            totemHooks[frame] = true
        end
    end
    state.changing = true
    if hide then
        state.frame:Hide()
    else
        state.frame:SetShown(state.nativeShown)
    end
    state.changing = nil
    if not hide then
        state.active = nil
        state.frame = nil
    end
end

function Interface.ApplyTotemTimers()
    if MurgleDB.interface.hideTotemTimers ~= true and not totemState.active and not totemState.pending then
        return
    end
    totemState.pending = true
    Murgle.DeferUntilOutOfCombat("interface.totemTimers", applyTotemTimers)
end

local helpTipsPrior

function Interface.ApplyHelpTips()
    local settings = MurgleDB.interface
    if settings.blockHelpTips ~= true and helpTipsPrior == nil and settings.helpTipsRestore == nil then
        return
    end
    if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then
        return
    end
    local current = GetCVar("hideHelptips")
    if current ~= "0" and current ~= "1" then
        return
    end
    -- Never write HelpTip.supressHelpTips: native Game Menu construction reads
    -- that shared Lua table before creating protected logout/exit callbacks.
    if settings.blockHelpTips == true then
        if helpTipsPrior ~= nil then
            return
        end
        local saved = settings.helpTipsRestore
        helpTipsPrior = (saved == "0" or saved == "1") and saved or current
        settings.helpTipsRestore = helpTipsPrior
        if current ~= "1" then
            SetCVar("hideHelptips", "1")
        end
    else
        local prior = helpTipsPrior or settings.helpTipsRestore
        if current == "1" and (prior == "0" or prior == "1") and current ~= prior then
            SetCVar("hideHelptips", prior)
        end
        helpTipsPrior, settings.helpTipsRestore = nil, nil
    end
end

local lootToastEvents = {
    "LOOT_ITEM_ROLL_WON",
    "SHOW_LOOT_TOAST",
    "SHOW_LOOT_TOAST_UPGRADE",
    "SHOW_PVP_FACTION_LOOT_TOAST",
    "SHOW_RATED_PVP_REWARD_TOAST",
    "SHOW_LOOT_TOAST_LEGENDARY_LOOTED",
}
local lootToastFrame, lootToastRegistered, lootToastPending

local function applyLootToasts()
    lootToastPending = nil
    if MurgleDB.interface.blockLootToasts ~= true then
        if lootToastFrame then
            for event in pairs(lootToastRegistered) do
                lootToastFrame:RegisterEvent(event)
            end
            lootToastFrame, lootToastRegistered = nil, nil
        end
        return
    end
    if lootToastFrame then
        return
    end
    local frame = AlertFrame
    if
        not frame
        or type(frame.IsProtected) ~= "function"
        or frame:IsProtected()
        or type(frame.IsEventRegistered) ~= "function"
        or type(frame.RegisterEvent) ~= "function"
        or type(frame.UnregisterEvent) ~= "function"
    then
        return
    end
    lootToastFrame, lootToastRegistered = frame, {}
    -- Leave active/queued alerts and every other subsystem running natively.
    for _, event in ipairs(lootToastEvents) do
        if frame:IsEventRegistered(event) then
            lootToastRegistered[event] = true
            frame:UnregisterEvent(event)
        end
    end
end

function Interface.ApplyLootToasts()
    if MurgleDB.interface.blockLootToasts ~= true and not lootToastFrame and not lootToastPending then
        return
    end
    lootToastPending = true
    Murgle.DeferUntilOutOfCombat("interface.lootToasts", applyLootToasts)
end

local trackerFonts, trackerFontSize, trackerFontPending
local trackerFontHooks = {}

local function selectedTrackerFontSize()
    local size = MurgleDB.interface.trackerFontSize
    if size == 9 or size == 10 or size == 11 then
        return size
    end
end

local function restoreTrackerFonts()
    if not trackerFonts then
        return
    end
    for _, saved in ipairs(trackerFonts) do
        saved.font:SetFont(saved.path, saved.size, saved.flags)
    end
    trackerFonts, trackerFontSize = nil, nil
end

local function applyTrackerFontSize()
    trackerFontPending = nil
    local size = selectedTrackerFontSize()
    local manager = ObjectiveTrackerManager
    local line, header = ObjectiveTrackerLineFont, ObjectiveTrackerHeaderFont
    if trackerFonts and (not size or trackerFonts[1].font ~= line or trackerFonts[2].font ~= header) then
        restoreTrackerFonts()
        if manager and type(manager.UpdateAll) == "function" then
            manager:UpdateAll()
        end
    end
    if not size or (trackerFonts and trackerFontSize == size) then
        return
    end
    if
        not manager
        or type(manager.UpdateAll) ~= "function"
        or type(manager.SetTextSize) ~= "function"
        or type(hooksecurefunc) ~= "function"
    then
        return
    end
    if not line or not header then
        return
    end
    for _, font in pairs({ line = line, header = header }) do
        if type(font.GetFont) ~= "function" or type(font.SetFont) ~= "function" then
            return
        end
    end
    if not trackerFonts then
        local linePath, lineSize, lineFlags = line:GetFont()
        local headerPath, headerSize, headerFlags = header:GetFont()
        if
            type(linePath) ~= "string"
            or type(lineSize) ~= "number"
            or type(headerPath) ~= "string"
            or type(headerSize) ~= "number"
        then
            return
        end
        trackerFonts = {
            { font = line, path = linePath, size = lineSize, flags = lineFlags },
            { font = header, path = headerPath, size = headerSize, flags = headerFlags },
        }
    end
    if not trackerFontHooks[manager] then
        trackerFontHooks[manager] = true
        hooksecurefunc(manager, "SetTextSize", function(self, nativeSize)
            if self ~= ObjectiveTrackerManager or (not trackerFonts and not selectedTrackerFontSize()) then
                return
            end
            -- Only accepted native sizes replace both shared fonts. Preserve
            -- that latest native preference for disable/reset, including Edit Mode.
            if type(nativeSize) == "number" and nativeSize >= 12 and nativeSize <= 20 then
                trackerFonts, trackerFontSize = nil, nil
                Interface.ApplyTrackerFontSize()
            end
        end)
    end
    line:SetFont(trackerFonts[1].path, size, trackerFonts[1].flags)
    header:SetFont(trackerFonts[2].path, size + 2, trackerFonts[2].flags)
    trackerFontSize = size
    manager:UpdateAll()
end

function Interface.ApplyTrackerFontSize()
    if not selectedTrackerFontSize() and not trackerFonts and not trackerFontPending then
        return
    end
    trackerFontPending = true
    Murgle.DeferUntilOutOfCombat("interface.trackerFontSize", applyTrackerFontSize)
end

local macroNames, macroPending
local macroPrefixes = {
    "ActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarLeftButton",
    "MultiBarRightButton",
    "MultiBar5Button",
    "MultiBar6Button",
    "MultiBar7Button",
}
local function applyMacroNames()
    macroPending = nil
    if MurgleDB.interface.hideMacroNames == true then
        if macroNames then
            return
        end
        macroNames = {}
        -- Native ActionButton Update changes only Name text, never its visibility.
        -- Enumerate existing native buttons once per enable, never on action updates.
        for _, prefix in ipairs(macroPrefixes) do
            for index = 1, 12 do
                local button = _G[prefix .. index]
                local name = button and button.Name
                if
                    name
                    and type(name.IsShown) == "function"
                    and type(name.Hide) == "function"
                    and type(name.Show) == "function"
                then
                    macroNames[#macroNames + 1] = { region = name, shown = name:IsShown() }
                    name:Hide()
                end
            end
        end
    elseif macroNames then
        for _, saved in ipairs(macroNames) do
            if saved.shown then
                saved.region:Show()
            else
                saved.region:Hide()
            end
        end
        macroNames = nil
    end
end

function Interface.ApplyMacroNames()
    if MurgleDB.interface.hideMacroNames == true or macroNames or macroPending then
        macroPending = true
        Murgle.DeferUntilOutOfCombat("interface.macroNames", applyMacroNames)
    end
end

-- Native CVar metadata is checked only on settings/startup actions. A changed
-- default or non-writable client fails closed rather than guessing compatibility.
function Interface.GetSpellQueueWindow()
    if not C_CVar or type(C_CVar.GetCVarInfo) ~= "function" or type(C_CVar.SetCVar) ~= "function" then
        return nil
    end
    local value, default, _, _, locked, secure, readOnly = C_CVar.GetCVarInfo("SpellQueueWindow")
    value = tonumber(value)
    if
        tonumber(default) ~= 400
        or not value
        or value ~= value
        or value < 0
        or value == math.huge
        or locked ~= false
        or secure ~= false
        or readOnly ~= false
    then
        return nil
    end
    return value
end

function Interface.SetSpellQueueWindow(value)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return
    end
    local current = Interface.GetSpellQueueWindow()
    if not current then
        return
    end
    value = math.max(0, math.min(400, math.floor(value / 10 + 0.5) * 10))
    if current ~= value and not C_CVar.SetCVar("SpellQueueWindow", tostring(value)) then
        return
    end
    MurgleDB.interface.spellQueueWindow = value
end

-- Native PerformanceBar.lua reads world latency as GetNetStats' fourth return.
-- Sample only on an explicit click; zero/missing latency is not a usable sample.
function Interface.AutoDetectSpellQueueWindow()
    if type(GetNetStats) ~= "function" then
        return
    end
    local _, _, _, latency = GetNetStats()
    if type(latency) ~= "number" or latency ~= latency or latency <= 0 or latency == math.huge then
        return
    end
    Interface.SetSpellQueueWindow(latency + 150)
end

local actionBarNames = {
    "MainActionBar",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarLeft",
    "MultiBarRight",
    "MultiBar5",
    "MultiBar6",
    "MultiBar7",
}
local actionBarStates = {}
local actionBarEvents, actionBarEditManager
local actionBarFactor = 1

local function readableAlpha(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number" and value >= 0 and value <= 1
end

local function writeActionBarAlpha(frame, state, value)
    state.writing = true
    frame:SetAlpha(value)
    state.writing = nil
end

function Interface.ApplyActionBarFade()
    local enabled = MurgleDB.interface.fadeActionBars == true and type(hooksecurefunc) == "function"
    local opacity = MurgleDB.interface.actionBarCombatOpacity
    if type(opacity) ~= "number" or not (opacity >= 0 and opacity <= 100) then
        opacity = 100
    end
    local manager = EditModeManagerFrame
    local editing = manager and type(manager.IsEditModeActive) == "function" and manager:IsEditModeActive()
    actionBarFactor = enabled and InCombatLockdown() and not editing and opacity / 100 or 1

    if enabled then
        local missing = false
        for _, name in ipairs(actionBarNames) do
            local frame = _G[name]
            if frame and type(frame.GetAlpha) == "function" and type(frame.SetAlpha) == "function" then
                if not actionBarStates[frame] then
                    local state = {}
                    actionBarStates[frame] = state
                    -- Native opacity writers must not erase the combat fade.
                    -- Observe their value for restoration without touching secure
                    -- visibility, mouse handling, bindings or button attributes.
                    hooksecurefunc(frame, "SetAlpha", function(self, value)
                        if state.writing or state.original == nil then
                            return
                        end
                        if not readableAlpha(value) then
                            state.original = nil
                            return
                        end
                        state.original = value
                        writeActionBarAlpha(self, state, value * actionBarFactor)
                    end)
                end
            else
                missing = true
            end
        end
        if
            manager ~= actionBarEditManager
            and manager
            and type(manager.EnterEditMode) == "function"
            and type(manager.ExitEditMode) == "function"
        then
            local function refresh()
                if MurgleDB.interface.fadeActionBars == true then
                    Interface.ApplyActionBarFade()
                end
            end
            hooksecurefunc(manager, "EnterEditMode", refresh)
            hooksecurefunc(manager, "ExitEditMode", refresh)
            actionBarEditManager = manager
        end
        if not actionBarEvents then
            actionBarEvents = CreateFrame("Frame")
            actionBarEvents:SetScript("OnEvent", function(_, event, addon)
                if event ~= "ADDON_LOADED" or addon == "Blizzard_ActionBar" or addon == "Blizzard_EditMode" then
                    Interface.ApplyActionBarFade()
                end
            end)
        end
        actionBarEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
        actionBarEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
        actionBarEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
        if missing or not actionBarEditManager then
            actionBarEvents:RegisterEvent("ADDON_LOADED")
        else
            actionBarEvents:UnregisterEvent("ADDON_LOADED")
        end
    elseif actionBarEvents then
        actionBarEvents:UnregisterEvent("PLAYER_REGEN_DISABLED")
        actionBarEvents:UnregisterEvent("PLAYER_REGEN_ENABLED")
        actionBarEvents:UnregisterEvent("PLAYER_ENTERING_WORLD")
        actionBarEvents:UnregisterEvent("ADDON_LOADED")
    end

    for frame, state in pairs(actionBarStates) do
        if actionBarFactor < 1 then
            if state.original == nil then
                local alpha = frame:GetAlpha()
                if readableAlpha(alpha) then
                    state.original = alpha
                end
            end
            if state.original ~= nil then
                writeActionBarAlpha(frame, state, state.original * actionBarFactor)
            end
        elseif state.original ~= nil then
            writeActionBarAlpha(frame, state, state.original)
            state.original = nil
        end
    end
end

function Interface.ApplyAll()
    Interface.ApplyActionBarFade()
    Interface.ApplyMacroNames()
    Interface.ApplyMicroMenu()
    Interface.ApplyBagBar()
    Interface.ApplyTrackerHeaders()
    Interface.ApplyTrackerFontSize()
    Interface.ApplyZoneText()
    Interface.ApplyBossBanner()
    Interface.ApplyTalkingHead()
    Interface.ApplyXP()
    Interface.ApplyTrackerVisibility()
    Interface.ApplyTotemTimers()
    Interface.ApplyHelpTips()
    Interface.ApplyLootToasts()
end

function Interface.Initialize()
    Interface.ApplyAll()
    if MurgleDB.interface.spellQueueWindow ~= nil then
        Interface.SetSpellQueueWindow(MurgleDB.interface.spellQueueWindow)
    end
    -- Addon startup precedes some native UI initialization. Retry once at login;
    -- explicit setting changes may also retry. Never permanently latch absence.
    local needsXP = MurgleDB.interface.hideXP == true
    if
        needsXP
        or MurgleDB.interface.hideMicroMenu
        or MurgleDB.interface.hideBagBar
        or MurgleDB.interface.objectiveTrackerHeaders == true
    then
        startupFrame = CreateFrame("Frame")
        startupFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        startupFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
            startupFrame = nil
            Interface.ApplyTrackerHeaders()
            Interface.ApplyMicroMenu()
            Interface.ApplyBagBar()
            Interface.ApplyXP()
        end)
    end
end
