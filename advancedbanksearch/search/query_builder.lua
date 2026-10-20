-- Turn visual conditions into RuneQL text
-- Typed text is always quoted, so it never becomes query syntax

local QueryBuilder = {}

local MAX_RULES = 6
local MAX_TEXT_LENGTH = 100
local MAX_NUMBER = 2147483647
-- Field order is the order the editor lists them
local FIELDS = {
    { key = "name", label = "Item name", kind = "text" },
    { key = "qty", label = "Quantity", kind = "number" },
    { key = "price", label = "GE price", kind = "number" },
    { key = "gehigh", label = "GE high price", kind = "number" },
    { key = "gelow", label = "GE low price", kind = "number" },
}
local OPERATORS = {
    text = {
        { key = "phrase", label = "has phrase" },
        { key = "words", label = "has all words" },
    },
    number = {
        { key = "equals", label = "is" },
        { key = "atleast", label = "is at least" },
        { key = "atmost", label = "is at most" },
        { key = "between", label = "is between" },
    },
}
local MULTIPLIERS = { [""] = 1, k = 1000, m = 1000000, b = 1000000000 }
local NUMBER_HELP = "enter a whole number like 500, 25k, or 1.5m."

-- Trim spaces from user text
local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

-- Find a field by its key
local function fieldOf(key)
    for index, field in ipairs(FIELDS) do
        if field.key == key then return field, index end
    end
    return nil
end

-- Find an operator of a field kind by its key
local function operatorOf(kind, key)
    for index, operator in ipairs(OPERATORS[kind] or {}) do
        if operator.key == key then return operator, index end
    end
    return nil
end

