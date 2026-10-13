local H = dofile("tests/helpers.lua")
local UI = dofile("tests/ui_helpers.lua")

local function withSparkles(fn, enabled)
    local values = {
        outlineModeShowLootEffectWhenDisabled = "0",
        graphicsOutlineMode = "2",
        OutlineEngineMode = "2",
        raidGraphicsOutlineMode = "1",
        RAIDOutlineEngineMode = "1",
    }
    local state = { reads = 0, writes = 0 }
    H.withGlobals({
        C_CVar = {
            GetCVarInfo = function(name)
                state.reads = state.reads + 1
                if state.missing == name then
                    return nil
                end
                return values[name], "0", false, false, false, state.secure == name, state.readOnly == name
            end,
            SetCVar = function(name, value)
                state.writes = state.writes + 1
                values[name] = value
                return true
            end,
        },
    }, function()
        UI.withAddon(function(M, ui)
            fn(M, values, state, ui)
        end, function()
            MurgleDB = { quests = { sparkles = enabled } }
        end)
    end)
end

test("quest sparkles disabled startup performs no native reads writes or registration", function()
    withSparkles(function(M, _, state, ui)
        assert(M.Quests, "quest module loaded")
        M.Quests.ApplyAll()
        eq(state.reads, 0)
        eq(state.writes, 0)
        eq(#ui.frames, 1)
    end)
end)

test("quest sparkles apply only native CVars and preserve originals through reload and reset", function()
    withSparkles(function(M, values, state)
        eq(values.outlineModeShowLootEffectWhenDisabled, "1")
        eq(values.graphicsOutlineMode, "0")
        eq(values.OutlineEngineMode, "0")
        eq(values.raidGraphicsOutlineMode, "0")
        eq(values.RAIDOutlineEngineMode, "0")
        M.Quests.ApplyAll()
        eq(state.writes, 5)
        H.loadAddonFile("Modules/Quests.lua", M)
        M.Quests.Initialize()
        M.ResetDB()
        eq(values.outlineModeShowLootEffectWhenDisabled, "0")
        eq(values.graphicsOutlineMode, "2")
        eq(values.OutlineEngineMode, "2")
        eq(values.raidGraphicsOutlineMode, "1")
        eq(values.RAIDOutlineEngineMode, "1")
        eq(MurgleDB.quests.sparkleRestore, nil)
    end, true)
end)

test("quest sparkle preflight rejects unavailable secure and read-only CVars before any write", function()
    withSparkles(function(M, _, state)
        MurgleDB.quests.sparkles = true
        for _, key in ipairs({ "missing", "secure", "readOnly" }) do
            state[key] = "RAIDOutlineEngineMode"
            M.Quests.ApplyAll()
            eq(state.writes, 0)
            state[key] = nil
        end
        M.Quests.ApplyAll()
        eq(state.writes, 5)
    end)
end)

test("quest sparkle disable preserves external graphics changes and explicit apply can reassert", function()
    withSparkles(function(M, values)
        values.graphicsOutlineMode = "3"
        MurgleDB.quests.sparkles = false
        M.Quests.ApplyAll()
        eq(values.graphicsOutlineMode, "3")
        MurgleDB.quests.sparkles = true
        M.Quests.ApplyAll()
        eq(values.graphicsOutlineMode, "0")
        values.graphicsOutlineMode = "2"
        M.Quests.ApplyAll()
        eq(values.graphicsOutlineMode, "0")
        MurgleDB.quests.sparkles = false
        M.Quests.ApplyAll()
        eq(values.graphicsOutlineMode, "3")
    end, true)
end)

test("quest sparkle settings are on Quests and reset restores native graphics", function()
    withSparkles(function(M, values, _, ui)
        M.Settings.Show()
        M.Settings.SelectCategory("Quests")
        eq(type(M.L.QUEST_SPARKLES), "string")
        local control
        for _, frame in ipairs(ui.frames) do
            if frame.kind == "CheckButton" then
                for _, region in ipairs(frame.regions) do
                    if region.text == M.L.QUEST_SPARKLES then
                        control = frame
                    end
                end
            end
        end
        assert(control, "quest sparkle control")
        control:SetChecked(true)
        control.scripts.OnClick(control)
        eq(values.OutlineEngineMode, "0")
        eq(MurgleDB.quests.sparkles, true)
        M.ResetDB()
        eq(values.OutlineEngineMode, "2")
    end)
end)

test("quest sparkle restoration handles graphics setters updating dependent CVars", function()
    withSparkles(function(M, values)
        values.OutlineEngineMode = "0"
        local set = C_CVar.SetCVar
        C_CVar.SetCVar = function(name, value)
            if name == "graphicsOutlineMode" then
                values.OutlineEngineMode = value
            end
            return set(name, value)
        end
        MurgleDB.quests.sparkles = true
        M.Quests.ApplyAll()
        MurgleDB.quests.sparkles = false
        M.Quests.ApplyAll()
        eq(values.graphicsOutlineMode, "2")
        eq(values.OutlineEngineMode, "0")
    end)
end)

test("quest sparkle partial restore retry retains external engine preference across reload", function()
    withSparkles(function(M, values)
        values.OutlineEngineMode = "3"
        local set = C_CVar.SetCVar
        local fail = true
        C_CVar.SetCVar = function(name, value)
            if name == "graphicsOutlineMode" then
                values.OutlineEngineMode = value
            end
            if name == "OutlineEngineMode" and value == "3" and fail then
                return false
            end
            return set(name, value)
        end
        MurgleDB.quests.sparkles = false
        M.Quests.ApplyAll()
        eq(values.OutlineEngineMode, "2")
        fail = false
        H.loadAddonFile("Modules/Quests.lua", M)
        M.Quests.ApplyAll()
        eq(values.OutlineEngineMode, "3")
        eq(MurgleDB.quests.sparkleRestore, nil)
    end, true)
end)

test("quest sparkle reset retains restoration across unavailable API and reload", function()
    withSparkles(function(M, values, state)
        state.missing = "OutlineEngineMode"
        M.ResetDB()
        H.loadAddonFile("Modules/Quests.lua", M)
        M.Quests.Initialize()
        M.ResetDB()
        state.missing = nil
        H.loadAddonFile("Modules/Quests.lua", M)
        M.Quests.Initialize()
        eq(values.OutlineEngineMode, "2")
        eq(values.outlineModeShowLootEffectWhenDisabled, "0")
        eq(MurgleDB.quests.sparkleRestore, nil)
    end, true)
end)
