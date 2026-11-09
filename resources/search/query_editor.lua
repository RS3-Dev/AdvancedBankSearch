-- Edit saved query names and expressions
-- Queries are built from visual conditions or typed as RuneQL in Advanced

local QueryBuilder = require("resources/search/query_builder")
local QueryStore = require("resources/search/query_store")
local ObjectConfig = require("resources/search/object_config")
local ItemIdentity = require("resources/search/item_identity")

local QueryEditor = {}
QueryEditor.__index = QueryEditor

local MARGIN = 8
local SCROLLBAR_WIDTH = 18
local GROUP_PADDING = 6
local GROUP_GAP = 8
local BUTTON_GAP = 8
local CONTROL_HEIGHT = 28
local LABEL_COLOUR = 0xF2C66DFF
local HINT_COLOUR = 0x9F947BFF
local PREVIEW_COLOUR = 0xE7D7B0FF
local ERROR_COLOUR = 0xE57373FF
local SMALL_FONT = id.Font.MUSEO_SANS_11PT_REGULAR
-- Where the mode panels start, and the rows of conditions
local PANEL_TOP = 74
local ROWS_TOP = 110
local QUERY_FIELD_HEIGHT = 288
local FOOTER_PADDING = 4
local FOOTER_HEIGHT = CONTROL_HEIGHT + FOOTER_PADDING * 2
local STATUS_HEIGHT = 22
local BUTTONS_TOP = FOOTER_PADDING
local MATCH_CHOICES = { { key = "all", label = "all conditions (AND)" }, { key = "any", label = "any condition (OR)" } }
local PICKER_PAGE_SIZE = 24
local PICKER_ROW_HEIGHT = 28
local REPLACE_TEXT = "Saving visual conditions will replace the advanced query."
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
        onClose = options.onClose,
        onChooseSprite = options.onChooseSprite,
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
        groupSlots = {},
        -- The RuneQL last built from the conditions and their saved form
        -- Advanced keeps the conditions only while its text is this
        generated = nil,
        generatedBuilder = nil,
    }, QueryEditor)
    if builder ~= nil then self.generated, self.generatedBuilder = record.query, builder end
    self.mode = options.editorMode == "advanced" and "advanced"
        or record.id ~= nil and builder == nil and "advanced" or "visual"
    self.draft = QueryBuilder.Draft(builder)

    for kind, choices in pairs(QueryBuilder.OPERATORS) do
        local positive = {}
        for _, choice in ipairs(choices) do
            if choice.key ~= "not_equals" and choice.key ~= "excludes" then positive[#positive + 1] = choice end
        end
        self.operators[kind] = sortedChoices(positive)
    end
    local state = options.state
    if state ~= nil then
        self.draft, self.mode = state.draft, state.mode
        self.generated, self.generatedBuilder = state.generated, state.generatedBuilder
        self.pickerIndex, self.pickerPage, self.pickerValues = state.pickerIndex, state.pickerPage, state.pickerValues
        self.preservedAdvanced, self.visualBaseline = state.preservedAdvanced, state.visualBaseline
    end
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
    self.nameText = options.state and options.state.name or record.name or ""
    self.queryText = options.state and options.state.query or record.query or ""
    self.spriteObjectID = options.state and options.state.spriteObjectID or ItemIdentity.ObjectID(record.icon)
    self.width = math.max(1, options.width or parent.width)
    self.contentWidth = math.max(1, self.width - MARGIN * 2 - SCROLLBAR_WIDTH)
    self.narrow = self.contentWidth < 600
    self.rowHeight = self.narrow and 68 or 34
    self.fieldWidth = self.narrow and math.floor((self.contentWidth - 76) * 0.48) or 140
    self.operatorX = MARGIN + self.fieldWidth + 6
    self.operatorWidth = self.narrow and self.contentWidth - self.fieldWidth - 76 or 136
    self.negateX = self.operatorX + self.operatorWidth + 6
    self.valueX = self.narrow and MARGIN or self.negateX + 34
    -- On two-line rows the value has the whole second line; its trash is above it.
    self.valueWidth = self.narrow and self.contentWidth or self.contentWidth - (self.valueX - MARGIN) - 34
    self.boundWidth = math.floor((self.valueWidth - 28) / 2)
    self.pickerColumns = math.max(1, math.min(4, math.floor(self.contentWidth / 110)))
    self.root = ui.Layer.new(parent)
    self.root:SetSize(self.width, options.height or parent.height)
    local overlay = options.overlay or parent
    prettyui.Tooltip.registerContext(self.root, overlay, function(target)
        local function position(node)
            local x, y = 0, 0
            while node ~= nil do
                x, y = x + (node.x or 0), y + (node.y or 0)
                node = node.parent
            end
            return x, y
        end
        local x, y = position(target)
        local ox, oy = position(overlay)
        return x - ox, y - oy
    end)
    self.body = self:Own(prettyui.SimpleView.new(self.root, {
        y = 0,
        width = 0, widthAnchor = 1.0,
        height = -FOOTER_HEIGHT, heightAnchor = 1.0,
        scrollable = true,
    }))
    self.content = self.body.content
    local footer = { root = ui.Layer.new(self.root) }
    function footer:Destroy() self.root:Destroy() end
    self.footer = self:Own(footer)
    footer.root:SetPos(0, -FOOTER_HEIGHT, 0, 1.0)
    footer.root:SetSize(0, FOOTER_HEIGHT, 1.0, 0)

    self.nameLabel = self:Own(prettyui.Text.new(self.content, {
        text = "Query name",
        x = MARGIN,
        y = 6,
        width = self.contentWidth,
        height = 20,
        colour = LABEL_COLOUR,
        font = id.Font.CINZEL_13PT_BOLD,
    }))
    self.nameField = self:Own(prettyui.TextField.new(self.content, {
        x = MARGIN,
        y = 27,
        width = self.contentWidth - 48,
        height = 30,
        text = self.nameText,
        placeholder = "Search name",
        maxLength = QueryStore.MAX_NAME_LENGTH,
        onChange = function(_, _, value)
            if not self.ready then return end
            self.nameText = tostring(value or "")
            self:ClearStatus()
        end,
    }))
    self.spriteSlot = self:Own(prettyui.ItemSlot.new(self.content, ObjectConfig.FromID(self.spriteObjectID), {
        x = MARGIN + self.contentWidth - 40, y = 22, clickthrough = false, tooltip = "Click to edit",
    }))
    self.spriteSlot.root:Subscribe(ui.Hook.ONCLICK, function()
        if self.ready and self.onChooseSprite ~= nil then self.onChooseSprite(self) end
        return false
    end)
    self:BuildVisual()
    self:BuildAdvanced(self.queryText)

    self.status = self:Own(prettyui.Text.new(self.footer.root, {
        text = "",
        x = MARGIN,
        y = 4,
        width = self.contentWidth,
        height = 18,
        colour = ERROR_COLOUR,
        font = SMALL_FONT,
        maxLines = 1,
    }))
    self.status.hidden = true

    local buttonWidth = math.floor((self.contentWidth - BUTTON_GAP) / 2)
    self.cancelButton = self:Own(prettyui.SimpleButton.new(self.footer.root, "Cancel", function()
        self:Close(false)
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
        width = self.contentWidth - buttonWidth - BUTTON_GAP,
        height = CONTROL_HEIGHT,
    }))

    self.ready = true
    self:ShowMode(self.mode)
    self:Changed()
    if self.blocked ~= nil then
        self.saveButton:SetDisabled(true)
        self:SetStatus(self.blocked)
    end
    if options.state ~= nil then
        self:SetStatus(options.state.status)
        if self.body.SetScrollPosition then self.body:SetScrollPosition(options.state.scrollY) end
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
        width = math.min(220, self.contentWidth - 130),
        height = CONTROL_HEIGHT,
        entries = entriesOf(MATCH_CHOICES),
        selectedID = self.draft.match == "any" and 2 or 1,
        onChange = function(_, entryID)
            if not self.ready or self.syncing then return end
            self.draft.match = MATCH_CHOICES[entryID] and MATCH_CHOICES[entryID].key or "all"
            self:Changed()
        end,
    }), group)

    -- Draw group surfaces before condition controls so their contents stay above them.
    for index = 1, QueryBuilder.MAX_RULES do self.groupSlots[index] = self:BuildGroupRow(index) end
    for index = 1, QueryBuilder.MAX_RULES do self.slots[index] = self:BuildRow(index) end

    local addLeft = MARGIN + 56 + math.min(220, self.contentWidth - 130) + 6
    self.addButton = self:Own(prettyui.SimpleButton.new(content, id.Sprite.BP3_MISSION_PLUS_ICON, function()
        self:AddRule()
    end, { x = addLeft, y = PANEL_TOP, width = CONTROL_HEIGHT, height = CONTROL_HEIGHT,
        iconSize = 18, tooltip = "Add condition to the query, outside groups" }), group)
    self.addGroupButton = self:Own(prettyui.SimpleButton.new(content, id.Sprite.MTX_STORE_BTN_PLUS_ACTIVE, function()
        self:AddGroup(self.draft, 0)
    end, { x = addLeft + 34, y = PANEL_TOP, width = CONTROL_HEIGHT, height = CONTROL_HEIGHT,
        iconSize = 18, tooltip = "Add group to the query" }), group)
    self.preview = self:Own(prettyui.Text.new(content, {
        text = "",
        x = MARGIN,
        y = ROWS_TOP,
        width = self.contentWidth,
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
    local top = ROWS_TOP + self.rowHeight * (index - 1)
    local slot = { kind = nil }
    -- Change this row's condition and refresh the preview
    local function edit(key, value)
        if not self.ready or self.syncing then return end
        local rule = self:Rule(index)
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
        width = self.fieldWidth,
        height = CONTROL_HEIGHT,
        entries = entriesOf(self.fields),
        selectedID = choiceID(self.fields, "name"),
        onChange = function(_, entryID) self:ChooseField(index, entryID) end,
    }))
    slot.operatorBox = self:Own(prettyui.ComboBox.new(content, {
        x = self.operatorX,
        y = top,
        width = self.operatorWidth,
        height = CONTROL_HEIGHT,
        entries = entriesOf(self.operators.text),
        selectedID = choiceID(self.operators.text, "phrase"),
        onChange = function(_, entryID) self:ChooseOperator(index, entryID) end,
    }))
    slot.negateButton = self:Own(prettyui.SimpleButton.new(content, id.Sprite.EXCLAMATION_MARK, function()
        if not self.ready then return end
        local rule = self:Rule(index)
        if rule == nil then return end
        rule.negate = not rule.negate
        self:SyncRows()
        self:Changed()
    end, { x = self.negateX, y = top, width = CONTROL_HEIGHT, height = CONTROL_HEIGHT,
        iconWidth = 10, iconHeight = 20,
        tooltip = "Exclude this condition (NOT). Items without this field are excluded too." }))
    slot.kind = "text"
    slot.valueField = self:Own(prettyui.TextField.new(content, {
        x = self.valueX,
        y = top,
        width = self.valueWidth,
        height = CONTROL_HEIGHT,
        maxLength = QueryBuilder.MAX_TEXT_LENGTH,
        onChange = function(_, _, value) edit("value", value) end,
    }))
    slot.valueField.root:Subscribe(ui.Hook.ONCLICK, "advancedbanksearch_value_picker", function()
        if not self.ready or self.syncing then return false end
        local rule = self:Rule(index)
        local field = rule and QueryBuilder.FieldOf(rule.field)
        if field and field.catalog and field.kind == "text" and trim(rule.value) == "" then
            self:OpenPicker(index, "")
        end
        return false
    end)
    local clear = self:Own({ root = ui.Layer.new(content) })
    clear.root:SetPos(self.valueX + self.valueWidth - 26, top)
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
        x = self.valueX,
        y = top,
        width = self.boundWidth,
        height = CONTROL_HEIGHT,
        maxLength = 16,
        placeholder = "Low",
        onChange = function(_, _, value) edit("min", value) end,
    }))
    slot.andText = self:Own(prettyui.Text.new(content, {
        text = "and",
        x = self.valueX + self.boundWidth,
        y = top,
        width = self.valueWidth - self.boundWidth * 2,
        height = CONTROL_HEIGHT,
        colour = HINT_COLOUR,
        font = SMALL_FONT,
        maxLines = 1,
        alignHorizontal = ui.AlignMode.CENTRE,
        alignVertical = ui.AlignMode.CENTRE,
    }))
    slot.maxField = self:Own(prettyui.TextField.new(content, {
        x = self.valueX + self.valueWidth - self.boundWidth,
        y = top,
        width = self.boundWidth,
        height = CONTROL_HEIGHT,
        maxLength = 16,
        placeholder = "High",
        onChange = function(_, _, value) edit("max", value) end,
    }))
    slot.removeButton = self:Own(prettyui.SimpleButton.new(content, id.Sprite.HUD_COMBAT_BTN_BIN, function()
        self:RemoveRule(index)
    end, { x = MARGIN + self.contentWidth - CONTROL_HEIGHT, y = top, width = CONTROL_HEIGHT, height = CONTROL_HEIGHT, tooltip = "Remove condition" }))
    return slot
