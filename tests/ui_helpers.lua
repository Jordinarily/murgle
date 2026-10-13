local H = dofile("tests/helpers.lua")
local UI = {}

function UI.withAddon(fn, beforeInitialize)
    local state = { frames = {}, named = {}, popups = {}, messages = {} }
    local function newRegion()
        local region = {}
        function region:SetPoint(...)
            self.point = { ... }
        end
        function region:SetAllPoints(target)
            self.allPoints = target
        end
        function region:SetSize(width, height)
            self.width, self.height = width, height
        end
        function region:SetText(text)
            self.text = text
        end
        function region:SetFont(path, size)
            self.font, self.fontSize = path, size
        end
        function region:SetTextColor(...)
            self.color = { ... }
        end
        function region:SetJustifyH(value)
            self.justify = value
        end
        function region:SetColorTexture(...)
            self.color = { ... }
        end
        function region:SetTexture(path)
            self.texture = path
        end
        return region
    end
    local function newFrame(kind, name, parent, template)
        eq(template, nil, "settings must not guess a Forever template")
        local frame = H.newEventFrame()
        frame.kind, frame.name, frame.parent = kind, name, parent
        frame.shown, frame.regions = true, {}
        function frame:SetSize(width, height)
            self.width, self.height = width, height
        end
        function frame:SetPoint(...)
            self.point = { ... }
        end
        function frame:SetFrameStrata(value)
            self.strata = value
        end
        function frame:SetMovable(value)
            self.movable = value
        end
        function frame:SetClampedToScreen(value)
            self.clamped = value
        end
        function frame:RegisterForDrag(button)
            self.dragButton = button
        end
        function frame:StartMoving()
            self.moving = true
        end
        function frame:StopMovingOrSizing()
            self.moving = false
        end
        function frame:EnableMouse(value)
            self.mouse = value
        end
        function frame:Show()
            self.shown = true
        end
        function frame:Hide()
            self.shown = false
        end
        function frame:IsShown()
            return self.shown
        end
        function frame:CreateTexture()
            local texture = newRegion()
            self.regions[#self.regions + 1] = texture
            return texture
        end
        function frame:CreateFontString()
            local label = newRegion()
            self.regions[#self.regions + 1] = label
            return label
        end
        function frame:SetOrientation(value)
            self.orientation = value
        end
        function frame:SetMinMaxValues(low, high)
            self.minimum, self.maximum = low, high
        end
        function frame:SetValueStep(step)
            self.step = step
        end
        function frame:SetObeyStepOnDrag(value)
            self.obeyStep = value
        end
        function frame:SetThumbTexture(texture)
            self.thumb = texture
        end
        function frame:SetValue(value)
            self.value = value
            if self.scripts.OnValueChanged then
                self.scripts.OnValueChanged(self, value)
            end
        end
        function frame:SetHighlightTexture(texture)
            self.highlight = texture
        end
        function frame:SetCheckedTexture(texture)
            self.checkedTexture = texture
        end
        function frame:SetChecked(value)
            self.checked = value
        end
        function frame:GetChecked()
            return self.checked
        end
        state.frames[#state.frames + 1] = frame
        if name then
            state.named[name] = frame
        end
        return frame
    end
    H.withGlobals({
        MerchantFrame = false,
        MerchantSellAllJunkButton = false,
        C_MerchantFrame = false,
        C_Container = false,
        NUM_BAG_SLOTS = false,
        CanMerchantRepair = false,
        CanGuildBankRepair = false,
        GetGuildBankWithdrawMoney = false,
        GetGuildBankMoney = false,
        GetRepairAllCost = false,
        GetMoney = false,
        RepairAllItems = false,
        Murgle = false,
        MurgleDB = false,
        SLASH_MURGLE1 = false,
        UIParent = {},
        UISpecialFrames = {},
        STANDARD_TEXT_FONT = "Fonts/FRIZQT__.TTF",
        CreateFrame = newFrame,
        SlashCmdList = {},
        StaticPopupDialogs = {},
        StaticPopup_Show = function(key)
            state.popups[#state.popups + 1] = key
        end,
        GetLocale = function()
            return "enUS"
        end,
        InCombatLockdown = function()
            return state.combat == true
        end,
        C_AddOns = false,
        TalkingHeadFrame = false,
        Bug = false,
        PTR_IssueReporter = false,
        IsBetaBuild = false,
        StatusTrackingBarInfo = false,
        MainStatusTrackingBarContainer = false,
        SecondaryStatusTrackingBarContainer = false,
        hooksecurefunc = false,
        MouseIsOver = false,
        GameTooltip = false,
        GameTooltip_SetDefaultAnchor = false,
        Enum = false,
        QuestFrame = false,
        QuestFrameDetailPanel = false,
        QuestFrameProgressPanel = false,
        QuestFrameRewardPanel = false,
        QuestFrameAcceptButton = false,
        QuestFrameCompleteButton = false,
        QuestFrameCompleteQuestButton = false,
        IsShiftKeyDown = false,
        GetQuestID = false,
        QuestFlagsPVP = false,
        QuestGetAutoAccept = false,
        QuestIsFromAdventureMap = false,
        QuestIsFromAreaTrigger = false,
        GetNumQuestChoices = false,
        GetQuestMoneyToGet = false,
        IsQuestCompletable = false,
        AcceptQuest = false,
        CompleteQuest = false,
        GetQuestReward = false,
        AlertFrame = false,
        HelpTip = false,
        TotemFrame = false,
        UIErrorsFrame = false,
        BLACK_LISTED_MESSAGE_TYPES = false,
        LE_GAME_ERR_SPELL_OUT_OF_RANGE = false,
        LE_GAME_ERR_OUT_OF_MANA = false,
        LE_GAME_ERR_ITEM_COOLDOWN = false,
        BossBanner = false,
        TopBannerMgr = false,
        TopBannerQueue = false,
        TopBannerManager_BannerFinished = false,
        ZoneTextFrame = false,
        SubZoneTextFrame = false,
        MicroMenu = false,
        BagsBar = false,
        ObjectiveTrackerFrame = false,
        QuestObjectiveTracker = false,
        ChatFrameMenuButton = false,
        ChatFrameChannelButton = false,
        ChatFrame2Tab = false,
        ChatFrame1 = false,
        ChatFrame1Tab = false,
        ChatFrame2 = false,
        ChatFrame3 = false,
        ChatFrame3Tab = false,
        CHAT_FRAMES = false,
        MOVING_CHATFRAME = false,
        ChatFrameUtil = false,
        FCFTab_UpdateAlpha = false,
        FCF_StopDragging = false,
        UIFrameFadeRemoveFrame = false,
        GameTimeFrame = false,
        TimeManagerClockButton = false,
        MinimapCluster = false,
        Minimap = false,
        AddonCompartmentFrame = false,
        MinimapCompassTexture = false,
        MinimapCompassTextureUnderlay = false,
        print = function(message)
            state.messages[#state.messages + 1] = message
        end,
    }, function()
        local M = {}
        for _, path in ipairs(H.addonFiles()) do
            H.loadAddonFile(path, M)
        end
        if beforeInitialize then
            beforeInitialize(M, state)
        end
        local core = state.frames[1]
        core.scripts.OnEvent(core, "ADDON_LOADED", "Murgle")
        fn(M, state)
    end)
end

return UI
