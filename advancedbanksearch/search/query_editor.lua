-- Edit saved query names and expressions
-- Queries are built from visual conditions or typed as RuneQL in Advanced

local QueryBuilder = require("advancedbanksearch/search/query_builder")
local QueryStore = require("advancedbanksearch/search/query_store")

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
local STATUS_TOP = 462
local BUTTONS_TOP = 486
-- Columns of a condition row
local FIELD_WIDTH = 140
local OPERATOR_X = MARGIN + 146
local OPERATOR_WIDTH = 136
local VALUE_X = MARGIN + 288
local VALUE_WIDTH = 210
local BOUND_WIDTH = 92
local REMOVE_X = MARGIN + 504
local REMOVE_WIDTH = CONTENT_WIDTH - 504
-- Combo box entries need whole-number IDs
local MATCH_ENTRIES = { { id = 1, label = "all conditions (AND)" }, { id = 2, label = "any condition (OR)" } }
local MATCH_KEYS = { "all", "any" }
local HINT = "Names match whole words in any case, so \"bone\" does not find \"bones\". Prices are per item "
    .. "from GE Prices; items without a price never match. Numbers can use k, m, or b, like 1.5m."
local LEAVE_TEXT = "Visual conditions replace this RuneQL. Press Visual again to use them."
local INCOMPLETE = "The conditions are incomplete, so the RuneQL text was not changed."

-- Trim spaces from user text
local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

-- List combo entries with whole-number IDs
local function entriesOf(choices)
    local entries = {}
    for index, choice in ipairs(choices) do entries[index] = { id = index, label = choice.label } end
    return entries
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
    local self = setmetatable({
        queryID = record.id,
        onSave = options.onSave,
        -- Why saving is blocked, kept while the player types
        blocked = options.blocked,
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
    local builder = QueryBuilder.Trusted(record.builder, record.query)
    if builder ~= nil then
        self.mode = "visual"
        self.generated, self.generatedBuilder = record.query, builder
    else
        self.mode = record.id ~= nil and "advanced" or "visual"
    end
    self.draft = QueryBuilder.Draft(builder)

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
        onClose = options.onClose,
    })
    self.content = self.window.content

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
        placeholder = "Query name",
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

    self.status = self:Own(prettyui.Text.new(self.content, {
        text = "",
        x = MARGIN,
        y = STATUS_TOP,
        width = CONTENT_WIDTH,
        height = 18,
        colour = ERROR_COLOUR,
        font = SMALL_FONT,
        maxLines = 1,
    }))
    self.status.hidden = true

    local buttonWidth = math.floor((CONTENT_WIDTH - BUTTON_GAP) / 2)
    self.cancelButton = self:Own(prettyui.SimpleButton.new(self.content, "Cancel", function()
        self.window:Close()
    end, {
        x = MARGIN,
        y = BUTTONS_TOP,
        width = buttonWidth,
        height = CONTROL_HEIGHT,
    }))
    self.saveButton = self:Own(prettyui.SimpleButton.new(self.content, "Save", function()
        self:Save()
    end, {
        x = MARGIN + buttonWidth + BUTTON_GAP,
        y = BUTTONS_TOP,
        width = CONTENT_WIDTH - buttonWidth - BUTTON_GAP,
        height = CONTROL_HEIGHT,
    }))

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
        entries = MATCH_ENTRIES,
        selectedID = self.draft.match == "any" and 2 or 1,
        onChange = function(_, entryID)
            self.draft.match = MATCH_KEYS[entryID] or "all"
            self:Changed()
        end,
    }), group)

    for index = 1, QueryBuilder.MAX_RULES do self.slots[index] = self:BuildRow(index) end

    local addTop = ROWS_TOP + ROW_HEIGHT * QueryBuilder.MAX_RULES + 4
    self.addButton = self:Own(prettyui.SimpleButton.new(content, "Add condition", function()
        self:AddRule()
    end, { x = MARGIN, y = addTop, width = 140, height = CONTROL_HEIGHT }), group)
    self:Own(prettyui.Text.new(content, {
        text = "Up to 6 conditions. Use Advanced for NOT, groups, or fuzzy words.",
        x = MARGIN + 150,
        y = addTop,
        width = CONTENT_WIDTH - 150,
        height = CONTROL_HEIGHT,
        colour = HINT_COLOUR,
        font = SMALL_FONT,
        maxLines = 1,
        alignVertical = ui.AlignMode.CENTRE,
    }), group)
    self:Own(prettyui.Text.new(content, {
        text = HINT,
        x = MARGIN,
        y = addTop + 36,
        width = CONTENT_WIDTH,
        height = 34,
        colour = HINT_COLOUR,
        font = SMALL_FONT,
        maxLines = 2,
        alignVertical = ui.AlignMode.TOPLEFT,
    }), group)
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
end

