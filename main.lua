--[[
BSD 2-Clause License

Copyright (c) 2026 Advanced Bank Search contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

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
-- Keep this list aligned with the runtime modules checked by tests/check.lua
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
