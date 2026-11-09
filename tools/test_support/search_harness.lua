-- Load Bank Core from BANKCORE_ROOT beside the built Advanced Bank Search
-- FAKE HOST: stand-in loader, components, and widgets, not the game client
-- Kept outside tests/ so tools/check.lua does not run it

local Harness = {}

-- Report whether a file exists
local function exists(path)
    local file = io.open(path, "rb")
    if file == nil then return false end
    file:close()
    return true
end

-- Read a file's text, or nil when it is missing
local function readText(path)
    local file = io.open(path, "rb")
    if file == nil then return nil end
    local text = file:read("a")
    file:close()
    return text
end

-- Find Bank Core's checkout and add its stand-in host modules
-- A checkout without the API this plugin uses is refused
function Harness.CoreRoot()
    local root = os.getenv("BANKCORE_ROOT")
    if root == nil then error("set BANKCORE_ROOT to the Bank Core checkout the tests load", 0) end
    root = string.gsub(root, "\\", "/")
    if not exists(root .. "/main.lua") then
        error("Bank Core was not found at " .. root .. "; set BANKCORE_ROOT to a bank-utilities checkout", 0)
    end
    local contract = readText(root .. "/docs/API.md") or ""
    for _, needed in ipairs({ "bankcore.Register(spec)", "ext:SetPage(page)", "ext:Open()", "onBankClose",
        "ext:GetBankItems()", "ext:GetMenuItem(menu)", "ext:GetBankState()", "onBankStateChanged(state)" }) do
        if not string.find(contract, needed, 1, true) then
            error("Bank Core at " .. root .. " lacks " .. needed .. " in its API reference; set BANKCORE_ROOT "
                .. "to a checkout with the extension API Advanced Bank Search uses", 0)
        end
    end
    -- This repository's tools come first, then Bank Core's
    if not string.find(package.path, root .. "/?.lua", 1, true) then
        package.path = package.path .. ";" .. root .. "/?.lua"
    end
    return root
end

-- Find the read-only PrettyUI checkout from PRETTYUI_ROOT
function Harness.PrettyUIRoot()
    local root = os.getenv("PRETTYUI_ROOT")
    if root == nil then error("set PRETTYUI_ROOT to a PrettyUI checkout the tests load widgets from", 0) end
    root = string.gsub(root, "\\", "/")
    if not exists(root .. "/src/sprite_button.lua") then
        error("PrettyUI's src/sprite_button.lua was not found under " .. root, 0)
    end
    return root
end

-- Load PrettyUI's real SpriteButton over the stand-in components
function Harness.LoadSpriteButton(prettyRoot)
    config.Cursor = { CURSOR_BLANK = 1, CURSOR_INFO = 2 }
    local stubs = {
        ["src/core/sprites"] = { SPRITE_BUTTONS = prettyui.Sprites.SPRITE_BUTTONS },
        ["src/tooltip"] = prettyui.Tooltip,
        ["src/core/cursor"] = { apply = function() end },
        ["src/core/wheel"] = { bind = function(component, options)
            if options and options._onScrollWheel then
                component:Subscribe(ui.Hook.ONSCROLLWHEEL, "prettyui_scroll_forward", options._onScrollWheel)
            end
        end },
    }
    local env = setmetatable({ require = function(name) return assert(stubs[name], name) end }, { __index = _G })
    return assert(loadfile(prettyRoot .. "/src/sprite_button.lua", "t", env))()
end

-- Load PrettyUI's real tooltips over the stand-in components
function Harness.LoadTooltip(prettyRoot)
    config.Font = config.Font or {}
    local stubs = {
        ["src/core/sprites"] = { CONTENT_FRAME = {} },
    }
    local env = setmetatable({ require = function(name)
        if name == "src/core/math" then return assert(loadfile(prettyRoot .. "/src/core/math.lua"))() end
        return assert(stubs[name], name)
    end }, { __index = _G })
    return assert(loadfile(prettyRoot .. "/src/tooltip.lua", "t", env))()
end

