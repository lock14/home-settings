"""TrueColor palette swatch strips, 6-pillar syntax preview cards, and fzf picker."""

from __future__ import annotations

import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import unicodedata

from theme_lib.generators import build_fzf_color_opts
from theme_lib.palette import get_holiday_meta, hex_to_rgb, ordered_theme_slugs
from theme_lib.reload import apply_theme

ANSI_SGR_RE = re.compile(r"\033\[[0-9;]*m")
_FZF_POS_CAP_CACHE: dict[str, bool] = {}

SWATCH_STRIP_KEYS: tuple[str, ...] = (
    "BASE03",
    "BASE0",
    "GREEN",
    "BLUE",
    "YELLOW",
    "VIOLET",
    "CYAN",
    "MAGENTA",
    "ORANGE",
    "RED",
)


def _use_nerd_fonts() -> bool:
    """Return False when IDE_NERD_FONTS=0|off|false|no|ascii, IDE_ASCII=1, or TERM=dumb."""
    nf = (os.environ.get("IDE_NERD_FONTS") or "").strip().lower()
    if nf in ("0", "false", "off", "no", "ascii"):
        return False
    if (os.environ.get("IDE_ASCII") or "").strip().lower() in ("1", "true", "on", "yes"):
        return False
    if (os.environ.get("TERM") or "").strip().lower() == "dumb":
        return False
    return True


def _detect_preview_color_tier() -> str:
    """Detect terminal color capability for theme previews and fzf pickers."""
    if os.environ.get("NO_COLOR"):
        return "nocolor"
    term = (os.environ.get("TERM") or "").strip().lower()
    if term == "dumb":
        return "mono"
    if term == "linux":
        return "16color"
    ct = (os.environ.get("COLORTERM") or "").strip().lower()
    if ct in ("16color", "ansi", "4bit"):
        return "16color"
    return "truecolor"


