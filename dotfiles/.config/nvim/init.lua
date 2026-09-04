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

-- Performance & Responsiveness
opt.updatetime = 250
opt.timeoutlen = 300

-- System Clipboard Integration
opt.clipboard = "unnamedplus"

-- Split Windows
opt.splitright = true
opt.splitbelow = true

-- -------------------------------------------------------------
-- 2. General Keymaps
-- -------------------------------------------------------------
local map = vim.keymap.set

-- Clear search highlight
map("n", "<leader>h", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Fast Save & Quit
map("n", "<leader>w", "<cmd>w<CR>", { desc = "Save file" })
map("n", "<leader>q", "<cmd>q<CR>", { desc = "Quit buffer" })

-- Better Window Navigation (Ctrl + hjkl)
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- Stay in indent mode when shifting
map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })

-- Move text up and down in visual mode
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move text down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move text up" })

-- File Explorer Toggle (Netrw fallback)
map("n", "<leader>e", "<cmd>Explore<CR>", { desc = "Open File Explorer" })

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
        highlight Comment guifg=#586E75 gui=italic
    ]])
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
                comments = { italic = true },
                keywords = { italic = false },
                functions = { bold = false },
                variables = {},
            },
            on_highlights = function(colors, _)
                return {
                    -- Base Editor
                    Normal = { fg = colors.base0, bg = colors.base03 },
                    CursorLine = { bg = colors.base02 },
                    LineNr = { fg = colors.base01, bg = colors.base03 },
                    CursorLineNr = { fg = colors.yellow, bg = colors.base02, bold = true },
                    SignColumn = { bg = colors.base03 },
                    -- Canonical Syntax Highlights
                    Comment = { fg = colors.base01, italic = true },
                    Keyword = { fg = colors.green },
                    Statement = { fg = colors.green },
                    Conditional = { fg = colors.green },
                    Repeat = { fg = colors.green },
                    Type = { fg = colors.yellow },
                    Structure = { fg = colors.green },
                    StorageClass = { fg = colors.green },
                    Function = { fg = colors.blue },
                    Identifier = { fg = colors.base0 },
                    String = { fg = colors.cyan },
                    Character = { fg = colors.cyan },
                    Constant = { fg = colors.base0 },
                    Number = { fg = colors.magenta },
                    Boolean = { fg = colors.magenta },
                    Float = { fg = colors.magenta },
                    Operator = { fg = colors.green },
                    PreProc = { fg = colors.orange },
                    Include = { fg = colors.orange },
                    Special = { fg = colors.violet },
                    goConstants = { fg = colors.magenta },
                    goExtraType = { fg = colors.magenta },
                    -- Tree-sitter & LSP Semantic Token Overrides (Exact 1:1 Parity with Bat)
                    ["@keyword"] = { fg = colors.green },
                    ["@keyword.function"] = { fg = colors.green },
                    ["@keyword.return"] = { fg = colors.green },
                    ["@keyword.coroutine"] = { fg = colors.green },
                    ["@type"] = { fg = colors.base0 },
                    ["@type.builtin"] = { fg = colors.yellow },
                    ["@type.definition"] = { fg = colors.base0 },
                    ["@function"] = { fg = colors.blue },
                    ["@function.call"] = { fg = colors.blue },
                    ["@function.method"] = { fg = colors.blue },
                    ["@function.method.call"] = { fg = colors.blue },
                    ["@function.builtin"] = { fg = colors.blue },
                    ["@variable"] = { fg = colors.base0 },
                    ["@variable.parameter"] = { fg = colors.base0 },
                    ["@variable.member"] = { fg = colors.base0 },
                    ["@property"] = { fg = colors.base0 },
                    ["@module"] = { fg = colors.base0 },
                    ["@module.builtin"] = { fg = colors.base0 },
                    ["@string"] = { fg = colors.cyan },
                    ["@string.special"] = { fg = colors.cyan },
                    ["@string.special.path"] = { fg = colors.cyan },
                    ["@string.special.url"] = { fg = colors.cyan },
                    ["@string.special.symbol"] = { fg = colors.cyan },
                    ["@string.escape"] = { fg = colors.cyan },
                    ["@comment"] = { fg = colors.base01, italic = true },
                    ["@constant"] = { fg = colors.base0 },
                    ["@constant.builtin"] = { fg = colors.magenta },
                    ["@number"] = { fg = colors.magenta },
                    ["@boolean"] = { fg = colors.magenta },
                    ["@operator"] = { fg = colors.green },
                    ["@lsp.type.keyword"] = { fg = colors.green },
                    ["@lsp.type.namespace"] = { fg = colors.base0 },
                    ["@lsp.type.type"] = { fg = colors.base0 },
                    ["@lsp.type.class"] = { fg = colors.base0 },
                    ["@lsp.type.struct"] = { fg = colors.base0 },
                    ["@lsp.type.interface"] = { fg = colors.base0 },
                    ["@lsp.type.typeParameter"] = { fg = colors.base0 },
                    ["@lsp.type.enumMember"] = { fg = colors.base0 },
                    ["@lsp.type.function"] = { fg = colors.blue },
                    ["@lsp.type.method"] = { fg = colors.blue },
                    ["@lsp.type.variable"] = { fg = colors.base0 },
                    ["@lsp.type.parameter"] = { fg = colors.base0 },
                    ["@lsp.type.property"] = { fg = colors.base0 },
                    ["@lsp.type.string"] = { fg = colors.cyan },
                    ["@lsp.type.comment"] = { fg = colors.base01, italic = true },
                    ["@lsp.typemod.variable.readonly"] = { fg = colors.base0 },
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
            local ts_ok, ts = pcall(require, "nvim-treesitter.configs")
            if ts_ok then
                ts.setup({
                    ensure_installed = {
                        "go",
                        "terraform",
                        "hcl",
                        "lua",
                        "vim",
                        "vimdoc",
                        "python",
                        "json",
                        "yaml",
                        "toml",
                        "markdown",
                        "markdown_inline",
                        "bash",
                    },
                    auto_install = true,
                    highlight = {
                        enable = true,
                        additional_vim_regex_highlighting = false,
                    },
                    indent = { enable = true },
                })
            end
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
        },
        opts = {
            defaults = {
                layout_strategy = "horizontal",
            },
        },
    },

    -- Mason & Language Server Protocol (LSP)
    {
        "williamboman/mason.nvim",
        opts = {},
    },
    {
        "williamboman/mason-lspconfig.nvim",
        dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
        opts = {
            ensure_installed = { "gopls", "terraformls", "pyright", "yamlls" },
            automatic_installation = true,
            automatic_enable = false,
        },
        config = function(_, opts)
            require("mason-lspconfig").setup(opts)

            -- Keybindings and Semantic Token cleanup on LSP attach
            vim.api.nvim_create_autocmd("LspAttach", {
                group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
                callback = function(ev)
                    local client = vim.lsp.get_client_by_id(ev.data.client_id)
                    if client then
                        -- Disable LSP semantic token overrides so Treesitter handles syntax highlighting consistently without coloring parts of import strings
                        client.server_capabilities.semanticTokensProvider = nil
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

            -- Configure servers using modern vim.lsp.config (Neovim 0.11+) with legacy fallback
            local servers = { "gopls", "terraformls", "pyright", "yamlls" }
            if vim.lsp.config and vim.lsp.enable then
                for _, s in ipairs(servers) do
                    vim.lsp.config[s] = {}
                end
                vim.lsp.enable(servers)
            else
                local lspconfig = require("lspconfig")
                for _, s in ipairs(servers) do
                    lspconfig[s].setup({})
                end
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
        end,
    },
})
