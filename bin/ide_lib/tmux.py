"""Tmux IPC, exact session/pane targeting, SSH/display sync, clipboard, and process inspection."""

from __future__ import annotations

from contextlib import contextmanager
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys

TYPE_CHECKING = False
if TYPE_CHECKING:
    from typing import Callable, Iterator

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
_SWITCHER_SESS_PREFIX = "ai-sw-"
_BARE_SHELL_CMD_RE = re.compile(
    r"^-?(?:(?:ba|z|da|k|mk|a|tc|c|fi)?sh|nu|elvish|xonsh|pwsh)$",
    re.IGNORECASE,
)


def is_switcher_session_name(sess: str) -> bool:
    """Return True when `sess` names an ephemeral 2-pane `ide --sessions` switcher session (`ai-sw-*`)."""
    return bool(sess) and sess.startswith(_SWITCHER_SESS_PREFIX)


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
        TMUX_SEP.join([
            "#{pid}",
            "#{session_name}",
            "#{@ide_session}",
            "#{@ide_socket}",
            "#{@ide_main_win}",
            "#{@ide_owner_sess}",
            "#{@ide_sw_docked_sess}",
        ]),
    )
    if not found or TMUX_SEP not in found:
        return ""
    fparts = (found.split(TMUX_SEP) + [""] * 7)[:7]
    pid, sess_name, ide_sess, ide_sock, ide_win, owner_sess, sw_docked_sess = fparts
    if pid != server_pid:
        return ""
    if is_ide_session_meta(sess_name, ide_sess, ide_sock, ide_win):
        return sess_name
    if is_switcher_session_name(sess_name):
        for cand_s in (owner_sess.strip(), sw_docked_sess.strip()):
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


def switcher_placeholder_cmd() -> str:
    """Return quiet zero-CPU shell loop for the switcher's inactive placeholder pane."""
    return 'printf "\\033[?25l"; trap "exit 0" INT TERM HUP; exec sleep 86400'


def _switcher_lock_path(sw_sess: str) -> str:
    rt_dir = (os.environ.get("XDG_RUNTIME_DIR") or "").strip()
    base = rt_dir if (rt_dir and os.path.isdir(rt_dir)) else "/tmp"
    try:
        uid_s = str(os.getuid())
    except AttributeError:
        uid_s = "0"
    return os.path.join(base, f"ide-sw-{uid_s}-{sanitize_name_token(sw_sess)}.lock")


@contextmanager
def _with_switcher_lock(sw_sess: str) -> Iterator[list[int]]:
    import signal

    try:
        import fcntl as _fcntl
    except ImportError:
        _fcntl = None  # type: ignore[assignment]

    deferred_sigs: list[int] = []
    saved_handlers: list[tuple[int, object]] = []

    def _defer_sig(signum: int, _frame: object) -> None:
        deferred_sigs.append(signum)

    for sname in ("SIGTERM", "SIGINT", "SIGHUP"):
        sig_num = getattr(signal, sname, None)
        if sig_num is not None:
            try:
                saved_handlers.append((sig_num, signal.signal(sig_num, _defer_sig)))
            except (OSError, ValueError):
                pass

    fd = -1
    if sw_sess and _fcntl is not None:
        lpath = _switcher_lock_path(sw_sess)
        try:
            fd = os.open(lpath, os.O_CREAT | os.O_RDWR, 0o600)
            _fcntl.flock(fd, _fcntl.LOCK_EX)
        except OSError:
            if fd >= 0:
                try:
                    os.close(fd)
                except OSError:
                    pass
                fd = -1
    try:
        yield deferred_sigs
    finally:
        if fd >= 0 and _fcntl is not None:
            try:
                _fcntl.flock(fd, _fcntl.LOCK_UN)
            except OSError:
                pass
            try:
                os.close(fd)
            except OSError:
                pass
        for sig_num, prev_h in saved_handlers:
            try:
                signal.signal(sig_num, prev_h)
            except (OSError, ValueError):
                pass
        if deferred_sigs:
            try:
                os.kill(os.getpid(), deferred_sigs[0])
            except OSError:
                pass


