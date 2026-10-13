local _, Murgle = ...
local L = Murgle.L
local Settings = {}
Murgle.Settings = Settings

-- Fixed palette; applied only at lazy creation and explicit control refresh.
local COLORS = {
    background = { 16 / 255, 19 / 255, 24 / 255, 1 },
    panel = { 21 / 255, 26 / 255, 33 / 255, 1 },
    button = { 28 / 255, 34 / 255, 43 / 255, 1 },
    selected = { 37 / 255, 45 / 255, 56 / 255, 1 },
    border = { 52 / 255, 61 / 255, 73 / 255, 1 },
    text = { 229 / 255, 233 / 255, 240 / 255 },
    secondary = { 181 / 255, 189 / 255, 201 / 255 },
    muted = { 115 / 255, 125 / 255, 140 / 255 },
    accent = { 111 / 255, 143 / 255, 174 / 255 },
    hover = { 120 / 255, 154 / 255, 184 / 255, 0.08 },
}

local window, content

local selected = "Interface"
local pages, navigation = {}, {}

local function label(parent, text, size)
    local font = parent:CreateFontString(nil, "OVERLAY")
    font:SetFont(STANDARD_TEXT_FONT, size or 13)
    font:SetText(text)
    font:SetTextColor(unpack(COLORS.text))
    font:SetJustifyH("LEFT")
    return font
end

local function button(parent, text, width, onClick)
    local control = CreateFrame("Button", nil, parent)
    control:SetSize(width, 30)
    local background = control:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(control)
    background:SetColorTexture(unpack(COLORS.button))
    local highlight = control:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(control)
    highlight:SetColorTexture(unpack(COLORS.hover))
    control:SetHighlightTexture(highlight)
    local textRegion = label(control, text)
    textRegion:SetPoint("CENTER")
    textRegion.background = background
    control:SetScript("OnClick", function(self, ...)
        onClick(self, ...)
    end)
    return control, textRegion
end

