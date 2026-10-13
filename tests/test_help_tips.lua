local UI = dofile("tests/ui_helpers.lua")

local function fixture(_, state)
    state.helpTipValue = "0"
    HelpTip = { supressHelpTips = {} }
    function HelpTip:SetHelpTipsEnabled()
        error("must not taint Blizzard's shared help-tip policy")
    end
    function HelpTip:AreHelpTipsEnabled()
        return state.helpTipValue ~= "1"
    end
    GetCVar = function(name)
        if name == "hideHelptips" then
            return state.helpTipValue
        end
    end
    SetCVar = function(name, value)
        eq(name, "hideHelptips")
        state.helpTipValue = value
        state.writes = (state.writes or 0) + 1
    end
end

local function block(M, enabled)
    MurgleDB.interface.blockHelpTips = enabled
    M.Interface.ApplyHelpTips()
end

test("help tips default leaves native policy untouched and toggles without recurring work", function()
    UI.withAddon(function(M, state)
        eq(MurgleDB.interface.blockHelpTips, false)
        eq(state.writes, nil)
        block(M, true)
        eq(HelpTip:AreHelpTipsEnabled(), false)
        block(M, true)
        eq(state.writes, 1)
        block(M, false)
        eq(HelpTip:AreHelpTipsEnabled(), true)
        eq(next(HelpTip.supressHelpTips), nil, "remove our policy entry entirely")
        eq(#state.frames, 1)
        eq(next(state.frames[1].events), nil)
    end, fixture)
end)

test("help tip restoration preserves external native preference changes", function()
    UI.withAddon(function(M, state)
        block(M, true)
        eq(next(HelpTip.supressHelpTips), nil)
        state.helpTipValue = "0"
        block(M, false)
        eq(state.writes, 1)
        eq(state.helpTipValue, "0")
    end, fixture)
end)

test("help tips missing native CVar fails closed and explicit apply retries", function()
    UI.withAddon(function(M, state)
        state.helpTipValue = nil
        block(M, true)
        eq(state.writes, nil)
        state.helpTipValue = "0"
        block(M, true)
        eq(state.helpTipValue, "1")
    end, fixture)
end)

test("saved help tip preference survives reload and reset restores prior value", function()
    UI.withAddon(function(M, state)
        eq(state.helpTipValue, "1")
        eq(next(HelpTip.supressHelpTips), nil)
        M.ResetDB()
        eq(state.helpTipValue, "0")
    end, function(M, state)
        fixture(M, state)
        state.helpTipValue = "1"
        MurgleDB = { interface = { blockHelpTips = true, helpTipsRestore = "0" } }
    end)
end)

test("help tip checkbox persists and reset refreshes its cached state", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        local control
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions) do
                if M.L.BLOCK_HELP_TIPS and region.text == M.L.BLOCK_HELP_TIPS then
                    control = frame
                end
            end
        end
        assert(control, "Block new help tips checkbox is available")
        control:SetChecked(true)
        control.scripts.OnClick(control)
        eq(MurgleDB.interface.blockHelpTips, true)
        eq(HelpTip:AreHelpTipsEnabled(), false)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(control:GetChecked(), false)
        eq(HelpTip:AreHelpTipsEnabled(), true)
    end, fixture)
end)
