package.path = "./?.lua;" .. package.path

-- Check built RuneQL text, then what the real RuneQL makes of it

local QueryBuilder = require("advancedbanksearch/search/query_builder")
local Ranking = require("advancedbanksearch/search/ranking")
local runeql = require("tools/test_support/runeql").Load()

-- Build conditions, failing the test when they are refused
local function build(match, rules)
    local query, saved, reason = QueryBuilder.Build({ match = match, rules = rules })
    assert(query ~= nil, reason)
    return query, saved
end

-- Return the reason conditions are refused
local function refused(match, rules)
    local query, saved, reason = QueryBuilder.Build({ match = match, rules = rules })
    assert(query == nil and saved == nil and reason ~= nil, tostring(query))
    return reason
end

-- Compile with the installed RuneQL and report whether a row matches
local function matches(query, row)
    local plan, reason = runeql.Compile(query)
    assert(plan ~= nil, query .. ": " .. tostring(reason))
    return (plan:Evaluate(row)) == true
end

-- Make one condition
local function rule(field, operator, value, min, max)
    return { field = field, operator = operator, value = value, min = min, max = max }
end

-- Numbers ---------------------------------------------------------------------------

for text, number in pairs({ ["0"] = 0, ["5"] = 5, [" 12 "] = 12, ["007"] = 7, ["1,000"] = 1000, ["25k"] = 25000,
    ["25K"] = 25000, ["1.5m"] = 1500000, ["1.1m"] = 1100000, ["0.5k"] = 500, [".5k"] = 500, ["2b"] = 2000000000,
    ["2147483647"] = 2147483647, ["1.234k"] = 1234 }) do
    local parsed = QueryBuilder.ParseNumber(text)
    assert(parsed == number and math.type(parsed) == "integer", text .. " gave " .. tostring(parsed))
end
for _, text in ipairs({ "", " ", "abc", "-1", "1.5", "1.2345k", "2147483648", "3b", "1e5", ".", "5.", "k",
    "1 000", "12x", "99999999999" }) do
    assert(QueryBuilder.ParseNumber(text) == nil, text)
end
assert(QueryBuilder.ParseNumber(42) == 42 and QueryBuilder.ParseNumber(-1) == nil and QueryBuilder.ParseNumber(4.5) == nil)

-- Name conditions -------------------------------------------------------------------

-- A phrase needs its words together and in order, any case
local phrase = build("all", { rule("name", "phrase", "  Dragon bones ") })
assert(phrase == 'name:"Dragon bones"', phrase)
assert(matches(phrase, { name = "Dragon bones" }) and matches(phrase, { name = "Baby dragon bones" }))
assert(not matches(phrase, { name = "Bones of a dragon" }) and not matches(phrase, { name = "Dragon" }))
-- Words are whole words, so the editor never promises substring matches
assert(not matches(build("all", { rule("name", "phrase", "bone") }), { name = "Dragon bones" }))

-- All words match anywhere in the name
local words = build("all", { rule("name", "words", "bones dragon") })
assert(words == '(name:"bones" AND name:"dragon")', words)
assert(matches(words, { name = "Dragon bones" }) and not matches(words, { name = "Dragon hide" }))
assert(build("all", { rule("name", "words", "iron") }) == 'name:"iron"')

-- Typed syntax stays literal text
local function onlyName(query)
    local plan = assert(runeql.Compile(query))
    local count = 0
    for _ in pairs(plan:Requirements()) do count = count + 1 end
    assert(plan:Requirements().name == true and count == 1, query)
end
local injected = build("all", { rule("name", "phrase", 'x OR qty:[0 TO *]') })
assert(injected == 'name:"x OR qty:[0 TO *]"', injected)
onlyName(injected)
assert(not matches(injected, { name = "Lobster", quantity = 5 }))
local split = build("all", { rule("name", "words", 'iron) OR (qty:[0 TO 5]') })
onlyName(split)
assert(not matches(split, { name = "Lobster", quantity = 5 }))
-- Quotes and backslashes are escaped, so RuneQL reads the words beside them
local quoted = build("all", { rule("name", "phrase", 'Ahrim\'s "robe" \\ top\\') })
assert(quoted == 'name:"Ahrim\'s \\"robe\\" \\\\ top\\\\"', quoted)
onlyName(quoted)
assert(matches(quoted, { name = "Ahrim's robe top" }) and not matches(quoted, { name = "Ahrim's robe" }))
for _, text in ipairs({ "*", "iron*", "bar~1", "/ir.n/", "(", ")", "-iron", "!", "NOT iron", "&&", "a^2" }) do
    onlyName(build("all", { rule("name", "phrase", "x " .. text) }))
