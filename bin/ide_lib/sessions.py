"""Tabular fleet listings, live ANSI session preview, `fzf` workspace switcher, and directory launcher."""

from __future__ import annotations

import os
import re
import select
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import time

from ide_lib.constants import (
    TMUX_SEP,
    _ANSI_ESC_RE,
    _SGR_RE,
    is_live_socket,
    pad_visible,
    resolve_mise_tool_bin,
    sanitize_name_token,
    shorten_home,
    trunc_visible,
    visible_width,
)
from ide_lib.fleet import (
    _PANE_FMT_FIELDS,
    _SESSION_FMT_FIELDS,
    ack_ai_session,
    classify_ide_fleet,
    list_ide_sessions_with_server_status,
    parse_ide_session_cols,
    populate_fleet_git,
    query_fleet_snapshot,
    refresh_fleet_topbar,
)
from ide_lib.hooks import (
    collect_configured_workspace_roots,
    resolve_workspace_target,
    sanitize_session_name,
    scandir_child_dirs,
)
from ide_lib.theme import build_fzf_env, load_active_palette, state_color
from ide_lib.tmux import (
    _with_switcher_lock,
    caller_switcher_session,
    check_is_ide_session,
    cleanup_switcher_session,
    close_switcher_session,
    current_ide_session,
    dock_session_into_switcher,
    is_ide_session_meta,
    is_switcher_session_name,
    pane_exists,
    read_switcher_result,
    resolve_active_client,
    resolve_switcher_context,
    resolve_target_session,
    run_tmux,
    session_exists,
    switcher_owner_alive,
    switcher_placeholder_cmd,
    switch_or_attach_session,
    tmux_out,
    undock_switcher_session,
)

_POPUP_SESS_RE = re.compile(r"^(ai|agy)-")
_DEFAULT_PREVIEW_INTERVAL = 0.2
_ENTRY_PPID = os.getppid()
_POPUP_FORWARD_ENV_VARS = (
    "IDE_WORKSPACE_DIRS",
    "IDE_LINK_RULES",
    "IDE_FZF_BIN",
    "IDE_ZOXIDE_BIN",
    "IDE_PREVIEW_INTERVAL",
    "FZF_DEFAULT_OPTS_FILE",
    "_ZO_DATA_DIR",
    "XDG_CONFIG_HOME",
    "XDG_CACHE_HOME",
    "XDG_DATA_HOME",
)


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
        elif os.environ.get("TMUX") or os.environ.get("IDE_CLIENT"):
            run_tmux("display-message", "No IDE agents waiting for attention.")
        else:
            print("No IDE agents waiting for attention.")
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


def _format_fleet_sessions_lines(fleet: list[dict[str, object]], esc: dict[str, str]) -> list[str]:
    if not fleet:
        return []
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
    return _format_fleet_sessions_lines(fleet, esc)


class _PreviewCache:
    """Mutable VCS and dirty-buffer state cached across fast streaming preview ticks."""

    def __init__(self) -> None:
        self.workdir: str = ""
        self.git_branch: str = "-"
        self.git_dirty: bool = False
        self.git_detail: str = "-"
        self.wt_roots: dict[str, str] = {}
        self.peer_workdirs: dict[str, str] = {}
        self.last_vcs_mono: float = 0.0
        self.last_quit_mono: float = 0.0
        self.last_raw_quit_err: str = ""


def _expanded_cell_widths(text: str, tabstop: int = 8) -> list[int]:
    """Expand tabs and strip ANSI escapes, returning per-glyph display cell widths."""
    clean = _ANSI_ESC_RE.sub("", text)
    if not clean:
        return []
    ts = tabstop if tabstop > 0 else 8
    widths: list[int] = []
    logical_col = 0
    ud_mod = None
    for ch in clean:
        cp = ord(ch)
        if ch == "\t":
            step = ts - (logical_col % ts)
            widths.extend([1] * step)
            logical_col += step
        elif cp < 0x20 or (0x7F <= cp < 0xA0):
            continue
        elif 0x20 <= cp < 0x7F:
            widths.append(1)
            logical_col += 1
        elif cp == 0xFE0F:
            if widths and widths[-1] == 1:
                widths[-1] = 2
                logical_col += 1
        elif (
            0xFE00 <= cp <= 0xFE0E
            or 0xE0100 <= cp <= 0xE01EF
            or cp in (0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF)
        ):
            continue
        elif 0xE000 <= cp <= 0xF8FF or 0xF0000 <= cp <= 0x10FFFF:
            widths.append(1)
            logical_col += 1
        else:
            if ud_mod is None:
                import unicodedata as ud_mod

            if ud_mod.combining(ch) or ud_mod.category(ch) in ("Mn", "Me", "Cf"):
                continue
            cw = 2 if (cp >= 0x1F300 or ud_mod.east_asian_width(ch) in ("W", "F")) else 1
            widths.append(cw)
            logical_col += cw
    return widths


def _ansi_visible_width(text: str, tabstop: int = 8) -> int:
    """Return terminal display column width after stripping ANSI escapes and expanding tabs."""
    return sum(_expanded_cell_widths(text, tabstop=tabstop))


def _resolve_fzf_wrap_config() -> tuple[int, int]:
    """Resolve `(wrap_sign_width, tabstop)` from `FZF_DEFAULT_OPTS_FILE` and `FZF_DEFAULT_OPTS`."""
    wrap_sign = "↳ "
    preview_wrap_sign: str | None = None
    tabstop = 8
    raw_chunks: list[str] = []
    opts_file = os.environ.get("FZF_DEFAULT_OPTS_FILE", "").strip()
    if opts_file:
        try:
            with open(os.path.expanduser(opts_file), "r", encoding="utf-8", errors="replace") as fh:
                raw_chunks.append(fh.read())
        except OSError:
            pass
    opts_env = os.environ.get("FZF_DEFAULT_OPTS", "").strip()
    if opts_env:
        raw_chunks.append(opts_env)
    for chunk in raw_chunks:
        try:
            tokens = shlex.split(chunk, comments=False, posix=True)
        except ValueError:
            tokens = chunk.split()
        idx = 0
        ntok = len(tokens)
        while idx < ntok:
            tok = tokens[idx]
            if tok == "--wrap-sign" and idx + 1 < ntok:
                wrap_sign = tokens[idx + 1]
                idx += 2
                continue
            if tok.startswith("--wrap-sign="):
                wrap_sign = tok.split("=", 1)[1]
                idx += 1
                continue
            if tok == "--preview-wrap-sign" and idx + 1 < ntok:
                preview_wrap_sign = tokens[idx + 1]
                idx += 2
                continue
            if tok.startswith("--preview-wrap-sign="):
                preview_wrap_sign = tok.split("=", 1)[1]
                idx += 1
                continue
            if tok == "--tabstop" and idx + 1 < ntok:
                val_s = tokens[idx + 1]
                if val_s.isdigit() and int(val_s) > 0:
                    tabstop = int(val_s)
                idx += 2
                continue
            if tok.startswith("--tabstop="):
                val_s = tok.split("=", 1)[1]
                if val_s.isdigit() and int(val_s) > 0:
                    tabstop = int(val_s)
                idx += 1
                continue
            idx += 1
    eff_sign = preview_wrap_sign if preview_wrap_sign is not None else wrap_sign
    return (_ansi_visible_width(eff_sign, tabstop=tabstop), tabstop)


