-- Hybrid IDE workspace integration: pane focus/parking/swapping, fleet session switcher,
-- Editor-to-AI context dispatch, workspace directory dive (:IdeCd), and workspace quit (:Q / :Quit).

local M = {}

local unpack_fn = table.unpack or unpack

-- Runs `ide` for this Editor's own workspace, naming $IDE_SESSION explicitly when set so `ide`
-- never guesses a session. Outside an `ide` session, `ide` falls back to exact $TMUX_PANE lookup.
function M.ide_job(...)
    local cmd = { vim.fn.expand("$HOME/.local/bin/ide"), ... }
    local sess = vim.env.IDE_SESSION
    if sess and sess ~= "" then
        table.insert(cmd, sess)
    end
    vim.fn.jobstart(cmd, { detach = true })
end

local function tmux_ide_action(...)
    local args = { ... }
    return function()
        if vim.env.TMUX then
            M.ide_job(unpack_fn(args))
        end
    end
end

local function send_visual_to_ai()
    local cur_mode = vim.fn.mode()
    local in_visual = (cur_mode == "v" or cur_mode == "V" or cur_mode == "\22")
    local v1, v2
    if in_visual then
        v1 = vim.fn.line("v")
        v2 = vim.fn.line(".")
    else
        v1 = vim.fn.line("'<")
        v2 = vim.fn.line("'>")
        if v1 == 0 or v2 == 0 then
            v1 = vim.fn.line(".")
            v2 = v1
        end
    end
    local l1 = math.min(v1, v2)
    local l2 = math.max(v1, v2)
    local buf_name = vim.api.nvim_buf_get_name(0)
    local is_file_buf = (vim.bo.buftype == "" and buf_name ~= "")
    local region_lines = nil
    if not is_file_buf then
        if in_visual and vim.fn.getregion then
            local ok, reg = pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = cur_mode })
            if ok and reg and #reg > 0 then
                region_lines = reg
            end
        end
        if not region_lines then
            region_lines = vim.api.nvim_buf_get_lines(0, math.max(0, l1 - 1), l2, false)
        end
    end
    if in_visual then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    end
    if not vim.env.TMUX then
        return
    end
    if is_file_buf then
        local buf_path = vim.fn.fnamemodify(buf_name, ":p")
        M.ide_job("send", "--ref", string.format("%s:%d-%d", buf_path, l1, l2))
    elseif region_lines then
        local text = table.concat(region_lines, "\n")
        if text ~= "" then
            M.ide_job("send", "--text", text)
        end
    end
end

local function send_line_to_ai()
    if not vim.env.TMUX then
        return
    end
    local buf_name = vim.api.nvim_buf_get_name(0)
    if vim.bo.buftype == "" and buf_name ~= "" then
        local buf_path = vim.fn.fnamemodify(buf_name, ":p")
        M.ide_job("send", "--ref", string.format("%s:%d", buf_path, vim.fn.line(".")))
    else
        local line_text = vim.api.nvim_get_current_line()
        if line_text ~= "" then
            M.ide_job("send", "--text", line_text)
        end
    end
end

local function send_diagnostics_to_ai()
    local diags = vim.diagnostic.get(0)
    if not diags or #diags == 0 then
        vim.notify("No diagnostics in current buffer", vim.log.levels.INFO)
        return
    end
    if not vim.env.TMUX then
        return
    end
    table.sort(diags, function(a, b)
        if a.lnum ~= b.lnum then
            return a.lnum < b.lnum
        end
        return (a.col or 0) < (b.col or 0)
    end)
    local sev_names = {
        [vim.diagnostic.severity.ERROR] = "ERROR",
        [vim.diagnostic.severity.WARN] = "WARN",
        [vim.diagnostic.severity.INFO] = "INFO",
        [vim.diagnostic.severity.HINT] = "HINT",
    }
    local buf_name = vim.api.nvim_buf_get_name(0)
    local header_path = (buf_name ~= "") and vim.fn.fnamemodify(buf_name, ":.") or "[No Name]"
    local out = { string.format("Diagnostics in %s:", header_path) }
    for _, d in ipairs(diags) do
        local sev = sev_names[d.severity] or "DIAG"
        local msg = tostring(d.message or ""):gsub("%s*\n%s*", " ")
        table.insert(out, string.format("- [%s] L%d:%d: %s", sev, (d.lnum or 0) + 1, (d.col or 0) + 1, msg))
    end
    M.ide_job("send", "--text", table.concat(out, "\n") .. "\n")
