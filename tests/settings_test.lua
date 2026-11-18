package.path = "./?.lua;./?/init.lua;" .. package.path

local Harness = require("tests/support/search_harness")
local h = Harness.new("settings")
local manifest = assert(io.open(h.searchFolder .. "/plugin.json", "rb"))
assert(manifest:read("a"):find('"hasSettingsIcon": true', 1, true))
manifest:close()
h:NameObjects({ { 101, "Iron bar" }, { 102, "Iron ore" } })
h.bankHost:SetItems({ { 101, 5 }, { 102, 0 } })
h:LoadSearch()
local app = h:App()
assert(app.settings.values.editorMode == "visual" and app.settings.values.includePlaceholders)
assert(app.settings.values.searchDelayTicks == 10)
local mount = assert(h.settingsSubscriptions.advancedbanksearch_settings)
local parent = ui.Layer.new(nil)
parent:SetSize(400, 500)
mount({ component = parent })
local settings, firstView = app.settings, app.settings.view
assert(firstView and settings.controls.editorMode:GetSelectedLabel() == "Visual")
settings.controls.editorMode.root:Click("Advanced")
settings.controls.includePlaceholders.root:Click("Hide placeholders")
settings.controls.searchDelayTicks.root:Click("Relaxed (400 ms)")
assert(settings.values.editorMode == "advanced" and settings.values.includePlaceholders == false)
assert(settings.values.searchDelayTicks == 20)
assert(h.databases.advancedbanksearch["advancedbanksearch:settings:v1"])
local stale = settings.controls.editorMode.onChange
mount({ component = parent })
assert(firstView.root.destroyed and settings.view ~= firstView)
stale(nil, 2)
assert(settings.values.editorMode == "advanced")

-- Failed persistence rolls the control back and preserves active preferences
local database = h.search.env.PersistentDB
h.search.env.PersistentDB = { GetString = database.GetString, SetString = function() return false end }
settings.controls.editorMode.root:Click("Visual")
assert(settings.values.editorMode == "advanced" and not settings.status.hidden)
assert(settings.controls.editorMode:GetSelectedLabel() == "Advanced")
h.search.env.PersistentDB = database

-- Reload keeps preferences and removes the previous settings listener/view
local oldView = settings.view
h.host:Unload("advancedbanksearch")
assert(oldView.root.destroyed and h.settingsSubscriptions.advancedbanksearch_settings == nil)
h:LoadSearch()
app = h:App()
assert(app.settings.values.editorMode == "advanced" and not app.settings.values.includePlaceholders)
h:LoadRuneQL()
h:LoadCore()
h:OpenBank()
h:Tick(2)
app:NewQuery()
assert(app.editor.mode == "advanced")
app:CloseEditor()

-- The preference applies to new queries and saved visual queries.
assert(app:SaveQuery(nil, "Typed", "iron"))
app:EditQuery("1")
assert(app.editor.mode == "advanced")
app:CloseEditor()
local builder = { match = "all", rules = { { field = "qty", operator = "atleast", value = 1 } } }
assert(app:SaveQuery(nil, "Visual", "qty:[1 TO *]", builder))
app:EditQuery("2")
assert(app.editor.mode == "advanced" and app.editor.queryField:GetText() == "qty:[1 TO *]")
assert(app.settings:Set("editorMode", "visual"))
assert(app.editor.mode == "visual" and app.editor.visualButton == nil and app.editor.advancedButton == nil)
assert(app.settings:Set("editorMode", "advanced"))
assert(app.editor.mode == "advanced")
-- The actual Plugin Hub control changes the live builder; a rejected write does not.
app.settings:Mount(parent)
assert(Harness.Find(parent, "Query builder") ~= nil)
app.settings.controls.editorMode.root:Click("Visual")
assert(app.editor.mode == "visual")
assert(app.editor.body.root.y == 0)
app.settings.controls.editorMode.root:Click("Advanced")
assert(app.editor.mode == "advanced")
local currentDB = h.search.env.PersistentDB
h.search.env.PersistentDB = { GetString = currentDB.GetString, SetString = function() return false end }
app.settings.controls.editorMode.root:Click("Visual")
assert(app.editor.mode == "advanced" and app.settings.controls.editorMode:GetSelectedLabel() == "Advanced")
h.search.env.PersistentDB = currentDB
app:CloseEditor()

-- Quick-search settings apply immediately, saved searches still exclude placeholders
assert(app.settings:Set("searchDelayTicks", 5))
app:QueueText("iron")
h:Tick(4)
assert(app.text ~= "iron")
h:Tick(1)
assert(app.text == "iron" and app:ShownPage() == "search")
assert(app.status == "1 match.")
local found = app:Run("iron", not app.settings.values.includePlaceholders)
assert(#found.matches == 1)
assert(app.settings:Set("includePlaceholders", true))
assert(app.status == "2 matches.")
found = app:Run("iron", not app.settings.values.includePlaceholders)
assert(#found.matches == 2)
assert(app.settings:Set("searchDelayTicks", 20))
app:QueueText("ore")
h:Tick(4)
assert(app.settings:Set("searchDelayTicks", 5))
h:Tick(4)
assert(app.text == "iron")
h:Tick(1)
assert(app.text == "ore")
assert(app:ChooseQuery("1"))
assert(app.counts["1"] == 1)

-- Invalid persisted data uses defaults without rewriting the stored data
h.host:Unload("advancedbanksearch")
h.databases.advancedbanksearch["advancedbanksearch:settings:v1"] = "broken JSON"
h:LoadSearch()
assert(h:App().settings.values.editorMode == "visual")
assert(h.databases.advancedbanksearch["advancedbanksearch:settings:v1"] == "broken JSON")
h.host:Unload("advancedbanksearch")
h.host:Unload("bankcore")
print("settings_test: ok")
