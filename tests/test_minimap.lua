local UI = dofile("tests/ui_helpers.lua")

local function compartmentFixture(_, state)
    local H = dofile("tests/helpers.lua")
    AddonCompartmentFrame = H.newVisibilityFrame(false)
    AddonCompartmentFrame.count = 0
    function AddonCompartmentFrame:UpdateDisplay()
        if self.count > 0 then
            self:Show()
        else
            self:Hide()
        end
    end
    state.hooks = 0
    hooksecurefunc = function(object, method, callback)
        state.hooks = state.hooks + 1
        local original = object[method]
        object[method] = function(self, ...)
            original(self, ...)
            callback(self, ...)
        end
    end
end

local function frame(shown)
    return {
        shown = shown,
        changes = 0,
        IsShown = function(self)
            return self.shown
        end,
        Hide = function(self)
            self.shown = false
            self.changes = self.changes + 1
        end,
        Show = function(self)
            self.shown = true
            self.changes = self.changes + 1
        end,
    }
end

local function fixtures()
    GameTimeFrame = frame(true)
    TimeManagerClockButton = frame(false)
    MinimapCluster = { ZoneTextButton = frame(true), Tracking = { Button = frame(true) } }
    Minimap = { ZoomIn = frame(true), ZoomOut = frame(false) }
end

local function enable()
    MurgleDB.minimap.hideCalendar = true
    MurgleDB.minimap.hideClock = true
    MurgleDB.minimap.hideZoneText = true
    MurgleDB.minimap.hideTracking = true
    MurgleDB.minimap.hideZoomButtons = true
end

