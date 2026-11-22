"""Tabular and JSON fleet listings, FIFO attention jump, workspace launcher, and `switch` entrypoint."""

from __future__ import annotations

import os
import shlex
import shutil
import subprocess
import sys

from ide_lib.constants import (
    is_switcher_session_name,
    pad_visible,
    resolve_mise_tool_bin,
    shorten_home,
    trunc_visible,
    use_nerd_fonts,
    visible_width,
)
from ide_lib.dock import (
    caller_switcher_session,
    close_switcher_session,
    switch_or_attach_session,
    undock_switcher_session,
)
from ide_lib.fleet import ack_ai_session, classify_ide_fleet, refresh_fleet_topbar
from ide_lib.hooks import collect_configured_workspace_roots, scandir_child_dirs
from ide_lib.preview import (
    _ansi_visible_width,
    _carry_sgr_prefix,
    _compute_fleet_columns,
    _format_fleet_sessions_lines,
    _resolve_fzf_wrap_config,
    _resolve_preview_interval,
    _select_preview_tail,
    _wrapped_preview_rows,
    compute_fleet_columns,
    format_fleet_sessions_lines,
    render_session_preview,
    sync_switcher_slot_preview,
)
from ide_lib.switcher import (
    SIDE_BY_SIDE_MIN_COLS,
    _FZF_RESIZE_CAP_CACHE,
    _POPUP_SESS_RE,
    _fzf_supports_resize_bind,
    build_sessions_fzf_args,
    format_sessions_footer_label,
    fzf_supports_resize_bind,
    handle_switcher_op,
    launch_picked_workspace,
    maybe_reenter_in_tmux_popup,
    OuterSwitcherSnapshot,
    parse_fzf_session_output,
    query_outer_switcher_snapshot,
    run_interactive_switcher_session,
)
from ide_lib.theme import build_fzf_env, detect_color_tier, load_active_palette, state_color
from ide_lib.tmux import (
    check_is_ide_session,
    current_ide_session,
    resolve_active_client,
    resolve_switcher_context,
    resolve_target_session,
    run_tmux,
    session_exists,
    tmux_out,
)

__all__ = [
    "_FZF_RESIZE_CAP_CACHE",
    "_ansi_visible_width",
    "_carry_sgr_prefix",
    "_collect_launcher_dirs",
    "_compute_fleet_columns",
    "_format_fleet_sessions_lines",
    "_fzf_supports_resize_bind",
    "_pick_workspace_directory",
    "_resolve_fzf_wrap_config",
    "_resolve_preview_interval",
    "_select_preview_tail",
    "_wrapped_preview_rows",
    "build_sessions_lines",
    "collect_launcher_dirs",
    "handle_switcher_op",
    "list_ide_fleet",
    "next_attention",
    "pick_workspace_directory",
    "render_session_preview",
    "run_new_workspace_picker",
    "run_sessions_picker",
]


def _notify_tmux_or_stdout(msg: str, client_name: str = "", sess: str = "") -> None:
    if client_name or os.environ.get("TMUX") or os.environ.get("IDE_CLIENT"):
        cl = client_name or resolve_active_client(sess)
        if cl:
            run_tmux("display-message", "-c", cl, msg)
        elif sess and session_exists(sess):
            run_tmux("display-message", "-t", f"={sess}:", msg)
        else:
            run_tmux("display-message", msg)
    else:
        print(msg)


