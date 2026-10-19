-- Rank a bank snapshot's stacks against RuneQL text the way the integrated search did: score
-- descending, ties in View All order. A query that names price fields is never ranked
-- without loaded prices, since RuneQL treats a missing field as matching nothing and a
-- negated price clause would then match every item

local ItemFields = require("advancedbanksearch/search/item_fields")

local Ranking = {}

-- Search text shorter than this, after trimming, shows no page
Ranking.MINIMUM_LENGTH = 2

-- Normalize spaces and casing before checking search text
function Ranking.Normalize(value)
    return (string.lower(tostring(value or "")):match("^%s*(.-)%s*$"):gsub("%s+", " "))
end

-- Report whether search text is long enough to search
function Ranking.IsSearchable(value)
    return #Ranking.Normalize(value) >= Ranking.MINIMUM_LENGTH
end

-- Return a function that reads an object's display name, caching every answer
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

-- Rank items by score(item), dropping those it does not match and, when asked, placeholders
function Ranking.Rank(items, score, excludePlaceholders)
    local matches = {}
    for index, item in ipairs(items) do
        if not excludePlaceholders or (tonumber(item.quantity) or 0) > 0 then
            local value = score(item)
            if value ~= nil then
                matches[#matches + 1] = { objectID = item.objectID, copy = item.copy, score = value, index = index }
            end
        end
    end
    table.sort(matches, function(left, right)
        if left.score == right.score then return left.index < right.index end
        return left.score > right.score
    end)
    return matches
end

-- Run RuneQL text over a snapshot's items. request: runeql (the API), text, items,
-- excludePlaceholders, prices (the GE price service or nil), and nameOf. The outcome's
-- state is "ok" with its matches, "invalid" with RuneQL's reason, "needs_prices" when the
-- text names price fields and no price service is loaded, or "prices_loading" until it is ready
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

-- List matches as page slots naming each stack's copy
function Ranking.Slots(matches)
    local slots = {}
    for index, match in ipairs(matches) do slots[index] = { item = match.objectID, copy = match.copy } end
    return slots
end

return Ranking
