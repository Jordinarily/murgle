local H = dofile("tests/helpers.lua")
local function setup(fn)
    local frames, labels = {}, {}
    local count, id, combat = 1200, 10, false
    local button = {
        CreateFontString = function()
            local l = {
                SetPoint = function() end,
                SetText = function(self, t)
                    self.text = t
                end,
                Show = function(self)
                    self.shown = true
                end,
                Hide = function(self)
                    self.shown = false
                end,
            }
            labels[#labels + 1] = l
            return l
        end,
    }
    H.withGlobals({
        MurgleDB = { lootVendors = { ammoCount = false } },
        MainMenuBarBackpackButton = button,
        CreateFrame = function()
            local f = H.newEventFrame()
            frames[#frames + 1] = f
            return f
        end,
        UnitUsesAmmo = function()
            return true
        end,
        GetInventoryItemCount = function()
            return count
        end,
        C_Item = {
            GetItemCount = function()
                return count
            end,
        },
        InCombatLockdown = function()
            return combat
        end,
    }, function()
        local M = { L = { AMMO_COUNT_TEXT = "Ammo: %d" } }
        H.loadAddonFile("Modules/Ammo.lua", M)
        fn(M.Ammo, frames, labels, function(n, i)
            count, id = n, i
        end)
    end)
end

test("ammo is inert until enabled and unregisters on disable", function()
    setup(function(A, frames, labels)
        A.ApplyAll()
        eq(#frames, 0)
        eq(#labels, 0)
        MurgleDB.lootVendors.ammoCount = true
        A.ApplyAll()
        eq(labels[1].text, "Ammo: 1200")
        eq(frames[1]:IsEventRegistered("BAG_UPDATE_DELAYED"), true)
        MurgleDB.lootVendors.ammoCount = false
        A.ApplyAll()
        eq(labels[1].shown, false)
        eq(next(frames[1].events), nil)
    end)
end)
test("ammo refreshes known equipped ammunition and hides unknown or missing ammo", function()
    setup(function(A, frames, labels, state)
        MurgleDB.lootVendors.ammoCount = true
        A.ApplyAll()
        state(0, 10)
        frames[1].scripts.OnEvent(frames[1], "BAG_UPDATE_DELAYED")
        eq(labels[1].text, "Ammo: 0")
        state(nil, nil)
        frames[1].scripts.OnEvent(frames[1], "PLAYER_EQUIPMENT_CHANGED")
        eq(labels[1].shown, false)
        MurgleDB.lootVendors.ammoCount = false
        A.ApplyAll()
    end)
end)

test("ammo avoids events for unsupported characters and malformed counts", function()
    setup(function(A, frames, labels, state)
        MurgleDB.lootVendors.ammoCount = true
        UnitUsesAmmo = function()
            return false
        end
        A.ApplyAll()
        eq(#frames, 0)
        UnitUsesAmmo = function()
            return true
        end
        state(0 / 0, 10)
        A.ApplyAll()
        eq(#labels, 0)
    end)
end)
