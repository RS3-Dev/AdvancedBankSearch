-- Connect RuneQL searches and saved queries to the native bank and filtered-page data

local StorageKeys = require("lib/features/storage_keys")
local BankInterface = require("lib/core/bank_interface")
local QueryItemFields = require("lib/features/search/query_item_fields")
local debugLog = require("lib/core/debug_log").Write

local BankNameSearch = {}

local SEARCH_SELECTION_ID = "__bankutils_search:name"
local SEARCH_HOST_STATIC_ID = 230 -- BANK__BOTTOM_PANEL_CONTENTS
local NATIVE_SEARCH_STATIC_IDS = {
    231, -- BANK__BANK_SEARCH_BUTTON_LAYER
    254, -- BANK__FILTER_RESULTS_LAYER
    257, -- BANK__BOTTOM_PANEL_CANCEL_SEARCH
}
local SEARCH_ICON_SPRITE_ID = 25230 -- TRH_ICON_SEARCH_QUERY_0
local SEARCH_X = 0
local SEARCH_Y = 3
local SEARCH_WIDTH = 170
local SEARCH_HEIGHT = 24
local SEARCH_ICON_SIZE = 18
local PARK_POSITION = -10000
local MINIMUM_QUERY_LENGTH = 2
local PRICE_WAIT_EVENT = "bankutils:runeql:price_wait"

-- Find a native bank component by its interface slot
local component = BankInterface.Get

-- Normalize spaces and casing before checking search text
local function normalize(value)
    return string.lower(tostring(value or ""))
        :match("^%s*(.-)%s*$")
        :gsub("%s+", " ")
end

