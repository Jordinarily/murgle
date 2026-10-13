local _, Murgle = ...
local Frames = {}
Murgle.Frames = Frames

-- Exact Camelot native controls, not a general CVar ownership service.
local native = {
    enemyNameplates = "nameplateShowEnemies",
    friendlyNameplates = "nameplateShowFriendlyPlayers",
    friendlyNamesOnly = "nameplateShowOnlyNameForFriendlyPlayerUnits",
    -- Retired controls: retain these two identifiers only to release saved ownership.
    enemyClassColours = "nameplateShowClassColor",
    friendlyClassColours = "nameplateShowFriendlyClassColor",
}
local owned, combatFrame
local playerRestore, targetRestore, factionHooked, factionApplied
local statusHooked, statusHiding, nameHooked, levelHooked
local targetOfTargetRestore
local restHooked, restRestore, hiddenName, hiddenNameAlpha

local function nativeValue(key)
    if not C_CVar or type(C_CVar.GetCVarInfo) ~= "function" or type(C_CVar.SetCVar) ~= "function" then
        return
    end
    local value, _, _, _, locked, secure, readOnly = C_CVar.GetCVarInfo(native[key])
    if (value == "0" or value == "1") and locked == false and secure == false and readOnly == false then
        return value
    end
end

function Frames.NativeAvailable(key)
    return key ~= "enemyClassColours"
        and key ~= "friendlyClassColours"
        and native[key] ~= nil
        and nativeValue(key) ~= nil
end

local function applyNative(key, desired)
    local settings = MurgleDB.frames
    local state = owned and owned[key]
    if desired == nil and not state then
        return false
    end
    local current = nativeValue(key)
    if not current then
        return false
    end
    if desired == nil then
        -- A native hotkey or another addon may have taken over since our write.
        if current == state.last and current ~= state.prior then
            C_CVar.SetCVar(native[key], state.prior)
            if nativeValue(key) ~= state.prior then
                return false
            end
        end
        owned[key] = nil
    else
        if not state then
            owned = owned or {}
            state = { prior = current }
            owned[key] = state
        end
        if current ~= desired then
            C_CVar.SetCVar(native[key], desired)
        end
        if nativeValue(key) ~= desired then
            return false
        end
        state.last = desired
    end
    settings.nativeRestore = owned and next(owned) and owned or nil
    return desired ~= nil
end

local function modeValue(mode, combat)
    if mode == "hidden" then
        return "0"
    elseif mode == "combat" then
        return combat and "1" or "0"
    end
end

local function combatChanged(_, event)
    local settings = MurgleDB.frames
    local value = event == "PLAYER_REGEN_DISABLED" and "1" or "0"
    if settings.enemyNameplates == "combat" then
        applyNative("enemyNameplates", value)
    end
    if settings.friendlyNameplates == "combat" then
        applyNative("friendlyNameplates", value)
    end
end

function Frames.ApplyNameplates()
    local settings = MurgleDB.frames
    if not owned and type(settings.nativeRestore) == "table" then
        owned = {}
        for key in pairs(native) do
            local saved = settings.nativeRestore[key]
            if type(saved) == "table" and (saved.prior == "0" or saved.prior == "1") then
                owned[key] = { prior = saved.prior, last = saved.last }
            end
        end
    end
    -- Preserve session ownership across reset even if a native setting is unavailable.
    settings.nativeRestore = owned and next(owned) and owned or nil
    local combat = type(InCombatLockdown) == "function" and InCombatLockdown()
    local enemy = applyNative("enemyNameplates", modeValue(settings.enemyNameplates, combat))
    local friendly = applyNative("friendlyNameplates", modeValue(settings.friendlyNameplates, combat))
    applyNative("friendlyNamesOnly", settings.friendlyNamesOnly == true and "1" or nil)
    applyNative("enemyClassColours", nil)
    applyNative("friendlyClassColours", nil)
    if enemy and settings.enemyNameplates == "combat" or friendly and settings.friendlyNameplates == "combat" then
        if not combatFrame then
            combatFrame = CreateFrame("Frame")
            combatFrame:SetScript("OnEvent", combatChanged)
        end
        combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    elseif combatFrame then
        combatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        combatFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function canHide(region)
    return region
        and type(region.Hide) == "function"
        and type(region.Show) == "function"
        and type(region.IsShown) == "function"