-- Read a whole number, allowing commas and a k, m, or b suffix
-- Uses whole-number arithmetic so 1.1m is exactly 1100000
function QueryBuilder.ParseNumber(value)
    if math.type(value) == "integer" then
        if value < 0 then return nil, NUMBER_HELP end
        if value > MAX_NUMBER then return nil, "numbers can be at most 2,147,483,647." end
        return value
    end
    local text = string.lower(trim(value)):gsub(",", "")
    local whole, dot, fraction, suffix = text:match("^(%d*)(%.?)(%d*)([kmb]?)$")
    if whole == nil or (whole == "" and fraction == "") or (dot == "." and fraction == "") then
        return nil, NUMBER_HELP
    end
    local multiplier = MULTIPLIERS[suffix]
    local places = #tostring(multiplier) - 1
    if #fraction > places then return nil, NUMBER_HELP end
    whole = whole:gsub("^0+(%d)", "%1")
    if #whole > 10 then return nil, "numbers can be at most 2,147,483,647." end
    local number = (math.tointeger(tonumber(whole ~= "" and whole or "0"))) * multiplier
    if fraction ~= "" then
        number = number + math.tointeger(tonumber(fraction .. string.rep("0", places - #fraction)))
    end
    if number > MAX_NUMBER then return nil, "numbers can be at most 2,147,483,647." end
    return number
end

-- Quote text as a RuneQL phrase, escaping quotes and backslashes
local function quote(text)
    return '"' .. text:gsub('[\\"]', "\\%0") .. '"'
end

-- Check one condition and return its RuneQL and saved form
local function buildRule(rule, position)
    local prefix = "Condition " .. position .. ": "
    if type(rule) ~= "table" then return nil, nil, prefix .. "choose a field." end
    local field = fieldOf(rule.field)
    if field == nil then return nil, nil, prefix .. "choose a field." end
    local operator = operatorOf(field.kind, rule.operator)
    if operator == nil then return nil, nil, prefix .. "choose how to compare." end

    if field.kind == "text" then
        local text = trim(rule.value)
        if text == "" then return nil, nil, prefix .. "enter words from the item name." end
        if #text > MAX_TEXT_LENGTH then
            return nil, nil, prefix .. "names can contain at most 100 characters."
        end
        local saved = { field = field.key, operator = operator.key, value = text }
        if operator.key == "phrase" then
            -- RuneQL matches only letters and digits, so others alone never match
            if not text:find("%w") then return nil, nil, prefix .. "the words need a letter or number." end
            return field.key .. ":" .. quote(text), saved
        end
        local parts = {}
        for word in text:gmatch("%S+") do
            if not word:find("%w") then return nil, nil, prefix .. "each word needs a letter or number." end
            parts[#parts + 1] = field.key .. ":" .. quote(word)
        end
        if #parts == 1 then return parts[1], saved end
        return "(" .. table.concat(parts, " AND ") .. ")", saved
    end

    local saved = { field = field.key, operator = operator.key }
    local lower, upper
    if operator.key == "between" then
        local reason
        lower, reason = QueryBuilder.ParseNumber(rule.min)
        if lower == nil then return nil, nil, prefix .. reason end
        upper, reason = QueryBuilder.ParseNumber(rule.max)
        if upper == nil then return nil, nil, prefix .. reason end
        if lower > upper then
            return nil, nil, prefix .. "the first number must not be more than the second."
        end
        saved.min, saved.max = lower, upper
    else
        local number, reason = QueryBuilder.ParseNumber(rule.value)
        if number == nil then return nil, nil, prefix .. reason end
        saved.value = number
        if operator.key ~= "atmost" then lower = number end
        if operator.key ~= "atleast" then upper = number end
    end
    local function bound(number) return number ~= nil and string.format("%d", number) or "*" end
    return field.key .. ":[" .. bound(lower) .. " TO " .. bound(upper) .. "]", saved
end

-- Build RuneQL from conditions, or return nil and why not
-- Also returns the conditions in the form saved with a query
function QueryBuilder.Build(builder)
    if type(builder) ~= "table" or (builder.match ~= "all" and builder.match ~= "any") then
        return nil, nil, "Choose whether all or any conditions must match."
    end
    local rules = type(builder.rules) == "table" and builder.rules or {}
    if #rules == 0 then return nil, nil, "Add at least one condition." end
    if #rules > MAX_RULES then return nil, nil, "Use at most 6 conditions, or Advanced for more." end
    local clauses, saved = {}, { match = builder.match, rules = {} }
    for position, rule in ipairs(rules) do
        local clause, savedRule, reason = buildRule(rule, position)
        if clause == nil then return nil, nil, reason end
        clauses[position], saved.rules[position] = clause, savedRule
    end
    return table.concat(clauses, builder.match == "all" and " AND " or " OR "), saved, nil
end

-- Return saved conditions only when they still give this exact query
function QueryBuilder.Trusted(builder, query)
    local generated, saved = QueryBuilder.Build(builder)
    if generated == nil or generated ~= query then return nil end
    return saved
end

-- Make a blank condition for a field
function QueryBuilder.NewRule(fieldKey)
    local field = fieldOf(fieldKey) or FIELDS[1]
    return { field = field.key, operator = OPERATORS[field.kind][1].key, value = "", min = "", max = "" }
end

-- Make editable text conditions from saved ones
function QueryBuilder.Draft(builder)
    local draft = { match = "all", rules = {} }
    if type(builder) ~= "table" then
        draft.rules[1] = QueryBuilder.NewRule()
        return draft
    end
    draft.match = builder.match == "any" and "any" or "all"
    for index, rule in ipairs(builder.rules or {}) do
        draft.rules[index] = {
            field = rule.field,
            operator = rule.operator,
            value = rule.value ~= nil and tostring(rule.value) or "",
            min = rule.min ~= nil and tostring(rule.min) or "",
            max = rule.max ~= nil and tostring(rule.max) or "",
        }
    end
    if #draft.rules == 0 then draft.rules[1] = QueryBuilder.NewRule() end
    return draft
end

-- Copy the saved fields of stored conditions
function QueryBuilder.Copy(builder)
    if type(builder) ~= "table" then return nil end
    local copy = { match = builder.match, rules = {} }
    for index, rule in ipairs(type(builder.rules) == "table" and builder.rules or {}) do
        if type(rule) == "table" then
            copy.rules[index] = { field = rule.field, operator = rule.operator,
                value = rule.value, min = rule.min, max = rule.max }
        else
            copy.rules[index] = rule
        end
    end
    return copy
end

QueryBuilder.FIELDS = FIELDS
QueryBuilder.OPERATORS = OPERATORS
QueryBuilder.MAX_RULES = MAX_RULES
QueryBuilder.MAX_TEXT_LENGTH = MAX_TEXT_LENGTH
QueryBuilder.FieldOf = fieldOf
QueryBuilder.OperatorOf = operatorOf

return QueryBuilder
