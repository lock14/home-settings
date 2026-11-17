-- Live buffer reloading, stale working directory recovery, and Markdown prose readability autocmds.

local M = {}

function M.recover_stale_cwd()
    local uv = vim.uv or vim.loop
    if not uv then
        return
    end
    local pwd = nil
    for _, cand in ipairs({ vim.env.PWD or "", vim.env.IDE_WORKDIR or "", vim.env.IDE_INITIAL_ROOT or "" }) do
        if cand and cand ~= "" and vim.fn.isdirectory(cand) == 1 then
            pwd = cand
            break
        end
    end
    if pwd then
        local s_dot = uv.fs_stat(".")
        local s_pwd = uv.fs_stat(pwd)
        if
            not uv.cwd()
            or not s_dot
            or s_dot.nlink == 0
            or (
                vim.fn.haslocaldir() == 0
                and vim.fn.haslocaldir(-1, 0) == 0
                and s_pwd
                and (s_dot.dev ~= s_pwd.dev or s_dot.ino ~= s_pwd.ino)
            )
        then
            pcall(vim.fn.chdir, pwd)
            vim.env.PWD = pwd
        end
    end
end

local function wrap_fs_abspath()
    if vim.fs and type(vim.fs.abspath) == "function" and not vim.fs._hs_abspath_wrapped then
        local orig_abspath = vim.fs.abspath
        vim.fs._hs_abspath_wrapped = true
        vim.fs.abspath = function(path)
            local ok, res = pcall(orig_abspath, path)
            if ok then
                return res
            end
            M.recover_stale_cwd()
            ok, res = pcall(orig_abspath, path)
            if ok then
                return res
            end
            if type(path) ~= "string" then
                error(res, 2)
            end
            local expanded = path:gsub("^~", vim.env.HOME or "~")
            if vim.startswith(expanded, "/") then
                return vim.fs.normalize(expanded)
            end
            local fb = (vim.env.PWD and vim.env.PWD ~= "" and vim.startswith(vim.env.PWD, "/")) and vim.env.PWD
                or (vim.env.IDE_WORKDIR and vim.env.IDE_WORKDIR ~= "" and vim.startswith(vim.env.IDE_WORKDIR, "/")) and vim.env.IDE_WORKDIR
                or (vim.env.IDE_INITIAL_ROOT and vim.env.IDE_INITIAL_ROOT ~= "" and vim.startswith(vim.env.IDE_INITIAL_ROOT, "/")) and vim.env.IDE_INITIAL_ROOT
                or (vim.env.HOME or "/")
            if expanded == "." or expanded == "" then
                return vim.fs.normalize(fb)
            end
            return vim.fs.normalize(vim.fs.joinpath(fb, expanded))
        end
    end
end

function M.setup(opts)
    local follow_editor_link = opts and opts.follow_editor_link or nil

    M.recover_stale_cwd()
    local uv = vim.uv or vim.loop
    if uv then
        local init_cwd = uv.cwd()
        local s_dot = uv.fs_stat(".")
        local cur_pwd = vim.env.PWD
        local s_pwd = (cur_pwd and cur_pwd ~= "") and uv.fs_stat(cur_pwd) or nil
        if
            init_cwd
            and init_cwd ~= ""
            and s_dot
            and s_dot.nlink ~= 0
            and (not s_pwd or s_dot.dev ~= s_pwd.dev or s_dot.ino ~= s_pwd.ino)
        then
            vim.env.PWD = init_cwd
        end
    end
    wrap_fs_abspath()

    local autoread_group = vim.api.nvim_create_augroup("SolarizedAutoRead", { clear = true })
    vim.api.nvim_create_autocmd("DirChanged", {
        group = autoread_group,
        pattern = "global",
        callback = function(ev)
            if ev.file and ev.file ~= "" then
                local cur_uv = vim.uv or vim.loop
                local cur_pwd = vim.env.PWD
                local s_cur = (cur_uv and cur_pwd and cur_pwd ~= "") and cur_uv.fs_stat(cur_pwd) or nil
                local s_ev = cur_uv and cur_uv.fs_stat(ev.file) or nil
                if not (s_cur and s_ev and s_cur.dev == s_ev.dev and s_cur.ino == s_ev.ino) then
                    vim.env.PWD = ev.file
                end
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "BufReadPre", "FileType" }, {
        group = autoread_group,
        callback = function()
            M.recover_stale_cwd()
        end,
    })
    vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
        group = autoread_group,
        callback = function()
            M.recover_stale_cwd()
            if vim.fn.getcmdwintype() == "" then
                pcall(vim.cmd, "silent! checktime")
            end
        end,
    })

    -- Word-boundary soft-wrapping and conceal-aware link navigation scoped strictly to Markdown buffers
    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("SolarizedMarkdownReadability", { clear = true }),
        pattern = { "markdown" },
        callback = function(ev)
            vim.opt_local.wrap = true
            vim.opt_local.linebreak = true
            vim.opt_local.breakindent = true
            local buf = (ev and ev.buf) or true
            vim.keymap.set("n", "<CR>", function()
                if not (follow_editor_link and follow_editor_link(false, false)) then
                    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
                end
            end, { buffer = buf, silent = true, desc = "Follow Markdown link under cursor" })
            vim.keymap.set("n", "gd", function()
                if not (follow_editor_link and follow_editor_link(false, true)) then
                    vim.lsp.buf.definition()
                end
            end, { buffer = buf, silent = true, desc = "Follow Markdown link or LSP definition" })
        end,
    })
end

return M
