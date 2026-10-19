-- Load the real Bank Core beside the built Advanced Bank Search in Bank Core's own stand-in host, so
-- tests drive Advanced Bank Search only through Bank Core's public API and what a player does.
-- Bank Core is read, never changed, from BANKCORE_ROOT, which must be set.
-- FAKE HOST: stand-in loader, components, and widgets, not the game client
-- Adapted from Bank Tags' harness. Kept outside tests/ so tools/check.lua does not count it
-- as a test program

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

-- Find Bank Core's checkout and let tests require its stand-in host modules. A checkout
-- without the API Advanced Bank Search uses is refused rather than tested against
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
    -- This repository's tools come first; Bank Core's fill in what it lacks
    if not string.find(package.path, root .. "/?.lua", 1, true) then
        package.path = package.path .. ";" .. root .. "/?.lua"
    end
    return root
end

-- Find the PrettyUI checkout PRETTYUI_ROOT names, read-only, whose real widgets tests run
function Harness.PrettyUIRoot()
    local root = os.getenv("PRETTYUI_ROOT")
    if root == nil then error("set PRETTYUI_ROOT to a PrettyUI checkout the tests load widgets from", 0) end
    root = string.gsub(root, "\\", "/")
    if not exists(root .. "/src/sprite_button.lua") then
        error("PrettyUI's src/sprite_button.lua was not found under " .. root, 0)
    end
    return root
end

-- Load PrettyUI's real SpriteButton over the stand-in host's components, with its sprite
-- table, tooltips, and wheel binding from the stand-in widgets and a cursor that sets nothing
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

-- Install the stand-in host and widgets, build the plugin into dist/test/<name>, and create
-- a loader. options.separateGlobals gives each plugin its own _G; options.cloneExports
-- injects an ordinary data clone of each export, as a host that clones exports would
function Harness.new(name, options)
    options = options or {}
    local coreRoot = Harness.CoreRoot()
    local bankHost = require("tools/test_support/fake_bank_host").install()
    bankHost:InstallSidebarWidgets()
    bankHost:InstallWindowWidgets()
    bankHost:InstallPanelWidgets()
    -- Host values the query editor reads that Bank Core's stand-in does not define
    ui.Margin = { new = function(...) return { ... } end }
    ui.AlignMode.BOTTOMRIGHT = 2
    id.Font.CINZEL_13PT_BOLD = 2
    -- Item names and config names RuneQL ranks by; tests fill them in
    local objects = {}
    config.Obj.FromID = function(objectID) return objects[objectID] end
    local contentSubscriptions = {}
    for _, event in ipairs({ "GameStateChanged", "MiniMenuEntrySelected",
        "InventoryAdded", "InventoryRemoved", "InventoryUpdated" }) do
        Event[event] = { Subscribe = function() end, Unsubscribe = function() end }
    end
    -- Each plugin's MiniMenuReady handler, by subscription ID
    local menuSubscriptions = {}
    Event.MiniMenuReady = {
        Subscribe = function(key, action) menuSubscriptions[key] = action end,
        Unsubscribe = function(key) menuSubscriptions[key] = nil end,
    }
    -- Sprite buttons are PrettyUI's own, so the tab can call only what PrettyUI defines
    prettyui.SpriteButton = Harness.LoadSpriteButton(Harness.PrettyUIRoot())
    Event.ContentLayerReady = {
        Subscribe = function(key, action) contentSubscriptions[key] = action end,
        Unsubscribe = function(key) contentSubscriptions[key] = nil end,
    }
    local Build = require("tools/build")
    local out = "dist/test/" .. name
    local built = Build.Run({ out = out })
    local Loader = require("tools/test_support/fake_plugin_host")
    local logged = {}
    local globals = { ui = ui, id = id, Event = Event, config = config, Vector4 = Vector4,
        Mouse = Mouse, MiniMenuActionType = MiniMenuActionType,
        Player = { IsAvailable = function() return true end }, GameState = { GAME = 30 },
        -- The host log keeps each line, so a test can see Bank Core report a failed mount
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
        contentSubscriptions = contentSubscriptions,
        menuSubscriptions = menuSubscriptions,
        coreRoot = coreRoot,
        out = out,
        coreFolder = coreRoot .. "/plugins/bankcore",
        searchFolder = built.folder,
        built = built,
    }, { __index = Harness })
end

-- Return the first line Bank Core logged for a failed plugin callback, or nil
function Harness:LoggedFailure()
    for _, line in ipairs(self.logged) do
        if string.find(line, " failed: ", 1, true) then return line end
    end
    return nil
end

-- Load Bank Core from its source checkout, as a plugin with its own module cache
function Harness:LoadCore()
    self.core = self.host:Load("bankcore", self.coreFolder, nil, self.coreRoot)
    return self.core
end

-- Load the built Advanced Bank Search folder
function Harness:LoadSearch()
    self.search = self.host:Load("advancedbanksearch", self.searchFolder)
    return self.search
end

-- Load the installed RuneQL, read-only, from RUNEQL_ROOT as a plugin of its own
function Harness:LoadRuneQL()
    local root = require("tools/test_support/runeql").Root()
    self.runeql = self.host:Load("runeql", root)
    return self.runeql
end

-- Name objects for RuneQL: each entry is { objectID, name, configName }
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

-- Mount a bank window and open the bank for the running Core session in View All
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

-- Choose one of Bank Core's sidebar tabs, as clicking it in the tab rail does
function Harness:ChooseTab(ownerID, tabID)
    self:Session().layout:SetSidebarMode("__bankutils_ext_tab:" .. ownerID .. "/" .. tabID)
end

-- Run logic ticks
function Harness:Tick(count)
    for _ = 1, count or 1 do self.bankHost:Tick() end
end

-- Show the plugin's content panel, as selecting its ribbon icon does
function Harness:OpenContentPanel(event)
    local panel = ui.Layer.new(nil)
    panel:SetSize(300, 400)
    self.contentSubscriptions[event or "advancedbanksearch_content"]({ component = panel })
    return panel
end

-- Build a menu over mounted content, lowest priority first with Cancel at the bottom, and let
-- every subscribed plugin answer it, in subscription ID order or, with coreFirst, Bank Core
-- first; the host documents no order. A plugin's entry is appended, as the API documents,
-- and shows its label as overrideText
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

-- List a menu's entry labels from lowest to highest priority, markup removed
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

-- Find a component under a parent whose text or content matches, searching depth first
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