-- Remember native search controls and their bounds so they can be parked and restored
function BankNameSearch:CaptureBankNameSearchComponents()
    self.components.bankSearchHost = component(SEARCH_HOST_STATIC_ID)
    self.components.nativeSearch = {}
    for _, staticID in ipairs(NATIVE_SEARCH_STATIC_IDS) do
        local value = component(staticID)
        if value ~= nil then
            self.components.nativeSearch[#self.components.nativeSearch + 1] = value
            self.original[value] = {
                x = value.x,
                y = value.y,
                width = value.width,
                height = value.height,
            }
        end
    end
end

-- Read the preference that enables the replacement RuneQL search field
function BankNameSearch:IsAdvancedBankSearchEnabled()
    return self.settings ~= nil and self.settings.enableAdvancedSearch == true
end

-- Park native search controls while the replacement field is active
function BankNameSearch:HideNativeBankSearch()
    for _, value in ipairs(self.components.nativeSearch or {}) do
        local original = self.original[value]
        if original ~= nil then value:SetPos(PARK_POSITION, original.y) end
    end
end

-- Return native search controls to their saved bounds
function BankNameSearch:RestoreNativeBankSearch()
    for _, value in ipairs(self.components.nativeSearch or {}) do
        local original = self.original[value]
        if original ~= nil then
            value:SetPos(original.x, original.y)
            value:SetSize(original.width, original.height)
        end
    end
end

-- Switch between replacement and native search when preferences change
function BankNameSearch:ApplyBankNameSearchSetting()
    if not self.active then return end
    if self:IsAdvancedBankSearchEnabled() then
        if self:CreateBankNameSearch() then self:HideNativeBankSearch() end
        return
    end

    if self:IsNameSearchSelection() then self:SetSelectedTag(nil) end
    self:DestroyBankNameSearch()
    self:ClearBankNameSearch(false)
    self:RestoreNativeBankSearch()
end

-- Recognize the temporary page used by the replacement bank search
function BankNameSearch:IsNameSearchSelection(value)
    return (value or self.selectedTag) == SEARCH_SELECTION_ID
end

-- Require enough search text before filtering the bank
function BankNameSearch:HasBankNameSearchQuery()
    return #normalize(self.bankSearchQuery) >= MINIMUM_QUERY_LENGTH
end

-- Check whether any normalized text remains in the search field
function BankNameSearch:HasBankNameSearchText()
    return normalize(self.bankSearchQuery) ~= ""
end

-- Cache item names from host definitions or saved tag records
function BankNameSearch:BankSearchObjectName(objectID)
    objectID = math.tointeger(tonumber(objectID))
    if objectID == nil then return nil end
    self.bankSearchNameCache = self.bankSearchNameCache or {}
    local cached = self.bankSearchNameCache[objectID]
    if cached ~= nil then return cached ~= false and cached or nil end

    local name = nil
    if config ~= nil and config.Obj ~= nil and config.Obj.FromID ~= nil then
        local ok, object = pcall(function() return config.Obj.FromID(objectID) end)
        if ok and object ~= nil then
            local nameOK, value = pcall(function() return object.name end)
            if nameOK and type(value) == "string" and value ~= "" then name = value end
        end
    end
    self.bankSearchNameCache[objectID] = name or false
    return name
end

-- Build a RuneQL scorer enriched with bank fields and any required prices
function BankNameSearch:BankQueryScorer(plan, selection)
    local service = QueryItemFields.Service()
    if QueryItemFields.NeedsPrices(plan) and not QueryItemFields.IsReady(service) then
        self:BeginRuneQueryPriceWait(selection, service)
    end
    local enrich = QueryItemFields.Enricher(plan, service)
    return function(_, name, item) return plan:Score(enrich(name, item)) end
end

-- End the temporary listener waiting for price data
function BankNameSearch:StopRuneQueryPriceWait()
    if self.runeQueryPriceWait ~= nil then
        Event.Logic.Unsubscribe(PRICE_WAIT_EVENT)
        self.runeQueryPriceWait = nil
    end
end

-- Recheck prices at intervals and refresh only while the same query remains selected
function BankNameSearch:BeginRuneQueryPriceWait(selection, service)
    if type(service) ~= "table" then
        debugLog("BankUtils price queries require the geprices dependency")
        return
    end
    debugLog("BankUtils is waiting for GE prices to load")
    self.runeQueryPriceWait = selection
    local ticks = 0
    Event.Logic.Subscribe(PRICE_WAIT_EVENT, function()
        ticks = ticks + 1
        if not self.active or self.selectedTag ~= selection then
            self:StopRuneQueryPriceWait()
        elseif ticks % 30 == 0 and QueryItemFields.IsReady(service) then
            self:StopRuneQueryPriceWait()
            self:ReapplySelectedTag(true)
            self:RefreshTags()
        elseif ticks >= 1800 then
            self:StopRuneQueryPriceWait()
            debugLog("BankUtils GE prices are unavailable; check geprices HTTP access")
        end
    end)
end

-- Collect current query matches without changing the active bank page
function BankNameSearch:RuneQueryResults(selection)
    local record = self.queryStore ~= nil
        and self.queryStore:GetBySelection(selection) or nil
    if record == nil then
        return nil, nil, "That RuneQL query no longer exists."
    end
    local plan, reason = runeql.Compile(record.query)
    if plan == nil then return nil, record, reason end
    local service = QueryItemFields.Service()
    if QueryItemFields.NeedsPrices(plan) and not QueryItemFields.IsReady(service) then
        return nil, record, "GE prices have not loaded yet. Check geprices HTTP access."
    end
    local enrich = QueryItemFields.Enricher(plan, service)

    -- The bank ranks its shown page's snapshot when one is shown, else the native items
    local items = self:CollectSearch(
        record.query,
        function(objectID) return self:BankSearchObjectName(objectID) end,
        function(_, name, item)
            return plan:Score(enrich(name, item))
        end,
        { excludePlaceholders = true }
    )
    if items == nil then
        return nil, record, "The current bank items are unavailable."
    end
    return items, record, nil
end

-- Clear transient search state and optionally its displayed field
function BankNameSearch:ClearBankNameSearch(updateField)
    self.bankSearchQuery = ""
    if updateField ~= false and self.bankSearchField ~= nil then
        self.bankSearchField:SetText("", false)
    end
end

-- Update search text and enter, refresh, or leave its temporary filtered page
function BankNameSearch:SetBankNameSearchQuery(value)
    local query = tostring(value or "")
    self.bankSearchQuery = query
    if #normalize(query) < MINIMUM_QUERY_LENGTH then
        if self:IsNameSearchSelection() then
            self.preserveBankSearchQueryOnDeselect = true
            self:SetSelectedTag(nil)
            self.preserveBankSearchQueryOnDeselect = false
        end
        return
    end

    if self:IsNameSearchSelection() then
        self:ReapplySelectedTag(true)
    else
        self:SetSelectedTag(SEARCH_SELECTION_ID)
    end
end

-- Create the replacement search field on the bank's native search host
function BankNameSearch:CreateBankNameSearch()
    self:DestroyBankNameSearch()
    if not self:IsAdvancedBankSearchEnabled() then return false end
    local parent = self.components.bankSearchHost
    if parent == nil then
        debugLog("Bank Utilities could not find the native bank search host")
        return false
    end

    self.bankSearchLayer = ui.Layer.new(parent)
    self.bankSearchLayer:SetPos(SEARCH_X, SEARCH_Y)
    self.bankSearchLayer:SetSize(SEARCH_WIDTH, SEARCH_HEIGHT)
    self.bankSearchLayer.clickthrough = false

    self.bankSearchField = prettyui.TextField.new(self.bankSearchLayer, {
        x = 0,
        y = 0,
        width = SEARCH_WIDTH,
        height = SEARCH_HEIGHT,
        placeholder = "Search items...",
        text = self.bankSearchQuery or "",
        maxLength = StorageKeys.LONG_INPUT_LIMIT,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        contentMargin = ui.Margin.new(28, 2, 8, 0),
        onChange = function(_, _, content)
            self:SetBankNameSearchQuery(content)
        end,
    })

    self.bankSearchIcon = ui.Sprite.new(self.bankSearchLayer)
    self.bankSearchIcon:SetPos(4, 3)
    self.bankSearchIcon:SetSize(SEARCH_ICON_SIZE, SEARCH_ICON_SIZE)
    self.bankSearchIcon.spriteID = SEARCH_ICON_SPRITE_ID
    self.bankSearchIcon.clickthrough = true
    self.bankSearchIcon:MoveToFront()
    self.bankSearchLayer:MoveToFront()
    return true
end

-- Stop price waiting and destroy the replacement search controls
function BankNameSearch:DestroyBankNameSearch()
    self:StopRuneQueryPriceWait()
    if self.bankSearchField ~= nil then
        pcall(function() self.bankSearchField:Destroy() end)
    end
    self.bankSearchField = nil
    self.bankSearchIcon = nil
    if self.bankSearchLayer ~= nil then
        pcall(function() self.bankSearchLayer:Destroy() end)
    end
    self.bankSearchLayer = nil
end

-- Attach this module's methods to the owner that holds their shared state
function BankNameSearch.install(target)
    for name, method in pairs(BankNameSearch) do
        if name ~= "install" then target[name] = method end
    end
end

BankNameSearch.SELECTION_ID = SEARCH_SELECTION_ID
BankNameSearch.MINIMUM_QUERY_LENGTH = MINIMUM_QUERY_LENGTH

return BankNameSearch
