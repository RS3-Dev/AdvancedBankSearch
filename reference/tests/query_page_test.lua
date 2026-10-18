package.path = "./?.lua;./?/init.lua;" .. package.path

-- Check that saved query pages are titled, built, counted, and recovered through their page
-- description, with placeholders, invalid and deleted queries, and price waits as before
-- Run all tests with Lua 5.4: lua54 tools/check.lua (toolchain notes in STAGE0_BASELINE.md)

local FakeBankHost = require("tools/test_support/fake_bank_host")
local host = FakeBankHost.install()
local TagStore = require("lib/features/tags/tag_store")
local QueryStore = require("lib/features/runesql/query_store")
local QueryPage = require("lib/features/runesql/query_page")
local TagPage = require("lib/features/tags/tag_page")
local CleanupPage = require("lib/features/cleanup/cleanup_page")
local NameSearchPage = require("lib/features/search/name_search_page")
local BankNameSearch = require("lib/features/search/bank_name_search")

-- Equal-length names tie on score, so bank order decides them; 103 is a placeholder
local function stockBank()
    host:SetItems({
        { 101, 5, "Iron bar" },
        { 102, 5, "Iron ore" },
        { 103, 0, "Iron axe" },
        { 104, 5, "Iron platebody" },
        { 105, 5, "Lobster" },
    })
end
stockBank()

-- A query whose text starts with "priced" needs GE prices and otherwise matches the rest
local compile = runeql.Compile
runeql.Compile = function(query)
    local priced = string.match(query, "^priced (.+)$")
    local plan, reason = compile(priced or query)
    if plan ~= nil and priced ~= nil then
        plan.Requirements = function() return { price = true } end
    end
    return plan, reason
end

local queries = QueryStore.new()
local _, iron = queries:Save(nil, "Iron", "iron")
local _, broken = queries:Save(nil, "Broken", "invalid(")
local _, priced = queries:Save(nil, "Priced", "priced iron")
local IRON = QueryStore.SelectionID(iron.id)
local BROKEN = QueryStore.SelectionID(broken.id)
local PRICED = QueryStore.SelectionID(priced.id)
local MISSING = QueryStore.SelectionID("999")

local store = TagStore.new()
store:SetLayoutPlacement(false)
assert(store:CreateTag("ores"))
assert(store:AddTag("ores", 102))
local layout, features = host:NewLayout(store, { queryStore = queries, settings = { enableRuneSQL = true } })
local sidebarRefreshes = 0
layout.RefreshTags = function() sidebarRefreshes = sidebarRefreshes + 1 end
-- The features refresh their own rows, such as the query counts
features.RefreshTags = layout.RefreshTags

-- Count query page builds and the count updates that follow them
local builds, recorded = 0, {}
local queryApply = QueryPage.Apply
QueryPage.Apply = function(owner, selection)
    assert(owner == layout)
    builds = builds + 1
    return queryApply(owner, selection)
