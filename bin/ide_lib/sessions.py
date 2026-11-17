"""Tabular fleet listings, live ANSI session preview, `fzf` workspace switcher, and directory launcher."""

from __future__ import annotations

import os
import re
import shlex
import shutil
import subprocess
import sys

from ide_lib.constants import (
    _SGR_RE,
    is_socket_path,
    pad_visible,
    shorten_home,
    trunc_visible,
    visible_width,
)
from ide_lib.fleet import ack_ai_session, classify_ide_fleet, refresh_fleet_topbar
from ide_lib.hooks import (
    collect_configured_workspace_roots,
    resolve_workspace_target,
    sanitize_session_name,
    scandir_child_dirs,
)
from ide_lib.theme import build_fzf_env, load_active_palette, state_color
from ide_lib.tmux import (
    check_is_ide_session,
    current_ide_session,
    pane_exists,
    resolve_active_client,
    resolve_target_session,
    run_tmux,
    session_exists,
    switch_or_attach_session,
    tmux_out,
)

_POPUP_SESS_RE = re.compile(r"^(ai|agy)-")
_POPUP_FORWARD_ENV_VARS = (
    "IDE_WORKSPACE_DIRS",
    "IDE_LINK_RULES",
    "IDE_FZF_BIN",
    "IDE_ZOXIDE_BIN",
    "_ZO_DATA_DIR",
    "XDG_CONFIG_HOME",
    "XDG_CACHE_HOME",
    "XDG_DATA_HOME",
)


def next_attention(target_arg: str) -> int:
    """Jump to the oldest IDE session awaiting AI attention (`ATTN` ahead of `DONE` in FIFO order)."""
    resolved_arg = resolve_target_session(target_arg) if target_arg else ""
    origin_sess = resolved_arg if (resolved_arg and session_exists(resolved_arg)) else current_ide_session()
    fleet = classify_ide_fleet(include_git=False, cur_sess=origin_sess)
    attn_entries = [e for e in fleet if bool(e["needs_attn"])]
    if not attn_entries:
        refresh_fleet_topbar()
        if os.environ.get("TMUX") or os.environ.get("IDE_CLIENT"):
            run_tmux("display-message", "No IDE agents waiting for attention.")
        else:
            print("No IDE agents waiting for attention.")
        return 0

    from ide_lib.layout import toggle_main_pane

    oldest = str(attn_entries[0]["sess"])
    toggle_main_pane("focus-ai", oldest)
    refresh_fleet_topbar()
    return switch_or_attach_session(oldest, origin_sess)


def _compute_fleet_columns(
    fleet: list[dict[str, object]],
    min_sess_w: int,
    max_sess_w: int,
    max_cli_w: int,
    max_git_w: int,
) -> tuple[list[str], list[str], int, int, int, int]:
    state_labels = [str(e.get("state_label") or e["state"]) for e in fleet]
    git_labels = [
        f"{e['git_branch']}{'*' if e['git_dirty'] else ''}" if e["git_branch"] != "-" else "-"
        for e in fleet
    ]
    sess_w = max(min_sess_w, min(max_sess_w, max(visible_width(str(e["sess"])) for e in fleet)))
    cli_w = max(5, min(max_cli_w, max(visible_width(str(e["ai_cli"])) for e in fleet)))
    state_w = max(5, min(16, max(visible_width(lbl) for lbl in state_labels)))
    git_w = max(6, min(max_git_w, max(visible_width(g) for g in git_labels)))
    return state_labels, git_labels, sess_w, cli_w, state_w, git_w


