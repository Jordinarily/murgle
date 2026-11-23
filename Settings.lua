local _, Murgle = ...
local L = Murgle.L
local Settings = {}
Murgle.Settings = Settings

-- Forever eac30af: Blizzard_Settings_Shared/{Blizzard_Settings,
-- Blizzard_Setting,Blizzard_SettingControls,Blizzard_SettingsInbound}.lua.
-- These register native list initializers; Blizzard creates visible controls.
local native, root, loading
local variables, initializers, parents = {}, {}, {}
local function defaulting()
    return SettingsPanel
        and type(SettingsPanel.CheckIsSettingDefaults) == "function"
        and SettingsPanel:CheckIsSettingDefaults() == true
end
local function condition(initializer, predicate)
    if not predicate then
        return
    end
    local parent = parents[predicate]
    if parent and initializers[parent] then
        initializer:SetParentInitializer(initializers[parent], predicate)
    else
        initializer:AddModifyPredicate(predicate)
    end
end
local required = {
    "RegisterVerticalLayoutCategory",
    "RegisterVerticalLayoutSubcategory",
    "RegisterAddOnCategory",
    "RegisterProxySetting",
    "CreateCheckbox",
    "CreateDropdown",
    "CreateSlider",
    "CreateSliderOptions",
    "CreateControlTextContainer",
    "OpenToCategory",
    "NotifyUpdate",
}
local function available()
    local api = _G.Settings
    if type(api) ~= "table" then
        return false
    end
    for _, key in ipairs(required) do
        if type(api[key]) ~= "function" then
            return false
        end
    end
    return type(CreateSettingsListSectionHeaderInitializer) == "function"
        and type(CreateSettingsButtonInitializer) == "function"
end
local function apply(module, method)
    return function()
        Murgle[module][method or "ApplyAll"]()
    end
end
local function proxy(category, group, key, kind, name, default, get, set)
    local variable = "Murgle_" .. group .. "_" .. key
    local setting = native.RegisterProxySetting(category, variable, kind, name, default, get, set)
    variables[#variables + 1] = variable
    return setting
end
local function header(layout, name, help)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name, help))
end
local function action(layout, name, text, fn, help, predicate)
    local initializer = CreateSettingsButtonInitializer(name, text, function()
        if not predicate or predicate() then
            fn()
            Settings.Refresh()
        end
    end, help, true)
    condition(initializer, predicate)
    layout:AddInitializer(initializer)
    return initializer
end
local function help(group, key)
    if key == "AUTO_WORLD_REFRESH" then
        return L.WORLD_REFRESH_SCOPE_NOTE .. "\n" .. L.WORLD_REFRESH_HARDCORE_NOTE
    elseif key == "CHAT_TABS" then
        return L.CHAT_TABS_MOUSEOVER_NOTE .. "\n" .. L.CHAT_TABS_HIDE_NOTE
    elseif group == "sound" then
        return L.SOUND_HELP
    end
    return L[key .. "_HELP"] or L[key]
end
local function toggle(category, group, key, labelKey, callback, predicate)
    local name = L[labelKey]
    local setting = proxy(category, group, key, "boolean", name, Murgle.DEFAULTS[group][key], function()
        return MurgleDB[group][key] == true
    end, function(value)
        if predicate and not predicate() and not defaulting() then
            return
        end
        MurgleDB[group][key] = value
        callback()
    end)
    local initializer = native.CreateCheckbox(category, setting, help(group, labelKey))
    condition(initializer, predicate)
    initializers[group .. "_" .. key] = initializer
    return initializer
