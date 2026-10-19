-- Edit saved query names and expressions without owning bank rendering

local QueryStore = require("advancedbanksearch/search/query_store")

local QueryEditor = {}
QueryEditor.__index = QueryEditor

local WIDTH = 540
local HEIGHT = 500
local MARGIN = 16
local CONTENT_WIDTH = WIDTH - 16 - MARGIN * 2
local BUTTON_GAP = 8
local QUERY_FIELD_HEIGHT = 286

-- Create the saved-query editor and connect its name, query, and save controls
function QueryEditor.new(parent, options)
    options = options or {}
    local record = options.record or {}
    local self = setmetatable({
        queryID = record.id,
        onSave = options.onSave,
    }, QueryEditor)

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

    local content = self.window.content
    self.nameLabel = prettyui.Text.new(content, {
        text = "Query name",
        x = MARGIN,
        y = 10,
        width = CONTENT_WIDTH,
        height = 20,
        colour = 0xF2C66DFF,
        font = id.Font.CINZEL_13PT_BOLD,
    })
    self.nameField = prettyui.TextField.new(content, {
        x = MARGIN,
        y = 31,
        width = CONTENT_WIDTH,
        height = 30,
        text = record.name or "",
        placeholder = "Query name",
        maxLength = QueryStore.MAX_NAME_LENGTH,
        onChange = function()
            if self.status ~= nil then self.status.hidden = true end
        end,
    })
    self.queryLabel = prettyui.Text.new(content, {
        text = "RuneQL",
        x = MARGIN,
        y = 72,
        width = 74,
        height = 20,
        colour = 0xF2C66DFF,
        font = id.Font.CINZEL_13PT_BOLD,
    })
    self.queryHint = prettyui.Text.new(content, {
        text = "Use OR between alternatives",
        x = MARGIN + 82,
        y = 72,
        width = CONTENT_WIDTH - 82,
        height = 20,
        colour = 0x9F947BFF,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        maxLines = 1,
        alignVertical = ui.AlignMode.CENTRE,
    })
    self.queryField = prettyui.TextField.new(content, {
        x = MARGIN,
        y = 94,
        width = CONTENT_WIDTH,
        height = QUERY_FIELD_HEIGHT,
        text = record.query or "",
        placeholder = "e.g. name:(vial AND water) OR name:\"dragon bones\"",
        maxLength = QueryStore.MAX_QUERY_LENGTH,
        maxLines = 0,
        lineSpacing = 14,
        alignVertical = ui.AlignMode.TOPLEFT,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        contentMargin = ui.Margin.new(8, 8, 8, 8),
        onChange = function(_, _, content)
            self:UpdateCharacterCount(content)
            if self.status ~= nil then self.status.hidden = true end
        end,
    })
    self.characterCount = prettyui.Text.new(content, {
        text = "",
        x = MARGIN,
        y = 384,
        width = CONTENT_WIDTH,
        height = 18,
        colour = 0x9F947BFF,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        maxLines = 1,
        alignHorizontal = ui.AlignMode.BOTTOMRIGHT,
    })
    self.status = prettyui.Text.new(content, {
        text = "",
        x = MARGIN,
        y = 384,
        width = CONTENT_WIDTH - 88,
        height = 18,
        colour = 0xE57373FF,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        maxLines = 1,
    })
    self.status.hidden = true

    local buttonY = 410
    local buttonWidth = math.floor((CONTENT_WIDTH - BUTTON_GAP) / 2)
    self.cancelButton = prettyui.SimpleButton.new(content, "Cancel", function()
        self.window:Close()
    end, {
        x = MARGIN,
        y = buttonY,
        width = buttonWidth,
        height = 28,
    })
    self.saveButton = prettyui.SimpleButton.new(content, "Save", function()
        self:Save()
    end, {
        x = MARGIN + buttonWidth + BUTTON_GAP,
        y = buttonY,
        width = CONTENT_WIDTH - buttonWidth - BUTTON_GAP,
        height = 28,
    })
    self:UpdateCharacterCount(record.query or "")
    return self
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

-- Submit the name and expression to the save callback and close only after success
function QueryEditor:Save()
    if self.onSave == nil then return end
    local saved, reason = self.onSave(
        self.queryID,
        self.nameField:GetText(),
        self.queryField:GetText()
    )
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

-- Destroy editor controls and release their window references
function QueryEditor:Destroy()
    for _, control in ipairs({
        self.saveButton,
        self.cancelButton,
        self.status,
        self.characterCount,
        self.queryField,
        self.queryHint,
        self.queryLabel,
        self.nameField,
        self.nameLabel,
        self.window,
    }) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    self.window = nil
    self.onSave = nil
end

return QueryEditor