end

local function canAnchor(region)
    return region
        and type(region.GetNumPoints) == "function"
        and type(region.GetPoint) == "function"
        and type(region.ClearAllPoints) == "function"
        and type(region.SetPoint) == "function"
end

local function capturePoints(region)
    local points = {}
    for i = 1, region:GetNumPoints() do
        points[i] = { region:GetPoint(i) }
    end
    return points
end

local function restorePoints(region, points)
    region:ClearAllPoints()
    for _, point in ipairs(points) do
        region:SetPoint(unpack(point))
    end
end

local function restoreClean(saved)
    if saved.status then
        if saved.statusShown then
            saved.status:Show()
        else
            saved.status:Hide()
        end
    end
    if saved.portraitShown then
        saved.portrait:Show()
    else
        saved.portrait:Hide()
    end
    saved.circle:SetAlpha(saved.circleAlpha)
    saved.art:SetAlpha(saved.alpha)
    restorePoints(saved.level, saved.points)
    saved.level:SetFontObject(saved.font)
    saved.name:SetWidth(saved.nameWidth)
    restorePoints(saved.name, saved.namePoints)
    for region, alpha in pairs(saved.artwork) do
        region:SetAlpha(alpha)
    end
    for region, color in pairs(saved.flash) do
        region:SetVertexColor(unpack(color))
    end
    if saved.skull then
        restorePoints(saved.skull, saved.skullPoints)
    end
end

-- Reduced scope: retain Blizzard's shaped bars/masks and secure hit rectangles.
-- Remove the separate portrait artwork and use a modest level at the bar edge.
local function clean(portrait, art, circle, level, name, skull, bars)
    if
        not canHide(portrait)
        or not circle
        or type(circle.GetAlpha) ~= "function"
        or type(circle.SetAlpha) ~= "function"
        or not canAnchor(level)
        or not canAnchor(name)
        or not bars
        or type(bars.GetWidth) ~= "function"
        or type(name.GetWidth) ~= "function"
        or type(name.SetWidth) ~= "function"
        or not GameFontNormalSmall
        or type(level.GetFontObject) ~= "function"
        or type(level.SetFontObject) ~= "function"
        or not art
        or type(art.GetAlpha) ~= "function"
        or type(art.SetAlpha) ~= "function"
        or skull and not canAnchor(skull)
    then
        return
    end
    local saved = {
        portrait = portrait,
        portraitShown = portrait:IsShown(),
        circle = circle,
        circleAlpha = circle:GetAlpha(),
        art = art,
        alpha = art:GetAlpha(),
        level = level,
        points = capturePoints(level),
        skull = skull,
        skullPoints = skull and capturePoints(skull),
        font = level:GetFontObject(),
        name = name,
        nameWidth = name:GetWidth(),
        namePoints = capturePoints(name),
        artwork = {},
        flash = {},
    }
    portrait:Hide()
    circle:SetAlpha(0)
    -- Alpha leaves Blizzard's vehicle/classification Show/Hide and atlas choices intact.
    art:SetAlpha(0)
    level:ClearAllPoints()
    level:SetPoint("BOTTOMRIGHT", bars, "TOPRIGHT", 0, 2)
    level:SetFontObject(GameFontNormalSmall)
    name:SetWidth(math.max(20, bars:GetWidth() - 28))
    name:ClearAllPoints()
    name:SetPoint("BOTTOMLEFT", bars, "TOPLEFT", 0, 2)
    if skull then
        skull:ClearAllPoints()
        skull:SetPoint("CENTER", level, "CENTER", 0, 0)
    end
    return saved
end

local function hideArtwork(saved, region, flash)
    if not region then
        return
    end
    if flash and type(region.GetVertexColor) == "function" and type(region.SetVertexColor) == "function" then
        local r, g, b, a = region:GetVertexColor()
        saved.flash[region] = { r, g, b, a }
        -- Native flash animation changes alpha, so vertex alpha hides the art
        -- without intercepting that animation's per-frame work.
        region:SetVertexColor(r, g, b, 0)
    elseif not flash and type(region.GetAlpha) == "function" and type(region.SetAlpha) == "function" then
        saved.artwork[region] = region:GetAlpha()
        region:SetAlpha(0)
    end