end
local function choice(category, group, key, labelKey, choices, callback, predicate)
    local default = Murgle.DEFAULTS[group][key]
    local stringValue = type(default) == "string"
    local kind = type(default)
    local setting = proxy(category, group, key, kind, L[labelKey], default, function()
        local value = MurgleDB[group][key]
        return stringValue and tostring(value) or value
    end, function(value)
        if predicate and not predicate() and not defaulting() then
            return
        end
        for _, item in ipairs(choices) do
            if value == (stringValue and tostring(item[1]) or item[1]) then
                MurgleDB[group][key] = item[1]
                callback()
                return
            end
        end
    end)
    local function options()
        local container = native.CreateControlTextContainer()
        for _, item in ipairs(choices) do
            container:Add(stringValue and tostring(item[1]) or item[1], item[2])
        end
        return container:GetData()
    end
    local initializer = native.CreateDropdown(category, setting, options, help(group, labelKey))
    condition(initializer, predicate)
    initializers[group .. "_" .. key] = initializer
    return initializer
end
local function parentEnabled(group, key, expected)
    if expected == nil then
        expected = true
    end
    local predicate = function()
        return MurgleDB[group][key] == expected
    end
    parents[predicate] = group .. "_" .. key
    return predicate
end
local function buildGeneral(category, layout)
    header(layout, L.SECTION_GENERAL)
    for _, item in ipairs({
        { "hideMicroMenu", "HIDE_MICRO_MENU", "ApplyMicroMenu" },
        { "hideBagBar", "HIDE_BAG_BAR", "ApplyBagBar" },
        { "hideStatusBar1", "HIDE_STATUS_BAR_1", "ApplyStatusBar1" },
        { "hideXP", "HIDE_XP", "ApplyXP" },
        { "hideZoneText", "HIDE_ZONE_TEXT", "ApplyZoneText" },
        { "hideBossBanner", "HIDE_BOSS_BANNER", "ApplyBossBanner" },
        { "hideTalkingHead", "HIDE_TALKING_HEAD", "ApplyTalkingHead" },
    }) do
        toggle(category, "interface", item[1], item[2], apply("Interface", item[3]))
    end
    toggle(category, "interface", "buffTriangleMouseover", "BUFF_TRIANGLE_HOVER", apply("Buffs"))
    toggle(category, "interface", "moveBags", "MOVE_BAGS", apply("Bags"))
    action(layout, L.MOVE_BAGS, L.RESET_BAG_POSITION, Murgle.Bags.ResetPosition)
    header(layout, L.CATEGORY_AUTOMATION, L.WORLD_REFRESH_SCOPE_NOTE)
    toggle(category, "automation", "autoWorldRefresh", "AUTO_WORLD_REFRESH", apply("Automation"))
    choice(category, "automation", "worldRefreshMode", "AUTO_WORLD_REFRESH", {
        { "hideOnly", L.WORLD_REFRESH_HIDE_ONLY },
        { "acceptAndHide", L.WORLD_REFRESH_ACCEPT_HIDE },
    }, apply("Automation"), parentEnabled("automation", "autoWorldRefresh"))
    action(layout, L.AUTO_WORLD_REFRESH, L.APPLY_WORLD_REFRESH, Murgle.Automation.ApplyWorldRefresh)
end
local function buildCombat(category, layout)
    header(layout, L.SPELL_QUEUE, L.SPELL_QUEUE_HELP)
    local function queueAvailable()
        return Murgle.Interface.GetSpellQueueWindow() ~= nil
    end
    local queue = proxy(category, "interface", "spellQueueWindow", "number", L.SPELL_QUEUE, 400, function()
        return Murgle.Interface.GetSpellQueueWindow() or 400
    end, Murgle.Interface.SetSpellQueueWindow)
    local queueOptions = native.CreateSliderOptions(0, 400, 10)
    queueOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return string.format("%d ms", value)
    end)
    native.CreateSlider(category, queue, queueOptions, L.SPELL_QUEUE_HELP):AddModifyPredicate(queueAvailable)
    action(
        layout,
        L.SPELL_QUEUE,
        L.SPELL_QUEUE_AUTO,
        Murgle.Interface.AutoDetectSpellQueueWindow,
        L.SPELL_QUEUE_HELP,
        queueAvailable
    )
    header(layout, L.CATEGORY_FRAMES)
    toggle(category, "frames", "hidePlayerName", "HIDE_PLAYER_NAME", apply("Frames", "ApplyPlayerName"))
    toggle(category, "frames", "hidePlayerFrame", "HIDE_PLAYER_FRAME", apply("Frames", "ApplyPlayerFrame"))
    toggle(category, "frames", "compactFrames", "COMPACT_FRAMES", apply("Frames", "ApplyCompact"))
