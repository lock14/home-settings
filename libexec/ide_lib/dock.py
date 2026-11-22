"""Two-pane `ai-sw-*` switcher docking state machine, `flock` serialization, and client handoff."""

from __future__ import annotations

from contextlib import contextmanager
import os
import shlex
import sys

TYPE_CHECKING = False
if TYPE_CHECKING:
    from typing import Callable, Iterator

from ide_lib.constants import (
    TMUX_SEP,
    is_switcher_session_name,
    read_switcher_result,
    safe_getcwd,
    write_switcher_result,
)
from ide_lib.tmux import (
    get_ide_var,
    is_ide_session_meta,
    notify_session_editor_images,
    pane_in_win,
    resolve_active_client,
    resolve_main_win,
    resolve_switcher_context,
    resolve_target_session,
    run_tmux,
    session_exists,
    set_ide_vars,
    tmux_out,
)

__all__ = [
    "build_clear_switcher_dock_opts",
    "build_dock_swap_cmds",
    "caller_switcher_session",
    "cleanup_switcher_session",
    "close_switcher_session",
    "dock_session_into_switcher",
    "find_switcher_for_client",
    "is_switcher_session_name",
    "pane_in_switcher_session",
    "read_switcher_result",
    "resolve_switcher_context",
    "select_dockable_ai_pane",
    "switch_or_attach_session",
    "switcher_owner_alive",
    "switcher_placeholder_cmd",
    "undock_session_if_docked",
    "undock_switcher_session",
    "with_switcher_lock",
    "write_switcher_result",
]


def switcher_placeholder_cmd() -> str:
    """Return quiet zero-CPU shell loop for the switcher's inactive placeholder pane."""
    return 'printf "\\033[?25l"; trap "exit 0" INT TERM HUP; exec sleep 86400'


def _user_login_shell() -> str:
    def_sh = tmux_out("show-options", "-gqv", "default-shell").strip()
    if def_sh and def_sh != "/bin/sh" and os.path.isfile(def_sh) and os.access(def_sh, os.X_OK):
        return def_sh
    env_sh = (os.environ.get("SHELL") or "").strip()
    if env_sh and env_sh != "/bin/sh" and os.path.isfile(env_sh) and os.access(env_sh, os.X_OK):
        return env_sh
    try:
        import pwd

        pw_sh = pwd.getpwuid(os.getuid()).pw_shell.strip()
        if pw_sh and os.path.isfile(pw_sh) and os.access(pw_sh, os.X_OK):
            return pw_sh
    except (ImportError, KeyError, AttributeError, OSError):
        pass
    return env_sh or def_sh or "/bin/sh"


def _switcher_lock_path(sock_hint: str = "") -> str:
    import hashlib

    rt_dir = (os.environ.get("XDG_RUNTIME_DIR") or "").strip()
    base = rt_dir if (rt_dir and os.path.isdir(rt_dir)) else "/tmp"
    try:
        uid_s = str(os.getuid())
    except AttributeError:
        uid_s = "0"
    raw_sock = sock_hint.strip()
    if not raw_sock:
        tmux_env = (os.environ.get("TMUX") or "").strip()
        if tmux_env:
            raw_sock = tmux_env.split(",", 1)[0].strip()
    if not raw_sock:
        t_tmp = (os.environ.get("TMUX_TMPDIR") or "/tmp").strip() or "/tmp"
        raw_sock = os.path.join(t_tmp, f"tmux-{uid_s}", "default")
    try:
        canon_sock = os.path.realpath(raw_sock)
    except OSError:
        canon_sock = os.path.abspath(raw_sock)
    digest = hashlib.sha256(canon_sock.encode("utf-8", errors="surrogateescape")).hexdigest()[:16]
    return os.path.join(base, f"ide-sw-srv-{uid_s}-{digest}.lock")


@contextmanager
def with_switcher_lock(sw_sess: str = "", sock_hint: str = "") -> Iterator[list[int]]:
    """Acquire server-scoped exclusive file lock for switcher state, deferring `SIGTERM`/`SIGINT`/`SIGHUP`."""
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
    if (sw_sess or sock_hint) and _fcntl is not None:
        lpath = _switcher_lock_path(sock_hint)
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


_with_switcher_lock = with_switcher_lock


def _save_zoomed_editor_view(ide_sock: str) -> str:
    if not ide_sock:
        return ""
    from ide_lib.constants import is_live_socket
    from ide_lib.nvim_rpc import nvim_remote_expr

    if not is_live_socket(ide_sock):
        return ""
    raw = nvim_remote_expr(ide_sock, "json_encode(winsaveview())")
    return raw if raw.startswith("{") else ""


