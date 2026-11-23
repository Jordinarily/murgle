local _, Murgle = ...
local Frames = {}
Murgle.Frames = Frames

local playerRestore, targetRestore, focusRestore, targetOfTargetRestore
local statusHooked, statusHiding, nameHooked, levelHooked
local restHooked, restRestore, hiddenName, hiddenNameAlpha
local playerFrameHidden, playerFramePriorAlpha

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
    for index = 1, region:GetNumPoints() do
        points[index] = { region:GetPoint(index) }
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
    if not saved then
        return
    end
    if saved.portraitShown then
        saved.portrait:Show()
    else
        saved.portrait:Hide()
    end
    saved.circle:SetAlpha(saved.circleAlpha)
    saved.art:SetAlpha(saved.alpha)
    for region, alpha in pairs(saved.artwork) do
        region:SetAlpha(alpha)
    end
    for region, color in pairs(saved.flash) do
        region:SetVertexColor(unpack(color))
    end
    if saved.status then
        if saved.statusShown then
            saved.status:Show()
        else
            saved.status:Hide()
        end
    end
    restorePoints(saved.level, saved.points)
    saved.level:SetFontObject(saved.font)
    saved.name:SetWidth(saved.nameWidth)
    restorePoints(saved.name, saved.namePoints)
    if saved.skull then
        restorePoints(saved.skull, saved.skullPoints)
    end
end

-- Retain Blizzard's shaped bars/masks, borders, and secure hit rectangles.
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
        or (skull and not canAnchor(skull))
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
        if saved.flash[region] == nil then
            saved.flash[region] = { region:GetVertexColor() }
        end
        region:SetVertexColor(0, 0, 0, 0)
    elseif not flash and type(region.GetAlpha) == "function" and type(region.SetAlpha) == "function" then
        if saved.artwork[region] == nil then
            saved.artwork[region] = region:GetAlpha()
        end
        region:SetAlpha(0)
    end
end

local function suppressPlayerStatus()
    local content = PlayerFrame and PlayerFrame.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    local status = main and main.StatusTexture
    if status and canHide(status) then
        statusHiding = true
        status:Hide()
        statusHiding = false
    end
end

local function statusShown(region)
    if
        not statusHiding
        and MurgleDB.frames.compactFrames == true
        and playerRestore
        and playerRestore.status == region
    then
        suppressPlayerStatus()
    end
end

local function statusHidden(region)
    if
        not statusHiding
        and MurgleDB.frames.compactFrames == true
        and playerRestore
        and playerRestore.status == region
    then
        playerRestore.statusShown = false
    end
end

local function suppressPlayerLevel()
    if
        MurgleDB.frames.compactFrames == true
        and playerRestore
        and PlayerLevelText
        and type(PlayerLevelText.SetAlpha) == "function"
    then
        PlayerLevelText:SetAlpha(0)
    end
end

local function alignPlayerName()
    if MurgleDB.frames.compactFrames == true and playerRestore and PlayerName and canAnchor(PlayerName) then
        local content = PlayerFrame and PlayerFrame.PlayerFrameContent
        local main = content and content.PlayerFrameContentMain
        local bars = main and main.HealthBarsContainer
        if bars and type(bars.GetWidth) == "function" then
            PlayerName:SetWidth(math.max(20, bars:GetWidth() - 28))
            PlayerName:ClearAllPoints()
            PlayerName:SetPoint("BOTTOMLEFT", bars, "TOPLEFT", 0, 2)
        end
    end
end

local function playerNameUpdated()
    if MurgleDB.frames.compactFrames == true and playerRestore then
        alignPlayerName()
    end
end

local function suppressRest()
    local content = PlayerFrame and PlayerFrame.PlayerFrameContent
    local contextual = content and content.PlayerFrameContentContextual
    local rest = contextual and contextual.PlayerRestLoop
    if rest and type(rest.Stop) == "function" then
        rest:Stop()
    end
end

local function restUpdated(state)
    if MurgleDB.frames.compactFrames == true and restRestore then
        suppressRest()
    end
end

local function applyRest()
    local settings = MurgleDB.frames
    if settings.compactFrames ~= true and restRestore then
        local content = PlayerFrame and PlayerFrame.PlayerFrameContent
        local contextual = content and content.PlayerFrameContentContextual
        local animation = contextual and contextual.PlayerRestLoop
        if animation and type(animation.Play) == "function" and restRestore.playing then
            animation:Play()
        end
        restRestore = nil
    elseif settings.compactFrames == true and not restRestore then
        local content = PlayerFrame and PlayerFrame.PlayerFrameContent
        local contextual = content and content.PlayerFrameContentContextual
        local animation = contextual and contextual.PlayerRestLoop
        if
            animation
            and type(animation.IsPlaying) == "function"
            and type(animation.Stop) == "function"
            and type(animation.Play) == "function"
            and type(PlayerFrame_UpdatePlayerRestLoop) == "function"
            and type(hooksecurefunc) == "function"
        then
            restRestore = { playing = animation:IsPlaying() }
            if not restHooked then
                hooksecurefunc("PlayerFrame_UpdatePlayerRestLoop", restUpdated)
                restHooked = true
            end
            suppressRest()
        end
    end
end

