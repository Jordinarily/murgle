local UI = dofile("tests/ui_helpers.lua")

local function fixture(_, state)
    state.repairs, state.hooks = 0, 0
    state.cost, state.money, state.canRepair = 100, 100, true
    MerchantFrame = {
        HookScript = function(_, script, callback)
            eq(script, "OnShow")
            state.hooks = state.hooks + 1
            state.show = callback
        end,
        IsShown = function()
            return not state.hidden
        end,
    }
    CanMerchantRepair = function()
        return state.canRepair
    end
    GetRepairAllCost = function()
        return state.cost, state.canRepair
    end
    GetMoney = function()
        return state.money
    end
    IsShiftKeyDown = function()
        return state.shift == true
    end
    RepairAllItems = function(guild)
        eq(guild, nil, "personal repair must not request guild funds")
        state.repairs = state.repairs + 1
    end
end

local function enable(M)
    assert(M.LootVendors, "repair module must be loaded")
    MurgleDB.lootVendors.autoRepair = true
    M.LootVendors.ApplyAll()
end

test("personal repair is inert by default and installs one hook only when enabled", function()
    UI.withAddon(function(M, state)
        eq(state.hooks, 0)
        eq(#state.frames, 1)
        enable(M)
        enable(M)
        eq(state.hooks, 1)
        eq(state.repairs, 0, "enabling must not immediately spend gold")
        state.show(MerchantFrame)
        eq(state.repairs, 1)
        MurgleDB.lootVendors.autoRepair = false
        M.LootVendors.ApplyAll()
        state.show(MerchantFrame)
        eq(state.repairs, 1)
    end, fixture)
end)

test("personal repair refuses invalid costs funds and unavailable repair service", function()
    UI.withAddon(function(M, state)
        enable(M)
        for _, value in ipairs({ 0, -1, math.huge, 0 / 0, 1.5, "100", false }) do
            state.cost = value
            state.show(MerchantFrame)
        end
        state.cost = nil
        state.show(MerchantFrame)
        state.cost = 100
        for _, value in ipairs({ 99, -1, math.huge, 0 / 0, "100", false }) do
            state.money = value
            state.show(MerchantFrame)
        end
        state.money = nil
        state.show(MerchantFrame)
        state.money, state.canRepair = 100, false
        state.show(MerchantFrame)
        eq(state.repairs, 0)
        state.canRepair = true
        state.show(MerchantFrame)
        eq(state.repairs, 1)
    end, fixture)
end)

test("personal repair skips Shift combat hidden replacement and missing APIs without deferral", function()
    UI.withAddon(function(M, state)
        enable(M)
        for _, flag in ipairs({ "shift", "combat", "hidden" }) do
            state[flag] = true
            state.show(MerchantFrame)
            state[flag] = false
        end
        local original = MerchantFrame
        MerchantFrame = {}
        state.show(original)
        MerchantFrame = original
        GetRepairAllCost = nil
        state.show(MerchantFrame)
        eq(state.repairs, 0)
        eq(M.GetDeferredCount(), 0)
    end, fixture)
end)

test("saved repair enable never constructs settings or duplicates its hook", function()
    UI.withAddon(function(M, state)
        eq(state.hooks, 1)
        eq(#state.frames, 1)
        local frame = MerchantFrame
        MerchantFrame = nil
        M.LootVendors.ApplyAll()
        MerchantFrame = frame
        M.LootVendors.ApplyAll()
        eq(state.hooks, 1)
        state.show(frame)
        eq(state.repairs, 1)
    end, function(M, state)
        fixture(M, state)
        MurgleDB = { lootVendors = { autoRepair = true } }
    end)
end)

test("repair installs on explicit retry after an initially missing merchant frame", function()
    UI.withAddon(function(M, state)
        local frame = MerchantFrame
        MerchantFrame = nil
        enable(M)
        eq(state.hooks, 0)
        MerchantFrame = frame
        M.LootVendors.ApplyAll()
        eq(state.hooks, 1)
        state.show(frame)
        eq(state.repairs, 1)
    end, fixture)
end)

test("repair refuses unknown service and repairability results independently", function()
    UI.withAddon(function(M, state)
        enable(M)
        CanMerchantRepair = function() end
        state.show(MerchantFrame)
        CanMerchantRepair = function()
            return true
        end
        GetRepairAllCost = function()
            return 100
        end
        state.show(MerchantFrame)
        eq(state.repairs, 0)
    end, fixture)
end)

test("personal repair checkbox persists and reset disables the installed hook", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        M.Settings.SelectCategory("LootVendors")
        eq(type(M.L.AUTO_REPAIR), "string")
        local control
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                if region.text == M.L.AUTO_REPAIR then
                    control = frame
                end
            end
        end
        assert(control, "personal repair checkbox must exist")
        control:SetChecked(true)
        control.scripts.OnClick(control)
        eq(MurgleDB.lootVendors.autoRepair, true)
        state.show(MerchantFrame)
        eq(state.repairs, 1)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(control:GetChecked(), false)
        state.show(MerchantFrame)
        eq(state.repairs, 1)
    end, fixture)
end)

local function guildFixture(M, state)
    fixture(M, state)
    state.allowed, state.limit, state.bank = true, 100, 100
    state.guildCalls, state.personalCalls = 0, 0
    CanGuildBankRepair = function()
        return state.allowed
    end
    GetGuildBankWithdrawMoney = function()
        return state.limit
    end
    GetGuildBankMoney = function()
        return state.bank
    end
    RepairAllItems = function(guild)
        if guild == true then
            state.guildCalls = state.guildCalls + 1
        else
            eq(guild, nil)
            state.personalCalls = state.personalCalls + 1
        end
    end
end

local function preferGuild(M)
    MurgleDB.lootVendors.guildRepair = true
    enable(M)
end

test("guild repair preference uses full and mixed native funding with one request", function()
    UI.withAddon(function(M, state)
        preferGuild(M)
        state.money = 0
        state.show(MerchantFrame)
        eq(state.guildCalls, 1)
        state.limit, state.money = 40, 60
        state.show(MerchantFrame)
        eq(state.guildCalls, 2)
        state.money = 59
        state.show(MerchantFrame)
        eq(state.guildCalls, 2, "combined funds must cover the whole cost")
        state.limit, state.bank, state.money = -1, 100, 0
        state.show(MerchantFrame)
        eq(state.guildCalls, 3, "unlimited allowance is capped by bank funds")
        state.bank = 99
        state.show(MerchantFrame)
        eq(state.guildCalls, 3)
        state.limit, state.bank, state.money = 100, 40, 60
        state.show(MerchantFrame)
        eq(state.guildCalls, 4, "finite allowance cannot exceed the bank balance")
        state.money = 59
        state.show(MerchantFrame)
        eq(state.guildCalls, 4)
        eq(state.personalCalls, 0, "never issue an immediate second repair attempt")
    end, guildFixture)
end)

test("guild denial or zero funds falls back to affordable personal repair", function()
    UI.withAddon(function(M, state)
        preferGuild(M)
        state.allowed = false
        state.show(MerchantFrame)
        eq(state.personalCalls, 1)
        state.allowed, state.limit = true, 0
        state.show(MerchantFrame)
        eq(state.personalCalls, 2)
        state.limit, state.bank = 100, 0
        state.show(MerchantFrame)
        eq(state.personalCalls, 3)
        state.money = 99
        state.show(MerchantFrame)
        eq(state.personalCalls, 3)
        eq(state.guildCalls, 0)
    end, guildFixture)
end)

test("unknown guild permission balances and allowances fail closed", function()
    UI.withAddon(function(M, state)
        preferGuild(M)
        state.allowed = nil
        state.show(MerchantFrame)
        state.allowed = true
        for _, value in ipairs({ -2, 1.5, math.huge, 0 / 0, "100", false }) do
            state.limit = value
            state.show(MerchantFrame)
        end
        state.limit = nil
        state.show(MerchantFrame)
        state.limit = 100
        for _, value in ipairs({ -1, 1.5, math.huge, 0 / 0, "100", false }) do
            state.bank = value
            state.show(MerchantFrame)
        end
        state.bank = nil
        state.show(MerchantFrame)
        state.bank = 100
        GetGuildBankWithdrawMoney = nil
        state.show(MerchantFrame)
        eq(state.personalCalls + state.guildCalls, 0)
    end, guildFixture)
end)

test("guild preference alone stays inert and disabling it restores personal behavior", function()
    UI.withAddon(function(M, state)
        MurgleDB.lootVendors.guildRepair = true
        M.LootVendors.ApplyAll()
        eq(state.hooks, 0)
        enable(M)
        for _, flag in ipairs({ "shift", "combat" }) do
            state[flag] = true
            state.show(MerchantFrame)
            state[flag] = false
        end
        eq(state.guildCalls, 0)
        MurgleDB.lootVendors.guildRepair = false
        GetGuildBankMoney = nil
        state.show(MerchantFrame)
        eq(state.personalCalls, 1)
    end, guildFixture)
end)

test("guild repair preference persists through its checkbox and reset", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        M.Settings.SelectCategory("LootVendors")
        local control, repair
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                if region.text == M.L.GUILD_REPAIR then
                    control = frame
                elseif region.text == M.L.AUTO_REPAIR then
                    repair = frame
                end
            end
        end
        assert(control, "guild preference checkbox required")
        assert(repair)
        eq(control:IsShown(), false)
        eq(state.hooks, 0)
        repair:SetChecked(true)
        repair.scripts.OnClick(repair)
        eq(control:IsShown(), true)
        control:SetChecked(true)
        control.scripts.OnClick(control)
        eq(MurgleDB.lootVendors.guildRepair, true)
        repair:SetChecked(false)
        repair.scripts.OnClick(repair)
        eq(control:IsShown(), false)
        eq(MurgleDB.lootVendors.guildRepair, true)
        repair:SetChecked(true)
        repair.scripts.OnClick(repair)
        eq(control:IsShown(), true)
        state.show(MerchantFrame)
        eq(state.guildCalls, 1)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(control:GetChecked(), false)
        eq(control:IsShown(), false)
        state.show(MerchantFrame)
        eq(state.guildCalls, 1)
    end, guildFixture)
end)

