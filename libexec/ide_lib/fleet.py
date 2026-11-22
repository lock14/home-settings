"""Deterministic AI lifecycle state machine, notifications, and urgency-tier fleet classifier."""

from __future__ import annotations

import os
import re
import select
import shutil
import subprocess
import sys
import time

from ide_lib.constants import (
    TMUX_SEP,
    is_live_socket,
    is_switcher_session_name,
    sanitize_agent_msg,
    sanitize_http_url,
    shorten_home,
)
from ide_lib.hooks import ide_rules_with_fn
from ide_lib.proc import is_bare_shell_cmd, pane_has_child_procs, pids_with_children
from ide_lib.tmux import (
    check_is_ide_session,
    current_ide_session,
    discover_display_env,
    get_ide_var,
    is_ide_session_meta,
    is_ssh_session,
    missing_session_msg,
    open_browser_url,
    resolve_active_client,
    resolve_role_pane,
    resolve_target_session,
    run_tmux,
    session_exists,
    session_has_focused_client,
    tmux_out,
)

_HOOK_NOTIF_TYPE_RE = re.compile(r'"(?:notification_type|type)"\s*:\s*"([^"\\]+)"')


def build_ai_state_option_cmds(
    sess: str,
    state: str = "",
    attn: str = "0",
    attn_ts: str = "",
    state_ts: str = "",
    msg: str = "",
) -> list[str]:
    """Build chained tmux `set-option` arguments for the 5 `@ide_ai_*` lifecycle options."""
    target = f"={sess}:"
    return [
        "set-option", "-q", "-t", target, "@ide_ai_state", state,
        ";",
        "set-option", "-q", "-t", target, "@ide_ai_attn", attn,
        ";",
        "set-option", "-q", "-t", target, "@ide_ai_attn_ts", attn_ts,
        ";",
        "set-option", "-q", "-t", target, "@ide_ai_state_ts", state_ts,
        ";",
        "set-option", "-q", "-t", target, "@ide_ai_msg", msg,
    ]


_SESSION_FMT_FIELDS = (
    "#{session_name}",
    "#{session_activity}",
    "#{session_last_attached}",
    "#{session_attached}",
    "#{@ide_session}",
    "#{@ide_socket}",
    "#{@ide_main_win}",
    "#{@ide_ai_pane}",
    "#{@ide_editor_pane}",
    "#{@ide_ai_cli}",
    "#{@ide_workdir}",
    "#{@ide_initial_root}",
    "#{@ide_ai_state}",
    "#{@ide_ai_attn}",
    "#{@ide_ai_attn_ts}",
    "#{@ide_ai_state_ts}",
    "#{@ide_ai_parked}",
    "#{@ide_ai_msg}",
    "#{@ide_quit_err}",
)

_PANE_FMT_FIELDS = (
    "#{session_name}",
    "#{window_id}",
    "#{window_name}",
    "#{pane_id}",
    "#{pane_pid}",
    "#{pane_active}",
    "#{window_active}",
    "#{window_zoomed_flag}",
    "#{@ide_role}",
    "#{pane_current_path}",
    "#{pane_current_command}",
    "#{window_activity}",
    "#{@ide_sw_placeholder}",
)


def parse_ide_session_cols(cols: list[str]) -> dict[str, str] | None:
    """Parse 19 `_SESSION_FMT_FIELDS` columns into an IDE session dict, or `None` if non-IDE."""
    padded = (cols + [""] * 19)[:19]
    (
        sess_name,
        activity,
        last_attached,
        attached,
        ide_sess,
        ide_sock,
        ide_win,
        ai_pane,
        ed_pane,
        ai_cli,
        workdir,
        init_root,
        ai_state,
        ai_attn,
        ai_attn_ts,
        ai_state_ts,
        ai_parked,
        ai_msg,
        quit_err,
    ) = padded
    if not is_ide_session_meta(sess_name, ide_sess, ide_sock, ide_win):
        return None
    return {
        "sess": sess_name,
        "activity": activity,
        "last_attached": last_attached,
        "attached": attached,
        "ide_sess": ide_sess,
        "ide_sock": ide_sock,
        "ide_win": ide_win,
        "ai_pane": ai_pane,
        "ed_pane": ed_pane,
        "ai_cli": ai_cli or "agy",
        "workdir": workdir or init_root,
        "init_root": init_root or workdir,
        "ai_state": ai_state,
        "ai_attn": ai_attn,
        "ai_attn_ts": ai_attn_ts,
        "ai_state_ts": ai_state_ts,
        "ai_parked": ai_parked,
        "ai_msg": ai_msg,
        "quit_err": quit_err,
    }


def list_ide_sessions_with_server_status() -> tuple[list[dict[str, str]], bool]:
    """Query tmux `list-sessions` once and return `(ide_session_dicts, server_is_up)`."""
    res = run_tmux("list-sessions", "-F", TMUX_SEP.join(_SESSION_FMT_FIELDS))
    if res.returncode != 0:
        return ([], False)
    if not res.stdout:
        return ([], True)
    items: list[dict[str, str]] = []
    for line in res.stdout.splitlines():
        parsed = parse_ide_session_cols(line.split(TMUX_SEP))
        if parsed is not None:
            items.append(parsed)
    return (items, True)


def query_fleet_snapshot() -> tuple[list[dict[str, str]], list[list[str]], bool]:
    """Query `list-sessions` and `list-panes -a` in a single tmux IPC round-trip."""
    res = run_tmux(
        "list-sessions",
        "-F",
        TMUX_SEP.join(["SESS", *_SESSION_FMT_FIELDS]),
        ";",
        "list-panes",
        "-a",
        "-F",
        TMUX_SEP.join(["PANE", *_PANE_FMT_FIELDS]),
    )
    if res.returncode != 0:
        return ([], [], False)
    if not res.stdout:
        return ([], [], True)
    sess_pfx = f"SESS{TMUX_SEP}"
    pane_pfx = f"PANE{TMUX_SEP}"
    items: list[dict[str, str]] = []
    pane_rows: list[list[str]] = []
    for line in res.stdout.splitlines():
        if line.startswith(sess_pfx):
            parsed = parse_ide_session_cols(line.split(TMUX_SEP)[1:])
            if parsed is not None:
                items.append(parsed)
        elif line.startswith(pane_pfx):
            pane_rows.append((line.split(TMUX_SEP)[1:] + [""] * 13)[:13])
    return (items, pane_rows, True)


