package.path = "./?.lua;./?/init.lua;" .. package.path

-- Offer saved queries to a stand-in of Bank Tags' import API
-- FAKE HOST: stand-in loader, components, widgets, and import registry, not the game client

local Harness = require("tools/test_support/search_harness")
local Standin = require("tools/test_support/tags_import_standin")

local KEY = "advancedbanksearch/saved-search"
local h = Harness.new("tag_source")
h:NameObjects({ { 101, "Iron bar" }, { 102, "Iron ore" }, { 103, "Iron axe" }, { 105, "Lobster" } })
-- 103 is a placeholder; 101 has three stacks: 5, 7, and 3
h.bankHost:SetItems({ { 101, 5 }, { 102, 5 }, { 103, 0 }, { 105, 9 }, { 101, 7 }, { 101, 3 } })

-- Bank Tags loads later; the source registers once reported
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
-- Store an unreadable query directly, since the editor refuses it
assert(app.queries:Save(nil, "Broken", "name:(iron"))

-- Ask the source for a draft and return its answer
local function request(input)
    tags:Request(KEY, input)
    h:Tick()
    return tags.results[KEY]
end

-- With the bank closed, the request fails and says so
local closed = request("Iron")
assert(closed.state == "error" and closed.value == "Open your bank to convert a saved search.", closed.value)

local _, layout = h:OpenBank()
h:Tick(2)
-- Every present iron stack is drafted, placeholder excluded
-- Bank Tags numbers 101's entries 1, 2, and 3, matching the stacks
local iron = request("iron")
assert(iron.state == "ready" and #iron.value == 1 and iron.value[1].name == "iron", tostring(iron.value))
local keys = {}
for _, key in ipairs(iron.value[1].keys) do keys[key] = true end
assert(#iron.value[1].keys == 4 and keys["object:101:1"] and keys["object:101:2"] and keys["object:101:3"]
    and keys["object:102:1"] and not keys["object:103:1"])

-- Only 101's second stack has over 6, so the copy would be wrong
local big = request("Big stacks, iron")
assert(big.state == "error" and big.value == "Iron bar: a later stack matched without the first, so it cannot be tagged exactly.",
    big.value)
-- Tag names drop commas, which Bank Tags refuses
assert(app:SaveQuery(nil, "Ores, all", "iron AND ore"))
local ores = request("ores, all")
assert(ores.state == "ready" and ores.value[1].name == "ores all", tostring(ores.value))
-- Names match trimmed and in any case, inner spaces kept
assert(app:SaveQuery(nil, "Iron  bars", 'name:"iron bar"'))
local bars = request(" iron  BARS ")
assert(bars.state == "ready" and bars.value[1].name == "iron bars" and #bars.value[1].keys == 3, tostring(bars.value))
assert(app.queries:FindName("Iron  bars").name == "Iron  bars")

-- Unknown, unreadable, price, and empty queries are refused
assert(request("missing").value == "No saved search has that name.")
assert(request("Broken").value == "RuneQL could not read this saved search.")
assert(request("Priced").value == "This saved search uses price fields, which need GE Prices.")
h.bankHost:SetItems({ { 101, 5 } })
layout:HandleInventoryUpdate()
h:Tick(4)
assert(request("Lobster").value == "This saved search matches nothing in your bank.")

-- Outside All Items the source refuses rather than guess copies
layout.nativeViewAll = false
local detect = layout.DetectNativeViewAll
layout.DetectNativeViewAll = function() return false end
assert(request("Iron").value == 'Select "All Items" in your bank to convert a saved search.')
layout.DetectNativeViewAll = detect
layout.nativeViewAll = true

-- Too many stacks are refused, not cut short
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
-- 1,999 stacks plus the row fit Bank Tags' 2,000 entries
many[2000] = nil
h.bankHost:SetItems(many)
layout:HandleInventoryUpdate()
h:Tick(4)
local fits = request("Iron")
assert(fits.state == "ready" and #fits.value[1].keys == 1999, tostring(fits.value))

-- Core unloading disables the source until it loads again
h.host:Unload("bankcore")
assert(tags.providers[KEY].unavailable == "Advanced Bank Search needs Bank Core to read your bank.")
h:LoadCore()
assert(tags.providers[KEY].unavailable == nil)

-- When Bank Tags unloads the source goes; a new one gets it
h.host:Notify("banktags", false, false)
assert(tags.providers[KEY] == nil and app.tagSource.handle == nil)
tags:Close()
local reloaded = Standin.new()
h.host.exports.banktags = reloaded.api
h.host:Notify("banktags", true, true)
assert(reloaded.providers[KEY] ~= nil and app.tagSource.handle ~= nil)

-- A newer copy takes the owner ID and this one never takes it back
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