end

local function suppressPlayerStatus()
    if playerRestore and playerRestore.status and MurgleDB.frames.cleanPlayer == true then
        statusHiding = true
        playerRestore.status:Hide()
        statusHiding = nil
    end
end

local function statusShown(region)
    if playerRestore and playerRestore.status == region then
        playerRestore.statusShown = true
        suppressPlayerStatus()
    end
end

local function statusHidden(region)
    if not statusHiding and playerRestore and playerRestore.status == region then
        playerRestore.statusShown = false
    end
end

local function suppressPlayerLevel()
    if not playerRestore or PlayerLevelText ~= playerRestore.level then
        return
    end
    -- UpdateLevel writes a new font colour including alpha. Preserve that latest
    -- native alpha for disable, then suppress at this event boundary.
    if playerRestore.artwork[PlayerLevelText] ~= nil then
        playerRestore.artwork[PlayerLevelText] = PlayerLevelText:GetAlpha()
        if MurgleDB.frames.cleanPlayer == true then
            PlayerLevelText:SetAlpha(0)
        end
    end
end

local function alignPlayerName()
    if MurgleDB.frames.cleanPlayer ~= true or not playerRestore then
        return
    end
    local content = PlayerFrame and PlayerFrame.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    if not main or not main.HealthBarsContainer or PlayerName ~= playerRestore.name then
        return
    end
    PlayerName:ClearAllPoints()
    PlayerName:SetPoint("BOTTOMLEFT", main.HealthBarsContainer, "TOPLEFT", 0, 2)
end

local function playerNameUpdated()
    if MurgleDB.frames.cleanPlayer == true and playerRestore then
        Murgle.DeferUntilOutOfCombat("framesPlayerName", alignPlayerName)
    end
end

local function suppressRest()
    if MurgleDB.frames.cleanPlayer == true and restRestore then
        restRestore.frame:Hide()
        restRestore.animation:Stop()
    end
end

local function restUpdated(state)
    if not restRestore then
        return
    end
    if type(issecretvalue) == "function" and issecretvalue(state) then
        return
    end
    if type(state) ~= "boolean" then
        return
    end
    restRestore.shown = state
    Murgle.DeferUntilOutOfCombat("frames.rest", suppressRest)
end

local function applyRest()
    if MurgleDB.frames.cleanPlayer ~= true and restRestore then
        local saved = restRestore
        restRestore = nil
        if saved.shown then
            saved.frame:Show()
            saved.animation:Play()
        else
            saved.frame:Hide()
            saved.animation:Stop()
        end
    elseif MurgleDB.frames.cleanPlayer == true and not restRestore then
        local content = PlayerFrame and PlayerFrame.PlayerFrameContent
        local contextual = content and content.PlayerFrameContentContextual
        local rest = contextual and contextual.PlayerRestLoop
        local animation = rest and rest.PlayerRestLoopAnim
        if
            canHide(rest)
            and animation
            and type(animation.Stop) == "function"
            and type(animation.Play) == "function"
            and type(PlayerFrame_UpdatePlayerRestLoop) == "function"
            and type(hooksecurefunc) == "function"
        then
            restRestore = { frame = rest, animation = animation, shown = rest:IsShown() }
            if not restHooked then
                hooksecurefunc("PlayerFrame_UpdatePlayerRestLoop", restUpdated)
                restHooked = true
            end
            suppressRest()
        end
    end
end

local function applyPlayerName()
    if MurgleDB.frames.hidePlayerName ~= true and hiddenName then
        hiddenName:SetAlpha(hiddenNameAlpha)
        hiddenName, hiddenNameAlpha = nil, nil
    elseif MurgleDB.frames.hidePlayerName == true and not hiddenName then
        if PlayerName and type(PlayerName.GetAlpha) == "function" and type(PlayerName.SetAlpha) == "function" then
            hiddenName, hiddenNameAlpha = PlayerName, PlayerName:GetAlpha()
            hiddenName:SetAlpha(0)
        end
    end
