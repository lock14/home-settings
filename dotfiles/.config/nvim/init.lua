-- =============================================================
-- Modern Lua Neovim Configuration (init.lua)
-- Developer Workstation Configuration (Linux, macOS, Windows)
-- =============================================================

-- Compatibility polyfills (Neovim 0.9 / 0.10 / 0.11+)
vim.uv = vim.uv or vim.loop
if not (vim.fs and vim.fs.joinpath) then
    vim.fs = vim.fs or {}
    vim.fs.joinpath = function(...)
        local parts = { ... }
        local result = table.concat(parts, "/"):gsub("//+", "/")
        return result
    end
end

-- Set Leader Key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- -------------------------------------------------------------
-- 1. Core Options & Editor Hygiene
-- -------------------------------------------------------------
local opt = vim.opt

-- Line Numbers
opt.number = true
opt.relativenumber = true

-- Tabs & Indentation
opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.expandtab = true
opt.smartindent = true
opt.autoindent = true

-- Appearance & Solarized UI
opt.termguicolors = true
opt.cursorline = true
opt.signcolumn = "yes"
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = false

-- Search Settings
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- Backup & State Files
opt.backup = false
opt.writebackup = false
opt.swapfile = false
opt.undofile = true

-- Performance, Responsiveness & Live Buffer Reloading
opt.updatetime = 250
opt.timeoutlen = 300
opt.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
    group = vim.api.nvim_create_augroup("SolarizedAutoRead", { clear = true }),
    callback = function()
        if vim.fn.getcmdwintype() == "" then
            pcall(vim.cmd, "silent! checktime")
        end
    end,
})

-- System Clipboard Integration (GNOME Terminal / X11 / Wayland / macOS + Native Neovim OSC 52)
if vim.fn.has("linux") == 1 then
    local in_ssh = (vim.env.SSH_CONNECTION ~= nil and vim.env.SSH_CONNECTION ~= "")
        or (vim.env.SSH_TTY ~= nil and vim.env.SSH_TTY ~= "")
        or (vim.env.SSH_CLIENT ~= nil and vim.env.SSH_CLIENT ~= "")
    if not in_ssh then
        if (not vim.env.DISPLAY or vim.env.DISPLAY == "") and vim.uv.fs_stat("/tmp/.X11-unix/X0") then
            vim.env.DISPLAY = ":0"
        end
        local uid = (vim.uv.getuid and vim.uv.getuid()) or nil
        if uid then
            local run_dir = "/run/user/" .. tostring(uid)
            if (not vim.env.WAYLAND_DISPLAY or vim.env.WAYLAND_DISPLAY == "") and vim.uv.fs_stat(run_dir .. "/wayland-0") then
                vim.env.WAYLAND_DISPLAY = "wayland-0"
            end
            if not vim.env.XAUTHORITY or vim.env.XAUTHORITY == "" then
                local auth_files = vim.fn.glob(run_dir .. "/.mutter-Xwaylandauth.*", true, true)
                if type(auth_files) == "table" and #auth_files > 0 then
                    vim.env.XAUTHORITY = auth_files[1]
                end
            end
        end
    end
end
opt.clipboard = "unnamedplus"

-- Split Windows
opt.splitright = true
opt.splitbelow = true

-- -------------------------------------------------------------
-- 2. General Keymaps
-- -------------------------------------------------------------
local map = vim.keymap.set

-- Auto-copy mouse visual selection to system clipboard (+) on mouse release
map("x", "<LeftRelease>", '<LeftRelease>"+ygv', { silent = true, desc = "Auto-copy mouse selection to clipboard" })
map("x", "<C-c>", '"+y', { silent = true, desc = "Copy visual selection to system clipboard" })
map("x", "<M-c>", '"+y', { silent = true, desc = "Copy visual selection to system clipboard" })
map({ "n", "i", "v", "t" }, "<M-v>", function()
    local text = vim.fn.getreg("+")
    if type(text) == "string" and text ~= "" then
        vim.api.nvim_paste(text, true, -1)
    end
end, { silent = true, desc = "Paste from system clipboard" })

-- Clear search highlight
map("n", "<leader>h", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Fast Save
map("n", "<leader>w", "<cmd>w<CR>", { desc = "Save file" })

-- Smart Home: jump to first non-blank character of line (matching .vimrc)
map({ "n", "v", "o" }, "<Home>", "^", { desc = "Move to first non-blank character of line" })
map("i", "<Home>", "<Esc>^i", { desc = "Move to first non-blank character of line" })

-- Layer 1 (Ctrl + hjkl in Normal mode): internal Neovim split navigation only (guarded against floating modals)
local function internal_split_nav(dir)
    return function()
        local cur_win = vim.api.nvim_get_current_win()
        local win_cfg = vim.api.nvim_win_get_config(cur_win)
        if win_cfg.relative and win_cfg.relative ~= "" then
            return
        end
        vim.cmd("wincmd " .. dir)
    end
end

-- Layer 2a (Alt + hjkl in all modes): seamless 2D spatial navigation across Neovim splits and Tmux panes
-- Guarded against floating modals (Telescope/LSP/MiniFiles) BEFORE mode exit and zoomed tmux panes.
local function smart_tmux_nav(dir, tmux_dir)
    return function()
        local cur_win = vim.api.nvim_get_current_win()
        local win_cfg = vim.api.nvim_win_get_config(cur_win)
        if win_cfg.relative and win_cfg.relative ~= "" then
            return
        end
        local mode = vim.api.nvim_get_mode().mode
        if mode == "t" or mode == "i" then
            vim.cmd("stopinsert")
        elseif mode == "v" or mode == "V" or mode == "\22" then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
        end
        vim.cmd("wincmd " .. dir)
        if vim.api.nvim_get_current_win() == cur_win and vim.env.TMUX then
            local pane = vim.env.TMUX_PANE
            local target_cmd = (pane and pane ~= "")
                and ("select-pane -t " .. pane .. " -" .. tmux_dir)
                or ("select-pane -" .. tmux_dir)
            local cmd = { "tmux", "if-shell" }
            if pane and pane ~= "" then
                vim.list_extend(cmd, { "-t", pane })
            end
            vim.list_extend(cmd, { "-F", "#{==:#{window_zoomed_flag},0}", target_cmd })
            vim.fn.jobstart(cmd, { detach = true })
        end
    end
end

map("n", "<C-h>", internal_split_nav("h"), { desc = "Move to left split" })
map("n", "<C-j>", internal_split_nav("j"), { desc = "Move to lower split" })
map("n", "<C-k>", internal_split_nav("k"), { desc = "Move to upper split" })
map("n", "<C-l>", internal_split_nav("l"), { desc = "Move to right split" })

map({ "n", "i", "v", "t" }, "<M-h>", smart_tmux_nav("h", "L"), { desc = "Move to left split or tmux pane" })
map({ "n", "i", "v", "t" }, "<M-j>", smart_tmux_nav("j", "D"), { desc = "Move to lower split or tmux pane" })
map({ "n", "i", "v", "t" }, "<M-k>", smart_tmux_nav("k", "U"), { desc = "Move to upper split or tmux pane" })
map({ "n", "i", "v", "t" }, "<M-l>", smart_tmux_nav("l", "R"), { desc = "Move to right split or tmux pane" })

-- Fast Buffer Cycling in Normal Mode
map("n", "H", "<cmd>bprevious<CR>", { silent = true, desc = "Previous buffer" })
map("n", "L", "<cmd>bnext<CR>", { silent = true, desc = "Next buffer" })

-- Stay in indent mode when shifting
map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })

