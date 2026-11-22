"""Active `home-settings` theme palette loader and `fzf` TrueColor environment builder."""

from __future__ import annotations

import os
import re
import shlex
import shutil

from ide_lib.constants import DEFAULT_THEME_HEX
from ide_lib.tmux import tmux_out

_THEME_KV_RE = re.compile(r'^([A-Z0-9_]+)="?(#[0-9A-Fa-f]{6})"?$')
_PALETTE_CACHE: tuple[tuple[str, int, int, int, str], dict[str, str], dict[str, str]] | None = None

_CUBE_STEPS = (0, 95, 135, 175, 215, 255)
_ANSI16_SGR_MAP: dict[str, str] = {
    "BASE03": "\033[30m",
    "BASE02": "\033[90m",
    "BASE01": "\033[90m",
    "BASE00": "\033[37m",
    "BASE0": "\033[37m",
    "BASE1": "\033[97m",
    "BASE2": "\033[97m",
    "BASE3": "\033[97m",
    "YELLOW": "\033[33m",
    "ORANGE": "\033[91m",
    "RED": "\033[31m",
    "MAGENTA": "\033[35m",
    "VIOLET": "\033[95m",
    "BLUE": "\033[34m",
    "CYAN": "\033[36m",
    "GREEN": "\033[32m",
}
_MONO_SGR_MAP: dict[str, str] = {
    "BASE03": "",
    "BASE02": "\033[7m",
    "BASE01": "\033[2m",
    "BASE00": "\033[2m",
    "BASE0": "",
    "BASE1": "\033[1m",
    "BASE2": "\033[1m",
    "BASE3": "\033[1m",
    "YELLOW": "\033[1m",
    "ORANGE": "\033[1m",
    "RED": "\033[1;7m",
    "MAGENTA": "\033[4m",
    "VIOLET": "\033[4m",
    "BLUE": "\033[1m",
    "CYAN": "\033[4m",
    "GREEN": "",
}


_TRUECOLOR_TERMS = (
    "xterm-256color",
    "tmux-256color",
    "xterm-ghostty",
    "xterm-kitty",
    "wezterm",
    "alacritty",
)


def detect_color_tier() -> str:
    """Detect terminal color capability (`nocolor`, `mono`, `truecolor`, `256color`, or `16color`)."""
    if os.environ.get("NO_COLOR"):
        return "nocolor"
    term = (os.environ.get("TERM") or "").strip().lower()
    if term == "dumb":
        return "mono"
    ct = (os.environ.get("COLORTERM") or "").strip().lower()
    if ct in ("truecolor", "24bit"):
        return "truecolor"
    if ct in ("256color", "8bit"):
        return "256color"
    if ct in ("16color", "ansi", "4bit"):
        return "16color"
    if not term or term in _TRUECOLOR_TERMS or term.startswith("foot"):
        return "truecolor"
    if "256color" in term or "256" in term:
        return "256color"
    return "16color"


def _rgb_to_ansi256(r: int, g: int, b: int) -> int:
    def _nearest_cube(v: int) -> int:
        best_i = 0
        best_d = 999
        for idx, step in enumerate(_CUBE_STEPS):
            d = abs(v - step)
            if d < best_d:
                best_d = d
                best_i = idx
        return best_i

    ci_r, ci_g, ci_b = _nearest_cube(r), _nearest_cube(g), _nearest_cube(b)
    cr, cg, cb = _CUBE_STEPS[ci_r], _CUBE_STEPS[ci_g], _CUBE_STEPS[ci_b]
    cube_dist = (r - cr) ** 2 + (g - cg) ** 2 + (b - cb) ** 2
    cube_idx = 16 + 36 * ci_r + 6 * ci_g + ci_b

    avg = (r + g + b) // 3
    if avg <= 8:
        gray_step = 0
    elif avg >= 238:
        gray_step = 23
    else:
        gray_step = round((avg - 8) / 10)
    gv = 8 + 10 * gray_step
    gray_dist = (r - gv) ** 2 + (g - gv) ** 2 + (b - gv) ** 2
    if gray_dist < cube_dist:
        return 232 + gray_step
    return cube_idx


def hex_to_fg(hex_code: str, tier: str = "truecolor", role_key: str = "") -> str:
    """Convert `#RRGGBB` into an SGR foreground sequence calibrated to `tier`."""
    if tier == "nocolor":
        return ""
    if tier == "mono":
        return _MONO_SGR_MAP.get(role_key, "")
    if tier == "16color":
        return _ANSI16_SGR_MAP.get(role_key, "")
    h = hex_code.lstrip("#")
    if len(h) != 6:
        return ""
    try:
        r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    except ValueError:
        return ""
    if tier == "256color":
        return f"\033[38;5;{_rgb_to_ansi256(r, g, b)}m"
    return f"\033[38;2;{r};{g};{b}m"


