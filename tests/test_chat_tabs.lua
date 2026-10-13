local UI = dofile("tests/ui_helpers.lua")
local H = dofile("tests/helpers.lua")

local function fixture(_, state)
    state.hooks = 0
    state.addChat = function(name)
        local frame = { hasBeenFaded = false, nativeOver = 0.6, nativeIdle = 0.2 }
        function frame:GetName()
            return name
        end
        local tab = H.newVisibilityFrame(true)
        tab.alpha, tab.over, tab.idle = 0.2, 0.6, 0.2
        function tab:SetAlpha(value)
            self.alpha = value
        end
        function tab:SetShown(shown)
            if shown then
                self:Show()
            else
                self:Hide()
            end
        end
        _G[name], _G[name .. "Tab"] = frame, tab
        CHAT_FRAMES[#CHAT_FRAMES + 1] = name
        return frame, tab
    end
    CHAT_FRAMES = {}
    state.addChat("ChatFrame1")
    ChatFrameUtil = {
        GetTabAlphas = function(tab)
            return tab.over, tab.idle
        end,
        SetTabAlphas = function(tab, over, idle)
            tab.over, tab.idle = over, idle
        end,
    }
    UIFrameFadeRemoveFrame = function(tab)
        tab.fade = nil
    end
    FCFTab_UpdateAlpha = function(frame)
        local tab = _G[frame:GetName() .. "Tab"]
        ChatFrameUtil.SetTabAlphas(tab, frame.nativeOver, frame.nativeIdle)
        UIFrameFadeRemoveFrame(tab)
        tab:SetAlpha(frame.hasBeenFaded and frame.nativeOver or frame.nativeIdle)
    end
    FCF_StopDragging = function()
        MOVING_CHATFRAME = nil
    end
    hooksecurefunc = function(target, name, callback)
        if type(target) == "string" then
            callback, name, target = name, target, _G
            assert(name == "FCFTab_UpdateAlpha" or name == "FCF_StopDragging", "only hook native transitions")
        end
        state.hooks = state.hooks + 1
        local original = target[name]
        target[name] = function(...)
            original(...)
            callback(...)
        end
    end
end

local function mode(M, value)
    MurgleDB.chat.tabs = value
    M.Chat.ApplyTabs()
end

test("chat mouseover leaves default idle and preserves native hover targets", function()
    UI.withAddon(function(M, state)
        eq(state.hooks, 0)
        eq(ChatFrame1Tab.alpha, 0.2)
        mode(M, "mouseover")
        eq(ChatFrame1Tab.idle, 0)
        eq(ChatFrame1Tab.over, 0.6)
        eq(ChatFrame1Tab.alpha, 0)
        eq(ChatFrame1Tab.shown, true)
        ChatFrame1.hasBeenFaded = true
        FCFTab_UpdateAlpha(ChatFrame1)
        eq(ChatFrame1Tab.alpha, 0.6)
        mode(M, "mouseover")
        eq(state.hooks, 1)
        mode(M, "show")
        eq(ChatFrame1Tab.idle, 0.2)
        eq(ChatFrame1Tab.alpha, 0.6)
        eq(#state.frames, 1)
        eq(next(state.frames[1].events), nil)
    end, fixture)
end)

test("hidden chat tabs suppress native shows and restore latest native close intent", function()
    UI.withAddon(function(M, state)
        local _, custom = state.addChat("ChatFrame3")
        mode(M, "hide")
        eq(ChatFrame1Tab.shown, false)
        eq(custom.shown, false)
        ChatFrame1Tab:SetShown(true)
        eq(ChatFrame1Tab.shown, false)
        custom:Hide()
        mode(M, "show")
        eq(ChatFrame1Tab.shown, true)
        eq(custom.shown, false, "closed window must stay closed")
        custom:Show()
        eq(custom.shown, true, "disabled hooks leave native visibility alone")
        eq(next(state.frames[1].events), nil)
    end, fixture)
end)

test("hidden chat tabs handle new windows direct shows and mouseover transitions", function()
    UI.withAddon(function(M, state)
        mode(M, "mouseover")
        mode(M, "hide")
        eq(ChatFrame1Tab.idle, 0.2, "restore fade policy before hiding")
        local frame, custom = state.addChat("ChatFrame3")
        FCFTab_UpdateAlpha(frame)
        eq(custom.shown, false)
        custom:Show()
        eq(custom.shown, false)
        custom:SetShown(false)
        mode(M, "mouseover")
        eq(ChatFrame1Tab.shown, true)
        eq(ChatFrame1Tab.idle, 0)
        eq(custom.shown, false)
        mode(M, "show")
        eq(ChatFrame1Tab.idle, 0.2)
    end, fixture)
end)

test("chat Hide leaves Combat Log checkbox independent and captures replacement tabs", function()
    UI.withAddon(function(M, state)
        mode(M, "hide")
        eq(ChatFrame2Tab.shown, true)
        MurgleDB.chat.hideCombatLog = true
        M.Chat.ApplyCombatLog()
        eq(ChatFrame2Tab.shown, false)
        local original = ChatFrame1Tab
        state.addChat("ChatFrame1")
        mode(M, "hide")
        eq(ChatFrame1Tab.shown, false)
        mode(M, "show")
        eq(original.shown, true)
        eq(ChatFrame1Tab.shown, true)
        eq(ChatFrame2Tab.shown, false)
        M.ResetDB()
        eq(ChatFrame2Tab.shown, true)
    end, function(M, state)
        fixture(M, state)
        state.addChat("ChatFrame2")
    end)
end)

test("chat Hide defers native visibility changes and reset during combat", function()
    UI.withAddon(function(M, state)
        eq(ChatFrame1Tab.shown, true)
        eq(state.hooks, 0)
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(ChatFrame1Tab.shown, false)
        state.combat = true
        ChatFrame1Tab:SetShown(true)
        eq(ChatFrame1Tab.shown, true)
        M.ResetDB()
        ChatFrame1Tab:Hide()
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(ChatFrame1Tab.shown, false)
        eq(M.GetDeferredCount(), 0)
    end, function(M, state)
        fixture(M, state)
        state.combat = true
        MurgleDB = { chat = { tabs = "hide" } }
    end)
end)

test("chat Hide fails closed for protected missing or actively dragged tabs", function()
    UI.withAddon(function(M)
        ChatFrame1Tab.protected = true
        mode(M, "hide")
        eq(ChatFrame1Tab.shown, true)
        ChatFrame1Tab.protected = false
        MOVING_CHATFRAME = ChatFrame1
        mode(M, "hide")
        eq(ChatFrame1Tab.shown, true, "do not interrupt native drag completion")
        MOVING_CHATFRAME = nil
        local setter = ChatFrame1Tab.SetShown
        ChatFrame1Tab.SetShown = nil
        mode(M, "hide")
        eq(ChatFrame1Tab.shown, true)
        ChatFrame1Tab.SetShown = setter
        mode(M, "hide")
        eq(ChatFrame1Tab.shown, false)
        mode(M, "invalid")
        eq(ChatFrame1Tab.shown, true)
    end, fixture)
end)

test("chat Hide choice replaces idle fading and reset restores native tabs", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        M.Settings.SelectCategory("Chat")
        local hide, fade
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                if region.text == M.L.CHAT_HIDE then
                    hide = frame
                elseif region.text == M.L.CHAT_FADE then
                    fade = frame
                end
            end
        end
        assert(hide, "Hide choice exists")
        fade.scripts.OnClick(fade)
        hide.scripts.OnClick(hide)
        eq(MurgleDB.chat.tabs, "hide")
        eq(ChatFrame1Tab.shown, false)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(ChatFrame1Tab.shown, true)
    end, fixture)
end)

test("chat Hide waits for native drag completion without polling", function()
    UI.withAddon(function(M, state)
        MOVING_CHATFRAME = ChatFrame1
        mode(M, "hide")
        eq(ChatFrame1Tab.shown, true)
        FCF_StopDragging(ChatFrame1)
        eq(ChatFrame1Tab.shown, false)
        mode(M, "show")
        MOVING_CHATFRAME = ChatFrame1
        FCF_StopDragging(ChatFrame1)
        eq(ChatFrame1Tab.shown, true)
        eq(next(state.frames[1].events), nil)
    end, fixture)
end)

test("owned hidden tabs revealed in combat can finish dragging before suppression", function()
    UI.withAddon(function(M, state)
        mode(M, "hide")
        state.combat = true
        ChatFrame1Tab:Show()
        MOVING_CHATFRAME = ChatFrame1
        state.combat = false
        ChatFrame1Tab:SetShown(true)
        eq(ChatFrame1Tab.shown, true, "native show during drag must remain visible")
        FCF_StopDragging(ChatFrame1)
        eq(ChatFrame1Tab.shown, false)
    end, fixture)
end)

test("chat tabs restore latest native alert policy and cancel an active fade", function()
    UI.withAddon(function(M)
        mode(M, "mouseover")
        ChatFrame1.nativeOver, ChatFrame1.nativeIdle = 1, 1
        FCFTab_UpdateAlpha(ChatFrame1)
        eq(ChatFrame1Tab.idle, 0)
        ChatFrame1Tab.fade = { target = 0 }
        mode(M, "show")
        eq(ChatFrame1Tab.idle, 1)
        eq(ChatFrame1Tab.alpha, 1)
        eq(ChatFrame1Tab.fade, nil)
        ChatFrame1.nativeIdle = 0.4
        FCFTab_UpdateAlpha(ChatFrame1)
        eq(ChatFrame1Tab.idle, 0.4, "disabled hook leaves native writes alone")
    end, fixture)
end)

test("chat tabs adopt new windows on native updates and restore captured tabs", function()
    UI.withAddon(function(M, state)
        mode(M, "mouseover")
        local frame, tab = state.addChat("ChatFrame3")
        FCFTab_UpdateAlpha(frame)
        eq(tab.idle, 0)
        local original = ChatFrame1Tab
        ChatFrame1Tab = H.newVisibilityFrame(true)
        M.ResetDB()
        eq(original.idle, 0.2)
        eq(tab.idle, 0.2)
        eq(ChatFrame1Tab.changes, 0)
    end, fixture)
end)

test("chat tab startup and native updates defer combat changes using latest choice", function()
    UI.withAddon(function(M, state)
        eq(state.hooks, 0)
        mode(M, "show")
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(ChatFrame1Tab.alpha, 0.2)
        eq(state.hooks, 0)
        mode(M, "mouseover")
        state.combat = true
        ChatFrame1.nativeIdle = 0.4
        FCFTab_UpdateAlpha(ChatFrame1)
        eq(ChatFrame1Tab.idle, 0.4)
        mode(M, "show")
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(ChatFrame1Tab.idle, 0.4)
        eq(M.GetDeferredCount(), 0)
    end, function(M, state)
        fixture(M, state)
        state.combat = true
        MurgleDB = { chat = { tabs = "mouseover" } }
    end)
end)

test("chat tabs skip protected and missing integrations and invalid mode restores", function()
    UI.withAddon(function(M, state)
        ChatFrame1Tab.protected = true
        mode(M, "mouseover")
        eq(ChatFrame1Tab.idle, 0.2)
        ChatFrame1Tab.protected = false
        local api = ChatFrameUtil
        ChatFrameUtil = nil
        mode(M, "mouseover")
        eq(ChatFrame1Tab.idle, 0.2)
        ChatFrameUtil = api
        mode(M, "mouseover")
        eq(ChatFrame1Tab.idle, 0)
        mode(M, "invalid")
        eq(ChatFrame1Tab.idle, 0.2)
        eq(next(state.frames[1].events), nil)
    end, fixture)
end)

test("chat mouseover setting persists and confirmed reset refreshes control", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        M.Settings.SelectCategory("Chat")
        local control
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                if region.text == M.L.CHAT_FADE then
                    control = frame
                end
            end
        end
        assert(control, "Fade choice exists")
        control.scripts.OnClick(control)
        eq(MurgleDB.chat.tabs, "mouseover")
        eq(ChatFrame1Tab.idle, 0)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(ChatFrame1Tab.idle, 0.2)
    end, fixture)
end)

test("saved chat fading preserves hidden Combat Log and restores after combat reset", function()
    UI.withAddon(function(M, state)
        eq(ChatFrame1Tab.idle, 0)
        eq(ChatFrame2Tab.idle, 0)
        eq(ChatFrame2Tab.shown, false)
        state.combat = true
        M.ResetDB()
        eq(ChatFrame1Tab.idle, 0)
        MurgleDB.chat.tabs = "mouseover"
        M.Chat.ApplyTabs()
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(ChatFrame1Tab.idle, 0, "latest choice cancels deferred restoration")
        eq(ChatFrame2Tab.shown, true, "Combat Log toggle restores independently")
        mode(M, "show")
        eq(ChatFrame1Tab.idle, 0.2)
        eq(ChatFrame2Tab.idle, 0.2)
        eq(M.GetDeferredCount(), 0)
    end, function(M, state)
        fixture(M, state)
        state.addChat("ChatFrame2")
        MurgleDB = { chat = { tabs = "mouseover", hideCombatLog = true } }
    end)
end)
