-- Start Advanced Bank Search on top of Bank Core
-- Required plugins are injected before startup; shutdown releases their handles.

local SESSION_KEY = "__advancedbanksearch_session"

local previous = rawget(_G, SESSION_KEY)
if previous ~= nil then pcall(function() previous:Shutdown() end) end
-- A reload reuses the same Lua state, so drop the old app before loading modules again
if rawget(_G, SESSION_KEY) == previous then _G[SESSION_KEY] = nil end
previous = nil
pcall(function() collectgarbage("collect") end)

-- Clear this plugin's saved modules so a reload uses the latest code
-- Keep this list aligned with the runtime modules checked by tools/check.lua
if package ~= nil and package.loaded ~= nil then
    for _, moduleName in ipairs({
        "resources/app",
        "resources/core/chunked_string_store",
        "resources/core/json",
        "resources/core/object_config",
        "resources/core/text",
        "resources/search/bank_controls",
        "resources/search/confirm_window",
        "resources/search/folder_dialog",
        "resources/search/geometry",
        "resources/search/icon_catalog",
        "resources/search/icon_picker",
        "resources/search/import_share",
        "resources/search/import_share_draft",
        "resources/search/item_fields",
        "resources/search/item_identity",
        "resources/search/list_parts",
        "resources/search/menu_entries",
        "resources/search/name_icon_editor",
        "resources/search/native_ui",
        "resources/search/object_config",
        "resources/search/query_builder",
        "resources/search/query_code",
        "resources/search/query_editor",
        "resources/search/query_list",
        "resources/search/query_list_drag",
        "resources/search/query_menus",
        "resources/search/query_sharing",
        "resources/search/query_store",
        "resources/search/ranking",
        "resources/search/search_tab",
        "resources/search/sidebar_rows",
        "resources/search/sidebar_theme",
        "resources/settings",
    }) do
        package.loaded[moduleName] = nil
    end
end

local App = require("resources/app")
local app = App.new()
_G[SESSION_KEY] = app
app:Start()

-- Connect or release Bank Core and track optional dependencies
function PluginDependencyUpdate(event)
    local name = event.pluginIdentifier
    if name ~= "bankcore" then
        app:DependencyChanged(name, event.enabled)
        return
    end
    if event.enabled then app:Connect() else app:Disconnect() end
end

-- Stop the session and drop its reload reference on unload
function PluginShutdown()
    app:Shutdown()
    if rawget(_G, SESSION_KEY) == app then _G[SESSION_KEY] = nil end
end