def _wrapped_preview_rows(
    text: str,
    cols: int,
    wrap_sign_w: int | None = None,
    tabstop: int | None = None,
) -> int:
    """Return visual row count of `text` inside a wrapped `fzf` preview box of width `cols`."""
    if cols <= 0:
        return 1
    if wrap_sign_w is None or tabstop is None:
        cfg_sign_w, cfg_ts = _resolve_fzf_wrap_config()
        if wrap_sign_w is None:
            wrap_sign_w = cfg_sign_w
        if tabstop is None:
            tabstop = cfg_ts
    widths = _expanded_cell_widths(text, tabstop=tabstop)
    if not widths:
        return 1
    eff_sign_w = wrap_sign_w if 0 <= wrap_sign_w < cols else 0
    rows = 1
    col = 0
    for cw in widths:
        if col + cw > cols:
            if col > 0:
                rows += 1
                col = eff_sign_w
                if col + cw > cols and col > 0:
                    col = 0
            if cw > cols:
                col = cols
                continue
        col += cw
    return rows


def _carry_sgr_prefix(lines: list[str]) -> str:
    """Return active SGR sequence remaining open at the end of `lines` (`''` when reset)."""
    fg = ""
    bg = ""
    ul_c = ""
    attrs: dict[str, str] = {}
    for line in lines:
        if "\x1b[" not in line:
            continue
        for match in _SGR_RE.finditer(line):
            body = match.group(0)[2:-1]
            if not body:
                fg = ""
                bg = ""
                ul_c = ""
                attrs.clear()
                continue
            parts = body.split(";")
            idx = 0
            nparts = len(parts)
            while idx < nparts:
                tok = parts[idx]
                if tok in ("", "0"):
                    fg = ""
                    bg = ""
                    ul_c = ""
                    attrs.clear()
                    idx += 1
                elif tok in ("38", "48", "58") and idx + 1 < nparts:
                    mode = parts[idx + 1]
                    span = 5 if (mode == "2" and idx + 4 < nparts) else (3 if (mode == "5" and idx + 2 < nparts) else 1)
                    seq = ";".join(parts[idx : idx + span])
                    if tok == "38":
                        fg = seq
                    elif tok == "48":
                        bg = seq
                    else:
                        ul_c = seq
                    idx += span
                elif tok.startswith(("38:", "48:", "58:")):
                    if tok.startswith("38:"):
                        fg = tok
                    elif tok.startswith("48:"):
                        bg = tok
                    else:
                        ul_c = tok
                    idx += 1
                elif tok in ("1", "2"):
                    attrs["weight"] = tok
                    idx += 1
                elif tok == "22":
                    attrs.pop("weight", None)
                    idx += 1
                elif tok == "3":
                    attrs["italic"] = "3"
                    idx += 1
                elif tok == "23":
                    attrs.pop("italic", None)
                    idx += 1
                elif tok == "4" or tok.startswith("4:"):
                    if tok == "4:0":
                        attrs.pop("ul", None)
                    else:
                        attrs["ul"] = tok
                    idx += 1
                elif tok == "24":
                    attrs.pop("ul", None)
                    idx += 1
                elif tok in ("5", "6"):
                    attrs["blink"] = tok
                    idx += 1
                elif tok == "25":
                    attrs.pop("blink", None)
                    idx += 1
                elif tok == "7":
                    attrs["rev"] = "7"
                    idx += 1
                elif tok == "27":
                    attrs.pop("rev", None)
                    idx += 1
                elif tok == "8":
                    attrs["hide"] = "8"
                    idx += 1
                elif tok == "28":
                    attrs.pop("hide", None)
                    idx += 1
                elif tok == "9":
                    attrs["strike"] = "9"
                    idx += 1
                elif tok == "29":
                    attrs.pop("strike", None)
                    idx += 1
                elif tok == "53":
                    attrs["over"] = "53"
                    idx += 1
                elif tok == "55":
                    attrs.pop("over", None)
                    idx += 1
                elif tok == "39":
                    fg = ""
                    idx += 1
                elif tok == "49":
                    bg = ""
                    idx += 1
                elif tok == "59":
                    ul_c = ""
                    idx += 1
                elif tok.isdigit():
                    code = int(tok)
                    if (30 <= code <= 37) or (90 <= code <= 97):
                        fg = tok
                    elif (40 <= code <= 47) or (100 <= code <= 107):
                        bg = tok
                    idx += 1
                else:
                    idx += 1
    active = [v for v in (*attrs.values(), fg, bg, ul_c) if v]
    return f"\x1b[{';'.join(active)}m" if active else ""


def _select_preview_tail(
    raw_lines: list[str],
    header_lines: list[str],
    preview_lines: int,
    preview_cols: int,
) -> list[str]:
    """Select the bottommost non-blank viewport lines fitting inside `preview_lines`."""
    cap_lines = list(raw_lines)
    while cap_lines and not _ANSI_ESC_RE.sub("", cap_lines[-1]).strip():
        cap_lines.pop()
    if not cap_lines:
        return []
    if preview_lines <= 0:
        tail = cap_lines[-35:]
        start_idx = len(cap_lines) - len(tail)
    else:
        sign_w, ts = _resolve_fzf_wrap_config()
        hdr_rows = sum(_wrapped_preview_rows(hl, preview_cols, wrap_sign_w=sign_w, tabstop=ts) for hl in header_lines)
        avail_rows = max(1, preview_lines - hdr_rows)
        picked_rev: list[str] = []
        used_rows = 0
        for raw_ln in reversed(cap_lines):
            ln_rows = _wrapped_preview_rows(raw_ln, preview_cols, wrap_sign_w=sign_w, tabstop=ts)
            if picked_rev and used_rows + ln_rows > avail_rows:
                break
            picked_rev.append(raw_ln)
            used_rows += ln_rows
            if used_rows >= avail_rows:
                break
        picked_rev.reverse()
        tail = picked_rev
        start_idx = len(cap_lines) - len(tail)
    if start_idx > 0 and tail and not tail[0].startswith(("\x1b[0m", "\x1b[m")):
        sgr_carry = _carry_sgr_prefix(cap_lines[:start_idx])
        if sgr_carry:
            tail = [sgr_carry + tail[0], *tail[1:]]
    return tail


