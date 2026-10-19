-- Draw the Search tab Bank Core mounts in its sidebar: the search field, a status line, the
-- saved queries with their last counts, and New, Edit, and Delete. The field keeps its
-- control while the tab refreshes, so typing is never interrupted

local SearchTab = {}
SearchTab.__index = SearchTab

local X = 8
local FIELD_TOP = 8
local FIELD_HEIGHT = 26
local STATUS_TOP = FIELD_TOP + FIELD_HEIGHT + 4
local STATUS_HEIGHT = 32
local HEADING_TOP = STATUS_TOP + STATUS_HEIGHT + 4
local HEADING_HEIGHT = 20
local LIST_TOP = HEADING_TOP + HEADING_HEIGHT + 2
local FOOTER_HEIGHT = 44
local BUTTON_HEIGHT = 28
local BUTTON_GAP = 6
local ROW_HEIGHT = 30
local TEXT = 0xE7D7B0FF
local MUTED = 0xAFA58FFF
local HEADING = 0xE7C878FF

-- Create the tab's mount callbacks for an app; the same functions stay registered, so Bank
-- Core keeps the column mounted across tab updates
function SearchTab.new(app)
    local self = setmetatable({ app = app, ctx = nil, controls = nil }, SearchTab)
    self.callbacks = {
        mount = function(ctx)
            self.ctx = ctx
            self:Build()
        end,
        resize = function() self:Build() end,
        unmount = function() self:Unmount() end,
    }
    return self
end

-- Destroy the column's controls; Bank Core destroys the layers they sit in
function SearchTab:DestroyControls()
    local controls = self.controls
    self.controls = nil
    if controls == nil then return end
    for _, control in ipairs(controls.owned) do pcall(function() control:Destroy() end) end
end

-- Forget the column when Bank Core unmounts it
function SearchTab:Unmount()
    self:DestroyControls()
    self.ctx = nil
end

-- Add a click-through text line to the column
local function addText(parent, content, y, width, height, colour, maxLines)
    local text = prettyui.Text.new(parent, {
        text = content, x = X, y = y, width = width, height = height,
        font = id.Font.MUSEO_SANS_11PT_REGULAR, colour = colour, maxLines = maxLines or 1,
    })
    text.clickthrough = true
    return text
end

-- Build the whole column inside Bank Core's parent, replacing anything built before
function SearchTab:Build()
    self:DestroyControls()
    local ctx = self.ctx
    if ctx == nil then return end
    local app = self.app
    local bounds = ctx:GetBounds()
    local parent = ctx.parent
    local width = math.max(1, bounds.width - X * 2)
    local controls = { owned = {} }
    local owned = controls.owned
    controls.field = prettyui.TextField.new(parent, {
        x = X, y = FIELD_TOP, width = width, height = FIELD_HEIGHT,
        placeholder = "Search items with RuneQL...", text = app.text, maxLength = 9999,
        onChange = function(_, _, content) app:SetText(content) end,
    })
    owned[#owned + 1] = controls.field
    controls.status = addText(parent, "", STATUS_TOP, width, STATUS_HEIGHT, MUTED, 2)
    owned[#owned + 1] = controls.status
    owned[#owned + 1] = addText(parent, "Saved searches", HEADING_TOP, width, HEADING_HEIGHT, HEADING)
    local listHeight = math.max(ROW_HEIGHT, bounds.height - FOOTER_HEIGHT - LIST_TOP - 4)
    controls.list = prettyui.List.new(parent, {
        x = X, y = LIST_TOP, width = width, height = listHeight, entryHeight = ROW_HEIGHT,
        maxSelected = 1, backgroundColour = 0x00000000, borderColour = 0x806432FF,
        selectedColour = 0x5A4526FF,
        _onEntryClick = function(_, entryID) app:ChooseQuery(entryID) end,
    })
    owned[#owned + 1] = controls.list
    controls.empty = addText(parent, "No saved searches yet. Press New to save one.", LIST_TOP + 6,
        width, 40, MUTED, 2)
    owned[#owned + 1] = controls.empty
    local top = bounds.height - FOOTER_HEIGHT + 8
    local buttonWidth = math.floor((width - BUTTON_GAP * 2) / 3)
    -- Add one footer button at a column
    local function button(label, column, action)
        local value = prettyui.SimpleButton.new(parent, label, action, {
            x = X + (column - 1) * (buttonWidth + BUTTON_GAP), y = top, width = buttonWidth, height = BUTTON_HEIGHT,
        })
        owned[#owned + 1] = value
        return value
    end
    controls.new = button("New", 1, function() app:NewQuery() end)
    controls.edit = button("Edit", 2, function() app:EditQuery() end)
    controls.delete = button("Delete", 3, function() app:DeleteQuery() end)
    self.controls = controls
    self:Refresh()
end

-- Show the app's current status, saved queries, and what can be done now
function SearchTab:Refresh()
    local controls = self.controls
    if controls == nil then return end
    local app = self.app
    controls.status.content = app.status or ""
    controls.status.rgba = app.statusIsError and 0xE57373FF or MUTED
    local entries = {}
    for _, record in ipairs(app.queries:All()) do
        local count = app.counts[record.id]
        entries[#entries + 1] = {
            id = record.id,
            label = record.name .. (count ~= nil and (" (" .. count .. ")") or ""),
            selected = record.id == app.selectedQuery,
            textColour = TEXT,
        }
    end
    controls.list:SetEntries(entries)
    controls.empty.hidden = #entries > 0
    local searchable = app:RuneQL() ~= nil
    local selected = app.selectedQuery ~= nil and app.queries:Get(app.selectedQuery) ~= nil
    -- Set each control's state only when it changes, not on every keystroke
    local states = { field = not searchable, edit = not selected, delete = not selected }
    controls.disabled = controls.disabled or {}
    for name, disabled in pairs(states) do
        if controls.disabled[name] ~= disabled then
            controls[name]:SetDisabled(disabled)
            controls.disabled[name] = disabled
        end
    end
end

-- Report whether the column is mounted now
function SearchTab:IsMounted()
    return self.controls ~= nil
end

return SearchTab
