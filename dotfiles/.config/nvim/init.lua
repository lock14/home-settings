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

-- Seamless Window & Role-Aware 3-Pane Tmux Navigation (Ctrl + hjkl & Alt + hjkl)
-- Guarded against floating modals (Telescope/LSP/MiniFiles) and zoomed tmux panes.
-- From Left Directory Tree (NVIM_IDE_TREE=1), Right/Up targets Top-Right Main ({top-right})
-- and Down targets Bottom-Right Shell ({bottom-right}).
local function smart_tmux_nav(dir, tmux_dir)
    return function()
        local mode = vim.api.nvim_get_mode().mode
        if mode == "t" or mode == "i" then
            vim.cmd("stopinsert")
        end
        local cur_win = vim.api.nvim_get_current_win()
        local win_cfg = vim.api.nvim_win_get_config(cur_win)
        if win_cfg.relative and win_cfg.relative ~= "" then
            return
        end
        vim.cmd("wincmd " .. dir)
        if vim.api.nvim_get_current_win() == cur_win and vim.env.TMUX then
            local target_cmd = "select-pane -" .. tmux_dir
            if vim.env.NVIM_IDE_TREE == "1" then
                if tmux_dir == "R" or tmux_dir == "U" then
                    target_cmd = "select-pane -t '{top-right}'"
                elseif tmux_dir == "D" then
                    target_cmd = "select-pane -t '{bottom-right}'"
                end
            end
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

map({ "n", "t" }, "<C-h>", smart_tmux_nav("h", "L"), { desc = "Move to left split or tmux pane" })
map({ "n", "t" }, "<C-j>", smart_tmux_nav("j", "D"), { desc = "Move to lower split or tmux pane" })
map({ "n", "t" }, "<C-k>", smart_tmux_nav("k", "U"), { desc = "Move to upper split or tmux pane" })
map({ "n", "t" }, "<C-l>", smart_tmux_nav("l", "R"), { desc = "Move to right split or tmux pane" })

map({ "n", "i", "v", "t" }, "<M-h>", smart_tmux_nav("h", "L"), { desc = "Move to left split or tmux pane" })
map({ "n", "i", "v", "t" }, "<M-j>", smart_tmux_nav("j", "D"), { desc = "Move to lower split or tmux pane" })
map({ "n", "i", "v", "t" }, "<M-k>", smart_tmux_nav("k", "U"), { desc = "Move to upper split or tmux pane" })
map({ "n", "i", "v", "t" }, "<M-l>", smart_tmux_nav("l", "R"), { desc = "Move to right split or tmux pane" })

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

-- =============================================================================
-- Native Solarized IDE Directory Tree Explorer (`SolarizedIdeTree`)
-- Zero-dependency, instant expand/collapse (`Enter`, `o`, `l`, `h`, Mouse),
-- RPC file open (`Enter`) & preview (`Tab` / `p`) into Top-Right Main Editor
-- =============================================================================
if vim.env.NVIM_IDE_TREE == "1" then
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
end

