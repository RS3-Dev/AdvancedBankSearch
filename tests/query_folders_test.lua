package.path = "./?.lua;./?/init.lua;" .. package.path

-- Drive the Search tab's folders, sorting, and compact layout through the real Bank Core and
-- the installed RuneQL: the status line taking room only while it has text, with the field
-- kept; folder rows with their counts, chevrons, and indented queries; a folder opening and
-- closing without changing the chosen query or the page; a closed folder outlined when it
-- holds the chosen query; sorting with arrows that never open a query; the row menus' folder
-- actions and their dialogs, dropped when stale; refused saves; and cleanup on unload
-- FAKE HOST: stand-in loader, components, and widgets, not the game client

local Harness = require("tools/test_support/search_harness")

local h = Harness.new("query_folders")
h:NameObjects({ { 101, "Iron bar" }, { 102, "Iron ore" }, { 105, "Lobster" } })
h.bankHost:SetItems({ { 101, 5 }, { 102, 5 }, { 105, 9 } })
h:LoadCore()
h:LoadRuneQL()
h:LoadSearch()
local app = h:App()
local _, layout = h:OpenBank()
h:Tick(2)
local tab = app.tab
local controls = tab.controls
local parent = h:TabParent()
assert(controls ~= nil and parent ~= nil, "the Search tab did not mount: " .. tostring(h:LoggedFailure()))

-- Type into the search field as the host reports it
local function type(text)
    controls.field.root.content = text
    controls.field.root.hooks[ui.Hook.ONCONTENTCHANGED](controls.field.root, "change", text)
    h:Tick(2)
end

-- List the rows as drawn: > marks a folder member, * a selected row
local function rows()
    local labels = {}
    for index, row in ipairs(controls.list.rows) do
        local info = tab.rowInfo[row.entry.id]
        labels[index] = (info.inFolder and ">" or "") .. row.entry.label .. (row.entry.selected and "*" or "")
    end
    return table.concat(labels, " | ")
end

-- Find a drawn row by its label
local function rowNamed(label)
    for _, row in ipairs(controls.list.rows) do
        if row.entry.label == label then return row end
    end
    error("no row " .. label .. " in " .. rows())
end

-- The shown page's key, or nil in the bank's own view
local function key()
    return layout.selectedTag ~= nil and layout.pageState.view.key or nil
end

-- Compact layout ------------------------------------------------------------------------

-- With nothing to say, the rows start just under the field, with no heading, and the sort
-- button sits at the field's right
local width = controls.width
assert(controls.status.hidden and controls.list.root.y == 40, tostring(controls.list.root.y))
assert(controls.field.options.width == width - 32 and controls.sort.root.x == 8 + width - 26)
-- The sort button is PrettyUI's real toggleable sprite button, off until clicked
local swap = prettyui.Sprites.SPRITE_BUTTONS.SWAP
assert(controls.sort.spriteName == "SWAP" and controls.sort.root.y == 8)
assert(controls.sort.disabled and controls.sort.root.spriteID == swap.disabled)
assert(Harness.Find(parent, "Saved searches") == nil)
local idleHeight = controls.list.root.height
assert(idleHeight == controls.height - 44 - 40 - 4, tostring(idleHeight))
-- A status line pushes the rows down and shortens them by as much; the field is kept
local field = controls.field
type("iron")
assert(controls.status.content == "2 matches." and not controls.status.hidden)
assert(controls.list.root.y == 60 and controls.list.root.height == idleHeight - 20, tostring(controls.list.root.y))
assert(controls.field == field and not field.root.destroyed and app.tab.controls == controls)
-- A long status takes two lines; clearing it gives the room back
app:ShowStatus(string.rep("x", 80), true)
app:Refresh()
assert(controls.list.root.y == 76 and controls.status.height == 32)
type("")
app:ShowStatus(nil)
app:Refresh()
assert(controls.status.hidden and controls.list.root.y == 40 and controls.list.root.height == idleHeight)
assert(controls.field == field)

-- Folders -------------------------------------------------------------------------------

for _, query in ipairs({ { "Bars", "bar" }, { "Ores", "ore" }, { "Fish", "lobster" } }) do
    assert(app:SaveQuery(nil, query[1], query[2]))
end
assert(app:CreateFolder("Smithing", "1") and app:MoveQueryToFolder("2", "1"))
assert(app.queries:CreateFolder("Empty"))
app:Refresh()
assert(rows() == "Smithing (2) | >Bars | >Ores | Fish* | Empty (0)", rows())
-- Folder rows have a chevron and room for it; members are indented
local smithing = rowNamed("Smithing (2)")
local chevron
for _, child in ipairs(smithing.root.children) do
    if child.spriteID == id.Sprite.BANK_ARROW_UP_0 then chevron = child end
end
assert(chevron ~= nil and chevron.x == -22 and chevron.clickthrough)
assert(smithing.label.x == 8 and smithing.label.width == -8 - 6 - 22)
assert(rowNamed("Bars").label.x == 26 and rowNamed("Fish").label.x == 8)

