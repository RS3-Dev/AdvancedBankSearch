-- Rank bank stacks against RuneQL text by score, then View All order
-- A match names its object; Bank Core shows an object's stocked stacks first
-- Price queries wait for prices, since "not" on a missing field matches everything

local ItemFields = require("resources/search/item_fields")

local Ranking = {}

-- Shorter trimmed search text shows no page
Ranking.MINIMUM_LENGTH = 2

-- Normalize spaces and case in search text
function Ranking.Normalize(value)
    return (string.lower(tostring(value or "")):match("^%s*(.-)%s*$"):gsub("%s+", " "))
end

-- Report whether search text is long enough to search
function Ranking.IsSearchable(value)
    return #Ranking.Normalize(value) >= Ranking.MINIMUM_LENGTH
end

-- Read objects' display names with a cache
function Ranking.NameReader()
    local names = {}
    return function(objectID)
        local cached = names[objectID]
        if cached ~= nil then return cached ~= false and cached or nil end
        local name = nil
        if config ~= nil and config.Obj ~= nil and config.Obj.FromID ~= nil then
            local ok, object = pcall(function() return config.Obj.FromID(objectID) end)
            if ok and object ~= nil then
                local nameOK, value = pcall(function() return object.name end)
                if nameOK and type(value) == "string" and value ~= "" then name = value end
            end
        end
        names[objectID] = name or false
        return name
    end
end

-- Rank matching items by score, optionally without placeholders
function Ranking.Rank(items, score, excludePlaceholders)
    local matches = {}
    for index, item in ipairs(items) do
        if not excludePlaceholders or (tonumber(item.quantity) or 0) > 0 then
            local value = score(item)
            if value ~= nil then
                matches[#matches + 1] = { objectID = item.objectID, score = value, index = index }
            end
        end
    end
    table.sort(matches, function(left, right)
        if left.score == right.score then return left.index < right.index end
        return left.score > right.score
    end)
    return matches
end

-- Run RuneQL text over a snapshot's items
-- States: ok, invalid, needs_prices, or prices_loading
function Ranking.Search(request)
    local plan, reason = request.runeql.Compile(request.text)
    if plan == nil then return { state = "invalid", reason = tostring(reason or "") } end
    local prices = request.prices
    if ItemFields.NeedsPrices(plan) then
        if prices == nil then return { state = "needs_prices" } end
        if not ItemFields.IsReady(prices) then return { state = "prices_loading" } end
    end
    local enrich = ItemFields.Enricher(plan, prices)
    local nameOf = request.nameOf
    local matches = Ranking.Rank(request.items, function(item)
        return plan:Score(enrich(nameOf(item.objectID), item))
    end, request.excludePlaceholders)
    return { state = "ok", matches = matches }
end

-- List matches as page slots, one object ID per matching stack
function Ranking.Slots(matches)
    local slots = {}
    for index, match in ipairs(matches) do slots[index] = match.objectID end
    return slots
end

return Ranking