def _resolve_preview_interval(override: float | None = None) -> float:
    """Resolve streaming refresh interval in seconds, clamped to `[0.02, 5.0]`."""
    raw_val: float | None = override
    if raw_val is None:
        env_s = os.environ.get("IDE_PREVIEW_INTERVAL", "").strip()
        if env_s:
            try:
                raw_val = float(env_s)
            except ValueError:
                raw_val = None
    val = _DEFAULT_PREVIEW_INTERVAL if (raw_val is None or raw_val <= 0) else raw_val
    return max(0.02, min(5.0, val))


def _format_session_preview_header(
    entry: dict[str, object],
    esc: dict[str, str],
    git_branch: str,
    git_dirty: bool,
    git_detail: str,
    quit_err: str,
    peers: list[str],
) -> list[str]:
    sess = str(entry["sess"])
    ai_cli = str(entry["ai_cli"])
    state = str(entry["state"])
    state_label = str(entry.get("state_label") or state)
    ai_msg = str(entry.get("ai_msg") or "")
    short_path = str(entry["short_path"])
    active_role = str(entry["active_role"])
    c_rst = esc["RESET"]
    c_state = state_color(state, esc)
    c_git = esc["YELLOW"] if git_dirty else (esc["GREEN"] if git_branch != "-" else esc["BASE01"])
    out_lines = [
        f"{esc['BLUE']} {sess}{c_rst}  {esc['BASE01']}(focused: {active_role}){c_rst}",
        f"{esc['BASE01']}Agent    :{c_rst} {esc['CYAN']}{ai_cli}{c_rst}  {esc['BASE01']}State:{c_rst} {c_state}{state_label}{c_rst}",
    ]
    if ai_msg:
        out_lines.append(f"{esc['BASE01']}Message  :{c_rst} {esc['BASE1']}{ai_msg}{c_rst}")
    out_lines.extend([
        f"{esc['BASE01']}Workspace:{c_rst} {esc['BASE0']}{short_path}{c_rst}",
        f"{esc['BASE01']}Git      :{c_rst} {c_git}{git_detail}{c_rst}",
    ])
    if quit_err:
        out_lines.append(f"{esc['BASE01']}Warning  :{c_rst} {esc['ORANGE']}{quit_err}{c_rst}")
    if peers:
        out_lines.append(f"{esc['BASE01']}Warning  :{c_rst} {esc['YELLOW']}Shared worktree with {', '.join(peers)}{c_rst}")
    return out_lines


def _build_session_preview_frame(
    sess: str,
    cache: _PreviewCache | None = None,
    vcs_interval: float = 1.6,
    header_only: bool = False,
) -> tuple[str, bool]:
    """Render a single ANSI preview frame `(frame_text, should_terminate)` for `sess`."""
    raw_sessions, pane_rows, server_up = query_fleet_snapshot()
    if not server_up:
        return ("Session is no longer active.", True)
    sess_raw = next((r for r in raw_sessions if r["sess"] == sess), None)
    if sess_raw is None:
        if not any(r and r[0] == sess for r in pane_rows) and not session_exists(sess):
            return ("Session is no longer active.", True)
        _, esc_non_ide = load_active_palette()
        return (f"{esc_non_ide['BLUE']}{sess}{esc_non_ide['RESET']}", True)

    now_mono = time.monotonic()
    raw_wd_hint = sess_raw.get("workdir", "")
    need_vcs = (
        cache is None
        or cache.last_vcs_mono <= 0.0
        or (now_mono - cache.last_vcs_mono) >= vcs_interval
        or (bool(raw_wd_hint) and raw_wd_hint != cache.workdir)
    )
    fleet = classify_ide_fleet(
        include_git=need_vcs,
        cur_sess="",
        git_only_sess=sess,
        raw_sessions=raw_sessions,
        panes_rows=pane_rows,
    )
    entry = next((e for e in fleet if str(e["sess"]) == sess), None)
    _, esc = load_active_palette()
    c_rst = esc["RESET"]
    if entry is None:
        return (f"{esc['BLUE']}{sess}{c_rst}", True)

    if cache is None:
        git_branch = str(entry["git_branch"])
        git_dirty = bool(entry["git_dirty"])
        git_detail = str(entry["git_detail"])
        peers = [str(p) for p in (entry.get("worktree_peers") or [])]
    elif need_vcs:
        cache.workdir = str(entry["workdir"])
        cache.git_branch = str(entry["git_branch"])
        cache.git_dirty = bool(entry["git_dirty"])
        cache.git_detail = str(entry["git_detail"])
        cache.wt_roots = {str(e["sess"]): str(e.get("worktree_root") or "") for e in fleet}
        cache.peer_workdirs = {str(e["sess"]): str(e.get("workdir") or "") for e in fleet}
        cache.last_vcs_mono = now_mono
        git_branch = cache.git_branch
        git_dirty = cache.git_dirty
        git_detail = cache.git_detail
        peers = [str(p) for p in (entry.get("worktree_peers") or [])]
    else:
        cur_wd = str(entry["workdir"])
        if cur_wd != cache.workdir:
            from ide_lib.git_info import git_summary

            gb, gd, gdet, _, wt_raw = git_summary(cur_wd)
            cache.workdir = cur_wd
            cache.git_branch = gb
            cache.git_dirty = gd
            cache.git_detail = gdet
            cache.wt_roots[sess] = os.path.realpath(wt_raw) if wt_raw else ""
            cache.peer_workdirs[sess] = cur_wd
            cache.last_vcs_mono = now_mono
        git_branch = cache.git_branch
        git_dirty = cache.git_dirty
        git_detail = cache.git_detail
        my_wt = cache.wt_roots.get(sess, "")
        peers = []
        if my_wt:
            for peer_e in fleet:
                psess = str(peer_e["sess"])
                p_wd = str(peer_e.get("workdir") or "")
                if psess not in cache.wt_roots or cache.peer_workdirs.get(psess) != p_wd:
                    from ide_lib.git_info import locate_git_dirs

                    p_wt_raw, _, _ = locate_git_dirs(p_wd)
                    cache.wt_roots[psess] = os.path.realpath(p_wt_raw) if p_wt_raw else ""
                    cache.peer_workdirs[psess] = p_wd
            same_wt = [e for e in fleet if cache.wt_roots.get(str(e["sess"]), "") == my_wt]
            if len(same_wt) >= 2 and any(str(p["state"]) == "WORKING" for p in same_wt):
                peers = [str(p["sess"]) for p in same_wt if str(p["sess"]) != sess]

    quit_err = str(entry.get("quit_err") or "")
    ide_sock = str(entry.get("ide_sock") or "")
    if quit_err:
        should_check_quit = (
            cache is None
            or quit_err != cache.last_raw_quit_err
            or (now_mono - cache.last_quit_mono) >= vcs_interval
        )
        if should_check_quit:
            if cache is not None:
                cache.last_raw_quit_err = quit_err
                cache.last_quit_mono = now_mono
            from ide_lib.nvim_rpc import ensure_session_editor_socket, nvim_modified_buf_count, resolve_nvim_bin

            if resolve_nvim_bin():
                ide_sock = ensure_session_editor_socket(sess, ide_sock)
                if ide_sock and is_live_socket(ide_sock) and nvim_modified_buf_count(ide_sock) == 0:
                    run_tmux("set-option", "-q", "-u", "-t", f"={sess}:", "@ide_quit_err")
                    quit_err = ""
                    if cache is not None:
                        cache.last_raw_quit_err = ""
    elif cache is not None:
        cache.last_raw_quit_err = ""

    raw_cols = os.environ.get("FZF_PREVIEW_COLUMNS", "").strip()
    raw_lines = os.environ.get("FZF_PREVIEW_LINES", "").strip()
    preview_cols = int(raw_cols) if raw_cols.isdigit() and int(raw_cols) > 0 else 0
    preview_lines = int(raw_lines) if raw_lines.isdigit() and int(raw_lines) > 0 else 0

    preview_pane = str(entry["preview_pane"])
    rule_w = min(56, preview_cols) if preview_cols > 0 else 56
    rule = "─" * rule_w
    out_lines = _format_session_preview_header(
        entry, esc, git_branch, git_dirty, git_detail, quit_err, peers
    )
    if header_only:
        return ("\n".join(out_lines), False)
    out_lines.append(f"{esc['BASE01']}{rule}{c_rst}")

    cap_start = f"-{max(40, preview_lines + 20)}" if preview_lines > 0 else "-40"
    cap_res = run_tmux("capture-pane", "-e", "-p", "-S", cap_start, "-t", preview_pane) if preview_pane else None
    if cap_res is not None and cap_res.returncode == 0:
        raw_cap = cap_res.stdout if isinstance(cap_res.stdout, str) else ""
        cap_raw_lines = [ln.rstrip("\r") for ln in raw_cap.rstrip("\n").split("\n")] if raw_cap else []
        tail = _select_preview_tail(cap_raw_lines, out_lines, preview_lines, preview_cols)
        if tail:
            out_lines.append("\n".join(tail) + c_rst)
        else:
            out_lines.append(f"{esc['BASE01']}(Viewport is empty){c_rst}")
    else:
        out_lines.append(f"{esc['BASE01']}(No active pane in session){c_rst}")
    return ("\n".join(out_lines), False)


