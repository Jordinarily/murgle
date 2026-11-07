local H = dofile("tests/helpers.lua")
local function setup(fn)
    local s = {
        bindings = { MOUSEWHEELUP = "MINIMAPZOOMIN", MOUSEWHEELDOWN = "MINIMAPZOOMOUT" },
        values = {
            raidFramesDisplayDebuffs = "0",
            raidFramesDisplayOnlyDispellableDebuffs = "1",
            raidFramesDispelIndicatorType = "2",
        },
        writes = 0,
        saves = 0,
    }
    H.withGlobals({
        InCombatLockdown = function()
            return s.combat == true
        end,
        GetBindingAction = function(key, overrides)
            return overrides and s.override or s.bindings[key] or ""
        end,
        SetBinding = function(key, command)
            s.writes = s.writes + 1
            if key == s.rejectKey and command == "CAMERAZOOMOUT" then
                return false
            end
            s.bindings[key] = command
            return true
        end,
        GetCurrentBindingSet = function()
            return 2
        end,
        SaveBindings = function(set)
            eq(set, 2)
            s.saves = s.saves + 1
        end,
        C_KeyBindings = {
            GetBindingContextForAction = function()
                return nil
            end,
        },
        SettingsPanel = {
            IsShown = function()
                return s.settingsShown == true
            end,
        },
        C_CVar = {
            GetCVarInfo = function(name)
                return s.values[name], nil, nil, nil, s.locked == name, false, false
            end,
            SetCVar = function(name, value)
                s.writes = s.writes + 1
                if s.rejectCVar ~= name then
                    s.values[name] = value
                end
            end,
        },
        Enum = { RaidDispelDisplayType = { DispellableByMe = 1 } },
    }, function()
        local M = {}
        H.loadAddonFile("Modules/NativeTools.lua", M)
        eq(s.writes, 0)
        fn(M.NativeTools, s)
    end)
end

test("camera repair is explicit and saves only verified camera wheel bindings", function()
    setup(function(T, s)
        local up, down, state = T.CameraBindings()
        eq(up, "MINIMAPZOOMIN")
        eq(down, "MINIMAPZOOMOUT")
        eq(state, "repairable")
        eq(s.writes, 0)
        eq(T.RestoreCamera(), "done")
        eq(s.bindings.MOUSEWHEELUP, "CAMERAZOOMIN")
        eq(s.bindings.MOUSEWHEELDOWN, "CAMERAZOOMOUT")
        eq(s.saves, 1)
        local _, _, result = T.CameraBindings()
        eq(result, "camera")
        eq(T.RestoreCamera(), "camera")
        eq(s.saves, 1)
    end)
end)
test("camera repair preserves custom assignments overrides combat and native settings edits", function()
    setup(function(T, s)
        s.bindings.MOUSEWHEELUP = "ACTIONBUTTON1"
        eq(T.RestoreCamera(), "custom")
        s.bindings.MOUSEWHEELUP = "MINIMAPZOOMIN"
        s.override = "ACTIONBUTTON2"
        eq(T.RestoreCamera(), "override")
        s.override = nil
        s.combat = true
        eq(T.RestoreCamera(), "combat")
        s.combat = false
        s.settingsShown = true
        eq(T.RestoreCamera(), "settings")
        eq(s.writes, 0)
        eq(s.saves, 0)
    end)
end)
test("camera repair rolls back partial failure and never saves it", function()
    setup(function(T, s)
        s.rejectKey = "MOUSEWHEELDOWN"
        eq(T.RestoreCamera(), "failed")
        eq(s.bindings.MOUSEWHEELUP, "MINIMAPZOOMIN")
        eq(s.bindings.MOUSEWHEELDOWN, "MINIMAPZOOMOUT")
        eq(s.saves, 0)
    end)
end)
test("camera repair handles unbound wheels and refuses missing binding APIs", function()
    setup(function(T, s)
        s.bindings = {}
        eq(T.RestoreCamera(), "done")
        eq(s.saves, 1)
        SetBinding = nil
        eq(T.RestoreCamera(), "unavailable")
    end)
end)
test("dispel setup uses native indicators and keeps other debuffs visible", function()
    setup(function(T, s)
        eq(T.ConfigureDispels(), "done")
        eq(s.values.raidFramesDisplayDebuffs, "1")
        eq(s.values.raidFramesDisplayOnlyDispellableDebuffs, "0")
        eq(s.values.raidFramesDispelIndicatorType, "1")
        eq(s.saves, 0)
        eq(T.ConfigureDispels(), "done")
        eq(s.writes, 3)
    end)
end)
test("dispel setup preflights all native settings and refuses combat missing or protected values", function()
    setup(function(T, s)
        s.combat = true
        eq(T.ConfigureDispels(), "combat")
        s.combat = false
        s.locked = "raidFramesDispelIndicatorType"
        eq(T.ConfigureDispels(), "unavailable")
        s.locked = nil
        s.values.raidFramesDispelIndicatorType = nil
        eq(T.ConfigureDispels(), "unavailable")
        eq(s.writes, 0)
    end)
end)
test("dispel setup restores previous preferences after a rejected native write", function()
    setup(function(T, s)
        s.rejectCVar = "raidFramesDispelIndicatorType"
        eq(T.ConfigureDispels(), "failed")
        eq(s.values.raidFramesDisplayDebuffs, "0")
        eq(s.values.raidFramesDisplayOnlyDispellableDebuffs, "1")
        eq(s.values.raidFramesDispelIndicatorType, "2")
    end)
end)

