-- Stand in for Bank Tags' import-source API as CONTRACT.md describes
-- It keeps the contract's shapes and limits but is not Bank Tags
-- Kept outside tests/ so tools/check.lua does not run it

local Standin = {}
Standin.__index = Standin

local PROVIDER_FIELDS = { label = true, icon = true, input = true, prompt = true, placeholder = true,
    actionLabel = true, unavailable = true, request = true }

-- Read 1 to limit characters of text without markup
local function label(value, limit)
    if type(value) ~= "string" then return nil end
    local text = string.match(value, "^%s*(.-)%s*$")
    if text == "" or #text > limit or string.find(text, "[%c<>]") then return nil end
    return text
end

-- Validate a provider as Bank Tags does
local function readProvider(input)
    if type(input) ~= "table" or getmetatable(input) ~= nil then return nil, "not a plain table" end
    for key in next, input do
        if not PROVIDER_FIELDS[key] then return nil, "unknown field " .. tostring(key) end
    end
    local record = { label = label(input.label, 64), icon = input.icon, input = input.input, request = input.request,
        prompt = input.prompt, placeholder = input.placeholder, unavailable = input.unavailable }
    if record.label == nil then return nil, "label" end
    if record.icon ~= nil and prettyui.Sprites.SPRITE_BUTTONS[record.icon] == nil then return nil, "icon" end
    if record.input ~= "text" and record.input ~= "action" then return nil, "input" end
    if type(record.request) ~= "function" then return nil, "request" end
    if input.actionLabel ~= nil then return nil, "actionLabel does not apply to text sources" end
    for field, limit in pairs({ prompt = 64, placeholder = 64, unavailable = 120 }) do
        if input[field] ~= nil and label(input[field], limit) == nil then return nil, field end
    end
    return record
end

-- Read a draft as Bank Tags' TagDraft does, up to 2,000 entries
-- Returns { name, keys = { "object:<id>:<copy>", ... } } tags, or nil and why
function Standin.ReadDraft(draft)
    if type(draft) ~= "table" or type(draft.tags) ~= "table" or #draft.tags == 0 or #draft.tags > 32 then
        return nil, "a draft is a table with 1 to 32 tags"
    end
    local budget = 2000
    local tags = {}
    for index, tag in ipairs(draft.tags) do
        local name = label(tag.name, 80)
        if name == nil or string.find(name, ",", 1, true) then return nil, "tag " .. index .. " name" end
        local copies, keys = {}, {}
        budget = budget - #(tag.rows or {})
        for _, row in ipairs(tag.rows or {}) do
            budget = budget - #row
            for _, entry in ipairs(row) do
                if math.type(entry) ~= "integer" then return nil, "tag " .. index .. " entry is not an object ID" end
                copies[entry] = (copies[entry] or 0) + 1
                keys[#keys + 1] = "object:" .. entry .. ":" .. copies[entry]
            end
        end
        if budget < 0 then return nil, "the draft is over 2,000 entries" end
        tags[index] = { name = string.lower(name), keys = keys }
    end
    return tags
end

-- Create the stand-in with its root in standin.api
function Standin.new()
    local self = setmetatable({ owners = {}, providers = {}, running = true, results = {} }, Standin)
    self.api = {
        LIMITS = { owners = 32, importProviders = 16, importProvidersPerOwner = 4, draftEntries = 2000 },
        RegisterExtension = function(ownerID, ownerLabel) return self:Register(ownerID, ownerLabel) end,
        GetState = function() return { running = self.running } end,
    }
    return self
end

-- Register an owner, replacing any earlier one with that ID
function Standin:Register(ownerID, ownerLabel)
    if not self.running then return nil, "stale_api" end
    if label(ownerLabel, 64) == nil then return nil, "invalid_label" end
    self:Drop(ownerID)
    local owner = { id = ownerID }
    self.owners[ownerID] = owner
    local standin = self
    local function live() return standin.running and standin.owners[ownerID] == owner end
    local handle = {
        RegisterImportProvider = function(_, providerID, input)
            if not live() then return false, "stale_handle" end
            local key = ownerID .. "/" .. providerID
            if standin.providers[key] ~= nil then return false, "duplicate_import_provider" end
            local record, why = readProvider(input)
            if record == nil then return false, "invalid_import_provider", why end
            record.owner = owner
            standin.providers[key] = record
            return true
        end,
        UpdateImportProvider = function(_, providerID, input)
            if not live() then return false, "stale_handle" end
            local key = ownerID .. "/" .. providerID
            if standin.providers[key] == nil then return false, "unknown_import_provider" end
            local record, why = readProvider(input)
            if record == nil then return false, "invalid_import_provider", why end
            record.owner = owner
            standin.providers[key] = record
            return true
        end,
        GetState = function() return { running = standin.running, live = live() } end,
        Dispose = function()
            if live() then standin:Drop(ownerID) end
            return true
        end,
    }
    return setmetatable({}, { __index = handle, __newindex = function() error("read-only", 2) end,
        __metatable = false })
end

-- Remove an owner and its sources
function Standin:Drop(ownerID)
    self.owners[ownerID] = nil
    for key, record in pairs(self.providers) do
        if record.owner.id == ownerID then self.providers[key] = nil end
    end
end

-- Request a draft next tick and record it in standin.results[key]
function Standin:Request(key, input)
    local record = self.providers[key]
    assert(record ~= nil and record.unavailable == nil, "the source is not usable")
    self.results[key] = nil
    local settled = false
    local function settle(state, value)
        if settled then return false, "stale_request" end
        settled = true
        self.results[key] = { state = state, value = value }
        return true
    end
    local request = setmetatable({}, { __index = {
        input = input, source = key,
        Resolve = function(_, draft)
            local tags, why = Standin.ReadDraft(draft)
            if tags == nil then return settle("invalid", why) end
            return settle("ready", tags)
        end,
        Fail = function(_, message)
            local text = label(message, 120)
            return settle("error", text or "The source could not load this import.")
        end,
        IsCurrent = function() return not settled end,
    }, __newindex = function() error("read-only", 2) end })
    local event = "tags_standin_request"
    Event.Logic.Subscribe(event, function()
        Event.Logic.Unsubscribe(event)
        record.request(request)
    end)
end

-- Refuse every later call, as Bank Tags does on shutdown
function Standin:Close()
    self.running = false
    self.owners, self.providers = {}, {}
end

return Standin
