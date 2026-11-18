-- Capability-probed terminal image rendering via snacks.image (Ghostty and Kitty U=1 Unicode placeholders).
-- Enforces silent no-op behavior on unsupported terminals, headless test isolation, =session-scoped tmux
-- client_termtype and SSH detection with live teardown/re-attach, and gutter-safe inline width clamping.

local M = {}

local PROBE_ID_BASE = 4294967265
local PROBE_ID_FEAT = 4294967266
local FENCE_HEX = "544E" -- hex("TN"): standard XTGETTCAP Terminal Name (uppercase hex; never queried by vim.termcap)
local LEGACY_FENCE_HEX = "6873696d67"
local STANDALONE_TIMEOUT_MS = 1000
local DETACHED_BACKOFF_MS = { 60, 140, 300, 600, 1100, 2000 }
local EMPTY_TERMTYPE_BACKOFF_MS = { 50, 120, 250, 500, 1000 }
local TMUX_MIN_RECHECK_NS = 250 * 1000 * 1000
local DEFAULT_IMG_DIRS = { "img", "images", "assets", "static", "public", "media", "attachments" }

local DISABLED_SNACKS_MODULES = {
    "animate",
    "bigfile",
    "dashboard",
    "dim",
    "explorer",
    "gh",
    "gitbrowse",
    "indent",
    "input",
    "layout",
    "lazygit",
    "notifier",
    "picker",
    "profiler",
    "quickfile",
    "scope",
    "scratch",
    "scroll",
    "statuscolumn",
    "terminal",
    "toggle",
    "words",
    "zen",
}

-- Persist state across `:source $MYVIMRC` module reloads so Snacks closures and M.state()/M.refresh() never split-brain
local S = _G._hs_snacks_image_ctx
if type(S) ~= "table" then
    S = {
        runtime = {
            mode = "headless",
            probed = false,
            supported = false,
            placeholders = false,
            remote = false,
            term_name = "unknown",
            clients_key = "",
            state = "init",
        },
        pending_detect_cbs = {},
        active_inlines = {},
        tracked_images = setmetatable({}, { __mode = "v" }),
        settled_empty_clients = {},
        retry_timer = nil,
        startup_detached_attempt = 0,
        startup_detached_active = true,
        empty_termtype_attempt = 0,
        empty_termtype_key = "",
        tmux_probe_inflight = false,
        tmux_probe_queued = false,
        last_tmux_probe_hrtime = 0,
        cached_tmux_sess_target = nil,
        passthrough_ensured_pane = nil,
        standalone_probe_started = false,
        installed = false,
    }
    _G._hs_snacks_image_ctx = S
end
local runtime = S.runtime

local function uv_lib()
    return vim.uv or vim.loop
end

local function is_headless()
    if #vim.api.nvim_list_uis() == 0 then
        return true
    end
    for _, arg in ipairs(vim.v.argv or {}) do
        if arg == "--headless" then
            return true
        end
    end
    return false
end

local function has_ssh_env(env_tbl)
    local e = env_tbl or vim.env
    return ((e.SSH_CONNECTION or "") ~= "")
        or ((e.SSH_CLIENT or "") ~= "")
        or ((e.SSH_TTY or "") ~= "")
end

local function parse_tmux_env_var(raw_tmux)
    local s = tostring(raw_tmux or "")
    if s == "" then
        return nil
    end
    local sock, pid, sess_id = s:match("^(.+),(%d+),([^,]+)$")
    if not pid then
        sock, pid, sess_id = s:match("^([^,]*),(%d+),([^,]+)$")
    end
    if not pid then
        sock = s:match("^([^,]+)") or ""
        pid = ""
        sess_id = ""
    end
    return {
        socket = sock or "",
        server_pid = pid or "",
        session_id = (sess_id or ""):gsub("^%$", ""),
    }
end

local function build_tmux_cmd(tmux_info, args)
    local cmd = { "tmux" }
    if tmux_info and tmux_info.socket ~= "" then
        table.insert(cmd, "-S")
        table.insert(cmd, tmux_info.socket)
    end
    for _, a in ipairs(args) do
        table.insert(cmd, a)
    end
    return cmd
end

local function stop_retry_timer()
    if S.retry_timer then
        if not S.retry_timer:is_closing() then
            S.retry_timer:stop()
            S.retry_timer:close()
        end
        S.retry_timer = nil
    end
end

local function schedule_retry(delay_ms, fn)
    stop_retry_timer()
    local uv = uv_lib()
    if not (uv and uv.new_timer) then
        return
    end
    S.retry_timer = uv.new_timer()
    if not S.retry_timer then
        return
    end
    S.retry_timer:start(delay_ms, 0, function()
        stop_retry_timer()
        vim.schedule(fn)
    end)
end

