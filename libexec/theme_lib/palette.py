"""Palette schema, color contrast math, holiday calendar, and dynamic theme discovery."""

from __future__ import annotations

import math
import os
from pathlib import Path
import re
import sys
from typing import TYPE_CHECKING
import unicodedata

if TYPE_CHECKING:
    import datetime

CORE_COLOR_KEYS = [
    "BASE03",
    "BASE02",
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
]

ALL_COLOR_KEYS = CORE_COLOR_KEYS + [
    "BASE04",
    "MIX_GREEN",
    "MIX_RED",
    "MIX_YELLOW",
    "MIX_BLUE",
    "MIX_MAGENTA",
    "MIX_BASE1",
]

# Canonical 16-entry terminal ANSI palette mapping (indices 0 through 15).
# Index 8 is pinned to BASE01, index 9 (ANSI 91) to ORANGE, and index 13 (ANSI 95) to VIOLET.
ANSI_ROLE_ORDER = (
    "BASE02",
    "RED",
    "GREEN",
    "YELLOW",
    "BLUE",
    "MAGENTA",
    "CYAN",
    "BASE2",
    "BASE01",
    "ORANGE",
    "BASE01",
    "BASE00",
    "BASE0",
    "VIOLET",
    "BASE1",
    "BASE3",
)

SOLARIZED_DARK_DEFAULTS: dict[str, str] = {
    "THEME_ID": "solarized-dark",
    "THEME_LABEL": "Solarized Dark",
    "THEME_DESCRIPTION": "Ethan Schoonover precision CIELAB dark palette",
    "THEME_MODE": "dark",
    "THEME_CATEGORY": "classic",
    "THEME_ORDER": "10",
    "BAT_THEME_NAME": "Solarized-Dark-TrueColor",
    "BTOP_THEME_NAME": "solarized_dark",
    "GHOSTTY_THEME_NAME": "Solarized Dark",
    "BASE03": "#002B36",
    "BASE02": "#073642",
    "BASE04": "#002731",
    "BASE01": "#586E75",
    "BASE00": "#657B83",
    "BASE0": "#839496",
    "BASE1": "#93A1A1",
    "BASE2": "#EEE8D5",
    "BASE3": "#FDF6E3",
    "YELLOW": "#B58900",
    "ORANGE": "#CB4B16",
    "RED": "#DC322F",
    "MAGENTA": "#D33682",
    "VIOLET": "#6C71C4",
    "BLUE": "#268BD2",
    "CYAN": "#2AA198",
    "GREEN": "#859900",
    "MIX_GREEN": "#274C25",
    "MIX_RED": "#422D33",
    "MIX_YELLOW": "#364725",
    "MIX_BLUE": "#0B4764",
    "MIX_MAGENTA": "#3E2E4C",
    "MIX_BASE1": "#2C4E56",
}

SOLARIZED_LIGHT_DEFAULTS: dict[str, str] = {
    **SOLARIZED_DARK_DEFAULTS,
    "THEME_ID": "solarized-light",
    "THEME_LABEL": "Solarized Light",
    "THEME_DESCRIPTION": "Ethan Schoonover precision CIELAB light palette",
    "THEME_MODE": "light",
    "THEME_CATEGORY": "classic",
    "THEME_ORDER": "20",
    "BAT_THEME_NAME": "Solarized-Light-TrueColor",
    "BTOP_THEME_NAME": "solarized_light",
    "GHOSTTY_THEME_NAME": "Solarized Light",
    "BASE03": "#FDF6E3",
    "BASE02": "#EEE8D5",
    "BASE04": "#E6DFCA",
    "BASE01": "#93A1A1",
    "BASE00": "#839496",
    "BASE0": "#657B83",
    "BASE1": "#586E75",
    "BASE2": "#073642",
    "BASE3": "#002B36",
    "MIX_GREEN": "#E5ECD0",
    "MIX_RED": "#F6D8D3",
    "MIX_YELLOW": "#F0E4C0",
    "MIX_BLUE": "#D8E6EE",
    "MIX_MAGENTA": "#F3D9E4",
    "MIX_BASE1": "#E4DEC8",
}

HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
ASSIGN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$")
FIXED_MMDD_RE = re.compile(r"^(\d{2})-(\d{2})$")
NTH_WEEKDAY_RE = re.compile(r"^nth-weekday:(\d{2}):(-?\d+):([0-6])$")


def _default_repo_dir() -> Path:
    return Path(__file__).resolve().parents[2]


def _ascii_ghostty_name(label: str) -> str:
    """Normalize a display label into an ASCII-safe cross-platform Ghostty theme filename."""
    decomposed = unicodedata.normalize("NFKD", label).encode("ascii", "ignore").decode("ascii")
    cleaned = re.sub(r"['\".]+", "", decomposed)
    return re.sub(r"\s+", " ", cleaned).strip() or "Custom Theme"


def theme_sort_key(theme: dict[str, str]) -> tuple[int, int, int, str]:
    """Return canonical sort key: built-in classic, built-in holiday, then custom user themes."""
    src_rank = 0 if theme.get("SOURCE") == "builtin" else 1
    cat = theme.get("THEME_CATEGORY", "classic" if src_rank == 0 else "user")
    cat_rank = 0 if cat == "classic" else (1 if cat == "holiday" else 2)
    try:
        order_num = int(theme.get("THEME_ORDER", "9999"))
    except ValueError:
        order_num = 9999
    return (src_rank, cat_rank, order_num, theme["THEME_ID"])


def ordered_theme_slugs(themes: dict[str, dict[str, str]]) -> list[str]:
    """Return theme slugs sorted by canonical category, order, and identifier."""
    return [slug for slug, _ in sorted(themes.items(), key=lambda kv: theme_sort_key(kv[1]))]


def get_holiday_meta(theme: dict[str, str]) -> dict[str, str] | None:
    """Return holiday icon, badge, and banner metadata when defined on a theme."""
    icon = theme.get("HOLIDAY_ICON", "").strip()
    if not icon:
        return None
    label = theme["THEME_LABEL"]
    badge = theme.get("HOLIDAY_BADGE", "").strip() or f"{icon} {label}"
    banner = theme.get("HOLIDAY_BANNER", "").strip() or f"{icon}  {label.upper()}  {icon}"
    return {"icon": icon, "badge": badge, "banner": banner}


def compute_easter_date(year: int) -> datetime.date:
    """Return Gregorian Easter Sunday for the given calendar year."""
    import datetime

    a = year % 19
    b = year // 100
    c = year % 100
    d = b // 4
    e = b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i = c // 4
    k = c % 4
    l_val = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l_val) // 451
    month = (h + l_val - 7 * m + 114) // 31
    day = ((h + l_val - 7 * m + 114) % 31) + 1
    return datetime.date(year, month, day)


def compute_thanksgiving_date(year: int) -> datetime.date:
    """Return US Thanksgiving (fourth Thursday of November) for the given year."""
    import datetime

    nov1 = datetime.date(year, 11, 1)
    offset = (3 - nov1.weekday()) % 7
    return datetime.date(year, 11, 1 + offset + 21)


def compute_nth_weekday_date(year: int, month: int, nth: int, weekday: int) -> datetime.date:
    """Return the nth (1..5 or -1 for last) weekday (0=Mon..6=Sun) in a given month."""
    import calendar
    import datetime

    if nth == -1:
        last_day = calendar.monthrange(year, month)[1]
        last_dt = datetime.date(year, month, last_day)
        offset = (last_dt.weekday() - weekday) % 7
        return datetime.date(year, month, last_day - offset)
    if nth < 1 or nth > 5:
        raise ValueError(f"Invalid nth weekday occurrence '{nth}' (expected 1..5 or -1)")
    first_dt = datetime.date(year, month, 1)
    offset = (weekday - first_dt.weekday()) % 7
    day = 1 + offset + (nth - 1) * 7
    return datetime.date(year, month, day)


