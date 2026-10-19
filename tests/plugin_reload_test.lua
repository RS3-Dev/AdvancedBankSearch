package.path = "./?.lua;./?/init.lua;" .. package.path

-- Load the built Advanced Bank Search beside the real Bank Core and the installed RuneQL in
-- isolated plugin environments and follow every load order: without Core, Core arriving late,
-- reloading, cloned, and unloading, the plugin reloading with and without a shared Lua state
-- while a price wait runs, a newer copy taking the owner ID, and saved queries kept in this
-- plugin's own saved data
-- FAKE HOST: stand-in loader, components, and widgets, not the game client

local Harness = require("tools/test_support/search_harness")

local NOT_CONNECTED = "Advanced Bank Search needs Bank Core. Enable Bank Core to search your bank."
local CONNECTED = "Advanced Bank Search is in your bank: open the bank and choose the Search tab in the sidebar."
local REPLACED = "A newer copy of Advanced Bank Search took over; this copy is idle."

local h = Harness.new("plugin_reload")
local Loader = require("tools/test_support/fake_plugin_host")
h:NameObjects({ { 101, "Iron bar" }, { 105, "Lobster" } })
h.bankHost:SetItems({ { 101, 5 }, { 105, 9 } })

-- Without Bank Core or RuneQL the plugin loads, publishes nothing, and says Core is needed
local search = h:LoadSearch()
local app = h:App()
assert(app ~= nil and not app:IsConnected() and search.result == nil and app:RuneQL() == nil)
local panel = h:OpenContentPanel()
assert(Harness.Find(panel, NOT_CONNECTED) ~= nil)
for moduleName in pairs(search.env.package.loaded) do
    assert(string.sub(moduleName, 1, 19) == "advancedbanksearch/", moduleName .. " is not this plugin's module")
end
-- Saving a query needs RuneQL; queries save to this plugin's own data
assert(select(2, app:SaveQuery(nil, "Iron", "iron")) == "Searching needs RuneQL. Enable RuneQL to search your bank.")

-- RuneQL and Core arrive late; the plugin connects and its panel says where it is
h:LoadRuneQL()
assert(app:RuneQL() ~= nil)
assert(app:SaveQuery(nil, "Iron", "iron"))
for key in pairs(h.databases.advancedbanksearch) do assert(string.find(key, "^advancedbanksearch:queries:v1:"), key) end
assert(next(h.databases.runeql or {}) == nil)
local core = h:LoadCore()
assert(app:IsConnected() and app.bank == core.result)
assert(Harness.Find(panel, CONNECTED) ~= nil)
local state = app.handle:GetState()
assert(table.concat(state.pages, ",") == "query,search" and state.tabs[1] == "search")
h:OpenBank()
h:Tick(2)
assert(app.tab.controls ~= nil and app:ChooseQuery("1"))

-- Core reloads; the plugin reconnects to the new API and its tab mounts again
local oldAPI = core.result
h.host:Reload("bankcore", { shutdown = true, notify = true, reinject = true })
assert(not oldAPI.GetState().running and app:IsConnected() and app.bank == core.result)
assert(app.shownPage == nil and app.snapshot == nil)
h:OpenBank()
h:Tick(2)
assert(app.tab.controls ~= nil)

-- A host that clones exports hands the plugin a copy of Core's API; a reload still connects
h.host:Reload("bankcore", { shutdown = true })
h.host.exports.bankcore = Loader.Clone(core.result)
h.host:Notify("bankcore", true, true)
assert(app:IsConnected() and app.bank == h.host.exports.bankcore and getmetatable(app.bank) == nil)

-- Core unloads while a price wait runs: the plugin lets go and the wait ends
h.host:Unload("bankcore")
assert(not app:IsConnected() and Harness.Find(panel, NOT_CONNECTED) ~= nil)
h:LoadCore()
h:OpenBank()
h:Tick(2)
h.host.exports.geprices = { isReady = function() return false end, getPrice = function() return { high = 1 } end }
h.host:Notify("geprices", true, true)
app:SetText("price:[1 TO *]")
assert(app.priceWait ~= nil and h.bankHost:Listener("advancedbanksearch_price_wait") ~= nil)
h.host:Unload("bankcore")
assert(app.priceWait == nil and h.bankHost:Listener("advancedbanksearch_price_wait") == nil)
h:LoadCore()
h:OpenBank()
h:Tick(2)

-- The plugin reloads in the same Lua state mid-wait: the old session stops its wait and the
-- new one reads the same saved queries; the old copy, told Core loaded, takes nothing back
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

-- A hot reload that keeps the module cache still runs fresh modules
local cachedApp = h.search.env.package.loaded["advancedbanksearch/app"]
h.host:Reload("advancedbanksearch")
local hot = h:App()
assert(hot ~= reloaded and reloaded.shutDown and hot:IsConnected())
assert(h.search.env.package.loaded["advancedbanksearch/app"] ~= cachedApp)
h:Tick(2)

-- Unloading mid-wait leaves no tab, listener, or subscription behind
hot:SetText("price:[3 TO *]")
assert(hot.priceWait ~= nil)
assert(h:Session().layout:FindSidebarTab("__bankutils_ext_tab:advancedbanksearch/search") ~= nil)
h.host:Unload("advancedbanksearch")
assert(not hot:IsConnected() and hot.priceWait == nil)
for _, subscription in ipairs(h.host:SubscriptionsOf("advancedbanksearch")) do
    error("Advanced Bank Search left " .. subscription .. " subscribed")
end
assert(h:Session().layout:FindSidebarTab("__bankutils_ext_tab:advancedbanksearch/search") == nil)
h.host:Unload("bankcore")

-- Separate Lua states with cloned exports: a newer copy takes the owner ID and the older one,
-- told Core loaded, stays idle
local split = Harness.new("plugin_reload_split", { separateGlobals = true, cloneExports = true })
split:LoadCore()
local first = split:LoadSearch()
local firstApp = rawget(first.env, "__advancedbanksearch_session")
assert(firstApp:IsConnected() and rawget(first.env._G, "__bankcore_api") == nil)
local second = split.host:Load("advancedbanksearch_copy", split.searchFolder, { name = "advancedbanksearch",
    dependencies = {}, optional = { bankcore = true, runeql = true, geprices = true, banktags = true } })
local secondApp = rawget(second.env, "__advancedbanksearch_session")
assert(secondApp:IsConnected() and not firstApp:IsConnected())
rawget(first.env, "PluginDependencyUpdate")({ pluginIdentifier = "bankcore", enabled = true })
assert(firstApp.retired and not firstApp:IsConnected() and secondApp:IsConnected())
local firstPanel = ui.Layer.new(nil)
firstPanel:SetSize(300, 400)
firstApp:CreatePanel(firstPanel)
assert(Harness.Find(firstPanel, REPLACED) ~= nil)

print("plugin_reload_test: ok")
