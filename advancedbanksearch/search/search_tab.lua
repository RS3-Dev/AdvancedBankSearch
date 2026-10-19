-- Draw the Search tab Bank Core mounts in its sidebar: the search field and the sort toggle,
-- a status line shown only when there is something to say, the saved queries and their
-- folders with each query's last count, and New, Edit, and Delete. The field keeps its
-- control while the tab refreshes, so typing is never interrupted; a refresh moves the
-- status line and rows rather than rebuilding them

local SearchTab = {}
SearchTab.__index = SearchTab

local X = 8
local FIELD_TOP = 8
local FIELD_HEIGHT = 26
local SORT_SIZE = 26
local SORT_GAP = 6
local BODY_TOP = FIELD_TOP + FIELD_HEIGHT + 6
local STATUS_LINE_HEIGHT = 16
local STATUS_GAP = 4
-- Roughly how wide a status character is, to tell when the line wraps to a second line
local STATUS_CHARACTER_WIDTH = 6
local FOOTER_HEIGHT = 44
local BUTTON_HEIGHT = 28
local BUTTON_GAP = 6
local ROW_HEIGHT = 30
local ROW_LEFT = 8
local FOLDER_INDENT = 18
local CHEVRON_SIZE = 14
local CHEVRON_RIGHT = 8
local ARROW_SIZE = 20
local ARROWS_WIDTH = ARROW_SIZE * 2 + 2 + 8
local FOLDER_PREFIX = "folder:"
local TEXT = 0xE7D7B0FF
local MUTED = 0xAFA58FFF
local ERROR = 0xE57373FF
local HEADING = 0xE7C878FF
local FOLDER_ROW = 0x302A21FF
local SELECTED_BORDER = 0xD2A84DFF

-- Create the tab's mount callbacks for an app; the same functions stay registered, so Bank
-- Core keeps the column mounted across tab updates
function SearchTab.new(app)
    local self = setmetatable({ app = app, ctx = nil, controls = nil, sortMode = false, rowInfo = {},
        arrows = {} }, SearchTab)
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

-- Destroy the sort arrows before their rows are replaced
function SearchTab:DestroyArrows()
    for _, arrow in ipairs(self.arrows) do pcall(function() arrow:Destroy() end) end
    self.arrows = {}
end