-- Move text up and down in visual mode
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move text down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move text up" })

-- Built-in Netrw Project Tree Sidebar Configuration
vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3
vim.g.netrw_browse_split = 4
vim.g.netrw_altv = 1
vim.g.netrw_winsize = 20

-- Runs `ide` for this Editor's own workspace. Like the tmux key bindings (`#{session_name}`), it names
-- the session explicitly, so `ide` never has to work out which session called it. Without a non-empty
-- $IDE_SESSION (an Editor started outside `ide`), `ide` falls back to looking up this pane's session.
local function ide_job(...)
    local cmd = { vim.fn.expand("$HOME/.local/bin/ide"), ... }
    local sess = vim.env.IDE_SESSION
    if sess and sess ~= "" then
        table.insert(cmd, sess)
    end
    vim.fn.jobstart(cmd, { detach = true })
end

-- Project File Explorer Toggle: toggles mini.files (`Space+e` at current buffer / `Space+E` at cwd, falling back to Lexplore)
local function toggle_file_explorer(use_cwd)
    local ok, mf = pcall(require, "mini.files")
    if ok and mf then
        if not mf.close() then
            local uv = vim.uv or vim.loop
            local buf_name = vim.api.nvim_buf_get_name(0)
            if not use_cwd and buf_name ~= "" then
                if uv.fs_stat(buf_name) then
                    mf.open(buf_name, false)
                    return
                end
                local buf_dir = vim.fn.fnamemodify(buf_name, ":h")
                if buf_dir ~= "" and uv.fs_stat(buf_dir) then
                    mf.open(buf_dir, false)
                    return
                end
            end
            mf.open(uv.cwd(), false)
        end
    else
        vim.cmd("Lexplore")
    end
end
map("n", "<leader>e", function()
    toggle_file_explorer(false)
end, { desc = "Toggle Mini.files Navigator (Buffer Dir)" })
map("n", "<leader>E", function()
    toggle_file_explorer(true)
end, { desc = "Toggle Mini.files Navigator (Workspace Root)" })

-- Workspace Role Jump, Visibility Toggle & Directional Swap Keybindings (Editor <-> AI Agent <-> Shell)
map("n", "<leader>a", function()
    if vim.env.TMUX then
        ide_job("--toggle")
    end
end, { desc = "Toggle Focus: Editor <-> AI Agent" })
map({ "n", "i", "v", "t" }, "<M-a>", function()
    if vim.env.TMUX then
        ide_job("--toggle")
    end
end, { desc = "Toggle Focus: Editor <-> AI Agent" })
map({ "n", "i", "v", "t" }, "<M-e>", function()
    if vim.env.TMUX then
        ide_job("--show-editor")
    end
end, { desc = "Focus Editor Pane (or bounce back)" })
map({ "n", "i", "v", "t" }, "<M-t>", function()
    if vim.env.TMUX then
        ide_job("--show-term")
    end
end, { desc = "Toggle Focus: Shell <-> Editor Pane" })
map({ "n", "i", "v", "t" }, "<M-E>", function()
    if vim.env.TMUX then
        ide_job("--toggle-editor")
    end
end, { desc = "Toggle Editor Pane Visibility" })
map({ "n", "i", "v", "t" }, "<M-T>", function()
    if vim.env.TMUX then
        ide_job("--toggle-term")
    end
end, { desc = "Toggle Shell Pane Visibility" })
map({ "n", "i", "v", "t" }, "<M-H>", function()
    if vim.env.TMUX then
        ide_job("--swap", "left")
    end
end, { desc = "Swap Active Pane Left" })
map({ "n", "i", "v", "t" }, "<M-J>", function()
    if vim.env.TMUX then
        ide_job("--swap", "down")
    end
end, { desc = "Swap Active Pane Down" })
map({ "n", "i", "v", "t" }, "<M-K>", function()
    if vim.env.TMUX then
        ide_job("--swap", "up")
    end
end, { desc = "Swap Active Pane Up" })
map({ "n", "i", "v", "t" }, "<M-L>", function()
    if vim.env.TMUX then
        ide_job("--swap", "right")
    end
end, { desc = "Swap Active Pane Right" })
local function open_ide_keys_popup()
    if vim.env.TMUX then
        vim.fn.jobstart({ "tmux", "display-popup", "-E", "-w", "86", "-h", "25", vim.fn.expand("$HOME/.local/bin/ide") .. " --keys" }, { detach = true })
    end
end
map("n", "<leader>?", open_ide_keys_popup, { desc = "Open IDE Keybinding Cheatsheet" })
map({ "n", "i", "v", "t" }, "<M-?>", open_ide_keys_popup, { desc = "Open IDE Keybinding Cheatsheet" })

-- One-Command Quit Everything (:Q, :Quit, Space+q, Alt+q, qide)
-- While keeping `:q`, `:wq`, `:qa`, and `:wqa` as standard Neovim commands.
local function count_real_modified_buffers()
    local cnt = 0
    for _, b in ipairs(vim.fn.getbufinfo({ bufmodified = 1 })) do
        local bt = vim.bo[b.bufnr].buftype
        if bt == "" then
            if b.name and b.name ~= "" then
                cnt = cnt + 1
            else
                local lines = vim.api.nvim_buf_get_lines(b.bufnr, 0, -1, false)
                local text = table.concat(lines, ""):gsub("%s+", "")
                if text ~= "" then
                    cnt = cnt + 1
                end
            end
        end
    end
    return cnt
end

local function quit_ide_or_nvim(force)
    if vim.env.TMUX and vim.env.NVIM_IDE_SOCKET and vim.env.NVIM_IDE_SOCKET ~= "" then
        if not force then
            local modified = count_real_modified_buffers()
            if modified > 0 then
                vim.api.nvim_echo({ { "E37: No write since last change in " .. modified .. " buffer(s) (save with :wa or press Alt+Shift+Q / :Q! to force)", "ErrorMsg" } }, true, {})
                return
            end
        end
        if force then
            ide_job("--quit", "--force")
        else
            ide_job("--quit")
        end
    else
        vim.cmd(force and "qa!" or "confirm qa")
    end
end

