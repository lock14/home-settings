"""TrueColor palette swatch strips, 6-pillar syntax preview cards, and fzf picker."""

from __future__ import annotations

import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys

from theme_lib.generators import build_fzf_color_opts
from theme_lib.palette import HOLIDAY_META, MANAGED_ORDER, hex_to_rgb
from theme_lib.reload import apply_theme

ANSI_SGR_RE = re.compile(r"\033\[[0-9;]*m")

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


def fg_esc(hex_str: str) -> str:
    """Return 24-bit TrueColor foreground SGR escape sequence for #RRGGBB."""
    r, g, b = hex_to_rgb(hex_str)
    return f"\033[38;2;{r};{g};{b}m"


def bg_esc(hex_str: str) -> str:
    """Return 24-bit TrueColor background SGR escape sequence for #RRGGBB."""
    r, g, b = hex_to_rgb(hex_str)
    return f"\033[48;2;{r};{g};{b}m"


def visible_len(text: str) -> int:
    """Compute terminal display column width ignoring ANSI SGR escapes."""
    plain = ANSI_SGR_RE.sub("", text)
    total = 0
    for ch in plain:
        cp = ord(ch)
        if 0x1F300 <= cp <= 0x1FAFF or ch == "✨":
            total += 2
        else:
            total += 1
    return total


def _char_width(ch: str) -> int:
    cp = ord(ch)
    return 2 if (0x1F300 <= cp <= 0x1FAFF or ch == "✨") else 1


def trunc_ansi_line(text: str, max_cols: int) -> str:
    """Truncate ANSI SGR text to `max_cols` visible cells, appending `…` when clipped."""
    if max_cols <= 0:
        return ""
    if visible_len(text) <= max_cols:
        return text
    if max_cols == 1:
        return "…"
    limit = max_cols - 1
    out: list[str] = []
    vis = 0
    idx = 0
    n = len(text)
    while idx < n:
        if text[idx] == "\033":
            m = ANSI_SGR_RE.match(text, idx)
            if m:
                out.append(m.group(0))
                idx = m.end()
                continue
        cw = _char_width(text[idx])
        if vis + cw > limit:
            break
        out.append(text[idx])
        vis += cw
        idx += 1
    out.append("…")
    return "".join(out)


def pad_preview_line(content: str, bg_code: str, width: int, left_pad: int = 2) -> str:
    """Pad or truncate a TrueColor preview row to an exact rectangular display column width."""
    rst = "\033[0m"
    eff_pad = min(left_pad, max(0, width - 1))
    clipped = trunc_ansi_line(content, max(1, width - eff_pad))
    prefix = f"{bg_code}{' ' * eff_pad}{clipped}{bg_code}"
    rem = max(0, width - visible_len(prefix))
    return f"{prefix}{' ' * rem}{rst}"


def ordered_theme_slugs(themes: dict[str, dict[str, str]]) -> list[str]:
    """Return managed slugs in canonical order followed by sorted custom user themes."""
    ordered = [s for s in MANAGED_ORDER if s in themes]
    for s in sorted(themes.keys()):
        if s not in ordered:
            ordered.append(s)
    return ordered


def format_swatch_strip(theme: dict[str, str]) -> str:
    """Render a compact 10-block TrueColor swatch strip for list and fzf views."""
    swatches = [fg_esc(theme[k]) + "██" for k in SWATCH_STRIP_KEYS]
    return "".join(swatches) + "\033[0m"