def _silence_broken_stdout() -> None:
    """Redirect broken stdout descriptor to `/dev/null` so interpreter shutdown stays silent."""
    try:
        devnull_fd = os.open(os.devnull, os.O_WRONLY)
        try:
            os.dup2(devnull_fd, sys.stdout.fileno())
        finally:
            os.close(devnull_fd)
    except (OSError, ValueError):
        pass


def _write_stdout_frame(payload: str, out_fd: int | None) -> None:
    """Write `payload` atomically to `out_fd` when available, falling back to `sys.stdout`."""
    if out_fd is None:
        sys.stdout.write(payload)
        sys.stdout.flush()
        return
    data = payload.encode("utf-8", errors="replace")
    view = memoryview(data)
    sent = 0
    total = len(data)
    while sent < total:
        written = os.write(out_fd, view[sent:])
        if written <= 0:
            break
        sent += written


def render_session_preview(
    target_arg: str,
    follow: bool = False,
    interval: float | None = None,
    max_frames: int = 0,
) -> int:
    """Render ANSI metadata and viewport preview for `target_arg` (one-shot or streaming `--follow`)."""
    sw_sess = os.environ.get("IDE_SWITCHER_SESSION", "").strip()
    seeded_path = os.environ.pop("IDE_PREVIEW_SEEDED", "").strip()
    has_sw_name = bool(sw_sess and is_switcher_session_name(sw_sess))
    sess = target_arg.strip()
    if not sess:
        if has_sw_name and session_exists(sw_sess):
            undock_switcher_session(sw_sess)
        print("Session is no longer active.")
        return 0
    in_switcher = has_sw_name
    out_fd: int | None = None
    try:
        sys.stdout.flush()
        out_fd = sys.stdout.fileno()
    except (OSError, ValueError, AttributeError):
        out_fd = None
    if not follow:
        if in_switcher:
            in_switcher = session_exists(sw_sess)
            if in_switcher:
                dock_session_into_switcher(sw_sess, sess)
        frame, _ = _build_session_preview_frame(sess, header_only=in_switcher)
        try:
            _write_stdout_frame(frame + "\n", out_fd)
        except BrokenPipeError:
            _silence_broken_stdout()
        except OSError:
            pass
        return 0

    seeded_frame: str | None = None
    step_s = _resolve_preview_interval(interval)
    vcs_interval = min(2.0, max(0.25, step_s * 8.0))
    cache = _PreviewCache()
    if seeded_path:
        try:
            with open(seeded_path, "r", encoding="utf-8", errors="replace") as sfh:
                seeded_frame = sfh.read().rstrip("\r\n")
        except OSError:
            seeded_frame = None
        try:
            os.unlink(seeded_path)
        except OSError:
            pass
        seed_base = seeded_path[:-2] if seeded_path.endswith(".1") else seeded_path
        meta_path = f"{seed_base}.meta.json"
        if os.path.isfile(meta_path):
            import json

            try:
                with open(meta_path, "r", encoding="utf-8") as mfh:
                    mdata = json.loads(mfh.read())
                if isinstance(mdata, dict) and seeded_frame is not None:
                    cache.workdir = str(mdata.get("workdir") or "")
                    cache.git_branch = str(mdata.get("git_branch") or "-")
                    cache.git_dirty = bool(mdata.get("git_dirty"))
                    cache.git_detail = str(mdata.get("git_detail") or "-")
                    raw_wts = mdata.get("wt_roots")
                    if isinstance(raw_wts, dict):
                        cache.wt_roots = {str(k): str(v) for k, v in raw_wts.items()}
                    raw_pwds = mdata.get("peer_workdirs")
                    if isinstance(raw_pwds, dict):
                        cache.peer_workdirs = {str(k): str(v) for k, v in raw_pwds.items()}
                    cache.last_vcs_mono = time.monotonic()
            except (OSError, ValueError):
                pass
            try:
                os.unlink(meta_path)
            except OSError:
                pass
    initial_ppid = _ENTRY_PPID if _ENTRY_PPID > 1 else os.getppid()
    stop_requested = False

    def _on_stop_sig(_signum: int, _frame: object) -> None:
        nonlocal stop_requested
        stop_requested = True

    saved_sigs: list[tuple[int, object]] = []
    for sig_name in ("SIGTERM", "SIGINT", "SIGHUP"):
        sig = getattr(signal, sig_name, None)
        if sig is not None:
            try:
                saved_sigs.append((sig, signal.signal(sig, _on_stop_sig)))
            except (OSError, ValueError):
                pass

    poller = None
    kqueue_obj = None
    pipe_already_closed = False
    if out_fd is not None:
        try:
            st_mode = os.fstat(out_fd).st_mode
            if stat.S_ISFIFO(st_mode) or stat.S_ISSOCK(st_mode):
                if hasattr(select, "kqueue"):
                    kq = select.kqueue()
                    kev = select.kevent(
                        out_fd,
                        filter=select.KQ_FILTER_WRITE,
                        flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                    )
                    init_evs = kq.control([kev], 1, 0)
                    if any(ev.flags & (select.KQ_EV_EOF | select.KQ_EV_ERROR) for ev in init_evs):
                        pipe_already_closed = True
                        kq.close()
                    else:
                        kqueue_obj = kq
                elif hasattr(select, "poll"):
                    p = select.poll()
                    p.register(out_fd, select.POLLERR | select.POLLHUP)
                    poller = p
        except (OSError, ValueError):
            poller = None
            if kqueue_obj is not None:
                try:
                    kqueue_obj.close()
                except OSError:
                    pass
                kqueue_obj = None

    def _preview_cancelled() -> bool:
        if stop_requested or pipe_already_closed:
            return True
        if initial_ppid > 1 and os.getppid() != initial_ppid:
            return True
        try:
            if kqueue_obj is not None:
                evs = kqueue_obj.control(None, 1, 0)
                if any(ev.flags & (select.KQ_EV_EOF | select.KQ_EV_ERROR) for ev in evs):
                    return True
            elif poller is not None and poller.poll(0):
                return True
        except OSError:
            return True
        return False

    if in_switcher and seeded_frame is None and not _preview_cancelled():
        if not dock_session_into_switcher(sw_sess, sess, cancel_check=_preview_cancelled):
            in_switcher = session_exists(sw_sess)

    clear_seq = "\x1b[H\x1b[2J" if sys.stdout.isatty() else "\x1b[2J"
    last_frame: str | None = seeded_frame
    emitted = 1 if seeded_frame is not None else 0
    skip_first_build = seeded_frame is not None
    try:
        while not stop_requested and not pipe_already_closed:
            if initial_ppid > 1 and os.getppid() != initial_ppid:
                break
            if skip_first_build:
                skip_first_build = False
                should_stop = False
            else:
                frame, should_stop = _build_session_preview_frame(
                    sess,
                    cache=cache,
                    vcs_interval=vcs_interval,
                    header_only=in_switcher,
                )
                if last_frame is None:
                    _write_stdout_frame(frame + "\n", out_fd)
                    last_frame = frame
                    emitted += 1
                elif frame != last_frame:
                    _write_stdout_frame(clear_seq + frame + "\n", out_fd)
                    last_frame = frame
                    emitted += 1
            if should_stop or stop_requested or (max_frames > 0 and emitted >= max_frames):
                break
            deadline = time.monotonic() + step_s
            pipe_closed = False
            while not stop_requested:
                rem = deadline - time.monotonic()
                if rem <= 0:
                    break
                if initial_ppid > 1 and os.getppid() != initial_ppid:
                    pipe_closed = True
                    break
                slice_s = min(0.05, rem)
                if kqueue_obj is not None:
                    t_kq = time.monotonic()
                    try:
                        evs = kqueue_obj.control(None, 1, slice_s)
                    except OSError:
                        pipe_closed = True
                        break
                    if any(ev.flags & (select.KQ_EV_EOF | select.KQ_EV_ERROR) for ev in evs):
                        pipe_closed = True
                        break
                    rem_slice = slice_s - (time.monotonic() - t_kq)
                    if rem_slice > 0.002 and not stop_requested:
                        time.sleep(rem_slice)
                elif poller is not None:
                    try:
                        if poller.poll(max(1, int(slice_s * 1000))):
                            pipe_closed = True
                            break
                    except OSError:
                        pipe_closed = True
                        break
                else:
                    time.sleep(slice_s)
            if pipe_closed:
                break
    except BrokenPipeError:
        _silence_broken_stdout()
    except (OSError, KeyboardInterrupt):
        pass
    finally:
        if kqueue_obj is not None:
            try:
                kqueue_obj.close()
            except OSError:
                pass
        for sig, prev_h in saved_sigs:
            try:
                signal.signal(sig, prev_h)
            except (OSError, ValueError):
                pass
    return 0


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


