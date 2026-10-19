-- Offer saved queries to Bank Tags' Import window through its published import-source API: the
-- player types a saved query's name, and the source answers with a draft of one tag holding
-- the stacks the query matches now. Bank Tags gives a repeated object its next copy in the
-- order listed, so a draft names exactly the matched stacks only when each object's matched
-- copies are 1 to k; any other match is refused rather than tagging another copy

local Ranking = require("advancedbanksearch/search/ranking")

local TagSource = {}
TagSource.__index = TagSource

local OWNER_ID = "advancedbanksearch"
local OWNER_LABEL = "Advanced Bank Search"
local PROVIDER_ID = "saved-search"
local API_KEY = "__banktags_api"
-- Bank Tags reads at most 2,000 draft entries; the row itself is one of them
local MAX_STACKS = 1999

-- Why a request failed, kept within Bank Tags' 120-character message limit
local FAILURES = {
    bank_closed = "Open your bank to convert a saved search.",
    not_all_items = 'Select "All Items" in your bank to convert a saved search.',
    building = "Your bank is still loading; try again in a moment.",
    invalid = "RuneQL could not read this saved search.",
    needs_prices = "This saved search uses price fields, which need GE Prices.",
    prices_loading = "GE prices have not loaded yet; try again in a moment.",
    empty = "This saved search matches nothing in your bank.",
}

-- Create the source for an app, registered with nothing
function TagSource.new(app)
    return setmetatable({ app = app, api = nil, handle = nil, retired = false, unavailable = nil }, TagSource)
end

-- Find a running Bank Tags API: the injected dependency first, the published copy second
local function findTags()
    -- Either may be missing, so both are checked by position rather than with ipairs
    local candidates = { banktags, rawget(_G, API_KEY) }
    for index = 1, 2 do
        local candidate = candidates[index]
        if type(candidate) == "table" and type(candidate.RegisterExtension) == "function"
            and type(candidate.GetState) == "function" and candidate.GetState().running then
            return candidate
        end
    end
    return nil
end

-- Say why the source cannot be used now, or nil when it can
function TagSource:Unavailable()
    if not self.app:IsConnected() then return "Advanced Bank Search needs Bank Core to read your bank." end
    if self.app:RuneQL() == nil then return "Converting a saved search needs RuneQL." end
    return nil
end

-- Describe the source for Bank Tags
function TagSource:Provider()
    return {
        label = "Saved bank search", icon = "SEARCH", input = "text",
        prompt = "Saved search name", placeholder = "Type a saved search's name...",
        unavailable = self.unavailable,
        request = function(request) self:Answer(request) end,
    }
end

-- Register the source with the running Bank Tags, unless a newer copy of this plugin took the
-- owner ID there
function TagSource:Connect()
    if self.handle ~= nil and self.handle:GetState().live then return true end
    if self.handle ~= nil and self.api.GetState().running then self.retired = true end
    self:Disconnect()
    if self.retired or not self.app.enabled.banktags then return false end
    local api = findTags()
    if api == nil then return false end
    local handle = api.RegisterExtension(OWNER_ID, OWNER_LABEL)
    if handle == nil then return false end
    self.unavailable = self:Unavailable()
    if not handle:RegisterImportProvider(PROVIDER_ID, self:Provider()) then
        pcall(function() handle:Dispose() end)
        return false
    end
    self.api, self.handle = api, handle
    return true
end

-- Remove the source from Bank Tags
function TagSource:Disconnect()
    local handle = self.handle
    self.api, self.handle = nil, nil
    if handle ~= nil then pcall(function() handle:Dispose() end) end
end

-- Tell Bank Tags when the source becomes usable or unusable
function TagSource:Update()
    if self.handle == nil then return end
    local unavailable = self:Unavailable()
    if unavailable == self.unavailable then return end
    self.unavailable = unavailable
    self.handle:UpdateImportProvider(PROVIDER_ID, self:Provider())
end

-- Find the first object whose matched copies are not 1 to k, or nil when every one is
local function inexactObject(matches)
    local copies = {}
    for _, match in ipairs(matches) do
        local list = copies[match.objectID] or {}
        copies[match.objectID] = list
        list[match.copy] = true
    end
    for objectID, list in pairs(copies) do
        local count = 0
        for _ in pairs(list) do count = count + 1 end
        for copy = 1, count do
            if not list[copy] then return objectID end
        end
    end
    return nil
end

-- Answer one request with a draft of the saved query's current matches, or say why not
function TagSource:Answer(request)
    local app = self.app
    local name = Ranking.Normalize(request.input)
    local record = app.queries:FindName(name)
    if record == nil then
        request:Fail("No saved search has that name.")
        return
    end
    local engine = app:RuneQL()
    if engine == nil or app.handle == nil then
        request:Fail(self:Unavailable() or "Advanced Bank Search cannot read your bank now.")
        return
    end
    local snapshot, reason = app.handle:GetBankItems()
    if snapshot == nil then
        request:Fail(FAILURES[reason] or FAILURES.bank_closed)
        return
    end
    local nameOf = Ranking.NameReader()
    local outcome = Ranking.Search({ runeql = engine, text = record.query, items = snapshot.items,
        excludePlaceholders = true, prices = app:Prices(), nameOf = nameOf })
    if outcome.state ~= "ok" then
        request:Fail(FAILURES[outcome.state])
        return
    end
    local matches = outcome.matches
    if #matches == 0 then
        request:Fail(FAILURES.empty)
        return
    end
    if #matches > MAX_STACKS then
        request:Fail("This search matches " .. #matches .. " stacks; Bank Tags imports at most 1,999.")
        return
    end
    local inexact = inexactObject(matches)
    if inexact ~= nil then
        local itemName = string.sub(nameOf(inexact) or ("item " .. inexact), 1, 40)
        request:Fail(itemName .. ": a later stack matched without the first, so it cannot be tagged exactly.")
        return
    end
    local row = {}
    for index, match in ipairs(matches) do row[index] = match.objectID end
    -- Bank Tags refuses commas in tag names
    local tagName = Ranking.Normalize(string.gsub(record.name, ",", " "))
    request:Resolve({ tags = { { name = tagName, rows = { row } } } })
end

return TagSource
