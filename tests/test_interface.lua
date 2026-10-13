local H = dofile("tests/helpers.lua")

local function withInterface(fn)
    local function frame(shown)
        local f = { shown = shown, hides = 0, shows = 0 }
        function f:IsShown()
            return self.shown
        end
        function f:Hide()
            self.shown = false
            self.hides = self.hides + 1
        end
        function f:Show()
            self.shown = true
            self.shows = self.shows + 1
        end
        return f
    end
    local menu, bags = frame(true), frame(false)
    local pending, combat = {}, false
    H.withGlobals({
        MicroMenu = menu,
        BagsBar = bags,
        MurgleDB = { interface = {} },
        CreateFrame = function()
            error("interface must not create event frames")
        end,
    }, function()
        local M = {
            DeferUntilOutOfCombat = function(key, fn)
                pending[key] = nil
                if combat then
                    pending[key] = fn
                else
                    fn()
                end
            end,
        }
        H.loadAddonFile("Modules/Interface.lua", M)
        fn(M, menu, bags, pending, function(value)
            combat = value
        end)
    end)
end

test("disabled interface options leave Blizzard frames untouched", function()
    withInterface(function(M, menu, bags)
        M.Interface.Initialize()
        eq(menu.hides + menu.shows + bags.hides + bags.shows, 0)
    end)
end)

test("interface restores original visibility and repeated apply preserves it", function()
    withInterface(function(M, menu, bags)
        MurgleDB.interface.hideMicroMenu = true
        MurgleDB.interface.hideBagBar = true
        M.Interface.ApplyAll()
        M.Interface.ApplyAll()
        eq(menu.shown, false)
        eq(bags.shown, false)
        MurgleDB.interface.hideMicroMenu = false
        MurgleDB.interface.hideBagBar = false
        M.Interface.ApplyAll()
        eq(menu.shown, true)
        eq(bags.shown, false)
        eq(bags.shows, 0)
    end)
end)

test("interface defers changes and applies latest saved choice", function()
    withInterface(function(M, menu, bags, pending, setCombat)
        setCombat(true)
        MurgleDB.interface.hideMicroMenu = true
        M.Interface.ApplyMicroMenu()
        eq(menu.shown, true)
        MurgleDB.interface.hideMicroMenu = false
        M.Interface.ApplyMicroMenu()
        setCombat(false)
        for _, fn in pairs(pending) do
            fn()
        end
        eq(menu.hides, 0)
        MurgleDB.interface.hideMicroMenu = true
        M.Interface.ApplyMicroMenu()
        eq(menu.shown, false)
    end)
end)

test("interface restores owned frames without changing replacement globals", function()
    withInterface(function(M, menu, bags)
        MurgleDB.interface.hideMicroMenu = true
        MurgleDB.interface.hideBagBar = true
        M.Interface.ApplyAll()
        local replacementMenu = H.newVisibilityFrame(false)
        local replacementBags = H.newVisibilityFrame(true)
        MicroMenu, BagsBar = replacementMenu, replacementBags
        M.Interface.ApplyAll()
        eq(replacementMenu.changes, 0)
        eq(replacementBags.changes, 0)
        MurgleDB.interface.hideMicroMenu = false
        MurgleDB.interface.hideBagBar = false
        M.Interface.ApplyAll()
        eq(menu.shown, true)
        eq(bags.shown, false)
        eq(replacementMenu.changes, 0)
        eq(replacementBags.changes, 0)

        -- A later enable must take fresh ownership after restoring the originals.
        MurgleDB.interface.hideMicroMenu = true
        MurgleDB.interface.hideBagBar = true
        M.Interface.ApplyAll()
        eq(replacementMenu.shown, false)
        eq(replacementBags.shown, false)
        MurgleDB.interface.hideMicroMenu = false
        MurgleDB.interface.hideBagBar = false
        M.Interface.ApplyAll()
        eq(replacementMenu.shown, false)
        eq(replacementBags.shown, true)
    end)
end)

