package.path = "./?.lua;" .. package.path

-- Save, rename, and delete queries under this plugin's own keys; never read the integrated
-- plugin's queries; report a failed save without changing anything; and never overwrite a
-- save that cannot be read

-- Saved data as the host keeps it per plugin; writes can be refused
local values = {}
local refuse = false
PersistentDB = {
    GetString = function(_, key) return values[key] end,
    SetString = function(_, key, value)
        if refuse then return false end
        values[key] = value
        return true
    end,
}

local QueryStore = require("advancedbanksearch/search/query_store")

-- The integrated plugin's queries sit in the same saved data and are never read
values["bankutils:runesql:text:v1:manifest"] = "a:1"
values["bankutils:runesql:text:v1:a:1"] = '{"schemaVersion":1,"nextId":2,"queries":[{"id":"1","name":"Old","query":"old"}]}'
local store = QueryStore.new()
assert(store.loadError == nil and #store:All() == 0)

-- Saving validates, then writes only this plugin's keys
assert(select(3, store:Save(nil, "  ", "iron")) == "Enter a query name.")
assert(select(3, store:Save(nil, string.rep("x", 41), "iron")) == "Query names can contain at most 40 characters.")
assert(select(3, store:Save(nil, "Iron", " ")) == "Enter a RuneQL query.")
assert(select(3, store:Save(nil, "Iron", string.rep("x", 10000))) == "RuneQL queries can contain at most 9,999 characters.")
local saved, iron = store:Save(nil, " Iron ", "iron")
assert(saved and iron.id == "1" and iron.name == "Iron" and iron.query == "iron")
assert(values["advancedbanksearch:queries:v1:manifest"] == "a:1")
for key in pairs(values) do
    assert(string.find(key, "^advancedbanksearch:queries:v1:") or string.find(key, "^bankutils:"), key)
end
assert(select(3, store:Save(nil, "IRON", "other")) == "A RuneQL query with that name already exists.")
local _, ore = store:Save(nil, "Ore", "ore")
-- Renaming keeps the ID; saving the same name for the same query is fine
assert(store:Save(ore.id, "Ores", "ore OR coal") and store:Get(ore.id).name == "Ores")
assert(store:Save(ore.id, "ores", "ore OR coal"))

-- A reload reads the same queries back
local reloaded = QueryStore.new()
assert(#reloaded:All() == 2 and reloaded:Get("2").query == "ore OR coal" and reloaded:FindName("IRON").id == "1")

-- A refused write is reported, and neither the store nor the published save changes
refuse = true
local manifest = values["advancedbanksearch:queries:v1:manifest"]
local ok, _, reason = store:Save(nil, "Lobster", "lobster")
assert(not ok and reason == "PersistentDB could not save RuneQL chunk 1.", reason)
assert(#store:All() == 2 and store:FindName("Lobster") == nil)
local deleted, deleteReason = store:Delete(iron.id)
assert(not deleted and deleteReason ~= nil and store:Get(iron.id) ~= nil)
assert(values["advancedbanksearch:queries:v1:manifest"] == manifest)
refuse = false

-- Deleting removes one query; a missing one says so
assert(store:Delete(iron.id) and store:Get(iron.id) == nil)
assert(select(2, store:Delete(iron.id)) == "That RuneQL query no longer exists.")
assert(select(3, store:Save("99", "Gone", "gone")) == "That RuneQL query no longer exists.")

-- A published save whose chunk is missing cannot be read: it loads empty with an error and
-- every save is refused, so it is never overwritten
local broken = values["advancedbanksearch:queries:v1:manifest"]
local generation = string.sub(broken, 1, 1)
values["advancedbanksearch:queries:v1:" .. generation .. ":1"] = nil
local unreadable = QueryStore.new()
assert(unreadable.loadError ~= nil and #unreadable:All() == 0)
local refused, _, why = unreadable:Save(nil, "New", "new")
assert(not refused and why == unreadable.loadError)
assert(values["advancedbanksearch:queries:v1:manifest"] == broken)
-- Text that is not JSON is unreadable too
values["advancedbanksearch:queries:v1:" .. generation .. ":1"] = "{not json"
assert(QueryStore.new().loadError ~= nil)

print("query_store_test: ok")
