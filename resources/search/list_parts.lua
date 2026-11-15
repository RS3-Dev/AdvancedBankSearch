-- Adapted from Bank Tags: sidebar/tag_list_parts.lua
-- Share row names and sizes for drawing and dragging

local SidebarRows = require("resources/search/sidebar_rows")
local Parts = {
    FOLDER_ENTRY_PREFIX = "folder:",
    ROW_HEIGHT = 30,
    ENTRY_HEIGHT = SidebarRows.ENTRY_HEIGHT,
}
local FOLDER_ENTRY_PREFIX = Parts.FOLDER_ENTRY_PREFIX

-- Read the folder named by a sidebar row
local function folderKeyOf(entryID)
    entryID = tostring(entryID or "")
    if string.sub(entryID, 1, #FOLDER_ENTRY_PREFIX) ~= FOLDER_ENTRY_PREFIX then return nil end
    return string.sub(entryID, #FOLDER_ENTRY_PREFIX + 1)
end

-- Describe a row as a query or folder
local function sidebarEntry(entryID)
    local folderKey = folderKeyOf(entryID)
    if folderKey ~= nil then return { kind = "folder", id = folderKey } end
    return { kind = "query", id = entryID }
end

Parts.folderKeyOf = folderKeyOf
Parts.sidebarEntry = sidebarEntry

return Parts