end
local recordCount = QueryPage.RecordMatchCount
QueryPage.RecordMatchCount = function(owner, selection, matchCount)
    recorded[#recorded + 1] = selection .. "=" .. tostring(matchCount)
    return recordCount(owner, selection, matchCount)
end

-- Return and reset the builds and count updates
local function take()
    local result = builds .. " [" .. table.concat(recorded, " ") .. "]"
    builds, recorded = 0, {}
    return result
end

-- List the displayed objects in display order
local function shown()
    local entries = layout:VisibleMirrorEntries()
    table.sort(entries, function(left, right)
        if left.y == right.y then return left.x < right.x end
        return left.y < right.y
    end)
    local objects = {}
    for _, entry in ipairs(entries) do
        objects[#objects + 1] = tostring(entry.objectID) .. (entry.placeholder and "p" or "")
    end
    return table.concat(objects, " ")
end

-- Lookup and titles: a saved query names its page; a deleted one reads RuneQL
assert(layout:SelectionPage(IRON) == QueryPage and layout:SelectionPage(MISSING) == QueryPage)
assert(layout:IsGeneratedSelection(IRON) and QueryPage.isMembershipEditable == false)
assert(layout:DisplayTagName(IRON) == "Iron" and layout:DisplayTagName(MISSING) == "RuneQL")
-- Without saved queries the same ID is an ordinary tag name, as before
local plain = host:NewLayout(store, {})
assert(plain:SelectionPage(IRON) == TagPage)
plain.selectedTag = IRON
assert(plain:FailedRebindRecovery() == nil)

-- Selecting builds once, leaves the placeholder out of the page and count, and records it
assert(layout:SetSelectedTag(IRON))
assert(take() == "1 [" .. IRON .. "=3]")
assert(shown() == "101 102 104", shown())
assert(features.runeQueryCounts[iron.id] == 3)

-- A refresh without force rebinds the same page without a build or count update
assert(layout:ReapplySelectedTag())
assert(take() == "0 []" and features.runeQueryCounts[iron.id] == 3)

-- A forced reapply after a withdrawal rebuilds once through the same count update
host:Rebuild(function(specs)
    specs[2][2] = 0
    return specs
end)
assert(layout:ReapplySelectedTag(true))
assert(take() == "1 [" .. IRON .. "=2]")
assert(shown() == "101 104", shown())
assert(features.runeQueryCounts[iron.id] == 2)
stockBank()

-- A query RuneQL cannot compile publishes an empty page and a zero count
assert(layout:SetSelectedTag(BROKEN))
assert(take() == "1 [" .. BROKEN .. "=0]")
assert(layout.pageState.active and shown() == "" and features.runeQueryCounts[broken.id] == 0)

-- A selection without a saved record stays selected with no page and a zero count
assert(layout:SetSelectedTag(MISSING))
assert(take() == "1 [" .. MISSING .. "=0]")
assert(layout.selectedTag == MISSING and not layout.pageState.active)
assert(features.runeQueryCounts["999"] == 0)

-- Deleting the selected query empties its page on the next forced reapply
local _, doomed = queries:Save(nil, "Doomed", "iron")
local DOOMED = QueryStore.SelectionID(doomed.id)
assert(layout:SetSelectedTag(DOOMED))
assert(take() == "1 [" .. DOOMED .. "=3]")
assert(queries:Delete(doomed.id))
assert(layout:ReapplySelectedTag(true))
assert(take() == "1 [" .. DOOMED .. "=0]" and not layout.pageState.active)
assert(layout:DisplayTagName(DOOMED) == "RuneQL")

-- Other pages build without a query count update
assert(layout:SetSelectedTag("ores"))
assert(take() == "0 []" and shown() == "102")

-- A price query shows what it can, waits for prices, then rebuilds and recounts once
geprices = { getPrice = function() return { high = 10 } end, isReady = function() return false end }
assert(layout:SetSelectedTag(PRICED))
assert(take() == "1 [" .. PRICED .. "=3]")
assert(features.runeQueryPriceWait == PRICED and host:Listener("price_wait") ~= nil)
for _ = 1, 29 do host:Tick() end
assert(take() == "0 []")
local ready = false
geprices.isReady = function() return ready end
ready = true
sidebarRefreshes = 0
host:Tick()
assert(take() == "1 [" .. PRICED .. "=3]", "price wait did not rebuild once")
assert(host:Listener("price_wait") == nil and features.runeQueryPriceWait == nil)
assert(sidebarRefreshes == 1)

-- Leaving a waiting price query stops the wait without another build
ready = false
assert(layout:SetSelectedTag(nil))
assert(layout:SetSelectedTag(PRICED))
take()
assert(host:Listener("price_wait") ~= nil)
assert(layout:SetSelectedTag("ores"))
assert(host:Listener("price_wait") == nil and features.runeQueryPriceWait == nil)
for _ = 1, 60 do host:Tick() end
assert(take() == "0 []" and layout.selectedTag == "ores")
geprices = nil

-- Failed-rebind recovery is read from the selected page each time it is asked
layout.selectedTag = IRON
assert(layout:FailedRebindRecovery() == "recreate_input")
QueryPage.failedRebindRecovery = nil
assert(layout:FailedRebindRecovery() == nil, "recovery policy was cached")
QueryPage.failedRebindRecovery = "recreate_input"
assert(layout:FailedRebindRecovery() == "recreate_input")
for _, page in ipairs({ TagPage, CleanupPage, NameSearchPage }) do
    assert(page.failedRebindRecovery == nil and page.RecordMatchCount == nil)
end
for _, selection in ipairs({
    "ores",
    "__bankutils_cleanup:metal_bank",
    BankNameSearch.SELECTION_ID,
}) do
    layout.selectedTag = selection
    assert(layout:FailedRebindRecovery() == nil, selection)
end
layout.selectedTag = nil
assert(layout:FailedRebindRecovery() == nil)

QueryPage.Apply = queryApply
QueryPage.RecordMatchCount = recordCount
runeql.Compile = compile
print("query_page_test: ok")
