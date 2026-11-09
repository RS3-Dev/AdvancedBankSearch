-- Bank Tags removal confirmation, using Window controls for older PrettyUI builds.
local ConfirmWindow = {}
ConfirmWindow.__index = ConfirmWindow
function ConfirmWindow.new(parent, options)
    local self = setmetatable({ owned = {} }, ConfirmWindow)
    self.window = prettyui.Window.new(parent, { title = options.title,
        x = -170, y = -82, xAnchor = 0.5, yAnchor = 0.5, width = 340, height = 164,
        minWidth = 340, maxWidth = 340, minHeight = 164, maxHeight = 164,
        scrollable = false, destroyOnClose = true, onClose = options.onClose })
    self.message = prettyui.Text.new(self.window.content, { text = options.message,
        x = 16, y = 18, width = 292, height = 52, maxLines = 4, colour = 0xE7D7B0FF,
        alignHorizontal = ui.AlignMode.CENTRE })
    self.cancelButton = prettyui.SimpleButton.new(self.window.content, "Cancel", function() self.window:Close() end,
        { x = 16, y = 88, width = 142, height = 28 })
    self.confirmButton = prettyui.SimpleButton.new(self.window.content, "Delete", function()
        local saved, reason = options.onConfirm()
        if saved then self.window:Close() else
            self.message.content, self.message.rgba = reason or "Could not delete the query.", 0xE57373FF
        end
    end, { x = 166, y = 88, width = 142, height = 28 })
    self.owned = { self.message, self.cancelButton, self.confirmButton, self.window }
    return self
end
function ConfirmWindow:Show() self.window:Show() end
function ConfirmWindow:Destroy()
    for _, control in ipairs(self.owned) do pcall(function() control:Destroy() end) end
    self.owned, self.window = {}, nil
end
return ConfirmWindow