end

-- Create a reusable grid for catalog choices
function QueryEditor:BuildPicker()
    local width = math.floor((self.contentWidth - 18) / self.pickerColumns)
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
    local rule = self:Rule(index)
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
    local rule = self.pickerIndex and self:Rule(self.pickerIndex)
    if value == nil or rule == nil then return end
    rule.value = tostring(value.value)
    self.pickerIndex = nil
    self:SyncRows()
    self:Changed()
end

-- Position the visible page of catalog choices
function QueryEditor:LayoutPicker(top, shown)
    local offset = (self.pickerPage - 1) * PICKER_PAGE_SIZE
    local width = math.floor((self.contentWidth - 18) / self.pickerColumns)
    local count = math.min(PICKER_PAGE_SIZE, #self.pickerValues - offset)
    local rows = math.ceil(math.max(0, count) / self.pickerColumns)
    for index, button in ipairs(self.pickerButtons) do
        local value = self.pickerValues[offset + index]
        -- Hiding a hovered button does not deliver mouse-leave in the client.
        -- Remove the overlay attachment before hiding or repurposing the button.
        button:SetTooltip(nil)
        setHidden(button, not shown or value == nil)
        if value ~= nil then
            button.content.content = value.label
            if shown then button:SetTooltip(value.label) end
            button.root:SetPos(MARGIN + ((index - 1) % self.pickerColumns) * (width + 6),
                top + math.floor((index - 1) / self.pickerColumns) * PICKER_ROW_HEIGHT)
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
        width = self.contentWidth - 82,
        height = 20,
        colour = HINT_COLOUR,
        font = SMALL_FONT,
        maxLines = 1,
        alignVertical = ui.AlignMode.CENTRE,
    }), group)
    self.queryField = self:Own(prettyui.TextField.new(content, {
        x = MARGIN,
        y = PANEL_TOP + 22,
        width = self.contentWidth,
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
            if not self.ready then return end
            self.queryText = tostring(value or "")
            self:UpdateCharacterCount(value)
            self:ClearStatus()
        end,
    }), group)
    self.characterCount = self:Own(prettyui.Text.new(content, {
        text = "",
        x = MARGIN,
        y = PANEL_TOP + 22 + QUERY_FIELD_HEIGHT + 6,
        width = self.contentWidth,
        height = 18,
        colour = HINT_COLOUR,
        font = SMALL_FONT,
        maxLines = 1,
        alignHorizontal = ui.AlignMode.BOTTOMRIGHT,
    }), group)
    self:UpdateCharacterCount(query)
