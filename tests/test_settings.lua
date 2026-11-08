local UI = dofile("tests/ui_helpers.lua")
local H = dofile("tests/helpers.lua")

test("native Settings registers six sections once without constructing controls", function()
    UI.withAddon(function(M, s)
        eq(#s.categories, 6)
        eq(s.categories[1].name, "Murgle")
        local names = { "Combat & Frames", "Map & Quests", "Items & Services", "Chat & Tooltips", "Errors & Sound" }
        for i, name in ipairs(names) do
            eq(s.categories[i + 1].name, name)
            eq(s.categories[i + 1].parent, s.categories[1])
        end
        eq(s.addonCategory, s.categories[1])
        eq(s.named.MurgleSettingsFrame, nil)
        local count = #s.frames
        M.Settings.Initialize()
        SlashCmdList.MURGLE("")
        eq(s.openCategory, s.categories[1]:GetID())
        eq(#s.categories, 6)
        eq(#s.frames, count)
        eq(#UISpecialFrames, 0)
    end)
end)

test("native controls cover every current saved primitive without retired options", function()
    UI.withAddon(function(M, s)
        for group, defaults in pairs(M.DEFAULTS) do
            if type(defaults) == "table" then
                for key, value in pairs(defaults) do
                    if type(value) ~= "table" then
                        local setting = s:setting(group, key)
                        eq(setting:GetValue(), MurgleDB[group][key], group .. "." .. key)
                    end
                end
            end
        end
        eq(s.settings.Murgle_lootVendors_openClams, nil)
        eq(s.settings.Murgle_automation_confirmEnchantReplace, nil)
        for _, c in ipairs(s.controls) do
            assert(c.buttonText ~= M.L.ENABLE_ALL and c.buttonText ~= M.L.DISABLE_ALL)
            if c.setting then
                assert(c.help and c.help ~= "")
            end
        end
    end)
end)

test("proxy controls preserve saved choices and resolve replacement DB after reset", function()
    UI.withAddon(function(M, s)
        local old = MurgleDB.interface
        local setting = s:setting("interface", "hideMicroMenu")
        eq(setting:GetValue(), true)
        M.Settings.ConfirmReset()
        eq(MurgleDB.interface, old, "reset must wait for confirmation")
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        assert(MurgleDB.interface ~= old)
        eq(setting:GetValue(), false)
        setting:SetValue(true)
        eq(MurgleDB.interface.hideMicroMenu, true)
        assert(s.notifications > 0)
    end, function()
        MurgleDB = { interface = { hideMicroMenu = true } }
    end)
end)

test("native setter uses only the selected feature apply path", function()
    UI.withAddon(function(M, s)
        local calls = 0
        M.Interface.ApplyMicroMenu = function()
            calls = calls + 1
        end
        M.ApplyAllSettings = function()
            error("blanket apply")
        end
        s:setting("interface", "hideMicroMenu"):SetValue(true)
        eq(calls, 1)
        eq(MurgleDB.interface.hideMicroMenu, true)
        eq(MurgleDB.interface.hideBagBar, false)
    end)
end)

test("native choices reject invalid values and preserve numeric tracker sizes", function()
    UI.withAddon(function(_, s)
        local font = s:setting("interface", "trackerFontSize")
        font:SetValue("10")
        eq(MurgleDB.interface.trackerFontSize, 10)
        eq(font:GetValue(), "10")
        font:SetValue("99")
        eq(MurgleDB.interface.trackerFontSize, 10)
        s:setting("automation", "worldRefreshMode"):SetValue("not-a-mode")
        eq(MurgleDB.automation.worldRefreshMode, "hideOnly")
    end)
end)

test("native controls keep enabled paging disableable and honour dependencies", function()
    UI.withAddon(function(M, s)
        M.ModifierPaging.Available = function()
            return false
        end
        local control = s:control("interface", "holdActionPages")
        eq(control:IsEnabled(), false)
        MurgleDB.interface.holdActionPages = true
        eq(control:IsEnabled(), true)
        s:setting("interface", "holdActionPages"):SetValue(false)
        eq(MurgleDB.interface.holdActionPages, false)
        eq(s:control("lootVendors", "guildRepair"):IsEnabled(), false)
        s:setting("lootVendors", "autoRepair"):SetValue(true)
        eq(s:control("lootVendors", "guildRepair"):IsEnabled(), true)
    end)
end)

test("native setters preserve combat deferral and reset restoration", function()
    local menu = H.newVisibilityFrame(true)
    UI.withAddon(function(M, s)
        s.combat = true
        s:setting("interface", "hideMicroMenu"):SetValue(true)
        eq(menu.shown, true)
        assert(M.GetDeferredCount() > 0)
        s.combat = false
        s.frames[1].scripts.OnEvent(s.frames[1], "PLAYER_REGEN_ENABLED")
        eq(menu.shown, false)
        M.ResetDB()
        eq(menu.shown, true)
    end, function()
        MicroMenu = menu
    end)
end)

test("late native Settings availability registers once and unregisters load listener", function()
    local saved
    UI.withAddon(function(M, s)
        eq(#s.categories, 0)
        Settings = saved
        local listener
        for _, f in ipairs(s.frames) do
            if f.events.ADDON_LOADED then
                listener = f
            end
        end
        assert(listener)
        listener.scripts.OnEvent(listener, "ADDON_LOADED", "Blizzard_Settings")
        eq(#s.categories, 6)
        eq(next(listener.events), nil)
        M.Settings.Initialize()
        eq(#s.categories, 6)
    end, function()
        saved = Settings
        Settings = false
    end)
end)

test("native quest level preference is not reset with addon defaults", function()
    UI.withAddon(function(M, s)
        local value = "1"
        M.NativeOptions.Read = function()
            return value, true
        end
        M.NativeOptions.Set = function(_, v)
            value = v
        end
        local setting = s:setting("native", "showQuestLevel")
        eq(setting:GetValue(), true)
        setting:SetValueToDefault()
        eq(value, "1")
        M.ResetDB()
        eq(value, "1")
    end)
end)

test("native dependent controls subscribe to their parent setting", function()
    UI.withAddon(function(_, s)
        local guild = s:control("lootVendors", "guildRepair")
        assert(guild.parent and guild.parent.setting == s:setting("lootVendors", "autoRepair"))
        local border = s:control("minimap", "hideBorder")
        assert(border.parent and border.parent.setting == s:setting("minimap", "square"))
    end)
end)

test("native Defaults clears saved child choices even when parent is disabled", function()
    UI.withAddon(function(_, s)
        s:setting("lootVendors", "autoRepair"):SetValue(true)
        s:setting("lootVendors", "guildRepair"):SetValue(true)
        s:setting("lootVendors", "autoRepair"):SetValue(false)
        s:setting("lootVendors", "guildRepair"):SetValueToDefault()
        eq(MurgleDB.lootVendors.guildRepair, false)
    end)
end)

test("every native dropdown option has a label and a value matching its setting type", function()
    UI.withAddon(function(_, s)
        for _, control in ipairs(s.controls) do
            if control.kind == "dropdown" then
                for _, option in ipairs(control.options()) do
                    eq(type(option.label), "string")
                    assert(option.label ~= "")
                    eq(type(option.value), control.setting.kind)
                end
            end
        end
    end)
end)

test("removed controls and actions stay absent", function()
    UI.withAddon(function(M, s)
        for _, variable in ipairs({
            "Murgle_lootVendors_markedJunk",
            "Murgle_lootVendors_restock",
            "Murgle_tooltip_spellDetails",
            "Murgle_automation_useQuestStarters",
        }) do
            eq(s.settings[variable], nil)
        end
        for _, control in ipairs(s.controls) do
            for _, text in ipairs({
                M.L.MARK_CURSOR_ITEM,
                M.L.CLEAR_MARKED_ITEMS,
                M.L.SELL_MARKED,
                M.L.CLEAR_RESTOCK,
                M.L.CLICK_CASTING,
                M.L.MUTE_ALL,
                M.L.UNMUTE_ALL,
            }) do
                assert(control.buttonText ~= text)
            end
        end
    end)
end)

test("spell queue slider formats the current value in milliseconds", function()
    UI.withAddon(function(_, s)
        local options = s:control("interface", "spellQueueWindow").options
        local formatter = assert(options.formatters and options.formatters[MinimalSliderWithSteppersMixin.Label.Right])
        eq(formatter(170), "170 ms")
        eq(formatter(400), "400 ms")
        eq(formatter(0), "0 ms")
    end)
end)

test("native refresh and sound choices retain important consequences in hover help", function()
    UI.withAddon(function(M, s)
        local refresh = s:control("automation", "worldRefreshMode")
        assert(refresh.help:find(M.L.WORLD_REFRESH_HARDCORE_NOTE, 1, true))
        local tabs = s:control("chat", "tabs")
        assert(tabs.help:find(M.L.CHAT_TABS_HIDE_NOTE, 1, true))
        assert(s:control("sound", "muteReadyCheck").help:find(M.L.SOUND_HELP, 1, true))
    end)
end)