local IdeTree = {
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
        vim.fn.jobstart({ vim.fn.expand("$HOME/.local/bin/ide"), "--cd", actual_dir }, { detach = true })
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

function IdeTree.dispatch_file(filepath, focus_editor)
    if vim.env.NVIM_IDE_TREE == "1" and vim.env.TMUX then
        local flag = focus_editor and "--open" or "--preview"
        vim.fn.jobstart({ vim.fn.expand("$HOME/.local/bin/ide"), flag, filepath }, { detach = true })
    else
        local cur_win = vim.api.nvim_get_current_win()
        vim.cmd("wincmd p")
        if vim.api.nvim_get_current_win() == cur_win then
            vim.cmd("rightbelow vsplit")
        end
        vim.cmd("edit " .. vim.fn.fnameescape(filepath))
        if not focus_editor and vim.api.nvim_win_is_valid(cur_win) then
            vim.api.nvim_set_current_win(cur_win)
        end
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
    vim.opt_local.statusline = "  Directory "
    IdeTree.render()
end

function IdeTree.toggle_split()
    if IdeTree.buf and vim.api.nvim_buf_is_valid(IdeTree.buf) then
        local win = vim.fn.bufwinid(IdeTree.buf)
        if win ~= -1 then
            vim.api.nvim_win_close(win, true)
            return
        end
    end
    vim.cmd("topleft 28vnew")
    IdeTree.open_in_current_win()
end

-- Project Tree Sidebar Toggle: focuses the dedicated Left Directory Pane in Tmux IDE,
-- or toggles the built-in SolarizedIdeTree split when running standalone outside `ide`.
map("n", "<leader>e", function()
    if vim.env.TMUX then
        local tree_pane = vim.fn.system("tmux show-options -qv @ide_tree_pane 2>/dev/null"):gsub("%s+$", "")
        if tree_pane == "" then
            tree_pane = vim.fn.system("tmux show-environment IDE_TREE_PANE 2>/dev/null"):gsub("^IDE_TREE_PANE=", ""):gsub("%s+$", "")
        end
        local ed_pane = vim.fn.system("tmux show-options -qv @ide_editor_pane 2>/dev/null"):gsub("%s+$", "")
        if ed_pane == "" then
            ed_pane = vim.fn.system("tmux show-environment NVIM_IDE_PANE 2>/dev/null"):gsub("^NVIM_IDE_PANE=", ""):gsub("%s+$", "")
        end
        if tree_pane ~= "" and not tree_pane:match("^-") then
            if vim.env.NVIM_IDE_TREE == "1" and ed_pane ~= "" and not ed_pane:match("^-") then
                vim.fn.system({ "tmux", "select-pane", "-t", ed_pane })
            else
                vim.fn.system({ "tmux", "select-pane", "-t", tree_pane })
            end
            return
        end
    end
    IdeTree.toggle_split()
end, { desc = "Focus/Toggle Project Tree Sidebar" })

-- In-Place Main Pane Toggle (Editor <-> AI Agent) via Tmux IDE
map("n", "<leader>a", function()
    if vim.env.TMUX then
        vim.fn.jobstart({ vim.fn.expand("$HOME/.local/bin/ide"), "--toggle" }, { detach = true })
    end
end, { desc = "Toggle Main Pane: Editor <-> AI Agent" })
map({ "n", "i", "t" }, "<M-a>", function()
    if vim.env.TMUX then
        vim.fn.jobstart({ vim.fn.expand("$HOME/.local/bin/ide"), "--toggle" }, { detach = true })
    end
end, { desc = "Toggle Main Pane: Editor <-> AI Agent" })

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
        local cmd = { vim.fn.expand("$HOME/.local/bin/ide"), "--quit" }
        if force then
            table.insert(cmd, "--force")
        end
        vim.fn.jobstart(cmd, { detach = true })
    else
        vim.cmd(force and "qa!" or "confirm qa")
    end
end

-- Smart buffer/split close for `:q`, `:q!`, `:wq`, `:wq!` inside the IDE Editor pane:
-- Closes the active split if multiple splits exist, or closes the current buffer (`:bdelete`)
-- while keeping the Neovim Editor pane alive and listening on $NVIM_IDE_SOCKET.
local function ide_close_buffer_or_split(bang, write)
    if write then
        local ok, err = pcall(function()
            vim.cmd(bang and "write!" or "write")
        end)
        if not ok then
            vim.api.nvim_echo({ { tostring(err), "ErrorMsg" } }, true, {})
            return
        end
    end

    if vim.fn.winnr("$") > 1 then
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
end, { nargs = "?", complete = "dir", desc = "Dive IDE Workspace (Tree, Editor, Shell, AI) to directory" })

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
            and vim.env.NVIM_IDE_TREE ~= "1"
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

if vim.env.NVIM_IDE_TREE == "1" then
    vim.api.nvim_create_autocmd("VimEnter", {
        group = ide_layout_group,
        callback = function()
            IdeTree.root = vim.fn.getcwd()
            IdeTree.open_in_current_win()
        end,
    })
else
    vim.api.nvim_create_autocmd("VimEnter", {
        group = ide_layout_group,
        callback = function()
            if vim.env.NVIM_IDE_LAYOUT == "1" and #vim.api.nvim_list_uis() > 0 and (vim.fn.argc() == 0 or vim.fn.isdirectory(vim.fn.argv(0)) == 0) then
                IdeTree.toggle_split()
                vim.cmd("wincmd p")
            end
        end,
    })
end

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
                    Include = { fg = colors.orange },
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
                    diffFile = { fg = colors.orange },
                    diffNewFile = { fg = colors.yellow },
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
                    shCommandSub = { fg = colors.orange },
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
                    jpropertiesSpecialChar = { fg = colors.violet },
                    jpropertiesComment = { fg = colors.base01, italic = false },

                    -- Language-Specific Tree-sitter Semantic Specializations & Contextual Invariance
                    -- Java (Principle 7 Operational Role Invariance & Module Directives)
                    ["@keyword.directive.java"] = { fg = colors.base0 },
                    ["@function.builtin.java"] = { fg = colors.green },
                    ["@variable.builtin.java"] = { fg = colors.green },
                    ["@module.java"] = { fg = colors.base0 },

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
                    ensure_installed = (vim.env.NVIM_IDE_TREE ~= "1") and parsers or {},
                    auto_install = (vim.env.NVIM_IDE_TREE ~= "1"),
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
                if vim.env.NVIM_IDE_TREE ~= "1" then
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
            if vim.env.NVIM_IDE_TREE == "1" then
                return
            end
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
