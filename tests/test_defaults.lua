local H = dofile("tests/helpers.lua")
local M = {}
H.loadAddonFile("Defaults.lua", M)

test("defaults fill missing keys without overwriting choices", function()
    local db = { interface = { hideTalkingHead = false }, tooltip = { xOffset = 0 } }
    eq(M.ApplyDefaults(db), db)
    eq(db.interface.hideTalkingHead, false)
    eq(db.interface.hideBossBanner, true)
    eq(db.tooltip.xOffset, 0)
    eq(db.errors.mode, "important")
    eq(db.schemaVersion, 1)
end)

test("defaults repair corrupt category values", function()
    local db = { interface = "broken", errors = false, tooltip = 12 }
    M.ApplyDefaults(db)
    eq(type(db.interface), "table")
    eq(type(db.errors), "table")
    eq(db.errors.mode, "important")
    eq(db.tooltip.anchor, "right")
end)

test("defaults reconstruct invalid roots", function()
    for _, root in ipairs({ false, "broken", 17 }) do
        local db = M.ApplyDefaults(root)
        eq(db.schemaVersion, 1)
        eq(db.automation.autoQuest, false)
    end
    eq(M.ApplyDefaults(nil).automation.autoWorldRefresh, true)
end)

test("defaults do not share mutable state across saved variable tables", function()
    local first, second = M.ApplyDefaults({}), M.ApplyDefaults({})
    first.interface.hideTalkingHead = false
    first.sound.example = true
    eq(second.interface.hideTalkingHead, true)
    eq(second.sound.example, nil)
    eq(M.DEFAULTS.interface.hideTalkingHead, true)
    eq(M.DEFAULTS.sound.example, nil)
end)

test("defaults preserve existing scalar choices and unknown data across loads", function()
    local db = { schemaVersion = 2, errors = { mode = "all" }, future = { keep = true } }
    M.ApplyDefaults(db)
    M.ApplyDefaults(db)
    eq(db.schemaVersion, 2)
    eq(db.errors.mode, "all")
    eq(db.future.keep, true)
end)

test("World Refresh defaults to hide-only and preserves explicit choices", function()
    local fresh = M.ApplyDefaults({})
    eq(fresh.automation.worldRefreshMode, "hideOnly")
    local existing = M.ApplyDefaults({ automation = { autoWorldRefresh = false, worldRefreshMode = "hideOnly" } })
    eq(existing.automation.autoWorldRefresh, false)
    eq(existing.automation.worldRefreshMode, "hideOnly")
    local legacy = M.ApplyDefaults({ automation = { autoWorldRefresh = false } })
    eq(legacy.automation.autoWorldRefresh, false)
    eq(legacy.automation.worldRefreshMode, "hideOnly")
end)

test("retired hidden errors migrate to all and reporter has no default", function()
    local db = M.ApplyDefaults({ errors = { mode = "hidden" }, interface = { hideZoneBug = true } })
    eq(db.errors.mode, "all")
    eq(M.DEFAULTS.interface.hideZoneBug, nil)
    eq(db.interface.hideZoneBug, true, "unknown legacy value is harmlessly retained")
end)
