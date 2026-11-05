package.path = "./?.lua;./?/init.lua;" .. package.path

-- Follow Bank Core and RuneQL through every load order
-- FAKE HOST: stand-in loader, components, and widgets, not the game client

local Harness = require("tools/test_support/search_harness")

local h = Harness.new("plugin_reload")
local Loader = require("tools/test_support/fake_plugin_host")
h:NameObjects({ { 101, "Iron bar" }, { 105, "Lobster" } })
h.bankHost:SetItems({ { 101, 5 }, { 105, 9 } })

-- Advanced Bank Search has no plugin window entry, so it has no ribbon icon or panel
local manifest = assert(io.open(h.searchFolder .. "/plugin.json", "rb"))
assert(string.find(manifest:read("a"), '"hasRibbonIcon": false', 1, true))
manifest:close()

-- Without Core or RuneQL, nothing is published
local search = h:LoadSearch()
local app = h:App()
assert(app ~= nil and not app:IsConnected() and search.result == nil and app:RuneQL() == nil)
for moduleName in pairs(search.env.package.loaded) do
    assert(string.sub(moduleName, 1, 10) == "resources/", moduleName .. " is not this plugin's module")
end
-- Saving needs RuneQL and writes to this plugin's own data
assert(select(2, app:SaveQuery(nil, "Iron", "iron")) == "Searching needs RuneQL. Enable RuneQL to search your bank.")

-- Late RuneQL and Core connect
h:LoadRuneQL()
assert(app:RuneQL() ~= nil)
assert(app:SaveQuery(nil, "Iron", "iron"))
for key in pairs(h.databases.advancedbanksearch) do assert(string.find(key, "^advancedbanksearch:queries:v1:"), key) end
assert(next(h.databases.runeql or {}) == nil)
local core = h:LoadCore()
assert(app:IsConnected() and not app.ext:IsOpen())
for _, subscription in ipairs(h.host:SubscriptionsOf("advancedbanksearch")) do
    assert(string.sub(subscription, 1, 18) ~= "ContentLayerReady.", subscription .. " is a plugin panel")
end
h:OpenBank()
h:Tick(2)
-- One rail icon, named for the plugin, with its column
local icon = h:Session().layout:FindSidebarTab("__bankutils_ext_tab:advancedbanksearch")
assert(icon ~= nil and icon.icon == "SEARCH" and icon.tooltip == "Advanced Bank Search" and icon.mount ~= nil)
assert(app.tab.controls ~= nil and app:ChooseQuery("1") and app:ShownPage() == "query")

-- A Core reload registers again, and the column mounts again
local oldExt = app.ext
h.host:Reload("bankcore", { shutdown = true, notify = true, reinject = true, notifyRequired = true })
assert(app:IsConnected() and app.ext ~= oldExt and select(2, oldExt:Open()) == "stale")
assert(app:ShownPage() == nil and app.items == nil and app.pageID == nil)
h:OpenBank()
h:Tick(2)
assert(app.tab.controls ~= nil)

-- A copied Core API still registers after a reload
oldExt = app.ext
h.host:Reload("bankcore", { shutdown = true })
h.host.exports.bankcore = Loader.Clone(core.result)
h.host:Notify("bankcore", true, true)
assert(getmetatable(h.host.exports.bankcore) == nil and app:IsConnected() and app.ext ~= oldExt)
h:OpenBank()
h:Tick(2)
assert(app.tab.controls ~= nil and app:ChooseQuery("1") and app:ShownPage() == "query")

-- Core unloading mid-wait releases the plugin and ends the wait
h.host:Unload("bankcore")
assert(not app:IsConnected())
h:LoadCore()
h:OpenBank()
h:Tick(2)
h.host.exports.geprices = { isReady = function() return false end, getPrice = function() return { high = 1 } end }
h.host:Notify("geprices", true, true)
app:SetText("price:[1 TO *]")
assert(app.priceWait ~= nil and h.bankHost:Listener("advancedbanksearch_price_wait") ~= nil)
app:QueueText("price:[5 TO *]")
assert(app.searchWait ~= nil and h.bankHost:Listener("advancedbanksearch_search_wait") ~= nil)
h.host:Unload("bankcore")
assert(app.priceWait == nil and h.bankHost:Listener("advancedbanksearch_price_wait") == nil)
assert(app.searchWait == nil and h.bankHost:Listener("advancedbanksearch_search_wait") == nil)
h:LoadCore()
h:OpenBank()
h:Tick(2)

-- A same-state reload mid-wait stops the old wait and keeps queries
-- The old copy takes nothing back when told Core loaded
app:SetText("price:[2 TO *]")
assert(app.priceWait ~= nil)
h.host:Reload("advancedbanksearch", { freshEnvironment = true })
local reloaded = h:App()
assert(reloaded ~= app and app.shutDown and app.priceWait == nil and reloaded:IsConnected())
assert(reloaded.queries:Get("1").name == "Iron")
rawget(search.env, "PluginDependencyUpdate")({ pluginIdentifier = "bankcore", enabled = true })
assert(reloaded:IsConnected() and not app:IsConnected())
h:Tick(2)
assert(reloaded.tab.controls ~= nil)

-- A reload that keeps cached modules still runs fresh ones
local cachedApp = h.search.env.package.loaded["resources/app"]
h.host:Reload("advancedbanksearch")
local hot = h:App()
assert(hot ~= reloaded and reloaded.shutDown and hot:IsConnected())
assert(h.search.env.package.loaded["resources/app"] ~= cachedApp)
h:Tick(2)

-- Unloading mid-wait leaves no tab, listener, or subscription behind
hot:SetText("price:[3 TO *]")
hot:QueueText("price:[4 TO *]")
assert(hot.priceWait ~= nil and hot.searchWait ~= nil)
assert(h:Session().layout:FindSidebarTab("__bankutils_ext_tab:advancedbanksearch") ~= nil)
h.host:Unload("advancedbanksearch")
assert(not hot:IsConnected() and hot.priceWait == nil and hot.searchWait == nil)
for _, subscription in ipairs(h.host:SubscriptionsOf("advancedbanksearch")) do
    error("Advanced Bank Search left " .. subscription .. " subscribed")
end
assert(h:Session().layout:FindSidebarTab("__bankutils_ext_tab:advancedbanksearch") == nil)
h.host:Unload("bankcore")

-- In separate Lua states, a newer copy's registration replaces the older one
local split = Harness.new("plugin_reload_split", { separateGlobals = true, cloneExports = true })
split:LoadCore()
local first = split:LoadSearch()
local firstApp = rawget(first.env, "__advancedbanksearch_session")
assert(firstApp:IsConnected() and rawget(first.env._G, "__bankcore_api") == nil)
local second = split.host:Load("advancedbanksearch_copy", split.searchFolder, { name = "advancedbanksearch",
    dependencies = {}, optional = { bankcore = true, runeql = true, geprices = true } })
local secondApp = rawget(second.env, "__advancedbanksearch_session")
assert(secondApp:IsConnected() and select(2, firstApp.ext:Open()) == "stale")
assert(select(2, secondApp.ext:Open()) == "no_page")

print("plugin_reload_test: ok")