def resolve_holiday_rule_date(rule: str, year: int) -> datetime.date:
    """Evaluate a HOLIDAY_DATE rule ('MM-DD', 'easter', 'thanksgiving', or 'nth-weekday:MM:N:DOW')."""
    import calendar
    import datetime

    cleaned = rule.strip().lower()
    if cleaned == "easter":
        return compute_easter_date(year)
    if cleaned == "thanksgiving":
        return compute_thanksgiving_date(year)
    m_fixed = FIXED_MMDD_RE.match(cleaned)
    if m_fixed:
        month = int(m_fixed.group(1))
        day = int(m_fixed.group(2))
        if month == 2 and day == 29 and not calendar.isleap(year):
            day = 28
        return datetime.date(year, month, day)
    m_nth = NTH_WEEKDAY_RE.match(cleaned)
    if m_nth:
        return compute_nth_weekday_date(
            year,
            int(m_nth.group(1)),
            int(m_nth.group(2)),
            int(m_nth.group(3)),
        )
    raise ValueError(
        f"Invalid HOLIDAY_DATE '{rule}' (expected MM-DD, easter, thanksgiving, or nth-weekday:MM:N:DOW)"
    )


def get_holiday_schedule_for_year(
    year: int,
    themes: dict[str, dict[str, str]] | None = None,
    repo_dir: Path | None = None,
) -> list[tuple[datetime.date, str]]:
    """Return the chronological holiday theme schedule discovered from theme definitions."""
    active_themes = themes if themes is not None else discover_themes(repo_dir or _default_repo_dir())
    schedule: list[tuple[datetime.date, str]] = []
    for slug in ordered_theme_slugs(active_themes):
        t = active_themes[slug]
        rule = t.get("HOLIDAY_DATE", "").strip()
        if rule:
            schedule.append((resolve_holiday_rule_date(rule, year), slug))
    schedule.sort(key=lambda pair: (pair[0], pair[1]))
    return schedule


def resolve_nearest_holiday_slug(
    today: datetime.date | None = None,
    themes: dict[str, dict[str, str]] | None = None,
    repo_dir: Path | None = None,
) -> str:
    """Resolve the active or nearest upcoming holiday theme slug."""
    import datetime

    if today is None:
        override = os.environ.get("THEME_HOLIDAY_DATE", "").strip()
        today = datetime.date.fromisoformat(override) if override else datetime.date.today()
    active_themes = themes if themes is not None else discover_themes(repo_dir or _default_repo_dir())
    candidates = get_holiday_schedule_for_year(today.year, active_themes) + get_holiday_schedule_for_year(
        today.year + 1, active_themes
    )
    if not candidates:
        return "solarized-dark"
    upcoming = sorted((d, slug) for d, slug in candidates if d >= today)
    return upcoming[0][1] if upcoming else candidates[0][1]


def hex_to_rgb(hex_str: str) -> tuple[int, int, int]:
    """Convert a #RRGGBB hex string into an (R, G, B) integer tuple."""
    h = hex_str.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def rgb_semicolon(hex_str: str) -> str:
    """Format a #RRGGBB hex string as semicolon-delimited SGR TrueColor channels."""
    r, g, b = hex_to_rgb(hex_str)
    return f"{r};{g};{b}"


def blend_hex(fg_hex: str, bg_hex: str, alpha: float = 0.20) -> str:
    """Alpha-blend foreground hex onto background hex and return uppercase #RRGGBB."""
    fr, fg, fb = hex_to_rgb(fg_hex)
    br, bg_g, bb = hex_to_rgb(bg_hex)
    r = int(round(fr * alpha + br * (1.0 - alpha)))
    g = int(round(fg * alpha + bg_g * (1.0 - alpha)))
    b = int(round(fb * alpha + bb * (1.0 - alpha)))
    return f"#{max(0, min(255, r)):02X}{max(0, min(255, g)):02X}{max(0, min(255, b)):02X}"


def relative_luminance(hex_str: str) -> float:
    """Compute WCAG 2.x relative sRGB luminance for a #RRGGBB color."""
    def _linearize(channel: int) -> float:
        c = channel / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = hex_to_rgb(hex_str)
    return 0.2126 * _linearize(r) + 0.7152 * _linearize(g) + 0.0722 * _linearize(b)


