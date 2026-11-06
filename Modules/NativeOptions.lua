local _, Murgle = ...
local NativeOptions = {}
Murgle.NativeOptions = NativeOptions

-- Bounds are conservative input limits for these controls, not engine limits.
NativeOptions.Groups = {
    { "HDR_OUTPUT", { "HDROutput", 0, 1, true }, { "RenderFormat", 1, 3, true }, { "HDRFactor", 1, 10 } },
    {
        "HDR_BRIGHTNESS",
        { "useHDRBrightness", 0, 1, true },
        { "HDRBrightness", 0, 2000 },
        { "useHDRPeakBrightness", 0, 1, true },
        { "HDRPeakBrightness", 0, 2000 },
    },
    {
        "WORLD_EFFECTS",
        { "groundEffectDensity", 0, 256, true },
        { "groundEffectDist", 0, 300 },
        { "ResampleAlwaysSharpen", 0, 1, true },
        { "ffxGlow", 0, 1, true },
        { "ffxDeath", 0, 1, true },
    },
}
local entries = { showQuestLevel = { "showQuestLevel", 0, 1, true } }
for _, group in ipairs(NativeOptions.Groups) do
    for i = 2, #group do
        entries[group[i][1]] = group[i]
    end
end

function NativeOptions.Read(name)
    if not entries[name] or not C_CVar or type(C_CVar.GetCVarInfo) ~= "function" then
        return
    end
    local value, _, _, _, locked, secure, readOnly = C_CVar.GetCVarInfo(name)
    local number = type(value) == "string" and tonumber(value)
    if not number or not (number > -math.huge and number < math.huge) then
        return
    end
    return value, locked == false and secure == false and readOnly == false
end

function NativeOptions.Set(name, value)
    local entry = entries[name]
    local _, writable = NativeOptions.Read(name)
    local number = (type(value) == "string" or type(value) == "number") and tonumber(value)
    if
        not entry
        or not writable
        or not number
        or not (number >= entry[2] and number <= entry[3])
        or entry[4] and number ~= math.floor(number)
        or not InCombatLockdown
        or InCombatLockdown() ~= false
        or type(C_CVar.SetCVar) ~= "function"
    then
        return
    end
    local ok = pcall(C_CVar.SetCVar, name, tostring(number))
    if ok then
        return NativeOptions.Read(name)
    end
end

function NativeOptions.Reset(name)
    if C_CVar and type(C_CVar.GetCVarDefault) == "function" then
        return NativeOptions.Set(name, C_CVar.GetCVarDefault(name))
    end
end
