-- General editor keymaps, Smart-Home, 4-layer split/Tmux navigation, link clicks, and mini.files toggles.

local M = {}

local function smart_home_expr()
    local line = vim.api.nvim_get_current_line()
    local col = vim.fn.col(".")
    local first_nb = line:find("[^ \t]")
    local target = first_nb and ((col == first_nb) and "0" or "^") or ((#line == 0 or col == #line) and "0" or "^")
    local m = vim.fn.mode()
    if m == "s" or m == "S" or m == "\19" then
        return (target == "0") and "<C-o>0" or "<C-o>^"
    end
    return target
end

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

function M.setup(opts)
    local follow_editor_link = opts and opts.follow_editor_link or nil
    local recover_stale_cwd = opts and opts.recover_stale_cwd or nil
    local map = vim.keymap.set

    -- Clipboard yanks and pastes
    map("x", "<LeftRelease>", '<LeftRelease>"+ygv', { silent = true, desc = "Auto-copy mouse selection to clipboard" })
    map("x", "<C-c>", '"+y', { silent = true, desc = "Copy visual selection to system clipboard" })
    map("x", "<M-c>", '"+y', { silent = true, desc = "Copy visual selection to system clipboard" })
    map({ "n", "i", "v", "t" }, "<M-v>", function()
        local text = vim.fn.getreg("+")
        if type(text) == "string" and text ~= "" then
            vim.api.nvim_paste(text, true, -1)
        end
    end, { silent = true, desc = "Paste from system clipboard" })

    -- Core buffer actions
    map("n", "<leader>h", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
    map("n", "<leader>w", "<cmd>w<CR>", { desc = "Save file" })

    -- Smart Home: jump to first non-blank character of line, or toggle to column 1 if already there
    map({ "n", "v", "o" }, "<Home>", smart_home_expr, {
        expr = true,
        replace_keycodes = true,
        silent = true,
        desc = "Smart Home: toggle first non-blank character and column 1",
    })
    map("i", "<Home>", function()
        local line = vim.api.nvim_get_current_line()
        local pos = vim.api.nvim_win_get_cursor(0)
        local row, col = pos[1], pos[2]
        local first_nb = line:find("[^ \t]")
        local target = 0
        if first_nb then
            local nb0 = first_nb - 1
            target = (col == nb0) and 0 or nb0
        else
            target = (col == #line) and 0 or #line
        end
        vim.api.nvim_win_set_cursor(0, { row, target })
    end, { silent = true, desc = "Smart Home: toggle first non-blank character and column 1" })

    -- Split and Tmux spatial navigation
    map("n", "<C-h>", internal_split_nav("h"), { desc = "Move to left split" })
    map("n", "<C-j>", internal_split_nav("j"), { desc = "Move to lower split" })
    map("n", "<C-k>", internal_split_nav("k"), { desc = "Move to upper split" })
    map("n", "<C-l>", internal_split_nav("l"), { desc = "Move to right split" })

    map({ "n", "i", "v", "t" }, "<M-h>", smart_tmux_nav("h", "L"), { desc = "Move to left split or tmux pane" })
    map({ "n", "i", "v", "t" }, "<M-j>", smart_tmux_nav("j", "D"), { desc = "Move to lower split or tmux pane" })
    map({ "n", "i", "v", "t" }, "<M-k>", smart_tmux_nav("k", "U"), { desc = "Move to upper split or tmux pane" })
    map({ "n", "i", "v", "t" }, "<M-l>", smart_tmux_nav("l", "R"), { desc = "Move to right split or tmux pane" })

    -- Buffer cycling and side mouse button (Mouse4/Mouse5) jumplist navigation
    map("n", "H", "<cmd>bprevious<CR>", { silent = true, desc = "Previous buffer" })
    map("n", "L", "<cmd>bnext<CR>", { silent = true, desc = "Next buffer" })
    map({ "n", "v" }, "<X1Mouse>", "<C-o>", { silent = true, desc = "Jump back in jumplist (Mouse4)" })
    map({ "n", "v" }, "<X2Mouse>", "<C-i>", { silent = true, desc = "Jump forward in jumplist (Mouse5)" })
    map("i", "<X1Mouse>", "<C-\\><C-o><C-o>", { silent = true, desc = "Jump back in jumplist (Mouse4)" })
    map("i", "<X2Mouse>", "<C-\\><C-o><C-i>", { silent = true, desc = "Jump forward in jumplist (Mouse5)" })

    -- Markdown and universal link navigation (Ctrl+Click, Alt+Click, gx)
    map({ "n", "v" }, "<C-LeftMouse>", function()
        if follow_editor_link then
            follow_editor_link(true, true)
        end
    end, { silent = true, desc = "Follow Markdown/file/web link or LSP definition" })
    map({ "n", "v" }, "<M-LeftMouse>", function()
        if follow_editor_link then
            follow_editor_link(true, false)
        end
    end, { silent = true, desc = "Follow Markdown/file/web link or LSP definition" })
    map("n", "gx", function()
        if not (follow_editor_link and follow_editor_link(false, false)) and vim.ui and vim.ui.open then
            vim.ui.open(vim.fn.expand("<cfile>"))
        end
    end, { silent = true, desc = "Follow Markdown/file/web link under cursor" })

    -- Visual indent and line movement
    map("v", "<", "<gv", { desc = "Indent left" })
    map("v", ">", ">gv", { desc = "Indent right" })
    map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move text down" })
    map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move text up" })

    -- Project file explorer toggle: mini.files (Space+e at buffer dir / Space+E at cwd, falling back to Lexplore)
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
                if recover_stale_cwd then
                    recover_stale_cwd()
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
end

return M
