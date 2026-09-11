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
                    Structure = { fg = colors.yellow },
                    StorageClass = { fg = colors.green },
                    Function = { fg = colors.blue },
                    Identifier = { fg = colors.base0 },
                    String = { fg = colors.cyan },
                    Character = { fg = colors.cyan },
                    Constant = { fg = colors.base0 },
                    Number = { fg = colors.magenta },
                    Boolean = { fg = colors.magenta },
                    Float = { fg = colors.magenta },
                    Operator = { fg = colors.base0 },
                    PreProc = { fg = colors.orange },
                    Include = { fg = colors.orange },
                    Define = { fg = colors.orange },
                    Macro = { fg = colors.blue },
                    Special = { fg = colors.violet },
                    Delimiter = { fg = colors.base0 },
                    -- Tree-sitter & LSP Semantic Token Overrides (Exact 1:1 Parity with Bat)
                    ["@keyword"] = { fg = colors.green },
                    ["@keyword.function"] = { fg = colors.green },
                    ["@keyword.return"] = { fg = colors.green },
                    ["@keyword.coroutine"] = { fg = colors.green },
                    ["@keyword.conditional.ternary"] = { fg = colors.base0 },
                    ["@keyword.directive"] = { fg = colors.orange },
                    ["@keyword.directive.define"] = { fg = colors.orange },
                    ["@keyword.type"] = { fg = colors.green },
                    ["@type"] = { fg = colors.yellow },
                    ["@type.builtin"] = { fg = colors.yellow },
                    ["@type.definition"] = { fg = colors.yellow },
                    ["@function"] = { fg = colors.blue },
                    ["@function.call"] = { fg = colors.blue },
                    ["@function.method"] = { fg = colors.blue },
                    ["@function.method.call"] = { fg = colors.blue },
                    ["@function.builtin"] = { fg = colors.blue },
                    ["@function.macro"] = { fg = colors.blue },
                    ["@variable"] = { fg = colors.base0 },
                    ["@variable.parameter"] = { fg = colors.base0 },
                    ["@variable.member"] = { fg = colors.base0 },
                    ["@property"] = { fg = colors.base0 },
                    ["@module"] = { fg = colors.base0 },
                    ["@module.builtin"] = { fg = colors.base0 },
                    ["@string"] = { fg = colors.cyan },
                    ["@string.documentation"] = { fg = colors.base01, italic = true },
                    ["@string.special"] = { fg = colors.cyan },
                    ["@string.special.path"] = { fg = colors.cyan },
                    ["@string.special.url"] = { fg = colors.cyan },
                    ["@string.special.symbol"] = { fg = colors.cyan },
                    ["@string.escape"] = { fg = colors.cyan },
                    ["@character.printf"] = { fg = colors.cyan },
                    ["@character.special"] = { fg = colors.cyan },
                    ["@comment"] = { fg = colors.base01, italic = true },
                    ["@comment.documentation"] = { fg = colors.base01, italic = true },
                    ["@spell"] = {},
                    ["@constant"] = { fg = colors.base0 },
                    ["@constant.builtin"] = { fg = colors.magenta },
                    ["@constant.macro"] = { fg = colors.orange },
                    ["@number"] = { fg = colors.magenta },
                    ["@boolean"] = { fg = colors.magenta },
                    ["@operator"] = { fg = colors.base0 },
                    ["@punctuation.bracket"] = { fg = colors.base0 },
                    ["@punctuation.delimiter"] = { fg = colors.base0 },
                    -- Markdown & Markup Overrides (Exact 1:1 Parity with Bat - First Principles Sequence)
                    ["@markup.heading"] = { fg = colors.orange, bold = true },
                    ["@markup.heading.1"] = { fg = colors.orange, bold = true },
                    ["@markup.heading.2"] = { fg = colors.yellow, bold = true },
                    ["@markup.heading.3"] = { fg = colors.blue, bold = true },
                    ["@markup.heading.4"] = { fg = colors.violet, bold = true },
                    ["@markup.heading.5"] = { fg = colors.magenta, bold = true },
                    ["@markup.heading.6"] = { fg = colors.base1, bold = true },
                    ["@markup.strong"] = { fg = colors.base1, bold = true },
                    ["@markup.italic"] = { italic = true },
                    ["@markup.raw"] = { fg = colors.cyan },
                    ["@markup.raw.block"] = { fg = colors.base0 },
                    ["@markup.link.label"] = { fg = colors.blue },
                    ["@markup.link.url"] = { fg = colors.cyan, underline = true },
                    ["@markup.quote"] = { fg = colors.blue, italic = true },
                    ["@markup.list"] = { fg = colors.green, bold = true },
                    ["@attribute"] = { fg = colors.orange },
                    ["@lsp.type.keyword"] = { fg = colors.green },
                    ["@lsp.type.namespace"] = { fg = colors.base0 },
                    ["@lsp.type.type"] = { fg = colors.yellow },
                    ["@lsp.type.class"] = { fg = colors.yellow },
                    ["@lsp.type.struct"] = { fg = colors.yellow },
                    ["@lsp.type.interface"] = { fg = colors.yellow },
                    ["@lsp.type.enum"] = { fg = colors.yellow },
                    ["@lsp.type.typeParameter"] = { fg = colors.yellow },
                    ["@lsp.type.enumMember"] = { fg = colors.base0 },
                    ["@lsp.type.function"] = { fg = colors.blue },
                    ["@lsp.type.method"] = { fg = colors.blue },
                    ["@lsp.type.variable"] = { fg = colors.base0 },
                    ["@lsp.type.parameter"] = { fg = colors.base0 },
                    ["@lsp.type.property"] = { fg = colors.base0 },
                    ["@lsp.type.string"] = { fg = colors.cyan },
                    ["@lsp.type.comment"] = { fg = colors.base01, italic = true },
                    ["@lsp.typemod.variable.readonly"] = { fg = colors.base0 },
                    -- Classic Vim Regex Fallbacks (Exact 1:1 Parity with Bat when Tree-sitter is offline)
                    markdownH1 = { fg = colors.orange, bold = true },
                    markdownH2 = { fg = colors.yellow, bold = true },
                    markdownH3 = { fg = colors.blue, bold = true },
                    markdownH4 = { fg = colors.violet, bold = true },
                    markdownH5 = { fg = colors.magenta, bold = true },
                    markdownH6 = { fg = colors.base1, bold = true },
                    markdownHeadingDelimiter = { fg = colors.orange, bold = true },
                    markdownBold = { fg = colors.base1, bold = true },
                    markdownItalic = { italic = true },
                    markdownCode = { fg = colors.cyan },
                    markdownCodeBlock = { fg = colors.base0 },
                    markdownCodeDelimiter = { fg = colors.base01 },
                    markdownBlockquote = { fg = colors.blue, italic = true },
                    markdownListMarker = { fg = colors.green, bold = true },
                    markdownOrderedListMarker = { fg = colors.green, bold = true },
                    markdownRule = { fg = colors.base01, bold = true },
                    markdownLinkText = { fg = colors.blue },
                    markdownUrl = { fg = colors.cyan, underline = true },
                    markdownId = { fg = colors.blue },
                    markdownIdDeclaration = { fg = colors.cyan },
                    htmlH1 = { fg = colors.orange, bold = true },
                    htmlH2 = { fg = colors.yellow, bold = true },
                    htmlH3 = { fg = colors.blue, bold = true },
                    htmlH4 = { fg = colors.violet, bold = true },
                    htmlH5 = { fg = colors.magenta, bold = true },
                    htmlH6 = { fg = colors.base1, bold = true },
                    htmlBold = { fg = colors.base1, bold = true },
                    htmlItalic = { italic = true },
                    goPredefinedIdentifiers = { fg = colors.magenta },
                    goConstants = { fg = colors.magenta },
                    goExtraType = { fg = colors.yellow },
                    goType = { fg = colors.yellow },
                    goSignedInts = { fg = colors.yellow },
                    goUnsignedInts = { fg = colors.yellow },
                    goFloats = { fg = colors.yellow },
                    goComplexes = { fg = colors.yellow },
                    goDecimalInt = { fg = colors.magenta },
                    goHexadecimalInt = { fg = colors.magenta },
                    goOctalInt = { fg = colors.magenta },
                    goFloat = { fg = colors.magenta },
                    pythonDocstring = { fg = colors.base01, italic = true },
                    pythonBuiltinType = { fg = colors.yellow },
                    pythonDecorator = { fg = colors.orange },
                    pythonDecoratorName = { fg = colors.orange },
                    rustCommentLineDoc = { fg = colors.base01, italic = true },
                    rustAttribute = { fg = colors.orange },
                    rustDerive = { fg = colors.orange },
                    rustDeriveTrait = { fg = colors.yellow },
                    cDefine = { fg = colors.orange },
                    cInclude = { fg = colors.orange },
                    cPreProc = { fg = colors.orange },
                    cPreCondit = { fg = colors.orange },
                    cppAccess = { fg = colors.green },
                    diffAdded = { fg = colors.green },
                    diffRemoved = { fg = colors.red },
                    diffChanged = { fg = colors.yellow },
                    diffLine = { fg = colors.blue },
                    diffFile = { fg = colors.orange },
                    diffNewFile = { fg = colors.yellow },
                    diffIndexLine = { fg = colors.base01 },
                    shOption = { fg = colors.base0 },
                    shCommandSub = { fg = colors.orange },
                    sqlKeyword = { fg = colors.green },
                    sqlSpecial = { fg = colors.magenta },
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
                "c", "cpp", "go", "python", "rust", "typescript",
                "javascript", "bash", "markdown", "markdown_inline",
                "json", "yaml", "toml", "terraform", "sql", "lua",
                "vim", "vimdoc", "diff", "printf"
            }

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
            if nts_ok and nts.setup then
                pcall(function()
                    nts.setup({
                        install_dir = vim.fn.stdpath("data") .. "/site",
                    })
                end)
                local installed = {}
                for _, p in ipairs(nts.get_installed()) do
                    installed[p] = true
                end
                local to_install = {}
                for _, p in ipairs(parsers) do
                    if not installed[p] then
                        table.insert(to_install, p)
                    end
                end
                if #to_install > 0 then
                    pcall(function()
                        nts.install(to_install)
                    end)
                end
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
