-- Exercise Core delegation, fallback safety, and every text-field write path.
local Text = require("resources/core/text")
local calls = 0
bankcore = { SanitizeString = function(value)
    calls = calls + 1
    return (value:gsub("<[^<>]*>", ""):gsub("[<>]", ""))
end }
assert(Text.sanitize("Iron<img=-1> ore") == "Iron ore" and calls == 1)
bankcore = nil
_G.__bankcore_api = { SanitizeString = function() error("unavailable") end }
for _, value in ipairs({ "<img=-1>", "<<img=-1>>", "<img=-1", "<col=red><img=-1></col>" }) do
    assert(not Text.sanitize(value):find("[<>]"))
end
_G.__bankcore_api = nil
local initial, changed, submitted
prettyui = { TextField = { new = function(_, options)
    initial = options.text
    return { value = initial, options = options, SetText = function(self, value) self.value = value end }
end } }
local field = Text.newField(nil, { text = "Safe<img=-1>",
    onChange = function(_, _, value) changed = value end,
    onSubmit = function(_, value) submitted = value end })
assert(initial == "Safe")
field.options.onChange(field, nil, "Paste<img=-1>")
assert(changed == "Paste" and field.value == "Paste")
field.options.onSubmit(field, "Submit<img=-1>")
assert(submitted == "Submit" and field.value == "Submit")
field:SetText("Replace<img=-1>")
assert(field.value == "Replace")
assert(Text.sanitize('qty:[10 TO *] AND name:"Iron ore"') == 'qty:[10 TO *] AND name:"Iron ore"')
print("text_safety_test: ok")