def next_attention(target_arg: str) -> int:
    """Jump to the oldest IDE session awaiting AI attention (`ATTN` ahead of `DONE` in FIFO order)."""
    sw_sess = caller_switcher_session(target_arg)
    sw_client = ""
    sw_res_file = ""
    if sw_sess:
        docked_s, sw_client, sw_res_file = resolve_switcher_context(sw_sess)
        sw_origin = tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_origin").strip()
        origin_sess = sw_origin or docked_s
    else:
        resolved_arg = resolve_target_session(target_arg) if target_arg else ""
        origin_sess = resolved_arg if (resolved_arg and session_exists(resolved_arg)) else current_ide_session()
    fleet = classify_ide_fleet(include_git=False, cur_sess=origin_sess)
    attn_entries = [e for e in fleet if bool(e["needs_attn"])]
    if not attn_entries:
        refresh_fleet_topbar()
        if sw_sess:
            if sw_client:
                run_tmux("display-message", "-c", sw_client, "No IDE agents waiting for attention.")
            else:
                run_tmux("display-message", "-t", f"={sw_sess}:", "No IDE agents waiting for attention.")
        else:
            _notify_tmux_or_stdout("No IDE agents waiting for attention.", sess=origin_sess)
        return 0

    from ide_lib.layout import toggle_main_pane

    oldest = str(attn_entries[0]["sess"])
    if sw_sess:
        close_switcher_session(
            sw_sess,
            action="switch",
            target=oldest,
            pressed="ctrl-a",
            res_file_hint=sw_res_file,
        )
        if not sw_res_file:
            toggle_main_pane("focus-ai", oldest)
            refresh_fleet_topbar()
            if sw_client:
                run_tmux("switch-client", "-c", sw_client, "-t", f"={oldest}")
        return 0
    toggle_main_pane("focus-ai", oldest)
    refresh_fleet_topbar()
    return switch_or_attach_session(oldest, origin_sess)


