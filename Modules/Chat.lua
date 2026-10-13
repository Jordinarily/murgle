local _, Murgle = ...
local Chat = {}
Murgle.Chat = Chat

local menuState, channelState, combatLogState = {}, {}, {}
local voiceStates = {}
local voicePending

local function hideVoiceButton()
    return false
end

local function applyVoiceButtons()
    voicePending = nil
    local hide = MurgleDB.chat.hideVoiceButtons == true
    for _, name in ipairs({ "ChatFrameToggleVoiceMuteButton", "ChatFrameToggleVoiceDeafenButton" }) do
        local state = voiceStates[name]
        local frame = state and state.frame or _G[name]
        if
            (hide or state)
            and frame
            and type(frame.IsProtected) == "function"
            and frame:IsProtected() == false
            and type(frame.SetVisibilityQueryFunction) == "function"
            and type(frame.UpdateVisibleState) == "function"
        then
            if hide and not state and type(frame.isVisible) == "function" then
                voiceStates[name] = { frame = frame, query = frame.isVisible }
                frame:SetVisibilityQueryFunction(hideVoiceButton)
                frame:UpdateVisibleState()
            elseif not hide and state then
                -- Preserve a policy another addon installed after ours.
                if frame.isVisible == hideVoiceButton then
                    frame:SetVisibilityQueryFunction(state.query)
                    frame:UpdateVisibleState()
                end
                voiceStates[name] = nil
            end
        end
    end
end

function Chat.ApplyVoiceButtons()
    if MurgleDB.chat.hideVoiceButtons ~= true and next(voiceStates) == nil and not voicePending then
        return
    end
    voicePending = true
    Murgle.DeferUntilOutOfCombat("chat.voiceButtons", applyVoiceButtons)
end

-- Capture only on first enable; restoring must not show a previously hidden button.
local function applyVisibility(frame, state, hide)
    state.pending = nil
    if state.unavailable or (not hide and state.shown == nil) then
        return
    end
    if
        not frame
        or type(frame.IsShown) ~= "function"
        or type(frame.Hide) ~= "function"
        or type(frame.Show) ~= "function"
    then
        state.unavailable = true
        return
    end
    if hide then
        if state.shown == nil then
            state.shown = frame:IsShown()
            state.frame = frame
        end
        state.frame:Hide()
    else
        local original = state.frame
        if state.shown then
            original:Show()
        else
            original:Hide()
        end
        state.shown, state.frame = nil, nil
    end
end

local function queue(key, state, hide, apply)
    if state.unavailable or (not hide and state.shown == nil and not state.pending) then
        return
    end
    state.pending = true
    Murgle.DeferUntilOutOfCombat(key, apply)
end

local function applyMenu()
    applyVisibility(menuState.frame or ChatFrameMenuButton, menuState, MurgleDB.chat.hideButtons == true)
end

local function applyChannels()
    applyVisibility(channelState.frame or ChatFrameChannelButton, channelState, MurgleDB.chat.hideButtons == true)
end

local combatLogHooks = {}

local function combatLogSafe(frame)
    return frame
        and type(frame.IsProtected) == "function"
        and frame:IsProtected() == false
        and type(frame.IsShown) == "function"
        and type(frame.Show) == "function"
        and type(frame.Hide) == "function"
        and type(frame.HookScript) == "function"
end

local function nativeCombatLogVisibility(frame, shown)
    if combatLogState.frame ~= frame or combatLogState.changing then
        return
    end
    combatLogState.shown = not not shown
    if shown and MurgleDB.chat.hideCombatLog == true then
        Chat.ApplyCombatLog()
    end
end

local function restoreCombatLog()
    local frame = combatLogState.frame
    if not combatLogSafe(frame) then
        return false
    end
    combatLogState.changing = true
    if combatLogState.shown then
        frame:Show()
    else
        frame:Hide()
    end
    combatLogState.changing = nil
    combatLogState.frame, combatLogState.shown = nil, nil
    return true
end

local function applyCombatLog()
    combatLogState.pending = nil
    local hide = MurgleDB.chat.hideCombatLog == true
    if combatLogState.frame and (not hide or combatLogState.frame ~= ChatFrame2Tab) then
        if not restoreCombatLog() then
            return
        end
    end
    local frame = ChatFrame2Tab
    if not hide or not combatLogSafe(frame) then
        return
    end
    if not combatLogState.frame then
        combatLogState.frame, combatLogState.shown = frame, frame:IsShown()
    end
    if not combatLogHooks[frame] then
        frame:HookScript("OnShow", function()
            nativeCombatLogVisibility(frame, true)
        end)
        -- OnHide does not fire for redundant native Hide calls on our hidden tab.
        if type(hooksecurefunc) == "function" then
            hooksecurefunc(frame, "Show", function()
                nativeCombatLogVisibility(frame, true)
            end)
            hooksecurefunc(frame, "Hide", function()
                nativeCombatLogVisibility(frame, false)
            end)
            if type(frame.SetShown) == "function" then
                hooksecurefunc(frame, "SetShown", function(_, shown)
                    nativeCombatLogVisibility(frame, shown)
                end)
            end
        end
        combatLogHooks[frame] = true
    end
    combatLogState.changing = true
    frame:Hide()
    combatLogState.changing = nil
