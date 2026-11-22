"""Deterministic repository asset and standalone target synchronizer for colors/themes/*.theme."""

from __future__ import annotations

from pathlib import Path
import re

from theme_lib.generators import (
    generate_btop_theme_text,
    generate_ghostty_theme_text,
    generate_tmtheme_text,
)
from theme_lib.palette import (
    FIXED_MMDD_RE,
    NTH_WEEKDAY_RE,
    discover_builtin_themes,
    ordered_theme_slugs,
)

SPEC_COLOR_KEYS: tuple[str, ...] = (
    "BASE03",
    "BASE02",
    "BASE04",
    "BASE01",
    "BASE00",
    "BASE0",
    "BASE1",
    "BASE2",
    "BASE3",
    "YELLOW",
    "ORANGE",
    "RED",
    "MAGENTA",
    "VIOLET",
    "BLUE",
    "CYAN",
    "GREEN",
    "MIX_GREEN",
    "MIX_RED",
    "MIX_YELLOW",
    "MIX_BLUE",
    "MIX_MAGENTA",
    "MIX_BASE1",
)

SPEC_FIELD_ORDER: tuple[str, ...] = (
    "THEME_LABEL",
    "THEME_MODE",
    "BAT_THEME_NAME",
    *SPEC_COLOR_KEYS,
)


def _pack_spec_fields(theme: dict[str, str]) -> str:
    return "|".join(theme[k] for k in SPEC_FIELD_ORDER)


def _vim_quote(text: str) -> str:
    if "'" not in text:
        return f"'{text}'"
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _bash_dq_escape(text: str) -> str:
    return (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("$", "\\$")
        .replace("`", "\\`")
    )


def _replace_bounded_block(text: str, begin_marker: str, end_marker: str, body: str) -> str:
    pattern = re.compile(
        rf"(^[ \t]*{re.escape(begin_marker)}\n).*?(^[ \t]*{re.escape(end_marker)}$)",
        re.DOTALL | re.MULTILINE,
    )
    if not pattern.search(text):
        raise ValueError(f"Missing bounded markers '{begin_marker}' .. '{end_marker}'")
    clean_body = body.rstrip("\n") + "\n"
    return pattern.sub(lambda m: f"{m.group(1)}{clean_body}{m.group(2)}", text, count=1)


def _format_backtick_list(slugs: list[str], mark_default: bool = False) -> str:
    items = [
        f"`{s}` (default)" if (mark_default and s == "solarized-dark") else f"`{s}`"
        for s in slugs
    ]
    if not items:
        return ""
    if len(items) == 1:
        return items[0]
    if len(items) == 2:
        return f"{items[0]} and {items[1]}"
    return f"{', '.join(items[:-1])}, and {items[-1]}"


def _build_vim_builtin_block(themes: dict[str, dict[str, str]], slugs: list[str]) -> str:
    order_lines: list[str] = ["let s:builtin_theme_order = ["]
    chunk: list[str] = []
    for idx, slug in enumerate(slugs):
        suffix = "," if idx + 1 < len(slugs) else ""
        chunk.append(f"'{slug}'{suffix}")
        if len(chunk) == 4 or idx + 1 == len(slugs):
            order_lines.append("    \\ " + " ".join(chunk))
            chunk = []
    order_lines.append("    \\ ]")

    max_key_len = max((len(s) + 3 for s in slugs), default=18)
    dict_lines: list[str] = [
        "",
        '" Compact 26-field built-in palette table (1:1 with colors/themes/*.theme for standalone servers):',
        '" LABEL|MODE|BAT_THEME|B03|B02|B04|B01|B00|B0|B1|B2|B3|YEL|ORA|RED|MAG|VIO|BLU|CYA|GRN|MGRN|MRED|MYEL|MBLU|MMAG|MB1',
        "let s:builtin_themes = {",
    ]
    for idx, slug in enumerate(slugs):
        key_tok = f"'{slug}':"
        comma = "," if idx + 1 < len(slugs) else ""
        val_tok = _vim_quote(_pack_spec_fields(themes[slug]))
        dict_lines.append(f"    \\ {key_tok:<{max_key_len}} {val_tok}{comma}")
    dict_lines.append("    \\ }")
    return "\n".join(order_lines + dict_lines)


