local _, Murgle = ...
local Automation = {}
Murgle.Automation = Automation

local hookedFrames = {}
local acted = {}
local refreshDefinition, refreshButtonAction, refreshOnShow, refreshExpiration
local refreshEventTable, refreshAction
local refreshToast, refreshMinimize
local refreshing = false
local selectingQuest = false
local gossipHookedFrames = {}
local refreshKey = "SHARD_TRANSFER_IMMINENT_EVENT"

local function refreshMode()
    local settings = MurgleDB.automation
    if settings.autoWorldRefresh ~= true then
        return nil
    end
    if settings.worldRefreshMode == "hideOnly" or settings.worldRefreshMode == "acceptAndHide" then
        return settings.worldRefreshMode
    end
end

local function visible(frame)
    return frame and type(frame.IsVisible) == "function" and frame:IsVisible() == true
end

local function ready(panel, button)
    return visible(panel) and visible(button) and type(button.IsEnabled) == "function" and button:IsEnabled() == true
end

local function refreshDefinitionMatches()
    local definition = StaticPopupDialogs and StaticPopupDialogs[refreshKey]
    return definition == refreshDefinition
        and definition
        and definition.OnButton1 == refreshButtonAction
        and definition.OnShow == refreshOnShow
        and definition.GetExpirationText == refreshExpiration
        and definition.button1 == SHARD_TRANSFER_NOW_BUTTON
        and definition.button2 == OKAY
        and definition.OnHide == nil
        and definition.OnCancel == nil
        and definition.OnButton2 == nil
end

local function refreshDialogSafe(dialog)
    return dialog
        and dialog.which == refreshKey
        and dialog.dialogInfo == refreshDefinition
        and dialog.customOnHideScript == nil
        and type(dialog.IsProtected) == "function"
        and dialog:IsProtected() == false
        and type(dialog.Hide) == "function"
        and visible(dialog)
end

local function toastMatches(frame, expected, mixin)
    return frame == expected
        and frame
        and mixin
        and frame.Start == mixin.Start
        and type(frame.Start) == "function"
        and frame.OnClick == mixin.OnClick
        and type(frame.OnClick) == "function"
        and type(frame.IsProtected) == "function"
        and frame:IsProtected() == false
        and type(frame.IsEventRegistered) == "function"
        and frame:IsEventRegistered("SHARD_TRANSFER_IMMINENT")
        and type(frame.Hide) == "function"
end

local function onRefreshWarning()
    local mode = refreshMode()
    if
        not mode
        or refreshing
        or GameEvent ~= refreshEventTable
        or not refreshDefinitionMatches()
        or type(InCombatLockdown) ~= "function"
        or InCombatLockdown() ~= false
        or type(IsShiftKeyDown) ~= "function"
        or IsShiftKeyDown() ~= false
        or type(StaticPopup_FindVisible) ~= "function"
    then
        return
    end
    local dialog = StaticPopup_FindVisible(refreshKey)
    if
        not refreshDialogSafe(dialog)
        or type(dialog.GetButton1) ~= "function"
        or not ready(dialog, dialog:GetButton1())
    then
        return
    end
    if mode == "acceptAndHide" then
        if not C_PlayerInteractionManager or C_PlayerInteractionManager.ShardTransferConfirm ~= refreshAction then
            return
        end
        if refreshToast then
            -- Either native event order is possible; the toast may already be
            -- hidden. A stale hook must not suppress the manual fallback.
            if not toastMatches(refreshToast, ShardTransferImminentFrame, ShardTransferImminentMixin) then
                return
            end
        else
            -- The explicit opt-in calls only the documented refresh action, never
            -- a generic popup callback. Its synchronous events cannot accept twice.
            refreshing = true
            refreshAction()
            refreshing = false
        end
    end
    -- Acceptance may synchronously close or reuse the pooled dialog.
    if refreshDefinitionMatches() and StaticPopup_FindVisible(refreshKey) == dialog and refreshDialogSafe(dialog) then
        dialog:Hide()
    end
end

