package.path = "./?.lua;./?/init.lua;" .. package.path

-- Build, save, and reopen queries in the editor's Visual and Advanced modes
-- FAKE HOST: stand-in loader, components, and widgets, not the game client
-- Combo boxes are PrettyUI's own, over a native field that sorts its labels

local Harness = require("tools/test_support/search_harness")

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
    simple_button = { "SimpleButton:SetActive(active)", "SimpleButton:SetDisabled(disabled)" },
    text_field = { "TextField:GetText()", "TextField:SetText(value, triggerCallback)", "TextField:SetPlaceholder(value)" },
}) do
    for _, method in ipairs(methods) do
        assert(string.find(source(name), "function " .. method, 1, true), name .. " lacks " .. method)
    end
end
local editorFile = assert(io.open("advancedbanksearch/search/query_editor.lua", "rb"))
local editorSource = editorFile:read("a")
editorFile:close()
assert(not string.find(editorSource, "SetSelected", 1, true))

local h = Harness.new("query_editor")
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

-- Press a PrettyUI button
local function press(button)
    assert(not button.disabled, "pressed a disabled button")
    button.root.hooks[ui.Hook.ONCLICK]()
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
    box.input.hooks[ui.Hook.ONCLICK]()
    assert(box.open and not box.dropdown.root.hidden)
    for _, entry in ipairs(box.dropdown.rows) do
        if entry.label == label then
            box.dropdown:Click(entry.id)
            assert(not box.open and box.input.content == label)
            return
        end
    end
    error("no combo entry " .. label)
end

-- List a combo box's entries in the order its dropdown shows them
local function labels(box)
    local listed = {}
    for index, entry in ipairs(box.dropdown.rows) do listed[index] = entry.label end
    return table.concat(listed, ",")
end

-- Return the label a combo box shows
local function shown(box)
    return box.input.content
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
assert(editor.mode == "visual" and editor.visualButton.active and not editor.advancedButton.active)
assert(shownRows() == 1 and row(1).removeButton.disabled and not editor.addButton.disabled)
assert(not visible(editor.queryField) and not visible(editor.characterCount) and visible(editor.preview))
assert(row(1).fieldBox:GetSelectedID() == 1 and row(1).operatorBox:GetSelectedID() == 1)
-- Lists keep the builder's order, not the alphabetical one, and show the draft's choice
assert(labels(row(1).fieldBox) == "Item name,Quantity,GE price,GE high price,GE low price")
assert(shown(row(1).fieldBox) == "Item name" and shown(row(1).operatorBox) == "has phrase")
assert(labels(row(1).operatorBox) == "has phrase,has all words")
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
    choose(row(1).fieldBox, "GE high price")
    local rule = editor.draft.rules[1]
    assert(rule.field == "gehigh" and rule.operator == "equals" and rule.value == "")
    assert(shown(row(1).fieldBox) == "GE high price" and shown(row(1).operatorBox) == "is")
    assert(labels(row(1).operatorBox) == "is,is greater than,is less than,is between")
    assert(row(1).valueField:GetText() == "" and row(1).valueField.placeholder == "Number")
    assert(editor.preview.content == "Condition 1: enter a whole number like 500, 25k, or 1.5m.")
    choose(row(1).operatorBox, "is greater than")
    enter(row(1).valueField, "5k")
    assert(editor.preview.content == "RuneQL: gehigh:[5000 TO *]", editor.preview.content)
    -- Another number field keeps the comparison and number
    choose(row(1).fieldBox, "GE low price")
    assert(editor.draft.rules[1].operator == "atleast" and shown(row(1).operatorBox) == "is greater than")
    assert(row(1).valueField:GetText() == "5k" and editor.preview.content == "RuneQL: gelow:[5000 TO *]")
    choose(row(1).operatorBox, "is between")
    assert(visible(row(1).minField) and not visible(row(1).valueField))
    choose(row(1).fieldBox, "Item name")
    rule = editor.draft.rules[1]
    assert(rule.field == "name" and rule.operator == "phrase" and rule.value == "")
    assert(shown(row(1).fieldBox) == "Item name" and shown(row(1).operatorBox) == "has phrase")
    assert(labels(row(1).operatorBox) == "has phrase,has all words")
    assert(visible(row(1).valueField) and not visible(row(1).minField) and not visible(row(1).andText))
