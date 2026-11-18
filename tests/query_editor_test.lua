package.path = "./?.lua;./?/init.lua;" .. package.path

-- Build, save, and reopen queries in the editor's Visual and Advanced modes
-- FAKE HOST: stand-in loader, components, and widgets, not the game client
-- Combo boxes are PrettyUI's own, over a native field that sorts its labels

local Harness = require("tests/support/search_harness")

-- The editor calls only methods PrettyUI 1.2.1 defines
local prettyRoot = Harness.PrettyUIRoot()
-- Read a PrettyUI source file
local function source(name)
    local file = assert(io.open(prettyRoot .. "/src/" .. name .. ".lua", "rb"))
    local text = file:read("a")
    file:close()
    return text
end
for name, methods in pairs({
    combo_box = { "ComboBox:SetEntries(entries, selectedID)", "ComboBox:Select(entryID, triggerEvents)" },
    simple_button = { "SimpleButton:SetActive(active)", "SimpleButton:SetDisabled(disabled)", "SimpleButton:SetTooltip(value)" },
    text_field = { "TextField:GetText()", "TextField:SetText(value, triggerCallback)", "TextField:SetPlaceholder(value)" },
}) do
    for _, method in ipairs(methods) do
        assert(string.find(source(name), "function " .. method, 1, true), name .. " lacks " .. method)
    end
end
local editorFile = assert(io.open("resources/search/query_editor.lua", "rb"))
local editorSource = editorFile:read("a")
editorFile:close()
assert(not string.find(editorSource, "SetSelected", 1, true))

local h = Harness.new("query_editor")
prettyui.SimpleButton = Harness.LoadSimpleButton(prettyRoot)
h:NameObjects({ { 101, "Iron bar" }, { 102, "Iron ore" }, { 103, "Rune bar" }, { 104, "Lobster" } })
h.bankHost:SetItems({ { 101, 5 }, { 102, 40 }, { 103, 2 }, { 104, 12 } })
h:LoadCore()
h:LoadRuneQL()
h:LoadSearch()
local app = h:App()
h:OpenBank()
h:Tick(2)
local controls = app.tab.controls
assert(controls ~= nil, "the Search tab did not mount: " .. tostring(h:LoggedFailure()))

-- Count live components including overlays beside the editor
local function liveNodes(node)
    if node.destroyed then return 0 end
    local count = 1
    for _, child in ipairs(node.children or {}) do count = count + liveNodes(child) end
    return count
end

-- Constructor callbacks and failures must not leave an orphan window
local baselineNodes = liveNodes(h.bankHost.window.host)
local comboFactory, fieldFactory = prettyui.ComboBox.new, prettyui.TextField.new
local staleCallbacks, fieldCount = {}, 0
prettyui.ComboBox.new = function(parent, options)
    local box = comboFactory(parent, options)
    if options.onChange then options.onChange(box, options.selectedID) end
    return box