-- Load real button components for allocation and cleanup checks
function Harness.LoadSimpleButton(prettyRoot)
    local stubs = {
        ["src/core/sprites"] = assert(loadfile(prettyRoot .. "/src/core/sprites.lua"))(),
        ["src/core/cursor"] = { apply = function() end },
        ["src/core/wheel"] = { bind = function() end },
        ["src/tooltip"] = prettyui.Tooltip,
    }
    local env = setmetatable({ require = function(name) return assert(stubs[name], name) end }, { __index = _G })
    return assert(loadfile(prettyRoot .. "/src/simple_button.lua", "t", env))()
end

-- Keep named hook subscriptions beside the unnamed one, as the client does
-- hooks[hook] still holds the latest subscription
function Harness.KeepNamedHooks()
    for _, class in ipairs({ "Layer", "Rectangle", "Sprite", "Button", "Text" }) do
        local new = ui[class].new
        ui[class].new = function(...)
            local node = new(...)
            local subscribe, unsubscribe = node.Subscribe, node.Unsubscribe
            node.subscriptions = {}
            function node:Subscribe(hook, name, action)
                local key = action ~= nil and name or ""
                self.subscriptions[hook] = self.subscriptions[hook] or {}
                self.subscriptions[hook][key] = action or name
                return subscribe(self, hook, name, action)
            end
            function node:Unsubscribe(hook, name)
                if self.subscriptions[hook] ~= nil then self.subscriptions[hook][name or ""] = nil end
                return unsubscribe(self, hook)
            end
            return node
        end
    end
end