test("missing interface frame retries on explicit apply without affecting other feature", function()
    withInterface(function(M, menu, bags)
        MicroMenu = nil
        MurgleDB.interface.hideMicroMenu = true
        MurgleDB.interface.hideBagBar = true
        M.Interface.ApplyAll()
        MicroMenu = menu
        M.Interface.ApplyAll()
        eq(menu.hides, 1)
        eq(bags.shown, false)
    end)
end)

test("disabled interface options do not queue work during combat", function()
    withInterface(function(M, menu, bags, pending, setCombat)
        setCombat(true)
        M.Interface.Initialize()
        eq(next(pending), nil)
    end)
end)

local UI = dofile("tests/ui_helpers.lua")
local function trackerFixtures()
    ObjectiveTrackerFrame = H.newVisibilityFrame(true)
    ObjectiveTrackerFrame.Header = H.newVisibilityFrame(true)
    QuestObjectiveTracker = H.newVisibilityFrame(true)
    QuestObjectiveTracker.Header = H.newVisibilityFrame(false)
end

test("tracker cleanup hides only captured headers and restores original visibility", function()
    UI.withAddon(function(M)
        eq(ObjectiveTrackerFrame.Header.shown, false)
        eq(ObjectiveTrackerFrame.changes, 0)
        eq(QuestObjectiveTracker.changes, 0)
        M.ApplyAllSettings()
        M.ResetDB()
        eq(ObjectiveTrackerFrame.Header.shown, true)
        eq(QuestObjectiveTracker.Header.shown, false)
    end, function(M)
        trackerFixtures()
        MurgleDB = M.ApplyDefaults({ interface = { objectiveTrackerHeaders = true } })
    end)
end)

test("tracker checkbox defers cleanup and reset refreshes its saved state", function()
    UI.withAddon(function(M, state)
        trackerFixtures()
        QuestObjectiveTracker.Header.shown = true
        M.Settings.Show()
        local checkbox
        for _, f in ipairs(state.frames) do
            if f.kind == "CheckButton" then
                for _, region in ipairs(f.regions) do
                    if region.text == M.L.TRACKER_HEADERS then
                        checkbox = f
                    end
                end
            end
        end
        assert(checkbox, "tracker header checkbox missing")
        state.combat = true
        checkbox:SetChecked(true)
        checkbox.scripts.OnClick(checkbox)
        eq(MurgleDB.interface.objectiveTrackerHeaders, true)
        eq(ObjectiveTrackerFrame.Header.changes, 0)
        state.combat = false
        local core = state.frames[1]
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(ObjectiveTrackerFrame.Header.shown, false)
        eq(QuestObjectiveTracker.Header.shown, false)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(checkbox:GetChecked(), false)
        eq(ObjectiveTrackerFrame.Header.shown, true)
        eq(QuestObjectiveTracker.Header.shown, true)
        eq(M.GetDeferredCount(), 0)
        eq(next(core.events), nil)
    end)
end)

test("missing tracker section does not block the main header and retries on explicit apply", function()
    UI.withAddon(function(M)
        trackerFixtures()
        QuestObjectiveTracker = nil
        MurgleDB.interface.objectiveTrackerHeaders = true
        M.ApplyAllSettings()
        eq(ObjectiveTrackerFrame.Header.shown, false)
        QuestObjectiveTracker = { Header = H.newVisibilityFrame(true) }
        M.ApplyAllSettings()
        eq(QuestObjectiveTracker.Header.shown, false)
        M.ResetDB()
        eq(ObjectiveTrackerFrame.Header.shown, true)
    end)
end)