def _restore_zoomed_editor_view(sess: str, saved_view: str, sock_hint: str = "") -> None:
    if not saved_view or not saved_view.startswith("{"):
        return
    import json

    from ide_lib.constants import is_live_socket
    from ide_lib.nvim_rpc import nvim_remote_expr

    sock = sock_hint or get_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET")
    if sock and is_live_socket(sock):
        lua_restore = (
            "(function(s) local ok, v = pcall(vim.fn.json_decode, s); "
            "if ok and type(v) == 'table' then pcall(vim.fn.winrestview, v); "
            "local g = vim.api.nvim_create_augroup('IdeRestoreZoomView', { clear = true }); "
            "vim.api.nvim_create_autocmd('VimResized', { group = g, once = true, "
            "callback = function() pcall(vim.fn.winrestview, v) end }); "
            "vim.defer_fn(function() pcall(vim.fn.winrestview, v) end, 40); "
            "vim.defer_fn(function() pcall(vim.api.nvim_del_augroup_by_name, 'IdeRestoreZoomView'); "
            "pcall(vim.fn.winrestview, v) end, 300) end; "
            "return '1' end)(_A)"
        )
        nvim_remote_expr(sock, f"luaeval({json.dumps(lua_restore)}, {json.dumps(saved_view)})")


def _restore_copy_scroll_pos(pane_id: str, want_pos: str) -> None:
    if not pane_id or not want_pos.isdigit() or int(want_pos) <= 0:
        return
    st = tmux_out("display-message", "-p", "-t", pane_id, "#{pane_in_mode}\t#{scroll_position}")
    if "\t" not in st:
        return
    in_m, cur_sp_s = st.split("\t", 1)
    if in_m.strip() != "1":
        return
    cur_sp = int(cur_sp_s.strip()) if cur_sp_s.strip().isdigit() else 0
    delta = int(want_pos) - cur_sp
    if delta > 0:
        run_tmux("send-keys", "-X", "-t", pane_id, "-N", str(delta), "scroll-up")
    elif delta < 0:
        run_tmux("send-keys", "-X", "-t", pane_id, "-N", str(-delta), "scroll-down")


def build_clear_switcher_dock_opts(sw_sess: str, clear_label: bool = False) -> list[str]:
    """Build chained `set-option` arguments resetting `@ide_sw_docked_*` metadata on `sw_sess`."""
    target = f"={sw_sess}:"
    cmds = [
        "set-option", "-q", "-t", target, "@ide_sw_docked_pane", "",
        ";",
        "set-option", "-q", "-t", target, "@ide_sw_docked_sess", "",
        ";",
        "set-option", "-q", "-t", target, "@ide_sw_was_zoomed", "0",
        ";",
        "set-option", "-q", "-t", target, "@ide_sw_zoomed_pane", "",
        ";",
        "set-option", "-q", "-t", target, "@ide_sw_copy_pos", "",
        ";",
        "set-option", "-q", "-t", target, "@ide_sw_ed_view", "",
    ]
    if clear_label:
        cmds.extend([";", "set-option", "-q", "-t", target, "@ide_sw_label", ""])
    return cmds


def build_dock_swap_cmds(
    sw_sess: str,
    slot_pane: str,
    target_sess: str,
    target_pane: str,
    label: str,
    was_zoomed: bool,
    zoomed_pane: str,
    healed_ai: bool = False,
    copy_pos: str = "",
    ed_view: str = "",
) -> list[str]:
    """Build atomic `swap-pane -d` and metadata option sequence docking `target_pane` into `sw_sess`."""
    cmds: list[str] = []
    if healed_ai:
        cmds.extend([
            "set-option", "-q", "-t", f"={target_sess}:", "@ide_ai_pane", target_pane,
            ";",
            "set-environment", "-t", f"={target_sess}", "IDE_AI_PANE", target_pane,
            ";",
        ])
    cmds.extend([
        "set-option", "-p", "-q", "-t", target_pane, "@ide_owner_sess", target_sess,
        ";",
        "set-option", "-p", "-q", "-t", target_pane, "@ide_sw_docked_by", sw_sess,
        ";",
        "swap-pane", "-d", "-s", slot_pane, "-t", target_pane,
        ";",
        "set-option", "-q", "-t", f"={target_sess}:", "@ide_docked_in", sw_sess,
        ";",
        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_docked_pane", target_pane,
        ";",
        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_docked_sess", target_sess,
        ";",
        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_selected_sess", target_sess,
        ";",
        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_was_zoomed", "1" if was_zoomed else "0",
        ";",
        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_zoomed_pane", zoomed_pane,
        ";",
        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_copy_pos", copy_pos,
        ";",
        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_ed_view", ed_view,
        ";",
        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_label", label,
    ])
    return cmds


