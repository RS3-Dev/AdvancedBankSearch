-- Load the installed RuneQL API from RUNEQL_ROOT, read-only
-- Support modules are loaded by tests, not run as test cases

local RuneQL = {}

-- Find RuneQL's folder, refusing one without its API module
function RuneQL.Root()
    local root = os.getenv("RUNEQL_ROOT")
    if root == nil then error("set RUNEQL_ROOT to the installed RuneQL plugin folder the tests load", 0) end
    root = string.gsub(root, "\\", "/")
    local file = io.open(root .. "/resources/lib/api.lua", "rb") or io.open(root .. "/lib/api.lua", "rb")
    if file == nil then error("RuneQL was not found at " .. root, 0) end
    file:close()
    return root
end

-- Load RuneQL's API in an environment of its own
function RuneQL.Load()
    local root = RuneQL.Root()
    local loaded = {}
    local env = setmetatable({ log = function() end }, { __index = _G })
    local function load(name)
        if loaded[name] ~= nil then return loaded[name] end
        local chunk = assert(loadfile(root .. "/" .. name .. ".lua", "t", env))
        local value = chunk(name)
        loaded[name] = value == nil and true or value
        return loaded[name]
    end
    env.require = load
    local modern = io.open(root .. "/resources/lib/api.lua", "rb")
    if modern ~= nil then modern:close(); return load("resources/lib/api") end
    return load("lib/api")
end

return RuneQL