def _vim_holiday_expr(rule: str) -> str:
    cleaned = rule.strip().lower()
    if cleaned == "easter":
        return "a:year * 10000 + l:em * 100 + l:ed"
    if cleaned == "thanksgiving":
        return "a:year * 10000 + 1100 + l:td"
    m_fixed = FIXED_MMDD_RE.match(cleaned)
    if m_fixed:
        mmdd = int(m_fixed.group(1)) * 100 + int(m_fixed.group(2))
        return f"a:year * 10000 + {mmdd}"
    m_nth = NTH_WEEKDAY_RE.match(cleaned)
    if m_nth:
        mon = int(m_nth.group(1))
        nth = int(m_nth.group(2))
        dow = int(m_nth.group(3))
        return f"a:year * 10000 + {mon * 100} + s:NthWeekdayOfMonth(a:year, {mon}, {nth}, {dow})"
    raise ValueError(f"Unsupported holiday rule for Vim codegen: {rule}")


def _build_vim_holiday_block(themes: dict[str, dict[str, str]], slugs: list[str]) -> str:
    entries: list[tuple[str, str]] = []
    for slug in slugs:
        rule = themes[slug].get("HOLIDAY_DATE", "").strip()
        if rule:
            entries.append((_vim_holiday_expr(rule), slug))
    lines = ["    return ["]
    for idx, (expr, slug) in enumerate(entries):
        comma = "," if idx + 1 < len(entries) else ""
        lines.append(f"        \\ [{expr}, '{slug}']{comma}")
    lines.append("        \\ ]")
    return "\n".join(lines)


def _build_bash_palette_block(themes: dict[str, dict[str, str]], slugs: list[str]) -> str:
    lines: list[str] = ["_HS_BUILTIN_THEME_ORDER=("]
    chunk: list[str] = []
    for idx, slug in enumerate(slugs):
        chunk.append(slug)
        if len(chunk) == 4 or idx + 1 == len(slugs):
            lines.append("    " + " ".join(chunk))
            chunk = []
    lines.append(")")
    lines.append("")
    lines.append("# Compact 26-field built-in palette lookup (1:1 with colors/themes/*.theme):")
    lines.append("# LABEL|MODE|BAT_THEME|B03|B02|B04|B01|B00|B0|B1|B2|B3|YEL|ORA|RED|MAG|VIO|BLU|CYA|GRN|MGRN|MRED|MYEL|MBLU|MMAG|MB1")
    lines.append("_hs_bash_builtin_spec() {")
    lines.append('    REPLY=""')
    lines.append('    case "${1:-}" in')
    max_pat = max((len(s) + 1 for s in slugs), default=18)
    for slug in slugs:
        pat = f"{slug})"
        spec = _bash_dq_escape(_pack_spec_fields(themes[slug]))
        lines.append(f'        {pat:<{max_pat}} REPLY="{spec}" ;;')
    lines.append("        *) return 1 ;;")
    lines.append("    esac")
    lines.append("    return 0")
    lines.append("}")
    lines.append("")
    lines.append("_hs_bash_builtin_holiday_icon() {")
    lines.append('    REPLY=""')
    lines.append('    case "${1:-}" in')
    h_slugs = [s for s in slugs if themes[s].get("HOLIDAY_ICON", "").strip()]
    max_hpat = max((len(s) + 1 for s in h_slugs), default=18)
    for slug in h_slugs:
        pat = f"{slug})"
        icon = _bash_dq_escape(themes[slug]["HOLIDAY_ICON"])
        lines.append(f'        {pat:<{max_hpat}} REPLY="{icon}" ;;')
    lines.append("        *) return 1 ;;")
    lines.append("    esac")
    lines.append("    return 0")
    lines.append("}")
    return "\n".join(lines)


def _bash_holiday_expr(rule: str) -> str:
    cleaned = rule.strip().lower()
    if cleaned == "easter":
        return "$easter_num"
    if cleaned == "thanksgiving":
        return "$tg_num"
    m_fixed = FIXED_MMDD_RE.match(cleaned)
    if m_fixed:
        mmdd = int(m_fixed.group(1)) * 100 + int(m_fixed.group(2))
        return f"$(( cy * 10000 + {mmdd} ))"
    m_nth = NTH_WEEKDAY_RE.match(cleaned)
    if m_nth:
        mon = int(m_nth.group(1))
        nth = int(m_nth.group(2))
        dow = int(m_nth.group(3))
        return f"$(_hs_bash_nth_weekday_num \"$cy\" {mon} {nth} {dow})"
    raise ValueError(f"Unsupported holiday rule for Bash codegen: {rule}")


