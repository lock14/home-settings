-- Core Neovim options, compatibility polyfills, filetype registrations, and SSH-safe clipboard setup.

local M = {}

local function setup_polyfills()
    vim.uv = vim.uv or vim.loop
    if not (vim.fs and vim.fs.joinpath) then
        vim.fs = vim.fs or {}
        vim.fs.joinpath = function(...)
            local parts = { ... }
            local result = table.concat(parts, "/"):gsub("//+", "/")
            return result
        end
    end
end

local function setup_filetypes_and_treesitter_aliases()
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
                lean = "lean",
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
        pcall(vim.treesitter.language.register, "lean", { "lean" })
    end
end

local function setup_clipboard()
    -- Recover local desktop DISPLAY / WAYLAND_DISPLAY when launched inside a persistent
    -- local tmux server, while strictly avoiding local socket probing over SSH so Neovim's
    -- built-in OSC 52 clipboard provider runs unimpeded on remote sessions.
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
    vim.opt.clipboard = "unnamedplus"
end

function M.setup()
    setup_polyfills()

    vim.g.mapleader = " "
    vim.g.maplocalleader = " "

    local opt = vim.opt

    -- Line numbers
    opt.number = true
    opt.relativenumber = true

    -- Tabs and indentation
    opt.tabstop = 4
    opt.shiftwidth = 4
    opt.softtabstop = 4
    opt.expandtab = true
    opt.smartindent = true
    opt.autoindent = true

    -- Appearance and scrolling
    opt.termguicolors = true
    opt.cursorline = true
    opt.signcolumn = "yes"
    opt.scrolloff = 8
    opt.sidescrolloff = 8
    opt.wrap = false
    if vim.fn.exists("+smoothscroll") == 1 then
        opt.smoothscroll = true
    end

    -- Search
    opt.ignorecase = true
    opt.smartcase = true
    opt.hlsearch = true
    opt.incsearch = true

    -- Backup and persistent undo
    opt.backup = false
    opt.writebackup = false
    opt.swapfile = false
    opt.undofile = true

    -- Responsiveness and live buffer reloading
    opt.updatetime = 250
    opt.timeoutlen = 300
    opt.autoread = true

    -- Split geometry
    opt.splitright = true
    opt.splitbelow = true

    -- Built-in Netrw fallback sidebar configuration
    vim.g.netrw_banner = 0
    vim.g.netrw_liststyle = 3
    vim.g.netrw_browse_split = 4
    vim.g.netrw_altv = 1
    vim.g.netrw_winsize = 20

    setup_filetypes_and_treesitter_aliases()
    setup_clipboard()
end

return M
