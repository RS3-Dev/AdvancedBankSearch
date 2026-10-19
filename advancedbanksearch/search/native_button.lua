-- Draw a native bank button with an icon lit on hover or use

local NativeButton = {}
NativeButton.__index = NativeButton

-- The host's button panel style, if the host does not name it
local BUTTON_PANEL = 318

-- Create a square button with a centred icon
function NativeButton.new(parent, spriteName, action, options)
    local self = setmetatable({
        action = action,
        active = false,
        hovered = false,
        sprites = prettyui.Sprites.SPRITE_BUTTONS[spriteName],
        x = options.x,
        y = options.y,
        width = options.size,
        height = options.size,
    }, NativeButton)
    self.root = ui.Button.new(parent)
    self.root:SetPos(self.x, self.y)
    self.root:SetSize(self.width, self.height)
    self.root.stylesheetID = id.StyleSheet.BUTTON_PANEL or BUTTON_PANEL
    if self.root.text ~= nil then self.root.text.content = "" end
    self.root:Subscribe(ui.Hook.ONBUTTONPRESSED, function() self.action(self, self.active) end)
    -- A host button holds no children, so the icon sits beside it
    local iconSize = options.iconSize
    self.icon = ui.Sprite.new(parent)
    self.icon:SetPos(self.x + math.floor((self.width - iconSize) / 2), self.y + math.floor((self.height - iconSize) / 2))
    self.icon:SetSize(iconSize, iconSize)
    self.icon.clickthrough = true
    self.root:Subscribe(ui.Hook.ONMOUSEOVER, function()
        self.hovered = true
        self:Update()
        return true
    end)
    self.root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        self.hovered = false
        self:Update()
        return true
    end)
    prettyui.Tooltip.bind(self, self.root, parent, options.tooltip)
    self:Update()
    return self
end

-- Show the panel style, and the lit icon while hovered or active
function NativeButton:Update()
    self.root.stylesheetID = id.StyleSheet.BUTTON_PANEL or BUTTON_PANEL
    self.icon.spriteID = (self.active or self.hovered) and self.sprites.active or self.sprites.neutral
end

-- Light the icon while the button's mode is on
function NativeButton:SetActive(active)
    self.active = active == true
    self:Update()
end

-- Change the tooltip through PrettyUI
function NativeButton:SetTooltip(value)
    return prettyui.Tooltip.set(self, value)
end

-- Remove the tooltip, icon, and button
function NativeButton:Destroy()
    prettyui.Tooltip.unbind(self)
    if self.icon ~= nil then self.icon:Destroy() end
    if self.root ~= nil then self.root:Destroy() end
    self.icon, self.root = nil, nil
end

return NativeButton