def _build_bash_holiday_block(themes: dict[str, dict[str, str]], slugs: list[str]) -> str:
    lines: list[str] = []
    for slug in slugs:
        rule = themes[slug].get("HOLIDAY_DATE", "").strip()
        if not rule:
            continue
        expr = _bash_holiday_expr(rule)
        lines.append(
            f'        cand_num={expr}; if [ "$cand_num" -ge "$today_num" ] && [ "$cand_num" -lt "$best_num" ]; then best_num="$cand_num"; best_slug="{slug}"; fi'
        )
    return "\n".join(lines)


def _build_zsh_fallback_block(slugs: list[str]) -> str:
    return f"        themes=({' '.join(slugs)})"


def _build_readme_catalog_block(classic_slugs: list[str], holiday_slugs: list[str]) -> str:
    total = len(classic_slugs) + len(holiday_slugs)
    classic_str = _format_backtick_list(classic_slugs, mark_default=True)
    lines = [
        f"- **Built-in palettes ({total} managed themes)**:",
        f"  - **Classic developer palettes ({len(classic_slugs)})**: {classic_str}.",
    ]
    if holiday_slugs:
        holiday_str = _format_backtick_list(holiday_slugs, mark_default=False)
        lines.append(f"  - **Major US Holiday palettes ({len(holiday_slugs)})**: {holiday_str}.")
    return "\n".join(lines)


def _build_color_arch_catalog_block(classic_slugs: list[str], holiday_slugs: list[str]) -> str:
    classic_str = _format_backtick_list(classic_slugs, mark_default=False)
    text = (
        f"The {len(classic_slugs)} classic daily-driver themes ({classic_str}) preserve strict "
        "physical hue-to-slot alignment and strictly monotonic `base03` through `base3` neutral ramps."
    )
    if holiday_slugs:
        holiday_str = _format_backtick_list(holiday_slugs, mark_default=False)
        text += (
            f" The {len(holiday_slugs)} US Holiday themes ({holiday_str}) keep the same AST token "
            "partitioning and pairwise semantic separation—guaranteeing `GREEN` valid commands, "
            "`YELLOW` control flow, and `RED` errors never collide and `MIX_GREEN` and `MIX_RED` "
            "retain green versus red diff polarity—while intentionally remapping high-visibility "
            "foreground slots and prompt or Tmux emblems to each holiday's signature colors."
        )
    return text