def write_switcher_result(res_path: str, action: str, target: str = "", pressed: str = "") -> None:
    """Atomically record the user's switcher selection (`switch`, `launch`, or `none`) to `res_path`."""
    if not res_path:
        return
    import json

    tmp_p = f"{res_path}.tmp.{os.getpid()}"
    payload = json.dumps({"action": action, "target": target, "pressed": pressed})
    try:
        fd = os.open(tmp_p, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
        try:
            os.write(fd, (payload + "\n").encode("utf-8"))
        finally:
            os.close(fd)
        os.replace(tmp_p, res_path)
    except OSError:
        try:
            os.unlink(tmp_p)
        except OSError:
            pass


def read_switcher_result(res_path: str) -> tuple[str, str, str] | None:
    """Read `(action, target, pressed)` from `res_path`, returning `None` if absent or invalid."""
    if not res_path or not os.path.isfile(res_path):
        return None
    import json

    try:
        with open(res_path, "r", encoding="utf-8") as fh:
            data = json.loads(fh.read())
        if isinstance(data, dict):
            return (
                str(data.get("action") or ""),
                str(data.get("target") or ""),
                str(data.get("pressed") or ""),
            )
    except (OSError, ValueError):
        pass
    return None


def resolve_switcher_context(sw_sess: str) -> tuple[str, str, str]:
    """Return `(docked_sess, outer_client, result_file)` for switcher session `sw_sess`."""
    if not is_switcher_session_name(sw_sess):
        return ("", "", "")
    raw = tmux_out(
        "display-message",
        "-p",
        "-t",
        f"={sw_sess}:",
        TMUX_SEP.join(["#{@ide_sw_docked_sess}", "#{@ide_sw_client}", "#{@ide_sw_result_file}"]),
    )
    if not raw or TMUX_SEP not in raw:
        return ("", "", "")
    ds, cl, rf = (raw.split(TMUX_SEP) + ["", "", ""])[:3]
    return (ds.strip(), cl.strip(), rf.strip())


def pane_in_switcher_session(sw_sess: str) -> bool:
    """Return True if `$TMUX_PANE` currently resides inside switcher session `sw_sess` on the active server."""
    if not is_switcher_session_name(sw_sess):
        return False
    tmux_pane = os.environ.get("TMUX_PANE", "").strip()
    tmux_env = os.environ.get("TMUX", "").strip()
    if not tmux_pane or not tmux_env:
        return False
    parts = tmux_env.split(",")
    if len(parts) < 3:
        return False
    server_pid = parts[-2]
    info = tmux_out(
        "display-message",
        "-p",
        "-t",
        tmux_pane,
        TMUX_SEP.join(["#{pid}", "#{session_name}"]),
    )
    if not info or TMUX_SEP not in info:
        return False
    pid, sname = (info.split(TMUX_SEP, 1) + ["", ""])[:2]
    return pid.strip() == server_pid and sname.strip() == sw_sess


def caller_switcher_session(target_arg: str = "") -> str:
    """Return the active `ai-sw-*` session when called from or targeting a switcher popup, else `''`."""
    if is_switcher_session_name(target_arg):
        return target_arg if session_exists(target_arg) else ""
    env_sw = os.environ.get("IDE_SWITCHER_SESSION", "").strip()
    if not target_arg and is_switcher_session_name(env_sw) and session_exists(env_sw):
        return env_sw
    tmux_pane = os.environ.get("TMUX_PANE", "").strip()
    tmux_env = os.environ.get("TMUX", "").strip()
    if tmux_pane and tmux_env:
        parts = tmux_env.split(",")
        if len(parts) >= 3:
            info = tmux_out(
                "display-message",
                "-p",
                "-t",
                tmux_pane,
                TMUX_SEP.join(["#{pid}", "#{session_name}", "#{@ide_sw_docked_sess}"]),
            )
            if info and TMUX_SEP in info:
                pid, sname, docked_s = (p.strip() for p in (info.split(TMUX_SEP) + ["", "", ""])[:3])
                if pid == parts[-2] and is_switcher_session_name(sname):
                    if not target_arg or resolve_target_session(target_arg) == docked_s:
                        return sname
    if not target_arg:
        ide_cl = os.environ.get("IDE_CLIENT", "").strip()
        if ide_cl and not ide_cl.startswith("#{"):
            cl_sess = tmux_out("display-message", "-p", "-c", ide_cl, "#{session_name}").strip()
            if is_switcher_session_name(cl_sess):
                return cl_sess
    return ""


def undock_switcher_session(sw_sess: str, _locked: bool = False) -> str:
    """Restore any docked IDE pane inside `sw_sess` back to its home workspace cell and zoom state."""
    if not is_switcher_session_name(sw_sess):
        return ""
    if not _locked:
        with _with_switcher_lock(sw_sess):
            return undock_switcher_session(sw_sess, _locked=True)

    info = tmux_out(
        "display-message",
        "-p",
        "-t",
        f"={sw_sess}:",
        TMUX_SEP.join([
            "#{@ide_switcher}",
            "#{@ide_sw_fzf_pane}",
            "#{@ide_sw_slot_pane}",
            "#{@ide_sw_docked_pane}",
            "#{@ide_sw_docked_sess}",
            "#{@ide_sw_was_zoomed}",
            "#{@ide_sw_zoomed_pane}",
            "#{window_id}",
            "#{window_zoomed_flag}",
        ]),
    )
    if not info or TMUX_SEP not in info:
        return ""
    parts = (info.split(TMUX_SEP) + [""] * 9)[:9]
    is_sw, fzf_pane, slot_pane, docked_pane, docked_sess, was_zoomed, zoomed_pane, sw_win, sw_zoom = (
        p.strip() for p in parts
    )
    if is_sw != "1" or not docked_pane:
        return ""

    pane_loc: dict[str, tuple[str, str]] = {}
    sess_pane_counts: dict[str, int] = {}
    for line in tmux_out(
        "list-panes",
        "-a",
        "-F",
        TMUX_SEP.join(["#{pane_id}", "#{session_name}", "#{window_id}"]),
    ).splitlines():
        lp = line.split(TMUX_SEP)
        if len(lp) >= 3:
            pane_loc[lp[0]] = (lp[1], lp[2])
            sess_pane_counts[lp[1]] = sess_pane_counts.get(lp[1], 0) + 1

    docked_loc = pane_loc.get(docked_pane)
    slot_loc = pane_loc.get(slot_pane) if slot_pane else None
    clear_sw_opts = [
        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_docked_pane", "",
        ";",
        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_docked_sess", "",
        ";",
        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_was_zoomed", "0",
        ";",
        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_zoomed_pane", "",
        ";",
        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_label", "",
    ]

    if docked_loc is not None and slot_loc is not None:
        cmds: list[str] = []
        if docked_loc[0] == sw_sess and slot_loc[0] != sw_sess:
            if sw_zoom == "1" and sw_win:
                cmds.extend(["resize-pane", "-Z", "-t", sw_win, ";"])
            cmds.extend(["swap-pane", "-d", "-s", docked_pane, "-t", slot_pane, ";"])
        cmds.extend(["set-option", "-p", "-q", "-u", "-t", docked_pane, "@ide_sw_docked_by", ";"])
        if docked_sess and docked_sess in sess_pane_counts:
            cmds.extend(["set-option", "-q", "-u", "-t", f"={docked_sess}:", "@ide_docked_in", ";"])
        cmds.extend(clear_sw_opts)
        run_tmux(*cmds)
        if was_zoomed == "1" and zoomed_pane and zoomed_pane in pane_loc:
            if tmux_out("display-message", "-p", "-t", zoomed_pane, "#{window_zoomed_flag}") == "0":
                run_tmux("resize-pane", "-Z", "-t", zoomed_pane)
        return docked_sess

    if docked_loc is None and slot_loc is not None:
        cmds_b: list[str] = list(clear_sw_opts)
        if docked_sess and docked_sess in sess_pane_counts:
            cmds_b.extend([";", "set-option", "-q", "-u", "-t", f"={docked_sess}:", "@ide_docked_in"])
        run_tmux(*cmds_b)
        if fzf_pane in pane_loc and pane_loc[fzf_pane][0] == sw_sess:
            if sw_zoom == "1" and sw_win:
                run_tmux("resize-pane", "-Z", "-t", sw_win)
            new_slot = tmux_out(
                "split-window", "-d", "-h", "-P", "-F", "#{pane_id}",
                "-t", fzf_pane, "-l", "56%", switcher_placeholder_cmd(),
            ).strip()
            if new_slot:
                run_tmux(
                    "set-option", "-p", "-q", "-t", new_slot, "@ide_sw_placeholder", "1",
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_slot_pane", new_slot,
                )
        slot_owner = slot_loc[0]
        if sess_pane_counts.get(slot_owner, 0) > 1:
            run_tmux("kill-pane", "-t", slot_pane)
        else:
            init_r = get_ide_var(slot_owner, "@ide_initial_root", "IDE_INITIAL_ROOT")
            wd = get_ide_var(slot_owner, "@ide_workdir", "IDE_WORKDIR") or init_r or safe_getcwd()
            ai_c = get_ide_var(slot_owner, "@ide_ai_cli", "IDE_AI_CLI") or "agy"
            ed_s = get_ide_var(slot_owner, "@ide_socket", "NVIM_IDE_SOCKET")
            ed_p = get_ide_var(slot_owner, "@ide_editor_pane", "NVIM_IDE_PANE")
            resp_env = [
                "-e", f"IDE_SESSION={slot_owner}",
                "-e", f"IDE_AI_CLI={ai_c}",
                "-e", f"IDE_INITIAL_ROOT={init_r or wd}",
                "-e", "FORCE_HYPERLINK=1",
            ]
            if ed_s:
                resp_env.extend(["-e", f"NVIM_IDE_SOCKET={ed_s}"])
            if ed_p:
                resp_env.extend(["-e", f"NVIM_IDE_PANE={ed_p}"])
            shell = os.environ.get("SHELL") or "/bin/sh"
            run_tmux(
                "set-option", "-p", "-q", "-u", "-t", slot_pane, "@ide_sw_placeholder",
                ";",
                "set-option", "-p", "-q", "-t", slot_pane, "@ide_role", "ai",
                ";",
                "set-option", "-p", "-q", "-t", slot_pane, "@ide_owner_sess", slot_owner,
                ";",
                "respawn-pane", "-k", "-t", slot_pane, "-c", wd, *resp_env, f"exec {shlex.quote(shell)} -l",
            )
            set_ide_var(slot_owner, "@ide_ai_pane", "IDE_AI_PANE", slot_pane)
        return docked_sess

    if docked_loc is not None and slot_loc is None:
        if docked_loc[0] == sw_sess:
            run_tmux(
                "respawn-pane", "-k", "-t", docked_pane, switcher_placeholder_cmd(),
                ";",
                "set-option", "-p", "-q", "-t", docked_pane, "@ide_sw_placeholder", "1",
                ";",
                "set-option", "-p", "-q", "-u", "-t", docked_pane, "@ide_role",
                ";",
                "set-option", "-p", "-q", "-u", "-t", docked_pane, "@ide_owner_sess",
                ";",
                "set-option", "-p", "-q", "-u", "-t", docked_pane, "@ide_sw_docked_by",
                ";",
                "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_slot_pane", docked_pane,
                ";",
                *clear_sw_opts,
            )
        else:
            run_tmux(
                "set-option", "-p", "-q", "-u", "-t", docked_pane, "@ide_sw_docked_by",
                ";",
                *clear_sw_opts,
            )
        return docked_sess

    cmds_d: list[str] = list(clear_sw_opts)
    if docked_sess and docked_sess in sess_pane_counts:
        cmds_d.extend([";", "set-option", "-q", "-u", "-t", f"={docked_sess}:", "@ide_docked_in"])
    run_tmux(*cmds_d)
    if fzf_pane in pane_loc and pane_loc[fzf_pane][0] == sw_sess:
        new_slot2 = tmux_out(
            "split-window", "-d", "-h", "-P", "-F", "#{pane_id}",
            "-t", fzf_pane, "-l", "56%", switcher_placeholder_cmd(),
        ).strip()
        if new_slot2:
            run_tmux(
                "set-option", "-p", "-q", "-t", new_slot2, "@ide_sw_placeholder", "1",
                ";",
                "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_slot_pane", new_slot2,
            )
    return docked_sess


def find_switcher_for_client(client_name: str) -> str:
    """Return an active `ai-sw-*` session currently bound to `client_name`, if any."""
    if not client_name:
        return ""
    out = tmux_out(
        "list-sessions",
        "-F",
        TMUX_SEP.join(["#{session_name}", "#{@ide_switcher}", "#{@ide_sw_client}", "#{@ide_sw_done}"]),
    )
    for line in out.splitlines():
        if TMUX_SEP not in line:
            continue
        sname, is_sw, sw_cl, sw_done = (p.strip() for p in (line.split(TMUX_SEP) + [""] * 4)[:4])
        if is_switcher_session_name(sname) and is_sw == "1" and sw_cl == client_name and sw_done != "1":
            return sname
    return ""


def dock_session_into_switcher(
    sw_sess: str,
    target_sess: str,
    cancel_check: Callable[[], bool] | None = None,
) -> bool:
    """Embed `target_sess`'s live AI pane into the right pane of switcher session `sw_sess`."""
    if not is_switcher_session_name(sw_sess):
        return False
    with _with_switcher_lock(sw_sess) as deferred_sigs:
        if deferred_sigs or (cancel_check is not None and cancel_check()):
            return False
        snap = run_tmux(
            "display-message",
            "-p",
            "-t",
            f"={sw_sess}:",
            TMUX_SEP.join([
                "SW",
                "#{@ide_switcher}",
                "#{@ide_sw_fzf_pane}",
                "#{@ide_sw_slot_pane}",
                "#{@ide_sw_docked_pane}",
                "#{@ide_sw_docked_sess}",
                "#{@ide_sw_was_zoomed}",
                "#{@ide_sw_zoomed_pane}",
                "#{@ide_sw_mode}",
                "#{window_id}",
                "#{window_zoomed_flag}",
            ]),
            ";",
            "list-sessions",
            "-F",
            TMUX_SEP.join([
                "SESS",
                "#{session_name}",
                "#{@ide_session}",
                "#{@ide_socket}",
                "#{@ide_main_win}",
                "#{@ide_ai_pane}",
                "#{@ide_ai_cli}",
                "#{@ide_docked_in}",
            ]),
            ";",
            "list-panes",
            "-a",
            "-F",
            TMUX_SEP.join([
                "PANE",
                "#{pane_id}",
                "#{session_name}",
                "#{window_id}",
                "#{pane_active}",
                "#{window_zoomed_flag}",
                "#{@ide_role}",
                "#{@ide_sw_docked_by}",
                "#{@ide_sw_placeholder}",
            ]),
        )
        if snap.returncode != 0 or not snap.stdout:
            return False

        sw_pfx = f"SW{TMUX_SEP}"
        sess_pfx = f"SESS{TMUX_SEP}"
        pane_pfx = f"PANE{TMUX_SEP}"
        sw_parts: list[str] = []
        sess_meta: dict[str, tuple[str, str, str, str, str, str]] = {}
        panes_by_id: dict[str, tuple[str, str, str, str, str, str, str]] = {}
        sess_panes: dict[str, list[tuple[str, str, str]]] = {}
        win_active_pane: dict[str, str] = {}

        for ln in snap.stdout.splitlines():
            if ln.startswith(sw_pfx):
                sw_parts = [p.strip() for p in (ln.split(TMUX_SEP)[1:] + [""] * 10)[:10]]
            elif ln.startswith(sess_pfx):
                sc = (ln.split(TMUX_SEP)[1:] + [""] * 7)[:7]
                sname = sc[0].strip()
                if sname:
                    sess_meta[sname] = (
                        sc[1].strip(),
                        sc[2].strip(),
                        sc[3].strip(),
                        sc[4].strip(),
                        sc[5].strip(),
                        sc[6].strip(),
                    )
            elif ln.startswith(pane_pfx):
                pc = (ln.split(TMUX_SEP)[1:] + [""] * 8)[:8]
                pid = pc[0].strip()
                psess = pc[1].strip()
                pwin = pc[2].strip()
                pact = pc[3].strip()
                pzoom = pc[4].strip()
                prole = pc[5].strip()
                pdocked_by = pc[6].strip()
                pph = pc[7].strip()
                if pid:
                    panes_by_id[pid] = (psess, pwin, pact, pzoom, prole, pdocked_by, pph)
                    sess_panes.setdefault(psess, []).append((pid, prole, pph))
                    if pact == "1" and pwin:
                        win_active_pane[pwin] = pid

        if not sw_parts:
            return False
        (
            is_sw,
            fzf_pane,
            slot_pane,
            cur_docked_pane,
            cur_docked_sess,
            prev_was_zoomed,
            prev_zoomed_pane,
            sw_mode,
            sw_win,
            sw_zoom,
        ) = sw_parts
        if is_sw != "1" or sw_mode == "new":
            return False

        clean_target = target_sess.strip()
        if clean_target and clean_target == cur_docked_sess and cur_docked_pane:
            cur_loc0 = panes_by_id.get(cur_docked_pane)
            if cur_loc0 is not None and cur_loc0[0] == sw_sess:
                return True

        inline_undock_cmds: list[str] = []
        if cur_docked_pane:
            cur_loc = panes_by_id.get(cur_docked_pane)
            slot_loc = panes_by_id.get(slot_pane) if slot_pane else None
            if (
                cur_loc is not None
                and slot_loc is not None
                and cur_loc[0] == sw_sess
                and slot_loc[0] != sw_sess
            ):
                if sw_zoom == "1" and sw_win:
                    inline_undock_cmds.extend(["resize-pane", "-Z", "-t", sw_win, ";"])
                    sw_zoom = "0"
                inline_undock_cmds.extend([
                    "swap-pane", "-d", "-s", cur_docked_pane, "-t", slot_pane, ";",
                    "set-option", "-p", "-q", "-u", "-t", cur_docked_pane, "@ide_sw_docked_by", ";",
                ])
                if cur_docked_sess and cur_docked_sess in sess_meta:
                    inline_undock_cmds.extend([
                        "set-option", "-q", "-u", "-t", f"={cur_docked_sess}:", "@ide_docked_in", ";",
                    ])
                if prev_was_zoomed == "1" and prev_zoomed_pane in panes_by_id and panes_by_id[prev_zoomed_pane][3] == "0":
                    inline_undock_cmds.extend(["resize-pane", "-Z", "-t", prev_zoomed_pane, ";"])
            else:
                undock_switcher_session(sw_sess, _locked=True)
                slot_pane = tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_slot_pane").strip()
                sw_zoom = tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{window_zoomed_flag}").strip()
                panes_by_id.clear()
                sess_panes.clear()
                win_active_pane.clear()
                for ln2 in tmux_out(
                    "list-panes",
                    "-a",
                    "-F",
                    TMUX_SEP.join([
                        "#{pane_id}",
                        "#{session_name}",
                        "#{window_id}",
                        "#{pane_active}",
                        "#{window_zoomed_flag}",
                        "#{@ide_role}",
                        "#{@ide_sw_docked_by}",
                        "#{@ide_sw_placeholder}",
                    ]),
                ).splitlines():
                    pc2 = (ln2.split(TMUX_SEP) + [""] * 8)[:8]
                    pid2 = pc2[0].strip()
                    if pid2:
                        panes_by_id[pid2] = (
                            pc2[1].strip(),
                            pc2[2].strip(),
                            pc2[3].strip(),
                            pc2[4].strip(),
                            pc2[5].strip(),
                            pc2[6].strip(),
                            pc2[7].strip(),
                        )
                        sess_panes.setdefault(pc2[1].strip(), []).append((pid2, pc2[5].strip(), pc2[7].strip()))
                        if pc2[3].strip() == "1" and pc2[2].strip():
                            win_active_pane[pc2[2].strip()] = pid2

        def _abort_after_undock(clear_label: bool = True) -> bool:
            if inline_undock_cmds:
                clear_opts = [
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_docked_pane", "", ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_docked_sess", "", ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_was_zoomed", "0", ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_zoomed_pane", "", ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_label", "",
                ]
                run_tmux(*inline_undock_cmds, *clear_opts)
            elif clear_label:
                run_tmux("set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_label", "")
            return False

        t_meta = sess_meta.get(clean_target) if clean_target else None
        if t_meta is None or not is_ide_session_meta(clean_target, t_meta[0], t_meta[1], t_meta[2]):
            return _abort_after_undock(clear_label=True)

        rec_ai = t_meta[3]
        if rec_ai and rec_ai in panes_by_id and is_switcher_session_name(panes_by_id[rec_ai][0]):
            return _abort_after_undock(clear_label=False)
        healed_ai = False
        target_pane = ""
        if (
            rec_ai
            and rec_ai in panes_by_id
            and panes_by_id[rec_ai][0] == clean_target
            and panes_by_id[rec_ai][6] != "1"
        ):
            target_pane = rec_ai
        else:
            for cand_pid, cand_role, cand_ph in sess_panes.get(clean_target, ()):
                if cand_role == "ai" and cand_ph != "1":
                    target_pane = cand_pid
                    healed_ai = True
                    break
            if not target_pane:
                for cand_pid, cand_role, cand_ph in sess_panes.get(clean_target, ()):
                    if cand_role not in ("editor", "term") and cand_ph != "1":
                        target_pane = cand_pid
                        break
        if not target_pane or target_pane not in panes_by_id:
            return _abort_after_undock(clear_label=True)

        p_sess, p_win, _, p_zoom, _, docked_by, _ = panes_by_id[target_pane]
        if p_sess != clean_target:
            return _abort_after_undock(clear_label=False)
        if docked_by and docked_by != sw_sess and docked_by in sess_meta:
            return _abort_after_undock(clear_label=False)

        was_zoomed = p_zoom == "1"
        zoomed_pane = win_active_pane.get(p_win, target_pane) if was_zoomed else ""

        if not slot_pane or slot_pane not in panes_by_id:
            if inline_undock_cmds:
                _abort_after_undock(clear_label=False)
                inline_undock_cmds.clear()
            if not fzf_pane or fzf_pane not in panes_by_id:
                return False
            if sw_zoom == "1" and sw_win:
                run_tmux("resize-pane", "-Z", "-t", sw_win)
                sw_zoom = "0"
            slot_pane = tmux_out(
                "split-window", "-d", "-h", "-P", "-F", "#{pane_id}",
                "-t", fzf_pane, "-l", "56%", switcher_placeholder_cmd(),
            ).strip()
            if not slot_pane:
                return False
            run_tmux(
                "set-option", "-p", "-q", "-t", slot_pane, "@ide_sw_placeholder", "1",
                ";",
                "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_slot_pane", slot_pane,
            )

        ai_cli = t_meta[4] or get_ide_var(clean_target, "@ide_ai_cli", "IDE_AI_CLI") or "AI"
        label = f"{clean_target} · {ai_cli}"
        cmds: list[str] = list(inline_undock_cmds)
        if sw_zoom == "1" and sw_win:
            cmds.extend(["resize-pane", "-Z", "-t", sw_win, ";"])
        if healed_ai:
            cmds.extend([
                "set-option", "-q", "-t", f"={clean_target}:", "@ide_ai_pane", target_pane, ";",
                "set-environment", "-t", f"={clean_target}", "IDE_AI_PANE", target_pane, ";",
            ])
        cmds.extend([
            "set-option", "-p", "-q", "-t", target_pane, "@ide_owner_sess", clean_target,
            ";",
            "set-option", "-p", "-q", "-t", target_pane, "@ide_sw_docked_by", sw_sess,
            ";",
            "swap-pane", "-d", "-s", slot_pane, "-t", target_pane,
            ";",
            "set-option", "-q", "-t", f"={clean_target}:", "@ide_docked_in", sw_sess,
            ";",
            "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_docked_pane", target_pane,
            ";",
            "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_docked_sess", clean_target,
            ";",
            "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_was_zoomed", "1" if was_zoomed else "0",
            ";",
            "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_zoomed_pane", zoomed_pane,
            ";",
            "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_label", label,
        ])
        swap_res = run_tmux(*cmds)
        return swap_res.returncode == 0


def switcher_owner_alive(sw_sess: str) -> bool:
    """Return True if the outer `ide --sessions` owner process for `sw_sess` is still alive."""
    if not is_switcher_session_name(sw_sess):
        return False
    raw_pid = tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_owner_pid").strip()
    if not raw_pid.isdigit():
        return False
    pid = int(raw_pid)
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False


def close_switcher_session(
    sw_sess: str,
    action: str = "",
    target: str = "",
    pressed: str = "",
    res_file_hint: str = "",
) -> None:
    """Undock `sw_sess`, record optional exit result, and detach popup clients cleanly."""
    if not is_switcher_session_name(sw_sess):
        return
    res_file = res_file_hint or tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_result_file").strip()
    if action and res_file:
        write_switcher_result(res_file, action, target, pressed)
    undock_switcher_session(sw_sess)
    if session_exists(sw_sess):
        run_tmux("set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_done", "1")
        for cl in tmux_out("list-clients", "-t", f"={sw_sess}", "-F", "#{client_name}").splitlines():
            cl_s = cl.strip()
            if cl_s:
                run_tmux("detach-client", "-t", cl_s)
        if not switcher_owner_alive(sw_sess):
            cleanup_switcher_session(sw_sess)


def cleanup_switcher_session(sw_sess: str) -> None:
    """Idempotently undock any embedded IDE pane and destroy switcher session `sw_sess`."""
    if not is_switcher_session_name(sw_sess):
        return
    lpath = _switcher_lock_path(sw_sess)
    with _with_switcher_lock(sw_sess):
        snap = run_tmux(
            "display-message",
            "-p",
            "-t",
            f"={sw_sess}:",
            TMUX_SEP.join([
                "SW",
                "#{@ide_switcher}",
                "#{@ide_sw_slot_pane}",
                "#{@ide_sw_docked_pane}",
                "#{@ide_sw_docked_sess}",
                "#{@ide_sw_was_zoomed}",
                "#{@ide_sw_zoomed_pane}",
                "#{window_id}",
                "#{window_zoomed_flag}",
            ]),
            ";",
            "list-panes",
            "-a",
            "-F",
            TMUX_SEP.join([
                "PANE",
                "#{pane_id}",
                "#{session_name}",
                "#{window_id}",
                "#{window_zoomed_flag}",
                "#{@ide_owner_sess}",
            ]),
        )
        if snap.returncode == 0 and snap.stdout:
            sw_pfx = f"SW{TMUX_SEP}"
            pane_pfx = f"PANE{TMUX_SEP}"
            sw_parts: list[str] = []
            pane_map: dict[str, tuple[str, str, str, str]] = {}
            all_sess: set[str] = set()
            sw_owned_panes: list[tuple[str, str]] = []
            for ln in snap.stdout.splitlines():
                if ln.startswith(sw_pfx):
                    sw_parts = [p.strip() for p in (ln.split(TMUX_SEP)[1:] + [""] * 8)[:8]]
                elif ln.startswith(pane_pfx):
                    pc = [p.strip() for p in (ln.split(TMUX_SEP)[1:] + [""] * 5)[:5]]
                    pid, psess, pwin, pzoom, powner = pc
                    if pid:
                        pane_map[pid] = (psess, pwin, pzoom, powner)
                        all_sess.add(psess)
                        if psess == sw_sess and powner:
                            sw_owned_panes.append((pid, powner))

            fast_handled = False
            if sw_parts and sw_parts[0] == "1":
                _, slot_pane, docked_pane, docked_sess, was_zoomed, zoomed_pane, sw_win, sw_zoom = sw_parts
                unhook_cmds = [
                    "set-hook", "-u", "-t", f"={sw_sess}:", "client-attached",
                    ";",
                    "set-hook", "-u", "-t", f"={sw_sess}:", "client-detached",
                    ";",
                    "set-hook", "-uw", "-t", f"={sw_sess}:", "pane-focus-in",
                ]
                if not docked_pane and not sw_owned_panes:
                    if run_tmux(*unhook_cmds, ";", "kill-session", "-t", f"={sw_sess}").returncode == 0:
                        fast_handled = True
                elif docked_pane and slot_pane:
                    d_loc = pane_map.get(docked_pane)
                    s_loc = pane_map.get(slot_pane)
                    extra_owned = [ pid for pid, _ in sw_owned_panes if pid != docked_pane ]
                    if (
                        d_loc is not None
                        and s_loc is not None
                        and d_loc[0] == sw_sess
                        and s_loc[0] != sw_sess
                        and not extra_owned
                    ):
                        cmds: list[str] = [*unhook_cmds, ";"]
                        if sw_zoom == "1" and sw_win:
                            cmds.extend(["resize-pane", "-Z", "-t", sw_win, ";"])
                        cmds.extend([
                            "swap-pane", "-d", "-s", docked_pane, "-t", slot_pane,
                            ";",
                            "set-option", "-p", "-q", "-u", "-t", docked_pane, "@ide_sw_docked_by",
                            ";",
                        ])
                        if docked_sess and docked_sess in all_sess:
                            cmds.extend(["set-option", "-q", "-u", "-t", f"={docked_sess}:", "@ide_docked_in", ";"])
                        if was_zoomed == "1" and zoomed_pane in pane_map and pane_map[zoomed_pane][2] == "0":
                            cmds.extend(["resize-pane", "-Z", "-t", zoomed_pane, ";"])
                        cmds.extend(["kill-session", "-t", f"={sw_sess}"])
                        if run_tmux(*cmds).returncode == 0:
                            fast_handled = True

            if not fast_handled and session_exists(sw_sess):
                run_tmux(
                    "set-hook", "-u", "-t", f"={sw_sess}:", "client-attached",
                    ";",
                    "set-hook", "-u", "-t", f"={sw_sess}:", "client-detached",
                    ";",
                    "set-hook", "-uw", "-t", f"={sw_sess}:", "pane-focus-in",
                )
                undock_switcher_session(sw_sess, _locked=True)
                for line in tmux_out(
                    "list-panes",
                    "-s",
                    "-t",
                    f"={sw_sess}:",
                    "-F",
                    TMUX_SEP.join(["#{pane_id}", "#{@ide_owner_sess}"]),
                ).splitlines():
                    if TMUX_SEP in line:
                        pid, owner_s = line.split(TMUX_SEP, 1)
                        owner_s = owner_s.strip()
                        if pid and owner_s and session_exists(owner_s):
                            run_tmux(
                                "set-option", "-p", "-q", "-u", "-t", pid, "@ide_sw_docked_by",
                                ";",
                                "set-option", "-q", "-u", "-t", f"={owner_s}:", "@ide_docked_in",
                                ";",
                                "join-pane", "-d", "-s", pid, "-t", f"={owner_s}:",
                            )
                run_tmux("kill-session", "-t", f"={sw_sess}")
    try:
        os.unlink(lpath)
    except OSError:
        pass


def undock_session_if_docked(sess: str, docked_in_hint: str | None = None) -> None:
    """If `sess` currently has its AI pane embedded in a switcher session, undock it back home."""
    if not sess:
        return
    sw_sess = (
        docked_in_hint.strip()
        if docked_in_hint is not None
        else tmux_out("show-options", "-qv", "-t", f"={sess}:", "@ide_docked_in").strip()
    )
    if sw_sess and is_switcher_session_name(sw_sess):
        undock_switcher_session(sw_sess)
        run_tmux("set-option", "-q", "-u", "-t", f"={sess}:", "@ide_docked_in")


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


def switch_or_attach_session(target_sess: str, origin_sess: str = "", sock_path: str = "") -> int:
    """Switch the active tmux client (or `exec` `attach-session` outside tmux) to `target_sess`."""
    if not target_sess or not session_exists(target_sess):
        return 1
    run_tmux("set-option", "-q", "-u", "-t", f"={target_sess}:", "@ide_quit_err")
    if os.environ.get("TMUX") or os.environ.get("IDE_CLIENT"):
        ide_client = resolve_active_client(origin_sess)
        if ide_client:
            cl_sess = tmux_out("display-message", "-p", "-c", ide_client, "#{session_name}").strip()
            if is_switcher_session_name(cl_sess):
                _, outer_cl, sw_rf = resolve_switcher_context(cl_sess)
                close_switcher_session(cl_sess, action="switch", target=target_sess, res_file_hint=sw_rf)
                if not sw_rf and outer_cl:
                    res = run_tmux("switch-client", "-c", outer_cl, "-t", f"={target_sess}")
                    if res.returncode == 0:
                        _notify_session_editor_images(target_sess)
                return 0
            res = run_tmux("switch-client", "-c", ide_client, "-t", f"={target_sess}")
            if res.returncode == 0:
                _notify_session_editor_images(target_sess)
                return 0
        if os.environ.get("TMUX"):
            cur_cl_sess = tmux_out("display-message", "-p", "#{session_name}").strip()
            if is_switcher_session_name(cur_cl_sess):
                _, outer_cl2, sw_rf2 = resolve_switcher_context(cur_cl_sess)
                close_switcher_session(cur_cl_sess, action="switch", target=target_sess, res_file_hint=sw_rf2)
                if not sw_rf2 and outer_cl2:
                    if run_tmux("switch-client", "-c", outer_cl2, "-t", f"={target_sess}").returncode == 0:
                        _notify_session_editor_images(target_sess)
                return 0
            res = run_tmux("switch-client", "-t", f"={target_sess}")
            if res.returncode == 0:
                _notify_session_editor_images(target_sess)
            return 0
    if os.environ.get("IDE_NO_ATTACH", "0") == "1" or not (sys.stdin.isatty() and sys.stdout.isatty()):
        return 0
    att_argv = ["tmux", *(["-S", sock_path] if sock_path else []), "attach-session", "-t", f"={target_sess}"]
    os.execvp("tmux", att_argv)
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
        from pathlib import Path

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

    import getpass
    from pathlib import Path

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
