-- Show RuneQL search and saved queries through Bank Core's API
-- RuneQL and GE Prices are read only while reported loaded

local FolderDialog = require("resources/search/folder_dialog")
local ItemFields = require("resources/search/item_fields")
local QueryBuilder = require("resources/search/query_builder")
local QueryEditor = require("resources/search/query_editor")
local QueryMenus = require("resources/search/query_menus")
local QueryStore = require("resources/search/query_store")
local Ranking = require("resources/search/ranking")
local SearchTab = require("resources/search/search_tab")
local Settings = require("resources/settings")

local App = {}
App.__index = App

local OWNER_ID = "advancedbanksearch"
local OWNER_LABEL = "Advanced Bank Search"
local SEARCH_PAGE = "search"
local QUERY_PAGE = "query"
local PRICE_WAIT_EVENT = "advancedbanksearch_price_wait"
local SEARCH_WAIT_EVENT = "advancedbanksearch_search_wait"
-- Logic ticks between GE Prices checks, and before giving up
local PRICE_CHECK_TICKS = 30
local PRICE_WAIT_LIMIT = 1800
-- Where each dependency publishes its API if not injected
local PUBLISHED = { bankcore = "__bankcore_api", runeql = "__runeql_api", geprices = "__geprices_api" }
-- What the player can do when Bank Core cannot open the results
local OPEN_REFUSALS = {
    not_all_items = 'Select "All Items" to view these search results.',
    preset_open = "Close the preset selector to view these search results.",
    search_active = "Clear the bank search to view these search results.",
    filter_active = "Clear the bank filter to view these search results.",
    bank_closed = "Open your bank to view these search results.",
    busy = "The bank is still updating. Try again.",
}

local function bankStateBlocker(state)
    if state == nil then return "stale" end
    if not state.bankOpen then return "bank_closed" end
    if state.presetOpen then return "preset_open" end
    if state.searchActive then return "search_active" end
    if state.filterActive then return "filter_active" end
    if not state.viewAll then return "not_all_items" end
    return nil
end

local NEEDS_RUNEQL = "Searching needs RuneQL. Enable RuneQL to search your bank."

-- Page text and status line for each outcome without items
local OUTCOMES = {
    empty = { label = "No items match", status = "No items match." },
    needs_runeql = { label = "This search needs RuneQL", status = NEEDS_RUNEQL },
    invalid = { label = "RuneQL could not read this search" },
    needs_prices = { label = "This search needs GE Prices", status = "Price fields need GE Prices. Enable GE Prices to use them." },
    prices_loading = { label = "Waiting for GE prices...", status = "Waiting for GE prices..." },
    prices_failed = { label = "GE prices did not load", status = "GE prices did not load; check GE Prices' HTTP access." },
    no_items = { label = "The bank's items are not available yet", status = "Open All Items to search your bank." },
}

-- Find a dependency's API that offers the called function
local function findDependency(injected, name, method)
    -- Either may be nil, so loop by index instead of ipairs
    local candidates = { injected, rawget(_G, PUBLISHED[name]) }
    for index = 1, 2 do
        local candidate = candidates[index]
        if type(candidate) == "table" and type(candidate[method]) == "function" then return candidate end
    end
    return nil
end

