local UI = dofile("tests/ui_helpers.lua")

local function fixture(_, state)
    state.hooks, state.accepted, state.progressed, state.rewarded = 0, 0, 0, 0
    state.questID, state.choices, state.cost = 17, 0, 0
    local function visible()
        return {
            IsVisible = function()
                return not state.hidden
            end,
            IsEnabled = function()
                return not state.disabled
            end,
        }
    end
    QuestFrame = visible()
    QuestFrameDetailPanel, QuestFrameProgressPanel, QuestFrameRewardPanel = visible(), visible(), visible()
    QuestFrameAcceptButton, QuestFrameCompleteButton, QuestFrameCompleteQuestButton = visible(), visible(), visible()
    function QuestFrame:HookScript(script, callback)
        eq(script, "OnEvent")
        state.hooks = state.hooks + 1
        state.callback = callback
    end
    function state.fire(event, ...)
        if state.callback then
            state.callback(QuestFrame, event, ...)
        end
    end
    IsShiftKeyDown = function()
        return state.shift == true
    end
    GetQuestID = function()
        return state.questID
    end
    QuestFlagsPVP = function()
        return state.pvp == true
    end
    QuestGetAutoAccept = function()
        return state.nativeAuto == true
    end
    QuestIsFromAdventureMap = function()
        return state.adventure == true
    end
    QuestIsFromAreaTrigger = function()
        return state.area == true
    end
    GetNumQuestChoices = function()
        return state.choices
    end
    GetQuestMoneyToGet = function()
        return state.cost
    end
    IsQuestCompletable = function()
        return not state.incomplete
    end
    AcceptQuest = function()
        state.accepted = state.accepted + 1
    end
    CompleteQuest = function()
        state.progressed = state.progressed + 1
    end
    GetQuestReward = function(choice)
        eq(choice, 0, "must never choose a reward")
        state.rewarded = state.rewarded + 1
    end
end
local function enable(M, accept, turnIn)
    MurgleDB.automation.autoQuest, MurgleDB.automation.autoTurnIn = accept, turnIn
    M.Automation.ApplyAll()
end