-- Give the stand-in SimpleButton PrettyUI's SetActive
function Harness.FollowPrettyUIControls()
    -- Native text inputs cannot own child component collections
    local newField, newLayer = prettyui.TextField.new, ui.Layer.new
    prettyui.TextField.new = function(parent, options)
        local field = newField(parent, options)
        field.root.nativeTextInput = true
        return field
    end
    ui.Layer.new = function(parent, ...)
        if parent and parent.nativeTextInput then error("native inputs cannot parent layers") end
        return newLayer(parent, ...)
    end
    local newWindow = prettyui.Window.new
    prettyui.Window.new = function(parent, options)
        local window = newWindow(parent, options)
        window.content:SetSize(options.width - 16, options.height - 40)
        function window:SetContentHeight(height) self.contentHeight = height end
        return window
    end
    local newView = prettyui.SimpleView.new
    prettyui.SimpleView.new = function(parent, options)
        local view = newView(parent, options)
        view.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
        view.root:SetSize((options.width or 0) + (options.widthAnchor or 0) * parent.width,
            (options.height or 0) + (options.heightAnchor or 0) * parent.height)
        function view:SetContentHeight(height)
            self.contentHeight = height
            self.content.height = height
        end
        function view:SetScrollPosition(y) self.scrollY = y end
        local cursor, controls = 0, {}
        function view:AddText(value)
            local options = type(value) == "table" and value or { text = value }
            options.y, options.width, options.height = cursor, self.root.width, 24
            local text = prettyui.Text.new(self.content, options)
            controls[#controls + 1] = text
            cursor = cursor + 30
            return text
        end
        view.AddTitle = view.AddText
        function view:AddComboBox(options)
            options.y, options.width, options.height = cursor, self.root.width, 30
            local combo = prettyui.ComboBox.new(self.content, options)
            controls[#controls + 1] = combo
            cursor = cursor + 38
            return combo
        end
        local destroy = view.Destroy
        function view:Destroy()
            for _, control in ipairs(controls) do control:Destroy() end
            destroy(self)
            self.root:Destroy()
        end
        return view
    end
    local newList = prettyui.List.new
    prettyui.List.new = function(parent, options)
        local list = newList(parent, options)
        list.viewport:SetSize(options.width, options.height)
        local setEntries, setSize = list.SetEntries, list.SetSize
        function list:SetEntries(entries)
            for _, row in ipairs(self.rows) do row.root:Destroy() end
            setEntries(self, entries)
            for index, row in ipairs(self.rows) do
                row.root:SetPos(0, (index - 1) * self.entryHeight)
                row.root:SetSize(self.root.width, self.entryHeight)
                row.label.content = row.entry.label
                row.label.rgba = row.entry.textColour
            end
        end
        function list:SetSize(width, height)
            setSize(self, width, height)
            self.viewport:SetSize(width, height)
        end
        function list:SetScrollPosition(position)
            local most = math.max(0, #self.rows * self.entryHeight - self.root.height)
            self.scrollY = math.max(0, math.min(math.floor(position or 0), most))
        end
        function list:_OnScrollWheel(_, delta) self:SetScrollPosition(self.scrollY + delta * self.entryHeight); return true end
        return list
    end
    local newSlot = prettyui.ItemSlot.new
    prettyui.ItemSlot.new = function(...)
        local slot = newSlot(...)
        slot.root:SetSize(40, 40)
        function slot:SetTooltip(value) self.tooltipText = value end
        return slot
    end
    prettyui.ItemGrid = { new = function(parent, _, options)
        local grid = { root = ui.Layer.new(parent), slots = {} }
        grid.root:SetPos(options.x, options.y)
        function grid:SetObjects(entries)
            for _, slot in ipairs(self.slots) do slot:Destroy() end
            self.slots = {}
            for index, entry in ipairs(entries) do
                self.slots[index] = prettyui.ItemSlot.new(self.root, entry.object, {
                    x = ((index - 1) % options.columns) * (40 + options.slotGap),
                    y = math.floor((index - 1) / options.columns) * (40 + options.slotGap),
                })
            end
        end
        function grid:GetSlot(index) return self.slots[index] end
        function grid:Destroy() self.root:Destroy() end
        return grid
    end }
    -- Same Tabs/GetPage/SetActive API used by Bank Tags' Import / Share window.
    prettyui.Tabs = { new = function(parent, entries, options)
        local tabs = { root = ui.Layer.new(parent), pages = {}, activeIndex = 1 }
        tabs.root:SetPos(options.x, options.y)
        tabs.root:SetSize(options.width, options.height)
        for index in ipairs(entries) do
            local page = { root = ui.Layer.new(tabs.root) }
            page.root:SetPos(0, 42)
            page.root:SetSize(options.width, options.height - 42)
            page.content = ui.Layer.new(page.root)
            page.content:SetSize(options.width, options.height - 42)
            function page:SetContentHeight(height) self.contentHeight = height; self.content.height = height end
            page.root.hidden = index ~= 1
            tabs.pages[index] = page
        end
        function tabs:GetPage(index) return self.pages[index] end
        function tabs:GetActiveIndex() return self.activeIndex end
        function tabs:SetActive(index)
            self.activeIndex = index
            for key, page in ipairs(self.pages) do page.root.hidden = key ~= index end
        end
        function tabs:Destroy() self.root:Destroy() end
        return tabs
    end }
    local newButton = prettyui.SimpleButton.new
    prettyui.SimpleButton.new = function(...)
        local button = newButton(...)
        button.active = false
        function button:SetActive(active) self.active = active == true end
        function button:SetTooltip(value) self.tooltip = value end
        return button
    end
end

-- Stand in for the client's native combo field as the live client acts
-- It lists labels alphabetically and treats every ID as a sorted position
-- IDs must be whole numbers, or the client fails
local function newNativeComboField(parent)
    local field = ui.Layer.new(parent)
    field.entryText, field.labels = {}, {}
    field.hasSelection, field.selectedID, field.selectedLabel = false, -1, ""
    local function wholeID(entryID)
        if math.type(entryID) ~= "integer" then error("combo field entry IDs must be integers", 3) end
    end
    local function pick(position)
        if field.labels[position] == nil then return false end
        field.hasSelection, field.selectedID, field.selectedLabel = true, position, field.labels[position]
        return true
    end
    function field:SetEntries(entriesMap, selectedID)
        self.labels = {}
        for label, entryID in pairs(entriesMap) do
            wholeID(entryID)
            self.labels[#self.labels + 1] = label
        end
        table.sort(self.labels)
        return pick(selectedID) or pick(1)
    end
    function field:Clear() self.labels, self.hasSelection, self.selectedID, self.selectedLabel = {}, false, -1, "" end
    function field:Add(label, entryID)
        wholeID(entryID)
        self.labels[#self.labels + 1] = label
        table.sort(self.labels)
        return true
    end
    function field:Select(entryID, triggerEvents)
        wholeID(entryID)
        if not pick(entryID) then return false end
        if triggerEvents == true then self.hooks[ui.Hook.ONSELECTIONCHANGED](self, entryID, 1) end
        return true
    end
    -- Choose a label as a player does, reported by its position
    function field:Click(label)
        for position, value in ipairs(self.labels) do
            if value == label then return self:Select(position, true) end
        end
        error("no combo entry " .. label)
    end
    return field
end

-- Stand in for PrettyUI's List under its ordered combo box dropdown
-- Rows stay in the order given, and a click reports the row's own ID
local function newDropdownList(parent, options)
    local list = { root = ui.Layer.new(parent), rows = {} }
    function list:SetEntries(entries)
        self.rows = {}
        for _, entry in ipairs(entries) do
            self.rows[#self.rows + 1] = { id = entry.id, label = entry.label, visible = true }
        end
    end
    local function rowOf(entryID)
        for _, row in ipairs(list.rows) do
            if row.id == entryID then return row end
        end
    end
    function list:SetEntryVisible(entryID, visible) rowOf(entryID).visible = visible end
    function list:SetSelected(entryID, selected)
        for _, row in ipairs(self.rows) do row.selected = false end
        rowOf(entryID).selected = selected
    end
    function list:SetScrollPosition(value) self.scrollY = value end
    function list:SetSize(width, height) self.root:SetSize(width, height) end
    function list:SetDisabled(disabled) self.disabled = disabled end
    function list:Clear() self.rows = {} end
    function list:Destroy() self.root:Destroy() end
    function list:Click(entryID) options._onEntryClick(self, entryID, true) end
    return list
end

-- Load PrettyUI's real ComboBox and OrderedComboBox over the stand-in field
-- Entries with an order field build the ordered box, as in PrettyUI
function Harness.LoadComboBox(prettyRoot)
    ui.Hook.ONSELECTIONCHANGED = ui.Hook.ONSELECTIONCHANGED or "selectionchanged"
    ui.SelectionChangeEvent = { SELECTED = 1 }
    ui.TextContentVisibilityMode = { VISIBLE = 1 }
    ui.InputFieldFilterMode = { NONE = 1 }
    ui.InputFieldKeyHandlingMode = { DEFAULT = 1 }
    ui.InputFieldActionResult = { CONTENT_CHANGE = 1, SUBMIT = 2, SUBMIT_ON_ESCAPE = 3, SUBMIT_ON_FOCUS_LOSS = 4 }
    ui.ComboField = { new = newNativeComboField }
    ui.InputField = { new = function(parent)
        local input = ui.Layer.new(parent)
        input.containerSprite, input.content = {}, ""
        function input:Setup() end
        return input
    end }
    id.StyleSheet.COMBO_DEFAULT, id.StyleSheet.INPUT_DEFAULT = 1, 2
    id.Font.MUSEO_SANS_15PT_REGULAR = id.Font.MUSEO_SANS_15PT_REGULAR or 1
    local stubs = {
        ["src/core/control_palette"] = assert(loadfile(prettyRoot .. "/src/core/control_palette.lua"))(),
        ["src/core/wheel"] = { bind = function() end },
        ["src/tooltip"] = prettyui.Tooltip,
        ["src/list"] = { new = newDropdownList },
    }
    local env = setmetatable({ require = function(name)
        if name == "src/core/math" then return assert(loadfile(prettyRoot .. "/src/core/math.lua"))() end
        return assert(stubs[name], name)
    end }, { __index = _G })
    stubs["src/ordered_combo_box"] = assert(loadfile(prettyRoot .. "/src/ordered_combo_box.lua", "t", env))()
    return assert(loadfile(prettyRoot .. "/src/combo_box.lua", "t", env))()
end

-- Run every subscription a component has for a hook
function Harness.Fire(node, hook, ...)
    local subscriptions = node.subscriptions[hook] or {}
    local names = {}
    for name in pairs(subscriptions) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do subscriptions[name](node, ...) end
    return #names
end

-- Install the stand-in host, build the plugin, and create a loader
-- separateGlobals gives each plugin its own _G
-- cloneExports injects a data copy of each export
function Harness.new(name, options)
    options = options or {}
    local coreRoot = Harness.CoreRoot()
    local bankHost = require("tools/test_support/fake_bank_host").install()
    -- Current Core reads the bank interface before its components. Older
    -- stand-in hosts expose only GetComponent; preserve that host's lookup.
    if ui.Interfaces.GetInterface == nil then
        local getComponent = ui.Interfaces.GetComponent
        function ui.Interfaces:GetComponent(...)
            local node = getComponent(self, ...)
            if node ~= nil and node.position == nil then
                node.position = { x = node.x or 0, y = node.y or 0, xParentPc = 0, yParentPc = 0,
                    xSelfPc = 0, ySelfPc = 0 }
                node.size = { width = node.width or 0, height = node.height or 0, widthParentPc = 0, heightParentPc = 0 }
                local setPos, setSize = node.SetPos, node.SetSize
                function node:SetPos(x, y, xp, yp, xs, ys)
                    self.position = { x = x, y = y, xParentPc = xp or 0, yParentPc = yp or 0,
                        xSelfPc = xs or 0, ySelfPc = ys or 0 }
                    return setPos(self, x, y, xp, yp, xs, ys)
                end
                function node:SetSize(width, height, wp, hp)
                    self.size = { width = width, height = height, widthParentPc = wp or 0, heightParentPc = hp or 0 }
                    return setSize(self, width, height, wp, hp)
                end
            end
            return node
        end
        function ui.Interfaces:GetInterface(interfaceID)
            if bankHost.window == nil then return nil end
            return { GetComponent = function(_, ...)
                return ui.Interfaces:GetComponent(interfaceID, ...)
            end }
        end
    end
    bankHost:InstallSidebarWidgets()
    bankHost:InstallWindowWidgets()
    bankHost:InstallPanelWidgets()
    Harness.FollowPrettyUIControls()
    -- Host values the query editor reads that the stand-in lacks
    ui.Margin = { new = function(...) return { ... } end }
    ui.AlignMode.BOTTOMRIGHT = 2
    id.Font.CINZEL_13PT_BOLD = 2
    id.Sprite.HUD_COMBAT_BTN_BIN = id.Sprite.HUD_COMBAT_BTN_BIN or 3
    id.Sprite.EXCLAMATION_MARK = id.Sprite.EXCLAMATION_MARK or 4
    id.Sprite.BP3_MISSION_PLUS_ICON = id.Sprite.BP3_MISSION_PLUS_ICON or 5
    id.Sprite.MTX_STORE_BTN_PLUS_ACTIVE = id.Sprite.MTX_STORE_BTN_PLUS_ACTIVE or 6
    ui.Hook.ONMOUSEREPEAT = ui.Hook.ONMOUSEREPEAT or "mouserepeat"
    MiniMenuEntryType = MiniMenuEntryType or { PLUGIN = "plugin" }
    -- Item and config names RuneQL ranks by, filled in by tests
    local objects = {}
    config.Obj.FromID = function(objectID) return objects[objectID] end
    -- Bank Core still listens for its own plugin panel
    for _, event in ipairs({ "GameStateChanged", "MiniMenuEntrySelected", "ContentLayerReady",
        "InventoryAdded", "InventoryRemoved", "InventoryUpdated" }) do
        Event[event] = { Subscribe = function() end, Unsubscribe = function() end }
    end
    local settingsSubscriptions = {}
    Event.SettingsLayerReady = {
        Subscribe = function(key, action) settingsSubscriptions[key] = action end,
        Unsubscribe = function(key) settingsSubscriptions[key] = nil end,
    }
    -- Each plugin's MiniMenuReady handler, by subscription ID
    local menuSubscriptions = {}
    Event.MiniMenuReady = {
        Subscribe = function(key, action) menuSubscriptions[key] = action end,
        Unsubscribe = function(key) menuSubscriptions[key] = nil end,
    }
    local menuOpenedSubscriptions = {}
    Event.MiniMenuOpened = {
        Subscribe = function(key, action) menuOpenedSubscriptions[key] = action end,
        Unsubscribe = function(key) menuOpenedSubscriptions[key] = nil end,
    }
    -- Use PrettyUI's own buttons and tooltips so real layers are made
    Harness.KeepNamedHooks()
    prettyui.Tooltip = Harness.LoadTooltip(Harness.PrettyUIRoot())
    prettyui.SpriteButton = Harness.LoadSpriteButton(Harness.PrettyUIRoot())
    prettyui.ComboBox = Harness.LoadComboBox(Harness.PrettyUIRoot())
    local Build = require("tools/build")
    local out = "dist/test/" .. name
    local built = Build.Run({ out = out })
    local Loader = require("tools/test_support/fake_plugin_host")
    -- Older Core test hosts read `dependencies`. Adapt the documented manifest key
    -- without changing Core or the plugin package.
    if not Loader.searchManifestAdapter then
        local readManifest = Loader.ReadManifest
        Loader.ReadManifest = function(folder)
            local manifest = readManifest(folder)
            local Json = require("resources/core/json")
            local file = assert(io.open(folder .. "/plugin.json", "rb"))
            local source = Json.decode(file:read("a"))
            file:close()
            for name in pairs(source.requiredDependencies or {}) do manifest.dependencies[name] = true end
            return manifest
        end
        Loader.searchManifestAdapter = true
    end
    local logged = {}
    local globals = { ui = ui, id = id, Event = Event, config = config, Vector4 = Vector4,
        Mouse = Mouse, MiniMenuActionType = MiniMenuActionType, MiniMenuEntryType = MiniMenuEntryType,
        Player = { IsAvailable = function() return true end }, GameState = { GAME = 30 },
        -- Keep each log line so tests can see failed mounts
        log = function(...) logged[#logged + 1] = table.concat({ ... }) end }
    local databases = {}
    local host = Loader.new(globals, { exports = { prettyui = prettyui }, databases = databases,
        separateGlobals = options.separateGlobals, cloneExports = options.cloneExports,
        recordEvents = true })
    -- Lifecycle tests deliberately inject dependency failures/reloads, including
    -- required plugins the real client would prevent from unloading independently.
    local notify = host.Notify
    host.Notify = function(self, name, enabled, reinject, notifyRequired)
        return notify(self, name, enabled, reinject, notifyRequired ~= false)
    end
    return setmetatable({
        bankHost = bankHost,
        host = host,
        objects = objects,
        databases = databases,
        logged = logged,
        menuSubscriptions = menuSubscriptions,
        menuOpenedSubscriptions = menuOpenedSubscriptions,
        settingsSubscriptions = settingsSubscriptions,
        coreRoot = coreRoot,
        out = out,
        coreFolder = coreRoot,
        searchFolder = built.folder,
        built = built,
    }, { __index = Harness })
end

-- Return Bank Core's first logged callback failure
function Harness:LoggedFailure()
    for _, line in ipairs(self.logged) do
        if string.find(line, " failed: ", 1, true) then return line end
    end
    return nil
end

-- Load Bank Core from its source checkout
function Harness:LoadCore()
    self.core = self.host:Load("bankcore", self.coreFolder, nil, self.coreRoot)
    return self.core
end

-- Load the built Advanced Bank Search folder
function Harness:LoadSearch()
    self.search = self.host:Load("advancedbanksearch", self.searchFolder)
    return self.search
end

-- Load the installed RuneQL from RUNEQL_ROOT as its own plugin
function Harness:LoadRuneQL()
    local root = require("tools/test_support/runeql").Root()
    self.runeql = self.host:Load("runeql", root)
    return self.runeql
end

-- Name objects for RuneQL from { objectID, name, configName }
function Harness:NameObjects(entries)
    for _, entry in ipairs(entries) do
        local object = { id = entry[1], name = entry[2], configName = entry[3] or string.upper(string.gsub(entry[2], " ", "_")) }
        self.objects[entry[1]] = object
        config.Obj[object.configName] = object
    end
end

-- Return the running Advanced Bank Search app
function Harness:App()
    return rawget(self.search.env._G, "__advancedbanksearch_session")
end

-- Return the mounted Search column's parent, if Bank Core mounted it
function Harness:TabParent()
    local layout = self:Session().layout
    return layout.tabMount ~= nil and layout.tabMount.values ~= nil and layout.tabMount.values.parent or nil
end

-- Return the running Bank Core session
function Harness:Session()
    return rawget(self.core.env._G, "__bankcore_session")
end

-- Open the bank in View All on a mounted window
function Harness:OpenBank(width, height)
    if self.bankHost.window == nil then
        local window = self.bankHost:MountBankWindow(width or 714, height or 650)
        self.bankHost.viewport.parent = window.all
    end
    local session = self:Session()
    assert(session.layout:IsReady() and session.layout:Apply())
    session.layout.nativeViewAll = true
    return session, session.layout
end

-- Click an extension's rail icon as the tab rail does
function Harness:ChooseTab(ownerID)
    self:Session().layout:SetSidebarMode("__bankutils_ext_tab:" .. ownerID)
end

-- Run logic ticks
function Harness:Tick(count)
    for _ = 1, count or 1 do self.bankHost:Tick() end
end

-- Build a menu over mounted content and let each plugin answer
-- Plugins answer in subscription order, or Bank Core first with coreFirst
-- With a native bank item, the menu is that item's, as the client gives its componentData
function Harness:ContentMenu(coreFirst, item)
    local menu = { entries = { { verbText = "Cancel", actionType = MiniMenuActionType.CANCEL },
        { verbText = "Walk here", actionType = 23 } } }
    if item ~= nil then
        -- The client reports the bank's interface on the item's parents
        self.bankHost.itemLayer.interfaceID = 517
        menu.entries[2] = { verbText = "Withdraw-1", actionType = 57, componentData = { opIndex = 1,
            objConfig = { id = item.associatedObjectID }, component = item } }
    end
    setmetatable(menu, { __index = function(values, key)
        if key == "entryCount" then return #values.entries end
    end })
    function menu:Add(label, action)
        self.entries[#self.entries + 1] = { verbText = label, overrideText = label, action = action, actionEntryType = MiniMenuEntryType.PLUGIN }
    end
    function menu:Swap(a, b) self.entries[a], self.entries[b] = self.entries[b], self.entries[a] end
    local keys = {}
    for key in pairs(self.menuSubscriptions) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if coreFirst then return a > b end
        return a < b
    end)
    for _, key in ipairs(keys) do self.menuSubscriptions[key]({ miniMenu = menu }) end
    menu.open = function()
        for _, callback in pairs(self.menuOpenedSubscriptions) do callback() end
    end
    return menu
end

-- List a menu's labels from lowest priority, without markup
function Harness.Labels(menu)
    local labels = {}
    for index, entry in ipairs(menu.entries) do labels[index] = (string.gsub(entry.verbText, "<[^>]->", "")) end
    return table.concat(labels, " | ")
end

-- Choose a menu entry whose label starts with the given text
function Harness.Choose(menu, label)
    if menu.open then menu.open() end
    for _, entry in ipairs(menu.entries) do
        if string.sub(entry.verbText, 1, #label) == label and entry.action ~= nil then return entry.action() end
    end
    error(label .. " is not in the menu: " .. Harness.Labels(menu))
end

-- Point the mouse at a position inside a component
function Harness:PointAt(component, x, y)
    local left, top, current = 0, 0, component
    while current ~= nil do
        left, top = left + (current.x or 0), top + (current.y or 0)
        current = current.parent
    end
    self.bankHost.mouse = { x = left + x, y = top + y }
    local app = self:App()
    local tree = app and app.tab.controls and app.tab.controls.tree
    if tree ~= nil then
        local Geometry = self.search.env.require("resources/search/geometry")
        local lx, ly = Geometry.absolutePosition(tree.list.viewport)
        local px, py = left + x - lx, top + y - ly + tree.list.scrollY
        for index, row in ipairs(tree.list.rows) do
            row.root.isMouseOver = px >= 0 and px < tree.list.viewport.width
                and py >= (index - 1) * 32 and py < (index - 1) * 32 + 30
        end
    end
end

-- Complete a row press/release as PrettyUI delivers it; a press alone can become a drag.
function Harness:ClickRow(entryID)
    local tree = self:App().tab.controls.tree
    local row = tree:RowFor(entryID)
    if row == nil then return false end
    self:PointAt(tree.list.viewport, 20, row.root.y - tree.list.scrollY + 10)
    if not tree.list:Click(entryID) then return false end
    row.root.hooks[ui.Hook.ONRELEASE]()
    return true
end

-- Find a component whose text matches, depth first
function Harness.Find(parent, text)
    for _, child in ipairs(parent.children or {}) do
        if not child.destroyed and not child.hidden then
            local content = child.content or (child.text and child.text.content)
            if content == text then return child end
            local found = Harness.Find(child, text)
            if found ~= nil then return found end
        end
    end
    return nil
end

return Harness