end

local socialFrame, socialShown, socialPending
local socialHooked = {}

local function applySocial()
    socialPending = nil
    local enabled = MurgleDB.chat.hideButtons == true
    local frame = socialFrame or QuickJoinToastButton
    if
        (not enabled and not socialFrame)
        or not frame
        or type(frame.IsProtected) ~= "function"
        or frame:IsProtected()
        or type(frame.IsShown) ~= "function"
        or type(frame.Hide) ~= "function"
        or type(frame.Show) ~= "function"
        or type(frame.InitMKB) ~= "function"
        or type(frame.UninitMKB) ~= "function"
        or type(hooksecurefunc) ~= "function"
    then
        return
    end
    if enabled then
        if not socialFrame then
            socialFrame, socialShown = frame, frame:IsShown()
        end
        if not socialHooked[frame] then
            socialHooked[frame] = true
            local function nativeChanged(self)
                if MurgleDB.chat.hideButtons ~= true or socialFrame ~= self then
                    return
                end
                socialShown = self:IsShown()
                socialPending = true
                Murgle.DeferUntilOutOfCombat("chat.social", applySocial)
            end
            hooksecurefunc(frame, "InitMKB", nativeChanged)
            hooksecurefunc(frame, "UninitMKB", nativeChanged)
        end
        frame:Hide()
    else
        if socialShown then
            frame:Show()
        else
            frame:Hide()
        end
        socialFrame, socialShown = nil, nil
    end
end

function Chat.ApplyButtons()
    if MurgleDB.chat.hideButtons == true and QuickJoinToastButton or socialFrame or socialPending then
        socialPending = true
        Murgle.DeferUntilOutOfCombat("chat.social", applySocial)
    end
    queue("chat.menu", menuState, MurgleDB.chat.hideButtons == true, applyMenu)
    queue("chat.channels", channelState, MurgleDB.chat.hideButtons == true, applyChannels)
end

function Chat.ApplyCombatLog()
    queue("chat.combatLog", combatLogState, MurgleDB.chat.hideCombatLog == true, applyCombatLog)
end

local tabStates = {}
local hiddenTabs, visibilityHooks = {}, {}
local tabsHooked, tabsPending
local dragHooked

local function visibilitySafe(tab)
    return tab
        and type(tab.IsProtected) == "function"
        and tab:IsProtected() == false
        and type(tab.IsShown) == "function"
        and type(tab.SetShown) == "function"
        and type(tab.Show) == "function"
        and type(tab.Hide) == "function"
end

local function nativeTabVisibility(tab, shown)
    local state = hiddenTabs[tab]
    if not state or state.changing then
        return
    end
    state.shown = not not shown
    if shown and MurgleDB.chat.tabs == "hide" then
        if InCombatLockdown() or state.frame == MOVING_CHATFRAME then
            Chat.ApplyTabs()
        elseif visibilitySafe(tab) then
            state.changing = true
            tab:Hide()
            state.changing = nil
        end
    end
end

local function hideChatTab(frame)
    if not frame or type(frame.GetName) ~= "function" then
        return
    end
    if frame == MOVING_CHATFRAME then
        if not dragHooked and type(FCF_StopDragging) == "function" and type(hooksecurefunc) == "function" then
            hooksecurefunc("FCF_StopDragging", function(stoppedFrame)
                if MurgleDB.chat.tabs == "hide" then
                    hideChatTab(stoppedFrame)
                end
            end)
            dragHooked = true
        end
        return
    end
    local name = frame:GetName()
    -- Combat Log has its own independent visibility control.
    if type(name) ~= "string" or name == "ChatFrame2" then
        return
    end
    local tab = _G[name .. "Tab"]
    if not visibilitySafe(tab) or type(hooksecurefunc) ~= "function" then
        return
    end
    if InCombatLockdown() then
        Chat.ApplyTabs()
        return
    end
    local state = hiddenTabs[tab]
    if not state then
        state = { shown = tab:IsShown(), frame = frame }
        hiddenTabs[tab] = state
    end
    if not visibilityHooks[tab] then
        -- Observe redundant Hide/SetShown calls: closed or minimized windows
        -- must not reappear when the option is disabled.
        hooksecurefunc(tab, "SetShown", function(_, shown)
            nativeTabVisibility(tab, shown)
        end)
        hooksecurefunc(tab, "Show", function()
            nativeTabVisibility(tab, true)
        end)
        hooksecurefunc(tab, "Hide", function()
            nativeTabVisibility(tab, false)
        end)
        visibilityHooks[tab] = true
    end
    state.changing = true
    tab:Hide()
    state.changing = nil
