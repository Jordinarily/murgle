local _, Murgle = ...
local NativeTools = {}
Murgle.NativeTools = NativeTools

-- Explicit settings actions only: no initialization, events, hooks or saved mirror.
local wheels = { "MOUSEWHEELUP", "MOUSEWHEELDOWN" }
local camera = { "CAMERAZOOMIN", "CAMERAZOOMOUT" }
local safe = { [""] = true, MINIMAPZOOMIN = true, MINIMAPZOOMOUT = true, CAMERAZOOMIN = true, CAMERAZOOMOUT = true }

local function inCombat()
    return type(InCombatLockdown) ~= "function" or InCombatLockdown() ~= false
end

function NativeTools.CameraBindings()
    if type(GetBindingAction) ~= "function" then
        return nil, nil, "unavailable"
    end
    local saved, effective = {}, {}
    for i, key in ipairs(wheels) do
        saved[i], effective[i] = GetBindingAction(key), GetBindingAction(key, true)
        if type(saved[i]) ~= "string" or type(effective[i]) ~= "string" then
            return nil, nil, "unavailable"
        end
    end
    local state = "repairable"
    if saved[1] ~= effective[1] or saved[2] ~= effective[2] then
        state = "override"
    elseif not safe[saved[1]] or not safe[saved[2]] then
        state = "custom"
    elseif saved[1] == camera[1] and saved[2] == camera[2] then
        state = "camera"
    end
    return effective[1], effective[2], state
end

function NativeTools.RestoreCamera()
    if inCombat() then
        return "combat"
    end
    if
        type(SetBinding) ~= "function"
        or type(SaveBindings) ~= "function"
        or type(GetCurrentBindingSet) ~= "function"
        or not C_KeyBindings
        or type(C_KeyBindings.GetBindingContextForAction) ~= "function"
    then
        return "unavailable"
    end
    if SettingsPanel and type(SettingsPanel.IsShown) == "function" and SettingsPanel:IsShown() then
        return "settings"
    end
    local set = GetCurrentBindingSet()
    if set ~= 1 and set ~= 2 then
        return "unavailable"
    end
    for command in pairs(safe) do
        if command ~= "" then
            local context = C_KeyBindings.GetBindingContextForAction(command)
            if context ~= nil and context ~= 0 then
                return "unavailable"
            end
        end
    end
    local up, down, state = NativeTools.CameraBindings()
    if state ~= "repairable" then
        return state
    end
    local previous = { up, down }
    local function rollback()
        for i, key in ipairs(wheels) do
            pcall(SetBinding, key, previous[i] ~= "" and previous[i] or nil)
        end
    end
    for i, key in ipairs(wheels) do
        local ok, accepted = pcall(SetBinding, key, camera[i])
        if not ok or not accepted or GetBindingAction(key) ~= camera[i] then
            rollback()
            return "failed"
        end
    end
    local _, _, result = NativeTools.CameraBindings()
    if result ~= "camera" then
        rollback()
        return "failed"
    end
    local ok = pcall(SaveBindings, set)
    if not ok then
        rollback()
        return "failed"
    end
    return "done"
end

local dispels = {
    { "raidFramesDisplayDebuffs", "1" },
    { "raidFramesDisplayOnlyDispellableDebuffs", "0" },
    { "raidFramesDispelIndicatorType", "1" },
}

function NativeTools.ConfigureDispels()
    if inCombat() then
        return "combat"
    end
    if
        not C_CVar
        or type(C_CVar.GetCVarInfo) ~= "function"
        or type(C_CVar.SetCVar) ~= "function"
        or not Enum
        or not Enum.RaidDispelDisplayType
        or Enum.RaidDispelDisplayType.DispellableByMe ~= 1
    then
        return "unavailable"
    end
    local previous = {}
    for i, entry in ipairs(dispels) do
        local value, _, _, _, locked, secure, readOnly = C_CVar.GetCVarInfo(entry[1])
        local number = type(value) == "string" and tonumber(value)
        if
            not number
            or number < 0
            or number > (i == 3 and 2 or 1)
            or number ~= math.floor(number)
            or locked ~= false
            or secure ~= false
            or readOnly ~= false
        then
            return "unavailable"
        end
        previous[i] = value
    end
    for i, entry in ipairs(dispels) do
        if previous[i] ~= entry[2] then
            local ok = pcall(C_CVar.SetCVar, entry[1], entry[2])
            if not ok or C_CVar.GetCVarInfo(entry[1]) ~= entry[2] then
                for j, original in ipairs(previous) do
                    pcall(C_CVar.SetCVar, dispels[j][1], original)
                end
                return "failed"
            end
        end
    end
    return "done"
end

function NativeTools.OpenPanel(which)
    if inCombat() then
        return "combat"
    end
    if which == "edit" then
        if
            not EditModeManagerFrame
            or type(EditModeManagerFrame.CanEnterEditMode) ~= "function"
            or not EditModeManagerFrame:CanEnterEditMode()
            or type(ShowUIPanel) ~= "function"
        then
            return "unavailable"
        end
        ShowUIPanel(EditModeManagerFrame)
    elseif which == "casting" then
        if type(ToggleClickBindingFrame) ~= "function" then
            return "unavailable"
        end
        ToggleClickBindingFrame()
    else
        if not Settings or type(Settings.OpenToCategory) ~= "function" then
            return "unavailable"
        end
        if which == "raid" and Settings.INTERFACE_CATEGORY_ID and type(RAID_FRAMES_LABEL) == "string" then
            Settings.OpenToCategory(Settings.INTERFACE_CATEGORY_ID, RAID_FRAMES_LABEL)
        elseif which == "bindings" and Settings.KEYBINDINGS_CATEGORY_ID and type(BINDING_HEADER_CAMERA) == "string" then
            Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID, BINDING_HEADER_CAMERA)
        else
            return "unavailable"
        end
    end
    return "opened"
end
