-- Bank Tags-style row actions and folder submenus. Explicit menu choices are
-- accepted once, then rechecked against the same row, mount and press count.
local MenuEntries = require("resources/search/menu_entries")
local Text = require("resources/core/text")
local QueryMenus = {}
QueryMenus.__index = QueryMenus
local MENU_EVENT = "advancedbanksearch_menu"
local ACTION_EVENT = "advancedbanksearch_menu_action"

function QueryMenus.new(app) return setmetatable({ app = app, pending = {}, started = false }, QueryMenus) end

function QueryMenus:Start()
    if self.started then return end
    self.started = true
    Event.MiniMenuReady.Subscribe(MENU_EVENT, function(event)
        local menu = event and event.miniMenu
        if menu ~= nil then pcall(function() self:HandleMenu(menu) end) end
    end)
    Event.MiniMenuOpened.Subscribe(MENU_EVENT, function()
        if self.rowMenu ~= nil then self.rowMenu.opened = true end
    end)
end

function QueryMenus:Stop()
    if self.started then
        Event.MiniMenuReady.Unsubscribe(MENU_EVENT)
        Event.MiniMenuOpened.Unsubscribe(MENU_EVENT)
    end
    self.started, self.rowMenu = false, nil
    Event.Logic.Unsubscribe(ACTION_EVENT)
    self.pending = {}
end

function QueryMenus:Defer(current, action)
    return function()
        if not current() then return end
        self.pending[#self.pending + 1] = function() if current() then action() end end
        Event.Logic.Subscribe(ACTION_EVENT, function()
            Event.Logic.Unsubscribe(ACTION_EVENT)
            local pending = self.pending
            self.pending = {}
            for _, run in ipairs(pending) do pcall(run) end
        end)
    end
end

function QueryMenus:RowAtPointer()
    local tab, ctx = self.app.tab, self.app.tab.ctx
    if ctx == nil or not tab:IsMounted() then return nil end
    return tab.controls.tree:HoveredEntry(), ctx
end

function QueryMenus:HandleMenu(menu)
    self.rowMenu = nil
    local app, tab = self.app, self.app.tab
    local ext = app.ext
    if ext == nil or ext:GetMenuItem(menu) ~= nil then return end
    local entry, ctx = self:RowAtPointer()
    if entry == nil then return end
    local tree, store = tab.controls.tree, app.queries
    local clicks = tree.clicks
    local function exists()
        return entry.kind == "folder" and store:GetFolder(entry.id) ~= nil
            or entry.kind == "query" and store:Get(entry.id) ~= nil
    end
    local current = function()
        return app.ext == ext and tab.ctx == ctx and tab.controls ~= nil
            and tab.controls.tree == tree and tree.clicks == clicks and exists()
    end
    local rowMenu = { opened = false, used = false }
    local function chosen(action, check)
        local deferred = self:Defer(check or current, action)
        return function()
            if not rowMenu.opened or rowMenu.used then return end
            rowMenu.used = true
            deferred()
        end
    end
    local entries = {}
    local function offer(label, name, action)
        entries[#entries + 1] = { label = label, subject = Text.plain(name), action = chosen(action) }
    end
    if entry.kind == "folder" then
        local folder = store:GetFolder(entry.id)
        offer(folder.collapsed and "Expand" or "Collapse", folder.name, function() app:ToggleFolder(entry.id) end)
        offer("Rename folder", folder.name, function() app:OpenRenameFolder(entry.id) end)
        offer("Ungroup folder", folder.name, function() app:UngroupFolder(entry.id) end)
    else
        local record = store:Get(entry.id)
        offer("Select", record.name, function() app:ChooseQuery(entry.id) end)
        offer("Edit", record.name, function() app:EditQuery(entry.id) end)
        offer("Rename", record.name, function() app:OpenRenameQuery(entry.id) end)
        if prettyui.MiniMenu == nil then
            offer("Move to folder...", record.name, function() app:OpenFolderChooser(entry.id) end)
        end
        local folder = store:GetFolder(store:FolderOf(entry.id))
        if folder ~= nil then
            offer("Remove from folder", folder.name, function() app:MoveQueryToFolder(entry.id, nil) end)
        end
        offer("Remove", record.name, function()
            app:OpenDeleteConfirm(entry.id)
        end)
    end
    if not MenuEntries.AddTop(menu, entries) then return end
    self.rowMenu = rowMenu
    if entry.kind == "query" then self:AddFolderSubmenu(menu, entry.id, 3, chosen, current) end
end

function QueryMenus:AddFolderSubmenu(menu, queryID, position, chosen, isCurrent)
    local MiniMenu = prettyui.MiniMenu
    if MiniMenu == nil then return end
    local app, children = self.app, {}
    local currentFolder = app.queries:FolderOf(queryID)
    for _, folder in ipairs(app.queries:Folders()) do
        local folderID = folder.id
        if folderID ~= currentFolder then
            children[#children + 1] = { label = Text.plain(folder.name),
                action = chosen(function() app:MoveQueryToFolder(queryID, folderID) end,
                    function() return isCurrent() and app.queries:GetFolder(folderID) ~= nil end) }
        end
    end
    children[#children + 1] = { label = "Create new folder",
        action = chosen(function() app:OpenCreateFolderPrompt(queryID) end) }
    children[#children + 1] = { label = "Cancel", action = function() end }
    local label = currentFolder ~= nil and "Move to folder" or "Add to folder"
    local record = app.queries:Get(queryID)
    local text = MenuEntries.Text(label, Text.plain(record.name))
    MiniMenu.AddSubmenu(menu, text, children, { title = label, position = position })
    MenuEntries.PlaceSubmenu(menu, text .. " <col=ffffff><gt></col>", position)
end
return QueryMenus