test("deferred reset restores owned tracker headers after their parent references disappear", function()
    UI.withAddon(function(M, state)
        trackerFixtures()
        local mainHeader, questHeader = ObjectiveTrackerFrame.Header, QuestObjectiveTracker.Header
        MurgleDB.interface.objectiveTrackerHeaders = true
        M.Interface.ApplyTrackerHeaders()
        eq(mainHeader.shown, false)
        eq(questHeader.shown, false)
        state.combat = true
        M.ResetDB()
        ObjectiveTrackerFrame, QuestObjectiveTracker = nil, nil
        state.combat = false
        local core = state.frames[1]
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(mainHeader.shown, true)
        eq(questHeader.shown, false)
        eq(M.GetDeferredCount(), 0)
        eq(next(core.events), nil)

        trackerFixtures()
        MurgleDB.interface.objectiveTrackerHeaders = true
        M.Interface.ApplyTrackerHeaders()
        eq(ObjectiveTrackerFrame.Header.shown, false)
        M.ResetDB()
        eq(ObjectiveTrackerFrame.Header.shown, true)
    end)
end)

local function zoneFixture()
    local frame = H.newEventFrame()
    frame.shown = true
    frame.hides = 0
    function frame:Hide()
        self.shown = false
        self.hides = self.hides + 1
    end
    function frame:IsProtected()
        return self.protected == true
    end
    frame:RegisterEvent("ZONE_CHANGED")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("UNRELATED_EVENT")
    return frame
end

test("zone suppression removes only owned events and disable restores their original registration", function()
    UI.withAddon(function(M, state)
        local zone, subzone = ZoneTextFrame, SubZoneTextFrame
        eq(zone:IsEventRegistered("ZONE_CHANGED"), false)
        eq(zone:IsEventRegistered("ZONE_CHANGED_NEW_AREA"), false)
        eq(zone:IsEventRegistered("UNRELATED_EVENT"), true)
        eq(zone.shown, false)
        eq(subzone.shown, false)
        M.Interface.ApplyZoneText()
        MurgleDB.interface.hideZoneText = false
        M.Interface.ApplyZoneText()
        eq(zone:IsEventRegistered("ZONE_CHANGED"), true)
        eq(zone:IsEventRegistered("ZONE_CHANGED_NEW_AREA"), true)
        eq(zone:IsEventRegistered("ZONE_CHANGED_INDOORS"), false)
        eq(zone.shown, false, "disabling must not replay a stale announcement")
        local hides = zone.hides
        M.Interface.ApplyZoneText()
        eq(zone.hides, hides)
        eq(next(state.frames[1].events), nil)
        eq(#state.frames, 1)
    end, function()
        ZoneTextFrame, SubZoneTextFrame = zoneFixture(), zoneFixture()
    end)
end)

test("disabled zone suppression is inert and combat applies the latest choice", function()
    UI.withAddon(function(M, state)
        eq(ZoneTextFrame.hides, 0)
        eq(M.GetDeferredCount(), 0)
        MurgleDB.interface.hideZoneText = true
        M.Interface.ApplyZoneText()
        MurgleDB.interface.hideZoneText = false
        M.Interface.ApplyZoneText()
        state.combat = false
        local core = state.frames[1]
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(ZoneTextFrame.hides, 0)
        eq(ZoneTextFrame:IsEventRegistered("ZONE_CHANGED"), true)
        M.ResetDB()
        eq(ZoneTextFrame.shown, false, "reset enables the approved default")
        eq(ZoneTextFrame:IsEventRegistered("ZONE_CHANGED"), false)
    end, function(_, state)
        ZoneTextFrame, SubZoneTextFrame = zoneFixture(), zoneFixture()
        MurgleDB = { interface = { hideZoneText = false } }
        state.combat = true
    end)
end)

test("zone suppression restores the original event owner when globals change", function()
    UI.withAddon(function(M)
        local original = ZoneTextFrame
        local replacement = zoneFixture()
        ZoneTextFrame = replacement
        SubZoneTextFrame = nil
        MurgleDB.interface.hideZoneText = false
        M.Interface.ApplyZoneText()
        eq(original:IsEventRegistered("ZONE_CHANGED"), true)
        eq(replacement.hides, 0)
    end, function()
        ZoneTextFrame, SubZoneTextFrame = zoneFixture(), zoneFixture()
    end)
end)

test("zone suppression skips protected or incompatible frames without disrupting startup", function()
    for _, mode in ipairs({ "protected", "incompatible", "missing" }) do
        UI.withAddon(function(M, state)
            if ZoneTextFrame then
                eq(ZoneTextFrame.hides, 0)
                eq(ZoneTextFrame:IsEventRegistered("ZONE_CHANGED"), true)
            end
            eq(SubZoneTextFrame.hides, 0)
            eq(M.GetDeferredCount(), 0)
            eq(next(state.frames[1].events), nil)
            eq(type(SlashCmdList.MURGLE), "function")
        end, function()
            ZoneTextFrame, SubZoneTextFrame = zoneFixture(), zoneFixture()
            if mode == "protected" then
                ZoneTextFrame.protected = true
            elseif mode == "incompatible" then
                ZoneTextFrame.UnregisterEvent = false
            else
                ZoneTextFrame = nil
            end
        end)
    end
end)

test("zone checkbox persists changes and reset restores its default and event suppression", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        local checkbox
        for _, frame in ipairs(state.frames) do
            if frame.kind == "CheckButton" then
                for _, region in ipairs(frame.regions) do
                    if region.text == M.L.HIDE_ZONE_TEXT then
                        checkbox = frame
                    end
                end
            end
        end
        assert(checkbox, "zone text checkbox missing")
        eq(checkbox:GetChecked(), true)
        checkbox:SetChecked(false)
        checkbox.scripts.OnClick(checkbox)
        eq(MurgleDB.interface.hideZoneText, false)
        eq(ZoneTextFrame:IsEventRegistered("ZONE_CHANGED"), true)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(checkbox:GetChecked(), true)
        eq(ZoneTextFrame:IsEventRegistered("ZONE_CHANGED"), false)
    end, function()
        ZoneTextFrame, SubZoneTextFrame = zoneFixture(), zoneFixture()
    end)
end)

