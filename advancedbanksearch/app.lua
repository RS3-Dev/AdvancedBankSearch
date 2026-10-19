-- Compose Advanced Bank Search: saved queries, the Search tab, the search and query pages,
-- the wait for GE prices, and the connection to Bank Core's public API. Through that API it
-- registers its mounted tab, two pages, and a listener, and reads the bank only through Bank
-- Core's item snapshots. RuneQL, GE Prices, and Bank Tags are optional dependencies, each
-- read only while the host last reported it loaded

local ItemFields = require("advancedbanksearch/search/item_fields")
local QueryEditor = require("advancedbanksearch/search/query_editor")
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
local CONTENT_EVENT = "advancedbanksearch_content"
local PRICE_WAIT_EVENT = "advancedbanksearch_price_wait"
-- How often a price wait checks GE Prices, and when it gives up, in logic ticks
local PRICE_CHECK_TICKS = 30
local PRICE_WAIT_LIMIT = 1800
-- Where each optional dependency publishes its API when its injected copy is missing
local PUBLISHED = { bankcore = "__bankcore_api", runeql = "__runeql_api", geprices = "__geprices_api" }
-- Readiness reasons that mean the bank is not open at all
local CLOSED = { stale_api = true, not_ready = true, bank_closed = true }

local NOT_CONNECTED = "Advanced Bank Search needs Bank Core. Enable Bank Core to search your bank."
local CONNECTED = "Advanced Bank Search is in your bank: open the bank and choose the Search tab in the sidebar."
local REPLACED = "A newer copy of Advanced Bank Search took over; this copy is idle."
local NEEDS_RUNEQL = "Searching needs RuneQL. Enable RuneQL to search your bank."

-- What a page shows, and the status line beside it, for each outcome that is not a list of items
local OUTCOMES = {
    empty = { label = "No items match", status = "No items match." },
    needs_runeql = { label = "This search needs RuneQL", status = NEEDS_RUNEQL },
    invalid = { label = "RuneQL could not read this search" },
    needs_prices = { label = "This search needs GE Prices", status = "Price fields need GE Prices. Enable GE Prices to use them." },
    prices_loading = { label = "Waiting for GE prices...", status = "Waiting for GE prices..." },
    prices_failed = { label = "GE prices did not load", status = "GE prices did not load; check GE Prices' HTTP access." },
    no_items = { label = "The bank's items are not available yet", status = "Open All Items to search your bank." },
}

-- Find a dependency's API: the injected global first, the published copy second, and only one
-- that offers the function the plugin calls
local function findDependency(injected, name, method)
    -- Either may be missing, so both are checked by position rather than with ipairs
    local candidates = { injected, rawget(_G, PUBLISHED[name]) }
    for index = 1, 2 do
        local candidate = candidates[index]
        if type(candidate) == "table" and type(candidate[method]) == "function" then return candidate end
    end
    return nil
end

-- Load the saved queries and build the tab, connected to nothing and subscribed to nothing
function App.new()
    local app = setmetatable({
        queries = QueryStore.new(),
        -- Whether the host last reported each optional dependency loaded; an unloaded plugin's
        -- injected global and published copy can outlive it
        enabled = { runeql = true, geprices = true, banktags = true },
        bank = nil,
        handle = nil,
        -- The last bank snapshot read, kept while Bank Core is still building
        snapshot = nil,
        -- The search text, and a serial that changes with it so a new search starts at the top
        text = "",
        serial = 0,
        -- The query chosen in the tab, the one the query page shows, the one whose delete
        -- waits for confirmation, and the last match count of each
        selectedQuery = nil,
        pageQuery = nil,
        confirmDelete = nil,
        counts = {},
        -- What Bank Core shows: the page and key, and what each page was last given
        shownPage = nil,
        shownKey = nil,
        published = {},
        -- The outcome the shown page was built from, the price wait for the shown key, and
        -- the key whose wait gave up, which stays failed until GE Prices or the key changes
        outcome = nil,
        priceWait = nil,
        pricesFailed = nil,
        status = nil,
        statusIsError = false,
        editor = nil,
        panel = nil,
        retired = false,
        started = false,
        shutDown = false,
    }, App)
    app.tab = SearchTab.new(app)
    -- The import source Bank Tags lists while it is loaded
    app.tagSource = TagSource.new(app)
    if app.queries.loadError ~= nil then app:ShowStatus(app.queries.loadError, true) end
    return app
