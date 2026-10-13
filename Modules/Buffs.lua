local _, Murgle = ...
local Buffs = {}
Murgle.Buffs = Buffs
local owned, prior, last
local hooked = {}

local function usable(button)
    return button
        and type(button.IsProtected) == "function"
        and not button:IsProtected()
        and type(button.GetAlpha) == "function"
        and type(button.SetAlpha) == "function"
        and type(button.HookScript) == "function"
        and type(button.IsMouseOver) == "function"
end

local function update(button)
    if MurgleDB.interface.buffTriangleMouseover ~= true or button ~= owned or not usable(button) then
        return
    end
    local alpha = button:IsMouseOver() and prior or 0
    if button:GetAlpha() ~= alpha then
        button:SetAlpha(alpha)
    end
    last = alpha
end

function Buffs.ApplyAll()
    if MurgleDB.interface.buffTriangleMouseover ~= true then
        if owned and usable(owned) then
            if owned:GetAlpha() == last then
                owned:SetAlpha(prior)
            end
            owned, prior, last = nil, nil, nil
        end
        return
    end
    local button = owned or (BuffFrame and BuffFrame.CollapseAndExpandButton)
    if not usable(button) then
        return
    end
    if not owned then
        owned, prior = button, button:GetAlpha()
    end
    if not hooked[button] then
        hooked[button] = true
        button:HookScript("OnEnter", update)
        button:HookScript("OnLeave", update)
        button:HookScript("OnShow", update)
    end
    update(button)
end

function Buffs.Initialize()
    Buffs.ApplyAll()
end
