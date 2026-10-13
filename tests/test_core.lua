local H = dofile("tests/helpers.lua")

local function withCore(inCombat, fn)
    local state = { combat = inCombat, frames = {}, messages = {}, errors = {} }
    local M = {}
    H.withGlobals({
        Murgle = false,
        MurgleDB = false,
        SLASH_MURGLE1 = false,
        SlashCmdList = {},
        CreateFrame = function(kind)
            eq(kind, "Frame")
            local frame = H.newEventFrame()
            state.frames[#state.frames + 1] = frame
            return frame
        end,
        InCombatLockdown = function()
            return state.combat
        end,
        C_AddOns = {
            GetAddOnMetadata = function(name, key)
                eq(name, "Murgle")
                eq(key, "Version")
                return "1.0.0"
            end,
        },
        print = function(message)
            state.messages[#state.messages + 1] = message
        end,
        geterrorhandler = function()
            return function(err)
                state.errors[#state.errors + 1] = err
            end
        end,
    }, function()
        H.loadAddonFile("Core.lua", M)
        H.loadAddonFile("Defaults.lua", M)
        fn(M, state, state.frames[1])
    end)
end

test("command parser supports aliases, case and whitespace without guessing", function()
    withCore(false, function(M)
        local cases = {
            { "", "toggle" },
            { "  ", "toggle" },
            { "reset", "reset" },
            { "r", "reset" },
            { "RESET", "reset" },
            { " R ", "reset" },
            { "version", "version" },
            { "v", "version" },
            { "VERSION", "version" },
            { "V", "version" },
            { "wrong", "unknown" },
            { "reset yes", "unknown" },
        }
        for _, row in ipairs(cases) do
            eq(M.ParseCommand(row[1]), row[2], row[1])
        end
        eq(M.ParseCommand(nil), "toggle")
    end)
end)

test("startup initializes only once for this addon and leaves no events or UI work", function()
    withCore(false, function(M, state, frame)
        eq(#state.frames, 1)
        eq(frame:IsEventRegistered("ADDON_LOADED"), true)
        local initialized = 0
        M.Interface = {
            Initialize = function()
                initialized = initialized + 1
            end,
        }
        frame.scripts.OnEvent(frame, "ADDON_LOADED", "AnotherAddon")
        eq(MurgleDB, false)
        eq(initialized, 0)
        frame.scripts.OnEvent(frame, "ADDON_LOADED", "Murgle")
        eq(Murgle, M)
        eq(MurgleDB.errors.mode, "important")
        eq(initialized, 1)
        eq(next(frame.events), nil)
        eq(frame.scripts.OnUpdate, nil)
        eq(#state.frames, 1)
        M.Initialize()
        eq(initialized, 1)
        eq(SLASH_MURGLE1, "/murgle")
        eq(type(SlashCmdList.MURGLE), "function")
    end)
end)

test("slash commands dispatch version, toggle, confirmation and help exactly once", function()
    withCore(false, function(M, state)
        local toggles, resets = 0, 0
        M.Settings = {
            Toggle = function()
                toggles = toggles + 1
            end,
            ConfirmReset = function()
                resets = resets + 1
            end,
        }
        M.L = { COMMAND_HELP = "localized help" }
        M.Initialize()
        SlashCmdList.MURGLE("")
        eq(toggles, 1)
        for _, value in ipairs({ "r", "reset", "R", "RESET" }) do
            SlashCmdList.MURGLE(value)
        end
        eq(resets, 4)
        for _, value in ipairs({ "v", "version", "V", "VERSION" }) do
            SlashCmdList.MURGLE(value)
        end
        eq(#state.messages, 4)
        for _, value in ipairs(state.messages) do
            eq(value, "Murgle 1.0.0")
        end
        SlashCmdList.MURGLE("nonsense")
        eq(#state.messages, 5)
        eq(state.messages[5], "localized help")
    end)
end)

test("missing settings and metadata fail conservatively before UI implementation", function()
    withCore(false, function(M, state)
        C_AddOns = false
        M.Initialize()
        SlashCmdList.MURGLE("")
        SlashCmdList.MURGLE("r")
        eq(#state.messages, 2)
        eq(M.GetVersion(), "1.0.0")
    end)
end)

test("combat deferral registers only while work is pending", function()
    withCore(true, function(M, state, frame)
        M.Initialize()
        local ran = 0
        M.DeferUntilOutOfCombat("unit-frame", function()
            ran = ran + 1
        end)
        eq(ran, 0)
        eq(M.GetDeferredCount(), 1)
        eq(frame:IsEventRegistered("PLAYER_REGEN_ENABLED"), true)
        frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED")
        eq(ran, 0)
        state.combat = false
        frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED")
        eq(ran, 1)
        eq(M.GetDeferredCount(), 0)
        eq(next(frame.events), nil)
    end)
end)

test("combat deferral replaces duplicate key and applies only the latest request", function()
    withCore(true, function(M, state, frame)
        local result = 0
        M.DeferUntilOutOfCombat("same", function()
            result = 1
        end)
        M.DeferUntilOutOfCombat("same", function()
            result = 2
        end)
        eq(M.GetDeferredCount(), 1)
        state.combat = false
        frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED")
        eq(result, 2)
    end)
end)

test("safe immediate requests cancel stale queued work for the same key", function()
    withCore(true, function(M, state, frame)
        local result = 0
        M.DeferUntilOutOfCombat("same", function()
            result = 1
        end)
        state.combat = false
        M.DeferUntilOutOfCombat("same", function()
            result = 2
        end)
        eq(result, 2)
        eq(M.GetDeferredCount(), 0)
        eq(frame:IsEventRegistered("PLAYER_REGEN_ENABLED"), false)
        frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED")
        eq(result, 2)
    end)
end)

test("a failed deferred change cannot strand unrelated work or the combat event", function()
    withCore(true, function(M, state, frame)
        local ran = 0
        M.DeferUntilOutOfCombat("broken", function()
            error("deliberate failure")
        end)
        M.DeferUntilOutOfCombat("healthy", function()
            ran = ran + 1
        end)
        state.combat = false
        frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED")
        eq(ran, 1)
        eq(#state.errors, 1)
        eq(M.GetDeferredCount(), 0)
        eq(frame:IsEventRegistered("PLAYER_REGEN_ENABLED"), false)
    end)
end)

test("combat restarting during queue execution retains pending work safely", function()
    withCore(true, function(M, state, frame)
        local ran = 0
        local function change()
            ran = ran + 1
            state.combat = true
        end
        M.DeferUntilOutOfCombat("one", change)
        M.DeferUntilOutOfCombat("two", change)
        state.combat = false
        frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED")
        eq(ran, 1)
        eq(M.GetDeferredCount(), 1)
        eq(frame:IsEventRegistered("PLAYER_REGEN_ENABLED"), true)
        state.combat = false
        frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED")
        eq(ran, 2)
        eq(M.GetDeferredCount(), 0)
        eq(frame:IsEventRegistered("PLAYER_REGEN_ENABLED"), false)
    end)
end)

test("reset replaces saved variables, restores defaults and reapplies existing modules", function()
    withCore(false, function(M)
        M.Initialize()
        local old = MurgleDB
        old.interface.hideTalkingHead = false
        local calls = 0
        local function applied()
            eq(MurgleDB.interface.hideTalkingHead, true)
            calls = calls + 1
        end
        for _, name in ipairs({
            "Interface",
            "Minimap",
            "Quests",
            "Automation",
            "LootVendors",
            "Chat",
            "Tooltip",
            "Errors",
            "Sound",
        }) do
            M[name] = { ApplyAll = applied }
        end
        M.ResetDB()
        eq(MurgleDB == old, false)
        eq(old.interface.hideTalkingHead, false)
        eq(calls, 9)
    end)
end)

test("reload alias registers once and invokes only native reload on command", function()
    local calls = 0
    H.withGlobals({
        ReloadUI = function()
            calls = calls + 1
        end,
        SLASH_MURGLERELOAD1 = false,
        hash_SlashCmdList = {},
        IsSecureCmd = function()
            return false
        end,
    }, function()
        withCore(false, function(M)
            M.Initialize()
            eq(calls, 0)
            eq(SLASH_MURGLERELOAD1, "/rl")
            SlashCmdList.MURGLERELOAD()
            eq(calls, 1)
            local callback = SlashCmdList.MURGLERELOAD
            M.Initialize()
            eq(SlashCmdList.MURGLERELOAD, callback)
        end)
    end)
end)

test("reload alias respects secure cached and unparsed addon registrations", function()
    for _, conflict in ipairs({ "secure", "cached", "alias" }) do
        H.withGlobals({
            ReloadUI = function()
                error("must not reload at startup")
            end,
            SLASH_MURGLERELOAD1 = false,
            SLASH_OTHER1 = "/other",
            SLASH_OTHER2 = "/rL",
            hash_SlashCmdList = conflict == "cached" and { ["/RL"] = function() end } or {},
            IsSecureCmd = function(command)
                eq(command, "/rl")
                return conflict == "secure"
            end,
        }, function()
            withCore(false, function(M)
                local existing = function() end
                if conflict == "alias" then
                    SlashCmdList.OTHER = existing
                end
                M.Initialize()
                eq(SLASH_MURGLERELOAD1, false)
                eq(SlashCmdList.MURGLERELOAD, nil)
                if conflict == "alias" then
                    eq(SlashCmdList.OTHER, existing)
                end
            end)
        end)
    end
end)
