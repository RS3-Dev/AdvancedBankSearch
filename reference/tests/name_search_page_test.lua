package.path = "./?.lua;./?/init.lua;" .. package.path

-- Check that the replacement bank search builds its page through its page description
-- while the search field, native search controls, and All Items re-entry behave as before
-- Run all tests with Lua 5.4: lua54 tools/check.lua (toolchain notes in STAGE0_BASELINE.md)

local FakeBankHost = require("tools/test_support/fake_bank_host")
local host = FakeBankHost.install()
local TagStore = require("lib/features/tags/tag_store")
local NameSearchPage = require("lib/features/search/name_search_page")
local BankNameSearch = require("lib/features/search/bank_name_search")
local Text = require("lib/core/text")

local SEARCH = BankNameSearch.SELECTION_ID

-- Equal-length names tie on score, so bank order decides them; 303 is a placeholder
host:SetItems({
    { 301, 5, "Iron bar" },
    { 302, 5, "Iron ore" },
    { 303, 0, "Iron axe" },
    { 304, 5, "Iron platebody" },
    { 305, 5, "Lobster" },
})

-- Native search controls exist so the replacement field can park and restore them
local nativeSearch = {}
local getComponent = ui.Interfaces.GetComponent
ui.Interfaces.GetComponent = function(interfaces, interfaceID, staticID)
    if staticID == 230 or staticID == 231 or staticID == 254 or staticID == 257 then
        nativeSearch[staticID] = nativeSearch[staticID] or ui.Layer.new(nil)
        return nativeSearch[staticID]
    end
    return getComponent(interfaces, interfaceID, staticID)
end
ui.Margin = { new = function(...) return { ... } end }
prettyui.TextField = { new = function(parent, options)
    local field = ui.Layer.new(parent, options)
    field.value = options.text
    function field:SetText(text) self.value = text end
    return field
end }

local store = TagStore.new()
store:SetLayoutPlacement(false)
assert(store:CreateTag("ores"))
assert(store:AddTag("ores", 302))
local layout, features = host:NewLayout(store, { settings = { enableAdvancedSearch = true } })
features:CaptureBankNameSearchComponents()
for staticID, value in pairs(nativeSearch) do
    value:SetPos(staticID, 7)
    value:SetSize(50, 20)
    features.original[value] = { x = staticID, y = 7, width = 50, height = 20 }
end

-- Count search page builds and every page computation
local builds, pageApplies, searches = 0, 0, 0
local searchApply = NameSearchPage.Apply
NameSearchPage.Apply = function(owner, selection)
    assert(owner == layout and selection == SEARCH)
    builds = builds + 1
    return searchApply(owner, selection)
end
local pageApply = layout.pageState.Apply
layout.pageState.Apply = function(...)
    pageApplies = pageApplies + 1
    return pageApply(...)
end
local applySearch = layout.pageState.ApplySearch
layout.pageState.ApplySearch = function(...)
    searches = searches + 1
    return applySearch(...)
end

-- Return and reset the build counts
local function counts()
    local result = builds .. " " .. pageApplies .. " " .. searches
    builds, pageApplies, searches = 0, 0, 0
    return result
end

