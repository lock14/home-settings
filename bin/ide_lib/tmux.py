"""Tmux IPC, exact session/pane targeting, SSH/display sync, clipboard, and process inspection."""

from __future__ import annotations

import getpass
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import sys

from ide_lib.constants import (
    TMUX_SEP,
    is_live_socket,
    is_socket_path,
    safe_getcwd,
    sanitize_http_url,
    sanitize_name_token,
)
from ide_lib.hooks import sanitize_session_name

_ALLOW_TMUX_ENV_FALLBACK = False
_POPUP_SESS_RE = re.compile(r"^(ai|agy)-")
_BARE_SHELL_CMD_RE = re.compile(
    r"^-?(?:(?:ba|z|da|k|mk|a|tc|c|fi)?sh|nu|elvish|xonsh|pwsh)$",
    re.IGNORECASE,
)


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
    return "Not inside an ide session (pass a session name, such as 'ide --quit <dir>')."


def is_ide_session_meta(sess_name: str, ide_sess: str, ide_sock: str, ide_win: str) -> bool:
    """Return True when tmux session metadata marks a managed IDE workspace (never `ai-*`/`agy-*` popups)."""
    if not sess_name or _POPUP_SESS_RE.match(sess_name):
        return False
    return bool(ide_sess or ide_sock or ide_win or sess_name.startswith("ide-"))


def check_is_ide_session(sess: str) -> bool:
    """Query tmux to confirm `sess` is a live `ide`-managed workspace session."""
    if not sess or _POPUP_SESS_RE.match(sess):
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
        TMUX_SEP.join(["#{pid}", "#{session_name}", "#{@ide_session}", "#{@ide_socket}", "#{@ide_main_win}"]),
    )
    if not found or TMUX_SEP not in found:
        return ""
    fparts = (found.split(TMUX_SEP) + ["", "", "", "", ""])[:5]
    pid, sess_name, ide_sess, ide_sock, ide_win = fparts[0], fparts[1], fparts[2], fparts[3], fparts[4]
    if pid != server_pid:
        return ""
    if is_ide_session_meta(sess_name, ide_sess, ide_sock, ide_win):
        return sess_name
    return ""


def resolve_target_session(arg: str = "") -> str:
    """Resolve an explicit session/directory token or infer the caller's session without guessing."""
    if arg.startswith("#{") and arg.endswith("}"):
        arg = ""
    if arg:
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
    """Return True if `pane` is alive in a hidden `_ide_park_*` window outside `win`."""
    if not pane or not win:
        return False
    info = tmux_out("display-message", "-p", "-t", pane, "#{pane_id}\t#{window_id}")
    if "\t" not in info:
        return False
    pid, wid = info.split("\t", 1)
    return pid == pane and wid != win


def resolve_main_win(sess: str, editor_pane: str = "", ai_pane: str = "", term_pane: str = "") -> str:
    """Locate and record the primary `ide` window ID for `sess`, skipping `_ide_park_*` windows."""
    main_win = get_ide_var(sess, "@ide_main_win", "IDE_MAIN_WIN")
    if window_exists(main_win):
        wname = tmux_out("display-message", "-p", "-t", main_win, "#{window_name}")
        if not wname.startswith("_ide_park_"):
            return main_win
    for p in (editor_pane, ai_pane, term_pane):
        if pane_exists(p):
            info = tmux_out("display-message", "-p", "-t", p, "#{window_id}\t#{window_name}")
            if "\t" in info:
                wid, wname = info.split("\t", 1)
                if wid and not wname.startswith("_ide_park_"):
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
    for line in out.splitlines():
        flags = {tok.strip() for tok in line.split(",") if tok.strip()}
        if "focused" in flags:
            return True
    return False


def _notify_session_editor_images(sess: str) -> None:
    raw_sock = get_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET")
    sock = raw_sock or (f"{os.environ.get('XDG_RUNTIME_DIR') or '/tmp'}/nvim-ide-{sess}.sock" if sess else "")
    nvim_bin = shutil.which("nvim")
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
    timeout_bin = shutil.which("timeout")
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


