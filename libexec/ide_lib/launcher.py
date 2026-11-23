"""Interactive `mono-tui` New Workspace card, AI Agent switcher dialog, and directory preview."""

from __future__ import annotations

import os
import select
import shutil
import sys

from ide_lib.constants import (
    pad_visible,
    sanitize_name_token,
    shorten_home,
    trunc_visible,
    use_nerd_fonts,
    visible_width,
)
from ide_lib.fleet import classify_ide_fleet
from ide_lib.git_info import git_summary
from ide_lib.hooks import (
    create_workspace_directory,
    default_workspace_parent,
    has_create_workspace_hook,
    resolve_workspace_target,
    sanitize_session_name,
)
from ide_lib.theme import detect_color_tier, load_active_palette, state_color

AGENT_CYCLE_ORDER = ("agy", "claude", "codex")


def _build_agent_choices(initial_agent: str) -> list[str]:
    cur = (initial_agent or "agy").strip() or "agy"
    choices = list(AGENT_CYCLE_ORDER)
    if cur not in choices:
        choices.insert(0, cur)
    return choices


def _format_card_footer(hints: list[str], inner_w: int) -> str:
    budget = max(10, inner_w - 4)
    chosen: list[str] = []
    for item in hints:
        cand_list = [*chosen, item]
        cand = " " + " · ".join(cand_list) + " "
        if visible_width(cand) <= budget or not chosen:
            chosen.append(item)
    out = " " + " · ".join(chosen) + " "
    if visible_width(out) > budget:
        return " " + trunc_visible(" · ".join(chosen), max(1, budget - 2)) + " "
    return out


def _preview_create_target(raw_name: str, use_hook: bool, parent_dir: str) -> tuple[str, bool]:
    clean = raw_name.strip()
    if clean and ".." in [seg for seg in clean.replace("\\", "/").split("/") if seg]:
        return ("(invalid '..' path segment)", False)
    if use_hook:
        shown = clean if clean else "<name>"
        return (f"ide_create_workspace {shown}", False)
    if not clean:
        return (f"{shorten_home(parent_dir)}/<name> (mkdir)", False)
    if clean.startswith(("/", "~/", "./")):
        cand = os.path.abspath(os.path.expanduser(clean))
    else:
        cand = os.path.abspath(os.path.join(parent_dir, clean))
    exists = os.path.isdir(cand)
    sfx = "(exists)" if exists else "(mkdir)"
    return (f"{shorten_home(cand)} {sfx}", exists)


