-- Load the real RuneQL API, read-only, from the installed plugin RUNEQL_ROOT names, with its
-- own module cache, so tests rank with RuneQL's documented Compile, Score, and Requirements
-- rather than a stand-in. Nothing from RuneQL is copied into this repository or its package
-- Kept outside tests/ so tools/check.lua does not count it as a test program

local RuneQL = {}

-- Find RuneQL's folder, refusing one without its API module
function RuneQL.Root()
    local root = os.getenv("RUNEQL_ROOT")
    if root == nil then error("set RUNEQL_ROOT to the installed RuneQL plugin folder the tests load", 0) end
    root = string.gsub(root, "\\", "/")
    local file = io.open(root .. "/lib/api.lua", "rb")
    if file == nil then error("RuneQL was not found at " .. root, 0) end
    file:close()
    return root
end

-- Return RuneQL's API table, loaded from its folder in an environment of its own
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
    return load("lib/api")
end

return RuneQL
