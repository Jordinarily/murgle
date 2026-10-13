local H = dofile("tests/helpers.lua")
local UI = dofile("tests/ui_helpers.lua")

test("error speech mute preserves native preference across reload and reset", function()
    local value, writes = "1", 0
    H.withGlobals({
        GetCVar = function(name)
            eq(name, "Sound_EnableErrorSpeech")
            return value
        end,
        SetCVar = function(name, v)
            eq(name, "Sound_EnableErrorSpeech")
            value = v
            writes = writes + 1
        end,
    }, function()
        H.withGlobals({ MurgleDB = { sound = {} } }, function()
            local M = {}
            H.loadAddonFile("Modules/Sound.lua", M)
            M.Sound.ApplyAll()
            eq(writes, 0)
            MurgleDB.sound.muteErrorSpeech = true
            M.Sound.ApplyAll()
            eq(value, "0")
            eq(MurgleDB.sound.errorSpeechRestore, "1")
            M.Sound.ApplyAll()
            eq(writes, 1)
            H.loadAddonFile("Modules/Sound.lua", M)
            M.Sound.ApplyAll()
            MurgleDB = { sound = {} }
            M.Sound.ApplyAll()
            eq(value, "1")
        end)
    end)
end)

local function withSound(fn)
    local muted, unmuted = {}, {}
    H.withGlobals({
        MurgleDB = { sound = { muteFizzle = false } },
        MuteSoundFile = function(id)
            muted[#muted + 1] = id
        end,
        UnmuteSoundFile = function(id)
            unmuted[#unmuted + 1] = id
        end,
        CreateFrame = function()
            error("sound muting must not create frames")
        end,
    }, function()
        local M = {}
        H.loadAddonFile("Modules/Sound.lua", M)
        assert(type(M.Sound.ApplyAll) == "function", "sound apply entry point")
        fn(M.Sound, muted, unmuted)
    end)
end

test("sound disabled startup performs no mute or unmute calls", function()
    withSound(function(S, muted, unmuted)
        S.Initialize()
        S.ApplyAll()
        eq(#muted, 0)
        eq(#unmuted, 0)
    end)
end)

test("spell-fizzle mute uses only the five independently sourced IDs once", function()
    withSound(function(S, muted, unmuted)
        MurgleDB.sound.muteFizzle = true
        S.Initialize()
        S.ApplyAll()
        eq(table.concat(muted, ","), "569772,569773,569774,569775,569776")
        eq(#unmuted, 0)
        MurgleDB.sound.muteFizzle = false
        S.ApplyAll()
        S.ApplyAll()
        eq(table.concat(unmuted, ","), table.concat(muted, ","))
        MurgleDB.sound.muteFizzle = true
        S.ApplyAll()
        eq(#muted, 10)
    end)
end)

test("sound invalid saved values restore only previously applied mutes", function()
    withSound(function(S, muted, unmuted)
        MurgleDB.sound.muteFizzle = "true"
        S.ApplyAll()
        eq(#muted, 0)
        eq(#unmuted, 0)
        MurgleDB.sound.muteFizzle = true
        S.ApplyAll()
        MurgleDB.sound.muteFizzle = 1
        S.ApplyAll()
        eq(#unmuted, 5)
    end)
end)

test("sound requires reversible APIs and retries when they become available", function()
    withSound(function(S, muted, unmuted)
        local mute, unmute = MuteSoundFile, UnmuteSoundFile
        MurgleDB.sound.muteFizzle = true
        UnmuteSoundFile = nil
        S.ApplyAll()
        eq(#muted, 0)
        UnmuteSoundFile, MuteSoundFile = unmute, nil
        S.ApplyAll()
        eq(#muted, 0)
        MuteSoundFile = mute
        S.ApplyAll()
        eq(#muted, 5)
        MurgleDB.sound.muteFizzle = false
        UnmuteSoundFile = nil
        S.ApplyAll()
        eq(#unmuted, 0)
        UnmuteSoundFile = unmute
        S.ApplyAll()
        eq(#unmuted, 5)
    end)
end)

test("sound settings persist and reset unmutes without changing error filtering", function()
    H.withGlobals({
        MuteSoundFile = function() end,
        UnmuteSoundFile = function() end,
    }, function()
        UI.withAddon(function(M, state)
            local muted, unmuted = 0, 0
            MuteSoundFile = function()
                muted = muted + 1
            end
            UnmuteSoundFile = function()
                unmuted = unmuted + 1
            end
            M.Settings.Show()
            M.Settings.SelectCategory("ErrorsSound")
            eq(type(M.L.MUTE_FIZZLE), "string")
            local check
            for _, frame in ipairs(state.frames) do
                if frame.kind == "CheckButton" then
                    for _, region in ipairs(frame.regions) do
                        if region.text == M.L.MUTE_FIZZLE then
                            check = frame
                        end
                    end
                end
            end
            assert(check, "fizzle checkbox")
            check:SetChecked(true)
            check.scripts.OnClick(check)
            eq(MurgleDB.sound.muteFizzle, true)
            eq(muted, 5)
            eq(MurgleDB.errors.mode, "important")
            M.Settings.ConfirmReset()
            StaticPopupDialogs.MURGLE_RESET.OnAccept()
            eq(MurgleDB.sound.muteFizzle, false)
            eq(unmuted, 5)
            eq(check:GetChecked(), false)
        end)
    end)
end)

test("curated train and mechanostrider mutes own only their explicit nonoverlapping files", function()
    withSound(function(S, muted, unmuted)
        MurgleDB.sound.muteTrains = true
        S.ApplyAll()
        eq(#muted, 16)
        MurgleDB.sound.muteMechanicalSteps = true
        S.ApplyAll()
        eq(#muted, 20)
        S.ApplyAll()
        eq(#muted, 20)
        MurgleDB.sound.muteTrains = false
        S.ApplyAll()
        eq(#unmuted, 16)
        for _, id in ipairs(unmuted) do
            assert(id ~= 550500 and id ~= 550501 and id ~= 550507 and id ~= 550514)
        end
        MurgleDB = { sound = {} }
        S.ApplyAll()
        eq(#unmuted, 20)
        S.ApplyAll()
        eq(#unmuted, 20)
        for _, id in ipairs(muted) do
            assert(id ~= 550511 and id ~= 550504 and id ~= 550498, "creature wound sounds must stay audible")
        end
    end)
end)

test("expanded sound groups mute verified files once and restore only the selected group", function()
    withSound(function(S, muted, unmuted)
        local groups = {
            { "muteFootsteps", 662, 540092, 1337785 },
            { "muteHooves", 439, 540095, 1337805 },
            { "muteChimes", 5, 565853, 566564 },
            { "muteInterface", 4, 567407, 567490 },
            { "muteReadyCheck", 1, 567478, 567478 },
            { "muteCatYawns", 1, 562388, 562388 },
            { "mutePiccolo", 1, 568271, 568271 },
            { "muteMechanostriders", 9, 555123, 555132 },
            { "muteZeppelins", 5, 565623, 567190 },
        }
        local seen = {}
        for _, group in ipairs(groups) do
            local start = #muted
            MurgleDB.sound[group[1]] = true
            S.ApplyAll()
            eq(#muted - start, group[2], group[1])
            eq(muted[start + 1], group[3])
            eq(muted[#muted], group[4])
            for i = start + 1, #muted do
                assert(not seen[muted[i]], "groups must not release another enabled group's file")
                seen[muted[i]] = true
            end
            S.ApplyAll()
            eq(#muted - start, group[2])
            local restored = #unmuted
            MurgleDB.sound[group[1]] = false
            S.ApplyAll()
            eq(#unmuted - restored, group[2])
            for i = 1, group[2] do
                eq(unmuted[restored + i], muted[start + i])
            end
        end
    end)
end)

test("expanded sound bulk reset and API loss retain reversible ownership", function()
    withSound(function(S, muted, unmuted)
        local unmute = UnmuteSoundFile
        UnmuteSoundFile = nil
        S.SetAllMuted(true)
        eq(#muted, 0)
        UnmuteSoundFile = unmute
        S.ApplyAll()
        eq(#muted, 1152)
        eq(S.AreAllMuted(), true)
        MurgleDB.sound.muteHooves = false
        eq(S.AreAllMuted(), false)
        S.ApplyAll()
        eq(#unmuted, 439)
        MurgleDB = { sound = {} }
        S.ApplyAll()
        eq(#unmuted, 1152)
        S.ApplyAll()
        eq(#unmuted, 1152)
    end)
end)
