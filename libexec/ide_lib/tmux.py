"""Tmux IPC, exact session/pane targeting, SSH/display sync, browser opener, and clipboard."""

from __future__ import annotations

import os
import subprocess
import sys

from ide_lib.constants import (
    TMUX_SEP,
    is_live_socket,
    is_socket_path,
    is_switcher_session_name,
    read_switcher_result,
    resolve_mise_tool_bin,
    safe_getcwd,
    sanitize_http_url,
    sanitize_name_token,
    which_executable,
    write_switcher_result,
)
from ide_lib.hooks import sanitize_session_name
from ide_lib.proc import (
    discover_pane_nvim_sockets,
    is_bare_shell_cmd,
    pane_has_child_procs,
    pane_tree_pids,
    pids_with_children,
)

__all__ = [
    "TMUX_THEME_V2_HEADER",
    "check_is_ide_session",
    "copy_to_system_clipboard",
    "current_ide_session",
    "discover_display_env",
    "discover_pane_nvim_sockets",
    "ensure_server_tmux_conf",
    "get_ide_var",
    "is_bare_shell_cmd",
    "is_ide_session_meta",
    "is_ssh_session",
    "is_switcher_session_name",
    "is_v2_tmux_theme_conf",
    "missing_session_msg",
    "most_recent_client",
    "normalize_pane_cwd",
    "notify_session_editor_images",
    "open_browser_url",
    "pane_exists",
    "pane_has_child_procs",
    "pane_in_win",
    "pane_is_parked",
    "pane_tree_pids",
    "paste_from_system_clipboard",
    "pids_with_children",
    "read_switcher_result",
    "resolve_active_client",
    "resolve_main_win",
    "resolve_role_pane",
    "resolve_switcher_context",
    "resolve_target_session",
    "run_tmux",
    "session_exists",
    "session_has_focused_client",
    "set_allow_tmux_env_fallback",
    "set_ide_var",
    "set_ide_vars",
    "tmux_conf_disk_version",
    "tmux_out",
    "window_exists",
    "write_switcher_result",
]

_ALLOW_TMUX_ENV_FALLBACK = False


def _is_popup_session_name(sess_name: str) -> bool:
    return sess_name.startswith(("ai-", "agy-"))


def set_allow_tmux_env_fallback(enabled: bool) -> None:
    """Allow SSH and display discovery to inspect tmux environment without `$TMUX`."""
    global _ALLOW_TMUX_ENV_FALLBACK
    _ALLOW_TMUX_ENV_FALLBACK = enabled