def list_ide_fleet(plain: bool = False) -> int:
    """Print active IDE sessions in urgency order (plain session names or aligned status table)."""
    cur_sess = current_ide_session()
    if plain:
        fleet_plain = classify_ide_fleet(include_git=False, cur_sess=cur_sess)
        for entry in fleet_plain:
            print(str(entry["sess"]))
        return 0

    fleet = classify_ide_fleet(include_git=True, cur_sess=cur_sess)
    if not fleet:
        print("No active IDE sessions.")
        return 0

    use_color = sys.stdout.isatty() and not bool(os.environ.get("NO_COLOR"))
    _, esc = load_active_palette()
    state_labels, git_labels, sess_w, cli_w, state_w, git_w = _compute_fleet_columns(
        fleet, min_sess_w=7, max_sess_w=28, max_cli_w=12, max_git_w=28
    )

    if use_color:
        c_hdr = esc["BASE01"]
        c_rst = esc["RESET"]
        print(
            f"  {c_hdr}{'SESSION':<{sess_w}}  {'AGENT':<{cli_w}}  {'STATE':<{state_w}}  {'BRANCH':<{git_w}}  WORKSPACE{c_rst}"
        )
    else:
        print(f"  {'SESSION':<{sess_w}}  {'AGENT':<{cli_w}}  {'STATE':<{state_w}}  {'BRANCH':<{git_w}}  WORKSPACE")

    for entry, st_lbl, git_lbl in zip(fleet, state_labels, git_labels):
        sess = str(entry["sess"])
        ai_cli = str(entry["ai_cli"])
        state = str(entry["state"])
        short_path = str(entry["short_path"])
        is_cur = bool(entry["is_current"])
        needs_attn = bool(entry["needs_attn"])
        has_wt_warn = bool(entry.get("worktree_peers"))
        s_pad = pad_visible(trunc_visible(sess, sess_w), sess_w)
        c_pad = pad_visible(trunc_visible(ai_cli, cli_w), cli_w)
        st_pad = pad_visible(trunc_visible(st_lbl, state_w), state_w)
        g_pad = pad_visible(trunc_visible(git_lbl, git_w), git_w)
        if use_color:
            attn_c = esc["GREEN"] if state == "DONE" else esc["ORANGE"]
            if is_cur:
                marker = f"{esc['CYAN']}▸{esc['RESET']}"
            elif needs_attn:
                marker = f"{attn_c}󰂚{esc['RESET']}"
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
    """Build `<session>\\t<ansi_display>` rows for `fzf` `--sessions`."""
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
    state_labels, git_labels, sess_w, cli_w, state_w, git_w = _compute_fleet_columns(
        fleet, min_sess_w=8, max_sess_w=24, max_cli_w=10, max_git_w=24
    )
    rows: list[str] = []
    for entry, st_lbl, git_lbl in zip(fleet, state_labels, git_labels):
        sess = str(entry["sess"])
        ai_cli = str(entry["ai_cli"])
        state = str(entry["state"])
        short_path = str(entry["short_path"])
        is_cur = bool(entry["is_current"])
        needs_attn = bool(entry["needs_attn"])
        has_wt_warn = bool(entry.get("worktree_peers"))
        attn_c = esc["GREEN"] if state == "DONE" else esc["ORANGE"]
        s_pad = pad_visible(trunc_visible(sess, sess_w), sess_w)
        c_pad = pad_visible(trunc_visible(ai_cli, cli_w), cli_w)
        st_pad = pad_visible(trunc_visible(st_lbl, state_w), state_w)
        g_pad = pad_visible(trunc_visible(git_lbl, git_w), git_w)
        if is_cur:
            marker = f"{esc['CYAN']}▸{esc['RESET']}"
        elif needs_attn:
            marker = f"{attn_c}󰂚{esc['RESET']}"
        else:
            marker = " "
        c_sess = esc["BASE1"] if is_cur else (attn_c if needs_attn else esc["BLUE"])
        c_state = state_color(state, esc)
        c_git = esc["YELLOW"] if bool(entry["git_dirty"]) else (esc["GREEN"] if git_lbl != "-" else esc["BASE01"])
        wt_sfx = f" {esc['YELLOW']}!{esc['RESET']}" if has_wt_warn else ""
        quit_sfx = f" {esc['ORANGE']}[unsaved]{esc['RESET']}" if entry.get("quit_err") else ""
        display = (
            f"{marker} {c_sess}{s_pad}{esc['RESET']}  "
            f"{esc['BASE0']}{c_pad}{esc['RESET']}  "
            f"{c_state}{st_pad}{esc['RESET']}  "
            f"{c_git}{g_pad}{esc['RESET']}  "
            f"{esc['BASE01']}{short_path}{esc['RESET']}{wt_sfx}{quit_sfx}"
        )
        rows.append(f"{sess}\t{display}")
    return rows