local function junkFixture(M, state)
    fixture(M, state)
    state.sales, state.junkCount, state.junkEnabled = 0, 2, true
    NUM_BAG_SLOTS = 0
    Enum = { ItemQuality = { Poor = 0 } }
    C_Container = {
        GetContainerNumSlots = function()
            return state.junkCount
        end,
        GetContainerItemInfo = function(_, slot)
            if slot ~= 1 then
                return nil
            end
            return {
                itemID = 123,
                quality = state.quality or 0,
                isLocked = state.junkDisabled == true,
                hasNoValue = state.junkHidden == true,
                stackCount = 1,
            }
        end,
        UseContainerItem = function()
            state.sales = state.sales + 1
        end,
    }
    C_MerchantFrame = {
        SellAllJunkItems = function()
            error("bulk eligibility must not be assumed")
        end,
    }
end

local function enableJunk(M)
    MurgleDB.lootVendors.sellJunk = true
    M.LootVendors.ApplyAll()
end

test("junk sale visits only eligible grey slots and stops on synchronous merchant close", function()
    UI.withAddon(function(M, state)
        enableJunk(M)
        state.junkCount = 5
        local items = {
            { itemID = 1, quality = 0, isLocked = false, hasNoValue = false, stackCount = 1 },
            { itemID = 2, quality = 1, isLocked = false, hasNoValue = false, stackCount = 1 },
            { itemID = 3, quality = 0, isLocked = true, hasNoValue = false, stackCount = 1 },
            { itemID = 4, isLocked = false, hasNoValue = false, stackCount = 1 },
            { itemID = 5, quality = 0, isLocked = false, hasNoValue = false, stackCount = 2 },
        }
        C_Container.GetContainerItemInfo = function(_, slot)
            return items[slot]
        end
        local sold = {}
        C_Container.UseContainerItem = function(_, slot)
            sold[#sold + 1] = slot
            state.show(MerchantFrame)
        end
        state.show(MerchantFrame)
        eq(table.concat(sold, ","), "5,1")
        sold = {}
        C_Container.UseContainerItem = function(_, slot)
            sold[#sold + 1] = slot
            state.hidden = true
        end
        state.show(MerchantFrame)
        eq(table.concat(sold, ","), "5")
    end, junkFixture)
end)

test("sell junk alone hooks once and sells only on the next merchant opening", function()
    UI.withAddon(function(M, state)
        eq(state.hooks, 0)
        enableJunk(M)
        enableJunk(M)
        eq(state.hooks, 1)
        eq(state.sales, 0)
        state.canRepair = false
        state.show(MerchantFrame)
        eq(state.sales, 1)
        eq(state.repairs, 0)
        MurgleDB.lootVendors.sellJunk = false
        state.show(MerchantFrame)
        eq(state.sales, 1)
    end, junkFixture)
end)

test("junk sale skips invalid slots locked valueless items Shift combat and missing APIs", function()
    UI.withAddon(function(M, state)
        enableJunk(M)
        for _, flag in ipairs({ "shift", "combat", "hidden", "junkHidden", "junkDisabled" }) do
            state[flag] = true
            state.show(MerchantFrame)
            state[flag] = false
        end
        for _, count in ipairs({ 0, -1, 1.5, math.huge, 0 / 0, "2", false }) do
            state.junkCount = count
            state.show(MerchantFrame)
        end
        state.junkCount = nil
        state.show(MerchantFrame)
        state.junkCount, state.quality = 2, 1
        state.show(MerchantFrame)
        state.quality = 0
        C_Container.UseContainerItem = nil
        state.show(MerchantFrame)
        eq(state.sales, 0)
        eq(M.GetDeferredCount(), 0)
    end, junkFixture)
end)

test("repair and junk sale share a hook and unavailable sale does not block repairs", function()
    UI.withAddon(function(M, state)
        enable(M)
        enableJunk(M)
        eq(state.hooks, 1)
        C_Container.UseContainerItem = function()
            eq(state.repairs, 1, "repair precedes sale without assuming immediate sale income")
            state.sales = state.sales + 1
        end
        state.show(MerchantFrame)
        eq(state.sales, 1)
        C_Container = nil
        state.show(MerchantFrame)
        eq(state.repairs, 2)
        eq(state.sales, 1)
    end, junkFixture)
end)

test("saved junk option initializes and checkbox reset leaves sale manual", function()
    UI.withAddon(function(M, state)
        eq(state.hooks, 1)
        eq(#state.frames, 1)
        M.Settings.Show()
        M.Settings.SelectCategory("LootVendors")
        local control
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                if region.text == M.L.SELL_JUNK then
                    control = frame
                end
            end
        end
        assert(control, "sell junk checkbox required")
        eq(control:GetChecked(), true)
        state.show(MerchantFrame)
        eq(state.sales, 1)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(control:GetChecked(), false)
        state.show(MerchantFrame)
        eq(state.sales, 1)
    end, function(M, state)
        junkFixture(M, state)
        MurgleDB = { lootVendors = { sellJunk = true } }
    end)
end)

test("junk sale rechecks merchant context after repair changes it", function()
    UI.withAddon(function(M, state)
        enable(M)
        enableJunk(M)
        local frame = MerchantFrame
        for _, flag in ipairs({ "hidden", "combat", "shift" }) do
            RepairAllItems = function()
                state[flag] = true
            end
            state.show(frame)
            eq(state.sales, 0)
            state[flag] = false
        end
        RepairAllItems = function()
            MerchantFrame = {}
        end
        state.show(frame)
        eq(state.sales, 0)
    end, junkFixture)
end)
