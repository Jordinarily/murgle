local _, Murgle = ...
local Bags = {}
Murgle.Bags = Bags

local bag, handle, originalClamp, originalPlaced
local hooked, active, dragging = false, false, false
local draggedClick = false
local REQUIRED_METHODS = {
    "ClearAllPoints",
    "SetPoint",
    "GetCenter",
    "GetEffectiveScale",
    "StartMoving",
    "StopMovingOrSizing",
    "IsClampedToScreen",
    "SetClampedToScreen",
    "IsUserPlaced",
    "SetUserPlaced",
}

local function finite(value)
    return type(value) == "number" and value == value and value > -100000 and value < 100000
end

local function usable(frame)
    if not frame or type(frame.IsProtected) ~= "function" or frame:IsProtected() then
        return false
    end
    for _, method in ipairs(REQUIRED_METHODS) do
        if type(frame[method]) ~= "function" then
            return false
        end
    end
    return UIParent and type(UIParent.GetCenter) == "function" and type(UIParent.GetEffectiveScale) == "function"
end

-- Native layout anchors the next container column to the combined bag. Detach
-- only that dependent frame before moving, using the cached native shown list.
local function detachDependent()
    if not ContainerFrameSettingsManager or type(ContainerFrameSettingsManager.GetBagsShown) ~= "function" then
        return false
    end
    local shown = ContainerFrameSettingsManager:GetBagsShown()
    if type(shown) ~= "table" then
        return false
    end
    local dependent
    for index = 1, #shown - 1 do
        if shown[index] == bag then
            dependent = shown[index + 1]
            break
        end
    end
    if not dependent then
        return true
    end
    if type(dependent.GetPoint) ~= "function" then
        return false
    end
    local _, relative = dependent:GetPoint(1)
    if relative ~= bag then
        return true
    end
    if
        type(dependent.IsProtected) ~= "function"
        or dependent:IsProtected()
        or type(dependent.GetCenter) ~= "function"
        or type(dependent.GetEffectiveScale) ~= "function"
        or type(dependent.ClearAllPoints) ~= "function"
        or type(dependent.SetPoint) ~= "function"
    then
        return false
    end
    local x, y = dependent:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    local scale, parentScale = dependent:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if
        not finite(x)
        or not finite(y)
        or not finite(parentX)
        or not finite(parentY)
        or not finite(scale)
        or scale <= 0
        or not finite(parentScale)
        or parentScale <= 0
    then
        return false
    end
    dependent:ClearAllPoints()
    dependent:SetPoint(
        "CENTER",
        UIParent,
        "CENTER",
        x - parentX * parentScale / scale,
        y - parentY * parentScale / scale
    )
    return true
end

local function applyPosition()
    if not active or MurgleDB.interface.moveBags ~= true or not usable(bag) or dragging then
        return
    end
    if InCombatLockdown() then
        Murgle.DeferUntilOutOfCombat("bags.position", applyPosition)
        return
    end
    local position = MurgleDB.interface.bagPosition
    if type(position) ~= "table" or not finite(position.x) or not finite(position.y) then
        return
    end
    local scale, parentScale = bag:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not finite(scale) or scale <= 0 or not finite(parentScale) or parentScale <= 0 then
        return
    end
    if not detachDependent() then
        return
    end
    bag:ClearAllPoints()
    bag:SetPoint("CENTER", UIParent, "CENTER", position.x * parentScale / scale, position.y * parentScale / scale)
end

local function stopDrag()
    if not dragging or not usable(bag) then
        return
    end
    if InCombatLockdown() then
        Murgle.DeferUntilOutOfCombat("bags.stop", stopDrag)
        return
    end
    dragging = false
    bag:StopMovingOrSizing()
    bag:SetUserPlaced(originalPlaced)
    if not active or MurgleDB.interface.moveBags ~= true then
        return
    end
    local x, y = bag:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    local scale, parentScale = bag:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if
        not finite(x)
        or not finite(y)
        or not finite(parentX)
        or not finite(parentY)
        or not finite(scale)
        or scale <= 0
        or not finite(parentScale)
        or parentScale <= 0
    then
        return
    end
    x, y = x * scale / parentScale - parentX, y * scale / parentScale - parentY
    if finite(x) and finite(y) then
        MurgleDB.interface.bagPosition = { x = x, y = y }
        applyPosition()
    end