def list_ide_sessions_raw() -> list[dict[str, str]]:
    """Return raw metadata dictionaries for all active IDE sessions."""
    items, _ = list_ide_sessions_with_server_status()
    return items


def _parse_attn_ts(raw_ts: str, fallback: float) -> float:
    s = raw_ts.strip()
    if not s:
        return fallback
    try:
        val = float(s)
        return val if val > 0 else fallback
    except ValueError:
        return fallback


def format_elapsed_age(state_ts: float, now: float | None = None) -> str:
    """Format elapsed duration since `state_ts` as a compact `Xs`, `Xm`, `Xh`, or `Xd` token."""
    if state_ts <= 0:
        return ""
    cur = time.time() if now is None else now
    delta = max(0, int(cur - state_ts))
    if delta < 60:
        return f"{delta}s"
    if delta < 3600:
        return f"{delta // 60}m"
    if delta < 86400:
        return f"{delta // 3600}h"
    return f"{delta // 86400}d"


def format_attn_summary(fleet: list[dict[str, object]]) -> str:
    """Format `@ide_attn_summary` (`<oldest>` or `<oldest> +<N>`) prioritizing `ATTN` ahead of `DONE`."""
    attn_items = sorted(
        (
            (0 if str(e["state"]) == "ATTN" else 1, float(e["attn_ts"]), str(e["sess"]))
            for e in fleet
            if bool(e["needs_attn"])
        ),
        key=lambda x: (x[0], x[1], x[2]),
    )
    if not attn_items:
        return ""
    if len(attn_items) == 1:
        return attn_items[0][2]
    return f"{attn_items[0][2]} +{len(attn_items) - 1}"


