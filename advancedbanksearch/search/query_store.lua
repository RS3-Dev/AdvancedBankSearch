-- Persist saved query records, and the folders and order they are listed in, while RuneQL
-- owns parsing and evaluation. Queries are saved as JSON text in this plugin's own keys; the
-- integrated plugin's bankutils:runesql:* data is never read. A save from before folders
-- has only its queries, which load ungrouped in their saved order

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
local GONE = "That RuneQL query no longer exists."
local FOLDER_GONE = "That folder no longer exists."

-- Copy the supported fields of a saved query record
local function copyRecord(record)
    if type(record) ~= "table" then return nil end
    return {
        id = tostring(record.id or ""),
        name = tostring(record.name or ""),
        query = tostring(record.query or ""),
    }
end

-- Return a list field of saved data, or an empty list when it is missing
local function listOf(data, field)
    return type(data) == "table" and type(data[field]) == "table" and data[field] or {}
end

-- Copy query records, folders, and the order, and normalize the next available IDs
local function copyData(data)
    local result = {
        schemaVersion = 1,
        nextId = math.max(1, math.floor(tonumber(data and data.nextId) or 1)),
        nextFolderId = math.max(1, math.floor(tonumber(data and data.nextFolderId) or 1)),
        queries = {},
        folders = {},
        order = {},
    }
    for _, record in ipairs(listOf(data, "queries")) do
        local copy = copyRecord(record)
        if copy ~= nil then result.queries[#result.queries + 1] = copy end
    end
    for _, folder in ipairs(listOf(data, "folders")) do
        if type(folder) == "table" then
            local members = {}
            for _, queryID in ipairs(listOf(folder, "queries")) do members[#members + 1] = tostring(queryID) end
            result.folders[#result.folders + 1] = { id = tostring(folder.id or ""), name = tostring(folder.name or ""),
                collapsed = folder.collapsed == true, queries = members }
        end
    end
    for _, entry in ipairs(listOf(data, "order")) do
        if type(entry) == "table" then
            result.order[#result.order + 1] = { kind = tostring(entry.kind or ""), id = tostring(entry.id or "") }
        end
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

-- Trim a folder name and reject a missing or overlong one
local function validateFolderName(name)
    name = trim(name)
    if name == "" then return nil, "Enter a folder name." end
    if #name > MAX_NAME_LENGTH then return nil, "Folder names can contain at most 40 characters." end
    return name, nil
end

-- Keep the folders and order consistent with the queries: each query is in at most one
-- folder, the first that lists it; an ID that names nothing is dropped; and each query or
-- folder the order misses goes at the end, queries in their saved order first
local function normalize(data)
    local known, claimed, folderByID, largestID = {}, {}, {}, 0
    for _, record in ipairs(data.queries) do known[record.id] = true end
    local folders = {}
    for _, folder in ipairs(data.folders) do
        local numericID = math.tointeger(tonumber(folder.id))
        local name = validateFolderName(folder.name)
        if numericID ~= nil and numericID > 0 and tostring(numericID) == folder.id and name ~= nil
            and folderByID[folder.id] == nil then
            local members = {}
            for _, queryID in ipairs(folder.queries) do
                if known[queryID] and not claimed[queryID] then
                    claimed[queryID] = true
                    members[#members + 1] = queryID
                end
            end
            folder.name, folder.queries = name, members
            folderByID[folder.id] = folder
            folders[#folders + 1] = folder
            largestID = math.max(largestID, numericID)
        end
    end
    local order, placed = {}, {}
    -- Place one query or folder in the top level once
    local function place(kind, entryID)
        local key = kind .. ":" .. entryID
        if placed[key] then return end
        placed[key] = true
        order[#order + 1] = { kind = kind, id = entryID }
    end
    for _, entry in ipairs(data.order) do
        if (entry.kind == "folder" and folderByID[entry.id] ~= nil)
            or (entry.kind == "query" and known[entry.id] and not claimed[entry.id]) then
            place(entry.kind, entry.id)
        end
    end
    for _, record in ipairs(data.queries) do
        if not claimed[record.id] then place("query", record.id) end
    end
    for _, folder in ipairs(folders) do place("folder", folder.id) end
    data.folders, data.order = folders, order
    data.nextFolderId = math.max(data.nextFolderId, largestID + 1)
    return data
end

-- Find a folder in saved data by ID
local function findFolder(data, folderID)
    for _, folder in ipairs(data.folders) do
        if folder.id == folderID then return folder end
    end
    return nil
end

-- Find a folder whose name matches, ignoring case, other than the one excluded
local function folderNamed(data, name, exceptID)
    local wanted = string.lower(name)
    for _, folder in ipairs(data.folders) do
        if folder.id ~= exceptID and string.lower(folder.name) == wanted then return folder end
    end
    return nil
end

-- Take a query out of the top level or its folder, and return where in the top level it
-- was: its own place, or just after its folder
local function detach(data, queryID)
    for index, entry in ipairs(data.order) do
        if entry.kind == "query" and entry.id == queryID then
            table.remove(data.order, index)
            return index
        elseif entry.kind == "folder" then
            local members = findFolder(data, entry.id).queries
            for memberIndex, member in ipairs(members) do
                if member == queryID then
                    table.remove(members, memberIndex)
                    return index + 1
                end
            end
        end
    end
    return #data.order + 1
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

-- Load the saved queries, retaining only valid unique query IDs, then the folders and order
-- that fit them. A save that cannot be read loads as empty with its error, and is never
-- overwritten
local function loadData()
    local saved, loadError = loadTextData()
    if saved == nil then return normalize(copyData(nil)), loadError end

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
    return normalize(data)
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

-- Normalize and persist changed data, adopting it only once it is saved
function QueryStore:Commit(nextData)
    normalize(nextData)
    local persisted, reason = self:Persist(nextData)
    if not persisted then return false, reason end
    self.data = nextData
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

-- Validate and persist a copied query set before adopting the edit in memory. An edited
-- query keeps its folder and place; a new one goes at the end of the top level
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
        if savedRecord == nil then return false, nil, GONE end
    else
        savedRecord = {
            id = tostring(nextData.nextId),
            name = name,
            query = query,
        }
        nextData.nextId = nextData.nextId + 1
        nextData.queries[#nextData.queries + 1] = savedRecord
    end

    local persisted, persistReason = self:Commit(nextData)
    if not persisted then return false, nil, persistReason end
    return true, copyRecord(savedRecord), nil
end

-- Persist a copied query set without the selected record, and out of its folder, before
-- adopting it
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
    if not removed then return false, GONE end
    return self:Commit(nextData)
end

-- List the queries and folders in sidebar order: { kind = "query", query } for a query
-- outside every folder, and { kind = "folder", id, name, collapsed, queries } for a folder
function QueryStore:Tree()
    local records = {}
    for _, record in ipairs(self.data.queries) do records[record.id] = record end
    local nodes = {}
    for _, entry in ipairs(self.data.order) do
        if entry.kind == "query" then
            nodes[#nodes + 1] = { kind = "query", query = copyRecord(records[entry.id]) }
        else
            local folder = findFolder(self.data, entry.id)
            local members = {}
            for index, queryID in ipairs(folder.queries) do members[index] = copyRecord(records[queryID]) end
            nodes[#nodes + 1] = { kind = "folder", id = folder.id, name = folder.name,
                collapsed = folder.collapsed, queries = members }
        end
    end
    return nodes
end

-- Return a copy of one folder's name, collapse state, and member count, or nil
function QueryStore:GetFolder(folderID)
    local folder = findFolder(self.data, tostring(folderID or ""))
    if folder == nil then return nil end
    return { id = folder.id, name = folder.name, collapsed = folder.collapsed, count = #folder.queries }
end

-- List the folders in sidebar order
function QueryStore:Folders()
    local folders = {}
    for _, node in ipairs(self:Tree()) do
        if node.kind == "folder" then folders[#folders + 1] = { id = node.id, name = node.name } end
    end
    return folders
end

-- Return the ID of the folder a query is in, or nil
function QueryStore:FolderOf(queryID)
    queryID = tostring(queryID or "")
    for _, folder in ipairs(self.data.folders) do
        for _, member in ipairs(folder.queries) do
            if member == queryID then return folder.id end
        end
    end
    return nil
end

-- Create a folder, holding a query when one is given: the folder takes the query's place
-- in the top level, or the place just after the query's old folder. Returns the folder ID
function QueryStore:CreateFolder(name, queryID)
    local reason
    name, reason = validateFolderName(name)
    if name == nil then return false, nil, reason end
    if folderNamed(self.data, name) ~= nil then return false, nil, "A folder with that name already exists." end
    queryID = queryID ~= nil and tostring(queryID) or nil
    if queryID ~= nil and self:Get(queryID) == nil then return false, nil, GONE end
    local nextData = copyData(self.data)
    local folderID = tostring(nextData.nextFolderId)
    nextData.nextFolderId = nextData.nextFolderId + 1
    local position = queryID ~= nil and detach(nextData, queryID) or #nextData.order + 1
    nextData.folders[#nextData.folders + 1] = { id = folderID, name = name, collapsed = false,
        queries = { queryID } }
    table.insert(nextData.order, position, { kind = "folder", id = folderID })
    local saved, saveReason = self:Commit(nextData)
    if not saved then return false, nil, saveReason end
    return true, folderID, nil
end

-- Rename a folder; its ID and members stay
function QueryStore:RenameFolder(folderID, name)
    folderID = tostring(folderID or "")
    if findFolder(self.data, folderID) == nil then return false, FOLDER_GONE end
    local reason
    name, reason = validateFolderName(name)
    if name == nil then return false, reason end
    if folderNamed(self.data, name, folderID) ~= nil then return false, "A folder with that name already exists." end
    local nextData = copyData(self.data)
    findFolder(nextData, folderID).name = name
    return self:Commit(nextData)
end

-- Remove a folder, keeping its queries, in order, where it was in the top level
function QueryStore:DeleteFolder(folderID)
    folderID = tostring(folderID or "")
    local nextData = copyData(self.data)
    local folder = findFolder(nextData, folderID)
    if folder == nil then return false, FOLDER_GONE end
    for index, entry in ipairs(nextData.order) do
        if entry.kind == "folder" and entry.id == folderID then
            table.remove(nextData.order, index)
            for offset, queryID in ipairs(folder.queries) do
                table.insert(nextData.order, index + offset - 1, { kind = "query", id = queryID })
            end
            break
        end
    end
    for index, value in ipairs(nextData.folders) do
        if value == folder then table.remove(nextData.folders, index) end
    end
    return self:Commit(nextData)
end

-- Collapse or expand a folder
function QueryStore:SetFolderCollapsed(folderID, collapsed)
    collapsed = collapsed == true
    local nextData = copyData(self.data)
    local folder = findFolder(nextData, tostring(folderID or ""))
    if folder == nil then return false, FOLDER_GONE end
    if folder.collapsed == collapsed then return true, nil end
    folder.collapsed = collapsed
    return self:Commit(nextData)
end

-- Move a query to the end of a folder, or, when the folder ID is nil, out of its folder to
-- just after it
function QueryStore:MoveToFolder(queryID, folderID)
    queryID = tostring(queryID or "")
    folderID = folderID ~= nil and tostring(folderID) or nil
    if self:Get(queryID) == nil then return false, GONE end
    if folderID ~= nil and findFolder(self.data, folderID) == nil then return false, FOLDER_GONE end
    if self:FolderOf(queryID) == folderID then return true, nil end
    local nextData = copyData(self.data)
    local position = detach(nextData, queryID)
    if folderID ~= nil then
        local members = findFolder(nextData, folderID).queries
        members[#members + 1] = queryID
    else
        table.insert(nextData.order, position, { kind = "query", id = queryID })
    end
    return self:Commit(nextData)
end

-- Move a folder or query one step among its siblings: the top level, or the query's folder.
-- kind is "folder" or "query" and offset is -1 or 1. A move past either end changes nothing
-- and gives no reason
function QueryStore:Move(kind, entryID, offset)
    if offset ~= -1 and offset ~= 1 then return false, "Choose up or down." end
    entryID = tostring(entryID or "")
    local nextData = copyData(self.data)
    local folderID = kind == "query" and self:FolderOf(entryID) or nil
    local siblings = folderID ~= nil and findFolder(nextData, folderID).queries or nextData.order
    local source
    for index, sibling in ipairs(siblings) do
        if sibling == entryID or (type(sibling) == "table" and sibling.kind == kind and sibling.id == entryID) then
            source = index
        end
    end
    if source == nil then return false, "That entry no longer exists." end
    local destination = source + offset
    if destination < 1 or destination > #siblings then return false, nil end
    siblings[source], siblings[destination] = siblings[destination], siblings[source]
    return self:Commit(nextData)
end

QueryStore.MAX_NAME_LENGTH = MAX_NAME_LENGTH
QueryStore.MAX_QUERY_LENGTH = MAX_QUERY_LENGTH
QueryStore.TEXT_STORE = TEXT_STORE

return QueryStore
