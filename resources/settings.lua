-- Save preferences and mount the Plugin Hub settings layer

local Json = require("resources/core/json")

local Settings = {}
Settings.__index = Settings

local STORE_KEY = "advancedbanksearch:settings:v1"
local EVENT_KEY = "advancedbanksearch_settings"
local DEFAULTS = { editorMode = "visual", includePlaceholders = true, searchDelayTicks = 10 }
local CHOICES = {
    editorMode = { { label = "Advanced", value = "advanced" }, { label = "Visual", value = "visual" } },
    includePlaceholders = { { label = "Hide placeholders", value = false }, { label = "Include placeholders", value = true } },
    searchDelayTicks = {
        { label = "Fast (100 ms)", value = 5 },
        { label = "Normal (200 ms)", value = 10 },
        { label = "Relaxed (400 ms)", value = 20 },
    },
}

-- Check preferences against their supported choices
local function valid(key, value)
    for _, choice in ipairs(CHOICES[key] or {}) do if choice.value == value then return true end end
    return false
end

-- Load saved values without changing absent or invalid data
function Settings.new()
    local saved = {}
    local ok, text = pcall(function() return PersistentDB:GetString(STORE_KEY) end)
    if ok and type(text) == "string" then
        local decoded, value = pcall(Json.decode, text)
        if decoded and type(value) == "table" then saved = value end
    end
    local values = {}
    for key, fallback in pairs(DEFAULTS) do
        if valid(key, saved[key]) then values[key] = saved[key] else values[key] = fallback end
    end
    return setmetatable({ values = values, controls = {} }, Settings)
end

-- Persist a preference before applying its behavior
function Settings:Set(key, value)
    if not valid(key, value) then return false, "Invalid preference." end
    if self.values[key] == value then return true end
    local nextValues = {}
    for name, current in pairs(self.values) do nextValues[name] = current end
    nextValues[key] = value
    local ok, written = pcall(function() return PersistentDB:SetString(STORE_KEY, Json.encode(nextValues)) end)
    if not ok or written == false then return false, "Could not save settings." end
    self.values = nextValues
    if self.onChange ~= nil then self.onChange(key) end
    return true
end

-- Destroy the previous mount and ignore its callbacks
function Settings:Unmount()
    local view = self.view
    self.view, self.controls, self.status = nil, {}, nil
    if view ~= nil then pcall(function() view:Destroy() end) end
end

-- Populate the client's settings layer with native controls
function Settings:Mount(parent)
    self:Unmount()
    local view = prettyui.SimpleView.new(parent, { width = parent.width, height = parent.height })
    self.view, self.rendering = view, true
    view:AddTitle("Advanced Bank Search")
    local function add(key, label)
        view:AddText(label)
        local entries, selected = {}, nil
        for index, choice in ipairs(CHOICES[key]) do
            entries[index] = { id = index, label = choice.label }
            if choice.value == self.values[key] then selected = index end
        end
        self.controls[key] = view:AddComboBox({
            entries = entries, selectedID = selected,
            onChange = function(combo, entryID)
                if self.view ~= view or self.rendering then return end
                local choice = CHOICES[key][entryID]
                if choice == nil then return end
                local saved, reason = self:Set(key, choice.value)
                self.status.content = reason or ""
                self.status.hidden = saved
                if not saved then
                    for index, current in ipairs(CHOICES[key]) do
                        if current.value == self.values[key] then combo:Select(index, false) break end
                    end
                end
            end,
        })
    end
    add("editorMode", "Default editor for new searches")
    add("includePlaceholders", "Include placeholders in search results")
    add("searchDelayTicks", "Search delay")
    self.status = view:AddText({ text = "", colour = 0xE57373FF })
    self.status.hidden = true
    self.rendering = false
end

-- Subscribe to the settings cog's layer event
function Settings:Start()
    Event.SettingsLayerReady.Subscribe(EVENT_KEY, function(event) self:Mount(event.component) end)
end

-- Release settings controls and the event subscription
function Settings:Shutdown()
    Event.SettingsLayerReady.Unsubscribe(EVENT_KEY)
    self:Unmount()
    self.onChange = nil
end

return Settings