map("n", "<leader>q", function() quit_ide_or_nvim(false) end, { desc = "Quit Entire IDE Workspace" })
map({ "n", "i", "v", "t" }, "<M-q>", function() quit_ide_or_nvim(false) end, { desc = "Quit Entire IDE Workspace" })
map({ "n", "i", "v", "t" }, "<M-Q>", function() quit_ide_or_nvim(true) end, { desc = "Force-Quit Entire IDE Workspace" })
vim.api.nvim_create_user_command("Q", function(opts) quit_ide_or_nvim(opts.bang) end, { bang = true, desc = "Quit Entire IDE Workspace" })
vim.api.nvim_create_user_command("Quit", function(opts) quit_ide_or_nvim(opts.bang) end, { bang = true, desc = "Quit Entire IDE Workspace" })

vim.api.nvim_create_user_command("IdeCd", function(opts)
    local target = vim.trim(opts.args or "")
    local resolved
    if target == "" then
        local buf_dir = vim.fn.expand("%:p:h")
        if buf_dir ~= "" and vim.fn.isdirectory(buf_dir) == 1 then
            resolved = buf_dir
        else
            resolved = vim.fn.getcwd()
        end
    elseif target == "~" or target == "--reset" then
        resolved = vim.env.IDE_INITIAL_ROOT or vim.fn.getcwd()
    else
        resolved = vim.fn.fnamemodify(vim.fn.expand(target), ":p"):gsub("/+$", "")
    end
    if resolved == "" then
        resolved = "/"
    end
    if vim.fn.isdirectory(resolved) ~= 1 then
        vim.notify("IdeCd: not a directory: " .. tostring(target), vim.log.levels.WARN)
        return
    end
    pcall(vim.cmd, "cd " .. vim.fn.fnameescape(resolved))
    if vim.env.TMUX then
        ide_job("--cd", resolved)
    end
end, { nargs = "?", complete = "dir", desc = "Dive IDE Workspace (Editor & Shell) to directory" })

map("n", "<leader>cd", "<cmd>IdeCd<CR>", { desc = "Dive IDE Workspace to Current Buffer Directory" })

-- -------------------------------------------------------------
-- 3. Bootstrap Lazy.nvim Plugin Manager
-- -------------------------------------------------------------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- -------------------------------------------------------------
-- 4. Plugin Ecosystem
-- -------------------------------------------------------------
local status_ok, lazy = pcall(require, "lazy")
if not status_ok then
    -- Fallback Solarized colors if offline/lazy not present
    vim.cmd([[
        highlight Normal guibg=#002B36 guifg=#839496
        highlight CursorLine guibg=#073642
        highlight Comment guifg=#586E75
    ]])
    return
end

-- If init.lua is re-sourced inside a running session (e.g. `:source $MYVIMRC`),
-- all core options, keymaps, and commands have already been refreshed above;
-- skip re-running `lazy.setup()` which emits "Re-sourcing your config is not supported with lazy.nvim".
if package.loaded["lazy.core.config"] then
    return
end