local function applyPlayerName()
    local hide = MurgleDB.frames and MurgleDB.frames.hidePlayerName == true
    if not hide and not hiddenName then
        return
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        Murgle.DeferUntilOutOfCombat("frames.playerName", applyPlayerName)
        return
    end
    if hide and not hiddenName then
        if PlayerName and type(PlayerName.GetAlpha) == "function" and type(PlayerName.SetAlpha) == "function" then
            hiddenName, hiddenNameAlpha = PlayerName, PlayerName:GetAlpha()
            hiddenName:SetAlpha(0)
        end
    elseif not hide and hiddenName then
        hiddenName:SetAlpha(hiddenNameAlpha or 1)
        hiddenName, hiddenNameAlpha = nil, nil
    end
end

local function applyPlayerFrame()
    local hide = MurgleDB.frames and MurgleDB.frames.hidePlayerFrame == true
    if not hide and not playerFrameHidden then
        return
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        Murgle.DeferUntilOutOfCombat("frames.playerFrame", applyPlayerFrame)
        return
    end
    if not PlayerFrame or type(PlayerFrame.SetAlpha) ~= "function" or type(PlayerFrame.GetAlpha) ~= "function" then
        return
    end
    if hide and not playerFrameHidden then
        playerFramePriorAlpha = PlayerFrame:GetAlpha()
        PlayerFrame:SetAlpha(0)
        if type(PlayerFrame.EnableMouse) == "function" then
            PlayerFrame:EnableMouse(false)
        end
        playerFrameHidden = true
    elseif not hide and playerFrameHidden then
        PlayerFrame:SetAlpha(playerFramePriorAlpha or 1)
        if type(PlayerFrame.EnableMouse) == "function" then
            PlayerFrame:EnableMouse(true)
        end
        playerFrameHidden = nil
        playerFramePriorAlpha = nil
    end
end

local function cleanTargetFrame(frame)
    local container = frame and frame.TargetFrameContainer
    local content = frame and frame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    local contextual = content and content.TargetFrameContentContextual
    if container and main and contextual then
        local restore = clean(
            container.Portrait,
            container.FrameTexture,
            main.LevelBackgroundCircle,
            main.LevelText,
            main.Name,
            contextual.HighLevelTexture,
            main.HealthBarsContainer
        )
        if restore then
            hideArtwork(restore, container.BossPortraitFrameTexture)
            hideArtwork(restore, container.Flash, true)
            hideArtwork(restore, contextual.PvpBackgroundCircle)
            hideArtwork(restore, contextual.PvpBackgroundIcon)
            hideArtwork(restore, contextual.LeaderIcon)
            hideArtwork(restore, contextual.GuideIcon)
            hideArtwork(restore, main.ReputationColor)
            return restore
        end
    end
end

local function applyTargetOfTarget()
    if MurgleDB.frames.compactFrames ~= true then
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
    local frame = TargetFrame and TargetFrame.totFrame
    if
        frame
        and canHide(frame.Portrait)
        and frame.FrameTexture
        and type(frame.FrameTexture.GetAlpha) == "function"
        and type(frame.FrameTexture.SetAlpha) == "function"
    then
        targetOfTargetRestore = { portrait = frame.Portrait, portraitShown = frame.Portrait:IsShown(), artwork = {} }
        frame.Portrait:Hide()
        hideArtwork(targetOfTargetRestore, frame.FrameTexture)
    end
end

local function applyClean()
    local settings = MurgleDB.frames
    applyRest()
    applyTargetOfTarget()
    applyPlayerName()
    applyPlayerFrame()

    if settings.compactFrames ~= true then
        if playerRestore then
            local name = playerRestore.name
            restoreClean(playerRestore)
            playerRestore = nil
            if nameHooked and PlayerName == name and type(PlayerFrame_UpdatePlayerNameTextAnchor) == "function" then
                name:ClearAllPoints()
                PlayerFrame_UpdatePlayerNameTextAnchor()
            end
        end
        if targetRestore then
            restoreClean(targetRestore)
            targetRestore = nil
        end
        if focusRestore then
            restoreClean(focusRestore)
            focusRestore = nil
        end
    else
        -- Compact PlayerFrame
        if not playerRestore then
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
                    if
                        type(PlayerFrame_UpdateStatus) == "function"
                        and type(hooksecurefunc) == "function"
                        and canHide(main.StatusTexture)
                    then
                        playerRestore.status = main.StatusTexture
                        playerRestore.statusShown = main.StatusTexture:IsShown()
                        if statusHooked ~= main.StatusTexture then
                            hooksecurefunc(main.StatusTexture, "Show", statusShown)
                            hooksecurefunc(main.StatusTexture, "Hide", statusHidden)
                            statusHooked = main.StatusTexture
                        end
                        suppressPlayerStatus()
                    end
                end
            end
        end

        -- Compact TargetFrame
        if not targetRestore and TargetFrame then
            targetRestore = cleanTargetFrame(TargetFrame)
        end

        -- Compact FocusFrame
        if not focusRestore and FocusFrame then
            focusRestore = cleanTargetFrame(FocusFrame)
        end
    end
end

function Frames.ApplyPlayerName()
    applyPlayerName()
end

function Frames.ApplyPlayerFrame()
    applyPlayerFrame()
end

function Frames.ApplyCompact()
    local enabled = MurgleDB.frames and MurgleDB.frames.compactFrames == true
    if not enabled and not playerRestore and not targetRestore and not focusRestore and not targetOfTargetRestore then
        return
    end
    Murgle.DeferUntilOutOfCombat("frames.clean", applyClean)
end

function Frames.ApplyAll()
    Frames.ApplyPlayerName()
    Frames.ApplyPlayerFrame()
    Frames.ApplyCompact()
end

function Frames.Initialize()
    Frames.ApplyAll()
end