local function applyWorldRefresh()
    if refreshEventTable or not refreshMode() then
        return
    end
    local definition = StaticPopupDialogs and StaticPopupDialogs[refreshKey]
    if
        not GameEvent
        or type(GameEvent.HandleShardTransferImminentEvent) ~= "function"
        or type(hooksecurefunc) ~= "function"
        or type(StaticPopup_FindVisible) ~= "function"
        or not definition
        or type(definition.OnButton1) ~= "function"
        or type(definition.OnShow) ~= "function"
        or type(definition.GetExpirationText) ~= "function"
        or type(SHARD_TRANSFER_NOW_BUTTON) ~= "string"
        or type(OKAY) ~= "string"
        or definition.button1 ~= SHARD_TRANSFER_NOW_BUTTON
        or definition.button2 ~= OKAY
        or definition.OnHide ~= nil
        or definition.OnCancel ~= nil
        or definition.OnButton2 ~= nil
        or not C_PlayerInteractionManager
        or type(C_PlayerInteractionManager.ShardTransferConfirm) ~= "function"
    then
        return
    end
    refreshDefinition, refreshButtonAction = definition, definition.OnButton1
    refreshOnShow, refreshExpiration = definition.OnShow, definition.GetExpirationText
    refreshEventTable, refreshAction = GameEvent, C_PlayerInteractionManager.ShardTransferConfirm
    -- Scope is the automatic warning. Manual/immediate refresh prompts stay native.
    hooksecurefunc(GameEvent, "HandleShardTransferImminentEvent", onRefreshWarning)
end

local function toastSafe(frame, expected, mixin)
    return toastMatches(frame, expected, mixin) and visible(frame)
end

local function onToastWarning(frame, event)
    local mode = refreshMode()
    if
        event ~= "SHARD_TRANSFER_IMMINENT"
        or not mode
        or refreshing
        or type(InCombatLockdown) ~= "function"
        or InCombatLockdown() ~= false
        or type(IsShiftKeyDown) ~= "function"
        or IsShiftKeyDown() ~= false
    then
        return
    end
    local primary = frame == refreshToast
    local expected = primary and ShardTransferImminentFrame or ShardTransferImminentMinimizeButton
    local mixin = primary and ShardTransferImminentMixin or ShardTransferImminentMinimizeMixin
    if not toastSafe(frame, expected, mixin) then
        return
    end
    if mode == "acceptAndHide" and primary then
        if
            not refreshDefinitionMatches()
            or not C_PlayerInteractionManager
            or C_PlayerInteractionManager.ShardTransferConfirm ~= refreshAction
        then
            return
        end
        refreshing = true
        refreshAction()
        refreshing = false
    end
    expected = primary and ShardTransferImminentFrame or ShardTransferImminentMinimizeButton
    if toastSafe(frame, expected, mixin) then
        frame:Hide()
    end
end

local function applyRefreshToast()
    if not refreshMode() then
        return
    end
    local function install(frame, mixin)
        if
            not frame
            or not mixin
            or type(frame.HookScript) ~= "function"
            or type(mixin.Start) ~= "function"
            or frame.Start ~= mixin.Start
            or type(mixin.OnClick) ~= "function"
            or frame.OnClick ~= mixin.OnClick
        then
            return
        end
        -- Post-native OnEvent, not OnShow: manual re-opening stays manual.
        frame:HookScript("OnEvent", onToastWarning)
        return frame
    end
    if not refreshToast then
        refreshToast = install(ShardTransferImminentFrame, ShardTransferImminentMixin)
    end
    if not refreshMinimize then
        refreshMinimize = install(ShardTransferImminentMinimizeButton, ShardTransferImminentMinimizeMixin)
    end
end

function Automation.CanTurnIn(choices, cost)
    return choices == 0 and cost == 0
end

local function canSelectQuest(frame)
    return MurgleDB.automation.autoTurnIn == true
        and not selectingQuest
        and type(IsShiftKeyDown) == "function"
        and IsShiftKeyDown() == false
        and type(InCombatLockdown) == "function"
        and InCombatLockdown() == false
        and visible(frame)
end

local function selectGossipQuest(frame)
    if
        frame ~= GossipFrame
        or not canSelectQuest(frame)
        or not C_GossipInfo
        or type(C_GossipInfo.GetActiveQuests) ~= "function"
        or type(C_GossipInfo.SelectActiveQuest) ~= "function"
    then
        return
    end
    local quests = C_GossipInfo.GetActiveQuests()
    if type(quests) ~= "table" then
        return
    end
    local id
    for _, quest in ipairs(quests) do
        if type(quest) ~= "table" or type(quest.isComplete) ~= "boolean" then
            return
        end
        if quest.isComplete then
            if id then
                return
            end
            id = quest.questID
            if type(id) ~= "number" or id <= 0 or id >= math.huge or id ~= math.floor(id) then
                return
            end
        end
    end
    if not id then
        return
    end
    -- Select only the quest entry. Reward choices and costs remain guarded by
    -- the existing progress/reward flow; gossip service options are never used.
    selectingQuest = true
    C_GossipInfo.SelectActiveQuest(id)
    selectingQuest = false
end

