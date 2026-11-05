local _, Murgle = ...
local SpellRanks = {}
Murgle.SpellRanks = SpellRanks
local events
local warned = {}
local function public(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end
local function integer(value, minimum, maximum)
    return public(value)
        and type(value) == "number"
        and value >= minimum
        and value <= maximum
        and value == math.floor(value)
end
local function enabled()
    return MurgleDB and MurgleDB.automation and MurgleDB.automation.warnLowRank == true
end
function SpellRanks.ParseRank(text)
    if not public(text) or type(text) ~= "string" then
        return
    end
    -- Numeric localized rank labels end in one decimal integer. Roman numerals,
    -- ranges, decimals, negative ranks and labels with other numbers are omitted.
    local digits = text:match("^[^%d%+%-%./]*([1-9]%d*)%s*$")
    local rank = digits and tonumber(digits)
    if integer(rank, 1, 1000) then
        return rank
    end
end
local function scan()
    if not enabled() or type(InCombatLockdown) ~= "function" or InCombatLockdown() ~= false then
        return
    end
    if
        not C_SpellBook
        or not C_Spell
        or not Enum
        or not Enum.SpellBookSpellBank
        or not Enum.SpellBookItemType
        or Enum.SpellBookSpellBank.Player == nil
        or Enum.SpellBookItemType.Spell == nil
        or type(C_SpellBook.GetNumSpellBookSkillLines) ~= "function"
        or type(C_SpellBook.GetSpellBookSkillLineInfo) ~= "function"
        or type(C_SpellBook.GetSpellBookItemName) ~= "function"
        or type(C_SpellBook.GetSpellBookItemInfo) ~= "function"
        or type(C_Spell.GetSpellName) ~= "function"
        or type(C_Spell.GetSpellSubtext) ~= "function"
        or type(GetActionInfo) ~= "function"
        or not DEFAULT_CHAT_FRAME
        or type(DEFAULT_CHAT_FRAME.AddMessage) ~= "function"
    then
        return
    end
    local count = C_SpellBook.GetNumSpellBookSkillLines()
    if not integer(count, 0, 100) then
        return
    end
    local bank, highest, learned, visited = Enum.SpellBookSpellBank.Player, {}, {}, {}
    local total = 0
    for line = 1, count do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if not public(info) or type(info) ~= "table" then
            return
        end
        local offset, size = info.itemIndexOffset, info.numSpellBookItems
        if not integer(offset, 0, 4096) or not integer(size, 0, 4096) or offset + size > 4096 then
            return
        end
        total = total + size
        if total > 4096 then
            return
        end
        if
            public(info.shouldHide)
            and info.shouldHide == false
            and public(info.offSpecID)
            and info.offSpecID == nil
        then
            for index = offset + 1, offset + size do
                if visited[index] then
                    return
                end
                visited[index] = true
                local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
                if
                    public(item)
                    and type(item) == "table"
                    and public(item.itemType)
                    and item.itemType == Enum.SpellBookItemType.Spell
                    and public(item.isPassive)
                    and item.isPassive == false
                    and public(item.isOffSpec)
                    and item.isOffSpec == false
                    and integer(item.spellID, 1, 2147483647)
                    and public(item.actionID)
                    and item.actionID == item.spellID
                then
                    local name, subtext = C_SpellBook.GetSpellBookItemName(index, bank)
                    local rank = SpellRanks.ParseRank(subtext)
                    if public(name) and type(name) == "string" and name ~= "" and rank then
                        learned[item.spellID] = { name = name, rank = rank }
                        highest[name] = math.max(highest[name] or 0, rank)
                    end
                end
            end
        end
    end
    local current, slots, emitted = {}, {}, {}
    local prefixes = {
        "ActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarLeftButton",
        "MultiBarRightButton",
        "MultiBar5Button",
        "MultiBar6Button",
        "MultiBar7Button",
    }
    for _, prefix in ipairs(prefixes) do
        for index = 1, 12 do
            local button = _G[prefix .. index]
            if
                button
                and type(button.IsVisible) == "function"
                and button:IsVisible() == true
                and integer(button.action, 1, 2147483647)
            then
                slots[button.action] = true
            end
        end
    end
    for slot in pairs(slots) do
        local kind, id = GetActionInfo(slot)
        if public(kind) and kind == "spell" and integer(id, 1, 2147483647) and learned[id] then
            local name, subtext = C_Spell.GetSpellName(id), C_Spell.GetSpellSubtext(id)
            local rank = SpellRanks.ParseRank(subtext)
            local known = learned[id]
            if public(name) and name == known.name and rank == known.rank and highest[name] > rank then
                local signature = tostring(id) .. ":" .. rank .. ":" .. highest[name]
                current[slot] = signature
                if warned[slot] ~= signature and not emitted[signature] then
                    emitted[signature] = true
                    DEFAULT_CHAT_FRAME:AddMessage(string.format(Murgle.L.WARN_LOW_RANK, name, rank, highest[name]))
                end
            end
        end
    end
    warned = current
end
function SpellRanks.Check()
    if not enabled() or type(InCombatLockdown) ~= "function" then
        return
    end
    if InCombatLockdown() then
        if type(Murgle.DeferUntilOutOfCombat) == "function" then
            Murgle.DeferUntilOutOfCombat("spellRanks.check", scan)
        end
    else
        scan()
    end
end
function SpellRanks.ApplyAll()
    if not enabled() then
        warned = {}
        if events then
            events:UnregisterEvent("SPELLS_CHANGED")
        end
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", SpellRanks.Check)
    end
    events:RegisterEvent("SPELLS_CHANGED")
end
function SpellRanks.Initialize()
    SpellRanks.ApplyAll()
end
