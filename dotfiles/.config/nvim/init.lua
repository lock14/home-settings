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

-- System Clipboard Integration (GNOME Terminal / X11 / Wayland / macOS + OSC 52 SSH fallback)
if vim.fn.has("linux") == 1 then
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
    if (not vim.env.DISPLAY or vim.env.DISPLAY == "") and (not vim.env.WAYLAND_DISPLAY or vim.env.WAYLAND_DISPLAY == "") then
        local ok_osc, osc52 = pcall(require, "vim.ui.clipboard.osc52")
        if ok_osc and osc52 then
            vim.g.clipboard = {
                name = "OSC 52",
                copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
                paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
            }
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

-- Auto-copy mouse visual selection to system clipboard (+ and *) on mouse release
-- Matches terminal copy-on-select ergonomics and ensures GNOME Terminal Ctrl+Shift+C -> Ctrl+V
-- works seamlessly while keeping the visual highlight active (gv) for vim operators (d, c, >).
map("x", "<LeftRelease>", function()
    if vim.bo.filetype == "ide_tree" then
        return "<LeftRelease>"
    end
    return '<LeftRelease>"+ygv"*ygv'
end, { expr = true, silent = true, desc = "Auto-copy mouse selection to clipboard and primary" })
map("x", "<C-c>", '"+y', { silent = true, desc = "Copy visual selection to system clipboard" })

-- Middle-click (<MiddleMouse>) paste from Primary (*) or System Clipboard (+) at clicked position
local function get_middle_paste_text()
    for _, reg in ipairs({ "*", "+", '"' }) do
        local ok, val = pcall(vim.fn.getreg, reg)
        if ok and type(val) == "string" and val ~= "" then
            return val
        end
    end
    return ""
end

map({ "n", "i" }, "<MiddleMouse>", function()
    local left_click = vim.api.nvim_replace_termcodes("<LeftMouse>", true, false, true)
    vim.api.nvim_feedkeys(left_click, "nx", false)
    if vim.bo.filetype == "ide_tree" or not vim.bo.modifiable then
        return
    end
    local text = get_middle_paste_text()
    if text ~= "" then
        vim.api.nvim_paste(text, true, -1)
    end
end, { silent = true, desc = "Middle-click paste from primary or system clipboard" })

map("x", "<MiddleMouse>", function()
    if vim.bo.filetype == "ide_tree" or not vim.bo.modifiable then
        return
    end
    local text = get_middle_paste_text()
    if text ~= "" then
        vim.api.nvim_paste(text, true, -1)
    end
end, { silent = true, desc = "Middle-click replace visual selection from primary or clipboard" })

map("c", "<MiddleMouse>", function()
    local ok_star, star = pcall(vim.fn.getreg, "*")
    if ok_star and type(star) == "string" and star ~= "" then
        return "<C-r>*"
    end
    return "<C-r>+"
end, { expr = true, desc = "Middle-click paste into command line" })

for _, mc in ipairs({ "<2-MiddleMouse>", "<3-MiddleMouse>", "<4-MiddleMouse>" }) do
    map({ "n", "i", "x", "c" }, mc, "<Nop>", { silent = true })
end

