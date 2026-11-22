"""Interactive 2-pane `ai-sw-*` workspace switcher popup session and `fzf` integration."""

from __future__ import annotations

import os
import re
import select
import shlex
import shutil
import subprocess
import sys
import time

from ide_lib.constants import (
    TMUX_SEP,
    is_switcher_session_name,
    read_switcher_result,
    sanitize_name_token,
    use_nerd_fonts,
    visible_width,
)
from ide_lib.dock import (
    cleanup_switcher_session,
    close_switcher_session,
    dock_session_into_switcher,
    select_dockable_ai_pane,
    switch_or_attach_session,
    switcher_owner_alive,
    switcher_placeholder_cmd,
    undock_switcher_session,
    with_switcher_lock,
)
from ide_lib.fleet import (
    _PANE_FMT_FIELDS,
    _SESSION_FMT_FIELDS,
    ack_ai_session,
    classify_ide_fleet,
    list_ide_sessions_with_server_status,
    parse_ide_session_cols,
    populate_fleet_git,
)
from ide_lib.hooks import resolve_workspace_target, sanitize_session_name
from ide_lib.preview import (
    PipeHangupWatcher,
    format_fleet_sessions_lines,
    format_session_preview_header,
    sync_switcher_slot_preview,
    write_slot_tty_viewport,
)
from ide_lib.theme import build_fzf_env, detect_color_tier, load_active_palette
from ide_lib.tmux import (
    pane_exists,
    resolve_active_client,
    resolve_switcher_context,
    run_tmux,
    session_exists,
    tmux_out,
)

SIDE_BY_SIDE_MIN_COLS = 90
_POPUP_SESS_RE = re.compile(r"^(ai|agy)-")
_POPUP_FORWARD_ENV_VARS = (
    "IDE_WORKSPACE_DIRS",
    "IDE_LINK_RULES",
    "IDE_FZF_BIN",
    "IDE_ZOXIDE_BIN",
    "IDE_PREVIEW_INTERVAL",
    "IDE_NERD_FONTS",
    "IDE_ASCII",
    "NO_COLOR",
    "NO_MOTION",
    "REDUCE_MOTION",
    "COLORTERM",
    "FZF_DEFAULT_OPTS_FILE",
    "_ZO_DATA_DIR",
    "XDG_CONFIG_HOME",
    "XDG_CACHE_HOME",
    "XDG_DATA_HOME",
)
_FZF_RESIZE_CAP_CACHE: dict[str, bool] = {}


def build_popup_env(client_name: str, forward_ai_cli: bool = False) -> list[str]:
    """Build shell-quoted `KEY=VAL` environment assignments for `tmux display-popup`."""
    popup_env = ["IDE_IN_POPUP=1", f"IDE_CLIENT={shlex.quote(client_name)}"]
    fwd_vars = (*_POPUP_FORWARD_ENV_VARS, "IDE_AI_CLI") if forward_ai_cli else _POPUP_FORWARD_ENV_VARS
    for fwd_var in fwd_vars:
        fwd_val = os.environ.get(fwd_var)
        if fwd_val:
            popup_env.append(f"{fwd_var}={shlex.quote(fwd_val)}")
    return popup_env


def maybe_reenter_in_tmux_popup(
    origin_sess: str,
    cur_sess: str,
    fzf_bin: str | None,
    forward_ai_cli: bool,
    inner_args: list[str],
    client_name_hint: str | None = None,
) -> int | None:
    """Re-invoke `inner_args` inside a `tmux display-popup` when running interactively inside `tmux`."""
    if not os.environ.get("TMUX") or os.environ.get("IDE_IN_POPUP") == "1" or os.environ.get("IDE_NO_POPUP") == "1":
        return None
    if client_name_hint is not None:
        client_name = client_name_hint
    else:
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
        popup_env = build_popup_env(client_name, forward_ai_cli=forward_ai_cli)
        inner_cmd = " ".join([*popup_env, *inner_args])
        pop_res = run_tmux("display-popup", "-c", client_name, "-E", "-w", "88%", "-h", "80%", inner_cmd)
        if pop_res.returncode == 0 or not sys.stdin.isatty():
            return 0 if pop_res.returncode in (0, 130) else pop_res.returncode
    return None


def launch_picked_workspace(
    chosen_dir: str,
    ide_self: str,
    origin_sess: str = "",
    layout_mode: str = "",
    ai_cli: str = "",
    ai_cli_from_flag: bool = False,
    detach_only: bool = False,
    sock_path: str = "",
) -> int:
    """Spawn or update the IDE workspace for `chosen_dir` and switch/attach unless `detach_only`."""
    resolved_dir = resolve_workspace_target(chosen_dir) or os.path.abspath(chosen_dir)
    target_sess = sanitize_session_name(resolved_dir)
    launch_cmd = [ide_self, "--detach"]
    if layout_mode == "2pane":
        launch_cmd.append("--2pane")
    if ai_cli_from_flag and ai_cli:
        launch_cmd.extend(["--ai", ai_cli])
    launch_cmd.append(resolved_dir)
    child_env = os.environ.copy()
    for drop_k in ("IDE_IN_POPUP", "IDE_SWITCHER_SESSION", "IDE_SWITCHER_RESULT"):
        child_env.pop(drop_k, None)
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
        rc = switch_or_attach_session(target_sess, origin_sess, sock_path=sock_path)
        ack_ai_session([target_sess], from_hook=True, refresh_always=False)
        return rc
    return launch_res.returncode