end
prettyui.TextField.new = function(parent, options)
    local field = fieldFactory(parent, options)
    if options.onChange then
        staleCallbacks[#staleCallbacks + 1] = function() options.onChange(field, "change", "constructor echo") end
        staleCallbacks[#staleCallbacks]()
    end
    fieldCount = fieldCount + 1
    if fieldCount == 4 then error("injected native construction failure") end
    return field
end
local opened, failure = app:NewQuery()
assert(not opened and failure == "failed", tostring(failure))
assert(app.editor == nil and app.editorExt == nil)
for _, callback in ipairs(staleCallbacks) do callback() end
assert(liveNodes(h.bankHost.window.host) == baselineNodes, "failed editor leaked components")
prettyui.ComboBox.new, prettyui.TextField.new = comboFactory, fieldFactory

-- Press a PrettyUI button
local function press(button)
    assert(not button.disabled, "pressed a disabled button")
    local action = button.root.hooks[ui.Hook.ONBUTTONPRESSED] or button.root.hooks[ui.Hook.ONCLICK]; action()
    h:Tick(1)
end

-- Type into a text field as the host reports it
local function enter(field, text)
    field.root.content = text
    field.root.hooks[ui.Hook.ONCONTENTCHANGED](field.root, "change", text)
end

-- Choose a combo box entry by its label as a player does
-- Opening lists the entries, and clicking one reports that row's ID
local function choose(box, label)
    assert(box.dropdown == nil, "editor dropdown should use the native control")
    box.root:Click(label)
    assert(box:GetSelectedLabel() == label)
end

-- List the labels native clients sort
local function labels(box)
    return table.concat(box.root.labels, ",")
end

-- Return the label a combo box shows
local function shown(box)
    return box:GetSelectedLabel()
end

-- Return the open editor's condition row
local function row(index)
    return app.editor.slots[index]
end

-- Report whether a control or label is shown
local function visible(control)
    return (control.root or control).hidden ~= true
end

-- List which rows show conditions
local function shownRows()
    local count = 0
    for _, slot in ipairs(app.editor.slots) do
        if visible(slot.fieldBox) then count = count + 1 end
    end
    return count
end

-- Repeated close and reopen must release controls and overlays
for _ = 1, 20 do
    app:NewQuery()
    local closing = app.editor
    choose(closing.slots[1].fieldBox, "Category")
    enter(closing.slots[1].valueField, "bird")
    assert(liveNodes(h.bankHost.window.host) < 4096, "editor exceeds the component budget")
    local staleEdit = closing.slots[1].valueField.options.onChange
    closing:Close()
    assert(app.editor == nil and closing.destroyed)
    staleEdit(nil, "change", "after close")
    assert(liveNodes(h.bankHost.window.host) == baselineNodes, "closed editor leaked components")
end

-- List the object IDs a saved query matches
local function matched(queryID)
    local outcome = app:Run(app.queries:Get(queryID).query, true)
    assert(outcome.state == "ok", outcome.state)
    local listed = {}
    for index, match in ipairs(outcome.matches) do listed[index] = match.objectID end
    table.sort(listed)
    return table.concat(listed, ",")
end

-- A new query starts in Visual ------------------------------------------------------

press(controls.new)
local editor = app.editor
assert(editor.mode == "visual" and editor.visualButton == nil and editor.advancedButton == nil)
assert(shownRows() == 1 and row(1).removeButton.disabled and not editor.addButton.disabled)
assert(not visible(editor.queryField) and not visible(editor.characterCount) and visible(editor.preview))
assert(editor.cancelButton.root.parent == editor.footer.root and editor.saveButton.root.parent == editor.footer.root)
assert(editor.footer.root.parent == editor.root and editor.footer.root.y == -editor.footer.root.height)
assert(editor.body.root.parent == editor.root and editor.content ~= editor.root)
local footerY, cancelY, saveY = editor.footer.root.y, editor.cancelButton.root.y, editor.saveButton.root.y
assert(shown(row(1).fieldBox) == "Item name" and shown(row(1).operatorBox) == "has phrase")
-- Native labels and IDs share alphabetical order and show the draft's choice
local expectedFields = { "Item name", "Quantity", "GE price", "Category", "Skills", "Types",
    "Combat style", "Slot", "Tier", "Tradeable", "Augmented", "Dose" }
table.sort(expectedFields)
assert(labels(row(1).fieldBox) == table.concat(expectedFields, ","))
assert(#editor.fields == 12)
assert(shown(row(1).fieldBox) == "Item name" and shown(row(1).operatorBox) == "has phrase")
assert(labels(row(1).operatorBox) == "has all words,has phrase")
assert(labels(editor.matchBox) == "all conditions (AND),any condition (OR)")
-- PrettyUI's native box, used without an order, shows and reports sorted positions
local nativeID
local native = prettyui.ComboBox.new(editor.content, {
    entries = { { id = 1, label = "Item name" }, { id = 2, label = "Quantity" }, { id = 3, label = "GE price" } },
    selectedID = 1,
    onChange = function(_, entryID) nativeID = entryID end,
})
assert(native.root.selectedLabel == "GE price")
native.root:Click("Quantity")
assert(nativeID == 3)
native:Destroy()
-- Switching between name and number fields takes effect at once, every time
for _ = 1, 2 do
    enter(row(1).valueField, "iron")
    choose(row(1).fieldBox, "GE price")
    local rule = editor.draft.rules[1]
    assert(rule.field == "price" and rule.operator == "equals" and rule.value == "")
    assert(shown(row(1).fieldBox) == "GE price" and shown(row(1).operatorBox) == "is")
    assert(labels(row(1).operatorBox) == "is,is at least,is at most,is between")
    assert(row(1).valueField:GetText() == "" and row(1).valueField.placeholder == "Number")
    assert(editor.preview.content == "")
    choose(row(1).operatorBox, "is at least")
    enter(row(1).valueField, "5k")
    assert(editor.preview.content == "price:[5000 TO *]", editor.preview.content)
    -- Another number field keeps the comparison and number
    choose(row(1).fieldBox, "Quantity")
    assert(editor.draft.rules[1].operator == "atleast" and shown(row(1).operatorBox) == "is at least")
    assert(row(1).valueField:GetText() == "5k" and editor.preview.content == "qty:[5000 TO *]")
    choose(row(1).operatorBox, "is between")
    assert(visible(row(1).minField) and not visible(row(1).valueField))
    choose(row(1).fieldBox, "Item name")
    rule = editor.draft.rules[1]
    assert(rule.field == "name" and rule.operator == "phrase" and rule.value == "")
    assert(shown(row(1).fieldBox) == "Item name" and shown(row(1).operatorBox) == "has phrase")
    assert(labels(row(1).operatorBox) == "has all words,has phrase")
    assert(visible(row(1).valueField) and not visible(row(1).minField) and not visible(row(1).andText))
end
assert(#row(1).operatorBox.root.labels == 2 and visible(row(1).valueField) and not visible(row(1).minField))
assert(editor.preview.content == "", editor.preview.content)
-- An incomplete condition is refused with its reason and nothing saves
enter(editor.nameField, "Iron stock")
press(editor.saveButton)
assert(app.editor == editor and editor.status.content == "Condition 1: enter words from the item name.")
assert(#app.queries:All() == 0)

-- Typing a name updates the preview and clears the message
enter(row(1).valueField, 'iron "bar"')
assert(editor.preview.content == 'name:"iron \\"bar\\""' and editor.status.hidden, editor.preview.content)
choose(row(1).operatorBox, "has all words")
assert(editor.preview.content == '(name:"iron" AND name:"\\"bar\\"")', editor.preview.content)
enter(row(1).valueField, "iron")

-- Adding a condition shows a row; a quantity offers number comparisons
press(editor.addButton)
assert(shownRows() == 2 and not row(1).removeButton.disabled and shown(row(2).fieldBox) == "Item name")
choose(row(2).fieldBox, "Quantity")
assert(editor.draft.rules[2].field == "qty" and #row(2).operatorBox.root.labels == 4)
assert(shown(row(2).operatorBox) == "is" and row(2).valueField.placeholder == "Number")
enter(row(2).valueField, "lots")
assert(editor.preview.content == "", editor.preview.content)
-- Between shows two bounds and checks their order
choose(row(2).operatorBox, "is between")
assert(not visible(row(2).valueField) and visible(row(2).minField) and visible(row(2).maxField))
assert(visible(row(2).andText))
enter(row(2).minField, "10")
enter(row(2).maxField, "5")
assert(editor.preview.content == "")
enter(row(2).maxField, "1k")
assert(editor.preview.content == 'name:"iron" AND qty:[10 TO 1000]', editor.preview.content)
-- Matching any joins with OR
choose(editor.matchBox, "any condition (OR)")
assert(editor.preview.content == 'name:"iron" OR qty:[10 TO 1000]', editor.preview.content)
choose(editor.matchBox, "all conditions (AND)")

-- At most six conditions; removing one moves the rest up
for _ = 3, 6 do press(editor.addButton) end
assert(shownRows() == 6 and editor.addButton.disabled)
choose(row(3).fieldBox, "GE price")
choose(row(3).operatorBox, "is at most")
enter(row(3).valueField, "1.5m")
press(row(2).removeButton)
assert(shownRows() == 5 and not editor.addButton.disabled)
assert(shown(row(2).fieldBox) == "GE price" and shown(row(2).operatorBox) == "is at most")
assert(row(2).valueField:GetText() == "1.5m" and not visible(row(2).minField))
assert(shown(row(2).fieldBox) == "GE price" and shown(row(2).operatorBox) == "is at most")
assert(shown(row(3).fieldBox) == "Item name" and shown(row(3).operatorBox) == "has phrase")
-- A field of the same kind keeps its comparison and number
choose(row(2).fieldBox, "Quantity")
assert(editor.draft.rules[2].operator == "atmost" and editor.draft.rules[2].value == "1.5m")
assert(shown(row(2).fieldBox) == "Quantity" and shown(row(2).operatorBox) == "is at most")
for _ = 1, 3 do press(row(3).removeButton) end
assert(shownRows() == 2 and not visible(row(3).fieldBox) and not visible(row(3).removeButton))
-- Choosing a name field again starts that condition over
choose(row(2).fieldBox, "Item name")
assert(editor.draft.rules[2].operator == "phrase" and editor.draft.rules[2].value == "")
assert(#row(2).operatorBox.root.labels == 2 and row(2).valueField:GetText() == "")
choose(row(2).fieldBox, "Quantity")
choose(row(2).operatorBox, "is at least")
enter(row(2).valueField, "10")
assert(editor.preview.content == 'name:"iron" AND qty:[10 TO *]', editor.preview.content)

-- Saving runs the same save as typed RuneQL, with the conditions kept
press(editor.saveButton)
assert(app.editor == nil and app.selectedQuery == "1")
local record = app.queries:Get("1")
assert(record.name == "Iron stock" and record.query == 'name:"iron" AND qty:[10 TO *]' and record.builder ~= nil)
assert(matched("1") == "102", matched("1"))
assert(string.find(h.databases.advancedbanksearch["advancedbanksearch:queries:v1:a:1"]
    or h.databases.advancedbanksearch["advancedbanksearch:queries:v1:b:1"], '"builder":', 1, true))

-- Reopening a visual query -----------------------------------------------------------

press(controls.edit)
editor = app.editor
assert(editor.queryID == "1" and editor.mode == "visual" and shownRows() == 2)
assert(row(1).valueField:GetText() == "iron" and shown(row(2).fieldBox) == "Quantity")
assert(shown(row(2).operatorBox) == "is at least" and row(2).valueField:GetText() == "10")
assert(shown(row(2).fieldBox) == "Quantity" and shown(row(2).operatorBox) == "is at least")
assert(labels(row(2).operatorBox) == "is,is at least,is at most,is between")
assert(editor.preview.content == record.query)
-- Advanced shows the text the conditions give, and Visual comes back without asking
assert(app.settings:Set("editorMode", "advanced"))
assert(editor.mode == "advanced" and editor.queryField:GetText() == record.query and visible(editor.queryField))
assert(not visible(editor.preview) and not visible(row(1).fieldBox))
assert(editor.characterCount.content == #record.query .. " / 9999")
assert(app.settings:Set("editorMode", "visual"))
assert(editor.mode == "visual" and editor.status.hidden and shownRows() == 2)
assert(shown(row(1).fieldBox) == "Item name" and shown(row(2).operatorBox) == "is at least")
-- Saving unchanged text from Advanced keeps the conditions
assert(app.settings:Set("editorMode", "advanced"))
press(editor.saveButton)
assert(app.queries:Get("1").builder ~= nil)

-- Typed text drops the conditions -------------------------------------------------

press(controls.edit)
editor = app.editor
assert(app.settings:Set("editorMode", "advanced"))
enter(editor.queryField, "(" .. record.query .. ") OR name:lobster")
-- Settings switch the open builder without losing detached Advanced text.
assert(app.settings:Set("editorMode", "visual"))
assert(editor.mode == "visual" and editor.status.content == "Saving visual conditions will replace the advanced query.")
assert(app.settings:Set("editorMode", "advanced"))
assert(editor.queryField:GetText() == "(" .. record.query .. ") OR name:lobster")
press(editor.saveButton)
record = app.queries:Get("1")
assert(record.query == '(name:"iron" AND qty:[10 TO *]) OR name:lobster' and record.builder == nil)
assert(matched("1") == "102,104", matched("1"))
-- It now opens in Advanced, untouched
press(controls.edit)
editor = app.editor
assert(editor.mode == "advanced" and editor.queryField:GetText() == record.query)
editor:Close()
assert(app.editor == nil)

-- A typed query ----------------------------------------------------------------------

-- RuneQL the conditions cannot hold stays typed text
local typed = "name:(rune AND bar~1) -name:ore"
assert(app:SaveQuery(nil, "Runes", typed))
app:EditQuery("2")
editor = app.editor
assert(editor.queryID == "2" and editor.mode == "advanced" and editor.queryField:GetText() == typed)
-- Visual starts blank for custom RuneQL; switching back keeps that text intact.
assert(app.settings:Set("editorMode", "visual"))
assert(editor.mode == "visual" and not editor.status.hidden)
assert(shownRows() == 1 and editor.draft.rules[1].value == "")
-- Incomplete conditions leave the typed text alone
assert(app.settings:Set("editorMode", "advanced"))
assert(editor.mode == "advanced" and editor.queryField:GetText() == typed)
assert(editor.status.content == "The conditions are incomplete, so the RuneQL text was not changed.")
press(editor.saveButton)
assert(app.queries:Get("2").query == typed and app.queries:Get("2").builder == nil)
-- Saving from Visual replaces the text only when the player chose it
app:EditQuery("2")
editor = app.editor
assert(app.settings:Set("editorMode", "visual"))
enter(row(1).valueField, "rune bar")
press(editor.saveButton)
assert(app.queries:Get("2").query == 'name:"rune bar"' and app.queries:Get("2").builder ~= nil)
assert(matched("2") == "103")

-- Saving refusals stay in the editor --------------------------------------------------

press(controls.new)
editor = app.editor
enter(editor.nameField, "runes")
enter(row(1).valueField, "lobster")
press(editor.saveButton)
assert(app.editor == editor and editor.status.content == "A RuneQL query with that name already exists.")
assert(#app.queries:All() == 2)
-- Changing a condition clears the message
enter(row(1).valueField, "lobster ")
assert(editor.status.hidden)

-- Catalog conditions save and reopen with their controls -------------------------------

editor:Close()
press(controls.new)
editor = app.editor
enter(editor.nameField, "Catalog equipment")
choose(row(1).fieldBox, "Combat style")
enter(row(1).valueField, "hybrid")
assert(#editor.pickerValues == 1)
press(editor.pickerButtons[1])
assert(editor.draft.rules[1].value == "hybrid" and editor.pickerIndex == nil)
-- Clear belongs inside the input; row removal stays outside it
local clearRoot, inputRoot = row(1).clearButton.root, row(1).valueField.root
assert(clearRoot.parent == inputRoot.parent and clearRoot.y == inputRoot.y)
assert(clearRoot.x >= inputRoot.x and clearRoot.x + clearRoot.width <= inputRoot.x + inputRoot.width)
assert(row(1).removeButton.root.parent == editor.content)
-- A delayed native content echo must not reopen the selected value
enter(row(1).valueField, "hybrid")
local valueClick = row(1).valueField.root.hooks[ui.Hook.ONCLICK]
valueClick()
assert(editor.pickerIndex == nil)
for _, button in ipairs(editor.pickerButtons) do assert(not visible(button)) end
-- Clearing still reopens all available options
press(row(1).clearButton)
assert(editor.pickerIndex == 1 and #editor.pickerValues == #app:RuneQL().Catalog.Values("combatStyle"))
choose(row(1).fieldBox, "Category")
assert(row(1).valueField.placeholder == "Choose a value")
assert(editor.pickerIndex == 1 and #editor.pickerValues == #app:RuneQL().Catalog.Categories())
assert(visible(editor.pickerNext) and editor.pickerPrevious.disabled)
local firstPage = editor.pickerButtons[1].content.content
press(editor.pickerNext)
assert(editor.pickerPage == 2 and editor.pickerButtons[1].content.content ~= firstPage)
-- Pickers show labels and persist canonical values
local selectedValue = editor.pickerValues[25].value
press(editor.pickerButtons[1])
assert(editor.draft.rules[1].value == selectedValue and editor.pickerIndex == nil)
assert(row(1).valueField:GetText() == selectedValue and visible(row(1).clearButton))
press(row(1).clearButton)
assert(editor.pickerIndex == 1 and row(1).valueField:GetText() == "")
assert(editor.pickerPage == 1 and not visible(row(1).clearButton))
enter(row(1).valueField, "wood-production")
assert(#editor.pickerValues == 1 and editor.pickerValues[1].label == "Woodcutting, Firemaking & Fletching materials")
local valueRoot = row(1).valueField.root
press(editor.pickerButtons[1])
assert(row(1).valueField.root == valueRoot and row(1).valueField:GetText() == "wood-production")
assert(editor.pickerIndex == nil)
enter(row(1).valueField, "melee-equipment")
press(editor.addButton)
choose(row(2).fieldBox, "Tier")
choose(row(2).operatorBox, "is between")
enter(row(2).minField, "80")
enter(row(2).maxField, "90")
press(editor.addButton)
choose(row(3).fieldBox, "Augmented")
assert(labels(row(3).operatorBox) == "is false,is true")
assert(not visible(row(3).valueField) and not visible(row(3).minField) and not visible(row(3).maxField))
choose(row(3).operatorBox, "is false")
assert(editor.preview.content == 'category:["melee-equipment" TO "melee-equipment"] AND tier:[80 TO 90] AND augmented:false')
press(editor.saveButton)
local catalogQuery = app.queries:All()[3]
app:EditQuery(catalogQuery.id)
editor = app.editor
assert(editor.mode == "visual" and shown(row(1).fieldBox) == "Category")
assert(shown(row(2).operatorBox) == "is between" and row(2).maxField:GetText() == "90")
assert(shown(row(3).operatorBox) == "is false" and not visible(row(3).valueField))
-- Changing away from a flag restores the value input
choose(row(3).fieldBox, "Tier")
assert(visible(row(3).valueField) and shown(row(3).operatorBox) == "is")
enter(row(3).valueField, "25k")
choose(row(3).fieldBox, "Skills")
assert(visible(row(3).valueField) and row(3).valueField:GetText() == "")
assert(editor.pickerIndex == 3 and #editor.pickerValues == #app:RuneQL().Catalog.Values("skills"))
assert(not visible(editor.pickerNext))
assert(editor.body.contentHeight > row(3).fieldBox.root.y)
editor.body:SetScrollPosition(100)
assert(editor.footer.root.y == footerY and editor.cancelButton.root.y == cancelY and editor.saveButton.root.y == saveY)
enter(row(3).valueField, "archaeology")
assert(editor.preview.content:find('skills:["archaeology" TO "archaeology"]', 1, true))

-- Closing and reloading ----------------------------------------------------------------

-- Closing destroys every control the editor made
local editorRoot, slot = editor.root, row(1)
local fieldRoot = slot.fieldBox.root
local saveRoot = editor.saveButton.root
app:CloseEditor()
assert(app.editor == nil and editorRoot.destroyed and fieldRoot.destroyed)
assert(slot.maxField.root.destroyed and saveRoot.destroyed and editor.queryField.root.destroyed)
assert(#editor.owned == 0 and editor.root == nil)
-- Unloading the plugin closes an open editor
press(controls.new)
editorRoot = app.editor.root
h.host:Unload("advancedbanksearch")
assert(editorRoot.destroyed)
-- A reload reads the conditions back
h:LoadSearch()
app = h:App()
h:Tick(2)
assert(app.queries:Get("1").builder == nil and app.queries:Get("2").builder.rules[1].value == "rune bar")
app:EditQuery(catalogQuery.id)
assert(app.editor.mode == "visual" and app.editor.draft.rules[3].operator == "false")
assert(app.editor.slots[3].valueField.root.hidden)
-- A missing dependency preserves builders, then restores Visual on load
h.host:Unload("runeql")
assert(app.editor == nil)
h.host:Unload("advancedbanksearch")
h:LoadSearch()
app = h:App()
assert(app.queries:Get(catalogQuery.id).builder.rules[1].field == "category")
h:LoadRuneQL()
app:EditQuery(catalogQuery.id)
assert(app.editor.mode == "visual" and app.editor.pickerIndex == nil)
assert(app.editor.draft.rules[1].value == "melee-equipment")
-- Discover a new field and its values without editing this plugin
local engine = app:RuneQL()
local fieldsOf, valuesOf = engine.Catalog.Fields, engine.Catalog.Values
engine.Catalog.Fields = function()
    local fields = fieldsOf()
    for _, field in ipairs(fields) do if field.key == "skills" then field.label = "Skills from RuneQL" end end
    fields[#fields + 1] = { key = "newCatalogField", label = "New catalog field", type = "text", multiple = true }
    return fields
end
engine.Catalog.Values = function(key, options)
    if key == "skills" then return { { value = "rune-supplies", label = "Rune supplies" } }, 1 end
    return valuesOf(key, options)
end
app:DependencyChanged("runeql", true)
app:NewQuery()
editor = app.editor
assert(not labels(row(1).fieldBox):find("New catalog field", 1, true))
choose(row(1).fieldBox, "Skills from RuneQL")
assert(editor.pickerIndex == 1 and editor.pickerButtons[1].content.content == "Rune supplies")
press(editor.pickerButtons[1])
assert(editor.draft.rules[1].field == "skills" and editor.draft.rules[1].value == "rune-supplies")
assert(editor.preview.content == 'skills:["rune-supplies" TO "rune-supplies"]')
engine.Catalog.Fields, engine.Catalog.Values = fieldsOf, valuesOf
app:DependencyChanged("runeql", true)
-- Dose is available for new conditions as well as saved searches
local doseBuilder = { match = "all", rules = { { field = "dose", operator = "equals", value = 3 } } }
assert(app:SaveQuery(nil, "Existing doses", "dose:[3 TO 3]", doseBuilder))
app:EditQuery(app.selectedQuery)
assert(app.editor.mode == "visual" and app.editor.draft.rules[1].field == "dose")
assert(shown(row(1).fieldBox) == "Dose" and app.editor.preview.content == "dose:[3 TO 3]")
app:NewQuery()
assert(#app.editor.fields == 12 and labels(row(1).fieldBox):find("Dose", 1, true))
local menus = {
    ["Item name"] = "has all words,has phrase",
    ["Category"] = "is",
    ["Skills"] = "includes",
    ["Types"] = "includes",
    ["Combat style"] = "includes",
    ["Slot"] = "includes",
    ["Quantity"] = "is,is at least,is at most,is between",
    ["GE price"] = "is,is at least,is at most,is between",
    ["Tier"] = "is,is at least,is at most,is between",
    ["Tradeable"] = "is false,is true",
    ["Augmented"] = "is false,is true",
}
for field, comparisons in pairs(menus) do
    choose(row(1).fieldBox, field)
    assert(labels(row(1).operatorBox) == comparisons, field .. ": " .. labels(row(1).operatorBox))
end
choose(row(1).fieldBox, "Skills")
press(row(1).negateButton)
enter(row(1).valueField, "mining")
enter(app.editor.nameField, "Without mining")
press(app.editor.saveButton)
local exclusionID = app.selectedQuery
app:EditQuery(exclusionID)
assert(app.editor.mode == "visual" and shown(row(1).operatorBox) == "includes" and row(1).negateButton.active)
assert(app.editor.draft.rules[1].operator == "includes" and app.editor.draft.rules[1].negate)
-- Older word/phrase queries remain unchanged and editable in Advanced
assert(app:SaveQuery(nil, "Legacy food", 'category:"food"',
    { match = "all", rules = { { field = "category", operator = "phrase", value = "food" } } }))
app:EditQuery(app.selectedQuery)
assert(app.editor.mode == "advanced" and app.editor.queryField:GetText() == 'category:"food"')
-- Nested groups own their conditions and their AND/OR choices.
app:NewQuery()
editor = app.editor
enter(editor.nameField, "Nested conditions")
choose(row(1).fieldBox, "Quantity")
choose(row(1).operatorBox, "is at least")
enter(row(1).valueField, "10")
press(editor.addGroupButton)
assert(#editor.groupRows == 1 and #editor.ruleRows == 2)
assert(editor.addButton.content.spriteID == id.Sprite.BP3_MISSION_PLUS_ICON)
assert(editor.groupSlots[1].addButton.content.spriteID == id.Sprite.BP3_MISSION_PLUS_ICON)
assert(editor.addGroupButton.content.spriteID == id.Sprite.MTX_STORE_BTN_PLUS_ACTIVE)
assert(editor.groupSlots[1].groupButton.content.spriteID == id.Sprite.MTX_STORE_BTN_PLUS_ACTIVE)
choose(row(2).fieldBox, "Category")
enter(row(2).valueField, "food")
press(editor.groupSlots[1].addButton)
choose(row(3).fieldBox, "Dose")
enter(row(3).valueField, "4")
local nestedText = 'qty:[10 TO *] AND (category:["food" TO "food"] OR dose:[4 TO 4])'
assert(editor.preview.content == nestedText, editor.preview.content)
assert(row(2).fieldBox.root.x > row(1).fieldBox.root.x)
local trashX = row(1).removeButton.root.x
for index = 1, 3 do
    assert(row(index).removeButton.root.x == trashX - (index > 1 and 6 or 0))
    assert(row(index).removeButton.content.spriteID == id.Sprite.HUD_COMBAT_BTN_BIN)
    local bang = row(index).negateButton.content
    assert(bang.spriteID == id.Sprite.EXCLAMATION_MARK and bang.width == 10 and bang.height == 20)
end
assert(editor.groupSlots[1].removeButton.root.x == editor.groupSlots[1].groupButton.root.x + 34)
assert(editor.groupSlots[1].removeButton.root.x < trashX)
assert(editor.visualButton == nil and editor.advancedButton == nil and editor.body.root.y == 0)
press(row(3).negateButton)
assert(editor:Rule(3).negate and row(3).negateButton.active)
press(row(3).negateButton)
assert(editor.preview.content == nestedText)
press(editor.groupSlots[1].groupButton)
assert(#editor.groupRows == 2 and #editor.ruleRows == 4)
enter(row(4).valueField, "iron")
press(editor.groupSlots[2].removeButton)
assert(#editor.groupRows == 1 and #editor.ruleRows == 3 and editor.preview.content == nestedText)
press(editor.saveButton)
local nestedID = app.selectedQuery
app:EditQuery(nestedID)
editor = app.editor
assert(editor.mode == "visual" and #editor.groupRows == 1 and editor.preview.content == nestedText)
local reloadedNested = getmetatable(app.queries).new():Get(nestedID)
assert(reloadedNested.builder.rules[2].rules[2].field == "dose")

-- Core destroys the previous layers on redraw. Drafts must live outside those controls.
assert(app.settings:Set("editorMode", "advanced"))
enter(editor.queryField, nestedText .. " OR name:lobster")
enter(editor.nameField, "Unsaved nested name")
assert(app.settings:Set("editorMode", "visual")) -- Preserve detached Advanced text across redraws too.
assert(editor.preservedAdvanced == nestedText .. " OR name:lobster")
editor.body:SetScrollPosition(90)
local oldEditor, oldRoot = editor, editor.root
oldEditor.nameField.GetText = function() error("read from retired input") end
oldEditor.queryField.GetText = function() error("read from retired input") end
local oldWidth = h.bankHost.itemLayer.width
h.bankHost.itemLayer.width = 800
assert(app.editorExt:Refresh())
h:Tick(2)
editor = app.editor
assert(editor ~= oldEditor and oldEditor.destroyed and oldRoot.destroyed)
assert(editor.mode == "visual" and editor.preservedAdvanced == nestedText .. " OR name:lobster" and editor.body.scrollY == 90)
assert(editor.nameField:GetText() == "Unsaved nested name")
assert(editor.queryField:GetText() == nestedText .. " OR name:lobster")
assert(not editor.narrow and editor.preview.content == nestedText)
assert(app.settings:Set("editorMode", "visual"))
assert(editor.mode == "visual")
local wideTrashX = row(1).removeButton.root.x
assert(wideTrashX > trashX and row(3).removeButton.root.x == wideTrashX - 6)
h.bankHost.itemLayer.width = oldWidth
assert(app.editorExt:Refresh())
h:Tick(2)
editor = app.editor
assert(editor.narrow and editor.nameField:GetText() == "Unsaved nested name")
assert(editor.preview.content == nestedText and row(1).valueField.root.y > row(1).operatorBox.root.y)

-- A hovered picker tooltip is destroyed on selection, filtering, paging and close.
choose(row(2).fieldBox, "Skills")
local picker = editor.pickerButtons[1]
assert(picker.tooltip ~= nil)
Harness.Fire(picker.root, ui.Hook.ONMOUSEOVER)
local selectedTooltip = picker.tooltip
assert(selectedTooltip.root.hidden == false)
local selectedTooltipRoot = selectedTooltip.root
press(picker)
assert(selectedTooltipRoot.destroyed and picker.tooltip == nil and editor.pickerIndex == nil)
choose(row(2).fieldBox, "Category")
picker = editor.pickerButtons[1]
Harness.Fire(picker.root, ui.Hook.ONMOUSEOVER)
local filteredTooltipRoot = picker.tooltip.root
enter(row(2).valueField, "wood-production")
assert(filteredTooltipRoot.destroyed)
press(row(2).clearButton)
-- Clear is hidden while the value is empty; reopen all options directly.
editor:OpenPicker(2, "")
picker = editor.pickerButtons[1]
Harness.Fire(picker.root, ui.Hook.ONMOUSEOVER)
local pagedTooltipRoot = picker.tooltip.root
press(editor.pickerNext)
assert(pagedTooltipRoot.destroyed)
picker = editor.pickerButtons[1]
Harness.Fire(picker.root, ui.Hook.ONMOUSEOVER)
local closingTooltipRoot = picker.tooltip.root
editor:Close()
assert(closingTooltipRoot.destroyed and app.editor == nil and app.editorExt == nil)

-- The reported example: root OR compares two AND groups, not their individual conditions.
app:NewQuery()
editor = app.editor
enter(editor.nameField, "Body price or head")
press(editor.addGroupButton)
press(row(1).removeButton) -- Remove the initial ungrouped condition.
choose(editor.matchBox, "any condition (OR)")
choose(editor.groupSlots[1].matchBox, "all conditions (AND)")
choose(row(1).fieldBox, "GE price")
choose(row(1).operatorBox, "is at least")
enter(row(1).valueField, "1000")
press(editor.groupSlots[1].addButton)
choose(row(2).fieldBox, "Slot")
enter(row(2).valueField, "body")
press(editor.addGroupButton)
choose(editor.groupSlots[2].matchBox, "all conditions (AND)")
choose(row(3).fieldBox, "Slot")
enter(row(3).valueField, "head")
local bodyOrHead = '(price:[1000 TO *] AND slot:["body" TO "body"]) OR (slot:["head" TO "head"])'
assert(editor.preview.content == bodyOrHead, editor.preview.content)
assert(#editor.draft.rules == 2 and #editor.draft.rules[1].rules == 2)
assert(editor.addButton.root.y == editor.matchBox.root.y)
assert(editor.addButton.root.x > editor.matchBox.root.x)
assert(editor.groupSlots[1].bottomEdge.root.y < editor.groupSlots[2].background.root.y)
assert(editor.contentWidth == editor.width - 16 - 18)
assert(editor.body.root.height == editor.root.height - editor.footer.root.height)
local bodyFrame = editor.groupSlots[1].background.root
local groupHeader = editor.groupSlots[1].matchBox.root
assert(groupHeader.x - bodyFrame.x == 6 and groupHeader.y - bodyFrame.y == 6)
local bodyValue = row(2).valueField.root
assert(bodyFrame.x + bodyFrame.width - bodyValue.x - bodyValue.width == 6)
assert(bodyFrame.x + bodyFrame.width - row(2).removeButton.root.x - row(2).removeButton.root.width == 6)
for index, group in ipairs(editor.groupSlots) do
    if index <= 2 then
        assert(group.removeButton.root.x == group.groupButton.root.x + 34)
        assert(group.removeButton.root.y == group.groupButton.root.y)
        assert(group.removeButton.root.x < row(index).removeButton.root.x)
        assert(group.background.root.clickthrough and group.edge.root.clickthrough)
    end
end
assert(app.settings:Set("editorMode", "advanced"))
assert(editor.queryField:GetText() == bodyOrHead)
press(editor.saveButton)
local groupedID = app.selectedQuery
assert(app.settings:Set("editorMode", "visual"))
app:EditQuery(groupedID)
editor = app.editor
assert(editor.mode == "visual" and editor.preview.content == bodyOrHead)
assert(#editor.draft.rules[1].rules == 2 and #editor.draft.rules[2].rules == 1)
-- Existing loose conditions retain their meaning, but are visibly outside every group.
local looseBody = table.remove(editor.draft.rules[1].rules, 2)
table.insert(editor.draft.rules, 2, looseBody)
editor:SyncRows()
editor:Changed()
assert(editor.preview.content == '(price:[1000 TO *]) OR slot:["body" TO "body"] OR (slot:["head" TO "head"])')
assert(editor.ruleRows[2].depth == 0 and row(2).fieldBox.root.x == 8)
assert(row(2).fieldBox.root.y > editor.groupSlots[1].bottomEdge.root.y)
assert(row(2).fieldBox.root.y < editor.groupSlots[2].background.root.y)
press(editor.groupSlots[2].removeButton)
assert(#editor.groupRows == 1 and #editor.ruleRows == 2 and editor:Rule(2).value == "body")
editor:Close() -- Do not save this intentionally different tree.
app:EditQuery(groupedID)
assert(app.editor.preview.content == bodyOrHead)
app.editor:Close()

-- Leaving for a saved search retires the editor without reopening its previous page.
app:NewQuery()
local leavingEditor = app.editor
assert(app:ChooseQuery(nestedID))
h:Tick(2)
assert(app.editor == nil and leavingEditor.destroyed and app:ShownPage() == "query")
app:NewQuery()
leavingEditor = app.editor
app:OnBankClose()
assert(app.editor == nil and leavingEditor.destroyed and app.editorExt == nil)

h.host:Unload("advancedbanksearch")
h.host:Unload("bankcore")
print("query_editor_test: ok")