def _read_tty_key(fd: int) -> tuple[str, str]:
    """Read one logical key event `(kind, text)` from raw TTY file descriptor `fd`."""
    try:
        b0 = os.read(fd, 1)
    except OSError:
        return ("eof", "")
    if not b0:
        return ("eof", "")

    if b0 == b"\x1b":
        r_ready, _, _ = select.select([fd], [], [], 0.03)
        if not r_ready:
            return ("esc", "")
        try:
            b1 = os.read(fd, 1)
        except OSError:
            return ("esc", "")
        if not b1:
            return ("esc", "")
        if b1 == b"[":
            seq = bytearray()
            while len(seq) < 24:
                r2, _, _ = select.select([fd], [], [], 0.02)
                if not r2:
                    break
                try:
                    ch = os.read(fd, 1)
                except OSError:
                    break
                if not ch:
                    break
                seq.extend(ch)
                if 0x40 <= ch[0] <= 0x7E:
                    break
            s = seq.decode("latin1", errors="ignore")
            if s == "D":
                return ("left", "")
            if s == "C":
                return ("right", "")
            if s == "A":
                return ("up", "")
            if s == "B":
                return ("down", "")
            if s in ("H", "1~", "7~"):
                return ("home", "")
            if s in ("F", "4~", "8~"):
                return ("end", "")
            if s == "3~":
                return ("delete", "")
            if s == "Z":
                return ("shift-tab", "")
            if s == "200~":
                # Drain bracketed paste payload up to \x1b[201~
                pasted = bytearray()
                while len(pasted) < 4096:
                    rp, _, _ = select.select([fd], [], [], 0.03)
                    if not rp:
                        break
                    try:
                        pch = os.read(fd, 1)
                    except OSError:
                        break
                    if not pch:
                        break
                    pasted.extend(pch)
                    if pasted.endswith(b"\x1b[201~"):
                        pasted = pasted[:-6]
                        break
                txt = pasted.decode("utf-8", errors="ignore")
                clean_p = "".join(c for c in txt if ord(c) >= 32 and ord(c) != 127)
                return ("text", clean_p)
            return ("noop", "")
        if b1 == b"O":
            r3, _, _ = select.select([fd], [], [], 0.015)
            if r3:
                try:
                    b2 = os.read(fd, 1)
                except OSError:
                    b2 = b""
                if b2 == b"H":
                    return ("home", "")
                if b2 == b"F":
                    return ("end", "")
                if b2 == b"A":
                    return ("up", "")
                if b2 == b"B":
                    return ("down", "")
                if b2 == b"C":
                    return ("right", "")
                if b2 == b"D":
                    return ("left", "")
                return ("noop", "")
            return ("noop", "")
        if b1 == b"o":
            return ("alt-o", "")
        if b1 == b"n":
            return ("alt-n", "")
        if b1 == b"s":
            return ("alt-s", "")
        if b1 == b"2":
            return ("alt-2", "")
        if b1 in (b"\x7f", b"\x08"):
            return ("kill-word", "")
        if b1 == b"b":
            return ("word-left", "")
        if b1 == b"f":
            return ("word-right", "")
        return ("noop", "")

    code = b0[0]
    if code in (13, 10):
        return ("enter", "")
    if code == 9:
        return ("tab", "")
    if code in (127, 8):
        return ("backspace", "")
    if code == 3:
        return ("ctrl-c", "")
    if code == 4:
        return ("ctrl-d", "")
    if code == 1:
        return ("home", "")
    if code == 5:
        return ("end", "")
    if code == 2:
        return ("left", "")
    if code == 6:
        return ("right", "")
    if code == 11:
        return ("kill-eol", "")
    if code == 21:
        return ("kill-bol", "")
    if code == 23:
        return ("kill-word", "")
    if code == 14:
        return ("down", "")
    if code == 16:
        return ("up", "")
    if code < 32:
        return ("noop", "")

    # Decode UTF-8 multi-byte codepoint if needed
    buf = bytearray(b0)
    need = 0
    if (code & 0xE0) == 0xC0:
        need = 1
    elif (code & 0xF0) == 0xE0:
        need = 2
    elif (code & 0xF8) == 0xF0:
        need = 3
    for _ in range(need):
        ru, _, _ = select.select([fd], [], [], 0.02)
        if not ru:
            break
        try:
            nxt = os.read(fd, 1)
        except OSError:
            break
        if not nxt:
            break
        buf.extend(nxt)
    ch_str = buf.decode("utf-8", errors="ignore")
    return ("text", ch_str) if ch_str else ("noop", "")


def _delete_prev_word(chars: list[str], cursor: int) -> tuple[list[str], int]:
    i = cursor
    while i > 0 and chars[i - 1] in (" ", "/", "-", "_"):
        i -= 1
    while i > 0 and chars[i - 1] not in (" ", "/", "-", "_"):
        i -= 1
    return (chars[:i] + chars[cursor:], i)


