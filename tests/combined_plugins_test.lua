package.path = "./?.lua;./?/init.lua;" .. package.path

-- Load Bank Cleaner from BANKCLEANER_DIST beside this plugin
-- Check that they share nothing and unload or reload independently
-- FAKE HOST: stand-in loader, components, and widgets, not the game client

local cleanerFolder = os.getenv("BANKCLEANER_DIST")
if cleanerFolder == nil then
    print("combined_plugins_test: skipped; set BANKCLEANER_DIST to a built bankcleaner folder")
    return
end
cleanerFolder = string.gsub(cleanerFolder, "\\", "/")
assert(io.open(cleanerFolder .. "/main.lua", "rb"), "no built Bank Cleaner at " .. cleanerFolder):close()

local Harness = require("tools/test_support/search_harness")

-- Check every module, subscription, and key is in its plugin's namespace
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

    -- Both tabs show in owner order, and connecting shows no page
    local _, layout = h:OpenBank()
    h:Tick(2)
    local ids = {}
    for index, tab in ipairs(layout.extensionTabs) do ids[index] = tab.id end
    assert(table.concat(ids, " ") == "__bankutils_ext_tab:advancedbanksearch/search __bankutils_ext_tab:bankcleaner/cleanup",
        table.concat(ids, " "))
    assert(not cleanerApp.handle:GetState().pageVisible and not searchApp.handle:GetState().pageVisible)
    assert(layout.shownPage == nil)

    -- Each plugin's pages work from its own tab
    h:ChooseTab("advancedbanksearch", "search")
    h:Tick(2)
    assert(searchApp.tab.controls ~= nil and not cleanerApp.tabActive)
    assert(searchApp:SaveQuery(nil, "Bars", "bar"))
    searchApp:SetText("bar")
    h:Tick(2)
    assert(layout.shownPage.key == "search:1")
    h:ChooseTab("bankcleaner", "cleanup")
    h:Tick(4)
    assert(searchApp.shownPage == nil and cleanerApp.tabActive and not cleanerApp:IsBusy())
    -- Search shows its page again, and Bank Cleaner's row list then shows a category in the
    -- same tick; Search's bank and price updates before it hears that leave Cleaner's page
    searchApp:SetText("iron")
    assert(searchApp.shownPage == "search" and layout.shownPage.key == "search:2")
    assert(cleanerApp.sidebar ~= nil and cleanerApp.sidebar.list:Click("metal_bank"))
    searchApp:OnBankItems()
    searchApp:DependencyChanged("geprices", true)
    assert(layout.shownPage.key == "cleanup:metal_bank" and searchApp.shownPage == "search")
    h:Tick(2)
    assert(layout.shownPage.key == "cleanup:metal_bank" and cleanerApp.shownCategory == "metal_bank")
    assert(searchApp.shownPage == nil)
    checkSeparate(h, cleaner, search)

    -- Reloading this plugin leaves Bank Cleaner's tab and page
    h.host:Reload("advancedbanksearch", { freshEnvironment = true })
    h:Tick(2)
    assert(h:App():IsConnected() and cleanerApp:IsConnected())
    assert(h:App().queries:Get("1").name == "Bars")
    h.host:Unload("advancedbanksearch")
    h:Tick(2)
    assert(cleanerApp:IsConnected() and layout.shownPage.key == "cleanup:metal_bank")
    assert(#h.host:SubscriptionsOf("advancedbanksearch") == 0)

    -- Once Bank Cleaner unloads, nothing of either remains in Core
    h.host:Unload("bankcleaner")
    h:Tick(2)
    assert(#layout.extensionTabs == 0 and #h.host:SubscriptionsOf("bankcleaner") == 0)
    h.host:Unload("bankcore")
end

print("combined_plugins_test: ok")
