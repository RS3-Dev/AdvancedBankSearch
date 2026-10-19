-- Start Advanced Bank Search: RuneQL search and saved queries in the bank sidebar, shown
-- through Bank Core's public API. Bank Core, RuneQL, GE Prices, and Bank Tags are optional
-- dependencies only because the host reports changes for optional dependencies; without
-- Bank Core, the plugin panel says it is needed

local SESSION_KEY = "__advancedbanksearch_session"

local previous = rawget(_G, SESSION_KEY)
if previous ~= nil then pcall(function() previous:Shutdown() end) end
-- Reload shares the Lua state, so release the old reference before rebuilding modules
if rawget(_G, SESSION_KEY) == previous then _G[SESSION_KEY] = nil end
previous = nil
pcall(function() collectgarbage("collect") end)

-- The host retains modules across reloads; evict this plugin's cache to keep callbacks current.
-- tools/build.lua writes the list into the built main.lua, so run the built folder, not this file
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

-- Connect when Bank Core loads and let go when it unloads; RuneQL, GE Prices, and Bank Tags
-- are read only while the host last reported them loaded
function PluginDependencyUpdate(event)
    local name = event.pluginIdentifier
    if name ~= "bankcore" then
        app:DependencyChanged(name, event.enabled)
        return
    end
    if event.enabled then app:Connect() else app:Disconnect() end
end

-- Stop the session and release its reload reference when the host unloads the plugin
function PluginShutdown()
    app:Shutdown()
    if rawget(_G, SESSION_KEY) == app then _G[SESSION_KEY] = nil end
end
