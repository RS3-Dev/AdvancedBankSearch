-- Edit saved query names and expressions
-- Queries are built from visual conditions or typed as RuneQL in Advanced

local QueryBuilder = require("resources/search/query_builder")
local QueryStore = require("resources/search/query_store")

local QueryEditor = {}
QueryEditor.__index = QueryEditor

local WIDTH = 620
local HEIGHT = 560
local MARGIN = 16
local CONTENT_WIDTH = WIDTH - 16 - MARGIN * 2
local BUTTON_GAP = 8
local CONTROL_HEIGHT = 28
local LABEL_COLOUR = 0xF2C66DFF
local HINT_COLOUR = 0x9F947BFF
local PREVIEW_COLOUR = 0xE7D7B0FF
local ERROR_COLOUR = 0xE57373FF
local SMALL_FONT = id.Font.MUSEO_SANS_11PT_REGULAR
-- Where the mode panels start, and the rows of conditions
local PANEL_TOP = 110
local ROWS_TOP = 146
local ROW_HEIGHT = 34
local QUERY_FIELD_HEIGHT = 288
local FOOTER_HEIGHT = 64
local BUTTONS_TOP = 28
-- Columns of a condition row
local FIELD_WIDTH = 140
local OPERATOR_X = MARGIN + 146
local OPERATOR_WIDTH = 136
local VALUE_X = MARGIN + 288
local VALUE_WIDTH = 210
local BOUND_WIDTH = 92
local REMOVE_X = MARGIN + 504
local REMOVE_WIDTH = CONTENT_WIDTH - 504
local MATCH_CHOICES = { { key = "all", label = "all conditions (AND)" }, { key = "any", label = "any condition (OR)" } }
local PICKER_COLUMNS = 4
local PICKER_PAGE_SIZE = 24
local PICKER_ROW_HEIGHT = 28
local LEAVE_TEXT = "Visual conditions replace this RuneQL. Press Visual again to use them."
local INCOMPLETE = "The conditions are incomplete, so the RuneQL text was not changed."

-- Trim spaces from user text
local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

-- Give native combos IDs matching their sorted labels
local function entriesOf(choices)
    local entries = {}
    for index, choice in ipairs(choices) do entries[index] = { id = index, label = choice.label } end
    return entries
end

-- Sort choices to match native combo positions
local function sortedChoices(choices)
    local sorted = {}
    for index, choice in ipairs(choices) do sorted[index] = choice end
    table.sort(sorted, function(a, b) return a.label < b.label end)
    return sorted
end

-- Find a native combo position by key
local function choiceID(choices, key)
    for index, choice in ipairs(choices) do if choice.key == key then return index end end
end

-- Show or hide a PrettyUI control or a text label
local function setHidden(control, hidden)
    local node = control.root or control
    node.hidden = hidden == true
end

-- Create the saved-query editor and its controls
-- A query opens in Visual only when its saved conditions still give it
function QueryEditor.new(parent, options)
    options = options or {}
    local record = options.record or {}
    local builder = QueryBuilder.Trusted(record.builder, record.query)
    if builder ~= nil and not QueryBuilder.SupportsVisual(builder) then builder = nil end
    local self = setmetatable({
        ready = false,
        destroyed = false,
        fields = sortedChoices(QueryBuilder.VisualFields(builder)),
        operators = {},
        queryID = record.id,
        onSave = options.onSave,
        -- Why saving is blocked, kept while the player types
        blocked = options.blocked,
        catalog = options.catalog,
        pickerIndex = nil,
        pickerPage = 1,
        pickerValues = {},
        pickerButtons = {},
        owned = {},
        visualControls = {},
        advancedControls = {},
        slots = {},
        -- The RuneQL last built from the conditions and their saved form
        -- Advanced keeps the conditions only while its text is this
        generated = nil,
        generatedBuilder = nil,
        confirmVisual = false,
    }, QueryEditor)
    if builder ~= nil then
        self.mode = "visual"
        self.generated, self.generatedBuilder = record.query, builder
    else
        self.mode = record.id ~= nil and "advanced" or options.defaultMode == "advanced" and "advanced" or "visual"
    end
    self.draft = QueryBuilder.Draft(builder)

    for kind, choices in pairs(QueryBuilder.OPERATORS) do self.operators[kind] = sortedChoices(choices) end
    local built, reason = pcall(self.Build, self, parent, options)
    if not built then
        self:Destroy()
        error(reason, 0)
    end
    return self