def run_tmux(*args: str, input_bytes: bytes | None = None) -> subprocess.CompletedProcess:
    """Invoke `tmux` with stdin closed (or `input_bytes`) and stderr suppressed."""
    if input_bytes is not None:
        return subprocess.run(
            ["tmux", *args],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    return subprocess.run(
        ["tmux", *args],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )


def tmux_out(*args: str) -> str:
    """Invoke `tmux` and return stdout stripped of trailing CR/LF."""
    res = run_tmux(*args)
    return (res.stdout or "").rstrip("\r\n") if isinstance(res.stdout, str) else ""


def session_exists(sess: str) -> bool:
    """Return True if an exact tmux session `=sess` exists."""
    return bool(sess) and run_tmux("has-session", "-t", f"={sess}").returncode == 0


def missing_session_msg(sess: str) -> str:
    """Format a user-facing diagnostic for a missing or unspecified IDE session."""
    if sess:
        return f"No active IDE session named '{sess}'."
    return "Not inside an ide session (pass a session name, such as 'ide quit <session>')."


def is_ide_session_meta(sess_name: str, ide_sess: str, ide_sock: str, ide_win: str) -> bool:
    """Return True when tmux session metadata marks a managed IDE workspace (never `ai-*`/`agy-*` popups)."""
    if not sess_name or _is_popup_session_name(sess_name):
        return False
    return bool(ide_sess or ide_sock or ide_win or sess_name.startswith("ide-"))


def check_is_ide_session(sess: str) -> bool:
    """Query tmux to confirm `sess` is a live `ide`-managed workspace session."""
    if not sess or _is_popup_session_name(sess):
        return False
    info = tmux_out(
        "display-message",
        "-p",
        "-t",
        f"={sess}:",
        TMUX_SEP.join(["#{session_name}", "#{@ide_session}", "#{@ide_socket}", "#{@ide_main_win}"]),
    )
    if not info or TMUX_SEP not in info:
        return False
    parts = (info.split(TMUX_SEP) + ["", "", "", ""])[:4]
    return is_ide_session_meta(parts[0], parts[1], parts[2], parts[3])


def resolve_switcher_context(sw_sess: str) -> tuple[str, str, str]:
    """Return `(active_sess, outer_client, result_file)` for switcher session `sw_sess`."""
    if not is_switcher_session_name(sw_sess):
        return ("", "", "")
    raw = tmux_out(
        "display-message",
        "-p",
        "-t",
        f"={sw_sess}:",
        TMUX_SEP.join(["#{@ide_sw_docked_sess}", "#{@ide_sw_selected_sess}", "#{@ide_sw_client}", "#{@ide_sw_result_file}"]),
    )
    if not raw or TMUX_SEP not in raw:
        return ("", "", "")
    ds, sel_s, cl, rf = (raw.split(TMUX_SEP) + ["", "", "", ""])[:4]
    return (ds.strip() or sel_s.strip(), cl.strip(), rf.strip())


def current_ide_session() -> str:
    """Resolve the caller's exact IDE session via `$TMUX_PANE` or `$TMUX` server PID & session ID."""
    tmux_env = os.environ.get("TMUX", "")
    if not tmux_env:
        return ""
    parts = tmux_env.split(",")
    if len(parts) < 3:
        return ""
    server_pid = parts[-2]
    last_part = parts[-1].lstrip("$")
    tmux_pane = os.environ.get("TMUX_PANE", "")
    target = tmux_pane if tmux_pane else (f"${last_part}" if last_part else "")
    if not target:
        return ""
    found = tmux_out(
        "display-message",
        "-p",
        "-t",
        target,
        TMUX_SEP.join([
            "#{pid}",
            "#{session_name}",
            "#{@ide_session}",
            "#{@ide_socket}",
            "#{@ide_main_win}",
            "#{@ide_owner_sess}",
            "#{@ide_sw_docked_sess}",
            "#{@ide_sw_selected_sess}",
        ]),
    )
    if not found or TMUX_SEP not in found:
        return ""
    fparts = (found.split(TMUX_SEP) + [""] * 8)[:8]
    pid, sess_name, ide_sess, ide_sock, ide_win, owner_sess, sw_docked_sess, sw_sel_sess = fparts
    if pid != server_pid:
        return ""
    if is_ide_session_meta(sess_name, ide_sess, ide_sock, ide_win):
        return sess_name
    if is_switcher_session_name(sess_name):
        for cand_s in (owner_sess.strip(), sw_docked_sess.strip(), sw_sel_sess.strip()):
            if cand_s and check_is_ide_session(cand_s):
                return cand_s
    return ""


def resolve_target_session(arg: str = "") -> str:
    """Resolve an explicit session/directory token or infer the caller's session without guessing."""
    if arg.startswith("#{") and arg.endswith("}"):
        arg = ""
    if arg:
        if is_switcher_session_name(arg):
            docked_s, _, _ = resolve_switcher_context(arg)
            return docked_s
        is_dir = os.path.isdir(arg)
        if not is_dir and sanitize_name_token(arg) == arg:
            return arg
        if session_exists(arg):
            return arg
        if is_dir:
            return sanitize_session_name(os.path.abspath(arg))
        return sanitize_name_token(arg)
    if os.environ.get("TMUX"):
        return current_ide_session()
    return sanitize_session_name(safe_getcwd())


def get_ide_var(sess: str, opt_name: str, env_name: str) -> str:
    """Read an IDE workspace setting from `@ide_*` user option with session environment fallback."""
    val = tmux_out("show-options", "-qv", "-t", f"={sess}:", opt_name)
    if not val:
        env_line = tmux_out("show-environment", "-t", f"={sess}", env_name)
        prefix = f"{env_name}="
        if env_line.startswith(prefix):
            val = env_line[len(prefix):]
    return val


def set_ide_var(sess: str, opt_name: str, env_name: str, val: str) -> None:
    """Atomically persist an IDE workspace setting to both `@ide_*` option and session environment."""
    run_tmux(
        "set-option", "-q", "-t", f"={sess}:", opt_name, val,
        ";",
        "set-environment", "-t", f"={sess}", env_name, val,
    )


def set_ide_vars(sess: str, pairs: list[tuple[str, str, str]]) -> None:
    """Batch-set multiple `(opt_name, env_name, val)` pairs in a single tmux invocation."""
    if not pairs:
        return
    cmd: list[str] = []
    for opt_name, env_name, val in pairs:
        if cmd:
            cmd.append(";")
        cmd.extend([
            "set-option", "-q", "-t", f"={sess}:", opt_name, val,
            ";",
            "set-environment", "-t", f"={sess}", env_name, val,
        ])
    run_tmux(*cmd)


def normalize_pane_cwd(
    raw_cwd: str,
    sess: str = "",
    target_arg: str = "",
    workdir_hint: str = "",
    init_root_hint: str = "",
) -> str:
    """Resolve `raw_cwd` or remap a detached FUSE/network mount path onto live workspace anchors."""
    if raw_cwd and os.path.isdir(raw_cwd):
        return raw_cwd
    if not sess and (os.environ.get("TMUX") or target_arg):
        sess = resolve_target_session(target_arg)
    workdir = workdir_hint
    init_root = init_root_hint
    if sess and (not workdir or not init_root) and session_exists(sess):
        if not workdir:
            workdir = get_ide_var(sess, "@ide_workdir", "IDE_WORKDIR")
        if not init_root:
            init_root = get_ide_var(sess, "@ide_initial_root", "IDE_INITIAL_ROOT")
    workdir = workdir or os.environ.get("IDE_WORKDIR") or ""
    init_root = init_root or os.environ.get("IDE_INITIAL_ROOT") or ""
    anchors = [a.rstrip("/") for a in (workdir, init_root, os.environ.get("PWD") or "") if a and os.path.isdir(a)]
    clean_raw = raw_cwd.rstrip("/") if raw_cwd else ""
    if clean_raw.startswith("/"):
        for anc in anchors:
            if anc.endswith(clean_raw):
                return anc
            cur = os.path.dirname(clean_raw)
            while cur and cur != "/":
                if anc.endswith(cur):
                    cand = anc + clean_raw[len(cur):]
                    if os.path.isdir(cand):
                        return cand
                cur = os.path.dirname(cur)
    for anc in anchors:
        return anc
    return safe_getcwd()


def pane_exists(pane: str) -> bool:
    """Return True if pane ID `pane` exists."""
    return bool(pane) and tmux_out("display-message", "-p", "-t", pane, "#{pane_id}") == pane


def window_exists(win: str) -> bool:
    """Return True if window ID `win` exists."""
    return bool(win) and tmux_out("display-message", "-p", "-t", win, "#{window_id}") == win


def pane_in_win(pane: str, win: str) -> bool:
    """Return True if `pane` currently resides inside `win`."""
    return bool(pane) and bool(win) and tmux_out("display-message", "-p", "-t", pane, "#{window_id}") == win


def pane_is_parked(pane: str, win: str) -> bool:
    """Return True if `pane` is alive in a hidden `_ide_park_*` window outside `win` (never `ai-sw-*`)."""
    if not pane or not win:
        return False
    info = tmux_out(
        "display-message",
        "-p",
        "-t",
        pane,
        TMUX_SEP.join(["#{pane_id}", "#{window_id}", "#{session_name}"]),
    )
    parts = info.split(TMUX_SEP)
    if len(parts) < 2:
        return False
    pid, wid = parts[0], parts[1]
    sname = parts[2] if len(parts) > 2 else ""
    return pid == pane and wid != win and not is_switcher_session_name(sname)


def resolve_main_win(sess: str, editor_pane: str = "", ai_pane: str = "", term_pane: str = "") -> str:
    """Locate and record the primary `ide` window ID for `sess`, skipping `_ide_park_*` windows."""
    main_win = get_ide_var(sess, "@ide_main_win", "IDE_MAIN_WIN")
    if window_exists(main_win):
        info0 = tmux_out(
            "display-message",
            "-p",
            "-t",
            main_win,
            TMUX_SEP.join(["#{window_name}", "#{session_name}"]),
        )
        wname0, sname0 = (info0.split(TMUX_SEP, 1) + [""])[:2]
        if not wname0.startswith("_ide_park_") and (not sname0 or sname0 == sess):
            return main_win
    for p in (editor_pane, ai_pane, term_pane):
        if pane_exists(p):
            info = tmux_out(
                "display-message",
                "-p",
                "-t",
                p,
                TMUX_SEP.join(["#{window_id}", "#{window_name}", "#{session_name}"]),
            )
            parts = info.split(TMUX_SEP)
            if len(parts) >= 2:
                wid, wname = parts[0], parts[1]
                sname = parts[2] if len(parts) > 2 else ""
                if wid and not wname.startswith("_ide_park_") and (not sname or sname == sess):
                    set_ide_var(sess, "@ide_main_win", "IDE_MAIN_WIN", wid)
                    return wid
    win_lines = tmux_out("list-windows", "-t", f"={sess}", "-F", "#{window_id}\t#{window_name}").splitlines()
    main_win = ""
    for line in win_lines:
        if "\t" in line:
            wid, wname = line.split("\t", 1)
            if not wname.startswith("_ide_park_"):
                main_win = wid
                break
    if not main_win and win_lines:
        main_win = win_lines[0].split("\t", 1)[0]
    if main_win:
        set_ide_var(sess, "@ide_main_win", "IDE_MAIN_WIN", main_win)
    return main_win


def resolve_role_pane(sess: str, role: str, opt_name: str, env_name: str) -> str:
    """Resolve the pane ID for `role` (`ai`, `editor`, `term`), healing stale option references."""
    pane = get_ide_var(sess, opt_name, env_name)
    if not pane_exists(pane):
        pane = ""
        for line in tmux_out("list-panes", "-s", "-t", f"={sess}:", "-F", "#{pane_id}\t#{@ide_role}").splitlines():
            if "\t" in line:
                pid, prole = line.split("\t", 1)
                if prole == role:
                    pane = pid
                    break
        if not pane and role == "ai":
            docked_in = tmux_out("show-options", "-qv", "-t", f"={sess}:", "@ide_docked_in").strip()
            if is_switcher_session_name(docked_in):
                cand_dp = tmux_out("show-options", "-qv", "-t", f"={docked_in}:", "@ide_sw_docked_pane").strip()
                cand_ds = tmux_out("show-options", "-qv", "-t", f"={docked_in}:", "@ide_sw_docked_sess").strip()
                if cand_ds == sess and pane_exists(cand_dp):
                    pane = cand_dp
        if pane:
            set_ide_var(sess, opt_name, env_name, pane)
    return pane


def most_recent_client(target: str) -> str:
    """Return the most recently active tmux client attached to `target`."""
    if not target:
        return ""
    tmux_target = target if target.startswith("$") else f"={target}"
    lines = tmux_out("list-clients", "-t", tmux_target, "-F", "#{client_activity}\t#{client_name}").splitlines()
    best_act = -1
    best_client = ""
    for line in lines:
        parts = line.split("\t", 1)
        if len(parts) == 2 and parts[1].strip():
            act = int(parts[0]) if parts[0].strip().isdigit() else 0
            if act >= best_act:
                best_act = act
                best_client = parts[1].strip()
    return best_client


def resolve_active_client(origin_sess: str = "") -> str:
    """Determine the target tmux client name via `$IDE_CLIENT`, `origin_sess`, or `$TMUX`."""
    ide_client = os.environ.get("IDE_CLIENT", "").strip()
    if ide_client and not ide_client.startswith("#{"):
        return ide_client
    if origin_sess:
        found = most_recent_client(origin_sess)
        if found:
            return found
    tmux_env = os.environ.get("TMUX", "")
    if tmux_env:
        parts = tmux_env.split(",")
        if len(parts) >= 3:
            last_part = parts[-1].lstrip("$")
            if last_part:
                found = most_recent_client(f"${last_part}")
                if found:
                    return found
    cl = tmux_out("display-message", "-p", "#{client_name}").strip()
    return "" if cl.startswith("#{") else cl


def session_has_focused_client(sess: str) -> bool:
    """Return True if at least one OS-focused terminal client is attached to `sess`."""
    if not sess:
        return False
    out = tmux_out("list-clients", "-t", f"={sess}", "-F", "#{client_flags}")
    if not out:
        return False
    if is_switcher_session_name(sess):
        outer_cl = tmux_out("show-options", "-qv", "-t", f"={sess}:", "@ide_sw_client").strip()
        if outer_cl:
            cflags = tmux_out("display-message", "-p", "-c", outer_cl, "#{client_flags}")
            return "focused" in {tok.strip() for tok in cflags.split(",") if tok.strip()}
    for line in out.splitlines():
        flags = {tok.strip() for tok in line.split(",") if tok.strip()}
        if "focused" in flags:
            return True
    return False


def notify_session_editor_images(sess: str) -> None:
    """Trigger capability-gated `refresh_home_settings_images` on `sess`'s Neovim Editor asynchronously."""
    raw_sock = get_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET")
    sock = raw_sock or (f"{os.environ.get('XDG_RUNTIME_DIR') or '/tmp'}/nvim-ide-{sess}.sock" if sess else "")
    nvim_bin = resolve_mise_tool_bin("nvim", install_dir_name="neovim")
    if not sock or not nvim_bin:
        return
    target_srv = ""
    expr = "luaeval('(_G.refresh_home_settings_images and _G.refresh_home_settings_images()) or 0')"
    if is_live_socket(sock):
        target_srv = sock
    else:
        ed_pane = resolve_role_pane(sess, "editor", "@ide_editor_pane", "NVIM_IDE_PANE")
        if ed_pane:
            ed_pid = tmux_out("display-message", "-p", "-t", ed_pane, "#{pane_pid}")
            cands = discover_pane_nvim_sockets(ed_pid, sock_hint=sock)
            if cands:
                sock_parent = os.path.dirname(sock)
                if sock_parent and not os.path.isdir(sock_parent):
                    try:
                        os.makedirs(sock_parent, mode=0o700, exist_ok=True)
                    except OSError:
                        pass
                target_srv = cands[0]
                esc_s = sock.replace("\\", "\\\\").replace("'", "\\'")
                esc_n = sess.replace("\\", "\\\\").replace("'", "\\'")
                lua_fn = (
                    "(function() if #vim.api.nvim_list_uis() > 0 and (vim.env.NVIM or '') == '' then "
                    f"local s='{esc_s}'; local u=vim.uv or vim.loop; local has=false; "
                    "for _,v in ipairs(vim.fn.serverlist()) do if v==s then "
                    "if u and u.fs_stat(s) then has=true else pcall(vim.fn.serverstop,s) end; break end end; "
                    "if not has then "
                    "local st = u and u.fs_stat(s) or nil; "
                    "if st and st.type == 'socket' then pcall(u.fs_unlink, s) end; "
                    "local ok,r=pcall(vim.fn.serverstart,s); has=(ok and r==s) end; "
                    f"if has then vim.env.NVIM_IDE_SOCKET=s; vim.env.IDE_SESSION='{esc_n}' end end; "
                    "return (_G.refresh_home_settings_images and _G.refresh_home_settings_images()) or 0 end)()"
                )
                expr = "luaeval(\"" + lua_fn.replace("\\", "\\\\").replace('"', '\\"') + "\")"
                if not raw_sock:
                    set_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET", sock)
    if not target_srv:
        return
    cmd = [
        nvim_bin,
        "--headless",
        "--server",
        target_srv,
        "--remote-expr",
        expr,
    ]
    timeout_bin = which_executable("timeout")
    if timeout_bin:
        cmd = [timeout_bin, "3", *cmd]
    env = os.environ.copy()
    if not env.get("NVIM_LOG_FILE"):
        env["NVIM_LOG_FILE"] = "/dev/null"
    try:
        subprocess.Popen(
            cmd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


_notify_session_editor_images = notify_session_editor_images


def _infer_env_session() -> str:
    lines = tmux_out("list-clients", "-F", TMUX_SEP.join(["#{client_activity}", "#{session_name}"])).splitlines()
    best_act = -1
    best_sess = ""
    for line in lines:
        parts = line.split(TMUX_SEP, 1)
        if len(parts) == 2 and parts[1].strip():
            cand = parts[1].strip()
            if not _is_popup_session_name(cand):
                act = int(parts[0]) if parts[0].strip().isdigit() else 0
                if act >= best_act:
                    best_act = act
                    best_sess = cand
    if best_sess and session_exists(best_sess):
        return best_sess
    s_lines = tmux_out(
        "list-sessions",
        "-F",
        TMUX_SEP.join([
            "#{session_last_attached}",
            "#{session_activity}",
            "#{session_name}",
            "#{@ide_session}",
            "#{@ide_socket}",
            "#{@ide_main_win}",
        ]),
    ).splitlines()
    best_ts = -1
    for line in s_lines:
        cols = (line.split(TMUX_SEP) + [""] * 6)[:6]
        if is_ide_session_meta(cols[2], cols[3], cols[4], cols[5]):
            la = int(cols[0]) if cols[0].strip().isdigit() else 0
            sa = int(cols[1]) if cols[1].strip().isdigit() else 0
            ts = max(la, sa)
            if ts >= best_ts:
                best_ts = ts
                best_sess = cols[2]
    return best_sess


def _collect_tmux_env_lines(target_arg: str = "") -> list[str]:
    env_lines: list[str] = []
    if target_arg and target_arg.startswith("%"):
        env_lines.extend(tmux_out("show-environment", "-t", target_arg).splitlines())
    else:
        sess = (
            target_arg
            if (target_arg and session_exists(target_arg))
            else (resolve_target_session(target_arg) if target_arg else current_ide_session())
        )
        if not sess and not os.environ.get("TMUX_PANE"):
            sess = _infer_env_session()
        if sess and session_exists(sess):
            env_lines.extend(tmux_out("show-environment", "-t", f"={sess}").splitlines())
        elif os.environ.get("TMUX_PANE"):
            env_lines.extend(tmux_out("show-environment", "-t", os.environ["TMUX_PANE"]).splitlines())
    env_lines.extend(tmux_out("show-environment", "-g").splitlines())
    return env_lines


def is_ssh_session(target_arg: str = "") -> bool:
    """Return True if the caller or target tmux session is running over SSH."""
    for var in ("SSH_CONNECTION", "SSH_TTY", "SSH_CLIENT"):
        if os.environ.get(var):
            return True
    if (os.environ.get("TMUX") or os.environ.get("TMUX_TMPDIR") or _ALLOW_TMUX_ENV_FALLBACK) and which_executable("tmux"):
        env_lines = _collect_tmux_env_lines(target_arg)
        seen_vars: set[str] = set()
        for line in env_lines:
            for var in ("SSH_CONNECTION", "SSH_TTY", "SSH_CLIENT"):
                if var in seen_vars:
                    continue
                if line == f"-{var}":
                    seen_vars.add(var)
                    continue
                prefix = f"{var}="
                if line.startswith(prefix):
                    seen_vars.add(var)
                    if len(line) > len(prefix):
                        return True
    return False


def discover_display_env(target_arg: str = "", ignore_tmux_env: bool = False) -> None:
    """Populate `DISPLAY`, `WAYLAND_DISPLAY`, `XAUTHORITY`, and `DBUS_SESSION_BUS_ADDRESS` on local desktops (never over SSH)."""
    if any(os.environ.get(v) for v in ("SSH_CONNECTION", "SSH_TTY", "SSH_CLIENT")):
        return
    if not ignore_tmux_env and is_ssh_session(target_arg):
        return
    if (
        not ignore_tmux_env
        and (os.environ.get("TMUX") or os.environ.get("TMUX_TMPDIR") or _ALLOW_TMUX_ENV_FALLBACK)
        and which_executable("tmux")
    ):
        env_lines = _collect_tmux_env_lines(target_arg)
        seen_vars: set[str] = set()
        for line in env_lines:
            for var in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS"):
                if var in seen_vars or os.environ.get(var):
                    continue
                prefix = f"{var}="
                if line.startswith(prefix):
                    val = line[len(prefix):]
                    if val:
                        os.environ[var] = val
                        seen_vars.add(var)
    has_explicit_display = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))
    if not has_explicit_display and is_socket_path("/tmp/.X11-unix/X0"):
        os.environ["DISPLAY"] = ":0"
    try:
        uid = os.getuid()
    except AttributeError:
        uid = None
    if uid is not None:
        from pathlib import Path

        run_dir = Path(f"/run/user/{uid}")
        if run_dir.is_dir():
            if not has_explicit_display and not os.environ.get("WAYLAND_DISPLAY") and is_socket_path(run_dir / "wayland-0"):
                os.environ["WAYLAND_DISPLAY"] = "wayland-0"
            if not os.environ.get("DBUS_SESSION_BUS_ADDRESS") and is_socket_path(run_dir / "bus"):
                os.environ["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={run_dir / 'bus'}"
            if os.environ.get("DISPLAY") and not os.environ.get("XAUTHORITY"):
                for auth_cand in sorted(run_dir.glob(".mutter-Xwaylandauth.*")):
                    if auth_cand.is_file():
                        os.environ["XAUTHORITY"] = str(auth_cand)
                        break


def open_browser_url(url: str, target_arg: str = "") -> bool:
    """Open a sanitized `http(s)://` URL in local browser or copy via OSC 52 over SSH."""
    import shlex

    url = sanitize_http_url(url)
    if not url:
        return False
    sess = (
        resolve_target_session(target_arg)
        if (os.environ.get("TMUX") or os.environ.get("TMUX_TMPDIR") or target_arg)
        else ""
    )
    has_tmux = bool(os.environ.get("TMUX")) or (bool(sess) and session_exists(sess))
    ssh_active = is_ssh_session(sess or target_arg)
    if has_tmux and which_executable("tmux"):
        if run_tmux("load-buffer", "-w", "-", input_bytes=url.encode("utf-8")).returncode != 0:
            run_tmux("load-buffer", "-", input_bytes=url.encode("utf-8"))
        if ssh_active:
            msg = f"Copied URL to clipboard (OSC 52): {url}"
            active_cl = resolve_active_client() if (os.environ.get("TMUX") or os.environ.get("IDE_CLIENT")) else ""
            if active_cl and is_switcher_session_name(target_arg):
                run_tmux("display-message", "-c", active_cl, "-d", "4000", msg)
            elif sess and session_exists(sess):
                run_tmux("display-message", "-d", "4000", "-t", f"={sess}:", msg)
            elif os.environ.get("TMUX_PANE"):
                run_tmux("display-message", "-d", "4000", "-t", os.environ["TMUX_PANE"], msg)
    if not ssh_active:
        discover_display_env(sess or target_arg)
    ide_browser = (os.environ.get("IDE_BROWSER") or "").strip()
    if ide_browser:
        parts = [ide_browser] if (os.path.isfile(ide_browser) and os.access(ide_browser, os.X_OK)) else shlex.split(ide_browser)
        if parts and (which_executable(parts[0]) or (os.path.isfile(parts[0]) and os.access(parts[0], os.X_OK))):
            subprocess.Popen(
                [*parts, url],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            return True
    has_display = not ssh_active and bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))
    for browser in (("xdg-open", "google-chrome") if has_display else ()) + (() if ssh_active else ("open",)):
        if which_executable(browser):
            subprocess.Popen(
                [browser, url],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            return True
    return bool(ssh_active and has_tmux)


def copy_to_system_clipboard(target_arg: str = "") -> None:
    """Broadcast `stdin` bytes to tmux OSC 52 buffer and local X11/Wayland/macOS clipboards."""
    import tempfile

    data = sys.stdin.buffer.read()
    with tempfile.NamedTemporaryFile(prefix="ide-clip.", delete=False) as tf:
        tf.write(data)
        tmp_path = tf.name

    def run_clip_in(cmd: list[str]) -> None:
        try:
            with open(tmp_path, "rb") as f_in:
                subprocess.run(
                    cmd,
                    stdin=f_in,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=2,
                    check=False,
                )
        except (OSError, subprocess.SubprocessError):
            pass

    try:
        if which_executable("tmux"):
            if run_tmux("load-buffer", "-w", tmp_path).returncode != 0:
                run_tmux("load-buffer", tmp_path)
        if not is_ssh_session(target_arg):
            if os.environ.get("DISPLAY"):
                if which_executable("xsel"):
                    run_clip_in(["xsel", "-ip"])
                    run_clip_in(["xsel", "-ib"])
                elif which_executable("xclip"):
                    for sel in ("primary", "clipboard"):
                        try:
                            with open(tmp_path, "rb") as fx:
                                subprocess.Popen(
                                    ["xclip", "-selection", sel, "-i"],
                                    stdin=fx,
                                    stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL,
                                    start_new_session=True,
                                )
                        except OSError:
                            pass
            if os.environ.get("WAYLAND_DISPLAY") and which_executable("wl-copy"):
                run_clip_in(["wl-copy", "--primary"])
                run_clip_in(["wl-copy"])
            if which_executable("pbcopy"):
                run_clip_in(["pbcopy"])
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def paste_from_system_clipboard(target_pane: str) -> None:
    """Paste from system clipboard (local desktop) or tmux buffer (SSH) into `target_pane`."""
    raw_target = target_pane or os.environ.get("TMUX_PANE", "")
    if not target_pane:
        target_pane = raw_target
        if not target_pane:
            sess = current_ide_session()
            if sess:
                target_pane = f"={sess}:"
                raw_target = sess
    data = b""

    def try_cmd(cmd: list[str]) -> bytes:
        try:
            res = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=2,
                check=False,
            )
            return res.stdout if res.returncode == 0 and res.stdout else b""
        except (OSError, subprocess.SubprocessError):
            return b""

    ssh_active = is_ssh_session(raw_target)
    has_display = bool(os.environ.get("DISPLAY"))
    if ssh_active and which_executable("tmux"):
        data = try_cmd(["tmux", "show-buffer"])

    if not ssh_active:
        if not data and has_display:
            if which_executable("xsel"):
                data = try_cmd(["xsel", "-ob"]) or try_cmd(["xsel", "-op"])
            if not data and which_executable("xclip"):
                for args in (
                    ["xclip", "-selection", "clipboard", "-t", "UTF8_STRING", "-o"],
                    ["xclip", "-selection", "clipboard", "-o"],
                    ["xclip", "-selection", "primary", "-t", "UTF8_STRING", "-o"],
                    ["xclip", "-selection", "primary", "-o"],
                ):
                    data = try_cmd(args)
                    if data:
                        break
        if not data and os.environ.get("WAYLAND_DISPLAY") and which_executable("wl-paste"):
            def _wl_paste_text(primary: bool) -> bytes:
                p_flag = ["--primary"] if primary else []
                raw_types = try_cmd(["wl-paste", *p_flag, "--list-types"])
                if raw_types:
                    lines = [
                        ln.strip()
                        for ln in raw_types.decode("utf-8", errors="ignore").splitlines()
                        if ln.strip()
                    ]
                    looks_like_mimes = bool(lines) and all(
                        "/" in ln or ln in ("TEXT", "STRING", "UTF8_STRING", "COMPOUND_TEXT")
                        for ln in lines
                    )
                    if looks_like_mimes:
                        preferred = (
                            "text/plain;charset=utf-8",
                            "text/plain",
                            "UTF8_STRING",
                            "TEXT",
                            "STRING",
                        )
                        chosen_mime = next((m for m in preferred if m in lines), "")
                        if not chosen_mime:
                            chosen_mime = next((ln for ln in lines if ln.lower().startswith("text/")), "")
                        if not chosen_mime:
                            return b""
                        return try_cmd(["wl-paste", *p_flag, "--type", chosen_mime, "--no-newline"])
                for mime in ("text/plain;charset=utf-8", "text/plain", "UTF8_STRING"):
                    cand = try_cmd(["wl-paste", *p_flag, "--type", mime, "--no-newline"])
                    if cand:
                        return cand
                cand_fb = try_cmd(["wl-paste", *p_flag, "--no-newline"])
                if cand_fb.startswith((b"\x89PNG\r\n\x1a\n", b"\xff\xd8\xff", b"GIF87a", b"GIF89a")):
                    return b""
                if len(cand_fb) >= 12 and cand_fb[:4] == b"RIFF" and cand_fb[8:12] == b"WEBP":
                    return b""
                return cand_fb

            data = _wl_paste_text(False) or _wl_paste_text(True)
        if not data and which_executable("pbpaste"):
            data = try_cmd(["pbpaste"])
    if not data and which_executable("tmux"):
        data = try_cmd(["tmux", "show-buffer"])

    if data and which_executable("tmux"):
        run_tmux("load-buffer", "-", input_bytes=data)
        if target_pane:
            if tmux_out("display-message", "-p", "-t", target_pane, "#{pane_in_mode}") == "1":
                run_tmux("copy-mode", "-q", "-t", target_pane)
            run_tmux("paste-buffer", "-p", "-t", target_pane)