def load_active_palette() -> tuple[dict[str, str], dict[str, str]]:
    """Load `(hex_map, ansi_fg_map)` from `active-theme.theme` degraded to active terminal capability."""
    global _PALETTE_CACHE
    tier = detect_color_tier()
    xdg_cfg = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    active_file = os.path.join(xdg_cfg, "home-settings", "active-theme.theme")
    try:
        st = os.stat(active_file)
        stat_key = (active_file, st.st_ino, st.st_mtime_ns, st.st_size, tier)
    except OSError:
        stat_key = (active_file, -1, -1, -1, tier)
    if _PALETTE_CACHE is not None and _PALETTE_CACHE[0] == stat_key:
        return (dict(_PALETTE_CACHE[1]), dict(_PALETTE_CACHE[2]))

    hex_map = dict(DEFAULT_THEME_HEX)
    if stat_key[1] >= 0:
        try:
            with open(active_file, "r", encoding="utf-8") as fh:
                for raw_line in fh:
                    m = _THEME_KV_RE.match(raw_line.strip())
                    if m and m.group(1) in hex_map:
                        hex_map[m.group(1)] = m.group(2)
        except OSError:
            pass
    esc_map = {k: hex_to_fg(v, tier=tier, role_key=k) for k, v in hex_map.items()}
    esc_map["RESET"] = "" if tier == "nocolor" else "\033[0m"
    _PALETTE_CACHE = (stat_key, hex_map, esc_map)
    return (dict(hex_map), dict(esc_map))


def state_color(state: str, esc: dict[str, str]) -> str:
    """Map an AI fleet urgency state label to its semantic palette escape sequence."""
    if state == "ATTN":
        return esc["ORANGE"]
    if state == "QUOTA":
        return esc["YELLOW"]
    if state == "WORKING":
        return esc["CYAN"]
    if state == "DONE":
        return esc["GREEN"]
    if state == "IDLE":
        return esc["BASE0"]
    return esc["BASE01"]


def build_fzf_env(hex_map: dict[str, str]) -> dict[str, str]:
    """Return environment dictionary with `FZF_DEFAULT_OPTS` synchronized to the active theme and color tier."""
    env = os.environ.copy()
    tier = detect_color_tier()
    if tier == "nocolor":
        env["FZF_DEFAULT_OPTS"] = "--no-color --layout=reverse --border=rounded --info=inline --no-scrollbar"
        return env
    if tier == "mono":
        env["FZF_DEFAULT_OPTS"] = "--color=bw --layout=reverse --border=rounded --info=inline --no-scrollbar"
        return env
    xdg_cfg = env.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    theme_env_path = os.path.join(xdg_cfg, "home-settings", "theme-env.sh")
    loaded_opts = ""
    if tier in ("truecolor", "256color"):
        try:
            with open(theme_env_path, "r", encoding="utf-8") as fh:
                for raw_line in fh:
                    stripped = raw_line.strip()
                    if stripped.startswith("export FZF_DEFAULT_OPTS="):
                        rhs = stripped[len("export FZF_DEFAULT_OPTS="):]
                        try:
                            parts = shlex.split(rhs, posix=True)
                            if len(parts) == 1:
                                loaded_opts = parts[0]
                        except ValueError:
                            pass
                        if not loaded_opts and len(rhs) >= 2 and rhs[0] == rhs[-1] and rhs[0] in ("'", '"'):
                            loaded_opts = rhs[1:-1]
        except OSError:
            pass
    if loaded_opts:
        env["FZF_DEFAULT_OPTS"] = loaded_opts
    elif tier in ("truecolor", "256color") and env.get("TMUX") and shutil.which("tmux"):
        tmux_fzf = tmux_out("show-environment", "-g", "FZF_DEFAULT_OPTS")
        if tmux_fzf.startswith("FZF_DEFAULT_OPTS=") and tmux_fzf[17:]:
            env["FZF_DEFAULT_OPTS"] = tmux_fzf[17:]
    if tier == "16color":
        env["FZF_DEFAULT_OPTS"] = "--color=16 --layout=reverse --border=rounded --info=inline --no-scrollbar"
    elif not env.get("FZF_DEFAULT_OPTS"):
        env["FZF_DEFAULT_OPTS"] = (
            f"--color=bg+:{hex_map['BASE02']},bg:{hex_map['BASE03']},spinner:{hex_map['GREEN']},"
            f"hl:{hex_map['BASE01']},fg:{hex_map['BASE0']},header:{hex_map['BASE01']},"
            f"border:{hex_map['BASE01']},separator:{hex_map['BASE01']},label:{hex_map['BASE01']},gutter:{hex_map['BASE03']},"
            f"info:{hex_map['YELLOW']},pointer:{hex_map['GREEN']},marker:{hex_map['GREEN']},"
            f"fg+:{hex_map['BASE1']},prompt:{hex_map['YELLOW']},hl+:{hex_map['BLUE']} "
            "--layout=reverse --border=rounded --info=inline --no-scrollbar"
        )
    return env
