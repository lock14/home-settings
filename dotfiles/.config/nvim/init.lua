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

-- Markdown Prose Readability (Word-Boundary Soft-Wrapping without Mutating Code Buffers)
vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("SolarizedMarkdownReadability", { clear = true }),
    pattern = { "markdown" },
    callback = function()
        vim.opt_local.wrap = true
        vim.opt_local.linebreak = true
        vim.opt_local.breakindent = true
    end,
})

-- Protocol Buffers, Textproto, GraphQL, Starlark/Bazel, OPA Rego, Dockerfile & Make Filetype & Tree-sitter Registration
if vim.filetype and vim.filetype.add then
    vim.filetype.add({
        extension = {
            proto = "proto",
            textproto = "pbtxt",
            pbtxt = "pbtxt",
            textpb = "pbtxt",
            prototxt = "pbtxt",
            graphql = "graphql",
            graphqls = "graphql",
            gql = "graphql",
            bzl = "bzl",
            bazel = "bzl",
            star = "bzl",
            rego = "rego",
            Dockerfile = "dockerfile",
            dockerfile = "dockerfile",
            Containerfile = "dockerfile",
            containerfile = "dockerfile",
            mk = "make",
            mak = "make",
        },
        filename = {
            ["Dockerfile"] = "dockerfile",
            ["dockerfile"] = "dockerfile",
            ["Containerfile"] = "dockerfile",
            ["containerfile"] = "dockerfile",
            ["Makefile"] = "make",
            ["makefile"] = "make",
            ["GNUmakefile"] = "make",
        },
        pattern = {
            [".*%.pb%.txt"] = "pbtxt",
            [".*%.proto%.text"] = "pbtxt",
            ["[Dd]ockerfile%..*"] = "dockerfile",
            ["[Cc]ontainerfile%..*"] = "dockerfile",
        },
    })
end
if vim.treesitter and vim.treesitter.language and vim.treesitter.language.register then
    pcall(vim.treesitter.language.register, "properties", { "jproperties", "properties" })
    pcall(vim.treesitter.language.register, "textproto", { "pbtxt", "textproto", "textpb", "prototxt" })
    pcall(vim.treesitter.language.register, "graphql", { "graphql", "graphqls", "gql" })
    pcall(vim.treesitter.language.register, "starlark", { "bzl", "starlark", "bazel" })
    pcall(vim.treesitter.language.register, "rego", { "rego" })
end

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

