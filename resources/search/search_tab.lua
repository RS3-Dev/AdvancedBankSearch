local Text = require("resources/core/text")

-- Search field and the Bank Tags-style draggable query tree.
local BankControls = require("resources/search/bank_controls")
local QueryList = require("resources/search/query_list")
local SidebarRows = require("resources/search/sidebar_rows")
local Theme = require("resources/search/sidebar_theme")

local SearchTab = {}
SearchTab.__index = SearchTab
local X = SidebarRows.CONTENT_X
local BODY_TOP = SidebarRows.LIST_TOP
local FOOTER_HEIGHT = SidebarRows.FOOTER_HEIGHT
local BUTTON_HEIGHT = 28
local BUTTON_GAP = 8
local STATUS_HEIGHT = 26

function SearchTab.new(app)
    local self = setmetatable({ app = app, rowInfo = {} }, SearchTab)
    self.callbacks = {
        mount = function(ctx) self.ctx = ctx; self:Build() end,
        resize = function(ctx) self.ctx = ctx; self:Resize() end,
        unmount = function() self:Unmount() end,
    }
    return self
end

local function windowPosition(component)
    local x, y = 0, 0
    while component ~= nil do
        x, y = x + (component.x or 0), y + (component.y or 0)
        component = component.parent
    end
    return x, y
end

function SearchTab:DestroyControls()
    local controls = self.controls
    self.controls = nil
    if controls == nil then return end
    for _, control in ipairs(controls.owned) do pcall(function() control:Destroy() end) end
    pcall(function() prettyui.Tooltip.unregisterContext(controls.parent) end)
end

function SearchTab:Unmount()
    self.app:StopSearchWait()
    self:DestroyControls()
    self.ctx = nil
end

