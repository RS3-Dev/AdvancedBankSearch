-- Clean and format plain text the same way across modules

local Text = {}

-- Use Core's sanitizer and retain a fallback for older or unavailable Core builds.
function Text.sanitize(value)
    local text = tostring(value or "")
    local candidates = { bankcore, rawget(_G, "__bankcore_api") }
    for index = 1, 2 do
        local api = candidates[index]
        if type(api) == "table" and type(api.SanitizeString) == "function" then
            local ok, clean = pcall(api.SanitizeString, text)
            if ok and type(clean) == "string" then text = clean; break end
        end
    end
    return (text:gsub("<[^<>]*>", ""):gsub("[<>]", ""))
end

-- Sanitize initial, pasted, submitted, and programmatically replaced field text.
function Text.newField(parent, options)
    options = options or {}
    options.text = Text.sanitize(options.text or options.content)
    local onChange, onSubmit = options.onChange, options.onSubmit
    options.onChange = function(field, reason, value)
        local clean = Text.sanitize(value)
        if clean ~= value then field:SetText(clean, false) end
        if onChange ~= nil then onChange(field, reason, clean) end
    end
    options.onSubmit = function(field, value)
        local clean = Text.sanitize(value)
        if clean ~= value then field:SetText(clean, false) end
        if onSubmit ~= nil then onSubmit(field, clean) end
    end
    local field = prettyui.TextField.new(parent, options)
    local setText = field.SetText
    field.SetText = function(self, value, triggerCallback)
        return setText(self, Text.sanitize(value), triggerCallback)
    end
    return field
end

-- Remove surrounding spaces from text supplied by the user
function Text.trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

-- Capitalize each word for display without changing the stored name
function Text.titleCase(value)
    -- Capitalize the first letter of each word
    return (Text.plain(value):gsub("(%S+)", function(word)
        return (word:gsub("^%l", string.upper))
    end))
end

-- Remove control characters and markup brackets
function Text.plain(value)
    local text = string.gsub(Text.sanitize(value), "%c", "")
    return Text.trim(text)
end

return Text