def classify_ide_fleet(
    include_git: bool = True,
    cur_sess: str = "",
    git_only_sess: str = "",
    raw_sessions: list[dict[str, str]] | None = None,
    panes_rows: list[list[str]] | None = None,
    focused_sessions: set[str] | None = None,
    precomputed_git: dict[str, tuple[str, bool, str, str, str]] | None = None,
) -> list[dict[str, object]]:
    """Classify and sort all active IDE sessions across the 5-tier urgency hierarchy."""
    if raw_sessions is None:
        raw_sessions, snap_panes, _ = query_fleet_snapshot()
        if panes_rows is None:
            panes_rows = snap_panes
    if not raw_sessions:
        return []

    if panes_rows is None:
        panes_res = run_tmux("list-panes", "-a", "-F", TMUX_SEP.join(_PANE_FMT_FIELDS))
        panes_rows = (
            [(ln.split(TMUX_SEP) + [""] * 13)[:13] for ln in panes_res.stdout.splitlines()]
            if (panes_res.returncode == 0 and panes_res.stdout)
            else []
        )

    panes_by_sess: dict[str, list[tuple[str, str, str, str, str, str, str, str, str, str, str, str]]] = {}
    panes_by_id: dict[str, tuple[str, str, str, str, str, str, str, str, str, str, str, str, str]] = {}
    for pcols_raw in panes_rows:
        pcols = (pcols_raw + [""] * 13)[:13]
        row_tup = (
            pcols[1],
            pcols[2],
            pcols[3],
            pcols[4],
            pcols[5],
            pcols[6],
            pcols[7],
            pcols[8],
            pcols[9],
            pcols[10],
            pcols[11],
            pcols[12],
        )
        panes_by_sess.setdefault(pcols[0], []).append(row_tup)
        if pcols[3]:
            panes_by_id[pcols[3]] = (pcols[0], *row_tup)

    preview_pane_by_sess: dict[str, str] = {}
    active_role_by_sess: dict[str, str] = {}
    fallback_dir_by_sess: dict[str, str] = {}
    ai_pid_by_sess: dict[str, int] = {}
    ai_cmd_by_sess: dict[str, str] = {}
    ed_pid_by_sess: dict[str, int] = {}
    ed_cmd_by_sess: dict[str, str] = {}
    win_act_by_sess: dict[str, int] = {}
    ai_win_pane_focused_by_sess: dict[str, bool] = {}
    ai_sw_focused_sess_by_sess: dict[str, str] = {}

    for item in raw_sessions:
        sess = item["sess"]
        spanes = panes_by_sess.get(sess, [])
        rec_ai = item["ai_pane"]
        rec_ed = item.get("ed_pane", "")
        ide_win = item["ide_win"]
        ai_pid_str = ""
        ai_cmd_str = ""
        ed_pid_str = ""
        ed_cmd_str = ""
        visible_ai = ""
        active_vis_pane = ""
        first_vis_pane = ""
        act_role = ""
        fb_dir = ""
        max_win_act = 0
        ai_win_pane_focused = False
        for wid, wname, pid, ppid, p_act, w_act, w_zoom, prole, ppath, pcmd, w_act_ts, sw_ph in spanes:
            if rec_ai and pid == rec_ai and not ai_pid_str:
                ai_pid_str = ppid
                ai_cmd_str = pcmd
            if rec_ed and pid == rec_ed and not ed_pid_str:
                ed_pid_str = ppid
                ed_cmd_str = pcmd
            if w_act_ts.isdigit():
                max_win_act = max(max_win_act, int(w_act_ts))
            if wname.startswith("_ide_park_"):
                continue
            if sw_ph == "1":
                if w_act == "1" and p_act == "1":
                    act_role = "ai"
                continue
            if not first_vis_pane:
                first_vis_pane = pid
            if not fb_dir and ppath:
                fb_dir = ppath
            if w_act == "1" and p_act == "1":
                active_vis_pane = pid
                act_role = prole or "shell"
                if (
                    (not ide_win or wid == ide_win)
                    and (pid == rec_ai or prole == "ai")
                    and not (w_zoom == "1" and prole != "ai")
                ):
                    ai_win_pane_focused = True
            if rec_ai and pid == rec_ai:
                visible_ai = pid
        if rec_ai and not ai_pid_str and rec_ai in panes_by_id:
            d_sess, _, _, _, d_ppid, d_pact, d_wact, d_wzoom, d_prole, d_ppath, d_pcmd, _, _ = panes_by_id[rec_ai]
            if is_switcher_session_name(d_sess):
                ai_pid_str = d_ppid
                ai_cmd_str = d_pcmd
                if not fb_dir and d_ppath:
                    fb_dir = d_ppath
                if item.get("ai_parked") != "1":
                    visible_ai = rec_ai
                if d_wact == "1" and d_pact == "1" and not (d_wzoom == "1" and d_prole != "ai"):
                    ai_sw_focused_sess_by_sess[sess] = d_sess
        if not ai_pid_str:
            for _, _, _, ppid, _, _, _, prole, _, pcmd, _, _ in spanes:
                if prole == "ai":
                    ai_pid_str = ppid
                    ai_cmd_str = pcmd
                    break
        if not ed_pid_str:
            for _, _, _, ppid, _, _, _, prole, _, pcmd, _, _ in spanes:
                if prole == "editor":
                    ed_pid_str = ppid
                    ed_cmd_str = pcmd
                    break
        if not visible_ai:
            for _, wname, pid, _, _, _, _, prole, _, _, _, _ in spanes:
                if wname.startswith("_ide_park_"):
                    continue
                if prole == "ai":
                    visible_ai = pid
                    break
        preview_pane_by_sess[sess] = visible_ai or active_vis_pane or first_vis_pane
        active_role_by_sess[sess] = act_role or "ai"
        fallback_dir_by_sess[sess] = fb_dir
        win_act_by_sess[sess] = max_win_act
        ai_win_pane_focused_by_sess[sess] = ai_win_pane_focused
        if ai_pid_str.strip().isdigit():
            ai_pid_by_sess[sess] = int(ai_pid_str.strip())
            ai_cmd_by_sess[sess] = ai_cmd_str.strip()
        if ed_pid_str.strip().isdigit():
            ed_pid_by_sess[sess] = int(ed_pid_str.strip())
            ed_cmd_by_sess[sess] = ed_cmd_str.strip()

    alive_child_pids = pids_with_children(set(ai_pid_by_sess.values()) | set(ed_pid_by_sess.values()))
    stale_cleanup_cmds: list[str] = []
    now_ts = time.time()
    git_by_sess: dict[str, tuple[str, bool, str, str, str]] = {}
    if include_git:
        from ide_lib.git_info import git_summary, locate_git_dirs

        wd_to_sessions: dict[str, list[str]] = {}
        for item in raw_sessions:
            s_name = item["sess"]
            wd = item["workdir"] or fallback_dir_by_sess.get(s_name, "")
            if precomputed_git is not None and s_name in precomputed_git:
                git_by_sess[s_name] = precomputed_git[s_name]
            elif not git_only_sess or s_name == git_only_sess:
                wd_to_sessions.setdefault(wd, []).append(s_name)
            else:
                wt_r, _, _ = locate_git_dirs(wd)
                git_by_sess[s_name] = ("-", False, "-", "", wt_r)
        unique_wds = list(wd_to_sessions.keys())
        if len(unique_wds) == 1:
            wd0 = unique_wds[0]
            res0 = git_summary(wd0)
            for s_n in wd_to_sessions[wd0]:
                git_by_sess[s_n] = res0
        elif len(unique_wds) > 1:
            from concurrent.futures import ThreadPoolExecutor

            with ThreadPoolExecutor(max_workers=min(8, len(unique_wds))) as pool:
                futs = [(w_d, pool.submit(git_summary, w_d)) for w_d in unique_wds]
                for w_d, fut in futs:
                    res_w = fut.result()
                    for s_n in wd_to_sessions[w_d]:
                        git_by_sess[s_n] = res_w

    def _has_focused_client(target_s: str) -> bool:
        if focused_sessions is not None:
            return target_s in focused_sessions
        return session_has_focused_client(target_s)

    fleet: list[dict[str, object]] = []
    for item in raw_sessions:
        sess = item["sess"]
        workdir = item["workdir"] or fallback_dir_by_sess.get(sess, "")
        if include_git:
            git_branch, git_dirty, git_detail, git_pr_url, worktree_root = git_by_sess.get(
                sess, ("-", False, "-", "", "")
            )
        else:
            git_branch, git_dirty, git_detail, git_pr_url, worktree_root = ("-", False, "-", "", "")

        sess_act = int(item["activity"]) if item["activity"].isdigit() else 0
        raw_last_att = item.get("last_attached", "")
        last_att = int(raw_last_att) if raw_last_att.isdigit() else 0
        win_act = win_act_by_sess.get(sess, 0)
        act_ts = max(sess_act, last_att, win_act)
        ai_pid = ai_pid_by_sess.get(sess, 0)
        ai_cmd = ai_cmd_by_sess.get(sess, "")
        has_child = bool(ai_pid) and (
            ai_pid in alive_child_pids or not is_bare_shell_cmd(ai_cmd)
        )
        raw_state = item["ai_state"].strip().lower()
        raw_attn = item["ai_attn"].strip()
        raw_attn_ts = item["ai_attn_ts"].strip()
        raw_state_ts = item.get("ai_state_ts", "").strip()
        raw_ai_msg = item.get("ai_msg", "").strip()
        raw_quit_err = item.get("quit_err", "").strip()
        ide_sock = item.get("ide_sock", "").strip()
        if raw_quit_err:
            ed_pid = ed_pid_by_sess.get(sess, 0)
            ed_cmd = ed_cmd_by_sess.get(sess, "")
            ed_has_child = bool(ed_pid) and (
                ed_pid in alive_child_pids or not is_bare_shell_cmd(ed_cmd)
            )
            if not (ide_sock and is_live_socket(ide_sock)) and not ed_has_child:
                if stale_cleanup_cmds:
                    stale_cleanup_cmds.append(";")
                stale_cleanup_cmds.extend(["set-option", "-q", "-u", "-t", f"={sess}:", "@ide_quit_err"])
                raw_quit_err = ""
        needs_attn = False
        state_ts = 0.0
        ai_msg_out = raw_ai_msg

        if not has_child:
            state = "SHELL"
            attn_ts = 0.0
            state_label = "SHELL"
            ai_msg_out = ""
            if raw_state or raw_attn not in ("", "0") or raw_attn_ts or raw_state_ts or raw_ai_msg:
                if stale_cleanup_cmds:
                    stale_cleanup_cmds.append(";")
                stale_cleanup_cmds.extend(build_ai_state_option_cmds(sess))
        else:
            sw_foc_sess = ai_sw_focused_sess_by_sess.get(sess, "")
            ai_is_focused = (
                (
                    item["attached"] not in ("", "0")
                    and item.get("ai_parked") != "1"
                    and ai_win_pane_focused_by_sess.get(sess, False)
                    and _has_focused_client(sess)
                )
                or (bool(sw_foc_sess) and _has_focused_client(sw_foc_sess))
                if (raw_state == "done" and raw_attn == "1")
                else False
            )
            if raw_state == "done" and raw_attn == "1" and ai_is_focused:
                raw_state = "idle"
                raw_attn = "0"
                raw_attn_ts = ""
                raw_state_ts = str(int(now_ts))
                ai_msg_out = ""
                if stale_cleanup_cmds:
                    stale_cleanup_cmds.append(";")
                stale_cleanup_cmds.extend(
                    build_ai_state_option_cmds(sess, state="idle", state_ts=raw_state_ts)
                )
            needs_attn = bool(raw_attn == "1")
            attn_ts = _parse_attn_ts(raw_attn_ts, float(act_ts or now_ts)) if needs_attn else 0.0
            if raw_state == "approval" or (raw_attn == "1" and raw_state != "done"):
                state = "ATTN"
            elif raw_state == "quota":
                state = "QUOTA"
            elif raw_state == "running":
                state = "WORKING"
            elif raw_state == "done":
                state = "DONE"
            elif raw_state == "idle":
                state = "IDLE"
            else:
                state = "-"
            state_ts = _parse_attn_ts(raw_state_ts, 0.0)
            if state_ts <= 0 and state in ("ATTN", "DONE") and raw_attn_ts:
                state_ts = _parse_attn_ts(raw_attn_ts, 0.0)
            if state in ("ATTN", "QUOTA", "WORKING", "DONE", "IDLE") and state_ts > 0:
                state_label = f"{state} {format_elapsed_age(state_ts, now_ts)}"
            else:
                state_label = state

        fleet.append({
            "sess": sess,
            "ai_cli": item["ai_cli"] or "agy",
            "state": state,
            "state_label": state_label,
            "state_ts": state_ts,
            "needs_attn": needs_attn,
            "attn_ts": attn_ts,
            "ai_msg": ai_msg_out,
            "quit_err": raw_quit_err,
            "ide_sock": ide_sock,
            "workdir": workdir,
            "short_path": shorten_home(workdir),
            "git_branch": git_branch,
            "git_dirty": git_dirty,
            "git_detail": git_detail,
            "git_pr_url": git_pr_url,
            "worktree_root": os.path.realpath(worktree_root) if worktree_root else "",
            "worktree_peers": [],
            "preview_pane": preview_pane_by_sess.get(sess, ""),
            "active_role": active_role_by_sess.get(sess, "ai"),
            "attached": item["attached"] not in ("", "0"),
            "activity": act_ts,
            "last_attached": last_att,
            "window_activity": win_act,
            "is_current": sess == cur_sess,
        })

    def _fleet_sort_key(entry: dict[str, object]) -> tuple[int, int, float, int, int, int, int, str]:
        st = str(entry["state"])
        needs_attn_flag = bool(entry["needs_attn"])
        sess_name = str(entry["sess"])
        if st == "ATTN":
            sub = 0 if needs_attn_flag else 1
            ts = (
                float(entry["attn_ts"])
                if needs_attn_flag
                else (float(entry.get("state_ts") or 0.0) or float(entry["activity"]))
            )
            return (0, sub, ts, 0, 0, 0, 0, sess_name)
        if st == "DONE" and needs_attn_flag:
            return (1, 0, float(entry["attn_ts"]), 0, 0, 0, 0, sess_name)
        is_cur = 0 if bool(entry["is_current"]) else 1
        neg_act = -int(entry["activity"])
        neg_att = -int(entry.get("last_attached", 0))
        neg_win = -int(entry.get("window_activity", 0))
        if st == "WORKING":
            return (2, 0, 0.0, is_cur, neg_act, neg_att, neg_win, sess_name)
        if st == "QUOTA":
            return (2, 1, 0.0, is_cur, neg_act, neg_att, neg_win, sess_name)
        if st == "SHELL":
            return (4, 0, 0.0, is_cur, neg_act, neg_att, neg_win, sess_name)
        return (3, 0, 0.0, is_cur, neg_act, neg_att, neg_win, sess_name)

    fleet.sort(key=_fleet_sort_key)

    if include_git:
        by_worktree: dict[str, list[dict[str, object]]] = {}
        for entry in fleet:
            wt = str(entry.get("worktree_root") or "")
            if wt:
                by_worktree.setdefault(wt, []).append(entry)
        for peers in by_worktree.values():
            if len(peers) >= 2 and any(str(p["state"]) == "WORKING" for p in peers):
                for entry in peers:
                    entry["worktree_peers"] = [str(p["sess"]) for p in peers if p is not entry]

    if stale_cleanup_cmds:
        active_cnt = sum(1 for e in fleet if e["state"] == "WORKING")
        stale_cleanup_cmds.extend([
            ";",
            "set-option", "-gq", "@ide_fleet_count", str(len(fleet)),
            ";",
            "set-option", "-gq", "@ide_fleet_active", str(active_cnt),
            ";",
            "set-option", "-gq", "@ide_attn_summary", format_attn_summary(fleet),
            ";",
            "refresh-client", "-S",
        ])
        run_tmux(*stale_cleanup_cmds)

    return fleet


