package.path = "./?.lua;" .. package.path

-- Rank bank stacks with the real RuneQL

local Ranking = require("resources/search/ranking")
local ItemFields = require("resources/search/item_fields")
local runeql = require("tools/test_support/runeql").Load()

local NAMES = {
    [101] = { name = "Iron bar", configName = "IRON_BAR" },
    [102] = { name = "Iron ore", configName = "IRON_ORE" },
    [103] = { name = "Iron axe", configName = "IRON_AXE" },
    [104] = { name = "Iron platebody", configName = "IRON_PLATEBODY" },
    [105] = { name = "Lobster", configName = "LOBSTER" },
}
config = { Obj = { FromID = function(objectID) return NAMES[objectID] end } }

-- Bank items as Bank Core reads them: 103 is a placeholder and 101 has two stacks
local ITEMS = {
    { objectID = 101, quantity = 5 },
    { objectID = 102, quantity = 5 },
    { objectID = 103, quantity = 0 },
    { objectID = 104, quantity = 5 },
    { objectID = 105, quantity = 9 },
    { objectID = 101, quantity = 3 },
}

-- Describe matches as object@bank position in order
local function listed(matches)
    local parts = {}
    for index, match in ipairs(matches) do parts[index] = match.objectID .. "@" .. match.index end
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
assert(listed(ranked) == "104@4 101@1 102@2 103@3 101@6", listed(ranked))
assert(listed(Ranking.Rank(ITEMS, function() return 1 end, true)) == "101@1 102@2 104@4 105@5 101@6")
-- Slots name each match's object, once per matching stack
assert(table.concat(Ranking.Slots(ranked), " ") == "104 101 102 103 101")

-- Every iron stack matches by score, then bank order
-- The placeholder is included unless excluded; the lobster never matches
local outcome = search("iron")
assert(outcome.state == "ok")
local seen = {}
for index, match in ipairs(outcome.matches) do
    seen[match.objectID .. "@" .. match.index] = true
    local nextMatch = outcome.matches[index + 1]
    if nextMatch ~= nil then
        assert(match.score > nextMatch.score or (match.score == nextMatch.score and match.index < nextMatch.index))
    end
end
assert(#outcome.matches == 5 and seen["101@1"] and seen["101@6"] and seen["103@3"] and not seen["105@5"])
assert(#search("iron", { excludePlaceholders = true }).matches == 4)
-- An exact name match ranks first
assert(search('name:"iron platebody"').matches[1].objectID == 104)
-- Quantity is a field RuneQL reads from the stack
assert(listed(search("qty:[6 TO *]").matches) == "105@5")

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
assert(listed(search("price:[100 TO *]", { prices = prices }).matches) == "105@5")
assert(listed(search("gelow:[1 TO 50]", { prices = prices }).matches) == "101@1 101@6")
assert(listed(search("lobster AND gehigh:[200 TO 200]", { prices = prices }).matches) == "105@5")
-- A query without price fields never needs GE Prices
assert(search("lobster").state == "ok" and listed(search("lobster").matches) == "105@5")

print("ranking_test: ok")
