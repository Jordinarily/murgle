local H = dofile("tests/helpers.lua")
local UI = dofile("tests/ui_helpers.lua")

local function withLoot(fn, enabled)
    local state = { calls = {}, frames = {}, count = 3, auto = true, modifier = false }
    H.withGlobals({
        MurgleDB = { lootVendors = { fastLoot = enabled == true } },
        CreateFrame = function()
            local frame = H.newEventFrame()
            state.frames[#state.frames + 1] = frame
            return frame
        end,
        InCombatLockdown = function()
            return state.combat == true
        end,
        GetCVarBool = function(name)
            eq(name, "autoLootDefault")
            return state.auto
        end,
        IsModifiedClick = function(name)
            eq(name, "AUTOLOOTTOGGLE")
            return state.modifier
        end,
        GetNumLootItems = function()
            return state.count
        end,
        GetLootSlotInfo = function(slot)
            return nil, nil, nil, nil, nil, slot == state.locked
        end,
        GetLootSlotType = function(slot)
            return slot == state.unknown and 99 or 1
        end,
        Enum = { LootSlotType = { Item = 1, Money = 2, Currency = 3 } },
        LootSlot = function(slot)
            state.calls[#state.calls + 1] = slot
            if state.onLoot then
                state.onLoot(slot)
            end
        end,
    }, function()
        local M = {}
        H.loadAddonFile("Modules/LootVendors.lua", M)
        function state:fire(event, value)
            local frame = self.frames[1]
            if frame and frame.events[event] then
                frame.scripts.OnEvent(frame, event, value)
            end
        end
        fn(M.LootVendors, state)
    end)
end

test("Fast Loot disabled startup is inert and disabling unregisters its events", function()
    withLoot(function(L, s)
        L.ApplyAll()
        eq(#s.frames, 0)
        MurgleDB.lootVendors.fastLoot = true
        L.ApplyAll()
        eq(#s.frames, 1)
        eq(s.frames[1].events.LOOT_READY, true)
        eq(s.frames[1].events.LOOT_CLOSED, true)
        L.ApplyAll()
        eq(#s.frames, 1)
        MurgleDB.lootVendors.fastLoot = false
        L.ApplyAll()
        eq(next(s.frames[1].events), nil)
        s:fire("LOOT_READY", true)
        eq(#s.calls, 0)
    end)
end)

test("Fast Loot requests unlocked known slots in reverse order once per window", function()
    withLoot(function(L, s)
        L.Initialize()
        s.locked = 2
        s:fire("LOOT_READY", true)
        eq(table.concat(s.calls, ","), "3,1")
        s:fire("LOOT_READY", true)
        eq(#s.calls, 2)
        s:fire("LOOT_CLOSED")
        s.locked, s.unknown = nil, 1
        s:fire("LOOT_READY", true)
        eq(table.concat(s.calls, ","), "3,1,3,2")
    end, true)
end)

test("Fast Loot respects native auto loot and modifier combinations", function()
    withLoot(function(L, s)
        L.ApplyAll()
        for _, pair in ipairs({ { false, false }, { true, true } }) do
            s.auto, s.modifier = pair[1], pair[2]
            s:fire("LOOT_READY", true)
        end
        eq(#s.calls, 0)
        s.auto, s.modifier = false, true
        s:fire("LOOT_READY", true)
        eq(#s.calls, 3)
    end, true)
end)

test("Fast Loot fails closed on unknown payload policy counts APIs and combat", function()
    withLoot(function(L, s)
        L.ApplyAll()
        s:fire("LOOT_READY", false)
        s:fire("LOOT_READY", nil)
        s:fire("LOOT_READY", 1)
        s.combat = true
        s:fire("LOOT_READY", true)
        s.combat = false
        for _, value in ipairs({ -1, 1.5, math.huge, 0 / 0, "3", false, 0 }) do
            s.count = value
            s:fire("LOOT_READY", true)
        end
        s.count, s.auto = 3, nil
        s:fire("LOOT_READY", true)
        s.auto, s.modifier = true, nil
        s:fire("LOOT_READY", true)
        s.modifier = false
        GetLootSlotInfo = nil
        s:fire("LOOT_READY", true)
        eq(#s.calls, 0)
    end, true)
end)

test("Fast Loot handles synchronous reentry and closure without further actions", function()
    withLoot(function(L, s)
        L.ApplyAll()
        s.onLoot = function()
            s:fire("LOOT_READY", true)
            s:fire("LOOT_CLOSED")
        end
        s:fire("LOOT_READY", true)
        eq(table.concat(s.calls, ","), "3")
        s.onLoot = nil
        s:fire("LOOT_READY", true)
        eq(table.concat(s.calls, ","), "3,3,2,1")
    end, true)
end)

test("Fast Loot stops if disabled or modifier changes during the pass", function()
    for _, change in ipairs({ "disable", "modifier", "combat" }) do
        withLoot(function(L, s)
            L.ApplyAll()
            s.onLoot = function()
                if change == "disable" then
                    MurgleDB.lootVendors.fastLoot = false
                    L.ApplyAll()
                elseif change == "modifier" then
                    s.modifier = true
                else
                    s.combat = true
                end
            end
            s:fire("LOOT_READY", true)
            eq(#s.calls, 1)
        end, true)
    end
end)

test("Fast Loot missing integration skips startup and can retry on explicit apply", function()
    withLoot(function(L, s)
        local loot = LootSlot
        LootSlot = nil
        L.Initialize()
        eq(#s.frames, 0)
        LootSlot = loot
        L.ApplyAll()
        s:fire("LOOT_READY", true)
        eq(#s.calls, 3)
    end, true)
end)

test("Fast Loot setting is available and preserves explicit disabled choice", function()
    UI.withAddon(function(M, s)
        eq(MurgleDB.lootVendors.fastLoot, false)
        M.Settings.Toggle()
        M.Settings.SelectCategory("LootVendors")
        local found
        for _, frame in ipairs(s.frames) do
            if frame.kind == "CheckButton" then
                for _, region in ipairs(frame.regions) do
                    if region.text == M.L.FAST_LOOT then
                        found = frame
                    end
                end
            end
        end
        assert(found, "Fast Loot checkbox")
        found:SetChecked(true)
        found.scripts.OnClick(found)
        eq(MurgleDB.lootVendors.fastLoot, true)
    end, function()
        MurgleDB = { lootVendors = { fastLoot = false } }
    end)
end)