def populate_fleet_git(fleet: list[dict[str, object]]) -> None:
    """Populate `git_*`, `worktree_root`, and `worktree_peers` in place across `fleet` in parallel."""
    if not fleet:
        return
    from ide_lib.git_info import git_summary

    wd_to_entries: dict[str, list[dict[str, object]]] = {}
    for entry in fleet:
        wd_to_entries.setdefault(str(entry.get("workdir") or ""), []).append(entry)

    git_by_wd: dict[str, tuple[str, bool, str, str, str]] = {}
    unique_wds = list(wd_to_entries.keys())
    if len(unique_wds) == 1:
        git_by_wd[unique_wds[0]] = git_summary(unique_wds[0])
    else:
        from concurrent.futures import ThreadPoolExecutor

        with ThreadPoolExecutor(max_workers=min(8, len(unique_wds))) as pool:
            futs = [(w_d, pool.submit(git_summary, w_d)) for w_d in unique_wds]
            for w_d, fut in futs:
                git_by_wd[w_d] = fut.result()

    by_worktree: dict[str, list[dict[str, object]]] = {}
    for wd, entries in wd_to_entries.items():
        gb, gd, gdet, gpr, wt_raw = git_by_wd[wd]
        wt_real = os.path.realpath(wt_raw) if wt_raw else ""
        for entry in entries:
            entry["git_branch"] = gb
            entry["git_dirty"] = gd
            entry["git_detail"] = gdet
            entry["git_pr_url"] = gpr
            entry["worktree_root"] = wt_real
            entry["worktree_peers"] = []
            if wt_real:
                by_worktree.setdefault(wt_real, []).append(entry)

    for peers in by_worktree.values():
        if len(peers) >= 2 and any(str(p["state"]) == "WORKING" for p in peers):
            for entry in peers:
                entry["worktree_peers"] = [str(p["sess"]) for p in peers if p is not entry]


