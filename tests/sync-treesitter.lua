-- Headless Tree-sitter parser installation and pinned-revision verification for CI.
-- Reads canonical parser and commit SHA specs directly from lua/solarized/treesitter.lua.

local ok_ts, ts_mod = pcall(require, "solarized.treesitter")
if not ok_ts or type(ts_mod) ~= "table" or type(ts_mod.parsers) ~= "table" then
    io.stderr:write("Failed to load solarized.treesitter module\n")
    vim.cmd("cquit 1")
end

local required = ts_mod.parsers
local pinned_revs = ts_mod.pinned_revs or {}

local function read_rev(lang)
    local rev_file = vim.fn.stdpath("data") .. "/site/parser-info/" .. lang .. ".revision"
    if vim.fn.filereadable(rev_file) == 1 then
        local lines = vim.fn.readfile(rev_file)
        if lines and #lines > 0 then
            return vim.trim(lines[1])
        end
    end
    return ""
end

local ok_nts, nts = pcall(require, "nvim-treesitter")
if not ok_nts or type(nts.install) ~= "function" then
    io.stderr:write("Failed to load nvim-treesitter installer\n")
    vim.cmd("cquit 1")
end

local function installed_parsers()
    local ok_p, list = pcall(nts.get_installed, "parsers")
    if not ok_p or type(list) ~= "table" then
        list = nts.get_installed()
    end
    local map = {}
    for _, p in ipairs(list) do
        map[p] = true
    end
    return map
end

local have = installed_parsers()
local to_install = {}
local to_force = {}
for _, p in ipairs(required) do
    if pinned_revs[p] then
        if (not have[p]) or (read_rev(p) ~= pinned_revs[p]) then
            table.insert(to_force, p)
        end
    elseif not have[p] then
        table.insert(to_install, p)
    end
end

if #to_install > 0 then
    nts.install(to_install, { max_jobs = 4 }):pwait(300000)
end
if #to_force > 0 then
    nts.install(to_force, { force = true, max_jobs = 2 }):pwait(120000)
end

for p, rev in pairs(pinned_revs) do
    local actual = read_rev(p)
    if actual ~= rev then
        io.stderr:write(
            "Pinned Tree-sitter parser revision mismatch for "
                .. p
                .. ": expected "
                .. rev
                .. ", got "
                .. tostring(actual)
                .. "\n"
        )
        vim.cmd("cquit 1")
    end
end

local after = installed_parsers()
local missing = {}
for _, p in ipairs(required) do
    if not after[p] then
        table.insert(missing, p)
    end
end
if #missing > 0 then
    io.stderr:write("Missing Tree-sitter parsers: " .. table.concat(missing, ", ") .. "\n")
    vim.cmd("cquit 1")
end