end

-- Show the mode selected through the plugin settings.
function QueryEditor:ShowMode(mode)
    if not self.ready then return end
    self.mode = mode
    for _, control in ipairs(self.visualControls) do setHidden(control, mode ~= "visual") end
    for _, control in ipairs(self.advancedControls) do setHidden(control, mode ~= "advanced") end
    self:SyncRows()
end

-- Switch to Advanced with the RuneQL the conditions give
-- Incomplete conditions leave the typed text as it was
function QueryEditor:ChooseAdvanced()
    if not self.ready or self.mode == "advanced" then return end
    local query, builder = QueryBuilder.Build(self.draft)
    self:ShowMode("advanced")
    if self.preservedAdvanced ~= nil and query == self.visualBaseline then
        self.queryText = self.preservedAdvanced
    elseif query ~= nil then
        self.generated, self.generatedBuilder = query, builder
        self.queryText = query
        self.preservedAdvanced, self.visualBaseline = nil, nil
    end
    self.queryField:SetText(self.queryText)
    self:UpdateCharacterCount(self.queryText)
    if query == nil then self:SetStatus(INCOMPLETE) else self:ClearStatus() end
end

-- Selecting Visual is explicit in settings. Retain detached Advanced text until
-- Save, or return to it when switching back without changing visual conditions.
function QueryEditor:ChooseVisual()
    if not self.ready or self.mode == "visual" then return end
    local text = self.queryField:GetText()
    local detached = trim(text) ~= "" and text ~= self.generated
    if detached then
        self.preservedAdvanced = text
        self.visualBaseline = QueryBuilder.Build(self.draft)
    end
    self:ShowMode("visual")
    self:Changed()
    if detached then self:SetStatus(REPLACE_TEXT) end
