"""Workspace geometry, `_ide_park_<role>` parking, swap, focus toggles, refresh, and lifecycle."""

from __future__ import annotations

import os
import shlex
import shutil
import signal
import subprocess
import sys
import time

from ide_lib.constants import (
    ROLE_PARK_VARS,
    TMUX_SEP,
    is_socket_path,
    is_switcher_session_name,
    safe_getcwd,
    visible_width,
)
from ide_lib.dock import (
    close_switcher_session,
    pane_in_switcher_session,
    undock_session_if_docked,
)
from ide_lib.fleet import (
    ack_ai_session,
    classify_ide_fleet,
    list_ide_sessions_with_server_status,
    refresh_fleet_topbar,
)
from ide_lib.hooks import resolve_workspace_target, sanitize_session_name
from ide_lib.nvim_rpc import (
    ensure_editor_nvim_running,
    ensure_session_editor_socket,
    nvim_modified_buf_count,
    nvim_recover_and_checktime,
    nvim_remote_expr,
    nvim_remote_send,
    resolve_ai_cmd,
    resolve_nvim_bin,
    send_editor_launch_keys,
)
from ide_lib.tmux import (
    check_is_ide_session,
    current_ide_session,
    get_ide_var,
    is_ssh_session,
    missing_session_msg,
    normalize_pane_cwd,
    pane_exists,
    pane_has_child_procs,
    pane_in_win,
    pane_is_parked,
    resolve_main_win,
    resolve_role_pane,
    resolve_target_session,
    run_tmux,
    session_exists,
    set_ide_var,
    set_ide_vars,
    tmux_out,
)


def _session_env_flags(
    session: str,
    ai_cli: str,
    nvim_socket: str,
    init_root: str,
    editor_pane: str = "",
    ide_notify: str = "",
) -> list[str]:
    flags = [
        "-e", f"IDE_SESSION={session}",
        "-e", f"IDE_AI_CLI={ai_cli}",
        "-e", f"NVIM_IDE_SOCKET={nvim_socket}",
    ]
    if editor_pane:
        flags.extend(["-e", f"NVIM_IDE_PANE={editor_pane}"])
    flags.extend([
        "-e", f"IDE_INITIAL_ROOT={init_root}",
        "-e", "FORCE_HYPERLINK=1",
    ])
    if ide_notify:
        flags.extend(["-e", f"IDE_NOTIFY={ide_notify}"])
    return flags


def focus_pane_preserving_zoom(
    win: str,
    target_pane: str,
    cur_pane_hint: str | None = None,
    was_zoomed_hint: str | None = None,
    pre_cmds: list[str] | None = None,
) -> None:
    """Focus `target_pane` in `win`, recording `@ide_last_pane` and keeping zoom active."""
    if cur_pane_hint is not None and was_zoomed_hint is not None:
        cur_pane, was_zoomed = cur_pane_hint, was_zoomed_hint
    else:
        info = tmux_out("display-message", "-p", "-t", win, "#{pane_id}\t#{window_zoomed_flag}")
        cur_pane, was_zoomed = (info.split("\t", 1) + ["0"])[:2] if "\t" in info else (info, "0")
    cmd: list[str] = list(pre_cmds) if pre_cmds else []
    if cmd:
        cmd.append(";")
    if cur_pane and cur_pane != target_pane:
        cmd.extend(["set-option", "-w", "-t", win, "@ide_last_pane", cur_pane, ";"])
    cmd.extend(["select-window", "-t", win, ";", "select-pane", "-t", target_pane])
    run_tmux(*cmd)
    if was_zoomed == "1" and tmux_out("display-message", "-p", "-t", win, "#{window_zoomed_flag}") == "0":
        run_tmux("resize-pane", "-Z", "-t", target_pane)


def clamp_dim(val_str: str, total: int, fallback: int) -> int:
    """Clamp a restored width or height within `[max(4, total//10), total - max(4, total//10)]`."""
    min_v = max(4, total // 10)
    max_v = max(min_v, total - min_v)
    try:
        val = int(val_str)
        if val <= 0:
            val = fallback
    except (ValueError, TypeError):
        val = fallback
    return max(min_v, min(max_v, val))


def pane_for_role(role: str, ai_pane: str, editor_pane: str, term_pane: str) -> str:
    """Map role token (`ai`, `editor`, `term`) to its corresponding pane ID."""
    if role == "ai":
        return ai_pane
    if role == "editor":
        return editor_pane
    if role == "term":
        return term_pane
    return ""


def resolve_layout_roles(sess: str) -> tuple[str, str, str, str]:
    """Return `(bar_role, bar_before, left_role, right_role)` for `sess`."""
    raw = tmux_out(
        "display-message",
        "-p",
        "-t",
        f"={sess}:",
        "#{@ide_editor_before}\t#{@ide_term_before}\t#{@ide_bar_role}\t#{@ide_bar_before}\t#{@ide_left_role}\t#{@ide_right_role}",
    )
    parts = raw.split("\t") if "\t" in raw else []
    ed_before = (parts[0] if len(parts) > 0 and parts[0] else "") or get_ide_var(sess, "@ide_editor_before", "IDE_EDITOR_BEFORE")
    term_before = (parts[1] if len(parts) > 1 and parts[1] else "") or get_ide_var(sess, "@ide_term_before", "IDE_TERM_BEFORE")
    bar_role = (parts[2] if len(parts) > 2 and parts[2] else "") or get_ide_var(sess, "@ide_bar_role", "IDE_BAR_ROLE") or "term"
    bar_before = (
        (parts[3] if len(parts) > 3 and parts[3] else "")
        or get_ide_var(sess, "@ide_bar_before", "IDE_BAR_BEFORE")
        or (term_before or "0")
    )
    left_role = (parts[4] if len(parts) > 4 and parts[4] else "") or get_ide_var(sess, "@ide_left_role", "IDE_LEFT_ROLE")
    right_role = (parts[5] if len(parts) > 5 and parts[5] else "") or get_ide_var(sess, "@ide_right_role", "IDE_RIGHT_ROLE")

    if (
        not left_role
        or not right_role
        or left_role == right_role
        or left_role == bar_role
        or right_role == bar_role
    ):
        if bar_role == "term":
            left_role, right_role = ("editor", "ai") if ed_before == "1" else ("ai", "editor")
        elif bar_role == "ai":
            left_role, right_role = ("editor", "term") if ed_before == "1" else ("term", "editor")
        elif bar_role == "editor":
            left_role, right_role = "ai", "term"
    return bar_role, bar_before, left_role, right_role


def record_main_geometry(
    sess: str,
    main_win: str,
    ai_pane: str,
    editor_pane: str,
    term_pane: str,
    pane_lines: list[str] | None = None,
) -> None:
    """Snapshot custom pane widths, heights, and swapped positions before parking or after swapping."""
    coords: dict[str, tuple[int, int, int, int]] = {}
    src_lines = (
        pane_lines
        if pane_lines is not None
        else tmux_out(
            "list-panes", "-t", main_win, "-F", "#{pane_id}\t#{pane_left}\t#{pane_top}\t#{pane_width}\t#{pane_height}"
        ).splitlines()
    )
    for line in src_lines:
        parts = line.split("\t")
        if len(parts) == 5:
            try:
                coords[parts[0]] = (int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]))
            except ValueError:
                pass

    ai_in = ai_pane in coords
    ed_in = editor_pane in coords
    term_in = term_pane in coords
    ai_left, ai_top, ai_w, ai_h = coords.get(ai_pane, (0, 0, 0, 0))
    ed_left, ed_top, ed_w, ed_h = coords.get(editor_pane, (0, 0, 0, 0))
    term_left, term_top, term_w, term_h = coords.get(term_pane, (0, 0, 0, 0))

    updates: list[tuple[str, str, str]] = []

    if ai_in and ed_in and term_in:
        bar_role = ""
        pair_a = pair_b = ""
        pa_left = pa_top = pa_w = pb_left = pb_w = bar_top = bar_h = 0
        if ai_top == ed_top and term_top != ai_top:
            pair_a, pa_left, pa_top, pa_w = "ai", ai_left, ai_top, ai_w
            pair_b, pb_left, pb_w = "editor", ed_left, ed_w
            bar_role, bar_top, bar_h = "term", term_top, term_h
        elif ed_top == term_top and ai_top != ed_top:
            pair_a, pa_left, pa_top, pa_w = "editor", ed_left, ed_top, ed_w
            pair_b, pb_left, pb_w = "term", term_left, term_w
            bar_role, bar_top, bar_h = "ai", ai_top, ai_h
        elif ai_top == term_top and ed_top != ai_top:
            pair_a, pa_left, pa_top, pa_w = "ai", ai_left, ai_top, ai_w
            pair_b, pb_left, pb_w = "term", term_left, term_w
            bar_role, bar_top, bar_h = "editor", ed_top, ed_h

        if bar_role:
            if pa_left <= pb_left:
                left_role, left_w = pair_a, pa_w
                right_role, right_w = pair_b, pb_w
            else:
                left_role, left_w = pair_b, pb_w
                right_role, right_w = pair_a, pa_w
            bar_before = "1" if bar_top < pa_top else "0"
            updates.extend([
                ("@ide_bar_role", "IDE_BAR_ROLE", bar_role),
                ("@ide_bar_before", "IDE_BAR_BEFORE", bar_before),
                ("@ide_term_before", "IDE_TERM_BEFORE", bar_before),
            ])
            if bar_h > 0:
                updates.extend([
                    ("@ide_bar_height", "IDE_BAR_HEIGHT", str(bar_h)),
                    ("@ide_term_height", "IDE_TERM_HEIGHT", str(bar_h)),
                ])
            updates.extend([
                ("@ide_left_role", "IDE_LEFT_ROLE", left_role),
                ("@ide_right_role", "IDE_RIGHT_ROLE", right_role),
            ])
            if left_w > 0:
                updates.append(("@ide_left_width", "IDE_LEFT_WIDTH", str(left_w)))
            if right_w > 0:
                updates.append(("@ide_right_width", "IDE_RIGHT_WIDTH", str(right_w)))

            if bar_role == "term":
                if ed_w > 0:
                    updates.append(("@ide_editor_width", "IDE_EDITOR_WIDTH", str(ed_w)))
                if ai_w > 0:
                    updates.append(("@ide_ai_width", "IDE_AI_WIDTH", str(ai_w)))
            elif left_role == "editor" or right_role == "editor":
                if ed_w > 0:
                    updates.append(("@ide_editor_width", "IDE_EDITOR_WIDTH", str(ed_w)))
            elif left_role == "ai" or right_role == "ai":
                if ai_w > 0:
                    updates.append(("@ide_ai_width", "IDE_AI_WIDTH", str(ai_w)))

            updates.append(("@ide_editor_before", "IDE_EDITOR_BEFORE", "1" if left_role == "editor" else "0"))
            swapped = "0" if (bar_role == "term" and bar_before == "0" and left_role == "ai") else "1"
            updates.append(("@ide_swapped", "IDE_SWAPPED", swapped))
            set_ide_vars(sess, updates)
            return

    r1 = r2 = r3 = ""
    l1 = t1 = w1 = h1 = l2 = t2 = w2 = h2 = 0
    if ai_in and ed_in and not term_in:
        r1, l1, t1, w1, h1 = "ai", ai_left, ai_top, ai_w, ai_h
        r2, l2, t2, w2, h2 = "editor", ed_left, ed_top, ed_w, ed_h
        r3 = "term"
    elif ai_in and term_in and not ed_in:
        r1, l1, t1, w1, h1 = "ai", ai_left, ai_top, ai_w, ai_h
        r2, l2, t2, w2, h2 = "term", term_left, term_top, term_w, term_h
        r3 = "editor"
    elif ed_in and term_in and not ai_in:
        r1, l1, t1, w1, h1 = "editor", ed_left, ed_top, ed_w, ed_h
        r2, l2, t2, w2, h2 = "term", term_left, term_top, term_w, term_h
        r3 = "ai"

    if r1 and r2:
        if t1 == t2:
            if l1 <= l2:
                left_role, left_w = r1, w1
                right_role, right_w = r2, w2
            else:
                left_role, left_w = r2, w2
                right_role, right_w = r1, w1
            updates.extend([
                ("@ide_bar_role", "IDE_BAR_ROLE", r3),
                ("@ide_left_role", "IDE_LEFT_ROLE", left_role),
                ("@ide_right_role", "IDE_RIGHT_ROLE", right_role),
            ])
            if left_w > 0:
                updates.append(("@ide_left_width", "IDE_LEFT_WIDTH", str(left_w)))
            if right_w > 0:
                updates.append(("@ide_right_width", "IDE_RIGHT_WIDTH", str(right_w)))
            if r3 == "term":
                if ed_w > 0:
                    updates.append(("@ide_editor_width", "IDE_EDITOR_WIDTH", str(ed_w)))
                if ai_w > 0:
                    updates.append(("@ide_ai_width", "IDE_AI_WIDTH", str(ai_w)))
            if left_role == "editor":
                updates.extend([
                    ("@ide_editor_before", "IDE_EDITOR_BEFORE", "1"),
                    ("@ide_swapped", "IDE_SWAPPED", "1"),
                ])
            else:
                updates.append(("@ide_editor_before", "IDE_EDITOR_BEFORE", "0"))
                if r3 == "term":
                    updates.append(("@ide_swapped", "IDE_SWAPPED", "0"))
        else:
            bar_role, _, _, _ = resolve_layout_roles(sess)
            bar_h = 0
            bar_before = "0"
            if r1 == bar_role:
                bar_h = h1
                if t1 < t2:
                    bar_before = "1"
            elif r2 == bar_role:
                bar_h = h2
                if t2 < t1:
                    bar_before = "1"
            else:
                updates.append(("@ide_bar_role", "IDE_BAR_ROLE", r2))
                bar_h = h2
                if t2 < t1:
                    bar_before = "1"
            updates.extend([
                ("@ide_bar_before", "IDE_BAR_BEFORE", bar_before),
                ("@ide_term_before", "IDE_TERM_BEFORE", bar_before),
            ])
            if bar_h > 0:
                updates.extend([
                    ("@ide_bar_height", "IDE_BAR_HEIGHT", str(bar_h)),
                    ("@ide_term_height", "IDE_TERM_HEIGHT", str(bar_h)),
                ])
        set_ide_vars(sess, updates)