def sync_managed_repo_assets(repo_dir: Path, check_only: bool = False) -> list[str]:
    """Synchronize or verify all derived repository theme files and standalone fallback blocks."""
    drift: list[str] = []
    themes = discover_builtin_themes(repo_dir)
    slugs = ordered_theme_slugs(themes)
    classic_slugs = [s for s in slugs if themes[s].get("THEME_CATEGORY") == "classic"]
    holiday_slugs = [s for s in slugs if themes[s].get("THEME_CATEGORY") == "holiday"]

    def _sync_file(path: Path, expected: str) -> None:
        rel = str(path.relative_to(repo_dir))
        current = path.read_text(encoding="utf-8") if path.is_file() else None
        if current != expected:
            drift.append(rel)
            if not check_only:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(expected, encoding="utf-8")

    def _prune_file(path: Path) -> None:
        rel = str(path.relative_to(repo_dir))
        drift.append(f"{rel} (orphaned)")
        if not check_only:
            path.unlink()

    colors_dir = repo_dir / "colors"
    base_tmtheme_path = colors_dir / "Solarized-Dark-TrueColor.tmTheme"
    if base_tmtheme_path.is_file():
        base_tmtheme = base_tmtheme_path.read_text(encoding="utf-8")
        expected_tm_names = {"Solarized-Dark-TrueColor.tmTheme"}
        for slug in slugs:
            t = themes[slug]
            tm_name = f"{t['BAT_THEME_NAME']}.tmTheme"
            expected_tm_names.add(tm_name)
            if slug != "solarized-dark":
                _sync_file(colors_dir / tm_name, generate_tmtheme_text(base_tmtheme, t))
        for existing_tm in sorted(colors_dir.glob("*.tmTheme")):
            if existing_tm.name not in expected_tm_names:
                _prune_file(existing_tm)

    btop_themes_dir = repo_dir / "dotfiles" / ".config" / "btop" / "themes"
    if btop_themes_dir.is_dir() or not check_only:
        expected_btop_names = {"solarized_dark.theme"}
        for slug in slugs:
            t = themes[slug]
            btop_name = f"{t['BTOP_THEME_NAME']}.theme"
            expected_btop_names.add(btop_name)
            if slug != "solarized-dark":
                _sync_file(btop_themes_dir / btop_name, generate_btop_theme_text(t))
        if btop_themes_dir.is_dir():
            for existing_bt in sorted(btop_themes_dir.glob("*.theme")):
                if existing_bt.name not in expected_btop_names:
                    _prune_file(existing_bt)

    ghostty_themes_dir = repo_dir / "dotfiles" / ".config" / "ghostty" / "themes"
    if ghostty_themes_dir.is_dir() or not check_only:
        expected_ghostty_names: set[str] = set()
        for slug in slugs:
            t = themes[slug]
            gt_name = t["GHOSTTY_THEME_NAME"]
            expected_ghostty_names.add(gt_name)
            _sync_file(ghostty_themes_dir / gt_name, generate_ghostty_theme_text(t))
        if ghostty_themes_dir.is_dir():
            for existing_gt in sorted(ghostty_themes_dir.iterdir()):
                if existing_gt.is_file() and existing_gt.name not in expected_ghostty_names:
                    _prune_file(existing_gt)

    vimrc_path = repo_dir / "dotfiles" / ".vimrc"
    if vimrc_path.is_file():
        vimrc_src = vimrc_path.read_text(encoding="utf-8")
        updated_vimrc = _replace_bounded_block(
            vimrc_src,
            '" BEGIN GENERATED BUILTIN THEMES',
            '" END GENERATED BUILTIN THEMES',
            _build_vim_builtin_block(themes, slugs),
        )
        updated_vimrc = _replace_bounded_block(
            updated_vimrc,
            '" BEGIN GENERATED HOLIDAY SCHEDULE',
            '" END GENERATED HOLIDAY SCHEDULE',
            _build_vim_holiday_block(themes, slugs),
        )
        _sync_file(vimrc_path, updated_vimrc)

    bash_palette_path = repo_dir / "dotfiles" / ".config" / "shell" / "bash-palette.sh"
    if bash_palette_path.is_file():
        bp_src = bash_palette_path.read_text(encoding="utf-8")
        updated_bp = _replace_bounded_block(
            bp_src,
            "# BEGIN GENERATED BUILTIN THEMES",
            "# END GENERATED BUILTIN THEMES",
            _build_bash_palette_block(themes, slugs),
        )
        _sync_file(bash_palette_path, updated_bp)

    bash_cli_path = repo_dir / "dotfiles" / ".config" / "shell" / "bash-theme-cli.sh"
    if bash_cli_path.is_file():
        bc_src = bash_cli_path.read_text(encoding="utf-8")
        updated_bc = _replace_bounded_block(
            bc_src,
            "# BEGIN GENERATED HOLIDAY SCHEDULE",
            "# END GENERATED HOLIDAY SCHEDULE",
            _build_bash_holiday_block(themes, slugs),
        )
        _sync_file(bash_cli_path, updated_bc)

    zsh_comp_path = repo_dir / "dotfiles" / ".zsh-completions"
    if zsh_comp_path.is_file():
        zc_src = zsh_comp_path.read_text(encoding="utf-8")
        updated_zc = _replace_bounded_block(
            zc_src,
            "# BEGIN GENERATED BUILTIN THEMES",
            "# END GENERATED BUILTIN THEMES",
            _build_zsh_fallback_block(slugs),
        )
        _sync_file(zsh_comp_path, updated_zc)

    readme_path = repo_dir / "README.md"
    if readme_path.is_file():
        readme_src = readme_path.read_text(encoding="utf-8")
        if "<!-- BEGIN GENERATED THEME CATALOG -->" in readme_src:
            updated_readme = _replace_bounded_block(
                readme_src,
                "<!-- BEGIN GENERATED THEME CATALOG -->",
                "<!-- END GENERATED THEME CATALOG -->",
                _build_readme_catalog_block(classic_slugs, holiday_slugs),
            )
            _sync_file(readme_path, updated_readme)

    color_arch_path = repo_dir / "docs" / "color-architecture.md"
    if color_arch_path.is_file():
        ca_src = color_arch_path.read_text(encoding="utf-8")
        if "<!-- BEGIN GENERATED THEME CATALOG -->" in ca_src:
            updated_ca = _replace_bounded_block(
                ca_src,
                "<!-- BEGIN GENERATED THEME CATALOG -->",
                "<!-- END GENERATED THEME CATALOG -->",
                _build_color_arch_catalog_block(classic_slugs, holiday_slugs),
            )
            _sync_file(color_arch_path, updated_ca)

    return drift