-- Copied from Bank Tags' title notice: centered, click-through, and overlay-owned.
function SearchTab:BuildStatus(controls)
    local banner = ui.Layer.new(self.ctx.overlay)
    banner:SetPos(80, 5)
    banner:SetSize(-160, STATUS_HEIGHT, 1.0, 0)
    banner.clickthrough = true
    controls.statusBanner = banner
    controls.owned[#controls.owned + 1] = banner
    local background = ui.Rectangle.new(banner)
    background:SetPos(0, 0)
    background:SetSize(0, STATUS_HEIGHT, 1.0, 0)
    background.fill, background.rgba, background.clickthrough = true, Theme.ROW_EVEN, true
    local text = ui.Text.new(banner)
    text:SetPos(8, 0)
    text:SetSize(-16, STATUS_HEIGHT, 1.0, 0)
    text.content = ""
    text.font, text.rgba = id.Font.MUSEO_SANS_11PT_REGULAR, Theme.ERROR_TEXT
    text.isShadowed, text.maxLines, text.clickthrough = true, 2, true
    text.alignVertical, text.alignHorizontal = ui.AlignMode.CENTRE, ui.AlignMode.CENTRE
    controls.statusText = text
    self:RefreshStatus()
end

function SearchTab:RefreshStatus()
    local controls = self.controls
    if controls == nil then return end
    -- Match counts stay out of the interface; only warnings cover the bank title.
    local message = self.app.statusIsError and self.app.status or nil
    controls.statusBanner.hidden = message == nil
    controls.statusText.content = Text.sanitize(message)
end

function SearchTab:Build()
    self:DestroyControls()
    local ctx, app = self.ctx, self.app
    if ctx == nil then return end
    local parent, width = ctx.parent, SidebarRows.ContentWidth(ctx.width)
    local controls = { parent = parent, owned = {}, footer = {}, columnWidth = ctx.width,
        width = width, height = ctx.height }
    prettyui.Tooltip.registerContext(parent, ctx.overlay, function(target)
        local x, y = windowPosition(target)
        local ox, oy = windowPosition(ctx.overlay)
        return x - ox, y - oy
    end)
    controls.field = Text.newField(parent, {
        x = X, y = SidebarRows.SEARCH_TOP, width = width, height = SidebarRows.SEARCH_HEIGHT,
        placeholder = "Search items...", text = app.draft, maxLength = 9999,
        onChange = function(_, _, content) app:QueueText(content) end,
    })
    controls.owned[#controls.owned + 1] = controls.field
    controls.tree = QueryList.new(parent, {
        store = app.queries, width = ctx.width,
        listHeight = math.max(32, ctx.height - FOOTER_HEIGHT - BODY_TOP - 4),
        isSelected = function(queryID) return app.selectedQuery == queryID end,
        onSelect = function(queryID) app:ChooseQuery(queryID) end,
        onToggleFolder = function(folderID) app:ToggleFolder(folderID) end,
        onReorder = function(source, target, after) app:ReorderEntry(source, target, after) end,
    })
    controls.owned[#controls.owned + 1] = controls.tree
    controls.list, controls.empty = controls.tree.list, controls.tree.emptyLabel
    local top = ctx.height - FOOTER_HEIGHT + 8
    controls.share = BankControls.button(parent, nil, function() app:OpenImportShare() end, {
        x = X, y = top, size = BUTTON_HEIGHT, iconSize = 18, spriteName = "EXPORT",
        tooltip = "Import and share queries",
    })
    controls.new = BankControls.button(parent, "New Query", function() app:NewQuery() end, {
        x = X + BUTTON_HEIGHT + BUTTON_GAP, y = top,
        width = width - BUTTON_HEIGHT - BUTTON_GAP, height = BUTTON_HEIGHT, tooltip = "Create a new query",
    })
    controls.edit = BankControls.button(parent, nil, function() app:EditQuery() end, {
        x = X + width - BUTTON_HEIGHT, y = top, size = BUTTON_HEIGHT, iconSize = 18,
        spriteName = "PENCIL", tooltip = "Edit query", hidden = true,
    })
    controls.footer = { controls.share, controls.new, controls.edit }
    for _, control in ipairs(controls.footer) do controls.owned[#controls.owned + 1] = control end
    self.controls = controls
    self:BuildStatus(controls)
    self:Refresh()
end

function SearchTab:Resize()
    local controls, ctx = self.controls, self.ctx
    if controls == nil or ctx == nil or controls.columnWidth ~= ctx.width then self:Build(); return end
    controls.tree:StopGesture()
    controls.height = ctx.height
    local top = ctx.height - FOOTER_HEIGHT + 8
    controls.list:SetSize(controls.width, math.max(32, controls.height - FOOTER_HEIGHT - BODY_TOP - 4))
    self:Refresh()
end

function SearchTab:Refresh()
    local controls, app = self.controls, self.app
    if controls == nil then return end
    self:RefreshStatus()
    controls.tree:Refresh()
    self.rowInfo = {}
    for _, entry in ipairs(controls.tree.entries) do
        local folderID = entry.id:match("^folder:(.+)$")
        self.rowInfo[entry.id] = folderID and { kind = "folder", id = folderID, expanded = entry.expanded }
            or { kind = "query", id = entry.id, inFolder = entry.folder ~= nil }
    end
    local searchable = app:RuneQL() ~= nil
    local selected = app.selectedQuery ~= nil and app.queries:Get(app.selectedQuery) ~= nil
    local top = controls.height - FOOTER_HEIGHT + 8
    local newWidth = controls.width - BUTTON_HEIGHT - BUTTON_GAP - (selected and BUTTON_HEIGHT + BUTTON_GAP or 0)
    controls.new.width = newWidth
    controls.new.root:SetSize(newWidth, BUTTON_HEIGHT)
    controls.edit.hidden = not selected
    for _, button in ipairs(controls.footer) do
        button.y = top
        button.root:SetPos(button.x, top)
        if button.icon ~= nil then
            button.icon:SetPos(button.x + math.floor((button.width - button.iconSize) / 2),
                top + math.floor((button.height - button.iconSize) / 2))
        end
        button:_UpdateState()
    end
    local states = { field = not searchable, edit = not selected }
    controls.disabled = controls.disabled or {}
    for name, disabled in pairs(states) do
        if controls.disabled[name] ~= disabled then
            controls[name]:SetDisabled(disabled)
            controls.disabled[name] = disabled
        end
    end
end

function SearchTab:EntryAt(x, y)
    local controls = self.controls
    if controls == nil or x == nil or y == nil or controls.tree.gesture ~= nil then return nil end
    local list = controls.list
    if list.root.hidden then return nil end
    local left, top = list.root.x or X, list.root.y or BODY_TOP
    if x < left or x >= left + controls.width or y < top or y >= top + list.root.height then return nil end
    local offset = y - top + (list.scrollY or 0)
    if offset % SidebarRows.ENTRY_HEIGHT >= 30 then return nil end
    local row = (list.rows or {})[math.floor(offset / SidebarRows.ENTRY_HEIGHT) + 1]
    if row == nil then return nil end
    return self.rowInfo[row.entry.id]
end

function SearchTab:IsMounted() return self.controls ~= nil end
return SearchTab
