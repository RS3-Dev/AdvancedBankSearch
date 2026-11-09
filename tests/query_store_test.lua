package.path = "./?.lua;" .. package.path

-- Save, rename, and delete queries under this plugin's own keys

-- Saved data as the host keeps it per plugin; writes can be refused
local values = {}
local refuse = false
PersistentDB = {
    GetString = function(_, key) return values[key] end,
    SetString = function(_, key, value)
        if refuse then return false end
        values[key] = value
        return true
    end,
}

local QueryStore = require("resources/search/query_store")

-- Bank Utilities' queries in the same data are never read
values["bankutils:runesql:text:v1:manifest"] = "a:1"
values["bankutils:runesql:text:v1:a:1"] = '{"schemaVersion":1,"nextId":2,"queries":[{"id":"1","name":"Old","query":"old"}]}'
local store = QueryStore.new()
assert(store.loadError == nil and #store:All() == 0)

-- Saving validates, then writes only this plugin's keys
assert(select(3, store:Save(nil, "  ", "iron")) == "Enter a query name.")
assert(select(3, store:Save(nil, string.rep("x", 41), "iron")) == "Query names can contain at most 40 characters.")
assert(select(3, store:Save(nil, "Iron", " ")) == "Enter a RuneQL query.")
assert(select(3, store:Save(nil, "Iron", string.rep("x", 10000))) == "RuneQL queries can contain at most 9,999 characters.")
local saved, iron = store:Save(nil, " Iron ", "iron")
assert(saved and iron.id == "1" and iron.name == "Iron" and iron.query == "iron")
assert(values["advancedbanksearch:queries:v1:manifest"] == "a:1")
for key in pairs(values) do
    assert(string.find(key, "^advancedbanksearch:queries:v1:") or string.find(key, "^bankutils:"), key)
end
assert(select(3, store:Save(nil, "IRON", "other")) == "A RuneQL query with that name already exists.")
local _, ore = store:Save(nil, "Ore", "ore")
-- Renaming keeps the ID, and the same name may be saved again
assert(store:Save(ore.id, "Ores", "ore OR coal") and store:Get(ore.id).name == "Ores")
assert(store:Save(ore.id, "ores", "ore OR coal"))

-- A reload reads the same queries back
local reloaded = QueryStore.new()
assert(#reloaded:All() == 2 and reloaded:Get("2").query == "ore OR coal" and reloaded:FindName("IRON").id == "1")

-- A refused write changes neither the store nor the save
refuse = true
local manifest = values["advancedbanksearch:queries:v1:manifest"]
local ok, _, reason = store:Save(nil, "Lobster", "lobster")
assert(not ok and reason == "PersistentDB could not save RuneQL chunk 1.", reason)
assert(#store:All() == 2 and store:FindName("Lobster") == nil)
local deleted, deleteReason = store:Delete(iron.id)
assert(not deleted and deleteReason ~= nil and store:Get(iron.id) ~= nil)
assert(values["advancedbanksearch:queries:v1:manifest"] == manifest)
refuse = false

-- Deleting removes one query; a missing one says so
assert(store:Delete(iron.id) and store:Get(iron.id) == nil)
assert(select(2, store:Delete(iron.id)) == "That RuneQL query no longer exists.")
assert(select(3, store:Save("99", "Gone", "gone")) == "That RuneQL query no longer exists.")

-- Folders ---------------------------------------------------------------------------------

-- Describe the tree: names, Name[members] folders, + when collapsed
local function tree(target)
    local parts = {}
    for _, node in ipairs(target:Tree()) do
        if node.kind == "query" then
            parts[#parts + 1] = node.query.name
        else
            local members = {}
            for index, record in ipairs(node.queries) do members[index] = record.name end
            parts[#parts + 1] = node.name .. (node.collapsed and "+" or "") .. "[" .. table.concat(members, ",") .. "]"
        end
    end
    return table.concat(parts, " ")
end

-- Publish a save with only flat queries, no folders or order
local function publish(text)
    values["advancedbanksearch:queries:v1:manifest"] = "a:1"
    values["advancedbanksearch:queries:v1:a:1"] = text
end
publish('{"schemaVersion":1,"nextId":4,"queries":[{"id":"3","name":"Gems","query":"gem"},'
    .. '{"id":"1","name":"Bars","query":"bar"},{"id":"2","name":"Ores","query":"ore"}]}')
local folders = QueryStore.new()
assert(folders.loadError == nil and tree(folders) == "Gems Bars Ores", tree(folders))
assert(#folders:Folders() == 0 and folders:FolderOf("1") == nil)

-- A folder for a query takes its place; others go at the end
assert(select(3, folders:CreateFolder("  ", "1")) == "Enter a folder name.")
assert(select(3, folders:CreateFolder(string.rep("x", 41))) == "Folder names can contain at most 40 characters.")
local made, smithing = folders:CreateFolder(" Smithing ", "1")
assert(made and smithing == "1" and tree(folders) == "Gems Smithing[Bars] Ores", tree(folders))
assert(select(3, folders:CreateFolder("SMITHING")) == "A folder with that name already exists.")
assert(folders:MoveToFolder("2", smithing) and tree(folders) == "Gems Smithing[Bars,Ores]", tree(folders))
local _, empty = folders:CreateFolder("Empty")
assert(tree(folders) == "Gems Smithing[Bars,Ores] Empty[]" and folders:GetFolder(empty).count == 0)
-- Moving out of a folder puts the query just after it
assert(folders:MoveToFolder("1", nil) and tree(folders) == "Gems Smithing[Ores] Bars Empty[]", tree(folders))
assert(folders:MoveToFolder("1", smithing) and folders:MoveToFolder("1", smithing))
assert(tree(folders) == "Gems Smithing[Ores,Bars] Empty[]", tree(folders))
assert(select(2, folders:MoveToFolder("1", "99")) == "That folder no longer exists.")
assert(select(2, folders:MoveToFolder("99", smithing)) == "That RuneQL query no longer exists.")

-- Reordering inserts a dragged entry before/after a sibling, never across folders.
local function entry(kind,id) return {kind=kind,id=id} end
assert(folders:Reorder(entry("folder",smithing),entry("query","3"),false) and tree(folders) == "Smithing[Ores,Bars] Gems Empty[]", tree(folders))
assert(folders:Reorder(entry("query","1"),entry("query","2"),false) and tree(folders) == "Smithing[Bars,Ores] Gems Empty[]", tree(folders))
local edge, edgeReason = folders:Reorder(entry("query","1"),entry("query","2"),false)
assert(not edge and edgeReason == nil and tree(folders) == "Smithing[Bars,Ores] Gems Empty[]")
assert(folders:Reorder(entry("query","3"),entry("folder",empty),true) and tree(folders) == "Smithing[Bars,Ores] Empty[] Gems", tree(folders))
assert(select(2, folders:Reorder(entry("folder","99"),entry("folder",empty),true)) == "That entry no longer exists.")

-- Renaming keeps the folder's ID and members; collapsing is saved
assert(folders:RenameFolder(smithing, "Metal") and folders:GetFolder(smithing).name == "Metal")
assert(folders:RenameFolder(smithing, "metal") and select(2, folders:RenameFolder(smithing, "Empty"))
    == "A folder with that name already exists.")
assert(folders:SetFolderCollapsed(smithing, true) and tree(folders) == "metal+[Bars,Ores] Empty[] Gems", tree(folders))

-- Edits keep their folder and place; new queries go last
assert(folders:Save("2", "Ores", "ore OR coal") and folders:FolderOf("2") == smithing)
local _, logs = folders:Save(nil, "Logs", "logs")
assert(tree(folders) == "metal+[Bars,Ores] Empty[] Gems Logs", tree(folders))

-- A reload reads the same tree, IDs, and collapse state back
local again = QueryStore.new()
assert(tree(again) == "metal+[Bars,Ores] Empty[] Gems Logs" and again:FolderOf("1") == smithing, tree(again))
assert(again:Get("2").query == "ore OR coal" and again:FindName("logs").id == logs.id)

-- Deleting a query keeps its folder; ungrouping keeps member places
assert(folders:Delete("2") and tree(folders) == "metal+[Bars] Empty[] Gems Logs", tree(folders))
assert(folders:DeleteFolder(smithing) and tree(folders) == "Bars Empty[] Gems Logs", tree(folders))
assert(folders:DeleteFolder(empty) and tree(folders) == "Bars Gems Logs" and folders:GetFolder(empty) == nil)
assert(select(2, folders:DeleteFolder(empty)) == "That folder no longer exists.")
-- Folder IDs are never reused
local _, newer = folders:CreateFolder("New", "3")
assert(newer == "3" and tree(folders) == "Bars New[Gems] Logs", tree(folders))

-- A refused write changes no tree, collapse state, or save
refuse = true
local published = values["advancedbanksearch:queries:v1:manifest"]
local before = tree(folders)
assert(not folders:CreateFolder("Other", "1") and not folders:MoveToFolder("1", newer))
assert(not folders:Reorder(entry("query","1"),entry("query","3"),true) and not folders:RenameFolder(newer, "Renamed"))
assert(not folders:DeleteFolder(newer) and not folders:SetFolderCollapsed(newer, true))
assert(tree(folders) == before and values["advancedbanksearch:queries:v1:manifest"] == published, tree(folders))
refuse = false

-- Folder data that does not fit is dropped, keeping its queries
publish('{"schemaVersion":1,"nextId":4,"nextFolderId":2,"queries":[{"id":"1","name":"Bars","query":"bar"},'
    .. '{"id":"2","name":"Ores","query":"ore"},{"id":"3","name":"Gems","query":"gem"}],'
    .. '"folders":[{"id":"5","name":"A","queries":["2","9","2"]},{"id":"6","name":"B","queries":["2","1"]},'
    .. '{"id":"x","name":"Bad","queries":["3"]},{"id":"7","name":" ","queries":[]},"junk",'
    .. '{"id":"5","name":"Again","queries":[]}],'
    .. '"order":[{"kind":"folder","id":"6"},{"kind":"query","id":"2"},{"kind":"folder","id":"9"},7,'
    .. '{"kind":"folder","id":"6"}]}')
local messy = QueryStore.new()
assert(messy.loadError == nil and tree(messy) == "B[Bars] Gems A[Ores]", tree(messy))
local _, folderID = messy:CreateFolder("C")
assert(folderID == "7", folderID)
-- Folders and order that are not lists load as none
publish('{"schemaVersion":1,"nextId":2,"queries":[{"id":"1","name":"Bars","query":"bar"}],"folders":"x","order":{}}')
assert(tree(QueryStore.new()) == "Bars")

-- Visual conditions -------------------------------------------------------------------

local QueryBuilder = require("resources/search/query_builder")

-- Read the published save back as text
local function savedText()
    local generation = string.sub(values["advancedbanksearch:queries:v1:manifest"], 1, 1)
    return values["advancedbanksearch:queries:v1:" .. generation .. ":1"]
end

-- A save from before visual conditions writes back the same text
local legacy = '{"folders":[{"collapsed":false,"id":"1","name":"Metal","queries":["1"]}],"nextFolderId":2,'
    .. '"nextId":3,"order":[{"id":"1","kind":"folder"},{"id":"2","kind":"query"}],"queries":['
    .. '{"id":"1","name":"Bars","query":"name:(iron AND bar)"},{"id":"2","name":"Gems","query":"gem~1"}],'
    .. '"schemaVersion":1}'
publish(legacy)
local visual = QueryStore.new()
assert(visual:Get("1").builder == nil and visual:Get("2").builder == nil)
assert(visual:Save("2", "Gems", "gem~1") and savedText() == legacy, savedText())
-- Conditions sent with text they do not give are not kept
assert(visual:Save("2", "Gems", "gem~1", { match = "all", rules = { { field = "name", operator = "phrase",
    value = "gem" } } }))
assert(visual:Get("2").builder == nil and savedText() == legacy)

-- Conditions are saved beside the query they give and read back
local draft = { match = "any", rules = { { field = "name", operator = "words", value = 'big "bones"', min = "",
    max = "" }, { field = "price", operator = "between", value = "", min = "1k", max = "2.5k" } } }
local builtQuery, builtConditions = QueryBuilder.Build(draft)
assert(builtQuery == '(name:"big" AND name:"\\"bones\\"") OR price:[1000 TO 2500]', builtQuery)
local savedVisual, visualRecord = visual:Save(nil, "Bones", builtQuery, builtConditions)
assert(savedVisual and visualRecord.builder.rules[2].max == 2500 and visualRecord.id == "3")
assert(visual:FolderOf("1") == "1" and tree(visual) == "Metal[Bars] Gems Bones", tree(visual))
local reread = QueryStore.new():Get(visualRecord.id)
assert(reread.query == builtQuery and reread.builder.match == "any" and reread.builder.rules[1].value == 'big "bones"')
assert(QueryBuilder.Build(reread.builder) == builtQuery and reread.builder.rules[2].min == 1000)
-- Returned records are copies
reread.builder.rules[1].value = "changed"
assert(visual:Get(visualRecord.id).builder.rules[1].value == 'big "bones"')
-- Saving typed text drops the conditions, so they are never trusted for it
assert(visual:Save(visualRecord.id, "Bones", builtQuery .. " OR bones"))
assert(visual:Get(visualRecord.id).builder == nil and QueryStore.new():Get(visualRecord.id).builder == nil)
assert(visual:Save(visualRecord.id, "Bones", builtQuery, builtConditions))
assert(QueryStore.new():Get(visualRecord.id).builder ~= nil)

-- Conditions that no longer give the saved text load as none, keeping the query
local text = savedText()
publish((text:gsub('"max":2500', '"max":2600')))
local tampered = QueryStore.new():Get(visualRecord.id)
assert(tampered.query == builtQuery and tampered.builder == nil)
publish((text:gsub('"match":"any"', '"match":"most"')))
assert(QueryStore.new():Get(visualRecord.id).builder == nil)
publish((text:gsub('"rules":%[', '"rules":["junk",')))
assert(QueryStore.new():Get(visualRecord.id).builder == nil)
publish((text:gsub('"builder":{', '"builder":7,"x":{')))
assert(QueryStore.new():Get(visualRecord.id).builder == nil and #QueryStore.new():All() == 3)

-- A save missing a chunk loads empty with an error and is never overwritten
local broken = values["advancedbanksearch:queries:v1:manifest"]
local generation = string.sub(broken, 1, 1)
values["advancedbanksearch:queries:v1:" .. generation .. ":1"] = nil
local unreadable = QueryStore.new()
assert(unreadable.loadError ~= nil and #unreadable:All() == 0)
local refused, _, why = unreadable:Save(nil, "New", "new")
assert(not refused and why == unreadable.loadError)
assert(values["advancedbanksearch:queries:v1:manifest"] == broken)
-- Text that is not JSON is unreadable too
values["advancedbanksearch:queries:v1:" .. generation .. ":1"] = "{not json"
assert(QueryStore.new().loadError ~= nil)

print("query_store_test: ok")
