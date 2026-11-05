local function setup(enabled)
    local addon, hook, eventFrame = {}, nil, nil
    local data = { { price = 100, count = 1 }, { price = 60, count = 2 } }
    local buttons = {}
    for i = 1, 2 do
        local index = i
        buttons[i] = {
            type = "choice",
            objectType = "item",
            Icon = {},
            GetID = function()
                return index
            end,
            GetParent = function()
                return QuestInfoRewardsFrame
            end,
            IsShown = function()
                return true
            end,
            IsProtected = function()
                return false
            end,
            IsForbidden = function()
                return false
            end,
            CreateTexture = function(self)
                local texture = {}
                function texture:SetAtlas(atlas)
                    self.atlas = atlas
                end
                function texture:SetSize() end
                function texture:SetPoint() end
                function texture:Show()
                    self.shown = true
                end
                function texture:Hide()
                    self.shown = false
                end
                self.marker = texture
                return texture
            end,
        }
    end
    QuestInfoRewardsFrame = {
        RewardButtons = buttons,
        scripts = {},
        IsShown = function()
            return true
        end,
        IsProtected = function()
            return false
        end,
        IsForbidden = function()
            return false
        end,
        HookScript = function(self, name, fn)
            self.scripts[name] = fn
        end,
    }
    QuestInfoFrame = { rewardsFrame = QuestInfoRewardsFrame }
    QUEST_TEMPLATE_REWARD, QUEST_TEMPLATE_DETAIL = {}, {}
    QuestInfo_Display = function() end
    GetNumQuestChoices = function()
        return #data
    end
    GetQuestItemInfoLootType = function(_, i)
        return data[i].currency and 1 or 0
    end
    GetQuestItemInfo = function(_, i)
        return "item", nil, data[i].count
    end
    GetQuestItemLink = function(_, i)
        if not data[i].noLink then
            return "item:" .. i
        end
    end
    C_Item = {
        GetItemInfo = function(link)
            local i = tonumber(link:match("(%d+)$"))
            return "item", link, nil, nil, nil, nil, nil, nil, nil, nil, data[i].price
        end,
    }
    InCombatLockdown = function()
        return false
    end
    hooksecurefunc = function(name, fn)
        eq(name, "QuestInfo_Display")
        hook = fn
    end
    CreateFrame = function()
        local f = { events = {} }
        function f:RegisterEvent(e)
            self.events[e] = true
        end
        function f:UnregisterAllEvents()
            self.events = {}
        end
        function f:SetScript(_, fn)
            self.handler = fn
        end
        eventFrame = f
        return f
    end
    GetQuestReward = function()
        error("reward selected")
    end
    QuestInfoItem_OnClick = function()
        error("choice changed")
    end
    MurgleDB = { quests = { rewardValues = enabled } }
    assert(loadfile("Modules/Rewards.lua"))("Murgle", addon)
    addon.Rewards:Initialize()
    return addon,
        buttons,
        data,
        function(template, mapView)
            hook(template or QUEST_TEMPLATE_REWARD, nil, nil, nil, mapView)
        end,
        function()
            return eventFrame
        end
end

test("reward values disabled startup is inert", function()
    local _, buttons, _, _, events = setup(false)
    eq(events(), nil)
    eq(buttons[1].marker, nil)
end)

test("reward values marks strictly highest total and preserves native choice", function()
    local _, buttons, _, display = setup(true)
    QuestInfoFrame.itemChoice = 1
    display()
    eq(buttons[1].marker, nil)
    eq(buttons[2].marker.shown, true)
    eq(buttons[2].marker.atlas, "coin-gold")
    eq(QuestInfoFrame.itemChoice, 1)
end)

test("reward values ties and unresolved data never claim a winner", function()
    local _, buttons, data, display, events = setup(true)
    data[1].price = 120
    display()
    eq(buttons[1].marker, nil)
    eq(buttons[2].marker, nil)
    data[1].price = nil
    display()
    eq(events().events.GET_ITEM_INFO_RECEIVED, true)
    data[1].price = 200
    events().handler(nil, "GET_ITEM_INFO_RECEIVED")
    eq(buttons[1].marker.shown, true)
    eq(events().events.GET_ITEM_INFO_RECEIVED, nil)
end)

test("reward values clears on context disable and close", function()
    local addon, buttons, _, display, events = setup(true)
    display()
    display({}, true)
    eq(buttons[2].marker.shown, false)
    eq(next(events().events), nil)
    display(QUEST_TEMPLATE_DETAIL)
    eq(buttons[2].marker.shown, true)
    QuestInfoRewardsFrame.scripts.OnHide()
    eq(buttons[2].marker.shown, false)
    eq(next(events().events), nil)
    display()
    MurgleDB.quests.rewardValues = false
    addon.Rewards:ApplyAll()
    eq(buttons[2].marker.shown, false)
    display()
    eq(buttons[2].marker.shown, false)
    MurgleDB.quests.rewardValues = true
    addon.Rewards:ApplyAll()
    display()
    eq(buttons[2].marker.shown, true)
end)

test("reward values skips currency ambiguity protected and unsupported frames", function()
    local _, buttons, data, display = setup(true)
    data[2].currency = true
    display()
    eq(buttons[1].marker, nil)
    data[2].currency = false
    buttons[2].IsProtected = function()
        return true
    end
    display()
    eq(buttons[2].marker, nil)
    buttons[2].IsProtected = function()
        return false
    end
    QuestInfoFrame.rewardsFrame = {}
    display()
    eq(buttons[2].marker, nil)
end)

test("reward values missing APIs zero prices malformed counts and combat fail closed", function()
    local addon, buttons, data, display = setup(true)
    data[1].price, data[2].price = 0, 0
    display()
    eq(buttons[2].marker, nil)
    data[2].price, data[2].count = 100, 0
    display()
    eq(buttons[2].marker, nil)
    data[2].count = 2
    InCombatLockdown = function()
        return true
    end
    display()
    eq(buttons[2].marker, nil)
    InCombatLockdown = function()
        return false
    end
    C_Item.GetItemInfo = nil
    addon.Rewards:ApplyAll()
    display()
    eq(buttons[2].marker, nil)
end)
