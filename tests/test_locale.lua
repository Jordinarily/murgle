local H = dofile("tests/helpers.lua")

local function withLocale(locale, fn)
    local M, calls = {}, 0
    H.withGlobals({
        GetLocale = function()
            calls = calls + 1
            return locale
        end,
    }, function()
        H.loadAddonFile("Locale.lua", M)
        fn(M)
        eq(calls, 1, "locale is detected once only")
    end)
end

test("English fallback provides core and category text", function()
    withLocale("enUS", function(M)
        eq(M.L.TITLE, "Murgle")
        eq(type(M.L.RESET_CONFIRM), "string")
        for _, name in ipairs({
            "INTERFACE",
            "MINIMAP",
            "AUTOMATION",
            "LOOT_VENDORS",
            "CHAT",
            "TOOLTIP",
            "ERRORS_SOUND",
        }) do
            eq(type(M.L["CATEGORY_" .. name]), "string")
        end
        eq(M.GetString("TITLE"), "Murgle")
    end)
end)

test("unknown and untranslated locales use complete English fallback", function()
    for _, locale in ipairs({ "xxXX", "frFR", "deDE" }) do
        withLocale(locale, function(M)
            eq(M.GetString("TITLE"), "Murgle")
            eq(M.GetString("CATEGORY_INTERFACE"), "Interface")
            eq(M.GetString("ABSENT_KEY"), "ABSENT_KEY")
            for _ = 1, 10 do
                M.GetString("TITLE")
            end
        end)
    end
end)

test("localization loads without an available locale API", function()
    H.withGlobals({ GetLocale = false }, function()
        local M = {}
        H.loadAddonFile("Locale.lua", M)
        eq(M.GetString("TITLE"), "Murgle")
    end)
end)