def run_create_workspace_dialog(
    initial_agent: str = "agy",
    layout_mode: str = "3pane",
    back_label: str = "cancel",
    allow_flip_open: bool = True,
    initial_name: str = "",
) -> tuple[str, str, str, str] | None:
    """Render interactive `New IDE >` workspace creation card and provision on Enter."""
    agents = _build_agent_choices(initial_agent)
    cur_agent = (initial_agent or "agy").strip() or "agy"
    agent_idx = agents.index(cur_agent) if cur_agent in agents else 0
    cur_layout = "2pane" if layout_mode == "2pane" else "3pane"
    chars = list(initial_name)
    cursor = len(chars)
    err_msg = ""

    # Non-TTY fallback (for scripted/piped invocations)
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        raw_line = sys.stdin.readline()
        if not raw_line:
            return None
        typed = raw_line.strip()
        if not typed:
            return None
        created_dir, create_err = create_workspace_directory(typed, interactive_tty=False)
        if create_err or not created_dir:
            if create_err:
                print(f"Error: {create_err}", file=sys.stderr)
            return None
        return ("launch", created_dir, agents[agent_idx], cur_layout)

    import termios
    import tty

    fd = sys.stdin.fileno()
    saved_attrs = termios.tcgetattr(fd)
    nf = use_nerd_fonts()
    tier = detect_color_tier()
    _, esc = load_active_palette()
    use_color = tier != "nocolor"
    c_rst = esc["RESET"] if use_color else ""
    c_b01 = esc["BASE01"] if use_color else ""
    c_b0 = esc["BASE0"] if use_color else ""
    c_b1 = esc["BASE1"] if use_color else ""
    c_blue = esc["BLUE"] if use_color else ""
    c_cyan = esc["CYAN"] if use_color else ""
    c_green = esc["GREEN"] if use_color else ""
    c_yellow = esc["YELLOW"] if use_color else ""
    c_orange = esc["ORANGE"] if use_color else ""
    ptr = ">" if (os.environ.get("TERM") or "").strip().lower() == "dumb" else "▸"
    hdr_ico = " " if nf else ""
    use_hook = has_create_workspace_hook()
    parent_dir = default_workspace_parent()

    def _render_card() -> None:
        sz = shutil.get_terminal_size((80, 24))
        cols = max(36, sz.columns)
        box_w = min(74, max(34, cols - 2))
        inner_w = box_w - 2
        left_margin = " " if cols >= box_w + 2 else ""

        title_plain = f" {hdr_ico}New IDE Workspace "
        title_trunc = trunc_visible(title_plain, max(6, inner_w - 2))
        top_fill = max(0, inner_w - 1 - visible_width(title_trunc))
        top_line = (
            f"{left_margin}{c_b01}╭─{c_blue}{title_trunc}{c_b01}{'─' * top_fill}╮{c_rst}"
        )

        footer_hints = ["Enter: create", "Tab: agent"]
        if allow_flip_open:
            footer_hints.append("Alt+o: open dir")
        footer_hints.append("Alt+2: layout")
        footer_hints.append(f"Esc: {back_label}")
        ftr_txt = _format_card_footer(footer_hints, inner_w)
        bot_fill = max(0, inner_w - 1 - visible_width(ftr_txt))
        bot_line = f"{left_margin}{c_b01}╰─{ftr_txt}{'─' * bot_fill}╯{c_rst}"

        def _box_row(content: str) -> str:
            vis = visible_width(content)
            if vis > inner_w - 2:
                # Content with SGR: fall back to safe plain truncation if needed
                padded = pad_visible(content, inner_w - 2)
            else:
                padded = pad_visible(content, inner_w - 2)
            return f"{left_margin}{c_b01}│{c_rst} {padded} {c_b01}│{c_rst}"

        name_str = "".join(chars)
        prompt_pfx = "New IDE > "
        avail_input_w = max(8, inner_w - 2 - len(prompt_pfx) - 1)
        # Keep cursor window visible inside avail_input_w
        start_idx = 0
        while cursor > start_idx and visible_width("".join(chars[start_idx:cursor])) > avail_input_w:
            start_idx += 1
        vis_slice: list[str] = []
        used_w = 0
        for ch_item in chars[start_idx:]:
            cw = visible_width(ch_item)
            if used_w + cw > avail_input_w:
                break
            vis_slice.append(ch_item)
            used_w += cw
        shown_name = "".join(vis_slice)
        cur_offset_cols = visible_width("".join(chars[start_idx:cursor]))
        name_row_content = f"{c_yellow}{prompt_pfx}{c_b1}{shown_name}{c_rst}"

        agent_parts: list[str] = []
        for idx, ag_name in enumerate(agents):
            if idx == agent_idx:
                agent_parts.append(f"{c_cyan}{ptr} {c_b1}{ag_name}{c_rst}")
            else:
                agent_parts.append(f"{c_b01}  {ag_name}{c_rst}")
        agent_joined = "  ".join(agent_parts)
        agent_lbl = f"{c_b01}Agent  :{c_rst} {agent_joined}"
        if visible_width(agent_lbl) > inner_w - 2:
            agent_lbl = f"{c_b01}Agent  :{c_rst} {c_cyan}{ptr} {c_b1}{agents[agent_idx]}{c_rst}"

        lay_desc = "2-pane side-by-side" if cur_layout == "2pane" else "3-pane inverted-T"
        lay_lbl = f"{c_b01}Layout :{c_rst} {c_b0}{trunc_visible(lay_desc, max(8, inner_w - 11))}{c_rst}"

        tgt_str, tgt_exists = _preview_create_target(name_str, use_hook, parent_dir)
        tgt_val = trunc_visible(tgt_str, max(8, inner_w - 11))
        tgt_c = c_yellow if tgt_exists else (c_cyan if use_hook else c_green)
        tgt_lbl = f"{c_b01}Target :{c_rst} {tgt_c}{tgt_val}{c_rst}"

        sess_preview = sanitize_name_token(os.path.basename(name_str.rstrip("/")) or name_str) if name_str.strip() else "-"
        sess_lbl = f"{c_b01}Session:{c_rst} {c_blue if name_str.strip() else c_b01}{trunc_visible(sess_preview, max(8, inner_w - 11))}{c_rst}"

        rows_out = [
            top_line,
            _box_row(""),
            _box_row(name_row_content),
            _box_row(""),
            _box_row(agent_lbl),
            _box_row(lay_lbl),
            _box_row(sess_lbl),
            _box_row(tgt_lbl),
        ]
        if err_msg:
            clean_err = trunc_visible(err_msg, max(10, inner_w - 2))
            rows_out.append(_box_row(f"{c_orange}{clean_err}{c_rst}"))
        else:
            rows_out.append(_box_row(""))
        rows_out.append(bot_line)

        input_row_1based = 3
        input_col_1based = len(left_margin) + 2 + len(prompt_pfx) + cur_offset_cols + 1
        frame = "\x1b[H\x1b[2J" + "\r\n".join(rows_out) + f"\x1b[{input_row_1based};{input_col_1based}H\x1b[?25h"
        sys.stdout.write(frame)
        sys.stdout.flush()

    try:
        tty.setraw(fd, when=termios.TCSANOW)
        while True:
            _render_card()
            kind, txt = _read_tty_key(fd)
            if kind in ("esc", "alt-s", "ctrl-c", "eof"):
                return None
            if kind == "ctrl-d":
                if not chars:
                    return None
                if cursor < len(chars):
                    chars.pop(cursor)
                    err_msg = ""
                continue
            if kind == "alt-o" and allow_flip_open:
                return ("flip-open", "", agents[agent_idx], cur_layout)
            if kind == "tab":
                agent_idx = (agent_idx + 1) % len(agents)
                continue
            if kind == "shift-tab":
                agent_idx = (agent_idx - 1) % len(agents)
                continue
            if kind == "alt-2":
                cur_layout = "2pane" if cur_layout == "3pane" else "3pane"
                continue
            if kind == "left":
                if cursor > 0:
                    cursor -= 1
                continue
            if kind == "right":
                if cursor < len(chars):
                    cursor += 1
                continue
            if kind == "home":
                cursor = 0
                continue
            if kind == "end":
                cursor = len(chars)
                continue
            if kind == "word-left":
                while cursor > 0 and chars[cursor - 1] in (" ", "/", "-", "_"):
                    cursor -= 1
                while cursor > 0 and chars[cursor - 1] not in (" ", "/", "-", "_"):
                    cursor -= 1
                continue
            if kind == "word-right":
                while cursor < len(chars) and chars[cursor] in (" ", "/", "-", "_"):
                    cursor += 1
                while cursor < len(chars) and chars[cursor] not in (" ", "/", "-", "_"):
                    cursor += 1
                continue
            if kind == "backspace":
                if cursor > 0:
                    chars.pop(cursor - 1)
                    cursor -= 1
                    err_msg = ""
                continue
            if kind == "delete":
                if cursor < len(chars):
                    chars.pop(cursor)
                    err_msg = ""
                continue
            if kind == "kill-bol":
                chars = chars[cursor:]
                cursor = 0
                err_msg = ""
                continue
            if kind == "kill-eol":
                chars = chars[:cursor]
                err_msg = ""
                continue
            if kind == "kill-word":
                chars, cursor = _delete_prev_word(chars, cursor)
                err_msg = ""
                continue
            if kind == "text" and txt:
                ins = list(txt)
                chars[cursor:cursor] = ins
                cursor += len(ins)
                err_msg = ""
                continue
            if kind == "enter":
                candidate = "".join(chars).strip()
                if not candidate:
                    err_msg = "Enter a workspace name (or press Esc to cancel)."
                    continue
                termios.tcsetattr(fd, termios.TCSADRAIN, saved_attrs)
                sys.stdout.write(f"\x1b[H\x1b[2J{c_cyan}Creating workspace '{candidate}'...{c_rst}\n")
                sys.stdout.flush()
                created_dir, create_err = create_workspace_directory(candidate, interactive_tty=True)
                if created_dir and not create_err:
                    return ("launch", created_dir, agents[agent_idx], cur_layout)
                err_msg = create_err or f"Could not create workspace '{candidate}'."
                tty.setraw(fd, when=termios.TCSANOW)
    finally:
        try:
            termios.tcsetattr(fd, termios.TCSADRAIN, saved_attrs)
        except Exception:
            pass
        try:
            sys.stdout.write("\x1b[H\x1b[2J\x1b[?25h")
            sys.stdout.flush()
        except OSError:
            pass


