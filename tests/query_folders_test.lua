package.path = "./?.lua;./?/init.lua;" .. package.path

-- Drive the Search tab's folders, sorting, layout, and row menus
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
local function enter(text)
    controls.field.root.content = text
    controls.field.root.hooks[ui.Hook.ONCONTENTCHANGED](controls.field.root, "change", text)
end

-- Type, then wait out the 10 quiet ticks before searching
local function type(text)
    enter(text)
    h:Tick(12)
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

-- With no status, rows sit under the field and sort sits at its right
local width = controls.width
assert(controls.status.hidden and controls.list.root.y == 40, tostring(controls.list.root.y))
local fieldOptions = controls.field.options
assert(fieldOptions.x == 8 and fieldOptions.y == 8 and fieldOptions.width == width - 32 and fieldOptions.height == 26)
assert(fieldOptions.placeholder == "Search items with RuneQL..." and fieldOptions.maxLength == 9999)
assert(Harness.Find(parent, "Saved searches") == nil)

-- The sort button is a native host button with a centred swap icon
-- The icon lets clicks through and lights on hover or while sorting
local swap = prettyui.Sprites.SPRITE_BUTTONS.SWAP
local sort = controls.sort
local button, icon = sort.root, sort.icon
assert(button.parent == parent and icon.parent == parent)
assert(button.x == 8 + width - 26 and button.y == 8 and button.width == 26 and button.height == 26)
assert(button.stylesheetID == 318 and button.text.content == "")
assert(button.enabled == nil and button.clickthrough == false and button.hidden == nil)
assert(button.hooks[ui.Hook.ONBUTTONPRESSED] ~= nil and button.hooks[ui.Hook.ONCLICK] == nil)
assert(icon.x == button.x + 4 and icon.y == 12 and icon.width == 18 and icon.height == 18)
assert(icon.clickthrough == true and icon.spriteID == swap.neutral)
-- Hover lights the icon and shows the tooltip in Core's overlay
local overlay = tab.ctx.overlay
local tooltip = sort.tooltip
assert(tooltip.root.parent == overlay and tooltip.root.hidden == true)
assert(tooltip.label.content == "Sort saved searches and folders")
assert(Harness.Fire(button, ui.Hook.ONMOUSEOVER) == 2)
assert(icon.spriteID == swap.active and tooltip.root.hidden == false)
assert(prettyui.Tooltip.getContext(parent).parent == overlay and prettyui.Tooltip.getContext(parent).tooltips[1] == tooltip)
Harness.Fire(button, ui.Hook.ONMOUSELEAVE)
assert(icon.spriteID == swap.neutral and tooltip.root.hidden == true)
local idleHeight = controls.list.root.height
assert(idleHeight == controls.height - 44 - 40 - 4, tostring(idleHeight))
-- A status line pushes the rows down; the field is kept
local field = controls.field
type("iron")
assert(controls.status.content == "2 matches." and not controls.status.hidden)
assert(controls.list.root.y == 60 and controls.list.root.height == idleHeight - 20, tostring(controls.list.root.y))
assert(controls.field == field and not field.root.destroyed and app.tab.controls == controls)
-- A long status takes two lines until cleared
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
-- Folder rows have a chevron; members are indented
local smithing = rowNamed("Smithing (2)")
local chevron
for _, child in ipairs(smithing.root.children) do
    if child.spriteID == id.Sprite.BANK_ARROW_UP_0 then chevron = child end
end
assert(chevron ~= nil and chevron.x == -22 and chevron.clickthrough)
assert(smithing.label.x == 8 and smithing.label.width == -8 - 6 - 22)
assert(rowNamed("Bars").label.x == 26 and rowNamed("Fish").label.x == 8)

-- Choosing a query shows its page; folder clicks only toggle
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

-- Press the sort button as the host reports it
local function pressSort()
    controls.sort.root.hooks[ui.Hook.ONBUTTONPRESSED]()
    h:Tick(2)
end
-- Each row has up and down arrows, disabled at its ends
local function arrows(label)
    local found = {}
    for _, arrow in ipairs(tab.arrows) do
        if arrow.root.parent == rowNamed(label).root then found[arrow.spriteName] = arrow end
    end
    return found.ARROW_UP, found.ARROW_DOWN
end
-- Find a folder row's chevron
local function chevronOf(label)
    for _, child in ipairs(rowNamed(label).root.children) do
        if child.spriteID == id.Sprite.BANK_ARROW_UP_0 and not child.destroyed then return child end
    end
end

