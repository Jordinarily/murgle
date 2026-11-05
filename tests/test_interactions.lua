local H = dofile("tests/helpers.lua")

local function withInteractions(fn)
    local M, frame, hooks = {}, nil, {}
    local state = { selected = 0, confirmed = 0, replaced = 0, rolled = 0 }
    local definition = { OnAccept = function() end }
    local popup = H.newVisibilityFrame(true)
    popup.which, popup.dialogInfo, popup.data = "LOOT_BIND", definition, 1
    local options = {
        {
            gossipOptionID = 10,
            orderIndex = 1,
            icon = 132057,
            flags = 0,
            rewards = {},
            status = 0,
            selectOptionWhenOnlyOption = false,
        },
    }
    local function safe()
        return state.combat ~= true
    end
    H.withGlobals({
        MurgleDB = { automation = {} },
        InCombatLockdown = function()
            return not safe()
        end,
        IsShiftKeyDown = function()
            return state.shift == true
        end,
        Enum = { GossipOptionStatus = { Available = 0 }, LootSlotType = { Item = 1 } },
        C_GossipInfo = {
            GetNumAvailableQuests = function()
                return state.quests or 0
            end,
            GetNumActiveQuests = function()
                return 0
            end,
            ForceGossip = function()
                return state.forced == true
            end,
            GetOptions = function()
                return options
            end,
            SelectOptionByIndex = function(index)
                state.selected = state.selected + 1
                eq(index, 1)
            end,
        },
        CreateFrame = function()
            frame = H.newEventFrame()
            return frame
        end,
        StaticPopup_Show = function() end,
        StaticPopup_FindVisible = function(which)
            return popup.shown and popup.which == which and popup or nil
        end,
        StaticPopupDialogs = { LOOT_BIND = definition, REPLACE_ENCHANT = definition, CONFIRM_LOOT_ROLL = definition },
        ConfirmLootRollDialog_Show = function() end,
        ConfirmDisenchantRollDialog_Show = function() end,
        hooksecurefunc = function(name, fn)
            hooks[name] = fn
        end,
        GetNumLootItems = function()
            return 1
        end,
        GetLootSlotType = function()
            return 1
        end,
        GetLootSlotInfo = function()
            return nil, nil, nil, nil, nil, false
        end,
        ConfirmLootSlot = function(slot)
            eq(slot, 1)
            state.confirmed = state.confirmed + 1
        end,
        ConfirmLootRoll = function(id, kind)
            eq(id, 3)
            eq(kind, 2)
            state.rolled = state.rolled + 1
        end,
        C_Item = {
            ReplaceEnchant = function()
                state.replaced = state.replaced + 1
            end,
        },
    }, function()
        H.loadAddonFile("Modules/Interactions.lua", M)
        fn(M.Interactions, state, options, hooks, popup, function()
            return frame
        end, definition)
    end)
end

test("native interactions disabled startup has no events hooks or actions", function()
    withInteractions(function(I, state, _, hooks, _, getFrame)
        I.Initialize()
        eq(getFrame(), nil)
        eq(next(hooks), nil)
        eq(state.selected + state.confirmed + state.replaced + state.rolled, 0)
    end)
end)

test("service gossip selects only sole free taxi and never repeats the same conversation", function()
    withInteractions(function(I, state, _, _, _, getFrame)
        MurgleDB.automation.skipServiceGossip = true
        I.ApplyAll()
        local frame = getFrame()
        frame.scripts.OnEvent(frame, "GOSSIP_SHOW")
        eq(state.selected, 1)
        frame.scripts.OnEvent(frame, "GOSSIP_SHOW")
        eq(state.selected, 1)
        frame.scripts.OnEvent(frame, "GOSSIP_CLOSED")
        frame.scripts.OnEvent(frame, "GOSSIP_SHOW")
        eq(state.selected, 2)
        MurgleDB.automation.skipServiceGossip = false
        I.ApplyAll()
        eq(next(frame.events), nil)
    end)
end)