def refresh_fleet_topbar(notify_switchers: bool = False) -> int:
    """Recompute and publish `@ide_fleet_count`, `@ide_fleet_active`, and `@ide_attn_summary`."""
    sw_fzf_candidates: list[str] = []
    if notify_switchers:
        res = run_tmux(
            "list-sessions",
            "-F",
            TMUX_SEP.join([
                "SESS",
                *_SESSION_FMT_FIELDS,
                "#{@ide_switcher}",
                "#{@ide_sw_done}",
                "#{@ide_sw_mode}",
                "#{@ide_sw_fzf_pane}",
            ]),
            ";",
            "list-panes",
            "-a",
            "-F",
            TMUX_SEP.join(["PANE", *_PANE_FMT_FIELDS]),
        )
        if res.returncode != 0:
            return 0
        raw_sessions: list[dict[str, str]] = []
        pane_rows: list[list[str]] = []
        sw_panes_raw: list[str] = []
        sess_pfx = f"SESS{TMUX_SEP}"
        pane_pfx = f"PANE{TMUX_SEP}"
        for line in (res.stdout or "").splitlines():
            if line.startswith(sess_pfx):
                cols = (line.split(TMUX_SEP)[1:] + [""] * 23)[:23]
                parsed = parse_ide_session_cols(cols[:19])
                if parsed is not None:
                    raw_sessions.append(parsed)
                elif cols[19].strip() == "1" and cols[20].strip() != "1" and cols[21].strip() != "new":
                    fp = cols[22].strip()
                    if fp:
                        sw_panes_raw.append(fp)
            elif line.startswith(pane_pfx):
                pane_rows.append((line.split(TMUX_SEP)[1:] + [""] * 13)[:13])
        if sw_panes_raw:
            live_pane_ids = {pr[3] for pr in pane_rows if len(pr) > 3 and pr[3]}
            sw_fzf_candidates = [fp for fp in sw_panes_raw if fp in live_pane_ids]
    else:
        raw_sessions, pane_rows, server_up = query_fleet_snapshot()
        if not server_up:
            return 0

    fleet = (
        classify_ide_fleet(include_git=False, cur_sess="", raw_sessions=raw_sessions, panes_rows=pane_rows)
        if raw_sessions
        else []
    )
    fleet_count = len(fleet)
    active_count = sum(1 for e in fleet if e["state"] == "WORKING")
    attn_summary = format_attn_summary(fleet)

    cmds: list[str] = [
        "set-option", "-gq", "@ide_fleet_count", str(fleet_count),
        ";",
        "set-option", "-gq", "@ide_fleet_active", str(active_count),
        ";",
        "set-option", "-gq", "@ide_attn_summary", attn_summary,
        ";",
        "refresh-client", "-S",
    ]
    for fp in sw_fzf_candidates:
        cmds.extend([";", "send-keys", "-t", fp, "F12"])
    run_tmux(*cmds)
    return 0


def inspect_session_ai_view(sess: str, need_focus: bool = True) -> dict[str, object]:
    """Snapshot AI visibility, focus, and `@ide_ai_*` state for `sess` in a single tmux query."""
    empty_view: dict[str, object] = {
        "exists": False,
        "is_ide": False,
        "ai_visible": False,
        "ai_focused": False,
        "ai_pane": "",
        "ai_state": "",
        "ai_attn": "",
        "ai_attn_ts": "",
        "ai_state_ts": "",
        "ai_cli": "agy",
        "workdir": "",
        "ai_msg": "",
    }
    if not sess:
        return empty_view
    res = run_tmux(
        "display-message",
        "-p",
        "-t",
        f"={sess}:",
        TMUX_SEP.join([
            "#{session_name}",
            "#{session_attached}",
            "#{@ide_session}",
            "#{@ide_socket}",
            "#{window_id}",
            "#{window_name}",
            "#{window_active}",
            "#{window_zoomed_flag}",
            "#{pane_active}",
            "#{@ide_role}",
            "#{@ide_main_win}",
            "#{@ide_ai_pane}",
            "#{@ide_ai_parked}",
            "#{@ide_ai_state}",
            "#{@ide_ai_attn}",
            "#{@ide_ai_attn_ts}",
            "#{@ide_ai_state_ts}",
            "#{@ide_ai_cli}",
            "#{@ide_workdir}",
            "#{@ide_initial_root}",
            "#{@ide_ai_msg}",
            "#{@ide_docked_in}",
        ]),
    )
    raw = (res.stdout or "").rstrip("\r\n") if res.returncode == 0 and isinstance(res.stdout, str) else ""
    if not raw or TMUX_SEP not in raw:
        return empty_view
    parts = (raw.split(TMUX_SEP) + [""] * 22)[:22]
    (
        sess_name,
        sess_attached,
        ide_sess,
        ide_sock,
        win_id,
        wname,
        win_active,
        zoomed,
        pane_active,
        prole,
        main_win,
        ai_pane,
        ai_parked,
        ai_state,
        ai_attn,
        ai_attn_ts,
        ai_state_ts,
        ai_cli,
        raw_workdir,
        raw_init_root,
        ai_msg,
        docked_in,
    ) = parts
    sess_name = sess_name.strip()
    sess_attached = sess_attached.strip()
    ide_sess = ide_sess.strip()
    ide_sock = ide_sock.strip()
    win_id = win_id.strip()
    wname = wname.strip()
    win_active = win_active.strip()
    zoomed = zoomed.strip()
    pane_active = pane_active.strip()
    prole = prole.strip()
    main_win = main_win.strip()
    ai_pane = ai_pane.strip()
    ai_parked = ai_parked.strip()
    ai_state = ai_state.strip()
    ai_attn = ai_attn.strip()
    ai_attn_ts = ai_attn_ts.strip()
    ai_state_ts = ai_state_ts.strip()
    ai_cli = ai_cli.strip()
    workdir = raw_workdir.rstrip("\r\n")
    init_root = raw_init_root.rstrip("\r\n")
    ai_msg = ai_msg.strip()
    docked_in = docked_in.strip()
    sess_exists = sess_name == sess
    is_ide = sess_exists and is_ide_session_meta(sess_name, ide_sess, ide_sock, main_win)
    geom_visible = (
        is_ide
        and sess_attached not in ("", "0")
        and win_active == "1"
        and not wname.startswith("_ide_park_")
        and (not main_win or win_id == main_win)
        and ai_parked != "1"
        and not (zoomed == "1" and prole != "ai")
        and not is_switcher_session_name(docked_in)
    )
    has_focus = session_has_focused_client(sess) if (need_focus and geom_visible) else False
    ai_visible = has_focus and geom_visible
    ai_focused = ai_visible and pane_active == "1" and prole == "ai"
    if is_ide and is_switcher_session_name(docked_in):
        sw_raw = tmux_out(
            "display-message",
            "-p",
            "-t",
            f"={docked_in}:",
            TMUX_SEP.join([
                "#{session_attached}",
                "#{window_active}",
                "#{window_zoomed_flag}",
                "#{pane_active}",
                "#{pane_id}",
                "#{@ide_sw_docked_pane}",
                "#{@ide_sw_docked_sess}",
            ]),
        )
        if sw_raw and TMUX_SEP in sw_raw:
            sw_att, sw_wact, sw_zoom, sw_pact, sw_pid, sw_dp, sw_ds = (
                p.strip() for p in (sw_raw.split(TMUX_SEP) + [""] * 7)[:7]
            )
            sw_geom = (
                sw_ds == sess
                and bool(sw_dp)
                and sw_att not in ("", "0")
                and sw_wact == "1"
                and not (sw_zoom == "1" and sw_pid != sw_dp)
            )
            if sw_geom:
                sw_foc = session_has_focused_client(docked_in) if need_focus else False
                ai_visible = ai_visible or sw_foc
                ai_focused = ai_focused or (sw_foc and sw_pact == "1" and sw_pid == sw_dp)
    return {
        "exists": sess_exists,
        "is_ide": is_ide,
        "ai_visible": ai_visible,
        "ai_focused": ai_focused,
        "ai_pane": ai_pane,
        "ai_state": ai_state.lower(),
        "ai_attn": ai_attn,
        "ai_attn_ts": ai_attn_ts,
        "ai_state_ts": ai_state_ts,
        "ai_cli": ai_cli or "agy",
        "workdir": workdir or init_root,
        "ai_msg": ai_msg,
    }


