package.path = "./?.lua;" .. package.path

-- Rank bank stacks with the real RuneQL

local Ranking = require("advancedbanksearch/search/ranking")
local ItemFields = require("advancedbanksearch/search/item_fields")
local runeql = require("tools/test_support/runeql").Load()

local NAMES = {
    [101] = { name = "Iron bar", configName = "IRON_BAR" },
    [102] = { name = "Iron ore", configName = "IRON_ORE" },
    [103] = { name = "Iron axe", configName = "IRON_AXE" },
    [104] = { name = "Iron platebody", configName = "IRON_PLATEBODY" },
    [105] = { name = "Lobster", configName = "LOBSTER" },
}
config = { Obj = { FromID = function(objectID) return NAMES[objectID] end } }

-- A snapshot where 103 is a placeholder and 101 has two stacks
local ITEMS = {
    { objectID = 101, copy = 1, quantity = 5, placeholder = false },
    { objectID = 102, copy = 1, quantity = 5, placeholder = false },
    { objectID = 103, copy = 1, quantity = 0, placeholder = true },
    { objectID = 104, copy = 1, quantity = 5, placeholder = false },
    { objectID = 105, copy = 1, quantity = 9, placeholder = false },
    { objectID = 101, copy = 2, quantity = 3, placeholder = false },
}

-- Describe matches as object:copy in order
local function listed(matches)
    local parts = {}
    for index, match in ipairs(matches) do parts[index] = match.objectID .. ":" .. match.copy end
    return table.concat(parts, " ")
end

-- Run a search over the stand-in bank
local function search(text, options)
    options = options or {}
    return Ranking.Search({ runeql = runeql, text = text, items = ITEMS, nameOf = Ranking.NameReader(),
        excludePlaceholders = options.excludePlaceholders, prices = options.prices })
end

-- Text needs two characters once trimmed
assert(not Ranking.IsSearchable(" i ") and Ranking.IsSearchable("ir") and Ranking.Normalize("  Iron   Bar ") == "iron bar")

-- Equal scores keep bank order
local ranked = Ranking.Rank(ITEMS, function(item)
    if item.objectID == 105 then return nil end
    return item.objectID == 104 and 2 or 1
end)
assert(listed(ranked) == "104:1 101:1 102:1 103:1 101:2", listed(ranked))
assert(listed(Ranking.Rank(ITEMS, function() return 1 end, true)) == "101:1 102:1 104:1 105:1 101:2")
local slots = Ranking.Slots(ranked)
assert(slots[1].item == 104 and slots[1].copy == 1 and slots[5].item == 101 and slots[5].copy == 2)

-- Every iron stack matches by score, then bank order
-- The placeholder is included unless excluded; the lobster never matches
local outcome = search("iron")
assert(outcome.state == "ok")
local seen = {}
for index, match in ipairs(outcome.matches) do
    seen[match.objectID .. ":" .. match.copy] = true
    local nextMatch = outcome.matches[index + 1]
    if nextMatch ~= nil then
        assert(match.score > nextMatch.score or (match.score == nextMatch.score and match.index < nextMatch.index))
    end
end
assert(#outcome.matches == 5 and seen["101:1"] and seen["101:2"] and seen["103:1"] and not seen["105:1"])
assert(#search("iron", { excludePlaceholders = true }).matches == 4)
-- An exact name match ranks first
assert(search('name:"iron platebody"').matches[1].objectID == 104)
-- Quantity is a field RuneQL reads from the stack
assert(listed(search("qty:[6 TO *]").matches) == "105:1")

-- Text RuneQL cannot read reports its reason
local invalid = search("name:(iron")
assert(invalid.state == "invalid" and #invalid.reason > 0, invalid.reason)

-- RuneQL matches nothing for a missing field, but "not" a range does match it
-- So an unpriced ranking would be wrong, not empty
local plan = runeql.Compile("iron AND NOT price:[1 TO 100]")
assert(plan ~= nil and plan:Score({ name = "Iron bar", fields = {} }) ~= nil)
assert(plan:Score({ name = "Iron bar", fields = { price = 50 } }) == nil)
-- A query that is only a "not" matches nothing, as in Lucene
assert(runeql.Compile("NOT price:[1 TO *]"):Score({ name = "Iron bar", fields = {} }) == nil)
assert(runeql.Compile("price:[1 TO *]"):Score({ name = "Iron bar", fields = {} }) == nil)
-- Requirements name fields in lower case
assert(ItemFields.NeedsPrices(runeql.Compile("PRICE:[1 TO *]")))
assert(ItemFields.NeedsPrices(runeql.Compile("iron AND gehigh:[1 TO 5]")))
assert(not ItemFields.NeedsPrices(runeql.Compile("iron AND qty:[1 TO *]")))

-- Price queries are not ranked until GE Prices is ready
assert(search("iron AND NOT price:[1 TO 100]").state == "needs_prices")
local ready = false
local prices = {
    isReady = function() return ready end,
    -- As documented, an item without a price raises
    getPrice = function(objectID)
        if objectID == 105 then return { high = 200, low = 150 } end
        if objectID == 101 then return { high = 0, low = 40 } end
        error("Price not found for itemId: " .. tostring(objectID))
    end,
}
assert(search("price:[100 TO *]", { prices = prices }).state == "prices_loading")
-- Ready prices join each stack; missing or zero means no price
ready = true
assert(listed(search("price:[100 TO *]", { prices = prices }).matches) == "105:1")
assert(listed(search("gelow:[1 TO 50]", { prices = prices }).matches) == "101:1 101:2")
assert(listed(search("lobster AND gehigh:[200 TO 200]", { prices = prices }).matches) == "105:1")
-- A query without price fields never needs GE Prices
assert(search("lobster").state == "ok" and listed(search("lobster").matches) == "105:1")

print("ranking_test: ok")