-- Load saved queries and build the column, before connecting
function App.new()
    QueryBuilder.SetCatalog(findDependency(runeql, "runeql", "Compile"))
    local app = setmetatable({
        queries = QueryStore.new(),
        settings = Settings.new(),
        -- Whether each optional dependency was last reported loaded
        -- A plugin's globals can stick around after it unloads
        enabled = { runeql = true, geprices = true },
        ext = nil,
        -- The last bank read, kept while Bank Core is busy
        items = nil,
        -- The search text
        text = "",
        -- The field's text and the wait before it becomes the search text
        draft = "",
        searchWait = nil,
        -- Chosen, page, and delete-pending queries, plus last match counts
        selectedQuery = nil,
        pageQuery = nil,
        confirmDelete = nil,
        counts = {},
        -- The page last given to Bank Core: SEARCH_PAGE or QUERY_PAGE
        pageID = nil,
        -- The shown page's price wait, and whether it gave up; a new page waits afresh
        priceWait = nil,
        pricesFailed = false,
        status = nil,
        statusIsError = false,
        editor = nil,
        folderDialog = nil,
        started = false,
        shutDown = false,
    }, App)
    app.tab = SearchTab.new(app)
    app.menus = QueryMenus.new(app)
    app.settings.onChange = function(key)
        if key == "includePlaceholders" and app:ShownPage() == SEARCH_PAGE then app:RefreshPage() end
        if key == "searchDelayTicks" and app.searchWait ~= nil then
            app:StopSearchWait()
            app:QueueText(app.draft)
        end
    end
    if app.queries.loadError ~= nil then app:ShowStatus(app.queries.loadError, true) end
    return app
end

-- Return RuneQL's API while it is reported loaded
function App:RuneQL()
    if not self.enabled.runeql then return nil end
    return findDependency(runeql, "runeql", "Compile")
end

-- Return the GE price service while it is reported loaded
function App:Prices()
    if not self.enabled.geprices then return nil end
    return findDependency(geprices, "geprices", "getPrice")
end

-- Connect to Bank Core if it runs
function App:Start()
    if self.shutDown or self.started then return end
    self.started = true
    self.settings:Start()
    self:Connect()
end

-- Report whether this plugin is registered with Bank Core
function App:IsConnected()
    return self.ext ~= nil
end

-- Register the Search icon, its column, and what the bank tells this plugin
-- Registering again replaces the earlier registration
function App:Connect()
    if self.shutDown then return false, "stopped" end
    self:Disconnect()
    local api = findDependency(bankcore, "bankcore", "Register")
    if api == nil then return false, "unavailable" end
    local ext, reason = api.Register({
        id = OWNER_ID, name = OWNER_LABEL, icon = "SEARCH", column = self.tab.callbacks,
        onClose = function() self:OnClose() end,
        onBankItems = function() self:OnBankItems() end,
        onBankClose = function() self:OnBankClose() end,
        onBankStateChanged = function(state) self:OnBankStateChanged(state) end,
    })
    if ext == nil then return false, reason end
    self.ext = ext
    self:OnBankStateChanged(ext:GetBankState())
    self.menus:Start()
    return true
end

-- Drop the registration, menus, waits, dialogs, and last bank read
function App:Disconnect()
    self.menus:Stop()
    self:StopSearchWait()
    self:StopPriceWait()
    self:CloseEditor()
    self:CloseFolderDialog()
    local ext = self.ext
    self.ext, self.items, self.pageID = nil, nil, nil
    if self.status == self.bankStateError then self:ShowStatus(nil) end
    self.bankStateError = nil
    if ext ~= nil then ext:Dispose() end
end

-- Follow a dependency loading or unloading
function App:DependencyChanged(name, enabled)
    if self.enabled[name] == nil then return end
    self.enabled[name] = enabled == true
    if name == "runeql" then
        self:CloseEditor()
        QueryBuilder.SetCatalog(self:RuneQL())
        if not enabled and self.ext ~= nil then self.ext:Close() end
        if not enabled then
            self:StopSearchWait()
            self:ShowStatus(NEEDS_RUNEQL, true)
        elseif self.status == NEEDS_RUNEQL then
            self:ShowStatus(nil)
        end
    elseif name == "geprices" then
        self:StopPriceWait()
        self.pricesFailed = false
        self:RefreshPage()
    end
    self:Refresh()
end

-- Name the page the bank shows when it is this plugin's, or nil
function App:ShownPage()
    if self.ext == nil or not self.ext:IsOpen() then return nil end
    return self.pageID
end

-- Refresh the column once this plugin's page stops showing; its price wait ends
function App:OnClose()
    self:StopPriceWait()
    self:Refresh()
end

