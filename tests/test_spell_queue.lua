local H = dofile("tests/helpers.lua")
local UI = dofile("tests/ui_helpers.lua")

local function withQueue(fn, saved)
    local state = { value = "175", default = "400", writes = 0 }
    H.withGlobals({
        C_CVar = {
            GetCVarInfo = function(name)
                if name == "SpellQueueWindow" then
                    return state.value, state.default, true, false, state.locked or false, false, false
                end
            end,
            SetCVar = function(name, value)
                eq(name, "SpellQueueWindow")
                state.writes = state.writes + 1
                if state.rejected then
                    return false
                end
                state.value = value
                return true
            end,
        },
    }, function()
        UI.withAddon(function(M, ui)
            fn(M, state, ui)
        end, function()
            MurgleDB = saved or {}
        end)
    end)
end

test("spell queue preserves existing native value on first install and applies deliberate choice", function()
    withQueue(function(M, state)
        eq(state.writes, 0)
        eq(M.Interface.GetSpellQueueWindow(), 175)
        M.Interface.SetSpellQueueWindow(236)
        eq(state.value, "240")
        eq(MurgleDB.interface.spellQueueWindow, 240)
        M.Interface.SetSpellQueueWindow(240)
        eq(state.writes, 1)
        M.Interface.SetSpellQueueWindow(-15)
        eq(state.value, "0")
        M.Interface.SetSpellQueueWindow(900)
        eq(state.value, "400")
        M.Interface.SetSpellQueueWindow(0 / 0)
        eq(state.writes, 3)
    end)
end)

test("spell queue reset restores 400 even without prior ownership", function()
    withQueue(function(M, state)
        M.ResetDB()
        eq(state.value, "400")
        eq(state.writes, 1)
        M.ResetDB()
        eq(state.writes, 1)
    end)
end)

test("spell queue rejects missing locked changed-default and refused native writes", function()
    withQueue(function(M, state)
        for _, key in ipairs({ "locked", "rejected" }) do
            state[key] = true
            M.Interface.SetSpellQueueWindow(200)
            eq(state.value, "175")
            eq(MurgleDB.interface.spellQueueWindow, nil)
            state[key] = nil
        end
        state.default = "300"
        eq(M.Interface.GetSpellQueueWindow(), nil)
        M.Interface.SetSpellQueueWindow(200)
        eq(state.value, "175")
        state.value = nil
        eq(M.Interface.GetSpellQueueWindow(), nil)
    end)
end)

test("spell queue saved explicit preference applies once at startup", function()
    withQueue(function(M, state)
        eq(state.value, "210")
        eq(state.writes, 1)
        M.ApplyAllSettings()
        eq(state.writes, 1)
    end, { interface = { spellQueueWindow = 210 } })
end)

test("spell queue slider refresh never writes and user input changes the native value", function()
    withQueue(function(M, state, ui)
        M.Settings.Show()
        M.Settings.SelectCategory("Automation")
        local slider, help
        for _, frame in ipairs(ui.frames) do
            if frame.kind == "Slider" then
                slider = frame
            end
            if frame.scripts.OnEnter and frame.scripts.OnLeave then
                help = frame
            end
        end
        assert(slider, "native spell queue slider missing")
        assert(help, "spell queue help missing")
        eq(state.writes, 0)
        eq(slider.value, 175)
        slider:SetValue(231)
        eq(state.value, "230")
        eq(slider.value, 230)
        M.ResetDB()
        M.Settings.SelectCategory("Automation")
        eq(slider.value, 400)
        eq(slider.scripts.OnUpdate, nil)
        eq(help.scripts.OnUpdate, nil)
    end)
end)

test("spell queue auto detect samples world latency only on click and preserves manual adjustment", function()
    local samples = 0
    H.withGlobals({
        GetNetStats = function()
            samples = samples + 1
            return 0, 0, 15, 86
        end,
    }, function()
        withQueue(function(M, state, ui)
            M.Settings.Show()
            M.Settings.SelectCategory("Automation")
            local slider, auto
            for _, frame in ipairs(ui.frames) do
                if frame.kind == "Slider" then
                    slider = frame
                elseif frame.kind == "Button" then
                    for _, region in ipairs(frame.regions) do
                        if region.text == M.L.SPELL_QUEUE_AUTO and region.text ~= nil then
                            auto = frame
                        end
                    end
                end
            end
            assert(auto, "auto detect button missing")
            assert(slider, "manual slider missing")
            eq(samples, 0)
            eq(state.writes, 0)
            auto.scripts.OnClick(auto)
            eq(samples, 1)
            eq(state.value, "240")
            eq(slider.value, 240)
            eq(MurgleDB.interface.spellQueueWindow, 240)
            slider:SetValue(180)
            eq(state.value, "180")
            M.Settings.SelectCategory("Automation")
            eq(samples, 1)
        end)
    end)
end)

test("spell queue auto detect clamps high latency and rejects unavailable or invalid samples", function()
    withQueue(function(M, state)
        for _, latency in ipairs({ 900, 0, -1, math.huge, -math.huge, 0 / 0, "50", false }) do
            H.withGlobals({
                GetNetStats = function()
                    return 0, 0, 20, latency
                end,
            }, function()
                local writes = state.writes
                M.Interface.AutoDetectSpellQueueWindow()
                if latency == 900 then
                    eq(state.value, "400")
                else
                    eq(state.writes, writes)
                end
            end)
        end
        for _, api in ipairs({
            false,
            function()
                return 0, 0, 20
            end,
        }) do
            H.withGlobals({ GetNetStats = api }, function()
                local writes = state.writes
                M.Interface.AutoDetectSpellQueueWindow()
                eq(state.writes, writes)
            end)
        end
        H.withGlobals({
            GetNetStats = function()
                return 0, 0, 20, 70
            end,
        }, function()
            state.locked = true
            M.Interface.AutoDetectSpellQueueWindow()
            eq(state.value, "400")
            state.locked = false
            state.rejected = true
            M.Interface.AutoDetectSpellQueueWindow()
            eq(state.value, "400")
            eq(MurgleDB.interface.spellQueueWindow, 400)
        end)
    end)
end)
