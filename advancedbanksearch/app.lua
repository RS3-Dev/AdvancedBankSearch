-- Show RuneQL search and saved queries through Bank Core's API
-- RuneQL, GE Prices, and Bank Tags are read only while reported loaded

local FolderDialog = require("advancedbanksearch/search/folder_dialog")
local ItemFields = require("advancedbanksearch/search/item_fields")
local QueryEditor = require("advancedbanksearch/search/query_editor")
local QueryMenus = require("advancedbanksearch/search/query_menus")
local QueryStore = require("advancedbanksearch/search/query_store")
local Ranking = require("advancedbanksearch/search/ranking")
local SearchTab = require("advancedbanksearch/search/search_tab")
local TagSource = require("advancedbanksearch/search/tag_source")

local App = {}
App.__index = App

local OWNER_ID = "advancedbanksearch"
local OWNER_LABEL = "Advanced Bank Search"
local TAB_ID = "search"
local SEARCH_PAGE = "search"
local QUERY_PAGE = "query"
local PRICE_WAIT_EVENT = "advancedbanksearch_price_wait"
local SEARCH_WAIT_EVENT = "advancedbanksearch_search_wait"
-- Ticks without typing before a search runs, 200 ms at 50 a second
local SEARCH_WAIT_TICKS = 10
-- Logic ticks between GE Prices checks, and before giving up
local PRICE_CHECK_TICKS = 30
local PRICE_WAIT_LIMIT = 1800
-- Where each dependency publishes its API if not injected
local PUBLISHED = { bankcore = "__bankcore_api", runeql = "__runeql_api", geprices = "__geprices_api" }
-- Not-ready reasons that mean the bank is not open at all
local CLOSED = { stale_api = true, not_ready = true, bank_closed = true }

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

-- Load saved queries and build the tab, before connecting
function App.new()
    local app = setmetatable({
        queries = QueryStore.new(),
        -- Whether each optional dependency was last reported loaded
        -- A plugin's globals can stick around after it unloads
        enabled = { runeql = true, geprices = true, banktags = true },
        bank = nil,
        handle = nil,
        -- The last bank read, kept while Bank Core is still building
        snapshot = nil,
        -- The search text, with a counter so a new search starts at the top
        text = "",
        serial = 0,
        -- The field's text and the wait before it becomes the search text
        draft = "",
        searchWait = nil,
        -- Chosen, shown, and delete-pending queries, plus last match counts
        selectedQuery = nil,
        pageQuery = nil,
        confirmDelete = nil,
        counts = {},
        -- The shown page and key, and a summary of each page's last sent layout
        shownPage = nil,
        shownKey = nil,
        published = {},
        -- The shown outcome, its price wait, and the page key that gave up waiting
        -- A failed key stays failed until GE Prices or the key changes
        outcome = nil,
        priceWait = nil,
        pricesFailed = nil,
        status = nil,
        statusIsError = false,
        editor = nil,
        folderDialog = nil,
        retired = false,
        started = false,
        shutDown = false,
    }, App)
    app.tab = SearchTab.new(app)
    app.menus = QueryMenus.new(app)
    -- The import source Bank Tags lists while it is loaded
    app.tagSource = TagSource.new(app)
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
    self:Connect()
    self.tagSource:Connect()
end

-- Report whether this plugin is registered with Bank Core
function App:IsConnected()
    return self.handle ~= nil and self.handle:GetState().live == true
end

-- Register the Search tab, its two pages, and the listener
function App:Connect()
    if self.shutDown then return false, "stopped" end
    if self:IsConnected() then return true end
    -- A newer load of this plugin owns the ID now, so leave it
    if self.handle ~= nil and self.bank.GetState().running then
        self.handle, self.bank, self.retired = nil, nil, true
        self:Disconnect()
    end
    if self.retired then return false, "replaced" end
    self:Disconnect()
    local api = findDependency(bankcore, "bankcore", "RegisterExtension")
    if api == nil or not api.GetState().running then return false, "unavailable" end
    local handle, reason = api.RegisterExtension(OWNER_ID, OWNER_LABEL)
    if handle == nil then return false, reason end
    self.bank, self.handle = api, handle
    local ok, failure = true, nil
    for _, pageID in ipairs({ SEARCH_PAGE, QUERY_PAGE }) do
        if ok then
            ok, failure = handle:RegisterPage(pageID, { title = "Search", layout = { { label = "No search yet" } } })
        end
    end
    if ok then
        ok, failure = handle:RegisterTab(TAB_ID, { label = "Search", icon = "SEARCH",
            tooltip = "Search your bank with RuneQL", mount = self.tab.callbacks })
    end
    if ok then
        ok, failure = handle:SetListener({
            onState = function(state) self:OnState(state) end,
            onPage = function(pageID, key) self:OnPage(pageID, key) end,
            onBankItems = function() self:OnBankItems() end,
        })
    end
    if not ok then
        self:Disconnect()
        return false, failure
    end
    self.menus:Start()
    self.tagSource:Update()
    return true
end

