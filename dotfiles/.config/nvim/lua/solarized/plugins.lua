-- Lazy.nvim bootstrapper, isolated lockfile seeding, and plugin ecosystem assembly.

local treesitter = require("solarized.treesitter")
local lsp = require("solarized.lsp")

local M = {}

local function bootstrap_lazy()
    local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
    if not (vim.uv or vim.loop).fs_stat(lazypath) then
        local out = vim.fn.system({
            "git",
            "clone",
            "--filter=blob:none",
            "https://github.com/folke/lazy.nvim.git",
            "--branch=stable",
            lazypath,
        })
        if vim.v.shell_error ~= 0 then
            error("Failed to clone lazy.nvim:\n" .. tostring(out))
        end
    end
    vim.opt.rtp:prepend(lazypath)
end

local function resolve_lazy_lockfile(repo_root)
    local default_data_home = (vim.fn.expand("$HOME") .. "/.local/share"):gsub("/+$", "")
    local current_data_home = (vim.env.XDG_DATA_HOME and vim.env.XDG_DATA_HOME ~= "")
        and vim.env.XDG_DATA_HOME:gsub("/+$", "")
        or default_data_home
    local cfg_lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
    local repo_lockfile = (repo_root ~= "") and (repo_root .. "/dotfiles/.config/nvim/lazy-lock.json") or cfg_lockfile
    local lazy_lockfile = cfg_lockfile
    if
        current_data_home ~= default_data_home
        or not (vim.uv or vim.loop).fs_stat(vim.fn.stdpath("data") .. "/lazy/solarized.nvim")
    then
        local uv = vim.uv or vim.loop
        local state_dir = vim.fn.stdpath("state")
        vim.fn.mkdir(state_dir, "p")
        lazy_lockfile = state_dir .. "/lazy-lock.json"
        local seed_lockfile = (vim.fn.filereadable(cfg_lockfile) == 1 and cfg_lockfile) or repo_lockfile
        local lock_stat = uv.fs_stat(lazy_lockfile)
        if vim.fn.filereadable(seed_lockfile) == 1 and not (lock_stat and (lock_stat.size or 0) > 0) then
            local tmp_lock = string.format("%s.%d.tmp", lazy_lockfile, vim.fn.getpid())
            if pcall(vim.fn.writefile, vim.fn.readfile(seed_lockfile), tmp_lock) then
                if not uv.fs_rename(tmp_lock, lazy_lockfile) then
                    uv.fs_unlink(tmp_lock)
                end
            end
        end
    end
    return lazy_lockfile
end

local function telescope_plugin_spec()
    return {
        "nvim-telescope/telescope.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
        keys = {
            { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find Files" },
            { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "Live Grep" },
            { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Find Buffers" },
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
    }
end

local function mini_plugin_spec()
    local map = vim.keymap.set
    return {
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
                                cfg.title = nchars <= w and name
                                    or ("…" .. vim.fn.strcharpart(name, nchars - w + 1, w - 1))
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
                    map("n", "<2-LeftMouse>", function()
                        local m = vim.fn.getmousepos()
                        if m.winid > 0 and vim.api.nvim_win_is_valid(m.winid) then
                            vim.api.nvim_set_current_win(m.winid)
                            if m.line > 0 then
                                local win_buf = vim.api.nvim_win_get_buf(m.winid)
                                local line_cnt = vim.api.nvim_buf_line_count(win_buf)
                                pcall(
                                    vim.api.nvim_win_set_cursor,
                                    m.winid,
                                    { math.min(m.line, line_cnt), math.max(0, m.column - 1) }
                                )
                            end
                        end
                        mf.go_in({ close_on_file = true })
                    end, {
                        buffer = buf_id,
                        nowait = true,
                        silent = true,
                        desc = "Open file or enter directory on double-click",
                    })
                end,
            })
        end,
    }
end

local function render_markdown_plugin_spec()
    return {
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
                style = "normal",
                cell = "raw",
                wrap = false,
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
    }
end

function M.setup(ctx, theme)
    bootstrap_lazy()

    local status_ok, lazy = pcall(require, "lazy")
    if not status_ok then
        _G.apply_home_settings_theme()
        return
    end

    -- Skip re-running lazy.setup() when init.lua is re-sourced inside an active session
    if package.loaded["lazy.core.config"] then
        _G.apply_home_settings_theme()
        return
    end

    local specs = {
        theme.solarized_plugin_spec(),
        treesitter.plugin_spec(ctx),
        telescope_plugin_spec(),
    }
    vim.list_extend(specs, lsp.plugin_specs())
    table.insert(specs, mini_plugin_spec())
    table.insert(specs, render_markdown_plugin_spec())

    lazy.setup(specs, {
        lockfile = resolve_lazy_lockfile(ctx and ctx.repo_root or ""),
    })
end

return M