def contrast_ratio(hex_a: str, hex_b: str) -> float:
    """Compute WCAG contrast ratio between two #RRGGBB colors."""
    lum_a = relative_luminance(hex_a)
    lum_b = relative_luminance(hex_b)
    return (max(lum_a, lum_b) + 0.05) / (min(lum_a, lum_b) + 0.05)


def rgb_distance(hex_a: str, hex_b: str) -> float:
    """Compute redmean-weighted perceptual RGB distance between two #RRGGBB colors."""
    r1, g1, b1 = hex_to_rgb(hex_a)
    r2, g2, b2 = hex_to_rgb(hex_b)
    rm = (r1 + r2) / 2.0
    dr, dg, db = r1 - r2, g1 - g2, b1 - b2
    return math.sqrt((2 + rm / 256.0) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256.0) * db * db)


def hue_difference(hex_a: str, hex_b: str) -> float:
    """Compute circular HSV hue angle separation in degrees (0.0 to 180.0)."""
    import colorsys

    r1, g1, b1 = [x / 255.0 for x in hex_to_rgb(hex_a)]
    r2, g2, b2 = [x / 255.0 for x in hex_to_rgb(hex_b)]
    hue1, _, _ = colorsys.rgb_to_hsv(r1, g1, b1)
    hue2, _, _ = colorsys.rgb_to_hsv(r2, g2, b2)
    diff = abs(hue1 - hue2) * 360.0
    return min(diff, 360.0 - diff)


def ansi_palette_hex_list(theme: dict[str, str], lowercase: bool = False) -> list[str]:
    """Return the ordered 16-color terminal ANSI palette for the given theme."""
    entries = [theme[role] for role in ANSI_ROLE_ORDER]
    return [val.lower() for val in entries] if lowercase else entries


def get_xdg_config_home() -> Path:
    """Resolve XDG_CONFIG_HOME or fall back to $HOME/.config."""
    xdg = os.environ.get("XDG_CONFIG_HOME", "").strip()
    if xdg:
        return Path(xdg)
    return Path(os.environ.get("HOME", str(Path.home()))) / ".config"


def get_user_themes_dirs() -> list[Path]:
    """Return ordered user custom theme search directories without duplicates."""
    dirs: list[Path] = []
    override = os.environ.get("HOME_SETTINGS_USER_THEMES_DIR", "").strip()
    if override:
        dirs.append(Path(override))
    cfg = get_xdg_config_home()
    dirs.append(cfg / "themes")
    dirs.append(cfg / "home-settings" / "themes")
    seen: set[str] = set()
    unique: list[Path] = []
    for d in dirs:
        s = str(d)
        if s not in seen:
            seen.add(s)
            unique.append(d)
    return unique


def slug_to_label(slug: str) -> str:
    """Convert a kebab-case or snake_case theme slug into a Title Case display label."""
    return " ".join(part.capitalize() for part in re.split(r"[-_]+", slug) if part)


def parse_theme_kv(path: Path, strict_lines: bool = False) -> dict[str, str]:
    """Parse KEY=VALUE assignments from a .theme or .conf file."""
    raw: dict[str, str] = {}
    with open(path, encoding="utf-8") as fh:
        for line_num, line in enumerate(fh, 1):
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            if s.startswith("export ") or s.startswith("export\t"):
                s = s[6:].strip()
            if strict_lines:
                if "=" not in s:
                    raise ValueError(f"{path}:{line_num}: invalid line (expected KEY=VALUE): {s}")
                k, v = s.split("=", 1)
                k, v = k.strip(), v.strip()
            else:
                m = ASSIGN_RE.match(s)
                if not m:
                    continue
                k, v = m.group(1), m.group(2).strip()
            if v and v[0] in ('"', "'"):
                q = v[0]
                end_idx = v.find(q, 1)
                if end_idx != -1:
                    rest = v[end_idx + 1 :].strip()
                    if not rest or rest.startswith("#"):
                        v = v[1:end_idx]
            else:
                v = re.split(r"\s+#", v, maxsplit=1)[0].strip()
            raw[k] = v
    return raw


