-- Persist saved query records while RuneQL owns parsing and evaluation. Queries are saved as
-- JSON text in this plugin's own keys; the integrated plugin's bankutils:runesql:* data is
-- never read

local ChunkedStringStore = require("advancedbanksearch/core/chunked_string_store")
local Json = require("advancedbanksearch/core/json")

-- Remove surrounding spaces from text supplied by the user
local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local QueryStore = {}
QueryStore.__index = QueryStore

local MAX_NAME_LENGTH = 40
local MAX_QUERY_LENGTH = 9999
local TEXT_STORE = {
    manifestKey = "advancedbanksearch:queries:v1:manifest",
    chunkPrefix = "advancedbanksearch:queries:v1:",
}
local UNREADABLE = "Your saved searches could not be read, so nothing is saved until this is fixed."

-- Copy the supported fields of a saved query record
local function copyRecord(record)
    if type(record) ~= "table" then return nil end
    return {
        id = tostring(record.id or ""),
        name = tostring(record.name or ""),
        query = tostring(record.query or ""),
    }
end

-- Copy query records and normalize the next available query ID
local function copyData(data)
    local result = {
        schemaVersion = 1,
        nextId = math.max(1, math.floor(tonumber(data and data.nextId) or 1)),
        queries = {},
    }
    local sourceQueries = type(data) == "table" and type(data.queries) == "table"
        and data.queries or {}
    for _, record in ipairs(sourceQueries) do
        local copy = copyRecord(record)
        if copy ~= nil then result.queries[#result.queries + 1] = copy end
    end
    return result
end

-- Trim query input and reject missing or overlong names and expressions
local function validate(name, query)
    name = trim(name)
    query = trim(query)
    if name == "" then return nil, nil, "Enter a query name." end
    if #name > MAX_NAME_LENGTH then
        return nil, nil, "Query names can contain at most 40 characters."
    end
    if query == "" then return nil, nil, "Enter a RuneQL query." end
    if #query > MAX_QUERY_LENGTH then
        return nil, nil, "RuneQL queries can contain at most 9,999 characters."
    end
    return name, query, nil
end

-- Report whether a save was published, whether or not it can be read
local function hasSave()
    if PersistentDB == nil or PersistentDB.GetString == nil then return false end
    local ok, value = pcall(function() return PersistentDB:GetString(TEXT_STORE.manifestKey) end)
    return ok and type(value) == "string"
end

-- Decode the published chunked save; nil with an error when a save exists but cannot be read
local function loadTextData()
    local encoded = ChunkedStringStore.Read(TEXT_STORE)
    if encoded == nil then return nil, hasSave() and UNREADABLE or nil end
    local ok, decoded = pcall(Json.decode, encoded)
    if not ok or type(decoded) ~= "table" then return nil, UNREADABLE end
    return decoded
end

-- Load the saved queries, retaining only valid unique query IDs. A save that cannot be read
-- loads as empty with its error, and is never overwritten
local function loadData()
    local saved, loadError = loadTextData()
    if saved == nil then return copyData(nil), loadError end

    local data = copyData(saved)
    local seen = {}
    local valid = {}
    local largestID = 0
    for _, record in ipairs(data.queries) do
        local numericID = math.tointeger(tonumber(record.id))
        local name, query = validate(record.name, record.query)
        if numericID ~= nil and numericID > 0 and not seen[numericID]
            and name ~= nil then
            seen[numericID] = true
            largestID = math.max(largestID, numericID)
            valid[#valid + 1] = {
                id = tostring(numericID),
                name = name,
                query = query,
            }
        end
    end
    data.queries = valid
    data.nextId = math.max(data.nextId, largestID + 1)
    return data
end

-- Load saved queries into a store with isolated editing copies
function QueryStore.new()
    local data, loadError = loadData()
    return setmetatable({ data = data, loadError = loadError }, QueryStore)
end

-- Write query data through chunked storage, refusing while the save cannot be read
function QueryStore:Persist(data)
    if self.loadError ~= nil then return false, self.loadError end
    if PersistentDB == nil or PersistentDB.SetString == nil or PersistentDB.GetString == nil then
        return false, "PersistentDB is unavailable."
    end
    local encoded = Json.encode(data)
    local saved, failure = ChunkedStringStore.Write(TEXT_STORE, encoded)
    if not saved and failure.stage == "chunk" then
        return false, "PersistentDB could not save RuneQL chunk "
            .. tostring(failure.index) .. "."
    end
    if not saved then
        return false, "PersistentDB could not publish the RuneQL save."
    end
    return true, nil
end

-- Return copies of saved queries for sidebar and editor use
function QueryStore:All()
    local result = {}
    for _, record in ipairs(self.data.queries) do
        result[#result + 1] = copyRecord(record)
    end
    return result
end

-- Find a saved query and return a copy safe for editing
function QueryStore:Get(queryID)
    queryID = tostring(queryID or "")
    for _, record in ipairs(self.data.queries) do
        if record.id == queryID then return copyRecord(record) end
    end
    return nil
end


-- Find a conflicting query name while optionally excluding the record being edited
function QueryStore:FindName(name, exceptID)
    local wanted = string.lower(trim(name))
    exceptID = exceptID ~= nil and tostring(exceptID) or nil
    for _, record in ipairs(self.data.queries) do
        if record.id ~= exceptID and string.lower(record.name) == wanted then
            return record
        end
    end
    return nil
end

-- Validate and persist a copied query set before adopting the edit in memory
function QueryStore:Save(queryID, name, query)
    local reason
    name, query, reason = validate(name, query)
    if name == nil then return false, nil, reason end
    queryID = queryID ~= nil and tostring(queryID) or nil
    if self:FindName(name, queryID) ~= nil then
        return false, nil, "A RuneQL query with that name already exists."
    end

    local nextData = copyData(self.data)
    local savedRecord = nil
    if queryID ~= nil then
        for _, record in ipairs(nextData.queries) do
            if record.id == queryID then
                record.name = name
                record.query = query
                savedRecord = record
                break
            end
        end
        if savedRecord == nil then return false, nil, "That RuneQL query no longer exists." end
    else
        savedRecord = {
            id = tostring(nextData.nextId),
            name = name,
            query = query,
        }
        nextData.nextId = nextData.nextId + 1
        nextData.queries[#nextData.queries + 1] = savedRecord
    end

    local persisted, persistReason = self:Persist(nextData)
    if not persisted then return false, nil, persistReason end
    self.data = nextData
    return true, copyRecord(savedRecord), nil
end

-- Persist a copied query set without the selected record before adopting it
function QueryStore:Delete(queryID)
    queryID = tostring(queryID or "")
    local nextData = copyData(self.data)
    local removed = false
    for index = #nextData.queries, 1, -1 do
        if nextData.queries[index].id == queryID then
            table.remove(nextData.queries, index)
            removed = true
            break
        end
    end
    if not removed then return false, "That RuneQL query no longer exists." end
    local persisted, persistReason = self:Persist(nextData)
    if not persisted then return false, persistReason end
    self.data = nextData
    return true, nil
end

QueryStore.MAX_NAME_LENGTH = MAX_NAME_LENGTH
QueryStore.MAX_QUERY_LENGTH = MAX_QUERY_LENGTH
QueryStore.TEXT_STORE = TEXT_STORE

return QueryStore