-- Choosing a query shows its page; a folder click opens or closes the folder only
assert(controls.list:Click("1"))
h:Tick(2)
assert(key() == "query:1" and app.selectedQuery == "1")
assert(controls.list:Click("folder:1"))
h:Tick(2)
assert(key() == "query:1" and app.selectedQuery == "1" and app.queries:GetFolder("1").collapsed)
-- The closed folder carries the chosen query's outline
assert(rows() == "Smithing (2)* | Fish | Empty (0)", rows())
local outlined = 0
for _, child in ipairs(rowNamed("Smithing (2)").root.children) do
    if child.rgba == 0xD2A84DFF then outlined = outlined + 1 end
end
assert(outlined == 4)
-- A fresh read of the saved data finds the folder closed
assert(getmetatable(app.queries).new():GetFolder("1").collapsed)
assert(controls.list:Click("folder:1"))
h:Tick(2)
assert(rows() == "Smithing (2) | >Bars (1)* | >Ores | Fish | Empty (0)", rows())

-- A refused save changes nothing and says why in the tab
local database = h.search.env.PersistentDB
h.search.env.PersistentDB = { GetString = database.GetString, SetString = function() return false end }
assert(controls.list:Click("folder:1"))
h:Tick(2)
assert(not app.queries:GetFolder("1").collapsed and app.statusIsError)
assert(string.find(app.status, "^PersistentDB could not ") and not controls.status.hidden, app.status)
assert(not app:MoveEntry("query", "3", -1) and rows() == "Smithing (2) | >Bars (1)* | >Ores | Fish | Empty (0)")
h.search.env.PersistentDB = database
app:ShowStatus(nil)
app:Refresh()

-- Sorting -------------------------------------------------------------------------------

-- Collapse Smithing first: sorting still shows its queries so they can move
assert(app:ToggleFolder("1"))
controls.sort.root.hooks.click()
assert(tab.sortMode and not controls.sort.disabled and controls.sort.root.spriteID == swap.neutral)
assert(rows() == "Smithing (2) | >Bars (1)* | >Ores | Fish | Empty (0)", rows())
-- Each row has an up and a down arrow at its right, past the label, disabled at its ends
local function arrows(label)
    local found = {}
    for _, arrow in ipairs(tab.arrows) do
        if arrow.root.parent == rowNamed(label).root then found[arrow.spriteName] = arrow end
    end
    return found.ARROW_UP, found.ARROW_DOWN
