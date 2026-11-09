-- Choose a saved search's folder or name a new folder
-- Listed mode is the fallback for PrettyUI builds without folder submenus.

local QueryStore = require("resources/search/query_store")

local FolderDialog = {}
FolderDialog.__index = FolderDialog

local WIDTH = 300
local MARGIN = 14
local CONTENT_WIDTH = WIDTH - 16 - MARGIN * 2
local ROW_HEIGHT = 30
local LIST_HEIGHT = ROW_HEIGHT * 5 + 2
local BUTTON_GAP = 8

-- Create the dialog from title, choices, field, and callbacks
-- onChoose and onSave return success and a reason
function FolderDialog.new(parent, options)
    local self = setmetatable({ onChoose = options.onChoose, onSave = options.onSave, owned = {} }, FolderDialog)
    local listed = options.choices ~= nil
    local dialogWidth = listed and WIDTH or 360
    local margin = listed and MARGIN or 16
    local controlWidth = listed and CONTENT_WIDTH or 312
    local fieldTop = listed and 40 + LIST_HEIGHT + 10 or 31
    -- Room for the field, status, buttons, and window frame
    local height = listed and fieldTop + 136 or 176
    self.window = prettyui.Window.new(parent, {
        title = options.title, x = -math.floor(dialogWidth / 2), y = -math.floor(height / 2),
        xAnchor = 0.5, yAnchor = 0.5, width = dialogWidth, height = height, minWidth = dialogWidth, maxWidth = dialogWidth,
        minHeight = height, maxHeight = height, scrollable = false, destroyOnClose = true,
        onClose = options.onClose,
    })
    local content = self.window.content
    local owned = self.owned
    -- Add one control the dialog destroys
    local function own(control)
        owned[#owned + 1] = control
        return control
    end
    own(prettyui.Text.new(content, { text = options.heading, x = margin, y = listed and 8 or 10, width = controlWidth, height = listed and 24 or 20,
        colour = 0xE7C878FF, maxLines = 1 }))
    if listed then
        local entries = {}
        for index, choice in ipairs(options.choices) do
            entries[index] = { id = choice.id, label = choice.label, textColour = 0xE7D7B0FF }
        end
        self.list = own(prettyui.List.new(content, {
            x = margin, y = 40, width = controlWidth, height = LIST_HEIGHT, entryHeight = ROW_HEIGHT,
            maxSelected = 1, backgroundColour = 0x00000000, borderColour = 0x806432FF, selectedColour = 0x5A4526FF,
            _onEntryClick = function(_, choiceID) self:Finish(self.onChoose(choiceID)) end,
        }))
        self.list:SetEntries(entries)
    end
    self.field = own(prettyui.TextField.new(content, {
        x = margin, y = fieldTop, width = controlWidth, height = 30, text = options.text or "",
        placeholder = options.placeholder or "Folder name", maxLength = QueryStore.MAX_NAME_LENGTH,
        onSubmit = function() self:Save() end,
    }))
    self.status = own(prettyui.Text.new(content, { text = "", x = margin, y = listed and fieldTop + 36 or 70, width = controlWidth,
        height = 18, colour = 0xE57373FF, maxLines = 1 }))
    self.status.hidden = true
    local buttonTop = listed and fieldTop + 36 + 24 or 96
    local buttonWidth = math.floor((controlWidth - BUTTON_GAP) / 2)
    self.cancelButton = own(prettyui.SimpleButton.new(content, "Cancel", function() self.window:Close() end, {
        x = margin, y = buttonTop, width = buttonWidth, height = 28,
    }))
    self.saveButton = own(prettyui.SimpleButton.new(content, options.saveLabel or "Save", function() self:Save() end, {
        x = margin + buttonWidth + BUTTON_GAP, y = buttonTop, width = controlWidth - buttonWidth - BUTTON_GAP,
        height = 28,
    }))
    return self
end

-- Close after a change succeeded, or show why it did not
function FolderDialog:Finish(ok, reason)
    if self.window == nil then return end
    if ok then
        self.window:Close()
    else
        self.status.content = tostring(reason or "Could not save the folder.")
        self.status.hidden = false
    end
end

-- Submit the typed folder name
function FolderDialog:Save()
    if self.onSave ~= nil then self:Finish(self.onSave(self.field:GetText())) end
end

-- Show the dialog window
function FolderDialog:Show()
    self.window:Show()
end

-- Destroy the dialog's controls and window
function FolderDialog:Destroy()
    for _, control in ipairs(self.owned) do pcall(function() control:Destroy() end) end
    local window = self.window
    self.window, self.owned, self.onChoose, self.onSave = nil, {}, nil, nil
    if window ~= nil then pcall(function() window:Destroy() end) end
end

return FolderDialog
