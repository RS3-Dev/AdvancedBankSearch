package.path = "./?.lua;./?/init.lua;" .. package.path

-- Drive the built Advanced Bank Search through Bank Core and RuneQL
-- FAKE HOST: stand-in loader, components, and widgets, not the game client

local Harness = require("tools/test_support/search_harness")

local h = Harness.new("search_app")
local host = h.bankHost
h:NameObjects({ { 101, "Iron bar" }, { 102, "Iron ore" }, { 103, "Iron axe" }, { 104, "Iron platebody" },
    { 105, "Lobster" } })
-- 103 is a placeholder; 101 has a second stack at the end
host:SetItems({ { 101, 5 }, { 102, 5 }, { 103, 0 }, { 104, 5 }, { 105, 9 }, { 101, 3 } })

h:LoadCore()
h:LoadRuneQL()
h:LoadSearch()
local app = h:App()
assert(app:IsConnected() and app:RuneQL() ~= nil and app:Prices() == nil)
local session, layout = h:OpenBank()
local service = session.pluginPages
h:Tick(2)
local controls = app.tab.controls
assert(controls ~= nil and h:TabParent() ~= nil, "the Search tab did not mount: " .. tostring(h:LoggedFailure()))

-- Count the pages this plugin gives Bank Core
local updates = 0
local createPage = service.CreatePage
service.CreatePage = function(pages, owner, page)
    if owner.id == "advancedbanksearch" then updates = updates + 1 end
    return createPage(pages, owner, page)
end
local function takeUpdates()
    local count = updates
    updates = 0
    return count
end

-- Type into the search field as the host reports it
local function enter(text)
    controls.field.root.content = text
    controls.field.root.hooks[ui.Hook.ONCONTENTCHANGED](controls.field.root, "change", text)
end

-- Type, then wait out the 10 quiet ticks before searching
local function type(text)
    enter(text)
    h:Tick(12)
end

-- Press a PrettyUI button
local function press(button)
    button.root.hooks[ui.Hook.ONCLICK]()
    h:Tick(2)
end