local function bossFixture(state)
    BossBanner = H.newEventFrame()
    BossBanner.stops = 0
    function BossBanner:IsProtected()
        return false
    end
    function BossBanner:StopBanner()
        self.stops = self.stops + 1
    end
    BossBanner:RegisterEvent("BOSS_KILL")
    BossBanner:RegisterEvent("UNRELATED_EVENT")
    TopBannerMgr = { currentBanner = { frame = BossBanner } }
    local other = { plays = 0 }
    function other:PlayBanner()
        self.plays = self.plays + 1
    end
    TopBannerQueue = { { frame = BossBanner }, { frame = other }, { frame = BossBanner } }
    state.otherBanner = other
    state.finished = 0
    TopBannerManager_BannerFinished = function()
        state.finished = state.finished + 1
        TopBannerMgr.currentBanner = table.remove(TopBannerQueue, 1)
        if TopBannerMgr.currentBanner then
            TopBannerMgr.currentBanner.frame:PlayBanner(TopBannerMgr.currentBanner.data)
        end
    end
end

test("boss suppression removes only boss queue entries and advances its active banner", function()
    UI.withAddon(function(M, state)
        eq(BossBanner:IsEventRegistered("BOSS_KILL"), false)
        eq(BossBanner:IsEventRegistered("UNRELATED_EVENT"), true)
        eq(BossBanner.stops, 1)
        eq(state.finished, 1)
        eq(TopBannerMgr.currentBanner.frame, state.otherBanner)
        eq(#TopBannerQueue, 0)
        M.Interface.ApplyBossBanner()
        eq(state.finished, 1)
        MurgleDB.interface.hideBossBanner = false
        M.Interface.ApplyBossBanner()
        eq(BossBanner:IsEventRegistered("BOSS_KILL"), true)
        eq(BossBanner:IsEventRegistered("ENCOUNTER_LOOT_RECEIVED"), false)
        eq(state.finished, 1)
        eq(#state.frames, 1)
    end, function(_, state)
        bossFixture(state)
    end)
end)

test("boss suppression never finishes a different current banner", function()
    UI.withAddon(function(M, state)
        eq(TopBannerMgr.currentBanner.frame, state.otherBanner)
        eq(state.finished, 0)
        eq(BossBanner.stops, 0)
        eq(#TopBannerQueue, 1)
        eq(TopBannerQueue[1].frame, state.otherBanner)
    end, function(_, state)
        bossFixture(state)
        TopBannerMgr.currentBanner = { frame = state.otherBanner }
    end)
end)

test("boss suppression defers in combat and cancellation leaves native state untouched", function()
    UI.withAddon(function(M, state)
        eq(BossBanner:IsEventRegistered("BOSS_KILL"), true)
        eq(state.finished, 0)
        eq(#TopBannerQueue, 3)
        MurgleDB.interface.hideBossBanner = false
        M.Interface.ApplyBossBanner()
        state.combat = false
        local core = state.frames[1]
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(BossBanner:IsEventRegistered("BOSS_KILL"), true)
        eq(state.finished, 0)
        eq(#TopBannerQueue, 3)
        eq(M.GetDeferredCount(), 0)
        eq(next(core.events), nil)
        M.ResetDB()
        eq(BossBanner:IsEventRegistered("BOSS_KILL"), false)
    end, function(_, state)
        bossFixture(state)
        state.combat = true
    end)
end)

test("unsupported boss manager fails closed before event or queue changes", function()
    UI.withAddon(function(M, state)
        eq(BossBanner:IsEventRegistered("BOSS_KILL"), true)
        eq(BossBanner.stops, 0)
        eq(#TopBannerQueue, 3)
        eq(next(state.frames[1].events), nil)
    end, function(_, state)
        bossFixture(state)
        TopBannerManager_BannerFinished = nil
    end)
end)

test("boss checkbox restores native events and reset resumes suppression", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        local checkbox
        for _, frame in ipairs(state.frames) do
            if frame.kind == "CheckButton" then
                for _, region in ipairs(frame.regions) do
                    if region.text == M.L.HIDE_BOSS_BANNER then
                        checkbox = frame
                    end
                end
            end
        end
        assert(checkbox, "boss banner checkbox missing")
        eq(checkbox:GetChecked(), true)
        checkbox:SetChecked(false)
        checkbox.scripts.OnClick(checkbox)
        eq(BossBanner:IsEventRegistered("BOSS_KILL"), true)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(checkbox:GetChecked(), true)
        eq(BossBanner:IsEventRegistered("BOSS_KILL"), false)
    end, function(_, state)
        bossFixture(state)
    end)
end)

test("disabled boss suppression leaves events and queue untouched during startup", function()
    UI.withAddon(function(M, state)
        eq(BossBanner:IsEventRegistered("BOSS_KILL"), true)
        eq(BossBanner.stops, 0)
        eq(state.finished, 0)
        eq(#TopBannerQueue, 3)
        eq(M.GetDeferredCount(), 0)
        eq(next(state.frames[1].events), nil)
    end, function(_, state)
        bossFixture(state)
        MurgleDB = { interface = { hideBossBanner = false } }
        state.combat = true
    end)
end)

test("boss disable restores original frame events even if manager globals disappear", function()
    UI.withAddon(function(M)
        local original = BossBanner
        BossBanner, TopBannerMgr, TopBannerQueue, TopBannerManager_BannerFinished = nil, nil, nil, nil
        MurgleDB.interface.hideBossBanner = false
        M.Interface.ApplyBossBanner()
        eq(original:IsEventRegistered("BOSS_KILL"), true)
        eq(original:IsEventRegistered("ENCOUNTER_LOOT_RECEIVED"), false)
    end, function(_, state)
        bossFixture(state)
    end)
end)

test("changed boss queue layout fails closed without removing event registrations", function()
    UI.withAddon(function(M, state)
        eq(BossBanner:IsEventRegistered("BOSS_KILL"), true)
        eq(BossBanner.stops, 0)
        eq(state.finished, 0)
        eq(#TopBannerQueue, 3)
    end, function(_, state)
        bossFixture(state)
        TopBannerQueue[2] = "unsupported"
    end)
end)

test("boss suppression rejects unplayable retained queue entries before mutation", function()
    UI.withAddon(function(M, state)
        eq(BossBanner:IsEventRegistered("BOSS_KILL"), true)
        eq(BossBanner.stops, 0)
        eq(state.finished, 0)
        eq(#TopBannerQueue, 3)
    end, function(_, state)
        bossFixture(state)
        state.otherBanner.PlayBanner = nil
    end)
end)

local function talkingFixture()
    TalkingHeadFrame = H.newEventFrame()
    TalkingHeadFrame.isPlaying = true
    TalkingHeadFrame.closes = 0
    function TalkingHeadFrame:IsProtected()
        return false
    end
    function TalkingHeadFrame:CloseImmediately()
        self.closes = self.closes + 1
        self.isPlaying = false
    end
    TalkingHeadFrame:RegisterEvent("TALKINGHEAD_REQUESTED")
    TalkingHeadFrame:RegisterEvent("TALKINGHEAD_CLOSE")
    TalkingHeadFrame:RegisterEvent("SOUNDKIT_FINISHED")
end

test("talking head suppression closes active playback and restores only its request registration", function()
    UI.withAddon(function(M, state)
        eq(TalkingHeadFrame.closes, 1)
        eq(TalkingHeadFrame:IsEventRegistered("TALKINGHEAD_REQUESTED"), false)
        eq(TalkingHeadFrame:IsEventRegistered("TALKINGHEAD_CLOSE"), true)
        eq(TalkingHeadFrame:IsEventRegistered("SOUNDKIT_FINISHED"), true)
        M.Interface.ApplyTalkingHead()
        eq(TalkingHeadFrame.closes, 1)
        local original = TalkingHeadFrame
        TalkingHeadFrame = nil
        MurgleDB.interface.hideTalkingHead = false
        M.Interface.ApplyTalkingHead()
        eq(original:IsEventRegistered("TALKINGHEAD_REQUESTED"), true)
        eq(original.closes, 1)
        eq(next(state.frames[1].events), nil)
        eq(#state.frames, 1)
    end, talkingFixture)
end)

test("talking head disable preserves an originally unregistered request event and idle preview", function()
    UI.withAddon(function(M)
        eq(TalkingHeadFrame.closes, 0)
        MurgleDB.interface.hideTalkingHead = false
        M.Interface.ApplyTalkingHead()
        eq(TalkingHeadFrame:IsEventRegistered("TALKINGHEAD_REQUESTED"), false)
        eq(TalkingHeadFrame.closes, 0)
    end, function()
        talkingFixture()
        TalkingHeadFrame:UnregisterEvent("TALKINGHEAD_REQUESTED")
        TalkingHeadFrame.isPlaying = false
        TalkingHeadFrame.isInEditMode = true
    end)
end)

test("talking head disabled startup is inert and combat cancellation preserves playback", function()
    UI.withAddon(function(M, state)
        eq(TalkingHeadFrame.closes, 0)
        eq(M.GetDeferredCount(), 0)
        MurgleDB.interface.hideTalkingHead = true
        M.Interface.ApplyTalkingHead()
        eq(TalkingHeadFrame.closes, 0)
        MurgleDB.interface.hideTalkingHead = false
        M.Interface.ApplyTalkingHead()
        state.combat = false
        local core = state.frames[1]
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(TalkingHeadFrame.closes, 0)
        eq(TalkingHeadFrame:IsEventRegistered("TALKINGHEAD_REQUESTED"), true)
        M.ResetDB()
        eq(TalkingHeadFrame.closes, 1)
        eq(TalkingHeadFrame:IsEventRegistered("TALKINGHEAD_REQUESTED"), false)
        eq(next(core.events), nil)
    end, function(_, state)
        talkingFixture()
        MurgleDB = { interface = { hideTalkingHead = false } }
        state.combat = true
    end)
end)

test("unsupported talking head integration leaves its request event untouched", function()
    UI.withAddon(function(M, state)
        eq(TalkingHeadFrame:IsEventRegistered("TALKINGHEAD_REQUESTED"), true)
        eq(M.GetDeferredCount(), 0)
        eq(next(state.frames[1].events), nil)
    end, function()
        talkingFixture()
        TalkingHeadFrame.CloseImmediately = nil
    end)
end)

test("talking head checkbox disables suppression and confirmed reset reenables it", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        local checkbox
        for _, frame in ipairs(state.frames) do
            if frame.kind == "CheckButton" then
                for _, region in ipairs(frame.regions) do
                    if region.text == M.L.HIDE_TALKING_HEAD then
                        checkbox = frame
                    end
                end
            end
        end
        assert(checkbox, "talking head checkbox missing")
        eq(checkbox:GetChecked(), true)
        checkbox:SetChecked(false)
        checkbox.scripts.OnClick(checkbox)
        eq(MurgleDB.interface.hideTalkingHead, false)
        eq(TalkingHeadFrame:IsEventRegistered("TALKINGHEAD_REQUESTED"), true)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(checkbox:GetChecked(), true)
        eq(TalkingHeadFrame:IsEventRegistered("TALKINGHEAD_REQUESTED"), false)
    end, talkingFixture)
end)

test("reset before entering world releases the startup retry listener", function()
    UI.withAddon(function(M, state)
        local startup = state.frames[#state.frames]
        eq(startup.events.PLAYER_ENTERING_WORLD, true)
        M.ResetDB()
        eq(next(startup.events), nil)
    end, function(M)
        MurgleDB = M.ApplyDefaults({ interface = { hideXP = true } })
    end)
end)

test("late micro menu and bags remain eligible for explicit startup retry", function()
    withInterface(function(M, menu, bags)
        MicroMenu, BagsBar = nil, nil
        MurgleDB.interface.hideMicroMenu = true
        MurgleDB.interface.hideBagBar = true
        M.Interface.ApplyAll()
        MicroMenu, BagsBar = menu, bags
        M.Interface.ApplyAll()
        eq(menu.shown, false)
        eq(menu.hides, 1)
        eq(bags.hides, 1)
    end)
end)

test("macro names hide once and restore captured FontStrings", function()
    local name = H.newVisibilityFrame(true)
    H.withGlobals({ ActionButton1 = { Name = name } }, function()
        UI.withAddon(function(M)
            MurgleDB.interface.hideMacroNames = true
            M.Interface.ApplyMacroNames()
            eq(name.shown, false)
            local changes = name.changes
            M.Interface.ApplyMacroNames()
            eq(name.changes, changes)
            M.ResetDB()
            eq(name.shown, true)
        end)
    end)
end)

test("native header shows after startup remain hidden and disabled hooks are inert", function()
    UI.withAddon(function(M, state)
        local root, quest = ObjectiveTrackerFrame.Header, QuestObjectiveTracker.Header
        root:Show()
        quest:Show()
        eq(root.shown, false)
        eq(quest.shown, false)
        M.Interface.ApplyTrackerHeaders()
        state.combat = true
        root:Show()
        eq(root.shown, true, "native combat changes must be deferred")
        MurgleDB.interface.objectiveTrackerHeaders = false
        M.Interface.ApplyTrackerHeaders()
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(root.shown, true)
        local changes = root.changes
        root:Show()
        eq(root.changes, changes + 1, "disabled hook must not hide")
    end, function(M)
        trackerFixtures()
        MurgleDB = M.ApplyDefaults({ interface = { objectiveTrackerHeaders = true } })
    end)
end)

test("saved header cleanup retries late native creation at login and releases listener", function()
    UI.withAddon(function(M, state)
        trackerFixtures()
        local startup = state.frames[#state.frames]
        eq(startup.events.PLAYER_ENTERING_WORLD, true)
        startup.scripts.OnEvent(startup, "PLAYER_ENTERING_WORLD")
        eq(ObjectiveTrackerFrame.Header.shown, false)
        eq(next(startup.events), nil)
        ObjectiveTrackerFrame.Header:Show()
        eq(ObjectiveTrackerFrame.Header.shown, false)
        M.ResetDB()
        eq(ObjectiveTrackerFrame.Header.shown, true)
    end, function(M)
        MurgleDB = M.ApplyDefaults({ interface = { objectiveTrackerHeaders = true } })
    end)
end)