end

local function apply()
    if MurgleDB.interface.moveBags ~= true then
        if not active then
            return
        end
        active = false
        stopDrag()
        handle:Hide()
        if usable(bag) then
            bag:SetClampedToScreen(originalClamp)
            bag:SetUserPlaced(originalPlaced)
            if type(UpdateContainerFrameAnchors) == "function" then
                UpdateContainerFrameAnchors()
            end
        end
        return
    end
    if
        not usable(ContainerFrameCombinedBags)
        or not ContainerFrameCombinedBags.TitleContainer
        or type(ContainerFrameCombinedBags.TitleContainer.GetFrameLevel) ~= "function"
        or type(UpdateContainerFrameAnchors) ~= "function"
        or type(hooksecurefunc) ~= "function"
        or not ContainerFrameSettingsManager
        or type(ContainerFrameSettingsManager.GetBagsShown) ~= "function"
    then
        return
    end
    if not handle then
        bag = ContainerFrameCombinedBags
        -- The native title is at frame level 510, above ordinary bag children.
        -- Parent to that title and cover its real bounds so native art cannot
        -- obscure the mouse target; portrait and close controls lie outside it.
        local title = bag.TitleContainer
        handle = CreateFrame("Button", nil, title)
        handle:SetAllPoints(title)
        handle:SetFrameLevel(title:GetFrameLevel() + 1)
        handle:EnableMouse(true)
        handle:RegisterForDrag("LeftButton")
        handle:SetScript("OnMouseDown", function()
            draggedClick = false
        end)
        handle:SetScript("OnClick", function()
            if
                not draggedClick
                and bag.PortraitButton
                and DropdownButtonMixin
                and type(DropdownButtonMixin.OnMouseDown_Intrinsic) == "function"
            then
                DropdownButtonMixin.OnMouseDown_Intrinsic(bag.PortraitButton)
            end
        end)
        handle:SetScript("OnDragStart", function()
            if
                active
                and MurgleDB.interface.moveBags == true
                and not InCombatLockdown()
                and usable(bag)
                and detachDependent()
            then
                draggedClick = true
                dragging = true
                bag:StartMoving()
            end
        end)
        handle:SetScript("OnDragStop", stopDrag)
        handle:SetScript("OnHide", stopDrag)
        handle:SetScript("OnEnter", function(self)
            if GameTooltip and type(GameTooltip.SetOwner) == "function" and type(GameTooltip.SetText) == "function" then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(Murgle.L.MOVE_BAGS_HELP, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        handle:SetScript("OnLeave", function(self)
            if GameTooltip and type(GameTooltip.GetOwner) == "function" and GameTooltip:GetOwner() == self then
                GameTooltip:Hide()
            end
        end)
    end
    if not active then
        originalClamp, originalPlaced = bag:IsClampedToScreen(), bag:IsUserPlaced()
        active = true
        bag:SetClampedToScreen(true)
        handle:Show()
    end
    if not hooked then
        -- Native OnShow and layout/scale updates reset bag anchors. Post-hook
        -- only the combined window; keep native layout for other bags/banks.
        hooksecurefunc("UpdateContainerFrameAnchors", applyPosition)
        hooked = true
    end
    applyPosition()
end

function Bags.ApplyAll()
    if MurgleDB.interface.moveBags ~= true and not active then
        return
    end
    Murgle.DeferUntilOutOfCombat("bags.apply", apply)
end

function Bags.ResetPosition()
    MurgleDB.interface.bagPosition = nil
    Murgle.DeferUntilOutOfCombat("bags.reset", function()
        -- A drag stop already queued by combat may have saved a position.
        MurgleDB.interface.bagPosition = nil
        if dragging then
            dragging = false
            if usable(bag) then
                bag:StopMovingOrSizing()
                bag:SetUserPlaced(originalPlaced)
            end
        end
        if type(UpdateContainerFrameAnchors) == "function" then
            UpdateContainerFrameAnchors()
        end
    end)
end

function Bags.Initialize()
    Bags.ApplyAll()
    if MurgleDB.interface.moveBags == true and not handle then
        local retry = CreateFrame("Frame")
        retry:RegisterEvent("PLAYER_ENTERING_WORLD")
        retry:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
            Bags.ApplyAll()
        end)
    end
end