test("native panel shortcuts select sourced categories and refuse combat or missing panels", function()
    local opened = {}
    H.withGlobals({
        InCombatLockdown = function()
            return false
        end,
        RAID_FRAMES_LABEL = "Raid frames",
        BINDING_HEADER_CAMERA = "Camera",
        Settings = {
            INTERFACE_CATEGORY_ID = 7,
            KEYBINDINGS_CATEGORY_ID = 8,
            OpenToCategory = function(category, scroll)
                opened[#opened + 1] = { category, scroll }
            end,
        },
        EditModeManagerFrame = {
            CanEnterEditMode = function()
                return true
            end,
        },
        ShowUIPanel = function(frame)
            eq(frame, EditModeManagerFrame)
            opened[#opened + 1] = { "edit" }
        end,
        ToggleClickBindingFrame = function()
            opened[#opened + 1] = { "casting" }
        end,
    }, function()
        local M = {}
        H.loadAddonFile("Modules/NativeTools.lua", M)
        local T = M.NativeTools
        eq(T.OpenPanel("raid"), "opened")
        eq(opened[1][1], 7)
        eq(opened[1][2], "Raid frames")
        eq(T.OpenPanel("bindings"), "opened")
        eq(opened[2][1], 8)
        eq(opened[2][2], "Camera")
        eq(T.OpenPanel("edit"), "opened")
        eq(T.OpenPanel("casting"), "opened")
        eq(T.OpenPanel("unknown"), "unavailable")
        InCombatLockdown = function()
            return true
        end
        eq(T.OpenPanel("raid"), "combat")
        eq(#opened, 4)
        InCombatLockdown = function()
            return false
        end
        Settings.INTERFACE_CATEGORY_ID = nil
        eq(T.OpenPanel("raid"), "unavailable")
        EditModeManagerFrame.CanEnterEditMode = function()
            return false
        end
        eq(T.OpenPanel("edit"), "unavailable")
        eq(#opened, 4)
    end)
end)

local UI = dofile("tests/ui_helpers.lua")
test("native setup page is read-only on entry and hides its controls on navigation", function()
    setup(function(_, s)
        UI.withAddon(function(M, state)
            M.Settings.Show()
            M.Settings.SelectCategory("NativeSetup")
            eq(type(M.L.CAMERA_RESTORE), "string")
            local restore, configure
            for _, frame in ipairs(state.frames) do
                if frame.kind == "Button" then
                    for _, region in ipairs(frame.regions) do
                        if region.text == M.L.CAMERA_RESTORE then
                            restore = frame
                        end
                        if region.text == M.L.DISPEL_SETUP then
                            configure = frame
                        end
                    end
                end
            end
            assert(restore, "camera repair button required")
            assert(configure, "dispel setup button required")
            eq(s.writes, 0)
            restore.scripts.OnClick(restore)
            eq(s.saves, 1)
            configure.scripts.OnClick(configure)
            eq(s.values.raidFramesDispelIndicatorType, "1")
            local page = restore.parent
            M.Settings.SelectCategory("Items")
            eq(page:IsShown(), false)
            M.Settings.SelectCategory("NativeSetup")
            eq(page:IsShown(), true)
        end, function()
            Enum = { RaidDispelDisplayType = { DispellableByMe = 1 } }
        end)
    end)
end)