def _build_normalized_theme(
    raw: dict[str, str],
    origin_label: str,
    default_slug: str,
    source: str,
) -> dict[str, str]:
    """Validate and materialize a complete 23-color theme dictionary from raw KV pairs."""
    mode = raw.get("THEME_MODE", "dark").strip().lower()
    if mode not in ("dark", "light"):
        raise ValueError(f"{origin_label}: invalid THEME_MODE '{mode}' (expected 'dark' or 'light')")

    base_defaults = SOLARIZED_LIGHT_DEFAULTS if mode == "light" else SOLARIZED_DARK_DEFAULTS
    slug = raw.get("THEME_ID", default_slug).strip().lower().replace("_", "-")
    label = raw.get("THEME_LABEL", "").strip() or slug_to_label(slug)
    desc = raw.get("THEME_DESCRIPTION", f"Custom {mode} color theme ({label})").strip()

    holiday_date = raw.get("HOLIDAY_DATE", "").strip().lower()
    if holiday_date:
        resolve_holiday_rule_date(holiday_date, 2026)

    category = raw.get("THEME_CATEGORY", "").strip().lower()
    if not category:
        if holiday_date:
            category = "holiday"
        elif source == "builtin":
            category = "classic"
        else:
            category = "user"
    if category not in ("classic", "holiday", "user"):
        raise ValueError(
            f"{origin_label}: invalid THEME_CATEGORY '{category}' (expected 'classic', 'holiday', or 'user')"
        )

    raw_order = raw.get("THEME_ORDER", "9999").strip()
    try:
        order_int = int(raw_order)
    except ValueError as exc:
        raise ValueError(f"{origin_label}: invalid integer THEME_ORDER '{raw_order}'") from exc

    theme: dict[str, str] = {
        "THEME_ID": slug,
        "THEME_LABEL": label,
        "THEME_DESCRIPTION": desc,
        "THEME_MODE": mode,
        "THEME_CATEGORY": category,
        "THEME_ORDER": str(order_int),
        "HOLIDAY_DATE": holiday_date,
        "HOLIDAY_ICON": raw.get("HOLIDAY_ICON", "").strip(),
        "HOLIDAY_BADGE": raw.get("HOLIDAY_BADGE", "").strip(),
        "HOLIDAY_BANNER": raw.get("HOLIDAY_BANNER", "").strip(),
        "SOURCE": source,
        "PATH": origin_label,
    }

    for key in CORE_COLOR_KEYS:
        val = raw.get(key, base_defaults[key]).strip().upper()
        if not HEX_RE.match(val):
            raise ValueError(f"{origin_label}: invalid hex color for {key}: '{val}' (expected #RRGGBB)")
        theme[key] = val

    base03 = theme["BASE03"]
    base02 = theme["BASE02"]
    default_computed = {
        "BASE04": blend_hex(base02, base03, 0.50),
        "MIX_GREEN": blend_hex(theme["GREEN"], base03, 0.18),
        "MIX_RED": blend_hex(theme["RED"], base03, 0.18),
        "MIX_YELLOW": blend_hex(theme["YELLOW"], base03, 0.20),
        "MIX_BLUE": blend_hex(theme["BLUE"], base03, 0.22),
        "MIX_MAGENTA": blend_hex(theme["MAGENTA"], base03, 0.20),
        "MIX_BASE1": blend_hex(theme["BASE1"], base03, 0.16),
    }
    for key, comp_val in default_computed.items():
        val = raw.get(key, comp_val).strip().upper()
        if not HEX_RE.match(val):
            raise ValueError(f"{origin_label}: invalid hex color for {key}: '{val}' (expected #RRGGBB)")
        theme[key] = val

    pascal_slug = "-".join(part.capitalize() for part in re.split(r"[-_]+", slug) if part)
    snake_slug = re.sub(r"[^a-z0-9]+", "_", slug).strip("_")
    theme["BAT_THEME_NAME"] = raw.get("BAT_THEME_NAME", f"{pascal_slug}-TrueColor").strip()
    theme["BTOP_THEME_NAME"] = raw.get("BTOP_THEME_NAME", snake_slug).strip()
    theme["GHOSTTY_THEME_NAME"] = raw.get("GHOSTTY_THEME_NAME", _ascii_ghostty_name(label)).strip()
    return theme