-- Retire results and pending work when native bank controls restrict the view.
-- Core may already have closed the page before delivering the state callback.
function App:OnBankStateChanged(state)
    if self.ext == nil then return "stale" end
    local blocked = bankStateBlocker(state)
    if blocked ~= nil then
        local hadResults = self.pageID ~= nil or self.searchWait ~= nil
        self:StopSearchWait()
        self:StopPriceWait()
        if self.ext:IsOpen() then self.ext:Close() end
        self.pageID = nil
        if hadResults then self:ShowBankStateError(blocked) end
    elseif self.bankStateError ~= nil then
        if self.status == self.bankStateError then self:ShowStatus(nil) end
        self.bankStateError = nil
    end
    self:Refresh()
    return blocked
end

function App:ShowBankStateError(reason)
    self.bankStateError = OPEN_REFUSALS[reason]
        or ("The bank cannot show results now (" .. tostring(reason) .. ").")
    self:ShowStatus(self.bankStateError, true)
end

-- Rank the last page again for the bank's new items
function App:OnBankItems()
    self:ReadBank()
    self:RefreshPage()
end

-- Drop the last bank read, typed search, and windows when the bank closes
function App:OnBankClose()
    self.items = nil
    self:StopSearchWait()
    self:CloseEditor()
    self:CloseFolderDialog()
end

-- Read the bank, keeping the last items while Core is busy or outside All Items
function App:ReadBank()
    if self.ext == nil then return nil end
    local items, reason = self.ext:GetBankItems()
    if items ~= nil then
        self.items = items
    elseif reason == "bank_closed" then
        self.items = nil
    end
    return self.items
end

-- Search the bank with text and rank the result
function App:Run(text, excludePlaceholders)
    local engine = self:RuneQL()
    if engine == nil then return { state = "needs_runeql" } end
    local items = self:ReadBank()
    if items == nil then return { state = "no_items" } end
    return Ranking.Search({ runeql = engine, text = text, items = items,
        excludePlaceholders = excludePlaceholders, prices = self:Prices(), nameOf = Ranking.NameReader() })
end

-- Lay out an outcome as stacks, or one label saying why not
local function rowsFor(outcome)
    if outcome.state == "ok" and #outcome.matches > 0 then return { { slots = Ranking.Slots(outcome.matches) } } end
    local described = OUTCOMES[outcome.state == "ok" and "empty" or outcome.state]
    return { { label = described.label } }
end

-- Show an outcome in the column's status line
function App:ShowOutcome(outcome)
    if outcome.state == "ok" then
        local count = #outcome.matches
        self:ShowStatus(count == 0 and OUTCOMES.empty.status or (count .. (count == 1 and " match." or " matches.")))
    elseif outcome.state == "invalid" then
        self:ShowStatus("RuneQL could not read this search: " .. outcome.reason, true)
    else
        self:ShowStatus(OUTCOMES[outcome.state].status, outcome.state ~= "prices_loading")
    end
end

-- Describe the search or saved-query page and its outcome
-- Prices that gave up waiting say so
function App:BuildPage(pageID)
    local title, text, excludePlaceholders = "Search", self.text, not self.settings.values.includePlaceholders
    local record = nil
    if pageID == QUERY_PAGE then
        record = self.queries:Get(self.pageQuery)
        if record == nil then return nil end
        title, text, excludePlaceholders = record.name, record.query, true
    end
    local outcome = self:Run(text, excludePlaceholders)
    if outcome.state == "prices_loading" and self.pricesFailed then outcome = { state = "prices_failed" } end
    if record ~= nil then self.counts[record.id] = outcome.state == "ok" and #outcome.matches or nil end
    return { title = title, rows = rowsFor(outcome) }, outcome
end

-- Rank a page and give it to Bank Core, which redraws it in place while it shows
function App:SetPage(pageID)
    local page, outcome = self:BuildPage(pageID)
    if page == nil then return false end
    local ok, reason = self.ext:SetPage(page)
    if not ok then
        self:ShowStatus("Bank Core refused the page (" .. tostring(reason) .. ").", true)
        return false
    end
    self.pageID = pageID
    return true, outcome
