local _, Murgle = ...
local Tooltip = {}
Murgle.Tooltip = Tooltip

local cursorHooked, combatHooked, combatEvents
local anchoredOwner
local anchors = { left = "ANCHOR_CURSOR_LEFT", right = "ANCHOR_CURSOR_RIGHT", cursor = "ANCHOR_CURSOR" }

local function cursorUsable()
    return GameTooltip
        and type(GameTooltip.SetOwner) == "function"
        and type(GameTooltip.GetOwner) == "function"
        and type(GameTooltip.GetAnchorType) == "function"
        and type(GameTooltip_SetDefaultAnchor) == "function"
        and type(hooksecurefunc) == "function"
end

local function applyCursor(tooltip, parent)
    if MurgleDB.tooltip.cursorAnchor ~= true or tooltip ~= GameTooltip then
        return
    end
    anchoredOwner = parent
    tooltip:SetOwner(parent, anchors[MurgleDB.tooltip.anchor] or anchors.right)
end

function Tooltip.ApplyCursorAnchor()
    if not cursorUsable() then
        return
    end
    if MurgleDB.tooltip.cursorAnchor == true then
        if not cursorHooked then
            hooksecurefunc("GameTooltip_SetDefaultAnchor", applyCursor)
            cursorHooked = true
        end
        if
            anchoredOwner
            and GameTooltip:GetOwner() == anchoredOwner
            and (
                GameTooltip:GetAnchorType() == "ANCHOR_CURSOR"
                or GameTooltip:GetAnchorType() == "ANCHOR_CURSOR_RIGHT"
                or GameTooltip:GetAnchorType() == "ANCHOR_CURSOR_LEFT"
            )
        then
            applyCursor(GameTooltip, anchoredOwner)
        end
    elseif anchoredOwner then
        if
            GameTooltip:GetOwner() == anchoredOwner
            and (
                GameTooltip:GetAnchorType() == "ANCHOR_CURSOR"
                or GameTooltip:GetAnchorType() == "ANCHOR_CURSOR_RIGHT"
                or GameTooltip:GetAnchorType() == "ANCHOR_CURSOR_LEFT"
            )
        then
            GameTooltip_SetDefaultAnchor(GameTooltip, anchoredOwner)
        end
        anchoredOwner = nil
    end
end

function Tooltip.SetAnchor(anchor)
    if not anchors[anchor] then
        return
    end
    MurgleDB.tooltip.anchor = anchor
    Tooltip.ApplyCursorAnchor()
end

local function hideCombatTooltip()
    if MurgleDB.tooltip.hideInCombat ~= true or not InCombatLockdown() then
        return
    end
    local kinds = Enum.TooltipDataType
    local worldType = GameTooltip:IsTooltipType(kinds.Unit)
        or type(kinds.Object) == "number" and GameTooltip:IsTooltipType(kinds.Object)
        or type(kinds.Corpse) == "number" and GameTooltip:IsTooltipType(kinds.Corpse)
    if worldType and not GameTooltip:IsProtected() then
        GameTooltip:Hide()
    end
end

function Tooltip.ApplyCombatHide()
    if MurgleDB.tooltip.hideInCombat ~= true then
        if combatEvents then
            combatEvents:UnregisterEvent("PLAYER_REGEN_DISABLED")
        end
        return
    end
    if
        not GameTooltip
        or not Enum
        or not Enum.TooltipDataType
        or type(Enum.TooltipDataType.Unit) ~= "number"
        or type(GameTooltip.IsTooltipType) ~= "function"
        or type(GameTooltip.IsProtected) ~= "function"
        or GameTooltip:IsProtected()
        or type(GameTooltip.Show) ~= "function"
        or type(GameTooltip.Hide) ~= "function"
        or type(hooksecurefunc) ~= "function"
        or type(InCombatLockdown) ~= "function"
    then
        return
    end
    if not combatHooked then
        -- Native data processing calls Show even when reusing an already-shown
        -- tooltip. Hook after Show so processing cannot immediately undo Hide.
        hooksecurefunc(GameTooltip, "Show", hideCombatTooltip)
        combatHooked = true
    end
    if not combatEvents then
        combatEvents = CreateFrame("Frame")
        combatEvents:SetScript("OnEvent", hideCombatTooltip)
    end
    combatEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
    hideCombatTooltip()
end

function Tooltip.ApplyAll()
    Tooltip.ApplyCursorAnchor()
    Tooltip.ApplyCombatHide()
end

function Tooltip.Initialize()
    Tooltip.ApplyAll()
end