def render_preview(theme: dict[str, str]) -> int:
    """Render a rectangular TrueColor palette and converged semantic code preview card."""
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

    b03 = bg_esc(theme["BASE03"])
    b02 = bg_esc(theme["BASE02"])
    b_grn = bg_esc(theme["MIX_GREEN"])
    b_red = bg_esc(theme["MIX_RED"])

    c_b01 = fg_esc(theme["BASE01"])
    c_b00 = fg_esc(theme["BASE00"])
    c_b0 = fg_esc(theme["BASE0"])
    c_b1 = fg_esc(theme["BASE1"])
    c_ylw = fg_esc(theme["YELLOW"])
    c_org = fg_esc(theme["ORANGE"])
    c_red = fg_esc(theme["RED"])
    c_mag = fg_esc(theme["MAGENTA"])
    c_vio = fg_esc(theme["VIOLET"])
    c_blu = fg_esc(theme["BLUE"])
    c_cyn = fg_esc(theme["CYAN"])
    c_grn = fg_esc(theme["GREEN"])

    hmeta = HOLIDAY_META.get(theme["THEME_ID"])
    session_icon = hmeta["icon"] if hmeta else ""
    prompt_icon = hmeta["icon"] if hmeta else ""

    rule_width = max(20, min(width - 4, 88))
    lines: list[str] = []
    if hmeta:
        lines.append(pad_preview_line(f"{c_ylw}{hmeta['banner']}", b02, width))
    lines.extend(
        [
            pad_preview_line(
                f"{c_org}{theme['THEME_LABEL']} {c_b01}({theme['THEME_ID']} | {theme['THEME_MODE']} | {theme['SOURCE']})",
                b02,
                width,
            ),
            pad_preview_line(f"{c_b0}{theme['THEME_DESCRIPTION']}", b02, width),
            pad_preview_line(f"{c_blu}Monotone Surface & Content Ramp:", b03, width),
        ]
    )

    mono_row = [
        f"{fg_esc(theme[k])}██ {c_b0}{k.lower()}:{theme[k]}"
        for k in ("BASE03", "BASE02", "BASE01", "BASE00", "BASE0", "BASE1", "BASE2", "BASE3")
    ]
    if width >= 82:
        lines.append(pad_preview_line("  ".join(mono_row[:4]), b03, width, left_pad=4))
        lines.append(pad_preview_line("  ".join(mono_row[4:]), b03, width, left_pad=4))
    else:
        for idx in range(0, len(mono_row), 2):
            lines.append(pad_preview_line("   ".join(mono_row[idx : idx + 2]), b03, width, left_pad=4))

    lines.append(pad_preview_line(f"{c_blu}Semantic Accent Architecture:", b03, width))
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
            col1 = f"{fg_esc(theme[k1])}██ {c_b1}{k1:<7} {c_b01}{theme[k1]} {c_b0}({r1:<18})"
            col2 = f"{fg_esc(theme[k2])}██ {c_b1}{k2:<7} {c_b01}{theme[k2]} {c_b0}({r2})"
            lines.append(pad_preview_line(f"{col1}   {col2}", b03, width, left_pad=4))
    elif width >= 60:
        for i in range(0, len(roles), 2):
            k1, _ = roles[i]
            k2, _ = roles[i + 1]
            col1 = f"{fg_esc(theme[k1])}██ {c_b1}{k1:<7} {c_b01}{theme[k1]}"
            col2 = f"{fg_esc(theme[k2])}██ {c_b1}{k2:<7} {c_b01}{theme[k2]}"
            lines.append(pad_preview_line(f"{col1}   {col2}", b03, width, left_pad=4))
    else:
        for k_acc, r_acc in roles:
            lines.append(
                pad_preview_line(
                    f"{fg_esc(theme[k_acc])}██ {c_b1}{k_acc:<7} {c_b01}{theme[k_acc]} {c_b0}({r_acc})",
                    b03,
                    width,
                    left_pad=4,
                )
            )

    lines.append(pad_preview_line(f"{c_b01}{'─' * rule_width}", b03, width))
    lines.append(pad_preview_line(f"{c_blu}Converged Semantic Code Preview:", b03, width))
    if width < 88:
        status_preview_line = (
            f"{c_blu}{session_icon} ide {c_b00}\uE0B1 {c_cyn}▸ 󰚩 agy {c_b01}· {c_b0} Editor {c_b01}· {c_b0} Shell"
            + (f"  {c_b00}\uE0B3 {c_ylw}{hmeta['badge']}" if (hmeta and width >= 64) else "")
        )
    else:
        status_preview_line = (
            f"{c_blu}{session_icon} ide {c_b00}\uE0B1 {c_cyn}▸ 󰚩 agy {c_b1}(Alt+a) {c_b01}· {c_b0} Editor (Alt+e) {c_b01}· {c_b0} Shell (Alt+t)"
            + (f"  {c_b00}\uE0B3 {c_ylw}{hmeta['badge']}" if hmeta else "")
        )
    lines.extend(
        [
            pad_preview_line(f"{c_b01}// {theme['THEME_LABEL']} — 6-Pillar Semantic Highlighting", b03, width, left_pad=4),
            pad_preview_line(f"{c_org}#include {c_cyn}<stdio.h>", b03, width, left_pad=4),
            pad_preview_line(f"{c_vio}import {c_vio}core::telemetry{c_b0};", b03, width, left_pad=4),
            pad_preview_line(f"{c_vio}#[derive(Clone)]", b03, width, left_pad=4),
            pad_preview_line(
                f"{c_grn}pub fn {c_blu}classify_sample{c_b0}(val: {c_grn}i64{c_b0}) -> {c_b0}Option<{c_grn}bool{c_b0}> {{",
                b03,
                width,
                left_pad=4,
            ),
            pad_preview_line(f"    {c_ylw}if {c_b0}val >= {c_mag}42 {c_b0}{{", b03, width, left_pad=4),
            pad_preview_line(f"    {c_red}-   {c_ylw}return {c_b0}Some({c_mag}false{c_b0});", b_red, width, left_pad=4),
            pad_preview_line(f"    {c_grn}+   {c_ylw}return {c_b0}Some({c_mag}true{c_b0});", b_grn, width, left_pad=4),
            pad_preview_line(f"    {c_b0}}}", b03, width, left_pad=4),
            pad_preview_line(f"    {c_b0}emit_log({c_cyn}\"status: %s\\n\"{c_b0});", b03, width, left_pad=4),
            pad_preview_line(f"    {c_ylw}return {c_mag}None{c_b0};", b03, width, left_pad=4),
            pad_preview_line(f"{c_b0}}}", b03, width, left_pad=4),
            pad_preview_line(status_preview_line, b02, width),
            pad_preview_line(
                f"{c_b0}{prompt_icon} {c_b01}\uE0B1 {c_blu}~/home-settings {c_b01}\uE0B1 {c_grn} main ✔ {c_grn}❯ {c_grn}theme {c_cyn}{theme['THEME_ID']}",
                b03,
                width,
                left_pad=2,
            ),
        ]
    )

    if in_fzf and target_height > len(lines):
        while len(lines) < target_height:
            lines.append(pad_preview_line("", b03, width))

    print("\n".join(lines))
    return 0


