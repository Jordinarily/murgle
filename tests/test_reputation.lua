local H = dofile("tests/helpers.lua")
local UI = dofile("tests/ui_helpers.lua")

local function withReputation(fn, enabled)
    local state = { reads = 0, watched = {}, collapsed = true }
    local rows = {
        { name = "Alliance", factionID = 0, isHeader = true, isCollapsed = true },
        { name = "Stormwind", factionID = 72, isHeader = false },
        { name = "Ironforge", factionID = 47, isHeader = false },
    }
    H.withGlobals({
        FACTION_STANDING_INCREASED = "Reputation with %s increased by %d.",
        FACTION_STANDING_INCREASED_GENERIC = "Reputation with %s increased.",
        C_Reputation = {
            GetNumFactions = function()
                return state.collapsed and 1 or #rows
            end,
            GetFactionDataByIndex = function(i)
                state.reads = state.reads + 1
                rows[1].isCollapsed = state.collapsed
                return rows[i]
            end,
            ExpandFactionHeader = function(i)
                eq(i, 1)
                state.collapsed = false
            end,
            CollapseFactionHeader = function(i)
                eq(i, 1)
                state.collapsed = true
            end,
            SetWatchedFactionByID = function(id)
                state.watched[#state.watched + 1] = id
            end,
        },
    }, function()
        UI.withAddon(function(M, ui)
            local function fire(message)
                for _, frame in ipairs(ui.frames) do
                    if frame.events.CHAT_MSG_COMBAT_FACTION_CHANGE then
                        frame.scripts.OnEvent(frame, "CHAT_MSG_COMBAT_FACTION_CHANGE", message)
                    end
                end
            end
            fn(M, state, fire, rows, ui)
        end, function()
            MurgleDB = { quests = { autoWatchReputation = enabled } }
        end)
    end)
end

test("reputation watches gains under collapsed headers and restores the list", function()
    withReputation(function(_, state, fire)
        eq(state.reads, 0, "no startup scan")
        fire("Reputation with Stormwind increased by 25.")
        eq(state.watched[1], 72)
        eq(state.collapsed, true)
        fire("Reputation with Ironforge increased.")
        eq(state.watched[2], 47)
    end, true)
end)

test("reputation ignores losses zero malformed and unknown gain messages", function()
    withReputation(function(_, state, fire)
        fire("Reputation with Stormwind decreased by 25.")
        fire("Reputation with Stormwind increased by 0.")
        fire("Reputation with Stormwind increased by -25.")
        fire(nil)
        eq(state.reads, 0)
        fire("Reputation with Unknown increased by 1.")
        eq(#state.watched, 0)
        eq(state.collapsed, true)
    end, true)
end)

test("reputation disabled startup and disable all are inert and reset unregisters", function()
    withReputation(function(M, state, fire)
        eq(MurgleDB.quests.autoWatchReputation, false)
        fire("Reputation with Stormwind increased by 1.")
        eq(state.reads, 0)
        MurgleDB.quests.autoWatchReputation = true
        M.Quests.ApplyAll()
        fire("Reputation with Stormwind increased by 1.")
        eq(#state.watched, 1)
        MurgleDB.quests.autoWatchReputation = false
        M.Quests.ApplyAll()
        local reads = state.reads
        fire("Reputation with Stormwind increased by 1.")
        eq(state.reads, reads)
        MurgleDB.quests.autoWatchReputation = true
        M.Quests.ApplyAll()
        M.ResetDB()
        fire("Reputation with Stormwind increased by 1.")
        eq(state.reads, reads)
    end)
end)

test("reputation localized positional templates escape punctuation and faction names", function()
    withReputation(function(M, state, fire, rows)
        FACTION_STANDING_INCREASED = "%2$d points : %1$s (gain)."
        rows[2].name = "A.B+%"
        MurgleDB.quests.autoWatchReputation = true
        M.Quests.ApplyAll()
        fire("15 points : A.B+% (gain).")
        eq(state.watched[1], 72)
    end)
end)

test("reputation ambiguous names missing APIs and combat fail closed", function()
    withReputation(function(M, state, fire, rows)
        rows[3].name = "Stormwind"
        fire("Reputation with Stormwind increased by 1.")
        eq(#state.watched, 0)
        rows[3].name = "Ironforge"
        H.withGlobals({
            InCombatLockdown = function()
                return true
            end,
        }, function()
            local reads = state.reads
            fire("Reputation with Stormwind increased by 1.")
            eq(state.reads, reads)
        end)
        C_Reputation.ExpandFactionHeader = nil
        M.Quests.ApplyAll()
        fire("Reputation with Stormwind increased by 1.")
        eq(#state.watched, 0)
    end, true)
end)

test("reputation restores nested headers after a lookup failure and can retry", function()
    withReputation(function(_, state, fire, rows)
        local outer, inner = true, true
        C_Reputation.GetNumFactions = function()
            return outer and 1 or (inner and 2 or 3)
        end
        C_Reputation.GetFactionDataByIndex = function(i)
            if i == 1 then
                return { name = "Outer", factionID = 0, isHeader = true, isCollapsed = outer }
            end
            if i == 2 then
                return { name = "Inner", factionID = 0, isHeader = true, isCollapsed = inner }
            end
            if state.fail then
                error("native lookup failed")
            end
            return rows[2]
        end
        C_Reputation.ExpandFactionHeader = function(i)
            if i == 1 then
                outer = false
            else
                inner = false
            end
        end
        C_Reputation.CollapseFactionHeader = function(i)
            if i == 1 then
                assert(inner, "inner must restore first")
                outer = true
            else
                inner = true
            end
        end
        state.fail = true
        fire("Reputation with Stormwind increased by 1.")
        eq(outer, true)
        eq(inner, true)
        eq(#state.watched, 0)
        state.fail = false
        fire("Reputation with Stormwind increased by 1.")
        eq(state.watched[1], 72)
        eq(outer, true)
        eq(inner, true)
    end, true)
end)

test("reputation setter failures do not permanently disable future gains", function()
    withReputation(function(_, state, fire)
        local setter = C_Reputation.SetWatchedFactionByID
        C_Reputation.SetWatchedFactionByID = function()
            error("native unavailable")
        end
        pcall(fire, "Reputation with Stormwind increased by 1.")
        C_Reputation.SetWatchedFactionByID = setter
        fire("Reputation with Stormwind increased by 1.")
        eq(state.watched[1], 72)
        eq(state.collapsed, true)
    end, true)
end)

test("reputation skips already watched faction and suppresses synchronous reentry", function()
    withReputation(function(_, state, fire, rows)
        rows[2].isWatched = true
        fire("Reputation with Stormwind increased by 1.")
        eq(#state.watched, 0)
        rows[2].isWatched = false
        local setter = C_Reputation.SetWatchedFactionByID
        C_Reputation.SetWatchedFactionByID = function(id)
            setter(id)
            fire("Reputation with Ironforge increased by 1.")
        end
        fire("Reputation with Stormwind increased by 1.")
        eq(#state.watched, 1)
        eq(state.watched[1], 72)
    end, true)
end)

test("reputation menu applies immediately and unavailable APIs disable its control", function()
    withReputation(function(M, state, fire, _, ui)
        M.Settings.Show()
        M.Settings.SelectCategory("Quests")
        local control
        for _, frame in ipairs(ui.frames) do
            for _, region in ipairs(frame.regions) do
                if frame.kind == "CheckButton" and region.text == M.L.AUTO_WATCH_REPUTATION then
                    control = frame
                end
            end
        end
        assert(control, "auto-watch checkbox")
        control:SetChecked(true)
        control.scripts.OnClick(control)
        fire("Reputation with Stormwind increased by 1.")
        eq(state.watched[1], 72)
        C_Reputation.SetWatchedFactionByID = nil
        M.Settings.SelectCategory("Quests")
        eq(control.mouse, false)
    end)
end)

test("reputation does not change watch when native header restoration silently fails", function()
    withReputation(function(_, state, fire)
        C_Reputation.CollapseFactionHeader = function() end
        fire("Reputation with Stormwind increased by 1.")
        eq(#state.watched, 0)
    end, true)
end)
