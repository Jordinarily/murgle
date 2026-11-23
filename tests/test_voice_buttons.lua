local H = dofile("tests/helpers.lua")

local function withVoice(fn)
    local s = { queued = {} }
    local function frame()
        local f = { shown = true, alpha = 1, mouse = true }
        function f:GetAlpha()
            return self.alpha
        end
        function f:SetAlpha(v)
            self.alpha = v
        end
        function f:EnableMouse(enabled)
            self.mouse = enabled
        end
        function f:IsProtected()
            return self.protected == true
        end
        return f
    end
    local mute, deafen = frame(), frame()
    H.withGlobals({
        MurgleDB = { chat = { cleanChat = false } },
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

test("voice buttons disabled are inert and clean chat suppresses alpha and mouse safely", function()
    withVoice(function(C, s, mute, deafen)
        C.ApplyCleanChat()
        eq(mute.alpha, 1)
        eq(mute.mouse, true)

        MurgleDB.chat.cleanChat = true
        C.ApplyCleanChat()
        eq(mute.alpha, 0)
        eq(mute.mouse, false)
        eq(deafen.alpha, 0)
        eq(deafen.mouse, false)

        MurgleDB.chat.cleanChat = false
        C.ApplyCleanChat()
        eq(mute.alpha, 1)
        eq(mute.mouse, true)
        eq(deafen.alpha, 1)
        eq(deafen.mouse, true)
    end)
end)

test("voice buttons skip missing integrations independently", function()
    withVoice(function(C, _, mute, deafen)
        ChatFrameToggleVoiceMuteButton = nil
        MurgleDB.chat.cleanChat = true
        C.ApplyCleanChat()
        eq(mute.alpha, 1)
        eq(deafen.alpha, 0)
        eq(deafen.mouse, false)
        MurgleDB.chat.cleanChat = false
        C.ApplyCleanChat()
        eq(deafen.alpha, 1)
        eq(deafen.mouse, true)
    end)
end)

test("voice buttons combat queue uses latest setting and applies after combat", function()
    withVoice(function(C, s, mute, deafen)
        s.combat = true
        MurgleDB.chat.cleanChat = true
        C.ApplyCleanChat()
        eq(mute.alpha, 1)
        s.combat = false
        for _, action in pairs(s.queued) do
            action()
        end
        eq(mute.alpha, 0)
        eq(mute.mouse, false)
        eq(deafen.alpha, 0)
        eq(deafen.mouse, false)
    end)
end)