TMUX_THEME_V2_HEADER = "# tmux-theme-v2"


def tmux_conf_disk_version(path: str = "") -> str:
    """Return `ino:mtime_ns:size` fingerprint for `~/.tmux.conf` (following symlinks), or `""` if absent."""
    target = path or os.path.expanduser("~/.tmux.conf")
    try:
        st = os.stat(target)
    except OSError:
        return ""
    return f"{st.st_ino}:{st.st_mtime_ns}:{st.st_size}"


def is_v2_tmux_theme_conf(path: str) -> bool:
    """Return True iff `path` is a readable file starting with `# tmux-theme-v2`."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.readline().rstrip("\r\n") == TMUX_THEME_V2_HEADER
    except OSError:
        return False


def _read_persisted_theme_id(active_theme_file: str) -> str:
    try:
        with open(active_theme_file, "r", encoding="utf-8") as fh:
            for line in fh:
                s = line.strip()
                if s.startswith("THEME_ID="):
                    return s.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError:
        return ""
    return ""


def _resolve_theme_bin(ide_self: str = "") -> str:
    cands: list[str] = []
    if ide_self:
        cands.append(os.path.join(os.path.dirname(os.path.abspath(ide_self)), "theme"))
    env_self = os.environ.get("IDE_SELF") or ""
    if env_self:
        cands.append(os.path.join(os.path.dirname(os.path.abspath(env_self)), "theme"))
    cands.append(os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "bin", "theme"))
    for cand in cands:
        if cand and os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return which_executable("theme") or ""


def ensure_server_tmux_conf(
    *,
    already_loaded: bool | None = None,
    loaded_ver: str | None = None,
    force_reload: bool = False,
    force_theme: bool = False,
    regen_theme: bool = False,
    ide_self: str = "",
) -> None:
    """Ensure the active Tmux server has sourced the current `~/.tmux.conf` and v2 `tmux-theme.conf`."""
    tmux_conf = os.path.expanduser("~/.tmux.conf")
    disk_ver = tmux_conf_disk_version(tmux_conf)

    if not force_reload and (already_loaded is None or (disk_ver and loaded_ver is None)):
        raw_state = tmux_out(
            "display-message",
            "-p",
            f"#{{@ide_tmux_conf_loaded}}{TMUX_SEP}#{{@ide_tmux_conf_ver}}",
        )
        l_flag, l_ver = (raw_state.split(TMUX_SEP) + ["", ""])[:2]
        if already_loaded is None:
            already_loaded = l_flag.strip() == "1"
        if loaded_ver is None:
            loaded_ver = l_ver.strip()

    need_source_conf = False
    if force_reload:
        need_source_conf = os.path.isfile(tmux_conf)
    elif disk_ver:
        if not already_loaded or (loaded_ver or "") != disk_ver:
            need_source_conf = True
    elif not already_loaded and os.path.isfile(tmux_conf):
        need_source_conf = True

    if need_source_conf:
        if disk_ver:
            run_tmux("source-file", tmux_conf, ";", "set-option", "-gq", "@ide_tmux_conf_ver", disk_ver)
        else:
            run_tmux("source-file", tmux_conf)

    xdg_cfg = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    hs_dir = os.path.join(xdg_cfg, "home-settings")
    active_theme_file = os.path.join(hs_dir, "active-theme.theme")
    tmux_theme_conf = os.path.join(hs_dir, "tmux-theme.conf")
    migrated_v2 = False

    if os.path.isfile(active_theme_file):
        theme_id = _read_persisted_theme_id(active_theme_file)
        repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        repo_gt_kb = os.path.join(repo_root, "dotfiles", ".config", "ghostty", "keybinds.conf")
        active_gt_kb = os.path.join(hs_dir, "active", "ghostty", "keybinds.conf")
        needs_v2_upgrade = (
            not is_v2_tmux_theme_conf(tmux_theme_conf)
            or (
                theme_id != "solarized-dark"
                and os.path.isfile(repo_gt_kb)
                and not os.path.isfile(active_gt_kb)
            )
        )
        if theme_id and (regen_theme or needs_v2_upgrade):
            theme_bin = _resolve_theme_bin(ide_self)
            if theme_bin:
                try:
                    up_proc = subprocess.run(
                        [theme_bin, "--set", theme_id, "--no-live"],
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=5,
                        check=False,
                    )
                    migrated_v2 = needs_v2_upgrade and up_proc.returncode == 0
                except (OSError, subprocess.SubprocessError):
                    pass

    if need_source_conf or force_theme or regen_theme or migrated_v2:
        if is_v2_tmux_theme_conf(tmux_theme_conf):
            run_tmux("source-file", tmux_theme_conf)