def select_dockable_ai_pane(
    target_sess: str,
    rec_ai: str,
    panes_by_id: dict[str, tuple[str, str, str, str, str, str, str]],
    sess_panes: dict[str, list[tuple[str, str, str]]],
) -> tuple[str, bool]:
    """Select `(target_pane, healed_ai)` for `target_sess`, refusing foreign or non-AI panes."""
    if not target_sess:
        return ("", False)
    if rec_ai and rec_ai in panes_by_id and is_switcher_session_name(panes_by_id[rec_ai][0]):
        return ("", False)
    if (
        rec_ai
        and rec_ai in panes_by_id
        and panes_by_id[rec_ai][0] == target_sess
        and panes_by_id[rec_ai][4] not in ("editor", "term")
        and panes_by_id[rec_ai][6] != "1"
    ):
        return (rec_ai, False)
    cands = sess_panes.get(target_sess, ())
    for cand_pid, cand_role, cand_ph in cands:
        if cand_role == "ai" and cand_ph != "1":
            return (cand_pid, True)
    if not rec_ai and not any(r for _, r, ph in cands if ph != "1"):
        for cand_pid, _, cand_ph in cands:
            if cand_ph != "1":
                return (cand_pid, True)
    return ("", False)


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
                TMUX_SEP.join(["#{pid}", "#{session_name}", "#{@ide_sw_docked_sess}", "#{@ide_sw_selected_sess}"]),
            )
            if info and TMUX_SEP in info:
                pid, sname, docked_s, sel_s = (p.strip() for p in (info.split(TMUX_SEP) + ["", "", "", ""])[:4])
                if pid == parts[-2] and is_switcher_session_name(sname):
                    if not target_arg or resolve_target_session(target_arg) in (docked_s, sel_s):
                        return sname
    if not target_arg:
        ide_cl = os.environ.get("IDE_CLIENT", "").strip()
        if ide_cl and not ide_cl.startswith("#{"):
            cl_sess = tmux_out("display-message", "-p", "-c", ide_cl, "#{session_name}").strip()
            if is_switcher_session_name(cl_sess):
                return cl_sess
    return ""


def _spawn_replacement_slot_pane(sw_sess: str, fzf_pane: str) -> str:
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
    return new_slot