-- Drop the handle, menus, waits, dialogs, and last bank read
function App:Disconnect()
    self.menus:Stop()
    self:StopSearchWait()
    self:StopPriceWait()
    self:CloseEditor()
    self:CloseFolderDialog()
    local handle = self.handle
    self.handle, self.bank = nil, nil
    self.snapshot, self.shownPage, self.shownKey, self.outcome, self.published = nil, nil, nil, nil, {}
    if handle ~= nil then pcall(function() handle:Dispose() end) end
    self.tagSource:Update()
end

-- Follow a dependency loading or unloading
function App:DependencyChanged(name, enabled)
    if self.enabled[name] == nil then return end
    self.enabled[name] = enabled == true
    if name == "runeql" then
        if not enabled and self.shownPage ~= nil and self.handle ~= nil then self.handle:LeavePage() end
        if not enabled then
            self:StopSearchWait()
            self:ShowStatus(NEEDS_RUNEQL, true)
        elseif self.status == NEEDS_RUNEQL then
            self:ShowStatus(nil)
        end
    elseif name == "geprices" then
        self:StopPriceWait()
        self.pricesFailed = nil
        self:RefreshPage()
    elseif name == "banktags" then
        if enabled then self.tagSource:Connect() else self.tagSource:Disconnect() end
    end
    self.tagSource:Update()
    self:Refresh()
end

-- Drop the last bank read, typed search, and windows when the bank closes
function App:OnState(state)
    if not state.running or CLOSED[state.reason] then
        self.snapshot = nil
        self:StopSearchWait()
        self:CloseEditor()
        self:CloseFolderDialog()
    end
end

-- Track the shown page; leaving a page ends its price wait
function App:OnPage(pageID, key)
    self.shownPage, self.shownKey = pageID, key
    if self.priceWait ~= nil and self.priceWait.key ~= key then self:StopPriceWait() end
    if pageID == nil then self.outcome = nil end
    self:Refresh()
end

-- Rank the shown page again, keeping its key and scroll
function App:OnBankItems()
    self:ReadBank()
    self:RefreshPage()
end

-- Read the bank, keeping the last items while Core builds
function App:ReadBank()
    if self.handle == nil then return nil end
    local snapshot, reason = self.handle:GetBankItems()
    if snapshot ~= nil then
        self.snapshot = snapshot
    elseif reason == "bank_closed" then
        self.snapshot = nil
    end
    return self.snapshot
end

-- Search the bank with text and rank the result
function App:Run(text, excludePlaceholders)
    local engine = self:RuneQL()
    if engine == nil then return { state = "needs_runeql" } end
    local snapshot = self:ReadBank()
    if snapshot == nil then return { state = "no_items" } end
    return Ranking.Search({ runeql = engine, text = text, items = snapshot.items,
        excludePlaceholders = excludePlaceholders, prices = self:Prices(), nameOf = Ranking.NameReader() })
end

-- Lay out an outcome as stacks, or one label saying why not
local function layoutFor(outcome)
    if outcome.state == "ok" and #outcome.matches > 0 then return { { slots = Ranking.Slots(outcome.matches) } } end
    local described = OUTCOMES[outcome.state == "ok" and "empty" or outcome.state]
    return { { label = described.label } }
end

-- Show an outcome in the tab's status line
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