end

local function open_ide_keys_popup()
    if vim.env.TMUX then
        local cmd = { "tmux", "display-popup" }
        if (vim.env.TMUX_PANE or "") ~= "" then
            table.insert(cmd, "-t")
            table.insert(cmd, vim.env.TMUX_PANE)
        end
        vim.list_extend(cmd, {
            "-E",
            "-w",
            "80",
            "-h",
            "24",
            vim.fn.shellescape(vim.fn.expand("$HOME/.local/bin/ide")) .. " keys",
        })
        vim.fn.jobstart(cmd, { detach = true })
    end
end

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

local function quit_ide_or_nvim(force, target_sessions)
    local targets = target_sessions or {}
    if vim.env.TMUX and vim.env.NVIM_IDE_SOCKET and vim.env.NVIM_IDE_SOCKET ~= "" then
        local cur_sess = vim.env.IDE_SESSION or ""
        local checks_local = (#targets == 0)
        if not checks_local and cur_sess ~= "" then
            for _, t in ipairs(targets) do
                if t == cur_sess then
                    checks_local = true
                    break
                end
            end
        end
        if not force and checks_local then
            local modified = count_real_modified_buffers()
            if modified > 0 then
                vim.api.nvim_echo({
                    {
                        "E37: No write since last change in "
                            .. modified
                            .. " buffer(s) (save with :wa or press Alt+Shift+Q / :Q! to force)",
                        "ErrorMsg",
                    },
                }, true, {})
                return
            end
        end
        if #targets == 0 then
            if force then
                M.ide_job("quit", "--force")
            else
                M.ide_job("quit")
            end
        else
            local cmd = { vim.fn.expand("$HOME/.local/bin/ide"), "quit" }
            if force then
                table.insert(cmd, "--force")
            end
            for _, t in ipairs(targets) do
                table.insert(cmd, t)
            end
            vim.fn.jobstart(cmd, { detach = true })
        end
    else
        vim.cmd(force and "qa!" or "confirm qa")
    end
end

local function complete_ide_sessions(arg_lead)
    local ide_bin = vim.fn.expand("$HOME/.local/bin/ide")
    if vim.fn.executable(ide_bin) ~= 1 then
        return {}
    end
    local lines = vim.fn.systemlist({ ide_bin, "list", "--plain" })
    if vim.v.shell_error ~= 0 then
        return {}
    end
    local matches = {}
    for _, s in ipairs(lines) do
        if s ~= "" and s:find(arg_lead, 1, true) == 1 then
            table.insert(matches, s)
        end
    end
    return matches
end

local function run_ide_cd(opts)
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
        M.ide_job("cd", resolved)
    end
end

local function run_ide_send(opts)
    if not vim.env.TMUX then
        return
    end
    local target = vim.trim(opts.args or "")
    if target == "" then
        target = vim.env.IDE_SESSION or ""
    end
    local mode_flag = opts.bang and "--switch" or "--no-focus"
    local ide_bin = vim.fn.expand("$HOME/.local/bin/ide")
    local l1 = math.min(opts.line1 or vim.fn.line("."), opts.line2 or vim.fn.line("."))
    local l2 = math.max(opts.line1 or vim.fn.line("."), opts.line2 or vim.fn.line("."))
    local has_range = (opts.range or 0) > 0
    local buf_name = vim.api.nvim_buf_get_name(0)
    if vim.bo.buftype == "" and buf_name ~= "" then
        local buf_path = vim.fn.fnamemodify(buf_name, ":p")
        local ref = has_range and string.format("%s:%d-%d", buf_path, l1, l2) or string.format("%s:%d", buf_path, l1)
        local cmd = { ide_bin, "send", "--ref", ref, mode_flag }
        if target ~= "" then
            table.insert(cmd, target)
        end
        vim.fn.jobstart(cmd, { detach = true })
    else
        local lines = vim.api.nvim_buf_get_lines(0, math.max(0, l1 - 1), l2, false)
        local text = table.concat(lines, "\n")
        if text == "" then
            return
        end
        local cmd = { ide_bin, "send", "--stdin", mode_flag }
        if target ~= "" then
            table.insert(cmd, target)
        end
        local jid = vim.fn.jobstart(cmd, { detach = true })
        if type(jid) == "number" and jid > 0 then
            pcall(vim.fn.chansend, jid, text)
            pcall(vim.fn.chanclose, jid, "stdin")
        end
    end
end

-- When Neovim is launched manually inside the IDE Editor pane (`nvim`, `vim`, `vi`),
-- verify exact tmux server PID + Editor pane identity asynchronously and self-bind `@ide_socket`
-- without blocking startup and without ever claiming `@ide_socket` from Shell, AI, or `:terminal` panes.
M._socket_probe_state = "idle"

local function maybe_bind_editor_ide_socket()
    if #vim.api.nvim_list_uis() == 0 then
        M._socket_probe_state = "skipped_headless"
        return
    end
    if (vim.env.NVIM or "") ~= "" then
        M._socket_probe_state = "skipped_nested_env"
        return
    end
    local tmux_env = vim.env.TMUX or ""
    local pane = vim.env.TMUX_PANE or ""
    if tmux_env == "" or pane == "" or pane:sub(1, 1) ~= "%" then
        M._socket_probe_state = "skipped_not_tmux"
        return
    end
    local srv_pid = tmux_env:match(",(%d+),[^,]*$")
    if not srv_pid or vim.fn.executable("tmux") ~= 1 then
        M._socket_probe_state = "skipped_not_tmux"
        return
    end
    local env_sock = vim.env.NVIM_IDE_SOCKET or ""
    if env_sock ~= "" then
        local uv0 = vim.uv or vim.loop
        for _, srv in ipairs(vim.fn.serverlist()) do
            if srv == env_sock and (not uv0 or uv0.fs_stat(env_sock)) then
                M._socket_probe_state = "already_listening"
                return
            end
        end
    end

    M._socket_probe_state = "running"
    local out_chunks = {}
    local jid = vim.fn.jobstart({
        "tmux",
        "display-message",
        "-p",
        "-t",
        pane,
        "#{pid}:#{pane_id}\t#{@ide_role}\t#{@ide_editor_pane}\t#{@ide_socket}\t#{@ide_session}\t#{pane_pid}",
    }, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            if type(data) == "table" then
                for _, line in ipairs(data) do
                    if line and line ~= "" then
                        table.insert(out_chunks, line)
                    end
                end
            end
        end,
        on_exit = function(_, code)
            if code ~= 0 or #out_chunks == 0 then
                M._socket_probe_state = "skipped_tmux_exit"
                return
            end
            local raw = out_chunks[1]:gsub("\r$", "")
            local parts = vim.split(raw, "\t", { plain = true })
            local prefix = parts[1] or ""
            local role = parts[2] or ""
            local ed_pane = parts[3] or ""
            local ide_sock = parts[4] or ""
            local ide_sess = parts[5] or ""
            local pane_pid_num = tonumber(parts[6] or "")
            if prefix ~= (srv_pid .. ":" .. pane) then
                M._socket_probe_state = "skipped_server_mismatch"
                return
            end
            if not ((ed_pane ~= "" and pane == ed_pane) or role == "editor") then
                M._socket_probe_state = "skipped_non_editor"
                return
            end
            if ide_sock == "" then
                ide_sock = env_sock
            end
            if ide_sock == "" then
                M._socket_probe_state = "skipped_no_sock"
                return
            end
            vim.schedule(function()
                if vim.v.exiting ~= vim.NIL then
                    M._socket_probe_state = "exiting"
                    return
                end
                local uv = vim.uv or vim.loop
                for _, srv in ipairs(vim.fn.serverlist()) do
                    if srv == ide_sock then
                        if not uv or uv.fs_stat(ide_sock) then
                            vim.env.NVIM_IDE_SOCKET = ide_sock
                            if ide_sess ~= "" then
                                vim.env.IDE_SESSION = ide_sess
                            end
                            M._socket_probe_state = "already_listening"
                            return
                        end
                        pcall(vim.fn.serverstop, ide_sock)
                        break
                    end
                end

                local function check_pane_ancestry()
                    if not pane_pid_num or pane_pid_num <= 0 then
                        return "unknown"
                    end
                    local my_pid = (uv and uv.os_getpid and uv.os_getpid()) or vim.fn.getpid()
                    local my_ppid = (uv and uv.os_getppid and uv.os_getppid()) or nil
                    if my_pid == pane_pid_num or my_ppid == pane_pid_num then
                        return "direct"
                    end
                    local f0 = io.open("/proc/" .. tostring(my_pid) .. "/stat", "r")
                    if f0 then
                        f0:close()
                        local cur = my_ppid
                        for _ = 1, 32 do
                            if not cur or cur <= 1 then
                                break
                            end
                            if cur == pane_pid_num then
                                return "direct"
                            end
                            local fh = io.open("/proc/" .. tostring(cur) .. "/stat", "r")
                            if not fh then
                                return "outside_pane"
                            end
                            local st_txt = fh:read("*a") or ""
                            fh:close()
                            local comm, rest = st_txt:match("^%d+%s+%((.*)%)%s+(.*)$")
                            if not comm or not rest then
                                return "outside_pane"
                            end
                            if cur ~= my_ppid and (comm == "nvim" or comm:find("^nvim", 1) ~= nil) then
                                return "nested_nvim"
                            end
                            local next_ppid = tonumber(rest:match("^%S+%s+(%d+)"))
                            if next_ppid == pane_pid_num then
                                return "direct"
                            end
                            cur = next_ppid
                        end
                        return "outside_pane"
                    end

                    -- Non-/proc POSIX fallback (macOS / BSD)
                    if vim.fn.executable("ps") ~= 1 then
                        return "unknown"
                    end
                    local ps_lines = vim.fn.systemlist({ "ps", "-eo", "pid=,ppid=,comm=" })
                    if vim.v.shell_error ~= 0 or type(ps_lines) ~= "table" or #ps_lines == 0 then
                        return "unknown"
                    end
                    local ppid_by_pid = {}
                    local comm_by_pid = {}
                    for _, pline in ipairs(ps_lines) do
                        local p_s, pp_s, cm_s = pline:match("^%s*(%d+)%s+(%d+)%s+(.+)$")
                        if p_s and pp_s and cm_s then
                            local p_n = tonumber(p_s)
                            local pp_n = tonumber(pp_s)
                            if p_n and pp_n then
                                ppid_by_pid[p_n] = pp_n
                                local trimmed = vim.trim(cm_s)
                                comm_by_pid[p_n] = trimmed:match("([^/]+)$") or trimmed
                            end
                        end
                    end
                    local start_ppid = my_ppid or ppid_by_pid[my_pid]
                    if start_ppid == pane_pid_num then
                        return "direct"
                    end
                    local cur = start_ppid
                    for _ = 1, 32 do
                        if not cur or cur <= 1 then
                            break
                        end
                        if cur == pane_pid_num then
                            return "direct"
                        end
                        local cm = comm_by_pid[cur]
                        local next_ppid = ppid_by_pid[cur]
                        if not next_ppid then
                            return "outside_pane"
                        end
                        if cur ~= start_ppid and cm and (cm == "nvim" or cm:find("^nvim", 1) ~= nil) then
                            return "nested_nvim"
                        end
                        if next_ppid == pane_pid_num then
                            return "direct"
                        end
                        cur = next_ppid
                    end
                    return "outside_pane"
                end

                local function resolve_ide_bin()
                    local cand = vim.fn.expand("$HOME/.local/bin/ide")
                    if vim.fn.executable(cand) == 1 then
                        return cand
                    end
                    local exe = vim.fn.exepath("ide")
                    return (exe ~= "") and exe or nil
                end

                local function delegate_heal_or_bind(bind_fn, unlink_first)
                    local ancestry = check_pane_ancestry()
                    if ancestry == "outside_pane" or ancestry == "nested_nvim" then
                        M._socket_probe_state = "skipped_ancestry:" .. ancestry
                        return
                    end
                    if ancestry == "direct" then
                        if unlink_first and uv and uv.fs_unlink then
                            pcall(uv.fs_unlink, ide_sock)
                        end
                        bind_fn()
                        return
                    end
                    local ide_bin = resolve_ide_bin()
                    if ide_bin then
                        local hcmd = { ide_bin, "_internal", "heal-socket" }
                        if ide_sess ~= "" then
                            table.insert(hcmd, ide_sess)
                        end
                        vim.fn.jobstart(hcmd, { detach = true })
                        M._socket_probe_state = "delegated_heal"
                    else
                        M._socket_probe_state = "skipped_ancestry:unknown"
                    end
                end

                local function bind_sock()
                    vim.schedule(function()
                        if vim.v.exiting ~= vim.NIL then
                            M._socket_probe_state = "exiting"
                            return
                        end
                        for _, srv in ipairs(vim.fn.serverlist()) do
                            if srv == ide_sock then
                                if not uv or uv.fs_stat(ide_sock) then
                                    M._socket_probe_state = "already_listening"
                                    return
                                end
                                pcall(vim.fn.serverstop, ide_sock)
                                break
                            end
                        end
                        local parent = vim.fn.fnamemodify(ide_sock, ":h")
                        if parent ~= "" and vim.fn.isdirectory(parent) == 0 then
                            pcall(vim.fn.mkdir, parent, "p", "0700")
                        end
                        local ok, started = pcall(vim.fn.serverstart, ide_sock)
                        if ok and started == ide_sock then
                            vim.env.NVIM_IDE_SOCKET = ide_sock
                            if ide_sess ~= "" then
                                vim.env.IDE_SESSION = ide_sess
                            end
                            M._socket_probe_state = "bound"
                        else
                            M._socket_probe_state = "bind_failed"
                        end
                    end)
                end

                local st = uv and uv.fs_stat(ide_sock) or nil
                if not st then
                    delegate_heal_or_bind(bind_sock, false)
                elseif st.type == "socket" and uv and uv.new_pipe then
                    local pipe = uv.new_pipe(false)
                    if pipe then
                        pipe:connect(ide_sock, function(err)
                            pcall(function()
                                if not pipe:is_closing() then
                                    pipe:close()
                                end
                            end)
                            if err then
                                vim.schedule(function()
                                    if vim.v.exiting == vim.NIL then
                                        delegate_heal_or_bind(bind_sock, true)
                                    else
                                        M._socket_probe_state = "exiting"
                                    end
                                end)
                            else
                                M._socket_probe_state = "live_peer"
                            end
                        end)
                    else
                        M._socket_probe_state = "skipped_no_pipe"
                    end
                else
                    M._socket_probe_state = "skipped_non_socket"
                end
            end)
        end,
    })
    if type(jid) ~= "number" or jid <= 0 then
        M._socket_probe_state = "skipped_jobstart_failed"
    end