def fzf_supports_resize_bind(fzf_bin: str, version_text: str | None = None) -> bool:
    """Return True when `fzf` is `>= 0.46.0` (supporting `--bind=resize:refresh-preview` and `zero:`)."""
    cache_file = ""
    cache_key = ""
    if version_text is None:
        if os.path.basename(fzf_bin) != "fzf":
            return False
        cached = _FZF_RESIZE_CAP_CACHE.get(fzf_bin)
        if cached is not None:
            return cached
        try:
            norm_bin = fzf_bin.replace("\\", "/")
            real_p = os.path.realpath(fzf_bin)
            if "/mise/shims/" not in norm_bin and os.path.basename(real_p) != "mise":
                st = os.stat(real_p)
                xdg_cache = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
                cache_file = os.path.join(xdg_cache, "home-settings", "fzf-cap.cache")
                cache_key = f"{real_p}\t{st.st_ino}\t{st.st_mtime_ns}\t{st.st_size}\t"
                with open(cache_file, "r", encoding="utf-8") as cf:
                    for line in cf:
                        if line.startswith(cache_key):
                            val = line[len(cache_key):].strip() == "1"
                            _FZF_RESIZE_CAP_CACHE[fzf_bin] = val
                            return val
        except OSError:
            pass
        try:
            res = subprocess.run(
                [fzf_bin, "--version"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=0.5,
                check=False,
            )
            version_text = res.stdout if res.returncode == 0 and res.stdout else ""
        except (OSError, subprocess.SubprocessError):
            version_text = ""
    tok = version_text.strip().split(" ", 1)[0].lstrip("v")
    parts = tok.split(".")
    supported = False
    if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
        supported = (int(parts[0]), int(parts[1])) >= (0, 46)
    if fzf_bin and os.path.basename(fzf_bin) == "fzf":
        _FZF_RESIZE_CAP_CACHE[fzf_bin] = supported
        if cache_file and cache_key:
            tmp_c = f"{cache_file}.tmp.{os.getpid()}"
            try:
                os.makedirs(os.path.dirname(cache_file), mode=0o700, exist_ok=True)
                cfd = os.open(tmp_c, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
                try:
                    os.write(cfd, f"{cache_key}{'1' if supported else '0'}\n".encode("utf-8"))
                finally:
                    os.close(cfd)
                os.replace(tmp_c, cache_file)
            except OSError:
                try:
                    os.unlink(tmp_c)
                except OSError:
                    pass
    return supported


_fzf_supports_resize_bind = fzf_supports_resize_bind


def handle_switcher_op(op: str, sw_sess: str) -> int:
    """Handle event-driven switcher pane hooks (`focus`, `focus-ai`, `zero`, and `cleanup`)."""
    if not is_switcher_session_name(sw_sess):
        return 0
    norm_op = op.strip().lower()
    if norm_op == "cleanup":
        for _ in range(10):
            time.sleep(0.05)
            att = tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{session_attached}").strip()
            if not session_exists(sw_sess) or att not in ("", "0"):
                break
            if not switcher_owner_alive(sw_sess):
                cleanup_switcher_session(sw_sess)
                break
        return 0
    if norm_op in ("zero", "zero-check"):
        _, sw_cl, sw_rf = resolve_switcher_context(sw_sess)
        if sw_rf:
            sw_dir = os.path.dirname(sw_rf)
            if sw_dir:
                for seed_fn in ("seed.ans", "seed.ans.1", "seed.ans.meta.json"):
                    try:
                        os.unlink(os.path.join(sw_dir, seed_fn))
                    except OSError:
                        pass
        if norm_op == "zero":
            undock_switcher_session(sw_sess)
            slot_tty = tmux_out(
                "display-message",
                "-p",
                "-t",
                tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_slot_pane").strip() or f"={sw_sess}:",
                "#{?#{==:#{@ide_sw_placeholder},1},#{pane_tty},}",
            ).strip()
            run_tmux(
                "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_selected_sess", "",
                ";",
                "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_label", "",
            )
            if slot_tty:
                try:
                    sfd = os.open(slot_tty, os.O_WRONLY | os.O_NOCTTY | os.O_NONBLOCK)
                    try:
                        os.write(sfd, b"\x1b[?25l\x1b[H\x1b[2J")
                    finally:
                        os.close(sfd)
                except OSError:
                    pass
        rem_ide, server_up = list_ide_sessions_with_server_status()
        if server_up and not rem_ide:
            close_switcher_session(sw_sess, action="none", res_file_hint=sw_rf)
            if sw_cl:
                run_tmux("display-message", "-c", sw_cl, "No active IDE sessions.")
        return 0
    if norm_op == "focus-ai":
        raw_ai = tmux_out(
            "display-message",
            "-p",
            "-t",
            f"={sw_sess}:",
            TMUX_SEP.join([
                "#{@ide_sw_docked_pane}",
                "#{@ide_sw_docked_sess}",
                "#{@ide_sw_selected_sess}",
                "#{@ide_sw_slot_pane}",
                "#{@ide_sw_mode}",
                "#{@ide_sw_done}",
            ]),
        )
        if raw_ai and TMUX_SEP in raw_ai:
            dp, ds, sel_s, sp, sw_m, sw_done = (
                p.strip() for p in (raw_ai.split(TMUX_SEP) + ["", "", "", "", "", ""])[:6]
            )
            if sw_m != "new" and sw_done != "1":
                want_s = ds or sel_s
                if (not dp or not pane_exists(dp)) and want_s:
                    if dock_session_into_switcher(sw_sess, want_s):
                        dp = tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_docked_pane").strip()
                        sp = tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_slot_pane").strip()
                        ds = want_s
                if tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_done").strip() == "1":
                    return 0
                if dp and not pane_exists(dp):
                    undock_switcher_session(sw_sess)
                    return 0
                cand_p = dp if dp else sp
                target_p = (
                    cand_p
                    if cand_p and tmux_out("display-message", "-p", "-t", cand_p, "#{session_name}").strip() == sw_sess
                    else ""
                )
                if target_p:
                    run_tmux(
                        "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_visited_ai", "1",
                        ";",
                        "select-pane", "-t", target_p,
                    )
                    if dp and target_p == dp and ds:
                        ack_ai_session([ds], from_hook=True, refresh_always=True, entering_ai=True)
        return 0
    if norm_op == "focus":
        raw_foc = tmux_out(
            "display-message",
            "-p",
            "-t",
            f"={sw_sess}:",
            TMUX_SEP.join([
                "#{pane_id}",
                "#{@ide_sw_fzf_pane}",
                "#{@ide_sw_docked_pane}",
                "#{@ide_sw_docked_sess}",
                "#{@ide_sw_selected_sess}",
                "#{@ide_sw_visited_ai}",
                "#{@ide_sw_mode}",
                "#{@ide_sw_done}",
            ]),
        )
        if not raw_foc or TMUX_SEP not in raw_foc:
            return 0
        act_p, fzf_p, docked_p, docked_s, sel_s, visited_ai, sw_mode, sw_done = (
            p.strip() for p in (raw_foc.split(TMUX_SEP) + [""] * 8)[:8]
        )
        if sw_mode == "new" or sw_done == "1":
            return 0
        if docked_p and not pane_exists(docked_p):
            undocked_s = undock_switcher_session(sw_sess)
            if undocked_s:
                preview_s = sel_s or undocked_s or docked_s
                if preview_s and sw_mode == "sessions":
                    sync_switcher_slot_preview(sw_sess, preview_s)
                run_tmux("set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_visited_ai", "0")
                if fzf_p and pane_exists(fzf_p):
                    run_tmux("send-keys", "-t", fzf_p, "C-r")
            return 0
        if fzf_p and act_p != fzf_p:
            want_s = docked_s or sel_s
            if (not docked_p or not pane_exists(docked_p)) and want_s:
                if dock_session_into_switcher(sw_sess, want_s):
                    docked_p = tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_docked_pane").strip()
                    docked_s = want_s
                    if docked_p and pane_exists(docked_p):
                        run_tmux("select-pane", "-t", docked_p)
            if docked_p and docked_s:
                run_tmux("set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_visited_ai", "1")
                ack_ai_session([docked_s], from_hook=True, refresh_always=True, entering_ai=True)
        elif fzf_p and act_p == fzf_p and sw_mode == "sessions":
            undocked_s = undock_switcher_session(sw_sess) if docked_p else ""
            preview_s = sel_s or undocked_s or docked_s
            if preview_s and undocked_s:
                sync_switcher_slot_preview(sw_sess, preview_s)
            if undocked_s or (not docked_p and visited_ai == "1"):
                run_tmux("set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_visited_ai", "0")
                if pane_exists(fzf_p):
                    run_tmux("send-keys", "-t", fzf_p, "C-r")
        return 0
    return 0


def _ensure_switcher_tmux_conf(already_loaded: bool = False) -> None:
    if already_loaded or tmux_out("show-options", "-gqv", "@ide_tmux_conf_loaded") == "1":
        return
    tmux_conf = os.path.expanduser("~/.tmux.conf")
    if os.path.isfile(tmux_conf):
        run_tmux("source-file", tmux_conf)
    xdg_cfg = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    tmux_theme_conf = os.path.join(xdg_cfg, "home-settings", "tmux-theme.conf")
    if os.path.isfile(tmux_theme_conf):
        run_tmux("source-file", tmux_theme_conf)


def format_sessions_footer_label(pane_w: int = 120, in_two_pane: bool = False) -> str:
    """Pack complete middle-dot-separated key hints within `pane_w` without mid-word clipping."""
    if in_two_pane:
        ordered = [
            "Enter: switch",
            "Alt+l: AI",
            "C-a/e/t: pane",
            "C-y: ack",
            "C-o: PR",
            "M-n: new",
            "C-x: quit",
            "C-r/F5: reload",
            "F1: help",
            "Alt+s: close",
        ]
        priority = [0, 1, 9, 3, 5, 6, 4, 7, 8, 2]
    else:
        ordered = [
            "Enter: switch",
            "C-a/e/t: pane",
            "C-y: ack",
            "C-o: PR",
            "M-n: new",
            "C-x: quit",
            "C-r/F5: reload",
            "F1: help",
            "Alt+s: close",
        ]
        priority = [0, 8, 2, 4, 5, 1, 3, 6, 7]

    budget = max(24, pane_w - 4)
    chosen_idxs: set[int] = set()
    for p_idx in priority:
        cand_idxs = sorted([*chosen_idxs, p_idx])
        cand_str = " " + " · ".join(ordered[i] for i in cand_idxs) + " "
        if visible_width(cand_str) <= budget or not chosen_idxs:
            chosen_idxs.add(p_idx)
    final_items = [ordered[i] for i in sorted(chosen_idxs)]
    return " " + " · ".join(final_items) + " "


def build_sessions_fzf_args(
    fzf_bin: str,
    ide_self: str,
    cur_sess: str,
    hex_map: dict[str, str],
    supports_modern_binds: bool,
    sw_sess: str = "",
    pane_h: int = 32,
    pane_w: int = 120,
    seed_sess: str = "",
    seed_file: str = "",
) -> list[str]:
    """Construct `fzf` argument vector for single-pane or 2-pane `ai-sw-*` session switching."""
    self_q = shlex.quote(ide_self)
    reload_cmd = f"{self_q} --sessions-lines" + (f" {shlex.quote(cur_sess)}" if cur_sess else "")
    quit_bind = f"ctrl-x:execute-silent({self_q} --quit {{+1}})+reload({reload_cmd})"
    ctrl_r_bind = f"ctrl-r:reload({reload_cmd})"
    f5_bind = f"f5:reload({reload_cmd})"
    ack_bind = f"ctrl-y:execute-silent({self_q} --ack-ai {{+1}})+reload({reload_cmd})"
    open_pr_bind = f"ctrl-o:execute-silent({self_q} --open-pr {{1}})"
    help_bind = f"f1:execute({self_q} --keys >/dev/tty </dev/tty)"
    alt_qmark_bind = f"alt-?:execute({self_q} --keys >/dev/tty </dev/tty)"
    if seed_sess and seed_file:
        seed_sess_q = shlex.quote(seed_sess)
        seed_q = shlex.quote(seed_file)
        seed_used_q = shlex.quote(f"{seed_file}.1")
        seed_meta_q = shlex.quote(f"{seed_file}.meta.json")
        preview_cmd = (
            f"if [ {seed_sess_q} = {{1}} ] && mv -f {seed_q} {seed_used_q} 2>/dev/null; then "
            f"cat {seed_used_q}; IDE_PREVIEW_SEEDED={seed_used_q} IDE_PREVIEW_WHILE_WORKING=1 exec {self_q} --session-preview --follow -- {{1}}; "
            f"fi; rm -f {seed_q} {seed_used_q} {seed_meta_q} 2>/dev/null || :; "
            f"IDE_PREVIEW_WHILE_WORKING=1 exec {self_q} --session-preview --follow -- {{1}}"
        )
    else:
        preview_cmd = f"IDE_PREVIEW_WHILE_WORKING=1 exec {self_q} --session-preview --follow -- {{1}}"

    switcher_extra_binds: list[str] = []
    if sw_sess:
        sw_q = shlex.quote(sw_sess)
        meta_rows = min(7, max(4, pane_h // 4))
        preview_window_spec = f"down:{meta_rows}:wrap:noinfo"
        switcher_extra_binds.append(f"--bind=alt-l:execute-silent({self_q} --switcher-op focus-ai {sw_q})")
        if supports_modern_binds:
            switcher_extra_binds.append(f"--bind=zero:execute-silent({self_q} --switcher-op zero {sw_q})")
        else:
            quit_bind = (
                f"ctrl-x:execute-silent({self_q} --quit {{+1}}; "
                f"{self_q} --switcher-op zero-check {sw_q})+reload({reload_cmd})"
            )
            ctrl_r_bind = (
                f"ctrl-r:execute-silent({self_q} --switcher-op zero-check {sw_q})+reload({reload_cmd})"
            )
            f5_bind = (
                f"f5:execute-silent({self_q} --switcher-op zero-check {sw_q})+reload({reload_cmd})"
            )
        resize_binds: list[str] = []
    else:
        preview_window_spec = (
            "down:50%:wrap:noinfo"
            if 0 < pane_w < SIDE_BY_SIDE_MIN_COLS
            else "right:56%:wrap:noinfo"
        )
        resize_binds = ["--bind=resize:refresh-preview"] if supports_modern_binds else []

    footer_label = format_sessions_footer_label(pane_w=pane_w, in_two_pane=bool(sw_sess))
    no_motion = bool(os.environ.get("NO_MOTION") or os.environ.get("REDUCE_MOTION"))
    spinner_hex = hex_map["BASE03"] if no_motion else hex_map["CYAN"]
    color_label_args = (
        []
        if detect_color_tier() in ("nocolor", "mono", "16color")
        else [
            f"--color=label:{hex_map['BASE01']}",
            (
                f"--color=border:{hex_map['BASE01']},separator:{hex_map['BASE01']},"
                f"gutter:{hex_map['BASE03']},preview-bg:{hex_map['BASE03']},spinner:{spinner_hex}"
            ),
        ]
    )

    return [
        fzf_bin,
        "--ansi",
        "--delimiter=\t",
        "--with-nth=2..",
        "--multi",
        "--layout=reverse",
        "--info=inline-right",
        "--no-scrollbar",
        "--prompt=IDE > ",
        "--border=rounded",
        f"--border-label={footer_label}",
        "--border-label-pos=bottom",
        *color_label_args,
        "--expect=ctrl-a,ctrl-e,ctrl-t,alt-n",
        "--bind=alt-s:abort",
        "--bind=f12:refresh-preview",
        *resize_binds,
        *switcher_extra_binds,
        f"--bind={ctrl_r_bind}",
        f"--bind={f5_bind}",
        f"--bind={help_bind}",
        f"--bind={alt_qmark_bind}",
        f"--bind={ack_bind}",
        f"--bind={open_pr_bind}",
        f"--bind={quit_bind}",
        f"--preview={preview_cmd}",
        f"--preview-window={preview_window_spec}",
    ]


_build_sessions_fzf_args = build_sessions_fzf_args


def parse_fzf_session_output(returncode: int, raw_out: str) -> tuple[str, str] | None:
    """Parse `(pressed, selected_line)` from `fzf --expect=...` stdout, or `None` on cancel/abort."""
    out_lines = raw_out.splitlines() if raw_out else []
    first_key = out_lines[0].strip() if out_lines else ""
    if returncode not in (0, 1) or (returncode == 1 and first_key != "alt-n") or not out_lines:
        return None
    if first_key in ("", "enter", "ctrl-a", "ctrl-e", "ctrl-t", "alt-n"):
        pressed = first_key
        selected_line = out_lines[1] if len(out_lines) > 1 else ""
    else:
        pressed = ""
        selected_line = out_lines[0]
    return (pressed, selected_line)


_parse_fzf_session_output = parse_fzf_session_output


class OuterSwitcherSnapshot:
    """Single-round-trip tmux client, session, and pane topology snapshot for `Alt+s`."""

    __slots__ = (
        "server_up",
        "server_pid",
        "sock_path",
        "tmux_conf_loaded",
        "origin_sess",
        "cur_sess",
        "client_name",
        "raw_cur",
        "client_w",
        "client_h",
        "existing_sw",
        "all_sessions",
        "raw_ide_sessions",
        "pane_rows_13",
        "pane_dock_map",
        "sess_panes",
        "win_active_pane",
        "focused_sessions",
    )

    def __init__(self) -> None:
        self.server_up = False
        self.server_pid = ""
        self.sock_path = ""
        self.tmux_conf_loaded = False
        self.origin_sess = ""
        self.cur_sess = ""
        self.client_name = ""
        self.raw_cur = ""
        self.client_w = 160
        self.client_h = 48
        self.existing_sw = ""
        self.all_sessions: set[str] = set()
        self.raw_ide_sessions: list[dict[str, str]] = []
        self.pane_rows_13: list[list[str]] = []
        self.pane_dock_map: dict[str, tuple[str, str, str, str, str, str, str]] = {}
        self.sess_panes: dict[str, list[tuple[str, str, str]]] = {}
        self.win_active_pane: dict[str, str] = {}
        self.focused_sessions: set[str] = set()


def _tmux_dquote(s: str) -> str:
    """Wrap `s` in tmux double quotes, escaping `\\`, `\"`, and `$` for `cmd-parse`."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$") + '"'


def query_outer_switcher_snapshot(target_arg: str) -> OuterSwitcherSnapshot:
    """Collect client, session, and pane topology for `Alt+s` in a single tmux IPC round-trip."""
    snap = OuterSwitcherSnapshot()
    res = run_tmux(
        "list-clients",
        "-F",
        TMUX_SEP.join([
            "CL",
            "#{client_name}",
            "#{session_name}",
            "#{session_id}",
            "#{client_activity}",
            "#{client_width}",
            "#{client_height}",
            "#{client_flags}",
            "#{socket_path}",
        ]),
        ";",
        "list-sessions",
        "-F",
        TMUX_SEP.join([
            "SESS",
            *_SESSION_FMT_FIELDS,
            "#{session_id}",
            "#{pid}",
            "#{socket_path}",
            "#{@ide_tmux_conf_loaded}",
            "#{@ide_switcher}",
            "#{@ide_sw_client}",
            "#{@ide_sw_done}",
            "#{@ide_sw_docked_sess}",
            "#{@ide_sw_selected_sess}",
        ]),
        ";",
        "list-panes",
        "-a",
        "-F",
        TMUX_SEP.join([
            "PANE",
            *_PANE_FMT_FIELDS,
            "#{@ide_owner_sess}",
            "#{@ide_sw_docked_by}",
        ]),
    )
    if res.returncode != 0 or not res.stdout:
        return snap

    snap.server_up = True
    cl_pfx = f"CL{TMUX_SEP}"
    sess_pfx = f"SESS{TMUX_SEP}"
    pane_pfx = f"PANE{TMUX_SEP}"

    clients: list[tuple[str, str, str, int, int, int, str]] = []
    clients_by_name: dict[str, tuple[str, str, int, int, str]] = {}
    focused_clients: set[str] = set()
    sess_by_id: dict[str, str] = {}
    sw_docked_map: dict[str, str] = {}
    sw_rows: list[tuple[str, str, str, str]] = []
    ide_sess_set: set[str] = set()
    pane_caller_map: dict[str, tuple[str, str]] = {}

    for line in res.stdout.splitlines():
        if line.startswith(cl_pfx):
            cc = (line.split(TMUX_SEP)[1:] + [""] * 8)[:8]
            cname = cc[0].strip()
            csess = cc[1].strip()
            csid = cc[2].strip()
            cact = int(cc[3]) if cc[3].strip().isdigit() else 0
            cw = int(cc[4]) if cc[4].strip().isdigit() else 160
            ch = int(cc[5]) if cc[5].strip().isdigit() else 48
            cflags = cc[6].strip()
            csock = cc[7].strip()
            if cname:
                clients.append((cname, csess, csid, cact, cw, ch, csock))
                clients_by_name[cname] = (csess, csid, cw, ch, csock)
            if csock and not snap.sock_path:
                snap.sock_path = csock
            if "focused" in {tok.strip() for tok in cflags.split(",") if tok.strip()}:
                if cname:
                    focused_clients.add(cname)
                if csess:
                    snap.focused_sessions.add(csess)
        elif line.startswith(sess_pfx):
            sc = (line.split(TMUX_SEP)[1:] + [""] * 28)[:28]
            sname = sc[0].strip()
            if not sname:
                continue
            snap.all_sessions.add(sname)
            sid = sc[19].strip()
            if sid:
                sess_by_id[sid] = sname
            if not snap.server_pid and sc[20].strip():
                snap.server_pid = sc[20].strip()
            if not snap.sock_path and sc[21].strip():
                snap.sock_path = sc[21].strip()
            if sc[22].strip() == "1":
                snap.tmux_conf_loaded = True
            is_sw = sc[23].strip()
            sw_cl = sc[24].strip()
            sw_done = sc[25].strip()
            sw_docked = sc[26].strip() or sc[27].strip()
            if is_switcher_session_name(sname):
                sw_rows.append((sname, is_sw, sw_cl, sw_done))
                if sw_docked:
                    sw_docked_map[sname] = sw_docked
            parsed_ide = parse_ide_session_cols(sc[:19])
            if parsed_ide is not None:
                snap.raw_ide_sessions.append(parsed_ide)
                ide_sess_set.add(sname)
        elif line.startswith(pane_pfx):
            pc = (line.split(TMUX_SEP)[1:] + [""] * 15)[:15]
            row13 = pc[:13]
            snap.pane_rows_13.append(row13)
            psess = row13[0].strip()
            pwin = row13[1].strip()
            pid = row13[3].strip()
            pact = row13[5].strip()
            pzoom = row13[7].strip()
            prole = row13[8].strip()
            pph = row13[12].strip()
            powner = pc[13].strip()
            pdocked_by = pc[14].strip()
            if pid:
                pane_caller_map[pid] = (psess, powner)
                snap.pane_dock_map[pid] = (psess, pwin, pact, pzoom, prole, pdocked_by, pph)
                snap.sess_panes.setdefault(psess, []).append((pid, prole, pph))
                if pact == "1" and pwin:
                    snap.win_active_pane[pwin] = pid

    for sname, is_sw, sw_cl, _ in sw_rows:
        if is_sw == "1" and sw_cl and sw_cl in focused_clients:
            snap.focused_sessions.add(sname)

    arg = "" if (target_arg.startswith("#{") and target_arg.endswith("}")) else target_arg
    resolved_arg = ""
    if arg:
        if is_switcher_session_name(arg):
            resolved_arg = sw_docked_map.get(arg, "")
        else:
            is_dir = os.path.isdir(arg)
            if not is_dir and sanitize_name_token(arg) == arg:
                resolved_arg = arg
            elif arg in snap.all_sessions:
                resolved_arg = arg
            elif is_dir:
                resolved_arg = sanitize_session_name(os.path.abspath(arg))
            else:
                resolved_arg = sanitize_name_token(arg)
    snap.origin_sess = resolved_arg if (resolved_arg and resolved_arg in snap.all_sessions) else ""

    tmux_env = os.environ.get("TMUX", "")
    tmux_parts = tmux_env.split(",") if tmux_env else []
    env_srv_pid = tmux_parts[-2] if len(tmux_parts) >= 3 else ""
    env_last_sid = tmux_parts[-1].lstrip("$") if len(tmux_parts) >= 3 else ""

    inferred_cur = ""
    if len(tmux_parts) >= 3 and (not snap.server_pid or env_srv_pid == snap.server_pid):
        tmux_pane = os.environ.get("TMUX_PANE", "")
        cand_sess = ""
        cand_owner = ""
        if tmux_pane and tmux_pane in pane_caller_map:
            cand_sess, cand_owner = pane_caller_map[tmux_pane]
        elif not tmux_pane and env_last_sid:
            cand_sess = sess_by_id.get(f"${env_last_sid}", "")
        if cand_sess in ide_sess_set:
            inferred_cur = cand_sess
        elif is_switcher_session_name(cand_sess):
            for fb_s in (cand_owner, sw_docked_map.get(cand_sess, "")):
                if fb_s and fb_s in ide_sess_set:
                    inferred_cur = fb_s
                    break

    snap.cur_sess = snap.origin_sess if (snap.origin_sess and snap.origin_sess in ide_sess_set) else inferred_cur

    if tmux_env:
        ide_cl = os.environ.get("IDE_CLIENT", "").strip()
        chosen_cl = ""
        if ide_cl and not ide_cl.startswith("#{"):
            chosen_cl = ide_cl
        else:
            origin_or_cur = snap.origin_sess or snap.cur_sess
            if origin_or_cur:
                best_act = -1
                for cname, csess, _, cact, _, _, _ in clients:
                    if csess == origin_or_cur and cact >= best_act:
                        best_act = cact
                        chosen_cl = cname
            if not chosen_cl and env_last_sid:
                want_sid = f"${env_last_sid}"
                best_act2 = -1
                for cname, _, csid, cact, _, _, _ in clients:
                    if csid == want_sid and cact >= best_act2:
                        best_act2 = cact
                        chosen_cl = cname
            if not chosen_cl:
                cl_fb = tmux_out("display-message", "-p", "#{client_name}").strip()
                if cl_fb and not cl_fb.startswith("#{"):
                    chosen_cl = cl_fb
        snap.client_name = chosen_cl
        if chosen_cl and chosen_cl in clients_by_name:
            csess, _, cw, ch, csock = clients_by_name[chosen_cl]
            snap.raw_cur = csess
            snap.client_w = cw
            snap.client_h = ch
            if csock:
                snap.sock_path = csock
        elif not chosen_cl:
            snap.raw_cur = snap.origin_sess or tmux_out("display-message", "-p", "#{session_name}")
        if chosen_cl:
            for sname, is_sw, sw_cl, sw_done in sw_rows:
                if is_sw == "1" and sw_cl == chosen_cl and sw_done != "1":
                    snap.existing_sw = sname
                    break

    return snap


def _fifo_reader_alive(wfd: int) -> bool:
    """Return False if the read end of FIFO `wfd` has already closed."""
    watcher = PipeHangupWatcher(wfd, check_stat=False)
    try:
        return not watcher.is_closed()
    finally:
        watcher.close()


def run_interactive_switcher_session(
    origin_sess: str,
    cur_sess: str,
    ide_self: str,
    fzf_bin: str,
    forward_ai_cli: bool,
    snap: OuterSwitcherSnapshot,
    client_name: str = "",
    layout_mode: str = "",
    ai_cli: str = "",
    ai_cli_from_flag: bool = False,
) -> int | None:
    """Spawn a 2-pane switcher (`fzf` list on left, live interactive AI pane on right) and attach."""
    import errno
    import json
    import tempfile
    import threading

    _ensure_switcher_tmux_conf(already_loaded=snap.tmux_conf_loaded)
    hex_map, esc = load_active_palette()
    fzf_env = build_fzf_env(hex_map)
    supports_modern_binds = fzf_supports_resize_bind(fzf_bin)

    fleet = classify_ide_fleet(
        include_git=False,
        cur_sess=cur_sess,
        raw_sessions=snap.raw_ide_sessions,
        panes_rows=snap.pane_rows_13,
        focused_sessions=snap.focused_sessions,
    )
    if not fleet:
        return None

    sock_path = snap.sock_path
    pop_w_arg = "90%"
    pop_h_arg = "85%"
    if client_name:
        if snap.client_w > 0 and snap.client_h > 0:
            pop_w = min(snap.client_w, max(min(82, snap.client_w), int(snap.client_w * 0.90)))
            pop_h = min(snap.client_h, max(min(22, snap.client_h), int(snap.client_h * 0.85)))
            sw_cols = max(20, pop_w - 2)
            sw_rows = max(10, pop_h - 2)
            pop_w_arg = str(pop_w)
            pop_h_arg = str(pop_h)
        else:
            sw_cols = max(80, int(160 * 0.90) - 2)
            sw_rows = max(20, int(48 * 0.85) - 2)
    else:
        term_sz = shutil.get_terminal_size(fallback=(160, 48))
        sw_cols = max(40, term_sz.columns)
        sw_rows = max(16, term_sz.lines)

    if sw_cols < SIDE_BY_SIDE_MIN_COLS:
        return None

    rt_raw = (os.environ.get("XDG_RUNTIME_DIR") or "").strip()
    rt_dir = rt_raw if (rt_raw and os.path.isdir(rt_raw)) else "/tmp"
    sw_tmp_dir = tempfile.mkdtemp(prefix=f"ide-sw-res-{os.getpid()}-", dir=rt_dir)
    res_file = os.path.join(sw_tmp_dir, "result.json")
    in_file = os.path.join(sw_tmp_dir, "rows.tsv")
    out_file = os.path.join(sw_tmp_dir, "fzf.out")
    rc_file = os.path.join(sw_tmp_dir, "fzf.rc")
    seed_file = os.path.join(sw_tmp_dir, "seed.ans")
    seed_meta_file = f"{seed_file}.meta.json"
    run_sh = os.path.join(sw_tmp_dir, "run_fzf.sh")

    sw_sess = f"ai-sw-{os.getpid()}-{int(time.monotonic() * 1000) % 1000000}"

    initial_entry = fleet[0]
    initial_top = str(initial_entry["sess"])
    init_meta = next((s for s in snap.raw_ide_sessions if s["sess"] == initial_top), None)
    target_pane = ""
    healed_ai = False
    init_label = ""
    busy_init_label = ""
    if init_meta is not None:
        rec_ai0 = init_meta["ai_pane"]
        if (
            rec_ai0
            and rec_ai0 in snap.pane_dock_map
            and is_switcher_session_name(snap.pane_dock_map[rec_ai0][0])
            and snap.pane_dock_map[rec_ai0][0] != sw_sess
        ):
            busy_init_label = f"{initial_top} · (in other switcher)"
        target_pane, healed_ai = select_dockable_ai_pane(
            initial_top,
            rec_ai0,
            snap.pane_dock_map,
            snap.sess_panes,
        )
        init_ai_cli = init_meta["ai_cli"] or "AI"
        init_label = busy_init_label or f"{initial_top} · {init_ai_cli}"

    seeded_sess = initial_top if (initial_top and not initial_entry.get("quit_err")) else ""
    left_pane_w = max(36, sw_cols - int(sw_cols * 0.56) - 1)

    fzf_args = build_sessions_fzf_args(
        fzf_bin=fzf_bin,
        ide_self=ide_self,
        cur_sess=cur_sess,
        hex_map=hex_map,
        supports_modern_binds=supports_modern_binds,
        sw_sess=sw_sess,
        pane_h=max(1, sw_rows - 1),
        pane_w=left_pane_w,
        seed_sess=seeded_sess,
        seed_file=seed_file if seeded_sess else "",
    )

    env_flags = [
        "-e", "IDE_IN_POPUP=1",
        "-e", f"IDE_SWITCHER_SESSION={sw_sess}",
        "-e", f"IDE_SWITCHER_RESULT={res_file}",
    ]
    if client_name:
        env_flags.extend(["-e", f"IDE_CLIENT={client_name}"])
    fwd_vars = (
        "HOME",
        "PATH",
        "XDG_RUNTIME_DIR",
        "TMUX_TMPDIR",
        *_POPUP_FORWARD_ENV_VARS,
        *(("IDE_AI_CLI",) if forward_ai_cli else ()),
    )
    for var_k in fwd_vars:
        var_v = os.environ.get(var_k)
        if var_v:
            env_flags.extend(["-e", f"{var_k}={var_v}"])

    self_q = shlex.quote(ide_self)
    sw_q = shlex.quote(sw_sess)
    alt_n_parts = [self_q, "--sessions"]
    if layout_mode == "2pane":
        alt_n_parts.append("--2pane")
    if ai_cli_from_flag and ai_cli:
        alt_n_parts.extend(["--ai", shlex.quote(ai_cli)])
    if cur_sess:
        alt_n_parts.append(shlex.quote(cur_sess))
    alt_n_cmd = " ".join(alt_n_parts)
    fzf_cmd_str = " ".join(shlex.quote(a) for a in fzf_args)
    fzf_def_opts_q = shlex.quote(fzf_env.get("FZF_DEFAULT_OPTS", ""))
    in_q = shlex.quote(in_file)
    out_q = shlex.quote(out_file)
    rc_q = shlex.quote(rc_file)
    seed_rm_q = (
        f"{shlex.quote(seed_file)} {shlex.quote(seed_file + '.1')} {shlex.quote(seed_meta_file)}"
    )

    nf = use_nerd_fonts()
    sw_ico = " " if nf else ""
    ai_ico = "󰚩 " if nf else ""
    ptr = ">" if (os.environ.get("TERM") or "").lower() == "dumb" else "▸"
    border_fmt = (
        f"#{{?#{{==:#{{@ide_sw_role}},list}},"
        f"#{{?#{{==:#{{@ide_sw_mode}},new}},"
        f"#[fg={hex_map['BLUE']}#,nobold]{ptr} {sw_ico}#[fg={hex_map['BASE1']}#,nobold]New Workspace #[fg={hex_map['BASE01']}#,nobold](Enter: launch · Esc: back) ,"
        f"#{{?pane_active,#[fg={hex_map['BLUE']}#,nobold]{ptr} {sw_ico}#[fg={hex_map['BASE1']}#,nobold]Sessions #[fg={hex_map['BASE01']}#,nobold](Alt+l: interact) ,"
        f"#[fg={hex_map['BASE01']}#,nobold]  {sw_ico}Sessions (Alt+h: list) }}}},"
        f"#{{?pane_active,#[fg={hex_map['CYAN']}#,nobold]{ptr} {ai_ico}#[fg={hex_map['BASE1']}#,nobold]#{{?#{{!=:#{{@ide_sw_label}},}},#{{@ide_sw_label}},AI}} #[fg={hex_map['GREEN']}#,nobold][LIVE] #[fg={hex_map['BASE01']}#,nobold](Alt+h: list · Alt+s: close) ,"
        f"#[fg={hex_map['BASE0']}#,nobold]  {ai_ico}#{{?#{{!=:#{{@ide_sw_label}},}},#{{@ide_sw_label}},(no session)}} #[fg={hex_map['BASE01']}#,nobold][PREVIEW] (Alt+l / click: interact) }}}}"
    )

    cancel_ev = threading.Event()
    dock_decided_ev = threading.Event()
    seed_allowed = bool(seeded_sess)
    feeder_thr: threading.Thread | None = None
    cleaned = False

    def _write_seed_artifacts() -> None:
        if not seeded_sess or not seed_allowed:
            return
        seed_lines = format_session_preview_header(
            initial_entry,
            esc,
            str(initial_entry["git_branch"]),
            bool(initial_entry["git_dirty"]),
            str(initial_entry["git_detail"]),
            "",
            [str(p) for p in (initial_entry.get("worktree_peers") or [])],
        )
        meta_payload = json.dumps({
            "state": str(initial_entry["state"]),
            "workdir": str(initial_entry.get("workdir") or ""),
            "git_branch": str(initial_entry["git_branch"]),
            "git_dirty": bool(initial_entry["git_dirty"]),
            "git_detail": str(initial_entry["git_detail"]),
            "wt_roots": {str(e["sess"]): str(e.get("worktree_root") or "") for e in fleet},
            "peer_workdirs": {str(e["sess"]): str(e.get("workdir") or "") for e in fleet},
        })
        try:
            tmp_meta = f"{seed_meta_file}.tmp"
            with open(tmp_meta, "w", encoding="utf-8") as mfh:
                mfh.write(meta_payload)
            os.replace(tmp_meta, seed_meta_file)
            tmp_seed = f"{seed_file}.tmp"
            with open(tmp_seed, "w", encoding="utf-8") as sfh:
                sfh.write("\n".join(seed_lines) + "\n")
            os.replace(tmp_seed, seed_file)
        except OSError:
            pass

    def _feed_fifo_rows() -> None:
        git_done = threading.Event()

        def _run_git() -> None:
            try:
                populate_fleet_git(fleet)
            finally:
                git_done.set()

        git_thr = threading.Thread(target=_run_git, daemon=True)
        git_thr.start()

        deadline = time.monotonic() + 5.0
        wfd = -1
        while not cancel_ev.is_set() and time.monotonic() < deadline:
            try:
                wfd = os.open(in_file, os.O_WRONLY | os.O_NONBLOCK)
                break
            except OSError as exc:
                if exc.errno == errno.ENXIO:
                    time.sleep(0.003)
                    continue
                return
        if wfd < 0:
            return
        try:
            while not git_done.wait(timeout=0.02):
                if cancel_ev.is_set():
                    return
            dock_decided_ev.wait(timeout=1.0)
            if cancel_ev.is_set() or not _fifo_reader_alive(wfd):
                return
            _write_seed_artifacts()
            rows_list = format_fleet_sessions_lines(fleet, esc)
            payload = ("\n".join(rows_list) + "\n").encode("utf-8") if rows_list else b""
            view = memoryview(payload)
            sent = 0
            total = len(payload)
            while sent < total and not cancel_ev.is_set():
                try:
                    written = os.write(wfd, view[sent:])
                    if written > 0:
                        sent += written
                except BlockingIOError:
                    select.select([], [wfd], [], 0.04)
                except OSError:
                    break
        finally:
            try:
                os.close(wfd)
            except OSError:
                pass

    def _cleanup_sw_state() -> None:
        nonlocal cleaned
        if not cleaned:
            cleaned = True
            cancel_ev.set()
            if feeder_thr is not None:
                feeder_thr.join(timeout=0.3)
            cleanup_switcher_session(sw_sess)
            shutil.rmtree(sw_tmp_dir, ignore_errors=True)

    try:
        use_fifo = False
        try:
            os.mkfifo(in_file, 0o600)
            use_fifo = True
        except OSError:
            use_fifo = False

        if use_fifo:
            feeder_thr = threading.Thread(target=_feed_fifo_rows, daemon=True)
            feeder_thr.start()
        else:
            populate_fleet_git(fleet)
            _write_seed_artifacts()
            initial_rows = format_fleet_sessions_lines(fleet, esc)
            if not initial_rows:
                return None
            with open(in_file, "w", encoding="utf-8") as inf:
                inf.write("\n".join(initial_rows) + "\n")

        sh_fd = os.open(run_sh, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o700)
        try:
            script_body = (
                "#!/bin/sh\n"
                f"export FZF_DEFAULT_OPTS={fzf_def_opts_q}\n"
                f"SHELL=/bin/sh {fzf_cmd_str} < {in_q} > {out_q}\n"
                "rc=$?\n"
                'first_ln=""\n'
                f'IFS= read -r first_ln < {out_q} || true\n'
                'if [ "$rc" -le 1 ] && [ "$first_ln" = "alt-n" ]; then\n'
                f"  rm -f {seed_rm_q} 2>/dev/null || true\n"
                f"  IDE_SW_START_ALT_N=1 exec {alt_n_cmd}\n"
                "fi\n"
                f"printf '%s\\n' \"$rc\" > {rc_q}\n"
                f'tmux set-option -q -t "={sw_sess}:" @ide_sw_done 1 \\; detach-client -s "={sw_sess}" >/dev/null 2>&1 || true\n'
                "printf '\\033[?25l'\n"
                'trap "exit 0" INT TERM HUP\n'
                "exec sleep 60\n"
            )
            os.write(sh_fd, script_body.encode("utf-8"))
        finally:
            os.close(sh_fd)

        focus_cond = (
            "#{&&:#{!=:#{@ide_sw_done},1},#{&&:#{!=:#{@ide_sw_mode},new},"
            "#{||:#{!=:#{pane_id},#{@ide_sw_fzf_pane}},#{==:#{@ide_sw_visited_ai},1},#{!=:#{@ide_sw_docked_pane},}}}}"
        )
        dead_dock_cond = (
            "#{&&:#{!=:#{@ide_sw_done},1},#{&&:#{!=:#{@ide_sw_mode},new},"
            "#{&&:#{!=:#{@ide_sw_docked_pane},},#{==:#{window_panes},1}}}}"
        )
        focus_sh = f"{self_q} --switcher-op focus {sw_q} || true".replace("#", "##")
        focus_run = f"run-shell -b {_tmux_dquote(focus_sh)}"
        focus_hook = f"if-shell -F {_tmux_dquote(focus_cond)} {_tmux_dquote(focus_run)}"
        dead_dock_hook = f"if-shell -F {_tmux_dquote(dead_dock_cond)} {_tmux_dquote(focus_run)}"
        cleanup_sh = (
            f"sleep 0.15; tmux has-session -t {shlex.quote('=' + sw_sess)} 2>/dev/null "
            f"&& exec {self_q} --switcher-op cleanup {sw_q} || true"
        ).replace("#", "##")
        cleanup_hook = f"run-shell -b {_tmux_dquote(cleanup_sh)}"

        slot_tty = ""
        slot_w = 0
        slot_h = 0
        try:
            with with_switcher_lock(sw_sess, sock_hint=sock_path):
                init_out = tmux_out(
                    "new-session",
                    "-d",
                    "-P",
                    "-F",
                    "#{pane_id}::#{window_id}",
                    "-s",
                    sw_sess,
                    "-n",
                    "sessions",
                    "-x",
                    str(sw_cols),
                    "-y",
                    str(sw_rows),
                    *env_flags,
                    f"/bin/sh {shlex.quote(run_sh)}",
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "status", "off",
                    ";",
                    "set-option", "-w", "-t", f"={sw_sess}:sessions", "automatic-rename", "off",
                    ";",
                    "set-option", "-w", "-t", f"={sw_sess}:sessions", "allow-rename", "off",
                    ";",
                    "set-option", "-w", "-t", f"={sw_sess}:sessions", "pane-border-status", "top",
                    ";",
                    "set-option", "-w", "-t", f"={sw_sess}:sessions", "pane-border-style", f"fg={hex_map['BASE01']},bg={hex_map['BASE03']}",
                    ";",
                    "set-option", "-w", "-t", f"={sw_sess}:sessions", "pane-active-border-style", f"fg={hex_map['BASE01']},bg={hex_map['BASE03']}",
                    ";",
                    "set-option", "-w", "-t", f"={sw_sess}:sessions", "pane-border-format", border_fmt,
                    ";",
                    "split-window",
                    "-d",
                    "-h",
                    "-P",
                    "-F",
                    "#{pane_id}::#{pane_tty}::#{pane_width}::#{pane_height}",
                    "-t",
                    f"={sw_sess}:sessions",
                    "-l",
                    "56%",
                    switcher_placeholder_cmd(),
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_switcher", "1",
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_owner_pid", str(os.getpid()),
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_client", client_name,
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_origin", origin_sess or cur_sess,
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_result_file", res_file,
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_mode", "sessions",
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_visited_ai", "0",
                    ";",
                    "set-hook", "-t", f"={sw_sess}:", "client-attached", "if-shell -F '#{==:#{@ide_sw_done},1}' 'detach-client'",
                    ";",
                    "set-hook", "-t", f"={sw_sess}:", "client-detached", cleanup_hook,
                )
                init_lines = [ln.strip() for ln in init_out.splitlines() if ln.strip()]
                if len(init_lines) < 2:
                    seed_allowed = False
                    return None
                fzf_pane, sw_win = (init_lines[0].split("::", 1) + [""])[:2]
                fzf_pane = fzf_pane.strip()
                sw_win = sw_win.strip()
                slot_parts = (init_lines[1].split("::") + ["", "", "", ""])[:4]
                slot_pane = slot_parts[0].strip()
                slot_tty = slot_parts[1].strip()
                slot_w = int(slot_parts[2].strip()) if slot_parts[2].strip().isdigit() else 0
                slot_h = int(slot_parts[3].strip()) if slot_parts[3].strip().isdigit() else 0
                if not fzf_pane or not sw_win or not slot_pane:
                    seed_allowed = False
                    return None

                wire_cmds: list[str] = [
                    "set-option", "-p", "-q", "-t", fzf_pane, "@ide_sw_role", "list",
                    ";",
                    "set-option", "-p", "-q", "-t", slot_pane, "@ide_sw_placeholder", "1",
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_fzf_pane", fzf_pane,
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_slot_pane", slot_pane,
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_selected_sess", initial_top,
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_label", init_label,
                    ";",
                    "set-hook", "-w", "-t", sw_win, "pane-focus-in", focus_hook,
                    ";",
                    "set-hook", "-w", "-t", sw_win, "window-layout-changed", dead_dock_hook,
                ]
                if healed_ai and target_pane and initial_top:
                    wire_cmds.extend([
                        ";",
                        "set-option", "-q", "-t", f"={initial_top}:", "@ide_ai_pane", target_pane,
                        ";",
                        "set-environment", "-t", f"={initial_top}", "IDE_AI_PANE", target_pane,
                    ])
                run_tmux(*wire_cmds)

            init_preview_pane = target_pane or str(initial_entry.get("preview_pane") or "")
            if slot_tty and slot_w > 0 and slot_h > 0:
                write_slot_tty_viewport(
                    slot_tty=slot_tty,
                    slot_w=slot_w,
                    slot_h=slot_h,
                    preview_pane=init_preview_pane,
                    esc=esc,
                )
        finally:
            dock_decided_ev.set()

        if client_name:
            sock_part = f"-S {shlex.quote(sock_path)} " if sock_path else ""
            sw_target_q = shlex.quote(f"={sw_sess}")
            attach_sh = f"TMUX= exec tmux {sock_part}attach-session -t {sw_target_q}"
            attach_cmd = f"/bin/sh -c {shlex.quote(attach_sh)}"
            pop_res = run_tmux("display-popup", "-c", client_name, "-E", "-w", pop_w_arg, "-h", pop_h_arg, attach_cmd)
        else:
            att_cmd = ["tmux", *(["-S", sock_path] if sock_path else []), "attach-session", "-t", f"={sw_sess}"]
            pop_res = subprocess.run(att_cmd, env={**os.environ, "TMUX": ""}, check=False)

        res_tuple = read_switcher_result(res_file)
        if res_tuple is None and pop_res.returncode in (0, 130) and os.path.isfile(rc_file):
            try:
                raw_rc = open(rc_file, "r", encoding="utf-8").read().strip()
                fzf_rc = int(raw_rc) if raw_rc.lstrip("-").isdigit() else 130
                raw_fzf_out = open(out_file, "r", encoding="utf-8", errors="replace").read() if os.path.isfile(out_file) else ""
                parsed_sel = parse_fzf_session_output(fzf_rc, raw_fzf_out)
                if parsed_sel is not None:
                    pressed_k, sel_ln = parsed_sel
                    picked_s = sel_ln.split("\t", 1)[0].strip()
                    res_tuple = ("switch", picked_s, pressed_k) if picked_s else ("none", "", "")
                else:
                    res_tuple = ("none", "", "")
            except OSError:
                pass

        _cleanup_sw_state()

        if res_tuple is None:
            if pop_res.returncode in (0, 130):
                return 0
            if client_name and not sys.stdin.isatty():
                return pop_res.returncode
            return None

        action, target_val, pressed = res_tuple
        if action == "launch" and target_val:
            return launch_picked_workspace(
                target_val,
                ide_self,
                origin_sess=origin_sess or cur_sess,
                layout_mode=layout_mode,
                ai_cli=ai_cli,
                ai_cli_from_flag=ai_cli_from_flag,
                sock_path=sock_path,
            )
        if action == "switch" and target_val and session_exists(target_val):
            if pressed in ("ctrl-a", "ctrl-e", "ctrl-t"):
                from ide_lib.layout import toggle_main_pane

                if pressed == "ctrl-a":
                    toggle_main_pane("focus-ai", target_val)
                elif pressed == "ctrl-e":
                    toggle_main_pane("focus-editor", target_val)
                else:
                    toggle_main_pane("focus-term", target_val)
            if not os.environ.get("TMUX") and not os.environ.get("IDE_CLIENT"):
                t_info = tmux_out(
                    "display-message",
                    "-p",
                    "-t",
                    f"={target_val}:",
                    TMUX_SEP.join(["#{@ide_role}", "#{@ide_ai_parked}"]),
                )
                t_role, t_park = (p.strip() for p in (t_info.split(TMUX_SEP) + ["", ""])[:2])
                if t_role == "ai" and t_park != "1":
                    ack_ai_session([target_val], from_hook=False, refresh_always=True, entering_ai=True)
            rc = switch_or_attach_session(target_val, origin_sess or cur_sess, sock_path=sock_path)
            ack_ai_session([target_val], from_hook=True, refresh_always=False)
            return rc
        return 0
    finally:
        _cleanup_sw_state()
