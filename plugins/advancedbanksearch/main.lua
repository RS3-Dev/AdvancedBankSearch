-- Start Advanced Bank Search on top of Bank Core
-- Dependencies are marked optional so the host tells us when they load or unload

local SESSION_KEY = "__advancedbanksearch_session"

local previous = rawget(_G, SESSION_KEY)
if previous ~= nil then pcall(function() previous:Shutdown() end) end
-- A reload reuses the same Lua state, so drop the old app before loading modules again
if rawget(_G, SESSION_KEY) == previous then _G[SESSION_KEY] = nil end
previous = nil
pcall(function() collectgarbage("collect") end)

-- The host keeps loaded modules across reloads, so clear this plugin's ones
-- tools/build.lua fills in this list, so run the built folder
if package ~= nil and package.loaded ~= nil then
    for _, moduleName in ipairs({
        -- build: every module this plugin loads
    }) do
        package.loaded[moduleName] = nil
    end
end

local App = require("advancedbanksearch/app")
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
