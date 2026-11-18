-- Run every test and check the directly installable runtime files
-- Usage from the repository root: lua54 tests/check.lua
-- Tests that load Bank Core read it from BANKCORE_ROOT
-- Each test runs in its own process since host stand-ins differ

package.path = "./?.lua;" .. package.path

local interpreter = arg[-1] or "lua54"
-- luac sits beside the interpreter in the Lua binary distribution
local compiler = interpreter:gsub("lua(%d*)%.exe$", "luac%1.exe"):gsub("lua(%d*)$", "luac%1")

-- Globals the host, Lua, and injected dependencies provide
local ALLOWED = {}
for name in ([[
ui id Event prettyui PersistentDB config log Mouse MiniMenuActionType game bankcore runeql gepl PluginShutdown
PluginDependencyUpdate pairs ipairs type tostring tonumber math string table pcall error select
next setmetatable getmetatable rawget rawset require assert collectgarbage package _G utf8
]]):gmatch("%S+") do ALLOWED[name] = true end

-- Run a command and return whether it succeeded and what it printed
local function run(command)
    local handle = io.popen(command .. " 2>&1")
    local output = handle:read("a")
    local ok = handle:close()
    return ok == true, output
end

-- List the tracked files matching git pathspecs
local function trackedFiles(...)
    local _, output = run("git ls-files " .. table.concat({ ... }, " "))
    local files = {}
    for path in output:gmatch("[^\r\n]+") do
        local file = io.open(path, "rb")
        if file ~= nil then file:close(); files[#files + 1] = path end
    end
    return files
end

local failures = 0

-- Check the exact source runtime that users install
local ModuleGraph = require("tests/support/module_graph")
local modules = ModuleGraph.PluginModules("main")
local runtime, shipped = { "main.lua" }, { ["main.lua"] = true }
for _, name in ipairs(modules) do
    runtime[#runtime + 1] = name .. ".lua"
    shipped[name .. ".lua"] = true
end
local entry = assert(ModuleGraph.Source("main"))
local orphans, strays = 0, 0
for _, name in ipairs(modules) do
    if not entry:find('"' .. name .. '"', 1, true) then
        orphans = orphans + 1
        print("MISSING RELOAD MODULE " .. name)
    end
    if name:sub(1, 10) ~= "resources/" then
        strays = strays + 1
        print("NON-RUNTIME MODULE " .. name)
    end
end
for _, path in ipairs(trackedFiles('"resources/*.lua"')) do
    if not shipped[path] then
        orphans = orphans + 1
        print("UNUSED RUNTIME " .. path)
    end
end

-- Show which Bank Core checkout the tests run against
local coreRoot = os.getenv("BANKCORE_ROOT")
if coreRoot == nil then
    print("Bank Core for tests: BANKCORE_ROOT is not set, so tests that load Bank Core fail")
else
    local _, coreHead = run('git -C "' .. coreRoot .. '" log -1 --format="%h %s"')
    print("Bank Core for tests: " .. coreRoot .. " at " .. (coreHead:match("[^\r\n]+") or "unknown"))
end
-- RuneQL is read from its installed folder, which is not a git checkout
print("RuneQL for tests: " .. (os.getenv("RUNEQL_ROOT") or "RUNEQL_ROOT is not set, so tests that rank fail"))
local prettyRoot = os.getenv("PRETTYUI_ROOT")
if prettyRoot == nil then
    print("PrettyUI for tests: PRETTYUI_ROOT is not set, so tests that load Bank Core fail")
else
    local _, prettyHead = run('git -C "' .. prettyRoot .. '" log -1 --format="%h %s"')
    print("PrettyUI for tests: " .. prettyRoot .. " at " .. (prettyHead:match("[^\r\n]+") or "unknown"))
end

local tests = trackedFiles('"tests/*_test.lua"')
for _, path in ipairs(tests) do
    local ok, output = run(('"%s" %s'):format(interpreter, path))
    if not ok then
        failures = failures + 1
        print("FAIL " .. path .. "\n" .. output)
    end
end
print(("%d of %d tests passed"):format(#tests - failures, #tests))

local globalProblems = 0
for _, path in ipairs(runtime) do
    local ok, listing = run(('"%s" -p -l -l %s'):format(compiler, path))
    if not ok then
        globalProblems = globalProblems + 1
        print("COMPILE ERROR " .. path .. "\n" .. listing)
    else
        local unexpected, seen = {}, {}
        for name in listing:gmatch('TABUP%s.-_ENV "([^"]+)"') do
            if not ALLOWED[name] and not seen[name] then
                seen[name] = true
                unexpected[#unexpected + 1] = name
            end
        end
        if #unexpected > 0 then
            globalProblems = globalProblems + 1
            table.sort(unexpected)
            print(path .. " uses unexpected globals: " .. table.concat(unexpected, ", "))
        end
    end
end
print(("%d of %d runtime files compile with no unexpected globals"):format(
    #runtime - globalProblems, #runtime))

os.exit(failures == 0 and globalProblems == 0 and orphans == 0 and strays == 0 and 0 or 1)
