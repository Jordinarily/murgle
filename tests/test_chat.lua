local UI = dofile("tests/ui_helpers.lua")
local H = dofile("tests/helpers.lua")

local function fixtures()
    ChatFrameMenuButton = H.newVisibilityFrame(true)
    ChatFrameChannelButton = H.newVisibilityFrame(false)
    ChatFrame2Tab = H.newVisibilityFrame(true)
end

test("chat saved choices hide captured controls and reset restores original states", function()
    UI.withAddon(function(M, state)
        eq(ChatFrameMenuButton.shown, false)
        eq(ChatFrame2Tab.shown, false)
        M.ApplyAllSettings()
        M.ResetDB()
        eq(ChatFrameMenuButton.shown, true)
        eq(ChatFrameChannelButton.shown, false)
        eq(ChatFrame2Tab.shown, true)
        eq(#state.frames, 1)
        eq(next(state.frames[1].events), nil)
    end, function(M)
        fixtures()
        MurgleDB = M.ApplyDefaults({ chat = { hideButtons = true, hideCombatLog = true } })
    end)
end)

test("disabled chat settings leave controls untouched even during combat startup", function()
    UI.withAddon(function(M, state)
        assert(M.Chat, "chat module must be loaded")
        eq(ChatFrameMenuButton.changes + ChatFrameChannelButton.changes + ChatFrame2Tab.changes, 0)
        eq(M.GetDeferredCount(), 0)
        eq(next(state.frames[1].events), nil)
        eq(#state.frames, 1)
    end, function(_, state)
        fixtures()
        state.combat = true
    end)
end)

test("chat controls fail independently and do not retry missing frames", function()
    UI.withAddon(function(M)
        assert(M.Chat, "chat module must be loaded")
        fixtures()
        ChatFrameMenuButton = nil
        ChatFrameChannelButton.shown = true
        MurgleDB.chat.hideButtons = true
        MurgleDB.chat.hideCombatLog = true
        M.ApplyAllSettings()
        eq(ChatFrameChannelButton.shown, false)
        eq(ChatFrame2Tab.shown, false)
        ChatFrameMenuButton = H.newVisibilityFrame(true)
        M.ApplyAllSettings()
        eq(ChatFrameMenuButton.changes, 0)
        M.ResetDB()
        eq(ChatFrameChannelButton.shown, true)
        eq(ChatFrame2Tab.shown, true)
    end)
end)

test("chat checkbox changes defer in combat and confirmed reset restores controls", function()
    UI.withAddon(function(M, state)
        fixtures()
        ChatFrameChannelButton.shown = true
        M.Settings.Show()
        local start = #state.frames
        M.Settings.SelectCategory("Chat")
        local controls = {}
        for i = start + 1, #state.frames do
            local f = state.frames[i]
            if f.kind == "CheckButton" then
                controls[#controls + 1] = f
            end
        end
        eq(#controls, 3)
        state.combat = true
        for _, control in ipairs(controls) do
            control:SetChecked(true)
            control.scripts.OnClick(control)
        end
        eq(MurgleDB.chat.hideButtons, true)
        eq(MurgleDB.chat.hideVoiceButtons, true)
        eq(MurgleDB.chat.hideCombatLog, true)
        eq(MurgleDB.interface.hideButtons, nil)
        eq(ChatFrameMenuButton.changes, 0)
        eq(ChatFrame2Tab.changes, 0)
        state.combat = false
        local core = state.frames[1]
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(ChatFrameMenuButton.shown, false)
        eq(ChatFrameChannelButton.shown, false)
        eq(ChatFrame2Tab.shown, false)
        state.combat = true
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(ChatFrameMenuButton.shown, false)
        for _, control in ipairs(controls) do
            eq(control:GetChecked(), false)
        end
        state.combat = false
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(ChatFrameMenuButton.shown, true)
        eq(ChatFrameChannelButton.shown, true)
        eq(ChatFrame2Tab.shown, true)
        eq(M.GetDeferredCount(), 0)
        eq(next(core.events), nil)
        local count = #state.frames
        M.Settings.SelectCategory("Interface")
        M.Settings.SelectCategory("Chat")
        eq(#state.frames, count)
    end)
end)

test("reset before combat ends cancels pending chat hiding", function()
    UI.withAddon(function(M, state)
        assert(M.Chat, "chat module must be loaded")
        M.ResetDB()
        state.combat = false
        local core = state.frames[1]
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(ChatFrameMenuButton.changes + ChatFrameChannelButton.changes + ChatFrame2Tab.changes, 0)
        eq(M.GetDeferredCount(), 0)
        eq(next(core.events), nil)
    end, function(M, state)
        fixtures()
        state.combat = true
        MurgleDB = M.ApplyDefaults({ chat = { hideButtons = true, hideCombatLog = true } })
    end)
end)

test("combat log tab stays hidden across native shows and restores on disable", function()
    UI.withAddon(function(M, state)
        fixtures()
        local tab = ChatFrame2Tab
        MurgleDB.chat.hideCombatLog = true
        M.Chat.ApplyCombatLog()
        tab:Show()
        eq(tab.shown, false)
        state.combat = true
        tab:Show()
        eq(tab.shown, true, "defer native re-show suppression during combat")
        MurgleDB.chat.hideCombatLog = false
        M.Chat.ApplyCombatLog()
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(tab.shown, true)
        tab:Hide()
        tab:Show()
        eq(tab.shown, true, "disabled hook must be inert")
        eq(M.GetDeferredCount(), 0)
    end)
end)

test("combat log restore follows native hide intent while already suppressed", function()
    UI.withAddon(function(M)
        fixtures()
        hooksecurefunc = function(frame, name, callback)
            local original = frame[name]
            frame[name] = function(...)
                original(...)
                callback(...)
            end
        end
        MurgleDB.chat.hideCombatLog = true
        M.Chat.ApplyCombatLog()
        ChatFrame2Tab:Hide()
        MurgleDB.chat.hideCombatLog = false
        M.Chat.ApplyCombatLog()
        eq(ChatFrame2Tab.shown, false, "native hidden intent must survive disable")
        MurgleDB.chat.hideCombatLog = true
        M.Chat.ApplyCombatLog()
        ChatFrame2Tab:Show()
        eq(ChatFrame2Tab.shown, false)
        M.ResetDB()
        eq(ChatFrame2Tab.shown, true, "latest native shown intent must survive reset")
    end)
end)

test("combat log replacement restores captured tab and suppresses new tab", function()
    UI.withAddon(function(M)
        fixtures()
        MurgleDB.chat.hideCombatLog = true
        M.Chat.ApplyCombatLog()
        local old = ChatFrame2Tab
        ChatFrame2Tab = H.newVisibilityFrame(true)
        M.Chat.ApplyCombatLog()
        eq(old.shown, true)
        eq(ChatFrame2Tab.shown, false)
        old:Hide()
        old:Show()
        M.ResetDB()
        eq(ChatFrame2Tab.shown, true)
    end)
end)

test("combat log tracks SetShown intent through deferred disable without duplicate hooks", function()
    UI.withAddon(function(M, state)
        fixtures()
        local tab = ChatFrame2Tab
        function tab:SetShown(shown)
            if shown then
                self:Show()
            else
                self:Hide()
            end
        end
        local hooks = 0
        hooksecurefunc = function(frame, name, callback)
            hooks = hooks + 1
            local original = frame[name]
            frame[name] = function(...)
                original(...)
                callback(...)
            end
        end
        MurgleDB.chat.hideCombatLog = true
        M.Chat.ApplyCombatLog()
        tab:SetShown(true)
        eq(tab.shown, false)
        state.combat = true
        MurgleDB.chat.hideCombatLog = false
        M.Chat.ApplyCombatLog()
        tab:SetShown(false)
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(tab.shown, false)
        MurgleDB.chat.hideCombatLog = true
        M.Chat.ApplyCombatLog()
        tab:SetShown(true)
        M.ResetDB()
        eq(tab.shown, true)
        eq(hooks, 3, "re-enabling must reuse installed method hooks")
        local writes = tab.changes
        tab:SetShown(false)
        eq(tab.changes, writes + 1, "disabled callbacks must not mutate visibility")
    end)
end)

test("combat log captures native Show while an ancestor prevents OnShow dispatch", function()
    UI.withAddon(function(M)
        fixtures()
        local tab = ChatFrame2Tab
        function tab:Show()
            self.shown = true
            self.changes = self.changes + 1
        end
        hooksecurefunc = function(frame, name, callback)
            local original = frame[name]
            frame[name] = function(...)
                original(...)
                callback(...)
            end
        end
        MurgleDB.chat.hideCombatLog = true
        M.Chat.ApplyCombatLog()
        tab:Hide()
        tab:Show()
        eq(tab.shown, false, "hide explicit state even without OnShow")
        M.ResetDB()
        eq(tab.shown, true, "restore most recent native Show request")
    end)
end)

test("chat social button hides and restores latest native input-mode visibility", function()
    local social = H.newVisibilityFrame(true)
    function social:InitMKB()
        self:Show()
    end
    function social:UninitMKB()
        self:Hide()
    end
    H.withGlobals({
        QuickJoinToastButton = social,
        hooksecurefunc = function(object, method, callback)
            local original = object[method]
            object[method] = function(self, ...)
                original(self, ...)
                callback(self, ...)
            end
        end,
    }, function()
        UI.withAddon(function(M)
            eq(social.changes, 0)
            MurgleDB.chat.hideButtons = true
            M.Chat.ApplyButtons()
            eq(social.shown, false)
            social:InitMKB()
            eq(social.shown, false)
            MurgleDB.chat.hideButtons = false
            M.Chat.ApplyButtons()
            eq(social.shown, true)
            MurgleDB.chat.hideButtons = true
            M.Chat.ApplyButtons()
            social:UninitMKB()
            M.ResetDB()
            eq(social.shown, false)
        end, function()
            hooksecurefunc = function(object, method, callback)
                local original = object[method]
                object[method] = function(self, ...)
                    original(self, ...)
                    callback(self, ...)
                end
            end
        end)
    end)
end)