test("quest automation is inert by default and hooks native events only once", function()
    UI.withAddon(function(M, state)
        eq(state.hooks, 0)
        eq(#state.frames, 1)
        enable(M, true, true)
        enable(M, true, true)
        eq(state.hooks, 1)
        state.fire("QUEST_DETAIL", 0)
        state.fire("QUEST_DETAIL", 0)
        eq(state.accepted, 1)
        state.fire("QUEST_PROGRESS")
        state.fire("QUEST_COMPLETE")
        state.fire("QUEST_COMPLETE")
        eq(state.progressed, 1)
        eq(state.rewarded, 1)
        enable(M, false, false)
        state.fire("QUEST_FINISHED")
        state.fire("QUEST_DETAIL", 0)
        eq(state.accepted, 1)
        eq(next(state.frames[1].events), nil)
    end, fixture)
end)

test("quest acceptance leaves PvP native autoaccepted and special offers manual", function()
    UI.withAddon(function(M, state)
        enable(M, true, false)
        for _, flag in ipairs({ "pvp", "nativeAuto", "adventure", "area" }) do
            state[flag] = true
            state.fire("QUEST_DETAIL", 0)
            state[flag] = false
        end
        state.fire("QUEST_DETAIL", 123)
        eq(state.accepted, 0)
        state.fire("QUEST_DETAIL", 0)
        eq(state.accepted, 1)
    end, fixture)
end)

test("quest actions cannot repeat through synchronous native event delivery", function()
    UI.withAddon(function(M, state)
        enable(M, true, true)
        AcceptQuest = function()
            state.accepted = state.accepted + 1
            if state.accepted < 3 then
                state.fire("QUEST_DETAIL", 0)
            end
        end
        CompleteQuest = function()
            state.progressed = state.progressed + 1
            if state.progressed < 3 then
                state.fire("QUEST_PROGRESS")
            end
            state.fire("QUEST_COMPLETE")
        end
        GetQuestReward = function(choice)
            eq(choice, 0)
            state.rewarded = state.rewarded + 1
            if state.rewarded < 3 then
                state.fire("QUEST_COMPLETE")
            end
        end
        state.fire("QUEST_DETAIL", 0)
        state.fire("QUEST_PROGRESS")
        eq(state.accepted, 1)
        eq(state.progressed, 1)
        eq(state.rewarded, 1)
        state.fire("QUEST_FINISHED")
        state.fire("QUEST_DETAIL", 0)
        eq(state.accepted, 2)
    end, fixture)
end)

test("quest turn in refuses every reward choice payment and unknown result", function()
    UI.withAddon(function(M, state)
        enable(M, false, true)
        for _, choices in ipairs({ 1, 2, -1, 0 / 0, "0", false }) do
            state.choices = choices
            state.fire("QUEST_PROGRESS")
            state.fire("QUEST_COMPLETE")
        end
        state.choices = nil
        state.fire("QUEST_COMPLETE")
        state.choices = 0
        for _, cost in ipairs({ 1, -1, 0 / 0, "0", false }) do
            state.cost = cost
            state.fire("QUEST_PROGRESS")
            state.fire("QUEST_COMPLETE")
        end
        state.cost = nil
        state.fire("QUEST_COMPLETE")
        eq(state.progressed + state.rewarded, 0)
        state.cost = 0
        state.incomplete = true
        state.fire("QUEST_PROGRESS")
        eq(state.progressed, 0)
        state.incomplete = false
        state.fire("QUEST_PROGRESS")
        state.fire("QUEST_COMPLETE")
        eq(state.progressed, 1)
        eq(state.rewarded, 1)
    end, fixture)
end)

test("quest automation skips Shift combat hidden disabled and invalid quest contexts", function()
    UI.withAddon(function(M, state)
        enable(M, true, true)
        for _, flag in ipairs({ "shift", "combat", "hidden", "disabled" }) do
            state[flag] = true
            state.fire("QUEST_DETAIL", 0)
            state.fire("QUEST_PROGRESS")
            state.fire("QUEST_COMPLETE")
            state[flag] = false
        end
        state.questID = 0
        state.fire("QUEST_DETAIL", 0)
        state.fire("QUEST_COMPLETE")
        eq(state.accepted + state.progressed + state.rewarded, 0)
        eq(M.GetDeferredCount(), 0, "never queue a stale quest action")
        state.questID = 18
        state.fire("QUEST_DETAIL", 0)
        eq(state.accepted, 1)
        state.fire("QUEST_FINISHED")
        state.fire("QUEST_DETAIL", 0)
        eq(state.accepted, 2, "later interaction may retry the same quest")
    end, fixture)
end)

test("quest automation missing APIs skip actions and explicit settings retry absent frame", function()
    UI.withAddon(function(M, state)
        local frame = QuestFrame
        QuestFrame = nil
        enable(M, true, true)
        eq(state.hooks, 0)
        QuestFrame = frame
        enable(M, true, true)
        QuestFlagsPVP = nil
        GetNumQuestChoices = nil
        state.fire("QUEST_DETAIL", 0)
        state.fire("QUEST_COMPLETE")
        eq(state.accepted + state.rewarded, 0)
        IsShiftKeyDown = nil
        state.fire("QUEST_PROGRESS")
        eq(state.progressed, 0)
    end, fixture)
end)

test("saved quest settings initialize and settings reset disables native hook actions", function()
    UI.withAddon(function(M, state)
        eq(state.hooks, 1)
        state.fire("QUEST_DETAIL", 0)
        eq(state.accepted, 1)
        M.Settings.Show()
        M.Settings.SelectCategory("Automation")
        local controls = {}
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                if region.text == M.L.AUTO_QUEST then
                    controls.accept = frame
                end
                if region.text == M.L.AUTO_TURN_IN then
                    controls.turnIn = frame
                end
            end
        end
        assert(controls.accept and controls.turnIn, "quest automation controls available")
        controls.turnIn:SetChecked(true)
        controls.turnIn.scripts.OnClick(controls.turnIn)
        eq(MurgleDB.automation.autoTurnIn, true)
        state.fire("QUEST_COMPLETE")
        eq(state.rewarded, 1)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(controls.accept:GetChecked(), false)
        eq(controls.turnIn:GetChecked(), false)
        state.fire("QUEST_FINISHED")
        state.fire("QUEST_DETAIL", 0)
        eq(state.accepted, 1)
    end, function(M, state)
        fixture(M, state)
        MurgleDB = { automation = { autoQuest = true } }
    end)
end)

local H = dofile("tests/helpers.lua")
local function withGreetings(fn)
    H.withGlobals({
        GossipFrame = false,
        C_GossipInfo = false,
        QuestFrameGreetingPanel = false,
        GetNumActiveQuests = false,
        GetActiveTitle = false,
        SelectActiveQuest = false,
    }, function()
        UI.withAddon(fn, function(M, state)
            fixture(M, state)
            state.selected, state.activeCount = 0, 1
            state.active = { { questID = 42, isComplete = true } }
            QuestFrameGreetingPanel = QuestFrameDetailPanel
            GetNumActiveQuests = function()
                return state.activeCount
            end
            GetActiveTitle = function()
                return "Quest", not state.incomplete
            end
            SelectActiveQuest = function(index)
                eq(index, 1)
                state.selected = state.selected + 1
            end
            GossipFrame = {
                IsVisible = function()
                    return not state.hidden
                end,
                HandleShow = function() end,
            }
            hooksecurefunc = function(frame, method, callback)
                local original = frame[method]
                frame[method] = function(self, ...)
                    original(self, ...)
                    callback(self, ...)
                end
            end
            C_GossipInfo = {
                GetActiveQuests = function()
                    return state.active
                end,
                SelectActiveQuest = function(id)
                    eq(id, 42)
                    state.selected = state.selected + 1
                    if state.reenter then
                        GossipFrame:HandleShow()
                    end
                end,
            }
        end)
    end)
end

test("auto turn in opens sole completed gossip quest without selecting services", function()
    withGreetings(function(M, state)
        GossipFrame:HandleShow()
        eq(state.selected, 0)
        enable(M, false, true)
        state.reenter = true
        GossipFrame:HandleShow()
        eq(state.selected, 1)
        state.reenter = false
        enable(M, false, false)
        GossipFrame:HandleShow()
        eq(state.selected, 1)
    end)
end)

test("completed gossip selection skips ambiguity invalid data Shift combat and hidden UI", function()
    withGreetings(function(M, state)
        enable(M, false, true)
        for _, active in ipairs({
            {},
            { { questID = 42, isComplete = false } },
            { { questID = 42, isComplete = true }, { questID = 43, isComplete = true } },
            { { questID = 0, isComplete = true } },
            { { questID = 42, isComplete = 1 } },
        }) do
            state.active = active
            GossipFrame:HandleShow()
        end
        state.active = { { questID = 42, isComplete = true } }
        for _, flag in ipairs({ "shift", "combat", "hidden" }) do
            state[flag] = true
            GossipFrame:HandleShow()
            state[flag] = false
        end
        eq(state.selected, 0)
        GossipFrame:HandleShow()
        eq(state.selected, 1)
    end)
end)

test("legacy greeting selects only a sole completed active quest with safety bypasses", function()
    withGreetings(function(M, state)
        enable(M, false, true)
        for _, count in ipairs({ 0, 2 }) do
            state.activeCount = count
            state.fire("QUEST_GREETING")
        end
        state.activeCount = 1
        for _, flag in ipairs({ "incomplete", "shift", "combat", "hidden" }) do
            state[flag] = true
            state.fire("QUEST_GREETING")
            state[flag] = false
        end
        eq(state.selected, 0)
        state.fire("QUEST_GREETING")
        eq(state.selected, 1)
    end)
end)

test("a single completed quest remains unambiguous beside incomplete active quests", function()
    withGreetings(function(M, state)
        enable(M, false, true)
        state.active = { { questID = 43, isComplete = false }, { questID = 42, isComplete = true } }
        GossipFrame:HandleShow()
        eq(state.selected, 1)
        state.activeCount = 2
        GetActiveTitle = function(index)
            return "Quest", index == 1
        end
        state.fire("QUEST_GREETING")
        eq(state.selected, 2)
    end)
end)