def _launch_picked_workspace(
    chosen_dir: str,
    ide_self: str,
    origin_sess: str = "",
    layout_mode: str = "",
    ai_cli: str = "",
    ai_cli_from_flag: bool = False,
    detach_only: bool = False,
    sock_path: str = "",
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
    client_name_hint: str | None = None,
) -> int | None:
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
    fzf_bin = resolve_mise_tool_bin("fzf", env_override="IDE_FZF_BIN")

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


_FZF_RESIZE_CAP_CACHE: dict[str, bool] = {}


def _fzf_supports_resize_bind(fzf_bin: str, version_text: str | None = None) -> bool:
    """Return True when `fzf` is `>= 0.46.0` (supporting `--bind=resize:refresh-preview`)."""
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
                cache_key = f"{real_p}\t{st.st_mtime_ns}\t{st.st_size}\t"
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
        if norm_op == "zero":
            undock_switcher_session(sw_sess)
        rem_ide, server_up = list_ide_sessions_with_server_status()
        if server_up and not rem_ide:
            _, sw_cl, sw_rf = resolve_switcher_context(sw_sess)
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
            TMUX_SEP.join(["#{@ide_sw_docked_pane}", "#{@ide_sw_slot_pane}", "#{@ide_sw_mode}"]),
        )
        if raw_ai and TMUX_SEP in raw_ai:
            dp, sp, sw_m = (p.strip() for p in (raw_ai.split(TMUX_SEP) + ["", "", ""])[:3])
            if sw_m != "new":
                target_p = dp if pane_exists(dp) else sp
                if target_p and pane_exists(target_p):
                    run_tmux("select-pane", "-t", target_p)
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
                "#{@ide_sw_visited_ai}",
                "#{@ide_sw_mode}",
            ]),
        )
        if not raw_foc or TMUX_SEP not in raw_foc:
            return 0
        act_p, fzf_p, docked_p, docked_s, visited_ai, sw_mode = (
            p.strip() for p in (raw_foc.split(TMUX_SEP) + [""] * 6)[:6]
        )
        if docked_p and act_p == docked_p and docked_s:
            run_tmux("set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_visited_ai", "1")
            ack_ai_session([docked_s], from_hook=True, refresh_always=True, entering_ai=True)
        elif fzf_p and act_p == fzf_p and visited_ai == "1" and sw_mode == "sessions":
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


