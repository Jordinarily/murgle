local H = dofile("tests/helpers.lua")
local function setup(fn)
    local values = { HDROutput = "0", HDRBrightness = "203", showQuestLevel = "0", groundEffectDensity = "16" }
    local writes, locked, combat, clamp = {}, false, false, false
    H.withGlobals({
        C_CVar = {
            GetCVarInfo = function(name)
                return values[name], nil, nil, nil, locked, false, false
            end,
            SetCVar = function(name, value)
                writes[#writes + 1] = name
                values[name] = clamp and "32" or tostring(value)
            end,
            GetCVarDefault = function()
                return "16"
            end,
        },
        InCombatLockdown = function()
            return combat
        end,
    }, function()
        local M = {}
        H.loadAddonFile("Modules/NativeOptions.lua", M)
        fn(M.NativeOptions, values, writes, function(l, c, cl)
            locked, combat, clamp = l, c, cl
        end)
    end)
end

test("native options never write at load and expose only known available variables", function()
    setup(function(N, values, writes)
        eq(#writes, 0)
        eq(N.Read("HDROutput"), "0")
        eq(N.Read("missing"), nil)
        eq(N.Set("arbitraryCVar", "1"), nil)
        eq(#writes, 0)
        eq(N.Set("showQuestLevel", "1"), "1")
        eq(values.showQuestLevel, "1")
    end)
end)
test("native options reject invalid ranges locked values and combat without writes", function()
    setup(function(N, _, writes, state)
        for _, v in ipairs({ "nan", "inf", "-1", "2001", "" }) do
            eq(N.Set("HDRBrightness", v), nil)
        end
        eq(N.Set("HDROutput", "2"), nil)
        state(true, false, false)
        eq(N.Set("HDROutput", "1"), nil)
        state(false, true, false)
        eq(N.Set("HDROutput", "1"), nil)
        eq(#writes, 0)
    end)
end)
test("native options return accepted clamped values and reset from client defaults", function()
    setup(function(N, _, writes, state)
        state(false, false, true)
        eq(N.Set("groundEffectDensity", "64"), "32")
        state(false, false, false)
        eq(N.Reset("groundEffectDensity"), "16")
        eq(#writes, 2)
    end)
end)

test("native option reads reject nonfinite data and require reversible write metadata", function()
    setup(function(N, values, writes)
        values.HDRBrightness = "nan"
        eq(N.Read("HDRBrightness"), nil)
        values.HDRBrightness = "inf"
        eq(N.Read("HDRBrightness"), nil)
        C_CVar.GetCVarInfo = function()
            return "1"
        end
        eq(N.Set("HDROutput", "0"), nil)
        eq(#writes, 0)
    end)
end)
