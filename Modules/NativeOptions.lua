local _, Murgle = ...
local NativeOptions = {}
Murgle.NativeOptions = NativeOptions

-- The native quest-level toggle is the only supported option here.
local entries = { showQuestLevel = { "showQuestLevel", 0, 1, true } }

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
