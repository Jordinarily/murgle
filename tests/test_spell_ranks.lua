local Helpers = dofile("tests/helpers.lua")
local function fixture(fn)
    local s = {
        warnings = {},
        books = { { "Fire", "Rank 1", 11 }, { "Fire", "Rank 10", 12 } },
        actions = { [1] = 11 },
        calls = 0,
    }
    local addon = { L = { WARN_LOW_RANK = "%s rank %d learned %d" } }
    local f = Helpers.newEventFrame()
    addon.DeferUntilOutOfCombat = function(_, callback)
        if s.combat then
            s.pending = callback
        else
            callback()
        end
    end
    Helpers.withGlobals({
        MurgleDB = { automation = { warnLowRank = true } },
        CreateFrame = function()
            return f
        end,
        InCombatLockdown = function()
            return s.combat == true
        end,
        issecretvalue = function(v)
            return v == "secret"
        end,
        ActionButton1 = {
            action = 1,
            IsVisible = function()
                return true
            end,
        },
        Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 } },
        C_SpellBook = {
            GetNumSpellBookSkillLines = function()
                s.calls = s.calls + 1
                return s.lines or 1
            end,
            GetSpellBookSkillLineInfo = function()
                return { itemIndexOffset = 0, numSpellBookItems = s.count or #s.books, shouldHide = false }
            end,
            GetSpellBookItemName = function(i)
                return s.books[i][1], s.books[i][2]
            end,
            GetSpellBookItemInfo = function(i)
                return {
                    spellID = s.books[i][3],
                    actionID = s.books[i][3],
                    itemType = 1,
                    isPassive = false,
                    isOffSpec = false,
                }
            end,
        },
        C_Spell = {
            GetSpellName = function(id)
                for _, v in ipairs(s.books) do
                    if v[3] == id then
                        return v[1]
                    end
                end
            end,
            GetSpellSubtext = function(id)
                for _, v in ipairs(s.books) do
                    if v[3] == id then
                        return v[2]
                    end
                end
            end,
        },
        GetActionInfo = function(slot)
            if s.actions[slot] then
                return s.actionType or "spell", s.actions[slot]
            end
        end,
        DEFAULT_CHAT_FRAME = {
            AddMessage = function(_, message)
                s.warnings[#s.warnings + 1] = message
            end,
        },
    }, function()
        Helpers.loadAddonFile("Modules/SpellRanks.lua", addon)
        addon.SpellRanks.Initialize()
        function s.fire()
            f.scripts.OnEvent(f, "SPELLS_CHANGED")
        end
        fn(s, addon, f)
    end)
end

test("spell ranks numeric localized rank parsing", function()
    fixture(function(_, addon)
        for text, expected in pairs({ ["Rank 10"] = 10, ["Rang 2"] = 2, ["等级 3"] = 3, ["4"] = 4 }) do
            eq(addon.SpellRanks.ParseRank(text), expected)
        end
        for _, text in ipairs({ "", "Rank 0", "Rank -1", "Rank 1.2", "Rank 2/3", "Rank II", "secret" }) do
            eq(addon.SpellRanks.ParseRank(text), nil)
        end
    end)
end)

test("spell ranks event scans warn without modifying actions", function()
    fixture(function(s)
        eq(#s.warnings, 0)
        s.fire()
        eq(#s.warnings, 1)
        eq(s.warnings[1], "Fire rank 1 learned 10")
        eq(s.actions[1], 11)
        s.fire()
        eq(#s.warnings, 1)
    end)
end)

test("spell ranks changed rank or action permits later warning", function()
    fixture(function(s, addon)
        addon.SpellRanks.Check()
        s.actions[1] = 12
        addon.SpellRanks.Check()
        s.actions[1] = 11
        addon.SpellRanks.Check()
        eq(#s.warnings, 2)
        s.books[2][2] = "Rank 11"
        addon.SpellRanks.Check()
        eq(#s.warnings, 3)
    end)
end)

test("spell ranks combat work defers and checks current setting", function()
    fixture(function(s, addon)
        s.combat = true
        s.fire()
        eq(s.calls, 0)
        eq(type(s.pending), "function")
        MurgleDB.automation.warnLowRank = false
        addon.SpellRanks.ApplyAll()
        s.combat = false
        s.pending()
        eq(s.calls, 0)
    end)
end)

test("spell ranks disabled unregisters and clears duplicate state", function()
    fixture(function(s, addon, f)
        s.fire()
        MurgleDB.automation.warnLowRank = false
        addon.SpellRanks.ApplyAll()
        eq(f.events.SPELLS_CHANGED, nil)
        MurgleDB.automation.warnLowRank = true
        addon.SpellRanks.ApplyAll()
        s.fire()
        eq(#s.warnings, 2)
    end)
end)

for _, reason in ipairs({ "macro", "secret", "missing", "bounds", "unlearned", "override" }) do
    test("spell ranks skips " .. reason, function()
        fixture(function(s, addon)
            if reason == "macro" then
                s.actionType = "macro"
            elseif reason == "secret" then
                s.books[2][2] = "secret"
            elseif reason == "missing" then
                C_Spell.GetSpellSubtext = nil
            elseif reason == "bounds" then
                s.count = 1000000
            elseif reason == "unlearned" then
                s.actions[1] = 999
            elseif reason == "override" then
                C_SpellBook.GetSpellBookItemInfo = function()
                    return { spellID = 12, actionID = 11, itemType = 1, isPassive = false, isOffSpec = false }
                end
            end
            addon.SpellRanks.Check()
            eq(#s.warnings, 0)
        end)
    end)
end

test("spell ranks reads native paged slots once and skips absent buttons", function()
    fixture(function(s, addon)
        Helpers.withGlobals({ MultiBarBottomLeftButton1 = ActionButton1 }, function()
            s.actions[13] = 11
            ActionButton1.action = 13
            addon.SpellRanks.Check()
            eq(#s.warnings, 1)
            eq(s.actions[13], 11)
            ActionButton1.action = nil
            addon.SpellRanks.Check()
            eq(#s.warnings, 1)
        end)
    end)
end)

test("spell ranks omits hidden native buttons", function()
    fixture(function(s, addon)
        ActionButton1.IsVisible = function()
            return false
        end
        addon.SpellRanks.Check()
        eq(#s.warnings, 0)
    end)
end)

test("spell ranks emits one message for duplicate low spell slots", function()
    fixture(function(s, addon)
        Helpers.withGlobals({
            ActionButton2 = {
                action = 2,
                IsVisible = function()
                    return true
                end,
            },
        }, function()
            s.actions[2] = 11
            addon.SpellRanks.Check()
            eq(#s.warnings, 1)
        end)
    end)
end)