def _drain_hook_stdin(max_keep_bytes: int = 1048576, max_drain_bytes: int = 16777216) -> str:
    try:
        if sys.stdin is None or sys.stdin.isatty():
            return ""
        fd = sys.stdin.fileno()
    except (OSError, ValueError, AttributeError):
        return ""
    chunks: list[bytes] = []
    kept = 0
    drained = 0
    started_json = False
    ended_json = False
    timeout = 0.02
    while drained < max_drain_bytes:
        try:
            ready, _, _ = select.select([fd], [], [], timeout)
        except (OSError, ValueError):
            break
        if not ready:
            break
        try:
            data = os.read(fd, min(65536, max_drain_bytes - drained))
        except OSError:
            break
        if not data:
            break
        if drained == 0:
            s_lead = data.lstrip()
            started_json = s_lead.startswith(b"{")
        drained += len(data)
        s_tail = data.rstrip()
        if s_tail:
            ended_json = s_tail.endswith(b"}")
        if kept < max_keep_bytes:
            take = data[: max_keep_bytes - kept]
            chunks.append(take)
            kept += len(take)
        timeout = 0.05 if (started_json and not ended_json) else 0.005
    return b"".join(chunks).decode("utf-8", errors="replace") if chunks else ""


def _parse_hook_metadata(stdin_raw: str, json_args: list[str]) -> tuple[str, str]:
    notif_type = ""
    msg = ""
    candidates: list[str] = list(json_args)
    if stdin_raw.strip():
        candidates.append(stdin_raw.strip())
    for raw in candidates:
        s = raw.strip()
        if not s.startswith("{"):
            continue
        obj = None
        if s.endswith("}"):
            import json

            try:
                parsed = json.loads(s)
                if isinstance(parsed, dict):
                    obj = parsed
            except ValueError:
                obj = None
        if obj is not None:
            if not notif_type:
                nt = obj.get("notification_type") or obj.get("type") or ""
                if isinstance(nt, str) and nt.strip():
                    notif_type = nt.strip().lower()
            if not msg:
                for k in ("message", "last-assistant-message", "last_assistant_message", "summary", "title"):
                    val = obj.get(k)
                    if isinstance(val, str) and val.strip():
                        cleaned = " ".join(val.split())
                        msg = (cleaned[:199] + "…") if len(cleaned) > 200 else cleaned
                        break
        elif not notif_type:
            m_nt = _HOOK_NOTIF_TYPE_RE.search(s)
            if m_nt and m_nt.group(1).strip():
                notif_type = m_nt.group(1).strip().lower()
    return (notif_type, msg)


def _resolve_ide_notify_policy(sess: str) -> str:
    raw = ""
    if "IDE_NOTIFY" in os.environ and os.environ["IDE_NOTIFY"].strip() != "":
        raw = os.environ["IDE_NOTIFY"]
    elif "IDE_NOTIFY" in os.environ and not os.environ.get("TMUX"):
        raw = os.environ["IDE_NOTIFY"]
    else:
        seen_in_sess = False
        if sess:
            sess_line = tmux_out("show-environment", "-t", f"={sess}", "IDE_NOTIFY").strip()
            if sess_line == "-IDE_NOTIFY":
                seen_in_sess = True
                raw = ""
            elif sess_line.startswith("IDE_NOTIFY="):
                seen_in_sess = True
                raw = sess_line[len("IDE_NOTIFY="):]
        if not seen_in_sess:
            glob_line = tmux_out("show-environment", "-g", "IDE_NOTIFY").strip()
            if glob_line.startswith("IDE_NOTIFY="):
                raw = glob_line[len("IDE_NOTIFY="):]
    norm = raw.strip().lower()
    if norm in ("1", "true", "on", "yes", "unfocused"):
        return "unfocused"
    if norm == "always":
        return "always"
    return "off"


def _spawn_detached(cmd: list[str], env: dict[str, str] | None = None) -> bool:
    try:
        subprocess.Popen(
            cmd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=True,
            start_new_session=True,
            env=env,
        )
        return True
    except OSError:
        return False


