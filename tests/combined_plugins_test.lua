package.path = "./?.lua;./?/init.lua;" .. package.path

-- Load the built Bank Cleaner (read from BANKCLEANER_DIST, which Bank Cleaner's own build
-- wrote) beside the built Advanced Bank Search, Bank Core, and RuneQL, in one shared Lua state
-- and again with separate states and cloned exports, to show the two plugins share no module
-- path, event, hook, reload global, tab, page, or saved data, and that either can unload or
-- reload without touching the other
-- FAKE HOST: stand-in loader, components, and widgets, not the game client

local cleanerFolder = os.getenv("BANKCLEANER_DIST")
if cleanerFolder == nil then
    print("combined_plugins_test: skipped; set BANKCLEANER_DIST to a built bankcleaner folder")
    return
end
cleanerFolder = string.gsub(cleanerFolder, "\\", "/")
assert(io.open(cleanerFolder .. "/main.lua", "rb"), "no built Bank Cleaner at " .. cleanerFolder):close()

local Harness = require("tools/test_support/search_harness")

-- Check every loaded module, subscription, and saved key belongs to its plugin's namespace
local function checkSeparate(h, cleaner, search)
    for moduleName in pairs(cleaner.env.package.loaded) do
        assert(string.find(moduleName, "^bankcleaner/"), "Bank Cleaner loaded " .. moduleName)
    end
    for moduleName in pairs(search.env.package.loaded) do
        assert(string.find(moduleName, "^advancedbanksearch/"), "Advanced Bank Search loaded " .. moduleName)
    end
    for _, subscription in ipairs(h.host:SubscriptionsOf("bankcleaner")) do
        assert(string.find(subscription, "%.bankcleaner_"), subscription)
    end
    for _, subscription in ipairs(h.host:SubscriptionsOf("advancedbanksearch")) do
        assert(string.find(subscription, "%.advancedbanksearch_"), subscription)
    end
    assert(next(h.databases.bankcleaner or {}) == nil)
    for key in pairs(h.databases.advancedbanksearch or {}) do
        assert(string.find(key, "^advancedbanksearch:"), key)
    end
end

for _, options in ipairs({ {}, { separateGlobals = true, cloneExports = true } }) do
    local h = Harness.new("combined", options)
    h:NameObjects({ { 2349, "Bronze bar" }, { 2351, "Iron bar" }, { 1944, "Egg" } })
    h.bankHost:SetItems({ { 2349, 3 }, { 2351, 1 }, { 1944, 2 } })
    h:LoadCore()
    h:LoadRuneQL()
    local cleaner = h.host:Load("bankcleaner", cleanerFolder)
    local search = h:LoadSearch()
    local cleanerApp = rawget(cleaner.env._G, "__bankcleaner_session")
    local searchApp = h:App()
    assert(cleanerApp ~= nil and searchApp ~= nil and cleanerApp ~= searchApp)
    assert(cleanerApp:IsConnected() and searchApp:IsConnected())

    -- Both tabs are in the rail, ordered by owner ID, and each owner has only its own pages
    local _, layout = h:OpenBank()
    h:Tick(2)
    local ids = {}
    for index, tab in ipairs(layout.extensionTabs) do ids[index] = tab.id end
    assert(table.concat(ids, " ") == "__bankutils_ext_tab:advancedbanksearch/search __bankutils_ext_tab:bankcleaner/cleanup",
        table.concat(ids, " "))
    assert(#cleanerApp.handle:GetState().pages == 13 and #searchApp.handle:GetState().pages == 2)

    -- Each works: a search page from the Search tab, then a category page from Cleanup
    h:ChooseTab("advancedbanksearch", "search")
    h:Tick(2)
    assert(searchApp.tab.controls ~= nil and not cleanerApp.tabActive)
    assert(searchApp:SaveQuery(nil, "Bars", "bar"))
    searchApp:SetText("bar")
    h:Tick(2)
    assert(layout.pageState.view.key == "search:1")
    h:ChooseTab("bankcleaner", "cleanup")
    h:Tick(4)
    assert(searchApp.shownPage == nil and cleanerApp.tabActive and not cleanerApp:IsBusy())
    assert(layout.list:Click("__bankutils_ext:bankcleaner/metal_bank"))
    h:Tick(2)
    assert(layout.pageState.view.key == "cleanup:metal_bank" and cleanerApp.shownPage == "metal_bank")
    checkSeparate(h, cleaner, search)

    -- Advanced Bank Search reloads and unloads; Bank Cleaner keeps its tab and page
    h.host:Reload("advancedbanksearch", { freshEnvironment = true })
    h:Tick(2)
    assert(h:App():IsConnected() and cleanerApp:IsConnected())
    assert(h:App().queries:Get("1").name == "Bars")
    h.host:Unload("advancedbanksearch")
    h:Tick(2)
    assert(cleanerApp:IsConnected() and layout.pageState.view.key == "cleanup:metal_bank")
    assert(#h.host:SubscriptionsOf("advancedbanksearch") == 0)

    -- Bank Cleaner unloads; nothing of either is left in Bank Core
    h.host:Unload("bankcleaner")
    h:Tick(2)
    assert(#layout.extensionTabs == 0 and #h.host:SubscriptionsOf("bankcleaner") == 0)
    h.host:Unload("bankcore")
end

print("combined_plugins_test: ok")