def undock_switcher_session(sw_sess: str, _locked: bool = False) -> str:
    """Restore any docked IDE pane inside `sw_sess` back to its home workspace cell and zoom state."""
    if not is_switcher_session_name(sw_sess):
        return ""
    if not _locked:
        with with_switcher_lock(sw_sess):
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
            "#{@ide_sw_copy_pos}",
            "#{@ide_sw_ed_view}",
            "#{window_id}",
            "#{window_zoomed_flag}",
        ]),
    )
    if not info or TMUX_SEP not in info:
        return ""
    parts = (info.split(TMUX_SEP) + [""] * 11)[:11]
    (
        is_sw,
        fzf_pane,
        slot_pane,
        docked_pane,
        docked_sess,
        was_zoomed,
        zoomed_pane,
        saved_copy_pos,
        saved_ed_view,
        sw_win,
        sw_zoom,
    ) = (p.strip() for p in parts)
    if is_sw != "1" or not docked_pane:
        return ""

    pane_loc: dict[str, tuple[str, str]] = {}
    pane_copy: dict[str, tuple[str, str]] = {}
    sess_pane_counts: dict[str, int] = {}
    for line in tmux_out(
        "list-panes",
        "-a",
        "-F",
        TMUX_SEP.join(["#{pane_id}", "#{session_name}", "#{window_id}", "#{pane_in_mode}", "#{scroll_position}"]),
    ).splitlines():
        lp = line.split(TMUX_SEP)
        if len(lp) >= 3:
            pane_loc[lp[0]] = (lp[1], lp[2])
            if len(lp) >= 5:
                pane_copy[lp[0]] = (lp[3].strip(), lp[4].strip())
            sess_pane_counts[lp[1]] = sess_pane_counts.get(lp[1], 0) + 1

    docked_loc = pane_loc.get(docked_pane)
    slot_loc = pane_loc.get(slot_pane) if slot_pane else None
    clear_sw_opts = build_clear_switcher_dock_opts(sw_sess)
    cur_in_m, cur_sp = pane_copy.get(docked_pane, ("0", ""))
    eff_copy_pos = (
        (cur_sp if (cur_sp.isdigit() and int(cur_sp) > 0) else saved_copy_pos)
        if cur_in_m == "1"
        else ""
    )

    if docked_loc is not None and slot_loc is not None:
        cmds: list[str] = []
        if docked_loc[0] == sw_sess and slot_loc[0] != sw_sess:
            if sw_zoom == "1" and sw_win:
                cmds.extend(["resize-pane", "-Z", "-t", sw_win, ";"])
            cmds.extend(["swap-pane", "-d", "-s", docked_pane, "-t", slot_pane, ";"])
        elif docked_loc[0] != sw_sess and slot_loc[0] != sw_sess and sess_pane_counts.get(slot_loc[0], 0) > 1:
            if fzf_pane in pane_loc and pane_loc[fzf_pane][0] == sw_sess:
                if sw_zoom == "1" and sw_win:
                    cmds.extend(["resize-pane", "-Z", "-t", sw_win, ";"])
                cmds.extend(["join-pane", "-d", "-h", "-l", "56%", "-s", slot_pane, "-t", fzf_pane, ";"])
            else:
                cmds.extend(["kill-pane", "-t", slot_pane, ";"])
        cmds.extend(["set-option", "-p", "-q", "-u", "-t", docked_pane, "@ide_sw_docked_by", ";"])
        if docked_sess and docked_sess in sess_pane_counts:
            cmds.extend(["set-option", "-q", "-u", "-t", f"={docked_sess}:", "@ide_docked_in", ";"])
        cmds.extend(clear_sw_opts)
        run_tmux(*cmds)
        if eff_copy_pos:
            _restore_copy_scroll_pos(docked_pane, eff_copy_pos)
        if was_zoomed == "1" and zoomed_pane and zoomed_pane in pane_loc:
            if tmux_out("display-message", "-p", "-t", zoomed_pane, "#{window_zoomed_flag}") == "0":
                run_tmux("resize-pane", "-Z", "-t", zoomed_pane)
            if zoomed_pane != docked_pane and docked_sess:
                _restore_zoomed_editor_view(docked_sess, saved_ed_view)
        return docked_sess

    if docked_loc is None and slot_loc is not None:
        cmds_b: list[str] = list(clear_sw_opts)
        if docked_sess and docked_sess in sess_pane_counts:
            cmds_b.extend([";", "set-option", "-q", "-u", "-t", f"={docked_sess}:", "@ide_docked_in"])
        run_tmux(*cmds_b)
        if fzf_pane in pane_loc and pane_loc[fzf_pane][0] == sw_sess:
            if sw_zoom == "1" and sw_win:
                run_tmux("resize-pane", "-Z", "-t", sw_win)
            _spawn_replacement_slot_pane(sw_sess, fzf_pane)
        slot_owner = slot_loc[0]
        dead_ai_reset = [
            ("@ide_ai_parked", "IDE_AI_PARKED", "0"),
            ("@ide_ai_state", "IDE_AI_STATE", ""),
            ("@ide_ai_attn", "IDE_AI_ATTN", "0"),
            ("@ide_ai_attn_ts", "IDE_AI_ATTN_TS", ""),
            ("@ide_ai_state_ts", "IDE_AI_STATE_TS", ""),
            ("@ide_ai_msg", "IDE_AI_MSG", ""),
        ]
        if sess_pane_counts.get(slot_owner, 0) > 1:
            run_tmux("kill-pane", "-t", slot_pane)
            set_ide_vars(slot_owner, dead_ai_reset)
            if was_zoomed == "1" and zoomed_pane and zoomed_pane != docked_pane and zoomed_pane in pane_loc:
                if tmux_out("display-message", "-p", "-t", zoomed_pane, "#{window_zoomed_flag}") == "0":
                    run_tmux("resize-pane", "-Z", "-t", zoomed_pane)
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
            shell = _user_login_shell()
            run_tmux(
                "set-option", "-p", "-q", "-u", "-t", slot_pane, "@ide_sw_placeholder",
                ";",
                "set-option", "-p", "-q", "-t", slot_pane, "@ide_role", "ai",
                ";",
                "set-option", "-p", "-q", "-t", slot_pane, "@ide_owner_sess", slot_owner,
                ";",
                "respawn-pane", "-k", "-t", slot_pane, "-c", wd, *resp_env, f"exec {shlex.quote(shell)} -l",
            )
            set_ide_vars(slot_owner, [("@ide_ai_pane", "IDE_AI_PANE", slot_pane), *dead_ai_reset])
        return docked_sess

    if docked_loc is not None and slot_loc is None:
        if docked_loc[0] == sw_sess:
            if docked_sess and docked_sess in sess_pane_counts:
                if sw_zoom == "1" and sw_win:
                    run_tmux("resize-pane", "-Z", "-t", sw_win)
                if fzf_pane in pane_loc and pane_loc[fzf_pane][0] == sw_sess:
                    _spawn_replacement_slot_pane(sw_sess, fzf_pane)
                was_parked = get_ide_var(docked_sess, "@ide_ai_parked", "IDE_AI_PARKED").strip() == "1"
                if was_parked:
                    run_tmux("break-pane", "-d", "-s", docked_pane, "-t", f"={docked_sess}:", "-n", "_ide_park_ai")
                    pk_win = tmux_out("display-message", "-p", "-t", docked_pane, "#{window_id}").strip()
                    if pk_win:
                        run_tmux(
                            "set-option", "-w", "-t", pk_win, "automatic-rename", "off",
                            ";",
                            "set-option", "-w", "-t", pk_win, "allow-rename", "off",
                        )
                else:
                    ed_p = get_ide_var(docked_sess, "@ide_editor_pane", "NVIM_IDE_PANE").strip()
                    tm_p = get_ide_var(docked_sess, "@ide_term_pane", "IDE_TERM_PANE").strip()
                    main_win = resolve_main_win(docked_sess, ed_p, "", tm_p)
                    home_zoom_p = ""
                    if main_win:
                        if tmux_out("display-message", "-p", "-t", main_win, "#{window_zoomed_flag}").strip() == "1":
                            home_zoom_p = tmux_out("display-message", "-p", "-t", main_win, "#{pane_id}").strip()
                            run_tmux("resize-pane", "-Z", "-t", main_win)
                        ed_before = get_ide_var(docked_sess, "@ide_editor_before", "IDE_EDITOR_BEFORE").strip() == "1"
                        if ed_p and pane_in_win(ed_p, main_win):
                            j_flags = ["-d", "-h", "-l", "50%"] if ed_before else ["-d", "-b", "-h", "-l", "50%"]
                            run_tmux("join-pane", *j_flags, "-s", docked_pane, "-t", ed_p)
                        else:
                            run_tmux("join-pane", "-d", "-b", "-f", "-v", "-l", "75%", "-s", docked_pane, "-t", main_win)
                    else:
                        run_tmux("join-pane", "-d", "-b", "-h", "-s", docked_pane, "-t", f"={docked_sess}:")
                    want_z = zoomed_pane if (was_zoomed == "1" and zoomed_pane) else home_zoom_p
                    if want_z and tmux_out("display-message", "-p", "-t", want_z, "#{window_zoomed_flag}").strip() == "0":
                        run_tmux("resize-pane", "-Z", "-t", want_z)
                run_tmux(
                    "set-option", "-p", "-q", "-u", "-t", docked_pane, "@ide_sw_docked_by",
                    ";",
                    "set-option", "-q", "-u", "-t", f"={docked_sess}:", "@ide_docked_in",
                    ";",
                    *clear_sw_opts,
                )
            else:
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
            cmds_c2: list[str] = [
                "set-option", "-p", "-q", "-u", "-t", docked_pane, "@ide_sw_docked_by",
                ";",
                *clear_sw_opts,
            ]
            if docked_sess and docked_sess in sess_pane_counts:
                cmds_c2.extend([";", "set-option", "-q", "-u", "-t", f"={docked_sess}:", "@ide_docked_in"])
            run_tmux(*cmds_c2)
            if fzf_pane in pane_loc and pane_loc[fzf_pane][0] == sw_sess:
                _spawn_replacement_slot_pane(sw_sess, fzf_pane)
        return docked_sess

    cmds_d: list[str] = list(clear_sw_opts)
    if docked_sess and docked_sess in sess_pane_counts:
        cmds_d.extend([";", "set-option", "-q", "-u", "-t", f"={docked_sess}:", "@ide_docked_in"])
    run_tmux(*cmds_d)
    if fzf_pane in pane_loc and pane_loc[fzf_pane][0] == sw_sess:
        _spawn_replacement_slot_pane(sw_sess, fzf_pane)
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
    with with_switcher_lock(sw_sess) as deferred_sigs:
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
                "#{@ide_sw_copy_pos}",
                "#{@ide_sw_ed_view}",
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
                "#{pane_in_mode}",
                "#{scroll_position}",
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
        pane_copy_by_id: dict[str, tuple[str, str]] = {}
        sess_panes: dict[str, list[tuple[str, str, str]]] = {}
        win_active_pane: dict[str, str] = {}

        for ln in snap.stdout.splitlines():
            if ln.startswith(sw_pfx):
                sw_parts = [p.strip() for p in (ln.split(TMUX_SEP)[1:] + [""] * 12)[:12]]
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
                pc = (ln.split(TMUX_SEP)[1:] + [""] * 10)[:10]
                pid = pc[0].strip()
                psess = pc[1].strip()
                pwin = pc[2].strip()
                pact = pc[3].strip()
                pzoom = pc[4].strip()
                prole = pc[5].strip()
                pdocked_by = pc[6].strip()
                pph = pc[7].strip()
                pin_mode = pc[8].strip()
                pscroll = pc[9].strip()
                if pid:
                    panes_by_id[pid] = (psess, pwin, pact, pzoom, prole, pdocked_by, pph)
                    pane_copy_by_id[pid] = (pin_mode, pscroll)
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
            prev_copy_pos,
            prev_ed_view,
        ) = sw_parts
        if is_sw != "1" or sw_mode == "new":
            return False

        clean_target = target_sess.strip()
        if clean_target and clean_target == cur_docked_sess and cur_docked_pane:
            cur_loc0 = panes_by_id.get(cur_docked_pane)
            if cur_loc0 is not None and cur_loc0[0] == sw_sess:
                return True

        inline_undock_cmds: list[str] = []
        restore_prev_copy_pane = ""
        restore_prev_copy_pos = ""
        restore_prev_ed_sess = ""
        restore_prev_ed_sock = ""
        restore_prev_ed_view = ""
        if cur_docked_pane:
            cur_loc = panes_by_id.get(cur_docked_pane)
            slot_loc = panes_by_id.get(slot_pane) if slot_pane else None
            if (
                cur_loc is not None
                and slot_loc is not None
                and cur_loc[0] == sw_sess
                and slot_loc[0] != sw_sess
            ):
                cur_im, cur_sp = pane_copy_by_id.get(cur_docked_pane, ("0", ""))
                if cur_im == "1":
                    restore_prev_copy_pos = cur_sp if (cur_sp.isdigit() and int(cur_sp) > 0) else prev_copy_pos
                    if restore_prev_copy_pos:
                        restore_prev_copy_pane = cur_docked_pane
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
                if (
                    prev_was_zoomed == "1"
                    and prev_zoomed_pane in panes_by_id
                    and (prev_zoomed_pane == cur_docked_pane or panes_by_id[prev_zoomed_pane][1] == slot_loc[1])
                ):
                    inline_undock_cmds.extend(["resize-pane", "-Z", "-t", prev_zoomed_pane, ";"])
                    if prev_zoomed_pane != cur_docked_pane and cur_docked_sess and prev_ed_view:
                        restore_prev_ed_sess = cur_docked_sess
                        restore_prev_ed_sock = sess_meta[cur_docked_sess][1] if cur_docked_sess in sess_meta else ""
                        restore_prev_ed_view = prev_ed_view
            else:
                undock_switcher_session(sw_sess, _locked=True)
                slot_pane = tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_slot_pane").strip()
                sw_zoom = tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{window_zoomed_flag}").strip()
                panes_by_id.clear()
                pane_copy_by_id.clear()
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
                        "#{pane_in_mode}",
                        "#{scroll_position}",
                    ]),
                ).splitlines():
                    pc2 = [x.strip() for x in (ln2.split(TMUX_SEP) + [""] * 10)[:10]]
                    pid2 = pc2[0]
                    if pid2:
                        panes_by_id[pid2] = (pc2[1], pc2[2], pc2[3], pc2[4], pc2[5], pc2[6], pc2[7])
                        pane_copy_by_id[pid2] = (pc2[8], pc2[9])
                        sess_panes.setdefault(pc2[1], []).append((pid2, pc2[5], pc2[7]))
                        if pc2[3] == "1" and pc2[2]:
                            win_active_pane[pc2[2]] = pid2

        def _finish_prev_restores() -> None:
            if restore_prev_copy_pane and restore_prev_copy_pos:
                _restore_copy_scroll_pos(restore_prev_copy_pane, restore_prev_copy_pos)
            if restore_prev_ed_sess and restore_prev_ed_view:
                _restore_zoomed_editor_view(restore_prev_ed_sess, restore_prev_ed_view, sock_hint=restore_prev_ed_sock)

        def _abort_after_undock(fallback_label: str = "") -> bool:
            if inline_undock_cmds:
                cmds_ab = [*inline_undock_cmds, *build_clear_switcher_dock_opts(sw_sess, clear_label=True)]
                if fallback_label:
                    cmds_ab[-1] = fallback_label
                run_tmux(*cmds_ab)
                _finish_prev_restores()
            else:
                run_tmux("set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_label", fallback_label)
            return False

        t_meta = sess_meta.get(clean_target) if clean_target else None
        if t_meta is None or not is_ide_session_meta(clean_target, t_meta[0], t_meta[1], t_meta[2]):
            return _abort_after_undock("")

        busy_label = f"{clean_target} · (in other switcher)"
        rec_ai = t_meta[3]
        if rec_ai and rec_ai in panes_by_id and is_switcher_session_name(panes_by_id[rec_ai][0]):
            return _abort_after_undock(busy_label if panes_by_id[rec_ai][0] != sw_sess else "")
        target_pane, healed_ai = select_dockable_ai_pane(clean_target, rec_ai, panes_by_id, sess_panes)
        if not target_pane or target_pane not in panes_by_id:
            return _abort_after_undock("")

        p_sess, p_win, _, p_zoom, _, docked_by, _ = panes_by_id[target_pane]
        if p_sess != clean_target:
            return _abort_after_undock(busy_label if is_switcher_session_name(p_sess) else "")
        if docked_by and docked_by != sw_sess and docked_by in sess_meta:
            return _abort_after_undock(busy_label)

        was_zoomed = p_zoom == "1"
        zoomed_pane = win_active_pane.get(p_win, target_pane) if was_zoomed else ""
        t_in_m, t_sp = pane_copy_by_id.get(target_pane, ("0", ""))
        new_copy_pos = t_sp if (t_in_m == "1" and t_sp.isdigit() and int(t_sp) > 0) else ""
        new_ed_view = (
            _save_zoomed_editor_view(t_meta[1])
            if (was_zoomed and zoomed_pane and zoomed_pane != target_pane)
            else ""
        )

        if not slot_pane or slot_pane not in panes_by_id:
            if inline_undock_cmds:
                _abort_after_undock("")
                inline_undock_cmds.clear()
            if not fzf_pane or fzf_pane not in panes_by_id:
                return False
            if sw_zoom == "1" and sw_win:
                run_tmux("resize-pane", "-Z", "-t", sw_win)
                sw_zoom = "0"
            slot_pane = _spawn_replacement_slot_pane(sw_sess, fzf_pane)
            if not slot_pane:
                return False

        ai_cli = t_meta[4] or get_ide_var(clean_target, "@ide_ai_cli", "IDE_AI_CLI") or "AI"
        label = f"{clean_target} · {ai_cli}"
        cmds: list[str] = list(inline_undock_cmds)
        if sw_zoom == "1" and sw_win:
            cmds.extend(["resize-pane", "-Z", "-t", sw_win, ";"])
        cmds.extend(
            build_dock_swap_cmds(
                sw_sess=sw_sess,
                slot_pane=slot_pane,
                target_sess=clean_target,
                target_pane=target_pane,
                label=label,
                was_zoomed=was_zoomed,
                zoomed_pane=zoomed_pane,
                healed_ai=healed_ai,
                copy_pos=new_copy_pos,
                ed_view=new_ed_view,
            )
        )
        ok = run_tmux(*cmds).returncode == 0
        if ok:
            _finish_prev_restores()
            if new_copy_pos:
                _restore_copy_scroll_pos(target_pane, new_copy_pos)
        return ok