def _escape_terminal_notifier(text: str) -> str:
    if text and text[0] in '[({<"\\':
        return "\\" + text
    return text


def _dispatch_agent_notification(
    state: str,
    sess: str,
    message: str,
    ai_visible: bool,
    ai_cli: str = "",
    workdir: str = "",
) -> None:
    eff_cli = ai_cli or get_ide_var(sess, "@ide_ai_cli", "IDE_AI_CLI") or "agy"
    eff_workdir = (
        workdir
        or get_ide_var(sess, "@ide_workdir", "IDE_WORKDIR")
        or get_ide_var(sess, "@ide_initial_root", "IDE_INITIAL_ROOT")
        or ""
    )
    title = f"IDE [{sess}] · Approval needed" if state == "approval" else f"IDE [{sess}] · Turn complete"
    clean_msg = sanitize_agent_msg(message, max_chars=200) if message else ""
    body = clean_msg or (
        f"{eff_cli} is waiting for input in {sess}"
        if state == "approval"
        else f"{eff_cli} finished turn in {sess}"
    )

    rules = ide_rules_with_fn("ide_notify")
    if rules:
        _spawn_detached([
            "bash",
            "-c",
            '. "$1" && declare -F ide_notify >/dev/null && ide_notify "$2" "$3" "$4" "$5" "$6" "$7"',
            "ide",
            rules,
            state,
            sess,
            eff_cli,
            eff_workdir,
            title,
            body,
        ])

    policy = _resolve_ide_notify_policy(sess)
    if policy == "off" or is_ssh_session(sess):
        return
    if policy == "unfocused" and ai_visible:
        return

    sync_id = f"ide-{sess}"
    if sys.platform == "darwin":
        tn_bin = shutil.which("terminal-notifier")
        osa_bin = shutil.which("osascript")
        tn_title = _escape_terminal_notifier(title)
        tn_body = _escape_terminal_notifier(body)
        osa_script = "on run argv\ndisplay notification (item 2 of argv) with title (item 1 of argv)\nend run"
        if tn_bin and osa_bin:
            _spawn_detached([
                "sh",
                "-c",
                '"$1" -title "$2" -message "$3" -group "$4" || "$5" -e "$6" -- "$7" "$8"',
                "ide-notify",
                tn_bin,
                tn_title,
                tn_body,
                sync_id,
                osa_bin,
                osa_script,
                title,
                body,
            ])
        elif tn_bin:
            _spawn_detached([tn_bin, "-title", tn_title, "-message", tn_body, "-group", sync_id])
        elif osa_bin:
            _spawn_detached([osa_bin, "-e", osa_script, "--", title, body])
        return

    discover_display_env(sess)
    if not (
        os.environ.get("DBUS_SESSION_BUS_ADDRESS")
        or os.environ.get("DISPLAY")
        or os.environ.get("WAYLAND_DISPLAY")
    ):
        return
    import html

    esc_body = html.escape(body, quote=False)
    busctl_bin = shutil.which("busctl")
    nsend_bin = shutil.which("notify-send")
    env_copy = os.environ.copy()
    if busctl_bin and nsend_bin:
        _spawn_detached(
            [
                "sh",
                "-c",
                '"$1" --user --auto-start=no -- call org.freedesktop.Notifications /org/freedesktop/Notifications '
                'org.freedesktop.Notifications Notify \'susssasa{sv}i\' ide 0 "" "$2" "$3" 0 2 urgency y 1 '
                'x-canonical-private-synchronous s "$4" -1 || '
                '"$5" -a ide -u normal -h "string:x-canonical-private-synchronous:$4" -- "$2" "$3"',
                "ide-notify",
                busctl_bin,
                title,
                esc_body,
                sync_id,
                nsend_bin,
            ],
            env=env_copy,
        )
    elif busctl_bin:
        _spawn_detached(
            [
                busctl_bin,
                "--user",
                "--auto-start=no",
                "--",
                "call",
                "org.freedesktop.Notifications",
                "/org/freedesktop/Notifications",
                "org.freedesktop.Notifications",
                "Notify",
                "susssasa{sv}i",
                "ide",
                "0",
                "",
                title,
                esc_body,
                "0",
                "2",
                "urgency",
                "y",
                "1",
                "x-canonical-private-synchronous",
                "s",
                sync_id,
                "-1",
            ],
            env=env_copy,
        )
    elif nsend_bin:
        _spawn_detached(
            [
                nsend_bin,
                "-a",
                "ide",
                "-u",
                "normal",
                "-h",
                f"string:x-canonical-private-synchronous:{sync_id}",
                "--",
                title,
                esc_body,
            ],
            env=env_copy,
        )


def set_agent_state(
    raw_state: str,
    target_arg: str,
    message: str = "",
    json_args: list[str] | None = None,
) -> int:
    """Transition deterministic AI lifecycle state (`running`, `approval`, `quota`, `done`, `idle`)."""
    stdin_raw = _drain_hook_stdin()
    state = raw_state.strip().lower()
    if state not in ("running", "approval", "quota", "done", "idle"):
        print(
            f"Error: Invalid '--agent-state' value '{raw_state}'. Expected: running, approval, quota, done, or idle.",
            file=sys.stderr,
        )
        return 1

    notif_type, meta_msg = _parse_hook_metadata(stdin_raw, json_args or [])
    if notif_type == "idle_prompt":
        return 0

    if target_arg:
        sess = resolve_target_session(target_arg)
        if not sess:
            print(f"Error: {missing_session_msg(sess or target_arg)}", file=sys.stderr)
            return 1
    else:
        if not os.environ.get("TMUX"):
            return 0
        sess = current_ide_session()
        if not sess:
            return 0

    view = inspect_session_ai_view(sess, need_focus=(state in ("approval", "done")))
    if not view["exists"] or not view["is_ide"]:
        if target_arg:
            print(f"Error: {missing_session_msg(sess or target_arg)}", file=sys.stderr)
            return 1
        return 0
    prev_state = str(view["ai_state"])
    raw_prev_attn = str(view["ai_attn"])
    prev_attn = "1" if raw_prev_attn == "1" else "0"
    cur_ts = str(view["ai_attn_ts"])
    cur_state_ts = str(view["ai_state_ts"])
    prev_msg = str(view.get("ai_msg") or "")
    ai_visible = bool(view["ai_visible"])
    ai_focused = bool(view["ai_focused"])
    now = time.time()
    state_ts_val = cur_state_ts if (prev_state == state and cur_state_ts) else str(int(now))

    raw_msg = message.strip() or meta_msg
    clean_msg = sanitize_agent_msg(raw_msg)
    if state in ("approval", "quota", "done"):
        msg_val = clean_msg if clean_msg else (prev_msg if prev_state == state else "")
    else:
        msg_val = ""

    if state in ("approval", "done"):
        if ai_focused:
            next_attn = "0"
            attn_ts_val = ""
        else:
            next_attn = "1"
            attn_ts_val = cur_ts if (prev_attn == "1" and cur_ts) else f"{now:.6f}"
    else:
        next_attn = "0"
        attn_ts_val = ""

    if not (
        prev_state == state
        and raw_prev_attn == next_attn
        and cur_ts == attn_ts_val
        and cur_state_ts == state_ts_val
        and prev_msg == msg_val
    ):
        run_tmux(
            *build_ai_state_option_cmds(
                sess,
                state=state,
                attn=next_attn,
                attn_ts=attn_ts_val,
                state_ts=state_ts_val,
                msg=msg_val,
            )
        )

    refresh_fleet_topbar(notify_switchers=True)
    if next_attn == "1" and state in ("approval", "done") and (prev_state != state or prev_attn != "1"):
        _dispatch_agent_notification(
            state,
            sess,
            raw_msg,
            ai_visible,
            ai_cli=str(view["ai_cli"]),
            workdir=str(view["workdir"]),
        )
    return 0


