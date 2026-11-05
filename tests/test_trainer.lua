local Helpers = dofile("tests/helpers.lua")

local function fixture(fn)
    local state = { money = 100, services = { { "A", 10 }, { "B", 20 } }, bought = {} }
    local frames, addon = {}, { L = { TRAIN_ALL = "Train All" } }
    local function frame()
        local f = Helpers.newEventFrame()
        f.shown = true
        function f:IsShown()
            return self.shown
        end
        function f:Show()
            self.shown = true
        end
        function f:Hide()
            self.shown = false
        end
        function f:SetSize() end
        function f:SetPoint() end
        function f:SetText() end
        function f:SetEnabled(value)
            self.enabled = value
        end
        frames[#frames + 1] = f
        return f
    end
    Helpers.withGlobals({
        MurgleDB = { automation = { trainAll = true } },
        CreateFrame = frame,
        ClassTrainerFrame = frame(),
        ClassTrainerTrainButton = frame(),
        C_Trainer = {
            GetTrainerType = function()
                return state.kind or 0
            end,
        },
        Enum = { TrainerType = { General = 0, Pet = 3, Tradeskills = 2 } },
        IsTradeskillTrainer = function()
            return state.profession == true
        end,
        InCombatLockdown = function()
            return state.combat == true
        end,
        IsShiftKeyDown = function()
            return state.shift == true
        end,
        GetMoney = function()
            return state.money
        end,
        GetNumTrainerServices = function()
            return #state.services
        end,
        GetTrainerServiceInfo = function(i)
            return state.services[i][1], "available", nil, nil, "Rank 1"
        end,
        GetTrainerServiceCost = function(i)
            return state.services[i][2], state.professionCost
        end,
        BuyTrainerService = function(i)
            local service = table.remove(state.services, i)
            state.bought[#state.bought + 1] = service[1]
            state.money = state.money - service[2]
            if state.reentrant then
                state.fire("TRAINER_UPDATE")
            end
        end,
    }, function()
        Helpers.loadAddonFile("Modules/Trainer.lua", addon)
        addon.Trainer.Initialize()
        function state.fire(event)
            for _, f in ipairs(frames) do
                if f.events[event] and f.scripts.OnEvent then
                    f.scripts.OnEvent(f, event)
                end
            end
        end
        function state.click()
            for _, f in ipairs(frames) do
                if f.scripts.OnClick then
                    f.scripts.OnClick(f, "LeftButton")
                end
            end
        end
        fn(state, addon, frames)
    end)
end

test("trainer spends only on click and follows confirmed shifted indices", function()
    fixture(function(s)
        s.fire("TRAINER_SHOW")
        eq(#s.bought, 0)
        s.click()
        eq(#s.bought, 1)
        s.fire("TRAINER_UPDATE")
        eq(#s.bought, 2)
        eq(s.bought[2], "B")
    end)
end)

for _, guard in ipairs({ "combat", "shift", "profession", "professionCost" }) do
    test("trainer refuses " .. guard, function()
        fixture(function(s)
            s[guard] = true
            s.click()
            eq(#s.bought, 0)
        end)
    end)
end

test("trainer refuses pet and unknown trainer types", function()
    fixture(function(s)
        s.kind = 3
        s.click()
        eq(#s.bought, 0)
        s.kind = 999
        s.click()
        eq(#s.bought, 0)
    end)
end)

for _, reason in ipairs({ "money", "changed", "closed", "disabled", "combat", "shift" }) do
    test("trainer cancels pending purchase on " .. reason, function()
        fixture(function(s, addon)
            s.click()
            eq(#s.bought, 1)
            if reason == "money" then
                s.money = 0
            elseif reason == "changed" then
                s.services[1][1] = "Unexpected"
            elseif reason == "closed" then
                s.fire("TRAINER_CLOSED")
            elseif reason == "disabled" then
                MurgleDB.automation.trainAll = false
                addon.Trainer.ApplyAll()
            else
                s[reason] = true
            end
            s.fire("TRAINER_UPDATE")
            eq(#s.bought, 1)
        end)
    end)
end

test("trainer fails closed on synchronous purchase event reentrancy", function()
    fixture(function(s)
        s.reentrant = true
        s.click()
        eq(#s.bought, 1)
        s.fire("TRAINER_UPDATE")
        eq(#s.bought, 1)
    end)
end)

test("trainer disabled startup creates no frames or events", function()
    local addon, created = {}, 0
    Helpers.withGlobals({
        MurgleDB = { automation = { trainAll = false } },
        CreateFrame = function()
            created = created + 1
        end,
    }, function()
        Helpers.loadAddonFile("Modules/Trainer.lua", addon)
        addon.Trainer.Initialize()
        eq(created, 0)
    end)
end)

test("trainer stops when purchase receives no confirming change", function()
    fixture(function(s)
        Helpers.withGlobals({ BuyTrainerService = function() end }, function()
            s.click()
            s.fire("TRAINER_UPDATE")
        end)
        s.fire("TRAINER_UPDATE")
        eq(#s.bought, 0)
    end)
end)

test("trainer validates money and ambiguous service identity", function()
    fixture(function(s)
        s.money = 0 / 0
        s.click()
        eq(#s.bought, 0)
        s.money = 100
        s.services[2][1] = "A"
        s.click()
        eq(#s.bought, 0)
    end)
end)

test("trainer skips missing native cost API", function()
    fixture(function(s)
        local saved = GetTrainerServiceCost
        GetTrainerServiceCost = nil
        s.click()
        GetTrainerServiceCost = saved
        eq(#s.bought, 0)
    end)
end)
