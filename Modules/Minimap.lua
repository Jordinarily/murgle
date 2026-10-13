local _, Murgle = ...
local MinimapOptions = {}
Murgle.Minimap = MinimapOptions

local zoneState, clockState, calendarState, headerState = {}, {}, {}, {}
local clockWaiter
local trackingState, trackingBackgroundState, zoomInState, zoomOutState = {}, {}, {}, {}

-- Capture only on first enable; restoring must not show a previously hidden button.
local function applyVisibility(frame, state, hide)
    state.pending = nil
    if not hide and state.shown == nil then
        return
    end
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
        state.frame:Hide()
    else
        local original = state.frame
        if state.shown then
            original:Show()
        else
            original:Hide()
        end
        state.shown, state.frame = nil, nil
    end
end

local function queue(key, state, hide, apply)
    if not hide and state.shown == nil and not state.pending then
        return
    end
    state.pending = true
    Murgle.DeferUntilOutOfCombat(key, apply)
end

local function applyZoneText()
    applyVisibility(
        zoneState.frame or (MinimapCluster and MinimapCluster.ZoneTextButton),
        zoneState,
        MurgleDB.minimap.hideZoneText == true
    )
end

local function applyClock()
    applyVisibility(clockState.frame or TimeManagerClockButton, clockState, MurgleDB.minimap.hideClock == true)
end

local function applyCalendar()
    applyVisibility(calendarState.frame or GameTimeFrame, calendarState, MurgleDB.minimap.hideCalendar == true)
end

local function applyTracking()
    applyVisibility(
        trackingBackgroundState.frame
            or (MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Background),
        trackingBackgroundState,
        MurgleDB.minimap.hideTracking == true
    )
    applyVisibility(
        trackingState.frame or (MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button),
        trackingState,
        MurgleDB.minimap.hideTracking == true
    )
end

local function applyZoomIn()
    applyVisibility(
        zoomInState.frame or (Minimap and Minimap.ZoomIn),
        zoomInState,
        MurgleDB.minimap.hideZoomButtons == true
    )
end

local function applyZoomOut()
    applyVisibility(
        zoomOutState.frame or (Minimap and Minimap.ZoomOut),
        zoomOutState,
        MurgleDB.minimap.hideZoomButtons == true
    )
end

function MinimapOptions.ApplyZoneText()
    queue("minimap.hideZoneText", zoneState, MurgleDB.minimap.hideZoneText == true, applyZoneText)
end

local function applyHeader()
    applyVisibility(
        headerState.frame or (MinimapCluster and MinimapCluster.BorderTop),
        headerState,
        MurgleDB.minimap.hideHeader == true
    )
end

function MinimapOptions.ApplyHeader()
    queue("minimap.hideHeader", headerState, MurgleDB.minimap.hideHeader == true, applyHeader)
end

function MinimapOptions.ApplyClock()
    if MurgleDB.minimap.hideClock == true and not TimeManagerClockButton then
        if not clockWaiter then
            clockWaiter = CreateFrame("Frame")
            clockWaiter:SetScript("OnEvent", function(self, _, addon)
                if addon == "Blizzard_TimeManager" then
                    self:UnregisterEvent("ADDON_LOADED")
                    queue("minimap.hideClock", clockState, MurgleDB.minimap.hideClock == true, applyClock)
                end
            end)
        end
        clockWaiter:RegisterEvent("ADDON_LOADED")
    elseif clockWaiter then
        clockWaiter:UnregisterEvent("ADDON_LOADED")
    end
    queue("minimap.hideClock", clockState, MurgleDB.minimap.hideClock == true, applyClock)
end

function MinimapOptions.ApplyCalendar()
    queue("minimap.hideCalendar", calendarState, MurgleDB.minimap.hideCalendar == true, applyCalendar)
end

function MinimapOptions.ApplyTracking()
    queue(
        "minimap.hideTracking",
        trackingState,
        MurgleDB.minimap.hideTracking == true or trackingBackgroundState.shown ~= nil,
        applyTracking
    )
end

function MinimapOptions.ApplyZoomButtons()
    queue("minimap.zoomIn", zoomInState, MurgleDB.minimap.hideZoomButtons == true, applyZoomIn)
    queue("minimap.zoomOut", zoomOutState, MurgleDB.minimap.hideZoomButtons == true, applyZoomOut)
end

local dayNightState = {}

local function applyDayNight()
    dayNightState.pending = nil
    local hide = MurgleDB.minimap.hideDayNight == true
    local frame = dayNightState.frame or (MinimapCluster and MinimapCluster.DielFrame)
    if not frame or type(frame.IsProtected) ~= "function" or frame:IsProtected() ~= false then
        return
    end
    applyVisibility(frame, dayNightState, hide)
end

function MinimapOptions.ApplyDayNight()
    queue("minimap.dayNight", dayNightState, MurgleDB.minimap.hideDayNight == true, applyDayNight)
end

local compartmentState = {}

local function applyAddonCompartment()
    compartmentState.pending = nil
    local hide = MurgleDB.minimap.hideAddonCompartment == true
    if not hide and not compartmentState.frame then
        return
    end
    local frame = compartmentState.frame or AddonCompartmentFrame
    if
        not frame
        or type(frame.IsProtected) ~= "function"
        or frame:IsProtected()
        or type(frame.UpdateDisplay) ~= "function"
        or type(frame.Hide) ~= "function"
        or type(hooksecurefunc) ~= "function"
    then
        return
    end
    if hide then
        if compartmentState.hooked ~= frame then
            hooksecurefunc(frame, "UpdateDisplay", function()
                if MurgleDB.minimap.hideAddonCompartment == true then
                    MinimapOptions.ApplyAddonCompartment()
                end
            end)
            compartmentState.hooked = frame
        end
        compartmentState.frame = frame
        frame:Hide()
    else
        compartmentState.frame = nil
        -- Registration can change while hidden. Let Blizzard recompute eligibility
        -- instead of restoring the pre-discovery shown state or showing an empty menu.
        frame:UpdateDisplay()
    end
