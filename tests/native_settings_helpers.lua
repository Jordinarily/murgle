local Native = {}
function Native.new(state)
    state.categories, state.settings, state.controls, state.layouts = {}, {}, {}, {}
    local api = {}
    local function category(name, parent)
        local c = { name = name, parent = parent, id = #state.categories + 1 }
        function c:GetID()
            return self.id
        end
        local layout = { initializers = {} }
        function layout:AddInitializer(i)
            self.initializers[#self.initializers + 1] = i
            state.controls[#state.controls + 1] = i
        end
        state.categories[#state.categories + 1] = c
        state.layouts[c] = layout
        return c, layout
    end
    api.RegisterVerticalLayoutCategory = function(name)
        return category(name)
    end
    api.RegisterVerticalLayoutSubcategory = function(parent, name)
        return category(name, parent)
    end
    api.RegisterAddOnCategory = function(c)
        state.addonCategory = c
    end
    api.OpenToCategory = function(id)
        state.openCategory = id
    end
    api.RegisterProxySetting = function(c, variable, kind, name, default, getter, setter)
        assert(not state.settings[variable], "duplicate setting")
        assert(type(name) == "string" and name ~= "", "setting needs a label")
        assert(default == nil or type(default) == kind, "native default type mismatch")
        local setting = { category = c, variable = variable, kind = kind, name = name, default = default }
        function setting:GetValue()
            return getter()
        end
        function setting:SetValue(value)
            eq(type(value), kind)
            if self:GetValue() ~= value then
                setter(value)
            end
        end
        function setting:SetValueToDefault()
            if default ~= nil then
                state.defaulting = true
                self:SetValue(default)
                state.defaulting = false
            end
        end
        state.settings[variable] = setting
        return setting
    end
    api.NotifyUpdate = function(variable)
        assert(state.settings[variable])
        state.notifications = (state.notifications or 0) + 1
    end
    api.CreateControlTextContainer = function()
        local c = { data = {} }
        function c:Add(value, label)
            self.data[#self.data + 1] = { value = value, label = label }
        end
        function c:GetData()
            return self.data
        end
        return c
    end
    api.CreateSliderOptions = function(min, max, step)
        local options = { min = min, max = max, step = step }
        function options:SetLabelFormatter(label, formatter)
            self.formatters = self.formatters or {}
            self.formatters[label] = formatter
        end
        return options
    end
    function Native.initializer(data)
        local i = data or {}
        function i:AddModifyPredicate(fn)
            self.predicates = self.predicates or {}
            self.predicates[#self.predicates + 1] = fn
        end
        function i:SetParentInitializer(parent, predicate)
            self.parent = parent
            if predicate then
                self:AddModifyPredicate(predicate)
            end
        end
        function i:AddEvaluateStateFrameEvent(event)
            self.evaluateEvents = self.evaluateEvents or {}
            self.evaluateEvents[event] = true
        end
        function i:IsEnabled()
            for _, predicate in ipairs(self.predicates or {}) do
                if not predicate() then
                    return false
                end
            end
            return true
        end
        return i
    end
    local function control(kind, c, setting, options, help)
        local i = Native.initializer({ kind = kind, setting = setting, options = options, help = help })
        state.layouts[c]:AddInitializer(i)
        return i
    end
    api.CreateCheckbox = function(c, s, help)
        return control("checkbox", c, s, nil, help)
    end
    api.CreateDropdown = function(c, s, options, help)
        return control("dropdown", c, s, options, help)
    end
    api.CreateSlider = function(c, s, options, help)
        return control("slider", c, s, options, help)
    end
    function state:setting(group, key)
        return assert(self.settings["Murgle_" .. group .. "_" .. key], group .. "." .. key)
    end
    function state:control(group, key)
        local setting = self:setting(group, key)
        for _, c in ipairs(self.controls) do
            if c.setting == setting then
                return c
            end
        end
        error("control missing")
    end
    function state:action(text)
        for _, c in ipairs(self.controls) do
            if c.buttonText == text then
                return c.buttonClick()
            end
        end
        error("action missing: " .. tostring(text))
    end
    return api
end
return Native
