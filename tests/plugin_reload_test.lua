package.path = "./?.lua;./?/init.lua;" .. package.path

-- Follow Bank Core and RuneQL through every load order
-- FAKE HOST: stand-in loader, components, and widgets, not the game client

local Harness = require("tools/test_support/search_harness")

local NOT_CONNECTED = "Advanced Bank Search needs Bank Core. Enable Bank Core to search your bank."
local CONNECTED = "Advanced Bank Search is in your bank: open the bank and choose the Search tab in the sidebar."
local REPLACED = "A newer copy of Advanced Bank Search took over; this copy is idle."

local h = Harness.new("plugin_reload")
local Loader = require("tools/test_support/fake_plugin_host")
h:NameObjects({ { 101, "Iron bar" }, { 105, "Lobster" } })
h.bankHost:SetItems({ { 101, 5 }, { 105, 9 } })

-- Without Core or RuneQL, nothing is published and the panel says so
local search = h:LoadSearch()
local app = h:App()
assert(app ~= nil and not app:IsConnected() and search.result == nil and app:RuneQL() == nil)
local panel = h:OpenContentPanel()
assert(Harness.Find(panel, NOT_CONNECTED) ~= nil)
for moduleName in pairs(search.env.package.loaded) do
    assert(string.sub(moduleName, 1, 19) == "advancedbanksearch/", moduleName .. " is not this plugin's module")
end
-- Saving needs RuneQL and writes to this plugin's own data
assert(select(2, app:SaveQuery(nil, "Iron", "iron")) == "Searching needs RuneQL. Enable RuneQL to search your bank.")

-- Late RuneQL and Core connect, and the panel says where to look
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

-- A Core reload reconnects and the tab mounts again
local oldAPI = core.result
h.host:Reload("bankcore", { shutdown = true, notify = true, reinject = true })
assert(not oldAPI.GetState().running and app:IsConnected() and app.bank == core.result)
assert(app.shownPage == nil and app.snapshot == nil)
h:OpenBank()
h:Tick(2)
assert(app.tab.controls ~= nil)

-- A cloned Core API still connects after a reload
h.host:Reload("bankcore", { shutdown = true })
h.host.exports.bankcore = Loader.Clone(core.result)
h.host:Notify("bankcore", true, true)
assert(app:IsConnected() and app.bank == h.host.exports.bankcore and getmetatable(app.bank) == nil)

-- Core unloading mid-wait releases the plugin and ends the wait
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

-- Separate states: a newer copy takes the owner ID
-- The older copy stays idle when told Core loaded
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
