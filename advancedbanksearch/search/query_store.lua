-- Persist saved query records while RuneQL owns parsing and evaluation

local ChunkedStringStore = require("advancedbanksearch/core/chunked_string_store")
local Json = require("advancedbanksearch/core/json")

-- The keys and limits the integrated plugin's shared storage-keys module named
local StorageKeys = {
    RUNESQL_KEY = "bankutils:runesql:v1",
    RUNESQL_TEXT_MANIFEST_KEY = "bankutils:runesql:text:v1:manifest",
    RUNESQL_TEXT_CHUNK_PREFIX = "bankutils:runesql:text:v1:",
    LONG_INPUT_LIMIT = 9999,
}

-- Remove surrounding spaces from text supplied by the user
local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local QueryStore = {}
QueryStore.__index = QueryStore

local SELECTION_PREFIX = "__bankutils_runesql:"
local MAX_NAME_LENGTH = 40
local MAX_QUERY_LENGTH = StorageKeys.LONG_INPUT_LIMIT
local TEXT_STORE = {
    manifestKey = StorageKeys.RUNESQL_TEXT_MANIFEST_KEY,
    chunkPrefix = StorageKeys.RUNESQL_TEXT_CHUNK_PREFIX,
}

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

-- Decode the published chunked save, allowing missing or malformed storage
local function loadTextData()
    local encoded = ChunkedStringStore.Read(TEXT_STORE)
    if encoded == nil then return nil end
    local ok, decoded = pcall(Json.decode, encoded)
    return ok and type(decoded) == "table" and decoded or nil
end

-- Load current or legacy query storage and retain only valid unique query IDs
local function loadData()
    local saved = loadTextData()
    if type(saved) ~= "table" then
        local ok, legacy = pcall(function()
            return PersistentDB:GetStructuredData(StorageKeys.RUNESQL_KEY)
        end)
        saved = ok and legacy or nil
    end
    if type(saved) ~= "table" then return copyData(nil) end

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
    return setmetatable({ data = loadData() }, QueryStore)
end

-- Write query data through chunked storage or the older structured-data host API
function QueryStore:Persist(data)
    if PersistentDB == nil then
        return false, "PersistentDB is unavailable."
    end
    if PersistentDB.SetString ~= nil and PersistentDB.GetString ~= nil then
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
    if PersistentDB.SetStructuredData == nil then
        return false, "PersistentDB is unavailable."
    end
    local ok, result = pcall(function()
        return PersistentDB:SetStructuredData(StorageKeys.RUNESQL_KEY, data)
    end)
    if not ok then
        return false, "PersistentDB rejected the RuneQL query."
    end
    if result == false then
        local readOK, stored = pcall(function()
            return PersistentDB:GetStructuredData(StorageKeys.RUNESQL_KEY)
        end)
        if not readOK or type(stored) ~= "table"
            or Json.encode(stored) ~= Json.encode(data) then
            return false, "PersistentDB rejected the RuneQL query."
        end
    end
    return true, nil
end

-- Create the sidebar selection ID for a valid saved query
function QueryStore.SelectionID(queryID)
    local numericID = math.tointeger(tonumber(queryID))
    if numericID == nil or numericID <= 0 then return nil end
    return SELECTION_PREFIX .. tostring(numericID)
end

-- Extract a saved query ID from a recognized sidebar selection
function QueryStore.QueryIDFromSelection(selection)
    if type(selection) ~= "string"
        or string.sub(selection, 1, #SELECTION_PREFIX) ~= SELECTION_PREFIX then
        return nil
    end
    local numericID = math.tointeger(tonumber(string.sub(selection, #SELECTION_PREFIX + 1)))
    return numericID ~= nil and numericID > 0 and tostring(numericID) or nil
end

-- Recognize selection IDs belonging to saved queries
function QueryStore:IsSelection(selection)
    return QueryStore.QueryIDFromSelection(selection) ~= nil
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

-- Resolve a sidebar selection to a copied saved query record
function QueryStore:GetBySelection(selection)
    local queryID = QueryStore.QueryIDFromSelection(selection)
    return queryID ~= nil and self:Get(queryID) or nil
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
QueryStore.SELECTION_PREFIX = SELECTION_PREFIX

return QueryStore