def _build_sessions_fzf_args(
    fzf_bin: str,
    ide_self: str,
    cur_sess: str,
    hex_map: dict[str, str],
    supports_modern_binds: bool,
    sw_sess: str = "",
    pane_h: int = 32,
    seed_sess: str = "",
    seed_file: str = "",
) -> list[str]:
    self_q = shlex.quote(ide_self)
    reload_cmd = f"{self_q} --sessions-lines" + (f" {shlex.quote(cur_sess)}" if cur_sess else "")
    quit_bind = f"ctrl-x:execute-silent({self_q} --quit {{+1}})+reload({reload_cmd})"
    ctrl_r_bind = f"ctrl-r:reload({reload_cmd})"
    ack_bind = f"ctrl-y:execute-silent({self_q} --ack-ai {{+1}})+reload({reload_cmd})"
    open_pr_bind = f"ctrl-o:execute-silent({self_q} --open-pr {{1}})"
    if seed_sess and seed_file:
        seed_sess_q = shlex.quote(seed_sess)
        seed_q = shlex.quote(seed_file)
        seed_used_q = shlex.quote(f"{seed_file}.1")
        seed_meta_q = shlex.quote(f"{seed_file}.meta.json")
        preview_cmd = (
            f"if [ {seed_sess_q} = {{1}} ] && mv -f {seed_q} {seed_used_q} 2>/dev/null; then "
            f"cat {seed_used_q}; IDE_PREVIEW_SEEDED={seed_used_q} exec {self_q} --session-preview --follow -- {{1}}; "
            f"fi; rm -f {seed_q} {seed_used_q} {seed_meta_q} 2>/dev/null || :; "
            f"exec {self_q} --session-preview --follow -- {{1}}"
        )
    else:
        preview_cmd = f"{self_q} --session-preview --follow -- {{1}}"

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
        resize_binds: list[str] = []
    else:
        preview_window_spec = "right:56%:wrap:noinfo"
        resize_binds = ["--bind=resize:refresh-preview"] if supports_modern_binds else []

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
        "--border-label= Enter: switch · C-a/e/t: pane · C-y: ack · C-o: PR · M-n: new · C-x: quit · C-r: reload · Alt+s: close ",
        "--border-label-pos=bottom",
        f"--color=label:{hex_map['BASE01']}",
        "--expect=ctrl-a,ctrl-e,ctrl-t,alt-n",
        "--bind=alt-s:abort",
        *resize_binds,
        *switcher_extra_binds,
        f"--bind={ctrl_r_bind}",
        f"--bind={ack_bind}",
        f"--bind={open_pr_bind}",
        f"--bind={quit_bind}",
        f"--preview={preview_cmd}",
        f"--preview-window={preview_window_spec}",
    ]


def _parse_fzf_session_output(returncode: int, raw_out: str) -> tuple[str, str] | None:
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


class _OuterSwitcherSnapshot:
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


def _query_outer_switcher_snapshot(target_arg: str) -> _OuterSwitcherSnapshot:
    """Collect client, session, and pane topology for `Alt+s` in a single tmux IPC round-trip."""
    snap = _OuterSwitcherSnapshot()
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
            sc = (line.split(TMUX_SEP)[1:] + [""] * 27)[:27]
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
            sw_docked = sc[26].strip()
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


