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
    local s = { frames = {}, hooks = 0, writes = 0, combat = false, pending = {} }
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
    local tc = { HighLevelTexture = region(), PvpBackgroundCircle = region(), PvpBackgroundIcon = region() }
    local p = {
        alpha = 1,
        mouse = true,
        PlayerFrameContainer = {
            PlayerPortrait = region(),
            FrameTexture = region(),
            VehicleFrameTexture = region(),
            AlternatePowerFrameTexture = region(),
            FrameFlash = region(),
        },
        PlayerFrameContent = { PlayerFrameContentMain = pm },
    }
    function p:GetAlpha()
        return self.alpha
    end
    function p:SetAlpha(v)
        self.alpha = v
    end
    function p:EnableMouse(v)
        self.mouse = v
    end

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
    local focus = {
        unit = "focus",
        TargetFrameContainer = {
            Portrait = region(),
            FrameTexture = region(),
            BossPortraitFrameTexture = region(),
            Flash = region(),
        },
        TargetFrameContent = {
            TargetFrameContentMain = {
                LevelBackgroundCircle = region(),
                LevelText = region(),
                Name = region(),
                HealthBarsContainer = region(),
                ManaBar = region(),
                ReputationColor = region(),
            },
            TargetFrameContentContextual = {
                HighLevelTexture = region(),
                PvpBackgroundCircle = region(),
                PvpBackgroundIcon = region(),
            },
        },
    }
    local tot = {
        Portrait = region(),
        FrameTexture = region(),
    }
    t.totFrame = tot

    H.withGlobals({
        GameFontNormalSmall = "small",
        PlayerFrame_UpdateStatus = false,
        PlayerFrame_UpdateLevel = false,
        PlayerFrame_UpdatePlayerRestLoop = false,
        PlayerFrame_UpdatePlayerNameTextAnchor = false,
        MurgleDB = { frames = { hidePlayerName = false, hidePlayerFrame = false, compactFrames = false } },
        PlayerFrame = p,
        TargetFrame = t,
        FocusFrame = focus,
        PlayerLevelText = region(),
        PlayerName = region(),
        InCombatLockdown = function()
            return s.combat
        end,
        hooksecurefunc = function(obj, method, hook)
            if type(obj) == "string" then
                obj, method, hook = _G, obj, method
            end
            s.hooks = s.hooks + 1
            local original = obj[method]
            obj[method] = function(...)
                if type(original) == "function" then
                    original(...)
                end
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
        fn(M.Frames, s, p, t, focus, pm, tm, tc)
    end)
end

test("unit frame defaults are inert", function()
    withFrames(function(F, s)
        F.Initialize()
        eq(s.hooks, 0)
        eq(#s.frames, 0)
        eq(s.writes, 0)
        eq(next(s.pending), nil)
    end)
end)

test("hide player name is independent reversible and combat deferred", function()
    withFrames(function(F, s)
        MurgleDB.frames.hidePlayerName = true
        F.ApplyPlayerName()
        eq(PlayerName.alpha, 0)

        s.combat = true
        MurgleDB.frames.hidePlayerName = false
        F.ApplyPlayerName()
        eq(PlayerName.alpha, 0)
        s.combat = false
        s.pending["frames.playerName"]()
        eq(PlayerName.alpha, 1)
    end)
end)

test("hide player frame is independent reversible and combat deferred", function()
    withFrames(function(F, s, p)
        MurgleDB.frames.hidePlayerFrame = true
        F.ApplyPlayerFrame()
        eq(p.alpha, 0)
        eq(p.mouse, false)

        s.combat = true
        MurgleDB.frames.hidePlayerFrame = false
        F.ApplyPlayerFrame()
        eq(p.alpha, 0)
        eq(p.mouse, false)
        s.combat = false
        s.pending["frames.playerFrame"]()
        eq(p.alpha, 1)
        eq(p.mouse, true)
    end)
end)

test("compact frames applies to player target and focus while keeping bar borders", function()
    withFrames(function(F, s, p, t, focus, pm, tm, tc)
        local levelParent = PlayerLevelText.points[1][2]
        MurgleDB.frames.compactFrames = true
        F.ApplyCompact()

        -- Player Frame compacted
        eq(p.PlayerFrameContainer.PlayerPortrait.shown, false)
        eq(p.PlayerFrameContainer.FrameTexture.alpha, 0)
        eq(pm.LevelBackgroundCircle.alpha, 0)
        eq(PlayerLevelText.points[1][2], pm.HealthBarsContainer)
        eq(PlayerLevelText.fontObject, "small")

        -- Target Frame compacted
        eq(t.TargetFrameContainer.Portrait.shown, false)
        eq(t.TargetFrameContainer.FrameTexture.alpha, 0)
        eq(tm.LevelText.points[1][2], tm.HealthBarsContainer)
        eq(tc.HighLevelTexture.points[1][2], tm.LevelText)
        eq(t.TargetFrameContainer.BossPortraitFrameTexture.alpha, 0)

        -- Focus Frame compacted
        eq(focus.TargetFrameContainer.Portrait.shown, false)
        eq(focus.TargetFrameContainer.FrameTexture.alpha, 0)

        -- Target of Target compacted
        eq(t.totFrame.Portrait.shown, false)
        eq(t.totFrame.FrameTexture.alpha, 0)

        -- Reversible on disable
        MurgleDB.frames.compactFrames = false
        F.ApplyCompact()
        eq(p.PlayerFrameContainer.PlayerPortrait.shown, true)
        eq(p.PlayerFrameContainer.FrameTexture.alpha, 1)
        eq(pm.LevelBackgroundCircle.alpha, 1)
        eq(PlayerLevelText.points[1][2], levelParent)
        eq(PlayerLevelText.fontObject, "large")
        eq(t.TargetFrameContainer.Portrait.shown, true)
        eq(t.TargetFrameContainer.FrameTexture.alpha, 1)
        eq(focus.TargetFrameContainer.Portrait.shown, true)
        eq(t.totFrame.Portrait.shown, true)
        eq(t.totFrame.FrameTexture.alpha, 1)
    end)
end)

test("compact frame changes defer in combat and apply latest setting", function()
    withFrames(function(F, s, p)
        s.combat = true
        MurgleDB.frames.compactFrames = true
        F.ApplyCompact()
        eq(p.PlayerFrameContainer.PlayerPortrait.shown, true)
        s.combat = false
        for _, callback in pairs(s.pending) do
            callback()
        end
        eq(p.PlayerFrameContainer.PlayerPortrait.shown, false)
    end)
end)