def run_agent_picker_dialog(
    sess: str,
    cur_agent: str,
    cur_state: str = "",
    back_label: str = "cancel",
) -> str | None:
    """Render interactive AI Agent restart/switch modal for `sess`."""
    cur_clean = (cur_agent or "agy").strip() or "agy"
    options: list[tuple[str, str]] = [("restart", f"Restart {cur_clean}")]
    for cand in AGENT_CYCLE_ORDER:
        if cand != cur_clean:
            options.append((cand, f"Switch to {cand}"))

    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        raw_ln = sys.stdin.readline().strip()
        if raw_ln in ("restart", *AGENT_CYCLE_ORDER):
            return raw_ln
        return None

    import termios
    import tty

    fd = sys.stdin.fileno()
    saved_attrs = termios.tcgetattr(fd)
    sel_idx = 1 if (cur_state == "QUOTA" and len(options) > 1) else 0
    nf = use_nerd_fonts()
    tier = detect_color_tier()
    _, esc = load_active_palette()
    use_color = tier != "nocolor"
    c_rst = esc["RESET"] if use_color else ""
    c_b01 = esc["BASE01"] if use_color else ""
    c_b0 = esc["BASE0"] if use_color else ""
    c_b1 = esc["BASE1"] if use_color else ""
    c_blue = esc["BLUE"] if use_color else ""
    c_cyan = esc["CYAN"] if use_color else ""
    c_state = state_color(cur_state or "IDLE", esc) if use_color else ""
    ptr = ">" if (os.environ.get("TERM") or "").strip().lower() == "dumb" else "▸"
    ai_ico = "󰚩 " if nf else ""

    def _render_agent_card() -> None:
        sz = shutil.get_terminal_size((80, 24))
        cols = max(36, sz.columns)
        box_w = min(64, max(34, cols - 2))
        inner_w = box_w - 2
        left_margin = " " if cols >= box_w + 2 else ""

        title_plain = f" {ai_ico}AI Agent · {sess} "
        title_trunc = trunc_visible(title_plain, max(8, inner_w - 2))
        top_fill = max(0, inner_w - 1 - visible_width(title_trunc))
        top_line = f"{left_margin}{c_b01}╭─{c_blue}{title_trunc}{c_b01}{'─' * top_fill}╮{c_rst}"

        ftr = _format_card_footer(["Enter: apply", "j/k: select", f"Esc: {back_label}"], inner_w)
        bot_fill = max(0, inner_w - 1 - visible_width(ftr))
        bot_line = f"{left_margin}{c_b01}╰─{ftr}{'─' * bot_fill}╯{c_rst}"

        def _row(txt_line: str) -> str:
            return f"{left_margin}{c_b01}│{c_rst} {pad_visible(txt_line, inner_w - 2)} {c_b01}│{c_rst}"

        st_disp = cur_state or "IDLE"
        rows_out = [
            top_line,
            _row(f"{c_b01}Current:{c_rst} {c_cyan}{cur_clean}{c_rst}  {c_b01}State:{c_rst} {c_state}{st_disp}{c_rst}"),
            _row(""),
        ]
        for idx, (_, label) in enumerate(options):
            num_hint = f"{idx + 1}."
            clean_lbl = trunc_visible(label, max(8, inner_w - 9))
            if idx == sel_idx:
                rows_out.append(_row(f"{c_cyan}{ptr} {num_hint} {c_b1}{clean_lbl}{c_rst}"))
            else:
                rows_out.append(_row(f"  {c_b01}{num_hint}{c_rst} {c_b0}{clean_lbl}{c_rst}"))
        rows_out.append(_row(""))
        rows_out.append(bot_line)

        sys.stdout.write("\x1b[?25l\x1b[H\x1b[2J" + "\r\n".join(rows_out))
        sys.stdout.flush()

    try:
        tty.setraw(fd, when=termios.TCSANOW)
        while True:
            _render_agent_card()
            kind, txt = _read_tty_key(fd)
            if kind in ("esc", "alt-s", "ctrl-c", "ctrl-d", "eof"):
                return None
            if kind == "text" and txt in ("q", "Q"):
                return None
            if kind == "text" and txt in ("j",):
                sel_idx = (sel_idx + 1) % len(options)
                continue
            if kind == "text" and txt in ("k",):
                sel_idx = (sel_idx - 1) % len(options)
                continue
            if kind == "text" and txt.isdigit():
                n_val = int(txt) - 1
                if 0 <= n_val < len(options):
                    return options[n_val][0]
            if kind in ("down", "tab"):
                sel_idx = (sel_idx + 1) % len(options)
                continue
            if kind in ("up", "shift-tab"):
                sel_idx = (sel_idx - 1) % len(options)
                continue
            if kind == "enter":
                return options[sel_idx][0]
    finally:
        try:
            termios.tcsetattr(fd, termios.TCSADRAIN, saved_attrs)
        except Exception:
            pass
        try:
            sys.stdout.write("\x1b[H\x1b[2J\x1b[?25h")
            sys.stdout.flush()
        except OSError:
            pass