def list_ide_fleet(plain: bool = False, json_output: bool = False) -> int:
    """Print active IDE sessions in urgency order (plain names, JSON array, or aligned status table)."""
    cur_sess = current_ide_session()
    if plain:
        fleet_plain = classify_ide_fleet(include_git=False, cur_sess=cur_sess)
        for entry in fleet_plain:
            print(str(entry["sess"]))
        return 0

    fleet = classify_ide_fleet(include_git=True, cur_sess=cur_sess)
    if json_output:
        import json

        payload = [
            {
                "session": str(e["sess"]),
                "agent": str(e["ai_cli"]),
                "state": str(e["state"]),
                "state_label": str(e["state_label"]),
                "state_ts": float(e["state_ts"]),
                "needs_attention": bool(e["needs_attn"]),
                "attention_ts": float(e["attn_ts"]),
                "message": str(e["ai_msg"]),
                "workdir": str(e["workdir"]),
                "git_branch": str(e["git_branch"]),
                "git_dirty": bool(e["git_dirty"]),
                "git_detail": str(e["git_detail"]),
                "git_pr_url": str(e["git_pr_url"]),
                "worktree_root": str(e["worktree_root"]),
                "worktree_peers": list(e.get("worktree_peers") or []),
                "active_role": str(e["active_role"]),
                "attached": bool(e["attached"]),
                "is_current": bool(e["is_current"]),
                "quit_error": str(e["quit_err"]),
            }
            for e in fleet
        ]
        print(json.dumps(payload, indent=2))
        return 0

    if not fleet:
        print("No active IDE sessions.")
        return 0

    tier = detect_color_tier()
    use_color = sys.stdout.isatty() and tier != "nocolor"
    nf = use_nerd_fonts()
    cur_glyph = "▸" if nf else "*"
    attn_glyph = "󰂚" if nf else "!"
    _, esc = load_active_palette()
    raw_cols = os.environ.get("IDE_LIST_COLUMNS", "").strip()
    if raw_cols.isdigit() and int(raw_cols) > 0:
        tty_cols = int(raw_cols)
    elif sys.stdout.isatty():
        tty_cols = shutil.get_terminal_size((120, 40)).columns
    else:
        tty_cols = 0

    if 0 < tty_cols < 90:
        max_sess_w, max_cli_w, max_git_w = 18, 10, 16
    elif 90 <= tty_cols < 100:
        max_sess_w, max_cli_w, max_git_w = 22, 11, 20
    else:
        max_sess_w, max_cli_w, max_git_w = 28, 12, 28

    state_labels, git_labels, sess_w, cli_w, state_w, git_w = compute_fleet_columns(
        fleet, min_sess_w=7, max_sess_w=max_sess_w, max_cli_w=max_cli_w, max_git_w=max_git_w
    )
    prefix_cols = 2 + sess_w + 2 + cli_w + 2 + state_w + 2 + git_w + 2

    def _fit_ws_path(path_text: str, extra_sfx: int = 0) -> str:
        if tty_cols <= 0:
            return path_text
        budget = max(8, tty_cols - prefix_cols - extra_sfx)
        if visible_width(path_text) <= budget:
            return path_text
        base = os.path.basename(path_text.rstrip("/"))
        if base and "/" in path_text.strip("/"):
            tail = f"/{base}"
            tail_w = visible_width(tail)
            if tail_w + 2 <= budget:
                head_budget = budget - tail_w - 1
                head = trunc_visible(path_text[: max(1, len(path_text) - len(tail))], head_budget + 1).rstrip("…")
                cand = f"{head}…{tail}"
                if visible_width(cand) <= budget:
                    return cand
        return trunc_visible(path_text, budget)

    ws_hdr = trunc_visible("WORKSPACE", max(4, tty_cols - prefix_cols)) if tty_cols > 0 else "WORKSPACE"
    if use_color:
        c_hdr = esc["BASE01"]
        c_rst = esc["RESET"]
        print(
            f"  {c_hdr}{'SESSION':<{sess_w}}  {'AGENT':<{cli_w}}  {'STATE':<{state_w}}  {'BRANCH':<{git_w}}  {ws_hdr}{c_rst}"
        )
    else:
        print(f"  {'SESSION':<{sess_w}}  {'AGENT':<{cli_w}}  {'STATE':<{state_w}}  {'BRANCH':<{git_w}}  {ws_hdr}")

    for entry, st_lbl, git_lbl in zip(fleet, state_labels, git_labels):
        sess = str(entry["sess"])
        ai_cli = str(entry["ai_cli"])
        state = str(entry["state"])
        is_cur = bool(entry["is_current"])
        needs_attn = bool(entry["needs_attn"])
        has_wt_warn = bool(entry.get("worktree_peers"))
        short_path = _fit_ws_path(str(entry["short_path"]), extra_sfx=2 if has_wt_warn else 0)
        s_pad = pad_visible(trunc_visible(sess, sess_w), sess_w)
        c_pad = pad_visible(trunc_visible(ai_cli, cli_w), cli_w)
        st_pad = pad_visible(trunc_visible(st_lbl, state_w), state_w)
        g_pad = pad_visible(trunc_visible(git_lbl, git_w), git_w)
        if use_color:
            attn_c = esc["GREEN"] if state == "DONE" else esc["ORANGE"]
            if is_cur:
                marker = f"{esc['CYAN']}{cur_glyph}{esc['RESET']}"
            elif needs_attn:
                marker = f"{attn_c}{attn_glyph}{esc['RESET']}"
            else:
                marker = " "
            c_sess = esc["BASE1"] if is_cur else (attn_c if needs_attn else esc["BLUE"])
            c_state = state_color(state, esc)
            c_git = esc["YELLOW"] if bool(entry["git_dirty"]) else (esc["GREEN"] if git_lbl != "-" else esc["BASE01"])
            wt_sfx = f" {esc['YELLOW']}!{esc['RESET']}" if has_wt_warn else ""
            print(
                f"{marker} {c_sess}{s_pad}{esc['RESET']}  "
                f"{esc['BASE0']}{c_pad}{esc['RESET']}  "
                f"{c_state}{st_pad}{esc['RESET']}  "
                f"{c_git}{g_pad}{esc['RESET']}  "
                f"{esc['BASE0']}{short_path}{esc['RESET']}{wt_sfx}"
            )
        else:
            marker = "*" if is_cur else ("!" if needs_attn else " ")
            wt_sfx = " !" if has_wt_warn else ""
            print(f"{marker} {s_pad}  {c_pad}  {st_pad}  {g_pad}  {short_path}{wt_sfx}")
    return 0