def unpark_role_pane(
    sess: str,
    role: str,
    main_win: str,
    ai_pane: str,
    editor_pane: str,
    term_pane: str,
    sock: str = "",
) -> None:
    """Rejoin a parked `_ide_park_<role>` pane into `main_win`, restoring saved geometry."""
    target_pane = pane_for_role(role, ai_pane, editor_pane, term_pane)
    if not pane_is_parked(target_pane, main_win):
        return

    win_info = tmux_out(
        "display-message", "-p", "-t", main_win, "#{window_zoomed_flag}\t#{window_width}\t#{window_height}"
    )
    parts = win_info.split("\t")
    if parts and parts[0] == "1":
        run_tmux("resize-pane", "-Z", "-t", main_win)
    try:
        win_w = int(parts[1]) if len(parts) > 1 else 160
        win_h = int(parts[2]) if len(parts) > 2 else 48
    except ValueError:
        win_w, win_h = 160, 48
    if win_w < 20:
        win_w = 160
    if win_h < 10:
        win_h = 48

    bar_role, bar_before, left_role, right_role = resolve_layout_roles(sess)
    vis_panes = [p for p in tmux_out("list-panes", "-t", main_win, "-F", "#{pane_id}").splitlines() if p]
    act_in_win = tmux_out("display-message", "-p", "-t", main_win, "#{pane_id}").strip()
    first_pane = vis_panes[0] if vis_panes else act_in_win

    if role == bar_role:
        saved_h = get_ide_var(sess, "@ide_bar_height", "IDE_BAR_HEIGHT") or get_ide_var(
            sess, "@ide_term_height", "IDE_TERM_HEIGHT"
        )
        bar_h = clamp_dim(saved_h, win_h, win_h // 4)
        if first_pane:
            if bar_before == "1":
                run_tmux("join-pane", "-d", "-f", "-b", "-v", "-l", str(bar_h), "-s", target_pane, "-t", first_pane)
            else:
                run_tmux("join-pane", "-d", "-f", "-v", "-l", str(bar_h), "-s", target_pane, "-t", first_pane)
    else:
        if role == left_role:
            sibling_role, join_before = right_role, True
        else:
            sibling_role, join_before = left_role, False
        sibling_pane = pane_for_role(sibling_role, ai_pane, editor_pane, term_pane)
        bar_pane = pane_for_role(bar_role, ai_pane, editor_pane, term_pane)
        non_bar_vis = [p for p in vis_panes if p != bar_pane]
        horiz_target = sibling_pane if pane_in_win(sibling_pane, main_win) else (
            (act_in_win if act_in_win in non_bar_vis else non_bar_vis[0]) if non_bar_vis else ""
        )
        if horiz_target:
            if join_before:
                saved_w = get_ide_var(sess, "@ide_left_width", "IDE_LEFT_WIDTH")
            else:
                saved_w = get_ide_var(sess, "@ide_right_width", "IDE_RIGHT_WIDTH")
            if not saved_w:
                if role == "editor":
                    saved_w = get_ide_var(sess, "@ide_editor_width", "IDE_EDITOR_WIDTH")
                elif role == "ai":
                    saved_w = get_ide_var(sess, "@ide_ai_width", "IDE_AI_WIDTH")
            target_w = clamp_dim(saved_w, win_w, win_w // 2)
            if join_before:
                run_tmux("join-pane", "-d", "-b", "-h", "-l", str(target_w), "-s", target_pane, "-t", horiz_target)
            else:
                run_tmux("join-pane", "-d", "-h", "-l", str(target_w), "-s", target_pane, "-t", horiz_target)
        elif first_pane:
            saved_bh = get_ide_var(sess, "@ide_bar_height", "IDE_BAR_HEIGHT") or get_ide_var(
                sess, "@ide_term_height", "IDE_TERM_HEIGHT"
            )
            bar_h = clamp_dim(saved_bh, win_h, win_h // 4)
            pair_h = clamp_dim(str(win_h - bar_h), win_h, (win_h * 3) // 4)
            if bar_before == "1":
                run_tmux("join-pane", "-d", "-f", "-v", "-l", str(pair_h), "-s", target_pane, "-t", first_pane)
            else:
                run_tmux("join-pane", "-d", "-f", "-b", "-v", "-l", str(pair_h), "-s", target_pane, "-t", first_pane)

    park_opt, park_env = ROLE_PARK_VARS.get(role, ("", ""))
    if park_opt:
        set_ide_var(sess, park_opt, park_env, "0")

    if role == "editor" and sock:
        sock = ensure_session_editor_socket(sess, sock, editor_pane=editor_pane)
        nvim_recover_and_checktime(
            sock,
            get_ide_var(sess, "@ide_workdir", "IDE_WORKDIR") or get_ide_var(sess, "@ide_initial_root", "IDE_INITIAL_ROOT"),
            "silent! normal! zz",
        )


def heal_split_for_role(
    sess: str,
    role: str,
    main_win: str,
    ai_pane: str,
    editor_pane: str,
    term_pane: str,
    cur_dir: str,
    extra_args: list[str],
) -> str:
    """Recreate a killed `role` pane in its canonical split position inside `main_win`."""
    if "FORCE_HYPERLINK=1" not in extra_args:
        extra_args = [*extra_args, "-e", "FORCE_HYPERLINK=1"]
    bar_role, bar_before, left_role, right_role = resolve_layout_roles(sess)
    if role == bar_role:
        flags = ["-b", "-f", "-v"] if bar_before == "1" else ["-f", "-v"]
        return tmux_out(
            "split-window", *flags, "-P", "-F", "#{pane_id}", "-t", main_win, "-l", "25%", "-c", cur_dir, *extra_args
        )
    sibling_role, join_before = (right_role, True) if role == left_role else (left_role, False)
    sibling_pane = pane_for_role(sibling_role, ai_pane, editor_pane, term_pane)
    if pane_in_win(sibling_pane, main_win):
        flags = ["-b", "-h"] if join_before else ["-h"]
        return tmux_out(
            "split-window", *flags, "-P", "-F", "#{pane_id}", "-t", sibling_pane, "-l", "50%", "-c", cur_dir, *extra_args
        )
    flags = ["-f", "-v"] if bar_before == "1" else ["-b", "-f", "-v"]
    return tmux_out(
        "split-window", *flags, "-P", "-F", "#{pane_id}", "-t", main_win, "-l", "75%", "-c", cur_dir, *extra_args
    )


def park_role_pane(
    sess: str,
    role: str,
    main_win: str,
    ai_pane: str,
    editor_pane: str,
    term_pane: str,
    sock: str = "",
) -> None:
    """Park `role` non-destructively into `_ide_park_<role>`, refusing to hide the last visible pane."""
    target_pane = pane_for_role(role, ai_pane, editor_pane, term_pane)
    if not pane_in_win(target_pane, main_win):
        return

    vis_panes = tmux_out("list-panes", "-t", main_win, "-F", "#{pane_id}").splitlines()
    if len(vis_panes) <= 1:
        run_tmux("display-message", "-d", "2500", "-t", f"={sess}:", "Cannot hide the last visible IDE pane")
        return

    if tmux_out("display-message", "-p", "-t", main_win, "#{window_zoomed_flag}") == "1":
        run_tmux("resize-pane", "-Z", "-t", main_win)

    record_main_geometry(sess, main_win, ai_pane, editor_pane, term_pane)

    active_pane = tmux_out("display-message", "-p", "-t", main_win, "#{pane_id}")
    last_pane = tmux_out("show-options", "-wqv", "-t", main_win, "@ide_last_pane")
    fallback_pane = ""
    if active_pane == target_pane:
        if last_pane and last_pane != target_pane and pane_in_win(last_pane, main_win):
            fallback_pane = last_pane
        else:
            candidates = {
                "term": (editor_pane, ai_pane),
                "editor": (ai_pane, term_pane),
                "ai": (editor_pane, term_pane),
            }.get(role, ())
            for cand in candidates:
                if pane_in_win(cand, main_win):
                    fallback_pane = cand
                    break
            if not fallback_pane:
                for vp in vis_panes:
                    if vp and vp != target_pane:
                        fallback_pane = vp
                        break

    run_tmux("break-pane", "-d", "-s", target_pane, "-n", f"_ide_park_{role}")
    park_opt, park_env = ROLE_PARK_VARS.get(role, ("", ""))
    if park_opt:
        set_ide_var(sess, park_opt, park_env, "1")
    park_win = tmux_out("display-message", "-p", "-t", target_pane, "#{window_id}")
    if park_win and park_win != main_win:
        run_tmux(
            "set-option", "-w", "-t", park_win, "automatic-rename", "off",
            ";",
            "set-option", "-w", "-t", park_win, "allow-rename", "off",
        )
    if fallback_pane and pane_in_win(fallback_pane, main_win):
        run_tmux("select-window", "-t", main_win, ";", "select-pane", "-t", fallback_pane)
        if fallback_pane == editor_pane and sock:
            sock = ensure_session_editor_socket(sess, sock, editor_pane=editor_pane)
            nvim_recover_and_checktime(
                sock,
                get_ide_var(sess, "@ide_workdir", "IDE_WORKDIR") or get_ide_var(sess, "@ide_initial_root", "IDE_INITIAL_ROOT"),
            )


def swap_ide_pane(raw_dir: str, target_arg: str) -> int:
    """Directionally swap the active pane with its neighbor in `raw_dir` (`left|down|up|right`)."""
    dir_map = {
        "left": "-L", "l": "-L", "-l": "-L",
        "down": "-D", "d": "-D", "-d": "-D",
        "up": "-U", "u": "-U", "-u": "-U",
        "right": "-R", "r": "-R", "-r": "-R",
    }
    dir_flag = dir_map.get(raw_dir.lower())
    if not dir_flag:
        print(f"Error: Invalid swap direction '{raw_dir}'. Expected: left, down, up, or right.", file=sys.stderr)
        return 1

    if is_switcher_session_name(target_arg):
        return 0

    sess = resolve_target_session(target_arg)
    if not sess:
        print(f"Error: {missing_session_msg(sess)}", file=sys.stderr)
        return 1

    def _query_swap_snap() -> subprocess.CompletedProcess:
        return run_tmux(
            "display-message",
            "-p",
            "-t",
            f"={sess}:",
            TMUX_SEP.join([
                "OPTS",
                "#{@ide_editor_pane}",
                "#{@ide_ai_pane}",
                "#{@ide_term_pane}",
                "#{@ide_main_win}",
                "#{@ide_layout_mode}",
                "#{@ide_docked_in}",
            ]),
            ";",
            "list-panes",
            "-s",
            "-t",
            f"={sess}:",
            "-F",
            TMUX_SEP.join([
                "PANE",
                "#{pane_id}",
                "#{window_id}",
                "#{window_name}",
                "#{@ide_role}",
                "#{pane_active}",
                "#{window_zoomed_flag}",
            ]),
        )

    snap = _query_swap_snap()
    if snap.returncode != 0 or not snap.stdout:
        print(f"Error: {missing_session_msg(sess)}", file=sys.stderr)
        return 1

    editor_pane = ai_pane = term_pane = main_win = layout_mode = docked_in = ""
    panes_by_id: dict[str, tuple[str, str, str, str, str]] = {}
    opts_pfx = f"OPTS{TMUX_SEP}"
    pane_pfx = f"PANE{TMUX_SEP}"

    def _parse_swap_snap(raw_out: str) -> None:
        nonlocal editor_pane, ai_pane, term_pane, main_win, layout_mode, docked_in
        panes_by_id.clear()
        for ln in raw_out.splitlines():
            if ln.startswith(opts_pfx):
                op = (ln.split(TMUX_SEP)[1:] + [""] * 6)[:6]
                editor_pane, ai_pane, term_pane, main_win, layout_mode, docked_in = op
            elif ln.startswith(pane_pfx):
                pp = ln.split(TMUX_SEP, 6)
                if len(pp) >= 7:
                    panes_by_id[pp[1]] = (pp[2], pp[3], pp[4], pp[5], pp[6])

    _parse_swap_snap(snap.stdout)
    if is_switcher_session_name(docked_in.strip()):
        undock_session_if_docked(sess, docked_in.strip())
        snap = _query_swap_snap()
        if snap.returncode == 0 and snap.stdout:
            _parse_swap_snap(snap.stdout)

    def _resolve_swap_role(cur_p: str, role: str, opt_name: str, env_name: str, check_env: bool = True) -> str:
        if cur_p and cur_p in panes_by_id:
            return cur_p
        for pid, (_, _, prole, _, _) in panes_by_id.items():
            if prole == role:
                set_ide_var(sess, opt_name, env_name, pid)
                return pid
        if check_env:
            env_line = tmux_out("show-environment", "-t", f"={sess}", env_name)
            prefix = f"{env_name}="
            if env_line.startswith(prefix):
                fb = env_line[len(prefix):]
                if fb and fb in panes_by_id:
                    return fb
        return ""

    editor_pane = _resolve_swap_role(editor_pane, "editor", "@ide_editor_pane", "NVIM_IDE_PANE")
    ai_pane = _resolve_swap_role(ai_pane, "ai", "@ide_ai_pane", "IDE_AI_PANE")
    term_pane = _resolve_swap_role(
        term_pane,
        "term",
        "@ide_term_pane",
        "IDE_TERM_PANE",
        check_env=(layout_mode or "3pane") != "2pane",
    )

    if not main_win or not any(wid == main_win and not wname.startswith("_ide_park_") for wid, wname, _, _, _ in panes_by_id.values()):
        main_win = resolve_main_win(sess, editor_pane, ai_pane, term_pane)
    if not main_win:
        return 1

    src_pane = ""
    was_zoomed = False
    for pid, (wid, _, _, p_act, w_zoom) in panes_by_id.items():
        if wid == main_win:
            if w_zoom == "1":
                was_zoomed = True
            if p_act == "1" and not src_pane:
                src_pane = pid
    if not src_pane:
        src_pane = tmux_out("display-message", "-p", "-t", main_win, "#{pane_id}")
    if not src_pane:
        return 0

    probe_cmd: list[str] = []
    if was_zoomed:
        probe_cmd.extend(["resize-pane", "-Z", "-t", main_win, ";"])
    probe_cmd.extend([
        "select-pane", "-t", src_pane, dir_flag,
        ";",
        "display-message", "-p", "-t", main_win, "#{pane_id}",
    ])
    dst_pane = tmux_out(*probe_cmd).strip()

    if dst_pane and dst_pane != src_pane:
        geom_lines = tmux_out(
            "swap-pane", "-s", src_pane, "-t", dst_pane,
            ";",
            "select-pane", "-t", src_pane,
            ";",
            "list-panes", "-t", main_win, "-F", "#{pane_id}\t#{pane_left}\t#{pane_top}\t#{pane_width}\t#{pane_height}",
        ).splitlines()
        record_main_geometry(sess, main_win, ai_pane, editor_pane, term_pane, pane_lines=geom_lines)
    return 0


def _handle_switcher_pane_toggle(sw_sess: str, mode: str) -> int:
    raw = tmux_out(
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
            "#{@ide_sw_client}",
            "#{@ide_sw_result_file}",
            "#{pane_id}",
            "#{window_id}",
            "#{window_zoomed_flag}",
            "#{@ide_sw_mode}",
        ]),
    )
    if not raw or TMUX_SEP not in raw:
        return 0
    (
        is_sw,
        fzf_pane,
        slot_pane,
        docked_pane,
        docked_sess,
        sw_client,
        res_file,
        act_pane,
        sw_win,
        sw_zoom,
        sw_mode,
    ) = (p.strip() for p in (raw.split(TMUX_SEP) + [""] * 11)[:11])
    if is_sw != "1" or sw_mode == "new":
        return 0

    if mode in ("toggle", "ai", "focus-ai"):
        right_pane = docked_pane if pane_exists(docked_pane) else slot_pane
        if mode == "focus-ai":
            target_p = right_pane
        else:
            target_p = right_pane if act_pane == fzf_pane else fzf_pane
        if target_p and sw_win and pane_exists(target_p):
            if target_p == fzf_pane and sw_zoom == "1":
                run_tmux("resize-pane", "-Z", "-t", sw_win)
                sw_zoom = "0"
            focus_pane_preserving_zoom(sw_win, target_p, cur_pane_hint=act_pane, was_zoomed_hint=sw_zoom or "0")
        return 0

    if mode in ("editor", "focus-editor", "term", "focus-term"):
        if docked_sess and session_exists(docked_sess):
            pressed_key = "ctrl-e" if "editor" in mode else "ctrl-t"
            close_switcher_session(
                sw_sess,
                action="switch",
                target=docked_sess,
                pressed=pressed_key,
                res_file_hint=res_file,
            )
            if not res_file and sw_client:
                toggle_main_pane("focus-editor" if "editor" in mode else "focus-term", docked_sess)
                run_tmux("switch-client", "-c", sw_client, "-t", f"={docked_sess}")
        return 0

    return 0


def toggle_main_pane(
    mode: str,
    target_arg: str,
    skip_checktime: bool = False,
    clear_quit_err: bool = True,
) -> int:
    """Focus, bounce back, unpark, or park `ai`, `editor`, or `term` panes in a single snapshot pass."""
    if is_switcher_session_name(target_arg):
        return _handle_switcher_pane_toggle(target_arg, mode)

    sess = resolve_target_session(target_arg)
    if not sess:
        print(f"Error: {missing_session_msg(sess)}", file=sys.stderr)
        return 1

    def _query_toggle_snap() -> subprocess.CompletedProcess:
        return run_tmux(
            "display-message",
            "-p",
            "-t",
            f"={sess}:",
            TMUX_SEP.join([
                "OPTS",
                "#{@ide_editor_pane}",
                "#{@ide_ai_pane}",
                "#{@ide_term_pane}",
                "#{@ide_main_win}",
                "#{@ide_layout_mode}",
                "#{@ide_socket}",
                "#{@ide_ai_cli}",
                "#{@ide_initial_root}",
                "#{@ide_workdir}",
                "#{@ide_last_pane_id}",
                "#{@ide_last_non_ai}",
                "#{@ide_quit_err}",
                "#{@ide_ai_state}",
                "#{@ide_ai_attn}",
                "#{@ide_ai_msg}",
                "#{@ide_docked_in}",
            ]),
            ";",
            "list-panes",
            "-s",
            "-t",
            f"={sess}:",
            "-F",
            TMUX_SEP.join([
                "PANE",
                "#{pane_id}",
                "#{window_id}",
                "#{window_name}",
                "#{@ide_role}",
                "#{pane_left}",
                "#{pane_top}",
                "#{pane_active}",
                "#{window_zoomed_flag}",
                "#{@ide_last_pane}",
                "#{pane_pid}",
                "#{pane_current_command}",
                "#{@ide_nvim_launch_ts}",
                "#{pane_current_path}",
            ]),
        )

    snap = _query_toggle_snap()
    if snap.returncode != 0 or not snap.stdout:
        print(f"Error: {missing_session_msg(sess)}", file=sys.stderr)
        return 1

    (
        editor_pane,
        ai_pane,
        term_pane,
        main_win,
        layout_mode,
        sock,
        ai_cli,
        init_root,
        workdir_opt,
        last_pane_id,
        last_non_ai,
        quit_err_cur,
        snap_ai_state,
        snap_ai_attn,
        snap_ai_msg,
        snap_docked_in,
    ) = ("",) * 16
    panes_by_id: dict[str, tuple[str, str, str, int, int, str, str, str, str, str, str, str]] = {}
    opts_pfx = f"OPTS{TMUX_SEP}"
    pane_pfx = f"PANE{TMUX_SEP}"

    def _parse_toggle_snap(raw_out: str) -> None:
        nonlocal editor_pane, ai_pane, term_pane, main_win, layout_mode, sock, ai_cli
        nonlocal init_root, workdir_opt, last_pane_id, last_non_ai, quit_err_cur
        nonlocal snap_ai_state, snap_ai_attn, snap_ai_msg, snap_docked_in
        panes_by_id.clear()
        for ln in raw_out.splitlines():
            if ln.startswith(opts_pfx):
                op = (ln.split(TMUX_SEP)[1:] + [""] * 16)[:16]
                (
                    editor_pane,
                    ai_pane,
                    term_pane,
                    main_win,
                    layout_mode,
                    sock,
                    ai_cli,
                    init_root,
                    workdir_opt,
                    last_pane_id,
                    last_non_ai,
                    quit_err_cur,
                    snap_ai_state,
                    snap_ai_attn,
                    snap_ai_msg,
                    snap_docked_in,
                ) = op
            elif ln.startswith(pane_pfx):
                pp = ln.split(TMUX_SEP, 13)
                if len(pp) >= 14:
                    try:
                        panes_by_id[pp[1]] = (
                            pp[2],
                            pp[3],
                            pp[4],
                            int(pp[5]),
                            int(pp[6]),
                            pp[7],
                            pp[8],
                            pp[9],
                            pp[10],
                            pp[11],
                            pp[12],
                            pp[13],
                        )
                    except ValueError:
                        pass

    _parse_toggle_snap(snap.stdout)
    clean_docked_in = snap_docked_in.strip()
    if is_switcher_session_name(clean_docked_in):
        if pane_in_switcher_session(clean_docked_in):
            return _handle_switcher_pane_toggle(clean_docked_in, mode)
        undock_session_if_docked(sess, clean_docked_in)
        snap = _query_toggle_snap()
        if snap.returncode == 0 and snap.stdout:
            _parse_toggle_snap(snap.stdout)

    snap_ai_state = snap_ai_state.strip().lower()
    snap_ai_attn = snap_ai_attn.strip()
    snap_ai_msg = snap_ai_msg.strip()

    pending_cmds: list[str] = []
    if clear_quit_err and quit_err_cur:
        pending_cmds.extend(["set-option", "-q", "-u", "-t", f"={sess}:", "@ide_quit_err"])

    need_term = (layout_mode or "3pane") != "2pane" or mode in ("term", "focus-term", "toggle-term")

    def resolve_cached_role(cur_p: str, role: str, opt_name: str, env_name: str, check_env: bool = True) -> str:
        if cur_p and cur_p in panes_by_id:
            return cur_p
        for pid, pval in panes_by_id.items():
            if pval[2] == role:
                set_ide_var(sess, opt_name, env_name, pid)
                return pid
        if check_env:
            env_line = tmux_out("show-environment", "-t", f"={sess}", env_name)
            prefix = f"{env_name}="
            if env_line.startswith(prefix):
                fallback_p = env_line[len(prefix):]
                if fallback_p and fallback_p in panes_by_id:
                    return fallback_p
        return ""

    editor_pane = resolve_cached_role(editor_pane, "editor", "@ide_editor_pane", "NVIM_IDE_PANE")
    ai_pane = resolve_cached_role(ai_pane, "ai", "@ide_ai_pane", "IDE_AI_PANE")
    term_pane = resolve_cached_role(term_pane, "term", "@ide_term_pane", "IDE_TERM_PANE", check_env=need_term)

    if not main_win or not any(
        pval[0] == main_win and not pval[1].startswith("_ide_park_") for pval in panes_by_id.values()
    ):
        main_win = resolve_main_win(sess, editor_pane, ai_pane, term_pane)

    if not sock:
        sock = get_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET")
    if not sock:
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
        sock = f"{runtime_dir}/nvim-ide-{sess}.sock"
    if not ai_cli:
        ai_cli = os.environ.get("IDE_AI_CLI") or "agy"

    if not ai_pane or not editor_pane or (not term_pane and need_term):
        rows = [
            (pval[3], pval[4], pid, pval[2])
            for pid, pval in panes_by_id.items()
            if pval[0] == main_win
        ]
        rows.sort(key=lambda r: (r[0], r[1]))
        if not ai_pane:
            for l, t, pid, prole in rows:
                if l == 0 and t == 0 and prole in ("", "ai"):
                    ai_pane = pid
                    old_v = panes_by_id[pid]
                    panes_by_id[pid] = (old_v[0], old_v[1], "ai", *old_v[3:])
                    run_tmux("set-option", "-p", "-t", ai_pane, "@ide_role", "ai")
                    set_ide_var(sess, "@ide_ai_pane", "IDE_AI_PANE", ai_pane)
                    break
        if not editor_pane:
            for l, t, pid, prole in rows:
                if l > 0 and prole in ("", "editor"):
                    editor_pane = pid
                    old_v = panes_by_id[pid]
                    panes_by_id[pid] = (old_v[0], old_v[1], "editor", *old_v[3:])
                    run_tmux("set-option", "-p", "-t", editor_pane, "@ide_role", "editor")
                    set_ide_var(sess, "@ide_editor_pane", "NVIM_IDE_PANE", editor_pane)
                    break
        if not term_pane and need_term:
            for l, t, pid, prole in rows:
                if l == 0 and t > 0 and prole in ("", "term"):
                    term_pane = pid
                    old_v = panes_by_id[pid]
                    panes_by_id[pid] = (old_v[0], old_v[1], "term", *old_v[3:])
                    run_tmux("set-option", "-p", "-t", term_pane, "@ide_role", "term")
                    set_ide_var(sess, "@ide_term_pane", "IDE_TERM_PANE", term_pane)
                    break

    raw_cur_dir = (
        (panes_by_id[editor_pane][11] if editor_pane in panes_by_id else "")
        or (panes_by_id[ai_pane][11] if ai_pane in panes_by_id else "")
    )
    cur_dir = normalize_pane_cwd(
        raw_cur_dir,
        sess=sess,
        workdir_hint=workdir_opt,
        init_root_hint=init_root,
    )
    if not init_root:
        init_root = cur_dir

    ed_just_healed = False
    ai_just_healed = False
    term_just_healed = False
    layout_mutated = False

    if not editor_pane or not ai_pane or (not term_pane and need_term):
        layout_mutated = True
        was_zoomed_before_heal = tmux_out("display-message", "-p", "-t", main_win, "#{window_zoomed_flag}") or "0"
        if was_zoomed_before_heal == "1":
            run_tmux("resize-pane", "-Z", "-t", main_win)

        if not editor_pane:
            editor_pane = heal_split_for_role(
                sess,
                "editor",
                main_win,
                ai_pane,
                editor_pane,
                term_pane,
                cur_dir,
                _session_env_flags(sess, ai_cli, sock, init_root),
            )
            if editor_pane:
                ed_just_healed = True
                run_tmux("set-option", "-p", "-t", editor_pane, "@ide_role", "editor")
                set_ide_vars(sess, [
                    ("@ide_editor_pane", "NVIM_IDE_PANE", editor_pane),
                    ("@ide_ed_parked", "IDE_ED_PARKED", "0"),
                ])
                send_editor_launch_keys(editor_pane, sock)

        if not ai_pane:
            ai_pane = heal_split_for_role(
                sess,
                "ai",
                main_win,
                ai_pane,
                editor_pane,
                term_pane,
                cur_dir,
                _session_env_flags(sess, ai_cli, sock, init_root, editor_pane=editor_pane),
            )
            if ai_pane:
                ai_just_healed = True
                run_tmux(
                    "set-option", "-p", "-t", ai_pane, "@ide_role", "ai",
                    ";",
                    "set-option", "-p", "-t", ai_pane, "@ide_owner_sess", sess,
                )
                set_ide_vars(sess, [
                    ("@ide_ai_pane", "IDE_AI_PANE", ai_pane),
                    ("@ide_ai_parked", "IDE_AI_PARKED", "0"),
                    ("@ide_ai_state", "IDE_AI_STATE", ""),
                    ("@ide_ai_attn", "IDE_AI_ATTN", "0"),
                    ("@ide_ai_attn_ts", "IDE_AI_ATTN_TS", ""),
                    ("@ide_ai_state_ts", "IDE_AI_STATE_TS", str(int(time.time()))),
                    ("@ide_ai_msg", "IDE_AI_MSG", ""),
                ])
                snap_ai_state = ""
                snap_ai_attn = "0"
                snap_ai_msg = ""
                ai_run_cmd = resolve_ai_cmd(ai_cli)
                if ai_run_cmd:
                    run_tmux("send-keys", "-t", ai_pane, f" {ai_run_cmd}", "C-m")

        if not term_pane and need_term:
            term_pane = heal_split_for_role(
                sess,
                "term",
                main_win,
                ai_pane,
                editor_pane,
                term_pane,
                cur_dir,
                _session_env_flags(sess, ai_cli, sock, init_root, editor_pane=editor_pane),
            )
            if term_pane:
                term_just_healed = True
                run_tmux("set-option", "-p", "-t", term_pane, "@ide_role", "term")
                set_ide_vars(sess, [
                    ("@ide_term_pane", "IDE_TERM_PANE", term_pane),
                    ("@ide_term_parked", "IDE_TERM_PARKED", "0"),
                ])

        if was_zoomed_before_heal == "1" and tmux_out("display-message", "-p", "-t", main_win, "#{window_zoomed_flag}") == "0":
            run_tmux("resize-pane", "-Z", "-t", main_win)

    active_pane = active_role = last_pane = ""
    main_win_zoomed = "0"
    if not layout_mutated and main_win:
        for pid, pval in panes_by_id.items():
            if pval[0] == main_win:
                if pval[6] == "1":
                    main_win_zoomed = "1"
                if pval[5] == "1" and not active_pane:
                    active_pane = pid
                    active_role = pval[2]
                    last_pane = pval[7]
    if not active_pane:
        win_state = tmux_out(
            "display-message",
            "-p",
            "-t",
            main_win,
            TMUX_SEP.join(["#{pane_id}", "#{@ide_role}", "#{@ide_last_pane}", "#{window_zoomed_flag}"]),
        )
        wparts = (win_state.split(TMUX_SEP) + ["", "", "", "0"])[:4]
        active_pane, active_role, last_pane, main_win_zoomed = wparts[0], wparts[1], wparts[2], wparts[3] or "0"
    started_in_ai = bool(active_pane == ai_pane or active_role == "ai")

    def _in_win(pane_id: str) -> bool:
        if not pane_id or not main_win:
            return False
        if not layout_mutated:
            p_entry = panes_by_id.get(pane_id)
            return p_entry is not None and p_entry[0] == main_win
        return pane_in_win(pane_id, main_win)

    def _is_parked(pane_id: str) -> bool:
        if not pane_id or not main_win:
            return False
        if not layout_mutated:
            p_entry = panes_by_id.get(pane_id)
            return p_entry is not None and p_entry[0] != main_win
        return pane_is_parked(pane_id, main_win)

    def _unpark(role: str, sock_arg: str = "") -> None:
        nonlocal layout_mutated
        target_p = pane_for_role(role, ai_pane, editor_pane, term_pane)
        if not layout_mutated and not _is_parked(target_p):
            return
        unpark_role_pane(sess, role, main_win, ai_pane, editor_pane, term_pane, sock_arg)
        layout_mutated = True

    def _ensure_ed_nvim() -> bool:
        ed_hint: tuple[str, str] | None = None
        pid_hint = ""
        if not layout_mutated and editor_pane in panes_by_id:
            ed_v = panes_by_id[editor_pane]
            ed_hint = (ed_v[9], ed_v[10])
            pid_hint = ed_v[8]
        return ensure_editor_nvim_running(
            editor_pane, sock, cached_cmd_ts=ed_hint, sess=sess, pane_pid_hint=pid_hint
        )

    def _flush_pending() -> None:
        if pending_cmds:
            run_tmux(*pending_cmds)
            pending_cmds.clear()

    def _focus_win_pane(target_p: str) -> None:
        pre = list(pending_cmds) if pending_cmds else None
        pending_cmds.clear()
        if not layout_mutated and active_pane:
            focus_pane_preserving_zoom(
                main_win,
                target_p,
                cur_pane_hint=active_pane,
                was_zoomed_hint=main_win_zoomed,
                pre_cmds=pre,
            )
        else:
            focus_pane_preserving_zoom(main_win, target_p, pre_cmds=pre)

    def _record_non_ai_origin() -> None:
        if active_pane and not started_in_ai and _in_win(active_pane):
            if pending_cmds:
                pending_cmds.append(";")
            pending_cmds.extend([
                "set-option", "-q", "-t", f"={sess}:", "@ide_last_pane_id", active_pane,
                ";",
                "set-option", "-q", "-t", f"={sess}:", "@ide_last_non_ai", active_role or "",
            ])

    def _needs_ai_ack_or_cleanup() -> bool:
        if snap_ai_attn not in ("", "0") or snap_ai_state == "done":
            return True
        if not snap_ai_state and not snap_ai_msg:
            return False
        if layout_mutated or not ai_pane or ai_pane not in panes_by_id:
            return True
        ai_v = panes_by_id[ai_pane]
        return not pane_has_child_procs(ai_v[8], ai_v[9])

    def _focus_ai_with_ack() -> None:
        if _needs_ai_ack_or_cleanup():
            ack_ai_session(sess, from_hook=False, refresh_always=False, entering_ai=True)
        _focus_win_pane(ai_pane)

    entered_ai = False
    if mode in ("toggle", "ai"):
        if started_in_ai:
            if last_pane_id and last_pane_id != ai_pane and _in_win(last_pane_id):
                if last_pane_id == editor_pane:
                    if not _ensure_ed_nvim() and not skip_checktime:
                        nvim_recover_and_checktime(sock, cur_dir)
                _focus_win_pane(last_pane_id)
            elif last_non_ai == "term" and _in_win(term_pane):
                _focus_win_pane(term_pane)
            else:
                if _is_parked(editor_pane) and not _in_win(term_pane):
                    _unpark("editor", sock)
                if _in_win(editor_pane):
                    if not _ensure_ed_nvim() and not skip_checktime:
                        nvim_recover_and_checktime(sock, cur_dir)
                    _focus_win_pane(editor_pane)
                elif _in_win(term_pane):
                    _focus_win_pane(term_pane)
                else:
                    _unpark("editor", sock)
                    _ensure_ed_nvim()
                    _focus_win_pane(editor_pane)
        else:
            _record_non_ai_origin()
            _unpark("ai", sock)
            _focus_ai_with_ack()
            entered_ai = True
    elif mode == "focus-ai":
        _record_non_ai_origin()
        _unpark("ai", sock)
        _focus_ai_with_ack()
        entered_ai = True
    elif mode == "editor":
        if active_pane == editor_pane or active_role == "editor":
            if ed_just_healed or _ensure_ed_nvim():
                _focus_win_pane(editor_pane)
            elif last_pane and last_pane != editor_pane and _in_win(last_pane):
                if last_pane == ai_pane:
                    _record_non_ai_origin()
                    _focus_ai_with_ack()
                    entered_ai = True
                else:
                    _focus_win_pane(last_pane)
            elif _in_win(ai_pane):
                _record_non_ai_origin()
                _focus_ai_with_ack()
                entered_ai = True
            elif _in_win(term_pane):
                _focus_win_pane(term_pane)
            else:
                _record_non_ai_origin()
                _unpark("ai", sock)
                _focus_ai_with_ack()
                entered_ai = True
        else:
            _unpark("editor", sock)
            if not _ensure_ed_nvim() and not skip_checktime:
                nvim_recover_and_checktime(sock, cur_dir)
            _focus_win_pane(editor_pane)
    elif mode == "focus-editor":
        _unpark("editor", "" if skip_checktime else sock)
        if not _ensure_ed_nvim() and not skip_checktime:
            nvim_recover_and_checktime(sock, cur_dir)
        _focus_win_pane(editor_pane)
    elif mode == "term":
        if active_pane == term_pane or active_role == "term":
            if last_pane and last_pane != term_pane and _in_win(last_pane):
                if last_pane == editor_pane:
                    if not _ensure_ed_nvim() and not skip_checktime:
                        nvim_recover_and_checktime(sock, cur_dir)
                    _focus_win_pane(last_pane)
                elif last_pane == ai_pane:
                    _record_non_ai_origin()
                    _focus_ai_with_ack()
                    entered_ai = True
                else:
                    _focus_win_pane(last_pane)
            elif _in_win(editor_pane):
                if not _ensure_ed_nvim() and not skip_checktime:
                    nvim_recover_and_checktime(sock, cur_dir)
                _focus_win_pane(editor_pane)
            elif _in_win(ai_pane):
                _record_non_ai_origin()
                _focus_ai_with_ack()
                entered_ai = True
            else:
                _unpark("editor", sock)
                _ensure_ed_nvim()
                _focus_win_pane(editor_pane)
        else:
            _unpark("term", sock)
            _focus_win_pane(term_pane)
    elif mode == "focus-term":
        _unpark("term", sock)
        _focus_win_pane(term_pane)
    elif mode == "toggle-editor":
        if ed_just_healed or _is_parked(editor_pane):
            _unpark("editor", sock)
            _ensure_ed_nvim()
            _focus_win_pane(editor_pane)
        else:
            _flush_pending()
            park_role_pane(sess, "editor", main_win, ai_pane, editor_pane, term_pane, sock)
    elif mode == "toggle-ai":
        if ai_just_healed or _is_parked(ai_pane):
            _record_non_ai_origin()
            _unpark("ai", sock)
            _focus_ai_with_ack()
            entered_ai = True
        else:
            _flush_pending()
            park_role_pane(sess, "ai", main_win, ai_pane, editor_pane, term_pane, sock)
    elif mode == "toggle-term":
        if term_just_healed or _is_parked(term_pane):
            _unpark("term", sock)
            _focus_win_pane(term_pane)
        else:
            _flush_pending()
            park_role_pane(sess, "term", main_win, ai_pane, editor_pane, term_pane, sock)

    _flush_pending()
    if started_in_ai and not entered_ai and _needs_ai_ack_or_cleanup():
        ack_ai_session(sess, from_hook=True, refresh_always=False)
    return 0


def status_click(x_str: str, target_arg: str) -> int:
    """Fallback column-bounded click handler for tmux < 3.4 when `#{mouse_status_range}` is empty."""
    import re

    try:
        x = int(x_str)
    except (ValueError, TypeError):
        return 0
    sess = resolve_target_session(target_arg)
    if not sess or not session_exists(sess):
        return 0

    info = tmux_out(
        "display-message",
        "-p",
        "-t",
        f"={sess}:",
        TMUX_SEP.join(["#{@ide_role}", "#{@ide_ai_cli}", "#{window_zoomed_flag}", "#{status-left}", "#{window_name}"]),
    )
    parts = (info.split(TMUX_SEP) + ["", "", "", "", ""])[:5]
    role = parts[0]
    ai_cli = parts[1] or "AI"
    zoomed = parts[2] == "1"
    status_left_raw = parts[3]
    win_name = parts[4]
    if win_name and win_name != "ide":
        return 0

    if status_left_raw:
        plain_left = re.sub(r"#\[[^\]]*\]", "", status_left_raw).replace("#S", sess)
        left_len = min(48, visible_width(plain_left))
    else:
        left_len = min(48, visible_width(sess) + 6)
    rel = x - left_len
    if rel < 0:
        return 0

    ai_w = 1 + (2 if role == "ai" else 0) + 2 + visible_width(ai_cli) + 8
    ed_w = (2 if role == "editor" else 0) + 16
    term_w = (2 if role == "term" else 0) + 16

    ed_start = ai_w + 3
    ed_end = ed_start + ed_w
    term_start = ed_end + 3
    term_end = term_start + term_w
    zoom_start = term_end + 2
    zoom_end = zoom_start + 15

    if 0 <= rel < ai_w:
        return toggle_main_pane("ai", sess)
    if ed_start <= rel < ed_end:
        return toggle_main_pane("editor", sess)
    if term_start <= rel < term_end:
        return toggle_main_pane("term", sess)
    if zoomed and zoom_start <= rel < zoom_end:
        run_tmux("resize-pane", "-Z", "-t", f"={sess}:")
    return 0


def run_ai_popup(target_arg: str) -> None:
    """Launch ad-hoc floating AI CLI overlay inside `ai-<session>` (`Alt+Shift+A`)."""
    sess = resolve_target_session(target_arg)
    run_tmux("set-option", "-t", f"=ai-{sess}:", "status", "off")
    ai_cli = get_ide_var(sess, "@ide_ai_cli", "IDE_AI_CLI") or os.environ.get("IDE_AI_CLI") or "agy"
    ai_cmd = resolve_ai_cmd(ai_cli)
    if ai_cmd:
        subprocess.run(ai_cmd, shell=True, check=False)
    shell = os.environ.get("SHELL") or "/bin/zsh"
    os.execvp(shell, [shell, "-l"])


def _close_and_unlink_nvim_sockets(
    sess: str,
    sock: str,
    runtime_dir: str,
    max_polls: int,
    poll_step: float,
    check_each: bool = False,
) -> None:
    has_nvim = bool(resolve_nvim_bin())
    candidates = (sock, f"{runtime_dir}/nvim-{sess}.sock", f"{runtime_dir}/nvim-ide-{sess}.sock")
    if not check_each and sock and is_socket_path(sock) and has_nvim:
        if nvim_remote_send(sock, "<C-\\><C-n><Cmd>qall!<CR>"):
            for _ in range(max_polls):
                if not is_socket_path(sock):
                    break
                time.sleep(poll_step)
    for p in candidates:
        if check_each and p and is_socket_path(p) and has_nvim:
            nvim_remote_send(p, "<C-\\><C-n><Cmd>qall!<CR>")
            for _ in range(max_polls):
                if not is_socket_path(p):
                    break
                time.sleep(poll_step)
        if p:
            try:
                os.unlink(p)
            except OSError:
                pass


def quit_ide(target_args: list[str] | str, force_quit: bool, is_kill: bool) -> int:
    """Safely terminate one or more IDE sessions, guarding against unsaved Neovim buffers unless forced."""
    if isinstance(target_args, str):
        raw_targets = [target_args] if target_args else [""]
    else:
        raw_targets = list(target_args) if target_args else [""]

    try:
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
    except (OSError, ValueError):
        pass

    cur_sess = current_ide_session()
    in_popup = os.environ.get("IDE_IN_POPUP") == "1"
    resolved_targets: list[tuple[str, str]] = []
    seen_sess: set[str] = set()
    closed_switcher = False
    for raw in raw_targets:
        if is_switcher_session_name(raw):
            close_switcher_session(raw, action="none")
            closed_switcher = True
            continue
        sess = resolve_target_session(raw)
        dedup_key = sess or f"__empty_{raw}"
        if dedup_key in seen_sess:
            continue
        seen_sess.add(dedup_key)
        resolved_targets.append((raw, sess))

    if closed_switcher and not resolved_targets:
        return 0

    rc = 0
    to_kill: list[tuple[str, str]] = []
    for raw, sess in resolved_targets:
        if not sess or not session_exists(sess):
            print(missing_session_msg(sess))
            continue

        raw_sock = get_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET")
        sock = ensure_session_editor_socket(sess, raw_sock) if resolve_nvim_bin() else raw_sock
        if not force_quit and sock and is_socket_path(sock) and resolve_nvim_bin():
            modified = nvim_modified_buf_count(sock)
            if modified > 0:
                warn_msg = f"Unsaved changes in {modified} buffer(s) — press Enter or Ctrl+e to review"
                run_tmux("set-option", "-q", "-t", f"={sess}:", "@ide_quit_err", warn_msg)
                ed_warn = f"Unsaved changes in {modified} buffer(s)! Save (:wqa) or press Alt+Shift+Q (:Q!) to force-quit"
                nvim_remote_send(
                    sock,
                    f'<C-\\><C-n><Cmd>redraw! | echohl ErrorMsg | echo strcharpart("{ed_warn}", 0, max([1, v:echospace])) | echohl None<CR>',
                )
                if not in_popup:
                    toggle_main_pane("focus-editor", raw or sess, clear_quit_err=False)
                    msg_txt = (
                        f"Unsaved changes in {modified} buffer(s)! Save (:wqa) or press Alt+Shift+Q to force-quit"
                        if (not cur_sess or cur_sess == sess)
                        else f"Unsaved changes in '{sess}' ({modified} buffer(s))! Save (:wqa) or use --force"
                    )
                    run_tmux("display-message", "-d", "4000", "-t", f"={sess}:", msg_txt)
                    if cur_sess and cur_sess != sess and session_exists(cur_sess):
                        run_tmux("display-message", "-d", "4000", "-t", f"={cur_sess}:", msg_txt)
                print(
                    "Aborted quit: unsaved changes in Neovim buffer(s). Save first or use 'ide quit --force' (Alt+Shift+Q).",
                    file=sys.stderr,
                )
                rc = 1
                continue
            run_tmux("set-option", "-q", "-u", "-t", f"={sess}:", "@ide_quit_err")

        to_kill.append((sess, sock))

    if not to_kill:
        return rc

    for sess, _ in to_kill:
        undock_session_if_docked(sess)

    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    for sess, sock in to_kill:
        _close_and_unlink_nvim_sockets(sess, sock, runtime_dir, max_polls=30, poll_step=0.1)

    killing_set = {sess for sess, _ in to_kill}
    if os.environ.get("IDE_IN_POPUP") == "1":
        other_ide = [
            e for e in classify_ide_fleet(include_git=False, cur_sess="")
            if str(e["sess"]) not in killing_set
        ]
        next_sess = str(other_ide[0]["sess"]) if other_ide else ""
        if not next_sess:
            best_act = -1
            for s_ln in tmux_out("list-sessions", "-F", "#{session_activity}\t#{session_name}").splitlines():
                if "\t" not in s_ln:
                    continue
                s_act_raw, s_cand = s_ln.split("\t", 1)
                s_cand = s_cand.strip()
                if not s_cand or s_cand in killing_set or s_cand.startswith(("ai-", "agy-")):
                    continue
                s_act = int(s_act_raw.strip()) if s_act_raw.strip().isdigit() else 0
                if s_act >= best_act:
                    best_act = s_act
                    next_sess = s_cand
        if next_sess:
            for sess, _ in to_kill:
                for cl in tmux_out("list-clients", "-t", f"={sess}", "-F", "#{client_name}").splitlines():
                    cl_s = cl.strip()
                    if cl_s:
                        run_tmux("switch-client", "-c", cl_s, "-t", f"={next_sess}")

    if is_kill:
        for sess, _ in to_kill:
            print(f"Terminated IDE session: {sess}")
        try:
            sys.stdout.flush()
        except OSError:
            pass

    kill_order = [sess for sess, _ in to_kill if sess != cur_sess]
    if cur_sess and cur_sess in killing_set:
        kill_order.append(cur_sess)

    for sess in kill_order:
        for target_sess in (f"=ai-{sess}", f"=agy-{sess}", f"={sess}"):
            run_tmux("kill-session", "-t", target_sess)

    for sess, sock in to_kill:
        _close_and_unlink_nvim_sockets(sess, sock, runtime_dir, max_polls=10, poll_step=0.05, check_each=True)

    refresh_fleet_topbar()
    return rc


def cd_ide_workspace(raw_target: str, target_arg: str) -> int:
    """Synchronize `@ide_workdir` and `#{session_path}` across Editor and Shell without respawning AI."""
    sess = resolve_target_session(target_arg)
    if not session_exists(sess):
        print(f"Error: {missing_session_msg(sess)}", file=sys.stderr)
        return 1

    init_root = get_ide_var(sess, "@ide_initial_root", "IDE_INITIAL_ROOT")
    cur_workdir = get_ide_var(sess, "@ide_workdir", "IDE_WORKDIR") or init_root or safe_getcwd()

    if raw_target in ("--reset", "~", "-"):
        target_dir = init_root if (init_root and os.path.isdir(init_root)) else cur_workdir
    elif raw_target.startswith("/"):
        target_dir = raw_target
    else:
        cand1 = os.path.join(cur_workdir, raw_target)
        cand2 = os.path.join(init_root, raw_target) if init_root else ""
        if os.path.isdir(cand1):
            target_dir = cand1
        elif cand2 and os.path.isdir(cand2):
            target_dir = cand2
        else:
            target_dir = os.path.join(safe_getcwd(), raw_target)

    if not os.path.isdir(target_dir):
        print(f"Error: Directory '{target_dir}' does not exist.", file=sys.stderr)
        return 1
    target_dir = os.path.realpath(target_dir)
    updates = [("@ide_workdir", "IDE_WORKDIR", target_dir)]
    if not init_root:
        updates.append(("@ide_initial_root", "IDE_INITIAL_ROOT", target_dir))
    set_ide_vars(sess, updates)

    run_tmux("attach-session", "-t", f"={sess}", "-c", target_dir)

    raw_sock = get_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET")
    sock = ensure_session_editor_socket(sess, raw_sock) if resolve_nvim_bin() else raw_sock
    term_pane = resolve_role_pane(sess, "term", "@ide_term_pane", "IDE_TERM_PANE")
    escaped_dir = target_dir.replace("'", "''")

    if sock and is_socket_path(sock) and resolve_nvim_bin():
        nvim_remote_expr(sock, f"execute('cd ' . fnameescape('{escaped_dir}'))")

    if os.environ.get("IDE_CD_SKIP_SHELL", "0") != "1" and pane_exists(term_pane):
        info = tmux_out(
            "display-message",
            "-p",
            "-t",
            term_pane,
            TMUX_SEP.join(["#{pane_current_command}", "#{pane_current_path}"]),
        )
        if TMUX_SEP in info:
            term_cmd, term_path = info.split(TMUX_SEP, 1)
            if term_cmd.startswith(("zsh", "bash", "sh")) and term_path != target_dir:
                run_tmux("send-keys", "-t", term_pane, "C-u", f" builtin cd -- {shlex.quote(target_dir)}", "C-m")

    run_tmux("display-message", "-d", "2500", "-t", f"={sess}:", f"IDE Working Directory -> {target_dir}")
    return 0


def refresh_ide_sessions(target_arg: str, ide_self: str) -> int:
    """Reload tmux config/theme and heal Editor CWDs + themes over RPC without touching Shell panes."""
    raw_sessions, server_up = list_ide_sessions_with_server_status()
    if target_arg:
        if not server_up:
            print(f"Error: {missing_session_msg(target_arg)}", file=sys.stderr)
            return 1
        sess = resolve_target_session(target_arg)
        if not sess or not session_exists(sess) or not check_is_ide_session(sess):
            print(f"Error: {missing_session_msg(sess or target_arg)}", file=sys.stderr)
            return 1
        target_items = [item for item in raw_sessions if item["sess"] == sess]
    else:
        if not server_up or not raw_sessions:
            print("No active IDE sessions.")
            return 0
        target_items = raw_sessions

    tmux_conf = os.path.expanduser("~/.tmux.conf")
    if os.path.isfile(tmux_conf):
        run_tmux("source-file", tmux_conf)

    xdg_cfg = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    active_theme_file = os.path.join(xdg_cfg, "home-settings", "active-theme.theme")
    tmux_theme_conf = os.path.join(xdg_cfg, "home-settings", "tmux-theme.conf")
    if os.path.isfile(active_theme_file):
        theme_id = ""
        try:
            with open(active_theme_file, "r", encoding="utf-8") as fh:
                for line in fh:
                    s = line.strip()
                    if s.startswith("THEME_ID="):
                        theme_id = s.split("=", 1)[1].strip().strip('"').strip("'")
                        break
        except OSError:
            pass
        if theme_id:
            sib_theme = os.path.join(os.path.dirname(os.path.abspath(ide_self)), "theme") if ide_self else ""
            theme_bin = (
                sib_theme
                if (sib_theme and os.path.isfile(sib_theme) and os.access(sib_theme, os.X_OK))
                else (shutil.which("theme") or "")
            )
            if theme_bin:
                try:
                    subprocess.run(
                        [theme_bin, "--set", theme_id, "--no-live"],
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=5,
                        check=False,
                    )
                except (OSError, subprocess.SubprocessError):
                    pass
    if os.path.isfile(tmux_theme_conf):
        run_tmux("source-file", tmux_theme_conf)

    has_nvim = bool(resolve_nvim_bin())
    home_dir = os.path.expanduser("~")
    editors_refreshed = 0
    theme_reload_ex = (
        "if exists('*v:lua.apply_home_settings_theme') | silent! call v:lua.apply_home_settings_theme() | endif | "
        "if exists('*v:lua.refresh_home_settings_images') | silent! call v:lua.refresh_home_settings_images() | endif"
    )

    for item in target_items:
        sess = item["sess"]
        fb_dir = ""
        for cand_d in (
            item.get("workdir", ""),
            item.get("init_root", ""),
            get_ide_var(sess, "@ide_workdir", "IDE_WORKDIR"),
            get_ide_var(sess, "@ide_initial_root", "IDE_INITIAL_ROOT"),
            home_dir,
        ):
            if cand_d and os.path.isdir(cand_d):
                fb_dir = cand_d
                break

        raw_sock = item.get("ide_sock", "") or get_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET")
        sock = ensure_session_editor_socket(sess, raw_sock) if has_nvim else raw_sock
        if sock and is_socket_path(sock) and has_nvim:
            nvim_recover_and_checktime(sock, fb_dir, extra_ex=theme_reload_ex)
            editors_refreshed += 1

    refresh_fleet_topbar()
    msg = f"Refreshed {len(target_items)} IDE session(s) ({editors_refreshed} editor(s))"
    if os.environ.get("TMUX") or os.environ.get("IDE_CLIENT"):
        msg_sess = target_items[0]["sess"] if len(target_items) == 1 else current_ide_session()
        if msg_sess and session_exists(msg_sess):
            run_tmux("display-message", "-d", "2500", "-t", f"={msg_sess}:", msg)
        else:
            run_tmux("display-message", "-d", "2500", msg)
    print(msg)
    return 0


def launch_or_attach_workspace(
    target_arg: str,
    layout_mode: str,
    ai_cli_from_flag: bool,
    detach_mode: bool,
) -> int:
    """Create a new 2-pane or 3-pane IDE workspace session or re-attach to an existing one."""
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    ide_ai_cli = os.environ["IDE_AI_CLI"]
    ide_notify_env = os.environ.get("IDE_NOTIFY", "")

    if (
        target_arg
        and "/" not in target_arg
        and target_arg not in (".", "..")
        and not target_arg.startswith("~")
        and not os.path.isdir(target_arg)
        and session_exists(target_arg)
        and check_is_ide_session(target_arg)
    ):
        session = target_arg
        session_existed = True
        target_dir = (
            get_ide_var(session, "@ide_workdir", "IDE_WORKDIR")
            or get_ide_var(session, "@ide_initial_root", "IDE_INITIAL_ROOT")
            or safe_getcwd()
        )
        nvim_socket = (
            get_ide_var(session, "@ide_socket", "NVIM_IDE_SOCKET")
            or f"{runtime_dir}/nvim-ide-{session}.sock"
        )
    else:
        already_resolved = os.environ.pop("IDE_WORKSPACE_RESOLVED", "") == "1"
        if not target_arg:
            target_dir = safe_getcwd()
            if not os.path.isdir(target_dir):
                print(f"Error: Directory '{target_dir}' does not exist.", file=sys.stderr)
                return 1
            target_dir = os.path.abspath(target_dir)
        elif target_arg in (".", "..") or target_arg.startswith(("./", "../")):
            if not os.path.isdir(target_arg):
                print(f"Error: Directory '{target_arg}' does not exist.", file=sys.stderr)
                return 1
            target_dir = os.path.abspath(target_arg)
        else:
            cand_target = (
                os.path.expanduser(target_arg)
                if (target_arg == "~" or target_arg.startswith("~/"))
                else target_arg
            )
            if os.path.isdir(cand_target):
                abs_cand = os.path.abspath(cand_target)
                if already_resolved:
                    target_dir = abs_cand
                else:
                    hook_dir = resolve_workspace_target(abs_cand)
                    target_dir = hook_dir if hook_dir else abs_cand
            else:
                hook_dir = "" if already_resolved else resolve_workspace_target(target_arg)
                if not hook_dir:
                    print(f"Error: Directory '{target_arg}' does not exist.", file=sys.stderr)
                    return 1
                target_dir = hook_dir

        session = sanitize_session_name(target_dir)
        session_existed = session_exists(session)
        nvim_socket = (
            (get_ide_var(session, "@ide_socket", "NVIM_IDE_SOCKET") if session_existed else "")
            or f"{runtime_dir}/nvim-ide-{session}.sock"
        )

    if not session_existed:
        try:
            os.unlink(nvim_socket)
        except OSError:
            pass

        term_sz = shutil.get_terminal_size(fallback=(160, 48))
        cols = term_sz.columns if term_sz.columns >= 80 else 160
        lines = term_sz.lines if term_sz.lines >= 24 else 48

        base_env_args = _session_env_flags(
            session, ide_ai_cli, nvim_socket, target_dir, ide_notify=ide_notify_env
        )
        init_info = tmux_out(
            "new-session", "-d", "-P", "-F", "#{pane_id}\t#{window_id}",
            "-s", session, "-n", "ide", "-c", target_dir, "-x", str(cols), "-y", str(lines),
            *base_env_args,
        )
        pane_ai, main_win = (init_info.split("\t", 1) + [""])[:2]
        pane_editor = tmux_out(
            "split-window", "-h", "-P", "-F", "#{pane_id}",
            "-t", pane_ai, "-l", "50%", "-c", target_dir,
            *base_env_args,
        )

        var_pairs = [
            ("@ide_session", "IDE_SESSION", session),
            ("@ide_ai_cli", "IDE_AI_CLI", ide_ai_cli),
            ("@ide_socket", "NVIM_IDE_SOCKET", nvim_socket),
            ("@ide_initial_root", "IDE_INITIAL_ROOT", target_dir),
            ("@ide_workdir", "IDE_WORKDIR", target_dir),
            ("@ide_main_win", "IDE_MAIN_WIN", main_win),
            ("@ide_editor_pane", "NVIM_IDE_PANE", pane_editor),
            ("@ide_ai_pane", "IDE_AI_PANE", pane_ai),
            ("@ide_layout_mode", "IDE_LAYOUT_MODE", layout_mode),
            ("@ide_ai_parked", "IDE_AI_PARKED", "0"),
            ("@ide_ed_parked", "IDE_ED_PARKED", "0"),
            ("@ide_term_parked", "IDE_TERM_PARKED", "0" if layout_mode == "3pane" else "1"),
            ("@ide_ai_state", "IDE_AI_STATE", ""),
            ("@ide_ai_attn", "IDE_AI_ATTN", "0"),
            ("@ide_ai_attn_ts", "IDE_AI_ATTN_TS", ""),
            ("@ide_ai_state_ts", "IDE_AI_STATE_TS", str(int(time.time()))),
            ("@ide_ai_msg", "IDE_AI_MSG", ""),
            ("@ide_force_hyperlink", "FORCE_HYPERLINK", "1"),
        ]

        pane_term = ""
        if layout_mode == "3pane":
            pane_term = tmux_out(
                "split-window", "-f", "-v", "-P", "-F", "#{pane_id}",
                "-t", main_win, "-l", "25%", "-c", target_dir,
                *base_env_args, "-e", f"NVIM_IDE_PANE={pane_editor}",
            )
            var_pairs.append(("@ide_term_pane", "IDE_TERM_PANE", pane_term))

        role_cmds = [
            "set-option", "-w", "-t", main_win, "automatic-rename", "off",
            ";",
            "set-option", "-w", "-t", main_win, "allow-rename", "off",
            ";",
            "set-option", "-p", "-t", pane_ai, "@ide_role", "ai",
            ";",
            "set-option", "-p", "-t", pane_ai, "@ide_owner_sess", session,
            ";",
            "set-option", "-p", "-t", pane_editor, "@ide_role", "editor",
        ]
        if pane_term:
            role_cmds.extend([";", "set-option", "-p", "-t", pane_term, "@ide_role", "term"])
        run_tmux(*role_cmds)
        set_ide_vars(session, var_pairs)

        readme = os.path.join(target_dir, "README.md")
        send_editor_launch_keys(pane_editor, nvim_socket, readme if os.path.isfile(readme) else "")

        ai_run_cmd = resolve_ai_cmd(ide_ai_cli)
        if ai_run_cmd:
            run_tmux("send-keys", "-t", pane_ai, f" {ai_run_cmd}", "C-m")

        run_tmux("select-window", "-t", main_win, ";", "select-pane", "-t", pane_ai)
    else:
        undock_session_if_docked(session)
        ed_pane_existing = resolve_role_pane(session, "editor", "@ide_editor_pane", "NVIM_IDE_PANE")
        if pane_exists(ed_pane_existing):
            ensure_editor_nvim_running(ed_pane_existing, nvim_socket, sess=session)
        if ai_cli_from_flag:
            existing_ai_cli = get_ide_var(session, "@ide_ai_cli", "IDE_AI_CLI")
            set_ide_var(session, "@ide_ai_cli", "IDE_AI_CLI", ide_ai_cli)
            if ide_ai_cli != existing_ai_cli:
                set_ide_vars(
                    session,
                    [
                        ("@ide_ai_state", "IDE_AI_STATE", ""),
                        ("@ide_ai_attn", "IDE_AI_ATTN", "0"),
                        ("@ide_ai_attn_ts", "IDE_AI_ATTN_TS", ""),
                        ("@ide_ai_state_ts", "IDE_AI_STATE_TS", str(int(time.time()))),
                        ("@ide_ai_msg", "IDE_AI_MSG", ""),
                    ],
                )
                run_tmux("kill-session", "-t", f"=ai-{session}")
                ai_pane_id = resolve_role_pane(session, "ai", "@ide_ai_pane", "IDE_AI_PANE")
                ed_pane_id = ed_pane_existing
                init_root_val = get_ide_var(session, "@ide_initial_root", "IDE_INITIAL_ROOT") or target_dir
                if pane_exists(ai_pane_id):
                    respawn_env_args = _session_env_flags(
                        session,
                        ide_ai_cli,
                        nvim_socket,
                        init_root_val,
                        editor_pane=ed_pane_id,
                        ide_notify=ide_notify_env,
                    )
                    res = run_tmux(
                        "respawn-pane", "-k", "-t", ai_pane_id, "-c", target_dir,
                        *respawn_env_args,
                    )
                    if res.returncode != 0:
                        shell = os.environ.get("SHELL") or "/bin/zsh"
                        notify_kv = f"IDE_NOTIFY={shlex.quote(ide_notify_env)} " if ide_notify_env else ""
                        run_tmux(
                            "respawn-pane", "-k", "-t", ai_pane_id, "-c", target_dir,
                            f"env IDE_SESSION={shlex.quote(session)} IDE_AI_CLI={shlex.quote(ide_ai_cli)} "
                            f"NVIM_IDE_SOCKET={shlex.quote(nvim_socket)} NVIM_IDE_PANE={shlex.quote(ed_pane_id)} "
                            f"IDE_INITIAL_ROOT={shlex.quote(init_root_val)} {notify_kv}FORCE_HYPERLINK=1 {shlex.quote(shell)} -l",
                        )
                    ai_run_cmd = resolve_ai_cmd(ide_ai_cli)
                    if ai_run_cmd:
                        run_tmux("send-keys", "-t", ai_pane_id, f" {ai_run_cmd}", "C-m")

    caller_is_ssh = any(os.environ.get(v) for v in ("SSH_CONNECTION", "SSH_TTY", "SSH_CLIENT")) or (
        bool(os.environ.get("TMUX")) and is_ssh_session("")
    )
    env_cmds: list[str] = [
        "set-environment", "-g", "FORCE_HYPERLINK", "1",
        ";",
        "set-environment", "-t", f"={session}", "FORCE_HYPERLINK", "1",
        ";",
        "set-option", "-q", "-u", "-t", f"={session}:", "@ide_quit_err",
    ]
    if "IDE_NOTIFY" in os.environ:
        if ide_notify_env:
            env_cmds.extend([";", "set-environment", "-t", f"={session}", "IDE_NOTIFY", ide_notify_env])
        else:
            env_cmds.extend([";", "set-environment", "-t", f"={session}", "-u", "IDE_NOTIFY"])
    for ssh_var in ("SSH_CONNECTION", "SSH_TTY", "SSH_CLIENT"):
        ssh_val = os.environ.get(ssh_var)
        if caller_is_ssh and ssh_val:
            env_cmds.extend([";", "set-environment", "-t", f"={session}", ssh_var, ssh_val])
        elif not caller_is_ssh:
            env_cmds.extend([";", "set-environment", "-t", f"={session}", "-r", ssh_var])
    for display_var in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS"):
        val = os.environ.get(display_var)
        if val and not caller_is_ssh:
            env_cmds.extend([";", "set-environment", "-t", f"={session}", display_var, val])
        elif caller_is_ssh and display_var in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY"):
            env_cmds.extend([";", "set-environment", "-t", f"={session}", "-r", display_var])
        elif not caller_is_ssh and display_var in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY"):
            env_cmds.extend([";", "set-environment", "-t", f"={session}", "-u", display_var])
    run_tmux(*env_cmds)

    if not session_existed or tmux_out("show-options", "-gqv", "@ide_tmux_conf_loaded") != "1":
        if tmux_out("show-options", "-gqv", "@ide_tmux_conf_loaded") != "1":
            tmux_conf = os.path.expanduser("~/.tmux.conf")
            if os.path.isfile(tmux_conf):
                run_tmux("source-file", tmux_conf)
        xdg_cfg = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
        tmux_theme_conf = os.path.join(xdg_cfg, "home-settings", "tmux-theme.conf")
        if os.path.isfile(tmux_theme_conf):
            run_tmux("source-file", tmux_theme_conf)
    run_tmux("set-option", "-q", "-t", f"={session}:", "status-position", "top")
    refresh_fleet_topbar()

    if detach_mode:
        return 0

    if os.environ.get("TMUX"):
        os.execvp("tmux", ["tmux", "switch-client", "-t", f"={session}"])
    else:
        os.execvp("tmux", ["tmux", "attach-session", "-t", f"={session}"])
    return 0