-- Fast Buffer Cycling & Side Mouse Button (Mouse4/Mouse5) Jumplist Navigation
map("n", "H", "<cmd>bprevious<CR>", { silent = true, desc = "Previous buffer" })
map("n", "L", "<cmd>bnext<CR>", { silent = true, desc = "Next buffer" })
map({ "n", "v" }, "<X1Mouse>", "<C-o>", { silent = true, desc = "Jump back in jumplist (Mouse4)" })
map({ "n", "v" }, "<X2Mouse>", "<C-i>", { silent = true, desc = "Jump forward in jumplist (Mouse5)" })
map("i", "<X1Mouse>", "<C-\\><C-o><C-o>", { silent = true, desc = "Jump back in jumplist (Mouse4)" })
map("i", "<X2Mouse>", "<C-\\><C-o><C-i>", { silent = true, desc = "Jump forward in jumplist (Mouse5)" })

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
        local cmd = { "tmux", "display-popup" }
        if (vim.env.TMUX_PANE or "") ~= "" then
            table.insert(cmd, "-t")
            table.insert(cmd, vim.env.TMUX_PANE)
        end
        vim.list_extend(cmd, { "-E", "-w", "86", "-h", "25", vim.fn.shellescape(vim.fn.expand("$HOME/.local/bin/ide")) .. " --keys" })
        vim.fn.jobstart(cmd, { detach = true })
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
                local hl = {
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

                    -- Mini.files Columnar Navigator (Solarized Dark Framing)
                    MiniFilesBorder = { fg = colors.base01, bg = colors.base04 },
                    MiniFilesBorderModified = { fg = colors.yellow, bg = colors.base04 },
                    MiniFilesCursorLine = { bg = colors.base02 },
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

                    -- Diagnostic Signs & Underlines (sp-only underline/undercurl without mutating syntax fg)
                    DiagnosticSignError = { fg = colors.red, bg = colors.base03 },
                    DiagnosticSignWarn = { fg = colors.yellow, bg = colors.base03 },
                    DiagnosticSignInfo = { fg = colors.blue, bg = colors.base03 },
                    DiagnosticSignHint = { fg = colors.cyan, bg = colors.base03 },
                    DiagnosticUnderlineError = { fg = "NONE", sp = colors.red, undercurl = true, underline = true },
                    DiagnosticUnderlineWarn = { fg = "NONE", sp = colors.yellow, undercurl = true, underline = true },
                    DiagnosticUnderlineInfo = { fg = "NONE", sp = colors.blue, undercurl = true, underline = true },
                    DiagnosticUnderlineHint = { fg = "NONE", sp = colors.cyan, undercurl = true, underline = true },

                    -- Markup & Diff Special Composite Highlights
                    ["@spell"] = {},
                    ["@markup.strong"] = { fg = colors.base1, bold = true },
                    ["@markup.italic"] = { fg = colors.base0, italic = true },
                    ["@markup.link"] = { fg = colors.base01, underline = false },
                    ["@markup.link.label"] = { fg = colors.blue, underline = false },
                    ["@markup.link.url"] = { fg = colors.cyan, underline = false },
                    ["@string.special.url.html"] = { fg = colors.cyan, underline = false },
                    RenderMarkdownCode = { fg = "NONE", bg = colors.base02 },
                    RenderMarkdownCodeBorder = { fg = colors.base01, bg = colors.base02 },
                    RenderMarkdownCodeInfo = { fg = colors.base01, bg = colors.base02, italic = false },
                    RenderMarkdownCodeFallback = { fg = colors.base0, bg = colors.base02 },
                    RenderMarkdownCodeInline = { fg = colors.cyan, bg = colors.base02 },
                    RenderMarkdownSign = { fg = colors.base01, bg = "NONE" },
                    RenderMarkdownIndent = { fg = colors.base02 },
                    RenderMarkdownInlineHighlight = { fg = colors.base1, bg = colors.base02 },
                    RenderMarkdownLink = { fg = colors.blue, bold = false, underline = false },
                    RenderMarkdownWikiLink = { fg = colors.blue, bold = false, underline = false },
                    markdownBold = { fg = colors.base1, bold = true },
                    markdownItalic = { italic = true },
                    markdownLinkText = { fg = colors.blue, underline = false },
                    markdownUrl = { fg = colors.cyan, underline = false },
                    DiffAdd = { fg = colors.green, bg = colors.mix_green },
                    DiffDelete = { fg = colors.red, bg = colors.mix_red },
                    DiffChange = { fg = colors.yellow, bg = colors.mix_yellow },
                    DiffText = { fg = colors.blue, bg = colors.mix_blue, bold = true },
                    protoTodo = { fg = colors.base01, bg = "NONE", bold = false },
                    pbtxtTodo = { fg = colors.base01, bg = "NONE", bold = false },
                }

                local function set_hl(groups, spec)
                    for _, g in ipairs(groups) do
                        hl[g] = spec
                    end
                end

                -- Calm Base0 Grey (#839496): Identifiers, Invocations, Custom Types, Operators, Punctuation & Neutralized Canvas
                set_hl({
                    "MiniFilesFile", "Type", "Structure", "Identifier", "Operator", "Delimiter", "TagDelimiter",
                    "@keyword.conditional.ternary", "@type", "@type.definition", "@type.qualifier", "@constructor",
                    "@function.call", "@function.method.call", "@function.builtin", "@variable", "@variable.member",
                    "@property", "@operator", "@punctuation.bracket", "@punctuation.delimiter", "@punctuation.special",
                    "@tag.delimiter", "@tag.attribute.css", "@markup.raw.xml", "@markup.raw.block",
                    "@lsp.type.type", "@lsp.type.class", "@lsp.type.struct", "@lsp.type.interface", "@lsp.type.enum",
                    "@lsp.type.typeParameter", "@lsp.type.variable", "@lsp.type.property", "@lsp.typemod.variable.readonly",
                    "markdownCodeBlock", "goExtraType", "goType", "rustDeriveTrait", "rustType", "cType", "cppType",
                    "shOption", "shCommandSub", "xmlTag", "xmlEndTag", "xmlEqual", "xmlProcessingDelim", "xmlCdata",
                    "htmlTag", "htmlEndTag", "htmlHead", "htmlTitle", "cssClassNameDot", "cssUnitizers",
                    "cssCustomProperty", "cssVar", "jpropertiesAssignment",
                    "@keyword.directive.java", "@type.builtin.terraform", "@type.builtin.hcl",
                    "@function.call.terraform", "@function.terraform", "@function.hcl",
                    "@markup.heading.html", "@markup.heading.1.html", "@markup.heading.2.html",
                    "@markup.heading.3.html", "@markup.heading.4.html", "@markup.heading.5.html", "@markup.heading.6.html",
                    "@type.builtin.starlark", "@variable.css", "@function.call.css", "@type.builtin.css",
                    "@constant.css", "@variable.properties",
                }, { fg = colors.base0 })

                set_hl({
                    "Parameter", "@variable.parameter", "@variable.parameter.builtin", "@markup.quote",
                    "@lsp.type.parameter", "markdownBlockquote", "htmlItalic", "@markup.italic.html",
                }, { fg = colors.base0, italic = false })

                set_hl({
                    "@markup.heading.5", "@markup.heading.6", "RenderMarkdownH5", "RenderMarkdownH6",
                    "markdownH5", "markdownH6", "htmlH1", "htmlH2", "htmlH3", "htmlH4", "htmlH5", "htmlH6",
                    "htmlBold", "@markup.strong.html",
                }, { fg = colors.base0, bold = false })

                set_hl({
                    "htmlUnderline", "htmlLink", "@markup.link.label.html", "@markup.link.html", "@markup.underline.html",
                }, { fg = colors.base0, underline = false })

                -- Calm Base01 Dim (#586E75): Comments, Documentation, Delimiters, Markers & Borders
                set_hl({
                    "@label", "@markup.raw.delimiter", "@markup.quote.marker", "@markup.table", "@markup.table.delimiter",
                    "RenderMarkdownQuote", "RenderMarkdownQuote1", "RenderMarkdownQuote2", "RenderMarkdownQuote3",
                    "RenderMarkdownQuote4", "RenderMarkdownQuote5", "RenderMarkdownQuote6", "RenderMarkdownDash",
                    "markdownCodeDelimiter", "diffIndexLine",
                }, { fg = colors.base01 })

                set_hl({
                    "Comment", "@string.documentation", "@comment", "@comment.documentation",
                    "RenderMarkdownHtmlComment", "@lsp.type.comment", "pythonDocstring", "rustCommentLineDoc",
                    "xmlComment", "xmlCommentPart", "htmlComment", "htmlCommentPart", "jpropertiesComment",
                    "protoComment", "pbtxtComment",
                }, { fg = colors.base01, italic = false })

                set_hl({
                    "@markup.heading.delimiter", "@markup.list.unchecked", "RenderMarkdownTableHead",
                    "RenderMarkdownTableRow", "RenderMarkdownTableFill", "RenderMarkdownLinkTitle",
                    "RenderMarkdownUnchecked", "markdownHeadingDelimiter", "markdownRule",
                }, { fg = colors.base01, bold = false })

                -- Base1 (#93A1A1) & Base02 (#073642) Markdown Headings / Backgrounds
                set_hl({ "@markup.heading.4", "RenderMarkdownH4", "markdownH4" }, { fg = colors.base1, bold = false })
                set_hl({
                    "RenderMarkdownH1Bg", "RenderMarkdownH2Bg", "RenderMarkdownH3Bg",
                    "RenderMarkdownH4Bg", "RenderMarkdownH5Bg", "RenderMarkdownH6Bg",
                }, { fg = "NONE", bg = colors.base02, bold = false })

                -- Solarized Green (#859900): Structural Scaffolding, Primitives, Mapping Keys & Diff Additions
                set_hl({
                    "Keyword", "Statement", "StorageClass", "TagAttribute",
                    "@keyword", "@keyword.function", "@keyword.modifier", "@keyword.operator", "@keyword.type",
                    "@type.builtin", "@tag.attribute", "@markup.alert.tip", "RenderMarkdownBullet", "@lsp.type.keyword",
                    "goSignedInts", "goUnsignedInts", "goFloats", "goComplexes", "goDeclaration", "goDeclType",
                    "pythonBuiltinType", "rustKeyword", "cStructure", "cStorageClass", "cppAccess", "cppStructure",
                    "cppStorageClass", "cppModifier", "diffAdded", "@diff.plus", "shFunctionKey", "sqlKeyword",
                    "xmlAttrib", "htmlArg", "cssProp", "jpropertiesIdentifier",
                    "protoStructure", "protoRepeat", "protoDefault", "protoExtend", "protoRPC", "protoType",
                    "protoTypedef", "pbtxtField", "@attribute.sql",
                    "@property.json", "@property.yaml", "@property.toml", "@property.css",
                    "@property.properties", "@property.textproto", "@property.pbtxt", "@property.graphql",
                }, { fg = colors.green })

                set_hl({
                    "@markup.list", "@markup.list.checked", "RenderMarkdownChecked", "RenderMarkdownSuccess",
                    "markdownListMarker", "markdownOrderedListMarker",
                }, { fg = colors.green, bold = false })

                -- Solarized Yellow (#B58900): Exclusive Imperative Control Flow & Diagnostics
                set_hl({
                    "DiagnosticWarn", "DiagnosticFloatingWarn", "DiagnosticVirtualTextWarn", "Conditional", "Repeat",
                    "@keyword.conditional", "@keyword.repeat", "@keyword.return", "@keyword.coroutine", "@keyword.exception",
                    "goStatement", "goConditional", "goRepeat", "pythonConditional", "pythonRepeat",
                    "pythonException", "pythonStatement", "rustConditional", "rustRepeat",
                    "cConditional", "cRepeat", "cStatement", "diffChanged", "@diff.delta",
                    "shConditional", "shRepeat", "shStatement",
                }, { fg = colors.yellow })

                -- Solarized Blue (#268BD2): Routine Declarations, Tags, Selectors, H2 & Info
                set_hl({
                    "Directory", "MiniFilesDirectory", "DiagnosticInfo", "DiagnosticFloatingInfo", "DiagnosticVirtualTextInfo",
                    "Function", "Macro", "Tag", "@function", "@function.method", "@function.macro", "@tag",
                    "@markup.alert.note", "@lsp.type.function", "@lsp.type.method", "markdownId", "rustMacro",
                    "diffLine", "@diff.line", "shFunction", "xmlTagName", "xmlNamespace", "htmlTagName",
                    "htmlSpecialTagName", "cssTagName", "cssClassName", "cssIdentifier", "pbtxtMessage",
                    "@type.css", "@tag.css",
                }, { fg = colors.blue })

                set_hl({
                    "@markup.heading.2", "RenderMarkdownH2", "RenderMarkdownInfo", "markdownH2",
                }, { fg = colors.blue, bold = false })

                -- Solarized Violet (#6C71C4): Module Imports, Namespaces, Attributes, H3 & Hints
                set_hl({
                    "Include", "Special", "@keyword.import", "@module", "@module.builtin", "@markup.alert.important",
                    "@attribute", "@lsp.type.namespace", "goDirective", "pythonDecorator", "pythonDecoratorName",
                    "rustAttribute", "rustDerive", "rustModPath", "xmlCdataStart", "xmlCdataEnd", "xmlCdataCdata",
                    "cssPseudoClass", "cssPseudoClassId", "protoSyntax",
                }, { fg = colors.violet })

                set_hl({
                    "@markup.heading.3", "RenderMarkdownH3", "RenderMarkdownMath", "RenderMarkdownHint", "markdownH3",
                }, { fg = colors.violet, bold = false })

                -- Solarized Orange (#CB4B16): Preprocessor Directives, Macros, H1 & Warnings
                set_hl({
                    "PreProc", "Define", "@keyword.directive", "@keyword.directive.define", "@constant.macro",
                    "@markup.alert.warning", "cDefine", "cInclude", "cPreProc", "cPreCondit",
                    "xmlProcessing", "xmlDocTypeDecl", "xmlDocTypeKeyword", "htmlDoctype", "cssAtRule",
                }, { fg = colors.orange })

                set_hl({
                    "@markup.heading", "@markup.heading.1", "RenderMarkdownH1", "RenderMarkdownTodo",
                    "RenderMarkdownWarn", "markdownH1",
                }, { fg = colors.orange, bold = false })

                -- Solarized Magenta (#D33682): Constants, Numbers, Booleans, Regexes, Receivers & Symbols
                set_hl({
                    "Constant", "Number", "Boolean", "Float",
                    "@variable.builtin", "@string.regexp", "@constant", "@constant.builtin", "@number",
                    "@number.float", "@boolean", "@lsp.type.enumMember",
                    "goPredefinedIdentifiers", "goConstants", "goDecimalInt", "goHexadecimalInt", "goOctalInt",
                    "goFloat", "cConstant", "sqlSpecial", "xmlEntity", "xmlEntityPunct", "htmlSpecialChar",
                    "cssColor", "cssValueNumber", "cssValueLength", "protoBool", "protoInt", "protoFloat",
                    "pbtxtEnum", "pbtxtBool", "pbtxtInt", "pbtxtHex", "pbtxtFloat", "@variable.builtin.go",
                    "@punctuation.delimiter.regex", "@punctuation.bracket.regex", "@operator.regex",
                    "@string.escape.regex", "@character.special.regex", "@constant.regex", "@property.regex",
                    "@string.special.css", "@string.special.symbol.elixir", "@string.special.symbol.clojure",
                    "@string.special.symbol.ruby",
                }, { fg = colors.magenta })

                -- Solarized Cyan (#2AA198): Strings, Characters, Format Specifiers, Escape Sequences & Hints
                set_hl({
                    "DiagnosticHint", "DiagnosticFloatingHint", "DiagnosticVirtualTextHint", "String", "Character",
                    "@string", "@string.special", "@string.special.path", "@string.special.url",
                    "@string.special.symbol", "@string.escape", "@character", "@character.printf",
                    "@character.special", "@markup.raw", "@lsp.type.string",
                    "markdownCode", "markdownIdDeclaration", "diffFile", "diffNewFile", "xmlString", "htmlString",
                    "cssStringQ", "cssStringQQ", "jpropertiesString", "jpropertiesSpecialChar",
                    "protoString", "pbtxtString",
                }, { fg = colors.cyan })

                -- Solarized Red (#DC322F): Errors, Diff Deletions & Overrides
                set_hl({
                    "DiagnosticError", "DiagnosticFloatingError", "DiagnosticVirtualTextError",
                    "@markup.alert.caution", "diffRemoved", "@diff.minus", "@keyword.modifier.css",
                }, { fg = colors.red })

                set_hl({ "RenderMarkdownError" }, { fg = colors.red, bold = false })

                return hl
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
                "c", "cpp", "go", "java", "kotlin", "swift", "python", "rust",
                "typescript", "javascript", "bash", "markdown", "markdown_inline",
                "json", "yaml", "toml", "terraform", "sql", "lua",
                "vim", "vimdoc", "diff", "printf", "xml", "html", "css",
                "properties", "proto", "textproto", "regex",
                "elixir", "haskell", "ocaml", "clojure",
                "zig", "c_sharp", "scala", "ruby",
                "graphql", "starlark", "rego", "dockerfile", "make"
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
                    max_number = 2,
                    preview = true,
                    width_focus = 35,
                    width_nofocus = 15,
                    width_preview = 25,
                },
            })
            local mf = require("mini.files")
            vim.api.nvim_create_autocmd("User", {
                group = vim.api.nvim_create_augroup("SolarizedMiniFilesWindow", { clear = true }),
                pattern = "MiniFilesWindowUpdate",
                callback = function(args)
                    local st = mf.get_explorer_state()
                    if not st or not st.windows or #st.windows == 0 then
                        return
                    end
                    local last_win = st.windows[#st.windows]
                    if args.data.win_id == last_win.win_id and last_win.path ~= st.branch[st.depth_focus] then
                        local cfg = vim.api.nvim_win_get_config(args.data.win_id)
                        local col = type(cfg.col) == "table" and (cfg.col[false] or cfg.col[1] or 0) or (cfg.col or 0)
                        local bw = (cfg.border == nil or cfg.border == "none") and 0 or 2
                        local w = vim.o.columns - col - bw
                        if w > cfg.width then
                            cfg.width = w
                            if last_win.path then
                                local clean_path = last_win.path:gsub("%z", "")
                                local name = (" " .. vim.fn.fnamemodify(clean_path, ":t") .. " "):gsub("\n", "<NL>")
                                local nchars = vim.fn.strchars(name)
                                cfg.title = nchars <= w and name or ("…" .. vim.fn.strcharpart(name, nchars - w + 1, w - 1))
                            end
                            vim.api.nvim_win_set_config(args.data.win_id, cfg)
                        end
                    end
                end,
            })
            vim.api.nvim_create_autocmd("User", {
                group = vim.api.nvim_create_augroup("SolarizedMiniFilesKeys", { clear = true }),
                pattern = "MiniFilesBufferCreate",
                callback = function(args)
                    local buf_id = args.data.buf_id
                    map("n", "<Left>", function()
                        mf.go_out()
                    end, { buffer = buf_id, nowait = true, desc = "Go out of directory" })
                    map("n", "<S-Left>", function()
                        mf.go_out()
                        mf.trim_right()
                    end, { buffer = buf_id, nowait = true, desc = "Go out of directory and trim right" })
                    map("n", "<Right>", function()
                        mf.go_in()
                    end, { buffer = buf_id, nowait = true, desc = "Go in entry" })
                    map("n", "<S-Right>", function()
                        mf.go_in({ close_on_file = true })
                    end, { buffer = buf_id, nowait = true, desc = "Go in entry and close on file" })
                    map("n", "<CR>", function()
                        mf.go_in({ close_on_file = true })
                    end, { buffer = buf_id, nowait = true, desc = "Open file or enter directory" })
                end,
            })
        end,
    },

    -- In-Buffer Markdown Rendering (Solarized Dark Semantic Architecture)
    {
        "MeanderingProgrammer/render-markdown.nvim",
        dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" },
        ft = { "markdown" },
        cmd = { "RenderMarkdown" },
        keys = {
            { "<leader>m", "<cmd>RenderMarkdown toggle<CR>", desc = "Toggle Markdown rendering" },
        },
        opts = {
            file_types = { "markdown" },
            render_modes = { "n", "v", "c", "t" },
            anti_conceal = {
                enabled = false,
            },
            win_options = {
                concealcursor = {
                    default = vim.o.concealcursor,
                    rendered = "nvc",
                },
            },
            heading = {
                enabled = true,
                sign = false,
                position = "inline",
                width = "block",
                right_pad = 1,
                icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
            },
            code = {
                enabled = true,
                sign = false,
                style = "full",
                position = "left",
                width = "full",
                border = "thin",
                above = "▄",
                below = "▀",
                left_pad = 1,
                right_pad = 1,
                highlight_language = "RenderMarkdownCodeInfo",
            },
            dash = {
                enabled = true,
                icon = "─",
                width = "full",
            },
            bullet = {
                enabled = true,
                icons = { "•", "◦", "▪", "▫" },
            },
            checkbox = {
                enabled = true,
                unchecked = { icon = "󰄱 ", highlight = "RenderMarkdownUnchecked" },
                checked = { icon = "󰱒 ", highlight = "RenderMarkdownChecked" },
            },
            quote = {
                enabled = true,
                icon = "▋",
                repeat_linebreak = true,
            },
            pipe_table = {
                enabled = true,
                preset = "round",
                style = "full",
                cell = "padded",
                alignment_indicator = "━",
            },
            link = {
                enabled = true,
                footnote = { enabled = true, superscript = true },
                image = "󰥶 ",
                email = "󰀓 ",
                hyperlink = "󰌹 ",
            },
            html = { enabled = false },
            latex = { enabled = false },
            yaml = { enabled = false },
        },
    },
})
