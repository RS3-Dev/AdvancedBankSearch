package.path = "./?.lua;./?/init.lua;" .. package.path

-- RuneQL v2 catalog results carry config names and never item IDs
runeql = {
    Catalog = {
        Find = function()
            return {
                { configName = "RUNE_SCIMITAR", displayName = "Rune scimitar", name = "Rune scimitar" },
                { configName = "REMOVED_FROM_CLIENT", displayName = "Gone", name = "Gone" },
            }, 2
        end,
    },
}
config = {
    Obj = setmetatable({
        FromID = function(id)
            if id == 1333 then return { id = 1333, configName = "RUNE_SCIMITAR" } end
            if id == 7 then return setmetatable({}, { __tostring = function() return "config.Obj.PRINTED_ONLY(7)" end }) end
            return nil
        end,
    }, {
        __index = function(_, name)
            if name == "RUNE_SCIMITAR" then return { id = 1333 } end
            return nil
        end,
    }),
}

local CatalogObjects = require("lib/features/search/catalog_objects")

-- Unresolvable configs are skipped so callers never receive a nil object ID
local results, total = CatalogObjects.Find("scimitar", 40)
assert(total == 2 and #results == 1)
assert(results[1].objectId == 1333 and results[1].displayName == "Rune scimitar")

assert(CatalogObjects.ObjectID("RUNE_SCIMITAR") == 1333)
assert(CatalogObjects.ObjectID("REMOVED_FROM_CLIENT") == nil)
assert(CatalogObjects.ObjectID("FromID") == nil)
assert(CatalogObjects.ConfigName(1333) == "RUNE_SCIMITAR")
assert(CatalogObjects.ConfigName(7) == "PRINTED_ONLY")
assert(CatalogObjects.ConfigName(99) == nil)

-- Query rows expose the config name instead of the removed item-ID field
local QueryItemFields = require("lib/features/search/query_item_fields")
local enrich = QueryItemFields.Enricher({ Requirements = function() return {} end }, nil)
local row = enrich("Rune scimitar", { objectID = 1333, quantity = 4 })
assert(row.configName == "RUNE_SCIMITAR" and row.itemID == nil and row.quantity == 4)
assert(enrich("Unknown", { objectID = 99 }).configName == nil)

print("catalog_objects_test: ok")