end

-- Construct controls before allowing their callbacks
function QueryEditor:Build(parent, options)
    local record = options.record or {}
    self.window = prettyui.Window.new(parent, {
        title = record.id ~= nil and "Edit RuneQL Query" or "Create RuneQL Query",
        x = -math.floor(WIDTH / 2),
        y = -math.floor(HEIGHT / 2),
        xAnchor = 0.5,
        yAnchor = 0.5,
        width = WIDTH,
        height = HEIGHT,
        minWidth = WIDTH,
        maxWidth = WIDTH,
        minHeight = HEIGHT,
        maxHeight = HEIGHT,
        scrollable = false,
        destroyOnClose = true,
        onClose = function()
            self:Destroy()
            if options.onClose ~= nil then options.onClose() end
        end,
    })
    self.body = self:Own(prettyui.SimpleView.new(self.window.content, {
        width = 0, widthAnchor = 1.0,
        height = -FOOTER_HEIGHT, heightAnchor = 1.0,
        scrollable = true,
    }))
    self.content = self.body.content
    local footer = { root = ui.Layer.new(self.window.content) }
    function footer:Destroy() self.root:Destroy() end
    self.footer = self:Own(footer)
    footer.root:SetPos(0, -FOOTER_HEIGHT, 0, 1.0)
    footer.root:SetSize(0, FOOTER_HEIGHT, 1.0, 0)

    self.nameLabel = self:Own(prettyui.Text.new(self.content, {
        text = "Query name",
        x = MARGIN,
        y = 10,
        width = CONTENT_WIDTH,
        height = 20,
        colour = LABEL_COLOUR,
        font = id.Font.CINZEL_13PT_BOLD,
    }))
    self.nameField = self:Own(prettyui.TextField.new(self.content, {
        x = MARGIN,
        y = 31,
        width = CONTENT_WIDTH,
        height = 30,
        text = record.name or "",
        placeholder = "Search name",
        maxLength = QueryStore.MAX_NAME_LENGTH,
        onChange = function() self:ClearStatus() end,
    }))
    self.visualButton = self:Own(prettyui.SimpleButton.new(self.content, "Visual", function()
        self:ChooseVisual()
    end, { x = MARGIN, y = 72, width = 100, height = CONTROL_HEIGHT }))
    self.advancedButton = self:Own(prettyui.SimpleButton.new(self.content, "Advanced", function()
        self:ChooseAdvanced()
    end, { x = MARGIN + 106, y = 72, width = 100, height = CONTROL_HEIGHT }))

    self:BuildVisual()
    self:BuildAdvanced(record.query or "")

    self.status = self:Own(prettyui.Text.new(self.footer.root, {
        text = "",
        x = MARGIN,
        y = 4,
        width = CONTENT_WIDTH,
        height = 18,
        colour = ERROR_COLOUR,
        font = SMALL_FONT,
        maxLines = 1,
    }))
    self.status.hidden = true

    local buttonWidth = math.floor((CONTENT_WIDTH - BUTTON_GAP) / 2)
    self.cancelButton = self:Own(prettyui.SimpleButton.new(self.footer.root, "Cancel", function()
        self.window:Close()
    end, {
        x = MARGIN,
        y = BUTTONS_TOP,
        width = buttonWidth,
        height = CONTROL_HEIGHT,
    }))
    self.saveButton = self:Own(prettyui.SimpleButton.new(self.footer.root, "Save", function()
        self:Save()
    end, {
        x = MARGIN + buttonWidth + BUTTON_GAP,
        y = BUTTONS_TOP,
        width = CONTENT_WIDTH - buttonWidth - BUTTON_GAP,
        height = CONTROL_HEIGHT,
    }))

    self.ready = true
    self:ShowMode(self.mode)
    self:Changed()
    if self.blocked ~= nil then
        self.saveButton:SetDisabled(true)
        self:SetStatus(self.blocked)
    end
    return self
end

