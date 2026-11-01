-- Add folder and saved-search entries to the Search column's row menus
-- The client places new entries unpredictably, so each is found and moved down
-- A chosen entry runs next tick, only if its column and row still exist

local QueryMenus = {}
QueryMenus.__index = QueryMenus

local MENU_EVENT = "advancedbanksearch_menu"
local ACTION_EVENT = "advancedbanksearch_menu_action"
local NAME_COLOUR = "f2c66d"

-- Create the menus for an app; nothing is subscribed until Start
function QueryMenus.new(app)
    return setmetatable({ app = app, pending = {}, started = false }, QueryMenus)
end

-- Answer menus while the plugin is connected to Bank Core
function QueryMenus:Start()
    if self.started then return end
    self.started = true
    Event.MiniMenuReady.Subscribe(MENU_EVENT, function(event)
        local menu = event and event.miniMenu
        if menu ~= nil then pcall(function() self:HandleMenu(menu) end) end
    end)
end

-- Stop answering menus and drop chosen entries that have not run
function QueryMenus:Stop()
    if self.started then Event.MiniMenuReady.Unsubscribe(MENU_EVENT) end
    self.started = false
    Event.Logic.Unsubscribe(ACTION_EVENT)
    self.pending = {}
end

-- Describe an entry well enough to tell it from its neighbours
local function signature(entry)
    return table.concat({ tostring(entry.actionType), tostring(entry.overrideText),
        tostring(entry.fullText), tostring(entry.verbText), tostring(entry.subjectText) }, "\n")
end

-- Strip markup and spaces and lowercase for comparison
local function normalize(value)
    return string.lower((tostring(value or ""):gsub("<[^>]->", "")):match("^%s*(.-)%s*$"))
end

-- Make Cancel the default so a left click does nothing
local function promoteCancel(menu)
    for index, entry in ipairs(menu.entries) do
        if entry.actionType == MiniMenuActionType.CANCEL then
            for current = index, menu.entryCount - 1 do menu:Swap(current, current + 1) end
            return
        end
    end
end

-- Add one entry and return its index, or nil if not found
local function add(menu, label, subject, action)
    local text = label .. " <col=" .. NAME_COLOUR .. ">" .. subject .. "</col>"
    local before = {}
    for index, current in ipairs(menu.entries) do before[index] = signature(current) end
    menu:Add(text, action)
    local entries, count = menu.entries, menu.entryCount
    if count ~= #before + 1 then return nil end
    local added = count
    for index = 1, count do
        if signature(entries[index]) ~= before[index] then
            added = index
            break
        end
    end
    local wanted, found = normalize(text), entries[added]
    if normalize(found.overrideText) ~= wanted and normalize(found.fullText) ~= wanted
        and normalize(found.verbText) ~= wanted then
        return nil
    end
    return added
end

-- Move an entry from one index to another, shifting the ones between
local function move(menu, from, to)
    local step = from < to and 1 or -1
    for current = from, to - step, step do menu:Swap(current, current + step) end
end

-- Add entries just above a bottom Cancel, keeping the default
-- If any entry is lost or the default moves, Cancel becomes default
local function addLow(menu, entries)
    local top = menu.entries[menu.entryCount]
    local topSignature = top ~= nil and signature(top) or nil
    local cancelTop = top ~= nil and top.actionType == MiniMenuActionType.CANCEL
    local first = menu.entries[1]
    local base = (not cancelTop and first ~= nil and first.actionType == MiniMenuActionType.CANCEL) and 1 or 0
    for index, entry in ipairs(entries) do
        local added = add(menu, entry[1], entry[2], entry[3])
        if added == nil then
            promoteCancel(menu)
            return
        end
        move(menu, added, base + index)
    end
    local now = menu.entries[menu.entryCount]
    if now == nil or signature(now) ~= topSignature then promoteCancel(menu) end
end

-- Run an action next tick if current() still returns true
function QueryMenus:Defer(current, action)
    return function()
        if not current() then return end
        self.pending[#self.pending + 1] = function()
            if current() then action() end
        end
        Event.Logic.Subscribe(ACTION_EVENT, function()
            Event.Logic.Unsubscribe(ACTION_EVENT)
            local pending = self.pending
            self.pending = {}
            for _, run in ipairs(pending) do pcall(run) end
        end)
    end
end

-- Get the pointer position in the scaled interface
local function pointer()
    if Mouse == nil or Mouse.GetPosition == nil then return nil, nil end
    local position = Mouse.GetPosition()
    if position == nil then return nil, nil end
    local interfaceScale = game ~= nil and game.options ~= nil and game.options.InterfaceScale or nil
    local percent = interfaceScale ~= nil and tonumber(interfaceScale.setting) or 100
    if percent <= 0 then percent = 100 end
    return position.x * 100 / percent, position.y * 100 / percent
end

-- Find the Search column row beneath the pointer, with the mounted context it was found in
function QueryMenus:RowAtPointer()
    local tab = self.app.tab
    local ctx = tab.ctx
    if ctx == nil or not tab:IsMounted() then return nil end
    local pointerX, pointerY = pointer()
    if pointerX == nil then return nil end
    local left, top, current = 0, 0, ctx.parent
    for _ = 1, 32 do
        if current == nil then break end
        left, top = left + (tonumber(current.x) or 0), top + (tonumber(current.y) or 0)
        current = current.parent
    end
    local x, y = math.floor(pointerX - left), math.floor(pointerY - top)
    if x < 0 or y < 0 or x >= ctx.width or y >= ctx.height then return nil end
    return tab:EntryAt(x, y), ctx
end

-- Show a name as a menu subject, without markup
local function plain(name)
    return (string.gsub(tostring(name), "[<>]", ""))
end

-- Offer the folder or saved-search actions for the clicked row
function QueryMenus:HandleMenu(menu)
    local app = self.app
    local ext = app.ext
    if ext == nil or ext:GetMenuItem(menu) ~= nil then return end
    local entry, ctx = self:RowAtPointer()
    if entry == nil then return end
    local store, tab = app.queries, app.tab
    local exists = entry.kind == "folder" and function() return store:GetFolder(entry.id) ~= nil end
        or function() return store:Get(entry.id) ~= nil end
    local current = function()
        return app.ext == ext and tab.ctx == ctx and tab:IsMounted() and exists()
    end
    local entries = {}
    -- Offer one action
    local function offer(label, name, action)
        entries[#entries + 1] = { label, plain(name), self:Defer(current, action) }
    end
    if entry.kind == "folder" then
        local folder = store:GetFolder(entry.id)
        if folder == nil then return end
        offer(folder.collapsed and "Expand" or "Collapse", folder.name, function() app:ToggleFolder(entry.id) end)
        offer("Rename folder", folder.name, function() app:OpenRenameFolder(entry.id) end)
        offer("Ungroup folder", folder.name, function() app:UngroupFolder(entry.id) end)
    else
        local record = store:Get(entry.id)
        if record == nil then return end
        offer("Edit", record.name, function() app:EditQuery(entry.id) end)
        offer("Move to folder...", record.name, function() app:OpenFolderChooser(entry.id) end)
        local folder = store:GetFolder(store:FolderOf(entry.id))
        if folder ~= nil then
            offer("Remove from folder", folder.name, function() app:MoveQueryToFolder(entry.id, nil) end)
        end
    end
    addLow(menu, entries)
end

return QueryMenus