end

-- Show a shown page's outcome, waiting for GE prices when it needs them
function App:FollowOutcome(outcome)
    self:ShowOutcome(outcome)
    if outcome.state == "prices_loading" then self:StartPriceWait() else self:StopPriceWait() end
end

-- Show a new search or saved query: set its page, then open it
-- A refusal goes to the column's status line
function App:ShowPage(pageID)
    if self.ext == nil then return false end
    local blocked = self:OnBankStateChanged(self.ext:GetBankState())
    if blocked ~= nil then
        self:ShowBankStateError(blocked)
        return false, blocked
    end
    self:StopPriceWait()
    self.pricesFailed = false
    local set, outcome = self:SetPage(pageID)
    if not set then return false end
    local opened, reason = self.ext:Open()
    if opened then
        self:FollowOutcome(outcome)
    else
        self:ShowBankStateError(reason)
    end
    return opened, reason
end

-- Rank the last page again after a change; only a shown page updates the status
function App:RefreshPage()
    if self.ext == nil or self.pageID == nil then return end
    local set, outcome = self:SetPage(self.pageID)
    if set and self.ext:IsOpen() then self:FollowOutcome(outcome) end
    self:Refresh()
end

-- Show the search page for long enough text, or leave it
function App:SetText(text)
    self:StopSearchWait()
    self.text = tostring(text or "")
    self.draft = self.text
    self.confirmDelete = nil
    if self.ext == nil then return end
    if self:RuneQL() == nil then
        self:ShowStatus(NEEDS_RUNEQL, true)
        self:Refresh()
        return
    end
    if not Ranking.IsSearchable(self.text) then
        if self:ShownPage() == SEARCH_PAGE then self.ext:Close() end
        self:ShowStatus(nil)
        self:Refresh()
        return
    end
    self:ShowPage(SEARCH_PAGE)
    self:Refresh()
end

-- Show a saved query's page, or leave it if already shown
-- Choosing one drops typed text still waiting to search
function App:ChooseQuery(queryID)
    self.confirmDelete = nil
    if self.queries:Get(queryID) == nil then return false end
    if self.ext == nil then return false end
    self:StopSearchWait()
    if self:ShownPage() == QUERY_PAGE and self.pageQuery == queryID then
        self.selectedQuery = queryID
        self.ext:Close()
        self:Refresh()
        return true
    end
    self.selectedQuery, self.pageQuery = queryID, queryID
    if self:RuneQL() == nil then
        self:ShowStatus(NEEDS_RUNEQL, true)
        self:Refresh()
        return false
    end
    local opened = self:ShowPage(QUERY_PAGE)
    self:Refresh()
    return opened
end

-- Search once typing pauses for the preferred delay
-- Short text and searches that can't run take effect at once
function App:QueueText(text)
    self.draft = tostring(text or "")
    self.confirmDelete = nil
    if self.ext == nil or self:RuneQL() == nil or not Ranking.IsSearchable(self.draft) then
        self:SetText(self.draft)
        return
    end
    if self.searchWait ~= nil then
        self.searchWait.ticks = 0
        return
    end
    local wait = { ticks = 0 }
    self.searchWait = wait
    Event.Logic.Subscribe(SEARCH_WAIT_EVENT, function()
        if self.searchWait ~= wait then return end
        wait.ticks = wait.ticks + 1
        if wait.ticks >= self.settings.values.searchDelayTicks then self:SetText(self.draft) end
    end)
end

-- Stop waiting to search typed text
function App:StopSearchWait()
    if self.searchWait == nil then return end
    self.searchWait = nil
    Event.Logic.Unsubscribe(SEARCH_WAIT_EVENT)
end