def _run_interactive_switcher_session(
    origin_sess: str,
    cur_sess: str,
    ide_self: str,
    fzf_bin: str,
    forward_ai_cli: bool,
    snap: _OuterSwitcherSnapshot,
    client_name: str = "",
) -> int | None:
    """Spawn a 2-pane switcher (`fzf` list on left, live interactive AI pane on right) and attach."""
    import errno
    import json
    import tempfile
    import threading

    _ensure_switcher_tmux_conf(already_loaded=snap.tmux_conf_loaded)
    hex_map, esc = load_active_palette()
    fzf_env = build_fzf_env(hex_map)
    supports_modern_binds = _fzf_supports_resize_bind(fzf_bin)

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
        sw_cols = max(80, term_sz.columns)
        sw_rows = max(20, term_sz.lines)

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
    was_zoomed = False
    zoomed_pane = ""
    init_label = ""
    if init_meta is not None:
        rec_ai = init_meta["ai_pane"]
        rec_dock_sw = (
            rec_ai in snap.pane_dock_map and is_switcher_session_name(snap.pane_dock_map[rec_ai][0])
            if rec_ai
            else False
        )
        if not rec_dock_sw:
            if (
                rec_ai
                and rec_ai in snap.pane_dock_map
                and snap.pane_dock_map[rec_ai][0] == initial_top
                and snap.pane_dock_map[rec_ai][6] != "1"
            ):
                target_pane = rec_ai
            else:
                for cand_pid, cand_role, cand_ph in snap.sess_panes.get(initial_top, ()):
                    if cand_role == "ai" and cand_ph != "1":
                        target_pane = cand_pid
                        healed_ai = True
                        break
                if not target_pane:
                    for cand_pid, cand_role, cand_ph in snap.sess_panes.get(initial_top, ()):
                        if cand_role not in ("editor", "term") and cand_ph != "1":
                            target_pane = cand_pid
                            break
        if target_pane and target_pane in snap.pane_dock_map:
            p_sess, p_win, _, p_zoom, _, docked_by, _ = snap.pane_dock_map[target_pane]
            if p_sess != initial_top or (
                docked_by and docked_by != sw_sess and docked_by in snap.all_sessions
            ):
                target_pane = ""
            else:
                was_zoomed = p_zoom == "1"
                zoomed_pane = snap.win_active_pane.get(p_win, target_pane) if was_zoomed else ""
                ai_cli = init_meta["ai_cli"] or "AI"
                init_label = f"{initial_top} · {ai_cli}"

    seeded_sess = initial_top if (target_pane and not initial_entry.get("quit_err")) else ""

    fzf_args = _build_sessions_fzf_args(
        fzf_bin=fzf_bin,
        ide_self=ide_self,
        cur_sess=cur_sess,
        hex_map=hex_map,
        supports_modern_binds=supports_modern_binds,
        sw_sess=sw_sess,
        pane_h=max(1, sw_rows - 1),
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
    alt_n_cmd = f"{self_q} --sessions" + (f" {shlex.quote(cur_sess)}" if cur_sess else "")
    fzf_cmd_str = " ".join(shlex.quote(a) for a in fzf_args)
    fzf_def_opts_q = shlex.quote(fzf_env.get("FZF_DEFAULT_OPTS", ""))
    in_q = shlex.quote(in_file)
    out_q = shlex.quote(out_file)
    rc_q = shlex.quote(rc_file)
    seed_rm_q = (
        f"{shlex.quote(seed_file)} {shlex.quote(seed_file + '.1')} {shlex.quote(seed_meta_file)}"
    )

    border_fmt = (
        f"#{{?#{{==:#{{@ide_sw_role}},list}},"
        f"#{{?#{{==:#{{@ide_sw_mode}},new}},"
        f"#[fg={hex_map['BLUE']}#,nobold]▸  #[fg={hex_map['BASE1']}#,nobold]New Workspace #[fg={hex_map['BASE01']}#,nobold](Enter: launch · Esc: back) ,"
        f"#{{?pane_active,#[fg={hex_map['BLUE']}#,nobold]▸  #[fg={hex_map['BASE1']}#,nobold]Sessions #[fg={hex_map['BASE01']}#,nobold](Alt+l: interact) ,"
        f"#[fg={hex_map['BASE01']}#,nobold]   Sessions (Alt+h: list) }}}},"
        f"#{{?pane_active,#[fg={hex_map['CYAN']}#,nobold]▸ 󰚩 #[fg={hex_map['BASE1']}#,nobold]#{{?#{{!=:#{{@ide_sw_label}},}},#{{@ide_sw_label}},AI}} #[fg={hex_map['BASE01']}#,nobold](live · Alt+h: list · Alt+s: close) ,"
        f"#[fg={hex_map['BASE0']}#,nobold]  󰚩 #{{?#{{!=:#{{@ide_sw_label}},}},#{{@ide_sw_label}},(no session)}} #[fg={hex_map['BASE01']}#,nobold](Alt+l / click: interact) }}}}"
    )

    cancel_ev = threading.Event()
    feeder_thr: threading.Thread | None = None
    cleaned = False

    def _write_seed_artifacts() -> None:
        if not seeded_sess:
            return
        seed_lines = _format_session_preview_header(
            initial_entry,
            esc,
            str(initial_entry["git_branch"]),
            bool(initial_entry["git_dirty"]),
            str(initial_entry["git_detail"]),
            "",
            [str(p) for p in (initial_entry.get("worktree_peers") or [])],
        )
        meta_payload = json.dumps({
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
        populate_fleet_git(fleet)
        if cancel_ev.is_set():
            return
        _write_seed_artifacts()
        rows_list = _format_fleet_sessions_lines(fleet, esc)
        payload = ("\n".join(rows_list) + "\n").encode("utf-8") if rows_list else b""
        deadline = time.monotonic() + 5.0
        wfd = -1
        while not cancel_ev.is_set() and time.monotonic() < deadline:
            try:
                wfd = os.open(in_file, os.O_WRONLY | os.O_NONBLOCK)
                break
            except OSError as exc:
                if exc.errno == errno.ENXIO:
                    time.sleep(0.004)
                    continue
                return
        if wfd < 0:
            return
        try:
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
            initial_rows = _format_fleet_sessions_lines(fleet, esc)
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
                "exec sleep 0.5\n"
            )
            os.write(sh_fd, script_body.encode("utf-8"))
        finally:
            os.close(sh_fd)

        focus_cond = "#{||:#{==:#{pane_id},#{@ide_sw_docked_pane}},#{==:#{@ide_sw_visited_ai},1}}"
        focus_sh = f"{self_q} --switcher-op focus {sw_q} || true".replace("#", "##")
        focus_run = f"run-shell -b {_tmux_dquote(focus_sh)}"
        focus_hook = f"if-shell -F {_tmux_dquote(focus_cond)} {_tmux_dquote(focus_run)}"
        cleanup_sh = (
            f"sleep 0.15; tmux has-session -t {shlex.quote('=' + sw_sess)} 2>/dev/null "
            f"&& exec {self_q} --switcher-op cleanup {sw_q} || true"
        ).replace("#", "##")
        cleanup_hook = f"run-shell -b {_tmux_dquote(cleanup_sh)}"

        fallback_dock_needed = False
        with _with_switcher_lock(sw_sess):
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
                "split-window",
                "-d",
                "-h",
                "-P",
                "-F",
                "#{pane_id}",
                "-t",
                f"={sw_sess}:sessions",
                "-l",
                "56%",
                switcher_placeholder_cmd(),
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
                return None
            fzf_pane, sw_win = (init_lines[0].split("::", 1) + [""])[:2]
            fzf_pane = fzf_pane.strip()
            sw_win = sw_win.strip()
            slot_pane = init_lines[1].strip()
            if not fzf_pane or not sw_win or not slot_pane:
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
                "set-hook", "-w", "-t", sw_win, "pane-focus-in", focus_hook,
            ]
            if target_pane:
                if healed_ai:
                    wire_cmds.extend([
                        ";",
                        "set-option", "-q", "-t", f"={initial_top}:", "@ide_ai_pane", target_pane,
                        ";",
                        "set-environment", "-t", f"={initial_top}", "IDE_AI_PANE", target_pane,
                    ])
                wire_cmds.extend([
                    ";",
                    "set-option", "-p", "-q", "-t", target_pane, "@ide_owner_sess", initial_top,
                    ";",
                    "set-option", "-p", "-q", "-t", target_pane, "@ide_sw_docked_by", sw_sess,
                    ";",
                    "swap-pane", "-d", "-s", slot_pane, "-t", target_pane,
                    ";",
                    "set-option", "-q", "-t", f"={initial_top}:", "@ide_docked_in", sw_sess,
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_docked_pane", target_pane,
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_docked_sess", initial_top,
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_was_zoomed", "1" if was_zoomed else "0",
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_zoomed_pane", zoomed_pane,
                    ";",
                    "set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_label", init_label,
                ])
            wire_res = run_tmux(*wire_cmds)
            if wire_res.returncode != 0 and initial_top:
                fallback_dock_needed = True

        if fallback_dock_needed:
            dock_session_into_switcher(sw_sess, initial_top)

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
                parsed_sel = _parse_fzf_session_output(fzf_rc, raw_fzf_out)
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
            return _launch_picked_workspace(
                target_val, ide_self, origin_sess=origin_sess or cur_sess, sock_path=sock_path
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


def run_sessions_picker(target_arg: str, ide_self: str, had_env_ai_cli: bool = False) -> int:
    """Open interactive `fzf` multi-session workspace switcher (`ide -s` / `ide --sessions`)."""
    fzf_bin = resolve_mise_tool_bin("fzf", env_override="IDE_FZF_BIN")
    sw_sess = os.environ.get("IDE_SWITCHER_SESSION", "").strip()
    sw_res_file = os.environ.get("IDE_SWITCHER_RESULT", "").strip()
    in_switcher = bool(sw_sess and is_switcher_session_name(sw_sess))
    start_alt_n = os.environ.pop("IDE_SW_START_ALT_N", "") == "1"

    outer_snap: _OuterSwitcherSnapshot | None = None
    if not in_switcher and os.environ.get("IDE_IN_POPUP") != "1" and os.environ.get("IDE_NO_POPUP") != "1":
        outer_snap = _query_outer_switcher_snapshot(target_arg)
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
                    sw_rc = _run_interactive_switcher_session(
                        origin_sess=origin_sess,
                        cur_sess=cur_sess,
                        ide_self=ide_self,
                        fzf_bin=fzf_bin,
                        forward_ai_cli=had_env_ai_cli,
                        snap=outer_snap,
                        client_name=client_name,
                    )
                    if sw_rc is not None:
                        return sw_rc
                else:
                    inner_args = [shlex.quote(ide_self), "--sessions"]
                    if cur_sess:
                        inner_args.append(shlex.quote(cur_sess))
                    popup_rc = _maybe_reenter_in_tmux_popup(
                        origin_sess,
                        cur_sess,
                        fzf_bin,
                        forward_ai_cli=had_env_ai_cli,
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
            sw_ext_rc = _run_interactive_switcher_session(
                origin_sess=origin_sess,
                cur_sess=cur_sess,
                ide_self=ide_self,
                fzf_bin=fzf_bin,
                forward_ai_cli=had_env_ai_cli,
                snap=outer_snap,
                client_name="",
            )
            if sw_ext_rc is not None:
                return sw_ext_rc
    else:
        resolved_arg = resolve_target_session(target_arg) if target_arg else ""
        origin_sess = resolved_arg if (resolved_arg and session_exists(resolved_arg)) else ""
        cur_sess = origin_sess if (origin_sess and check_is_ide_session(origin_sess)) else current_ide_session()

    if not fzf_bin:
        has_sessions = bool(outer_snap.raw_ide_sessions) if outer_snap is not None else bool(build_sessions_lines(cur_sess))
        if not has_sessions:
            if os.environ.get("TMUX"):
                run_tmux("display-message", "No active IDE sessions.")
            else:
                print("No active IDE sessions.")
            return 0
        return list_ide_fleet(plain=False)

    hex_map, _ = load_active_palette()
    env = build_fzf_env(hex_map)
    is_interactive = (sys.stdin.isatty() and sys.stdout.isatty()) or os.environ.get("IDE_IN_POPUP") == "1"

    if start_alt_n and in_switcher:
        undock_switcher_session(sw_sess)
        run_tmux("set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_mode", "new")
        if tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{window_zoomed_flag}") == "0":
            run_tmux("resize-pane", "-Z", "-t", f"={sw_sess}:")
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
                if os.environ.get("TMUX"):
                    run_tmux("display-message", "No active IDE sessions.")
                else:
                    print("No active IDE sessions.")
                return 0
            if in_switcher:
                undock_switcher_session(sw_sess)
                run_tmux("set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_mode", "new")
                if tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{window_zoomed_flag}") == "0":
                    run_tmux("resize-pane", "-Z", "-t", f"={sw_sess}:")
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
            return _launch_picked_workspace(chosen_dir, ide_self, origin_sess=origin_sess or cur_sess)
        first_iter = True

    supports_modern_binds = _fzf_supports_resize_bind(fzf_bin)
    pane_h = 32
    if in_switcher:
        pane_h_s = tmux_out(
            "display-message",
            "-p",
            "-t",
            os.environ.get("TMUX_PANE", f"={sw_sess}:"),
            "#{pane_height}",
        ).strip()
        pane_h = int(pane_h_s) if pane_h_s.isdigit() and int(pane_h_s) > 0 else 32
    fzf_args = _build_sessions_fzf_args(
        fzf_bin=fzf_bin,
        ide_self=ide_self,
        cur_sess=cur_sess,
        hex_map=hex_map,
        supports_modern_binds=supports_modern_binds,
        sw_sess=sw_sess if in_switcher else "",
        pane_h=pane_h,
    )

    while True:
        was_first = first_iter
        rows = initial_rows if first_iter else build_sessions_lines(cur_sess)
        first_iter = False
        if not rows:
            if in_switcher:
                close_switcher_session(sw_sess, action="none", res_file_hint=sw_res_file)
            if os.environ.get("TMUX"):
                run_tmux("display-message", "No active IDE sessions.")
            else:
                print("No active IDE sessions.")
            return 0

        if in_switcher and not was_first:
            run_tmux("set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_mode", "sessions")
            if tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{window_zoomed_flag}") == "1":
                run_tmux("resize-pane", "-Z", "-t", f"={sw_sess}:")
            if rows:
                dock_session_into_switcher(sw_sess, rows[0].split("\t", 1)[0].strip())

        proc = subprocess.run(
            fzf_args,
            input="\n".join(rows) + "\n",
            stdout=subprocess.PIPE,
            text=True,
            env=env,
            check=False,
        )
        parsed = _parse_fzf_session_output(proc.returncode, proc.stdout or "")
        if parsed is None:
            if in_switcher:
                close_switcher_session(sw_sess, action="none", res_file_hint=sw_res_file)
            return 0
        pressed, selected_line = parsed

        if pressed == "alt-n":
            if in_switcher:
                undock_switcher_session(sw_sess)
                run_tmux("set-option", "-q", "-t", f"={sw_sess}:", "@ide_sw_mode", "new")
                if tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{window_zoomed_flag}") == "0":
                    run_tmux("resize-pane", "-Z", "-t", f"={sw_sess}:")
            chosen_dir = _pick_workspace_directory(fzf_bin, env, back_to_sessions=True)
            if not chosen_dir:
                continue
            if in_switcher:
                close_switcher_session(
                    sw_sess, action="launch", target=chosen_dir, pressed="alt-n", res_file_hint=sw_res_file
                )
                return 0
            return _launch_picked_workspace(chosen_dir, ide_self, origin_sess=origin_sess or cur_sess)

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