def build_sessions_lines(cur_sess: str = "") -> list[str]:
    """Build `<session>\\t<ansi_display>` rows for `fzf` `ide switch`."""
    if cur_sess and not session_exists(cur_sess):
        cur_sess = ""
    if not cur_sess:
        cl = os.environ.get("IDE_CLIENT", "").strip()
        if cl and not cl.startswith("#{"):
            cand = tmux_out("display-message", "-p", "-c", cl, "#{session_name}").strip()
            if cand and check_is_ide_session(cand):
                cur_sess = cand
        if not cur_sess:
            cur_sess = current_ide_session()
    fleet = classify_ide_fleet(include_git=True, cur_sess=cur_sess)
    if not fleet:
        return []
    _, esc = load_active_palette()
    raw_pw = os.environ.get("IDE_SESSIONS_PANE_W", "").strip()
    pane_w = int(raw_pw) if raw_pw.isdigit() and int(raw_pw) > 0 else 0
    return format_fleet_sessions_lines(fleet, esc, pane_w=pane_w)


def _collect_launcher_dirs() -> list[str]:
    """Collect candidate workspace directories ranked by `zoxide` frecency, hooks, and `$HOME`."""
    dirs: list[str] = []
    seen: set[str] = set()
    parent_cache: dict[str, set[str]] = {}
    hook_ws_roots, managed_parents, _ = collect_configured_workspace_roots(parent_cache=parent_cache)
    hook_ws_roots_set = set(hook_ws_roots)

    zoxide_bin = resolve_mise_tool_bin("zoxide", env_override="IDE_ZOXIDE_BIN")
    if zoxide_bin:
        res = None
        try:
            res = subprocess.run(
                [zoxide_bin, "query", "-l", "--all"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=1.0,
                check=False,
            )
            if res.returncode != 0:
                res = subprocess.run(
                    [zoxide_bin, "query", "-l"],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                    timeout=1.0,
                    check=False,
                )
        except (OSError, subprocess.SubprocessError):
            res = None

        if res is not None and res.returncode == 0 and res.stdout:
            for raw in res.stdout.splitlines():
                cand_raw = raw.strip()
                if not cand_raw:
                    continue
                norm = os.path.abspath(os.path.expanduser(cand_raw))

                matched_ws = ""
                if hook_ws_roots_set:
                    cur = norm
                    while True:
                        if cur in hook_ws_roots_set:
                            matched_ws = cur
                            break
                        parent = os.path.dirname(cur)
                        if parent == cur:
                            break
                        cur = parent
                if matched_ws:
                    if matched_ws not in seen:
                        seen.add(matched_ws)
                        dirs.append(matched_ws)
                    continue

                if managed_parents:
                    dead_managed_child = False
                    cur = norm
                    while True:
                        parent = os.path.dirname(cur)
                        if parent == cur:
                            break
                        if parent in managed_parents:
                            if os.path.basename(cur) not in scandir_child_dirs(parent, parent_cache):
                                dead_managed_child = True
                                break
                        cur = parent
                    if dead_managed_child:
                        continue

                if norm not in seen and os.path.isdir(norm):
                    seen.add(norm)
                    dirs.append(norm)

    for ws_root in hook_ws_roots:
        if ws_root not in seen:
            seen.add(ws_root)
            dirs.append(ws_root)

    home = os.path.expanduser("~")
    if home and os.path.isdir(home):
        try:
            for entry in sorted(os.listdir(home)):
                if entry.startswith("."):
                    continue
                cand = os.path.join(home, entry)
                norm = os.path.abspath(cand)
                if norm not in seen and os.path.isdir(cand):
                    seen.add(norm)
                    dirs.append(norm)
        except OSError:
            pass
        if not dirs:
            dirs.append(os.path.abspath(home))
    return dirs


collect_launcher_dirs = _collect_launcher_dirs


def _format_new_picker_footer(cols: int, back_to_sessions: bool) -> str:
    """Pack bottom `--border-label` hints for `New IDE >` within `cols` without mid-word clipping."""
    full_esc = "Esc: back to sessions" if back_to_sessions else "Esc: cancel"
    short_esc = "Esc: back" if back_to_sessions else "Esc: cancel"
    candidates = (
        f" Enter: launch workspace · {full_esc} ",
        f" Enter: launch · {short_esc} ",
        " Enter · Esc ",
    )
    budget = max(8, cols - 4) if cols > 0 else 120
    for cand in candidates:
        if visible_width(cand) <= budget:
            return cand
    return f" {trunc_visible('Enter · Esc', max(1, budget - 2))} "


def _pick_workspace_directory(
    fzf_bin: str,
    env: dict[str, str],
    back_to_sessions: bool = True,
) -> str:
    """Run `fzf` `New IDE >` directory picker using unit-separator (`\\x1f`) framing."""
    dirs = _collect_launcher_dirs()
    if not dirs:
        return ""
    hex_map, esc = load_active_palette()
    rows = [f"{d}\x1f{esc['BLUE']}{shorten_home(d)}{esc['RESET']}" for d in dirs]
    raw_w = (env.get("FZF_COLUMNS") or env.get("COLUMNS") or os.environ.get("COLUMNS") or "").strip()
    picker_cols = int(raw_w) if raw_w.isdigit() and int(raw_w) > 0 else shutil.get_terminal_size((120, 40)).columns
    footer_lbl = _format_new_picker_footer(picker_cols, back_to_sessions=back_to_sessions)
    color_label_args = (
        []
        if detect_color_tier() in ("nocolor", "mono", "16color")
        else [
            f"--color=label:{hex_map['BASE01']}",
            f"--color=border:{hex_map['BASE01']},separator:{hex_map['BASE01']},gutter:{hex_map['BASE03']}",
        ]
    )
    dir_args = [
        fzf_bin,
        "--ansi",
        "--delimiter=\x1f",
        "--with-nth=2..",
        "--layout=reverse",
        "--info=inline-right",
        "--prompt=New IDE > ",
        "--border=rounded",
        f"--border-label={footer_lbl}",
        "--border-label-pos=bottom",
        *color_label_args,
        "--bind=alt-s:abort",
    ]
    proc = subprocess.run(
        dir_args,
        input="\n".join(rows) + "\n",
        stdout=subprocess.PIPE,
        text=True,
        env=env,
        check=False,
    )
    if proc.returncode != 0 or not proc.stdout:
        return ""
    first = proc.stdout.splitlines()[0].split("\x1f", 1)[0].rstrip("\r\n")
    return first if (first and os.path.isdir(first)) else ""


pick_workspace_directory = _pick_workspace_directory


def run_new_workspace_picker(
    target_arg: str,
    ide_self: str,
    layout_mode: str = "",
    ai_cli: str = "",
    ai_cli_from_flag: bool = False,
    had_env_ai_cli: bool = False,
    detach_only: bool = False,
) -> int:
    """Open interactive `New IDE >` workspace directory picker (`ide -n` or `ide new`)."""
    resolved_arg = resolve_target_session(target_arg) if target_arg else ""
    origin_sess = resolved_arg if (resolved_arg and session_exists(resolved_arg)) else ""
    cur_sess = origin_sess if (origin_sess and check_is_ide_session(origin_sess)) else current_ide_session()
    fzf_bin = resolve_mise_tool_bin("fzf", env_override="IDE_FZF_BIN")

    if not detach_only and fzf_bin:
        inner_args = [shlex.quote(ide_self), "new"]
        if layout_mode == "2pane":
            inner_args.append("--2pane")
        if ai_cli_from_flag and ai_cli:
            inner_args.extend(["--agent", shlex.quote(ai_cli)])
        if cur_sess:
            inner_args.append(shlex.quote(cur_sess))
        popup_rc = maybe_reenter_in_tmux_popup(
            origin_sess, cur_sess, fzf_bin, forward_ai_cli=had_env_ai_cli, inner_args=inner_args
        )
        if popup_rc is not None:
            return popup_rc

    if not fzf_bin:
        print("Error: 'fzf' is required for 'ide new'.", file=sys.stderr)
        return 1
    if not (
        (sys.stdin.isatty() and sys.stdout.isatty())
        or os.environ.get("IDE_IN_POPUP") == "1"
        or bool(os.environ.get("IDE_FZF_BIN"))
    ):
        print("Error: 'ide new' requires an interactive terminal.", file=sys.stderr)
        return 1

    hex_map, _ = load_active_palette()
    env = build_fzf_env(hex_map)
    chosen_dir = _pick_workspace_directory(fzf_bin, env, back_to_sessions=False)
    if not chosen_dir:
        return 0
    return launch_picked_workspace(
        chosen_dir,
        ide_self,
        origin_sess=origin_sess or cur_sess,
        layout_mode=layout_mode,
        ai_cli=ai_cli,
        ai_cli_from_flag=ai_cli_from_flag,
        detach_only=detach_only,
    )


def _enter_switcher_new_mode(sw_sess: str) -> None:
    """Undock `sw_sess` and zoom its left `fzf` pane into full-width `New IDE >` mode."""
    undock_switcher_session(sw_sess)
    run_tmux("set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_mode", "new")
    if tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{window_zoomed_flag}") == "0":
        run_tmux("resize-pane", "-Z", "-t", f"={sw_sess}:")


def run_sessions_picker(
    target_arg: str,
    ide_self: str,
    had_env_ai_cli: bool = False,
    layout_mode: str = "",
    ai_cli: str = "",
    ai_cli_from_flag: bool = False,
    detach_only: bool = False,
) -> int:
    """Open interactive `fzf` multi-session workspace switcher (`ide -s` or `ide switch`)."""
    forward_ai = had_env_ai_cli or ai_cli_from_flag
    fzf_bin = resolve_mise_tool_bin("fzf", env_override="IDE_FZF_BIN")
    sw_sess = os.environ.get("IDE_SWITCHER_SESSION", "").strip()
    sw_res_file = os.environ.get("IDE_SWITCHER_RESULT", "").strip()
    in_switcher = bool(sw_sess and is_switcher_session_name(sw_sess))
    start_alt_n = os.environ.pop("IDE_SW_START_ALT_N", "") == "1"

    outer_snap: OuterSwitcherSnapshot | None = None
    if not in_switcher and os.environ.get("IDE_IN_POPUP") != "1" and os.environ.get("IDE_NO_POPUP") != "1":
        outer_snap = query_outer_switcher_snapshot(target_arg)
        origin_sess = outer_snap.origin_sess
        cur_sess = outer_snap.cur_sess
        if os.environ.get("TMUX"):
            client_name = outer_snap.client_name
            if _POPUP_SESS_RE.match(outer_snap.raw_cur):
                if client_name:
                    run_tmux("detach-client", "-t", client_name)
                else:
                    run_tmux("detach-client")
                return 0
            if client_name and outer_snap.existing_sw:
                close_switcher_session(outer_snap.existing_sw, action="none")
                return 0
            if client_name and fzf_bin:
                if outer_snap.raw_ide_sessions:
                    sw_rc = run_interactive_switcher_session(
                        origin_sess=origin_sess,
                        cur_sess=cur_sess,
                        ide_self=ide_self,
                        fzf_bin=fzf_bin,
                        forward_ai_cli=forward_ai,
                        snap=outer_snap,
                        client_name=client_name,
                        layout_mode=layout_mode,
                        ai_cli=ai_cli,
                        ai_cli_from_flag=ai_cli_from_flag,
                    )
                    if sw_rc is not None:
                        return sw_rc
                inner_args = [shlex.quote(ide_self), "switch"]
                if layout_mode == "2pane":
                    inner_args.append("--2pane")
                if ai_cli_from_flag and ai_cli:
                    inner_args.extend(["--agent", shlex.quote(ai_cli)])
                if detach_only:
                    inner_args.append("--detach")
                if cur_sess:
                    inner_args.append(shlex.quote(cur_sess))
                popup_rc = maybe_reenter_in_tmux_popup(
                    origin_sess,
                    cur_sess,
                    fzf_bin,
                    forward_ai_cli=forward_ai,
                    inner_args=inner_args,
                    client_name_hint=client_name,
                )
                if popup_rc is not None:
                    return popup_rc
        elif (
            sys.stdin.isatty()
            and sys.stdout.isatty()
            and fzf_bin
            and os.path.basename(fzf_bin) == "fzf"
            and outer_snap.raw_ide_sessions
        ):
            sw_ext_rc = run_interactive_switcher_session(
                origin_sess=origin_sess,
                cur_sess=cur_sess,
                ide_self=ide_self,
                fzf_bin=fzf_bin,
                forward_ai_cli=forward_ai,
                snap=outer_snap,
                client_name="",
                layout_mode=layout_mode,
                ai_cli=ai_cli,
                ai_cli_from_flag=ai_cli_from_flag,
            )
            if sw_ext_rc is not None:
                return sw_ext_rc
    else:
        resolved_arg = resolve_target_session(target_arg) if target_arg else ""
        origin_sess = resolved_arg if (resolved_arg and session_exists(resolved_arg)) else ""
        cur_sess = origin_sess if (origin_sess and check_is_ide_session(origin_sess)) else current_ide_session()

    outer_client = outer_snap.client_name if outer_snap is not None else ""

    if not fzf_bin:
        has_sessions = bool(outer_snap.raw_ide_sessions) if outer_snap is not None else bool(build_sessions_lines(cur_sess))
        if not has_sessions:
            _notify_tmux_or_stdout("No active IDE sessions.", client_name=outer_client, sess=origin_sess or cur_sess)
            return 0
        return list_ide_fleet(plain=False)

    hex_map, _ = load_active_palette()
    env = build_fzf_env(hex_map)
    is_interactive = (sys.stdin.isatty() and sys.stdout.isatty()) or os.environ.get("IDE_IN_POPUP") == "1"

    if start_alt_n and in_switcher:
        _enter_switcher_new_mode(sw_sess)
        chosen_dir0 = _pick_workspace_directory(fzf_bin, env, back_to_sessions=True)
        if chosen_dir0:
            close_switcher_session(
                sw_sess, action="launch", target=chosen_dir0, pressed="alt-n", res_file_hint=sw_res_file
            )
            return 0
        initial_rows: list[str] = []
        first_iter = False
    else:
        if outer_snap is not None and not outer_snap.raw_ide_sessions:
            initial_rows = []
        else:
            initial_rows = build_sessions_lines(cur_sess)
        if not initial_rows:
            if not is_interactive:
                _notify_tmux_or_stdout("No active IDE sessions.", client_name=outer_client, sess=origin_sess or cur_sess)
                return 0
            if in_switcher:
                _enter_switcher_new_mode(sw_sess)
            chosen_dir = _pick_workspace_directory(fzf_bin, env, back_to_sessions=False)
            if not chosen_dir:
                if in_switcher:
                    close_switcher_session(sw_sess, action="none", res_file_hint=sw_res_file)
                return 0
            if in_switcher:
                close_switcher_session(
                    sw_sess, action="launch", target=chosen_dir, pressed="alt-n", res_file_hint=sw_res_file
                )
                return 0
            return launch_picked_workspace(
                chosen_dir,
                ide_self,
                origin_sess=origin_sess or cur_sess,
                layout_mode=layout_mode,
                ai_cli=ai_cli,
                ai_cli_from_flag=ai_cli_from_flag,
                detach_only=detach_only,
            )
        first_iter = True

    supports_modern_binds = fzf_supports_resize_bind(fzf_bin)
    pane_h = 32
    pane_w = 160
    if in_switcher:
        dims_s = tmux_out(
            "display-message",
            "-p",
            "-t",
            os.environ.get("TMUX_PANE", f"={sw_sess}:"),
            "#{pane_height}\t#{pane_width}",
        ).strip()
        ph_s, pw_s = (dims_s.split("\t") + ["", ""])[:2]
        pane_h = int(ph_s) if ph_s.isdigit() and int(ph_s) > 0 else 32
        pane_w = int(pw_s) if pw_s.isdigit() and int(pw_s) > 0 else 64
    else:
        term_sz = shutil.get_terminal_size(fallback=(160, 48))
        pane_w = term_sz.columns if term_sz.columns >= 40 else 160
        pane_h = term_sz.lines if term_sz.lines >= 12 else 32
    fzf_args = build_sessions_fzf_args(
        fzf_bin=fzf_bin,
        ide_self=ide_self,
        cur_sess=cur_sess,
        hex_map=hex_map,
        supports_modern_binds=supports_modern_binds,
        sw_sess=sw_sess if in_switcher else "",
        pane_h=pane_h,
        pane_w=pane_w,
    )

    while True:
        was_first = first_iter
        rows = initial_rows if first_iter else build_sessions_lines(cur_sess)
        first_iter = False
        if not rows:
            sw_cl = ""
            if in_switcher:
                _, sw_cl, _ = resolve_switcher_context(sw_sess)
                close_switcher_session(sw_sess, action="none", res_file_hint=sw_res_file)
            _notify_tmux_or_stdout(
                "No active IDE sessions.",
                client_name=sw_cl or outer_client,
                sess=origin_sess or cur_sess,
            )
            return 0

        if in_switcher and not was_first:
            run_tmux("set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_mode", "sessions")
            if tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{window_zoomed_flag}") == "1":
                run_tmux("resize-pane", "-Z", "-t", f"={sw_sess}:")
            if rows:
                sync_switcher_slot_preview(sw_sess, rows[0].split("\t", 1)[0].strip())

        proc = subprocess.run(
            fzf_args,
            input="\n".join(rows) + "\n",
            stdout=subprocess.PIPE,
            text=True,
            env={**env, "SHELL": "/bin/sh"},
            check=False,
        )
        parsed = parse_fzf_session_output(proc.returncode, proc.stdout or "")
        if parsed is None:
            if in_switcher:
                close_switcher_session(sw_sess, action="none", res_file_hint=sw_res_file)
            return 0
        pressed, selected_line = parsed

        if pressed == "alt-n":
            if in_switcher:
                _enter_switcher_new_mode(sw_sess)
            chosen_dir = _pick_workspace_directory(fzf_bin, env, back_to_sessions=True)
            if not chosen_dir:
                continue
            if in_switcher:
                close_switcher_session(
                    sw_sess, action="launch", target=chosen_dir, pressed="alt-n", res_file_hint=sw_res_file
                )
                return 0
            return launch_picked_workspace(
                chosen_dir,
                ide_self,
                origin_sess=origin_sess or cur_sess,
                layout_mode=layout_mode,
                ai_cli=ai_cli,
                ai_cli_from_flag=ai_cli_from_flag,
                detach_only=detach_only,
            )

        chosen_sess = selected_line.split("\t", 1)[0].strip()
        if not chosen_sess or not session_exists(chosen_sess):
            if in_switcher:
                close_switcher_session(sw_sess, action="none", res_file_hint=sw_res_file)
            return 0

        if in_switcher:
            close_switcher_session(
                sw_sess, action="switch", target=chosen_sess, pressed=pressed, res_file_hint=sw_res_file
            )
            return 0

        if pressed in ("ctrl-a", "ctrl-e", "ctrl-t"):
            from ide_lib.layout import toggle_main_pane

            if pressed == "ctrl-a":
                toggle_main_pane("focus-ai", chosen_sess)
            elif pressed == "ctrl-e":
                toggle_main_pane("focus-editor", chosen_sess)
            else:
                toggle_main_pane("focus-term", chosen_sess)

        rc = switch_or_attach_session(chosen_sess, origin_sess or cur_sess)
        ack_ai_session([chosen_sess], from_hook=True, refresh_always=False)
        return rc
