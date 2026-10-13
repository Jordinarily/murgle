local H = dofile("tests/helpers.lua")
local UI = dofile("tests/ui_helpers.lua")
local events = {
    "LOOT_ITEM_ROLL_WON",
    "SHOW_LOOT_TOAST",
    "SHOW_LOOT_TOAST_UPGRADE",
    "SHOW_PVP_FACTION_LOOT_TOAST",
    "SHOW_RATED_PVP_REWARD_TOAST",
    "SHOW_LOOT_TOAST_LEGENDARY_LOOTED",
}
local function fixture()
    AlertFrame = H.newEventFrame()
    function AlertFrame:IsProtected()
        return self.protected == true
    end
    for _, event in ipairs(events) do
        AlertFrame:RegisterEvent(event)
    end
    AlertFrame:RegisterEvent("ACHIEVEMENT_EARNED")
    AlertFrame:RegisterEvent("QUEST_TURNED_IN")
end
local function block(M, value)
    MurgleDB.interface.blockLootToasts = value
    M.Interface.ApplyLootToasts()
end

test("loot toast suppression changes only six notification registrations and restores them", function()
    UI.withAddon(function(M, state)
        eq(MurgleDB.interface.blockLootToasts, false)
        block(M, true)
        for _, event in ipairs(events) do
            eq(AlertFrame:IsEventRegistered(event), false)
        end
        eq(AlertFrame:IsEventRegistered("ACHIEVEMENT_EARNED"), true)
        eq(AlertFrame:IsEventRegistered("QUEST_TURNED_IN"), true)
        block(M, true)
        block(M, false)
        for _, event in ipairs(events) do
            eq(AlertFrame:IsEventRegistered(event), true)
        end
        eq(#state.frames, 1)
        eq(next(state.frames[1].events), nil)
    end, fixture)
end)

test("loot toast restore preserves originally absent events and captured frame", function()
    UI.withAddon(function(M)
        local original = AlertFrame
        original:UnregisterEvent("SHOW_LOOT_TOAST_UPGRADE")
        block(M, true)
        AlertFrame = H.newEventFrame()
        M.ResetDB()
        eq(original:IsEventRegistered("SHOW_LOOT_TOAST"), true)
        eq(original:IsEventRegistered("SHOW_LOOT_TOAST_UPGRADE"), false)
        eq(next(AlertFrame.events), nil)
    end, fixture)
end)

test("loot toast startup and combat cancellation apply the latest choice", function()
    UI.withAddon(function(M, state)
        eq(AlertFrame:IsEventRegistered("SHOW_LOOT_TOAST"), false)
        state.combat = true
        block(M, false)
        block(M, true)
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(AlertFrame:IsEventRegistered("SHOW_LOOT_TOAST"), false)
        eq(M.GetDeferredCount(), 0)
        state.combat = true
        M.ResetDB()
        eq(AlertFrame:IsEventRegistered("SHOW_LOOT_TOAST"), false)
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(AlertFrame:IsEventRegistered("SHOW_LOOT_TOAST"), true)
    end, function()
        fixture()
        MurgleDB = { interface = { blockLootToasts = true } }
    end)
end)

test("loot toasts missing and protected integrations fail closed with explicit retry", function()
    UI.withAddon(function(M)
        local original = AlertFrame
        AlertFrame = nil
        block(M, true)
        AlertFrame = original
        original.protected = true
        block(M, true)
        eq(original:IsEventRegistered("SHOW_LOOT_TOAST"), true)
        original.protected = false
        local register = original.RegisterEvent
        original.RegisterEvent = nil
        block(M, true)
        eq(original:IsEventRegistered("SHOW_LOOT_TOAST"), true)
        original.RegisterEvent = register
        block(M, true)
        eq(original:IsEventRegistered("SHOW_LOOT_TOAST"), false)
    end, fixture)
end)

test("loot toast checkbox changes policy and confirmed reset refreshes it", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        local control
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                if M.L.BLOCK_LOOT_TOASTS and region.text == M.L.BLOCK_LOOT_TOASTS then
                    control = frame
                end
            end
        end
        assert(control, "Block loot toasts checkbox is available")
        control:SetChecked(true)
        control.scripts.OnClick(control)
        eq(MurgleDB.interface.blockLootToasts, true)
        eq(AlertFrame:IsEventRegistered("SHOW_LOOT_TOAST"), false)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(control:GetChecked(), false)
        eq(AlertFrame:IsEventRegistered("SHOW_LOOT_TOAST"), true)
    end, fixture)
end)
