local H = dofile("tests/helpers.lua")
test("retired item automation and vendor features ignore legacy enabled flags", function()
    local M = {}
    H.loadAddonFile("Defaults.lua", M)
    local db = M.ApplyDefaults({
        automation = { useQuestStarters = true },
        lootVendors = { openClams = true, markedJunk = true, restock = true },
        tooltip = { spellDetails = true },
    })
    eq(db.automation.useQuestStarters, nil)
    eq(db.lootVendors.openClams, nil)
    eq(db.lootVendors.markedJunk, nil)
    eq(db.lootVendors.restock, nil)
    eq(db.tooltip.spellDetails, nil)
    local f = assert(io.open("Murgle.toc"))
    local toc = f:read("*a")
    f:close()
    assert(not toc:find("Modules/ItemOpening.lua", 1, true))
end)
