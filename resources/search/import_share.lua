local Text = require("resources/core/text")

-- Ported from Bank Tags windows/import_share.lua with query-specific data callbacks.
-- Preview imported queries and display share codes

local Code = require("resources/search/query_code")

local Draft = require("resources/search/import_share_draft")

local ImportShare = {}
ImportShare.__index = ImportShare
for name, method in pairs(Draft.methods) do ImportShare[name] = method end

local WIDTH = 520
local HEIGHT = 520
local CONTENT_WIDTH = WIDTH - 16
-- The tabs fill the window below the title bar
local TABS_HEIGHT = 466
local SHARE_PAGE_MIN_HEIGHT = TABS_HEIGHT - 42
local IMPORT_NO_FOLDER, IMPORT_NEW_FOLDER = Draft.NO_FOLDER, Draft.NEW_FOLDER
local FOLDER_NAME_Y = Draft.FOLDER_NAME_Y
local STATUS_SUCCESS = 0x78C47CFF
local STATUS_ERROR = 0xE57373FF

-- Create a settings label
local function text(parent, value, y, options)
    options = options or {}
    return prettyui.Text.new(parent, {
        text = Text.sanitize(value),
        x = options.x or 18,
        y = y,
        width = options.width or 452,
        height = options.height or 24,
        colour = options.colour or 0xC9BEA4FF,
        font = options.font,
        maxLines = options.maxLines or 2,
        alignHorizontal = options.alignHorizontal,
    })
end

-- Create the import and sharing pages
function ImportShare.new(parent, options)
    local self = setmetatable({
        options = options,
        controls = {},
        shareRows = {},
        closed = false,
        ready = false,
    }, ImportShare)

    local ok, reason = pcall(self.Build, self, parent, options)
    if not ok then self:Destroy(); error(reason, 0) end
    return self
end

function ImportShare:Build(parent, options)
    self.window = prettyui.Window.new(parent, {
        title = "Query Import / Share",
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
        -- Mark the window closed and notify its owner
        onClose = function()
            self.closed = true
            if options.onClose ~= nil then options.onClose() end
        end,
    })

    self.tabs = prettyui.Tabs.new(self.window.content, {
        { kind = "text", text = "Import", value = "import" },
        { kind = "text", text = "Share", value = "share", scrollable = true },
    }, {
        x = 0,
        y = 0,
        width = CONTENT_WIDTH,
        height = TABS_HEIGHT,
        scrollable = false,
        tabInset = 4,
    })

    local importPage = self.tabs:GetPage(1)
    self.controls.importTitle = text(importPage.content, "Import queries", 0, {
        colour = 0xF2C66DFF,
        font = id.Font.CINZEL_13PT_BOLD,
    })
    -- The input fills in the name, sprite, and folder below
    self.controls.importCodeLabel = text(importPage.content, "Import code", 32, {
        height = 20, maxLines = 1,
    })
    self.importField = Text.newField(importPage.content, {
        x = 18,
        y = 56,
        width = 452,
        height = 30,
        maxLength = Code.INPUT_LIMIT,
        maxLines = 1,
        placeholder = "Paste a shared query code or backup...",
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        onChange = function(_, _, content) self:RefreshImportPreview(content) end,
    })
    self.controls.importNameLabel = text(importPage.content, "Query name", 98, {
        width = 404, height = 20, maxLines = 1,
    })
    self.controls.importSpriteLabel = text(importPage.content, "Icon", 98, {
        x = 422, width = 48, height = 20, maxLines = 1,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        alignHorizontal = ui.AlignMode.CENTRE,
    })
    self.importNameField = Text.newField(importPage.content, {
        x = 18, y = 127, width = 404, height = 30,
        placeholder = "Query name", maxLength = 40, maxLines = 1,
        disabled = true,
    })
    self.importSpriteSlot = prettyui.ItemSlot.new(importPage.content, nil, {
        x = 430, y = 122, clickthrough = false, disabled = true,
        tooltip = "Choose query icon",
    })
    -- Choose an icon for the current import draft
    self.importSpriteSlot.root:Subscribe(ui.Hook.ONCLICK, function()
        self:ChooseImportSprite()
        return false
    end)
    self.controls.importFolderLabel = text(importPage.content, "Folder", 170, {
        height = 20, maxLines = 1,
    })
    self.importFolder = prettyui.ComboBox.new(importPage.content, {
        x = 18, y = 194, width = 452, height = 30,
        entries = {
            { id = IMPORT_NO_FOLDER, label = "No folder", order = 1 },
            { id = IMPORT_NEW_FOLDER, label = "New folder...", order = 2 },
        },
        selectedID = IMPORT_NO_FOLDER,
        disabled = true,
        maxVisibleEntries = 6,
        onChange = function() self:UpdateImportFolderControls() end,
    })
    self.importFolderName = Text.newField(importPage.content, {
        x = 18, y = FOLDER_NAME_Y, width = 452, height = 30,
        placeholder = "New folder name", maxLength = 40,
        maxLines = 1, disabled = true,
    })
    self.importFolderName.root.hidden = true
    -- Import the preview after the player's explicit choice
    self.importButton = prettyui.SimpleButton.new(importPage.content, "Import queries", function()
        self:Import()
    end, {
        x = 18,
        y = FOLDER_NAME_Y,
        width = 452,
        height = 28,
    })
    self.importStatus = text(importPage.content, "", FOLDER_NAME_Y + 36, {
        width = 452,
        height = 36,
        maxLines = 2,
        alignHorizontal = ui.AlignMode.CENTRE,
    })
    self.importStatus.hidden = true

    local sharePage = self.tabs:GetPage(2)
    self.sharePage = sharePage
    self.shareRows = {}
    self.controls.shareTitle = text(sharePage.content, "Share queries", 12, {
        colour = 0xF2C66DFF,
        font = id.Font.CINZEL_13PT_BOLD,
    })
    self.controls.shareCopy = text(sharePage.content,
        "Click a code, then Ctrl+A and Ctrl+C to copy.",
        38, { height = 24, maxLines = 1 })
    self:RefreshExports()
    self.ready = true
    self:RefreshImportPreview("")
    return self
