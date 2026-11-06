local H = dofile("tests/helpers.lua")
test("native quest-level helper cannot write removed graphics settings", function()
    local value, writes = "0", 0
    H.withGlobals({
        C_CVar = {
            GetCVarInfo = function()
                return value, nil, nil, nil, false, false, false
            end,
            SetCVar = function(_, v)
                value = v
                writes = writes + 1
            end,
        },
        InCombatLockdown = function()
            return false
        end,
    }, function()
        local M = {}
        H.loadAddonFile("Modules/NativeOptions.lua", M)
        eq(writes, 0)
        eq(M.NativeOptions.Set("HDROutput", "1"), nil)
        eq(M.NativeOptions.Set("groundEffectDensity", "64"), nil)
        eq(writes, 0)
        eq(M.NativeOptions.Set("showQuestLevel", "1"), "1")
        eq(writes, 1)
        eq(M.NativeOptions.Set("showQuestLevel", "2"), nil)
        eq(writes, 1)
    end)
end)
test("native quest-level helper refuses combat and unavailable protection metadata", function()
    H.withGlobals({
        C_CVar = {
            GetCVarInfo = function()
                return "0", nil, nil, nil, false, false, false
            end,
            SetCVar = function()
                error("must not write")
            end,
        },
        InCombatLockdown = function()
            return true
        end,
    }, function()
        local M = {}
        H.loadAddonFile("Modules/NativeOptions.lua", M)
        eq(M.NativeOptions.Set("showQuestLevel", "1"), nil)
        InCombatLockdown = function()
            return false
        end
        C_CVar.GetCVarInfo = function()
            return "0"
        end
        eq(M.NativeOptions.Set("showQuestLevel", "1"), nil)
    end)
end)