def render_session_preview(target_arg: str) -> int:
    """Render live ANSI metadata and visible viewport preview for `target_arg`."""
    sess = target_arg.strip()
    if not sess or not session_exists(sess):
        print("Session is no longer active.")
        return 0
    fleet = classify_ide_fleet(include_git=True, cur_sess=current_ide_session(), git_only_sess=sess)
    entry = next((e for e in fleet if str(e["sess"]) == sess), None)
    _, esc = load_active_palette()
    c_rst = esc["RESET"]
    if entry is None:
        print(f"{esc['BLUE']}{sess}{c_rst}")
        return 0

    ai_cli = str(entry["ai_cli"])
    state = str(entry["state"])
    state_label = str(entry.get("state_label") or state)
    ai_msg = str(entry.get("ai_msg") or "")
    quit_err = str(entry.get("quit_err") or "")
    ide_sock = str(entry.get("ide_sock") or "")
    if quit_err and ide_sock and is_socket_path(ide_sock):
        from ide_lib.nvim_rpc import nvim_modified_buf_count, resolve_nvim_bin

        if resolve_nvim_bin() and nvim_modified_buf_count(ide_sock) == 0:
            run_tmux("set-option", "-q", "-u", "-t", f"={sess}:", "@ide_quit_err")
            quit_err = ""
    short_path = str(entry["short_path"])
    git_branch = str(entry["git_branch"])
    git_detail = str(entry["git_detail"])
    preview_pane = str(entry["preview_pane"])
    active_role = str(entry["active_role"])
    peers = [str(p) for p in (entry.get("worktree_peers") or [])]
    c_state = state_color(state, esc)
    c_git = esc["YELLOW"] if bool(entry["git_dirty"]) else (esc["GREEN"] if git_branch != "-" else esc["BASE01"])
    rule = "─" * 56

    print(f"{esc['BLUE']} {sess}{c_rst}  {esc['BASE01']}(focused: {active_role}){c_rst}")
    print(f"{esc['BASE01']}Agent    :{c_rst} {esc['CYAN']}{ai_cli}{c_rst}  {esc['BASE01']}State:{c_rst} {c_state}{state_label}{c_rst}")
    if ai_msg:
        print(f"{esc['BASE01']}Message  :{c_rst} {esc['BASE1']}{ai_msg}{c_rst}")
    print(f"{esc['BASE01']}Workspace:{c_rst} {esc['BASE0']}{short_path}{c_rst}")
    print(f"{esc['BASE01']}Git      :{c_rst} {c_git}{git_detail}{c_rst}")
    if quit_err:
        print(f"{esc['BASE01']}Warning  :{c_rst} {esc['ORANGE']}{quit_err}{c_rst}")
    if peers:
        print(f"{esc['BASE01']}Warning  :{c_rst} {esc['YELLOW']}Shared worktree with {', '.join(peers)}{c_rst}")
    print(f"{esc['BASE01']}{rule}{c_rst}")

    if preview_pane and pane_exists(preview_pane):
        cap = tmux_out("capture-pane", "-e", "-p", "-S", "-40", "-t", preview_pane)
        cap_lines = cap.splitlines()
        while cap_lines and not _SGR_RE.sub("", cap_lines[-1]).strip():
            cap_lines.pop()
        tail = cap_lines[-35:]
        if tail:
            print("\n".join(tail) + c_rst)
        else:
            print(f"{esc['BASE01']}(Viewport is empty){c_rst}")
    else:
        print(f"{esc['BASE01']}(No active pane in session){c_rst}")
    return 0


