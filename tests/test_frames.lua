local H = dofile("tests/helpers.lua")

local function region()
    local r = H.newVisibilityFrame(true)
    r.alpha, r.points = 1, { { "CENTER", {}, "CENTER", 0, -0.5 } }
    function r:GetAlpha()
        return self.alpha
    end
    function r:SetAlpha(v)
        self.alpha = v
    end
    function r:GetNumPoints()
        return #self.points
    end
    function r:GetPoint(i)
        return unpack(self.points[i])
    end
    function r:ClearAllPoints()
        self.points = {}
    end
    function r:SetPoint(...)
        local point = { ... }
        for i, existing in ipairs(self.points) do
            if existing[1] == point[1] then
                self.points[i] = point
                return
            end
        end
        self.points[#self.points + 1] = point
    end
    r.fontObject, r.width, r.vertex = "large", 124, { 1, 1, 1, 1 }
    function r:GetFontObject()
        return self.fontObject
    end
    function r:SetFontObject(value)
        self.fontObject = value
    end
    function r:GetWidth()
        return self.width
    end
    function r:SetWidth(value)
        self.width = value
    end
    function r:GetVertexColor()
        return unpack(self.vertex)
    end
    function r:SetVertexColor(...)
        self.vertex = { ... }
    end
    return r
end

local function withFrames(fn)
    local s = { frames = {}, hooks = 0, writes = 0, combat = false, pending = {}, enemy = false, player = false }
    s.values = {
        nameplateShowEnemies = "1",
        nameplateShowFriendlyPlayers = "1",
        nameplateShowFriendlyNpcs = "1",
        nameplateShowOnlyNameForFriendlyPlayerUnits = "0",
        nameplateShowClassColor = "0",
        nameplateShowFriendlyClassColor = "0",
    }
    local pm = {
        LevelBackgroundCircle = region(),
        HealthBarsContainer = region(),
        StatusTexture = region(),
        PvpBackgroundCircle = region(),
        PvpBackgroundIcon = region(),
        ManaBarArea = { ManaBar = region() },
    }
    local tm = {
        LevelBackgroundCircle = region(),
        LevelText = region(),
        Name = region(),
        HealthBarsContainer = region(),
        ManaBar = region(),
        ReputationColor = region(),
    }
    for _, main in ipairs({ pm, tm }) do
        main.edges = {}
        function main:CreateTexture()
            local edge = region()
            edge.points = {}
            function edge:SetColorTexture(...)
                self.color = { ... }
            end
            function edge:SetHeight(height)
                self.height = height
            end
            self.edges[#self.edges + 1] = edge
            return edge
        end
    end
    local tc = { HighLevelTexture = region(), PvpBackgroundCircle = region(), PvpBackgroundIcon = region() }
    local p = {
        PlayerFrameContainer = {
            PlayerPortrait = region(),
            FrameTexture = region(),
            VehicleFrameTexture = region(),
            AlternatePowerFrameTexture = region(),
            FrameFlash = region(),
        },
        PlayerFrameContent = { PlayerFrameContentMain = pm },
    }
    local t = {
        unit = "target",
        TargetFrameContainer = {
            Portrait = region(),
            FrameTexture = region(),
            BossPortraitFrameTexture = region(),
            Flash = region(),
        },
        TargetFrameContent = { TargetFrameContentMain = tm, TargetFrameContentContextual = tc },
    }
    function t:CheckFaction()
        tc.PvpBackgroundCircle:Show()
        tc.PvpBackgroundIcon:Show()
    end
    H.withGlobals({
        GameFontNormalSmall = "small",
        PlayerFrame_UpdateStatus = false,
        PlayerFrame_UpdateLevel = false,
        PlayerFrame_UpdatePlayerRestLoop = false,
        PlayerFrame_UpdatePlayerNameTextAnchor = false,
        MurgleDB = { frames = { enemyNameplates = "blizzard", friendlyNameplates = "blizzard" } },
        PlayerFrame = p,
        TargetFrame = t,
        PlayerLevelText = region(),
        PlayerName = region(),
        C_CVar = {
            GetCVarInfo = function(name)
                return s.values[name], nil, nil, nil, false, false, false
            end,
            SetCVar = function(name, value)
                s.writes = s.writes + 1
                s.values[name] = value
                return true
            end,
        },
        InCombatLockdown = function()
            return s.combat
        end,
        UnitIsPlayer = function()
            return s.player
        end,
        UnitCanAttack = function()
            return s.enemy
        end,
        CreateFrame = function(_, _, parent)
            if parent == pm or parent == tm then
                local outline = region()
                outline.points = {}
                function outline:CreateTexture(...)
                    return parent:CreateTexture(...)
                end
                parent.outline = outline
                return outline
            end
            local f = H.newEventFrame()
            s.frames[#s.frames + 1] = f
            return f
        end,
        hooksecurefunc = function(obj, method, hook)
            if type(obj) == "string" then
                obj, method, hook = _G, obj, method
            end
            s.hooks = s.hooks + 1
            local original = obj[method]
            obj[method] = function(...)
                original(...)
                hook(...)
            end
        end,
    }, function()
        local M = {
            DeferUntilOutOfCombat = function(key, callback)
                if s.combat then
                    s.pending[key] = callback
                else
                    s.pending[key] = nil
                    callback()
                end
            end,
        }
        H.loadAddonFile("Modules/Frames.lua", M)
        fn(M.Frames, s, p, t, pm, tm, tc)
    end)
end

test("unit frame defaults are inert", function()
    withFrames(function(F, s)
        F.Initialize()
        eq(s.hooks, 0)
        eq(#s.frames, 0)
        eq(s.writes, 0)
    end)
end)

test("native nameplate modes use exact player CVar and release combat events", function()
    withFrames(function(F, s)
        MurgleDB.frames.enemyNameplates = "combat"
        MurgleDB.frames.friendlyNameplates = "hidden"
        F.ApplyAll()
        eq(s.values.nameplateShowEnemies, "0")
        eq(s.values.nameplateShowFriendlyPlayers, "0")
        eq(s.values.nameplateShowFriendlyNpcs, "1")
        eq(s.frames[1].events.PLAYER_REGEN_DISABLED, true)
        s.combat = true
        s.frames[1].scripts.OnEvent(nil, "PLAYER_REGEN_DISABLED")
        eq(s.values.nameplateShowEnemies, "1")
        eq(s.values.nameplateShowFriendlyPlayers, "0")
        MurgleDB.frames.enemyNameplates = "blizzard"
        MurgleDB.frames.friendlyNameplates = "blizzard"
        F.ApplyAll()
        eq(s.values.nameplateShowEnemies, "1")
        eq(s.values.nameplateShowFriendlyPlayers, "1")
        eq(next(s.frames[1].events), nil)
    end)
end)

test("native overrides survive reload ownership and respect external edits on release", function()
    withFrames(function(F, s)
        MurgleDB.frames.enemyNameplates = "hidden"
        F.ApplyAll()
        local M = {
            DeferUntilOutOfCombat = function(_, f)
                f()
            end,
        }
        H.loadAddonFile("Modules/Frames.lua", M)
        MurgleDB.frames.enemyNameplates = "blizzard"
        M.Frames.ApplyAll()
        eq(s.values.nameplateShowEnemies, "1")
        MurgleDB.frames.friendlyNamesOnly = true
        MurgleDB.frames.enemyClassColours = true
        M.Frames.ApplyAll()
        eq(s.values.nameplateShowOnlyNameForFriendlyPlayerUnits, "1")
        eq(s.values.nameplateShowClassColor, "0")
        s.values.nameplateShowClassColor = "0"
        MurgleDB.frames = {}
        M.Frames.ApplyAll()
        eq(s.values.nameplateShowOnlyNameForFriendlyPlayerUnits, "0")
        eq(s.values.nameplateShowClassColor, "0")
    end)
end)

test("missing or restricted native CVar skips only that control", function()
    withFrames(function(F, s)
        s.values.nameplateShowFriendlyPlayers = nil
        MurgleDB.frames.enemyNameplates, MurgleDB.frames.friendlyNameplates = "hidden", "combat"
        F.ApplyAll()
        eq(s.values.nameplateShowEnemies, "0")
        eq(#s.frames, 0)
        eq(F.NativeAvailable("friendlyNameplates"), false)
    end)
end)

test("clean frames use native bar header anchors and restore captured artwork", function()
    withFrames(function(F, s, p, t, pm, tm, tc)
        local levelParent = PlayerLevelText.points[1][2]
        MurgleDB.frames.cleanPlayer, MurgleDB.frames.cleanTarget = true, true
        F.ApplyAll()
        eq(p.PlayerFrameContainer.PlayerPortrait.shown, false)
        eq(p.PlayerFrameContainer.FrameTexture.alpha, 0)
        eq(pm.LevelBackgroundCircle.alpha, 0)
        eq(PlayerLevelText.points[1][2], pm.HealthBarsContainer)
        eq(tm.LevelText.points[1][2], tm.HealthBarsContainer)
        eq(tc.HighLevelTexture.points[1][2], tm.LevelText)
        eq(t.TargetFrameContainer.BossPortraitFrameTexture.alpha, 0)
        eq(p.PlayerFrameContainer.AlternatePowerFrameTexture.alpha, 0)
        eq(p.PlayerFrameContainer.VehicleFrameTexture.alpha, 0)
        eq(p.PlayerFrameContainer.FrameFlash.vertex[4], 0)
        eq(pm.PvpBackgroundCircle.alpha, 0)
        eq(tc.PvpBackgroundCircle.alpha, 0)
        eq(PlayerLevelText.fontObject, "small")
        eq(tm.LevelText.fontObject, "small")
        MurgleDB.frames.cleanPlayer, MurgleDB.frames.cleanTarget = false, false
        F.ApplyAll()
        eq(p.PlayerFrameContainer.PlayerPortrait.shown, true)
        eq(p.PlayerFrameContainer.FrameTexture.alpha, 1)
        eq(PlayerLevelText.points[1][2], levelParent)
        eq(PlayerLevelText.fontObject, "large")
        eq(t.TargetFrameContainer.BossPortraitFrameTexture.alpha, 1)
        eq(p.PlayerFrameContainer.FrameFlash.vertex[4], 1)
        eq(s.hooks, 1)
    end)
end)

test("clean frame changes defer in combat and apply latest setting", function()
    withFrames(function(F, s, p)
        s.combat = true
        MurgleDB.frames.cleanPlayer = true
        F.ApplyAll()
        eq(p.PlayerFrameContainer.PlayerPortrait.shown, true)
        s.combat = false
        for _, callback in pairs(s.pending) do
            callback()
        end
        eq(p.PlayerFrameContainer.PlayerPortrait.shown, false)
    end)
end)

test("faction icon uses one target-only lazy hook and returns native control", function()
    withFrames(function(F, s, _, t, _, _, tc)
        MurgleDB.frames.enemyFactionOnly = true
        F.ApplyAll()
        eq(s.hooks, 1)
        eq(tc.PvpBackgroundIcon.shown, false)
        s.player, s.enemy = true, true
        t:CheckFaction()
        eq(tc.PvpBackgroundIcon.shown, true)
        s.enemy = false
        t:CheckFaction()
        eq(tc.PvpBackgroundIcon.shown, false)
        t.unit = "focus"
        t:CheckFaction()
        eq(tc.PvpBackgroundIcon.shown, true)
        t.unit = "target"
        MurgleDB.frames.enemyFactionOnly = false
        F.ApplyAll()
        eq(tc.PvpBackgroundIcon.shown, true)
        t:CheckFaction()
        eq(tc.PvpBackgroundIcon.shown, true)
        eq(#s.frames, 0)
    end)
end)

test("clean target does not restore an obsolete level badge visibility", function()
    withFrames(function(F, _, _, _, _, main)
        MurgleDB.frames.cleanTarget = true
        F.ApplyAll()
        main.LevelBackgroundCircle:Hide()
        MurgleDB.frames.cleanTarget = false
        F.ApplyAll()
        eq(main.LevelBackgroundCircle.shown, false)
    end)
end)

test("unit frame page applies native modes and Disable all relinquishes them", function()
    local UI = dofile("tests/ui_helpers.lua")
    local values = { nameplateShowEnemies = "1", nameplateShowFriendlyPlayers = "1" }
    H.withGlobals({
        C_CVar = {
            GetCVarInfo = function(key)
                return values[key], "1", true, false, false, false, false
            end,
            SetCVar = function(key, value)
                values[key] = value
                return true
            end,
        },
    }, function()
        UI.withAddon(function(M, state)
            M.Settings.Show()
            local start = #state.frames
            M.Settings.SelectCategory("Frames")
            local hidden
            for i = start + 1, #state.frames do
                local control = state.frames[i]
                for _, r in ipairs(control.regions) do
                    if r.text == M.L.HIDDEN and not hidden then
                        hidden = control
                    end
                end
            end
            assert(hidden, "native nameplate choices missing")
            hidden.scripts.OnClick(hidden)
            eq(values.nameplateShowEnemies, "0")
            eq(values.nameplateShowFriendlyPlayers, "1")
            MurgleDB.frames.enemyNameplates = "blizzard"
            MurgleDB.frames.friendlyNameplates = "blizzard"
            M.Frames.ApplyAll()
            eq(values.nameplateShowEnemies, "1")
            eq(MurgleDB.frames.enemyNameplates, "blizzard")
        end)
    end)
end)

test("clean player status preserves current native tint and restores after repeated hidden updates", function()
    withFrames(function(F, s, p, t, pm)
        PlayerFrame_UpdateStatus = function()
            if s.noTint then
                pm.StatusTexture:Hide()
            else
                pm.StatusTexture:SetVertexColor(1, 0.25, 0, 1)
                pm.StatusTexture:Show()
            end
        end
        MurgleDB.frames.cleanPlayer = true
        F.ApplyAll()
        PlayerFrame_UpdateStatus()
        eq(pm.StatusTexture.shown, false)
        s.noTint = true
        PlayerFrame_UpdateStatus()
        MurgleDB.frames.cleanPlayer = false
        F.ApplyAll()
        eq(pm.StatusTexture.vertex[4], 1)
        s.noTint = false
        PlayerFrame_UpdateStatus()
        eq(pm.StatusTexture.vertex[4], 1)
        eq(s.hooks, 2)
    end)
end)

test("compact frames remove outlines while retaining names and reversible artwork", function()
    withFrames(function(F, s, p, t, pm, tm)
        pm.PvpBackgroundIcon.alpha = 0.6
        tm.ReputationColor.alpha = 0.8
        MurgleDB.frames.cleanPlayer, MurgleDB.frames.cleanTarget = true, true
        F.ApplyAll()
        eq(pm.PvpBackgroundIcon.alpha, 0)
        eq(tm.ReputationColor.alpha, 0)
        eq(tm.Name.alpha, 1)
        eq(PlayerName.alpha, 1)
        eq(PlayerLevelText.alpha, 0)
        eq(#pm.edges, 0)
        eq(#tm.edges, 0)
        MurgleDB.frames.cleanPlayer, MurgleDB.frames.cleanTarget = false, false
        F.ApplyAll()
        eq(pm.PvpBackgroundIcon.alpha, 0.6)
        eq(tm.ReputationColor.alpha, 0.8)
        eq(PlayerLevelText.alpha, 1)
    end)
end)

test("clean player name survives native art updates and defers correction in combat", function()
    withFrames(function(F, s, _, _, main)
        PlayerFrame_UpdatePlayerNameTextAnchor = function()
            local x = PlayerFrame.unit == "vehicle" and 96 or 88
            PlayerName:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", x, -27)
        end
        PlayerName:ClearAllPoints()
        PlayerFrame_UpdatePlayerNameTextAnchor()
        F.ApplyAll()
        eq(s.hooks, 0)
        MurgleDB.frames.cleanPlayer = true
        F.ApplyAll()
        PlayerFrame_UpdatePlayerNameTextAnchor()
        eq(#PlayerName.points, 1)
        eq(PlayerName.points[1][1], "BOTTOMLEFT")
        eq(PlayerName.points[1][2], main.HealthBarsContainer)
        s.combat = true
        PlayerFrame_UpdatePlayerNameTextAnchor()
        eq(#PlayerName.points, 2)
        eq(PlayerName.points[2][1], "TOPLEFT")
        s.combat = false
        for key, callback in pairs(s.pending) do
            s.pending[key] = nil
            callback()
        end
        eq(PlayerName.points[1][1], "BOTTOMLEFT")
        s.combat = true
        PlayerFrame.unit = "vehicle"
        PlayerFrame_UpdatePlayerNameTextAnchor()
        MurgleDB.frames.cleanPlayer = false
        F.ApplyAll()
        s.combat = false
        for key, callback in pairs(s.pending) do
            s.pending[key] = nil
            callback()
        end
        eq(#PlayerName.points, 1)
        eq(PlayerName.points[1][1], "TOPLEFT")
        eq(PlayerName.points[1][4], 96, "disable must restore current vehicle placement")
        PlayerFrame.unit = "player"
        PlayerFrame_UpdatePlayerNameTextAnchor()
        eq(PlayerName.points[1][4], 88)
        eq(next(s.pending), nil)
        eq(s.hooks, 1)
    end)
end)

test("hide player name is independent reversible and combat deferred", function()
    withFrames(function(F, s, p, t, pm, tm)
        PlayerName.alpha = 0.7
        MurgleDB.frames.hidePlayerName = true
        s.combat = true
        F.ApplyAll()
        eq(PlayerName.alpha, 0.7)
        s.combat = false
        for _, callback in pairs(s.pending) do
            callback()
        end
        eq(PlayerName.alpha, 0)
        eq(tm.Name.alpha, 1)
        eq(p.PlayerFrameContainer.PlayerPortrait.shown, true)
        MurgleDB.frames.cleanPlayer = true
        F.ApplyAll()
        MurgleDB.frames.cleanPlayer = false
        F.ApplyAll()
        eq(PlayerName.alpha, 0)
        MurgleDB.frames.hidePlayerName = false
        F.ApplyAll()
        eq(PlayerName.alpha, 0.7)
        eq(s.hooks, 0)
    end)
end)

test("compact player stops native rest animation and restores latest resting state", function()
    withFrames(function(F, s, p)
        local rest = region()
        local animation = { playing = true }
        function animation:Play()
            self.playing = true
        end
        function animation:Stop()
            self.playing = false
        end
        rest.PlayerRestLoopAnim = animation
        p.PlayerFrameContent.PlayerFrameContentContextual = { PlayerRestLoop = rest }
        PlayerFrame_UpdatePlayerRestLoop = function(state)
            if state then
                rest:Show()
                animation:Play()
            else
                rest:Hide()
                animation:Stop()
            end
        end
        MurgleDB.frames.cleanPlayer = true
        F.ApplyAll()
        eq(rest.shown, false)
        eq(animation.playing, false)
        PlayerFrame_UpdatePlayerRestLoop(true)
        eq(rest.shown, false)
        eq(animation.playing, false)
        PlayerFrame_UpdatePlayerRestLoop(false)
        MurgleDB.frames.cleanPlayer = false
        F.ApplyAll()
        eq(rest.shown, false, "disable must not restore stale resting state")
        eq(animation.playing, false)
        MurgleDB.frames.cleanPlayer = true
        F.ApplyAll()
        PlayerFrame_UpdatePlayerRestLoop(true)
        MurgleDB.frames.cleanPlayer = false
        F.ApplyAll()
        eq(rest.shown, true)
        eq(animation.playing, true)
        eq(s.hooks, 1)
        eq(#s.frames, 0)
    end)
end)

test("compact target suppresses native reaction refresh through one shared faction hook", function()
    withFrames(function(F, s, p, t, pm, tm, tc)
        t.CheckFaction = function(self)
            tm.ReputationColor:SetAlpha(1)
            tm.ReputationColor:SetVertexColor(1, 0, 0, 1)
            tc.PvpBackgroundIcon:Show()
        end
        MurgleDB.frames.cleanTarget = true
        F.ApplyAll()
        t:CheckFaction()
        eq(tm.ReputationColor.alpha, 0)
        eq(tm.Name.alpha, 1)
        MurgleDB.frames.enemyFactionOnly = true
        F.ApplyAll()
        t:CheckFaction()
        eq(tc.PvpBackgroundIcon.shown, false)
        eq(s.hooks, 1)
        eq(#s.frames, 0)
        MurgleDB.frames.cleanTarget, MurgleDB.frames.enemyFactionOnly = false, false
        F.ApplyAll()
        t:CheckFaction()
        eq(tm.ReputationColor.alpha, 1)
        eq(tc.PvpBackgroundIcon.shown, true)
    end)
end)

test("retired class colours ignore old settings and restore owned native values once", function()
    withFrames(function(F, s)
        MurgleDB.frames.friendlyClassColours = true
        MurgleDB.frames.enemyClassColours = true
        MurgleDB.frames.nativeRestore = {
            friendlyClassColours = { prior = "0", last = "1" },
            enemyClassColours = { prior = "0", last = "1" },
        }
        s.values.nameplateShowFriendlyClassColor = "1"
        s.values.nameplateShowClassColor = "1"
        F.ApplyAll()
        eq(s.values.nameplateShowFriendlyClassColor, "0")
        eq(s.values.nameplateShowClassColor, "0")
        eq(MurgleDB.frames.nativeRestore, nil)
        eq(F.NativeAvailable("friendlyClassColours"), false)
        eq(F.NativeAvailable("enemyClassColours"), false)
        local writes = s.writes
        F.ApplyAll()
        eq(s.writes, writes)
        eq(s.hooks, 0)
        eq(#s.frames, 0)
    end)
end)

test("restoration uses native resting changes while disable waits for combat", function()
    withFrames(function(F, s, p)
        local rest = region()
        local animation = { playing = true }
        function animation:Play()
            self.playing = true
        end
        function animation:Stop()
            self.playing = false
        end
        rest.PlayerRestLoopAnim = animation
        p.PlayerFrameContent.PlayerFrameContentContextual = { PlayerRestLoop = rest }
        PlayerFrame_UpdatePlayerRestLoop = function(value)
            if value then
                rest:Show()
                animation:Play()
            else
                rest:Hide()
                animation:Stop()
            end
        end
        MurgleDB.frames.cleanPlayer = true
        F.ApplyAll()
        s.combat = true
        MurgleDB.frames.cleanPlayer = false
        F.ApplyAll()
        PlayerFrame_UpdatePlayerRestLoop(false)
        s.combat = false
        for _, callback in pairs(s.pending) do
            callback()
        end
        eq(rest.shown, false)
        eq(animation.playing, false)
    end)
end)

test("compact player level survives native colour alpha updates", function()
    withFrames(function(F, s)
        PlayerFrame_UpdateLevel = function()
            PlayerLevelText:SetAlpha(1)
        end
        MurgleDB.frames.cleanPlayer = true
        F.ApplyAll()
        PlayerFrame_UpdateLevel()
        eq(PlayerLevelText.alpha, 0)
        MurgleDB.frames.cleanPlayer = false
        F.ApplyAll()
        eq(PlayerLevelText.alpha, 1)
        PlayerFrame_UpdateLevel()
        eq(PlayerLevelText.alpha, 1)
    end)
end)

test("compact player hides status art before native animation can restore its alpha", function()
    withFrames(function(F, s, p, _, pm)
        local corner = region()
        p.PlayerFrameContent.PlayerFrameContentContextual = { PlayerPortraitCornerIcon = corner }
        PlayerFrame_UpdateStatus = function()
            pm.StatusTexture:SetVertexColor(1, 0.88, 0.25, 1)
            pm.StatusTexture:Show()
        end
        MurgleDB.frames.cleanPlayer = true
        F.ApplyAll()
        PlayerFrame_UpdateStatus()
        eq(pm.StatusTexture.shown, false)
        eq(corner.alpha, 0)
        pm.StatusTexture:SetAlpha(1)
        eq(pm.StatusTexture.shown, false)
        MurgleDB.frames.cleanPlayer = false
        F.ApplyAll()
        eq(pm.StatusTexture.shown, true)
        eq(corner.alpha, 1)
    end)
end)

test("compact target suppresses faction and leader and releases to independent faction mode", function()
    withFrames(function(F, s, _, t, _, _, tc)
        tc.LeaderIcon, tc.GuideIcon = region(), region()
        s.player, s.enemy = true, true
        MurgleDB.frames.cleanTarget = true
        MurgleDB.frames.enemyFactionOnly = true
        F.ApplyAll()
        eq(tc.PvpBackgroundIcon.alpha, 0)
        eq(tc.LeaderIcon.alpha, 0)
        eq(tc.GuideIcon.alpha, 0)
        t:CheckFaction()
        eq(tc.PvpBackgroundIcon.alpha, 0)
        s.enemy = false
        t:CheckFaction()
        MurgleDB.frames.cleanTarget = false
        F.ApplyAll()
        eq(tc.PvpBackgroundIcon.alpha, 1)
        eq(tc.PvpBackgroundIcon.shown, false)
        eq(tc.LeaderIcon.alpha, 1)
        s.enemy = true
        t:CheckFaction()
        eq(tc.PvpBackgroundIcon.shown, true)
    end)
end)

test("compact target of target is independent deferred reversible and leaves bars untouched", function()
    withFrames(function(F, s, p, t)
        local tot = { Portrait = region(), FrameTexture = region(), HealthBar = region(), ManaBar = region() }
        t.totFrame = tot
        tot.Portrait.alpha, tot.FrameTexture.alpha = 0.7, 0.8
        MurgleDB.frames.cleanTargetOfTarget = true
        s.combat = true
        F.ApplyAll()
        eq(tot.Portrait.alpha, 0.7)
        s.combat = false
        for key, callback in pairs(s.pending) do
            s.pending[key] = nil
            callback()
        end
        eq(tot.Portrait.shown, false)
        eq(tot.FrameTexture.alpha, 0)
        eq(tot.HealthBar.alpha, 1)
        eq(tot.ManaBar.alpha, 1)
        eq(t.TargetFrameContainer.Portrait.shown, true)
        MurgleDB.frames.cleanTargetOfTarget = false
        F.ApplyAll()
        eq(tot.Portrait.alpha, 0.7)
        eq(tot.FrameTexture.alpha, 0.8)
        eq(s.hooks, 0)
    end)
end)

test("compact player release preserves native status and level changes during combat", function()
    withFrames(function(F, s, _, _, pm)
        PlayerFrame_UpdateStatus = function()
            if s.resting then
                pm.StatusTexture:Show()
            else
                pm.StatusTexture:Hide()
            end
        end
        PlayerFrame_UpdateLevel = function()
            PlayerLevelText:SetAlpha(0.8)
        end
        s.resting = true
        MurgleDB.frames.cleanPlayer = true
        F.ApplyAll()
        s.combat = true
        MurgleDB.frames.cleanPlayer = false
        F.ApplyAll()
        s.resting = false
        PlayerFrame_UpdateStatus()
        PlayerFrame_UpdateLevel()
        s.combat = false
        for key, callback in pairs(s.pending) do
            s.pending[key] = nil
            callback()
        end
        eq(pm.StatusTexture.shown, false)
        eq(PlayerLevelText.alpha, 0.8)
    end)
end)

test("independent faction choice releases native visibility while compact target stays enabled", function()
    withFrames(function(F, s, _, t, _, _, tc)
        MurgleDB.frames.cleanTarget = true
        MurgleDB.frames.enemyFactionOnly = true
        F.ApplyAll()
        eq(tc.PvpBackgroundIcon.shown, false)
        MurgleDB.frames.enemyFactionOnly = false
        F.ApplyAll()
        eq(tc.PvpBackgroundIcon.shown, true)
        eq(tc.PvpBackgroundIcon.alpha, 0)
        MurgleDB.frames.cleanTarget = false
        F.ApplyAll()
        eq(tc.PvpBackgroundIcon.shown, true)
        eq(tc.PvpBackgroundIcon.alpha, 1)
    end)
end)

test("compact target of target skips incomplete artwork and can retry explicitly", function()
    withFrames(function(F, s, _, t)
        local portrait, art = region(), region()
        t.totFrame = { Portrait = portrait, FrameTexture = art }
        local setAlpha = art.SetAlpha
        art.SetAlpha = nil
        MurgleDB.frames.cleanTargetOfTarget = true
        F.ApplyAll()
        eq(portrait.alpha, 1)
        art.SetAlpha = setAlpha
        F.ApplyAll()
        eq(portrait.shown, false)
        eq(art.alpha, 0)
        s.combat = true
        MurgleDB.frames.cleanTargetOfTarget = false
        F.ApplyAll()
        MurgleDB.frames.cleanTargetOfTarget = true
        F.ApplyAll()
        s.combat = false
        for key, callback in pairs(s.pending) do
            s.pending[key] = nil
            callback()
        end
        eq(art.alpha, 0)
    end)
end)

test("compact player preserves status intent when native hate-list branch does not write visibility", function()
    withFrames(function(F, s, _, _, pm)
        PlayerFrame_UpdateStatus = function()
            if not s.hateOnly then
                pm.StatusTexture:Show()
            end
        end
        MurgleDB.frames.cleanPlayer = true
        F.ApplyAll()
        PlayerFrame_UpdateStatus()
        eq(pm.StatusTexture.shown, false)
        s.hateOnly = true
        PlayerFrame_UpdateStatus()
        MurgleDB.frames.cleanPlayer = false
        F.ApplyAll()
        eq(pm.StatusTexture.shown, true)
    end)
end)

test("compact target of target survives native portrait health tint and preserves hidden origins", function()
    withFrames(function(F, s, _, t)
        local portrait, art = region(), region()
        t.totFrame = { Portrait = portrait, FrameTexture = art }
        function t.totFrame:HealthCheck()
            self.Portrait:SetVertexColor(1, 0, 0, 1)
            self.Portrait:SetAlpha(1)
        end
        MurgleDB.frames.cleanTargetOfTarget = true
        F.ApplyAll()
        t.totFrame:HealthCheck()
        eq(portrait.shown, false)
        MurgleDB.frames.cleanTargetOfTarget = false
        F.ApplyAll()
        eq(portrait.shown, true)
        eq(portrait.vertex[2], 0)
        portrait:Hide()
        MurgleDB.frames.cleanTargetOfTarget = true
        F.ApplyAll()
        MurgleDB.frames.cleanTargetOfTarget = false
        F.ApplyAll()
        eq(portrait.shown, false)
    end)
end)