test("service gossip leaves quests forced multiple paid flagged and bypassed options alone", function()
    withInteractions(function(I, state, options, _, _, getFrame)
        MurgleDB.automation.skipServiceGossip = true
        I.ApplyAll()
        local frame = getFrame()
        local function show()
            frame.scripts.OnEvent(frame, "GOSSIP_SHOW")
            eq(state.selected, 0)
        end
        state.quests = 1
        show()
        state.quests = 0
        state.forced = true
        show()
        state.forced = false
        state.shift = true
        show()
        state.shift = false
        state.combat = true
        show()
        state.combat = false
        options[1].flags = 1
        show()
        options[1].flags = 0
        options[1].icon = 999
        show()
        options[1].icon = 132057
        options[1].selectOptionWhenOnlyOption = true
        show()
        options[1].selectOptionWhenOnlyOption = false
        options[1].rewards = { {} }
        show()
        options[1].rewards = {}
        options[2] = options[1]
        show()
    end)
end)

test("loot pickup confirmation accepts exact current native slot and hides only its dialog", function()
    withInteractions(function(I, state, _, hooks, popup)
        MurgleDB.automation.confirmLootPickup = true
        I.ApplyAll()
        hooks.StaticPopup_Show("LOOT_BIND")
        eq(state.confirmed, 1)
        eq(popup.shown, false)
        popup.shown = true
        popup.which = "SPELL_CONFIRMATION_PROMPT"
        hooks.StaticPopup_Show(popup.which)
        eq(state.confirmed, 1)
    end)
end)

test("native confirmation choices stay separate and skip combat Shift altered or protected dialogs", function()
    withInteractions(function(I, state, _, hooks, popup)
        MurgleDB.automation.confirmEnchantReplace = true
        I.ApplyAll()
        hooks.StaticPopup_Show("LOOT_BIND")
        eq(state.confirmed, 0)
        popup.which = "REPLACE_ENCHANT"
        state.shift = true
        hooks.StaticPopup_Show(popup.which)
        eq(state.replaced, 0)
        state.shift = false
        state.combat = true
        hooks.StaticPopup_Show(popup.which)
        eq(state.replaced, 0)
        state.combat = false
        popup.protected = true
        hooks.StaticPopup_Show(popup.which)
        eq(state.replaced, 0)
        popup.protected = false
        popup.dialogInfo = {}
        hooks.StaticPopup_Show(popup.which)
        eq(state.replaced, 0)
        popup.dialogInfo = StaticPopupDialogs.REPLACE_ENCHANT
        hooks.StaticPopup_Show(popup.which)
        eq(state.replaced, 1)
    end)
end)

test("roll confirmation confirms only the roll already selected by native UI", function()
    withInteractions(function(I, state, _, hooks, popup)
        MurgleDB.automation.confirmLootRolls = true
        I.ApplyAll()
        popup.which, popup.data, popup.data2 = "CONFIRM_LOOT_ROLL", 3, 2
        hooks.ConfirmLootRollDialog_Show(3, 1)
        eq(state.rolled, 0)
        hooks.ConfirmLootRollDialog_Show(3, 2)
        eq(state.rolled, 1)
        popup.shown = true
        MurgleDB.automation.confirmLootRolls = false
        I.ApplyAll()
        hooks.ConfirmLootRollDialog_Show(3, 2)
        eq(state.rolled, 1)
    end)
end)

test("confirm action cannot hide a popup reused synchronously by another native request", function()
    withInteractions(function(I, state, _, hooks, popup)
        MurgleDB.automation.confirmEnchantReplace = true
        I.ApplyAll()
        popup.which = "REPLACE_ENCHANT"
        C_Item.ReplaceEnchant = function()
            state.replaced = state.replaced + 1
            hooks.StaticPopup_Show("REPLACE_ENCHANT")
        end
        hooks.StaticPopup_Show("REPLACE_ENCHANT")
        eq(state.replaced, 1)
        eq(popup.shown, true)
    end)
end)

test("removed native popup definitions leave confirmation untouched", function()
    withInteractions(function(I, state, _, hooks, popup)
        MurgleDB.automation.confirmLootPickup = true
        StaticPopupDialogs.LOOT_BIND = nil
        popup.dialogInfo = nil
        I.ApplyAll()
        hooks.StaticPopup_Show("LOOT_BIND")
        eq(state.confirmed, 0)
    end)
end)