def _collect_launcher_dirs() -> list[str]:
    """Collect candidate workspace directories ranked by `zoxide` frecency, hooks, and `$HOME`."""
    dirs: list[str] = []
    seen: set[str] = set()
    parent_cache: dict[str, set[str]] = {}
    hook_ws_roots, managed_parents, _ = collect_configured_workspace_roots(parent_cache=parent_cache)
    hook_ws_roots_set = set(hook_ws_roots)

    zoxide_bin = os.environ.get("IDE_ZOXIDE_BIN") or shutil.which("zoxide")
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
    esc_hint = "Esc: back to sessions" if back_to_sessions else "Esc: cancel"
    dir_args = [
        fzf_bin,
        "--ansi",
        "--delimiter=\x1f",
        "--with-nth=2..",
        "--layout=reverse",
        "--info=inline-right",
        "--prompt=New IDE > ",
        "--border=rounded",
        f"--border-label= Enter: launch workspace · {esc_hint} ",
        "--border-label-pos=bottom",
        f"--color=label:{hex_map['BASE01']}",
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


def _launch_picked_workspace(
    chosen_dir: str,
    ide_self: str,
    origin_sess: str = "",
    layout_mode: str = "",
    ai_cli: str = "",
    ai_cli_from_flag: bool = False,
    detach_only: bool = False,
) -> int:
    resolved_dir = resolve_workspace_target(chosen_dir) or os.path.abspath(chosen_dir)
    target_sess = sanitize_session_name(resolved_dir)
    launch_cmd = [ide_self, "--detach"]
    if layout_mode == "2pane":
        launch_cmd.append("--2pane")
    if ai_cli_from_flag and ai_cli:
        launch_cmd.extend(["--ai", ai_cli])
    launch_cmd.append(resolved_dir)
    child_env = os.environ.copy()
    child_env["IDE_WORKSPACE_RESOLVED"] = "1"
    launch_res = subprocess.run(
        launch_cmd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=child_env,
        check=False,
    )
    if detach_only:
        return 0 if session_exists(target_sess) else launch_res.returncode
    if session_exists(target_sess):
        rc = switch_or_attach_session(target_sess, origin_sess)
        ack_ai_session([target_sess], from_hook=True, refresh_always=False)
        return rc
    return launch_res.returncode


def _build_popup_env(client_name: str, forward_ai_cli: bool = False) -> list[str]:
    popup_env = ["IDE_IN_POPUP=1", f"IDE_CLIENT={shlex.quote(client_name)}"]
    fwd_vars = (*_POPUP_FORWARD_ENV_VARS, "IDE_AI_CLI") if forward_ai_cli else _POPUP_FORWARD_ENV_VARS
    for fwd_var in fwd_vars:
        fwd_val = os.environ.get(fwd_var)
        if fwd_val:
            popup_env.append(f"{fwd_var}={shlex.quote(fwd_val)}")
    return popup_env


def _maybe_reenter_in_tmux_popup(
    origin_sess: str,
    cur_sess: str,
    fzf_bin: str | None,
    forward_ai_cli: bool,
    inner_args: list[str],
) -> int | None:
    if not os.environ.get("TMUX") or os.environ.get("IDE_IN_POPUP") == "1" or os.environ.get("IDE_NO_POPUP") == "1":
        return None
    client_name = resolve_active_client(origin_sess or cur_sess)
    raw_cur = (
        tmux_out("display-message", "-p", "-c", client_name, "#{session_name}")
        if client_name
        else (origin_sess or tmux_out("display-message", "-p", "#{session_name}"))
    )
    if _POPUP_SESS_RE.match(raw_cur):
        if client_name:
            run_tmux("detach-client", "-t", client_name)
        else:
            run_tmux("detach-client")
        return 0
    if client_name and fzf_bin:
        popup_env = _build_popup_env(client_name, forward_ai_cli=forward_ai_cli)
        inner_cmd = " ".join([*popup_env, *inner_args])
        pop_res = run_tmux("display-popup", "-c", client_name, "-E", "-w", "88%", "-h", "80%", inner_cmd)
        if pop_res.returncode == 0 or not sys.stdin.isatty():
            return 0 if pop_res.returncode in (0, 130) else pop_res.returncode
    return None


def run_new_workspace_picker(
    target_arg: str,
    ide_self: str,
    layout_mode: str = "",
    ai_cli: str = "",
    ai_cli_from_flag: bool = False,
    had_env_ai_cli: bool = False,
    detach_only: bool = False,
) -> int:
    """Open interactive `New IDE >` workspace directory picker (`ide -n` / `ide --new`)."""
    resolved_arg = resolve_target_session(target_arg) if target_arg else ""
    origin_sess = resolved_arg if (resolved_arg and session_exists(resolved_arg)) else ""
    cur_sess = origin_sess if (origin_sess and check_is_ide_session(origin_sess)) else current_ide_session()
    fzf_bin = os.environ.get("IDE_FZF_BIN") or shutil.which("fzf")

    if not detach_only and fzf_bin:
        inner_args = [shlex.quote(ide_self), "--new"]
        if layout_mode == "2pane":
            inner_args.append("--2pane")
        if ai_cli_from_flag and ai_cli:
            inner_args.extend(["--ai", shlex.quote(ai_cli)])
        if cur_sess:
            inner_args.append(shlex.quote(cur_sess))
        popup_rc = _maybe_reenter_in_tmux_popup(
            origin_sess, cur_sess, fzf_bin, forward_ai_cli=had_env_ai_cli, inner_args=inner_args
        )
        if popup_rc is not None:
            return popup_rc

    if not fzf_bin:
        print("Error: 'fzf' is required for 'ide --new'.", file=sys.stderr)
        return 1
    if not (
        (sys.stdin.isatty() and sys.stdout.isatty())
        or os.environ.get("IDE_IN_POPUP") == "1"
        or bool(os.environ.get("IDE_FZF_BIN"))
    ):
        print("Error: 'ide --new' requires an interactive terminal.", file=sys.stderr)
        return 1

    hex_map, _ = load_active_palette()
    env = build_fzf_env(hex_map)
    chosen_dir = _pick_workspace_directory(fzf_bin, env, back_to_sessions=False)
    if not chosen_dir:
        return 0
    return _launch_picked_workspace(
        chosen_dir,
        ide_self,
        origin_sess=origin_sess or cur_sess,
        layout_mode=layout_mode,
        ai_cli=ai_cli,
        ai_cli_from_flag=ai_cli_from_flag,
        detach_only=detach_only,
    )


def run_sessions_picker(target_arg: str, ide_self: str, had_env_ai_cli: bool = False) -> int:
    """Open interactive `fzf` multi-session workspace switcher (`ide -s` / `ide --sessions`)."""
    resolved_arg = resolve_target_session(target_arg) if target_arg else ""
    origin_sess = resolved_arg if (resolved_arg and session_exists(resolved_arg)) else ""
    cur_sess = origin_sess if (origin_sess and check_is_ide_session(origin_sess)) else current_ide_session()
    fzf_bin = os.environ.get("IDE_FZF_BIN") or shutil.which("fzf")

    inner_args = [shlex.quote(ide_self), "--sessions"]
    if cur_sess:
        inner_args.append(shlex.quote(cur_sess))
    popup_rc = _maybe_reenter_in_tmux_popup(
        origin_sess, cur_sess, fzf_bin, forward_ai_cli=had_env_ai_cli, inner_args=inner_args
    )
    if popup_rc is not None:
        return popup_rc

    if not fzf_bin:
        rows_plain = build_sessions_lines(cur_sess)
        if not rows_plain:
            if os.environ.get("TMUX"):
                run_tmux("display-message", "No active IDE sessions.")
            else:
                print("No active IDE sessions.")
            return 0
        return list_ide_fleet(plain=False)

    hex_map, _ = load_active_palette()
    env = build_fzf_env(hex_map)
    is_interactive = (sys.stdin.isatty() and sys.stdout.isatty()) or os.environ.get("IDE_IN_POPUP") == "1"
    initial_rows = build_sessions_lines(cur_sess)
    if not initial_rows:
        if not is_interactive:
            if os.environ.get("TMUX"):
                run_tmux("display-message", "No active IDE sessions.")
            else:
                print("No active IDE sessions.")
            return 0
        chosen_dir = _pick_workspace_directory(fzf_bin, env, back_to_sessions=False)
        if not chosen_dir:
            return 0
        return _launch_picked_workspace(chosen_dir, ide_self, origin_sess=origin_sess or cur_sess)

    self_q = shlex.quote(ide_self)
    reload_cmd = f"{self_q} --sessions-lines" + (f" {shlex.quote(cur_sess)}" if cur_sess else "")
    quit_bind = f"ctrl-x:execute-silent({self_q} --quit {{+1}})+reload({reload_cmd})"
    ack_bind = f"ctrl-y:execute-silent({self_q} --ack-ai {{+1}})+reload({reload_cmd})"
    open_pr_bind = f"ctrl-o:execute-silent({self_q} --open-pr {{1}})"
    preview_cmd = f"{self_q} --session-preview {{1}}"
    fzf_args = [
        fzf_bin,
        "--ansi",
        "--delimiter=\t",
        "--with-nth=2..",
        "--multi",
        "--layout=reverse",
        "--info=inline-right",
        "--prompt=IDE > ",
        "--border=rounded",
        "--border-label= Enter: switch · C-a/e/t: pane · C-y: ack · C-o: PR · M-n: new · C-x: quit · C-r: reload · Alt+s: close ",
        "--border-label-pos=bottom",
        f"--color=label:{hex_map['BASE01']}",
        "--expect=ctrl-a,ctrl-e,ctrl-t,alt-n",
        "--bind=alt-s:abort",
        f"--bind=ctrl-r:reload({reload_cmd})",
        f"--bind={ack_bind}",
        f"--bind={open_pr_bind}",
        f"--bind={quit_bind}",
        f"--preview={preview_cmd}",
        "--preview-window=right:56%:wrap",
    ]

    first_iter = True
    while True:
        rows = initial_rows if first_iter else build_sessions_lines(cur_sess)
        first_iter = False
        if not rows:
            if os.environ.get("TMUX"):
                run_tmux("display-message", "No active IDE sessions.")
            else:
                print("No active IDE sessions.")
            return 0

        proc = subprocess.run(
            fzf_args,
            input="\n".join(rows) + "\n",
            stdout=subprocess.PIPE,
            text=True,
            env=env,
            check=False,
        )
        out_lines = proc.stdout.splitlines() if proc.stdout else []
        first_key = out_lines[0].strip() if out_lines else ""
        if proc.returncode not in (0, 1) or (proc.returncode == 1 and first_key != "alt-n") or not out_lines:
            return 0
        if first_key in ("", "enter", "ctrl-a", "ctrl-e", "ctrl-t", "alt-n"):
            pressed = first_key
            selected_line = out_lines[1] if len(out_lines) > 1 else ""
        else:
            pressed = ""
            selected_line = out_lines[0]

        if pressed == "alt-n":
            chosen_dir = _pick_workspace_directory(fzf_bin, env, back_to_sessions=True)
            if not chosen_dir:
                continue
            return _launch_picked_workspace(chosen_dir, ide_self, origin_sess=origin_sess or cur_sess)

        chosen_sess = selected_line.split("\t", 1)[0].strip()
        if not chosen_sess or not session_exists(chosen_sess):
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