-- Destroy the column's controls; Bank Core destroys the layers they sit in
function SearchTab:DestroyControls()
    self:DestroyArrows()
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
    local controls = { owned = {}, width = width, height = bounds.height }
    local owned = controls.owned
    controls.field = prettyui.TextField.new(parent, {
        x = X, y = FIELD_TOP, width = math.max(1, width - SORT_SIZE - SORT_GAP), height = FIELD_HEIGHT,
        placeholder = "Search items with RuneQL...", text = app.text, maxLength = 9999,
        onChange = function(_, _, content) app:SetText(content) end,
    })
    owned[#owned + 1] = controls.field
    controls.sort = prettyui.SpriteButton.new(parent, "SWAP", function() self:SetSortMode(not self.sortMode) end, {
        x = X + width - SORT_SIZE, y = FIELD_TOP, size = SORT_SIZE, tooltip = "Sort saved searches and folders",
    })
    owned[#owned + 1] = controls.sort
    controls.status = addText(parent, "", BODY_TOP, width, STATUS_LINE_HEIGHT, MUTED, 2)
    controls.status.hidden = true
    owned[#owned + 1] = controls.status
    controls.list = prettyui.List.new(parent, {
        x = X, y = BODY_TOP, width = width, height = ROW_HEIGHT, entryHeight = ROW_HEIGHT,
        maxSelected = 1, backgroundColour = 0x00000000, borderColour = 0x806432FF,
        selectedColour = 0x5A4526FF,
        -- Rows do nothing while sorting, so an arrow the click passes through opens nothing
        beforeEntryClick = function() return not self.sortMode end,
        _onEntryClick = function(_, entryID) self:Click(entryID) end,
    })
    owned[#owned + 1] = controls.list
    controls.empty = addText(parent, "No saved searches yet. Press New to save one.", BODY_TOP + 6,
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

-- Open a query or toggle a folder from its row; while sorting, rows only redraw
function SearchTab:Click(entryID)
    local info = self.rowInfo[entryID]
    if self.sortMode or info == nil then
        self:Refresh()
    elseif info.kind == "folder" then
        self.app:ToggleFolder(info.id)
    else
        self.app:ChooseQuery(info.id)
    end
end

-- Turn sorting on or off
function SearchTab:SetSortMode(enabled)
    self.sortMode = enabled == true
    self:Refresh()
end

-- Describe the rows: queries and folders in sidebar order, each expanded folder's queries
-- beneath it. Sorting expands every folder so each query can move. Each row's kind, ID, and
-- place among its siblings are kept by entry ID, since PrettyUI copies only its own fields
function SearchTab:Entries()
    local app = self.app
    local entries, rowInfo = {}, {}
    -- Append one query row
    local function addQuery(record, inFolder, index, siblings)
        local matched = app.counts[record.id]
        entries[#entries + 1] = {
            id = record.id,
            label = record.name .. (matched ~= nil and (" (" .. matched .. ")") or ""),
            selected = record.id == app.selectedQuery,
            textColour = TEXT,
        }
        rowInfo[record.id] = { kind = "query", id = record.id, inFolder = inFolder, index = index, count = siblings }
    end
    local tree = app.queries:Tree()
    for index, node in ipairs(tree) do
        if node.kind == "query" then
            addQuery(node.query, false, index, #tree)
        else
            local expanded = self.sortMode or not node.collapsed
            local holdsSelected = false
            for _, record in ipairs(node.queries) do
                if record.id == app.selectedQuery then holdsSelected = true end
            end
            local entryID = FOLDER_PREFIX .. node.id
            entries[#entries + 1] = {
                id = entryID,
                label = node.name .. " (" .. #node.queries .. ")",
                -- A collapsed folder carries the outline of the selected query it hides
                selected = holdsSelected and not expanded,
                backgroundColour = FOLDER_ROW,
                textColour = HEADING,
            }
            rowInfo[entryID] = { kind = "folder", id = node.id, expanded = expanded, index = index, count = #tree }
            if expanded then
                for memberIndex, record in ipairs(node.queries) do
                    addQuery(record, true, memberIndex, #node.queries)
                end
            end
        end
    end
    return entries, rowInfo
end

-- Outline a selected row in gold: top, bottom, left, and right edges, each as x, y, width,
-- height, x anchor, and width anchor
local FRAME_EDGES = {
    { 0, 0, 0, 1, 0, 1.0 }, { 0, ROW_HEIGHT - 1, 0, 1, 0, 1.0 },
    { 0, 0, 1, ROW_HEIGHT, 0, 0 }, { -1, 0, 1, ROW_HEIGHT, 1.0, 0 },
}
local function addSelectedFrame(root)
    for _, edge in ipairs(FRAME_EDGES) do
        local rectangle = ui.Rectangle.new(root)
        rectangle:SetPos(edge[1], edge[2], edge[5], 0)
        rectangle:SetSize(edge[3], edge[4], edge[6], 0)
        rectangle.fill = true
        rectangle.rgba = SELECTED_BORDER
        rectangle.clickthrough = true
        rectangle:MoveToFront()
    end
end

-- Point a folder's chevron down when it is open and right when it is closed. The bank arrow
-- faces up and the host turns sprites anticlockwise; it may read any of these fields
local function addChevron(root, expanded)
    local chevron = ui.Sprite.new(root)
    chevron:SetPos(-CHEVRON_RIGHT - CHEVRON_SIZE, math.floor((ROW_HEIGHT - CHEVRON_SIZE) / 2), 1.0, 0)
    chevron:SetSize(CHEVRON_SIZE, CHEVRON_SIZE)
    chevron.spriteID = id.Sprite.BANK_ARROW_UP_0
    local radians = expanded and math.pi or math.pi * 1.5
    if chevron.SetRotation ~= nil then pcall(function() chevron:SetRotation(radians) end) end
    pcall(function() chevron.rotation = radians end)
    pcall(function() chevron.angle = radians end)
    pcall(function() chevron.rotationDegrees = expanded and 180 or 270 end)
    pcall(function() chevron.angleDegrees = expanded and 180 or 270 end)
    chevron.clickthrough = true
    chevron:MoveToFront()
end

-- Place each row's label clear of its chevron and arrows, indent folder members, outline the
-- selected row, and add the sort arrows
function SearchTab:DecorateRows()
    for _, row in ipairs(self.controls.list.rows or {}) do
        local info = self.rowInfo[row.entry.id]
        local right = self.sortMode and ARROWS_WIDTH or 6
        local left = ROW_LEFT
        if info.kind == "folder" then
            addChevron(row.root, info.expanded)
            right = right + CHEVRON_RIGHT + CHEVRON_SIZE
        elseif info.inFolder then
            left = ROW_LEFT + FOLDER_INDENT
        end
        row.label:SetPos(left, 0)
        row.label:SetSize(-left - right, ROW_HEIGHT, 1.0, 0)
        if row.entry.selected then addSelectedFrame(row.root) end
        if self.sortMode then self:AddArrows(row, info) end
    end
end

-- Add up and down arrows at the row's right, each disabled at its end of the row's siblings
function SearchTab:AddArrows(row, info)
    local list = self.controls.list
    for _, offset in ipairs({ -1, 1 }) do
        local up = offset == -1
        local arrow = prettyui.SpriteButton.new(row.root, up and "ARROW_UP" or "ARROW_DOWN", function()
            self.app:MoveEntry(info.kind, info.id, offset)
        end, {
            x = up and -ARROWS_WIDTH or -ARROW_SIZE - 8, xAnchor = 1.0,
            y = math.floor((ROW_HEIGHT - ARROW_SIZE) / 2), size = ARROW_SIZE,
            disabled = (up and info.index == 1) or (not up and info.index == info.count),
            _onScrollWheel = function(component, delta) return list:_OnScrollWheel(component, delta) end,
        })
        self.arrows[#self.arrows + 1] = arrow
    end
end

-- Place the status line under the field when it has text, and the rows under it or under
-- the field, sized to the rest of the column above the footer
function SearchTab:Layout(text)
    local controls = self.controls
    local status = controls.status
    local top = BODY_TOP
    if text ~= "" then
        local lines = #text * STATUS_CHARACTER_WIDTH > controls.width and 2 or 1
        status:SetSize(controls.width, lines * STATUS_LINE_HEIGHT)
        top = BODY_TOP + lines * STATUS_LINE_HEIGHT + STATUS_GAP
    end
    status.hidden = text == ""
    if controls.listTop == top then return end
    controls.listTop = top
    controls.list.root:SetPos(X, top)
    controls.list:SetSize(controls.width, math.max(ROW_HEIGHT, controls.height - FOOTER_HEIGHT - top - 4))
    controls.empty:SetPos(X, top + 6)
end

-- Show the app's current status, saved queries and folders, and what can be done now
function SearchTab:Refresh()
    local controls = self.controls
    if controls == nil then return end
    local app = self.app
    local text = app.status or ""
    controls.status.content = text
    controls.status.rgba = app.statusIsError and ERROR or MUTED
    self:Layout(text)
    self:DestroyArrows()
    local entries
    entries, self.rowInfo = self:Entries()
    controls.list:SetEntries(entries)
    self:DecorateRows()
    controls.empty.hidden = #entries > 0
    controls.sort:SetSelected(self.sortMode)
    controls.sort:SetTooltip(self.sortMode and "Finish sorting" or "Sort saved searches and folders")
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

-- Find what a row under a point in the column is: { kind, id } for a query or folder, or
-- nil. Rows are measured from the list's top and scroll, so a scrolled list finds the row
-- actually under the point
function SearchTab:EntryAt(x, y)
    local controls = self.controls
    if controls == nil or x == nil or y == nil then return nil end
    local list = controls.list
    local left, top = list.root.x or X, list.root.y or BODY_TOP
    local height = list.root.height or 0
    if x < left or x >= left + controls.width or y < top or y >= top + height then return nil end
    local index = math.floor((y - top - 1 + (list.scrollY or 0)) / ROW_HEIGHT) + 1
    local row = (list.rows or {})[index]
    if row == nil then return nil end
    local info = self.rowInfo[row.entry.id]
    return info ~= nil and { kind = info.kind, id = info.id } or nil
end

-- Report whether the column is mounted now
function SearchTab:IsMounted()
    return self.controls ~= nil
end

return SearchTab
