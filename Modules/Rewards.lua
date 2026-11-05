local _, Murgle = ...
local Rewards = {}
Murgle.Rewards = Rewards

local installed, active = false, false
local events
local markers = {}

local function enabled()
    return MurgleDB and MurgleDB.quests and MurgleDB.quests.rewardValues == true
end

local function available()
    return type(QuestInfo_Display) == "function"
        and type(hooksecurefunc) == "function"
        and type(CreateFrame) == "function"
        and type(GetNumQuestChoices) == "function"
        and type(GetQuestItemInfoLootType) == "function"
        and type(GetQuestItemInfo) == "function"
        and type(GetQuestItemLink) == "function"
        and type(InCombatLockdown) == "function"
        and C_Item
        and type(C_Item.GetItemInfo) == "function"
        and QuestInfoRewardsFrame
        and type(QuestInfoRewardsFrame.HookScript) == "function"
        and QuestInfoFrame
        and QUEST_TEMPLATE_REWARD
        and QUEST_TEMPLATE_DETAIL
end

local function safe(frame)
    return frame
        and type(frame.IsShown) == "function"
        and type(frame.IsForbidden) == "function"
        and frame:IsForbidden() == false
        and type(frame.IsProtected) == "function"
        and frame:IsProtected() == false
end

local function clear()
    for _, marker in pairs(markers) do
        marker:Hide()
    end
    if events then
        events:UnregisterAllEvents()
    end
end

local function integer(value, positive)
    return type(value) == "number"
        and value == value
        and value < math.huge
        and value >= (positive and 1 or 0)
        and value == math.floor(value)
end

local function refresh()
    clear()
    local frame = QuestInfoRewardsFrame
    if
        not active
        or not enabled()
        or not available()
        or InCombatLockdown() ~= false
        or not safe(frame)
        or not frame:IsShown()
        or QuestInfoFrame.rewardsFrame ~= frame
        or QuestInfoFrame.questLog
        or QuestInfoFrame.mapView
        or type(frame.RewardButtons) ~= "table"
    then
        return
    end
    local count = GetNumQuestChoices()
    if not integer(count, true) or count < 2 or count > #frame.RewardButtons then
        return
    end
    local winner, highest, tied, pending = nil, 0, false, false
    for i = 1, count do
        local button = frame.RewardButtons[i]
        if
            not safe(button)
            or type(button.GetParent) ~= "function"
            or button:GetParent() ~= frame
            or type(button.GetID) ~= "function"
            or button:GetID() ~= i
            or button.type ~= "choice"
            or button.objectType ~= "item"
            or button.currencyInfo
            or not button:IsShown()
            or not button.Icon
            or type(button.CreateTexture) ~= "function"
            or GetQuestItemInfoLootType("choice", i) ~= 0
        then
            return
        end
        local _, _, quantity = GetQuestItemInfo("choice", i)
        local link = GetQuestItemLink("choice", i)
        if not integer(quantity, true) then
            pending = true
        elseif type(link) ~= "string" or link == "" then
            pending = true
        else
            local _, cachedLink, _, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(link)
            if cachedLink ~= link or not integer(price, false) then
                pending = true
            else
                local total = price * quantity
                if not integer(total, false) or total > 9007199254740991 then
                    return
                end
                if total > highest then
                    winner, highest, tied = button, total, false
                elseif total == highest then
                    tied = true
                end
            end
        end
    end
    events:RegisterEvent("QUEST_ITEM_UPDATE")
    if pending then
        events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        return
    end
    if not winner or tied or highest == 0 then
        return
    end
    local marker = markers[winner]
    if not marker then
        marker = winner:CreateTexture(nil, "OVERLAY", nil, 7)
        marker:SetAtlas("coin-gold")
        marker:SetSize(12, 12)
        marker:SetPoint("TOPLEFT", winner.Icon, "TOPLEFT", 2, -2)
        markers[winner] = marker
    end
    marker:Show()
end

function Rewards.ApplyAll()
    clear()
    if not enabled() or not available() then
        active = false
        return
    end
    if not installed then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", function()
            refresh()
        end)
        hooksecurefunc("QuestInfo_Display", function(template, _, _, _, mapView)
            if not enabled() then
                return
            end
            active = mapView ~= true and (template == QUEST_TEMPLATE_REWARD or template == QUEST_TEMPLATE_DETAIL)
            refresh()
        end)
        QuestInfoRewardsFrame:HookScript("OnHide", function()
            active = false
            clear()
        end)
        installed = true
    end
    refresh()
end

function Rewards.Initialize()
    Rewards.ApplyAll()
end