end

-- Resolve a displayed condition back to its nested group.
function QueryEditor:Rule(index)
    local row = self.ruleRows and self.ruleRows[index]
    return row and row.rule
end

-- Add a condition to the chosen group (the root by default).
function QueryEditor:AddRule(group)
    if not self.ready or #self.ruleRows >= QueryBuilder.MAX_RULES then return end
    group = group or self.draft
    group.rules[#group.rules + 1] = QueryBuilder.NewRule()
    self.pickerIndex = nil
    self:SyncRows()
    self:Changed()
end

function QueryEditor:AddGroup(group, depth)
    if not self.ready or #self.ruleRows >= QueryBuilder.MAX_RULES
        or #self.groupRows >= QueryBuilder.MAX_RULES or depth >= 3 then return end
    group.rules[#group.rules + 1] = { match = "any", rules = { QueryBuilder.NewRule() } }
    self.pickerIndex = nil
    self:SyncRows()
    self:Changed()
end

-- Keep at least one condition in the query. Empty groups can be filled or removed.
function QueryEditor:RemoveRule(index)
    local row = self.ruleRows[index]
    if not self.ready or #self.ruleRows <= 1 or row == nil then return end
    table.remove(row.siblings, row.position)
    self.pickerIndex = nil
    self:SyncRows()
    self:Changed()
end

function QueryEditor:RemoveGroup(index)
    local row = self.groupRows[index]
    if not self.ready or row == nil then return end
    table.remove(row.siblings, row.position)
    local _, conditions = QueryBuilder.Rows(self.draft)
    if #conditions == 0 then self.draft.rules[#self.draft.rules + 1] = QueryBuilder.NewRule() end
    self.pickerIndex = nil
    self:SyncRows()
    self:Changed()
end

-- A group's actions stay together in its header, inside a visible group boundary.
function QueryEditor:BuildGroupRow(index)
    local slot = {}
    local function rectangle(colour)
        local control = self:Own({ root = ui.Rectangle.new(self.content) })
        function control:Destroy() self.root:Destroy() end
        control.root.fill, control.root.rgba, control.root.clickthrough = true, colour, true
        return control
    end
    slot.background = rectangle(0x27231DFF)
    slot.topEdge = rectangle(0x806432FF)
    slot.bottomEdge = rectangle(0x806432FF)
    slot.rightEdge = rectangle(0x806432FF)
    slot.edge = rectangle(0x806432FF)
    slot.matchBox = self:Own(prettyui.ComboBox.new(self.content, {
        width = 206, height = CONTROL_HEIGHT, entries = entriesOf(MATCH_CHOICES), selectedID = 2,
        onChange = function(_, entryID)
            if not self.ready or self.syncing then return end
            local row = self.groupRows[index]
            if row == nil then return end
            row.rule.match = MATCH_CHOICES[entryID] and MATCH_CHOICES[entryID].key or "all"
            self:Changed()
        end,
    }))
    slot.addButton = self:Own(prettyui.SimpleButton.new(self.content, id.Sprite.BP3_MISSION_PLUS_ICON, function()
        local row = self.groupRows[index]
        if row ~= nil then self:AddRule(row.rule) end
    end, { width = CONTROL_HEIGHT, height = CONTROL_HEIGHT, iconSize = 18, tooltip = "Add condition to this group" }))
    slot.groupButton = self:Own(prettyui.SimpleButton.new(self.content, id.Sprite.MTX_STORE_BTN_PLUS_ACTIVE, function()
        local row = self.groupRows[index]
        if row ~= nil then self:AddGroup(row.rule, row.depth + 1) end
    end, { width = CONTROL_HEIGHT, height = CONTROL_HEIGHT, iconSize = 18, tooltip = "Add subgroup" }))
    slot.removeButton = self:Own(prettyui.SimpleButton.new(self.content, id.Sprite.HUD_COMBAT_BTN_BIN, function()
        self:RemoveGroup(index)
    end, { width = 28, height = CONTROL_HEIGHT, tooltip = "Remove group and its conditions" }))
    return slot
end

-- Change a condition's field, starting over when its kind changes
function QueryEditor:ChooseField(index, entryID)
    if not self.ready then return end
    local rule, field = self:Rule(index), self.fields[entryID]
    if rule == nil or field == nil or field.key == rule.field then return end
    local before = QueryBuilder.FieldOf(rule.field)
    if before == nil or before.kind ~= field.kind or field.catalog or before.catalog then
        local row = self.ruleRows[index]
        row.siblings[row.position] = QueryBuilder.NewRule(field.key)
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
    local rule = self:Rule(index)
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
    if not self.ready or self.syncing then return end
    self.syncing = true
    prettyui.Tooltip.hideContextTooltips(self.root)
    local visual = self.mode == "visual"
    local rows
    rows, self.ruleRows, self.groupRows = QueryBuilder.Rows(self.draft)
    local count = #self.ruleRows
    local top, pickerTop, openGroups = ROWS_TOP, ROWS_TOP, {}
    local function closeGroup()
        local row = table.remove(openGroups)
        row.bottom = top + GROUP_PADDING
        top = row.bottom + GROUP_GAP
    end
    for _, row in ipairs(rows) do
        -- Leave a visible closing border and gap before the next sibling.
        while #openGroups > 0 and openGroups[#openGroups].depth >= row.depth do closeGroup() end
        row.top = top
        if row.groupIndex ~= nil then
            row.top = top + GROUP_PADDING
            row.boxTop = top
            top = row.top + 34
            openGroups[#openGroups + 1] = row
        else
            top = top + self.rowHeight
            if self.pickerIndex == row.conditionIndex then
                pickerTop = top
                top = top + self:LayoutPicker(pickerTop, visual)
            end
        end
    end
    while #openGroups > 0 do closeGroup() end
    if self.pickerIndex == nil then self:LayoutPicker(pickerTop, false) end
    for index, slot in ipairs(self.slots) do
        local row = self.ruleRows[index]
        local rule = row and row.rule
        local shown = visual and rule ~= nil
        local between, boolean, clear = false, false, false
        local rowTop = row and row.top or ROWS_TOP
        for _, control in ipairs({ slot.fieldBox, slot.operatorBox, slot.valueField, slot.minField,
            slot.andText, slot.maxField, slot.removeButton, slot.clearButton, slot.negateButton }) do
            local node = control.root or control
            local valueControl = control == slot.valueField or control == slot.minField
                or control == slot.maxField or control == slot.andText or control == slot.clearButton
            node:SetPos(node.x, rowTop + (self.narrow and valueControl and 34 or 0))
        end
        if rule ~= nil then
            local indent = row.depth * 12
            slot.fieldBox.root:SetPos(MARGIN + indent, rowTop)
            slot.fieldBox.root:SetSize(self.fieldWidth - indent, CONTROL_HEIGHT)
            local valueLeft = self.valueX + (self.narrow and indent or 0)
            local inset = row.depth > 0 and GROUP_PADDING or 0
            slot.operatorBox.root:SetSize(self.operatorWidth - inset, CONTROL_HEIGHT)
            slot.negateButton.root:SetPos(self.negateX - inset, rowTop)
            slot.removeButton.root:SetPos(MARGIN + self.contentWidth - CONTROL_HEIGHT - inset, rowTop)
            local valueWidth = self.valueWidth - (self.narrow and indent or 0) - inset
            local valueTop = rowTop + (self.narrow and 34 or 0)
            local boundWidth = math.floor((valueWidth - 28) / 2)
            slot.valueField.root:SetPos(valueLeft, valueTop)
            slot.minField.root:SetPos(valueLeft, valueTop)
            slot.minField.root:SetSize(boundWidth, CONTROL_HEIGHT)
            slot.andText:SetPos(valueLeft + boundWidth, valueTop)
            slot.maxField.root:SetPos(valueLeft + valueWidth - boundWidth, valueTop)
            slot.maxField.root:SetSize(boundWidth, CONTROL_HEIGHT)
            slot.clearButton.root:SetPos(valueLeft + valueWidth - 26, valueTop)
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
            slot.valueField.root:SetSize(valueWidth, CONTROL_HEIGHT)
            slot.valueField.root.contentMargin = ui.Margin.new(8, 3, clear and 32 or 8, 0)
            slot.minField:SetText(rule.min)
            slot.maxField:SetText(rule.max)
            slot.removeButton:SetDisabled(count <= 1)
            slot.negateButton:SetActive(rule.negate == true)
        end
        setHidden(slot.fieldBox, not shown)
        setHidden(slot.operatorBox, not shown)
        setHidden(slot.valueField, not shown or between or boolean)
        setHidden(slot.minField, not shown or not between)
        setHidden(slot.andText, not shown or not between)
        setHidden(slot.maxField, not shown or not between)
        setHidden(slot.removeButton, not shown)
        setHidden(slot.negateButton, not shown)
        setHidden(slot.clearButton, not shown or not clear)
    end
    for index, slot in ipairs(self.groupSlots) do
        local row = self.groupRows[index]
        local shown = visual and row ~= nil
        for _, control in pairs(slot) do setHidden(control, not shown) end
        if row ~= nil then
            local left = MARGIN + row.depth * 12 + GROUP_PADDING
            local matchWidth = math.min(206, self.contentWidth - row.depth * 12 - GROUP_PADDING * 2 - 114)
            slot.matchBox.root:SetPos(left, row.top)
            slot.matchBox.root:SetSize(matchWidth, CONTROL_HEIGHT)
            slot.matchBox:Select(row.rule.match == "any" and 2 or 1, false)
            slot.addButton.root:SetPos(left + matchWidth + 6, row.top)
            slot.groupButton.root:SetPos(left + matchWidth + 40, row.top)
            slot.removeButton.root:SetPos(left + matchWidth + 74, row.top)
            slot.addButton:SetDisabled(count >= QueryBuilder.MAX_RULES)
            slot.groupButton:SetDisabled(count >= QueryBuilder.MAX_RULES or #self.groupRows >= QueryBuilder.MAX_RULES
                or row.depth + 1 >= 3)
            local boxLeft, boxTop = left - GROUP_PADDING, row.boxTop
            local boxWidth = self.contentWidth - row.depth * 12
            local boxHeight = row.bottom - boxTop + 1
            slot.background.root:SetPos(boxLeft, boxTop)
            slot.background.root:SetSize(boxWidth, boxHeight)
            slot.topEdge.root:SetPos(boxLeft, boxTop)
            slot.topEdge.root:SetSize(boxWidth, 1)
            slot.bottomEdge.root:SetPos(boxLeft, row.bottom)
            slot.bottomEdge.root:SetSize(boxWidth, 1)
            slot.edge.root:SetPos(boxLeft, boxTop)
            slot.edge.root:SetSize(1, boxHeight)
            slot.rightEdge.root:SetPos(boxLeft + boxWidth - 1, boxTop)
            slot.rightEdge.root:SetSize(1, boxHeight)
        end
    end
    self.addButton:SetDisabled(count >= QueryBuilder.MAX_RULES)
    self.addGroupButton:SetDisabled(count >= QueryBuilder.MAX_RULES or #self.groupRows >= QueryBuilder.MAX_RULES)
    self.preview:SetPos(MARGIN, top + 10)
    self.body:SetContentHeight(visual and top + 50 or PANEL_TOP + 22 + QUERY_FIELD_HEIGHT + 30)
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
    self.statusText = value
    self.status.content = tostring(value or "")
    self.status.hidden = value == nil or value == ""
    -- Reserve feedback space only while there is a message to display.
    local messageHeight = self.status.hidden and 0 or STATUS_HEIGHT
    local height = FOOTER_HEIGHT + messageHeight
    self.footer.root:SetPos(0, -height, 0, 1.0)
    self.footer.root:SetSize(self.width, height)
    self.body.root:SetSize(self.width, math.max(1, self.root.height - height))
    self.cancelButton.root:SetPos(MARGIN, BUTTONS_TOP + messageHeight)
    self.saveButton.root:SetPos(self.saveButton.root.x, BUTTONS_TOP + messageHeight)
end

-- Hide feedback once the player changes something
-- A blocked save keeps its reason shown
function QueryEditor:ClearStatus()
    if not self.ready then return end
    if self.status == nil or self.blocked ~= nil then return end
    self:SetStatus(nil)
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
    local saved, reason = self.onSave(self.queryID, self.nameField:GetText(), query, builder, self.spriteObjectID)
    if saved then
        self:Close(true)
    else
        self:SetStatus(reason or "Could not save the RuneQL query.")
    end
end

-- Preview an item icon until the query itself is saved.
function QueryEditor:SetSprite(objectID)
    if not self.ready then return end
    self.spriteObjectID = math.tointeger(tonumber(objectID))
    self.spriteSlot:SetObject(ObjectConfig.FromID(self.spriteObjectID))
    self.spriteSlot:SetTooltip("Click to edit")
end

-- Capture edits before Core replaces its custom-view layers on resize or refresh.
function QueryEditor:Snapshot()
    return { name = self.nameText, query = self.queryText, spriteObjectID = self.spriteObjectID,
        draft = self.draft, mode = self.mode, generated = self.generated, generatedBuilder = self.generatedBuilder,
        pickerIndex = self.pickerIndex, pickerPage = self.pickerPage, pickerValues = self.pickerValues,
        preservedAdvanced = self.preservedAdvanced, visualBaseline = self.visualBaseline, status = self.statusText,
        scrollY = self.body.scrollY or 0 }
end

-- Finish editing through the owning bank view.
function QueryEditor:Close(saved)
    if not self.ready then return end
    if self.onClose ~= nil then self.onClose(saved == true) else self:Destroy() end
end

-- Destroy controls and their tooltip contexts before Core retires the view layers
function QueryEditor:Destroy()
    if self.destroyed then return end
    self.destroyed, self.ready = true, false
    for index = #self.owned, 1, -1 do
        local control = self.owned[index]
        pcall(function() control:Destroy() end)
    end
    local root = self.root
    self.owned, self.visualControls, self.advancedControls, self.slots, self.groupSlots = {}, {}, {}, {}, {}
    self.root, self.onSave, self.onClose, self.catalog = nil, nil, nil
    self.pickerButtons, self.pickerValues = {}, {}
    if root ~= nil then
        pcall(function() prettyui.Tooltip.unregisterContext(root) end)
        pcall(function() root:Destroy() end)
    end
end

return QueryEditor