def switcher_owner_alive(sw_sess: str) -> bool:
    """Return True if the outer `ide switch` owner process for `sw_sess` is still alive."""
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
    if session_exists(sw_sess):
        run_tmux(
            "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_done", "1",
            ";",
            "set-hook", "-uw", "-t", f"={sw_sess}:", "pane-focus-in",
            ";",
            "set-hook", "-uw", "-t", f"={sw_sess}:", "window-layout-changed",
        )
    undock_switcher_session(sw_sess)
    if session_exists(sw_sess):
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
    with with_switcher_lock(sw_sess):
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
                "#{@ide_sw_copy_pos}",
                "#{@ide_sw_ed_view}",
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
                "#{pane_in_mode}",
                "#{scroll_position}",
            ]),
        )
        if snap.returncode == 0 and snap.stdout:
            sw_pfx = f"SW{TMUX_SEP}"
            pane_pfx = f"PANE{TMUX_SEP}"
            sw_parts: list[str] = []
            pane_map: dict[str, tuple[str, str, str, str]] = {}
            pane_copy: dict[str, tuple[str, str]] = {}
            all_sess: set[str] = set()
            sw_owned_panes: list[tuple[str, str]] = []
            for ln in snap.stdout.splitlines():
                if ln.startswith(sw_pfx):
                    sw_parts = [p.strip() for p in (ln.split(TMUX_SEP)[1:] + [""] * 10)[:10]]
                elif ln.startswith(pane_pfx):
                    pc = [p.strip() for p in (ln.split(TMUX_SEP)[1:] + [""] * 7)[:7]]
                    pid, psess, pwin, pzoom, powner, pin_m, psp = pc
                    if pid:
                        pane_map[pid] = (psess, pwin, pzoom, powner)
                        pane_copy[pid] = (pin_m, psp)
                        all_sess.add(psess)
                        if psess == sw_sess and powner:
                            sw_owned_panes.append((pid, powner))

            unhook_cmds = [
                "set-hook", "-u", "-t", f"={sw_sess}:", "client-attached",
                ";",
                "set-hook", "-u", "-t", f"={sw_sess}:", "client-detached",
                ";",
                "set-hook", "-uw", "-t", f"={sw_sess}:", "pane-focus-in",
                ";",
                "set-hook", "-uw", "-t", f"={sw_sess}:", "window-layout-changed",
            ]
            fast_handled = False
            if sw_parts and sw_parts[0] == "1":
                (
                    _,
                    slot_pane,
                    docked_pane,
                    docked_sess,
                    was_zoomed,
                    zoomed_pane,
                    sw_win,
                    sw_zoom,
                    saved_copy_pos,
                    saved_ed_view,
                ) = sw_parts
                if not docked_pane and not sw_owned_panes:
                    empty_cmds: list[str] = [*unhook_cmds, ";"]
                    if sw_zoom == "1" and sw_win:
                        empty_cmds.extend(["resize-pane", "-Z", "-t", sw_win, ";"])
                    empty_cmds.extend(["kill-session", "-t", f"={sw_sess}"])
                    if run_tmux(*empty_cmds).returncode == 0:
                        fast_handled = True
                elif docked_pane and slot_pane:
                    d_loc = pane_map.get(docked_pane)
                    s_loc = pane_map.get(slot_pane)
                    extra_owned = [pid for pid, _ in sw_owned_panes if pid != docked_pane]
                    if (
                        d_loc is not None
                        and s_loc is not None
                        and d_loc[0] == sw_sess
                        and s_loc[0] != sw_sess
                        and not extra_owned
                    ):
                        c_im, c_sp = pane_copy.get(docked_pane, ("0", ""))
                        eff_copy = (
                            (c_sp if (c_sp.isdigit() and int(c_sp) > 0) else saved_copy_pos)
                            if c_im == "1"
                            else ""
                        )
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
                        restore_ed = False
                        if (
                            was_zoomed == "1"
                            and zoomed_pane in pane_map
                            and (zoomed_pane == docked_pane or pane_map[zoomed_pane][1] == s_loc[1])
                        ):
                            cmds.extend(["resize-pane", "-Z", "-t", zoomed_pane, ";"])
                            restore_ed = bool(zoomed_pane != docked_pane and docked_sess and saved_ed_view)
                        cmds.extend(["kill-session", "-t", f"={sw_sess}"])
                        if run_tmux(*cmds).returncode == 0:
                            fast_handled = True
                            if eff_copy:
                                _restore_copy_scroll_pos(docked_pane, eff_copy)
                            if restore_ed:
                                _restore_zoomed_editor_view(docked_sess, saved_ed_view)

            if not fast_handled and session_exists(sw_sess):
                run_tmux(*unhook_cmds)
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
                for zwin in tmux_out(
                    "list-windows", "-t", f"={sw_sess}", "-F", "#{?window_zoomed_flag,#{window_id},}"
                ).splitlines():
                    if zwin.strip():
                        run_tmux("resize-pane", "-Z", "-t", zwin.strip())
                run_tmux("kill-session", "-t", f"={sw_sess}")


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
                        notify_session_editor_images(target_sess)
                return 0
            res = run_tmux("switch-client", "-c", ide_client, "-t", f"={target_sess}")
            if res.returncode == 0:
                notify_session_editor_images(target_sess)
                return 0
        if os.environ.get("TMUX"):
            cur_cl_sess = tmux_out("display-message", "-p", "#{session_name}").strip()
            if is_switcher_session_name(cur_cl_sess):
                _, outer_cl2, sw_rf2 = resolve_switcher_context(cur_cl_sess)
                close_switcher_session(cur_cl_sess, action="switch", target=target_sess, res_file_hint=sw_rf2)
                if not sw_rf2 and outer_cl2:
                    if run_tmux("switch-client", "-c", outer_cl2, "-t", f"={target_sess}").returncode == 0:
                        notify_session_editor_images(target_sess)
                return 0
            res = run_tmux("switch-client", "-t", f"={target_sess}")
            if res.returncode == 0:
                notify_session_editor_images(target_sess)
            return 0
    if os.environ.get("IDE_NO_ATTACH", "0") == "1" or not (sys.stdin.isatty() and sys.stdout.isatty()):
        return 0
    att_argv = ["tmux", *(["-S", sock_path] if sock_path else []), "attach-session", "-t", f"={target_sess}"]
    os.execvp("tmux", att_argv)
    return 0
