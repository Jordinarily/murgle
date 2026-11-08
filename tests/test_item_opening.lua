local H = dofile("tests/helpers.lua")
local function withOpening(fn)
    local s = { frames = {}, items = {}, uses = {}, free = 8, autoLoot = true }
    local M = {}
    local function item(bag, slot)
        return s.items[bag] and s.items[bag][slot]
    end
    local values = {
        MurgleDB = { lootVendors = { openClams = false }, automation = { useQuestStarters = false } },
        NUM_BAG_SLOTS = 4,
        CreateFrame = function()
            local f = H.newEventFrame()
            s.frames[#s.frames + 1] = f
            return f
        end,
        InCombatLockdown = function()
            return s.combat == true
        end,
        IsShiftKeyDown = function()
            return s.shift == true
        end,
        IsStealthed = function()
            return s.stealth == true
        end,
        UnitCastingInfo = function()
            return s.casting
        end,
        UnitChannelInfo = function()
            return s.channel
        end,
        SpellIsTargeting = function()
            return s.targeting == true
        end,
        GetCursorInfo = function()
            return s.cursor
        end,
        GetCVarBool = function()
            return s.autoLoot
        end,
        IsModifiedClick = function()
            return s.modifiedLoot == true
        end,
        GetNumLootItems = function()
            return s.loot or 0
        end,
        MerchantFrame = {
            IsShown = function()
                return s.merchant == true
            end,
        },
        QuestFrame = {
            IsShown = function()
                return s.questShown == true
            end,
        },
        StaticPopup1 = {
            IsShown = function()
                return s.popup == true
            end,
        },
        ItemLocation = {
            CreateFromBagAndSlot = function(_, bag, slot)
                return { bag = bag, slot = slot }
            end,
        },
        C_Secrets = {
            ShouldUnitSpellCastingBeSecret = function()
                return s.secret == true
            end,
        },
        C_Item = {
            GetItemGUID = function(loc)
                local i = item(loc.bag, loc.slot)
                return i and i.guid
            end,
            IsItemDataCachedByID = function()
                return not s.uncached
            end,
            GetItemSpell = function()
                return s.spell
            end,
        },
        C_QuestLog = {
            IsQuestFlaggedCompleted = function()
                return s.complete == true
            end,
        },
        C_Container = {
            GetContainerNumSlots = function(bag)
                return s.items[bag] and #s.items[bag] or 0
            end,
            GetContainerNumFreeSlots = function()
                return s.free, 0
            end,
            GetContainerItemInfo = function(bag, slot)
                local i = item(bag, slot)
                if s.onRead then
                    s.onRead(bag, slot)
                end
                if not i then
                    return
                end
                return {
                    itemID = i.id,
                    stackCount = i.count or 1,
                    isLocked = i.locked == true,
                    hasLoot = i.hasLoot == true,
                }
            end,
            GetContainerItemQuestInfo = function(bag, slot)
                local i = item(bag, slot)
                return i and i.quest or {}
            end,
            UseContainerItem = function(bag, slot)
                assert(not s.combat and not s.merchant, "unsafe item use")
                s.uses[#s.uses + 1] = { bag = bag, slot = slot, id = item(bag, slot).id }
                if s.onUse then
                    s.onUse(bag, slot)
                end
            end,
        },
    }
    H.withGlobals(values, function()
        H.loadAddonFile("Modules/ItemOpening.lua", M)
        function s:fire(event, ...)
            for _, f in ipairs(self.frames) do
                if f.events[event] then
                    f.scripts.OnEvent(f, event, ...)
                end
            end
        end
        function s:enable(clams, quests)
            MurgleDB.lootVendors.openClams = clams == true
            MurgleDB.automation.useQuestStarters = quests == true
            M.ItemOpening.ApplyAll()
        end
        function s:clam(id, guid, count)
            return { id = id or 5523, guid = guid or "clam-A", count = count or 1, hasLoot = true }
        end
        function s:starter(id, guid, questID)
            return { id = id or 900, guid = guid or "quest-A", quest = { questID = questID or 42, isActive = false } }
        end
        fn(M, s)
    end)
end

test("item opening disabled startup creates no frame or work", function()
    withOpening(function(M, s)
        M.ItemOpening.Initialize()
        eq(#s.frames, 0)
        eq(#s.uses, 0)
    end)
end)
test("container opening accepts arbitrary loot containers and processes one per event", function()
    withOpening(function(_, s)
        s:enable(true)
        s.items[0] =
            { s:clam(987654, "arbitrary"), s:clam(5523), s:clam(5524, "B"), s:clam(7973, "C"), s:clam(15874, "D") }
        for n = 1, 5 do
            s:fire(n == 1 and "BAG_UPDATE_DELAYED" or "LOOT_CLOSED")
            eq(#s.uses, n)
        end
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 5, "refused unchanged containers never retried")
        eq(s.uses[1].slot, 1)
    end)
end)
test("clam stack continues after successful count changes but not duplicate events", function()
    withOpening(function(_, s)
        s:enable(true)
        s.items[0] = { s:clam(nil, nil, 2) }
        s:fire("BAG_UPDATE_DELAYED")
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 1)
        s.items[0][1].count = 1
        s:fire("LOOT_CLOSED")
        eq(#s.uses, 2)
    end)
end)
for _, guard in ipairs({
    "combat",
    "shift",
    "stealth",
    "casting",
    "channel",
    "targeting",
    "cursor",
    "merchant",
    "questShown",
    "popup",
    "secret",
}) do
    test("item opening pauses for " .. guard .. " and resumes from a native event", function()
        withOpening(function(_, s)
            s:enable(true)
            s.items[0] = { s:clam() }
            s[guard] = true
            s:fire("BAG_UPDATE_DELAYED")
            eq(#s.uses, 0)
            s[guard] = nil
            s:fire("PLAYER_REGEN_ENABLED")
            eq(#s.uses, 1)
        end)
    end)
end
test("clams require unlocked loot metadata auto loot and four free general slots", function()
    withOpening(function(_, s)
        s:enable(true)
        s.items[0] = { s:clam() }
        for _, block in ipairs({ "locked", "noLoot", "noAutoLoot", "full", "loot" }) do
            local i = s.items[0][1]
            i.locked, i.hasLoot = block == "locked", block ~= "noLoot"
            s.autoLoot, s.free, s.loot = block ~= "noAutoLoot", block == "full" and 0 or 8, block == "loot" and 1 or 0
            s:fire("BAG_UPDATE_DELAYED")
            eq(#s.uses, 0)
        end
        s.loot = 0
        s:fire("LOOT_CLOSED")
        eq(#s.uses, 1)
    end)
end)
test("quest starters observe a baseline then open new offers only once without accepting", function()
    withOpening(function(_, s)
        s.items[0] = { s:starter(900, "old") }
        s:enable(false, true)
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 0)
        s.items[0][2] = s:starter(901, "new", 43)
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 1)
        eq(s.uses[1].id, 901)
        s:fire("QUEST_FINISHED")
        s.items[0][2] = s:starter(901, "replacement", 43)
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 1, "declined or already attempted quest never reopens")
    end)
end)
for _, reason in ipairs({ "active", "ordinary", "spell", "complete", "uncached" }) do
    test("quest starter excludes " .. reason, function()
        withOpening(function(_, s)
            s:enable(false, true)
            local i = s:starter()
            if reason == "active" then
                i.quest.isActive = true
            end
            if reason == "ordinary" then
                i.quest = { isQuestItem = true, isActive = false }
            end
            s.spell = reason == "spell" and "Use spell" or nil
            s.complete, s.uncached = reason == "complete", reason == "uncached"
            s.items[0] = { i }
            s:fire("BAG_UPDATE_DELAYED")
            eq(#s.uses, 0)
        end)
    end)
end
test("new quest offer waits through combat and never uses bank items", function()
    withOpening(function(_, s)
        s:enable(false, true)
        s.items[0] = { s:starter() }
        s.items[5] = { s:starter(902, "bank", 44) }
        s.combat = true
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 0)
        s.combat = false
        s:fire("PLAYER_REGEN_ENABLED")
        eq(#s.uses, 1)
        eq(s.uses[1].bag, 0)
    end)
end)
test("disabling unregisters all events and re-enable does not reopen old quests", function()
    withOpening(function(_, s)
        s:enable(true, true)
        s:enable(false, false)
        eq(next(s.frames[1].events), nil)
        s.items[0] = { s:starter() }
        s:fire("BAG_UPDATE_DELAYED")
        s:enable(false, true)
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 0)
    end)
end)

test("item opening waits for loot closure and handles synchronous event reentry", function()
    withOpening(function(_, s)
        s:enable(true)
        s.items[0] = { s:clam(), s:clam(7973, "second") }
        s.onUse = function()
            s:fire("BAG_UPDATE_DELAYED")
        end
        s:fire("BAG_UPDATE_DELAYED")
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 1)
        s:fire("LOOT_CLOSED")
        eq(#s.uses, 2)
    end)
end)
test("new quest option does not inherit old items observed with clams enabled", function()
    withOpening(function(_, s)
        s:enable(true, false)
        s.items[0] = { s:starter() }
        s:fire("BAG_UPDATE_DELAYED")
        s:enable(true, true)
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 0)
    end)
end)
test("item use revalidates GUID immediately before acting", function()
    withOpening(function(_, s)
        s:enable(true)
        s.items[0] = { s:clam() }
        local reads = 0
        s.onRead = function()
            reads = reads + 1
            if reads == 2 then
                s.items[0][1].guid = "replacement"
            end
        end
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 0)
    end)
end)
test("missing essential APIs cannot create an automation frame", function()
    withOpening(function(_, s)
        H.withGlobals({ C_Secrets = false }, function()
            s:enable(true, true)
        end)
        eq(#s.frames, 0)
        eq(#s.uses, 0)
    end)
end)
test("missing quest API leaves starters manual while clams still work", function()
    withOpening(function(_, s)
        C_Container.GetContainerItemQuestInfo = nil
        s:enable(true, true)
        s.items[0] = { s:starter(), s:clam() }
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 1)
        eq(s.uses[1].id, 5523)
    end)
end)

test("enabling quest starters during combat captures baseline before later acquisitions", function()
    withOpening(function(_, s)
        s.combat = true
        s.items[0] = { s:starter(900, "old", 42) }
        s:enable(false, true)
        s.items[0][2] = s:starter(901, "new", 43)
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 0)
        s.combat = false
        s:fire("PLAYER_REGEN_ENABLED")
        eq(#s.uses, 1)
        eq(s.uses[1].id, 901)
    end)
end)
test("pending quest data requests once and resumes on item data completion", function()
    withOpening(function(_, s)
        local requests = 0
        C_Item.RequestLoadItemDataByID = function(id)
            eq(id, 900)
            requests = requests + 1
        end
        s:enable(false, true)
        s.uncached = true
        s.items[0] = { s:starter() }
        s:fire("BAG_UPDATE_DELAYED")
        s:fire("BAG_UPDATE_DELAYED")
        eq(requests, 1)
        eq(#s.uses, 0)
        s.uncached = false
        s:fire("ITEM_DATA_LOAD_RESULT", 900, true)
        eq(#s.uses, 1)
    end)
end)
test("Shift release resumes pending items without an unrelated bag event", function()
    withOpening(function(_, s)
        s:enable(true)
        s.shift = true
        s.items[0] = { s:clam() }
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 0)
        s.shift = false
        s:fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
        eq(#s.uses, 1)
    end)
end)

test("container opening leaves ordinary items and missing loot metadata alone", function()
    withOpening(function(_, s)
        s:enable(true)
        local plain, unknown = s:clam(999, "plain"), s:clam(1000, "unknown")
        plain.hasLoot, unknown.hasLoot = false, nil
        s.items[0] = { plain, unknown, s:clam(1001, "container") }
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 1)
        eq(s.uses[1].id, 1001)
    end)
end)
test("container loot eligibility is revalidated before item use", function()
    withOpening(function(_, s)
        s:enable(true)
        s.items[0] = { s:clam(5523) }
        local reads = 0
        s.onRead = function()
            reads = reads + 1
            if reads == 2 then
                s.items[0][1].hasLoot = false
            end
        end
        s:fire("BAG_UPDATE_DELAYED")
        eq(#s.uses, 0)
    end)
end)