end
local up, down = arrows("Smithing (2)")
assert(up.root.x == -50 and down.root.x == -28 and up.root.y == 5)
assert(up.disabled and not down.disabled)
assert(rowNamed("Fish").label.width == -8 - 50)
local barsUp, barsDown = arrows("Bars (1)")
assert(barsUp.disabled and not barsDown.disabled)
-- Clicking a row while sorting opens nothing
assert(controls.list:Click("3"))
h:Tick(2)
assert(key() == "query:1" and app.selectedQuery == "1")
assert(controls.list:Click("folder:1"))
h:Tick(2)
assert(app.queries:GetFolder("1").collapsed)
-- Arrows move one step: queries within their folder, folders and loose queries at the top
select(2, arrows("Bars (1)")).root.hooks.click()
assert(rows() == "Smithing (2) | >Ores | >Bars (1)* | Fish | Empty (0)", rows())
select(2, arrows("Smithing (2)")).root.hooks.click()
assert(rows() == "Fish | Smithing (2) | >Ores | >Bars (1)* | Empty (0)", rows())
assert(key() == "query:1")
-- Finishing shows Smithing closed again; the order is saved
controls.sort.root.hooks.click()
assert(not tab.sortMode and controls.sort.disabled and #tab.arrows == 0)
assert(rows() == "Fish | Smithing (2)* | Empty (0)", rows())

-- Row menus -----------------------------------------------------------------------------

-- Open a menu over a row, as a right-click there does
local function menuOver(label, coreFirst)
    local row = rowNamed(label)
    local index
    for rowIndex, value in ipairs(controls.list.rows) do
        if value == row then index = rowIndex end
    end
    h:PointAt(parent, 20, controls.list.root.y + (index - 1) * 30 + 10)
    return h:ContentMenu(coreFirst)
end
-- A folder offers Expand, Rename folder, and Ungroup folder, low, and Bank Core makes Cancel
-- the left click over mounted content, whichever plugin answers first
local menu = menuOver("Smithing (2)")
assert(Harness.Labels(menu) == "Expand Smithing | Rename folder Smithing | Ungroup folder Smithing | Walk here | Cancel",
    Harness.Labels(menu))
menu = menuOver("Smithing (2)", true)
assert(Harness.Labels(menu) == "Expand Smithing | Rename folder Smithing | Ungroup folder Smithing | Walk here | Cancel",
    Harness.Labels(menu))
-- A chosen entry runs on the next tick
Harness.Choose(menu, "Expand")
assert(app.queries:GetFolder("1").collapsed)
h:Tick()
assert(not app.queries:GetFolder("1").collapsed and rows() == "Fish | Smithing (2) | >Ores | >Bars (1)* | Empty (0)",
    rows())
-- Nothing is offered outside the rows
h:PointAt(parent, 20, controls.list.root.y + controls.list.root.height + 2)
assert(Harness.Labels(h:ContentMenu()) == "Walk here | Cancel")

-- Rename folder opens the dialog; a taken name is refused there, and a new name saved
Harness.Choose(menuOver("Smithing (2)"), "Rename folder")
h:Tick()
local dialog = app.folderDialog
assert(dialog ~= nil and dialog.field:GetText() == "Smithing" and dialog.list == nil)
dialog.field:SetText("empty")
dialog.saveButton.action()
assert(app.folderDialog == dialog and dialog.status.content == "A folder with that name already exists.")
assert(app.status == nil)
dialog.field:SetText("Metal")
dialog.saveButton.action()
assert(app.folderDialog == nil and rows() == "Fish | Metal (2) | >Ores | >Bars (1)* | Empty (0)", rows())

-- A query offers Edit and Move to folder, and Remove from folder when it is in one
menu = menuOver("Fish")
assert(Harness.Labels(menu) == "Edit Fish | Move to folder... Fish | Walk here | Cancel", Harness.Labels(menu))
Harness.Choose(menu, "Edit")
h:Tick()
assert(app.editor ~= nil and app.editor.queryID == "3" and app.selectedQuery == "1")
app:CloseEditor()
-- Move to folder lists every folder, and creates one from its field
Harness.Choose(menuOver("Fish"), "Move to folder")
h:Tick()
dialog = app.folderDialog
local choices = {}
for index, row in ipairs(dialog.list.rows) do choices[index] = row.entry.label end
assert(table.concat(choices, ",") == "Metal,Empty", table.concat(choices, ","))
dialog.field:SetText("Sea")
dialog.saveButton.action()
assert(app.folderDialog == nil and rows() == "Sea (1) | >Fish | Metal (2) | >Ores | >Bars (1)* | Empty (0)", rows())
-- A query in a folder can go to another folder or none
menu = menuOver("Ores")
assert(Harness.Labels(menu) == "Edit Ores | Move to folder... Ores | Remove from folder Metal | Walk here | Cancel",
    Harness.Labels(menu))
Harness.Choose(menu, "Move to folder")
h:Tick()
choices = {}
for index, row in ipairs(app.folderDialog.list.rows) do choices[index] = row.entry.label end
assert(table.concat(choices, ",") == "No folder,Sea,Empty", table.concat(choices, ","))
assert(app.folderDialog.list:Click("2"))
assert(app.folderDialog == nil and rows() == "Sea (1) | >Fish | Metal (1) | >Bars (1)* | Empty (1) | >Ores", rows())
Harness.Choose(menuOver("Ores"), "Remove from folder")
h:Tick()
assert(rows() == "Sea (1) | >Fish | Metal (1) | >Bars (1)* | Empty (0) | Ores", rows())
-- Ungrouping keeps the folder's queries where it was
Harness.Choose(menuOver("Sea (1)"), "Ungroup folder")
h:Tick()
assert(rows() == "Fish | Metal (1) | >Bars (1)* | Empty (0) | Ores", rows())
assert(key() == "query:1" and app.selectedQuery == "1")

-- An entry is dropped when its row is gone, or its column unmounted, before it runs
Harness.Choose(menuOver("Empty (0)"), "Ungroup folder")
assert(app:UngroupFolder("2"))
h:Tick()
assert(app.folderDialog == nil and rows() == "Fish | Metal (1) | >Bars (1)* | Ores", rows())
Harness.Choose(menuOver("Metal (1)"), "Rename folder")
local ctx = tab.ctx
tab.callbacks.unmount()
h:Tick()
assert(app.folderDialog == nil)
tab.callbacks.mount(ctx)
controls = tab.controls
-- Deleting a query takes it out of its folder; the empty folder stays
assert(controls.list:Click("1"))
h:Tick(2)
app:DeleteQuery()
app:DeleteQuery()
assert(rows() == "Fish | Metal (0) | Ores", rows())

-- Reloading reads the same folders and order back
h.host:Reload("advancedbanksearch", { freshEnvironment = true })
h:Tick(2)
app = h:App()
tab, controls = app.tab, app.tab.controls
assert(rows() == "Fish | Metal (0) | Ores", rows())

-- Unloading leaves no menu subscription or pending action behind
Harness.Choose(menuOver("Metal (0)"), "Ungroup folder")
h.host:Unload("advancedbanksearch")
assert(h.menuSubscriptions.advancedbanksearch_menu == nil)
assert(h.bankHost:Listener("advancedbanksearch_menu_action") == nil)
for _, subscription in ipairs(h.host:SubscriptionsOf("advancedbanksearch")) do
    error("Advanced Bank Search left " .. subscription .. " subscribed")
end
h.host:Unload("bankcore")
print("query_folders_test: ok")
