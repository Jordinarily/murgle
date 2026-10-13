local addonName, Murgle = ...
_G.Murgle = Murgle

local frame = CreateFrame("Frame")
local pending = {}
local pendingCount = 0
local initialized = false

function Murgle.ParseCommand(message)
    local command = string.lower(string.match(message or "", "^%s*(.-)%s*$"))
    if command == "" then
        return "toggle"
    elseif command == "reset" or command == "r" then
        return "reset"
    elseif command == "version" or command == "v" then
        return "version"
    end
    return "unknown"
end

function Murgle.GetVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"
    end
    return "1.0.0"
end

function Murgle.GetDeferredCount()
    return pendingCount
end

function Murgle.DeferUntilOutOfCombat(key, fn)
    if InCombatLockdown() then
        if pending[key] == nil then
            pendingCount = pendingCount + 1
        end
        pending[key] = fn
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    -- A newer safe change supersedes an older request awaiting the regen event.
    if pending[key] then
        pending[key] = nil
        pendingCount = pendingCount - 1
    end
    if pendingCount == 0 then
        frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    fn()
end

local function drainPending()
    while pendingCount > 0 and not InCombatLockdown() do
        local key, fn = next(pending)
        pending[key] = nil
        pendingCount = pendingCount - 1
        -- Remove before invoking: a failed change must not leave an idle event
        -- registered, retry forever, or prevent unrelated changes from applying.
        if pendingCount == 0 then
            frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
        local ok, err = pcall(fn)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

function Murgle.ApplyAllSettings()
    if Murgle.Interface then
        Murgle.Interface.ApplyAll()
    end
    if Murgle.Minimap then
        Murgle.Minimap.ApplyAll()
    end
    if Murgle.Frames then
        Murgle.Frames.ApplyAll()
    end
    if Murgle.Buffs then
        Murgle.Buffs.ApplyAll()
    end
    if Murgle.Quests then
        Murgle.Quests.ApplyAll()
    end
    if Murgle.Automation then
        Murgle.Automation.ApplyAll()
    end
    if Murgle.LootVendors then
        Murgle.LootVendors.ApplyAll()
    end
    if Murgle.Chat then
        Murgle.Chat.ApplyAll()
    end
    if Murgle.Tooltip then
        Murgle.Tooltip.ApplyAll()
    end
    if Murgle.Errors then
        Murgle.Errors.ApplyAll()
    end
    if Murgle.Sound then
        Murgle.Sound.ApplyAll()
    end
end

function Murgle.ResetDB()
    MurgleDB = Murgle.ApplyDefaults({})
    if Murgle.Interface and Murgle.Interface.SetSpellQueueWindow then
        Murgle.Interface.SetSpellQueueWindow(400)
    end
    Murgle.ApplyAllSettings()
end

local function slashCommand(message)
    local command = Murgle.ParseCommand(message)
    if command == "version" then
        print("Murgle " .. Murgle.GetVersion())
    elseif command == "toggle" and Murgle.Settings then
        Murgle.Settings.Toggle()
    elseif command == "reset" and Murgle.Settings then
        Murgle.Settings.ConfirmReset()
    else
        print(Murgle.L and Murgle.L.COMMAND_HELP or "/murgle, /murgle r|reset, /murgle v|version")
    end
end

local function registerReloadAlias()
    if type(ReloadUI) ~= "function" or SlashCmdList.MURGLERELOAD or SLASH_MURGLERELOAD1 then
        return
    end
    if type(IsSecureCmd) == "function" and IsSecureCmd("/rl") then
        return
    end
    if type(hash_SlashCmdList) == "table" and hash_SlashCmdList["/RL"] then
        return
    end
    -- The native command cache may not have consumed another addon's aliases yet.
    for key in pairs(SlashCmdList) do
        if type(key) == "string" then
            local index = 1
            local alias = _G["SLASH_" .. key .. index]
            while type(alias) == "string" do
                if string.lower(alias) == "/rl" then
                    return
                end
                index = index + 1
                alias = _G["SLASH_" .. key .. index]
            end
        end
    end
    SLASH_MURGLERELOAD1 = "/rl"
    SlashCmdList.MURGLERELOAD = ReloadUI
end

function Murgle.Initialize()
    if initialized then
        return
    end
    initialized = true
    frame:UnregisterEvent("ADDON_LOADED")
    MurgleDB = Murgle.ApplyDefaults(MurgleDB)
    if Murgle.Interface then
        Murgle.Interface.Initialize()
    end
    if Murgle.Minimap then
        Murgle.Minimap.Initialize()
    end
    if Murgle.Frames then
        Murgle.Frames.Initialize()
    end
    if Murgle.Buffs then
        Murgle.Buffs.Initialize()
    end
    if Murgle.Quests then
        Murgle.Quests.Initialize()
    end
    if Murgle.Automation then
        Murgle.Automation.Initialize()
    end
    if Murgle.LootVendors then
        Murgle.LootVendors.Initialize()
    end
    if Murgle.Chat then
        Murgle.Chat.Initialize()
    end
    if Murgle.Tooltip then
        Murgle.Tooltip.Initialize()
    end
    if Murgle.Errors then
        Murgle.Errors.Initialize()
    end
    if Murgle.Sound then
        Murgle.Sound.Initialize()
    end
    SLASH_MURGLE1 = "/murgle"
    SlashCmdList.MURGLE = slashCommand
    registerReloadAlias()
end

frame:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon == addonName then
        Murgle.Initialize()
    elseif event == "PLAYER_REGEN_ENABLED" then
        drainPending()
    end
end)
frame:RegisterEvent("ADDON_LOADED")
