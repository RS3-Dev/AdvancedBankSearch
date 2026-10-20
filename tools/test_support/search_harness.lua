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
    if not exists(root .. "/plugins/bankcore/main.lua") then
        error("Bank Core was not found at " .. root .. "; set BANKCORE_ROOT to a bank-utilities checkout", 0)
    end
    local contract = readText(root .. "/HOST_CONTRACT.md") or ""
    for _, needed in ipairs({ "PluginDependencyUpdate(event)", "the root is a plain table", "onBankItems",
        "GetBankItems", "`{ label = text }` or `{ slots = list }`", "ctx:OpenPage" }) do
        if not string.find(contract, needed, 1, true) then
            error("Bank Core at " .. root .. " lacks " .. needed .. " in its contract; set BANKCORE_ROOT "
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
    ui.Interfaces.GetInterface = function() return {} end
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
        ["src/core/math"] = assert(loadfile(prettyRoot .. "/src/core/math.lua"))(),
    }
    local env = setmetatable({ require = function(name) return assert(stubs[name], name) end }, { __index = _G })
    return assert(loadfile(prettyRoot .. "/src/tooltip.lua", "t", env))()
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
    local newButton = prettyui.SimpleButton.new
    prettyui.SimpleButton.new = function(...)
        local button = newButton(...)
        button.active = false
        function button:SetActive(active) self.active = active == true end
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
        ["src/core/math"] = assert(loadfile(prettyRoot .. "/src/core/math.lua"))(),
        ["src/core/wheel"] = { bind = function() end },
        ["src/tooltip"] = prettyui.Tooltip,
        ["src/list"] = { new = newDropdownList },
    }
    local env = setmetatable({ require = function(name) return assert(stubs[name], name) end }, { __index = _G })
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
    bankHost:InstallSidebarWidgets()
    bankHost:InstallWindowWidgets()
    bankHost:InstallPanelWidgets()
    Harness.FollowPrettyUIControls()
    -- Host values the query editor reads that the stand-in lacks
    ui.Margin = { new = function(...) return { ... } end }
    ui.AlignMode.BOTTOMRIGHT = 2
    id.Font.CINZEL_13PT_BOLD = 2
    -- Item and config names RuneQL ranks by, filled in by tests
    local objects = {}
    config.Obj.FromID = function(objectID) return objects[objectID] end
    -- Bank Core still listens for its own plugin panel
    for _, event in ipairs({ "GameStateChanged", "MiniMenuEntrySelected", "ContentLayerReady",
        "InventoryAdded", "InventoryRemoved", "InventoryUpdated" }) do
        Event[event] = { Subscribe = function() end, Unsubscribe = function() end }
    end
    -- Each plugin's MiniMenuReady handler, by subscription ID
    local menuSubscriptions = {}
    Event.MiniMenuReady = {
        Subscribe = function(key, action) menuSubscriptions[key] = action end,
        Unsubscribe = function(key) menuSubscriptions[key] = nil end,
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
    return setmetatable({
        bankHost = bankHost,
        host = host,
        objects = objects,
        databases = databases,
        logged = logged,
        menuSubscriptions = menuSubscriptions,
        coreRoot = coreRoot,
        out = out,
        coreFolder = coreRoot .. "/plugins/bankcore",
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
        self.objects[entry[1]] = { name = entry[2], configName = entry[3] or string.upper(string.gsub(entry[2], " ", "_")) }
    end
end

-- Return the running Advanced Bank Search app
function Harness:App()
    return rawget(self.search.env._G, "__advancedbanksearch_session")
end

-- Return the mounted Search tab's parent, if Bank Core mounted it
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

-- Choose a Core sidebar tab as the tab rail does
function Harness:ChooseTab(ownerID, tabID)
    self:Session().layout:SetSidebarMode("__bankutils_ext_tab:" .. ownerID .. "/" .. tabID)
end

-- Run logic ticks
function Harness:Tick(count)
    for _ = 1, count or 1 do self.bankHost:Tick() end
end

-- Build a menu over mounted content and let each plugin answer
-- Plugins answer in subscription order, or Bank Core first with coreFirst
function Harness:ContentMenu(coreFirst)
    local menu = { entries = { { verbText = "Cancel", actionType = MiniMenuActionType.CANCEL },
        { verbText = "Walk here", actionType = 23 } } }
    setmetatable(menu, { __index = function(values, key)
        if key == "entryCount" then return #values.entries end
    end })
    function menu:Add(label, action)
        self.entries[#self.entries + 1] = { verbText = label, overrideText = label, action = action }
    end
    function menu:Swap(a, b) self.entries[a], self.entries[b] = self.entries[b], self.entries[a] end
    local keys = {}
    for key in pairs(self.menuSubscriptions) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if coreFirst then return a > b end
        return a < b
    end)
    for _, key in ipairs(keys) do self.menuSubscriptions[key]({ miniMenu = menu }) end
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
