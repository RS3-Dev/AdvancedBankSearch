package.path = "./?.lua;./?/init.lua;" .. package.path

-- Offer saved queries to Bank Tags' Import window through a stand-in of its published import
-- API: registration and availability, drafts naming exactly the matched stacks, refusals for
-- copies Bank Tags cannot name, too many stacks, the bank's state, prices, and unknown names,
-- and Bank Tags unloading, reloading, or giving the owner ID to a newer copy
-- FAKE HOST: stand-in loader, components, widgets, and import registry, not the game client

local Harness = require("tools/test_support/search_harness")
local Standin = require("tools/test_support/tags_import_standin")

local KEY = "advancedbanksearch/saved-search"
local h = Harness.new("tag_source")
h:NameObjects({ { 101, "Iron bar" }, { 102, "Iron ore" }, { 103, "Iron axe" }, { 105, "Lobster" } })
-- 103 is a placeholder; 101 has three stacks: 5, 7, and 3
h.bankHost:SetItems({ { 101, 5 }, { 102, 5 }, { 103, 0 }, { 105, 9 }, { 101, 7 }, { 101, 3 } })

-- Bank Tags loads after this plugin; the source registers once the host reports it
local tags = Standin.new()
h:LoadCore()
h:LoadSearch()
local app = h:App()
assert(tags.providers[KEY] == nil)
h.host.exports.banktags = tags.api
h.host:Notify("banktags", true, true)
local source = tags.providers[KEY]
assert(source ~= nil and source.label == "Saved bank search" and source.input == "text" and source.icon == "SEARCH")
-- Without RuneQL the source says why it cannot be used
assert(source.unavailable == "Converting a saved search needs RuneQL.", tostring(source.unavailable))
h:LoadRuneQL()
assert(tags.providers[KEY].unavailable == nil)
assert(app:SaveQuery(nil, "Iron", "iron"))
assert(app:SaveQuery(nil, "Big stacks, iron", "iron AND qty:[6 TO *]"))
assert(app:SaveQuery(nil, "Lobster", "lobster"))
assert(app:SaveQuery(nil, "Priced", "iron AND price:[1 TO *]"))
assert(app:SaveQuery(nil, "Broken", "name:(iron"))

-- Ask the source for a draft and return its answer
local function request(input)
    tags:Request(KEY, input)
    h:Tick()
    return tags.results[KEY]
end

-- The bank is closed: the request fails saying so
local closed = request("Iron")
assert(closed.state == "error" and closed.value == "Open your bank to convert a saved search.", closed.value)

local _, layout = h:OpenBank()
h:Tick(2)
-- Every present iron stack, the placeholder left out, as the query page shows them; Bank
-- Tags assigns 101's three entries copies 1, 2, and 3, exactly the stacks matched
local iron = request("iron")
assert(iron.state == "ready" and #iron.value == 1 and iron.value[1].name == "iron", tostring(iron.value))
local keys = {}
for _, key in ipairs(iron.value[1].keys) do keys[key] = true end
assert(#iron.value[1].keys == 4 and keys["object:101:1"] and keys["object:101:2"] and keys["object:101:3"]
    and keys["object:102:1"] and not keys["object:103:1"])

-- Only 101's second stack has more than 6: Bank Tags would tag copy 1, so the source refuses
local big = request("Big stacks, iron")
assert(big.state == "error" and big.value == "Iron bar: a later stack matched without the first, so it cannot be tagged exactly.",
    big.value)
-- A tag name keeps no comma, which Bank Tags refuses
assert(app:SaveQuery(nil, "Ores, all", "iron AND ore"))
local ores = request("ores, all")
assert(ores.state == "ready" and ores.value[1].name == "ores all", tostring(ores.value))

-- Unknown names, unreadable queries, price queries, and nothing found are refused
assert(request("missing").value == "No saved search has that name.")
assert(request("Broken").value == "RuneQL could not read this saved search.")
assert(request("Priced").value == "This saved search uses price fields, which need GE Prices.")
h.bankHost:SetItems({ { 101, 5 } })
layout:HandleInventoryUpdate()
h:Tick(4)
assert(request("Lobster").value == "This saved search matches nothing in your bank.")

-- Outside All Items the source refuses rather than guessing copies
layout.nativeViewAll = false
local detect = layout.DetectNativeViewAll
layout.DetectNativeViewAll = function() return false end
assert(request("Iron").value == 'Select "All Items" in your bank to convert a saved search.')
layout.DetectNativeViewAll = detect
layout.nativeViewAll = true

-- More stacks than Bank Tags imports are refused, not cut short
local many, names = {}, {}
for index = 1, 2000 do
    many[index] = { 50000 + index, 1 }
    names[index] = { 50000 + index, "Iron thing " .. index }
end
h:NameObjects(names)
h.bankHost:SetItems(many)
layout:HandleInventoryUpdate()
h:Tick(4)
local tooMany = request("Iron")
assert(tooMany.value == "This search matches 2000 stacks; Bank Tags imports at most 1,999.", tooMany.value)
-- 1,999 stacks fit Bank Tags' 2,000 entries with the row
many[2000] = nil
h.bankHost:SetItems(many)
layout:HandleInventoryUpdate()
h:Tick(4)
local fits = request("Iron")
assert(fits.state == "ready" and #fits.value[1].keys == 1999, tostring(fits.value))

-- Bank Core unloading makes the source unavailable; loading it again makes it usable
h.host:Unload("bankcore")
assert(tags.providers[KEY].unavailable == "Advanced Bank Search needs Bank Core to read your bank.")
h:LoadCore()
assert(tags.providers[KEY].unavailable == nil)

-- Bank Tags unloads: the source is removed; a new Bank Tags gets it again
h.host:Notify("banktags", false, false)
assert(tags.providers[KEY] == nil and app.tagSource.handle == nil)
tags:Close()
local reloaded = Standin.new()
h.host.exports.banktags = reloaded.api
h.host:Notify("banktags", true, true)
assert(reloaded.providers[KEY] ~= nil and app.tagSource.handle ~= nil)

-- A newer copy of this plugin takes the owner ID in Bank Tags; this copy never takes it back
local newer = assert(reloaded.api.RegisterExtension("advancedbanksearch", "Advanced Bank Search"))
assert(newer:RegisterImportProvider("saved-search", { label = "Newer", input = "text", request = function() end }))
h.host:Notify("banktags", true, true)
assert(app.tagSource.retired and reloaded.providers[KEY].label == "Newer")

-- Unloading this plugin removes its source from a live Bank Tags
local fresh = Standin.new()
h.host.exports.banktags = fresh.api
h.host:Reload("advancedbanksearch", { freshEnvironment = true, notify = false })
assert(fresh.providers[KEY] ~= nil)
h.host:Unload("advancedbanksearch")
assert(fresh.providers[KEY] == nil)

print("tag_source_test: ok")
