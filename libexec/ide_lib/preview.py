"""Live ANSI session preview renderer, `fzf` wrap-width model, and `--follow` streamer."""

from __future__ import annotations

import errno
import os
import select
import shlex
import signal
import stat
import sys
import time

from ide_lib.constants import (
    _ANSI_ESC_RE,
    _SGR_RE,
    is_live_socket,
    is_switcher_session_name,
    pad_visible,
    trunc_visible,
    visible_width,
)
from ide_lib.dock import dock_session_into_switcher, undock_switcher_session
from ide_lib.fleet import classify_ide_fleet, query_fleet_snapshot
from ide_lib.theme import load_active_palette, state_color
from ide_lib.tmux import run_tmux, session_exists

_DEFAULT_PREVIEW_INTERVAL = 0.2
_ENTRY_PPID = os.getppid()


def compute_fleet_columns(
    fleet: list[dict[str, object]],
    min_sess_w: int,
    max_sess_w: int,
    max_cli_w: int,
    max_git_w: int,
) -> tuple[list[str], list[str], int, int, int, int]:
    """Compute aligned column labels and widths across `fleet` entries."""
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


_compute_fleet_columns = compute_fleet_columns


def format_fleet_sessions_lines(fleet: list[dict[str, object]], esc: dict[str, str]) -> list[str]:
    """Format `<session>\\t<ansi_display>` rows across `fleet` for `fzf`."""
    if not fleet:
        return []
    state_labels, git_labels, sess_w, cli_w, state_w, git_w = compute_fleet_columns(
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


_format_fleet_sessions_lines = format_fleet_sessions_lines


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


def format_session_preview_header(
    entry: dict[str, object],
    esc: dict[str, str],
    git_branch: str,
    git_dirty: bool,
    git_detail: str,
    quit_err: str,
    peers: list[str],
) -> list[str]:
    """Render ANSI workspace metadata lines for `entry`."""
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


_format_session_preview_header = format_session_preview_header


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

    out_lines = format_session_preview_header(
        entry, esc, git_branch, git_dirty, git_detail, quit_err, peers
    )
    if header_only:
        return ("\n".join(out_lines), False)

    raw_cols = os.environ.get("FZF_PREVIEW_COLUMNS", "").strip()
    raw_lines = os.environ.get("FZF_PREVIEW_LINES", "").strip()
    preview_cols = int(raw_cols) if raw_cols.isdigit() and int(raw_cols) > 0 else 0
    preview_lines = int(raw_lines) if raw_lines.isdigit() and int(raw_lines) > 0 else 0

    preview_pane = str(entry["preview_pane"])
    rule_w = min(56, preview_cols) if preview_cols > 0 else 56
    out_lines.append(f"{esc['BASE01']}{'─' * rule_w}{c_rst}")

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


class PipeHangupWatcher:
    """Cross-platform (`kqueue` on BSD/macOS, `poll` on Linux/POSIX) write-end hangup detector."""

    __slots__ = ("_kq", "_poller", "_sel", "closed")

    def __init__(self, fd: int | None, *, check_stat: bool = True, select_mod: object | None = None) -> None:
        sel = select if select_mod is None else select_mod
        self._sel = sel
        self._kq: object | None = None
        self._poller: object | None = None
        self.closed = False
        if fd is None or fd < 0:
            return
        if check_stat:
            try:
                st_mode = os.fstat(fd).st_mode
            except OSError:
                self.closed = True
                return
            if not (stat.S_ISFIFO(st_mode) or stat.S_ISSOCK(st_mode)):
                return
        if hasattr(sel, "kqueue"):
            kq = None
            try:
                kq = sel.kqueue()  # type: ignore[attr-defined]
                kev = sel.kevent(  # type: ignore[attr-defined]
                    fd,
                    filter=sel.KQ_FILTER_WRITE,  # type: ignore[attr-defined]
                    flags=sel.KQ_EV_ADD | sel.KQ_EV_CLEAR,  # type: ignore[attr-defined]
                )
                init_evs = kq.control([kev], 1, 0)
                reg_unsupported = False
                for ev in init_evs:
                    if ev.flags & sel.KQ_EV_ERROR:  # type: ignore[attr-defined]
                        if int(ev.data) in (errno.EPIPE, errno.EBADF):
                            self.closed = True
                        else:
                            reg_unsupported = True
                        break
                    if ev.flags & sel.KQ_EV_EOF:  # type: ignore[attr-defined]
                        self.closed = True
                        break
                if self.closed or reg_unsupported:
                    kq.close()
                    kq = None
                    if self.closed:
                        return
                else:
                    self._kq = kq
                    return
            except (OSError, ValueError):
                if kq is not None:
                    try:
                        kq.close()
                    except OSError:
                        pass
        if hasattr(sel, "poll"):
            try:
                p = sel.poll()  # type: ignore[attr-defined]
                p.register(fd, sel.POLLERR | sel.POLLHUP)  # type: ignore[attr-defined]
                nval_bit = getattr(sel, "POLLNVAL", 0)
                evs0 = p.poll(0)
                if any(mask & (sel.POLLERR | sel.POLLHUP | nval_bit) for _, mask in evs0):  # type: ignore[attr-defined]
                    self.closed = True
                    return
                self._poller = p
            except (OSError, ValueError):
                self._poller = None

    def is_closed(self) -> bool:
        """Poll without blocking and return True if the read end has closed."""
        if self.closed:
            return True
        sel = self._sel
        try:
            if self._kq is not None:
                evs = self._kq.control(None, 1, 0)  # type: ignore[attr-defined]
                if any(
                    ev.flags & (sel.KQ_EV_EOF | sel.KQ_EV_ERROR)  # type: ignore[attr-defined]
                    for ev in evs
                ):
                    self.closed = True
                    return True
            elif self._poller is not None:
                nval_bit = getattr(sel, "POLLNVAL", 0)
                evs_p = self._poller.poll(0)  # type: ignore[attr-defined]
                if any(mask & (sel.POLLERR | sel.POLLHUP | nval_bit) for _, mask in evs_p):  # type: ignore[attr-defined]
                    self.closed = True
                    return True
        except OSError:
            self.closed = True
            return True
        return False

    def wait_closed(self, timeout_s: float) -> bool:
        """Wait up to `timeout_s` seconds, returning True immediately if the read end closes."""
        if self.closed:
            return True
        if timeout_s <= 0:
            return self.is_closed()
        sel = self._sel
        if self._kq is not None:
            t0 = time.monotonic()
            try:
                evs = self._kq.control(None, 1, timeout_s)  # type: ignore[attr-defined]
            except OSError:
                self.closed = True
                return True
            if any(ev.flags & (sel.KQ_EV_EOF | sel.KQ_EV_ERROR) for ev in evs):  # type: ignore[attr-defined]
                self.closed = True
                return True
            rem = timeout_s - (time.monotonic() - t0)
            if rem > 0.002:
                time.sleep(rem)
            return self.is_closed()
        if self._poller is not None:
            nval_bit = getattr(sel, "POLLNVAL", 0)
            try:
                evs_p = self._poller.poll(max(1, int(timeout_s * 1000)))  # type: ignore[attr-defined]
                if any(mask & (sel.POLLERR | sel.POLLHUP | nval_bit) for _, mask in evs_p):  # type: ignore[attr-defined]
                    self.closed = True
                    return True
            except OSError:
                self.closed = True
                return True
            return False
        time.sleep(timeout_s)
        return False

    def close(self) -> None:
        """Release underlying kernel event descriptor if any."""
        if self._kq is not None:
            try:
                self._kq.close()  # type: ignore[attr-defined]
            except OSError:
                pass
            self._kq = None
        self._poller = None


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
        seed_fresh = False
        try:
            seed_st = os.stat(seeded_path)
            seed_fresh = (time.time() - seed_st.st_mtime) <= 1.5
            if seed_fresh:
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

            if seed_fresh and seeded_frame is not None:
                try:
                    with open(meta_path, "r", encoding="utf-8") as mfh:
                        mdata = json.loads(mfh.read())
                    if isinstance(mdata, dict):
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

    watcher = PipeHangupWatcher(out_fd)

    def _preview_cancelled() -> bool:
        if stop_requested or watcher.is_closed():
            return True
        if initial_ppid > 1 and os.getppid() != initial_ppid:
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
        while not stop_requested and not watcher.closed:
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
                if watcher.wait_closed(min(0.05, rem)):
                    pipe_closed = True
                    break
            if pipe_closed:
                break
    except BrokenPipeError:
        _silence_broken_stdout()
    except (OSError, KeyboardInterrupt):
        pass
    finally:
        watcher.close()
        for sig, prev_h in saved_sigs:
            try:
                signal.signal(sig, prev_h)
            except (OSError, ValueError):
                pass
    return 0