end

local function applyTargetOfTarget()
    if MurgleDB.frames.cleanTargetOfTarget ~= true then
        if targetOfTargetRestore then
            for region, alpha in pairs(targetOfTargetRestore.artwork) do
                region:SetAlpha(alpha)
            end
            if targetOfTargetRestore.portraitShown then
                targetOfTargetRestore.portrait:Show()
            else
                targetOfTargetRestore.portrait:Hide()
            end
            targetOfTargetRestore = nil
        end
        return
    end
    if targetOfTargetRestore then
        return
    end
    -- Mainline TargetFrameMixin:CreateTargetofTarget stores this exact child.
    -- Only portrait and border artwork; no secure button, mask or bar changes.
    local frame = TargetFrame and TargetFrame.totFrame
    if
        frame
        and canHide(frame.Portrait)
        and frame.FrameTexture
        and type(frame.FrameTexture.GetAlpha) == "function"
        and type(frame.FrameTexture.SetAlpha) == "function"
    then
        targetOfTargetRestore = { portrait = frame.Portrait, portraitShown = frame.Portrait:IsShown(), artwork = {} }
        -- HealthCheck writes portrait vertex alpha. Visibility survives that
        -- native tint update without needing a health callback.
        frame.Portrait:Hide()
        hideArtwork(targetOfTargetRestore, frame.FrameTexture)
    end
end

local function applyClean()
    local settings = MurgleDB.frames
    applyRest()
    applyTargetOfTarget()
    applyPlayerName()
    if settings.cleanPlayer ~= true and playerRestore then
        local name = playerRestore.name
        restoreClean(playerRestore)
        playerRestore = nil
        -- Vehicle transitions change the native offset while cleanup owns the
        -- name. Relinquish ownership before restoring the current native layout.
        if nameHooked and PlayerName == name and type(PlayerFrame_UpdatePlayerNameTextAnchor) == "function" then
            name:ClearAllPoints()
            PlayerFrame_UpdatePlayerNameTextAnchor()
        end
    elseif settings.cleanPlayer == true and not playerRestore then
        local container = PlayerFrame and PlayerFrame.PlayerFrameContainer
        local content = PlayerFrame and PlayerFrame.PlayerFrameContent
        local main = content and content.PlayerFrameContentMain
        if container and main then
            playerRestore = clean(
                container.PlayerPortrait,
                container.FrameTexture,
                main.LevelBackgroundCircle,
                PlayerLevelText,
                PlayerName,
                nil,
                main.HealthBarsContainer
            )
            if playerRestore then
                hideArtwork(playerRestore, container.VehicleFrameTexture)
                hideArtwork(playerRestore, container.AlternatePowerFrameTexture)
                hideArtwork(playerRestore, container.FrameFlash, true)
                hideArtwork(playerRestore, main.PvpBackgroundCircle)
                hideArtwork(playerRestore, main.PvpBackgroundIcon)
                hideArtwork(playerRestore, PlayerLevelText)
                local contextual = content.PlayerFrameContentContextual
                hideArtwork(playerRestore, contextual and contextual.PlayerPortraitCornerIcon)
                if
                    not levelHooked
                    and type(PlayerFrame_UpdateLevel) == "function"
                    and type(hooksecurefunc) == "function"
                then
                    hooksecurefunc("PlayerFrame_UpdateLevel", suppressPlayerLevel)
                    levelHooked = true
                end
                if
                    not nameHooked
                    and type(PlayerFrame_UpdatePlayerNameTextAnchor) == "function"
                    and type(hooksecurefunc) == "function"
                then
                    hooksecurefunc("PlayerFrame_UpdatePlayerNameTextAnchor", playerNameUpdated)
                    nameHooked = true
                end
                -- Only install this event-boundary hook when the native API is available.
                if
                    type(PlayerFrame_UpdateStatus) == "function"
                    and type(hooksecurefunc) == "function"
                    and canHide(main.StatusTexture)
                then
                    playerRestore.status = main.StatusTexture
                    playerRestore.statusShown = main.StatusTexture:IsShown()
                    if statusHooked ~= main.StatusTexture then
                        -- UpdateStatus has a hate-list branch with no visibility
                        -- write. Observe actual Show/Hide intent, not our hidden
                        -- state; neither method is called by the alpha animation.
                        hooksecurefunc(main.StatusTexture, "Show", statusShown)
                        hooksecurefunc(main.StatusTexture, "Hide", statusHidden)
                        statusHooked = main.StatusTexture
                    end
                    suppressPlayerStatus()
                end
            end
        end
    end
    if settings.cleanTarget ~= true and targetRestore then
        restoreClean(targetRestore)
        targetRestore = nil
    elseif settings.cleanTarget == true and not targetRestore then
        local container = TargetFrame and TargetFrame.TargetFrameContainer
        local content = TargetFrame and TargetFrame.TargetFrameContent
        local main = content and content.TargetFrameContentMain
        local contextual = content and content.TargetFrameContentContextual
        if container and main and contextual then
            targetRestore = clean(
                container.Portrait,
                container.FrameTexture,
                main.LevelBackgroundCircle,
                main.LevelText,
                main.Name,
                contextual.HighLevelTexture,
                main.HealthBarsContainer
            )
            if targetRestore then
                hideArtwork(targetRestore, container.BossPortraitFrameTexture)
                hideArtwork(targetRestore, container.Flash, true)
                hideArtwork(targetRestore, contextual.PvpBackgroundCircle)
                hideArtwork(targetRestore, contextual.PvpBackgroundIcon)
                hideArtwork(targetRestore, contextual.LeaderIcon)
                hideArtwork(targetRestore, contextual.GuideIcon)
                hideArtwork(targetRestore, main.ReputationColor)
            end
        end
    end