end

-- Show feedback in green, red, or a given colour
function ImportShare:SetPageStatus(control, value, success)
    control.content = Text.sanitize(value)
    control.rgba = success and STATUS_SUCCESS or STATUS_ERROR
    control.hidden = value == nil or value == ""
end

-- Remove the share rows before rebuilding them
function ImportShare:DestroyShareRows()
    for index = #self.shareRows, 1, -1 do
        local row = self.shareRows[index]
        if row.label ~= nil then pcall(function() prettyui.Tooltip.unbind(row.label) end) end
        if row.field ~= nil then pcall(function() row.field:Destroy() end) end
        if row.root ~= nil then pcall(function() row.root:Destroy() end) end
    end
    self.shareRows = {}
end

-- Create a row to copy each query's share code
function ImportShare:RebuildShareRows(exports)
    self:DestroyShareRows()
    local startY = 74
    local rowHeight = 82
    for index, export in ipairs(exports) do
        local root = ui.Layer.new(self.sharePage.content)
        root:SetPos(18, startY + (index - 1) * rowHeight)
        root:SetSize(452, 78)
        root.clickthrough = true
        local label = prettyui.Text.new(root, {
            text = Text.plain(export.name),
            x = 0,
            y = 0,
            width = 452,
            height = 42,
            font = id.Font.MUSEO_SANS_11PT_REGULAR,
            colour = export.value ~= nil and 0xD8CCAEFF or 0xE57373FF,
            maxLines = 2,
            alignVertical = ui.AlignMode.CENTRE,
            tooltip = Text.plain(export.reason or export.name),
        })
        local value = export.value or tostring(export.reason or "Unavailable")
        local tooLarge = #value > Code.INPUT_LIMIT
        if tooLarge then
            value = "Too large for the game field (" .. tostring(#value) .. " characters)"
            label.rgba = 0xE57373FF
        end
        local field = Text.newField(root, {
            x = 0,
            y = 46,
            width = 452,
            height = 27,
            maxLength = Code.INPUT_LIMIT,
            maxLines = 1,
            font = id.Font.MUSEO_SANS_11PT_REGULAR,
            text = Text.sanitize(value),
        })
        self.shareRows[#self.shareRows + 1] = {
            tag = export.name,
            root = root,
            label = label,
            field = field,
        }
    end
    if #self.shareRows == 0 then
        local empty = text(self.sharePage.content, "No queries to share yet.", startY + 10, {
            x = 18,
            width = 452,
            height = 28,
            alignHorizontal = ui.AlignMode.CENTRE,
            colour = 0x9F947BFF,
        })
        self.shareRows[1] = { root = empty }
    end
    self.sharePage:SetContentHeight(math.max(SHARE_PAGE_MIN_HEIGHT,
        startY + #self.shareRows * rowHeight + 8))
end

-- Reload share codes and refresh the sharing rows
function ImportShare:RefreshExports()
    self:RebuildShareRows(self.options.onGetQueryExports())
end

-- Show the window
function ImportShare:Show()
    self.window:Show()
end

-- Destroy the pages and controls before the window
function ImportShare:Destroy()
    self.closed, self.ready = true, false
    self.importRevision = (self.importRevision or 0) + 1
    self.importData = nil
    self.importText = nil
    self:DestroyShareRows()
    for _, control in pairs(self.controls) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    for _, key in ipairs({ "importField", "importNameField", "importSpriteSlot", "importFolder",
        "importFolderName", "importButton", "importStatus", "tabs", "window" }) do
        local control = self[key]
        if control ~= nil then pcall(function() control:Destroy() end) end
        self[key] = nil
    end
    self.controls = {}
    self.window, self.options = nil, nil
end

return ImportShare