def switch_or_attach_session(target_sess: str, origin_sess: str = "") -> int:
    """Switch the active tmux client (or `exec` `attach-session` outside tmux) to `target_sess`."""
    if not target_sess or not session_exists(target_sess):
        return 1
    run_tmux("set-option", "-q", "-u", "-t", f"={target_sess}:", "@ide_quit_err")
    if os.environ.get("TMUX") or os.environ.get("IDE_CLIENT"):
        ide_client = resolve_active_client(origin_sess)
        if ide_client:
            res = run_tmux("switch-client", "-c", ide_client, "-t", f"={target_sess}")
            if res.returncode == 0:
                _notify_session_editor_images(target_sess)
                return 0
        if os.environ.get("TMUX"):
            res = run_tmux("switch-client", "-t", f"={target_sess}")
            if res.returncode == 0:
                _notify_session_editor_images(target_sess)
            return 0
    if os.environ.get("IDE_NO_ATTACH", "0") == "1" or not (sys.stdin.isatty() and sys.stdout.isatty()):
        return 0
    os.execvp("tmux", ["tmux", "attach-session", "-t", f"={target_sess}"])
    return 0


def _infer_env_session() -> str:
    lines = tmux_out("list-clients", "-F", TMUX_SEP.join(["#{client_activity}", "#{session_name}"])).splitlines()
    best_act = -1
    best_sess = ""
    for line in lines:
        parts = line.split(TMUX_SEP, 1)
        if len(parts) == 2 and parts[1].strip():
            cand = parts[1].strip()
            if not _POPUP_SESS_RE.match(cand):
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
    if (os.environ.get("TMUX") or os.environ.get("TMUX_TMPDIR") or _ALLOW_TMUX_ENV_FALLBACK) and shutil.which("tmux"):
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
        and shutil.which("tmux")
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
    if not os.environ.get("DISPLAY") and is_socket_path("/tmp/.X11-unix/X0"):
        os.environ["DISPLAY"] = ":0"
    try:
        uid = os.getuid()
    except AttributeError:
        uid = None
    if uid is not None:
        run_dir = Path(f"/run/user/{uid}")
        if run_dir.is_dir():
            if not os.environ.get("WAYLAND_DISPLAY") and is_socket_path(run_dir / "wayland-0"):
                os.environ["WAYLAND_DISPLAY"] = "wayland-0"
            if not os.environ.get("DBUS_SESSION_BUS_ADDRESS") and is_socket_path(run_dir / "bus"):
                os.environ["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={run_dir / 'bus'}"
            if not os.environ.get("XAUTHORITY"):
                for auth_cand in sorted(run_dir.glob(".mutter-Xwaylandauth.*")):
                    if auth_cand.is_file():
                        os.environ["XAUTHORITY"] = str(auth_cand)
                        break


def open_browser_url(url: str, target_arg: str = "") -> bool:
    """Open a sanitized `http(s)://` URL in local browser or copy via OSC 52 over SSH."""
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
    if has_tmux and shutil.which("tmux"):
        if run_tmux("load-buffer", "-w", "-", input_bytes=url.encode("utf-8")).returncode != 0:
            run_tmux("load-buffer", "-", input_bytes=url.encode("utf-8"))
        if ssh_active:
            msg = f"Copied URL to clipboard (OSC 52): {url}"
            if sess and session_exists(sess):
                run_tmux("display-message", "-d", "4000", "-t", f"={sess}:", msg)
            elif os.environ.get("TMUX_PANE"):
                run_tmux("display-message", "-d", "4000", "-t", os.environ["TMUX_PANE"], msg)
    if not ssh_active:
        discover_display_env(sess or target_arg)
    ide_browser = (os.environ.get("IDE_BROWSER") or "").strip()
    if ide_browser:
        parts = [ide_browser] if (os.path.isfile(ide_browser) and os.access(ide_browser, os.X_OK)) else shlex.split(ide_browser)
        if parts and (shutil.which(parts[0]) or (os.path.isfile(parts[0]) and os.access(parts[0], os.X_OK))):
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
        if shutil.which(browser):
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
        if shutil.which("tmux"):
            if run_tmux("load-buffer", "-w", tmp_path).returncode != 0:
                run_tmux("load-buffer", tmp_path)
        if not is_ssh_session(target_arg):
            if os.environ.get("DISPLAY"):
                if shutil.which("xsel"):
                    run_clip_in(["xsel", "-ip"])
                    run_clip_in(["xsel", "-ib"])
                elif shutil.which("xclip"):
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
            if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-copy"):
                run_clip_in(["wl-copy", "--primary"])
                run_clip_in(["wl-copy"])
            if shutil.which("pbcopy"):
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
    if ssh_active and shutil.which("tmux"):
        data = try_cmd(["tmux", "show-buffer"])

    if not ssh_active:
        if not data and has_display:
            if shutil.which("xsel"):
                data = try_cmd(["xsel", "-ob"]) or try_cmd(["xsel", "-op"])
            if not data and shutil.which("xclip"):
                for args in (
                    ["xclip", "-selection", "clipboard", "-t", "UTF8_STRING", "-o"],
                    ["xclip", "-selection", "clipboard", "-o"],
                    ["xclip", "-selection", "primary", "-t", "UTF8_STRING", "-o"],
                    ["xclip", "-selection", "primary", "-o"],
                ):
                    data = try_cmd(args)
                    if data:
                        break
        if not data and os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-paste"):
            data = try_cmd(["wl-paste", "--no-newline"]) or try_cmd(["wl-paste", "--primary", "--no-newline"])
        if not data and shutil.which("pbpaste"):
            data = try_cmd(["pbpaste"])
    if not data and shutil.which("tmux"):
        data = try_cmd(["tmux", "show-buffer"])

    if data and shutil.which("tmux"):
        run_tmux("load-buffer", "-", input_bytes=data)
        if target_pane:
            if tmux_out("display-message", "-p", "-t", target_pane, "#{pane_in_mode}") == "1":
                run_tmux("copy-mode", "-q", "-t", target_pane)
            run_tmux("paste-buffer", "-p", "-t", target_pane)


def pids_with_children(pids: set[int]) -> set[int]:
    """Return the subset of `pids` that currently own at least one live child process."""
    if not pids:
        return set()
    found: set[int] = set()
    my_pid = os.getpid()
    if os.path.isfile(f"/proc/{my_pid}/task/{my_pid}/children"):
        for pid in pids:
            task_dir = f"/proc/{pid}/task"
            try:
                tids = os.listdir(task_dir)
            except OSError:
                continue
            for tid in tids:
                try:
                    with open(f"{task_dir}/{tid}/children", "r", encoding="utf-8") as fh:
                        if fh.read().strip():
                            found.add(pid)
                            break
                except OSError:
                    continue
        return found

    if os.path.isfile("/proc/stat"):
        try:
            for entry in os.listdir("/proc"):
                if not entry.isdigit():
                    continue
                try:
                    with open(f"/proc/{entry}/stat", "r", encoding="utf-8", errors="replace") as fh:
                        stat_txt = fh.read()
                except OSError:
                    continue
                rparen = stat_txt.rfind(")")
                if rparen < 0:
                    continue
                fields = stat_txt[rparen + 2:].split(None, 2)
                if len(fields) >= 2 and fields[1].isdigit():
                    ppid = int(fields[1])
                    if ppid in pids:
                        found.add(ppid)
                        if len(found) == len(pids):
                            break
            return found
        except OSError:
            pass

    ps_bin = shutil.which("ps") or ("/bin/ps" if os.path.isfile("/bin/ps") else "ps")
    try:
        res = subprocess.run(
            [ps_bin, "-eo", "ppid="],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=2.0,
            check=False,
        )
        if res.returncode == 0 and res.stdout:
            for tok in res.stdout.split():
                if tok.isdigit():
                    ppid = int(tok)
                    if ppid in pids:
                        found.add(ppid)
    except (OSError, subprocess.SubprocessError):
        pass
    return found


def is_bare_shell_cmd(cmd: str) -> bool:
    """Return True if `cmd` names an interactive shell rather than a direct foreground binary."""
    s = os.path.basename(cmd.strip())
    return not s or bool(_BARE_SHELL_CMD_RE.match(s))


def pane_has_child_procs(pane_pid: str, pane_cmd: str = "") -> bool:
    """Return True if an AI pane is running a foreground CLI (either via `exec` or child process)."""
    p = pane_pid.strip()
    if not p.isdigit():
        return False
    pid = int(p)
    if pid <= 0:
        return False
    if pane_cmd.strip() and not is_bare_shell_cmd(pane_cmd):
        return True
    return pid in pids_with_children({pid})


def _read_proc_state_and_ppid(pid: int) -> tuple[str, str, int]:
    try:
        with open(f"/proc/{pid}/stat", "r", encoding="utf-8", errors="replace") as fh:
            stat_txt = fh.read()
    except OSError:
        return ("", "", 0)
    lparen = stat_txt.find("(")
    rparen = stat_txt.rfind(")")
    if lparen < 0 or rparen < lparen:
        return ("", "", 0)
    comm = stat_txt[lparen + 1:rparen]
    fields = stat_txt[rparen + 2:].split(None, 2)
    if not fields:
        return (comm, "", 0)
    st_ch = fields[0]
    ppid = int(fields[1]) if len(fields) >= 2 and fields[1].isdigit() else 0
    return (comm, st_ch, ppid)


def _pane_tree_snapshot(
    pane_pid: str,
    max_pids: int = 64,
) -> tuple[list[int], dict[int, int], dict[int, str], dict[int, str]]:
    p = pane_pid.strip()
    if not p.isdigit():
        return ([], {}, {}, {})
    root = int(p)
    if root <= 0:
        return ([], {}, {}, {})
    parent_by_pid: dict[int, int] = {}
    state_by_pid: dict[int, str] = {}
    comm_by_pid: dict[int, str] = {}
    my_pid = os.getpid()
    if os.path.isfile(f"/proc/{my_pid}/task/{my_pid}/children"):
        order = [root]
        seen = {root}
        cm0, st0, _ = _read_proc_state_and_ppid(root)
        if cm0:
            comm_by_pid[root] = cm0
        if st0:
            state_by_pid[root] = st0
        idx = 0
        while idx < len(order) and len(order) < max_pids:
            cur = order[idx]
            idx += 1
            task_dir = f"/proc/{cur}/task"
            try:
                tids = sorted(os.listdir(task_dir))
            except OSError:
                continue
            for tid in tids:
                try:
                    with open(f"{task_dir}/{tid}/children", "r", encoding="utf-8") as fh:
                        raw_children = fh.read().split()
                except OSError:
                    continue
                for tok in raw_children:
                    if tok.isdigit():
                        cpid = int(tok)
                        if cpid > 0 and cpid not in seen:
                            seen.add(cpid)
                            parent_by_pid[cpid] = cur
                            cmc, stc, _ = _read_proc_state_and_ppid(cpid)
                            if cmc:
                                comm_by_pid[cpid] = cmc
                            if stc:
                                state_by_pid[cpid] = stc
                            order.append(cpid)
                            if len(order) >= max_pids:
                                break
                if len(order) >= max_pids:
                    break
        return (order, parent_by_pid, state_by_pid, comm_by_pid)

    children_by_ppid: dict[int, list[int]] = {}
    if os.path.isfile("/proc/stat"):
        try:
            for entry in os.listdir("/proc"):
                if not entry.isdigit():
                    continue
                cpid = int(entry)
                cm_ch, st_ch, ppid = _read_proc_state_and_ppid(cpid)
                if cm_ch:
                    comm_by_pid[cpid] = cm_ch
                if st_ch:
                    state_by_pid[cpid] = st_ch
                if ppid > 0:
                    children_by_ppid.setdefault(ppid, []).append(cpid)
        except OSError:
            children_by_ppid.clear()
            state_by_pid.clear()
            comm_by_pid.clear()

    if not children_by_ppid:
        ps_bin = shutil.which("ps") or ("/bin/ps" if os.path.isfile("/bin/ps") else "ps")
        try:
            res = subprocess.run(
                [ps_bin, "-eo", "pid=,ppid=,stat=,comm="],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=2.0,
                check=False,
            )
            if res.returncode != 0 or not res.stdout:
                res = subprocess.run(
                    [ps_bin, "-eo", "pid=,ppid="],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                    timeout=2.0,
                    check=False,
                )
            if res.returncode == 0 and res.stdout:
                for line in res.stdout.splitlines():
                    parts = line.split(None, 3)
                    if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
                        cpid = int(parts[0])
                        ppid = int(parts[1])
                        children_by_ppid.setdefault(ppid, []).append(cpid)
                        if len(parts) >= 3:
                            state_by_pid[cpid] = parts[2]
                        if len(parts) >= 4:
                            comm_by_pid[cpid] = os.path.basename(parts[3].strip())
        except (OSError, subprocess.SubprocessError):
            pass

    order = [root]
    seen = {root}
    idx = 0
    while idx < len(order) and len(order) < max_pids:
        cur = order[idx]
        idx += 1
        for cpid in sorted(children_by_ppid.get(cur, ())):
            if cpid > 0 and cpid not in seen:
                seen.add(cpid)
                parent_by_pid[cpid] = cur
                order.append(cpid)
                if len(order) >= max_pids:
                    break
    return (order, parent_by_pid, state_by_pid, comm_by_pid)


def pane_tree_pids(pane_pid: str, max_pids: int = 64) -> list[int]:
    """Return `[root_pid, ...]` in breadth-first descendant order for `pane_pid`."""
    return _pane_tree_snapshot(pane_pid, max_pids=max_pids)[0]


def _read_proc_nvim_env(pid: int) -> tuple[str, str, str]:
    try:
        with open(f"/proc/{pid}/environ", "rb") as fh:
            raw = fh.read(262144)
    except OSError:
        return ("", "", "")
    listen_addr = ""
    xdg_rt = ""
    tmpdir = ""
    for entry in raw.split(b"\x00"):
        if entry.startswith(b"NVIM_LISTEN_ADDRESS="):
            listen_addr = entry[20:].decode("utf-8", errors="surrogateescape").strip()
        elif entry.startswith(b"XDG_RUNTIME_DIR="):
            xdg_rt = entry[16:].decode("utf-8", errors="surrogateescape").strip()
        elif entry.startswith(b"TMPDIR="):
            tmpdir = entry[7:].decode("utf-8", errors="surrogateescape").strip()
    return (listen_addr, xdg_rt, tmpdir)


def _read_proc_nvim_cmdline(pid: int) -> tuple[bool, list[str]]:
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            raw = fh.read(65536)
    except OSError:
        return (False, [])
    if not raw:
        return (False, [])
    args = [tok.decode("utf-8", errors="surrogateescape") for tok in raw.split(b"\x00") if tok]
    is_headless = "--headless" in args
    listen_paths: list[str] = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--":
            break
        if arg == "--listen" and i + 1 < len(args):
            val = args[i + 1].strip()
            if val.startswith("/"):
                listen_paths.append(val)
            i += 2
            continue
        if arg.startswith("--listen="):
            val = arg[9:].strip()
            if val.startswith("/"):
                listen_paths.append(val)
        i += 1
    return (is_headless, listen_paths)


def _is_stopped_or_zombie_state(st: str) -> bool:
    return bool(st) and st[0] in ("T", "t", "Z", "X")


def _is_nvim_comm_name(comm: str) -> bool:
    base = os.path.basename(comm)
    return base == "nvim" or base.startswith("nvim.") or base.startswith("nvim-")


def discover_pane_nvim_sockets(pane_pid: str, sock_hint: str = "") -> list[str]:
    """Discover live ephemeral Neovim sockets belonging to processes inside `pane_pid`'s tree."""
    raw_pids, parent_by_pid, state_by_pid, comm_by_pid = _pane_tree_snapshot(pane_pid)
    if not raw_pids:
        return []

    cmdline_by_pid: dict[int, tuple[bool, list[str]]] = {}
    ranked: list[tuple[int, int, int, int]] = []
    for bfs_idx, cpid in enumerate(raw_pids):
        if _is_stopped_or_zombie_state(state_by_pid.get(cpid, "")):
            continue
        stopped_anc = False
        nested_under_nvim = False
        imm_parent = parent_by_pid.get(cpid)
        anc = imm_parent
        seen_anc: set[int] = set()
        while anc is not None and anc not in seen_anc:
            seen_anc.add(anc)
            if _is_stopped_or_zombie_state(state_by_pid.get(anc, "")):
                stopped_anc = True
            if anc != imm_parent and _is_nvim_comm_name(comm_by_pid.get(anc, "")):
                nested_under_nvim = True
                break
            anc = parent_by_pid.get(anc)
        if nested_under_nvim:
            continue
        is_headless, lpaths = _read_proc_nvim_cmdline(cpid)
        cmdline_by_pid[cpid] = (is_headless, lpaths)
        ranked.append((1 if is_headless else 0, 1 if stopped_anc else 0, bfs_idx, cpid))

    if not ranked:
        return []
    ranked.sort()
    pids = [item[3] for item in ranked]

    try:
        uid: int | None = os.getuid()
    except AttributeError:
        uid = None
    try:
        nvim_user = os.environ.get("USER", "").strip() or getpass.getuser()
    except Exception:
        nvim_user = ""

    excl_abs = os.path.abspath(sock_hint) if sock_hint else ""
    excl_real = os.path.realpath(sock_hint) if sock_hint else ""
    excl_inode: tuple[int, int] | None = None
    if sock_hint:
        try:
            hst = os.stat(sock_hint)
            excl_inode = (hst.st_dev, hst.st_ino)
        except OSError:
            excl_inode = None
    sock_dir = os.path.dirname(excl_abs) if excl_abs else ""
    sock_real_dir = os.path.dirname(excl_real) if excl_real else ""
    env_xdg_rt = os.environ.get("XDG_RUNTIME_DIR", "").strip()
    env_tmp = os.environ.get("TMPDIR", "").strip()
    darwin_tmp = ""
    if hasattr(os, "confstr"):
        try:
            darwin_tmp = (os.confstr("CS_DARWIN_USER_TEMP_DIR") or "").strip()
        except (ValueError, OSError):
            darwin_tmp = ""
    run_uid_dir = f"/run/user/{uid}" if uid is not None else ""

    found: list[str] = []
    seen_paths: set[str] = set()
    seen_inodes: set[tuple[int, int]] = set()

    def _accept(cand_raw: str) -> None:
        if not cand_raw or ":" in os.path.basename(cand_raw):
            return
        cand_abs = os.path.abspath(cand_raw)
        cand_real = os.path.realpath(cand_raw)
        if cand_abs in (excl_abs, excl_real) or cand_real in (excl_abs, excl_real):
            return
        if cand_real in seen_paths or cand_abs in seen_paths:
            return
        try:
            st = os.stat(cand_raw)
        except OSError:
            return
        if not stat.S_ISSOCK(st.st_mode):
            return
        if uid is not None and st.st_uid != uid:
            return
        ino_key = (st.st_dev, st.st_ino)
        if excl_inode is not None and ino_key == excl_inode:
            return
        if ino_key in seen_inodes:
            return
        if not is_live_socket(cand_raw):
            return
        seen_paths.add(cand_real)
        seen_paths.add(cand_abs)
        seen_inodes.add(ino_key)
        found.append(cand_raw)

    for cpid in pids:
        _, cmd_lpaths = cmdline_by_pid.get(cpid, (False, []))
        for lp in cmd_lpaths:
            _accept(lp)
        proc_listen, proc_xdg_rt, proc_tmp = _read_proc_nvim_env(cpid)
        if proc_listen and proc_listen.startswith("/"):
            _accept(proc_listen)

        seen_rt: set[str] = set()
        for rt_d in (proc_xdg_rt, sock_dir, sock_real_dir, env_xdg_rt, run_uid_dir):
            if not rt_d:
                continue
            rt_real = os.path.realpath(rt_d)
            if rt_real in seen_rt or not os.path.isdir(rt_d):
                continue
            seen_rt.add(rt_real)
            try:
                for p in sorted(Path(rt_d).glob(f"nvim.{cpid}.*")):
                    _accept(str(p))
            except OSError:
                pass

        seen_tmp: set[str] = set()
        for tmp_d in (proc_tmp, sock_dir, sock_real_dir, env_tmp, darwin_tmp, "/tmp"):
            if not tmp_d:
                continue
            tmp_real = os.path.realpath(tmp_d)
            if tmp_real in seen_tmp or not os.path.isdir(tmp_d):
                continue
            seen_tmp.add(tmp_real)
            try:
                for p in sorted(Path(tmp_d).glob(f"nvim.{cpid}.*")):
                    _accept(str(p))
            except OSError:
                pass
            if nvim_user:
                user_nvim_dir = Path(tmp_d) / f"nvim.{nvim_user}"
                if user_nvim_dir.is_dir():
                    for pat in (f"nvim.{cpid}.*", f"*/nvim.{cpid}.*"):
                        try:
                            for p in sorted(user_nvim_dir.glob(pat)):
                                _accept(str(p))
                        except OSError:
                            pass

    if not found and os.path.isfile("/proc/net/unix"):
        by_pid: dict[int, list[str]] = {}
        pid_set = set(pids)
        try:
            with open("/proc/net/unix", "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if "nvim." not in line:
                        continue
                    parts = line.split()
                    if not parts:
                        continue
                    spath = parts[-1]
                    if not spath.startswith("/"):
                        continue
                    bname = os.path.basename(spath)
                    if bname.startswith("nvim."):
                        bparts = bname.split(".")
                        if len(bparts) >= 3 and bparts[1].isdigit():
                            mpid = int(bparts[1])
                            if mpid in pid_set:
                                by_pid.setdefault(mpid, []).append(spath)
        except OSError:
            pass
        for cpid in pids:
            for spath in sorted(by_pid.get(cpid, ())):
                _accept(spath)

    return found