-- Clear search highlight
map("n", "<leader>h", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Fast Save
map("n", "<leader>w", "<cmd>w<CR>", { desc = "Save file" })

-- Seamless Window & 4-Layer Spatial Tmux Navigation (Ctrl + hjkl in Normal, Alt + hjkl in all modes)
-- Guarded against floating modals (Telescope/LSP/MiniFiles) BEFORE stopinsert() and zoomed tmux panes.
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
        end
        vim.cmd("wincmd " .. dir)
        if vim.api.nvim_get_current_win() == cur_win and vim.env.TMUX then
            local target_cmd = "select-pane -" .. tmux_dir
            vim.fn.system({
                "tmux",
                "if-shell",
                "-F",
                "#{==:#{window_zoomed_flag},0}",
                target_cmd,
            })
        end
    end
end

map("n", "<C-h>", smart_tmux_nav("h", "L"), { desc = "Move to left split or tmux pane" })
map("n", "<C-j>", smart_tmux_nav("j", "D"), { desc = "Move to lower split or tmux pane" })
map("n", "<C-k>", smart_tmux_nav("k", "U"), { desc = "Move to upper split or tmux pane" })
map("n", "<C-l>", smart_tmux_nav("l", "R"), { desc = "Move to right split or tmux pane" })

map({ "n", "i", "v", "t" }, "<M-h>", smart_tmux_nav("h", "L"), { desc = "Move to left split or tmux pane" })
map({ "n", "i", "v", "t" }, "<M-j>", smart_tmux_nav("j", "D"), { desc = "Move to lower split or tmux pane" })
map({ "n", "i", "v", "t" }, "<M-k>", smart_tmux_nav("k", "U"), { desc = "Move to upper split or tmux pane" })
map({ "n", "i", "v", "t" }, "<M-l>", smart_tmux_nav("l", "R"), { desc = "Move to right split or tmux pane" })

-- Fast Buffer Cycling in Normal Mode (overridden buffer-locally inside SolarizedIdeTree)
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
-- the session explicitly, so `ide` never has to work out which session called it. Without an `ide-*`
-- $IDE_SESSION (an Editor started outside `ide`), `ide` falls back to looking up this pane's session.
local function ide_job(...)
    local cmd = { vim.fn.expand("$HOME/.local/bin/ide"), ... }
    local sess = vim.env.IDE_SESSION
    if sess and sess:match("^ide%-") then
        table.insert(cmd, sess)
    end
    vim.fn.jobstart(cmd, { detach = true })
end

-- =============================================================================
-- Native Solarized IDE Directory Tree Explorer (`SolarizedIdeTree`)
-- Zero-dependency, in-process sidebar split (`Space+e`), instant expand/collapse
-- (`Enter`, `o`, `l`, `h`, Mouse), file open (`Enter`) & preview (`Tab` / `p`)
-- =============================================================================
local IdeTree = _G.IdeTree or {
    buf = nil,
    ns = vim.api.nvim_create_namespace("SolarizedIdeTree"),
    root = vim.fn.getcwd(),
    initial_root = vim.env.IDE_INITIAL_ROOT or vim.fn.getcwd(),
    expanded = {},
    entries = {},
    dir_cache = {},
    max_entries = 500,
    dotfile_mode = 1, -- 1 = show dotfiles (hide .git), 2 = show all including .git, 0 = hide dotfiles
}
_G.IdeTree = IdeTree

local function ide_tree_icon(name, is_dir, is_open)
    if is_dir then
        return is_open and "" or ""
    end
    local ext = name:match("%.([^%.]+)$") or ""
    ext = ext:lower()
    local icons = {
        lua = "", sh = "", zsh = "", bash = "",
        go = "", py = "", rs = "", js = "", ts = "",
        c = "", h = "", cpp = "", cc = "", hpp = "",
        java = "", md = "", json = "", yaml = "", yml = "",
        toml = "", conf = "", vim = "", html = "", css = "",
        xml = "󰗀", sql = "", tf = "",
    }
    return icons[ext] or ""
end

function IdeTree.should_show(name)
    if IdeTree.dotfile_mode == 2 then
        return true
    elseif IdeTree.dotfile_mode == 1 then
        return name ~= ".git" and name ~= ".DS_Store"
    else
        return name:sub(1, 1) ~= "."
    end
end

function IdeTree.invalidate_cache(dir)
    if dir then
        IdeTree.dir_cache[dir] = nil
    else
        IdeTree.dir_cache = {}
    end
end

function IdeTree.scan_dir(dir)
    if IdeTree.dir_cache[dir] then
        return IdeTree.dir_cache[dir]
    end
    local uv = vim.uv or vim.loop
    local req = uv.fs_scandir(dir)
    if not req then
        return {}
    end
    local dirs, files = {}, {}
    while true do
        local name, ftype = uv.fs_scandir_next(req)
        if not name then
            break
        end
        if IdeTree.should_show(name) then
            local full = dir .. "/" .. name
            if not ftype or ftype == "link" then
                local st = uv.fs_stat(full)
                ftype = st and st.type or "file"
            end
            if ftype == "directory" then
                table.insert(dirs, { name = name, path = full, is_dir = true })
            else
                table.insert(files, { name = name, path = full, is_dir = false })
            end
        end
    end
    table.sort(dirs, function(a, b) return a.name:lower() < b.name:lower() end)
    table.sort(files, function(a, b) return a.name:lower() < b.name:lower() end)
    for _, f in ipairs(files) do
        table.insert(dirs, f)
    end
    IdeTree.dir_cache[dir] = dirs
    return dirs
end

-- Automatically unfold single-child directory chains (e.g. java/com/google/...) up to 6 levels
function IdeTree.auto_expand_chain(dir)
    local cur = dir
    local last = dir
    for _ = 1, 6 do
        local children = IdeTree.scan_dir(cur)
        if #children == 1 and children[1].is_dir then
            cur = children[1].path
            IdeTree.expanded[cur] = true
            last = cur
        else
            break
        end
    end
    return last
end

function IdeTree.set_root(new_root)
    if not new_root or new_root == "" then
        return
    end
    local resolved = vim.fn.fnamemodify(new_root, ":p"):gsub("/+$", "")
    if resolved == "" then
        resolved = "/"
    end
    if vim.fn.isdirectory(resolved) ~= 1 then
        vim.api.nvim_echo({ { "Directory does not exist: " .. resolved, "ErrorMsg" } }, true, {})
        return
    end
    IdeTree.root = resolved
    IdeTree.expanded = {}
    IdeTree.invalidate_cache()
    pcall(vim.cmd, "cd " .. vim.fn.fnameescape(resolved))
    IdeTree.auto_expand_chain(resolved)
    IdeTree.render()
end

function IdeTree.dive(target_dir)
    if not target_dir or target_dir == "" then
        return
    end
    local actual_dir = target_dir
    if target_dir == "--reset" or target_dir == "~" then
        actual_dir = IdeTree.initial_root
    end
    IdeTree.set_root(actual_dir)
    if vim.env.TMUX then
        ide_job("--cd", actual_dir)
    end
end

function IdeTree.render(target_path)
    if not IdeTree.buf or not vim.api.nvim_buf_is_valid(IdeTree.buf) then
        return
    end
    local win = vim.fn.bufwinid(IdeTree.buf)
    local cur_line = (win ~= -1) and vim.api.nvim_win_get_cursor(win)[1] or 2
    if not target_path and IdeTree.entries[cur_line] then
        target_path = IdeTree.entries[cur_line].path
    end

    local lines = {}
    local highlights = {}
    IdeTree.entries = {}

    local root_name = vim.fn.fnamemodify(IdeTree.root, ":t")
    if root_name == "" then root_name = "/" end
    local rel_suffix = ""
    if IdeTree.initial_root and IdeTree.root ~= IdeTree.initial_root and IdeTree.root:sub(1, #IdeTree.initial_root + 1) == (IdeTree.initial_root .. "/") then
        rel_suffix = " (" .. IdeTree.root:sub(#IdeTree.initial_root + 2) .. ")"
    end
    lines[1] = "  " .. root_name .. "/" .. rel_suffix
    IdeTree.entries[1] = { path = IdeTree.root, name = root_name, is_dir = true, depth = -1, parent = vim.fn.fnamemodify(IdeTree.root, ":h") }
    table.insert(highlights, { line = 0, col_start = 0, col_end = #lines[1], hl = "Directory" })

    local function walk(dir, depth)
        local children = IdeTree.scan_dir(dir)
        local limit = math.min(#children, IdeTree.max_entries)
        for i = 1, limit do
            local item = children[i]
            local lnum = #lines + 1
            local indent = string.rep("  ", depth)
            if item.is_dir then
                local is_open = IdeTree.expanded[item.path] == true
                local chevron = is_open and " " or " "
                local icon = ide_tree_icon(item.name, true, is_open) .. " "
                local text = " " .. indent .. chevron .. icon .. item.name .. "/"
                lines[lnum] = text
                IdeTree.entries[lnum] = {
                    path = item.path,
                    name = item.name,
                    is_dir = true,
                    depth = depth,
                    parent = dir,
                }
                local chev_start = 1 + #indent
                local chev_end = chev_start + #chevron
                table.insert(highlights, { line = lnum - 1, col_start = 0, col_end = chev_end, hl = "Comment" })
                table.insert(highlights, { line = lnum - 1, col_start = chev_end, col_end = #text, hl = "Directory" })
                if is_open then
                    walk(item.path, depth + 1)
                end
            else
                local icon = ide_tree_icon(item.name, false, false) .. " "
                local text = " " .. indent .. "  " .. icon .. item.name
                lines[lnum] = text
                IdeTree.entries[lnum] = {
                    path = item.path,
                    name = item.name,
                    is_dir = false,
                    depth = depth,
                    parent = dir,
                }
                local icon_end = 1 + #indent + 2 + #icon
                table.insert(highlights, { line = lnum - 1, col_start = 0, col_end = icon_end, hl = "Comment" })
                table.insert(highlights, { line = lnum - 1, col_start = icon_end, col_end = #text, hl = "Normal" })
            end
        end
        if #children > limit then
            local lnum = #lines + 1
            local indent = string.rep("  ", depth)
            local more_cnt = #children - limit
            local text = " " .. indent .. "  … (+" .. tostring(more_cnt) .. " more — press '>' or D to dive)"
            lines[lnum] = text
            IdeTree.entries[lnum] = { path = dir, name = "…", is_dir = true, depth = depth, parent = dir, is_more_hint = true }
            table.insert(highlights, { line = lnum - 1, col_start = 0, col_end = #text, hl = "Comment" })
        end
    end

    walk(IdeTree.root, 0)

    vim.bo[IdeTree.buf].modifiable = true
    vim.api.nvim_buf_set_lines(IdeTree.buf, 0, -1, false, lines)
    vim.bo[IdeTree.buf].modifiable = false
    vim.bo[IdeTree.buf].modified = false

    vim.api.nvim_buf_clear_namespace(IdeTree.buf, IdeTree.ns, 0, -1)
    for _, h in ipairs(highlights) do
        vim.api.nvim_buf_set_extmark(IdeTree.buf, IdeTree.ns, h.line, h.col_start, {
            end_col = h.col_end,
            hl_group = h.hl,
        })
    end

    if win ~= -1 then
        local new_line = math.min(cur_line, #lines)
        if target_path then
            for idx, entry in ipairs(IdeTree.entries) do
                if entry.path == target_path then
                    new_line = idx
                    break
                end
            end
        end
        pcall(vim.api.nvim_win_set_cursor, win, { math.max(1, new_line), 1 })
    end
end

function IdeTree.focus_code_win()
    local cur_win = vim.api.nvim_get_current_win()
    local cur_cfg = vim.api.nvim_win_get_config(cur_win)
    local cur_ft = vim.bo.filetype
    if (not cur_cfg.relative or cur_cfg.relative == "") and cur_ft ~= "ide_tree" and cur_ft ~= "netrw" then
        return cur_win
    end
    vim.cmd("wincmd p")
    local prev_win = vim.api.nvim_get_current_win()
    local prev_cfg = vim.api.nvim_win_get_config(prev_win)
    local prev_ft = vim.bo.filetype
    if prev_win ~= cur_win and (not prev_cfg.relative or prev_cfg.relative == "") and prev_ft ~= "ide_tree" and prev_ft ~= "netrw" then
        return prev_win
    end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local cfg = vim.api.nvim_win_get_config(win)
        if win ~= cur_win and (not cfg.relative or cfg.relative == "") then
            local buf = vim.api.nvim_win_get_buf(win)
            local ft = vim.bo[buf].filetype
            if ft ~= "ide_tree" and ft ~= "netrw" then
                vim.api.nvim_set_current_win(win)
                return win
            end
        end
    end
    vim.cmd("rightbelow vnew")
    vim.opt_local.number = true
    vim.opt_local.relativenumber = true
    vim.opt_local.signcolumn = "yes"
    vim.opt_local.winfixwidth = false
    vim.opt_local.winfixheight = false
    vim.opt_local.statusline = ""
    if vim.api.nvim_win_is_valid(cur_win) then
        pcall(vim.api.nvim_win_set_width, cur_win, 28)
    end
    return vim.api.nvim_get_current_win()
end

function IdeTree.dispatch_file(filepath, focus_editor)
    local cur_win = vim.api.nvim_get_current_win()
    IdeTree.focus_code_win()
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
    if not focus_editor and vim.api.nvim_win_is_valid(cur_win) then
        vim.api.nvim_set_current_win(cur_win)
    end
end

function IdeTree.action_enter(focus_editor)
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local item = IdeTree.entries[lnum]
    if not item then return end
    if item.is_more_hint then
        IdeTree.action_prompt_dive()
        return
    end
    if lnum == 1 then
        IdeTree.invalidate_cache()
        IdeTree.render()
        return
    end
    if item.is_dir then
        local next_state = not IdeTree.expanded[item.path]
        IdeTree.expanded[item.path] = next_state
        local target = item.path
        if next_state then
            target = IdeTree.auto_expand_chain(item.path)
        end
        IdeTree.render(target)
    else
        IdeTree.dispatch_file(item.path, focus_editor ~= false)
    end
end

function IdeTree.action_expand()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local item = IdeTree.entries[lnum]
    if not item then return end
    if item.is_dir then
        if not IdeTree.expanded[item.path] then
            IdeTree.expanded[item.path] = true
            local target = IdeTree.auto_expand_chain(item.path)
            IdeTree.render(target)
        elseif lnum < #IdeTree.entries then
            vim.api.nvim_win_set_cursor(0, { lnum + 1, 1 })
        end
    else
        IdeTree.dispatch_file(item.path, true)
    end
end

function IdeTree.action_collapse()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local item = IdeTree.entries[lnum]
    if not item then return end
    if lnum == 1 then
        local parent_dir = vim.fn.fnamemodify(IdeTree.root, ":h")
        if parent_dir ~= "" and parent_dir ~= IdeTree.root then
            IdeTree.dive(parent_dir)
        end
        return
    end
    if item.is_dir and IdeTree.expanded[item.path] then
        IdeTree.expanded[item.path] = false
        IdeTree.render(item.path)
    elseif item.parent and item.parent ~= IdeTree.root then
        IdeTree.expanded[item.parent] = false
        IdeTree.render(item.parent)
    end
end

function IdeTree.action_dive_cursor()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local item = IdeTree.entries[lnum]
    if not item then return end
    local target = item.is_dir and item.path or (item.parent or IdeTree.root)
    if target and target ~= "" then
        IdeTree.dive(target)
    end
end

function IdeTree.action_dive_up()
    local parent_dir = vim.fn.fnamemodify(IdeTree.root, ":h")
    if parent_dir and parent_dir ~= "" and parent_dir ~= IdeTree.root then
        IdeTree.dive(parent_dir)
    end
end

function IdeTree.action_prompt_dive()
    local input = vim.fn.input("Dive IDE to path: ", IdeTree.root .. "/", "dir")
    if input and input ~= "" then
        IdeTree.dive(input)
    end
end

function IdeTree.action_expand_all(dir, depth)
    dir = dir or IdeTree.root
    depth = depth or 0
    if depth > 2 then return end
    for _, item in ipairs(IdeTree.scan_dir(dir)) do
        if item.is_dir then
            IdeTree.expanded[item.path] = true
            IdeTree.action_expand_all(item.path, depth + 1)
        end
    end
    if depth == 0 then IdeTree.render() end
end

function IdeTree.action_create()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local item = IdeTree.entries[lnum] or IdeTree.entries[1]
    local base_dir = item.is_dir and item.path or (item.parent or IdeTree.root)
    local input = vim.fn.input("New file/folder (end with / for dir): ")
    if input == "" then return end
    local target = base_dir .. "/" .. input
    if input:sub(-1) == "/" then
        vim.fn.mkdir(target, "p")
    else
        vim.fn.mkdir(vim.fn.fnamemodify(target, ":h"), "p")
        vim.fn.writefile({}, target)
    end
    IdeTree.invalidate_cache(base_dir)
    IdeTree.expanded[base_dir] = true
    IdeTree.render(target:gsub("/$", ""))
end

function IdeTree.action_rename()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local item = IdeTree.entries[lnum]
    if not item or lnum == 1 then return end
    local new_name = vim.fn.input("Rename " .. item.name .. " to: ", item.name)
    if new_name == "" or new_name == item.name then return end
    local dest = (item.parent or IdeTree.root) .. "/" .. new_name
    vim.fn.rename(item.path, dest)
    IdeTree.invalidate_cache(item.parent or IdeTree.root)
    IdeTree.render(dest)
end

function IdeTree.action_delete()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local item = IdeTree.entries[lnum]
    if not item or lnum == 1 then return end
    local ans = vim.fn.input("Delete '" .. item.name .. "'? (y/N): ")
    if ans:lower() == "y" then
        vim.fn.delete(item.path, "rf")
        IdeTree.invalidate_cache(item.parent or IdeTree.root)
        IdeTree.render()
    end
end

function IdeTree.attach_mappings(buf)
    local bmap = function(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, nowait = true, desc = desc })
    end
    bmap("<CR>", function() IdeTree.action_enter(true) end, "Toggle directory or open file in Editor")
    bmap("o", function() IdeTree.action_enter(true) end, "Toggle directory or open file in Editor")
    bmap("l", IdeTree.action_expand, "Expand directory or open file")
    bmap("<Right>", IdeTree.action_expand, "Expand directory or open file")
    bmap("h", IdeTree.action_collapse, "Collapse directory or parent")
    bmap("<Left>", IdeTree.action_collapse, "Collapse directory or parent")
    bmap("-", IdeTree.action_collapse, "Collapse directory or parent")
    bmap(">", IdeTree.action_dive_cursor, "Dive IDE into directory under cursor")
    bmap("C", IdeTree.action_dive_cursor, "Dive IDE into directory under cursor")
    bmap("<", IdeTree.action_dive_up, "Dive IDE up to parent directory (..)")
    bmap("<BS>", IdeTree.action_dive_up, "Dive IDE up to parent directory (..)")
    bmap("D", IdeTree.action_prompt_dive, "Prompt for path and dive IDE working directory")
    bmap("~", function() IdeTree.dive("--reset") end, "Reset IDE working directory to initial root")
    bmap("=", function() IdeTree.dive("--reset") end, "Reset IDE working directory to initial root")
    bmap("<Tab>", function() IdeTree.action_enter(false) end, "Toggle directory or preview file")
    bmap("p", function() IdeTree.action_enter(false) end, "Preview file in Editor")
    bmap("<LeftMouse>", function()
        local now = (vim.uv or vim.loop).hrtime()
        local pos = vim.fn.getmousepos()
        if pos and pos.winid and pos.winid > 0 and vim.api.nvim_win_is_valid(pos.winid) then
            local was_focused = (pos.winid == vim.api.nvim_get_current_win())
            if not was_focused then
                IdeTree.suppress_release = true
                vim.api.nvim_set_current_win(pos.winid)
            elseif (now - (IdeTree.focus_gained_ns or 0)) < 150000000 then
                IdeTree.suppress_release = true
            else
                IdeTree.suppress_release = false
            end
            if pos.line and pos.line > 0 then
                local line_cnt = vim.api.nvim_buf_line_count(buf)
                local target_line = math.min(pos.line, line_cnt)
                pcall(vim.api.nvim_win_set_cursor, pos.winid, { target_line, math.max(0, (pos.column or 1) - 1) })
                IdeTree.mouse_down_line = target_line
            end
        end
    end, "Position cursor and latch focus state on mouse down")
    bmap("<2-LeftMouse>", function()
        local lnum = vim.api.nvim_win_get_cursor(0)[1]
        local item = IdeTree.entries[lnum]
        if item and not item.is_dir then
            IdeTree.dispatch_file(item.path, true)
        end
    end, "Open file on double-click")
    bmap("<LeftRelease>", function()
        if IdeTree.suppress_release then
            IdeTree.suppress_release = false
            return
        end
        local now = (vim.uv or vim.loop).hrtime()
        if (now - (IdeTree.focus_gained_ns or 0)) < 150000000 then
            return
        end
        local pos = vim.fn.getmousepos()
        local lnum = vim.api.nvim_win_get_cursor(0)[1]
        if pos and pos.line and pos.line > 0 and IdeTree.mouse_down_line and pos.line ~= IdeTree.mouse_down_line then
            return
        end
        local item = IdeTree.entries[lnum]
        if item and item.is_dir and lnum > 1 then
            if IdeTree.last_dir_toggle_path == item.path and (now - (IdeTree.last_dir_toggle_ns or 0)) < 450000000 then
                return
            end
            IdeTree.last_dir_toggle_ns = now
            IdeTree.last_dir_toggle_path = item.path
            local next_state = not IdeTree.expanded[item.path]
            IdeTree.expanded[item.path] = next_state
            local target = item.path
            if next_state then
                target = IdeTree.auto_expand_chain(item.path)
            end
            IdeTree.render(target)
        end
    end, "Single-click toggle directory")
    bmap("W", function() IdeTree.expanded = {}; IdeTree.render() end, "Collapse all directories")
    bmap("E", function() IdeTree.action_expand_all() end, "Expand all directories")
    bmap("R", function() IdeTree.invalidate_cache(); IdeTree.render() end, "Refresh directory tree")
    bmap(".", function()
        IdeTree.dotfile_mode = (IdeTree.dotfile_mode + 1) % 3
        IdeTree.invalidate_cache()
        IdeTree.render()
    end, "Cycle hidden dotfiles filter")
    bmap("H", function()
        IdeTree.dotfile_mode = (IdeTree.dotfile_mode + 1) % 3
        IdeTree.invalidate_cache()
        IdeTree.render()
    end, "Cycle hidden dotfiles filter")
    bmap("a", IdeTree.action_create, "Create file or directory")
    bmap("r", IdeTree.action_rename, "Rename file or directory")
    bmap("d", IdeTree.action_delete, "Delete file or directory")
end

function IdeTree.open_in_current_win()
    if not IdeTree.buf or not vim.api.nvim_buf_is_valid(IdeTree.buf) then
        IdeTree.buf = vim.api.nvim_create_buf(false, true)
        vim.bo[IdeTree.buf].buftype = "nofile"
        vim.bo[IdeTree.buf].bufhidden = "hide"
        vim.bo[IdeTree.buf].swapfile = false
        vim.bo[IdeTree.buf].filetype = "ide_tree"
        IdeTree.attach_mappings(IdeTree.buf)
    end
    vim.api.nvim_win_set_buf(0, IdeTree.buf)
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = "no"
    vim.opt_local.wrap = false
    vim.opt_local.cursorline = true
    vim.opt_local.winfixwidth = true
    vim.opt_local.winfixheight = true
    vim.opt_local.statusline = "  Directory "
    IdeTree.render()
end

function IdeTree.toggle_split()
    if IdeTree.buf and vim.api.nvim_buf_is_valid(IdeTree.buf) then
        local win = vim.fn.bufwinid(IdeTree.buf)
        if win ~= -1 then
            if vim.fn.winnr("$") == 1 then
                vim.api.nvim_set_current_win(win)
                IdeTree.focus_code_win()
            end
            pcall(vim.api.nvim_win_close, win, true)
            return
        end
    end
    vim.cmd("topleft 28vnew")
    IdeTree.open_in_current_win()
end

-- Project Tree Sidebar Toggle: toggles the in-process SolarizedIdeTree split (`Space+e`)
map("n", "<leader>e", function()
    IdeTree.toggle_split()
end, { desc = "Toggle Project Tree Sidebar" })

-- =============================================================================
-- AI Live-Follow Mode (`IdeFollow`)
-- Automatically reloads buffers (`checktime`), opens the files the AI edits in
-- the Top-Right Editor pane, and centers (`normal! zz`) the line it changed
-- while you stay in the Top-Left AI Agent pane.
-- Session-scoped: only AI conversations launched in this IDE session's root
-- drive the Editor, so concurrent `ide` sessions never move each other.
-- Follow signals (the 1.5 s tick never waits on a subprocess):
--   1. Edit logs: each file-edit tool call this session's AI records (agy
--      `transcript_full.jsonl`, Claude Code project transcripts) names the
--      exact file and line, in any workspace (git, Mercurial, or none).
--   2. Plan & walkthrough artifacts written by those conversations.
--   3. A background `git status` (adaptive backoff) for edits the AI makes
--      through shell commands (`sed -i`, formatters, code generators).
-- =============================================================================
local IdeFollow = _G.IdeFollow or {
    enabled = (vim.env.NVIM_IDE_SOCKET ~= nil and vim.env.NVIM_IDE_SOCKET ~= ""),
    last_mtime_ns = 0,
    last_file = "",
    timer = nil,
}
-- Reuse the live table on `:source` so the running follow timer and `Space af` keep sharing state
_G.IdeFollow = IdeFollow
IdeFollow.agy_history = IdeFollow.agy_history or {} -- per agy prompt log: { offset, partial, convs }
IdeFollow.plan_verdicts = IdeFollow.plan_verdicts or {}
IdeFollow.workspace_roots = IdeFollow.workspace_roots or {}
-- Edit logs being tailed ([log path] = read state) and the files they recently edited ([path] = hint)
IdeFollow.edit_logs = IdeFollow.edit_logs or {}
IdeFollow.edits = IdeFollow.edits or {}
IdeFollow.edit_seq = IdeFollow.edit_seq or 0
-- Background `git status` of the current root (`paths`: most recently modified dirty files of the last scan)
IdeFollow.vcs = IdeFollow.vcs or { root = nil, toplevel = nil, paths = {}, inflight = false, next_ns = 0, gen = 0, scans = 0 }
IdeFollow.jumps = IdeFollow.jumps or 0 -- bumped on every follow so stale async hunk lookups are dropped

local IDE_FOLLOW_TICK_MS = 1500
local IDE_FOLLOW_MAX_CONVERSATIONS = 8 -- most recent AI conversations per workspace to watch
local IDE_FOLLOW_MAX_SUBAGENT_DEPTH = 2 -- nested subagent levels watched below each conversation
local IDE_FOLLOW_MAX_DIRS = 32 -- conversation directories scanned per tick (newest first)
local IDE_FOLLOW_FRESH_SECONDS = 120 -- keep re-checking ownership of brand-new plans this long
local IDE_FOLLOW_TRANSCRIPT_TAIL = 2 * 1024 * 1024 -- transcript bytes searched for a plan reference
local IDE_FOLLOW_EDIT_LOG_TAIL = 256 * 1024 -- bytes of a newly discovered edit log parsed for recent edits
local IDE_FOLLOW_MAX_EDITS = 16 -- recently edited files kept as follow candidates
local IDE_FOLLOW_MAX_CLAUDE_LOGS = 4 -- most recently active Claude Code transcripts tailed per project
local IDE_FOLLOW_MAX_VCS_PATHS = 64 -- most recently modified dirty files re-checked on every tick
local IDE_FOLLOW_VCS_BACKOFF = 4 -- idle time between git scans, as a multiple of the last scan's duration
local IDE_FOLLOW_AGY_RESCAN_SECONDS = 30 -- how often ~/.gemini is re-listed for agy data directories

local function stat_mtime_ns(path)
    local uv = vim.uv or vim.loop
    local st = uv.fs_stat(path)
    if not st or st.type ~= "file" or not st.mtime then
        return 0
    end
    return (st.mtime.sec or 0) * 1000000000 + (st.mtime.nsec or 0)
end

-- Reads up to `len` bytes of `path` starting at byte `offset` (nil when unreadable).
local function read_bytes(path, offset, len)
    local uv = vim.uv or vim.loop
    local fd = uv.fs_open(path, "r", 438)
    if not fd then
        return nil
    end
    local data = uv.fs_read(fd, len, offset)
    uv.fs_close(fd)
    return data
end

-- Wall-clock time in the same nanosecond units as file mtimes.
local function now_ns()
    local uv = vim.uv or vim.loop
    local t = uv.clock_gettime and uv.clock_gettime("realtime")
    return t and (t.sec * 1000000000 + t.nsec) or os.time() * 1000000000
end

local function strip_trailing_slash(path)
    return (path:gsub("(.)/+$", "%1"))
end

-- Workspace containing `dir`: its nearest ancestor holding a `.git` or `.hg` marker (a git or Mercurial
-- work tree), else `dir` itself. Cached per directory; a few stats on first use.
local function workspace_root(dir)
    local hit = IdeFollow.workspace_roots[dir]
    if hit == nil then
        local uv = vim.uv or vim.loop
        hit = dir
        local cur = dir
        while cur do
            if uv.fs_stat(cur .. "/.git") or uv.fs_stat(cur .. "/.hg") then
                hit = cur
                break
            end
            local parent = vim.fs.dirname(cur)
            cur = (parent and parent ~= cur) and parent or nil
        end
        IdeFollow.workspace_roots[dir] = hit
    end
    return hit
end

-- Spellings (as launched and symlink-resolved) of the directory this IDE session was started in
-- (`$IDE_INITIAL_ROOT`): the AI Agent pane's working directory, and therefore the workspace every AI
-- conversation of this session records. Returns the spelling set plus a stable cache key.
function IdeFollow.session_roots()
    local root = IdeTree.initial_root or vim.fn.getcwd()
    if type(root) ~= "string" or root == "" then
        return {}, nil
    end
    local cached = IdeFollow.roots_cache
    if not cached or cached.key ~= root then
        local uv = vim.uv or vim.loop
        local set = { [strip_trailing_slash(root)] = true }
        local real = uv.fs_realpath(root)
        if real then
            set[strip_trailing_slash(real)] = true
        end
        cached = { key = root, set = set }
        IdeFollow.roots_cache = cached
    end
    return cached.set, cached.key
end

-- Data directories of `agy`, the default AI CLI: each directory under `~/.gemini/` holding its
-- `cli/history.jsonl` prompt log (re-listed every IDE_FOLLOW_AGY_RESCAN_SECONDS), or only
-- `vim.g.ide_agy_dir` when that is set.
local function agy_dirs()
    local pinned = vim.g.ide_agy_dir
    if type(pinned) == "string" and pinned ~= "" then
        return { vim.fs.normalize(pinned) }
    end
    local gemini = vim.fs.normalize("~/.gemini")
    local now = os.time()
    local cached = IdeFollow.agy_dirs_cache
    if not cached or cached.root ~= gemini or now - cached.at >= IDE_FOLLOW_AGY_RESCAN_SECONDS then
        local uv = vim.uv or vim.loop
        local dirs = {}
        local req = uv.fs_scandir(gemini)
        while req do
            local name = uv.fs_scandir_next(req)
            if not name then
                break
            end
            if uv.fs_stat(gemini .. "/" .. name .. "/cli/history.jsonl") then
                dirs[#dirs + 1] = gemini .. "/" .. name
            end
        end
        table.sort(dirs)
        cached = { root = gemini, at = now, dirs = dirs }
        IdeFollow.agy_dirs_cache = cached
    end
    return cached.dirs
end

local function claude_dir()
    local dir = vim.g.ide_claude_dir
    return vim.fs.normalize((type(dir) == "string" and dir ~= "") and dir or "~/.claude")
end

-- Incrementally indexes an agy prompt log (`<agy dir>/cli/history.jsonl`: one JSON object per prompt
-- carrying `conversationId` + `workspace`) into { [conversation id] = { root, ts } }.
local function agy_conversations(history_path)
    local uv = vim.uv or vim.loop
    local st = uv.fs_stat(history_path)
    local state = IdeFollow.agy_history[history_path]
    if not state or not st or st.size < state.offset then
        state = { offset = 0, partial = "", convs = {} }
        IdeFollow.agy_history[history_path] = state
    end
    if not st or st.size <= state.offset then
        return state.convs
    end
    local chunk = read_bytes(history_path, state.offset, st.size - state.offset)
    if not chunk or chunk == "" then
        return state.convs
    end
    state.offset = state.offset + #chunk
    local text = state.partial .. chunk
    local last_nl = text:match("^.*()\n")
    state.partial = last_nl and text:sub(last_nl + 1) or text
    for line in (last_nl and text:sub(1, last_nl) or ""):gmatch("[^\n]+") do
        if line:find('"conversationId"', 1, true) then
            local ok, entry = pcall(vim.json.decode, line)
            if ok and type(entry) == "table" and type(entry.workspace) == "string"
                and type(entry.conversationId) == "string" and entry.conversationId:match("^[%w_-]+$")
            then
                state.convs[entry.conversationId] = {
                    root = strip_trailing_slash(entry.workspace),
                    ts = tonumber(entry.timestamp) or 0,
                }
            end
        end
    end
    return state.convs
end

-- Brain directories (`<agy dir>/brain/<id>`) of the most recent agy conversations started in one of
-- `roots`, plus the subagents they spawned (recorded as `<id>/.system_generated/subagents/<child>.json`).
function IdeFollow.agy_conversation_dirs(roots)
    local uv = vim.uv or vim.loop
    local owned = {}
    for _, dir in ipairs(agy_dirs()) do
        for id, info in pairs(agy_conversations(dir .. "/cli/history.jsonl")) do
            if roots[info.root] then
                owned[#owned + 1] = { id = id, ts = info.ts, brain = dir .. "/brain/" }
            end
        end
    end
    table.sort(owned, function(a, b)
        return a.ts > b.ts
    end)
    local dirs, seen = {}, {}
    -- Newest conversation first, each with its whole subagent subtree, until the directory budget is spent
    for i = 1, math.min(#owned, IDE_FOLLOW_MAX_CONVERSATIONS) do
        local brain = owned[i].brain
        local queue, head = { { id = owned[i].id, depth = 0 } }, 1
        while queue[head] and #dirs < IDE_FOLLOW_MAX_DIRS do
            local item = queue[head]
            head = head + 1
            local conv_dir = brain .. item.id
            if not seen[conv_dir] then
                seen[conv_dir] = true
                dirs[#dirs + 1] = conv_dir
                local req = item.depth < IDE_FOLLOW_MAX_SUBAGENT_DEPTH
                    and uv.fs_scandir(conv_dir .. "/.system_generated/subagents")
                while req do
                    local name = uv.fs_scandir_next(req)
                    if not name then
                        break
                    end
                    local child = name:match("^([%w_-]+)%.json$")
                    if child then
                        queue[#queue + 1] = { id = child, depth = item.depth + 1 }
                    end
                end
            end
        end
    end
    return dirs
end

-- Claude Code transcripts (`~/.claude/projects/<root with non-alphanumerics as '-'>/<session>.jsonl`) of
-- sessions launched in one of `roots`, most recently active first (at most `limit` when given).
local function claude_session_logs(roots, limit)
    local uv = vim.uv or vim.loop
    local projects = claude_dir() .. "/projects/"
    local logs, tried = {}, {}
    for root in pairs(roots) do
        for _, encoded in ipairs({ (root:gsub("[^%w]", "-")), (root:gsub("/", "-")) }) do
            local req = not tried[encoded] and uv.fs_scandir(projects .. encoded)
            tried[encoded] = true
            while req do
                local name = uv.fs_scandir_next(req)
                if not name then
                    break
                end
                local path = projects .. encoded .. "/" .. name
                local st = name:sub(-6) == ".jsonl" and uv.fs_stat(path)
                if st and st.mtime then
                    logs[#logs + 1] = { path = path, st = st, mtime = st.mtime.sec * 1000000000 + (st.mtime.nsec or 0) }
                end
            end
        end
    end
    table.sort(logs, function(a, b)
        return a.mtime > b.mtime
    end)
    for i = #logs, (limit or #logs) + 1, -1 do
        logs[i] = nil
    end
    return logs
end

-- Claude Code keeps every project's plans in one shared `~/.claude/plans/` directory, so a plan
-- belongs to this session only when a transcript of a Claude session launched in one of `roots`
-- references it.
local function claude_plan_in_session(plan_path, plan_mtime, roots)
    local needle = vim.fn.fnamemodify(plan_path, ":t")
    local plan_sec = math.floor(plan_mtime / 1000000000)
    for _, log in ipairs(claude_session_logs(roots)) do
        -- Only sessions still writing when the plan was saved can own it; search their recent tail
        if log.st.mtime.sec + 60 >= plan_sec then
            local offset = math.max(0, log.st.size - IDE_FOLLOW_TRANSCRIPT_TAIL)
            local tail = read_bytes(log.path, offset, log.st.size - offset)
            if tail and tail:find(needle, 1, true) then
                return true
            end
        end
    end
    return false
end

-- Memoizes a plan's ownership per version (path + mtime); negative verdicts on brand-new plans are
-- re-checked for IDE_FOLLOW_FRESH_SECONDS in case the transcript lags slightly behind the write.
local function claude_plan_owned(plan_path, plan_mtime, roots, roots_key)
    local hit = IdeFollow.plan_verdicts[plan_path]
    if hit and hit.mtime == plan_mtime and hit.roots_key == roots_key
        and (hit.owned or os.time() - math.floor(plan_mtime / 1000000000) > IDE_FOLLOW_FRESH_SECONDS)
    then
        return hit.owned
    end
    local owned = claude_plan_in_session(plan_path, plan_mtime, roots)
    IdeFollow.plan_verdicts[plan_path] = { mtime = plan_mtime, roots_key = roots_key, owned = owned }
    return owned
end

-- Newest `*.md` directly inside `dir` that is newer than `newest_mtime` and passes `accept`.
local function scan_markdown(dir, accept, newest_path, newest_mtime)
    local uv = vim.uv or vim.loop
    local req = uv.fs_scandir(dir)
    while req do
        local name, ftype = uv.fs_scandir_next(req)
        if not name then
            break
        end
        if name:sub(1, 1) ~= "." and name:sub(-3) == ".md" and (not ftype or ftype == "file" or ftype == "link") then
            local full = dir .. "/" .. name
            local mtime = stat_mtime_ns(full)
            if mtime > newest_mtime and (not accept or accept(full, mtime)) then
                newest_path, newest_mtime = full, mtime
            end
        end
    end
    return newest_path, newest_mtime
end

-- Newest plan / walkthrough artifact written by an AI conversation that belongs to this IDE session:
-- agy artifacts in `<agy dir>/brain/<id>/*.md` and Claude Code plans in `~/.claude/plans/`.
-- `conv_dirs` (this tick's `agy_conversation_dirs()`) is resolved when omitted.
function IdeFollow.find_newest_artifact(newest_path, newest_mtime, conv_dirs)
    local roots, roots_key = IdeFollow.session_roots()
    if not roots_key then
        return newest_path, newest_mtime
    end
    for _, conv_dir in ipairs(conv_dirs or IdeFollow.agy_conversation_dirs(roots)) do
        newest_path, newest_mtime = scan_markdown(conv_dir, nil, newest_path, newest_mtime)
    end
    return scan_markdown(claude_dir() .. "/plans", function(path, mtime)
        return claude_plan_owned(path, mtime, roots, roots_key)
    end, newest_path, newest_mtime)
end

-- -----------------------------------------------------------------------------
-- Edit logs: every file edit this session's AI records, and where in the file it landed
-- -----------------------------------------------------------------------------

-- First line of `text` with at least 4 non-blank characters (trimmed) and its 1-based line index:
-- distinctive enough to spot where an edit landed.
local function edit_needle(text)
    local index = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        index = index + 1
        local trimmed = vim.trim((line:gsub("\r$", "")))
        if #trimmed >= 4 then
            return trimmed, index
        end
    end
    return nil, nil
end

local AGY_EDIT_TOOLS = { write_to_file = true, replace_file_content = true, multi_replace_file_content = true }

-- Path + landing hint of one agy file-edit tool call. `encoded`: the arguments come from the compact
-- `transcript.jsonl`, which JSON-encodes every value.
local function agy_edit(call, encoded)
    local args = type(call) == "table" and AGY_EDIT_TOOLS[call.name] and call.args
    if type(args) ~= "table" then
        return nil
    end
    local function arg(key)
        local v = args[key]
        if encoded and type(v) == "string" then
            local ok, decoded = pcall(vim.json.decode, v)
            return ok and decoded or v
        end
        return v
    end
    local path = arg("TargetFile")
    if type(path) ~= "string" or path:sub(1, 1) ~= "/" then
        return nil
    end
    if call.name == "write_to_file" then
        -- Appends land on the new last line; whole-file writes on line 1 (refined to the last `git diff`
        -- hunk when git tracks the file)
        return path, arg("Append") == true and { line = -1 } or { line = 1, whole = true }
    end
    -- replace_file_content: its single chunk; multi_replace_file_content: its topmost chunk (the
    -- only one whose StartLine later chunks cannot shift)
    local chunk = { StartLine = arg("StartLine"), EndLine = arg("EndLine"), ReplacementContent = arg("ReplacementContent") }
    local chunks = arg("ReplacementChunks")
    if type(chunks) == "table" then
        for _, c in ipairs(chunks) do
            local start = type(c) == "table" and tonumber(c.StartLine)
            if start and not (tonumber(chunk.StartLine) and tonumber(chunk.StartLine) <= start) then
                chunk = c
            end
        end
    end
    local first, last = tonumber(chunk.StartLine), tonumber(chunk.EndLine)
    local text = type(chunk.ReplacementContent) == "string" and chunk.ReplacementContent or ""
    local _, newlines = text:gsub("\n", "")
    return path, { line = first, text = text, span = first and ((last or first) - first + newlines + 1) or nil }
end

-- Path + landing hint of one Claude Code `tool_use` block (`Edit`, `MultiEdit`, `Write`, `NotebookEdit`).
local function claude_edit(block)
    local input = type(block) == "table" and block.type == "tool_use" and block.input
    if type(input) ~= "table" then
        return nil
    end
    local path = input.file_path or input.notebook_path
    if type(path) ~= "string" or path:sub(1, 1) ~= "/" then
        return nil
    end
    if block.name == "Write" then
        return path, { line = 1, whole = true }
    elseif block.name == "Edit" then
        return path, { text = input.new_string }
    elseif block.name == "MultiEdit" then
        local first = type(input.edits) == "table" and input.edits[1]
        return path, { text = type(first) == "table" and first.new_string or nil }
    elseif block.name == "NotebookEdit" then
        return path, {}
    end
    return nil
end

-- Directories an edit must fall under to drive this session's Editor: the workspaces of the session
-- root (as launched and symlink-resolved) and of the current `icd` root, minus the AI tools' own state
-- (`~/.gemini`, agy's data directories, `~/.claude`: scratch files, plans and transcripts are not
-- project edits).
local function edit_scope(roots)
    local scope = { include = {}, exclude = { vim.fs.normalize("~/.gemini"), claude_dir() } }
    for _, dir in ipairs(agy_dirs()) do
        scope.exclude[#scope.exclude + 1] = dir
    end
    for root in pairs(roots) do
        scope.include[workspace_root(root)] = true
    end
    if type(IdeTree.root) == "string" and IdeTree.root ~= "" then
        scope.include[workspace_root(strip_trailing_slash(IdeTree.root))] = true
    end
    return scope
end

local function under(path, dir)
    return dir == "/" or path:sub(1, #dir + 1) == dir .. "/"
end

local function in_scope(path, scope)
    for _, dir in ipairs(scope.exclude) do
        if under(path, dir) then
            return false
        end
    end
    for dir in pairs(scope.include) do
        if under(path, dir) then
            return true
        end
    end
    return false
end

-- Remembers the latest in-scope edit per file, keeping the IDE_FOLLOW_MAX_EDITS most recent files.
local function note_edit(scope, path, hint)
    if not path or not in_scope(path, scope) then
        return
    end
    IdeFollow.edit_seq = IdeFollow.edit_seq + 1
    hint.seq = IdeFollow.edit_seq
    IdeFollow.edits[path] = hint
    local count, oldest = 0, nil
    for p, h in pairs(IdeFollow.edits) do
        count = count + 1
        if not oldest or h.seq < IdeFollow.edits[oldest].seq then
            oldest = p
        end
    end
    if count > IDE_FOLLOW_MAX_EDITS then
        IdeFollow.edits[oldest] = nil
    end
end

-- Records the file edits in complete, newly appended log lines (a substring check gates JSON decoding).
local function record_edits(text, kind, encoded, scope)
    local marker = kind == "agy" and '"TargetFile"' or '"tool_use"'
    for line in text:gmatch("[^\n]+") do
        if line:find(marker, 1, true) then
            local ok, entry = pcall(vim.json.decode, line)
            if ok and type(entry) == "table" then
                if kind == "agy" then
                    for _, call in ipairs(type(entry.tool_calls) == "table" and entry.tool_calls or {}) do
                        note_edit(scope, agy_edit(call, encoded))
                    end
                elseif type(entry.message) == "table" and type(entry.message.content) == "table" then
                    for _, block in ipairs(entry.message.content) do
                        note_edit(scope, claude_edit(block))
                    end
                end
            end
        end
    end
end

-- Parses what the log at `path` gained since the last tick. A log seen for the first time is read
-- from its last IDE_FOLLOW_EDIT_LOG_TAIL bytes; `prime` skips to its end instead (activity from
-- before the Editor started is not followed).
local function tail_edit_log(path, size, kind, encoded, scope, prime)
    local state = IdeFollow.edit_logs[path]
    if prime or not state or size < state.offset then
        local start = prime and size or math.max(0, size - IDE_FOLLOW_EDIT_LOG_TAIL)
        -- Starting mid-line: the first (partial) line is skipped
        state = { offset = start, partial = "", skip = start > 0 and read_bytes(path, start - 1, 1) ~= "\n" }
        IdeFollow.edit_logs[path] = state
    end
    if size <= state.offset then
        return
    end
    local chunk = read_bytes(path, state.offset, size - state.offset)
    if not chunk or chunk == "" then
        return
    end
    state.offset = state.offset + #chunk
    local text = state.partial .. chunk
    local last_nl = text:match("^.*()\n")
    state.partial = last_nl and text:sub(last_nl + 1) or text
    if not last_nl then
        return
    end
    text = text:sub(1, last_nl)
    if state.skip then
        text = text:gsub("^[^\n]*\n", "", 1)
        state.skip = false
    end
    record_edits(text, kind, encoded, scope)
end

-- Tails this session's edit logs: the agy transcripts of its conversations and their subagents
-- (`<brain>/<id>/.system_generated/logs/transcript_full.jsonl`) and its most recently active Claude
-- Code transcripts, recording the in-scope file edits they gained since the last tick.
function IdeFollow.read_edit_logs(roots, conv_dirs, prime)
    local uv = vim.uv or vim.loop
    local scope = edit_scope(roots)
    for _, dir in ipairs(conv_dirs) do
        local logs = dir .. "/.system_generated/logs/"
        local path, encoded = logs .. "transcript_full.jsonl", false
        local st = uv.fs_stat(path)
        if not st then
            path, encoded = logs .. "transcript.jsonl", true
            st = uv.fs_stat(path)
        end
        if st then
            tail_edit_log(path, st.size, "agy", encoded, scope, prime)
        end
    end
    for _, log in ipairs(claude_session_logs(roots, IDE_FOLLOW_MAX_CLAUDE_LOGS)) do
        tail_edit_log(log.path, log.st.size, "claude", false, scope, prime)
    end
end

-- Newest file among the logged edits. An edit waiting on a permission prompt stays a candidate until
-- it lands (or IDE_FOLLOW_MAX_EDITS newer edits evict it).
local function newest_logged_edit(newest_path, newest_mtime)
    for path in pairs(IdeFollow.edits) do
        local mtime = stat_mtime_ns(path)
        if mtime > newest_mtime then
            newest_path, newest_mtime = path, mtime
        end
    end
    return newest_path, newest_mtime
end

-- Line of the current buffer a logged edit landed on: the first distinctive line of its replacement
-- block where that block now sits (else where that line alone first appears), searched from the tool
-- call's StartLine through the replaced range (the whole buffer for Claude Code edits, which carry no
-- line numbers); else StartLine itself.
local function edit_landing_line(hint)
    local total = vim.api.nvim_buf_line_count(0)
    if hint.line == -1 then
        return total
    end
    local first = hint.line and math.max(1, math.min(hint.line, total)) or 1
    local last = hint.line and math.min(total, first + (hint.span or 0) + 2) or total
    local text = type(hint.text) == "string" and (hint.text:gsub("\r", ""):gsub("\n+$", "")) or ""
    if text ~= "" then
        local lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)
        local needle, lead = edit_needle(text)
        local joined = table.concat(lines, "\n")
        local pos = joined:find(text, 1, true)
        if pos then
            local _, before = joined:sub(1, pos - 1):gsub("\n", "")
            return first + before + (lead or 1) - 1
        end
        for i, line in ipairs(needle and lines or {}) do
            if line:find(needle, 1, true) then
                return first + i - 1
            end
        end
    end
    return hint.line and first or nil
end

local function center_line(line)
    local total = vim.api.nvim_buf_line_count(0)
    pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, math.min(line, total)), 0 })
    pcall(vim.cmd, "normal! zz")
end

-- -----------------------------------------------------------------------------
-- Background `git status`: catches edits made through shell commands. Never awaited by the tick:
-- one scan in flight at a time, each starting no sooner than one tick, or (1 + IDE_FOLLOW_VCS_BACKOFF)
-- x the previous scan's duration, after the previous one started.
-- -----------------------------------------------------------------------------

-- Dirty paths of `git status --porcelain -z` output (renames / copies list the new path first).
local function porcelain_paths(out, toplevel)
    local paths = {}
    local fields = vim.split(out or "", "\0", { plain = true })
    local i = 1
    while i <= #fields do
        local field = fields[i]
        if #field > 3 then
            paths[#paths + 1] = toplevel .. "/" .. field:sub(4)
            if field:sub(1, 2):find("[RC]") then
                i = i + 1
            end
        end
        i = i + 1
    end
    return paths
end

-- The IDE_FOLLOW_MAX_VCS_PATHS most recently modified existing files of `paths`.
local function freshest(paths)
    local stamped = {}
    for _, path in ipairs(paths) do
        local mtime = stat_mtime_ns(path)
        if mtime > 0 then
            stamped[#stamped + 1] = { path = path, mtime = mtime }
        end
    end
    table.sort(stamped, function(a, b)
        return a.mtime > b.mtime
    end)
    local out = {}
    for i = 1, math.min(#stamped, IDE_FOLLOW_MAX_VCS_PATHS) do
        out[i] = stamped[i].path
    end
    return out
end

-- Starts the next background scan of `root` when due (`force`: now, unless one is in flight). The
-- first run resolves the git toplevel; porcelain paths are relative to it even after `icd`.
function IdeFollow.refresh_vcs(root, force)
    local uv = vim.uv or vim.loop
    local vcs = IdeFollow.vcs
    if vcs.root ~= root then
        vcs.gen = vcs.gen + 1
        vcs.root, vcs.toplevel, vcs.paths, vcs.inflight, vcs.next_ns = root, nil, {}, false, 0
    end
    if vcs.inflight or vcs.toplevel == false or (not force and uv.hrtime() < vcs.next_ns) then
        return
    end
    local gen, started = vcs.gen, uv.hrtime()
    local cmd = vcs.toplevel and { "git", "-C", vcs.toplevel, "--no-optional-locks", "status", "--porcelain", "-z", "-uall" }
        or { "git", "-C", root, "rev-parse", "--show-toplevel" }
    vcs.inflight = true
    local ok = pcall(vim.system, cmd, {}, vim.schedule_wrap(function(res)
        if gen ~= vcs.gen then
            return -- the root changed (`icd`) while git was running
        end
        vcs.inflight = false
        if not vcs.toplevel then
            local top = res.code == 0 and vim.trim(res.stdout or "") or ""
            vcs.toplevel = top ~= "" and top or false
            if vcs.toplevel then
                IdeFollow.refresh_vcs(root, true) -- straight on to the first status scan
            end
            return
        end
        if res.code == 0 then
            vcs.paths = freshest(porcelain_paths(res.stdout, vcs.toplevel))
        end
        vcs.scans = vcs.scans + 1
        local took = uv.hrtime() - started
        vcs.next_ns = started + math.max((IDE_FOLLOW_TICK_MS - 250) * 1000000, (1 + IDE_FOLLOW_VCS_BACKOFF) * took)
    end))
    if not ok then
        vcs.inflight, vcs.toplevel = false, false -- git is not installed
    end
end

-- Last hunk start (`@@ -a,b +c,d @@`) of `git diff -U0` output.
local function last_hunk_line(diff)
    local last = nil
    for n in (diff or ""):gmatch("\n@@ %-[0-9,]+ %+([0-9]+)") do
        n = tonumber(n)
        if n and n > 0 then
            last = n
        end
    end
    return last
end

-- `path` as it sits under the git work tree `toplevel` (which `rev-parse` reports symlink-resolved),
-- or nil when the file is outside it.
local function repo_path(path, toplevel)
    if under(path, toplevel) then
        return path
    end
    local real = (vim.uv or vim.loop).fs_realpath(path)
    return real and under(real, toplevel) and real or nil
end

-- Centers the last `git diff` hunk of `path` once git answers, unless you have moved on since.
local function jump_to_git_hunk(path, toplevel)
    local jump, buf, cursor = IdeFollow.jumps, vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)
    pcall(vim.system, { "git", "-C", toplevel, "--no-optional-locks", "diff", "-U0", "--", path }, {},
        vim.schedule_wrap(function(res)
            local line = res.code == 0 and last_hunk_line(res.stdout)
            if line and jump == IdeFollow.jumps and vim.api.nvim_get_mode().mode == "n"
                and vim.api.nvim_get_current_buf() == buf and vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor)
            then
                center_line(line)
            end
        end))
end

-- Newest follow candidate across this session's logged AI edits, the freshest dirty files of the last
-- background `git status`, and this session's plan / walkthrough artifacts (stats and small reads only).
function IdeFollow.find_newest_modified(root)
    root = (root and root ~= "") and root or IdeTree.root or vim.fn.getcwd()
    local roots, roots_key = IdeFollow.session_roots()
    local conv_dirs = roots_key and IdeFollow.agy_conversation_dirs(roots) or {}
    if roots_key then
        IdeFollow.read_edit_logs(roots, conv_dirs)
    end
    local newest_path, newest_mtime = newest_logged_edit(nil, 0)
    if IdeFollow.vcs.root == root then
        for _, path in ipairs(IdeFollow.vcs.paths) do
            local mtime = stat_mtime_ns(path)
            if mtime > newest_mtime then
                newest_path, newest_mtime = path, mtime
            end
        end
    end
    return IdeFollow.find_newest_artifact(newest_path, newest_mtime, conv_dirs)
end

function IdeFollow.sync(force)
    if vim.api.nvim_get_mode().mode ~= "n" or vim.fn.getcmdwintype() ~= "" then
        return false
    end
    pcall(vim.cmd, "silent! checktime")
    if not IdeFollow.enabled and not force then
        return false
    end
    if vim.bo.modified then
        return false
    end
    local root = IdeTree.root or vim.fn.getcwd()
    IdeFollow.refresh_vcs(root, force) -- background: its dirty files feed a later tick
    local newest_path, newest_mtime = IdeFollow.find_newest_modified(root)
    if not newest_path or newest_mtime == 0 then
        return false
    end
    -- Only strictly newer writes move the Editor, so files leaving the candidate set (reverted
    -- edits, a finished conversation's artifacts) never yank it back to an older file
    if not force and newest_mtime <= IdeFollow.last_mtime_ns then
        return false
    end
    IdeFollow.last_mtime_ns = newest_mtime
    IdeFollow.last_file = newest_path
    IdeFollow.jumps = IdeFollow.jumps + 1

    if IdeTree.buf and vim.api.nvim_buf_is_valid(IdeTree.buf) and vim.fn.bufwinid(IdeTree.buf) ~= -1 then
        IdeTree.invalidate_cache()
        IdeTree.render()
    end

    IdeTree.focus_code_win()
    local cur_name = vim.api.nvim_buf_get_name(0)
    if cur_name ~= newest_path then
        vim.cmd("silent! edit " .. vim.fn.fnameescape(newest_path))
    else
        pcall(vim.cmd, "silent! checktime")
    end

    -- Land on the changed line: the logged edit's own line; files the AI changed only through the
    -- shell (or rewrote whole) move on to their last `git diff` hunk once git answers
    local hint = IdeFollow.edits[newest_path]
    local line = hint and edit_landing_line(hint)
    if line then
        center_line(line)
    end
    local toplevel = IdeFollow.vcs.toplevel
    local git_path = (not line or hint.whole) and toplevel and repo_path(newest_path, toplevel)
    if git_path then
        jump_to_git_hunk(git_path, toplevel)
    end
    return true
end

function IdeFollow.toggle()
    IdeFollow.enabled = not IdeFollow.enabled
    local state = IdeFollow.enabled and "ON (auto-following AI edits)" or "OFF (manual mode)"
    vim.api.nvim_echo({ { "AI Live-Follow Mode: " .. state, "MoreMsg" } }, false, {})
end

function IdeFollow.start_timer()
    if IdeFollow.timer then
        return
    end
    -- Only activity from now on is followed: the baseline is the current time, and this session's
    -- existing edit logs are skipped to their end (deferred out of startup: indexing the prompt
    -- history can take tens of milliseconds)
    IdeFollow.last_mtime_ns = math.max(IdeFollow.last_mtime_ns, now_ns())
    vim.schedule(function()
        pcall(function()
            local roots, roots_key = IdeFollow.session_roots()
            if roots_key then
                IdeFollow.read_edit_logs(roots, IdeFollow.agy_conversation_dirs(roots), true)
            end
        end)
    end)
    local uv = vim.uv or vim.loop
    if uv and uv.new_timer then
        IdeFollow.timer = uv.new_timer()
        if IdeFollow.timer then
            IdeFollow.timer:start(IDE_FOLLOW_TICK_MS, IDE_FOLLOW_TICK_MS, vim.schedule_wrap(function()
                if IdeFollow.enabled then
                    pcall(IdeFollow.sync, false)
                end
            end))
        end
    end
end

vim.api.nvim_create_user_command("IdeFollowToggle", function()
    IdeFollow.toggle()
end, { desc = "Toggle AI Live-Follow Mode" })

map("n", "<leader>af", function()
    IdeFollow.toggle()
end, { desc = "Toggle AI Live-Follow Mode" })

-- Your own saves are not AI activity: advance the follow baseline on every write so the Editor
-- never snaps the cursor back to the last diff hunk of a file you just saved.
vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("SolarizedIdeFollow", { clear = true }),
    callback = function(args)
        local path = vim.api.nvim_buf_get_name(args.buf)
        local mtime = stat_mtime_ns(path)
        if mtime > IdeFollow.last_mtime_ns then
            IdeFollow.last_mtime_ns = mtime
            IdeFollow.last_file = path
        end
    end,
})

-- Workspace Role Jump & Toggle Keybindings (Editor <-> AI Agent <-> Shell)
map("n", "<leader>a", function()
    if vim.env.TMUX then
        ide_job("--toggle")
    end
end, { desc = "Toggle Focus: Editor <-> AI Agent" })
map({ "n", "i", "t" }, "<M-a>", function()
    if vim.env.TMUX then
        ide_job("--toggle")
    end
end, { desc = "Toggle Focus: Editor <-> AI Agent" })
map({ "n", "i", "t" }, "<M-e>", function()
    if vim.env.TMUX then
        ide_job("--show-editor")
    end
end, { desc = "Focus/Zoom Editor Pane" })
map({ "n", "i", "t" }, "<M-t>", function()
    if vim.env.TMUX then
        ide_job("--show-term")
    end
end, { desc = "Toggle Focus: Shell <-> Editor Pane" })

-- One-Command Quit Everything (:Q, :Quit, :qa, :wqa, Space+q, Alt+q, qide)
-- While keeping `:q` and `:wq` scoped strictly to closing the active buffer/split in the Editor pane.
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
                vim.api.nvim_echo({ { "E37: No write since last change in " .. modified .. " buffer(s) (save with :wqa or press Alt+Shift+Q / :Q! to force)", "ErrorMsg" } }, true, {})
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

-- Smart buffer/split close for `:q`, `:q!`, `:wq`, `:wq!` inside the IDE Editor pane:
-- - If the current window is a sidebar (`ide_tree` or `netrw`), closes that sidebar window.
-- - If multiple non-sidebar splits exist, closes the active split (`:quit`).
-- - If this is the last non-sidebar code window (even when `ide_tree` is open beside it),
--   replaces the buffer in-place and runs `:bdelete` so the code split is never destroyed
--   and `ide_tree` never stretches across 100% of the Editor pane.
local function ide_close_buffer_or_split(bang, write)
    local cur_ft = vim.bo.filetype
    if cur_ft == "ide_tree" or cur_ft == "netrw" then
        if vim.fn.winnr("$") > 1 then
            pcall(vim.cmd, "close")
        end
        return
    end

    if write then
        local ok, err = pcall(function()
            vim.cmd(bang and "write!" or "write")
        end)
        if not ok then
            vim.api.nvim_echo({ { tostring(err), "ErrorMsg" } }, true, {})
            return
        end
    end

    local non_sidebar_wins = 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local cfg = vim.api.nvim_win_get_config(win)
        if not cfg.relative or cfg.relative == "" then
            local buf = vim.api.nvim_win_get_buf(win)
            local ft = vim.bo[buf].filetype
            if ft ~= "ide_tree" and ft ~= "netrw" then
                non_sidebar_wins = non_sidebar_wins + 1
            end
        end
    end

    if non_sidebar_wins > 1 then
        pcall(function()
            vim.cmd(bang and "quit!" or "quit")
        end)
        return
    end

    local cur_buf = vim.api.nvim_get_current_buf()
    if vim.bo[cur_buf].modified and not bang then
        local lines = vim.api.nvim_buf_get_lines(cur_buf, 0, -1, false)
        local is_blank_unnamed = (vim.api.nvim_buf_get_name(cur_buf) == "" and table.concat(lines, ""):gsub("%s+", "") == "")
        if not is_blank_unnamed then
            vim.api.nvim_echo({ { "E37: No write since last change (add ! to override)", "ErrorMsg" } }, true, {})
            return
        end
        bang = true
    end

    local listed = vim.fn.getbufinfo({ buflisted = 1 })
    local next_buf = nil
    for _, b in ipairs(listed) do
        if b.bufnr ~= cur_buf then
            next_buf = b.bufnr
            break
        end
    end

    if next_buf and vim.api.nvim_buf_is_valid(next_buf) then
        vim.cmd("buffer " .. next_buf)
    else
        vim.cmd("enew")
    end
    if vim.api.nvim_buf_is_valid(cur_buf) then
        pcall(function()
            vim.cmd((bang and "bdelete! " or "bdelete ") .. cur_buf)
        end)
    end
end

vim.api.nvim_create_user_command("IdeClose", function(opts)
    ide_close_buffer_or_split(opts.bang, false)
end, { bang = true, desc = "Close current buffer or split without exiting IDE Editor" })

vim.api.nvim_create_user_command("IdeWriteClose", function(opts)
    ide_close_buffer_or_split(opts.bang, true)
end, { bang = true, desc = "Write and close current buffer or split without exiting IDE Editor" })

map("n", "<leader>q", function() quit_ide_or_nvim(false) end, { desc = "Quit Entire IDE Workspace" })
map({ "n", "i", "v", "t" }, "<M-q>", function() quit_ide_or_nvim(false) end, { desc = "Quit Entire IDE Workspace" })
map({ "n", "i", "v", "t" }, "<M-Q>", function() quit_ide_or_nvim(true) end, { desc = "Force-Quit Entire IDE Workspace" })
vim.api.nvim_create_user_command("Q", function(opts) quit_ide_or_nvim(opts.bang) end, { bang = true, desc = "Quit Entire IDE Workspace" })
vim.api.nvim_create_user_command("Quit", function(opts) quit_ide_or_nvim(opts.bang) end, { bang = true, desc = "Quit Entire IDE Workspace" })

vim.api.nvim_create_user_command("IdeCd", function(opts)
    local target = vim.trim(opts.args or "")
    if target == "" then
        local buf_dir = vim.fn.expand("%:p:h")
        if buf_dir ~= "" and vim.fn.isdirectory(buf_dir) == 1 then
            target = buf_dir
        else
            target = vim.fn.getcwd()
        end
    elseif target ~= "~" and target ~= "--reset" then
        target = vim.fn.fnamemodify(vim.fn.expand(target), ":p"):gsub("/+$", "")
    end
    IdeTree.dive(target)
end, { nargs = "?", complete = "dir", desc = "Dive IDE Workspace (Tree, Editor, Shell) to directory" })

map("n", "<leader>cd", "<cmd>IdeCd<CR>", { desc = "Dive IDE Workspace to Current Buffer Directory" })

local ide_layout_group = vim.api.nvim_create_augroup("SolarizedIdeLayout", { clear = true })

-- In the primary IDE Editor (`--listen $NVIM_IDE_SOCKET`), remap command-line `:q` / `:wq`
-- to close the current buffer/split while keeping the Editor pane open, and `:qa` / `:wqa` to quit the IDE.
vim.api.nvim_create_autocmd("VimEnter", {
    group = ide_layout_group,
    callback = function()
        if vim.env.NVIM_IDE_SOCKET
            and vim.env.NVIM_IDE_SOCKET ~= ""
            and vim.v.servername == vim.env.NVIM_IDE_SOCKET
        then
            vim.cmd([[
                cnoreabbrev <expr> q (getcmdtype() ==# ':' && getcmdline() ==# 'q') ? 'IdeClose' : 'q'
                cnoreabbrev <expr> q! (getcmdtype() ==# ':' && getcmdline() ==# 'q!') ? 'IdeClose!' : 'q!'
                cnoreabbrev <expr> wq (getcmdtype() ==# ':' && getcmdline() ==# 'wq') ? 'IdeWriteClose' : 'wq'
                cnoreabbrev <expr> wq! (getcmdtype() ==# ':' && getcmdline() ==# 'wq!') ? 'IdeWriteClose!' : 'wq!'
                cnoreabbrev <expr> qa (getcmdtype() ==# ':' && getcmdline() ==# 'qa') ? 'Q' : 'qa'
                cnoreabbrev <expr> qa! (getcmdtype() ==# ':' && getcmdline() ==# 'qa!') ? 'Q!' : 'qa!'
                cnoreabbrev <expr> wqa (getcmdtype() ==# ':' && getcmdline() ==# 'wqa') ? 'wall \| Q' : 'wqa'
                cnoreabbrev <expr> wqa! (getcmdtype() ==# ':' && getcmdline() ==# 'wqa!') ? 'wall! \| Q!' : 'wqa!'
            ]])
            IdeFollow.start_timer()
        end
    end,
})

vim.api.nvim_create_autocmd({ "FocusGained", "WinEnter" }, {
    group = ide_layout_group,
    callback = function()
        if vim.bo.filetype == "ide_tree" then
            IdeTree.focus_gained_ns = (vim.uv or vim.loop).hrtime()
        end
    end,
})

vim.api.nvim_create_autocmd("VimEnter", {
    group = ide_layout_group,
    callback = function()
        if vim.env.NVIM_IDE_LAYOUT == "1" and #vim.api.nvim_list_uis() > 0 and (vim.fn.argc() == 0 or vim.fn.isdirectory(vim.fn.argv(0)) == 0) then
            IdeTree.toggle_split()
            vim.cmd("wincmd p")
        end
    end,
})

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

-- If init.lua is re-sourced inside a running session (e.g. `:source $MYVIMRC` or hot-reload),
-- all core options, keymaps, commands, and IdeTree have already been refreshed above;
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
            vim.keymap.set("n", "<leader>E", function()
                local mf = require("mini.files")
                if not mf.close() then
                    local buf_name = vim.api.nvim_buf_get_name(0)
                    if buf_name ~= "" and (vim.uv or vim.loop).fs_stat(buf_name) then
                        mf.open(buf_name, false)
                    else
                        mf.open((vim.uv or vim.loop).cwd(), true)
                    end
                end
            end, { desc = "Toggle Mini.files Navigator" })
        end,
    },
})
