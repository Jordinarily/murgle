local function setup(enabled)
    local frames, hooks = {}, { registrations = 0, removals = 0, nativeHooks = 0 }
    local callbacks = {}
    EventRegistry = {
        RegisterCallback = function(_, event, callback, owner)
            eq(event, "ContainerFrameItemButton.EnterButton")
            assert(not callbacks[owner], "duplicate native enter callback")
            callbacks[owner] = callback
            hooks.registrations = hooks.registrations + 1
        end,
        UnregisterCallback = function(_, event, owner)
            eq(event, "ContainerFrameItemButton.EnterButton")
            callbacks[owner] = nil
            hooks.removals = hooks.removals + 1
        end,
        TriggerEvent = function(_, event, button)
            eq(event, "ContainerFrameItemButton.EnterButton")
            for owner, callback in pairs(callbacks) do
                callback(owner, button)
            end
        end,
    }
    hooks.OnEnter = function(button)
        EventRegistry:TriggerEvent("ContainerFrameItemButton.EnterButton", button)
    end
    local combat, alt, quality, link, guid = false, true, 2, "item:100", "Item-100-A"
    local addon = {}
    MurgleDB = { lootVendors = { disenchantClick = enabled } }
    InCombatLockdown = function()
        return combat
    end
    IsAltKeyDown = function()
        return alt
    end
    IsControlKeyDown = function()
        return false
    end
    IsShiftKeyDown = function()
        return false
    end
    C_SpellBook = {
        IsSpellKnown = function()
            return true
        end,
    }
    ItemLocation = {
        CreateFromBagAndSlot = function(_, bag, slot)
            return { bag = bag, slot = slot }
        end,
    }
    C_Item = {
        GetItemGUID = function()
            return guid
        end,
        GetItemInfo = function()
            return "Green", link, quality, nil, nil, nil, nil, nil, nil, nil, nil, 4
        end,
    }
    C_Container = {
        GetContainerItemInfo = function()
            return { hyperlink = link, quality = quality, isLocked = false, itemID = 100 }
        end,
    }
    ContainerFrameItemButtonMixin = {
        OnEnter = function() end,
        GetBagID = function(self)
            return self.bag
        end,
    }
    NUM_BAG_FRAMES = 4
    ContainerFrameItemButton_OnEnter = function() end
    hooksecurefunc = function(key, fn)
        hooks.nativeHooks = hooks.nativeHooks + 1
    end
    RegisterAttributeDriver = function(f, key, value)
        f.driver = value
    end
    CastSpellByID = function()
        error("insecure cast")
    end
    UseContainerItem = function()
        error("insecure item use")
    end
    StaticPopup_OnClick = function()
        error("confirmation accepted")
    end
    UIParent = {}
    CreateFrame = function(_, name, parent, template)
        local f = { scripts = {}, attrs = {}, template = template, events = {} }
        function f:SetScript(key, fn)
            self.scripts[key] = fn
        end
        function f:RegisterEvent(e)
            self.events[e] = true
        end
        function f:UnregisterAllEvents()
            self.events = {}
        end
        function f:SetAttribute(k, v)
            self.attrs[k] = v
        end
        function f:GetAttribute(k)
            return self.attrs[k]
        end
        function f:Hide()
            self.shown = false
        end
        function f:Show()
            self.shown = true
        end
        function f:ClearAllPoints() end
        function f:SetAllPoints(p)
            self.anchor = p
        end
        function f:SetFrameStrata() end
        function f:SetFrameLevel() end
        function f:RegisterForClicks() end
        frames[#frames + 1] = f
        return f
    end
    assert(loadfile("Modules/ItemActions.lua"))("Murgle", addon)
    addon.ItemActions:Initialize()
    local button = {
        bag = 0,
        GetBagID = ContainerFrameItemButtonMixin.GetBagID,
        GetID = function()
            return 1
        end,
        IsShown = function()
            return true
        end,
        IsMouseOver = function()
            return true
        end,
    }
    return addon,
        frames,
        hooks,
        button,
        function(c, a, q, l, g)
            combat, alt, quality, link, guid = c, a, q or quality, l or link, g or guid
        end
end

test("item actions disabled startup creates no hooks or frames", function()
    local _, frames, hooks = setup(false)
    eq(#frames, 0)
    eq(hooks.registrations, 0)
    eq(hooks.nativeHooks, 0)
end)

test("item actions arm only green carried gear and recheck identity before input", function()
    local _, frames, hooks, button, state = setup(true)
    hooks.OnEnter(button)
    local overlay = frames[1]
    eq(overlay.shown, true)
    eq(overlay.attrs["alt-type1"], "spell")
    eq(overlay.attrs.spell, 13262)
    eq(overlay.attrs["target-bag"], 0)
    state(false, true, 2, "item:101")
    overlay.scripts.PreClick(overlay, "LeftButton")
    eq(overlay.attrs["alt-type1"], nil)
    state(false, true, 3)
    hooks.OnEnter(button)
    eq(overlay.shown, false)
    button.bag = -1
    state(false, true, 2)
    hooks.OnEnter(button)
    eq(overlay.shown, false)
end)

test("item actions modifier release bag events disable and reenable clear targets", function()
    local addon, frames, hooks, button, state = setup(true)
    local overlay, events = frames[1], frames[2]
    hooks.OnEnter(button)
    state(false, false)
    events.scripts.OnEvent(events, "MODIFIER_STATE_CHANGED")
    eq(overlay.shown, false)
    state(false, true)
    hooks.OnEnter(button)
    events.scripts.OnEvent(events, "BAG_UPDATE")
    eq(overlay.attrs["target-slot"], nil)
    hooks.OnEnter(button)
    MurgleDB.lootVendors.disenchantClick = false
    addon.ItemActions:ApplyAll()
    eq(overlay.shown, false)
    hooks.OnEnter(button)
    eq(overlay.shown, false)
    MurgleDB.lootVendors.disenchantClick = true
    addon.ItemActions:ApplyAll()
    hooks.OnEnter(button)
    eq(overlay.shown, true)
    eq(type(overlay.attrs._onattributechanged), "string")
    eq(overlay.driver:find("combat", 1, true) ~= nil, true)
    state(true, true)
    hooks.OnEnter(button)
    state(false, true)
    events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED")
    eq(overlay.shown, false)
    hooks.OnEnter({})
    eq(overlay.shown, false)
end)

test("item actions missing API fails closed without side effects", function()
    local addon, frames = setup(false)
    C_SpellBook = nil
    MurgleDB.lootVendors.disenchantClick = true
    addon.ItemActions:ApplyAll()
    eq(#frames, 0)
end)

test("item actions Alt press while already over native slot arms once", function()
    local _, frames, hooks, button, state = setup(true)
    state(false, false)
    hooks.OnEnter(button)
    eq(frames[1].shown, false)
    state(false, true)
    frames[2].scripts.OnEvent(frames[2], "MODIFIER_STATE_CHANGED")
    eq(frames[1].shown, true)
    frames[1].scripts.PostClick()
    eq(frames[1].shown, false)
    eq(frames[1].attrs.spell, nil)
end)

test("item actions identical-link replacement disarms before destructive input", function()
    local _, frames, hooks, button, state = setup(true)
    hooks.OnEnter(button)
    eq(frames[1].shown, true)
    state(false, true, 2, "item:100", "Item-100-B")
    frames[1].scripts.PreClick(frames[1], "LeftButton")
    eq(frames[1].attrs["alt-type1"], nil)
    eq(frames[1].attrs["target-slot"], nil)
end)

test("item actions missing or absent GUID never arms", function()
    local _, frames, hooks, button = setup(true)
    C_Item.GetItemGUID = function()
        return nil
    end
    hooks.OnEnter(button)
    eq(frames[1].shown, false)
    C_Item.GetItemGUID = nil
    hooks.OnEnter(button)
    eq(frames[1].shown, false)
end)

test("item actions secure hiding removes the action before combat input", function()
    local _, frames, hooks, button, state = setup(true)
    local overlay = frames[1]
    hooks.OnEnter(button)
    local hide =
        assert(loadstring("return function(self, name, value) " .. overlay.attrs._onattributechanged .. " end"))()
    state(true, false)
    hide(overlay, "visibility", "hide")
    overlay.scripts.PreClick(overlay, "LeftButton")
    eq(overlay.shown, false)
    eq(overlay.attrs["alt-type1"], nil)
end)

test("item actions first enabled in combat installs through core deferral after combat", function()
    local addon, frames, hooks, _, combat = setup(false)
    local pending
    addon.DeferUntilOutOfCombat = function(key, fn)
        eq(key, "items.apply")
        pending = fn
    end
    combat(true)
    MurgleDB.lootVendors.disenchantClick = true
    addon.ItemActions.ApplyAll()
    eq(#frames, 0)
    eq(type(pending), "function")
    combat(false)
    pending()
    eq(#frames, 2)
    eq(hooks.registrations, 1)
    eq(hooks.nativeHooks, 0)
end)

test("item actions native callback subscription follows enable state without native hooks", function()
    local addon, frames, registry, button = setup(true)
    eq(registry.registrations, 1)
    eq(registry.nativeHooks, 0)
    addon.ItemActions.ApplyAll()
    addon.ItemActions.ApplyAll()
    eq(registry.registrations, 1)
    registry.OnEnter(button)
    eq(frames[1].shown, true)
    MurgleDB.lootVendors.disenchantClick = false
    addon.ItemActions.ApplyAll()
    eq(registry.removals, 1)
    registry.OnEnter(button)
    eq(frames[1].shown, false)
    MurgleDB.lootVendors.disenchantClick = true
    addon.ItemActions.ApplyAll()
    eq(registry.registrations, 2)
    registry.OnEnter(button)
    eq(frames[1].shown, true)
    eq(registry.nativeHooks, 0)
end)

test("item actions combat disable unregisters native callback before deferred overlay cleanup", function()
    local addon, frames, registry, button, state = setup(true)
    local pending
    addon.DeferUntilOutOfCombat = function(_, fn)
        pending = fn
    end
    registry.OnEnter(button)
    state(true, true)
    MurgleDB.lootVendors.disenchantClick = false
    addon.ItemActions.ApplyAll()
    eq(registry.removals, 1)
    eq(type(pending), "function")
    state(false, true)
    pending()
    registry.OnEnter(button)
    eq(frames[1].shown, false)
    eq(frames[1].attrs["alt-type1"], nil)
    eq(registry.registrations, 1)
end)

test("item actions missing native registry fails closed without hook fallback", function()
    local addon, frames, registry = setup(false)
    EventRegistry = nil
    MurgleDB.lootVendors.disenchantClick = true
    addon.ItemActions.ApplyAll()
    eq(#frames, 0)
    eq(registry.nativeHooks, 0)
    eq(registry.registrations, 0)
end)