-- Reuse Spell Queue's native tooltip behavior for short, optional help.
local function helpButton(page, text, caption)
    local help = button(page, "?", 20, function() end)
    help:SetSize(20, 20)
    help:SetPoint("LEFT", caption, "RIGHT", 4, 0)
    help:SetScript("OnEnter", function(self)
        if GameTooltip and type(GameTooltip.SetOwner) == "function" and type(GameTooltip.SetText) == "function" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(type(text) == "function" and text() or text, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    help:SetScript("OnLeave", function(self)
        if GameTooltip and type(GameTooltip.GetOwner) == "function" and GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)
    return help
end

local function setSelected(caption, active)
    caption:SetTextColor(unpack(active and COLORS.accent or COLORS.text))
    caption.background:SetColorTexture(unpack(active and COLORS.selected or COLORS.button))
end

local function newPage(title)
    local page = CreateFrame("Frame", nil, content)
    page:SetSize(420, 325)
    page:SetPoint("TOPLEFT")
    local heading = label(page, title, 18)
    heading:SetPoint("TOPLEFT", 0, 0)
    return page
end

local function checkbox(page, text, key, row, apply, category)
    local control = CreateFrame("CheckButton", nil, page)
    control:SetSize(22, 22)
    control:SetPoint("TOPLEFT", 0, -36 - (row - 1) * 36)
    local background = control:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(control)
    background:SetColorTexture(unpack(COLORS.border))
    local checked = control:CreateTexture(nil, "ARTWORK")
    checked:SetPoint("TOPLEFT", 4, -4)
    checked:SetPoint("BOTTOMRIGHT", -4, 4)
    checked:SetColorTexture(unpack(COLORS.accent))
    control:SetCheckedTexture(checked)
    local caption = label(control, text)
    caption:SetPoint("LEFT", control, "RIGHT", 8, 0)
    control.caption = caption
    control:SetScript("OnClick", function(self)
        MurgleDB[category or "interface"][key] = self:GetChecked() == true
        apply()
        if page.Refresh then
            page:Refresh()
        end
    end)
    category = category or "interface"
    if type(Murgle.DEFAULTS[category][key]) == "boolean" then
        page.toggles = page.toggles or {}
        page.toggles[#page.toggles + 1] = { category = category, key = key, apply = apply }
    end
    return control
end

local function interfacePage()
    local page = newPage(L.CATEGORY_INTERFACE)
    local menu = checkbox(page, L.HIDE_MICRO_MENU, "hideMicroMenu", 1, function()
        Murgle.Interface.ApplyMicroMenu()
    end)
    local bags = checkbox(page, L.HIDE_BAG_BAR, "hideBagBar", 2, function()
        Murgle.Interface.ApplyBagBar()
    end)
    local tracker = checkbox(page, L.TRACKER_HEADERS, "objectiveTrackerHeaders", 3, function()
        Murgle.Interface.ApplyTrackerHeaders()
    end)
    local zone = checkbox(page, L.HIDE_ZONE_TEXT, "hideZoneText", 4, function()
        Murgle.Interface.ApplyZoneText()
    end)
    local boss = checkbox(page, L.HIDE_BOSS_BANNER, "hideBossBanner", 5, function()
        Murgle.Interface.ApplyBossBanner()
    end)
    local talking = checkbox(page, L.HIDE_TALKING_HEAD, "hideTalkingHead", 6, function()
        Murgle.Interface.ApplyTalkingHead()
    end)
    local totems = checkbox(page, L.HIDE_TOTEM_TIMERS, "hideTotemTimers", 7, Murgle.Interface.ApplyTotemTimers)
    local helpTips = checkbox(page, L.BLOCK_HELP_TIPS, "blockHelpTips", 7, Murgle.Interface.ApplyHelpTips)
    for row, control in ipairs({ menu, bags, tracker, zone, boss, talking, helpTips }) do
        control:SetPoint("TOPLEFT", 0, -36 - (row - 1) * 22)
    end
    totems:SetPoint("TOPLEFT", 215, -146)
    local lootToasts = checkbox(page, L.BLOCK_LOOT_TOASTS, "blockLootToasts", 7, Murgle.Interface.ApplyLootToasts)
    lootToasts:SetPoint("TOPLEFT", 215, -168)
    local xp = checkbox(page, L.HIDE_XP, "hideXP", 8, Murgle.Interface.ApplyXP)
    xp:SetPoint("TOPLEFT", 0, -198)
    local buffHover = checkbox(page, L.BUFF_TRIANGLE_HOVER, "buffTriangleMouseover", 1, Murgle.Buffs.ApplyAll)
    buffHover:SetPoint("TOPLEFT", 215, -36)
    local macros = checkbox(page, L.HIDE_MACRO_NAMES, "hideMacroNames", 1, Murgle.Interface.ApplyMacroNames)
    macros:SetPoint("TOPLEFT", 215, -58)
    local trackerLabel = label(page, L.TRACKER_VISIBILITY)
    trackerLabel:SetPoint("TOPLEFT", 0, -228)
    local trackerButtons = {}
    for index, choice in ipairs({
        { "always", L.ALWAYS },
        { "ooc", L.OUT_OF_COMBAT },
        { "hidden", L.HIDDEN },
    }) do
        local mode = choice[1]
        local control, caption = button(page, choice[2], 98, function()
            MurgleDB.interface.objectiveTrackerVisibility = mode
            Murgle.Interface.ApplyTrackerVisibility()
            page:Refresh()
        end)
        control:SetSize(98, 25)
        control:SetPoint("TOPLEFT", (index - 1) * 104, -249)
        trackerButtons[mode] = caption
    end
    local fontLabel = label(page, L.TRACKER_FONT_SIZE)
    fontLabel:SetPoint("TOPLEFT", 0, -282)
    local fontCaptions = {}
    for index, choice in ipairs({ { "default", L.BLIZZARD_DEFAULT }, { 9, "9" }, { 10, "10" }, { 11, "11" } }) do
        local size = choice[1]
        local control, caption = button(page, choice[2], index == 1 and 126 or 32, function()
            MurgleDB.interface.trackerFontSize = size
            Murgle.Interface.ApplyTrackerFontSize()
            page:Refresh()
        end)
        control:SetSize(index == 1 and 126 or 32, 25)
        control:SetPoint("TOPLEFT", index == 1 and 160 or 290 + (index - 2) * 38, -276)
        fontCaptions[size] = caption
    end
    helpButton(menu, L.INTERFACE_COMBAT_NOTE, menu.caption)
    function page:Refresh()
        menu:SetChecked(MurgleDB.interface.hideMicroMenu == true)
        bags:SetChecked(MurgleDB.interface.hideBagBar == true)
        tracker:SetChecked(MurgleDB.interface.objectiveTrackerHeaders == true)
        zone:SetChecked(MurgleDB.interface.hideZoneText == true)
        boss:SetChecked(MurgleDB.interface.hideBossBanner == true)
        talking:SetChecked(MurgleDB.interface.hideTalkingHead == true)
        totems:SetChecked(MurgleDB.interface.hideTotemTimers == true)
        helpTips:SetChecked(MurgleDB.interface.blockHelpTips == true)
        lootToasts:SetChecked(MurgleDB.interface.blockLootToasts == true)
        local trackerMode = MurgleDB.interface.objectiveTrackerVisibility
        if not trackerButtons[trackerMode] then
            trackerMode = "always"
        end
        for mode, caption in pairs(trackerButtons) do
            setSelected(caption, mode == trackerMode)
        end
        local fontSize = MurgleDB.interface.trackerFontSize
        if not fontCaptions[fontSize] then
            fontSize = "default"
        end
        for size, caption in pairs(fontCaptions) do
            setSelected(caption, size == fontSize)
        end
        xp:SetChecked(MurgleDB.interface.hideXP == true)
        macros:SetChecked(MurgleDB.interface.hideMacroNames == true)
        buffHover:SetChecked(MurgleDB.interface.buffTriangleMouseover == true)
    end
    return page
end

local function minimapPage()
    local page = newPage(L.CATEGORY_MINIMAP)
    local zone = checkbox(page, L.HIDE_MINIMAP_ZONE, "hideZoneText", 1, Murgle.Minimap.ApplyZoneText, "minimap")
    local clock = checkbox(page, L.HIDE_CLOCK, "hideClock", 2, Murgle.Minimap.ApplyClock, "minimap")
    local calendar = checkbox(page, L.HIDE_CALENDAR, "hideCalendar", 3, Murgle.Minimap.ApplyCalendar, "minimap")
    local tracking = checkbox(page, L.HIDE_TRACKING, "hideTracking", 4, Murgle.Minimap.ApplyTracking, "minimap")
    local zoom = checkbox(page, L.HIDE_ZOOM_BUTTONS, "hideZoomButtons", 5, Murgle.Minimap.ApplyZoomButtons, "minimap")
    local compartment = checkbox(
        page,
        L.HIDE_ADDON_COMPARTMENT,
        "hideAddonCompartment",
        6,
        Murgle.Minimap.ApplyAddonCompartment,
        "minimap"
    )
    local border = checkbox(page, L.HIDE_MINIMAP_BORDER, "hideBorder", 7, Murgle.Minimap.ApplyBorder, "minimap")
    local square = checkbox(page, L.SQUARE_MINIMAP, "square", 8, Murgle.Minimap.ApplySquare, "minimap")
    local dayNight = checkbox(page, L.HIDE_DAY_NIGHT, "hideDayNight", 9, Murgle.Minimap.ApplyDayNight, "minimap")
    local header = checkbox(page, L.HIDE_MINIMAP_HEADER, "hideHeader", 10, Murgle.Minimap.ApplyHeader, "minimap")
    for row, control in ipairs({
        zone,
        clock,
        calendar,
        tracking,
        zoom,
        compartment,
        border,
        square,
        dayNight,
        header,
    }) do
        control:SetPoint("TOPLEFT", math.floor((row - 1) / 6) * 215, -36 - ((row - 1) % 6) * 25)
    end
    helpButton(square, L.SQUARE_MINIMAP_NOTE, square.caption)
    function page:Refresh()
        zone:SetChecked(MurgleDB.minimap.hideZoneText == true)
        clock:SetChecked(MurgleDB.minimap.hideClock == true)
        calendar:SetChecked(MurgleDB.minimap.hideCalendar == true)
        tracking:SetChecked(MurgleDB.minimap.hideTracking == true)
        zoom:SetChecked(MurgleDB.minimap.hideZoomButtons == true)
        compartment:SetChecked(MurgleDB.minimap.hideAddonCompartment == true)
        border:SetChecked(MurgleDB.minimap.hideBorder == true)
        if MurgleDB.minimap.square == true then
            border:Hide()
        else
            border:Show()
        end
        square:SetChecked(MurgleDB.minimap.square == true)
        header:SetChecked(MurgleDB.minimap.hideHeader == true)
        dayNight:SetChecked(MurgleDB.minimap.hideDayNight == true)
    end
    return page
end

local function chatPage()
    local page = newPage(L.CATEGORY_CHAT)
    local buttons = checkbox(page, L.HIDE_CHAT_BUTTONS, "hideButtons", 1, Murgle.Chat.ApplyButtons, "chat")
    local combatLog = checkbox(page, L.HIDE_COMBAT_LOG, "hideCombatLog", 2, Murgle.Chat.ApplyCombatLog, "chat")
    local tabsLabel = label(page, L.CHAT_TABS)
    tabsLabel:SetPoint("TOPLEFT", 0, -116)
    helpButton(page, L.CHAT_TABS_MOUSEOVER_NOTE .. "\n" .. L.CHAT_TABS_HIDE_NOTE, tabsLabel)
    local tabs = {}
    for index, choice in ipairs({ { "hide", L.CHAT_HIDE }, { "mouseover", L.CHAT_FADE }, { "show", L.CHAT_DEFAULT } }) do
        local mode = choice[1]
        local control, caption = button(page, choice[2], 100, function()
            MurgleDB.chat.tabs = mode
            Murgle.Chat.ApplyTabs()
            page:Refresh()
        end)
        control:SetPoint("TOPLEFT", (index - 1) * 108, -140)
        tabs[mode] = caption
    end
    local voice = checkbox(page, L.HIDE_VOICE_BUTTONS, "hideVoiceButtons", 5, Murgle.Chat.ApplyVoiceButtons, "chat")
    helpButton(voice, L.HIDE_VOICE_BUTTONS_NOTE, voice.caption)
    function page:Refresh()
        buttons:SetChecked(MurgleDB.chat.hideButtons == true)
        voice:SetChecked(MurgleDB.chat.hideVoiceButtons == true)
        combatLog:SetChecked(MurgleDB.chat.hideCombatLog == true)
        local mode = tabs[MurgleDB.chat.tabs] and MurgleDB.chat.tabs or "show"
        for key, caption in pairs(tabs) do
            setSelected(caption, key == mode)
        end
    end
    return page
end

local function tooltipPage()
    local page = newPage(L.CATEGORY_TOOLTIP)
    local cursor = checkbox(page, L.CURSOR_ANCHOR, "cursorAnchor", 1, Murgle.Tooltip.ApplyCursorAnchor, "tooltip")
    local combat = checkbox(page, L.COMBAT_TOOLTIP_HIDE, "hideInCombat", 2, Murgle.Tooltip.ApplyCombatHide, "tooltip")
    local captions, controls = {}, {}
    for index, choice in ipairs({ { "left", L.CURSOR_LEFT }, { "right", L.CURSOR_RIGHT }, { "cursor", L.CURSOR_AT } }) do
        local control, caption = button(page, choice[2], 132, function()
            Murgle.Tooltip.SetAnchor(choice[1])
            page:Refresh()
        end)
        control:SetPoint("TOPLEFT", (index - 1) * 140, -66)
        captions[choice[1]] = caption
        controls[choice[1]] = control
    end
    helpButton(page, L.TOOLTIP_SCOPE_NOTE, combat.caption)
    function page:Refresh()
        cursor:SetChecked(MurgleDB.tooltip.cursorAnchor == true)
        combat:SetChecked(MurgleDB.tooltip.hideInCombat == true)
        local showCursorOptions = MurgleDB.tooltip.cursorAnchor == true
        combat:SetPoint("TOPLEFT", 0, showCursorOptions and -108 or -72)
        for key, caption in pairs(captions) do
            if showCursorOptions then
                controls[key]:Show()
            else
                controls[key]:Hide()
            end
            setSelected(caption, key == MurgleDB.tooltip.anchor)
        end
    end
    return page
end

local function spellQueueControl(page)
    if not Murgle.Interface.GetSpellQueueWindow() then
        return
    end
    local title = label(page, L.SPELL_QUEUE)
    title:SetPoint("TOPLEFT", 0, -279)
    local valueText = label(page, "", 12)
    valueText:SetPoint("TOPRIGHT", -10, -279)
    helpButton(page, L.SPELL_QUEUE_HELP, title)
    local slider = CreateFrame("Slider", nil, page)
    slider:SetSize(400, 16)
    slider:SetPoint("TOPLEFT", 0, -305)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(0, 400)
    slider:SetValueStep(10)
    slider:SetObeyStepOnDrag(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetSize(400, 4)
    track:SetColorTexture(unpack(COLORS.border))
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(10, 16)
    thumb:SetColorTexture(unpack(COLORS.accent))
    slider:SetThumbTexture(thumb)
    local low, high = label(page, L.SPELL_QUEUE_OFF, 11), label(page, L.SPELL_QUEUE_DEFAULT, 11)
    low:SetPoint("TOPLEFT", 0, -326)
    high:SetPoint("TOPRIGHT", -10, -326)
    local refreshing = false
    local function refresh()
        local value = Murgle.Interface.GetSpellQueueWindow()
        if value then
            refreshing = true
            slider:SetValue(math.min(value, 400))
            refreshing = false
            valueText:SetText(tostring(value) .. " ms")
        end
    end
    slider:SetScript("OnValueChanged", function(_, value)
        if refreshing then
            return
        end
        Murgle.Interface.SetSpellQueueWindow(value)
        refresh()
    end)
    local auto = button(page, L.SPELL_QUEUE_AUTO, 120, function()
        Murgle.Interface.AutoDetectSpellQueueWindow()
        refresh()
    end)
    auto:SetSize(120, 22)
    auto:SetPoint("TOPLEFT", 195, -276)
    refresh()
    return refresh
end

local function automationPage()
    local page = newPage(L.CATEGORY_AUTOMATION)
    local accept = checkbox(page, L.AUTO_QUEST, "autoQuest", 1, Murgle.Automation.ApplyAll, "automation")
    local turnIn = checkbox(page, L.AUTO_TURN_IN, "autoTurnIn", 2, Murgle.Automation.ApplyAll, "automation")
    helpButton(page, L.QUEST_AUTOMATION_NOTE, accept.caption)
    local refresh =
        checkbox(page, L.AUTO_WORLD_REFRESH, "autoWorldRefresh", 4, Murgle.Automation.ApplyAll, "automation")
    helpButton(page, L.WORLD_REFRESH_SCOPE_NOTE .. "\n" .. L.WORLD_REFRESH_HARDCORE_NOTE, refresh.caption)
    local refreshCaptions, refreshControls = {}, {}
    for index, choice in ipairs({
        { "hideOnly", L.WORLD_REFRESH_HIDE_ONLY },
        { "acceptAndHide", L.WORLD_REFRESH_ACCEPT_HIDE },
    }) do
        local mode = choice[1]
        local control, caption = button(page, choice[2], 160, function()
            MurgleDB.automation.worldRefreshMode = mode
            Murgle.Automation.ApplyAll()
            page:Refresh()
        end)
        control:SetPoint("TOPLEFT", (index - 1) * 168, -174)
        refreshCaptions[mode] = caption
        refreshControls[mode] = control
    end
    local refreshQueue = spellQueueControl(page)
    function page:Refresh()
        if refreshQueue then
            refreshQueue()
        end
        accept:SetChecked(MurgleDB.automation.autoQuest == true)
        turnIn:SetChecked(MurgleDB.automation.autoTurnIn == true)
        refresh:SetChecked(MurgleDB.automation.autoWorldRefresh == true)
        for mode, caption in pairs(refreshCaptions) do
            if MurgleDB.automation.autoWorldRefresh == true then
                refreshControls[mode]:Show()
            else
                refreshControls[mode]:Hide()
            end
            setSelected(caption, mode == MurgleDB.automation.worldRefreshMode)
        end
    end
    return page
end

local function lootVendorsPage()
    local page = newPage(L.CATEGORY_LOOT_VENDORS)
    local repair = checkbox(page, L.AUTO_REPAIR, "autoRepair", 1, Murgle.LootVendors.ApplyAll, "lootVendors")
    local guild = checkbox(page, L.GUILD_REPAIR, "guildRepair", 2, Murgle.LootVendors.ApplyAll, "lootVendors")
    local junk = checkbox(page, L.SELL_JUNK, "sellJunk", 3, Murgle.LootVendors.ApplyAll, "lootVendors")
    local fast = checkbox(page, L.FAST_LOOT, "fastLoot", 4, Murgle.LootVendors.ApplyAll, "lootVendors")
    helpButton(page, L.AUTO_REPAIR_NOTE, repair.caption)
    helpButton(page, L.SELL_JUNK_NOTE, junk.caption)
    helpButton(page, L.FAST_LOOT_NOTE, fast.caption)
    function page:Refresh()
        repair:SetChecked(MurgleDB.lootVendors.autoRepair == true)
        guild:SetChecked(MurgleDB.lootVendors.guildRepair == true)
        if MurgleDB.lootVendors.autoRepair == true then
            guild:Show()
            guild:SetPoint("TOPLEFT", 22, -66)
            junk:SetPoint("TOPLEFT", 0, -102)
            fast:SetPoint("TOPLEFT", 0, -138)
        else
            guild:Hide()
            junk:SetPoint("TOPLEFT", 0, -72)
            fast:SetPoint("TOPLEFT", 0, -108)
        end
        junk:SetChecked(MurgleDB.lootVendors.sellJunk == true)
        fast:SetChecked(MurgleDB.lootVendors.fastLoot == true)
    end
    return page
end

local function errorsPage()
    local page = newPage(L.CATEGORY_ERRORS_SOUND)
    local captions = {}
    for index, choice in ipairs({ { "all", L.ALL }, { "important", L.IMPORTANT } }) do
        local mode = choice[1]
        local control, caption = button(page, choice[2], 130, function()
            Murgle.Errors.SetMode(mode)
            page:Refresh()
        end)
        control:SetPoint("TOPLEFT", (index - 1) * 138, -32)
        captions[mode] = caption
    end
    local note = label(page, L.ERROR_SCOPE_NOTE, 12)
    note:SetPoint("TOPLEFT", 0, -68)
    note:SetSize(410, 32)
    local checks = {}
    for index, item in ipairs({
        { "muteFizzle", L.MUTE_FIZZLE },
        { "muteErrorSpeech", L.MUTE_ERROR_SPEECH },
        { "muteTrains", L.MUTE_TRAINS },
        { "muteMechanicalSteps", L.MUTE_MECHANICAL_STEPS },
        { "muteFootsteps", L.MUTE_FOOTSTEPS },
        { "muteHooves", L.MUTE_HOOVES },
        { "muteChimes", L.MUTE_CHIMES },
        { "muteInterface", L.MUTE_INTERFACE },
        { "muteReadyCheck", L.MUTE_READY_CHECK },
        { "muteCatYawns", L.MUTE_CAT_YAWNS },
        { "mutePiccolo", L.MUTE_PICCOLO },
        { "muteMechanostriders", L.MUTE_MECHANOSTRIDERS },
        { "muteZeppelins", L.MUTE_ZEPPELINS },
    }) do
        local check = checkbox(page, item[2], item[1], 1, Murgle.Sound.ApplyAll, "sound")
        check:SetPoint("TOPLEFT", ((index - 1) % 2) * 215, -150 - math.floor((index - 1) / 2) * 24)
        checks[item[1]] = check
    end
    local muteAll, muteCaption = button(page, L.MUTE_ALL, 166, function()
        Murgle.Sound.SetAllMuted(not Murgle.Sound.AreAllMuted())
        page:Refresh()
    end)
    muteAll:SetSize(166, 24)
    muteAll:SetPoint("TOPLEFT", 0, -120)
    helpButton(page, L.SOUND_HELP, muteCaption)
    function page:Refresh()
        muteCaption:SetText(Murgle.Sound.AreAllMuted() and L.UNMUTE_ALL or L.MUTE_ALL)
        for key, check in pairs(checks) do
            check:SetChecked(MurgleDB.sound[key] == true)
        end
        local selected = MurgleDB.errors.mode
        if not captions[selected] then
            selected = "all"
        end
        for mode, caption in pairs(captions) do
            setSelected(caption, mode == selected)
        end
    end
    return page
end

-- Page factories are settings-only dispatch; feature modules remain independent.
local function framesPage()
    local page = newPage(L.CATEGORY_FRAMES)
    local checks = {}
    for row, item in ipairs({
        { "cleanPlayer", L.CLEAN_PLAYER },
        { "cleanTarget", L.CLEAN_TARGET },
        { "cleanTargetOfTarget", L.CLEAN_TARGET_OF_TARGET },
        { "hidePlayerName", L.HIDE_PLAYER_NAME },
        { "enemyFactionOnly", L.ENEMY_FACTION_ONLY },
    }) do
        checks[item[1]] = checkbox(page, item[2], item[1], row, Murgle.Frames.ApplyAll, "frames")
        checks[item[1]]:SetPoint("TOPLEFT", 0, -36 - (row - 1) * 25)
    end
    local captions = {}
    for row, item in ipairs({
        { "enemyNameplates", L.ENEMY_NAMEPLATES },
        { "friendlyNameplates", L.FRIENDLY_NAMEPLATES },
    }) do
        local key = item[1]
        if Murgle.Frames.NativeAvailable(key) then
            local heading = label(page, item[2])
            heading:SetPoint("TOPLEFT", 0, -166 - (row - 1) * 65)
            captions[key] = {}
            for index, mode in ipairs({
                { "blizzard", L.GAME_SETTINGS },
                { "combat", L.COMBAT },
                { "hidden", L.HIDDEN },
            }) do
                local control, caption = button(page, mode[2], 130, function()
                    MurgleDB.frames[key] = mode[1]
                    Murgle.Frames.ApplyAll()
                    page:Refresh()
                end)
                control:SetPoint("TOPLEFT", (index - 1) * 138, -187 - (row - 1) * 65)
                captions[key][mode[1]] = caption
            end
        end
    end
    for row, item in ipairs({
        { "friendlyNamesOnly", L.FRIENDLY_NAMES_ONLY },
    }) do
        if Murgle.Frames.NativeAvailable(item[1]) then
            local control = checkbox(page, item[2], item[1], row, Murgle.Frames.ApplyAll, "frames")
            control:SetPoint("TOPLEFT", 0, -296 - (row - 1) * 25)
            checks[item[1]] = control
        end
    end
    function page:Refresh()
        for key, control in pairs(checks) do
            control:SetChecked(MurgleDB.frames[key] == true)
        end
        for key, modes in pairs(captions) do
            for mode, caption in pairs(modes) do
                setSelected(caption, MurgleDB.frames[key] == mode)
            end
        end
    end
    return page
end

local pageFactories = {
    Frames = framesPage,
    Interface = function()
        return interfacePage()
    end,
    Minimap = function()
        return minimapPage()
    end,
    Quests = function()
        local page = newPage(L.CATEGORY_QUESTS)
        local sparkles = checkbox(page, L.QUEST_SPARKLES, "sparkles", 1, Murgle.Quests.ApplyAll, "quests")
        local note = label(page, L.QUEST_SPARKLES_NOTE)
        note:SetPoint("TOPLEFT", 0, -66)
        note:SetSize(410, 32)
        helpButton(page, function()
            return Murgle.Quests.SparklesAvailable() and L.QUEST_SPARKLES_HELP or L.QUEST_SPARKLES_UNAVAILABLE
        end, sparkles.caption)
        local reputation =
            checkbox(page, L.AUTO_WATCH_REPUTATION, "autoWatchReputation", 5, Murgle.Quests.ApplyAll, "quests")
        local reputationNote = label(page, L.AUTO_WATCH_REPUTATION_NOTE)
        reputationNote:SetPoint("TOPLEFT", 0, -208)
        reputationNote:SetSize(410, 32)
        helpButton(page, function()
            return Murgle.Quests.ReputationAvailable() and L.AUTO_WATCH_REPUTATION_HELP
                or L.AUTO_WATCH_REPUTATION_UNAVAILABLE
        end, reputation.caption)
        function page:Refresh()
            reputation:SetChecked(MurgleDB.quests.autoWatchReputation == true)
            local reputationAvailable = Murgle.Quests.ReputationAvailable()
            reputation:EnableMouse(reputationAvailable == true)
            sparkles:SetChecked(MurgleDB.quests.sparkles == true)
            local available = Murgle.Quests.SparklesAvailable()
            sparkles:EnableMouse(available)
        end
        return page
    end,
    Automation = function()
        return automationPage()
    end,
    LootVendors = function()
        return lootVendorsPage()
    end,
    Chat = function()
        return chatPage()
    end,
    Tooltip = function()
        return tooltipPage()
    end,
    ErrorsSound = function()
        return errorsPage()
    end,
}

function Settings.SelectCategory(name)
    if not window or not pageFactories[name] then
        return
    end
    if pages[selected] then
        pages[selected]:Hide()
    end
    selected = name
    if not pages[name] then
        pages[name] = pageFactories[name]()
    end
    pages[name]:Show()
    if pages[name].Refresh then
        pages[name]:Refresh()
    end
    for key, text in pairs(navigation) do
        setSelected(text, key == name)
    end
end

local function setPageFeatures(enabled)
    local page = pages[selected]
    if not page then
        return
    end
    local apply = {}
    for _, item in ipairs(page.toggles or {}) do
        MurgleDB[item.category][item.key] = enabled
        apply[item.apply] = true
    end
    for callback in pairs(apply) do
        callback()
    end
    if page.Refresh then
        page:Refresh()
    end
end

local function createWindow()
    window = CreateFrame("Frame", "MurgleSettingsFrame", UIParent)
    window:SetSize(650, 470)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetSize(550, 54)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        window:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
    end)
    window:SetScript("OnHide", function()
        window:StopMovingOrSizing()
    end)
    local background = window:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(window)
    background:SetColorTexture(unpack(COLORS.background))
    local icon = window:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", 18, -16)
    icon:SetTexture("Interface\\AddOns\\Murgle\\Media\\MurgleIcon.tga")
    local title = label(window, L.TITLE, 22)
    title:SetPoint("TOPLEFT", 60, -21)
    local close = button(window, L.CLOSE, 74, Settings.Hide)
    close:SetPoint("TOPRIGHT", -16, -16)
    local reset = button(window, L.RESET, 120, Settings.ConfirmReset)
    reset:SetSize(120, 26)
    reset:SetPoint("BOTTOMLEFT", 18, 18)
    content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", 202, -70)
    content:SetSize(430, 325)
    local enable = button(content, L.ENABLE_ALL, 112, function()
        setPageFeatures(true)
    end)
    enable:SetSize(112, 26)
    enable:SetPoint("TOPRIGHT", -120, 4)
    local disable = button(content, L.DISABLE_ALL, 112, function()
        setPageFeatures(false)
    end)
    disable:SetSize(112, 26)
    disable:SetPoint("TOPRIGHT", 0, 4)
    local panel = window:CreateTexture(nil, "BACKGROUND")
    panel:SetPoint("TOPLEFT", 194, -60)
    panel:SetSize(440, 345)
    panel:SetColorTexture(unpack(COLORS.panel))

    local function addNavigation(name, titleText, row)
        local control, text = button(window, titleText, 166, function()
            Settings.SelectCategory(name)
        end)
        control:SetSize(166, 28)
        control:SetPoint("TOPLEFT", 18, -66 - (row - 1) * 30)
        navigation[name] = text
    end
    addNavigation("Interface", L.CATEGORY_INTERFACE, 1)
    addNavigation("Minimap", L.CATEGORY_MINIMAP, 2)
    addNavigation("Automation", L.CATEGORY_AUTOMATION, 3)
    addNavigation("LootVendors", L.CATEGORY_LOOT_VENDORS, 4)
    addNavigation("Chat", L.CATEGORY_CHAT, 5)
    addNavigation("Tooltip", L.CATEGORY_TOOLTIP, 6)
    addNavigation("ErrorsSound", L.CATEGORY_ERRORS_SOUND, 7)
    addNavigation("Quests", L.CATEGORY_QUESTS, 8)
    addNavigation("Frames", L.CATEGORY_FRAMES, 9)
    UISpecialFrames[#UISpecialFrames + 1] = "MurgleSettingsFrame"
    Settings.SelectCategory(selected)
end

function Settings.Show()
    if not window then
        createWindow()
    end
    window:Show()
end

function Settings.Hide()
    if window then
        window:Hide()
    end
end

function Settings.Toggle()
    if window and window:IsShown() then
        Settings.Hide()
    else
        Settings.Show()
    end
end

function Settings.ConfirmReset()
    if not StaticPopupDialogs.MURGLE_RESET then
        StaticPopupDialogs.MURGLE_RESET = {
            text = L.RESET_CONFIRM,
            button1 = L.RESET,
            button2 = L.CANCEL,
            OnAccept = function()
                Murgle.ResetDB()
                for _, page in pairs(pages) do
                    if page.Refresh then
                        page:Refresh()
                    end
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end
    StaticPopup_Show("MURGLE_RESET")
end