-- Keep a control so the editor destroys it
function QueryEditor:Own(control, group)
    self.owned[#self.owned + 1] = control
    if group ~= nil then group[#group + 1] = control end
    return control
end

-- Create the match choice, condition rows, add button, and preview
function QueryEditor:BuildVisual()
    local content, group = self.content, self.visualControls
    self:Own(prettyui.Text.new(content, {
        text = "Match",
        x = MARGIN,
        y = PANEL_TOP,
        width = 52,
        height = CONTROL_HEIGHT,
        colour = LABEL_COLOUR,
        font = id.Font.CINZEL_13PT_BOLD,
        alignVertical = ui.AlignMode.CENTRE,
    }), group)
    self.matchBox = self:Own(prettyui.ComboBox.new(content, {
        x = MARGIN + 56,
        y = PANEL_TOP,
        width = 220,
        height = CONTROL_HEIGHT,
        entries = entriesOf(MATCH_CHOICES),
        selectedID = self.draft.match == "any" and 2 or 1,
        onChange = function(_, entryID)
            if not self.ready or self.syncing then return end
            self.draft.match = MATCH_CHOICES[entryID] and MATCH_CHOICES[entryID].key or "all"
            self:Changed()
        end,
    }), group)

    for index = 1, QueryBuilder.MAX_RULES do self.slots[index] = self:BuildRow(index) end

    local addTop = ROWS_TOP + ROW_HEIGHT * QueryBuilder.MAX_RULES + 4
    self.addButton = self:Own(prettyui.SimpleButton.new(content, "Add condition", function()
        self:AddRule()
    end, { x = MARGIN, y = addTop, width = 140, height = CONTROL_HEIGHT }), group)
    self.preview = self:Own(prettyui.Text.new(content, {
        text = "",
        x = MARGIN,
        y = addTop + 74,
        width = CONTENT_WIDTH,
        height = 32,
        colour = PREVIEW_COLOUR,
        font = SMALL_FONT,
        maxLines = 2,
        alignVertical = ui.AlignMode.TOPLEFT,
    }), group)
    self:BuildPicker()
end

-- Create one condition row's controls, shown when it has a condition
function QueryEditor:BuildRow(index)
    local content = self.content
    local top = ROWS_TOP + ROW_HEIGHT * (index - 1)
    local slot = { kind = nil }
    -- Change this row's condition and refresh the preview
    local function edit(key, value)
        if not self.ready or self.syncing then return end
        local rule = self.draft.rules[index]
        if rule == nil then return end
        -- Native fields can echo a programmatic value on a later event
        if rule[key] == value then return end
        rule[key] = value
        if key == "value" then
            local field = QueryBuilder.FieldOf(rule.field)
            if field.catalog and field.kind == "text" then
                self:OpenPicker(index, value)
            end
        end
        self:Changed()
    end
    slot.fieldBox = self:Own(prettyui.ComboBox.new(content, {
        x = MARGIN,
        y = top,
        width = FIELD_WIDTH,
        height = CONTROL_HEIGHT,
        entries = entriesOf(self.fields),
        selectedID = choiceID(self.fields, "name"),
        onChange = function(_, entryID) self:ChooseField(index, entryID) end,
    }))
    slot.operatorBox = self:Own(prettyui.ComboBox.new(content, {
        x = OPERATOR_X,
        y = top,
        width = OPERATOR_WIDTH,
        height = CONTROL_HEIGHT,
        entries = entriesOf(self.operators.text),
        selectedID = choiceID(self.operators.text, "phrase"),
        onChange = function(_, entryID) self:ChooseOperator(index, entryID) end,
    }))
    slot.kind = "text"
    slot.valueField = self:Own(prettyui.TextField.new(content, {
        x = VALUE_X,
        y = top,
        width = VALUE_WIDTH,
        height = CONTROL_HEIGHT,
        maxLength = QueryBuilder.MAX_TEXT_LENGTH,
        onChange = function(_, _, value) edit("value", value) end,
    }))
    slot.valueField.root:Subscribe(ui.Hook.ONCLICK, "advancedbanksearch_value_picker", function()
        if not self.ready or self.syncing then return false end
        local rule = self.draft.rules[index]
        local field = rule and QueryBuilder.FieldOf(rule.field)
        if field and field.catalog and field.kind == "text" and trim(rule.value) == "" then
            self:OpenPicker(index, "")
        end
        return false
    end)
    local clear = self:Own({ root = ui.Layer.new(content) })
    clear.root:SetPos(VALUE_X + VALUE_WIDTH - 26, top)
    function clear:Destroy()
        prettyui.Tooltip.unbind(self)
        self.root:Destroy()
    end
    clear.root:SetSize(24, CONTROL_HEIGHT)
    clear.root.clickthrough = false
    local cross = prettyui.Text.new(clear.root, {
        text = "×", width = 24, height = CONTROL_HEIGHT, font = SMALL_FONT,
        colour = HINT_COLOUR, alignHorizontal = ui.AlignMode.CENTRE,
        alignVertical = ui.AlignMode.CENTRE,
    })
    cross.clickthrough = true
    clear.root:Subscribe(ui.Hook.ONCLICK, function()
        edit("value", "")
        self:SyncRows()
        return true
    end)
    clear.root:Subscribe(ui.Hook.ONMOUSEOVER, function()
        if self.ready then cross.rgba = LABEL_COLOUR end
    end)
    clear.root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        if self.ready then cross.rgba = HINT_COLOUR end
    end)
    prettyui.Tooltip.bind(clear, clear.root, content, "Clear value")
    slot.clearButton = clear
    slot.minField = self:Own(prettyui.TextField.new(content, {
        x = VALUE_X,
        y = top,
        width = BOUND_WIDTH,
        height = CONTROL_HEIGHT,
        maxLength = 16,
        placeholder = "Low",
        onChange = function(_, _, value) edit("min", value) end,
    }))
    slot.andText = self:Own(prettyui.Text.new(content, {
        text = "and",
        x = VALUE_X + BOUND_WIDTH,
        y = top,
        width = VALUE_WIDTH - BOUND_WIDTH * 2,
        height = CONTROL_HEIGHT,
        colour = HINT_COLOUR,
        font = SMALL_FONT,
        maxLines = 1,
        alignHorizontal = ui.AlignMode.CENTRE,
        alignVertical = ui.AlignMode.CENTRE,
    }))
    slot.maxField = self:Own(prettyui.TextField.new(content, {
        x = VALUE_X + VALUE_WIDTH - BOUND_WIDTH,
        y = top,
        width = BOUND_WIDTH,
        height = CONTROL_HEIGHT,
        maxLength = 16,
        placeholder = "High",
        onChange = function(_, _, value) edit("max", value) end,
    }))
    slot.removeButton = self:Own(prettyui.SimpleButton.new(content, "Remove", function()
        self:RemoveRule(index)
    end, { x = REMOVE_X, y = top, width = REMOVE_WIDTH, height = CONTROL_HEIGHT }))
    return slot
end

-- Create a reusable grid for catalog choices
function QueryEditor:BuildPicker()
    local width = math.floor((CONTENT_WIDTH - 18) / PICKER_COLUMNS)
    for index = 1, PICKER_PAGE_SIZE do
        local button = self:Own(prettyui.SimpleButton.new(self.content, "", function()
            self:ChooseValue(index)
        end, { width = width, height = 24 }))
        button.content.font = SMALL_FONT
        self.pickerButtons[index] = button
    end
    self.pickerPrevious = self:Own(prettyui.SimpleButton.new(self.content, "‹", function()
        if not self.ready then return end
        self.pickerPage = self.pickerPage - 1
        self:SyncRows()
    end, { width = 28, height = 24 }))
    self.pickerNext = self:Own(prettyui.SimpleButton.new(self.content, "›", function()
        if not self.ready then return end
        self.pickerPage = self.pickerPage + 1
        self:SyncRows()
    end, { width = 28, height = 24 }))
end

-- Fetch choices when a catalog value is edited
function QueryEditor:OpenPicker(index, filter)
    if not self.ready then return end
    if type(self.catalog) ~= "table" or type(self.catalog.Values) ~= "function" then return end
    local rule = self.draft.rules[index]
    local values, _, reason = self.catalog.Values(rule.field, { query = filter or "" })
    self.pickerValues = values or {}
    self.pickerIndex = #self.pickerValues > 0 and index or nil
    self.pickerPage = 1
    self:SyncRows()
    if reason ~= nil and self.status ~= nil then self:SetStatus(reason) end
end

-- Fill the value and collapse its choices
function QueryEditor:ChooseValue(index)
    if not self.ready then return end
    local value = self.pickerValues[(self.pickerPage - 1) * PICKER_PAGE_SIZE + index]
    local rule = self.pickerIndex and self.draft.rules[self.pickerIndex]
    if value == nil or rule == nil then return end
    rule.value = tostring(value.value)
    self.pickerIndex = nil
    self:SyncRows()
    self:Changed()
end

-- Position the visible page of catalog choices
function QueryEditor:LayoutPicker(top, shown)
    local offset = (self.pickerPage - 1) * PICKER_PAGE_SIZE
    local width = math.floor((CONTENT_WIDTH - 18) / PICKER_COLUMNS)
    local count = math.min(PICKER_PAGE_SIZE, #self.pickerValues - offset)
    local rows = math.ceil(math.max(0, count) / PICKER_COLUMNS)
    for index, button in ipairs(self.pickerButtons) do
        local value = self.pickerValues[offset + index]
        setHidden(button, not shown or value == nil)
        if value ~= nil then
            button.content.content = value.label
            button:SetTooltip(value.label)
            button.root:SetPos(MARGIN + ((index - 1) % PICKER_COLUMNS) * (width + 6),
                top + math.floor((index - 1) / PICKER_COLUMNS) * PICKER_ROW_HEIGHT)
        end
    end
    local paged = shown and #self.pickerValues > PICKER_PAGE_SIZE
    setHidden(self.pickerPrevious, not paged)
    setHidden(self.pickerNext, not paged)
    self.pickerPrevious:SetDisabled(self.pickerPage <= 1)
    self.pickerNext:SetDisabled(offset + PICKER_PAGE_SIZE >= #self.pickerValues)
    self.pickerPrevious.root:SetPos(MARGIN, top + rows * PICKER_ROW_HEIGHT)
    self.pickerNext.root:SetPos(MARGIN + 34, top + rows * PICKER_ROW_HEIGHT)
    return shown and (rows * PICKER_ROW_HEIGHT + (paged and 28 or 0) + 8) or 0
end

-- Create the typed RuneQL field and its length count
function QueryEditor:BuildAdvanced(query)
    local content, group = self.content, self.advancedControls
    self:Own(prettyui.Text.new(content, {
        text = "RuneQL",
        x = MARGIN,
        y = PANEL_TOP,
        width = 74,
        height = 20,
        colour = LABEL_COLOUR,
        font = id.Font.CINZEL_13PT_BOLD,
    }), group)
    self:Own(prettyui.Text.new(content, {
        text = "Use OR between alternatives",
        x = MARGIN + 82,
        y = PANEL_TOP,
        width = CONTENT_WIDTH - 82,
        height = 20,
        colour = HINT_COLOUR,
        font = SMALL_FONT,
        maxLines = 1,
        alignVertical = ui.AlignMode.CENTRE,
    }), group)
    self.queryField = self:Own(prettyui.TextField.new(content, {
        x = MARGIN,
        y = PANEL_TOP + 22,
        width = CONTENT_WIDTH,
        height = QUERY_FIELD_HEIGHT,
        text = query,
        placeholder = "e.g. name:(vial AND water) OR name:\"dragon bones\"",
        maxLength = QueryStore.MAX_QUERY_LENGTH,
        maxLines = 0,
        lineSpacing = 14,
        alignVertical = ui.AlignMode.TOPLEFT,
        font = SMALL_FONT,
        contentMargin = ui.Margin.new(8, 8, 8, 8),
        onChange = function(_, _, value)
            self:UpdateCharacterCount(value)
            self:ClearStatus()
        end,
    }), group)
    self.characterCount = self:Own(prettyui.Text.new(content, {
        text = "",
        x = MARGIN,
        y = PANEL_TOP + 22 + QUERY_FIELD_HEIGHT + 6,
        width = CONTENT_WIDTH,
        height = 18,
        colour = HINT_COLOUR,
        font = SMALL_FONT,
        maxLines = 1,
        alignHorizontal = ui.AlignMode.BOTTOMRIGHT,
    }), group)
    self:UpdateCharacterCount(query)
end

-- Show one mode's controls and light its button
function QueryEditor:ShowMode(mode)
    if not self.ready then return end
    self.mode = mode
    self.confirmVisual = false
    for _, control in ipairs(self.visualControls) do setHidden(control, mode ~= "visual") end
    for _, control in ipairs(self.advancedControls) do setHidden(control, mode ~= "advanced") end
    self.visualButton:SetActive(mode == "visual")
    self.advancedButton:SetActive(mode == "advanced")
    self:SyncRows()
end

-- Switch to Advanced with the RuneQL the conditions give
-- Incomplete conditions leave the typed text as it was
function QueryEditor:ChooseAdvanced()
    if not self.ready then return end
    if self.mode == "advanced" then return end
    local query, builder = QueryBuilder.Build(self.draft)
    self:ShowMode("advanced")
    if query == nil then
        self:SetStatus(INCOMPLETE)
        return
    end
    self.generated, self.generatedBuilder = query, builder
    self.queryField:SetText(query)
    self:UpdateCharacterCount(query)
    self:ClearStatus()
end

-- Switch to Visual, asking first when it would replace typed RuneQL
function QueryEditor:ChooseVisual()
    if not self.ready then return end
    if self.mode == "visual" then return end
    local text = self.queryField:GetText()
    local linked = self.generated ~= nil and text == self.generated
    if not linked and trim(text) ~= "" and not self.confirmVisual then
        self.confirmVisual = true
        self:SetStatus(LEAVE_TEXT)
        return
    end
    self:ShowMode("visual")
    self:Changed()
end

-- Add a blank name condition below the others
function QueryEditor:AddRule()
    if not self.ready then return end
    if #self.draft.rules >= QueryBuilder.MAX_RULES then return end
    self.draft.rules[#self.draft.rules + 1] = QueryBuilder.NewRule()
    self.pickerIndex = nil
    self:SyncRows()
    self:Changed()
end

-- Remove a condition, keeping at least one
function QueryEditor:RemoveRule(index)
    if not self.ready then return end
    if #self.draft.rules <= 1 or self.draft.rules[index] == nil then return end
    table.remove(self.draft.rules, index)
    self.pickerIndex = nil
    self:SyncRows()
    self:Changed()
end

-- Change a condition's field, starting over when its kind changes
function QueryEditor:ChooseField(index, entryID)
    if not self.ready then return end
    local rule, field = self.draft.rules[index], self.fields[entryID]
    if rule == nil or field == nil or field.key == rule.field then return end
    local before = QueryBuilder.FieldOf(rule.field)
    if before == nil or before.kind ~= field.kind or field.catalog or before.catalog then
        self.draft.rules[index] = QueryBuilder.NewRule(field.key)
    else
        rule.field = field.key
    end
    self.pickerIndex = nil
    self:SyncRows()
    if field.catalog and field.kind == "text" then self:OpenPicker(index, "") end
    self:Changed()
end

-- Change how a condition compares its value
function QueryEditor:ChooseOperator(index, entryID)
    if not self.ready then return end
    local rule = self.draft.rules[index]
    if rule == nil then return end
    local operator = self.operators[QueryBuilder.OperatorKind(rule.field)][entryID]
    if operator == nil or operator.key == rule.operator then return end
    rule.operator = operator.key
    self:SyncRows()
    self:Changed()
end

-- Show each row's condition, hiding rows without one
-- Suppress callbacks while reflecting saved conditions
function QueryEditor:SyncRows()
    if not self.ready then return end
    if self.syncing then return end
    self.syncing = true
    local visual = self.mode == "visual"
    local count = #self.draft.rules
    local pickerTop = ROWS_TOP + ROW_HEIGHT * (self.pickerIndex or 0)
    local pickerHeight = self:LayoutPicker(pickerTop, visual and self.pickerIndex ~= nil)
    for index, slot in ipairs(self.slots) do
        local rule = self.draft.rules[index]
        local shown = visual and rule ~= nil
        local between, boolean = false, false
        local clear = false
        local top = ROWS_TOP + ROW_HEIGHT * (index - 1)
        if self.pickerIndex ~= nil and index > self.pickerIndex then top = top + pickerHeight end
        for _, control in ipairs({ slot.fieldBox, slot.operatorBox, slot.valueField, slot.minField,
            slot.andText, slot.maxField, slot.removeButton, slot.clearButton }) do
            local node = control.root or control
            node:SetPos(node.x, top)
        end
        if rule ~= nil then
            local field = QueryBuilder.FieldOf(rule.field)
            local fieldIndex = choiceID(self.fields, rule.field)
            local operatorKind = QueryBuilder.OperatorKind(rule.field)
            local operatorIndex = choiceID(self.operators[operatorKind], rule.operator)
            slot.fieldBox:Select(fieldIndex, false)
            if slot.kind ~= operatorKind then
                slot.operatorBox:SetEntries(entriesOf(self.operators[operatorKind]), operatorIndex)
                slot.kind = operatorKind
            else
                slot.operatorBox:Select(operatorIndex, false)
            end
            between = rule.operator == "between"
            boolean = field.kind == "boolean"
            clear = field.catalog and field.kind == "text" and rule.value ~= ""
            if slot.valueField:GetText() ~= rule.value then slot.valueField:SetText(rule.value) end
            slot.valueField:SetPlaceholder(field.kind == "text"
                and (field.catalog and "Choose a value" or "Words in the name") or "Number")
            slot.valueField.root:SetSize(VALUE_WIDTH, CONTROL_HEIGHT)
            slot.valueField.root.contentMargin = ui.Margin.new(8, 3, clear and 32 or 8, 0)
            slot.minField:SetText(rule.min)
            slot.maxField:SetText(rule.max)
            slot.removeButton:SetDisabled(count <= 1)
        end
        setHidden(slot.fieldBox, not shown)
        setHidden(slot.operatorBox, not shown)
        setHidden(slot.valueField, not shown or between or boolean)
        setHidden(slot.minField, not shown or not between)
        setHidden(slot.andText, not shown or not between)
        setHidden(slot.maxField, not shown or not between)
        setHidden(slot.removeButton, not shown)
        setHidden(slot.clearButton, not shown or not clear)
    end
    self.addButton:SetDisabled(count >= QueryBuilder.MAX_RULES)
    local addTop = ROWS_TOP + ROW_HEIGHT * count + pickerHeight + 4
    self.addButton.root:SetPos(MARGIN, addTop)
    self.preview:SetPos(MARGIN, addTop + 40)
    self.body:SetContentHeight(visual and addTop + 80 or PANEL_TOP + 22 + QUERY_FIELD_HEIGHT + 30)
    self.syncing = false
end

-- Refresh the preview after a condition changed
function QueryEditor:Changed()
    if not self.ready then return end
    self:ClearStatus()
    local query = QueryBuilder.Build(self.draft)
    self.preview.content = query or ""
    self.preview.rgba = query ~= nil and PREVIEW_COLOUR or HINT_COLOUR
end

-- Show the current query length and its supported limit
function QueryEditor:UpdateCharacterCount(value)
    if not self.ready then return end
    if self.characterCount == nil then return end
    self.characterCount.content = tostring(#tostring(value or ""))
        .. " / " .. tostring(QueryStore.MAX_QUERY_LENGTH)
end

-- Show validation feedback, hiding the message when it is empty
function QueryEditor:SetStatus(value)
    self.status.content = tostring(value or "")
    self.status.hidden = value == nil or value == ""
end

-- Hide feedback once the player changes something
-- A blocked save keeps its reason shown
function QueryEditor:ClearStatus()
    if not self.ready then return end
    if self.status == nil or self.blocked ~= nil then return end
    self.confirmVisual = false
    self.status.hidden = true
end

-- Send the name, query, and conditions to save, closing on success
-- Advanced text keeps the conditions only while it is what they gave
function QueryEditor:Save()
    if not self.ready then return end
    if self.onSave == nil or self.blocked ~= nil then return end
    local query, builder
    if self.mode == "visual" then
        local reason
        query, builder, reason = QueryBuilder.Build(self.draft)
        if query == nil then
            self:SetStatus(reason)
            return
        end
    else
        query = self.queryField:GetText()
        builder = query == self.generated and self.generatedBuilder or nil
    end
    local saved, reason = self.onSave(self.queryID, self.nameField:GetText(), query, builder)
    if saved then
        self.window:Close()
    else
        self:SetStatus(reason or "Could not save the RuneQL query.")
    end
end

-- Show the existing editor window
function QueryEditor:Show()
    if not self.ready then return end
    self.window:Show()
end

-- Destroy the editor's controls and window
function QueryEditor:Destroy()
    if self.destroyed then return end
    self.destroyed, self.ready = true, false
    for index = #self.owned, 1, -1 do
        local control = self.owned[index]
        pcall(function() control:Destroy() end)
    end
    local window = self.window
    self.owned, self.visualControls, self.advancedControls, self.slots = {}, {}, {}, {}
    self.window, self.onSave, self.catalog = nil, nil, nil
    self.pickerButtons, self.pickerValues = {}, {}
    if window ~= nil then pcall(function() window:Destroy() end) end
end

return QueryEditor