local function selectGreetingQuest(frame)
    if
        not canSelectQuest(frame)
        or not visible(QuestFrameGreetingPanel)
        or type(GetNumActiveQuests) ~= "function"
        or type(GetActiveTitle) ~= "function"
        or type(SelectActiveQuest) ~= "function"
    then
        return
    end
    local count = GetNumActiveQuests()
    if type(count) ~= "number" or count <= 0 or count >= math.huge or count ~= math.floor(count) then
        return
    end
    local selected
    for index = 1, count do
        local _, complete = GetActiveTitle(index)
        if type(complete) ~= "boolean" then
            return
        end
        if complete then
            if selected then
                return
            end
            selected = index
        end
    end
    if selected then
        selectingQuest = true
        SelectActiveQuest(selected)
        selectingQuest = false
    end
end

local function onQuestEvent(frame, event, questStartItemID)
    local settings = MurgleDB.automation
    if settings.autoQuest ~= true and settings.autoTurnIn ~= true then
        return
    end
    if frame ~= QuestFrame then
        return
    end
    if event == "QUEST_GREETING" then
        selectGreetingQuest(frame)
        return
    end
    if event == "QUEST_FINISHED" then
        acted = {}
        return
    end
    if event ~= "QUEST_DETAIL" and event ~= "QUEST_PROGRESS" and event ~= "QUEST_COMPLETE" then
        return
    end
    if
        type(IsShiftKeyDown) ~= "function"
        or IsShiftKeyDown() ~= false
        or type(InCombatLockdown) ~= "function"
        or InCombatLockdown() ~= false
        or type(GetQuestID) ~= "function"
        or not visible(frame)
    then
        return
    end
    local questID = GetQuestID()
    if type(questID) ~= "number" or questID <= 0 or questID >= math.huge or questID ~= math.floor(questID) then
        return
    end
    if acted[event] == questID then
        return
    end
    local action
    if event == "QUEST_DETAIL" then
        if
            settings.autoQuest ~= true
            or (questStartItemID ~= nil and questStartItemID ~= 0)
            or not ready(QuestFrameDetailPanel, QuestFrameAcceptButton)
            or type(QuestFlagsPVP) ~= "function"
            or QuestFlagsPVP() ~= false
            or type(QuestGetAutoAccept) ~= "function"
            or QuestGetAutoAccept() ~= false
            or type(QuestIsFromAdventureMap) ~= "function"
            or QuestIsFromAdventureMap() ~= false
            or type(QuestIsFromAreaTrigger) ~= "function"
            or QuestIsFromAreaTrigger() ~= false
            or type(AcceptQuest) ~= "function"
        then
            return
        end
        action = AcceptQuest
    else
        if
            settings.autoTurnIn ~= true
            or type(GetNumQuestChoices) ~= "function"
            or type(GetQuestMoneyToGet) ~= "function"
            or not Automation.CanTurnIn(GetNumQuestChoices(), GetQuestMoneyToGet())
        then
            return
        end
        if event == "QUEST_PROGRESS" then
            if
                not ready(QuestFrameProgressPanel, QuestFrameCompleteButton)
                or type(IsQuestCompletable) ~= "function"
                or IsQuestCompletable() ~= true
                or type(CompleteQuest) ~= "function"
            then
                return
            end
            action = CompleteQuest
        else
            if
                not ready(QuestFrameRewardPanel, QuestFrameCompleteQuestButton)
                or type(GetQuestReward) ~= "function"
            then
                return
            end
            action = GetQuestReward
        end
    end
    -- Mark before the action: it can synchronously trigger another quest event.
    acted[event] = questID
    if event == "QUEST_COMPLETE" then
        action(0)
    else
        action()
    end
end

function Automation.ApplyAll()
    applyWorldRefresh()
    applyRefreshToast()
    if MurgleDB.automation.autoQuest ~= true and MurgleDB.automation.autoTurnIn ~= true then
        acted = {}
        return
    end
    local gossip = GossipFrame
    if
        MurgleDB.automation.autoTurnIn == true
        and gossip
        and not gossipHookedFrames[gossip]
        and type(gossip.HandleShow) == "function"
        and type(hooksecurefunc) == "function"
    then
        -- Native HandleShow finishes populating and displaying the gossip UI.
        hooksecurefunc(gossip, "HandleShow", selectGossipQuest)
        gossipHookedFrames[gossip] = true
    end
    local frame = QuestFrame
    if not frame or type(frame.HookScript) ~= "function" or hookedFrames[frame] then
        return
    end
    -- Run after Blizzard has populated the appropriate panel and button state.
    frame:HookScript("OnEvent", onQuestEvent)
    hookedFrames[frame] = true
end

function Automation.Initialize()
    Automation.ApplyAll()
end