def list_themes(
    themes: dict[str, dict[str, str]],
    current_slug: str,
    plain: bool = False,
) -> int:
    """List all managed and user-defined themes with active marker and optional swatches."""
    use_color = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
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
        hmeta = HOLIDAY_META.get(slug)
        display_label = f"{hmeta['icon']} {t['THEME_LABEL']}" if hmeta else t["THEME_LABEL"]
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

    lines: list[str] = []
    for slug in ordered_theme_slugs(themes):
        t = themes[slug]
        active_tag = "(active)" if slug == current_slug else "        "
        strip = format_swatch_strip(t)
        hmeta = HOLIDAY_META.get(slug)
        display_label = f"{hmeta['icon']} {t['THEME_LABEL']}" if hmeta else t["THEME_LABEL"]
        if term_cols < 76:
            lines.append(f"{slug:<18}  {active_tag}  {strip}  {display_label}")
        else:
            lines.append(f"{slug:<18}  {active_tag}  {t['THEME_MODE']:<5}  {t['SOURCE']:<7}  {strip}  {display_label}")

    if term_cols < 90:
        height_arg = "--height=95%"
        preview_win = "--preview-window=down:58%:nowrap:noinfo"
    elif term_cols < 110:
        height_arg = "--height=90%"
        preview_win = "--preview-window=right:56%:nowrap:noinfo"
    else:
        height_arg = "--height=80%"
        preview_win = "--preview-window=right:60%:nowrap:noinfo"

    header_arg = (
        "--header=Enter: apply · Esc: cancel"
        if term_cols < 68
        else "--header=Select a color theme (Enter to apply, Esc to cancel)"
    )

    fzf_colors = build_fzf_color_opts(themes[current_slug], include_layout=False)
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
        fzf_colors,
    ]
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