end

-- Return RuneQL's API while the host reports it loaded, or nil
function App:RuneQL()
    if not self.enabled.runeql then return nil end
    return findDependency(runeql, "runeql", "Compile")
end

-- Return the GE price service while the host reports it loaded, or nil
function App:Prices()
    if not self.enabled.geprices then return nil end
    return findDependency(geprices, "geprices", "getPrice")
end

-- Subscribe to this plugin's panel and connect to Bank Core if it runs
function App:Start()
    if self.shutDown or self.started then return end
    self.started = true
    Event.ContentLayerReady.Subscribe(CONTENT_EVENT, function(event) self:CreatePanel(event.component) end)
    self:Connect()
    self.tagSource:Connect()
end

-- Report whether this plugin's owner is registered with a running Bank Core
function App:IsConnected()
    return self.handle ~= nil and self.handle:GetState().live == true
end

-- Register the Search tab, its two pages, and the listener with the running Bank Core
function App:Connect()
    if self.shutDown then return false, "stopped" end
    if self:IsConnected() then return true end
    -- A newer load of this plugin took the owner ID; taking it back would undo that
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
    self.tagSource:Update()
    self:UpdatePanelNotice()
    return true
end

-- Drop the owner handle, the price wait, the editor, and the bank snapshot; saved queries stay
function App:Disconnect()
    self:StopPriceWait()
    self:CloseEditor()
    local handle = self.handle
    self.handle, self.bank = nil, nil
    self.snapshot, self.shownPage, self.shownKey, self.outcome, self.published = nil, nil, nil, nil, {}
    if handle ~= nil then pcall(function() handle:Dispose() end) end
    self.tagSource:Update()
    self:UpdatePanelNotice()
end

-- Follow the host's report that an optional dependency loaded or unloaded
function App:DependencyChanged(name, enabled)
    if self.enabled[name] == nil then return end
    self.enabled[name] = enabled == true
    if name == "runeql" then
        if not enabled and self.shownPage ~= nil and self.handle ~= nil then self.handle:LeavePage() end
        if not enabled then
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

-- A closed bank drops the snapshot and the editor; the snapshot is read again on reopening
function App:OnState(state)
    if not state.running or CLOSED[state.reason] then
        self.snapshot = nil
        self:CloseEditor()
    end
end

-- Remember which of this plugin's pages Bank Core shows; leaving a page ends its price wait
function App:OnPage(pageID, key)
    self.shownPage, self.shownKey = pageID, key
    if self.priceWait ~= nil and self.priceWait.key ~= key then self:StopPriceWait() end
    if pageID == nil then self.outcome = nil end
    self:Refresh()
end

-- Rank the shown page again over the bank's new items, keeping its key and scroll position
function App:OnBankItems()
    self:ReadBank()
    self:RefreshPage()
end

-- Read the bank's items, keeping the last snapshot while Bank Core is still building
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

-- Rank text over the bank: an outcome with a state and, when "ok", its matches
function App:Run(text, excludePlaceholders)
    local engine = self:RuneQL()
    if engine == nil then return { state = "needs_runeql" } end
    local snapshot = self:ReadBank()
    if snapshot == nil then return { state = "no_items" } end
    return Ranking.Search({ runeql = engine, text = text, items = snapshot.items,
        excludePlaceholders = excludePlaceholders, prices = self:Prices(), nameOf = Ranking.NameReader() })
end

-- Lay out an outcome as page rows: its stacks, or one label saying why there are none
local function layoutFor(outcome)
    if outcome.state == "ok" and #outcome.matches > 0 then return { { slots = Ranking.Slots(outcome.matches) } } end
    local described = OUTCOMES[outcome.state == "ok" and "empty" or outcome.state]
    return { { label = described.label } }
end

-- Say what an outcome found in the tab's status line
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

-- Summarise a page as text, so an unchanged page is not sent to Bank Core again
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