end

function M.setup()
    local map = vim.keymap.set
    local sock_group = vim.api.nvim_create_augroup("SolarizedIdeSocket", { clear = true })
    if vim.v.vim_did_enter == 1 then
        maybe_bind_editor_ide_socket()
    else
        vim.api.nvim_create_autocmd("VimEnter", {
            group = sock_group,
            once = true,
            callback = maybe_bind_editor_ide_socket,
        })
    end

    -- Role focus, visibility parking, directional swaps, fleet switcher, and context dispatch
    map("n", "<leader>a", tmux_ide_action("_internal", "toggle"), { desc = "Toggle Focus: Editor <-> AI Agent" })
    map("x", "<leader>a", send_visual_to_ai, { desc = "Send Visual Selection Reference to AI Agent" })
    map("n", "<leader>il", send_line_to_ai, { desc = "Send Current Line Reference to AI Agent" })
    map("n", "<leader>id", send_diagnostics_to_ai, { desc = "Send Buffer Diagnostics to AI Agent" })

    map({ "n", "i", "v", "t" }, "<M-a>", tmux_ide_action("_internal", "toggle"), { desc = "Toggle Focus: Editor <-> AI Agent" })
    map({ "n", "i", "v", "t" }, "<M-e>", tmux_ide_action("_internal", "show", "editor"), { desc = "Focus Editor Pane (or bounce back)" })
    map({ "n", "i", "v", "t" }, "<M-t>", tmux_ide_action("_internal", "show", "term"), { desc = "Toggle Focus: Shell <-> Editor Pane" })
    map({ "n", "i", "v", "t" }, "<M-E>", tmux_ide_action("_internal", "park", "editor"), { desc = "Toggle Editor Pane Visibility" })
    map({ "n", "i", "v", "t" }, "<M-T>", tmux_ide_action("_internal", "park", "term"), { desc = "Toggle Shell Pane Visibility" })

    map({ "n", "i", "v", "t" }, "<M-H>", tmux_ide_action("_internal", "swap", "left"), { desc = "Swap Active Pane Left" })
    map({ "n", "i", "v", "t" }, "<M-J>", tmux_ide_action("_internal", "swap", "down"), { desc = "Swap Active Pane Down" })
    map({ "n", "i", "v", "t" }, "<M-K>", tmux_ide_action("_internal", "swap", "up"), { desc = "Swap Active Pane Up" })
    map({ "n", "i", "v", "t" }, "<M-L>", tmux_ide_action("_internal", "swap", "right"), { desc = "Swap Active Pane Right" })

    local open_ide_sessions_popup = tmux_ide_action("switch")
    map("n", "<leader>s", open_ide_sessions_popup, { desc = "Switch IDE Workspace Session" })
    map({ "n", "i", "v", "t" }, "<M-s>", open_ide_sessions_popup, { desc = "Switch IDE Workspace Session" })
    map({ "n", "i", "v", "t" }, "<M-S>", tmux_ide_action("next"), { desc = "Jump to Next Attention AI Agent" })

    map("n", "<leader>?", open_ide_keys_popup, { desc = "Open IDE Keybinding Cheatsheet" })
    map({ "n", "i", "v", "t" }, "<M-?>", open_ide_keys_popup, { desc = "Open IDE Keybinding Cheatsheet" })

    -- One-command workspace termination while keeping native :q/:wq/:qa/:wqa untouched
    map("n", "<leader>q", function()
        quit_ide_or_nvim(false)
    end, { desc = "Quit Entire IDE Workspace" })
    map({ "n", "i", "v", "t" }, "<M-q>", function()
        quit_ide_or_nvim(false)
    end, { desc = "Quit Entire IDE Workspace" })
    map({ "n", "i", "v", "t" }, "<M-Q>", function()
        quit_ide_or_nvim(true)
    end, { desc = "Force-Quit Entire IDE Workspace" })

    vim.api.nvim_create_user_command("Q", function(opts)
        quit_ide_or_nvim(opts.bang, opts.fargs)
    end, { bang = true, nargs = "*", complete = complete_ide_sessions, desc = "Quit Entire IDE Workspace" })
    vim.api.nvim_create_user_command("Quit", function(opts)
        quit_ide_or_nvim(opts.bang, opts.fargs)
    end, { bang = true, nargs = "*", complete = complete_ide_sessions, desc = "Quit Entire IDE Workspace" })

    vim.api.nvim_create_user_command("IdeCd", run_ide_cd, {
        nargs = "?",
        complete = "dir",
        desc = "Dive IDE Workspace (Editor & Shell) to directory",
    })
    map("n", "<leader>cd", "<cmd>IdeCd<CR>", { desc = "Dive IDE Workspace to Current Buffer Directory" })

    vim.api.nvim_create_user_command("IdeSend", run_ide_send, {
        bang = true,
        range = true,
        nargs = "?",
        complete = complete_ide_sessions,
        desc = "Stage line or visual range into target IDE session AI prompt",
    })
end

return M
