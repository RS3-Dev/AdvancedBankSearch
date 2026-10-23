-- Draw the Search tab: field, sort button, status, and saved queries
-- Refresh moves rows and status without rebuilding the field

local NativeButton = require("advancedbanksearch/search/native_button")

local SearchTab = {}
SearchTab.__index = SearchTab

local X = 8
local FIELD_TOP = 8
local FIELD_HEIGHT = 26
local SORT_SIZE = 26
local SORT_GAP = 6
local SORT_ICON_SIZE = 18
local BODY_TOP = FIELD_TOP + FIELD_HEIGHT + 6
local STATUS_LINE_HEIGHT = 16
local STATUS_GAP = 4
-- Rough status character width, to spot a wrapped line
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

-- Create the tab's mount callbacks, kept so Core keeps the column
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

-- Destroy the column's controls and tooltip overlay
function SearchTab:DestroyControls()
    self:DestroyArrows()
    local controls = self.controls
    self.controls = nil
    if controls == nil then return end
    for _, control in ipairs(controls.owned) do pcall(function() control:Destroy() end) end
    pcall(function() prettyui.Tooltip.unregisterContext(controls.parent) end)
end

-- Forget the column, sorting, and any waiting search on unmount
function SearchTab:Unmount()
    self.app:StopSearchWait()
    self:DestroyControls()
    self.ctx = nil
    self.sortMode = false
end

-- Find a component's position in the window
local function windowPosition(component)
    local x, y = 0, 0
    while component ~= nil do
        x, y = x + (component.x or 0), y + (component.y or 0)
        component = component.parent
    end
    return x, y
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

-- Build the column inside Bank Core's parent
function SearchTab:Build()
    self:DestroyControls()
    local ctx = self.ctx
    if ctx == nil then return end
    local app = self.app
    local bounds = ctx:GetBounds()
    local parent = ctx.parent
    local width = math.max(1, bounds.width - X * 2)
    local controls = { parent = parent, owned = {}, width = width, height = bounds.height }
    local owned = controls.owned
    -- Tooltips use the window overlay so the column does not clip them
    local overlay = ctx.overlay
    prettyui.Tooltip.registerContext(parent, overlay, function(target)
        local x, y = windowPosition(target)
        local originX, originY = windowPosition(overlay)
        return x - originX, y - originY
    end)
    controls.field = prettyui.TextField.new(parent, {
        x = X, y = FIELD_TOP, width = math.max(1, width - SORT_SIZE - SORT_GAP), height = FIELD_HEIGHT,
        placeholder = "Search items with RuneQL...", text = app.draft, maxLength = 9999,
        onChange = function(_, _, content)
            -- Starting a search ends sorting
            if tostring(content or "") ~= "" and self.sortMode then self:SetSortMode(false) end
            app:QueueText(content)
        end,
    })
    owned[#owned + 1] = controls.field
    controls.sort = NativeButton.new(parent, "SWAP", function() self:SetSortMode(not self.sortMode) end, {
        x = X + width - SORT_SIZE, y = FIELD_TOP, size = SORT_SIZE, iconSize = SORT_ICON_SIZE,
        tooltip = "Sort saved searches and folders",
    })
    owned[#owned + 1] = controls.sort
    controls.status = addText(parent, "", BODY_TOP, width, STATUS_LINE_HEIGHT, MUTED, 2)
    controls.status.hidden = true
    owned[#owned + 1] = controls.status
    controls.list = prettyui.List.new(parent, {
        x = X, y = BODY_TOP, width = width, height = ROW_HEIGHT, entryHeight = ROW_HEIGHT,
        maxSelected = 1, backgroundColour = 0x00000000, borderColour = 0x806432FF,
        selectedColour = 0x5A4526FF,
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

-- Open a query or toggle a folder from its row
-- While sorting, query rows only redraw
function SearchTab:Click(entryID)
    local info = self.rowInfo[entryID]
    if info ~= nil and info.kind == "folder" then
        self.app:ToggleFolder(info.id)
    elseif self.sortMode or info == nil then
        self:Refresh()
    else
        self.app:ChooseQuery(info.id)
    end
end

-- Toggle sorting, keeping the search text
function SearchTab:SetSortMode(enabled)
    self.sortMode = enabled == true
    self:Refresh()
end

-- List query and folder rows in sidebar order
-- Row info is kept by entry ID since PrettyUI copies only its fields
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
            local expanded = not node.collapsed
            local holdsSelected = false
            for _, record in ipairs(node.queries) do
                if record.id == app.selectedQuery then holdsSelected = true end
            end
            local entryID = FOLDER_PREFIX .. node.id
            entries[#entries + 1] = {
                id = entryID,
                label = node.name .. " (" .. #node.queries .. ")",
                -- A collapsed folder takes the outline of its selected query
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

-- Gold outline edges: x, y, width, height, and anchors
local FRAME_EDGES = {
    { 0, 0, 0, 1, 0, 1.0 }, { 0, ROW_HEIGHT - 1, 0, 1, 0, 1.0 },
    { 0, 0, 1, ROW_HEIGHT, 0, 0 }, { -1, 0, 1, ROW_HEIGHT, 1.0, 0 },
}
-- Outline the selected search without taking its input
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

-- Point a folder chevron down when open and right when closed
-- The arrow faces up and the host may read any of these rotation fields
local function addChevron(root, expanded, rightInset)
    local chevron = ui.Sprite.new(root)
    chevron:SetPos(-CHEVRON_RIGHT - CHEVRON_SIZE - rightInset, math.floor((ROW_HEIGHT - CHEVRON_SIZE) / 2), 1.0, 0)
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

-- Place labels, indent members, outline selection, and add arrows
function SearchTab:DecorateRows()
    for _, row in ipairs(self.controls.list.rows or {}) do
        local info = self.rowInfo[row.entry.id]
        local arrowsWidth = self.sortMode and ARROWS_WIDTH or 0
        local right = math.max(6, arrowsWidth)
        local left = ROW_LEFT
        if info.kind == "folder" then
            addChevron(row.root, info.expanded, arrowsWidth)
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

-- Add up and down arrows, disabled at either end
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

-- Place the status line and rows to fill the column above the footer
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

-- Refresh the status, saved queries, and buttons
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
    controls.sort:SetActive(self.sortMode)
    controls.sort:SetTooltip(self.sortMode and "Finish sorting saved searches and folders"
        or "Sort saved searches and folders")
    local searchable = app:RuneQL() ~= nil
    local selected = app.selectedQuery ~= nil and app.queries:Get(app.selectedQuery) ~= nil
    -- Only update controls whose state changed
    local states = { field = not searchable, edit = not selected, delete = not selected }
    controls.disabled = controls.disabled or {}
    for name, disabled in pairs(states) do
        if controls.disabled[name] ~= disabled then
            controls[name]:SetDisabled(disabled)
            controls.disabled[name] = disabled
        end
    end
end

-- Find the query or folder row at a point, allowing for scroll
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