-- Describe the page for the search text or a saved query, with the outcome it shows
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

-- Give Bank Core a page when it changed, and follow its outcome: the status line, and a wait
-- while GE prices load
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

-- Show one of this plugin's pages: through the tab's context, so a refusal shows Bank Core's
-- View All guidance, or the handle when the tab is not mounted
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

-- Rank the shown page again, as after a bank or dependency change
function App:RefreshPage()
    if self.handle == nil or self.shownPage == nil then return end
    if self.shownPage == QUERY_PAGE and self.queries:Get(self.pageQuery) == nil then
        self.handle:LeavePage()
        return
    end
    self:PutPage(self.shownPage)
    self:Refresh()
end

-- Follow the search field: text long enough shows the search page from the top, and shorter
-- text leaves it
function App:SetText(text)
    self.text = tostring(text or "")
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

-- Show a saved query's page, or return to the bank's own view when it is already shown
function App:ChooseQuery(queryID)
    self.confirmDelete = nil
    if self.queries:Get(queryID) == nil then return false end
    if self.handle == nil then return false end
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

-- Check every PRICE_CHECK_TICKS ticks whether prices loaded for the shown page, then rank it
-- again; give up after the limit. The wait ends when its page or key is no longer shown
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

-- Open the editor for the chosen query
function App:EditQuery()
    self.confirmDelete = nil
    local record = self.queries:Get(self.selectedQuery)
    if record ~= nil then self:OpenEditor(record) end
end

-- Delete the chosen query once its deletion is confirmed by pressing Delete again
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

-- Open the query editor, replacing one already open. Saving needs RuneQL
function App:OpenEditor(record)
    self:CloseEditor()
    local parent = windowParent()
    if parent == nil then return false end
    local editor
    editor = QueryEditor.new(parent, {
        record = record,
        blocked = self:RuneQL() == nil and NEEDS_RUNEQL or nil,
        onSave = function(queryID, name, query) return self:SaveQuery(queryID, name, query) end,
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

-- Save a query from the editor once RuneQL can read it, then show the change; a failed save
-- changes nothing. A saved query's old count is dropped, and counted again when its page shows
function App:SaveQuery(queryID, name, query)
    local engine = self:RuneQL()
    if engine == nil then return false, NEEDS_RUNEQL end
    local plan, queryReason = engine.Compile(query)
    if plan == nil then return false, tostring(queryReason or "RuneQL could not read this query.") end
    local saved, record, reason = self.queries:Save(queryID, name, query)
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

-- Redraw the tab and the panel notice
function App:Refresh()
    self.tab:Refresh()
    self:UpdatePanelNotice()
end

-- Say whether the plugin is in the bank, or why not
function App:PanelNotice()
    if self:IsConnected() then
        return CONNECTED .. (self:RuneQL() == nil and (" " .. NEEDS_RUNEQL) or "")
    end
    return self.retired and REPLACED or NOT_CONNECTED
end

-- Show the current notice on an open plugin panel
function App:UpdatePanelNotice()
    if self.panel ~= nil then self.panel.content = self:PanelNotice() end
end

-- Show the notice on this plugin's own panel, connecting first if Bank Core started
function App:CreatePanel(parent)
    if self.shutDown then return end
    self:Connect()
    self:DestroyPanel()
    self.panel = prettyui.Text.new(parent, {
        text = self:PanelNotice(), x = 12, y = 12, width = math.max(1, (parent.width or 300) - 24),
        height = 80, font = id.Font.MUSEO_SANS_11PT_REGULAR, colour = 0xD7C9ADFF, maxLines = 4,
    })
end

-- Release the panel's text
function App:DestroyPanel()
    local panel = self.panel
    self.panel = nil
    if panel ~= nil then pcall(function() panel:Destroy() end) end
end

-- Stop the plugin: release its panel, editor, price wait, and Bank Core registration
function App:Shutdown()
    if self.shutDown then return end
    self.shutDown = true
    if self.started then Event.ContentLayerReady.Unsubscribe(CONTENT_EVENT) end
    pcall(function() self:DestroyPanel() end)
    pcall(function() self:Disconnect() end)
    pcall(function() self.tagSource:Disconnect() end)
end

return App