-- Sorting keeps the icon lit and the tooltip says how to finish
-- A closed folder stays closed
assert(app:ToggleFolder("1"))
pressSort()
assert(tab.sortMode and controls.sort == sort and button.stylesheetID == 318 and button.clickthrough == false)
assert(icon.spriteID == swap.active and tooltip.label.content == "Finish sorting saved searches and folders")
Harness.Fire(button, ui.Hook.ONMOUSELEAVE)
assert(icon.spriteID == swap.active)
assert(rows() == "Smithing (2)* | Fish | Empty (0)", rows())
local up, down = arrows("Smithing (2)")
assert(up.root.x == -50 and down.root.x == -28 and up.root.y == 5 and up.root.width == 20)
assert(up.disabled and not down.disabled and up.root.clickthrough and not down.root.clickthrough)
assert(#tab.arrows == 6)
-- The chevron moves left of the arrows and the name stops before it
assert(chevronOf("Smithing (2)").x == -22 - 50 and rowNamed("Smithing (2)").label.width == -8 - 50 - 22)
assert(rowNamed("Fish").label.width == -8 - 50)
-- Folders still toggle while sorting; the chosen query and page stay
assert(controls.list:Click("folder:1"))
h:Tick(2)
assert(not app.queries:GetFolder("1").collapsed and key() == "query:1" and app.selectedQuery == "1")
assert(rows() == "Smithing (2) | >Bars (1)* | >Ores | Fish | Empty (0)", rows())
local barsUp, barsDown = arrows("Bars (1)")
assert(barsUp.disabled and not barsDown.disabled)
-- Clicking a query while sorting chooses nothing
assert(controls.list:Click("3"))
h:Tick(2)
assert(key() == "query:1" and app.selectedQuery == "1")
assert(rows() == "Smithing (2) | >Bars (1)* | >Ores | Fish | Empty (0)", rows())
-- Arrows move rows one step among their siblings
select(2, arrows("Bars (1)")).root.hooks.click()
assert(rows() == "Smithing (2) | >Ores | >Bars (1)* | Fish | Empty (0)", rows())
select(2, arrows("Smithing (2)")).root.hooks.click()
assert(rows() == "Fish | Smithing (2) | >Ores | >Bars (1)* | Empty (0)", rows())
assert(key() == "query:1" and app.selectedQuery == "1")
-- Finishing removes the arrows and restores the chevron and icon
pressSort()
assert(not tab.sortMode and #tab.arrows == 0 and icon.spriteID == swap.neutral)
assert(tooltip.label.content == "Sort saved searches and folders" and chevronOf("Smithing (2)").x == -22)
assert(rows() == "Fish | Smithing (2) | >Ores | >Bars (1)* | Empty (0)", rows())

-- Typing a search ends sorting at once without rebuilding the field
field = controls.field
pressSort()
assert(tab.sortMode and #tab.arrows > 0)
enter("iron")
assert(not tab.sortMode and #tab.arrows == 0 and app.searchWait ~= nil and app.text ~= "iron")
h:Tick(12)
assert(not tab.sortMode and #tab.arrows == 0 and icon.spriteID == swap.neutral)
assert(controls.field == field and not field.root.destroyed and field:GetText() == "iron" and app.text == "iron")
assert(app.shownPage == "search" and string.find(key(), "^search:"), tostring(key()))
type("iron b")
assert(controls.field == field and app.text == "iron b" and not tab.sortMode)
-- Sorting keeps the search; clearing the field keeps sorting
pressSort()
assert(tab.sortMode and field:GetText() == "iron b" and app.text == "iron b" and app.shownPage == "search")
type("")
assert(tab.sortMode and app.shownPage == nil and controls.field == field)
-- A resize while sorting rebuilds the column with one tooltip layer
tab.callbacks.resize()
assert(tab.sortMode and button.destroyed and icon.destroyed and tooltip.root == nil)
controls = tab.controls
assert(controls.sort ~= sort and controls.sort.icon.spriteID == swap.active and #tab.arrows > 0)
assert(#prettyui.Tooltip.getContext(parent).tooltips == 1)
assert(prettyui.Tooltip.getContext(parent).tooltips[1] == controls.sort.tooltip)
-- Unmounting ends sorting; remounting shows the saved order
sort, tooltip = controls.sort, controls.sort.tooltip
local tooltipRoot = tooltip.root
local mounted = tab.ctx
tab.callbacks.unmount()
assert(not tab.sortMode and sort.root == nil and tooltipRoot.destroyed and prettyui.Tooltip.getContext(parent) == nil)
tab.callbacks.mount(mounted)
controls = tab.controls
assert(not tab.sortMode and controls.sort.icon.spriteID == swap.neutral and #tab.arrows == 0)
assert(rows() == "Fish | Smithing (2) | >Ores | >Bars (1)* | Empty (0)", rows())
assert(getmetatable(app.queries).new():Tree()[1].query.name == "Fish")
-- Unmounting drops a waiting search; remounting keeps the typed text
enter("iron ore")
tab.callbacks.unmount()
assert(app.searchWait == nil and h.bankHost:Listener("advancedbanksearch_search_wait") == nil)
tab.callbacks.mount(mounted)
controls = tab.controls
h:Tick(20)
assert(controls.field:GetText() == "iron ore" and app.shownPage == nil and app.text == "")
-- Show Bars and close Smithing before the menu checks
assert(controls.list:Click("1"))
assert(controls.list:Click("folder:1"))
h:Tick(2)
assert(key() == "query:1" and rows() == "Fish | Smithing (2)* | Empty (0)", rows())
app:ShowStatus(nil)
app:Refresh()

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
-- A folder offers Expand, Rename folder, and Ungroup folder, low
-- Cancel is the left click whichever plugin answers first
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

-- Rename folder refuses a taken name and saves a new one
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

-- A query offers Edit, Move to folder, and Remove from folder
menu = menuOver("Fish")
assert(Harness.Labels(menu) == "Edit Fish | Move to folder... Fish | Walk here | Cancel", Harness.Labels(menu))
Harness.Choose(menu, "Edit")
h:Tick()
assert(app.editor ~= nil and app.editor.queryID == "3" and app.selectedQuery == "1")
app:CloseEditor()
-- Move to folder lists every folder and can create one
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

-- An entry is dropped if its row or column is gone first
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
-- Deleting a query keeps its now empty folder
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

-- Unloading leaves no menu subscription or pending action
Harness.Choose(menuOver("Metal (0)"), "Ungroup folder")
h.host:Unload("advancedbanksearch")
assert(h.menuSubscriptions.advancedbanksearch_menu == nil)
assert(h.bankHost:Listener("advancedbanksearch_menu_action") == nil)
for _, subscription in ipairs(h.host:SubscriptionsOf("advancedbanksearch")) do
    error("Advanced Bank Search left " .. subscription .. " subscribed")
end
h.host:Unload("bankcore")
print("query_folders_test: ok")
