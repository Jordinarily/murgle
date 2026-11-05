local H = dofile("tests/helpers.lua")

local function withBags(fn, saved)
    local M, combat, hooks, handles, deferred = {}, false, {}, {}, {}
    local bag = { x = 900, y = 500, scale = 0.75, points = 0, clamped = false, placed = false }
    function bag:IsProtected()
        return self.protected == true
    end
    function bag:GetCenter()
        return self.x, self.y
    end
    function bag:GetEffectiveScale()
        return self.scale
    end
    function bag:ClearAllPoints()
        self.points = self.points + 1
    end
    function bag:SetPoint(...)
        self.anchor = { ... }
    end
    function bag:StartMoving()
        self.moving = true
    end
    function bag:StopMovingOrSizing()
        self.moving = false
    end
    function bag:IsClampedToScreen()
        return self.clamped
    end
    function bag:SetClampedToScreen(value)
        self.clamped = value
    end
    function bag:IsUserPlaced()
        return self.placed
    end
    function bag:SetUserPlaced(value)
        self.placed = value
    end
    bag.TitleContainer = {
        GetFrameLevel = function()
            return 510
        end,
    }
    local root = {}
    function root:GetCenter()
        return 500, 400
    end
    function root:GetEffectiveScale()
        return 1
    end
    local restores = 0
    H.withGlobals({
        MurgleDB = { interface = saved or { moveBags = false } },
        ContainerFrameCombinedBags = bag,
        ContainerFrameSettingsManager = {
            GetBagsShown = function()
                return { bag }
            end,
        },
        UIParent = root,
        GameTooltip = false,
        InCombatLockdown = function()
            return combat
        end,
        UpdateContainerFrameAnchors = function()
            restores = restores + 1
            if hooks.anchor then
                hooks.anchor()
            end
        end,
        hooksecurefunc = function(name, fn)
            eq(name, "UpdateContainerFrameAnchors")
            eq(hooks.anchor, nil, "only one native hook")
            hooks.anchor = fn
        end,
        CreateFrame = function(kind, name, parent)
            local handle = H.newEventFrame()
            handle.parent = parent
            function handle:SetAllPoints(target)
                self.allPoints = target
            end
            function handle:SetFrameLevel(level)
                self.level = level
            end
            function handle:EnableMouse(enabled)
                self.mouse = enabled
            end
            function handle:SetSize() end
            function handle:SetPoint() end
            function handle:RegisterForDrag() end
            function handle:Show()
                self.shown = true
            end
            function handle:Hide()
                self.shown = false
            end
            handles[#handles + 1] = handle
            return handle
        end,
    }, function()
        M.DeferUntilOutOfCombat = function(key, apply)
            if combat then
                deferred[key] = apply
            else
                deferred[key] = nil
                apply()
            end
        end
        H.loadAddonFile("Modules/Bags.lua", M)
        fn(M.Bags, bag, handles, hooks, function(value)
            combat = value
        end, function()
            combat = false
            if deferred["bags.stop"] then
                local stop = deferred["bags.stop"]
                deferred["bags.stop"] = nil
                stop()
            end
            for key, apply in pairs(deferred) do
                deferred[key] = nil
                apply()
            end
        end, function()
            return restores
        end)
    end)
end

test("bag positioning disabled startup creates no handle hook or native mutation", function()
    withBags(function(B, bag, handles, hooks)
        B.ApplyAll()
        eq(#handles, 0)
        eq(hooks.anchor, nil)
        eq(bag.points, 0)
    end)
end)

test("bag drag saves scaled center offsets and native layout reapplies them", function()
    withBags(function(B, bag, handles, hooks)
        B.ApplyAll()
        eq(#handles, 1)
        eq(bag.anchor, nil, "no saved position preserves native anchor")
        handles[1].scripts.OnDragStart()
        eq(bag.moving, true)
        handles[1].scripts.OnDragStop()
        eq(bag.moving, false)
        eq(MurgleDB.interface.bagPosition.x, 175)
        eq(MurgleDB.interface.bagPosition.y, -25)
        eq(bag.anchor[1], "CENTER")
        eq(bag.anchor[4], 175 / 0.75)
        local points = bag.points
        hooks.anchor()
        eq(bag.points, points + 1)
        B.ApplyAll()
        eq(#handles, 1)
    end, { moveBags = true })
end)

test("bag disable restores native placement and properties; reset clears saved position", function()
    withBags(function(B, bag, handles, hooks, _, _, restores)
        B.ApplyAll()
        eq(bag.clamped, true)
        MurgleDB.interface.moveBags = false
        B.ApplyAll()
        eq(handles[1].shown, false)
        eq(bag.clamped, false)
        eq(restores(), 1)
        local points = bag.points
        hooks.anchor()
        eq(bag.points, points)
        B.ResetPosition()
        eq(MurgleDB.interface.bagPosition, nil)
        MurgleDB.interface.moveBags = true
        B.ApplyAll()
        eq(handles[1].shown, true)
        eq(#handles, 1)
    end, { moveBags = true, bagPosition = { x = 10, y = 20 } })
end)

test("bag changes defer in combat and dragging cannot begin during combat", function()
    withBags(function(B, bag, handles, hooks, combat, drain)
        combat(true)
        B.ApplyAll()
        eq(#handles, 0)
        drain()
        combat(true)
        handles[1].scripts.OnDragStart()
        eq(bag.moving, nil)
        local points = bag.points
        hooks.anchor()
        eq(bag.points, points)
        B.ResetPosition()
        eq(bag.points, points)
        drain()
        eq(MurgleDB.interface.bagPosition, nil)
    end, { moveBags = true, bagPosition = { x = 10, y = 20 } })
end)

test("bag positioning skips protected missing integrations and corrupt positions", function()
    withBags(function(B, bag, handles)
        bag.protected = true
        B.ApplyAll()
        eq(#handles, 0)
        bag.protected = false
        local clear = bag.ClearAllPoints
        bag.ClearAllPoints = nil
        B.ApplyAll()
        eq(#handles, 0)
        bag.ClearAllPoints = clear
        B.ApplyAll()
        eq(#handles, 1)
        eq(bag.anchor, nil)
    end, { moveBags = true, bagPosition = { x = 0 / 0, y = 20 } })
end)

test("bag hide during drag saves once and combat interruption defers stopping safely", function()
    withBags(function(B, bag, handles, _, combat, drain)
        B.ApplyAll()
        handles[1].scripts.OnDragStart()
        combat(true)
        handles[1].scripts.OnHide()
        eq(MurgleDB.interface.bagPosition, nil)
        drain()
        eq(bag.moving, false)
        eq(MurgleDB.interface.bagPosition.x, 175)
        local saved = MurgleDB.interface.bagPosition
        handles[1].scripts.OnDragStop()
        eq(MurgleDB.interface.bagPosition, saved)
    end, { moveBags = true })
end)

test("reset wins over a drag stop that was already deferred by combat", function()
    withBags(function(B, bag, handles, _, combat, drain)
        B.ApplyAll()
        handles[1].scripts.OnDragStart()
        combat(true)
        handles[1].scripts.OnDragStop()
        B.ResetPosition()
        drain()
        eq(MurgleDB.interface.bagPosition, nil)
        eq(bag.moving, false)
    end, { moveBags = true })
end)

test("saved bag anchor survives new module load and adapts to current scale", function()
    withBags(function(B, bag, handles, hooks)
        B.ApplyAll()
        eq(bag.anchor[4], 120 / 0.75)
        eq(bag.anchor[5], -60 / 0.75)
        bag.scale = 1.25
        hooks.anchor()
        eq(bag.anchor[4], 120 / 1.25)
        eq(bag.anchor[5], -60 / 1.25)
    end, { moveBags = true, bagPosition = { x = 120, y = -60 } })
end)

test("moving combined bags detaches dependent windows at their native screen position", function()
    withBags(function(B, bag, handles)
        local secondary = { relative = bag }
        function secondary:IsProtected()
            return false
        end
        function secondary:GetPoint()
            return "BOTTOMRIGHT", self.relative, "BOTTOMLEFT", -11, 0
        end
        function secondary:GetCenter()
            return 300, 250
        end
        function secondary:GetEffectiveScale()
            return 0.75
        end
        function secondary:ClearAllPoints() end
        function secondary:SetPoint(...)
            self.anchor = { ... }
            self.relative = self.anchor[2]
        end
        local shown = { bag, secondary }
        local integrations = {
            ContainerFrameSettingsManager = {
                GetBagsShown = function()
                    return shown
                end,
            },
        }
        H.withGlobals(integrations, function()
            B.ApplyAll()
            handles[1].scripts.OnDragStart()
            eq(secondary.relative, UIParent)
            eq(secondary.anchor[4], 300 - 500 / 0.75)
            eq(secondary.anchor[5], 250 - 400 / 0.75)
        end)
    end, { moveBags = true })
end)

test("bag title clicks retain the native menu while a drag does not click it", function()
    withBags(function(B, bag, handles)
        local opened = 0
        bag.PortraitButton = {}
        local integrations = {
            DropdownButtonMixin = {
                OnMouseDown_Intrinsic = function(button)
                    eq(button, bag.PortraitButton)
                    opened = opened + 1
                end,
            },
        }
        H.withGlobals(integrations, function()
            B.ApplyAll()
            local handle = handles[1]
            assert(handle.scripts.OnClick, "title click must forward to native menu")
            handle.scripts.OnMouseDown()
            handle.scripts.OnClick()
            eq(opened, 1)
            handle.scripts.OnMouseDown()
            handle.scripts.OnDragStart()
            handle.scripts.OnDragStop()
            handle.scripts.OnClick()
            eq(opened, 1)
            handle.scripts.OnMouseDown()
            handle.scripts.OnClick()
            eq(opened, 2)
        end)
    end, { moveBags = true })
end)

test("bag title drag target covers the native title above its high frame layers", function()
    withBags(function(B, bag, handles)
        B.ApplyAll()
        local control = handles[1]
        -- The native title is at level 510, above ordinary bag children. A
        -- mouse target below it cannot reliably receive the user's title drag.
        eq(control.parent, bag.TitleContainer)
        eq(control.allPoints, bag.TitleContainer)
        eq(control.mouse, true)
        assert(control.level > bag.TitleContainer:GetFrameLevel(), "drag target below native title")
        control.scripts.OnDragStart()
        eq(bag.moving, true)
        control.scripts.OnDragStop()
        eq(MurgleDB.interface.bagPosition.x, 175)
    end, { moveBags = true })
end)

test("bag dragging skips a missing native title and retries on explicit apply", function()
    withBags(function(B, bag, handles)
        local title = bag.TitleContainer
        bag.TitleContainer = nil
        B.ApplyAll()
        eq(#handles, 0)
        bag.TitleContainer = title
        B.ApplyAll()
        eq(#handles, 1)
        eq(handles[1].parent, title)
    end, { moveBags = true })
end)
