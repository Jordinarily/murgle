local _, Murgle = ...
local Trainer = {}
Murgle.Trainer = Trainer

local events, button, queue, pending, purchasing
local sessionClosed = false
local function enabled()
    return MurgleDB and MurgleDB.automation and MurgleDB.automation.trainAll == true
end
local function integer(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end
local function safe()
    return enabled()
        and not sessionClosed
        and type(InCombatLockdown) == "function"
        and InCombatLockdown() == false
        and type(IsShiftKeyDown) == "function"
        and IsShiftKeyDown() == false
        and ClassTrainerFrame
        and type(ClassTrainerFrame.IsShown) == "function"
        and ClassTrainerFrame:IsShown()
        and type(IsTradeskillTrainer) == "function"
        and IsTradeskillTrainer() == false
        and C_Trainer
        and type(C_Trainer.GetTrainerType) == "function"
        and Enum
        and Enum.TrainerType
        and Enum.TrainerType.General ~= nil
        and C_Trainer.GetTrainerType() == Enum.TrainerType.General
end
local function cancel()
    queue, pending = nil, nil
end
local function available()
    if
        not safe()
        or type(GetNumTrainerServices) ~= "function"
        or type(GetTrainerServiceInfo) ~= "function"
        or type(GetTrainerServiceCost) ~= "function"
        or type(GetMoney) ~= "function"
        or type(BuyTrainerService) ~= "function"
    then
        return
    end
    local count = GetNumTrainerServices()
    if not integer(count) then
        return
    end
    local list, seen = {}, {}
    for index = 1, count do
        local name, kind, _, _, rank = GetTrainerServiceInfo(index)
        if kind == "available" then
            local cost, profession = GetTrainerServiceCost(index)
            if
                type(name) ~= "string"
                or name == ""
                or not integer(cost)
                or (profession ~= nil and profession ~= false)
            then
                return
            end
            if rank ~= nil and type(rank) ~= "string" then
                return
            end
            local key = name .. "\001" .. (rank or "")
            if seen[key] then
                return
            end
            seen[key] = true
            list[#list + 1] = { key = key, cost = cost, index = index }
        end
    end
    return list
end
local function same(a, b)
    return a and b and a.key == b.key and a.cost == b.cost
end
local function refresh()
    if not button then
        return
    end
    local list = available()
    if list then
        button:Show()
        button:SetEnabled(not queue and #list > 0)
    else
        button:Hide()
    end
end
local function purchase(list)
    local nextService = list[1]
    local money = GetMoney()
    if not nextService or not integer(money) or money < nextService.cost then
        cancel()
        return
    end
    pending = nextService
    purchasing = true
    -- The next TRAINER_UPDATE must prove this purchase left the available list.
    -- A synchronous update cancels the queue rather than recursively spending.
    BuyTrainerService(nextService.index)
    purchasing = false
end
local function click(_, mouseButton)
    if mouseButton ~= "LeftButton" or queue then
        return
    end
    local list = available()
    if not list or #list == 0 then
        return
    end
    queue = list
    purchase(list)
    refresh()
end
local function advance()
    if not queue then
        return
    end
    if purchasing then
        cancel()
        return
    end
    local list = available()
    if not list or not pending or #list ~= #queue - 1 then
        cancel()
        return
    end
    for i = 1, #list do
        if not same(list[i], queue[i + 1]) then
            cancel()
            return
        end
    end
    queue, pending = list, nil
    if #list == 0 then
        cancel()
        return
    end
    purchase(list)
end
local function ensureButton()
    if
        button
        or not ClassTrainerFrame
        or not ClassTrainerTrainButton
        or type(InCombatLockdown) ~= "function"
        or InCombatLockdown() ~= false
    then
        return
    end
    button = CreateFrame("Button", nil, ClassTrainerFrame, "UIPanelButtonTemplate")
    button:SetSize(100, 22)
    button:SetPoint("RIGHT", ClassTrainerTrainButton, "LEFT", -4, 0)
    button:SetText(Murgle.L.TRAIN_ALL)
    button:SetScript("OnClick", click)
    button:SetScript("OnEnter", function(self)
        local list = available()
        if not list or not GameTooltip or type(SetTooltipMoney) ~= "function" then
            return
        end
        local total = 0
        for _, service in ipairs(list) do
            total = total + service.cost
        end
        if not integer(total) then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Murgle.L.TRAIN_ALL)
        SetTooltipMoney(GameTooltip, total)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
end
local eventNames = {
    "TRAINER_SHOW",
    "TRAINER_UPDATE",
    "TRAINER_CLOSED",
    "PLAYER_MONEY",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "MODIFIER_STATE_CHANGED",
    "ADDON_LOADED",
}
function Trainer.ApplyAll()
    if not enabled() then
        cancel()
        if events then
            for _, event in ipairs(eventNames) do
                events:UnregisterEvent(event)
            end
        end
        if button then
            button:Hide()
        end
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", function(_, event)
            if not enabled() then
                Trainer.ApplyAll()
                return
            end
            if event == "TRAINER_SHOW" then
                sessionClosed = false
                cancel()
            elseif event == "TRAINER_CLOSED" then
                sessionClosed = true
                cancel()
            elseif event == "TRAINER_UPDATE" then
                advance()
            elseif event == "PLAYER_REGEN_DISABLED" or (event == "MODIFIER_STATE_CHANGED" and IsShiftKeyDown()) then
                cancel()
            end
            ensureButton()
            refresh()
        end)
    end
    for _, event in ipairs(eventNames) do
        events:RegisterEvent(event)
    end
    ensureButton()
    refresh()
end
function Trainer.Initialize()
    Trainer.ApplyAll()
end
