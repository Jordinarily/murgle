local passed, failed = 0, 0

function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        io.write("PASS ", name, "\n")
    else
        failed = failed + 1
        io.stderr:write("FAIL ", name, ": ", tostring(err), "\n")
    end
end

function eq(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local tests = {
    "tests/test_manifest.lua",
    "tests/test_startup.lua",
    "tests/test_defaults.lua",
    "tests/test_core.lua",
    "tests/test_locale.lua",
    "tests/test_settings.lua",
    "tests/test_interface.lua",
    "tests/test_spell_queue.lua",
    "tests/test_experience.lua",
    "tests/test_minimap.lua",
    "tests/test_frames.lua",
    "tests/test_buffs.lua",
    "tests/test_chat.lua",
    "tests/test_voice_buttons.lua",
    "tests/test_chat_tabs.lua",
    "tests/test_tooltip.lua",
    "tests/test_tracker_visibility.lua",
    "tests/test_tracker_fonts.lua",
    "tests/test_quest_sparkles.lua",
    "tests/test_reputation.lua",
    "tests/test_errors.lua",
    "tests/test_totems.lua",
    "tests/test_help_tips.lua",
    "tests/test_alerts.lua",
    "tests/test_automation.lua",
    "tests/test_loot_vendors.lua",
    "tests/test_fast_loot.lua",
    "tests/test_sound.lua",
    "tests/test_world_refresh.lua",
}

for _, path in ipairs(tests) do
    dofile(path)
end

io.write(string.format("%d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
