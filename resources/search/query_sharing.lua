-- Share queries and stage an entire import before publishing a single new save.
local Code = require("resources/search/query_code")
local Json = require("resources/core/json")
local ItemIdentity = require("resources/search/item_identity")
local Sharing = {}

function Sharing:QueryExports()
    local result, tree = {}, self:Tree()
    if #self:All() > 1 then result[#result + 1] = { name = "All queries (backup)", value = Code.Encode(tree) } end
    for _, node in ipairs(tree) do
        local function add(record)
            result[#result + 1] = { name = record.name, value = Code.Encode(tree, record.id) }
        end
        if node.kind == "query" then add(node.query) else for _, record in ipairs(node.queries) do add(record) end end
    end
    return result
end

function Sharing:ImportText(source, options, engine)
    if self.loadError ~= nil then return false, nil, self.loadError end
    local imported, problem = Code.Decode(source, engine)
    if imported == nil then return false, nil, problem end
    local data = Json.decode(Json.encode(self.data))
    local folderByName, folderByID = {}, {}
    for _, folder in ipairs(data.folders) do folderByName[string.lower(folder.name)], folderByID[folder.id] = folder, folder end
    if options ~= nil then
        if #imported.queries ~= 1 then return false, nil, "Only a single-query code can be customized." end
        local record = imported.queries[1]
        local title = Code.Name(options.name or record.name)
        if title == nil then return false, nil, "Enter a query name of up to 40 characters." end
        local previousKey = string.lower(record.name)
        record.name = title
        for _, entry in ipairs(imported.order) do
            if entry.kind == "query" and entry.key == previousKey then entry.key = string.lower(title) end
        end
        if options.spriteObjectID ~= nil then
            local objectID = math.tointeger(tonumber(options.spriteObjectID))
            if objectID == nil or objectID < 0 or objectID > 2147483647 then return false, nil, "Choose a valid item icon." end
            record.icon = ItemIdentity.Reference(objectID)
        end
        if options.newFolderName ~= nil then
            local folderName = Code.Name(options.newFolderName)
            if folderName == nil then return false, nil, "Enter a folder name of up to 40 characters." end
            record.folder = string.lower(folderName)
            imported.folders[#imported.folders + 1] = { name = folderName, key = record.folder, collapsed = false }
        elseif options.folderID == false then
            record.folder = nil
        elseif options.folderID ~= nil then
            local folder = folderByID[options.folderID]
            if folder == nil then return false, nil, "The selected folder no longer exists." end
            record.folder, record.destinationID = nil, folder.id
        elseif options.sharedFolder ~= nil then
            local found = false
            for _, folder in ipairs(imported.folders) do if folder.key == options.sharedFolder then found = true end end
            if not found then return false, nil, "The shared folder no longer exists." end
            record.folder = options.sharedFolder
        end
    end
    local usedFolders, mappedFolders, newFolders = {}, {}, {}
    for _, record in ipairs(imported.queries) do if record.folder ~= nil then usedFolders[record.folder] = true end end
    if options == nil then for _, folder in ipairs(imported.folders) do usedFolders[folder.key] = true end end
    for _, folder in ipairs(imported.folders) do
        if usedFolders[folder.key] and mappedFolders[folder.key] == nil then
            local destination = folderByName[folder.key]
            if destination == nil then
                destination = { id = tostring(data.nextFolderId), name = folder.name, icon = folder.icon,
                    collapsed = folder.collapsed == true, queries = {} }
                data.nextFolderId = data.nextFolderId + 1
                data.folders[#data.folders + 1] = destination
                folderByName[folder.key], folderByID[destination.id], newFolders[destination.id] = destination, destination, true
            end
            mappedFolders[folder.key] = destination.id
        end
    end
    local recordsByName, importedIDs, mappedQueries = {}, {}, {}
    for _, record in ipairs(data.queries) do recordsByName[string.lower(record.name)] = record end
    for _, record in ipairs(imported.queries) do
        local key = string.lower(record.name)
        local saved = recordsByName[key]
        if saved == nil then
            saved = { id = tostring(data.nextId) }
            data.nextId = data.nextId + 1
            data.queries[#data.queries + 1] = saved
        end
        saved.name, saved.query, saved.icon, saved.builder = record.name, record.query, record.icon, record.builder
        record.destinationID = record.destinationID or mappedFolders[record.folder]
        mappedQueries[key], importedIDs[saved.id] = saved, true
        record.savedID = saved.id
    end
    -- Remove old placements before assigning the imported queries to destinations.
    local oldOrder = {}
    for _, entry in ipairs(data.order) do
        if entry.kind ~= "query" or not importedIDs[entry.id] then oldOrder[#oldOrder + 1] = entry end
    end
    for _, folder in ipairs(data.folders) do
        for index = #folder.queries, 1, -1 do
            if importedIDs[folder.queries[index]] then table.remove(folder.queries, index) end
        end
    end
    for _, record in ipairs(imported.queries) do
        if record.destinationID ~= nil then
            local members = folderByID[record.destinationID].queries
            members[#members + 1] = record.savedID
        end
    end
    local order, placed = {}, {}
    local function place(kind, entryID)
        if entryID == nil then return end
        local key = kind .. ":" .. entryID
        if placed[key] then return end
        placed[key] = true
        order[#order + 1] = { kind = kind, id = entryID }
    end
    for _, entry in ipairs(imported.order) do
        if entry.kind == "folder" then
            local folderID = mappedFolders[entry.key]
            if newFolders[folderID] then place("folder", folderID) end
        else
            local record = mappedQueries[entry.key]
            if record ~= nil then
                local folderID
                for _, importedRecord in ipairs(imported.queries) do
                    if importedRecord.savedID == record.id then folderID = importedRecord.destinationID end
                end
                if folderID == nil then place("query", record.id) end
            end
        end
    end
    for _, record in ipairs(imported.queries) do
        if record.destinationID == nil then place("query", record.savedID)
        elseif newFolders[record.destinationID] then place("folder", record.destinationID) end
    end
    for _, entry in ipairs(oldOrder) do place(entry.kind, entry.id) end
    for _, folder in ipairs(data.folders) do place("folder", folder.id) end
    data.order = order
    local saved, reason = self:Commit(data)
    if not saved then return false, nil, reason end
    return true, { queries = #imported.queries }
end

function Sharing.install(store)
    store.QueryExports, store.ImportText = Sharing.QueryExports, Sharing.ImportText
end
return Sharing