def parse_theme_file(
    path: Path,
    default_slug: str | None = None,
    source: str = "builtin",
) -> dict[str, str]:
    """Parse and strictly validate a built-in or user theme definition file."""
    raw = parse_theme_kv(path, strict_lines=True)
    return _build_normalized_theme(
        raw,
        origin_label=str(path),
        default_slug=default_slug or path.stem,
        source=source,
    )


def discover_builtin_themes(repo_dir: Path) -> dict[str, dict[str, str]]:
    """Discover and sort all built-in repository themes directly from colors/themes/*.theme."""
    raw_builtin: dict[str, dict[str, str]] = {}
    managed_dir = repo_dir / "colors" / "themes"
    if managed_dir.is_dir():
        for p in sorted(managed_dir.glob("*.theme")):
            if not p.is_file():
                continue
            t = parse_theme_file(p, default_slug=p.stem.lower(), source="builtin")
            raw_builtin[t["THEME_ID"]] = t
    return {slug: raw_builtin[slug] for slug in ordered_theme_slugs(raw_builtin)}


def discover_themes(repo_dir: Path) -> dict[str, dict[str, str]]:
    """Discover all built-in repository themes and user-defined custom themes in canonical order."""
    themes = discover_builtin_themes(repo_dir)
    for udir in get_user_themes_dirs():
        if not udir.is_dir():
            continue
        candidates = sorted(list(udir.glob("*.theme")) + list(udir.glob("*.conf")))
        for p in candidates:
            if not p.is_file():
                continue
            t = parse_theme_file(p, default_slug=p.stem.lower(), source="user")
            themes[t["THEME_ID"]] = t
    return {slug: themes[slug] for slug in ordered_theme_slugs(themes)}


def resolve_single_theme(repo_dir: Path, raw_name: str) -> dict[str, str]:
    """Resolve a single theme by slug for standalone terminal profile provisioners."""
    cleaned = raw_name.strip()
    slug = (cleaned or "solarized-dark").lower().replace("_", "-")
    if not SLUG_RE.match(slug):
        raise ValueError(f"Unknown theme '{cleaned}'")

    user_dirs = get_user_themes_dirs()
    parsed: dict[str, str] | None = None
    origin = slug
    source = "user"

    for udir in user_dirs:
        for ext in (".theme", ".conf"):
            cand = udir / f"{slug}{ext}"
            if cand.is_file():
                parsed = parse_theme_kv(cand, strict_lines=False)
                origin = str(cand)
                break
        if parsed is not None:
            break

    if parsed is None:
        for udir in user_dirs:
            if not udir.is_dir():
                continue
            for cand in sorted(list(udir.glob("*.theme")) + list(udir.glob("*.conf"))):
                if not cand.is_file():
                    continue
                kv = parse_theme_kv(cand, strict_lines=False)
                cand_id = kv.get("THEME_ID", cand.stem).strip().lower().replace("_", "-")
                if cand_id == slug:
                    parsed = kv
                    origin = str(cand)
                    break
            if parsed is not None:
                break

    if parsed is None:
        managed_dir = repo_dir / "colors" / "themes"
        builtin_cand = managed_dir / f"{slug}.theme"
        if builtin_cand.is_file():
            parsed = parse_theme_kv(builtin_cand, strict_lines=False)
            origin = str(builtin_cand)
            source = "builtin"
        elif managed_dir.is_dir():
            for cand in sorted(managed_dir.glob("*.theme")):
                kv = parse_theme_kv(cand, strict_lines=False)
                cand_id = kv.get("THEME_ID", cand.stem).strip().lower().replace("_", "-")
                if cand_id == slug:
                    parsed = kv
                    origin = str(cand)
                    source = "builtin"
                    break

    if parsed is None:
        active_snap = get_xdg_config_home() / "home-settings" / "active-theme.theme"
        if active_snap.is_file():
            kv = parse_theme_kv(active_snap, strict_lines=False)
            if kv.get("THEME_ID", "").strip().lower().replace("_", "-") == slug:
                parsed = kv
                origin = str(active_snap)
                source = "active"

    if parsed is None:
        if slug == "solarized-dark":
            parsed = {"THEME_ID": "solarized-dark", "THEME_LABEL": "Solarized Dark"}
            source = "builtin"
        else:
            raise ValueError(f"Unknown theme '{cleaned or slug}'")

    return _build_normalized_theme(parsed, origin_label=origin, default_slug=slug, source=source)