end
local function buildMap(category, layout)
    header(layout, L.CATEGORY_MINIMAP)
    toggle(category, "minimap", "cleanSquare", "CLEAN_SQUARE_MINIMAP", apply("Minimap", "ApplyCleanSquare"))
    toggle(category, "minimap", "hideClock", "HIDE_CLOCK", apply("Minimap", "ApplyClock"))
    toggle(category, "minimap", "hideTracking", "HIDE_TRACKING", apply("Minimap", "ApplyTracking"))
    header(layout, L.CATEGORY_QUESTS)
    toggle(
        category,
        "interface",
        "objectiveTrackerHeaders",
        "TRACKER_HEADERS",
        apply("Interface", "ApplyTrackerHeaders")
    )
    choice(category, "interface", "objectiveTrackerVisibility", "TRACKER_VISIBILITY", {
        { "always", L.ALWAYS },
        { "ooc", L.OUT_OF_COMBAT },
        { "hidden", L.HIDDEN },
    }, apply("Interface", "ApplyTrackerVisibility"))
    local sparklesAvailable = function()
        return Murgle.Quests.SparklesAvailable()
    end
    local sparkles = toggle(category, "quests", "sparkles", "QUEST_SPARKLES", apply("Quests"), sparklesAvailable)
    condition(sparkles, sparklesAvailable)
    toggle(category, "quests", "rewardValues", "REWARD_VALUES", apply("Rewards"))
    toggle(category, "automation", "autoQuest", "AUTO_QUEST", apply("Automation"))
    toggle(category, "automation", "autoTurnIn", "AUTO_TURN_IN", apply("Automation"))
end
local function buildItems(category, layout)
    header(layout, L.CATEGORY_ITEMS)
    toggle(category, "lootVendors", "fastLoot", "FAST_LOOT", apply("LootVendors"))
    toggle(category, "lootVendors", "ammoCount", "AMMO_COUNT", apply("Ammo"))
    toggle(category, "automation", "confirmLootPickup", "CONFIRM_LOOT_PICKUP", apply("Interactions"))
    toggle(category, "automation", "confirmLootRolls", "CONFIRM_LOOT_ROLLS", apply("Interactions"))
    header(layout, L.SECTION_SERVICES)
    toggle(category, "lootVendors", "autoRepair", "AUTO_REPAIR", apply("LootVendors"))
    toggle(
        category,
        "lootVendors",
        "guildRepair",
        "GUILD_REPAIR",
        apply("LootVendors"),
        parentEnabled("lootVendors", "autoRepair")
    )
    toggle(category, "lootVendors", "sellJunk", "SELL_JUNK", apply("LootVendors"))
    toggle(category, "lootVendors", "bulkBuy", "BULK_BUY", apply("Commerce"))
    toggle(category, "automation", "trainAll", "TRAIN_ALL", apply("Trainer"))
    toggle(category, "automation", "skipServiceGossip", "SKIP_SERVICE_GOSSIP", apply("Interactions"))