-- Recheck prices for the shown page every PRICE_CHECK_TICKS ticks, up to the limit
-- The wait ends once the page stops showing
function App:StartPriceWait()
    if self.priceWait ~= nil then return end
    local wait = { ticks = 0 }
    self.priceWait = wait
    Event.Logic.Subscribe(PRICE_WAIT_EVENT, function()
        if self.priceWait ~= wait then return end
        wait.ticks = wait.ticks + 1
        if self.ext == nil or not self.ext:IsOpen() then
            self:StopPriceWait()
        elseif wait.ticks % PRICE_CHECK_TICKS == 0 and ItemFields.IsReady(self:Prices()) then
            self:StopPriceWait()
            self:RefreshPage()
        elseif wait.ticks >= PRICE_WAIT_LIMIT then
            self:StopPriceWait()
            self.pricesFailed = true
            self:RefreshPage()
        end
    end)
end

-- Stop waiting for GE prices
function App:StopPriceWait()
    if self.priceWait == nil then return end
    self.priceWait = nil
    Event.Logic.Unsubscribe(PRICE_WAIT_EVENT)
end

-- Open the editor for a new query
function App:NewQuery()
    self.confirmDelete = nil
    self:OpenEditor(nil)
end

-- Open the editor for a query, the chosen one by default
function App:EditQuery(queryID)
    self.confirmDelete = nil
    local record = self.queries:Get(queryID or self.selectedQuery)
    if record ~= nil then self:OpenEditor(record) end
end

-- Delete the chosen query when Delete is pressed twice
function App:DeleteQuery()
    local record = self.queries:Get(self.selectedQuery)
    if record == nil then return false end
    if self.confirmDelete ~= record.id then
        self.confirmDelete = record.id
        self:ShowStatus('Press Delete again to delete "' .. record.name .. '".', true)
        self:Refresh()
        return false
    end
    self.confirmDelete = nil
    local deleted, reason = self.queries:Delete(record.id)
    if not deleted then
        self:ShowStatus(reason, true)
        self:Refresh()
        return false
    end
    self.counts[record.id] = nil
    if self.editor ~= nil and self.editor.queryID == record.id then self:CloseEditor() end
    -- The deleted query's page closes and is not ranked again
    if self.pageID == QUERY_PAGE and self.pageQuery == record.id then
        self.ext:Close()
        self.pageID = nil
    end
    self.selectedQuery = nil
    self:ShowStatus('Deleted "' .. record.name .. '".')
    self:Refresh()
    return true
end

-- Find the layer standalone windows open on
local function windowParent()
    return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_LAYER)
        or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
end

-- Open the query editor, replacing any open one
function App:OpenEditor(record)
    self:CloseEditor()
    self:CloseFolderDialog()
    local parent = windowParent()
    if parent == nil then return false end
    local engine = self:RuneQL()
    local editor
    editor = QueryEditor.new(parent, {
        record = record,
        defaultMode = self.settings.values.editorMode,
        catalog = engine and engine.Catalog,
        blocked = engine == nil and NEEDS_RUNEQL or nil,
        onSave = function(queryID, name, query, builder)
            return self:SaveQuery(queryID, name, query, builder)
        end,
        onClose = function()
            if self.editor == editor then self.editor = nil end
        end,
    })
    self.editor = editor
    editor:Show()
    return true
end

-- Close the query editor
function App:CloseEditor()
    local editor = self.editor
    self.editor = nil
    if editor ~= nil then pcall(function() editor:Destroy() end) end
end

-- Open a folder dialog, replacing the editor or a dialog already open
function App:OpenFolderDialog(options)
    self:CloseEditor()
    self:CloseFolderDialog()
    local parent = windowParent()
    if parent == nil then return false end
    local dialog
    options.onClose = function()
        if self.folderDialog == dialog then self.folderDialog = nil end
    end
    dialog = FolderDialog.new(parent, options)
    self.folderDialog = dialog
    dialog:Show()
    return true
end

-- Close the folder dialog
function App:CloseFolderDialog()
    local dialog = self.folderDialog
    self.folderDialog = nil
    if dialog ~= nil then pcall(function() dialog:Destroy() end) end
