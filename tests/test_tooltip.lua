local H = dofile("tests/helpers.lua")

local function withTooltip(fn)
    local state = { hooks = 0, frames = {}, combat = false }
    local tip = H.newVisibilityFrame(false)
    tip.owner, tip.anchor, tip.kind = {}, "ANCHOR_NONE", 1
    function tip:SetOwner(owner, anchor, x, y)
        self.owner, self.anchor, self.x, self.y = owner, anchor, x, y
    end
    function tip:GetOwner()
        return self.owner
    end
    function tip:GetAnchorType()
        return self.anchor
    end
    function tip:IsTooltipType(kind)
        return self.kind == kind
    end
    H.withGlobals({
        MurgleDB = {
            tooltip = { cursorAnchor = false, hideInCombat = false },
        },
        GameTooltip = tip,
        UIParent = {},
        Enum = {
            TooltipDataType = { Unit = 1 },
        },
        GameTooltip_SetDefaultAnchor = function(frame, parent)
            frame:SetOwner(parent, "ANCHOR_NONE")
        end,
        InCombatLockdown = function()
            return state.combat
        end,
        CreateFrame = function()
            local frame = H.newEventFrame()
            state.frames[#state.frames + 1] = frame
            return frame
        end,
        hooksecurefunc = function(object, method, callback)
            state.hooks = state.hooks + 1
            if type(object) == "string" then
                local name, hook = object, method
                local original = _G[name]
                _G[name] = function(...)
                    original(...)
                    hook(...)
                end
            else
                local original = object[method]
                object[method] = function(self, ...)
                    original(self, ...)
                    callback(self, ...)
                end
            end
        end,
    }, function()
        local M = {}
        H.loadAddonFile("Modules/Tooltip.lua", M)
        fn(M.Tooltip, tip, state)
    end)
end

test("disabled tooltip features install no hooks or events", function()
    withTooltip(function(T, tip, state)
        T.Initialize()
        eq(state.hooks, 0)
        eq(#state.frames, 0)
        eq(tip.changes, 0)
    end)
end)

test("cursor anchor preserves native owner and restores default anchor on disable", function()
    withTooltip(function(T, tip, state)
        MurgleDB.tooltip.cursorAnchor = true
        T.ApplyCursorAnchor()
        local owner = {}
        GameTooltip_SetDefaultAnchor(tip, owner)
        eq(tip.owner, owner)
        eq(tip.anchor, "ANCHOR_CURSOR_RIGHT")
        eq(tip.x, nil)
        T.ApplyCursorAnchor()
        eq(state.hooks, 1)
        MurgleDB.tooltip.cursorAnchor = false
        T.ApplyCursorAnchor()
        eq(tip.anchor, "ANCHOR_NONE")
        GameTooltip_SetDefaultAnchor(tip, owner)
        eq(tip.anchor, "ANCHOR_NONE")
    end)
end)

test("cursor choices use native anchors and reject unknown choices", function()
    withTooltip(function(T, tip)
        MurgleDB.tooltip.cursorAnchor = true
        T.SetAnchor("right")
        GameTooltip_SetDefaultAnchor(tip, UIParent)
        eq(tip.anchor, "ANCHOR_CURSOR_RIGHT")
        eq(tip.x, nil)
        T.SetAnchor("left")
        eq(tip.anchor, "ANCHOR_CURSOR_LEFT")
        T.SetAnchor("cursor")
        eq(tip.anchor, "ANCHOR_CURSOR")
        T.SetAnchor("invalid")
        eq(MurgleDB.tooltip.anchor, "cursor")
        MurgleDB.tooltip.cursorAnchor = false
        T.ApplyCursorAnchor()
        eq(tip.anchor, "ANCHOR_NONE")
    end)
end)

test("cursor disable does not disturb a tooltip reowned by another caller", function()
    withTooltip(function(T, tip)
        MurgleDB.tooltip.cursorAnchor = true
        T.ApplyCursorAnchor()
        GameTooltip_SetDefaultAnchor(tip, UIParent)
        local custom = {}
        tip:SetOwner(custom, "ANCHOR_LEFT")
        MurgleDB.tooltip.cursorAnchor = false
        T.ApplyCursorAnchor()
        eq(tip.owner, custom)
        eq(tip.anchor, "ANCHOR_LEFT")
    end)
end)

test("combat tooltip hiding leaves item and spell tooltips visible and removes its event on disable", function()
    withTooltip(function(T, tip, state)
        MurgleDB.tooltip.hideInCombat = true
        T.ApplyCombatHide()
        tip:Show()
        eq(tip.shown, true)
        state.combat = true
        state.frames[1].scripts.OnEvent()
        eq(tip.shown, false)
        tip:Show()
        eq(tip.shown, false)
        tip.kind = 2
        tip:Show()
        eq(tip.shown, true, "item and spell tooltips stay visible")
        MurgleDB.tooltip.hideInCombat = false
        T.ApplyCombatHide()
        eq(next(state.frames[1].events), nil)
        tip.kind = 1
        tip:Show()
        eq(tip.shown, true)
    end)
end)

test("combat tooltip hiding covers native objects and corpses without extra hooks", function()
    withTooltip(function(T, tip, state)
        Enum.TooltipDataType.Object, Enum.TooltipDataType.Corpse = 4, 3
        MurgleDB.tooltip.hideInCombat = true
        T.ApplyCombatHide()
        for _, kind in ipairs({ 4, 3 }) do
            tip.kind = kind
            tip:Show()
            eq(tip.shown, true, "out of combat remains native")
            state.combat = true
            state.frames[1].scripts.OnEvent()
            eq(tip.shown, false, "existing world tooltip hides on combat entry")
            tip:Show()
            eq(tip.shown, false, "native repeated Show remains hidden")
            state.combat = false
        end
        T.ApplyCombatHide()
        eq(state.hooks, 1)
        eq(#state.frames, 1)
        MurgleDB.tooltip.hideInCombat = false
        T.ApplyCombatHide()
        state.combat = true
        tip:Show()
        eq(tip.shown, true)
    end)
end)

test("world tooltip hiding skips absent enum values unknown types and protected tooltips", function()
    withTooltip(function(T, tip, state)
        MurgleDB.tooltip.hideInCombat = true
        state.combat = true
        T.ApplyCombatHide()
        tip.kind = nil
        tip:Show()
        eq(tip.shown, true, "nil must not match an absent enum")
        Enum.TooltipDataType.Object = 4
        tip.kind, tip.protected = 4, true
        tip:Show()
        eq(tip.shown, true)
        tip.protected = false
        tip:Show()
        eq(tip.shown, false)
        tip.kind = 99
        tip:Show()
        eq(tip.shown, true)
    end)
end)

test("missing tooltip API fails independently without hooks or events", function()
    withTooltip(function(T, tip, state)
        tip.IsTooltipType = nil
        MurgleDB.tooltip.hideInCombat = true
        T.ApplyCombatHide()
        eq(#state.frames, 0)
        eq(state.hooks, 0)
        MurgleDB.tooltip.cursorAnchor = true
        T.ApplyCursorAnchor()
        GameTooltip_SetDefaultAnchor(tip, UIParent)
        eq(tip.anchor, "ANCHOR_CURSOR_RIGHT")
    end)
end)

local UI = dofile("tests/ui_helpers.lua")

test("tooltip settings persist to their category and reset cached controls", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        local start = #state.frames
        M.Settings.SelectCategory("Tooltip")
        local checks = {}
        local plus
        for i = start + 1, #state.frames do
            local frame = state.frames[i]
            if frame.kind == "CheckButton" then
                checks[#checks + 1] = frame
                frame:SetChecked(true)
                frame.scripts.OnClick(frame)
            elseif frame.kind == "Button" and not plus then
                for _, region in ipairs(frame.regions) do
                    if region.text == "At cursor" then
                        plus = frame
                    end
                end
            end
        end
        eq(#checks, 2)
        eq(MurgleDB.tooltip.cursorAnchor, true)
        eq(MurgleDB.tooltip.hideInCombat, true)
        eq(MurgleDB.tooltip.compact, nil)
        eq(MurgleDB.interface.cursorAnchor, nil)
        assert(plus)
        plus.scripts.OnClick(plus)
        eq(MurgleDB.tooltip.anchor, "cursor")
        eq(plus:IsShown(), true)
        checks[1]:SetChecked(false)
        checks[1].scripts.OnClick(checks[1])
        eq(plus:IsShown(), false)
        eq(MurgleDB.tooltip.anchor, "cursor")
        checks[1]:SetChecked(true)
        checks[1].scripts.OnClick(checks[1])
        eq(plus:IsShown(), true)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        eq(MurgleDB.tooltip.anchor, "right")
        eq(checks[1]:GetChecked(), false)
        eq(checks[2]:GetChecked(), false)
        eq(plus:IsShown(), false)
        eq(MurgleDB.tooltip.compact, nil)
    end)
end)