end
assert(#row(1).operatorBox.entries == 2 and visible(row(1).valueField) and not visible(row(1).minField))
assert(editor.preview.content == "Condition 1: enter words from the item name.", editor.preview.content)
-- An incomplete condition is refused with its reason and nothing saves
enter(editor.nameField, "Iron stock")
press(editor.saveButton)
assert(app.editor == editor and editor.status.content == "Condition 1: enter words from the item name.")
assert(#app.queries:All() == 0)

-- Typing a name updates the preview and clears the message
enter(row(1).valueField, 'iron "bar"')
assert(editor.preview.content == 'RuneQL: name:"iron \\"bar\\""' and editor.status.hidden, editor.preview.content)
choose(row(1).operatorBox, "has all words")
assert(editor.preview.content == 'RuneQL: (name:"iron" AND name:"\\"bar\\"")', editor.preview.content)
enter(row(1).valueField, "iron")

-- Adding a condition shows a row; a quantity offers number comparisons
press(editor.addButton)
assert(shownRows() == 2 and not row(1).removeButton.disabled and row(2).fieldBox:GetSelectedID() == 1)
choose(row(2).fieldBox, "Quantity")
assert(editor.draft.rules[2].field == "qty" and #row(2).operatorBox.entries == 4)
assert(row(2).operatorBox:GetSelectedID() == 1 and row(2).valueField.placeholder == "Number")
enter(row(2).valueField, "lots")
assert(editor.preview.content == "Condition 2: enter a whole number like 500, 25k, or 1.5m.", editor.preview.content)
-- Between shows two bounds and checks their order
choose(row(2).operatorBox, "is between")
assert(not visible(row(2).valueField) and visible(row(2).minField) and visible(row(2).maxField))
assert(visible(row(2).andText))
enter(row(2).minField, "10")
enter(row(2).maxField, "5")
assert(editor.preview.content == "Condition 2: the first number must not be more than the second.")
enter(row(2).maxField, "1k")
assert(editor.preview.content == 'RuneQL: name:"iron" AND qty:[10 TO 1000]', editor.preview.content)
-- Matching any joins with OR
choose(editor.matchBox, "any condition (OR)")
assert(editor.preview.content == 'RuneQL: name:"iron" OR qty:[10 TO 1000]', editor.preview.content)
choose(editor.matchBox, "all conditions (AND)")

-- At most six conditions; removing one moves the rest up
for _ = 3, 6 do press(editor.addButton) end
assert(shownRows() == 6 and editor.addButton.disabled)
choose(row(3).fieldBox, "GE price")
choose(row(3).operatorBox, "is less than")
enter(row(3).valueField, "1.5m")
press(row(2).removeButton)
assert(shownRows() == 5 and not editor.addButton.disabled)
assert(row(2).fieldBox:GetSelectedID() == 3 and row(2).operatorBox:GetSelectedID() == 3)
assert(row(2).valueField:GetText() == "1.5m" and not visible(row(2).minField))
assert(shown(row(2).fieldBox) == "GE price" and shown(row(2).operatorBox) == "is less than")
assert(shown(row(3).fieldBox) == "Item name" and shown(row(3).operatorBox) == "has phrase")
-- A field of the same kind keeps its comparison and number
choose(row(2).fieldBox, "Quantity")
assert(editor.draft.rules[2].operator == "atmost" and editor.draft.rules[2].value == "1.5m")
assert(shown(row(2).fieldBox) == "Quantity" and shown(row(2).operatorBox) == "is less than")
for _ = 1, 3 do press(row(3).removeButton) end
assert(shownRows() == 2 and not visible(row(3).fieldBox) and not visible(row(3).removeButton))
-- Choosing a name field again starts that condition over
choose(row(2).fieldBox, "Item name")
assert(editor.draft.rules[2].operator == "phrase" and editor.draft.rules[2].value == "")
assert(#row(2).operatorBox.entries == 2 and row(2).valueField:GetText() == "")
choose(row(2).fieldBox, "Quantity")
choose(row(2).operatorBox, "is greater than")
enter(row(2).valueField, "10")
assert(editor.preview.content == 'RuneQL: name:"iron" AND qty:[10 TO *]', editor.preview.content)

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
assert(row(1).valueField:GetText() == "iron" and row(2).fieldBox:GetSelectedID() == 2)
assert(row(2).operatorBox:GetSelectedID() == 2 and row(2).valueField:GetText() == "10")
assert(shown(row(2).fieldBox) == "Quantity" and shown(row(2).operatorBox) == "is greater than")
assert(labels(row(2).operatorBox) == "is,is greater than,is less than,is between")
assert(editor.preview.content == "RuneQL: " .. record.query)
-- Advanced shows the text the conditions give, and Visual comes back without asking
press(editor.advancedButton)
assert(editor.mode == "advanced" and editor.queryField:GetText() == record.query and visible(editor.queryField))
assert(not visible(editor.preview) and not visible(row(1).fieldBox) and editor.advancedButton.active)
assert(editor.characterCount.content == #record.query .. " / 9999")
press(editor.visualButton)
assert(editor.mode == "visual" and editor.status.hidden and shownRows() == 2)
assert(shown(row(1).fieldBox) == "Item name" and shown(row(2).operatorBox) == "is greater than")
-- Saving unchanged text from Advanced keeps the conditions
press(editor.advancedButton)
press(editor.saveButton)
assert(app.queries:Get("1").builder ~= nil)

-- Typed text drops the conditions -------------------------------------------------

press(controls.edit)
editor = app.editor
press(editor.advancedButton)
enter(editor.queryField, "(" .. record.query .. ") OR name:lobster")
-- Visual asks before replacing typed text
press(editor.visualButton)
assert(editor.mode == "advanced" and editor.status.content == "Visual conditions replace this RuneQL. Press Visual again to use them.")
press(editor.saveButton)
record = app.queries:Get("1")
assert(record.query == '(name:"iron" AND qty:[10 TO *]) OR name:lobster' and record.builder == nil)
assert(matched("1") == "102,104", matched("1"))
-- It now opens in Advanced, untouched
press(controls.edit)
editor = app.editor
assert(editor.mode == "advanced" and editor.queryField:GetText() == record.query)
editor.window:Close()
assert(app.editor == nil)

-- A typed query ----------------------------------------------------------------------

-- RuneQL the conditions cannot hold stays typed text
local typed = "name:(rune AND bar~1) -name:ore"
assert(app:SaveQuery(nil, "Runes", typed))
app:EditQuery("2")
editor = app.editor
assert(editor.queryID == "2" and editor.mode == "advanced" and editor.queryField:GetText() == typed)
-- Leaving for Visual needs a second press, then starts a blank condition
press(editor.visualButton)
assert(editor.mode == "advanced" and not editor.status.hidden)
-- Typing again asks again
enter(editor.queryField, typed .. " ")
assert(editor.status.hidden and not editor.confirmVisual)
enter(editor.queryField, typed)
press(editor.visualButton)
press(editor.visualButton)
assert(editor.mode == "visual" and shownRows() == 1 and editor.draft.rules[1].value == "")
-- Incomplete conditions leave the typed text alone
press(editor.advancedButton)
assert(editor.mode == "advanced" and editor.queryField:GetText() == typed)
assert(editor.status.content == "The conditions are incomplete, so the RuneQL text was not changed.")
press(editor.saveButton)
assert(app.queries:Get("2").query == typed and app.queries:Get("2").builder == nil)
-- Saving from Visual replaces the text only when the player chose it
app:EditQuery("2")
editor = app.editor
press(editor.visualButton)
press(editor.visualButton)
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

-- Closing and reloading ----------------------------------------------------------------

-- Closing destroys every control the editor made
local window, slot = editor.window, row(1)
local fieldRoot, fieldList = slot.fieldBox.root, slot.fieldBox.dropdown.root
app:CloseEditor()
assert(app.editor == nil and window.root.destroyed and fieldRoot.destroyed and fieldList.destroyed)
assert(slot.maxField.root.destroyed and editor.saveButton.root.destroyed and editor.queryField.root.destroyed)
assert(#editor.owned == 0 and editor.window == nil)
-- Unloading the plugin closes an open editor
press(controls.new)
window = app.editor.window
h.host:Unload("advancedbanksearch")
assert(window.root.destroyed)
-- A reload reads the conditions back
h:LoadSearch()
app = h:App()
h:Tick(2)
assert(app.queries:Get("1").builder == nil and app.queries:Get("2").builder.rules[1].value == "rune bar")
h.host:Unload("advancedbanksearch")
h.host:Unload("bankcore")
print("query_editor_test: ok")
