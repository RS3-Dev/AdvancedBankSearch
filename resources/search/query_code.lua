-- Portable query codes. The JSON envelope follows Bank Tags' preview/share flow,
-- with a distinct format so tag layouts cannot be mistaken for query expressions.
local Json = require("resources/core/json")
local QueryBuilder = require("resources/search/query_builder")
local Text = require("resources/core/text")
local Code = { INPUT_LIMIT = 9999, MAX_QUERIES = 1000, MAX_FOLDERS = 200 }
local FORMAT, VERSION = "advancedbanksearch-queries", 1

local function name(value)
    if type(value) ~= "string" then return nil end
    value = Text.trim(value)
    return value ~= "" and #value <= 40 and value or nil
end
Code.Name = name

local function icon(value)
    if type(value) ~= "string" then return nil, true end
    if value:sub(1, 1) == "#" then
        local objectID = value:match("^#(%d+)$")
        objectID = objectID and math.tointeger(tonumber(objectID))
        if objectID == nil or objectID < 0 or objectID > 2147483647 then return nil, false end
    end
    return value, true
end

-- Bound optional visual metadata before walking it; invalid metadata never changes
-- the authoritative RuneQL text and simply opens in Advanced after import.
local function safeBuilder(builder)
    local count, groups = 0, 0
    local function check(group, depth)
        if depth > 3 or type(group) ~= "table" or type(group.rules) ~= "table"
            or (group.match ~= "all" and group.match ~= "any") or #group.rules == 0 or #group.rules > 6 then return false end
        for _, rule in ipairs(group.rules) do
            if type(rule) ~= "table" then return false end
            if rule.rules ~= nil then
                groups = groups + 1
                if groups > 6 or not check(rule, depth + 1) then return false end
            else
                count = count + 1
                if count > 6 or type(rule.field) ~= "string" or type(rule.operator) ~= "string" then return false end
                if rule.negate ~= nil and type(rule.negate) ~= "boolean" then return false end
                for _, key in ipairs({ "value", "min", "max" }) do
                    if rule[key] ~= nil and type(rule[key]) ~= "string" and type(rule[key]) ~= "number" then return false end
                end
            end
        end
        return true
    end
    if check(builder, 0) then return QueryBuilder.Copy(builder) end
end

-- Encode a single query with its folder, or every query in sidebar order.
function Code.Encode(tree, onlyID)
    local data = { format = FORMAT, version = VERSION, queries = {}, folders = {}, order = {} }
    for _, node in ipairs(tree) do
        local folderAdded = false
        local function add(record)
            if onlyID ~= nil and record.id ~= onlyID then return end
            local copy = { name = record.name, query = record.query, builder = QueryBuilder.Copy(record.builder), icon = record.icon }
            if node.kind == "folder" then
                copy.folder = node.name
                if not folderAdded then
                    data.folders[#data.folders + 1] = { name = node.name, icon = node.icon, collapsed = node.collapsed }
                    data.order[#data.order + 1] = { kind = "folder", name = node.name }
                    folderAdded = true
                end
            else
                data.order[#data.order + 1] = { kind = "query", name = record.name }
            end
            data.queries[#data.queries + 1] = copy
        end
        if node.kind == "query" then add(node.query) else
            for _, record in ipairs(node.queries) do add(record) end
            if onlyID == nil and not folderAdded then
                data.folders[#data.folders + 1] = { name = node.name, icon = node.icon, collapsed = node.collapsed }
                data.order[#data.order + 1] = { kind = "folder", name = node.name }
            end
        end
    end
    return Json.encode(data)
end

-- Validate the whole preview before any import writes. Local IDs are never shared.
function Code.Decode(source, engine)
    if type(source) ~= "string" or Text.trim(source) == "" then return nil, "Paste a query share code first." end
    if #source > 1000000 then return nil, "The import is too large." end
    local ok, input = pcall(Json.decode, Text.trim(source))
    if not ok or type(input) ~= "table" or input.format ~= FORMAT or input.version ~= VERSION
        or type(input.queries) ~= "table" then return nil, "This is not a supported query share code." end
    if #input.queries == 0 then return nil, "The code contains no queries." end
    if #input.queries > Code.MAX_QUERIES then return nil, "The code contains too many queries." end
    if engine == nil or type(engine.Compile) ~= "function" then return nil, "Enable RuneQL to import queries." end
    local data = { queries = {}, folders = {}, order = {} }
    local folders, queries = {}, {}
    for _, folder in ipairs(type(input.folders) == "table" and input.folders or {}) do
        local title = type(folder) == "table" and name(folder.name) or nil
        if title == nil or #data.folders >= Code.MAX_FOLDERS then return nil, "The code has an invalid folder." end
        local key = string.lower(title)
        if folders[key] ~= nil then return nil, "The code repeats a folder name." end
        local folderIcon, validIcon = icon(folder.icon)
        if not validIcon then return nil, "The code has an invalid folder icon." end
        local copy = { name = title, key = key, icon = folderIcon,
            collapsed = folder.collapsed == true }
        folders[key], data.folders[#data.folders + 1] = copy, copy
    end
    for index, record in ipairs(input.queries) do
        local title = type(record) == "table" and name(record.name) or nil
        local expression = type(record) == "table" and type(record.query) == "string" and Text.trim(record.query) or ""
        if title == nil or expression == "" or #expression > 9999 then return nil, "Query " .. index .. " has an invalid name or expression." end
        local key = string.lower(title)
        if queries[key] ~= nil then return nil, "The code repeats a query name." end
        local compiled, plan, reason = pcall(engine.Compile, expression)
        if not compiled or plan == nil then return nil, title .. ": " .. tostring(reason or plan or "RuneQL could not read the query.") end
        local folderKey = type(record.folder) == "string" and string.lower(record.folder) or nil
        if folderKey ~= nil and folders[folderKey] == nil then return nil, "A query refers to an unknown folder." end
        local builder = safeBuilder(record.builder)
        local queryIcon, validIcon = icon(record.icon)
        if not validIcon then return nil, "The code has an invalid query icon." end
        local copy = { name = title, query = expression, folder = folderKey,
            icon = queryIcon,
            builder = builder and QueryBuilder.Restore(builder, expression) or nil }
        queries[key], data.queries[#data.queries + 1] = copy, copy
    end
    local placed = {}
    local function place(kind, key)
        local record = kind == "query" and queries[key] or kind == "folder" and folders[key]
        local token = kind .. ":" .. key
        if record ~= nil and not placed[token] then
            placed[token] = true
            data.order[#data.order + 1] = { kind = kind, key = key }
        end
    end
    for _, entry in ipairs(type(input.order) == "table" and input.order or {}) do
        if type(entry) == "table" and type(entry.name) == "string" and (entry.kind == "query" or entry.kind == "folder") then
            place(entry.kind, string.lower(entry.name))
        end
    end
    for _, record in ipairs(data.queries) do if record.folder == nil then place("query", string.lower(record.name)) end end
    for _, folder in ipairs(data.folders) do place("folder", folder.key) end
    return data
end
return Code