end

local function correctFaction(frame)
    if frame ~= TargetFrame or frame.unit ~= "target" then
        return
    end
    if MurgleDB.frames.cleanTarget == true and targetRestore then
        local main = frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
        local region = main and main.ReputationColor
        if region and targetRestore.artwork[region] ~= nil then
            region:SetAlpha(0)
        end
    end
    if MurgleDB.frames.enemyFactionOnly ~= true then
        return
    end
    local player, enemy = UnitIsPlayer("target"), UnitCanAttack("player", "target")
    if type(issecretvalue) == "function" and (issecretvalue(player) or issecretvalue(enemy)) then
        return
    end
    if type(player) ~= "boolean" or type(enemy) ~= "boolean" then
        return
    end
    if player and enemy then
        return
    end
    local content = frame.TargetFrameContent
    local contextual = content and content.TargetFrameContentContextual
    if contextual then
        if canHide(contextual.PvpBackgroundCircle) then
            contextual.PvpBackgroundCircle:Hide()
        end
        if canHide(contextual.PvpBackgroundIcon) then
            contextual.PvpBackgroundIcon:Hide()
        end
    end
end

local function applyFaction()
    if not TargetFrame or type(TargetFrame.CheckFaction) ~= "function" then
        return
    end
    if MurgleDB.frames.enemyFactionOnly == true or MurgleDB.frames.cleanTarget == true then
        if
            type(hooksecurefunc) ~= "function"
            or type(UnitIsPlayer) ~= "function"
            or type(UnitCanAttack) ~= "function"
        then
            return
        end
        if not factionHooked then
            hooksecurefunc(TargetFrame, "CheckFaction", correctFaction)
            factionHooked = true
        end
        TargetFrame:CheckFaction()
        factionApplied = true
    elseif factionApplied then
        TargetFrame:CheckFaction()
        factionApplied = nil
    end
end

function Frames.ApplyAll()
    Frames.ApplyNameplates()
    if
        MurgleDB.frames.cleanPlayer == true
        or MurgleDB.frames.cleanTarget == true
        or MurgleDB.frames.cleanTargetOfTarget == true
        or targetOfTargetRestore
        or MurgleDB.frames.hidePlayerName == true
        or hiddenName
        or restRestore
        or playerRestore
        or targetRestore
    then
        Murgle.DeferUntilOutOfCombat("frames.clean", applyClean)
    end
    applyFaction()
end

function Frames.Initialize()
    Frames.ApplyAll()
end