-- Describe the shown page: labels, then object:copy, ? for placeholders
local function shown()
    local entries = {}
    for _, heading in ipairs(layout.pageState:GetLayoutSections()) do
        entries[#entries + 1] = { y = heading.y, x = -1, text = "[" .. heading.label .. "]" }
    end
    for _, entry in ipairs(layout:BuildPageItems()) do
        entries[#entries + 1] = { y = entry.y, x = entry.x,
            text = string.gsub(entry.layoutKey, "^object:", "") .. (entry.placeholder and "?" or "") }
    end
    table.sort(entries, function(a, b)
        if a.y == b.y then return a.x < b.x end
        return a.y < b.y
    end)
    local parts = {}
    for index, entry in ipairs(entries) do parts[index] = entry.text end
    return table.concat(parts, " ")
end

-- The shown page's key, or nil in the bank's own view
local function key()
    return layout.shownPage ~= nil and layout.shownPage.key or nil
end

-- List the saved query rows as drawn
local function rows()
    local labels = {}
    for index, entry in ipairs(controls.list.rows) do labels[index] = entry.entry.label end
    return table.concat(labels, " | ")
end

-- Searching -----------------------------------------------------------------------------

-- One character shows nothing; longer text opens the search page
-- RuneQL matches whole terms
type("i")
assert(key() == nil and app.shownPage == nil)
type("iron")
assert(key() == "search:1" and app.shownPage == "search", tostring(key()))
assert(layout.shownPage.title == "Search")
-- Every iron stack, placeholder included, and never the lobster
local first = shown()
assert(string.find(first, "103:1?", 1, true) and string.find(first, "101:2", 1, true) and not string.find(first, "105"), first)
assert(controls.status.content == "5 matches.", controls.status.content)
-- New text gets a new key and starts at the top
type("iron bar")
assert(key() == "search:2" and string.find(shown(), "^101:1 101:2"), shown())

-- A bank change reranks under the same key
takeUpdates()
host:Rebuild(function(specs)
    specs[1][2] = 0
    return specs
end)
layout:HandleInventoryUpdate()
h:Tick(4)
assert(key() == "search:2")
assert(string.find(shown(), "101:1?", 1, true), shown())
-- A bank change with the same results sends nothing
takeUpdates()
host:Rebuild()
layout:HandleInventoryUpdate()
h:Tick(4)
assert(takeUpdates() == 0)

-- Text RuneQL cannot read shows why
type("name:(iron")
assert(shown() == "[RuneQL could not read this search]", shown())
assert(string.find(controls.status.content, "^RuneQL could not read this search: "))
-- Nothing found says so
type("dragon")
assert(shown() == "[No items match]" and controls.status.content == "No items match.")
-- Clearing the text returns to the bank's own view
type("")
assert(key() == nil and app.shownPage == nil)

-- Typing pauses --------------------------------------------------------------------------

-- Count the texts RuneQL compiles
local engine = app:RuneQL()
local compile = engine.Compile
local compiled = {}
engine.Compile = function(text, ...)
    compiled[#compiled + 1] = text
    return compile(text, ...)
end
local function takeCompiled()
    local texts = table.concat(compiled, " | ")
    compiled = {}
    return texts
end
local function waiting()
    return app.searchWait ~= nil and h.bankHost:Listener("advancedbanksearch_search_wait") ~= nil
end

-- Rapid typing searches once, 10 quiet ticks after the last key
takeUpdates()
local field, serial = controls.field, app.serial
for _, text in ipairs({ "ir", "iro", "iron", "iron b", "iron ba" }) do
    enter(text)
    h:Tick(9)
end
assert(takeCompiled() == "" and takeUpdates() == 0 and key() == nil and app.text == "" and app.draft == "iron ba")
assert(waiting() and app.serial == serial)
enter("iron bar")
h:Tick(9)
assert(takeCompiled() == "" and takeUpdates() == 0 and key() == nil)
h:Tick()
assert(takeCompiled() == "iron bar" and takeUpdates() == 1 and app.serial == serial + 1)
assert(key() == "search:" .. app.serial and string.find(shown(), "^101:1%?? 101:2"), shown())
assert(not waiting() and controls.field == field and field:GetText() == "iron bar")
h:Tick(20)
assert(takeCompiled() == "" and takeUpdates() == 0)

-- Bank changes and dependency changes while typing rank only the shown search
enter("lobster")
host:Rebuild(function(specs)
    specs[2][2] = 0
    return specs
end)
layout:HandleInventoryUpdate()
h:Tick(4)
h.host:Notify("geprices", false, false)
h:Tick(2)
local during = takeCompiled()
assert(string.find(during, "iron bar", 1, true) and not string.find(during, "lobster", 1, true), during)
assert(app.text == "iron bar" and string.find(shown(), "^101:1%?? 101:2") and waiting(), shown())
h:Tick(4)
assert(takeCompiled() == "lobster" and app.text == "lobster" and not waiting())
h:Tick(2)
assert(shown() == "105:1", shown())

-- Clearing or short text applies at once and drops the waiting search
enter("iron ore")
h:Tick(5)
enter("")
h:Tick(2)
assert(key() == nil and app.text == "" and not waiting())
type("lobster")
enter("lobster b")
h:Tick(3)
enter("l")
h:Tick(2)
assert(key() == nil and app.text == "l" and not waiting())
h:Tick(20)
local settled = takeCompiled()
assert(key() == nil and string.find(settled, "lobster", 1, true) and not string.find(settled, "lobster b", 1, true), settled)

-- A resize keeps the typed text and its wait without searching
enter("iron ore")
h:Tick(5)
app.tab.callbacks.resize()
controls = app.tab.controls
assert(controls.field ~= field and controls.field:GetText() == "iron ore" and waiting() and takeCompiled() == "")
h:Tick(5)
assert(takeCompiled() == "iron ore" and string.find(key(), "^search:") and controls.field:GetText() == "iron ore")
type("")

-- Typing updates disabled states only when they change
local disabledSets = 0
for _, name in ipairs({ "field", "edit", "delete" }) do
    local setDisabled = controls[name].SetDisabled
    controls[name].SetDisabled = function(...)
        disabledSets = disabledSets + 1
        return setDisabled(...)
    end
end
type("i")
type("")
assert(disabledSets == 0)
host:SetItems({ { 101, 5 }, { 102, 5 }, { 103, 0 }, { 104, 5 }, { 105, 9 }, { 101, 3 } })
layout:HandleInventoryUpdate()
h:Tick(4)

-- Saved queries -------------------------------------------------------------------------

assert(rows() == "" and not controls.empty.hidden)
assert(controls.edit.disabled and controls.delete.disabled)
-- The editor opens shown
local newWindow, shownWindows = prettyui.Window.new, 0
prettyui.Window.new = function(...)
    local window = newWindow(...)
    local show = window.Show
    function window:Show()
        shownWindows = shownWindows + 1
        return show(self)
    end
    return window
end
press(controls.new)
local editor = app.editor
assert(editor ~= nil and editor.queryID == nil and shownWindows == 1)
-- New queries start in Visual; these are typed in Advanced
assert(editor.mode == "visual")
press(editor.advancedButton)
editor.nameField:SetText("Iron")
editor.queryField:SetText("iron")
-- Saving compiles at once, not after a pause
takeCompiled()
editor.saveButton.root.hooks[ui.Hook.ONCLICK]()
assert(app.editor == nil and takeCompiled() == "iron" and not waiting())
h:Tick(2)
assert(app.editor == nil and rows() == "Iron" and app.selectedQuery == "1")
assert(h.databases.advancedbanksearch["advancedbanksearch:queries:v1:manifest"] ~= nil)

-- Choosing it shows its page without placeholders and adds its count
-- Text still waiting to search is dropped, so it cannot take the page
enter("lobster")
assert(controls.list:Click("1"))
h:Tick(20)
assert(key() == "query:1" and layout.shownPage.title == "Iron")
assert(not waiting() and app.text == "" and controls.field:GetText() == "lobster")
assert(not string.find(shown(), "?", 1, true) and string.find(shown(), "101:2", 1, true), shown())
assert(rows() == "Iron (4)", rows())
-- Choosing it again returns to the bank's own view
assert(controls.list:Click("1"))
h:Tick(2)
assert(key() == nil)

-- Editing renames the shown page
assert(controls.list:Click("1"))
h:Tick(2)
press(controls.edit)
app.editor.nameField:SetText("Bars")
app.editor.queryField:SetText('name:"iron bar"')
press(app.editor.saveButton)
h:Tick(2)
assert(layout.shownPage.title == "Bars" and key() == "query:1")
assert(shown() == "101:1 101:2" and rows() == "Bars (2)", shown())

-- A refused save shows in the editor and changes nothing
local database = h.search.env.PersistentDB
h.search.env.PersistentDB = { GetString = database.GetString, SetString = function() return false end }
press(controls.new)
press(app.editor.advancedButton)
app.editor.nameField:SetText("Lobster")
app.editor.queryField:SetText("lobster")
press(app.editor.saveButton)
assert(app.editor ~= nil and app.editor.status.content == "PersistentDB could not save RuneQL chunk 1.")
assert(app.queries:FindName("Lobster") == nil and rows() == "Bars (2)")
h.search.env.PersistentDB = database
press(app.editor.saveButton)
assert(app.editor == nil and rows() == "Bars (2) | Lobster")

-- Saving another query selects it but keeps the shown page
assert(key() == "query:1" and app.selectedQuery == "2")

-- Unreadable query text is refused with RuneQL's reason
-- Nothing is written and the editor and tab stay as they were
local function stored()
    local entries = {}
    for name, value in pairs(h.databases.advancedbanksearch) do entries[#entries + 1] = name .. "=" .. tostring(value) end
    table.sort(entries)
    return table.concat(entries, "\n")
end
local before = stored()
local unreadable, unreadableReason = app:RuneQL().Compile("iron AND (")
assert(unreadable == nil and unreadableReason ~= nil)
press(controls.new)
press(app.editor.advancedButton)
app.editor.nameField:SetText("Broken")
app.editor.queryField:SetText("iron AND (")
press(app.editor.saveButton)
assert(app.editor ~= nil and app.editor.status.content == tostring(unreadableReason), app.editor.status.content)
assert(stored() == before and rows() == "Bars (2) | Lobster" and app.selectedQuery == "2" and key() == "query:1")
app:CloseEditor()
-- Editing an unshown query drops its count only when saved
assert(controls.list:Click("1"))
h:Tick(2)
assert(key() == nil and app.selectedQuery == "1" and rows() == "Bars (2) | Lobster")
press(controls.edit)
app.editor.queryField:SetText("iron AND (")
press(app.editor.saveButton)
assert(app.editor ~= nil and stored() == before and rows() == "Bars (2) | Lobster")
app.editor.queryField:SetText("iron")
press(app.editor.saveButton)
assert(app.editor == nil and app.queries:Get("1").query == "iron" and rows() == "Bars | Lobster", rows())
-- Showing it counts it afresh
assert(controls.list:Click("1"))
h:Tick(2)
assert(key() == "query:1" and rows() == "Bars (4) | Lobster", rows())

-- Delete asks once, then deletes and leaves the page
assert(controls.list:Click("1"))
h:Tick(2)
assert(key() == nil and app.selectedQuery == "1")
assert(controls.list:Click("1"))
h:Tick(2)
assert(key() == "query:1")
press(controls.delete)
assert(app.queries:Get("1") ~= nil and controls.status.content == 'Press Delete again to delete "Bars".')
press(controls.delete)
assert(app.queries:Get("1") == nil and key() == nil and rows() == "Lobster")

-- Price queries -------------------------------------------------------------------------

-- Without GE Prices, a price query's page says it needs them
type("iron AND NOT price:[1 TO 100]")
assert(shown() == "[This search needs GE Prices]", shown())
assert(app.priceWait == nil)
-- With no prices yet, the page checks every 30 ticks
local ready = false
local prices = {
    isReady = function() return ready end,
    getPrice = function(objectID)
        if objectID == 101 then return { high = 50, low = 40 } end
        error("Price not found for itemId: " .. tostring(objectID))
    end,
}
h.host.exports.geprices = prices
h.host:Notify("geprices", true, true)
assert(app:Prices() == prices)
type("iron AND NOT price:[1 TO 100] ")
assert(shown() == "[Waiting for GE prices...]" and app.priceWait ~= nil, shown())
assert(controls.status.content == "Waiting for GE prices...")
-- No check runs before the 30th tick
local wait = app.priceWait
while wait.ticks < 28 do h:Tick() end
ready = true
h:Tick()
assert(app.priceWait == wait and shown() == "[Waiting for GE prices...]")
h:Tick()
assert(wait.ticks == 30 and app.priceWait == nil)
h:Tick(2)
-- Once prices load, unpriced or cheap iron stacks are ranked
assert(app.priceWait == nil and h.bankHost:Listener("advancedbanksearch_price_wait") == nil)
assert(not string.find(shown(), "101", 1, true) and string.find(shown(), "102:1", 1, true), shown())

-- A wait from an earlier search is dropped when it changes
ready = false
type("price:[1 TO *]")
assert(app.priceWait ~= nil)
local waitKey = app.priceWait.key
type("lobster")
assert(app.priceWait == nil and key() ~= waitKey and shown() == "105:1", shown())
ready = true
for _ = 1, 60 do h:Tick() end
assert(shown() == "105:1")

-- Prices that arrive after the player picks a native tab show nothing, even a bank change
-- heard before the page's notice; the bank keeps its own view
ready = false
type("price:[3 TO *]")
assert(app.priceWait ~= nil and app.shownPage == "search")
takeUpdates()
layout:SetNativeViewAll(false)
app:OnBankItems()
assert(layout.shownPage == nil and takeUpdates() == 0)
ready = true
for _ = 1, 60 do h:Tick() end
assert(layout.shownPage == nil and app.shownPage == nil and app.priceWait == nil and takeUpdates() == 0)
layout:SetNativeViewAll(true)

-- A wait gives up after 1,800 ticks; the query is kept
ready = false
type("price:[1 TO *]")
for _ = 1, 1800 do h:Tick() end
assert(app.priceWait == nil and shown() == "[GE prices did not load]", shown())
assert(controls.status.content == "GE prices did not load; check GE Prices' HTTP access.")

-- GE Prices unloading ends a wait and its global is ignored
type("price:[2 TO *]")
assert(app.priceWait ~= nil)
h.host:Notify("geprices", false, false)
assert(app.priceWait == nil and app:Prices() == nil and rawget(h.search.env, "geprices") == prices)
h:Tick(2)
assert(shown() == "[This search needs GE Prices]", shown())

-- RuneQL unloading ----------------------------------------------------------------------

-- The page closes, waiting typed text is dropped, and the field is disabled
-- Queries stay but cannot save
enter("lobster")
h.host:Notify("runeql", false, false)
assert(not waiting())
h:Tick(20)
assert(key() == nil and app:RuneQL() == nil and controls.field.disabled)
assert(rows() == "Lobster" and controls.status.content == "Searching needs RuneQL. Enable RuneQL to search your bank.")
press(controls.new)
assert(app.editor.saveButton.disabled and app.editor.status.content == "Searching needs RuneQL. Enable RuneQL to search your bank.")
press(app.editor.saveButton)
assert(app.editor ~= nil and app.queries:FindName("") == nil and #app.queries:All() == 1)
app:CloseEditor()
assert(controls.list:Click("2"))
h:Tick(2)
assert(key() == nil)
-- RuneQL loads again and searching works
h.host:Notify("runeql", true, true)
h:Tick()
assert(not controls.field.disabled)
type("lobster")
assert(shown() == "105:1")

-- Closing the bank leaves the page and closes the editor
-- Waiting typed text is dropped too
press(controls.new)
assert(app.editor ~= nil)
enter("iron")
assert(waiting())
h.bankHost:UnmountBankWindow()
session.layout:Restore()
h:Tick(20)
assert(app.editor == nil and app.shownPage == nil and not waiting())

h.host:Unload("advancedbanksearch")
h.host:Unload("bankcore")
print("search_app_test: ok")
