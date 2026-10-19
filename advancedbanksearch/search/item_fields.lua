-- Enrich query records with bank fields and optional price data. The caller passes the GE
-- price service it found, or nil

local ObjectConfig = require("advancedbanksearch/core/object_config")

local QueryItemFields = {}

-- Check the query's required fields before requesting price data
function QueryItemFields.NeedsPrices(plan)
    local fields = plan:Requirements()
    return fields.price == true or fields.gehigh == true or fields.gelow == true
end

-- Check whether the price dependency can serve the query's fields
function QueryItemFields.IsReady(service)
    if type(service) ~= "table" or type(service.getPrice) ~= "function" then
        return false
    end
    if type(service.isReady) ~= "function" then return true end
    local ok, ready = pcall(service.isReady)
    return ok and ready == true
end

-- Accept only positive numeric prices so missing values do not become valid query fields
local function positive(value)
    value = tonumber(value)
    return value ~= nil and value > 0 and value or nil
end

-- Build query records with bank fields and prices cached for one execution
function QueryItemFields.Enricher(plan, service)
    local needsPrices = QueryItemFields.NeedsPrices(plan)
    local ready = needsPrices and QueryItemFields.IsReady(service)
    -- Cache within one execution, including missing prices and repeated stacks
    -- A later execution reads fresh values from the dependency
    local prices = {}
    local configNames = {}
    return function(name, item)
        item = item or {}
        local fields = {}
        for key, value in pairs(item.fields or {}) do fields[key] = value end
        if needsPrices and ready and item.objectID ~= nil then
            local price = prices[item.objectID]
            if price == nil then
                local ok, result = pcall(service.getPrice, item.objectID)
                price = ok and type(result) == "table" and result or false
                prices[item.objectID] = price
            end
            if price ~= false then
                fields.gehigh = positive(price.high)
                fields.gelow = positive(price.low)
                fields.price = fields.gehigh or fields.gelow
            end
        end
        -- RuneQL v2 identifies items by config name; item IDs are not query fields
        local configName = nil
        if item.objectID ~= nil then
            configName = configNames[item.objectID]
            if configName == nil then
                configName = ObjectConfig.ConfigName(item.objectID) or false
                configNames[item.objectID] = configName
            end
        end
        return {
            name = name,
            configName = configName or nil,
            quantity = item.quantity,
            fields = fields,
        }
    end
end

return QueryItemFields