def ack_ai_session(
    targets: list[str] | str,
    from_hook: bool = False,
    refresh_always: bool = True,
    entering_ai: bool = False,
) -> int:
    """Acknowledge AI attention on one or more sessions (`done` -> `idle`, `approval` muted)."""
    raw_list = [targets] if isinstance(targets, str) else list(targets)
    cleaned_targets = [t for t in raw_list if t]
    resolved_sessions: list[str] = []
    if cleaned_targets:
        for t_arg in cleaned_targets:
            cand = resolve_target_session(t_arg)
            if cand and cand not in resolved_sessions:
                resolved_sessions.append(cand)
    elif os.environ.get("TMUX"):
        cur = current_ide_session()
        if cur:
            resolved_sessions.append(cur)

    should_refresh = refresh_always
    batch_cmds: list[str] = []
    now_s = str(int(time.time()))
    need_focus = bool(from_hook and not entering_ai)

    for sess in resolved_sessions:
        if not sess:
            continue
        view = inspect_session_ai_view(sess, need_focus=need_focus)
        if not view["exists"] or not view["is_ide"]:
            continue
        ai_focused = bool(view["ai_focused"])
        ai_state = str(view["ai_state"])
        ai_attn = str(view["ai_attn"])
        cur_state_ts = str(view["ai_state_ts"])
        prev_msg = str(view.get("ai_msg") or "")
        ai_pane_id = str(view.get("ai_pane") or "") or resolve_role_pane(sess, "ai", "@ide_ai_pane", "IDE_AI_PANE")

        if ai_state or ai_attn not in ("", "0") or prev_msg:
            ai_alive = False
            if ai_pane_id:
                p_info = tmux_out(
                    "display-message",
                    "-p",
                    "-t",
                    ai_pane_id,
                    TMUX_SEP.join(["#{pane_id}", "#{pane_pid}", "#{pane_current_command}"]),
                )
                if p_info and TMUX_SEP in p_info:
                    got_id, p_pid, p_cmd = (p_info.split(TMUX_SEP, 2) + ["", "", ""])[:3]
                    if got_id == ai_pane_id:
                        ai_alive = pane_has_child_procs(p_pid, p_cmd)
            if not ai_alive:
                if batch_cmds:
                    batch_cmds.append(";")
                batch_cmds.extend(build_ai_state_option_cmds(sess))
                should_refresh = True
                continue

        can_ack = (ai_focused or entering_ai) if from_hook else True
        if can_ack and (ai_attn not in ("", "0") or ai_state == "done"):
            if ai_state == "done":
                next_state = "idle"
                next_msg = ""
            elif ai_state == "approval":
                next_state = "approval"
                next_msg = prev_msg
            else:
                next_state = ai_state
                next_msg = prev_msg
            next_state_ts = (
                cur_state_ts
                if (next_state == ai_state and cur_state_ts)
                else (now_s if next_state else "")
            )
            if batch_cmds:
                batch_cmds.append(";")
            batch_cmds.extend(
                build_ai_state_option_cmds(
                    sess,
                    state=next_state,
                    attn="0",
                    attn_ts="",
                    state_ts=next_state_ts,
                    msg=next_msg,
                )
            )
            should_refresh = True

    if batch_cmds:
        run_tmux(*batch_cmds)
    if should_refresh:
        refresh_fleet_topbar(notify_switchers=True)
    return 0


def open_session_pr(target_arg: str) -> int:
    """Open the cached or `.git/config` PR/MR URL for `target_arg` in browser or OSC 52."""
    if target_arg:
        sess = resolve_target_session(target_arg)
    elif os.environ.get("TMUX"):
        sess = current_ide_session()
    else:
        sess = ""
    if not sess or not session_exists(sess) or not check_is_ide_session(sess):
        print(f"Error: {missing_session_msg(sess or target_arg)}", file=sys.stderr)
        return 1
    workdir = (
        get_ide_var(sess, "@ide_workdir", "IDE_WORKDIR")
        or get_ide_var(sess, "@ide_initial_root", "IDE_INITIAL_ROOT")
        or tmux_out("display-message", "-p", "-t", f"={sess}:", "#{pane_current_path}").strip()
    )
    from ide_lib.git_info import git_summary

    _, _, _, raw_pr_url, _ = git_summary(workdir)
    pr_url = sanitize_http_url(raw_pr_url)
    if not pr_url:
        msg = f"No cached PR/MR URL for session '{sess}'."
        if os.environ.get("TMUX") or os.environ.get("IDE_CLIENT"):
            ide_client = resolve_active_client()
            if ide_client:
                run_tmux("display-message", "-c", ide_client, "-d", "2500", msg)
            else:
                run_tmux("display-message", "-d", "2500", "-t", f"={sess}:", msg)
        else:
            print(msg, file=sys.stderr)
        return 1
    discover_display_env(sess)
    return 0 if open_browser_url(pr_url, sess) else 1