end
local function buildChat(category, layout)
    header(layout, L.CATEGORY_CHAT)
    toggle(category, "chat", "cleanChat", "CLEAN_CHAT_FRAME", apply("Chat", "ApplyCleanChat"))
    toggle(category, "chat", "hideCombatLog", "HIDE_COMBAT_LOG", apply("Chat", "ApplyCombatLog"))
    choice(category, "chat", "tabs", "CHAT_TABS", {
        { "show", L.CHAT_DEFAULT },
        { "mouseover", L.CHAT_FADE },
        { "hide", L.CHAT_HIDE },
    }, apply("Chat", "ApplyTabs"))
    header(layout, L.CATEGORY_TOOLTIP)
    toggle(category, "tooltip", "cursorAnchor", "CURSOR_ANCHOR", apply("Tooltip", "ApplyCursorAnchor"))
    choice(category, "tooltip", "anchor", "CURSOR_ANCHOR", {
        { "left", L.CURSOR_LEFT },
        { "right", L.CURSOR_RIGHT },
        { "cursor", L.CURSOR_AT },
    }, apply("Tooltip", "ApplyCursorAnchor"), parentEnabled("tooltip", "cursorAnchor"))
    toggle(category, "tooltip", "hideInCombat", "COMBAT_TOOLTIP_HIDE", apply("Tooltip", "ApplyCombatHide"))
end
local function buildSound(category, layout)
    header(layout, L.SECTION_ERRORS, L.ERROR_SCOPE_NOTE)
    choice(
        category,
        "errors",
        "mode",
        "SECTION_ERRORS",
        { { "all", L.ALL }, { "important", L.IMPORTANT } },
        apply("Errors")
    )
    header(layout, L.SECTION_SOUND, L.SOUND_HELP)
    for _, item in ipairs({
        { "muteFizzle", "MUTE_FIZZLE" },
        { "muteErrorSpeech", "MUTE_ERROR_SPEECH" },
        { "muteTrains", "MUTE_TRAINS" },
        { "muteMechanicalSteps", "MUTE_MECHANICAL_STEPS" },
        { "muteFootsteps", "MUTE_FOOTSTEPS" },
        { "muteHooves", "MUTE_HOOVES" },
        { "muteChimes", "MUTE_CHIMES" },
        { "muteInterface", "MUTE_INTERFACE" },
        { "muteReadyCheck", "MUTE_READY_CHECK" },
        { "muteCatYawns", "MUTE_CAT_YAWNS" },
        { "mutePiccolo", "MUTE_PICCOLO" },
        { "muteMechanostriders", "MUTE_MECHANOSTRIDERS" },
        { "muteZeppelins", "MUTE_ZEPPELINS" },
    }) do
        toggle(category, "sound", item[1], item[2], apply("Sound"))
    end
end
function Settings.Refresh()
    if native and native.NotifyUpdate then
        for _, variable in ipairs(variables) do
            native.NotifyUpdate(variable)
        end
    end
end
function Settings.Initialize()
    if root then
        return true
    end
    if not available() then
        if not loading then
            loading = CreateFrame("Frame")
            loading:SetScript("OnEvent", function()
                Settings.Initialize()
            end)
            loading:RegisterEvent("ADDON_LOADED")
        end
        return false
    end
    if loading then
        loading:UnregisterEvent("ADDON_LOADED")
    end
    native = _G.Settings
    local layout
    root, layout = native.RegisterVerticalLayoutCategory(L.TITLE)
    buildGeneral(root, layout)
    for _, item in ipairs({
        { L.SECTION_COMBAT, buildCombat },
        { L.SECTION_MAP, buildMap },
        { L.SECTION_ITEMS, buildItems },
        { L.SECTION_CHAT, buildChat },
        { L.CATEGORY_ERRORS_SOUND, buildSound },
    }) do
        local category, sublayout = native.RegisterVerticalLayoutSubcategory(root, item[1])
        item[2](category, sublayout)
    end
    native.RegisterAddOnCategory(root)
    return true
end
function Settings.Show()
    if Settings.Initialize() then
        native.OpenToCategory(root:GetID())
    end
end
Settings.Toggle = Settings.Show

function Settings.ConfirmReset()
    if not StaticPopupDialogs.MURGLE_RESET then
        StaticPopupDialogs.MURGLE_RESET = {
            text = L.RESET_CONFIRM,
            button1 = L.RESET,
            button2 = L.CANCEL,
            OnAccept = function()
                Murgle.ResetDB()
                Settings.Refresh()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end
    StaticPopup_Show("MURGLE_RESET")
end