def get_current_theme_slug(themes: dict[str, dict[str, str]]) -> str:
    """Determine the active theme slug from XDG state or environment fallback."""
    state_file = get_xdg_config_home() / "home-settings" / "theme"
    if state_file.is_file():
        try:
            saved = state_file.read_text(encoding="utf-8").strip().lower()
            if saved in themes:
                return saved
        except OSError:
            pass
    env_theme = os.environ.get("HOME_SETTINGS_THEME", "").strip().lower()
    if env_theme and env_theme in themes:
        return env_theme
    return "solarized-dark"


def create_user_theme(
    new_name: str,
    base_slug: str,
    themes: dict[str, dict[str, str]],
    force: bool = False,
) -> int:
    """Scaffold a new custom user theme file from an existing base theme."""
    slug = new_name.strip().lower().replace("_", "-")
    if not SLUG_RE.match(slug):
        sys.stderr.write(
            f"theme: invalid theme name '{new_name}' (use lowercase letters, numbers, and hyphens)\n"
        )
        return 1
    base_key = base_slug.strip().lower().replace("_", "-")
    if base_key not in themes:
        sys.stderr.write(f"theme: unknown base theme '{base_slug}'\n")
        return 1
    base = themes[base_key]
    user_dir = get_user_themes_dirs()[0]
    user_dir.mkdir(parents=True, exist_ok=True)
    target_path = user_dir / f"{slug}.theme"
    if target_path.exists() and not force:
        sys.stderr.write(
            f"theme: custom theme file already exists: {target_path} (use --force to overwrite)\n"
        )
        return 1

    label = slug_to_label(slug)
    pascal_slug = "-".join(part.capitalize() for part in slug.split("-") if part)
    snake_slug = slug.replace("-", "_")
    ghostty_name = _ascii_ghostty_name(label)
    content = f"""# Custom User Theme: {slug} (based on {base['THEME_ID']})
THEME_ID="{slug}"
THEME_LABEL="{label}"
THEME_DESCRIPTION="Custom {base['THEME_MODE']} theme based on {base['THEME_LABEL']}"
THEME_MODE="{base['THEME_MODE']}"
BAT_THEME_NAME="{pascal_slug}-TrueColor"
BTOP_THEME_NAME="{snake_slug}"
GHOSTTY_THEME_NAME="{ghostty_name}"

# Monotone Surface & Content Ramp
BASE03="{base['BASE03']}"
BASE02="{base['BASE02']}"
BASE04="{base['BASE04']}"
BASE01="{base['BASE01']}"
BASE00="{base['BASE00']}"
BASE0="{base['BASE0']}"
BASE1="{base['BASE1']}"
BASE2="{base['BASE2']}"
BASE3="{base['BASE3']}"

# Semantic Accent Palette
YELLOW="{base['YELLOW']}"
ORANGE="{base['ORANGE']}"
RED="{base['RED']}"
MAGENTA="{base['MAGENTA']}"
VIOLET="{base['VIOLET']}"
BLUE="{base['BLUE']}"
CYAN="{base['CYAN']}"
GREEN="{base['GREEN']}"

# Diff & Search Surface Tints
MIX_GREEN="{base['MIX_GREEN']}"
MIX_RED="{base['MIX_RED']}"
MIX_YELLOW="{base['MIX_YELLOW']}"
MIX_BLUE="{base['MIX_BLUE']}"
MIX_MAGENTA="{base['MIX_MAGENTA']}"
MIX_BASE1="{base['MIX_BASE1']}"
"""
    target_path.write_text(content, encoding="utf-8")
    print(str(target_path))
    return 0
