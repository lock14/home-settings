-- Lazy.nvim bootstrapper, files-refstorage guard, isolated lockfile seeding, and plugin ecosystem assembly.

local treesitter = require("solarized.treesitter")
local lsp = require("solarized.lsp")
local images = require("solarized.images")

local M = {}

local function read_small_file(uv, path)
    if not (uv and uv.fs_open) then
        return nil
    end
    local fd = uv.fs_open(path, "r", 438)
    if not fd then
        return nil
    end
    local st = uv.fs_fstat(fd)
    local data = (st and st.size and st.size > 0 and st.size <= 65536) and uv.fs_read(fd, st.size, 0) or nil
    uv.fs_close(fd)
    return data
end

-- Execute a git command with GIT_DEFAULT_REF_FORMAT=files scoped strictly to the child call so
-- lazy.nvim (which reads raw .git/HEAD and .git/refs/* files) never encounters reftable stubs,
-- without leaking GIT_DEFAULT_REF_FORMAT into Neovim terminals or child shells.
local function run_git_files_ref(cmd)
    local had_env = vim.env.GIT_DEFAULT_REF_FORMAT ~= nil
    local prev_env = vim.env.GIT_DEFAULT_REF_FORMAT
    vim.env.GIT_DEFAULT_REF_FORMAT = "files"
    local ok, out = pcall(vim.fn.system, cmd)
    local err_code = vim.v.shell_error
    if had_env then
        vim.env.GIT_DEFAULT_REF_FORMAT = prev_env
    else
        vim.env.GIT_DEFAULT_REF_FORMAT = nil
    end
    if not ok then
        error(out)
    end
    return out, err_code
end

-- Zero-fork startup scan over stdpath("data")/lazy: only spawns git when a plugin checkout uses
-- Git reftable storage, contains poisoned `.invalid` fetch refspecs, or has nvim-treesitter's
-- origin/HEAD still pointing at legacy master.
local function heal_lazy_git_repos()
    local uv = vim.uv or vim.loop
    if not (uv and uv.fs_scandir) then
        return
    end
    local lazy_root = vim.fn.stdpath("data") .. "/lazy"
    local scan = uv.fs_scandir(lazy_root)
    if not scan then
        return
    end
    while true do
        local name, ftype = uv.fs_scandir_next(scan)
        if not name then
            break
        end
        local dir = lazy_root .. "/" .. name
        local is_dir = (ftype == "directory")
        if not is_dir and (ftype == nil or ftype == "link") then
            local st = uv.fs_stat(dir)
            is_dir = (st ~= nil and st.type == "directory")
        end
        if is_dir then
            local git_dir = dir .. "/.git"
            local git_st = uv.fs_stat(git_dir)
            if git_st and git_st.type == "directory" then
                local rt_st = uv.fs_stat(git_dir .. "/reftable")
                if rt_st and rt_st.type == "directory" then
                    pcall(run_git_files_ref, { "git", "-C", dir, "refs", "migrate", "--ref-format=files" })
                end
                local cfg = read_small_file(uv, git_dir .. "/config")
                if cfg and cfg:find("refs/heads/.invalid", 1, true) then
                    pcall(run_git_files_ref, {
                        "git",
                        "-C",
                        dir,
                        "config",
                        "--unset-all",
                        "remote.origin.fetch",
                        "refs/heads/\\.invalid",
                    })
                end
                if name == "nvim-treesitter" then
                    local origin_head = read_small_file(uv, git_dir .. "/refs/remotes/origin/HEAD")
                    if origin_head and origin_head:find("refs/remotes/origin/master", 1, true) then
                        local has_main = uv.fs_stat(git_dir .. "/refs/remotes/origin/main") ~= nil
                        if not has_main then
                            local packed = read_small_file(uv, git_dir .. "/packed-refs") or ""
                            has_main = packed:find("refs/remotes/origin/main", 1, true) ~= nil
                        end
                        if has_main then
                            pcall(run_git_files_ref, { "git", "-C", dir, "remote", "set-head", "origin", "main" })
                        end
                    end
                end
            end
        end
    end
end

local function wrap_lazy_git_spawn()
    local ok_proc, proc = pcall(require, "lazy.manage.process")
    if not (ok_proc and type(proc) == "table" and type(proc.spawn) == "function") then
        return
    end
    if proc._hs_files_ref_wrapped then
        return
    end
    local orig_spawn = proc.spawn
    proc.spawn = function(cmd, opts)
        local bin = type(cmd) == "table" and cmd[1] or cmd
        if bin == "git" then
            opts = vim.tbl_extend("force", {}, opts or {})
            opts.env = vim.tbl_extend("keep", opts.env or {}, {
                GIT_DEFAULT_REF_FORMAT = "files",
            })
        end
        return orig_spawn(cmd, opts)
    end
    proc._hs_files_ref_wrapped = true
end

local function bootstrap_lazy()
    local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
    if not (vim.uv or vim.loop).fs_stat(lazypath) then
        local out, err_code = run_git_files_ref({
            "git",
            "clone",
            "--filter=blob:none",
            "https://github.com/folke/lazy.nvim.git",
            "--branch=stable",
            lazypath,
        })
        if err_code ~= 0 then
            error("Failed to clone lazy.nvim:\n" .. tostring(out))
        end
    end
    vim.opt.rtp:prepend(lazypath)
end

local function resolve_lazy_lockfile(repo_root)
    if vim.env.NVIM_LAZY_LOCKFILE and vim.env.NVIM_LAZY_LOCKFILE ~= "" then
        return vim.env.NVIM_LAZY_LOCKFILE
    end
    local uv = vim.uv or vim.loop
    local default_data_home = (vim.fn.expand("$HOME") .. "/.local/share"):gsub("/+$", "")
    local current_data_home = (vim.env.XDG_DATA_HOME and vim.env.XDG_DATA_HOME ~= "")
        and vim.env.XDG_DATA_HOME:gsub("/+$", "")
        or default_data_home
    local cfg_lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
    local repo_lockfile = (repo_root ~= "") and (repo_root .. "/dotfiles/.config/nvim/lazy-lock.json") or cfg_lockfile
    local lazy_lockfile = cfg_lockfile
    if
        current_data_home ~= default_data_home
        or not uv.fs_stat(vim.fn.stdpath("data") .. "/lazy/solarized.nvim")
    then
        local state_dir = vim.fn.stdpath("state")
        vim.fn.mkdir(state_dir, "p")
        lazy_lockfile = state_dir .. "/lazy-lock.json"
        local seed_lockfile = (vim.fn.filereadable(cfg_lockfile) == 1 and cfg_lockfile) or repo_lockfile
        if vim.fn.filereadable(seed_lockfile) == 1 then
            local seed_raw = read_small_file(uv, seed_lockfile)
            local cur_raw = read_small_file(uv, lazy_lockfile)
            if seed_raw and seed_raw ~= cur_raw then
                local tmp_lock = string.format("%s.%d.tmp", lazy_lockfile, vim.fn.getpid())
                if pcall(vim.fn.writefile, vim.fn.readfile(seed_lockfile), tmp_lock) then
                    if not uv.fs_rename(tmp_lock, lazy_lockfile) then
                        uv.fs_unlink(tmp_lock)
                    end
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
                layout_strategy = "flex",
                layout_config = {
                    width = 0.94,
                    height = 0.90,
                    horizontal = { preview_width = 0.55 },
                    vertical = { preview_height = 0.50, mirror = false },
                    flex = { flip_columns = 110 },
                },
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
            local function mini_files_window_widths()
                local cols = vim.o.columns
                if cols >= 80 then
                    return 35, 25
                end
                local wf = math.max(18, math.min(35, math.floor(cols * 0.42)))
                local wp = math.max(15, math.min(25, cols - wf - 6))
                return wf, wp
            end
            local init_wf, init_wp = mini_files_window_widths()
            require("mini.files").setup({
                windows = {
                    max_number = 2,
                    preview = true,
                    width_focus = init_wf,
                    width_nofocus = 15,
                    width_preview = init_wp,
                },
            })
            local mf = require("mini.files")
            local mf_group = vim.api.nvim_create_augroup("SolarizedMiniFilesWindow", { clear = true })
            local last_wf, last_wp = init_wf, init_wp
            local function sync_mini_files_widths()
                local wf, wp = mini_files_window_widths()
                local changed = (wf ~= last_wf or wp ~= last_wp)
                last_wf, last_wp = wf, wp
                if mf.config and mf.config.windows then
                    mf.config.windows.width_focus = wf
                    mf.config.windows.width_preview = wp
                end
                if changed then
                    local st = mf.get_explorer_state()
                    if st and st.windows and #st.windows > 0 then
                        mf.refresh({ windows = { width_focus = wf, width_preview = wp } })
                    end
                end
            end
            vim.api.nvim_create_autocmd("User", {
                group = mf_group,
                pattern = "MiniFilesExplorerOpen",
                callback = sync_mini_files_widths,
            })
            vim.api.nvim_create_autocmd("VimResized", {
                group = mf_group,
                callback = sync_mini_files_widths,
            })
            vim.api.nvim_create_autocmd("User", {
                group = mf_group,
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

M.heal_lazy_git_repos = heal_lazy_git_repos
M.wrap_lazy_git_spawn = wrap_lazy_git_spawn

function M.setup(ctx, theme)
    heal_lazy_git_repos()
    bootstrap_lazy()

    local status_ok, lazy = pcall(require, "lazy")
    if not status_ok then
        _G.apply_home_settings_theme()
        return
    end

    -- Skip re-running lazy.setup() when init.lua is re-sourced inside an active session
    if package.loaded["lazy.core.config"] then
        _G.apply_home_settings_theme()
        images.on_reload()
        return
    end

    -- Wrap lazy.manage.process.spawn lazily when any Lazy git lifecycle task begins so
    -- `lazy.core.config` is not prematurely loaded before `lazy.setup()` runs.
    vim.api.nvim_create_autocmd("User", {
        group = vim.api.nvim_create_augroup("SolarizedLazyGitRefFormat", { clear = true }),
        pattern = { "LazyInstallPre", "LazyUpdatePre", "LazySyncPre", "LazyRestorePre", "LazyCheckPre" },
        callback = wrap_lazy_git_spawn,
    })

    local specs = {
        theme.solarized_plugin_spec(),
        treesitter.plugin_spec(ctx),
        telescope_plugin_spec(),
    }
    vim.list_extend(specs, lsp.plugin_specs())
    table.insert(specs, mini_plugin_spec())
    table.insert(specs, render_markdown_plugin_spec())
    table.insert(specs, images.plugin_spec())

    lazy.setup(specs, {
        lockfile = resolve_lazy_lockfile(ctx and ctx.repo_root or ""),
    })
end

return M