def render_directory_preview(raw_dir: str, cur_sess: str = "") -> int:
    """Render ANSI workspace directory, active-session, VCS, and contents preview for `ide dir`."""
    cand_raw = (raw_dir or "").strip()
    if not cand_raw:
        return 0
    cand_abs = os.path.abspath(os.path.expanduser(cand_raw))
    if not os.path.isdir(cand_abs):
        print(f"Directory '{cand_raw}' does not exist.")
        return 0

    resolved_dir = resolve_workspace_target(cand_abs) or cand_abs
    sess_name = sanitize_session_name(resolved_dir)
    _, esc = load_active_palette()
    tier = detect_color_tier()
    use_color = tier != "nocolor"
    c_rst = esc["RESET"] if use_color else ""
    c_b01 = esc["BASE01"] if use_color else ""
    c_b0 = esc["BASE0"] if use_color else ""
    c_blue = esc["BLUE"] if use_color else ""
    c_cyan = esc["CYAN"] if use_color else ""
    c_green = esc["GREEN"] if use_color else ""
    c_yellow = esc["YELLOW"] if use_color else ""
    nf = use_nerd_fonts()

    raw_cols = (os.environ.get("FZF_PREVIEW_COLUMNS") or os.environ.get("COLUMNS") or "").strip()
    raw_lines = (os.environ.get("FZF_PREVIEW_LINES") or os.environ.get("LINES") or "").strip()
    max_cols = int(raw_cols) if raw_cols.isdigit() and int(raw_cols) > 0 else 80
    max_lines = int(raw_lines) if raw_lines.isdigit() and int(raw_lines) > 0 else 28
    val_budget = max(12, max_cols - 12)

    fleet = classify_ide_fleet(include_git=False, cur_sess=cur_sess)
    real_resolved = os.path.realpath(resolved_dir)
    real_cand = os.path.realpath(cand_abs)
    active_entry = None
    for entry in fleet:
        ewd = str(entry.get("workdir") or "")
        eroot = str(entry.get("init_root") or "")
        if str(entry["sess"]) == sess_name or (
            ewd and os.path.realpath(ewd) in (real_resolved, real_cand)
        ) or (
            eroot and os.path.realpath(eroot) in (real_resolved, real_cand)
        ):
            active_entry = entry
            break

    hdr_ico = " " if nf else ""
    hdr_name = trunc_visible(f"{hdr_ico}{sess_name}", max(8, max_cols - 22))
    if active_entry is not None:
        ag = str(active_entry["ai_cli"])
        st = str(active_entry["state"])
        st_lbl = str(active_entry.get("state_label") or st)
        c_st = state_color(st, esc) if use_color else ""
        status_sfx = f"{c_b01}(active:{c_rst} {c_cyan}{ag}{c_rst} {c_b01}·{c_rst} {c_st}{st_lbl}{c_b01}){c_rst}"
    else:
        status_sfx = f"{c_b01}(not running){c_rst}"

    git_branch, git_dirty, git_detail, _, _ = git_summary(resolved_dir)
    c_git = c_yellow if git_dirty else (c_green if git_branch != "-" else c_b01)

    out: list[str] = [
        f"{c_blue}{hdr_name}{c_rst}  {status_sfx}",
        f"{c_b01}Path     :{c_rst} {c_b0}{trunc_visible(shorten_home(cand_abs), val_budget)}{c_rst}",
    ]
    if os.path.abspath(resolved_dir) != cand_abs:
        out.append(
            f"{c_b01}Target   :{c_rst} {c_b0}{trunc_visible(shorten_home(resolved_dir), val_budget)}{c_rst}"
        )
    out.append(
        f"{c_b01}VCS      :{c_rst} {c_git}{trunc_visible(git_detail, val_budget)}{c_rst}"
    )

    dirs_list: list[str] = []
    files_list: list[str] = []
    scanned = 0
    try:
        with os.scandir(resolved_dir) as it:
            for dent in it:
                if dent.name == ".git":
                    continue
                scanned += 1
                if scanned > 240:
                    break
                try:
                    if dent.is_dir():
                        dirs_list.append(dent.name)
                    else:
                        files_list.append(dent.name)
                except OSError:
                    files_list.append(dent.name)
    except OSError:
        pass
    dirs_list.sort(key=lambda s: (s.startswith("."), s.lower()))
    files_list.sort(key=lambda s: (s.startswith("."), s.lower()))

    rem_rows = max(0, max_lines - len(out) - 2)
    if rem_rows >= 2 and (dirs_list or files_list):
        rule_w = max(4, min(36, max_cols - 14))
        out.append(f"{c_b01}── Contents {'─' * rule_w}{c_rst}")
        combined: list[tuple[bool, str]] = [
            *((True, d) for d in dirs_list),
            *((False, f) for f in files_list),
        ]
        limit = min(16, rem_rows - 1 if len(combined) > rem_rows else rem_rows)
        dir_ico = " " if nf else ""
        file_ico = " " if nf else ""
        for is_d, name in combined[:limit]:
            clean_nm = name.replace("\n", " ").replace("\r", " ")
            if is_d:
                item_txt = trunc_visible(f"  {dir_ico}{clean_nm}/", max(6, max_cols - 1))
                out.append(f"{c_blue}{item_txt}{c_rst}")
            else:
                item_txt = trunc_visible(f"  {file_ico}{clean_nm}", max(6, max_cols - 1))
                out.append(f"{c_b0}{item_txt}{c_rst}")
        if len(combined) > limit:
            more_n = len(combined) - limit
            out.append(f"{c_b01}  … +{more_n} more{c_rst}")

    print("\n".join(out[: max(1, max_lines)]))
    return 0