test("saved minimap choices apply at startup and reset restores each original visibility", function()
    UI.withAddon(function(M, state)
        eq(GameTimeFrame.shown, false)
        eq(MinimapCluster.ZoneTextButton.shown, false)
        eq(MinimapCluster.Tracking.Button.shown, false)
        eq(Minimap.ZoomIn.shown, false)
        M.ApplyAllSettings()
        M.ResetDB()
        eq(GameTimeFrame.shown, true)
        eq(TimeManagerClockButton.shown, false)
        eq(MinimapCluster.ZoneTextButton.shown, true)
        eq(MinimapCluster.Tracking.Button.shown, true)
        eq(Minimap.ZoomIn.shown, true)
        eq(Minimap.ZoomOut.shown, false)
        eq(#state.frames, 1)
        eq(next(state.frames[1].events), nil)
    end, function(M)
        fixtures()
        MurgleDB = M.ApplyDefaults({})
        enable()
    end)
end)

test("disabled minimap options neither touch frames nor queue work in combat", function()
    UI.withAddon(function(M, state)
        assert(M.Minimap, "minimap module must be loaded")
        eq(GameTimeFrame.changes, 0)
        eq(TimeManagerClockButton.changes, 0)
        eq(MinimapCluster.ZoneTextButton.changes, 0)
        eq(MinimapCluster.Tracking.Button.changes, 0)
        eq(Minimap.ZoomIn.changes + Minimap.ZoomOut.changes, 0)
        eq(M.GetDeferredCount(), 0)
        eq(next(state.frames[1].events), nil)
        eq(#state.frames, 1)
    end, function(_, state)
        fixtures()
        state.combat = true
    end)
end)

test("minimap settings save to the correct category and reset supersedes combat requests", function()
    UI.withAddon(function(M, state)
        fixtures()
        M.Settings.Show()
        local start = #state.frames
        M.Settings.SelectCategory("Minimap")
        local controls = {}
        for i = start + 1, #state.frames do
            local f = state.frames[i]
            if f.kind == "CheckButton" then
                controls[#controls + 1] = f
            end
        end
        eq(#controls, 10)
        state.combat = true
        for _, control in ipairs(controls) do
            control:SetChecked(true)
            control.scripts.OnClick(control)
        end
        eq(MurgleDB.minimap.square, true)
        eq(MurgleDB.minimap.hideBorder, true)
        eq(MurgleDB.minimap.hideCalendar, true)
        eq(MurgleDB.minimap.hideClock, true)
        eq(MurgleDB.minimap.hideTracking, true)
        eq(MurgleDB.minimap.hideZoneText, true)
        eq(MurgleDB.minimap.hideZoomButtons, true)
        eq(MurgleDB.interface.hideCalendar, nil)
        eq(GameTimeFrame.changes, 0)
        M.Settings.ConfirmReset()
        StaticPopupDialogs.MURGLE_RESET.OnAccept()
        state.combat = false
        local core = state.frames[1]
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(GameTimeFrame.changes, 0)
        eq(Minimap.ZoomIn.changes, 0)
        eq(M.GetDeferredCount(), 0)
        eq(next(core.events), nil)
        for _, control in ipairs(controls) do
            eq(control:GetChecked(), false)
        end
    end)
end)

test("missing minimap children retry safely when native frames become available", function()
    UI.withAddon(function(M)
        assert(M.Minimap, "minimap module must be loaded")
        fixtures()
        MinimapCluster.Tracking = nil
        Minimap.ZoomOut = nil
        GameTimeFrame = nil
        enable()
        M.ApplyAllSettings()
        eq(Minimap.ZoomIn.shown, false)
        eq(MinimapCluster.ZoneTextButton.shown, false)
        GameTimeFrame = frame(true)
        M.ApplyAllSettings()
        eq(GameTimeFrame.shown, false)
        M.ResetDB()
        eq(Minimap.ZoomIn.shown, true)
        eq(MinimapCluster.ZoneTextButton.shown, true)
    end)
end)

test("each minimap checkbox hides its own target and restores it on disable", function()
    UI.withAddon(function(M, state)
        fixtures()
        compartmentFixture(M, state)
        AddonCompartmentFrame.count = 1
        AddonCompartmentFrame:UpdateDisplay()
        MinimapCompassTexture = { alpha = 1 }
        function MinimapCompassTexture:GetAlpha()
            return self.alpha
        end
        function MinimapCompassTexture:SetAlpha(value)
            self.alpha = value
        end
        MinimapCluster.BorderTop = frame(true)
        MinimapCluster.DielFrame = dofile("tests/helpers.lua").newVisibilityFrame(true)
        TimeManagerClockButton.shown = true
        Minimap.ZoomOut.shown = true
        M.Settings.Show()
        local start = #state.frames
        M.Settings.SelectCategory("Minimap")
        local targets = {
            [M.L.HIDE_MINIMAP_ZONE] = MinimapCluster.ZoneTextButton,
            [M.L.HIDE_CLOCK] = TimeManagerClockButton,
            [M.L.HIDE_MINIMAP_HEADER] = MinimapCluster.BorderTop,
            [M.L.HIDE_CALENDAR] = GameTimeFrame,
            [M.L.HIDE_TRACKING] = MinimapCluster.Tracking.Button,
            [M.L.HIDE_ZOOM_BUTTONS] = Minimap.ZoomIn,
            [M.L.HIDE_ADDON_COMPARTMENT] = AddonCompartmentFrame,
            [M.L.HIDE_MINIMAP_BORDER] = MinimapCompassTexture,
            [M.L.HIDE_DAY_NIGHT] = MinimapCluster.DielFrame,
        }
        for i = start + 1, #state.frames do
            local control = state.frames[i]
            if control.kind == "CheckButton" then
                local target, square
                for _, region in ipairs(control.regions) do
                    target = target or targets[region.text]
                    square = square or region.text == M.L.SQUARE_MINIMAP
                end
                assert(target or square)
                if target then
                    control:SetChecked(true)
                    control.scripts.OnClick(control)
                    eq(target.alpha or target.shown, target.alpha and 0 or false)
                    control:SetChecked(false)
                    control.scripts.OnClick(control)
                    eq(target.alpha or target.shown, target.alpha and 1 or true)
                end
            end
        end
        eq(Minimap.ZoomOut.changes, 2)
        eq(Minimap.ZoomOut.shown, true)
    end)
end)

test("minimap startup in combat applies saved choices only after combat", function()
    UI.withAddon(function(M, state)
        eq(GameTimeFrame.changes, 0)
        eq(M.GetDeferredCount(), 6)
        state.combat = false
        local core = state.frames[1]
        core.scripts.OnEvent(core, "PLAYER_REGEN_ENABLED")
        eq(GameTimeFrame.shown, false)
        eq(Minimap.ZoomIn.shown, false)
        eq(M.GetDeferredCount(), 0)
        eq(next(core.events), nil)
    end, function(M, state)
        fixtures()
        state.combat = true
        MurgleDB = M.ApplyDefaults({})
        enable()
    end)
end)

test("addon compartment hiding survives native discovery and restores current eligibility", function()
    UI.withAddon(function(M, state)
        eq(state.hooks, 0)
        eq(AddonCompartmentFrame.changes, 0)
        MurgleDB.minimap.hideAddonCompartment = true
        M.Minimap.ApplyAddonCompartment()
        AddonCompartmentFrame.count = 2
        AddonCompartmentFrame:UpdateDisplay()
        eq(AddonCompartmentFrame.shown, false)
        M.Minimap.ApplyAddonCompartment()
        eq(state.hooks, 1)
        M.ResetDB()
        eq(AddonCompartmentFrame.shown, true, "restore current native eligibility, not pre-discovery hidden state")
        MurgleDB.minimap.hideAddonCompartment = true
        M.Minimap.ApplyAddonCompartment()
        AddonCompartmentFrame.count = 0
        M.ResetDB()
        eq(AddonCompartmentFrame.shown, false, "empty compartment must remain hidden")
    end, compartmentFixture)
end)

test("addon compartment combat deferral follows latest choice and rejects protected frames", function()
    UI.withAddon(function(M, state)
        local frame = AddonCompartmentFrame
        frame.count = 1
        frame:UpdateDisplay()
        frame.protected = true
        MurgleDB.minimap.hideAddonCompartment = true
        M.Minimap.ApplyAddonCompartment()
        eq(frame.shown, true)
        eq(state.hooks, 0)
        frame.protected = false
        state.combat = true
        M.Minimap.ApplyAddonCompartment()
        M.ResetDB()
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(frame.shown, true)
        eq(state.hooks, 0)
        eq(M.GetDeferredCount(), 0)
    end, compartmentFixture)
end)

test("minimap rim hiding preserves artwork alpha without hiding its button parent", function()
    UI.withAddon(function(M)
        local function texture(alpha)
            return {
                alpha = alpha,
                GetAlpha = function(self)
                    return self.alpha
                end,
                SetAlpha = function(self, value)
                    self.alpha = value
                end,
            }
        end
        MinimapCompassTexture = texture(0.8)
        MinimapCompassTextureUnderlay = texture(0.6)
        MurgleDB.minimap.hideBorder = true
        M.Minimap.ApplyBorder()
        eq(MinimapCompassTexture.alpha, 0)
        eq(MinimapCompassTextureUnderlay.alpha, 0)
        M.Minimap.ApplyBorder()
        M.ResetDB()
        eq(MinimapCompassTexture.alpha, 0.8)
        eq(MinimapCompassTextureUnderlay.alpha, 0.6)
    end)
end)

test("minimap rim reset cancels combat hiding and restores captured textures after replacement", function()
    UI.withAddon(function(M, state)
        local rim = { alpha = 0.7 }
        function rim:GetAlpha()
            return self.alpha
        end
        function rim:SetAlpha(value)
            self.alpha = value
        end
        MinimapCompassTexture = rim
        MurgleDB.minimap.hideBorder = true
        state.combat = true
        M.Minimap.ApplyBorder()
        eq(rim.alpha, 0.7)
        M.ResetDB()
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(rim.alpha, 0.7)
        MurgleDB.minimap.hideBorder = true
        M.Minimap.ApplyBorder()
        eq(rim.alpha, 0)
        MinimapCompassTexture = false
        M.ResetDB()
        eq(rim.alpha, 0.7)
    end)
end)

local H = dofile("tests/helpers.lua")

local function maskFixture(_, state)
    Minimap = H.newVisibilityFrame(true)
    Minimap.mask, Minimap.maskCalls = "native-original", 0
    function Minimap:SetMaskTexture(asset)
        self.mask = asset
        self.maskCalls = self.maskCalls + 1
    end
end

test("square minimap is inert by default and restores round mask on disable and reset", function()
    UI.withAddon(function(M, state)
        local map = Minimap
        eq(map.maskCalls, 0)
        MurgleDB.minimap.square = true
        M.Minimap.ApplySquare()
        eq(map.mask, "Interface\\BUTTONS\\WHITE8X8")
        eq(map.shown, true)
        eq(#state.frames, 1, "mask changes create no event frames")
        M.Minimap.ApplySquare()
        eq(map.maskCalls, 1, "repeated enable does not rewrite the mask")
        MurgleDB.minimap.square = false
        M.Minimap.ApplySquare()
        eq(map.mask, "ui-hud-minimap-frame-generic-mask")
        MurgleDB.minimap.square = true
        M.Minimap.ApplySquare()
        M.ResetDB()
        eq(map.mask, "ui-hud-minimap-frame-generic-mask")
        eq(next(state.frames[1].events), nil)
    end, maskFixture)
end)

test("square minimap combat queue follows latest choice and restores the owned frame", function()
    UI.withAddon(function(M, state)
        local map = Minimap
        state.combat = true
        MurgleDB.minimap.square = true
        M.Minimap.ApplySquare()
        M.ResetDB()
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(map.maskCalls, 0)
        MurgleDB.minimap.square = true
        M.Minimap.ApplySquare()
        Minimap = H.newVisibilityFrame(true)
        M.ResetDB()
        eq(map.mask, "ui-hud-minimap-frame-generic-mask")
        eq(Minimap.changes, 0)
        eq(M.GetDeferredCount(), 0)
    end, maskFixture)
end)

test("square minimap skips missing or protected integrations without blocking later retry", function()
    UI.withAddon(function(M)
        local map = Minimap
        MurgleDB.minimap.square = true
        Minimap = nil
        M.Minimap.ApplySquare()
        Minimap = map
        map.protected = true
        M.Minimap.ApplySquare()
        eq(map.maskCalls, 0)
        map.protected = false
        local setter = map.SetMaskTexture
        map.SetMaskTexture = nil
        M.Minimap.ApplySquare()
        eq(map.maskCalls, 0)
        map.SetMaskTexture = setter
        M.Minimap.ApplySquare()
        eq(map.maskCalls, 1)
    end, maskFixture)
end)

test("saved square minimap applies during startup without opening settings", function()
    UI.withAddon(function(M, state)
        eq(Minimap.mask, "Interface\\BUTTONS\\WHITE8X8")
        eq(#state.frames, 1)
        M.Settings.Show()
        M.Settings.SelectCategory("Minimap")
        local square
        for _, frame in ipairs(state.frames) do
            for _, region in ipairs(frame.regions or {}) do
                if region.text == M.L.SQUARE_MINIMAP then
                    square = frame
                end
            end
        end
        assert(square)
        eq(square:GetChecked(), true)
        square:SetChecked(false)
        square.scripts.OnClick(square)
        eq(MurgleDB.minimap.square, false)
        eq(Minimap.mask, "ui-hud-minimap-frame-generic-mask")
    end, function(M, state)
        maskFixture(M, state)
        MurgleDB = { minimap = { square = true } }
    end)
end)

test("owned square mask defers restoration and cancels it when reenabled during combat", function()
    UI.withAddon(function(M, state)
        local map = Minimap
        MurgleDB.minimap.square = true
        M.Minimap.ApplySquare()
        state.combat = true
        M.ResetDB()
        eq(map.mask, "Interface\\BUTTONS\\WHITE8X8")
        eq(map.maskCalls, 1)
        MurgleDB.minimap.square = true
        M.Minimap.ApplySquare()
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(map.mask, "Interface\\BUTTONS\\WHITE8X8")
        eq(map.maskCalls, 1)
        state.combat = true
        M.ResetDB()
        eq(map.maskCalls, 1)
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(map.mask, "ui-hud-minimap-frame-generic-mask")
        eq(map.maskCalls, 2)
        eq(M.GetDeferredCount(), 0)
        eq(next(state.frames[1].events), nil)
    end, maskFixture)
end)

test("day night indicator is inert until enabled and restores captured visibility", function()
    UI.withAddon(function(M)
        local H = dofile("tests/helpers.lua")
        local indicator = H.newVisibilityFrame(true)
        MinimapCluster = { DielFrame = indicator }
        M.Minimap.ApplyAll()
        eq(indicator.changes, 0)
        MurgleDB.minimap.hideDayNight = true
        M.Minimap.ApplyAll()
        eq(indicator.shown, false)
        MinimapCluster.DielFrame = H.newVisibilityFrame(true)
        M.ResetDB()
        eq(indicator.shown, true)
        eq(MinimapCluster.DielFrame.changes, 0)
    end)
end)

test("day night indicator skips unsafe frames and uses latest combat choice", function()
    UI.withAddon(function(M, state)
        local H = dofile("tests/helpers.lua")
        MurgleDB.minimap.hideDayNight = true
        MinimapCluster = {}
        M.Minimap.ApplyAll()
        local indicator = H.newVisibilityFrame(false)
        indicator.protected = true
        MinimapCluster.DielFrame = indicator
        M.Minimap.ApplyAll()
        eq(indicator.changes, 0)
        indicator.protected = false
        state.combat = true
        M.Minimap.ApplyAll()
        M.ResetDB()
        state.combat = false
        state.frames[1].scripts.OnEvent(state.frames[1], "PLAYER_REGEN_ENABLED")
        eq(indicator.changes, 0)
        MurgleDB.minimap.hideDayNight = true
        M.Minimap.ApplyAll()
        eq(indicator.changes, 1)
        M.ResetDB()
        eq(indicator.shown, false)
    end)
end)

test("day night checkbox persists and reset restores saved startup visibility", function()
    UI.withAddon(function(M, state)
        eq(MinimapCluster.DielFrame.shown, false)
        M.Settings.Show()
        M.Settings.SelectCategory("Minimap")
        local control
        for _, widget in ipairs(state.frames) do
            if widget.kind == "CheckButton" and widget:GetChecked() == true then
                control = widget
            end
        end
        assert(control, "saved indicator choice must have a checked control")
        control:SetChecked(false)
        control.scripts.OnClick(control)
        eq(MurgleDB.minimap.hideDayNight, false)
        eq(MinimapCluster.DielFrame.shown, true)
    end, function(M)
        local H = dofile("tests/helpers.lua")
        MinimapCluster = { DielFrame = H.newVisibilityFrame(true) }
        MurgleDB = M.ApplyDefaults({ minimap = { hideDayNight = true } })
    end)
end)

test("clock hiding waits for native TimeManager load then releases its listener", function()
    UI.withAddon(function(M, state)
        TimeManagerClockButton = nil
        MurgleDB.minimap.hideClock = true
        M.Minimap.ApplyClock()
        local waiter
        for _, f in ipairs(state.frames) do
            if f.events.ADDON_LOADED then
                waiter = f
            end
        end
        assert(waiter, "missing clock must wait for its native addon")
        TimeManagerClockButton = frame(true)
        waiter.scripts.OnEvent(waiter, "ADDON_LOADED", "Unrelated")
        eq(TimeManagerClockButton.shown, true)
        waiter.scripts.OnEvent(waiter, "ADDON_LOADED", "Blizzard_TimeManager")
        eq(TimeManagerClockButton.shown, false)
        eq(next(waiter.events), nil)
        M.ResetDB()
        eq(TimeManagerClockButton.shown, true)
    end)
end)

test("minimap header art hides independently and restores native visibility", function()
    UI.withAddon(function(M)
        MinimapCluster = { BorderTop = frame(true) }
        MurgleDB.minimap.hideHeader = true
        M.Minimap.ApplyHeader()
        eq(MinimapCluster.BorderTop.shown, false)
        M.ResetDB()
        eq(MinimapCluster.BorderTop.shown, true)
    end)
end)

test("retired minimap coordinates preserve the native preference through startup and reset", function()
    local H = dofile("tests/helpers.lua")
    H.withGlobals({
        C_CVar = {
            GetCVarInfo = function(name)
                assert(name ~= "minimapShowPlayerCoords", "retired preference must not be read")
            end,
            SetCVar = function(name)
                assert(name ~= "minimapShowPlayerCoords", "native preference must remain untouched")
            end,
        },
    }, function()
        UI.withAddon(function(M)
            local db = M.ApplyDefaults({ minimap = { hideCoordinates = true, coordinatesRestore = "1" } })
            eq(db.minimap.hideCoordinates, nil)
            eq(db.minimap.coordinatesRestore, nil)
            MurgleDB = db
            M.Minimap.ApplyAll()
            M.ResetDB()
        end)
    end)
end)

test("tracking hiding includes its native background without hiding other minimap art", function()
    UI.withAddon(function(M)
        local background = frame(true)
        MinimapCluster = { Tracking = { Button = frame(true), Background = background } }
        MurgleDB.minimap.hideTracking = true
        M.Minimap.ApplyTracking()
        eq(background.shown, false)
        M.ResetDB()
        eq(background.shown, true)
    end)
end)

test("square minimap owns compass art with rim option and creates four static edges", function()
    UI.withAddon(function(M, state)
        local map = Minimap
        local rim = { alpha = 0.8 }
        function rim:GetAlpha()
            return self.alpha
        end
        function rim:SetAlpha(value)
            self.alpha = value
        end
        MinimapCompassTexture = rim
        local edges = {}
        function map:CreateTexture()
            local edge = H.newVisibilityFrame(true)
            function edge:SetColorTexture(...)
                self.color = { ... }
            end
            function edge:SetPoint(...) end
            function edge:SetHeight(value)
                self.height = value
            end
            function edge:SetWidth(value)
                self.width = value
            end
            edges[#edges + 1] = edge
            return edge
        end
        MurgleDB.minimap.square = true
        M.Minimap.ApplySquare()
        eq(rim.alpha, 0)
        eq(#edges, 4)
        eq(edges[1].height, 1)
        eq(edges[3].width, 1)
        M.Minimap.ApplySquare()
        eq(#edges, 4)
        MurgleDB.minimap.hideBorder = true
        M.Minimap.ApplyBorder()
        MurgleDB.minimap.square = false
        M.Minimap.ApplySquare()
        eq(rim.alpha, 0)
        eq(edges[1].shown, false)
        MurgleDB.minimap.hideBorder = false
        M.Minimap.ApplyBorder()
        eq(rim.alpha, 0.8)
        MurgleDB.minimap.square = true
        M.Minimap.ApplySquare()
        eq(#edges, 4)
        eq(edges[1].shown, true)
        M.ResetDB()
        eq(rim.alpha, 0.8)
    end, maskFixture)
end)

test("square minimap suppresses and restores native blob ring textures", function()
    UI.withAddon(function(M, state)
        local map = Minimap
        local calls = {}
        for _, method in ipairs({
            "SetQuestBlobRingScalar",
            "SetQuestBlobRingAlpha",
            "SetArchBlobRingScalar",
            "SetArchBlobRingAlpha",
            "SetTaskBlobRingScalar",
            "SetTaskBlobRingAlpha",
        }) do
            map[method] = function(_, val)
                calls[method] = val
            end
        end
        MurgleDB.minimap.square = true
        M.Minimap.ApplySquare()
        eq(calls.SetQuestBlobRingScalar, 0)
        eq(calls.SetQuestBlobRingAlpha, 0)
        eq(calls.SetArchBlobRingScalar, 0)
        eq(calls.SetArchBlobRingAlpha, 0)
        eq(calls.SetTaskBlobRingScalar, 0)
        eq(calls.SetTaskBlobRingAlpha, 0)
        MurgleDB.minimap.square = false
        M.Minimap.ApplySquare()
        eq(calls.SetQuestBlobRingScalar, 1)
        eq(calls.SetQuestBlobRingAlpha, 1)
        eq(calls.SetArchBlobRingScalar, 1)
        eq(calls.SetArchBlobRingAlpha, 1)
        eq(calls.SetTaskBlobRingScalar, 1)
        eq(calls.SetTaskBlobRingAlpha, 1)
    end, maskFixture)
end)

test("square minimap hides rim control without changing its saved preference", function()
    UI.withAddon(function(M, state)
        M.Settings.Show()
        M.Settings.SelectCategory("Minimap")
        local rim, square
        for _, control in ipairs(state.frames) do
            if control.kind == "CheckButton" then
                for _, region in ipairs(control.regions) do
                    if region.text == M.L.HIDE_MINIMAP_BORDER then
                        rim = control
                    elseif region.text == M.L.SQUARE_MINIMAP then
                        square = control
                    end
                end
            end
        end
        assert(rim and square)
        rim:SetChecked(true)
        rim.scripts.OnClick(rim)
        eq(rim:IsShown(), true)
        square:SetChecked(true)
        square.scripts.OnClick(square)
        eq(rim:IsShown(), false)
        eq(MurgleDB.minimap.hideBorder, true)
        square:SetChecked(false)
        square.scripts.OnClick(square)
        eq(rim:IsShown(), true)
        eq(rim:GetChecked(), true)
        eq(MurgleDB.minimap.hideBorder, true)
    end)
end)

test("retired quest circle preference is inert and square still restores its rings", function()
    UI.withAddon(function(M, state)
        local calls, writes = {}, 0
        for _, method in ipairs({
            "SetQuestBlobRingScalar",
            "SetQuestBlobRingAlpha",
            "SetTaskBlobRingScalar",
            "SetTaskBlobRingAlpha",
            "SetArchBlobRingScalar",
            "SetArchBlobRingAlpha",
        }) do
            Minimap[method] = function(_, value)
                calls[method] = value
                writes = writes + 1
            end
        end
        MurgleDB.minimap.hideQuestCircles = true
        M.Minimap.Initialize()
        eq(writes, 0)
        MurgleDB.minimap.square = true
        M.Minimap.ApplySquare()
        eq(calls.SetQuestBlobRingAlpha, 0)
        eq(calls.SetTaskBlobRingAlpha, 0)
        eq(calls.SetArchBlobRingAlpha, 0)
        MurgleDB.minimap.square = false
        M.Minimap.ApplySquare()
        eq(calls.SetQuestBlobRingAlpha, 1)
        eq(calls.SetTaskBlobRingAlpha, 1)
        eq(calls.SetArchBlobRingAlpha, 1)
    end, maskFixture)
end)