end

local function restoreHiddenTabs()
    for tab, state in pairs(hiddenTabs) do
        if visibilitySafe(tab) then
            state.changing = true
            tab:SetShown(state.shown)
            state.changing = nil
            hiddenTabs[tab] = nil
        end
    end
end

local function tabSafe(tab)
    return tab
        and type(tab.IsProtected) == "function"
        and tab:IsProtected() == false
        and type(tab.SetAlpha) == "function"
end

local function writeTab(frame, state, enabled)
    if not tabSafe(state.tab) or type(UIFrameFadeRemoveFrame) ~= "function" then
        return false
    end
    local idle = enabled and 0 or state.idle
    state.setAlphas(state.tab, state.over, idle)
    UIFrameFadeRemoveFrame(state.tab)
    state.tab:SetAlpha(frame.hasBeenFaded and state.over or idle)
    return true
end

local function captureTab(frame, nativeUpdate)
    local api = ChatFrameUtil
    if
        not frame
        or type(frame.GetName) ~= "function"
        or type(api) ~= "table"
        or type(api.GetTabAlphas) ~= "function"
        or type(api.SetTabAlphas) ~= "function"
    then
        return
    end
    local name = frame:GetName()
    local tab = type(name) == "string" and _G[name .. "Tab"]
    if not tabSafe(tab) then
        return
    end
    local state = tabStates[frame]
    if state and state.tab ~= tab then
        -- Restore the captured object before adopting a replacement.
        if InCombatLockdown() or not writeTab(frame, state, false) then
            return
        end
        tabStates[frame], state = nil, nil
    end
    if not state or nativeUpdate then
        local over, idle = api.GetTabAlphas(tab)
        if
            type(over) ~= "number"
            or type(idle) ~= "number"
            or not (over >= 0 and over <= 1 and idle >= 0 and idle <= 1)
        then
            return
        end
        if not state then
            state = { tab = tab }
            tabStates[frame] = state
        end
        state.over, state.idle, state.setAlphas = over, idle, api.SetTabAlphas
    end
    return state
end

local function nativeAlphaUpdated(frame)
    local enabled = MurgleDB.chat.tabs == "mouseover"
    if not enabled and not tabStates[frame] then
        return
    end
    -- Capture native policy even during deferred restoration, so a new alert
    -- or selection cannot be overwritten by an obsolete pre-combat target.
    local state = captureTab(frame, true)
    if not state then
        return
    end
    if InCombatLockdown() then
        Chat.ApplyTabs()
    elseif enabled then
        writeTab(frame, state, true)
    else
        tabStates[frame] = nil
    end
end

local function nativeTabUpdated(frame)
    nativeAlphaUpdated(frame)
    if MurgleDB.chat.tabs == "hide" then
        hideChatTab(frame)
    end
end

local function applyTabs()
    tabsPending = nil
    local hide = MurgleDB.chat.tabs == "hide"
    if not hide then
        restoreHiddenTabs()
    end
    if MurgleDB.chat.tabs ~= "mouseover" then
        for frame, state in pairs(tabStates) do
            if writeTab(frame, state, false) then
                tabStates[frame] = nil
            end
        end
        if not hide then
            return
        end
    end
    if type(CHAT_FRAMES) ~= "table" or type(FCFTab_UpdateAlpha) ~= "function" or type(hooksecurefunc) ~= "function" then
        return
    end
    if
        not hide
        and (
            type(ChatFrameUtil) ~= "table"
            or type(ChatFrameUtil.GetTabAlphas) ~= "function"
            or type(ChatFrameUtil.SetTabAlphas) ~= "function"
            or type(UIFrameFadeRemoveFrame) ~= "function"
        )
    then
        return
    end
    if not tabsHooked then
        hooksecurefunc("FCFTab_UpdateAlpha", nativeTabUpdated)
        tabsHooked = true
    end
    for _, name in pairs(CHAT_FRAMES) do
        local frame = type(name) == "string" and _G[name]
        if hide then
            hideChatTab(frame)
        else
            local state = captureTab(frame, false)
            if state then
                writeTab(frame, state, true)
            end
        end
    end
end

function Chat.ApplyTabs()
    if
        MurgleDB.chat.tabs ~= "mouseover"
        and MurgleDB.chat.tabs ~= "hide"
        and next(tabStates) == nil
        and next(hiddenTabs) == nil
        and not tabsPending
    then
        return
    end
    tabsPending = true
    Murgle.DeferUntilOutOfCombat("chat.tabs", applyTabs)
end

function Chat.ApplyAll()
    Chat.ApplyButtons()
    Chat.ApplyVoiceButtons()
    Chat.ApplyCombatLog()
    Chat.ApplyTabs()
end

function Chat.Initialize()
    Chat.ApplyAll()
end