-- Summarise a page so unchanged pages are not resent
local function signature(page)
    local parts = { page.title, page.key }
    for _, row in ipairs(page.layout) do
        if row.label ~= nil then
            parts[#parts + 1] = "L" .. row.label
        else
            for _, slot in ipairs(row.slots) do parts[#parts + 1] = slot.item .. ":" .. slot.copy end
        end
    end
    return table.concat(parts, "\n")
end

-- Describe the search or saved-query page and its outcome
function App:BuildPage(pageID)
    if pageID == SEARCH_PAGE then
        local outcome = self:Run(self.text, false)
        return { title = "Search", key = "search:" .. self.serial, layout = layoutFor(outcome) }, outcome
    end
    local record = self.queries:Get(self.pageQuery)
    if record == nil then return nil end
    local outcome = self:Run(record.query, true)
    self.counts[record.id] = outcome.state == "ok" and #outcome.matches or nil
    return { title = record.name, key = "query:" .. record.id, layout = layoutFor(outcome) }, outcome
end

-- Send a changed page to Bank Core and show its status
-- Wait for GE prices when the outcome needs them
function App:PutPage(pageID)
    local page, outcome = self:BuildPage(pageID)
    if page == nil then return false, "unknown_query" end
    if outcome.state == "prices_loading" and self.pricesFailed == page.key then
        outcome = { state = "prices_failed" }
        page.layout = layoutFor(outcome)
    end
    self.outcome = outcome
    local text = signature(page)
    if self.published[pageID] ~= text then
        local ok, reason = self.handle:UpdatePage(pageID, page)
        if not ok then
            self:ShowStatus("Bank Core refused the page (" .. tostring(reason) .. ").", true)
            return false, reason
        end
        self.published[pageID] = text
    end
    self:ShowOutcome(outcome)
    if outcome.state == "prices_loading" then
        self:StartPriceWait(page.key, pageID)
    elseif self.priceWait ~= nil and self.priceWait.key == page.key then
        self:StopPriceWait()
    end
    return true, page.key
end

-- Show a page through the tab, or through Core when the tab isn't shown
-- Going through the tab shows Core's View All guidance on refusal
function App:ShowPage(pageID)
    local ok, key = self:PutPage(pageID)
    if not ok then return false end
    local ctx = self.tab.ctx
    local opened, reason
    if ctx ~= nil then
        opened, reason = ctx:OpenPage(pageID)
    else
        opened, reason = self.handle:OpenPage(pageID)
    end
    if opened then
        self.shownPage, self.shownKey = pageID, key
    else
        self:ShowStatus("The bank cannot show results now (" .. tostring(reason) .. ").", true)
    end
    return opened, reason
end

-- Rank the shown page again after a change
function App:RefreshPage()
    if self.handle == nil or self.shownPage == nil then return end
    if self.shownPage == QUERY_PAGE and self.queries:Get(self.pageQuery) == nil then
        self.handle:LeavePage()
        return
    end
    self:PutPage(self.shownPage)
    self:Refresh()
end

-- Show the search page for long enough text, or leave it
function App:SetText(text)
    self:StopSearchWait()
    self.text = tostring(text or "")
    self.draft = self.text
    self.confirmDelete = nil
    if self.handle == nil then return end
    if self:RuneQL() == nil then
        self:ShowStatus(NEEDS_RUNEQL, true)
        self:Refresh()
        return
    end
    self:StopPriceWait()
    if not Ranking.IsSearchable(self.text) then
        if self.shownPage == SEARCH_PAGE then self.handle:LeavePage() end
        self:ShowStatus(nil)
        self:Refresh()
        return
    end
    self.serial = self.serial + 1
    self:ShowPage(SEARCH_PAGE)
    self:Refresh()
end

-- Show a saved query's page, or leave it if already shown
-- Choosing one drops typed text still waiting to search
function App:ChooseQuery(queryID)
    self.confirmDelete = nil
    if self.queries:Get(queryID) == nil then return false end
    if self.handle == nil then return false end
    self:StopSearchWait()
    if self.shownPage == QUERY_PAGE and self.pageQuery == queryID then
        self.selectedQuery = queryID
        self.handle:LeavePage()
        self:Refresh()
        return true
    end
    self.selectedQuery, self.pageQuery = queryID, queryID
    self:StopPriceWait()
    if self:RuneQL() == nil then
        self:ShowStatus(NEEDS_RUNEQL, true)
        self:Refresh()
        return false
    end
    local opened = self:ShowPage(QUERY_PAGE)
    self:Refresh()
    return opened
end

-- Search typed text once typing pauses for SEARCH_WAIT_TICKS
-- Short text and searches that can't run take effect at once
function App:QueueText(text)
    self.draft = tostring(text or "")
    self.confirmDelete = nil
    if self.handle == nil or self:RuneQL() == nil or not Ranking.IsSearchable(self.draft) then
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
        if wait.ticks >= SEARCH_WAIT_TICKS then self:SetText(self.draft) end
    end)
end

-- Stop waiting to search typed text
function App:StopSearchWait()
    if self.searchWait == nil then return end
    self.searchWait = nil
    Event.Logic.Unsubscribe(SEARCH_WAIT_EVENT)
end

-- Recheck prices every PRICE_CHECK_TICKS ticks, up to the limit
-- The wait ends once its page or key is no longer shown
function App:StartPriceWait(key, pageID)
    if self.priceWait ~= nil and self.priceWait.key == key then return end
    self:StopPriceWait()
    local wait = { key = key, pageID = pageID, ticks = 0 }
    self.priceWait = wait
    Event.Logic.Subscribe(PRICE_WAIT_EVENT, function()
        if self.priceWait ~= wait then return end
        wait.ticks = wait.ticks + 1
        if self.handle == nil or self.shownKey ~= key then
            self:StopPriceWait()
        elseif wait.ticks % PRICE_CHECK_TICKS == 0 and ItemFields.IsReady(self:Prices()) then
            self:StopPriceWait()
            self:RefreshPage()
        elseif wait.ticks >= PRICE_WAIT_LIMIT then
            self:StopPriceWait()
            self.pricesFailed = key
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
    if self.shownPage == QUERY_PAGE and self.pageQuery == record.id and self.handle ~= nil then
        self.handle:LeavePage()
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
    local editor
    editor = QueryEditor.new(parent, {
        record = record,
        blocked = self:RuneQL() == nil and NEEDS_RUNEQL or nil,
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
    if self.shownPage == QUERY_PAGE and self.pageQuery == record.id and self.handle ~= nil then
        self:RefreshPage()
    end
    self:Refresh()
    return true
end

-- Show a line in the tab's status, or clear it with nil
function App:ShowStatus(text, isError)
    self.status = text
    self.statusIsError = isError == true
end

-- Redraw the tab
function App:Refresh()
    self.tab:Refresh()
end

-- Release the menus, windows, waits, and registration
function App:Shutdown()
    if self.shutDown then return end
    self.shutDown = true
    pcall(function() self:Disconnect() end)
    pcall(function() self.tagSource:Disconnect() end)
end

return App