end

function MinimapOptions.ApplyAddonCompartment()
    if
        MurgleDB.minimap.hideAddonCompartment ~= true
        and not compartmentState.frame
        and not compartmentState.pending
    then
        return
    end
    compartmentState.pending = true
    Murgle.DeferUntilOutOfCombat("minimap.addonCompartment", applyAddonCompartment)
end

local squareFrame, squarePending
local squareEdges, squareEdgeFrame
local borderState = {}
local borderPending

local function applyBorder()
    borderPending = nil
    if MurgleDB.minimap.hideBorder ~= true and not squareFrame then
        for texture, alpha in pairs(borderState) do
            texture:SetAlpha(alpha)
            borderState[texture] = nil
        end
        return
    end
    -- These are artwork regions, not MinimapBackdrop (which also owns buttons).
    local function hide(texture)
        if not texture or type(texture.GetAlpha) ~= "function" or type(texture.SetAlpha) ~= "function" then
            return
        end
        if borderState[texture] == nil then
            borderState[texture] = texture:GetAlpha()
        end
        texture:SetAlpha(0)
    end
    hide(MinimapCompassTexture)
    hide(MinimapCompassTextureUnderlay)
end

function MinimapOptions.ApplyBorder()
    if MurgleDB.minimap.hideBorder ~= true and not borderPending and not next(borderState) then
        return
    end
    borderPending = true
    Murgle.DeferUntilOutOfCombat("minimap.border", applyBorder)
end

local function setSquareEdges(frame, enabled)
    if enabled and type(frame.CreateTexture) == "function" then
        if squareEdgeFrame ~= frame then
            squareEdges, squareEdgeFrame = {}, frame
            for i = 1, 4 do
                local edge = frame:CreateTexture(nil, "OVERLAY", nil, 7)
                edge:SetColorTexture(0.12, 0.12, 0.12, 1)
                if i <= 2 then
                    local point = i == 1 and "TOP" or "BOTTOM"
                    edge:SetPoint(point .. "LEFT", frame, point .. "LEFT", 0, 0)
                    edge:SetPoint(point .. "RIGHT", frame, point .. "RIGHT", 0, 0)
                    edge:SetHeight(1)
                else
                    local point = i == 3 and "LEFT" or "RIGHT"
                    edge:SetPoint("TOP" .. point, frame, "TOP" .. point, 0, 0)
                    edge:SetPoint("BOTTOM" .. point, frame, "BOTTOM" .. point, 0, 0)
                    edge:SetWidth(1)
                end
                squareEdges[i] = edge
            end
        end
    end
    if squareEdges then
        for _, edge in ipairs(squareEdges) do
            if enabled then
                edge:Show()
            else
                edge:Hide()
            end
        end
    end
end

local function applyBlobRings(frame, enabled)
    local value = enabled and 0 or 1
    -- Preserve Square Minimap's established ring cleanup. No independent
    -- quest-area control: ring setters alone do not hide the filled area.
    if type(frame.SetQuestBlobRingScalar) == "function" then
        frame:SetQuestBlobRingScalar(value)
    end
    if type(frame.SetQuestBlobRingAlpha) == "function" then
        frame:SetQuestBlobRingAlpha(value)
    end
    if type(frame.SetTaskBlobRingScalar) == "function" then
        frame:SetTaskBlobRingScalar(value)
    end
    if type(frame.SetTaskBlobRingAlpha) == "function" then
        frame:SetTaskBlobRingAlpha(value)
    end
    if type(frame.SetArchBlobRingScalar) == "function" then
        frame:SetArchBlobRingScalar(value)
    end
    if type(frame.SetArchBlobRingAlpha) == "function" then
        frame:SetArchBlobRingAlpha(value)
    end
end

local function applySquare()
    squarePending = nil
    local enabled = MurgleDB.minimap.square == true
    if enabled and squareFrame or not enabled and not squareFrame then
        return
    end
    local frame = squareFrame or Minimap
    if
        not frame
        or type(frame.SetMaskTexture) ~= "function"
        or type(frame.IsProtected) ~= "function"
        or frame:IsProtected()
    then
        return
    end
    -- The minimap API has no mask getter. Disable restores Blizzard's round
    -- mask, not an unknown custom mask installed by another addon.
    if enabled then
        frame:SetMaskTexture("Interface\\BUTTONS\\WHITE8X8")
        squareFrame = frame
    else
        frame:SetMaskTexture("ui-hud-minimap-frame-generic-mask")
        squareFrame = nil
    end
    applyBlobRings(frame, enabled)
    applyBorder()
    setSquareEdges(frame, enabled)
end

function MinimapOptions.ApplySquare()
    if MurgleDB.minimap.square ~= true and not squareFrame and not squarePending then
        return
    end
    squarePending = true
    Murgle.DeferUntilOutOfCombat("minimap.square", applySquare)
end

function MinimapOptions.ApplyAll()
    MinimapOptions.ApplyHeader()
    MinimapOptions.ApplyZoneText()
    MinimapOptions.ApplyClock()
    MinimapOptions.ApplyCalendar()
    MinimapOptions.ApplyTracking()
    MinimapOptions.ApplyZoomButtons()
    MinimapOptions.ApplyAddonCompartment()
    MinimapOptions.ApplyBorder()
    MinimapOptions.ApplySquare()
    MinimapOptions.ApplyDayNight()
end

function MinimapOptions.Initialize()
    MinimapOptions.ApplyAll()
end
