local H = dofile("tests/helpers.lua")

local function withVoice(fn)
    local s = { loggedIn = true, updates = 0, queued = {} }
    local function frame()
        local f = { shown = true }
        f.isVisible = function()
            return s.loggedIn
        end
        function f:IsProtected()
            return self.protected == true
        end
        function f:SetVisibilityQueryFunction(query)
            self.isVisible = query
        end
        function f:UpdateVisibleState()
            s.updates = s.updates + 1
            self.shown = self:isVisible()
        end
        return f
    end
    local mute, deafen = frame(), frame()
    H.withGlobals({
        MurgleDB = { chat = { hideVoiceButtons = false } },
        ChatFrameToggleVoiceMuteButton = mute,
        ChatFrameToggleVoiceDeafenButton = deafen,
    }, function()
        local M = {
            DeferUntilOutOfCombat = function(key, action)
                if s.combat then
                    s.queued[key] = action
                else
                    action()
                end
            end,
        }
        H.loadAddonFile("Modules/Chat.lua", M)
        fn(M.Chat, s, mute, deafen)
    end)
end

test("voice buttons disabled are inert and restore current native visibility", function()
    withVoice(function(C, s, mute, deafen)
        C.ApplyVoiceButtons()
        eq(s.updates, 0)
        local original = mute.isVisible
        MurgleDB.chat.hideVoiceButtons = true
        C.ApplyVoiceButtons()
        eq(mute.shown, false)
        eq(deafen.shown, false)
        local updates = s.updates
        C.ApplyVoiceButtons()
        eq(s.updates, updates)
        mute:UpdateVisibleState()
        eq(mute.shown, false)
        s.loggedIn = false
        MurgleDB.chat.hideVoiceButtons = false
        C.ApplyVoiceButtons()
        eq(mute.isVisible, original)
        eq(mute.shown, false)
        s.loggedIn = true
        mute:UpdateVisibleState()
        eq(mute.shown, true)
    end)
end)

test("voice buttons preserve external policies and restore captured frames", function()
    withVoice(function(C, _, mute, deafen)
        local original = mute.isVisible
        MurgleDB.chat.hideVoiceButtons = true
        C.ApplyVoiceButtons()
        local external = function()
            return false
        end
        deafen:SetVisibilityQueryFunction(external)
        ChatFrameToggleVoiceMuteButton = nil
        MurgleDB.chat.hideVoiceButtons = false
        C.ApplyVoiceButtons()
        eq(mute.isVisible, original)
        eq(deafen.isVisible, external)
    end)
end)

test("voice buttons skip protected and missing integrations independently", function()
    withVoice(function(C, _, mute, deafen)
        mute.protected = true
        local original = mute.isVisible
        MurgleDB.chat.hideVoiceButtons = true
        C.ApplyVoiceButtons()
        eq(mute.isVisible, original)
        eq(deafen.shown, false)
        mute.protected = false
        mute.SetVisibilityQueryFunction = nil
        C.ApplyVoiceButtons()
        eq(mute.isVisible, original)
    end)
end)

test("voice buttons combat queue uses latest setting and restores after protection clears", function()
    withVoice(function(C, s, mute)
        s.combat = true
        MurgleDB.chat.hideVoiceButtons = true
        C.ApplyVoiceButtons()
        eq(s.updates, 0)
        MurgleDB.chat.hideVoiceButtons = false
        C.ApplyVoiceButtons()
        s.combat = false
        for _, action in pairs(s.queued) do
            action()
        end
        eq(s.updates, 0)
        MurgleDB.chat.hideVoiceButtons = true
        C.ApplyVoiceButtons()
        mute.protected = true
        MurgleDB.chat.hideVoiceButtons = false
        C.ApplyVoiceButtons()
        eq(mute.shown, false)
        mute.protected = false
        C.ApplyVoiceButtons()
        eq(mute.shown, true)
    end)
end)
