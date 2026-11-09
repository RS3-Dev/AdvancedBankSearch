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
assert(controls ~= nil and h:TabParent() ~= nil, "the Search column did not mount: " .. tostring(h:LoggedFailure()))

-- Count the pages this plugin gives Bank Core
local updates = 0
local setPage = service.SetPage
service.SetPage = function(pages, owner, page)
    if owner.id == "advancedbanksearch" then updates = updates + 1 end
    return setPage(pages, owner, page)
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
    local action = button.root.hooks[ui.Hook.ONBUTTONPRESSED] or button.root.hooks[ui.Hook.ONCLICK]; action()
    h:Tick(2)
end

-- Describe the shown page below its title: labels, then object=quantity for each stack
local function shown()
    local entries = {}
    for index, heading in ipairs(layout.pageState:GetLayoutSections()) do
        -- The first heading is the page title
        if index > 1 then entries[#entries + 1] = { y = heading.y, x = -1, text = "[" .. heading.label .. "]" } end
    end
    for _, entry in ipairs(layout:BuildPageItems()) do
        entries[#entries + 1] = { y = entry.y, x = entry.x, text = entry.objectID .. "=" .. tostring(entry.quantity) }
    end
    table.sort(entries, function(a, b)
        if a.y == b.y then return a.x < b.x end
        return a.y < b.y
    end)
    local parts = {}
    for index, entry in ipairs(entries) do parts[index] = entry.text end
    return table.concat(parts, " ")
end

-- Bank Core's key for the shown opening, or nil in the bank's own view
-- Opening again changes it; a redraw in place keeps it
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
assert(key() == nil and app:ShownPage() == nil)
type("iron")
assert(key() ~= nil and app:ShownPage() == "search")
assert(layout.shownPage.title == "Search")
-- Every iron stack, placeholder included, and never the lobster
local first = shown()
assert(string.find(first, "103=0", 1, true) and string.find(first, "101=3", 1, true) and not string.find(first, "105"), first)
assert(app.status == "5 matches.", app.status)
-- New text opens again, starting at the top; 101 is listed once per matching stack
local opening = key()
type("iron bar")
assert(key() ~= opening and string.find(shown(), "^101=5 101=3 "), shown())

-- A bank change keeps result slots; Core updates stocked stacks and placeholders itself.
opening = key()
takeUpdates()
host:Rebuild(function(specs)
    specs[1][2] = 0
    return specs
end)
layout:HandleInventoryUpdate()
h:Tick(4)
assert(takeUpdates() == 0 and key() == opening)
assert(string.find(shown(), "^101=3 101=0 "), shown())

-- Text RuneQL cannot read shows why
type("name:(iron")
assert(shown() == "[RuneQL could not read this search]", shown())
assert(string.find(app.status, "^RuneQL could not read this search: "))
-- Nothing found says so
type("dragon")
assert(shown() == "[No items match]" and app.status == "No items match.")
-- Clearing the text returns to the bank's own view
type("")
assert(key() == nil and app:ShownPage() == nil)

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
local field = controls.field
for _, text in ipairs({ "ir", "iro", "iron", "iron b", "iron ba" }) do
    enter(text)
    h:Tick(9)
end
assert(takeCompiled() == "" and takeUpdates() == 0 and key() == nil and app.text == "" and app.draft == "iron ba")
assert(waiting())
enter("iron bar")
h:Tick(9)
assert(takeCompiled() == "" and takeUpdates() == 0 and key() == nil)
h:Tick()
assert(takeCompiled() == "iron bar" and takeUpdates() == 1)
assert(app:ShownPage() == "search" and string.find(shown(), "^101=3 101=0 "), shown())
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
h.host:Notify("gepl", false, false)
h:Tick(2)
local during = takeCompiled()
assert(string.find(during, "iron bar", 1, true) and not string.find(during, "lobster", 1, true), during)
assert(app.text == "iron bar" and string.find(shown(), "^101=3 101=0 ") and waiting(), shown())
h:Tick(4)
assert(takeCompiled() == "lobster" and app.text == "lobster" and not waiting())
h:Tick(2)
assert(shown() == "105=9", shown())

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

-- A taller column keeps the field, its text, and its wait without searching
-- The footer buttons move to the new bottom and the list grows
enter("iron ore")
h:Tick(5)
local listHeight, footerTop = controls.list.root.height, controls.new.root.y
layout:ResizeSidebar(layout.sidebarHeight + 40)
assert(app.tab.controls == controls and controls.field == field and controls.field:GetText() == "iron ore")
assert(waiting() and takeCompiled() == "" and h:TabParent() == app.tab.ctx.parent)
assert(controls.new.root.y == footerTop + 40 and controls.share.root.y == footerTop + 40)
assert(controls.list.root.height == listHeight + 40, tostring(controls.list.root.height))
h:Tick(5)
assert(takeCompiled() == "iron ore" and app:ShownPage() == "search" and controls.field:GetText() == "iron ore")
type("")

-- Typing updates disabled states only when they change
local disabledSets = 0
for _, name in ipairs({ "field", "edit" }) do
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
assert(controls.edit.hidden and controls.delete == nil)
-- The editor opens in the bank without creating a separate window
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
assert(editor ~= nil and editor.queryID == nil and shownWindows == 0 and app.editorExt:IsOpen())
-- New queries start in Visual; these are typed in Advanced
assert(editor.mode == "visual")
assert(app.settings:Set("editorMode", "advanced"))
editor.nameField:SetText("Iron")
editor.queryField:SetText("iron")
-- Saving compiles at once, not after a pause
takeCompiled()
editor.saveButton.root.hooks[ui.Hook.ONCLICK]()
assert(app.editor == nil and takeCompiled() == "iron" and not waiting())
h:Tick(2)
assert(app.editor == nil and rows() == "Iron" and app.selectedQuery == "1")
assert(h.databases.advancedbanksearch["advancedbanksearch:queries:v1:manifest"] ~= nil)

-- Choosing it shows its page without placeholders and keeps its name alone
-- Text still waiting to search is dropped, so it cannot take the page
enter("lobster")
assert(h:ClickRow("1"))
h:Tick(20)
assert(app:ShownPage() == "query" and layout.shownPage.title == "Iron")
assert(not waiting() and app.text == "" and controls.field:GetText() == "lobster")
assert(shown() == "101=5 102=5 104=5 101=3", shown())
assert(rows() == "Iron", rows())
-- Withdrawing all of an item keeps its slot, even with no native placeholder.
opening = key()
takeUpdates()
host:SetItems({ { 101, 2 }, { 103, 0 }, { 104, 0 }, { 105, 9 }, { 101, 3 } })
layout:HandleInventoryUpdate()
h:Tick(4)
assert(key() == opening and takeUpdates() == 0)
assert(shown() == "101=2 102=0 104=0 101=3", shown())
assert(h:ClickRow("1"))
assert(h:ClickRow("1"))
h:Tick(4)
assert(shown() == "101=2 101=3", shown())
-- Depositing items also leaves membership fixed until the next opening.
host:SetItems({ { 101, 5 }, { 102, 5 }, { 103, 0 }, { 104, 5 }, { 105, 9 }, { 101, 3 } })
layout:HandleInventoryUpdate()
h:Tick(4)
assert(shown() == "101=5 101=3", shown())
-- Choosing it again returns to the bank's own view
assert(h:ClickRow("1"))
h:Tick(2)
assert(key() == nil)

-- Editing renames the shown page
assert(h:ClickRow("1"))
h:Tick(2)
press(controls.edit)
app.editor.nameField:SetText("Bars")
app.editor.queryField:SetText('name:"iron bar"')
press(app.editor.saveButton)
h:Tick(2)
assert(layout.shownPage.title == "Bars" and app:ShownPage() == "query")
assert(shown() == "101=5 101=3" and rows() == "Bars", shown())

-- A refused save shows in the editor and changes nothing
local database = h.search.env.PersistentDB
h.search.env.PersistentDB = { GetString = database.GetString, SetString = function() return false end }
press(controls.new)
assert(app.settings:Set("editorMode", "advanced"))
app.editor.nameField:SetText("Lobster")
app.editor.queryField:SetText("lobster")
press(app.editor.saveButton)
assert(app.editor ~= nil and app.editor.status.content == "PersistentDB could not save RuneQL chunk 1.")
assert(app.queries:FindName("Lobster") == nil and rows() == "Bars")
h.search.env.PersistentDB = database
press(app.editor.saveButton)
assert(app.editor == nil and rows() == "Bars | Lobster")

-- Saving another query selects it but keeps the shown page
assert(app:ShownPage() == "query" and app.pageQuery == "1" and app.selectedQuery == "2")

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
assert(app.settings:Set("editorMode", "advanced"))
app.editor.nameField:SetText("Broken")
app.editor.queryField:SetText("iron AND (")
press(app.editor.saveButton)
assert(app.editor ~= nil and app.editor.status.content == tostring(unreadableReason), app.editor.status.content)
assert(stored() == before and rows() == "Bars | Lobster" and app.selectedQuery == "2" and app:ShownPage() == nil and app.editorExt:IsOpen())
app.editor:Close()
-- Editing an unshown query drops its count only when saved
assert(h:ClickRow("1"))
h:Tick(2)
assert(key() == nil and app.selectedQuery == "1" and rows() == "Bars | Lobster")
press(controls.edit)
app.editor.queryField:SetText("iron AND (")
press(app.editor.saveButton)
assert(app.editor ~= nil and stored() == before and rows() == "Bars | Lobster")
app.editor.queryField:SetText("iron")
press(app.editor.saveButton)
assert(app.editor == nil and app.queries:Get("1").query == "iron" and rows() == "Bars | Lobster", rows())
-- Showing it refreshes results without adding a count to the name
assert(h:ClickRow("1"))
h:Tick(2)
assert(app:ShownPage() == "query" and rows() == "Bars | Lobster", rows())

-- Delete asks once, then deletes and leaves the page
assert(h:ClickRow("1"))
h:Tick(2)
assert(key() == nil and app.selectedQuery == "1")
assert(h:ClickRow("1"))
h:Tick(2)
assert(app:ShownPage() == "query")
app:DeleteQuery()
assert(app.queries:Get("1") ~= nil and app.status == 'Press Delete again to delete "Bars".')
app:DeleteQuery()
assert(app.queries:Get("1") == nil and key() == nil and app.pageID == nil and rows() == "Lobster")

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
h.host.exports.gepl = prices
h.host:Notify("gepl", true, true)
assert(app:Prices() == prices)
type("iron AND NOT price:[1 TO 100] ")
assert(shown() == "[Waiting for GE prices...]" and app.priceWait ~= nil, shown())
assert(app.status == "Waiting for GE prices...")
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
assert(not string.find(shown(), "101", 1, true) and string.find(shown(), "102=5", 1, true), shown())

-- A wait from an earlier search is dropped when it changes
ready = false
type("price:[1 TO *]")
assert(app.priceWait ~= nil)
type("lobster")
assert(app.priceWait == nil and shown() == "105=9", shown())
ready = true
for _ = 1, 60 do h:Tick() end
assert(shown() == "105=9")

-- Prices that arrive after the player picks a native tab show nothing, even a bank change
-- heard before the page's close; the bank keeps its own view and the page is only stored
ready = false
type("price:[3 TO *]")
assert(app.priceWait ~= nil and app:ShownPage() == "search")
layout:SetNativeViewAll(false)
app:OnBankItems()
assert(layout.shownPage == nil and app:ShownPage() == nil and app.pageID == "search")
ready = true
for _ = 1, 60 do h:Tick() end
assert(layout.shownPage == nil and app.priceWait == nil)
-- Outside All Items, a new search says what to do in the status line
type("lobster")
assert(layout.shownPage == nil and app.status == 'Select "All Items" to view these search results.')
layout:SetNativeViewAll(true)
h:Tick(2)

-- A wait gives up after 1,800 ticks; the query is kept
ready = false
type("price:[1 TO *]")
for _ = 1, 1800 do h:Tick() end
assert(app.priceWait == nil and shown() == "[GE prices did not load]", shown())
assert(app.status == "GE prices did not load; check GE Prices' HTTP access.")

-- GE Prices unloading ends a wait and its global is ignored
type("price:[2 TO *]")
assert(app.priceWait ~= nil)
h.host:Notify("gepl", false, false)
assert(app.priceWait == nil and app:Prices() == nil and rawget(h.search.env, "gepl") == prices)
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
assert(rows() == "Lobster" and app.status == "Searching needs RuneQL. Enable RuneQL to search your bank.")
press(controls.new)
assert(app.editor.saveButton.disabled and app.editor.status.content == "Searching needs RuneQL. Enable RuneQL to search your bank.")
press(app.editor.saveButton)
assert(app.editor ~= nil and app.queries:FindName("") == nil and #app.queries:All() == 1)
app.editor:Close()
assert(h:ClickRow("2"))
h:Tick(2)
assert(key() == nil)
-- RuneQL loads again and searching works
h.host:Notify("runeql", true, true)
h:Tick()
assert(not controls.field.disabled)
type("lobster")
assert(shown() == "105=9")

-- Closing the bank leaves the page and closes the editor
-- Waiting typed text is dropped too
press(controls.new)
assert(app.editor ~= nil)
enter("iron")
assert(waiting())
h.bankHost:UnmountBankWindow()
session:CloseBank()
h:Tick(20)
assert(app.editor == nil and app:ShownPage() == nil and not waiting() and app.items == nil)

h.host:Unload("advancedbanksearch")
h.host:Unload("bankcore")
print("search_app_test: ok")