-- List the displayed objects in display order
local function shown()
    local entries = layout:VisibleMirrorEntries()
    table.sort(entries, function(left, right)
        if left.y == right.y then return left.x < right.x end
        return left.y < right.y
    end)
    local objects = {}
    for _, entry in ipairs(entries) do
        objects[#objects + 1] = tostring(entry.objectID) .. (entry.placeholder and "p" or "")
    end
    return table.concat(objects, " ")
end

-- Report whether each native search control sits at its saved place
local function nativeSearchHome()
    for staticID, value in pairs(nativeSearch) do
        if staticID ~= 230 and value.x ~= staticID then return false end
    end
    return true
end

-- Enabling the replacement field parks the native controls; lookup, title, and edit policy
-- come from the search page description
features:ApplyBankNameSearchSetting()
assert(features.bankSearchField ~= nil and not nativeSearchHome())
assert(nativeSearch[231].x == -10000 and nativeSearch[231].y == 7)
assert(layout:SelectionPage(SEARCH) == NameSearchPage)
assert(layout:IsGeneratedSelection(SEARCH))
assert(layout:DisplayTagName(SEARCH) == Text.titleCase(SEARCH))
assert(NameSearchPage.isMembershipEditable == false)

-- One character does not open the page
features:SetBankNameSearchQuery("i")
assert(layout.selectedTag == nil and counts() == "0 0 0")

-- Two characters open the transient page, built once through the description; equal scores
-- keep bank order and the placeholder stays a placeholder
features:SetBankNameSearchQuery("ir")
assert(layout.selectedTag == SEARCH and counts() == "1 0 1")
assert(shown() == "301 302 303p 304", shown())
assert(layout.nativeLease.interactionHitLayer ~= nil)

-- Typing more refreshes the same page through the same description, ranked by score
features:SetBankNameSearchQuery("iron ba")
assert(layout.selectedTag == SEARCH and counts() == "1 0 1")
assert(shown() == "301", shown())
features:SetBankNameSearchQuery("iron")
assert(counts() == "1 0 1" and shown() == "301 302 303p 304", shown())

-- No matches and text RuneQL cannot compile both publish an empty page, not the bank
features:SetBankNameSearchQuery("zzz")
assert(layout.selectedTag == SEARCH and layout.pageState.active and shown() == "")
features:SetBankNameSearchQuery("invalid(")
assert(layout.selectedTag == SEARCH and layout.pageState.active and shown() == "")
counts()

-- Deleting back to one character leaves the page but keeps the typed text
features:SetBankNameSearchQuery("iron")
counts()
features.bankSearchField:SetText("i")
features:SetBankNameSearchQuery("i")
assert(layout.selectedTag == nil and counts() == "0 1 0")
assert(features.bankSearchQuery == "i" and features.bankSearchField.value == "i")
assert(not layout.pageState.active and layout.nativeLease.interactionHitLayer == nil)
assert(features.preserveBankSearchQueryOnDeselect == false)

-- Selecting a tag clears the search text and builds only the tag page
features:SetBankNameSearchQuery("iron")
counts()
assert(layout:SetSelectedTag("ores"))
assert(counts() == "0 1 0" and shown() == "302")
assert(features.bankSearchQuery == "" and features.bankSearchField.value == "")

-- Clicking the replacement field returns to the native view and clears its text
features:SetBankNameSearchQuery("iron")
assert(layout.selectedTag == SEARCH)
features:ReturnToNativeSearch()
assert(layout.selectedTag == nil and features.bankSearchQuery == "")
assert(not layout.pageState.active)

-- Leaving All Items closes the page and clears its text
features:SetBankNameSearchQuery("iron")
counts()
layout:SetNativeViewAll(false)
assert(layout.selectedTag == nil and features.bankSearchQuery == "" and counts() == "0 1 0")

-- Text typed outside All Items is refused but kept, then opens the page on return
features:SetBankNameSearchQuery("lob")
assert(layout.selectedTag == nil and features.bankSearchQuery == "lob" and counts() == "0 0 0")
layout:SetNativeViewAll(true)
assert(layout.selectedTag == SEARCH and counts() == "1 0 1" and shown() == "305")

-- A price search waits for prices only while its page stays selected
local compile = runeql.Compile
runeql.Compile = function(query)
    local plan = compile(query)
    plan.Requirements = function() return { price = true } end
    return plan
end
geprices = { getPrice = function() return nil end, isReady = function() return false end }
features:SetBankNameSearchQuery("iron")
assert(features.runeQueryPriceWait == SEARCH and host:Listener("price_wait") ~= nil)
features:ReturnToNativeSearch()
assert(features.runeQueryPriceWait == nil and host:Listener("price_wait") == nil)
runeql.Compile = compile
geprices = nil

-- Turning the replacement field off leaves the page and restores the native controls
features:SetBankNameSearchQuery("iron")
counts()
layout.settings.enableAdvancedSearch = false
features:ApplyBankNameSearchSetting()
assert(layout.selectedTag == nil and counts() == "0 1 0")
assert(features.bankSearchField == nil and features.bankSearchQuery == "")
assert(nativeSearchHome())

NameSearchPage.Apply = searchApply
print("name_search_page_test: ok")