-- Create one condition row's controls, shown when it has a condition
function QueryEditor:BuildRow(index)
    local content = self.content
    local top = ROWS_TOP + ROW_HEIGHT * (index - 1)
    local slot = { kind = nil }
    -- Change this row's condition and refresh the preview
    local function edit(key, value)
        local rule = self.draft.rules[index]
        if rule == nil then return end
        rule[key] = value
        self:Changed()
    end
    slot.fieldBox = self:Own(prettyui.ComboBox.new(content, {
        x = MARGIN,
        y = top,
        width = FIELD_WIDTH,
        height = CONTROL_HEIGHT,
        entries = entriesOf(QueryBuilder.FIELDS),
        selectedID = 1,
        onChange = function(_, entryID) self:ChooseField(index, entryID) end,
    }))
    slot.operatorBox = self:Own(prettyui.ComboBox.new(content, {
        x = OPERATOR_X,
        y = top,
        width = OPERATOR_WIDTH,
        height = CONTROL_HEIGHT,
        entries = entriesOf(QueryBuilder.OPERATORS.text),
        selectedID = 1,
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
    slot.minField = self:Own(prettyui.TextField.new(content, {
        x = VALUE_X,
        y = top,
        width = BOUND_WIDTH,
        height = CONTROL_HEIGHT,
        maxLength = 16,
        placeholder = "From",
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
        placeholder = "To",
        onChange = function(_, _, value) edit("max", value) end,
    }))
    slot.removeButton = self:Own(prettyui.SimpleButton.new(content, "Remove", function()
        self:RemoveRule(index)
    end, { x = REMOVE_X, y = top, width = REMOVE_WIDTH, height = CONTROL_HEIGHT }))
    return slot
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
    if #self.draft.rules >= QueryBuilder.MAX_RULES then return end
    self.draft.rules[#self.draft.rules + 1] = QueryBuilder.NewRule()
    self:SyncRows()
    self:Changed()
end

-- Remove a condition, keeping at least one
function QueryEditor:RemoveRule(index)
    if #self.draft.rules <= 1 or self.draft.rules[index] == nil then return end
    table.remove(self.draft.rules, index)
    self:SyncRows()
    self:Changed()
end

-- Change a condition's field, starting over when its kind changes
function QueryEditor:ChooseField(index, entryID)
    if self.syncing then return end
    local rule, field = self.draft.rules[index], QueryBuilder.FIELDS[entryID]
    if rule == nil or field == nil or field.key == rule.field then return end
    local before = QueryBuilder.FieldOf(rule.field)
    if before == nil or before.kind ~= field.kind then
        self.draft.rules[index] = QueryBuilder.NewRule(field.key)
    else
        rule.field = field.key
    end
    self:SyncRows()
    self:Changed()
end

-- Change how a condition compares its value
function QueryEditor:ChooseOperator(index, entryID)
    local rule = self.draft.rules[index]
    if self.syncing or rule == nil then return end
    local operator = QueryBuilder.OPERATORS[QueryBuilder.FieldOf(rule.field).kind][entryID]
    if operator == nil or operator.key == rule.operator then return end
    rule.operator = operator.key
    self:SyncRows()
    self:Changed()
end

-- Show each row's condition, hiding rows without one
-- Combo boxes may report their own changes here, so those are ignored
function QueryEditor:SyncRows()
    local visual = self.mode == "visual"
    local count = #self.draft.rules
    self.syncing = true
    for index, slot in ipairs(self.slots) do
        local rule = self.draft.rules[index]
        local shown = visual and rule ~= nil
        local between = false
        if rule ~= nil then
            local field, fieldIndex = QueryBuilder.FieldOf(rule.field)
            local _, operatorIndex = QueryBuilder.OperatorOf(field.kind, rule.operator)
            slot.fieldBox:Select(fieldIndex, false)
            if slot.kind ~= field.kind then
                slot.operatorBox:SetEntries(entriesOf(QueryBuilder.OPERATORS[field.kind]), operatorIndex)
                slot.kind = field.kind
            else
                slot.operatorBox:Select(operatorIndex, false)
            end
            between = rule.operator == "between"
            slot.valueField:SetText(rule.value)
            slot.valueField:SetPlaceholder(field.kind == "text" and "Words in the name" or "Number")
            slot.minField:SetText(rule.min)
            slot.maxField:SetText(rule.max)
            slot.removeButton:SetDisabled(count <= 1)
        end
        setHidden(slot.fieldBox, not shown)
        setHidden(slot.operatorBox, not shown)
        setHidden(slot.valueField, not shown or between)
        setHidden(slot.minField, not shown or not between)
        setHidden(slot.andText, not shown or not between)
        setHidden(slot.maxField, not shown or not between)
        setHidden(slot.removeButton, not shown)
    end
    self.syncing = false
    self.addButton:SetDisabled(count >= QueryBuilder.MAX_RULES)
end

-- Refresh the preview after a condition changed
function QueryEditor:Changed()
    self:ClearStatus()
    local query, _, reason = QueryBuilder.Build(self.draft)
    self.preview.content = query ~= nil and ("RuneQL: " .. query) or reason
    self.preview.rgba = query ~= nil and PREVIEW_COLOUR or HINT_COLOUR
end

-- Show the current query length and its supported limit
function QueryEditor:UpdateCharacterCount(value)
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
    if self.status == nil or self.blocked ~= nil then return end
    self.confirmVisual = false
    self.status.hidden = true
end

-- Send the name, query, and conditions to save, closing on success
-- Advanced text keeps the conditions only while it is what they gave
function QueryEditor:Save()
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
    self.window:Show()
end

-- Destroy the editor's controls and window
function QueryEditor:Destroy()
    for index = #self.owned, 1, -1 do
        local control = self.owned[index]
        pcall(function() control:Destroy() end)
    end
    local window = self.window
    self.owned, self.visualControls, self.advancedControls, self.slots = {}, {}, {}, {}
    self.window, self.onSave = nil, nil
    if window ~= nil then pcall(function() window:Destroy() end) end
end

return QueryEditor