end
assert(not matches(build("all", { rule("name", "phrase", "NOT iron") }), { name = "Lobster" }))

-- Text RuneQL could never match is refused instead of saved
assert(refused("all", { rule("name", "phrase", "   ") }) == "Condition 1: enter words from the item name.")
assert(refused("all", { rule("name", "phrase", "!!!") }) == "Condition 1: the words need a letter or number.")
assert(refused("all", { rule("name", "words", "iron -") }) == "Condition 1: each word needs a letter or number.")
assert(refused("all", { rule("name", "phrase", string.rep("a", 101)) })
    == "Condition 1: names can contain at most 100 characters.")
assert(build("all", { rule("name", "phrase", string.rep("a", 100)) }) ~= nil)

-- Number conditions -----------------------------------------------------------------

-- Each bound is inclusive and matches RuneQL's own comparison
local function quantities(operator, value, min, max)
    local query = build("all", { rule("qty", operator, value, min, max) })
    local found = {}
    for quantity = 0, 12 do
        if matches(query, { name = "Coins", quantity = quantity }) then found[#found + 1] = quantity end
    end
    return query, table.concat(found, ",")
end
local query, found = quantities("equals", "5")
assert(query == "qty:[5 TO 5]" and found == "5", query .. " " .. found)
query, found = quantities("atleast", "10")
assert(query == "qty:[10 TO *]" and found == "10,11,12", found)
query, found = quantities("atmost", "2")
assert(query == "qty:[* TO 2]" and found == "0,1,2", found)
query, found = quantities("between", nil, "5", "7")
assert(query == "qty:[5 TO 7]" and found == "5,6,7", found)
query, found = quantities("between", nil, "6", "6")
assert(found == "6", found)
assert(build("all", { rule("price", "atleast", "1.5m") }) == "price:[1500000 TO *]")
assert(build("all", { rule("gehigh", "equals", "2b") }) == "gehigh:[2000000000 TO 2000000000]")

assert(refused("all", { rule("qty", "equals", "") }) == "Condition 1: enter a whole number like 500, 25k, or 1.5m.")
assert(refused("all", { rule("qty", "atleast", "-3") }) == "Condition 1: enter a whole number like 500, 25k, or 1.5m.")
assert(refused("all", { rule("price", "atmost", "1.5") }) == "Condition 1: enter a whole number like 500, 25k, or 1.5m.")
assert(refused("all", { rule("gelow", "equals", "3b") }) == "Condition 1: numbers can be at most 2,147,483,647.")
assert(refused("all", { rule("qty", "between", nil, "8", "7") })
    == "Condition 1: the first number must not be more than the second.")
assert(refused("all", { rule("qty", "between", nil, "8", "") })
    == "Condition 1: enter a whole number like 500, 25k, or 1.5m.")

-- A price condition never matches a stack without that price
for _, field in ipairs({ "price", "gehigh", "gelow" }) do
    for _, operator in ipairs({ "equals", "atleast", "atmost", "between" }) do
        local priced = build("all", { rule(field, operator, "0", "0", "2147483647") })
        assert(not matches(priced, { name = "Coins", quantity = 1, fields = {} }), priced)
    end
    local cheap = build("all", { rule(field, "atmost", "100") })
    assert(matches(cheap, { name = "Coins", fields = { [field] = 100 } }))
    assert(not matches(cheap, { name = "Coins", fields = { [field] = 101 } }))
end

-- Prices are per item, from GE Prices, and the ranking waits for them
local NAMES = { [1] = { name = "Rune bar" }, [2] = { name = "Rune ore" }, [3] = { name = "Untradeable" } }
config = { Obj = { FromID = function(objectID) return NAMES[objectID] end } }
local ITEMS = {
    { objectID = 1, quantity = 100 },
    { objectID = 2, quantity = 1 },
    { objectID = 3, quantity = 1 },
}
local PRICES = { [1] = { high = 12000, low = 11000 }, [2] = { high = 9000, low = 8500 } }
local ready = false
local prices = {
    isReady = function() return ready end,
    getPrice = function(objectID) return assert(PRICES[objectID], "no price") end,
}
local cheapRunes = build("all", { rule("name", "words", "rune"), rule("price", "atmost", "10k") })
-- Per item, so 100 bars at 12k each are not cheap
local function ranked(text, service)
    local outcome = Ranking.Search({ runeql = runeql, text = text, items = ITEMS, nameOf = Ranking.NameReader(),
        prices = service })
    if outcome.state ~= "ok" then return outcome.state end
    local listed = {}
    for index, match in ipairs(outcome.matches) do listed[index] = match.objectID end
    return table.concat(listed, ",")
end
assert(ranked(cheapRunes, nil) == "needs_prices")
assert(ranked(cheapRunes, prices) == "prices_loading")
ready = true
assert(ranked(cheapRunes, prices) == "2", ranked(cheapRunes, prices))
assert(ranked(build("any", { rule("gelow", "atmost", "1m") }), prices) == "1,2")
assert(ranked(build("all", { rule("qty", "atleast", "1") }), nil) == "1,2,3")

-- Matching all or any ---------------------------------------------------------------

local ironAndMany = { rule("name", "phrase", "iron"), rule("qty", "atleast", "5") }
local all = build("all", ironAndMany)
local any = build("any", ironAndMany)
assert(all == 'name:"iron" AND qty:[5 TO *]' and any == 'name:"iron" OR qty:[5 TO *]', all .. " | " .. any)
for _, case in ipairs({
    { "Iron bar", 9, true, true },
    { "Iron bar", 3, false, true },
    { "Lobster", 9, false, true },
    { "Lobster", 3, false, false },
}) do
    local row = { name = case[1], quantity = case[2] }
    assert(matches(all, row) == case[3] and matches(any, row) == case[4], case[1] .. " " .. case[2])
end
-- A group of words keeps its own AND inside an OR
local grouped = build("any", { rule("name", "words", "iron bar"), rule("qty", "atleast", "100") })
assert(grouped == '(name:"iron" AND name:"bar") OR qty:[100 TO *]', grouped)
assert(matches(grouped, { name = "Iron bar", quantity = 1 }) and matches(grouped, { name = "Lobster", quantity = 100 }))
assert(not matches(grouped, { name = "Iron ore", quantity = 1 }))
local three = build("all", { rule("name", "words", "iron bar"), rule("qty", "atleast", "2"), rule("qty", "atmost", "4") })
assert(matches(three, { name = "Iron bar", quantity = 3 }) and not matches(three, { name = "Iron bar", quantity = 5 }))

-- Missing or unknown parts are refused
assert(refused("all", {}) == "Add at least one condition.")
assert(refused("some", ironAndMany) == "Choose whether all or any conditions must match.")
assert(refused("all", { rule("id", "equals", "1") }) == "Condition 1: choose a field.")
assert(refused("all", { rule("name", "atleast", "1") }) == "Condition 1: choose how to compare.")
assert(refused("all", { rule("qty", "phrase", "1") }) == "Condition 1: choose how to compare.")
assert(refused("all", { rule("name", "phrase", "iron"), "bad" }) == "Condition 2: choose a field.")
local many = {}
for index = 1, QueryBuilder.MAX_RULES do many[index] = rule("qty", "atleast", tostring(index)) end
assert(build("all", many) ~= nil)
many[#many + 1] = rule("qty", "atleast", "1")
assert(refused("all", many) == "Use at most 6 conditions, or Advanced for more.")

-- Saved conditions ------------------------------------------------------------------

-- The saved form keeps numbers, drops unused text, and builds the same query
local built, saved = build("any", { rule("name", "phrase", " iron ", "1", "2"), rule("qty", "atleast", "1.5k", "9", "9"),
    rule("price", "between", "7", "1k", "2k") })
assert(saved.match == "any" and #saved.rules == 3)
assert(saved.rules[1].value == "iron" and saved.rules[1].min == nil and saved.rules[1].max == nil)
assert(saved.rules[2].value == 1500 and saved.rules[2].min == nil)
assert(saved.rules[3].value == nil and saved.rules[3].min == 1000 and saved.rules[3].max == 2000)
assert(QueryBuilder.Build(saved) == built and QueryBuilder.Trusted(saved, built) ~= nil)
-- Conditions are trusted only for the exact query they give
assert(QueryBuilder.Trusted(saved, built .. " ") == nil and QueryBuilder.Trusted(saved, "iron") == nil)
assert(QueryBuilder.Trusted({ match = "any", rules = {} }, "") == nil and QueryBuilder.Trusted(nil, built) == nil)
-- Editing text built from saved conditions gives the same query
local draft = QueryBuilder.Draft(saved)
assert(draft.rules[2].value == "1500" and draft.rules[3].min == "1000" and draft.rules[3].max == "2000")
assert(QueryBuilder.Build(draft) == built)
assert(#QueryBuilder.Draft(nil).rules == 1 and QueryBuilder.Draft(nil).rules[1].field == "name")
-- A copy is separate from the original
local copy = QueryBuilder.Copy(saved)
copy.rules[1].value = "changed"
assert(saved.rules[1].value == "iron" and QueryBuilder.Copy("x") == nil)

print("query builder test passed")
