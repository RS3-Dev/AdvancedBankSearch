package.path = "./?.lua;./?/init.lua;" .. package.path

-- FAKE HOST: exercise real Core state delivery and native page cleanup.
local Harness = require("tools/test_support/search_harness")
local h = Harness.new("bank_state", { separateGlobals = true, cloneExports = true })
h:NameObjects({ { 101, "Iron bar" } })
h.bankHost:SetItems({ { 101, 5 } })
local core = h:LoadCore()
local register, listener = core.result.Register
local closes, reads = 0, 0
core.result.Register = function(spec)
    if spec.id == "advancedbanksearch" then listener = assert(spec.onBankStateChanged) end
    local ext, reason = register(spec)
    if ext ~= nil and spec.id == "advancedbanksearch" then
        local close, read = ext.Close, ext.GetBankState
        ext.Close = function(...) closes = closes + 1; return close(...) end
        ext.GetBankState = function(...) reads = reads + 1; return read(...) end
    end
    return ext, reason
end
h:LoadRuneQL()
h:LoadSearch()
local app = h:App()
assert(app:IsConnected() and reads == 1)
local session, layout = h:OpenBank()
h:Tick(2)
local saved, record = app.queries:Save(nil, "Iron", "iron")
assert(saved)
local persisted = app.queries.data
local function available()
    return { bankOpen = true, viewAll = true, searchActive = false, filterActive = false, presetOpen = false }
end
for _, restriction in ipairs({ "bankOpen", "viewAll", "searchActive", "filterActive", "presetOpen" }) do
    for _, savedQuery in ipairs({ false, true }) do
        if savedQuery then assert(app:ChooseQuery(record.id)) else app:SetText("iron") end
        assert(app:ShownPage() ~= nil)
        app:QueueText("iron bar")
        local state = available()
        state[restriction] = restriction ~= "bankOpen" and restriction ~= "viewAll"
        local before = closes
        listener(state)
        assert(closes == before + 1 and app:ShownPage() == nil and layout.shownPage == nil, restriction)
        assert(app.pageID == nil and app.priceWait == nil and app.searchWait == nil)
        assert(app.statusIsError and app.status ~= nil)
        listener(state)
        assert(closes == before + 1)
        listener(available())
        h:Tick(20)
        assert(app:ShownPage() == nil and app.pageID == nil and app.status == nil)
        assert(app.queries.data == persisted and app.queries:Get(record.id).query == "iron")
    end
end

-- Native state reads reject openings before a callback arrives, and real delivery
-- also handles Core having already removed the page.
local getComponent = ui.Interfaces.GetComponent
local background, cancel, label, preset = { spriteID = 8070 }, { visible = false },
    { visible = true, content = "" }, { visible = false }
ui.Interfaces.GetComponent = function(self, interfaceID, staticID, categoryID, dynamicID)
    if interfaceID == 517 then
        if staticID == 166 and categoryID == 0 and dynamicID == 0 then return background end
        if staticID == 257 then
            if categoryID == 0 and dynamicID == 9 then return label end
            if categoryID == nil then return cancel end
        end
        if staticID == 86 then return preset end
    end
    return getComponent(self, interfaceID, staticID, categoryID, dynamicID)
end
for _, mode in ipairs({
    { label = "Cancel Search", message = "Clear the bank search" },
    { label = "Clear Filter", message = "Clear the bank filter" },
}) do
    app:SetText("iron")
    assert(app:ShownPage() == "search")
    cancel.visible, label.content = true, mode.label
    session.pluginPages:Notify()
    h:Tick(12)
    assert(app:ShownPage() == nil and layout.shownPage == nil and app.pageID == nil)
    assert(app.statusIsError and app.status:find(mode.message, 1, true), tostring(app.status))
    assert(not app:ChooseQuery(record.id) and app.pageID == nil)
    cancel.visible = false
    session.pluginPages:Notify()
    h:Tick(12)
    assert(app.status == nil and app:ShownPage() == nil)
    cancel.visible = true
    assert(not app:ChooseQuery(record.id), "opening must read live state")
    cancel.visible = false
    listener(available())
end

for _, restriction in ipairs({ "viewAll", "presetOpen" }) do
    app:SetText("iron")
    assert(app:ShownPage() == "search")
    if restriction == "viewAll" then background.spriteID = 8069 else preset.visible = true end
    session.pluginPages:Notify()
    h:Tick(12)
    assert(app:ShownPage() == nil and app.pageID == nil and app.statusIsError)
    assert(not app:ChooseQuery(record.id))
    background.spriteID, preset.visible = 8070, false
    layout:SetNativeViewAll(true)
    session.pluginPages:Notify()
    h:Tick(12)
    assert(app.status == nil and app:ShownPage() == nil)
end

-- A restriction never closes another extension's page.
local other = assert(core.result.Register({ id = "other", name = "Other" }))
assert(other:SetPage({ rows = { { slots = { 101 } } } }) and other:Open())
h:Tick(2)
local before = closes
local state = available()
state.filterActive = true
listener(state)
assert(other:IsOpen() and closes == before)
listener(available())
assert(other:Close())

-- Failed-price polling is also retired, and stale callbacks end on disposal.
app:SetText("price:[1 TO *]")
app:StartPriceWait()
state = available()
state.presetOpen = true
listener(state)
assert(app.priceWait == nil and app.pageID == nil)
local previous = app.ext
assert(app:Connect() and app.ext ~= previous)
assert(select(2, previous:GetBankState()) == "stale")
ui.Interfaces.GetComponent = getComponent
h.host:Unload("advancedbanksearch")
session.pluginPages:Notify()
h:Tick(2)
assert(app.ext == nil and h:LoggedFailure() == nil, tostring(h:LoggedFailure()))
h.host:Unload("bankcore")
print("bank_state_test: ok")