end

-- Choose a query's folder, no folder, or a new folder
function App:OpenFolderChooser(queryID)
    local record = self.queries:Get(queryID)
    if record == nil then return false end
    local current = self.queries:FolderOf(queryID)
    local choices = {}
    if current ~= nil then choices[1] = { id = "", label = "No folder" } end
    for _, folder in ipairs(self.queries:Folders()) do
        if folder.id ~= current then choices[#choices + 1] = { id = folder.id, label = folder.name } end
    end
    return self:OpenFolderDialog({ title = "Move to Folder", heading = record.name, choices = choices,
        placeholder = "New folder name", saveLabel = "Create",
        onChoose = function(folderID) return self:MoveQueryToFolder(queryID, folderID ~= "" and folderID or nil) end,
        onSave = function(name) return self:CreateFolder(name, queryID) end })
end

-- Rename a folder through the folder dialog
function App:OpenRenameFolder(folderID)
    local folder = self.queries:GetFolder(folderID)
    if folder == nil then return false end
    return self:OpenFolderDialog({ title = "Rename Folder", heading = folder.name, text = folder.name,
        onSave = function(name) return self:RenameFolder(folderID, name) end })
end

-- Redraw after a folder or order change and report any refusal
function App:FolderChanged(fromTab, ok, reason)
    if not ok and reason ~= nil and fromTab then self:ShowStatus(reason, true) end
    self:Refresh()
    return ok, reason
end

-- Collapse or expand a folder, keeping the shown page
function App:ToggleFolder(folderID)
    local folder = self.queries:GetFolder(folderID)
    if folder == nil then return false end
    return self:FolderChanged(true, self.queries:SetFolderCollapsed(folderID, not folder.collapsed))
end

-- Move a query into a folder, or out with nil
function App:MoveQueryToFolder(queryID, folderID)
    return self:FolderChanged(false, self.queries:MoveToFolder(queryID, folderID))
end

-- Create a folder holding a query
function App:CreateFolder(name, queryID)
    local ok, _, reason = self.queries:CreateFolder(name, queryID)
    return self:FolderChanged(false, ok, reason)
end

-- Rename a folder
function App:RenameFolder(folderID, name)
    return self:FolderChanged(false, self.queries:RenameFolder(folderID, name))
end

-- Remove a folder, keeping its queries
function App:UngroupFolder(folderID)
    return self:FolderChanged(true, self.queries:DeleteFolder(folderID))
end

-- Move a folder or query one step among its siblings
function App:MoveEntry(kind, entryID, offset)
    return self:FolderChanged(true, self.queries:Move(kind, entryID, offset))
end

-- Save a query from the editor once RuneQL can read it
-- Visual conditions are kept only when they give the same text
-- A saved query is counted again when its page shows
function App:SaveQuery(queryID, name, query, builder)
    local engine = self:RuneQL()
    if engine == nil then return false, NEEDS_RUNEQL end
    local plan, queryReason = engine.Compile(query)
    if plan == nil then return false, tostring(queryReason or "RuneQL could not read this query.") end
    local saved, record, reason = self.queries:Save(queryID, name, query, builder)
    if not saved then return false, reason end
    self.counts[record.id] = nil
    self.selectedQuery = record.id
    self:ShowStatus('Saved "' .. record.name .. '".')
    if self:ShownPage() == QUERY_PAGE and self.pageQuery == record.id then self:RefreshPage() end
    self:Refresh()
    return true
end

-- Show a line in the column's status, or clear it with nil
function App:ShowStatus(text, isError)
    self.status = text
    self.statusIsError = isError == true
end

-- Redraw the column
function App:Refresh()
    self.tab:Refresh()
end

-- Release the menus, windows, waits, and registration
function App:Shutdown()
    if self.shutDown then return end
    self.shutDown = true
    self.settings:Shutdown()
    pcall(function() self:Disconnect() end)
end

return App
