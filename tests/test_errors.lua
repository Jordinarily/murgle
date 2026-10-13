local H = dofile("tests/helpers.lua")
local UI = dofile("tests/ui_helpers.lua")

local function fixture(_, state)
    local frame = H.newEventFrame()
    frame.protected = false
    function frame:IsProtected()
        return self.protected
    end
    frame:RegisterEvent("UI_ERROR_MESSAGE")
    frame:RegisterEvent("UI_INFO_MESSAGE")
    frame:RegisterEvent("SYSMSG")
    function frame:SetMessageTypeEnabled(id, enabled)
        BLACK_LISTED_MESSAGE_TYPES[id] = not enabled
        state.filterWrites = (state.filterWrites or 0) + 1
    end
    UIErrorsFrame = frame
    LE_GAME_ERR_SPELL_OUT_OF_RANGE = 101
    LE_GAME_ERR_OUT_OF_MANA = 102
    LE_GAME_ERR_ITEM_COOLDOWN = 103
    BLACK_LISTED_MESSAGE_TYPES = { [102] = false, [103] = true, [999] = true }
end

test("important error filtering changes only explicit IDs and all restores exact native entries", function()
    UI.withAddon(function(M, state)
        eq(MurgleDB.errors.mode, "important")
        eq(BLACK_LISTED_MESSAGE_TYPES[101], true)
        eq(BLACK_LISTED_MESSAGE_TYPES[102], true)
        eq(BLACK_LISTED_MESSAGE_TYPES[103], true)
        eq(BLACK_LISTED_MESSAGE_TYPES[999], true)
        eq(BLACK_LISTED_MESSAGE_TYPES[555], nil, "unknown messages retain native eligibility")
        local writes = state.filterWrites
        M.Errors.ApplyAll()
        eq(state.filterWrites, writes)
        M.Errors.SetMode("all")
        eq(BLACK_LISTED_MESSAGE_TYPES[101], nil)
        eq(BLACK_LISTED_MESSAGE_TYPES[102], false)
        eq(BLACK_LISTED_MESSAGE_TYPES[103], true)
        eq(BLACK_LISTED_MESSAGE_TYPES[999], true)
        eq(#state.frames, 1)
        eq(next(state.frames[1].events), nil)
    end, fixture)
end)

test("error modes preserve external changes and originally absent event registrations", function()
    UI.withAddon(function(M)
        BLACK_LISTED_MESSAGE_TYPES[101] = false
        M.Errors.SetMode("all")
        eq(BLACK_LISTED_MESSAGE_TYPES[101], false, "leave another caller's changed filter alone")
        UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
        M.Errors.SetMode("hidden")
        M.Errors.SetMode("all")
        eq(UIErrorsFrame:IsEventRegistered("UI_ERROR_MESSAGE"), false)
        M.Errors.SetMode("important")
        M.Errors.SetMode("invalid")
        eq(BLACK_LISTED_MESSAGE_TYPES[101], false)
    end, fixture)
end)

test("missing and protected error integrations fail independently and can retry", function()
    UI.withAddon(function(M)
        M.Errors.SetMode("all")
        local frame = UIErrorsFrame
        frame.protected = true
        M.Errors.SetMode("hidden")
        eq(frame:IsEventRegistered("UI_ERROR_MESSAGE"), true)
        frame.protected = false
        BLACK_LISTED_MESSAGE_TYPES = nil
        M.Errors.SetMode("important")
        eq(frame:IsEventRegistered("UI_ERROR_MESSAGE"), true)
        M.Errors.SetMode("hidden")
        eq(frame:IsEventRegistered("UI_ERROR_MESSAGE"), true, "retired mode leaves native events alone")
        M.Errors.SetMode("all")
        UIErrorsFrame = nil
        M.Errors.SetMode("important")
    end, fixture)
end)

test("error filtering restores captured blacklist after global replacement", function()
    UI.withAddon(function(M)
        local original = BLACK_LISTED_MESSAGE_TYPES
        BLACK_LISTED_MESSAGE_TYPES = {}
        M.Errors.SetMode("all")
        eq(original[101], nil)
        eq(original[102], false)
        eq(next(BLACK_LISTED_MESSAGE_TYPES), nil)
    end, fixture)
end)

test("error settings persist modes and reset returns to important without startup UI", function()
    UI.withAddon(function(M, state)
        eq(#state.frames, 1)
        M.Settings.Show()
        local start = #state.frames
        M.Settings.SelectCategory("ErrorsSound")
        local all, hidden, important
        for index, frame in ipairs(state.frames) do
            if index > start and frame.kind == "Button" then
                for _, region in ipairs(frame.regions) do
                    if region.text == M.L.ALL then
                        all = frame
                    end
                    if region.text == M.L.HIDDEN then
                        hidden = frame
                    end
                    if region.text == M.L.IMPORTANT then
                        important = frame
                    end
                end
            end
        end
        assert(all and important and not hidden)
        M.Errors.SetMode("hidden")
        eq(MurgleDB.errors.mode, "all")
        eq(UIErrorsFrame:IsEventRegistered("UI_ERROR_MESSAGE"), true)
        all.scripts.OnClick(all)
        eq(MurgleDB.errors.mode, "all")
        eq(UIErrorsFrame:IsEventRegistered("UI_ERROR_MESSAGE"), true)
        M.ResetDB()
        eq(MurgleDB.errors.mode, "important")
        eq(BLACK_LISTED_MESSAGE_TYPES[101], true)
    end, fixture)
end)

test("missing error constants do not suppress unknown IDs or block other known filters", function()
    UI.withAddon(function(M)
        eq(BLACK_LISTED_MESSAGE_TYPES[101], nil)
        eq(BLACK_LISTED_MESSAGE_TYPES[102], true)
        eq(BLACK_LISTED_MESSAGE_TYPES[103], true)
        M.Errors.SetMode("all")
        eq(BLACK_LISTED_MESSAGE_TYPES[102], false)
        eq(BLACK_LISTED_MESSAGE_TYPES[103], true)
    end, function(M, state)
        fixture(M, state)
        LE_GAME_ERR_SPELL_OUT_OF_RANGE = nil
    end)
end)

test("saved all error mode leaves existing filters and registrations untouched", function()
    UI.withAddon(function(_, state)
        eq(state.filterWrites, nil)
        eq(BLACK_LISTED_MESSAGE_TYPES[101], nil)
        eq(UIErrorsFrame:IsEventRegistered("UI_ERROR_MESSAGE"), true)
        eq(#state.frames, 1)
    end, function(M, state)
        fixture(M, state)
        MurgleDB = { errors = { mode = "all" } }
    end)
end)