lazy.setup({
    -- Authentic Solarized Dark Theme (1:1 with Terminal & Ethan Schoonover palette)
    {
        "maxmx03/solarized.nvim",
        lazy = false,
        priority = 1000,
        opts = {
            variant = "spring",
            transparent = {
                enabled = false,
            },
            styles = {
                comments = { italic = false },
                keywords = { italic = false },
                functions = { bold = false },
                variables = { italic = false },
                parameters = { italic = false },
            },
            on_highlights = function(colors, _)
                return {
                    -- =========================================================================
                    -- Non-Language-Specific UI & Framing Architecture (Converged Solarized Dark)
                    -- =========================================================================
                    -- Base Canvas & Cursor
                    Normal = { fg = colors.base0, bg = colors.base03 },
                    NormalNC = { fg = colors.base0, bg = colors.base03 },
                    Cursor = { fg = colors.base03, bg = colors.base0 },
                    CursorLine = { bg = colors.base02 },
                    CursorColumn = { bg = colors.base02 },
                    ColorColumn = { bg = colors.base02 },

                    -- Gutter & Navigation Coordinates (Calm Monochromatic Luminance)
                    LineNr = { fg = colors.base01, bg = colors.base03 },
                    LineNrAbove = { fg = colors.base01, bg = colors.base03 },
                    LineNrBelow = { fg = colors.base01, bg = colors.base03 },
                    CursorLineNr = { fg = colors.base1, bg = colors.base02, bold = true },
                    SignColumn = { bg = colors.base03 },
                    FoldColumn = { fg = colors.base01, bg = colors.base03 },
                    Folded = { fg = colors.base0, bg = colors.base02 },

                    -- Window Framing & Splits (Calm Base01 Dim Borders, Zero Chromatic Noise)
                    WinSeparator = { fg = colors.base01, bg = colors.base03 },
                    VertSplit = { fg = colors.base01, bg = colors.base03 },
                    FloatBorder = { fg = colors.base01, bg = colors.base04 },
                    FloatTitle = { fg = colors.base1, bg = colors.base02, bold = true },
                    NormalFloat = { fg = colors.base0, bg = colors.base04 },
                    Directory = { fg = colors.blue },

                    -- Mini.files Columnar Navigator (Solarized Dark Framing)
                    MiniFilesBorder = { fg = colors.base01, bg = colors.base04 },
                    MiniFilesBorderModified = { fg = colors.yellow, bg = colors.base04 },
                    MiniFilesCursorLine = { bg = colors.base02 },
                    MiniFilesDirectory = { fg = colors.blue },
                    MiniFilesFile = { fg = colors.base0 },
                    MiniFilesNormal = { fg = colors.base0, bg = colors.base04 },
                    MiniFilesTitle = { fg = colors.base01, bg = colors.base02 },
                    MiniFilesTitleFocused = { fg = colors.base1, bg = colors.base02, bold = true },

                    -- Delimiter Matching (Luminance Bounding without Syntax Corruption)
                    MatchParen = { fg = colors.base1, bg = colors.base02, bold = true },

                    -- Search & Selection Plane (Zero Collision)
                    Visual = { bg = colors.mix_base1 },
                    VisualNOS = { bg = colors.mix_base1 },
                    Search = { fg = colors.base1, bg = colors.mix_yellow, bold = true },
                    IncSearch = { fg = colors.magenta, bg = colors.mix_magenta, bold = true },
                    CurSearch = { fg = colors.magenta, bg = colors.mix_magenta, bold = true },

                    -- Status, Tabline & Completion Menus
                    StatusLine = { fg = colors.base1, bg = colors.base04 },
                    StatusLineNC = { fg = colors.base01, bg = colors.base04 },
                    TabLine = { fg = colors.base01, bg = colors.base04 },
                    TabLineFill = { fg = colors.base0, bg = colors.base04 },
                    TabLineSel = { fg = colors.base0, bg = colors.base03 },
                    Pmenu = { fg = colors.base0, bg = colors.base04 },
                    PmenuSel = { fg = colors.base2, bg = colors.base01 },
                    PmenuSbar = { bg = colors.base04 },
                    PmenuThumb = { bg = colors.base1 },

                    -- Diagnostic Severity Hierarchy (Unified 4-Tier Ladder)
                    DiagnosticError = { fg = colors.red },
                    DiagnosticSignError = { fg = colors.red, bg = colors.base03 },
                    DiagnosticFloatingError = { fg = colors.red },
                    DiagnosticVirtualTextError = { fg = colors.red },
                    DiagnosticWarn = { fg = colors.yellow },
                    DiagnosticSignWarn = { fg = colors.yellow, bg = colors.base03 },
                    DiagnosticFloatingWarn = { fg = colors.yellow },
                    DiagnosticVirtualTextWarn = { fg = colors.yellow },
                    DiagnosticInfo = { fg = colors.blue },
                    DiagnosticSignInfo = { fg = colors.blue, bg = colors.base03 },
                    DiagnosticFloatingInfo = { fg = colors.blue },
                    DiagnosticVirtualTextInfo = { fg = colors.blue },
                    DiagnosticHint = { fg = colors.cyan },
                    DiagnosticSignHint = { fg = colors.cyan, bg = colors.base03 },
                    DiagnosticFloatingHint = { fg = colors.cyan },
                    DiagnosticVirtualTextHint = { fg = colors.cyan },
                    -- Canonical Syntax Highlights
                    Comment = { fg = colors.base01, italic = false },
                    Keyword = { fg = colors.green },
                    Statement = { fg = colors.green },
                    Conditional = { fg = colors.yellow },
                    Repeat = { fg = colors.yellow },
                    Type = { fg = colors.base0 },
                    Structure = { fg = colors.base0 },
                    StorageClass = { fg = colors.green },
                    Function = { fg = colors.blue },
                    Identifier = { fg = colors.base0 },
                    Parameter = { fg = colors.base0, italic = false },
                    String = { fg = colors.cyan },
                    Character = { fg = colors.cyan },
                    Constant = { fg = colors.magenta },
                    Number = { fg = colors.magenta },
                    Boolean = { fg = colors.magenta },
                    Float = { fg = colors.magenta },
                    Operator = { fg = colors.base0 },
                    PreProc = { fg = colors.orange },
                    Include = { fg = colors.violet },
                    Define = { fg = colors.orange },
                    Macro = { fg = colors.blue },
                    Special = { fg = colors.violet },
                    Delimiter = { fg = colors.base0 },
                    -- Tree-sitter & LSP Semantic Token Overrides (Exact 1:1 Parity with Bat)
                    ["@keyword"] = { fg = colors.green },
                    ["@keyword.function"] = { fg = colors.green },
                    ["@keyword.modifier"] = { fg = colors.green },
                    ["@keyword.operator"] = { fg = colors.green },
                    ["@keyword.conditional"] = { fg = colors.yellow },
                    ["@keyword.repeat"] = { fg = colors.yellow },
                    ["@keyword.return"] = { fg = colors.yellow },
                    ["@keyword.coroutine"] = { fg = colors.yellow },
                    ["@keyword.exception"] = { fg = colors.yellow },
                    ["@keyword.conditional.ternary"] = { fg = colors.base0 },
                    ["@keyword.directive"] = { fg = colors.orange },
                    ["@keyword.directive.define"] = { fg = colors.orange },
                    ["@keyword.import"] = { fg = colors.violet },
                    ["@keyword.type"] = { fg = colors.green },
                    ["@type"] = { fg = colors.base0 },
                    ["@type.builtin"] = { fg = colors.green },
                    ["@type.definition"] = { fg = colors.base0 },
                    ["@type.qualifier"] = { fg = colors.base0 },
                    ["@constructor"] = { fg = colors.base0 },
                    ["@function"] = { fg = colors.blue },
                    ["@function.call"] = { fg = colors.base0 },
                    ["@function.method"] = { fg = colors.blue },
                    ["@function.method.call"] = { fg = colors.base0 },
                    ["@function.builtin"] = { fg = colors.base0 },
                    ["@function.macro"] = { fg = colors.blue },
                    ["@variable"] = { fg = colors.base0 },
                    ["@variable.parameter"] = { fg = colors.base0, italic = false },
                    ["@variable.parameter.builtin"] = { fg = colors.base0, italic = false },
                    ["@variable.builtin"] = { fg = colors.magenta },
                    ["@variable.member"] = { fg = colors.base0 },
                    ["@property"] = { fg = colors.base0 },
                    ["@module"] = { fg = colors.violet },
                    ["@module.builtin"] = { fg = colors.violet },
                    ["@string"] = { fg = colors.cyan },
                    ["@string.documentation"] = { fg = colors.base01, italic = false },
                    ["@string.special"] = { fg = colors.cyan },
                    ["@string.special.path"] = { fg = colors.cyan },
                    ["@string.special.url"] = { fg = colors.cyan },
                    ["@string.special.symbol"] = { fg = colors.cyan },
                    ["@string.escape"] = { fg = colors.cyan },
                    ["@character"] = { fg = colors.cyan },
                    ["@character.printf"] = { fg = colors.cyan },
                    ["@character.special"] = { fg = colors.cyan },
                    ["@comment"] = { fg = colors.base01, italic = false },
                    ["@comment.documentation"] = { fg = colors.base01, italic = false },
                    ["@spell"] = {},
                    ["@label"] = { fg = colors.base01 },
                    ["@constant"] = { fg = colors.magenta },
                    ["@constant.builtin"] = { fg = colors.magenta },
                    ["@constant.macro"] = { fg = colors.orange },
                    ["@number"] = { fg = colors.magenta },
                    ["@number.float"] = { fg = colors.magenta },
                    ["@boolean"] = { fg = colors.magenta },
                    ["@operator"] = { fg = colors.base0 },
                    ["@punctuation.bracket"] = { fg = colors.base0 },
                    ["@punctuation.delimiter"] = { fg = colors.base0 },
                    ["@punctuation.special"] = { fg = colors.base0 },
                    -- Tags & Markup Elements (HTML / XML / JSX / TSX)
                    Tag = { fg = colors.blue },
                    TagAttribute = { fg = colors.green },
                    TagDelimiter = { fg = colors.base0 },
                    ["@tag"] = { fg = colors.blue },
                    ["@tag.attribute"] = { fg = colors.green },
                    ["@tag.delimiter"] = { fg = colors.base0 },
                    ["@tag.attribute.css"] = { fg = colors.base0 },
                    ["@markup.raw.xml"] = { fg = colors.base0 },
                    -- Diagnostic Underlines (sp-only underline/undercurl without mutating syntax fg)
                    DiagnosticUnderlineError = { fg = "NONE", sp = colors.red, undercurl = true, underline = true },
                    DiagnosticUnderlineWarn = { fg = "NONE", sp = colors.yellow, undercurl = true, underline = true },
                    DiagnosticUnderlineInfo = { fg = "NONE", sp = colors.blue, undercurl = true, underline = true },
                    DiagnosticUnderlineHint = { fg = "NONE", sp = colors.cyan, undercurl = true, underline = true },
                    -- Markdown & Markup Overrides (Exact 1:1 Parity with Bat - First Principles Sequence)
                    ["@markup.heading"] = { fg = colors.orange, bold = false },
                    ["@markup.heading.1"] = { fg = colors.orange, bold = false },
                    ["@markup.heading.2"] = { fg = colors.blue, bold = false },
                    ["@markup.heading.3"] = { fg = colors.violet, bold = false },
                    ["@markup.heading.4"] = { fg = colors.base1, bold = false },
                    ["@markup.heading.5"] = { fg = colors.base0, bold = false },
                    ["@markup.heading.6"] = { fg = colors.base0, bold = false },
                    ["@markup.heading.delimiter"] = { fg = colors.base01, bold = false },
                    ["@markup.strong"] = { fg = colors.base1, bold = true },
                    ["@markup.italic"] = { fg = colors.base0, italic = true },
                    ["@markup.raw"] = { fg = colors.cyan },
                    ["@markup.raw.delimiter"] = { fg = colors.base01 },
                    ["@markup.raw.block"] = { fg = colors.base0 },
                    ["@markup.link"] = { fg = colors.base01 },
                    ["@markup.link.label"] = { fg = colors.blue },
                    ["@markup.link.url"] = { fg = colors.cyan, underline = true },
                    ["@markup.quote"] = { fg = colors.base0, italic = false },
                    ["@markup.quote.marker"] = { fg = colors.base01 },
                    ["@markup.list"] = { fg = colors.green, bold = false },
                    ["@markup.list.checked"] = { fg = colors.green, bold = false },
                    ["@markup.list.unchecked"] = { fg = colors.base01, bold = false },
                    ["@markup.table"] = { fg = colors.base01 },
                    ["@markup.table.delimiter"] = { fg = colors.base01 },
                    ["@markup.alert.note"] = { fg = colors.blue },
                    ["@markup.alert.tip"] = { fg = colors.green },
                    ["@markup.alert.important"] = { fg = colors.violet },
                    ["@markup.alert.warning"] = { fg = colors.orange },
                    ["@markup.alert.caution"] = { fg = colors.red },
                    ["@attribute"] = { fg = colors.violet },
                    ["@lsp.type.keyword"] = { fg = colors.green },
                    ["@lsp.type.namespace"] = { fg = colors.violet },
                    ["@lsp.type.type"] = { fg = colors.base0 },
                    ["@lsp.type.class"] = { fg = colors.base0 },
                    ["@lsp.type.struct"] = { fg = colors.base0 },
                    ["@lsp.type.interface"] = { fg = colors.base0 },
                    ["@lsp.type.enum"] = { fg = colors.base0 },
                    ["@lsp.type.typeParameter"] = { fg = colors.base0 },
                    ["@lsp.type.enumMember"] = { fg = colors.magenta },
                    ["@lsp.type.function"] = { fg = colors.blue },
                    ["@lsp.type.method"] = { fg = colors.blue },
                    ["@lsp.type.variable"] = { fg = colors.base0 },
                    ["@lsp.type.parameter"] = { fg = colors.base0, italic = false },
                    ["@lsp.type.property"] = { fg = colors.base0 },
                    ["@lsp.type.string"] = { fg = colors.cyan },
                    ["@lsp.type.comment"] = { fg = colors.base01, italic = false },
                    ["@lsp.typemod.variable.readonly"] = { fg = colors.base0 },
                    -- Classic Vim Regex Fallbacks (Exact 1:1 Parity with Bat when Tree-sitter is offline)
                    markdownH1 = { fg = colors.orange, bold = false },
                    markdownH2 = { fg = colors.blue, bold = false },
                    markdownH3 = { fg = colors.violet, bold = false },
                    markdownH4 = { fg = colors.base1, bold = false },
                    markdownH5 = { fg = colors.base0, bold = false },
                    markdownH6 = { fg = colors.base0, bold = false },
                    markdownHeadingDelimiter = { fg = colors.base01, bold = false },
                    markdownBold = { fg = colors.base1, bold = true },
                    markdownItalic = { italic = true },
                    markdownCode = { fg = colors.cyan },
                    markdownCodeBlock = { fg = colors.base0 },
                    markdownCodeDelimiter = { fg = colors.base01 },
                    markdownBlockquote = { fg = colors.base0, italic = false },
                    markdownListMarker = { fg = colors.green, bold = false },
                    markdownOrderedListMarker = { fg = colors.green, bold = false },
                    markdownRule = { fg = colors.base01, bold = false },
                    markdownLinkText = { fg = colors.blue },
                    markdownUrl = { fg = colors.cyan, underline = true },
                    markdownId = { fg = colors.blue },
                    markdownIdDeclaration = { fg = colors.cyan },
                    goPredefinedIdentifiers = { fg = colors.magenta },
                    goConstants = { fg = colors.magenta },
                    goExtraType = { fg = colors.base0 },
                    goType = { fg = colors.base0 },
                    goSignedInts = { fg = colors.green },
                    goUnsignedInts = { fg = colors.green },
                    goFloats = { fg = colors.green },
                    goComplexes = { fg = colors.green },
                    goDecimalInt = { fg = colors.magenta },
                    goHexadecimalInt = { fg = colors.magenta },
                    goOctalInt = { fg = colors.magenta },
                    goFloat = { fg = colors.magenta },
                    goStatement = { fg = colors.yellow },
                    goConditional = { fg = colors.yellow },
                    goRepeat = { fg = colors.yellow },
                    goDeclaration = { fg = colors.green },
                    goDeclType = { fg = colors.green },
                    goDirective = { fg = colors.violet },
                    pythonDocstring = { fg = colors.base01, italic = false },
                    pythonBuiltinType = { fg = colors.green },
                    pythonDecorator = { fg = colors.violet },
                    pythonDecoratorName = { fg = colors.violet },
                    pythonConditional = { fg = colors.yellow },
                    pythonRepeat = { fg = colors.yellow },
                    pythonException = { fg = colors.yellow },
                    pythonStatement = { fg = colors.yellow },
                    rustCommentLineDoc = { fg = colors.base01, italic = false },
                    rustAttribute = { fg = colors.violet },
                    rustDerive = { fg = colors.violet },
                    rustDeriveTrait = { fg = colors.base0 },
                    rustConditional = { fg = colors.yellow },
                    rustRepeat = { fg = colors.yellow },
                    rustKeyword = { fg = colors.green },
                    rustModPath = { fg = colors.violet },
                    rustMacro = { fg = colors.blue },
                    rustType = { fg = colors.base0 },
                    cDefine = { fg = colors.orange },
                    cInclude = { fg = colors.orange },
                    cPreProc = { fg = colors.orange },
                    cPreCondit = { fg = colors.orange },
                    cType = { fg = colors.base0 },
                    cStructure = { fg = colors.green },
                    cStorageClass = { fg = colors.green },
                    cConditional = { fg = colors.yellow },
                    cRepeat = { fg = colors.yellow },
                    cStatement = { fg = colors.yellow },
                    cConstant = { fg = colors.magenta },
                    cppAccess = { fg = colors.green },
                    cppType = { fg = colors.base0 },
                    cppStructure = { fg = colors.green },
                    cppStorageClass = { fg = colors.green },
                    cppModifier = { fg = colors.green },
                    diffAdded = { fg = colors.green },
                    diffRemoved = { fg = colors.red },
                    diffChanged = { fg = colors.yellow },
                    diffLine = { fg = colors.blue },
                    diffFile = { fg = colors.cyan },
                    diffNewFile = { fg = colors.cyan },
                    diffIndexLine = { fg = colors.base01 },
                    DiffAdd = { fg = colors.green, bg = colors.mix_green },
                    DiffDelete = { fg = colors.red, bg = colors.mix_red },
                    DiffChange = { fg = colors.yellow, bg = colors.mix_yellow },
                    DiffText = { fg = colors.blue, bg = colors.mix_blue, bold = true },
                    ["@diff.plus"] = { fg = colors.green },
                    ["@diff.minus"] = { fg = colors.red },
                    ["@diff.delta"] = { fg = colors.yellow },
                    ["@diff.line"] = { fg = colors.blue },
                    -- Legacy Vim Regex Fallbacks (Shell and SQL)
                    shOption = { fg = colors.base0 },
                    shCommandSub = { fg = colors.base0 },
                    shConditional = { fg = colors.yellow },
                    shRepeat = { fg = colors.yellow },
                    shStatement = { fg = colors.yellow },
                    shFunctionKey = { fg = colors.green },
                    shFunction = { fg = colors.blue },
                    sqlKeyword = { fg = colors.green },
                    sqlSpecial = { fg = colors.magenta },
                    -- Legacy XML Syntax Fallbacks
                    xmlTagName = { fg = colors.blue },
                    xmlTag = { fg = colors.base0 },
                    xmlEndTag = { fg = colors.base0 },
                    xmlAttrib = { fg = colors.green },
                    xmlEqual = { fg = colors.base0 },
                    xmlString = { fg = colors.cyan },
                    xmlProcessing = { fg = colors.orange },
                    xmlProcessingDelim = { fg = colors.base0 },
                    xmlDocTypeDecl = { fg = colors.orange },
                    xmlDocTypeKeyword = { fg = colors.orange },
                    xmlEntity = { fg = colors.magenta },
                    xmlEntityPunct = { fg = colors.magenta },
                    xmlCdataStart = { fg = colors.violet },
                    xmlCdataEnd = { fg = colors.violet },
                    xmlCdata = { fg = colors.base0 },
                    xmlCdataCdata = { fg = colors.violet },
                    xmlComment = { fg = colors.base01, italic = false },
                    xmlCommentPart = { fg = colors.base01, italic = false },
                    xmlNamespace = { fg = colors.blue },
                    -- Legacy HTML Syntax Fallbacks
                    htmlTagName = { fg = colors.blue },
                    htmlSpecialTagName = { fg = colors.blue },
                    htmlTag = { fg = colors.base0 },
                    htmlEndTag = { fg = colors.base0 },
                    htmlArg = { fg = colors.green },
                    htmlString = { fg = colors.cyan },
                    htmlComment = { fg = colors.base01, italic = false },
                    htmlCommentPart = { fg = colors.base01, italic = false },
                    htmlSpecialChar = { fg = colors.magenta },
                    htmlDoctype = { fg = colors.orange },
                    htmlHead = { fg = colors.base0 },
                    htmlTitle = { fg = colors.base0 },
                    htmlH1 = { fg = colors.base0, bold = false },
                    htmlH2 = { fg = colors.base0, bold = false },
                    htmlH3 = { fg = colors.base0, bold = false },
                    htmlH4 = { fg = colors.base0, bold = false },
                    htmlH5 = { fg = colors.base0, bold = false },
                    htmlH6 = { fg = colors.base0, bold = false },
                    htmlBold = { fg = colors.base0, bold = false },
                    htmlItalic = { fg = colors.base0, italic = false },
                    htmlUnderline = { fg = colors.base0, underline = false },
                    htmlLink = { fg = colors.base0, underline = false },
                    -- Legacy CSS Syntax Fallbacks
                    cssProp = { fg = colors.green },
                    cssTagName = { fg = colors.blue },
                    cssClassName = { fg = colors.blue },
                    cssClassNameDot = { fg = colors.base0 },
                    cssIdentifier = { fg = colors.blue },
                    cssColor = { fg = colors.magenta },
                    cssValueNumber = { fg = colors.magenta },
                    cssValueLength = { fg = colors.magenta },
                    cssUnitizers = { fg = colors.base0 },
                    cssStringQ = { fg = colors.cyan },
                    cssStringQQ = { fg = colors.cyan },
                    cssPseudoClass = { fg = colors.violet },
                    cssPseudoClassId = { fg = colors.violet },
                    cssCustomProperty = { fg = colors.base0 },
                    cssVar = { fg = colors.base0 },
                    cssAtRule = { fg = colors.orange },
                    -- Legacy Java Properties Syntax Fallbacks
                    jpropertiesIdentifier = { fg = colors.green },
                    jpropertiesAssignment = { fg = colors.base0 },
                    jpropertiesString = { fg = colors.cyan },
                    jpropertiesSpecialChar = { fg = colors.cyan },
                    jpropertiesComment = { fg = colors.base01, italic = false },

                    -- Language-Specific Tree-sitter Semantic Specializations & Contextual Invariance
                    -- Java (Principle 7 Operational Role Invariance & Module Directives)
                    ["@keyword.directive.java"] = { fg = colors.base0 },

                    -- Go (Principle 12 Blank Identifier Sentinel)
                    ["@variable.builtin.go"] = { fg = colors.magenta },

                    -- SQL (Principle 29 Scaffolding Constraints)
                    ["@attribute.sql"] = { fg = colors.green },

                    -- Terraform / HCL (Principle 35 Calm Typename Declarations)
                    ["@type.builtin.terraform"] = { fg = colors.base0 },
                    ["@type.builtin.hcl"] = { fg = colors.base0 },

                    -- HTML (Semantic Headings & Content Desensitization to calm Base0 Grey)
                    ["@markup.heading.html"] = { fg = colors.base0 },
                    ["@markup.heading.1.html"] = { fg = colors.base0 },
                    ["@markup.heading.2.html"] = { fg = colors.base0 },
                    ["@markup.heading.3.html"] = { fg = colors.base0 },
                    ["@markup.heading.4.html"] = { fg = colors.base0 },
                    ["@markup.heading.5.html"] = { fg = colors.base0 },
                    ["@markup.heading.6.html"] = { fg = colors.base0 },
                    ["@markup.link.label.html"] = { fg = colors.base0, underline = false },
                    ["@markup.link.html"] = { fg = colors.base0, underline = false },
                    ["@markup.strong.html"] = { fg = colors.base0, bold = false },
                    ["@markup.italic.html"] = { fg = colors.base0, italic = false },
                    ["@markup.underline.html"] = { fg = colors.base0, underline = false },
                    ["@string.special.url.html"] = { fg = colors.cyan, underline = false },

                    -- Declarative Configuration Continuum (Mapping Keys in Solarized Green)
                    ["@property.json"] = { fg = colors.green },
                    ["@property.yaml"] = { fg = colors.green },
                    ["@property.toml"] = { fg = colors.green },
                    ["@property.css"] = { fg = colors.green },
                    ["@property.properties"] = { fg = colors.green },

                    -- CSS (Universal Semantic Architecture: Selectors Blue, Properties Green, Custom Props Base0, Hex Magenta)
                    ["@type.css"] = { fg = colors.blue },
                    ["@tag.css"] = { fg = colors.blue },
                    ["@variable.css"] = { fg = colors.base0 },
                    ["@function.call.css"] = { fg = colors.base0 },
                    ["@type.builtin.css"] = { fg = colors.base0 },
                    ["@string.special.css"] = { fg = colors.magenta },
                    ["@constant.css"] = { fg = colors.base0 },
                    ["@keyword.modifier.css"] = { fg = colors.red },

                    -- Java Properties (Variable Interpolation in Base0 Grey)
                    ["@variable.properties"] = { fg = colors.base0 },
                }
            end,
        },
        config = function(_, opts)
            vim.o.background = "dark"
            require("solarized").setup(opts)
            vim.cmd.colorscheme("solarized")
        end,
    },

    -- Tree-sitter AST Syntax Highlighting
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        lazy = false,
        priority = 900,
        config = function()
            local parsers = {
                "c", "cpp", "go", "java", "python", "rust", "typescript",
                "javascript", "bash", "markdown", "markdown_inline",
                "json", "yaml", "toml", "terraform", "sql", "lua",
                "vim", "vimdoc", "diff", "printf", "xml", "html", "css",
                "properties", "regex"
            }

            -- Pin tree-sitter-css to revision with Container Query support (PR #96)
            local css_pinned_rev = "a93651c7bef1b73c47bdc7cd530ffa4ebffae032"
            local function pin_parsers()
                local parsers_meta_ok, parsers_meta = pcall(require, "nvim-treesitter.parsers")
                if parsers_meta_ok then
                    if parsers_meta.css and parsers_meta.css.install_info then
                        parsers_meta.css.install_info.revision = css_pinned_rev
                    elseif parsers_meta.get_parser_configs then
                        local pconfigs = parsers_meta.get_parser_configs()
                        if pconfigs.css and pconfigs.css.install_info then
                            pconfigs.css.install_info.revision = css_pinned_rev
                        end
                    end
                end
            end
            pin_parsers()
            vim.api.nvim_create_autocmd("User", {
                group = vim.api.nvim_create_augroup("SolarizedTreesitterPin", { clear = true }),
                pattern = "TSUpdate",
                callback = pin_parsers,
            })

            -- Support legacy nvim-treesitter.configs if present
            local ts_configs_ok, ts_configs = pcall(require, "nvim-treesitter.configs")
            if ts_configs_ok then
                ts_configs.setup({
                    ensure_installed = parsers,
                    auto_install = true,
                    highlight = {
                        enable = true,
                        additional_vim_regex_highlighting = false,
                    },
                    indent = { enable = true },
                })
            end

            -- Support modern nvim-treesitter rewrite API
            local nts_ok, nts = pcall(require, "nvim-treesitter")
            if nts_ok and nts.setup and type(nts.get_installed) == "function" then
                pcall(function()
                    nts.setup({
                        install_dir = vim.fn.stdpath("data") .. "/site",
                    })
                end)
                local installed = {}
                for _, p in ipairs(nts.get_installed()) do
                    installed[p] = true
                end
                local css_rev_file = vim.fn.stdpath("data") .. "/site/parser-info/css.revision"
                local current_css_rev = ""
                if vim.fn.filereadable(css_rev_file) == 1 then
                    local rev_lines = vim.fn.readfile(css_rev_file)
                    if rev_lines and #rev_lines > 0 then
                        current_css_rev = vim.trim(rev_lines[1])
                    end
                end
                local need_css_install = (not installed["css"]) or (current_css_rev ~= css_pinned_rev)
                local to_install = {}
                for _, p in ipairs(parsers) do
                    if not installed[p] and p ~= "css" then
                        table.insert(to_install, p)
                    end
                end
                if #to_install > 0 then
                    pcall(function()
                        nts.install(to_install)
                    end)
                end
                if need_css_install and type(nts.install) == "function" then
                    pcall(function()
                        nts.install({ "css" }, { force = true }):pwait(60000)
                    end)
                end
            end

            -- Ensure user config directory unconditionally takes precedence over site queries in runtimepath
            vim.opt.rtp:prepend(vim.fn.stdpath("config"))

            -- Register Tree-sitter language aliases
            pcall(vim.treesitter.language.register, "properties", { "jproperties", "properties" })

            -- Ensure compatibility with Neovim 0.12 directive handling (captures passed as TSNode[])
            if vim.treesitter.query.add_directive then
                local function unwrap_node(node)
                    if type(node) == "table" and not node.range then
                        return node[1]
                    end
                    return node
                end

                vim.treesitter.query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
                    local capture_id = pred[2]
                    local node = unwrap_node(match[capture_id])
                    if not node or not node.range then return end
                    local alias = vim.treesitter.get_node_text(node, bufnr):lower()
                    metadata["injection.language"] = alias
                end, { force = true })

                vim.treesitter.query.add_directive("set-lang-from-mimetype!", function(match, _, bufnr, pred, metadata)
                    local capture_id = pred[2]
                    local node = unwrap_node(match[capture_id])
                    if not node or not node.range then return end
                    local type_attr_value = vim.treesitter.get_node_text(node, bufnr)
                    local mimes = {
                        ["importmap"] = "json",
                        ["module"] = "javascript",
                        ["application/ecmascript"] = "javascript",
                        ["text/ecmascript"] = "javascript",
                        ["text/javascript"] = "javascript",
                    }
                    if mimes[type_attr_value] then
                        metadata["injection.language"] = mimes[type_attr_value]
                    else
                        local parts = vim.split(type_attr_value, "/", { trimempty = true })
                        metadata["injection.language"] = parts[#parts]
                    end
                end, { force = true })

                vim.treesitter.query.add_directive("downcase!", function(match, _, bufnr, pred, metadata)
                    local capture_id = pred[2]
                    local node = unwrap_node(match[capture_id])
                    if not node or not node.range then return end
                    local text = vim.treesitter.get_node_text(node, bufnr):lower()
                    local prop = pred[3]
                    metadata[prop] = text
                end, { force = true })
            end

            -- Autocommand to start Tree-sitter highlighting on buffer attach (Neovim 0.12+)
            vim.api.nvim_create_autocmd("FileType", {
                group = vim.api.nvim_create_augroup("SolarizedTreesitterHighlight", { clear = true }),
                callback = function(args)
                    pcall(vim.treesitter.start, args.buf)
                end,
            })
        end,
    },

    -- Telescope Fuzzy Finder
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
        keys = {
            { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find Files" },
            { "<leader>fg", "<cmd>Telescope live_grep<CR>",  desc = "Live Grep" },
            { "<leader>fb", "<cmd>Telescope buffers<CR>",    desc = "Find Buffers" },
            { "<leader>gs", "<cmd>Telescope git_status<CR>", desc = "Git Status (AI Modified Files)" },
        },
        opts = {
            defaults = {
                layout_strategy = "horizontal",
                mappings = {
                    i = {
                        ["<C-j>"] = "move_selection_next",
                        ["<C-k>"] = "move_selection_previous",
                    },
                    n = {
                        ["<C-j>"] = "move_selection_next",
                        ["<C-k>"] = "move_selection_previous",
                    },
                },
            },
        },
    },

    -- Mason & Language Server Protocol (LSP)
    {
        "williamboman/mason.nvim",
        opts = {},
    },
    {
        "mfussenegger/nvim-jdtls",
        ft = "java",
    },
    {
        "williamboman/mason-lspconfig.nvim",
        dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
        opts = {
            ensure_installed = {
                "clangd",
                "rust_analyzer",
                "gopls",
                "pyright",
                "lua_ls",
                "bashls",
                "terraformls",
                "yamlls",
                "jsonls",
                "jdtls",
            },
            automatic_enable = false,
        },
        config = function(_, opts)
            if #vim.api.nvim_list_uis() > 0 then
                local ok_reg, registry = pcall(require, "mason-registry")
                if ok_reg then
                    local retried = {}
                    registry:on("package:install:failed", function(pkg)
                        if retried[pkg.name] then return end
                        retried[pkg.name] = true
                        local npm_ver = vim.fn.system({ "npm", "view", pkg.name, "dist-tags.latest" }):gsub("%s+$", "")
                        if vim.v.shell_error == 0 and npm_ver ~= "" then
                            vim.schedule(function()
                                pkg:install({ version = npm_ver })
                            end)
                        end
                    end)
                end
                require("mason-lspconfig").setup(opts)
            end

            -- Keybindings and Semantic Token cleanup on LSP attach
            vim.api.nvim_create_autocmd("LspAttach", {
                group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
                callback = function(ev)
                    local client = vim.lsp.get_client_by_id(ev.data.client_id)
                    if client then
                        -- Disable LSP semantic token overrides so Treesitter handles syntax highlighting consistently without coloring parts of import strings
                        client.server_capabilities.semanticTokensProvider = nil
                        -- Disable documentLinkProvider to eliminate rogue clickable hyperlink metadata and spurious link highlights
                        client.server_capabilities.documentLinkProvider = nil
                    end

                    local bufmap = function(keys, func, desc)
                        vim.keymap.set("n", keys, func, { buffer = ev.buf, desc = "LSP: " .. desc })
                    end
                    bufmap("gd", vim.lsp.buf.definition, "Goto Definition")
                    bufmap("gr", vim.lsp.buf.references, "Goto References")
                    bufmap("K", vim.lsp.buf.hover, "Hover Documentation")
                    bufmap("<leader>rn", vim.lsp.buf.rename, "Rename Symbol")
                    bufmap("<leader>ca", vim.lsp.buf.code_action, "Code Action")
                    bufmap("<leader>d", vim.diagnostic.open_float, "Line Diagnostics")
                end,
            })

            -- Server-specific configuration overrides
            local server_configs = {
                clangd = {
                    cmd = {
                        "clangd",
                        "--background-index",
                        "--clang-tidy",
                        "--header-insertion=iwyu",
                        "--completion-style=detailed",
                        "--fallback-style=llvm",
                    },
                },
                lua_ls = {
                    settings = {
                        Lua = {
                            diagnostics = {
                                globals = { "vim" },
                            },
                            workspace = {
                                library = vim.api.nvim_get_runtime_file("", true),
                                checkThirdParty = false,
                            },
                            telemetry = { enable = false },
                        },
                    },
                },
                rust_analyzer = {
                    settings = {
                        ["rust-analyzer"] = {
                            check = {
                                command = "check",
                            },
                        },
                    },
                },
                gopls = {},
                pyright = {},
                bashls = {},
                terraformls = {},
                yamlls = {
                    settings = {
                        yaml = {
                            validate = false,
                        },
                    },
                },
                jsonls = {
                    settings = {
                        json = {
                            validate = { enable = false },
                        },
                    },
                },
            }

            -- Configure servers using modern vim.lsp.config (Neovim 0.11+) with legacy fallback
            -- Note: jdtls is managed on-demand via ftplugin/java.lua with nvim-jdtls
            local servers = { "clangd", "rust_analyzer", "gopls", "pyright", "lua_ls", "bashls", "terraformls", "yamlls", "jsonls" }
            local server_bins = {
                clangd = "clangd",
                rust_analyzer = "rust-analyzer",
                gopls = "gopls",
                pyright = "pyright-langserver",
                lua_ls = "lua-language-server",
                bashls = "bash-language-server",
                terraformls = "terraform-ls",
                yamlls = "yaml-language-server",
                jsonls = "vscode-json-language-server",
            }
            local mason_bin_dir = vim.fn.stdpath("data") .. "/mason/bin"
            if not (vim.env.PATH or ""):find(mason_bin_dir, 1, true) then
                vim.env.PATH = mason_bin_dir .. ":" .. (vim.env.PATH or "")
            end
            if vim.lsp.config and vim.lsp.enable then
                for _, s in ipairs(servers) do
                    vim.lsp.config[s] = server_configs[s] or {}
                end
            end
            local already_enabled = {}
            local function enable_installed_servers()
                local newly_enabled = {}
                for _, s in ipairs(servers) do
                    if not already_enabled[s] then
                        local bin = server_bins[s] or s
                        if vim.fn.executable(bin) == 1 or vim.fn.executable(mason_bin_dir .. "/" .. bin) == 1 then
                            already_enabled[s] = true
                            table.insert(newly_enabled, s)
                        end
                    end
                end
                if #newly_enabled > 0 then
                    if vim.lsp.config and vim.lsp.enable then
                        vim.lsp.enable(newly_enabled)
                    else
                        local lspconfig = require("lspconfig")
                        for _, s in ipairs(newly_enabled) do
                            lspconfig[s].setup(server_configs[s] or {})
                        end
                    end
                end
            end
            enable_installed_servers()
            if #vim.api.nvim_list_uis() > 0 then
                pcall(function()
                    local registry = require("mason-registry")
                    registry:on("package:install:success", vim.schedule_wrap(enable_installed_servers))
                end)
            end
        end,
    },

    -- Lightweight Editor Utilities (Mini.nvim)
    {
        "echasnovski/mini.nvim",
        version = false,
        config = function()
            require("mini.pairs").setup()
            require("mini.comment").setup()
            require("mini.surround").setup()
            require("mini.icons").setup()
            require("mini.files").setup({
                windows = {
                    preview = true,
                    width_focus = 35,
                    width_preview = 45,
                },
            })
        end,
    },
})