local function hex_decode_ascii(hex_str)
    if type(hex_str) ~= "string" or hex_str == "" or (#hex_str % 2) ~= 0 then
        return ""
    end
    if not hex_str:match("^[0-9a-fA-F]+$") then
        return ""
    end
    return (hex_str:gsub("..", function(cc)
        return string.char(tonumber(cc, 16))
    end))
end

local function is_u1_terminal_name(raw)
    local lc = tostring(raw or ""):lower()
    if lc:find("ghostty", 1, true) then
        return true, "ghostty"
    end
    if lc:find("kitty", 1, true) then
        return true, "kitty"
    end
    return false, nil
end

function M.resolve_doc_image(file, src)
    if type(src) ~= "string" or src == "" or src:find("^%w%w+://") then
        return nil
    end
    local uv = uv_lib()
    local expanded = src:gsub("^~/", (vim.env.HOME or "~") .. "/")
    if expanded:sub(1, 1) == "/" or expanded:match("^%a:[/\\]") then
        if vim.fn.filereadable(expanded) == 1 then
            return (uv and uv.fs_realpath and uv.fs_realpath(expanded)) or vim.fs.normalize(expanded)
        end
        return nil
    end

    local roots = {}
    if type(file) == "string" and file ~= "" then
        local doc_dir = vim.fs.dirname(file)
        if doc_dir and doc_dir ~= "" and doc_dir ~= "." then
            table.insert(roots, doc_dir)
        end
    end
    local cwd = (uv and uv.cwd and uv.cwd()) or vim.env.PWD or ""
    if cwd ~= "" and cwd ~= roots[1] then
        table.insert(roots, cwd)
    end

    for _, root in ipairs(roots) do
        local cand = root .. "/" .. expanded
        if vim.fn.filereadable(cand) == 1 then
            return (uv and uv.fs_realpath and uv.fs_realpath(cand)) or vim.fs.normalize(cand)
        end
    end

    local ok_s, SnacksImg = pcall(require, "snacks.image")
    local img_dirs = (ok_s and SnacksImg and SnacksImg.config and SnacksImg.config.img_dirs) or DEFAULT_IMG_DIRS
    for _, root in ipairs(roots) do
        for _, sub in ipairs(img_dirs) do
            local dir = root .. "/" .. sub
            if vim.fn.isdirectory(dir) == 1 then
                local cand = dir .. "/" .. expanded
                if vim.fn.filereadable(cand) == 1 then
                    return (uv and uv.fs_realpath and uv.fs_realpath(cand)) or vim.fs.normalize(cand)
                end
            end
        end
    end

    if roots[1] then
        return vim.fs.normalize(roots[1] .. "/" .. expanded)
    end
    return nil
end

function M.evaluate_wire_probe(probe_state)
    local ps = probe_state or {}
    local xt = vim.trim(tostring(ps.xtversion or ""))
    local tn = vim.trim(tostring(ps.xtcap_tn or ""))
    local ident = (xt ~= "") and xt or tn
    local is_known_u1, known_name = is_u1_terminal_name(ident)
    local has_gfx = ps.has_graphics == true
    local placeholders = false
    if has_gfx then
        if ps.feature_u1 == true then
            placeholders = true
        elseif ps.feature_u1 == nil and is_known_u1 then
            placeholders = true
        end
    end
    local supported = has_gfx and placeholders
    local term_name = known_name or (ident ~= "" and ident:match("^(%S+)") or (supported and "kitty-u1" or "unsupported"))
    return {
        supported = supported,
        placeholders = placeholders,
        term_name = term_name:lower(),
    }
end

function M.parse_tmux_probe_output(raw_out, proc_env)
    local clients = {}
    local sess_ssh = {}
    for line in tostring(raw_out or ""):gmatch("[^\r\n]+") do
        if line:sub(1, 14) == "__HS_CLIENT__\t" then
            local rest = line:sub(15)
            local cname, ctype, cterm = rest:match("^([^\t]*)\t([^\t]*)\t(.*)$")
            if cname then
                table.insert(clients, {
                    name = vim.trim(cname),
                    termtype = vim.trim(ctype),
                    termname = vim.trim(cterm),
                })
            end
        else
            for _, k in ipairs({ "SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY" }) do
                if line == "-" .. k then
                    sess_ssh[k] = false
                elseif line:sub(1, #k + 1) == (k .. "=") then
                    sess_ssh[k] = (line:sub(#k + 2) ~= "")
                end
            end
        end
    end

    local penv = proc_env or vim.env
    local is_remote = false
    for _, k in ipairs({ "SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY" }) do
        if sess_ssh[k] == true then
            is_remote = true
            break
        elseif sess_ssh[k] == nil and (penv[k] or "") ~= "" then
            is_remote = true
            break
        end
    end

    table.sort(clients, function(a, b)
        return a.name < b.name
    end)

    if #clients == 0 then
        return {
            state = "detached",
            supported = false,
            placeholders = false,
            remote = is_remote,
            term_name = "detached",
            clients_key = "",
        }
    end

    local key_parts = {}
    local has_empty = false
    local has_unsupported = false
    local detected_name = nil

    for _, cl in ipairs(clients) do
        table.insert(key_parts, cl.name .. "=" .. cl.termtype)
        if cl.termtype == "" then
            has_empty = true
        else
            local ok_u1, tname = is_u1_terminal_name(cl.termtype)
            if ok_u1 then
                detected_name = detected_name or tname
            else
                has_unsupported = true
            end
        end
    end

    local clients_key = table.concat(key_parts, ";")
    if has_unsupported then
        return {
            state = "unsupported",
            supported = false,
            placeholders = false,
            remote = is_remote,
            term_name = "unsupported",
            clients_key = clients_key,
        }
    end

    if has_empty then
        return {
            state = "transient_empty",
            supported = false,
            placeholders = false,
            remote = is_remote,
            term_name = "pending",
            clients_key = clients_key,
        }
    end

    return {
        state = "supported",
        supported = true,
        placeholders = true,
        remote = is_remote,
        term_name = detected_name or "ghostty",
        clients_key = clients_key,
    }
end

function M.compute_inline_max_width(placement)
    if not (placement and placement.buf and vim.api.nvim_buf_is_valid(placement.buf)) then
        return nil
    end
    local wins = (type(placement.wins) == "function") and placement:wins() or vim.fn.win_findbuf(placement.buf)
    if not wins or #wins == 0 then
        return nil
    end

    local opts = placement.opts or {}
    local pos = opts.pos or { 1, 0 }
    local range = opts.range or { pos[1], pos[2], pos[1], pos[2] }
    local offset = math.max(0, tonumber(range[2]) or 0)
    local lines = vim.api.nvim_buf_get_lines(placement.buf, math.max(0, range[1] - 1), range[3], false)
    local text_width = 0
    for _, line in ipairs(lines) do
        text_width = math.max(text_width, vim.api.nvim_strwidth(line))
    end
    local last_line = lines[#lines] or ""
    local has_after = last_line:sub((tonumber(range[4]) or 0) + 1):find("%S") ~= nil
    local can_overlay = (#lines > 1 or not has_after)
    if can_overlay then
        for _, win in ipairs(wins) do
            if vim.api.nvim_win_is_valid(win) and vim.wo[win].wrap then
                local info = vim.fn.getwininfo(win)[1]
                if info and (info.width - info.textoff) < text_width then
                    can_overlay = false
                    break
                end
            end
        end
    end

    local pad = can_overlay and offset or 0
    local min_avail = nil
    for _, win in ipairs(wins) do
        if vim.api.nvim_win_is_valid(win) then
            local info = vim.fn.getwininfo(win)[1]
            local win_w = info and info.width or vim.api.nvim_win_get_width(win)
            local textoff = info and info.textoff or 0
            local avail = math.max(1, win_w - textoff - pad)
            if min_avail == nil or avail < min_avail then
                min_avail = avail
            end
        end
    end
    return min_avail
end

local function sync_snacks_terminal_state()
    local ok_t, Terminal = pcall(require, "snacks.image.terminal")
    if not ok_t then
        return
    end
    local name_parts = {}
    if runtime.term_name and runtime.term_name ~= "" then
        table.insert(name_parts, runtime.term_name)
    end
    if runtime.mode == "tmux" then
        table.insert(name_parts, "tmux")
    end
    if runtime.remote then
        table.insert(name_parts, "ssh")
    end
    Terminal._terminal = {
        terminal = runtime.term_name,
        version = "",
        supported = runtime.supported,
        placeholders = runtime.placeholders,
    }
    Terminal._env = {
        name = table.concat(name_parts, "/"),
        env = {},
        supported = runtime.supported,
        placeholders = runtime.placeholders,
        remote = runtime.remote,
        transform = (runtime.mode == "tmux")
                and function(data)
                    return ("\027Ptmux;" .. data:gsub("\027", "\027\027")) .. "\027\\"
                end
            or nil,
    }
    Terminal.transform = Terminal._env.transform
end

local function flush_detect_callbacks()
    if #S.pending_detect_cbs == 0 then
        return
    end
    local cbs = S.pending_detect_cbs
    S.pending_detect_cbs = {}
    local ok_t, Terminal = pcall(require, "snacks.image.terminal")
    local term_obj = (ok_t and Terminal._terminal) or {
        terminal = runtime.term_name,
        version = "",
        supported = runtime.supported,
        placeholders = runtime.placeholders,
    }
    for _, cb in ipairs(cbs) do
        pcall(cb, term_obj)
    end
end

local function reset_image_transmission_cache()
    for _, img in pairs(S.tracked_images) do
        if type(img) == "table" then
            img.sent = false
        end
    end
    local ok_img, Image = pcall(require, "snacks.image.image")
    if ok_img and type(Image.clear) == "function" then
        pcall(Image.clear)
    end
end

local function current_buf_render_sig(file)
    return table.concat({
        tostring(file or ""),
        tostring(runtime.supported),
        tostring(runtime.remote),
        tostring(runtime.clients_key or ""),
    }, "|")
end

local function is_minifiles_preview_buf(buf)
    local ok_mf, mf = pcall(require, "mini.files")
    if not (ok_mf and mf and type(mf.get_explorer_state) == "function") then
        return false, nil
    end
    local st = mf.get_explorer_state()
    if not (st and st.windows and #st.windows > 0) then
        return false, nil
    end
    local last_win = st.windows[#st.windows]
    if
        last_win
        and last_win.win_id
        and vim.api.nvim_win_is_valid(last_win.win_id)
        and vim.api.nvim_win_get_buf(last_win.win_id) == buf
        and last_win.path
        and last_win.path ~= st.branch[st.depth_focus]
    then
        return true, last_win.path:gsub("%z", "")
    end
    return false, nil
end

local function teardown_all_placements(re_render_image_bufs)
    for buf, inst in pairs(S.active_inlines) do
        if type(inst) == "table" then
            inst._hs_closed = true
            for _, p in pairs(inst.imgs or {}) do
                pcall(function()
                    p:close()
                end)
            end
            inst.imgs = {}
            inst.idx = {}
        end
        pcall(vim.api.nvim_del_augroup_by_name, "snacks.image.inline." .. tostring(buf))
    end
    S.active_inlines = {}

    local doc_ok, Doc = pcall(require, "snacks.image.doc")
    if doc_ok and Doc and type(Doc.hover_close) == "function" then
        pcall(Doc.hover_close)
    end

    local ok_p, Placement = pcall(require, "snacks.image.placement")
    if ok_p and Placement and type(Placement.clean) == "function" then
        pcall(Placement.clean)
    end

    local ns = (ok_p and Placement and Placement.ns) or nil
    local ok_b, Buf = pcall(require, "snacks.image.buf")

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
            if ns then
                pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
            end
            pcall(function()
                vim.b[buf].snacks_image_attached = nil
                vim.b[buf].hs_image_render_sig = nil
            end)
            pcall(vim.api.nvim_del_augroup_by_name, "snacks.image.doc." .. tostring(buf))
            pcall(vim.api.nvim_del_augroup_by_name, "snacks.image.inline." .. tostring(buf))
            if re_render_image_bufs and ok_b and Buf and vim.api.nvim_buf_is_loaded(buf) then
                local img_src = vim.b[buf].hs_image_file_src
                if type(img_src) == "string" and img_src ~= "" then
                    pcall(Buf._attach, buf, { src = img_src })
                end
            end
        end
    end
end

local function expand_minifiles_preview_win_height(win_id)
    if not (win_id and vim.api.nvim_win_is_valid(win_id)) then
        return
    end
    local ok_cfg, cfg = pcall(vim.api.nvim_win_get_config, win_id)
    if not (ok_cfg and cfg and cfg.relative and cfg.relative ~= "") then
        return
    end
    local row = type(cfg.row) == "table" and (cfg.row[false] or cfg.row[1] or 0) or (cfg.row or 0)
    local bw = (cfg.border == nil or cfg.border == "none") and 0 or 2
    local status_h = (vim.o.laststatus > 0) and 1 or 0
    local avail_h = vim.o.lines - row - bw - vim.o.cmdheight - status_h
    if avail_h > vim.api.nvim_win_get_height(win_id) then
        pcall(vim.api.nvim_win_set_height, win_id, avail_h)
    end
end

local function attach_eligible_buffers()
    local ok_s, SnacksImg = pcall(require, "snacks.image")
    if not (ok_s and SnacksImg) then
        return
    end
    local langs = {}
    for _, l in ipairs(SnacksImg.langs() or {}) do
        langs[l] = true
    end
    local uv = uv_lib()

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
            local is_mf_prev, mf_path = is_minifiles_preview_buf(buf)
            if is_mf_prev and mf_path and SnacksImg.supports_file(mf_path) then
                local st = uv and uv.fs_stat(mf_path) or nil
                if st and st.type == "file" then
                    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                        if vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_buf(w) == buf then
                            expand_minifiles_preview_win_height(w)
                        end
                    end
                    vim.b[buf].hs_image_render_sig = nil
                    pcall(SnacksImg.buf._attach, buf, { src = mf_path })
                end
            else
                local img_src = vim.b[buf].hs_image_file_src
                local buf_name = vim.api.nvim_buf_get_name(buf)
                if type(img_src) == "string" and img_src ~= "" then
                    vim.b[buf].hs_image_render_sig = nil
                    pcall(SnacksImg.buf._attach, buf, { src = img_src })
                elseif vim.bo[buf].buftype == "" and buf_name ~= "" and SnacksImg.supports_file(buf_name) then
                    vim.b[buf].hs_image_file_src = buf_name
                    vim.b[buf].hs_image_render_sig = nil
                    pcall(SnacksImg.buf._attach, buf)
                else
                    local ft = vim.bo[buf].filetype
                    if ft and ft ~= "" then
                        local ok_lang, lang = pcall(vim.treesitter.language.get_lang, ft)
                        local resolved_lang = (ok_lang and lang) or ft
                        if langs[resolved_lang] then
                            vim.b[buf].snacks_image_attached = nil
                            pcall(SnacksImg.doc._attach, buf)
                        end
                    end
                end
            end
        end
    end
end

local function run_async_cmd(cmd, on_exit)
    if vim.system then
        local ok = pcall(vim.system, cmd, { text = true }, vim.schedule_wrap(function(res)
            on_exit((res and res.code) or 1, (res and res.stdout) or "")
        end))
        if ok then
            return
        end
    end
    local out_chunks = {}
    local jid = vim.fn.jobstart(cmd, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            if type(data) == "table" then
                out_chunks = data
            end
        end,
        on_exit = function(_, code)
            vim.schedule(function()
                on_exit(code or 1, table.concat(out_chunks, "\n"))
            end)
        end,
    })
    if type(jid) ~= "number" or jid <= 0 then
        vim.schedule(function()
            on_exit(1, "")
        end)
    end
end

local function ensure_tmux_pane_passthrough(on_ready)
    if runtime.mode ~= "tmux" or not runtime.supported then
        if on_ready then
            on_ready()
        end
        return
    end
    local pane = vim.env.TMUX_PANE or ""
    local tmux_info = (pane ~= "") and parse_tmux_env_var(vim.env.TMUX) or nil
    if pane == "" or not tmux_info or S.passthrough_ensured_pane == pane then
        if on_ready then
            on_ready()
        end
        return
    end
    local cmd = build_tmux_cmd(tmux_info, { "set-option", "-p", "-q", "-t", pane, "allow-passthrough", "on" })
    run_async_cmd(cmd, function(code)
        if code == 0 then
            S.passthrough_ensured_pane = pane
        end
        if on_ready then
            on_ready()
        end
    end)
end

local function apply_capability_transition(next_cap)
    local prev_supported = runtime.supported
    local prev_remote = runtime.remote
    local prev_clients_key = runtime.clients_key

    local next_supported = (next_cap.supported == true) and (next_cap.placeholders == true)
    local next_remote = next_cap.remote == true
    local next_clients_key = tostring(next_cap.clients_key or "")
    local client_switched = prev_supported
        and next_supported
        and (prev_remote ~= next_remote or prev_clients_key ~= next_clients_key)

    if prev_supported and not next_supported then
        -- Mute terminal output BEFORE cleaning placements so zero Kitty escape sequences leak to VTE/detached clients
        runtime.supported = false
        runtime.placeholders = false
        runtime.remote = next_remote
        runtime.term_name = tostring(next_cap.term_name or "unsupported")
        runtime.clients_key = next_clients_key
        runtime.state = tostring(next_cap.state or "unsupported")
        runtime.probed = next_cap.probed ~= false
        sync_snacks_terminal_state()
        teardown_all_placements(true)
        reset_image_transmission_cache()
        flush_detect_callbacks()
        return
    end

    if client_switched then
        -- Mute writes while tearing down old client extmarks, then re-transmit images to the new client/transport
        runtime.supported = false
        runtime.placeholders = false
        sync_snacks_terminal_state()
        teardown_all_placements(false)
        reset_image_transmission_cache()
    elseif not prev_supported and next_supported then
        reset_image_transmission_cache()
    end

    runtime.supported = next_supported
    runtime.placeholders = next_supported
    runtime.remote = next_remote
    runtime.term_name = tostring(next_cap.term_name or (next_supported and "ghostty" or "unsupported"))
    runtime.clients_key = next_clients_key
    runtime.state = tostring(next_cap.state or (next_supported and "supported" or "unsupported"))
    runtime.probed = next_cap.probed ~= false
    sync_snacks_terminal_state()

    if next_supported and (not prev_supported or client_switched) then
        ensure_tmux_pane_passthrough(function()
            if runtime.supported then
                attach_eligible_buffers()
            end
            flush_detect_callbacks()
        end)
        return
    elseif not next_supported then
        -- Ensure any BufReadCmd image buffers waiting on initial detection populate clean metadata text
        local ok_b, Buf = pcall(require, "snacks.image.buf")
        if ok_b and Buf then
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
                    local img_src = vim.b[buf].hs_image_file_src
                    if type(img_src) == "string" and img_src ~= "" and vim.bo[buf].filetype ~= "markdown" then
                        pcall(Buf._attach, buf, { src = img_src })
                    end
                end
            end
        end
    end

    flush_detect_callbacks()
end

local function resolve_tmux_session_target(tmux_info, force_lookup, cb)
    if not force_lookup then
        if S.cached_tmux_sess_target and S.cached_tmux_sess_target ~= "" then
            return cb(S.cached_tmux_sess_target, true)
        end
        local ide_sess = vim.env.IDE_SESSION or ""
        if ide_sess ~= "" then
            S.cached_tmux_sess_target = "=" .. ide_sess
            return cb(S.cached_tmux_sess_target, true)
        end
    end

    local pane_or_sess = vim.env.TMUX_PANE or ""
    if pane_or_sess == "" and tmux_info.session_id ~= "" then
        pane_or_sess = "$" .. tmux_info.session_id
    end
    if pane_or_sess == "" then
        return cb(nil, false)
    end

    local cmd = build_tmux_cmd(tmux_info, {
        "display-message",
        "-p",
        "-t",
        pane_or_sess,
        "#{pid}\t#{session_name}",
    })
    run_async_cmd(cmd, function(code, stdout)
        if code ~= 0 or stdout == "" then
            return cb(nil, false)
        end
        local pid, sname = vim.trim(stdout):match("^(%S+)\t(.+)$")
        if not sname or sname == "" then
            return cb(nil, false)
        end
        if tmux_info.server_pid ~= "" and pid ~= tmux_info.server_pid then
            return cb(nil, false)
        end
        S.cached_tmux_sess_target = "=" .. sname
        cb(S.cached_tmux_sess_target, false)
    end)
end

local function probe_tmux_capabilities(force)
    if runtime.mode ~= "tmux" or is_headless() then
        return
    end
    local uv = uv_lib()
    local now_ns = (uv and uv.hrtime and uv.hrtime()) or 0
    if not force and runtime.probed and now_ns > 0 and (now_ns - S.last_tmux_probe_hrtime) < TMUX_MIN_RECHECK_NS then
        flush_detect_callbacks()
        return
    end
    if S.tmux_probe_inflight then
        S.tmux_probe_queued = true
        return
    end
    S.tmux_probe_inflight = true
    S.last_tmux_probe_hrtime = now_ns

    local tmux_info = parse_tmux_env_var(vim.env.TMUX)
    if not tmux_info then
        S.tmux_probe_inflight = false
        apply_capability_transition({
            state = "unsupported",
            supported = false,
            placeholders = false,
            remote = has_ssh_env(),
            term_name = "unsupported",
            clients_key = "",
            probed = true,
        })
        return
    end

    local function finish_tmux_probe()
        S.tmux_probe_inflight = false
        if S.tmux_probe_queued then
            S.tmux_probe_queued = false
            probe_tmux_capabilities(true)
        end
    end

    local function query_with_target(sess_target, allow_fallback)
        if not sess_target then
            apply_capability_transition({
                state = "detached",
                supported = false,
                placeholders = false,
                remote = has_ssh_env(),
                term_name = "detached",
                clients_key = "",
                probed = true,
            })
            finish_tmux_probe()
            return
        end

        local cmd = build_tmux_cmd(tmux_info, {
            "list-clients",
            "-t",
            sess_target,
            "-F",
            "__HS_CLIENT__\t#{client_name}\t#{client_termtype}\t#{client_termname}",
            ";",
            "show-environment",
            "-t",
            sess_target,
        })
        run_async_cmd(cmd, function(code, stdout)
            if code ~= 0 and allow_fallback then
                S.cached_tmux_sess_target = nil
                resolve_tmux_session_target(tmux_info, true, function(fallback_target)
                    query_with_target(fallback_target, false)
                end)
                return
            end
            if code ~= 0 then
                apply_capability_transition({
                    state = "detached",
                    supported = false,
                    placeholders = false,
                    remote = has_ssh_env(),
                    term_name = "detached",
                    clients_key = "",
                    probed = true,
                })
                finish_tmux_probe()
                return
            end

            local parsed = M.parse_tmux_probe_output(stdout, vim.env)

            if parsed.state == "detached" then
                if S.startup_detached_active and S.startup_detached_attempt < #DETACHED_BACKOFF_MS then
                    S.startup_detached_attempt = S.startup_detached_attempt + 1
                    local delay = DETACHED_BACKOFF_MS[S.startup_detached_attempt]
                    apply_capability_transition(vim.tbl_extend("force", parsed, { probed = false }))
                    schedule_retry(delay, function()
                        probe_tmux_capabilities(true)
                    end)
                else
                    S.startup_detached_active = false
                    stop_retry_timer()
                    apply_capability_transition(vim.tbl_extend("force", parsed, { probed = true }))
                end
                finish_tmux_probe()
                return
            end

            -- At least one client is attached to =session
            S.startup_detached_active = false

            if parsed.state == "transient_empty" then
                if not S.settled_empty_clients[parsed.clients_key] then
                    if S.empty_termtype_key ~= parsed.clients_key then
                        S.empty_termtype_key = parsed.clients_key
                        S.empty_termtype_attempt = 0
                    end
                    if S.empty_termtype_attempt < #EMPTY_TERMTYPE_BACKOFF_MS then
                        S.empty_termtype_attempt = S.empty_termtype_attempt + 1
                        local delay = EMPTY_TERMTYPE_BACKOFF_MS[S.empty_termtype_attempt]
                        apply_capability_transition(vim.tbl_extend("force", parsed, { probed = false }))
                        schedule_retry(delay, function()
                            probe_tmux_capabilities(true)
                        end)
                        finish_tmux_probe()
                        return
                    end
                    S.settled_empty_clients[parsed.clients_key] = true
                end
                stop_retry_timer()
                apply_capability_transition({
                    state = "unsupported",
                    supported = false,
                    placeholders = false,
                    remote = parsed.remote,
                    term_name = "unsupported",
                    clients_key = parsed.clients_key,
                    probed = true,
                })
                finish_tmux_probe()
                return
            end

            S.empty_termtype_key = ""
            S.empty_termtype_attempt = 0
            stop_retry_timer()
            apply_capability_transition(vim.tbl_extend("force", parsed, { probed = true }))
            finish_tmux_probe()
        end)
    end

    resolve_tmux_session_target(tmux_info, false, function(sess_target, from_cache)
        query_with_target(sess_target, from_cache == true)
    end)
end

local function start_standalone_wire_probe()
    if S.standalone_probe_started or runtime.mode ~= "standalone" or is_headless() then
        return
    end
    if not vim.api.nvim_ui_send then
        apply_capability_transition({
            state = "unsupported",
            supported = false,
            placeholders = false,
            remote = has_ssh_env(),
            term_name = "unsupported",
            clients_key = "standalone",
            probed = true,
        })
        return
    end
    S.standalone_probe_started = true

    local probe_state = {
        has_graphics = false,
        feature_u1 = nil,
        xtversion = "",
        xtcap_tn = "",
    }
    local finished = false
    local augroup = vim.api.nvim_create_augroup("SolarizedImageWireProbe", { clear = true })
    local timeout_timer = nil

    local function finalize_wire_probe()
        if finished then
            return
        end
        finished = true
        if timeout_timer then
            if not timeout_timer:is_closing() then
                timeout_timer:stop()
                timeout_timer:close()
            end
            timeout_timer = nil
        end
        pcall(vim.api.nvim_del_augroup_by_id, augroup)
        local eval = M.evaluate_wire_probe(probe_state)
        apply_capability_transition({
            state = eval.supported and "supported" or "unsupported",
            supported = eval.supported,
            placeholders = eval.placeholders,
            remote = has_ssh_env(),
            term_name = eval.term_name,
            clients_key = "standalone:" .. eval.term_name,
            probed = true,
        })
    end

    vim.api.nvim_create_autocmd("TermResponse", {
        group = augroup,
        callback = function(ev)
            local raw_seq = (ev and ev.data and ev.data.sequence) or ""
            if raw_seq == "" then
                return
            end
            local seq = raw_seq:gsub("\027\\$", ""):gsub("\007$", "")

            local ctrl, body = seq:match("^\027_G([^;]*);(.*)$")
            if ctrl then
                local kv = {}
                for pair in ctrl:gmatch("[^,]+") do
                    local k, v = pair:match("^([^=]+)=(.*)$")
                    if k then
                        kv[k] = v
                    end
                end
                if kv.i == tostring(PROBE_ID_BASE) and body == "OK" then
                    probe_state.has_graphics = true
                elseif kv.i == tostring(PROBE_ID_FEAT) and body == "OK" then
                    probe_state.has_graphics = true
                    if kv.e == "T" then
                        probe_state.feature_u1 = (kv.U == "1")
                    end
                end
                return
            end

            local xtver = seq:match("^\027P>|(.+)$")
            if xtver then
                probe_state.xtversion = vim.trim(xtver)
                return
            end

            local tn_hex = seq:match("^\027P1%+r[5][4][4][eE]=([0-9a-fA-F]*)")
            if tn_hex ~= nil then
                local decoded = vim.trim(hex_decode_ascii(tn_hex))
                if decoded ~= "" then
                    probe_state.xtcap_tn = decoded
                end
                vim.schedule(finalize_wire_probe)
                return true
            end

            local seq_lc = seq:lower()
            if
                seq_lc:find("^\027p[01]%+r" .. FENCE_HEX:lower())
                or seq_lc:find("^\027p[01]%+r" .. LEGACY_FENCE_HEX)
                or (seq == "\027P0+r" and probe_state.xtversion ~= "")
            then
                vim.schedule(finalize_wire_probe)
                return true
            end
        end,
    })

    local uv = uv_lib()
    if uv and uv.new_timer then
        timeout_timer = uv.new_timer()
        if timeout_timer then
            timeout_timer:start(STANDALONE_TIMEOUT_MS, 0, function()
                vim.schedule(finalize_wire_probe)
            end)
        end
    end

    local wire_payload = string.format(
        "\027_Gi=%d,s=1,v=1,a=q,t=d,f=24;AAAA\027\\\027_Ga=q,i=%d,e=T,U=1\027\\\027[>q\027P+q%s\027\\",
        PROBE_ID_BASE,
        PROBE_ID_FEAT,
        FENCE_HEX
    )
    vim.api.nvim_ui_send(wire_payload)
end

local function register_minifiles_autocmds()
    local ok_s, SnacksImg = pcall(require, "snacks.image")
    local ok_p, Placement = pcall(require, "snacks.image.placement")
    local ok_b, Buf = pcall(require, "snacks.image.buf")
    if not (ok_s and ok_p and ok_b and SnacksImg and Placement and Buf) then
        return
    end
    local mf_group = vim.api.nvim_create_augroup("SolarizedMiniFilesImagePreview", { clear = true })
    vim.api.nvim_create_autocmd("User", {
        group = mf_group,
        pattern = "MiniFilesWindowUpdate",
        callback = function(args)
            local buf_id = args and args.data and args.data.buf_id
            local win_id = args and args.data and args.data.win_id
            if not (buf_id and win_id) then
                return
            end
            vim.schedule(function()
                if not (vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_win_is_valid(win_id)) then
                    return
                end
                local is_prev, clean_path = is_minifiles_preview_buf(buf_id)
                if not is_prev or not clean_path then
                    vim.b[buf_id].hs_image_render_sig = nil
                    Placement.clean(buf_id)
                    return
                end
                if not runtime.supported or not SnacksImg.supports_file(clean_path) then
                    vim.b[buf_id].hs_image_render_sig = nil
                    Placement.clean(buf_id)
                    return
                end
                local uv = uv_lib()
                local st = uv and uv.fs_stat(clean_path) or nil
                if st and st.type == "file" then
                    expand_minifiles_preview_win_height(win_id)
                    local sig = current_buf_render_sig(clean_path)
                    local has_marks = #vim.api.nvim_buf_get_extmarks(buf_id, Placement.ns, 0, -1, { limit = 1 }) > 0
                    if vim.b[buf_id].hs_image_render_sig == sig and has_marks then
                        return
                    end
                    Buf._attach(buf_id, { src = clean_path })
                end
            end)
        end,
    })
    vim.api.nvim_create_autocmd("User", {
        group = mf_group,
        pattern = "MiniFilesExplorerClose",
        callback = function()
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "image" and not vim.b[buf].hs_image_file_src then
                    vim.b[buf].hs_image_render_sig = nil
                    Placement.clean(buf)
                end
            end
        end,
    })
end

local function install_snacks_overrides()
    local SnacksImg = require("snacks.image")
    local Terminal = require("snacks.image.terminal")
    local Placement = require("snacks.image.placement")
    local Image = require("snacks.image.image")
    local Inline = require("snacks.image.inline")
    local Doc = require("snacks.image.doc")
    local Buf = require("snacks.image.buf")
    local Util = require("snacks.image.util")

    if Terminal._hs_installed then
        register_minifiles_autocmds()
        return
    end
    Terminal._hs_installed = true

    -- Prevent snacks.image.terminal from ever executing untargeted `tmux set -p allow-passthrough all`
    for _, e in ipairs(Terminal.envs() or {}) do
        if e.name == "tmux" then
            e.setup = nil
        end
    end

    -- Strict terminal write gate: zero escape sequences leave Neovim unless capability is verified
    Terminal.write = function(data)
        if is_headless() or not runtime.supported or not vim.api.nvim_ui_send then
            return
        end
        if runtime.mode == "tmux" then
            data = ("\027Ptmux;" .. data:gsub("\027", "\027\027")) .. "\027\\"
        end
        vim.api.nvim_ui_send(data)
    end

    -- Guard TIOCGWINSZ when xpixel/ypixel are 0 (common on SSH and tmux PTYs before pixel size reports)
    local orig_size = Terminal.size
    Terminal.size = function()
        local s = orig_size()
        if
            not s
            or not (s.cell_width and s.cell_width > 0 and s.cell_width == s.cell_width)
            or not (s.cell_height and s.cell_height > 0 and s.cell_height == s.cell_height)
            or (s.width or 0) <= 0
            or (s.height or 0) <= 0
        then
            local dw, dh = 9, 18
            local cols = math.max(1, vim.o.columns or 80)
            local rows = math.max(1, vim.o.lines or 24)
            return {
                width = cols * dw,
                height = rows * dh,
                columns = cols,
                rows = rows,
                cell_width = dw,
                cell_height = dh,
                scale = dw / 8,
            }
        end
        return s
    end

    -- Guard 0-DPI metadata division in util.fit
    local orig_fit = Util.fit
    Util.fit = function(file, cells, opts)
        if opts and opts.info and opts.info.dpi then
            local dpi_w = tonumber(opts.info.dpi.width) or 0
            local dpi_h = tonumber(opts.info.dpi.height) or 0
            if dpi_w <= 0 or dpi_h <= 0 then
                opts = vim.tbl_extend("force", {}, opts)
                opts.info = vim.tbl_extend("force", {}, opts.info, {
                    dpi = {
                        width = dpi_w > 0 and dpi_w or 72,
                        height = dpi_h > 0 and dpi_h or 72,
                    },
                })
            end
        end
        return orig_fit(file, cells, opts)
    end

    -- Non-blocking Terminal.env() and Terminal.detect(cb) backed by our wire/tmux state machine
    sync_snacks_terminal_state()
    Terminal.env = function()
        if not Terminal._env then
            sync_snacks_terminal_state()
        end
        return Terminal._env
    end

    Terminal.detect = function(cb)
        if is_headless() then
            runtime.probed = true
            runtime.supported = false
            runtime.placeholders = false
            sync_snacks_terminal_state()
            if cb then
                cb(Terminal._terminal)
            end
            return
        end
        if runtime.mode == "tmux" then
            if cb then
                table.insert(S.pending_detect_cbs, cb)
            end
            probe_tmux_capabilities(false)
            return
        end
        if runtime.probed then
            if cb then
                cb(Terminal._terminal)
            end
            return
        end
        if cb then
            table.insert(S.pending_detect_cbs, cb)
        end
    end
    Terminal._detect = Terminal.detect

    -- Track Image instances, skip base64/sleep sends when unsupported, and fix upstream ipairs placement-id bug in Image:del
    local orig_image_new = Image.new
    Image.new = function(src)
        local img = orig_image_new(src)
        if type(img) == "table" and img.id then
            S.tracked_images[img.id] = img
        end
        return img
    end

    local orig_image_send = Image.send
    Image.send = function(self)
        if is_headless() or not runtime.supported then
            self.sent = false
            return
        end
        return orig_image_send(self)
    end

    Image.del = function(self, pid)
        local ids = pid and { pid } or vim.tbl_keys(self.placements or {})
        for _, p_id in ipairs(ids) do
            if self.placements and self.placements[p_id] then
                Terminal.request({ a = "d", d = "i", i = self.id, p = p_id })
                self.placements[p_id] = nil
            end
        end
        if not next(self.placements or {}) then
            Terminal.request({ a = "d", d = "i", i = self.id })
        end
    end

    -- Clamp inline placements to `win_width - textoff` (minus indent padding) without mutating opts permanently
    local orig_placement_state = Placement.state
    Placement.state = function(self)
        if self.opts and self.opts.inline then
            local avail_w = M.compute_inline_max_width(self)
            if avail_w then
                local orig_max_w = self.opts.max_width
                local orig_w = self.opts.width
                self.opts.max_width = orig_max_w and math.min(orig_max_w, avail_w) or avail_w
                if orig_w then
                    self.opts.width = math.min(orig_w, avail_w)
                end
                local ok, st = pcall(orig_placement_state, self)
                self.opts.max_width = orig_max_w
                self.opts.width = orig_w
                if not ok then
                    error(st)
                end
                if st and st.loc and st.loc.width and st.loc.width > avail_w then
                    st.loc.width = avail_w
                end
                return st
            end
        end
        return orig_placement_state(self)
    end

    -- Never fall back to direct cursor-escape rendering if placeholders are unavailable
    Placement.render_fallback = function() end

    -- Stop 80ms progress spinner timers immediately on close or unsupported transitions (prevents infinite VTE timer leak)
    Placement.progress = function(self)
        if self.opts.inline or self.closed or not runtime.supported or self:ready() then
            return
        end
        if not vim.api.nvim_buf_is_valid(self.buf) then
            return
        end
        vim.bo[self.buf].modifiable = true
        vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, {})
        vim.bo[self.buf].modifiable = false
        local uv = uv_lib()
        local timer = (uv and uv.new_timer) and uv.new_timer() or nil
        if not timer then
            return
        end
        self._hs_progress_timer = timer
        local ok_u, SnacksUtil = pcall(require, "snacks.util")
        timer:start(
            0,
            80,
            vim.schedule_wrap(function()
                if
                    self.closed
                    or not runtime.supported
                    or self:ready()
                    or self.img:failed()
                    or not vim.api.nvim_buf_is_valid(self.buf)
                then
                    if not timer:is_closing() then
                        timer:stop()
                        timer:close()
                    end
                    self._hs_progress_timer = nil
                    return
                end
                local cur_step = self.img._convert and self.img._convert:current() or nil
                local step_name = (cur_step and cur_step.name) or "image"
                local spin = (ok_u and SnacksUtil and SnacksUtil.spinner) and SnacksUtil.spinner() or "…"
                vim.api.nvim_buf_clear_namespace(self.buf, Placement.ns, 0, -1)
                vim.api.nvim_buf_set_extmark(self.buf, Placement.ns, 0, 0, {
                    virt_text = {
                        { spin, "SnacksImageSpinner" },
                        { " " },
                        { step_name .. " loading …", "SnacksImageLoading" },
                    },
                })
            end)
        )
    end

    local orig_placement_close = Placement.close
    Placement.close = function(self)
        local t = self and self._hs_progress_timer or nil
        if t then
            if not t:is_closing() then
                t:stop()
                t:close()
            end
            self._hs_progress_timer = nil
        end
        return orig_placement_close(self)
    end

    local orig_placement_update = Placement.update
    Placement.update = function(self, ...)
        if not self or self.closed or not runtime.supported then
            return
        end
        return orig_placement_update(self, ...)
    end

    -- Guard async Tree-sitter Doc.find_visible callbacks against firing after a client switch/teardown
    local orig_find_visible = Doc.find_visible
    Doc.find_visible = function(buf, cb)
        if not runtime.supported or not vim.api.nvim_buf_is_valid(buf) then
            return
        end
        local expected_inst = S.active_inlines[buf]
        return orig_find_visible(buf, function(imgs)
            if not runtime.supported or not vim.api.nvim_buf_is_valid(buf) then
                return
            end
            if expected_inst and expected_inst._hs_closed then
                return
            end
            if cb then
                cb(imgs)
            end
        end)
    end

    -- Track Inline instances and make nvim_buf_attach(on_lines) cleanly detachable on client switches
    local orig_inline_new = Inline.new
    Inline.new = function(buf)
        if not runtime.supported then
            return nil
        end
        local prev = S.active_inlines[buf]
        if prev and not prev._hs_closed then
            return prev
        end
        local inst = nil
        local orig_buf_attach = vim.api.nvim_buf_attach
        vim.api.nvim_buf_attach = function(b, send_buf, attach_opts)
            if attach_opts and attach_opts.on_lines then
                local orig_on_lines = attach_opts.on_lines
                attach_opts = vim.tbl_extend("force", {}, attach_opts, {
                    on_lines = function(...)
                        if inst and inst._hs_closed then
                            return true
                        end
                        if not runtime.supported then
                            return
                        end
                        return orig_on_lines(...)
                    end,
                })
            end
            return orig_buf_attach(b, send_buf, attach_opts)
        end
        local ok, res = pcall(orig_inline_new, buf)
        vim.api.nvim_buf_attach = orig_buf_attach
        if not ok then
            error(res)
        end
        inst = res
        local orig_inst_update = inst.update
        inst.update = function(self_inst, ...)
            if self_inst._hs_closed or not runtime.supported then
                return
            end
            return orig_inst_update(self_inst, ...)
        end
        local orig_inst_conceal = inst.conceal
        inst.conceal = function(self_inst, ...)
            if self_inst._hs_closed or not runtime.supported then
                return
            end
            return orig_inst_conceal(self_inst, ...)
        end
        S.active_inlines[buf] = inst
        return inst
    end

    -- Do not permanently latch `snacks_image_attached = true` when terminal is currently unsupported
    Doc._attach = function(buf)
        if not vim.api.nvim_buf_is_valid(buf) then
            return
        end
        if not (SnacksImg.config.doc.inline and runtime.supported and runtime.placeholders) then
            vim.b[buf].snacks_image_attached = nil
            return
        end
        if vim.b[buf].snacks_image_attached and S.active_inlines[buf] and not S.active_inlines[buf]._hs_closed then
            return
        end
        vim.b[buf].snacks_image_attached = true
        Inline.new(buf)
    end

    -- Binary-file safety for `:edit foo.png` and clean line-clearing + dedup for Ghostty/Kitty + mini.files previews
    local orig_buf_attach_inner = Buf._attach
    Buf._attach = function(buf, opts)
        if not vim.api.nvim_buf_is_valid(buf) then
            return
        end
        opts = opts or {}
        local file = opts.src or vim.api.nvim_buf_get_name(buf)
        if not opts.src and file ~= "" then
            vim.b[buf].hs_image_file_src = file
        end
        local sig = current_buf_render_sig(file)
        if vim.b[buf].hs_image_render_sig == sig then
            if runtime.supported then
                local has_marks = #vim.api.nvim_buf_get_extmarks(buf, Placement.ns, 0, -1, { limit = 1 }) > 0
                if has_marks then
                    return
                end
            elseif vim.bo[buf].filetype == "markdown" then
                return
            end
        end
        vim.b[buf].hs_image_render_sig = sig
        if SnacksImg.supports(file) then
            Placement.clean(buf)
            vim.bo[buf].modifiable = true
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
            vim.bo[buf].modifiable = false
            vim.bo[buf].modified = false
        end
        return orig_buf_attach_inner(buf, opts)
    end

    local orig_buf_attach_entry = Buf.attach
    Buf.attach = function(buf, opts)
        if vim.api.nvim_buf_is_valid(buf) then
            local bname = (opts and opts.src) or vim.api.nvim_buf_get_name(buf)
            if not (opts and opts.src) and bname ~= "" then
                vim.b[buf].hs_image_file_src = bname
            end
            vim.b[buf].hs_image_render_sig = nil
            vim.bo[buf].modifiable = false
            vim.bo[buf].modified = false
            vim.bo[buf].swapfile = false
        end
        return orig_buf_attach_entry(buf, opts)
    end

    SnacksImg.setup()
    register_minifiles_autocmds()
end

local function register_lifecycle_autocmds(trigger_initial)
    if is_headless() then
        return
    end
    local life_group = vim.api.nvim_create_augroup("SolarizedImageLifecycle", { clear = true })
    if runtime.mode == "tmux" then
        vim.api.nvim_create_autocmd({ "FocusGained", "VimResized" }, {
            group = life_group,
            callback = function()
                probe_tmux_capabilities(true)
            end,
        })
        vim.api.nvim_create_autocmd("BufWinEnter", {
            group = life_group,
            callback = function()
                probe_tmux_capabilities(false)
            end,
        })
        if trigger_initial then
            if vim.v.vim_did_enter == 1 then
                probe_tmux_capabilities(true)
            else
                vim.api.nvim_create_autocmd("UIEnter", {
                    group = life_group,
                    once = true,
                    callback = function()
                        probe_tmux_capabilities(true)
                    end,
                })
            end
        end
    elseif trigger_initial then
        if vim.v.vim_did_enter == 1 then
            start_standalone_wire_probe()
        else
            vim.api.nvim_create_autocmd("UIEnter", {
                group = life_group,
                once = true,
                callback = start_standalone_wire_probe,
            })
        end
    end
end

function M.refresh()
    if runtime.mode == "tmux" and not is_headless() then
        probe_tmux_capabilities(true)
    end
end

function M.on_reload()
    _G.refresh_home_settings_images = M.refresh
    if S.installed then
        register_minifiles_autocmds()
        register_lifecycle_autocmds(false)
    end
end

function M.state()
    return vim.deepcopy(runtime)
end

function M.install()
    _G.refresh_home_settings_images = M.refresh
    local headless = is_headless()
    local has_tmux = not headless and ((vim.env.TMUX or "") ~= "")
    if not has_tmux then
        vim.env.SNACKS_TMUX = "false"
    end

    if S.installed then
        M.on_reload()
        return
    end
    S.installed = true

    runtime.mode = headless and "headless" or (has_tmux and "tmux" or "standalone")
    runtime.remote = has_ssh_env()
    runtime.supported = false
    runtime.placeholders = false
    runtime.probed = headless
    runtime.term_name = headless and "headless" or "unknown"
    runtime.clients_key = ""
    runtime.state = headless and "headless" or "init"

    install_snacks_overrides()
    register_lifecycle_autocmds(true)
end

function M.plugin_spec()
    if is_headless() or (vim.env.TMUX or "") == "" then
        vim.env.SNACKS_TMUX = "false"
    end

    local opts = {
        image = {
            enabled = true,
            force = false,
            resolve = M.resolve_doc_image,
            doc = {
                enabled = true,
                inline = true,
                float = false,
                max_width = 80,
                max_height = 40,
                auto_resize = true,
            },
            convert = {
                notify = false,
            },
            math = {
                enabled = false,
            },
        },
    }
    for _, mod_name in ipairs(DISABLED_SNACKS_MODULES) do
        opts[mod_name] = { enabled = false }
    end

    return {
        "folke/snacks.nvim",
        lazy = false,
        priority = 1000,
        opts = opts,
        config = function(_, resolved_opts)
            if is_headless() or (vim.env.TMUX or "") == "" then
                vim.env.SNACKS_TMUX = "false"
            end
            local ok, snacks = pcall(require, "snacks")
            if not ok or not snacks then
                return
            end
            snacks.setup(resolved_opts)
            pcall(vim.api.nvim_clear_autocmds, {
                group = "snacks",
                event = "BufReadCmd",
                pattern = "gh://*",
            })
            M.install()
        end,
    }
end

return M
