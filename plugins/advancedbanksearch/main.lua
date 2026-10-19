-- Start Advanced Bank Search. This stage only loads the search modules; the connection to
-- Bank Core comes later

-- The host retains modules across reloads; evict this plugin's cache to keep callbacks current.
-- tools/build.lua writes the list into the built main.lua, so run the built folder, not this file
if package ~= nil and package.loaded ~= nil then
    for _, moduleName in ipairs({
        -- build: every module this plugin loads
    }) do
        package.loaded[moduleName] = nil
    end
end

require("advancedbanksearch/search/item_fields")
require("advancedbanksearch/search/query_editor")