def _fzf_supports_load_pos(fzf_bin: str) -> bool:
    """Return True when fzf supports `--bind=load:pos(N)` (>= 0.36) without probing tiny test mocks."""
    override = (os.environ.get("THEME_FZF_POS") or "").strip().lower()
    if override in ("1", "true", "yes", "on"):
        return True
    if override in ("0", "false", "no", "off"):
        return False
    if fzf_bin in _FZF_POS_CAP_CACHE:
        return _FZF_POS_CAP_CACHE[fzf_bin]
    supported = False
    try:
        if os.path.getsize(fzf_bin) > 65536:
            res = subprocess.run(
                [fzf_bin, "--version"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=1.5,
                check=False,
            )
            m = re.match(r"^\s*(\d+)\.(\d+)", res.stdout or "")
            if m:
                major, minor = int(m.group(1)), int(m.group(2))
                supported = (major > 0) or (minor >= 36)
    except (OSError, subprocess.SubprocessError):
        supported = False
    _FZF_POS_CAP_CACHE[fzf_bin] = supported
    return supported


def fg_esc(hex_str: str) -> str:
    """Return 24-bit TrueColor foreground SGR escape sequence for #RRGGBB."""
    r, g, b = hex_to_rgb(hex_str)
    return f"\033[38;2;{r};{g};{b}m"


def bg_esc(hex_str: str) -> str:
    """Return 24-bit TrueColor background SGR escape sequence for #RRGGBB."""
    r, g, b = hex_to_rgb(hex_str)
    return f"\033[48;2;{r};{g};{b}m"


def _char_width(ch: str) -> int:
    """Return terminal cell width accounting for combining marks, PUA glyphs, emojis, and CJK."""
    cp = ord(ch)
    if 0x20 <= cp < 0x7F:
        return 1
    if cp < 0x20 or cp == 0x7F or cp in (0x200D, 0xFE0E, 0xFE0F):
        return 0
    if 0xE000 <= cp <= 0xF8FF or 0xF0000 <= cp <= 0x10FFFF:
        return 1
    if unicodedata.combining(ch):
        return 0
    if 0x1F300 <= cp <= 0x1FAFF or ch == "✨" or unicodedata.east_asian_width(ch) in ("W", "F"):
        return 2
    return 1


def visible_len(text: str) -> int:
    """Compute terminal display column width ignoring ANSI SGR escapes and expanding tabs."""
    plain = ANSI_SGR_RE.sub("", text).replace("\t", "    ")
    return sum(_char_width(ch) for ch in plain)


def trunc_ansi_line(text: str, max_cols: int) -> str:
    """Truncate ANSI SGR text to `max_cols` visible cells, appending `…` when clipped."""
    if max_cols <= 0:
        return ""
    expanded = text.replace("\t", "    ")
    if visible_len(expanded) <= max_cols:
        return expanded
    if max_cols == 1:
        return "…"
    limit = max_cols - 1
    out: list[str] = []
    vis = 0
    idx = 0
    n = len(expanded)
    while idx < n:
        if expanded[idx] == "\033":
            m = ANSI_SGR_RE.match(expanded, idx)
            if m:
                out.append(m.group(0))
                idx = m.end()
                continue
        cw = _char_width(expanded[idx])
        if vis + cw > limit:
            break
        out.append(expanded[idx])
        vis += cw
        idx += 1
    out.append("…")
    return "".join(out)


def pad_preview_line(content: str, bg_code: str, width: int, left_pad: int = 2, reset_code: str = "\033[0m") -> str:
    """Pad or truncate a preview row to an exact rectangular display column width."""
    eff_pad = min(left_pad, max(0, width - 1))
    clipped = trunc_ansi_line(content, max(1, width - eff_pad))
    prefix = f"{bg_code}{' ' * eff_pad}{clipped}{bg_code}"
    rem = max(0, width - visible_len(prefix))
    return f"{prefix}{' ' * rem}{reset_code}"


def format_swatch_strip(theme: dict[str, str]) -> str:
    """Render a compact 10-block TrueColor swatch strip for list and fzf views."""
    swatches = [fg_esc(theme[k]) + "██" for k in SWATCH_STRIP_KEYS]
    return "".join(swatches) + "\033[0m"


def render_preview(theme: dict[str, str]) -> int:
    """Render a rectangular TrueColor (or NO_COLOR/ASCII-safe) palette and semantic code preview card."""
    fzf_cols = os.environ.get("FZF_PREVIEW_COLUMNS", "").strip()
    fzf_lines = os.environ.get("FZF_PREVIEW_LINES", "").strip()
    in_fzf = bool(fzf_cols and fzf_lines)

    if fzf_cols:
        try:
            width = max(44, int(fzf_cols))
        except ValueError:
            width = 94
    elif sys.stdout.isatty():
        width = max(44, min(94, shutil.get_terminal_size((94, 30)).columns))
    else:
        width = 94
    try:
        target_height = max(24, int(fzf_lines)) if fzf_lines else 0
    except ValueError:
        target_height = 0

    tier = _detect_preview_color_tier()
    use_tc = tier == "truecolor"
    rst = "" if tier in ("nocolor", "mono") else "\033[0m"
    nf_ok = _use_nerd_fonts()

    b03 = bg_esc(theme["BASE03"]) if use_tc else ""
    b02 = bg_esc(theme["BASE02"]) if use_tc else ""
    b_grn = bg_esc(theme["MIX_GREEN"]) if use_tc else ""
    b_red = bg_esc(theme["MIX_RED"]) if use_tc else ""

    c_b01 = fg_esc(theme["BASE01"]) if use_tc else ""
    c_b00 = fg_esc(theme["BASE00"]) if use_tc else ""
    c_b0 = fg_esc(theme["BASE0"]) if use_tc else ""
    c_b1 = fg_esc(theme["BASE1"]) if use_tc else ""
    c_ylw = fg_esc(theme["YELLOW"]) if use_tc else ""
    c_org = fg_esc(theme["ORANGE"]) if use_tc else ""
    c_red = fg_esc(theme["RED"]) if use_tc else ""
    c_mag = fg_esc(theme["MAGENTA"]) if use_tc else ""
    c_vio = fg_esc(theme["VIOLET"]) if use_tc else ""
    c_blu = fg_esc(theme["BLUE"]) if use_tc else ""
    c_cyn = fg_esc(theme["CYAN"]) if use_tc else ""
    c_grn = fg_esc(theme["GREEN"]) if use_tc else ""

    hmeta = get_holiday_meta(theme)
    if hmeta and nf_ok:
        session_icon = hmeta["icon"]
        prompt_icon = hmeta["icon"]
    elif nf_ok:
        session_icon = ""
        prompt_icon = ""
    else:
        session_icon = "*"
        prompt_icon = "$"

    sep_r = "\uE0B1" if nf_ok else ">"
    sep_l = "\uE0B3" if nf_ok else "|"
    ai_ic = "󰚩 " if nf_ok else ""
    ed_ic = " " if nf_ok else ""
    sh_ic = " " if nf_ok else ""
    git_ic = " " if nf_ok else "git:"
    chk_ic = "✔" if tier != "mono" else "ok"
    prm_ic = "❯" if tier != "mono" else ">"
    rule_ch = "─" if tier != "mono" else "-"
    sw_glyph = "██" if use_tc else "##"

    def _pad(content: str, bg_code: str, left_pad: int = 2) -> str:
        return pad_preview_line(content, bg_code, width, left_pad=left_pad, reset_code=rst)

    rule_width = max(20, min(width - 4, 88))
    lines: list[str] = []
    if hmeta and nf_ok:
        lines.append(_pad(f"{c_ylw}{hmeta['banner']}", b02))
    lines.extend(
        [
            _pad(
                f"{c_org}{theme['THEME_LABEL']} {c_b01}({theme['THEME_ID']} | {theme['THEME_MODE']} | {theme['SOURCE']})",
                b02,
            ),
            _pad(f"{c_b0}{theme['THEME_DESCRIPTION']}", b02),
            _pad(f"{c_blu}Monotone Surface & Content Ramp:", b03),
        ]
    )

    mono_row = [
        f"{fg_esc(theme[k]) if use_tc else ''}{sw_glyph} {c_b0}{k.lower()}:{theme[k]}"
        for k in ("BASE03", "BASE02", "BASE01", "BASE00", "BASE0", "BASE1", "BASE2", "BASE3")
    ]
    if width >= 82:
        lines.append(_pad("  ".join(mono_row[:4]), b03, left_pad=4))
        lines.append(_pad("  ".join(mono_row[4:]), b03, left_pad=4))
    else:
        for idx in range(0, len(mono_row), 2):
            lines.append(_pad("   ".join(mono_row[idx : idx + 2]), b03, left_pad=4))

    lines.append(_pad(f"{c_blu}Semantic Accent Architecture:", b03))
    roles = [
        ("YELLOW", "control flow"),
        ("ORANGE", "preprocessor / H1"),
        ("RED", "errors / deletions"),
        ("MAGENTA", "constants / numbers"),
        ("VIOLET", "imports / attributes"),
        ("BLUE", "function defs / H2"),
        ("CYAN", "strings / escapes"),
        ("GREEN", "keywords / types"),
    ]
    if width >= 84:
        for i in range(0, len(roles), 2):
            k1, r1 = roles[i]
            k2, r2 = roles[i + 1]
            c1 = fg_esc(theme[k1]) if use_tc else ""
            c2 = fg_esc(theme[k2]) if use_tc else ""
            col1 = f"{c1}{sw_glyph} {c_b1}{k1:<7} {c_b01}{theme[k1]} {c_b0}({r1:<18})"
            col2 = f"{c2}{sw_glyph} {c_b1}{k2:<7} {c_b01}{theme[k2]} {c_b0}({r2})"
            lines.append(_pad(f"{col1}   {col2}", b03, left_pad=4))
    elif width >= 60:
        for i in range(0, len(roles), 2):
            k1, _ = roles[i]
            k2, _ = roles[i + 1]
            c1 = fg_esc(theme[k1]) if use_tc else ""
            c2 = fg_esc(theme[k2]) if use_tc else ""
            col1 = f"{c1}{sw_glyph} {c_b1}{k1:<7} {c_b01}{theme[k1]}"
            col2 = f"{c2}{sw_glyph} {c_b1}{k2:<7} {c_b01}{theme[k2]}"
            lines.append(_pad(f"{col1}   {col2}", b03, left_pad=4))
    else:
        for k_acc, r_acc in roles:
            c_acc = fg_esc(theme[k_acc]) if use_tc else ""
            lines.append(
                _pad(
                    f"{c_acc}{sw_glyph} {c_b1}{k_acc:<7} {c_b01}{theme[k_acc]} {c_b0}({r_acc})",
                    b03,
                    left_pad=4,
                )
            )

    lines.append(_pad(f"{c_b01}{rule_ch * rule_width}", b03))
    lines.append(_pad(f"{c_blu}Converged Semantic Code Preview:", b03))
    ptr = "▸" if tier != "mono" else ">"
    mid_dot = "·" if tier != "mono" else "|"
    h_badge = f"  {c_b00}{sep_l} {c_ylw}{hmeta['badge']}" if (hmeta and nf_ok) else ""
    if width < 88:
        status_preview_line = (
            f"{c_blu}{session_icon} ide {c_b00}{sep_r} {c_cyn}{ptr} {ai_ic}agy {c_b01}{mid_dot} {c_b0}{ed_ic}Editor {c_b01}{mid_dot} {c_b0}{sh_ic}Shell"
            + (h_badge if width >= 64 else "")
        )
    else:
        status_preview_line = (
            f"{c_blu}{session_icon} ide {c_b00}{sep_r} {c_cyn}{ptr} {ai_ic}agy {c_b1}(Alt+a) {c_b01}{mid_dot} {c_b0}{ed_ic}Editor (Alt+e) {c_b01}{mid_dot} {c_b0}{sh_ic}Shell (Alt+t)"
            + h_badge
        )
    lines.extend(
        [
            _pad(f"{c_b01}// {theme['THEME_LABEL']} — 6-Pillar Semantic Highlighting", b03, left_pad=4),
            _pad(f"{c_org}#include {c_cyn}<stdio.h>", b03, left_pad=4),
            _pad(f"{c_vio}import {c_vio}core::telemetry{c_b0};", b03, left_pad=4),
            _pad(f"{c_vio}#[derive(Clone)]", b03, left_pad=4),
            _pad(
                f"{c_grn}pub fn {c_blu}classify_sample{c_b0}(val: {c_grn}i64{c_b0}) -> {c_b0}Option<{c_grn}bool{c_b0}> {{",
                b03,
                left_pad=4,
            ),
            _pad(f"    {c_ylw}if {c_b0}val >= {c_mag}42 {c_b0}{{", b03, left_pad=4),
            _pad(f"    {c_red}-   {c_ylw}return {c_b0}Some({c_mag}false{c_b0});", b_red, left_pad=4),
            _pad(f"    {c_grn}+   {c_ylw}return {c_b0}Some({c_mag}true{c_b0});", b_grn, left_pad=4),
            _pad(f"    {c_b0}}}", b03, left_pad=4),
            _pad(f"    {c_b0}emit_log({c_cyn}\"status: %s\\n\"{c_b0});", b03, left_pad=4),
            _pad(f"    {c_ylw}return {c_mag}None{c_b0};", b03, left_pad=4),
            _pad(f"{c_b0}}}", b03, left_pad=4),
            _pad(status_preview_line, b02),
            _pad(
                f"{c_b0}{prompt_icon} {c_b01}{sep_r} {c_blu}~/home-settings {c_b01}{sep_r} {c_grn}{git_ic}main {chk_ic} {c_grn}{prm_ic} {c_grn}theme {c_cyn}{theme['THEME_ID']}",
                b03,
                left_pad=2,
            ),
        ]
    )

    if in_fzf and target_height > len(lines):
        while len(lines) < target_height:
            lines.append(_pad("", b03))

    print("\n".join(lines))
    return 0


def list_themes(
    themes: dict[str, dict[str, str]],
    current_slug: str,
    plain: bool = False,
) -> int:
    """List all managed and user-defined themes with active marker and optional swatches."""
    tier = _detect_preview_color_tier()
    use_color = sys.stdout.isatty() and tier == "truecolor"
    nf_ok = _use_nerd_fonts()
    raw_list_cols = os.environ.get("THEME_LIST_COLUMNS", "").strip()
    if raw_list_cols.isdigit() and int(raw_list_cols) > 0:
        tty_cols = int(raw_list_cols)
    elif sys.stdout.isatty():
        tty_cols = shutil.get_terminal_size((120, 40)).columns
    else:
        tty_cols = 0

    for slug in ordered_theme_slugs(themes):
        if plain:
            print(slug)
            continue
        t = themes[slug]
        marker = "*" if slug == current_slug else " "
        hmeta = get_holiday_meta(t)
        display_label = f"{hmeta['icon']} {t['THEME_LABEL']}" if (hmeta and nf_ok) else t["THEME_LABEL"]
        tail_text = f"{display_label} — {t['THEME_DESCRIPTION']}"
        show_strip = use_color and (tty_cols == 0 or tty_cols >= 68)
        prefix_w = 2 + 18 + 1 + 5 + 2 + 7 + 2 + (22 if show_strip else 0)
        if tty_cols > 0:
            rem_w = max(8, tty_cols - prefix_w)
            tail_text = trunc_ansi_line(tail_text, rem_w)
        if show_strip:
            strip = format_swatch_strip(t)
            print(
                f"{marker} {slug:<18} {t['THEME_MODE']:<5}  {t['SOURCE']:<7}  {strip}  {tail_text}"
            )
        else:
            print(
                f"{marker} {slug:<18} {t['THEME_MODE']:<5}  {t['SOURCE']:<7}  {tail_text}"
            )
    return 0


def run_fzf_picker(
    themes: dict[str, dict[str, str]],
    current_slug: str,
    repo_dir: Path,
    dry_run: bool = False,
    no_live: bool = False,
) -> int:
    """Launch an interactive fzf theme picker with live TrueColor preview pane."""
    in_wrapper = os.environ.get("THEME_SHELL_WRAPPER") == "1"
    fzf_bin = shutil.which("fzf")
    if not fzf_bin:
        rc = list_themes(themes, current_slug)
        return 130 if (in_wrapper and rc == 0) else rc

    raw_cols = os.environ.get("COLUMNS", "").strip()
    if raw_cols.isdigit() and int(raw_cols) > 0:
        term_cols = int(raw_cols)
    else:
        term_cols = shutil.get_terminal_size((120, 40)).columns

    tier = _detect_preview_color_tier()
    use_tc = tier == "truecolor"
    nf_ok = _use_nerd_fonts()

    ordered = ordered_theme_slugs(themes)
    active_pos = 1
    lines: list[str] = []
    for idx, slug in enumerate(ordered, 1):
        if slug == current_slug:
            active_pos = idx
        t = themes[slug]
        active_tag = "(active)" if slug == current_slug else "        "
        hmeta = get_holiday_meta(t)
        display_label = f"{hmeta['icon']} {t['THEME_LABEL']}" if (hmeta and nf_ok) else t["THEME_LABEL"]
        if use_tc:
            strip = format_swatch_strip(t)
            if term_cols < 76:
                lines.append(f"{slug:<18}  {active_tag}  {strip}  {display_label}")
            else:
                lines.append(f"{slug:<18}  {active_tag}  {t['THEME_MODE']:<5}  {t['SOURCE']:<7}  {strip}  {display_label}")
        elif term_cols < 76:
            lines.append(f"{slug:<18}  {active_tag}  {display_label}")
        else:
            lines.append(f"{slug:<18}  {active_tag}  {t['THEME_MODE']:<5}  {t['SOURCE']:<7}  {display_label}")

    if term_cols < 90:
        height_arg = "--height=95%"
        preview_win = "--preview-window=down:58%:nowrap:noinfo"
    elif term_cols < 110:
        height_arg = "--height=90%"
        preview_win = "--preview-window=right:56%:nowrap:noinfo"
    else:
        height_arg = "--height=80%"
        preview_win = "--preview-window=right:60%:nowrap:noinfo"

    sep = "|" if tier == "mono" else "·"
    header_arg = (
        f"--header=Enter: apply {sep} Esc: cancel"
        if term_cols < 68
        else f"--header=Select a color theme (Enter: apply {sep} Esc: cancel)"
    )

    if tier == "nocolor":
        fzf_color_arg = "--no-color"
    elif tier == "mono":
        fzf_color_arg = "--color=bw"
    elif tier == "16color":
        fzf_color_arg = "--color=16"
    else:
        fzf_color_arg = build_fzf_color_opts(themes[current_slug], include_layout=False)

    self_bin = str(repo_dir / "bin" / "theme")
    preview_cmd = f"{shlex.quote(self_bin)} --preview {{1}}"
    cmd = [
        fzf_bin,
        "--ansi",
        "--no-multi",
        "--reverse",
        "--no-scrollbar",
        height_arg,
        "--border=rounded",
        "--prompt=Theme > ",
        header_arg,
        f"--preview={preview_cmd}",
        preview_win,
        fzf_color_arg,
    ]
    if active_pos > 1 and _fzf_supports_load_pos(fzf_bin):
        cmd.append(f"--bind=load:pos({active_pos})")
    proc = subprocess.run(cmd, input="\n".join(lines) + "\n", text=True, capture_output=True, check=False)
    if proc.returncode != 0:
        return 130 if in_wrapper else 0
    selected = proc.stdout.strip()
    if not selected:
        return 130 if in_wrapper else 0
    tokens = selected.split()
    chosen_slug = (tokens[1] if tokens and tokens[0] == "*" and len(tokens) > 1 else tokens[0]).strip().lower()
    if chosen_slug not in themes:
        sys.stderr.write(f"theme: unknown theme selected: {chosen_slug}\n")
        return 1
    return apply_theme(themes[chosen_slug], repo_dir, dry_run=dry_run, no_live=no_live)
