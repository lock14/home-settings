"""Configuration and theme artifact generators across terminal, Tmux, Git, and shells."""

from __future__ import annotations

from pathlib import Path
import re

from theme_lib.palette import (
    ALL_COLOR_KEYS,
    CORE_COLOR_KEYS,
    SOLARIZED_DARK_DEFAULTS,
    ansi_palette_hex_list,
    blend_hex,
    get_holiday_meta,
    hex_to_rgb,
    rgb_semicolon,
)

DIRCOLORS_KEYWORD_MAP: dict[str, str] = {
    "NORMAL": "no",
    "FILE": "fi",
    "RESET": "rs",
    "DIR": "di",
    "OTHER_WRITABLE": "ow",
    "LINK": "ln",
    "MULTIHARDLINK": "mh",
    "FIFO": "pi",
    "SOCK": "so",
    "DOOR": "do",
    "BLK": "bd",
    "CHR": "cd",
    "ORPHAN": "or",
    "MISSING": "mi",
    "SETUID": "su",
    "SETGID": "sg",
    "CAPABILITY": "ca",
    "STICKY_OTHER_WRITABLE": "tw",
    "STICKY": "st",
    "EXEC": "ex",
}

GHOSTTY_KEYBIND_DIRECTIVES: tuple[str, ...] = (
    "keybind = ctrl+shift+d=new_split:auto",
    "keybind = ctrl+shift+w=close_surface",
    "keybind = ctrl+shift+enter=toggle_split_zoom",
    "keybind = ctrl+shift+h=goto_split:left",
    "keybind = ctrl+shift+j=goto_split:bottom",
    "keybind = ctrl+shift+k=goto_split:top",
    "keybind = ctrl+shift+l=goto_split:right",
    "keybind = ctrl+shift+t=new_tab",
    r"keybind = alt+left=text:\x1b[1;3D",
    r"keybind = alt+right=text:\x1b[1;3C",
    r"keybind = alt+up=text:\x1b[1;3A",
    r"keybind = alt+down=text:\x1b[1;3B",
    r"keybind = alt+shift+left=text:\x1b[1;4D",
    r"keybind = alt+shift+right=text:\x1b[1;4C",
    r"keybind = alt+shift+up=text:\x1b[1;4A",
    r"keybind = alt+shift+down=text:\x1b[1;4B",
)


def build_fzf_color_opts(theme: dict[str, str], include_layout: bool = True) -> str:
    """Build TrueColor fzf --color flags (with optional layout flags) for a theme."""
    if include_layout:
        return (
            f"--color=bg+:{theme['BASE02']},bg:{theme['BASE03']},spinner:{theme['GREEN']},hl:{theme['BASE01']} "
            f"--color=fg:{theme['BASE0']},header:{theme['BASE01']},info:{theme['YELLOW']},pointer:{theme['GREEN']} "
            f"--color=marker:{theme['GREEN']},fg+:{theme['BASE1']},prompt:{theme['YELLOW']},hl+:{theme['BLUE']} "
            f"--color=border:{theme['BASE01']},separator:{theme['BASE01']},label:{theme['BASE01']},gutter:{theme['BASE03']} "
            f"--layout=reverse --border=rounded --info=inline"
        )
    return (
        f"--color=bg+:{theme['BASE02']},bg:{theme['BASE03']},spinner:{theme['GREEN']},"
        f"hl:{theme['BASE01']},fg:{theme['BASE0']},header:{theme['BASE01']},"
        f"border:{theme['BASE01']},separator:{theme['BASE01']},label:{theme['BASE01']},gutter:{theme['BASE03']},"
        f"info:{theme['YELLOW']},pointer:{theme['GREEN']},marker:{theme['GREEN']},"
        f"fg+:{theme['BASE1']},prompt:{theme['YELLOW']},hl+:{theme['BLUE']}"
    )


def generate_tmtheme_text(base_tmtheme_text: str, theme: dict[str, str]) -> str:
    """Remap the canonical Solarized Dark .tmTheme XML into the target theme palette."""
    replacements = {SOLARIZED_DARK_DEFAULTS[key]: theme[key] for key in CORE_COLOR_KEYS}
    pattern = re.compile("|".join(re.escape(k) for k in replacements), re.IGNORECASE)
    out = pattern.sub(lambda m: replacements[m.group(0).upper()], base_tmtheme_text)
    return out.replace(
        "<string>Solarized-Dark-TrueColor</string>",
        f"<string>{theme['BAT_THEME_NAME']}</string>",
    )


def generate_btop_theme_text(theme: dict[str, str]) -> str:
    """Generate a TrueColor btop .theme file for the given palette."""
    c = {k: v.lower() for k, v in theme.items() if k in ALL_COLOR_KEYS}
    return f"""# {theme['THEME_LABEL']} TrueColor theme for btop
# Matches the 16-color semantic palette architecture

# Main background, empty for terminal default, need to be empty if you want transparent background
theme[main_bg]="{c['BASE03']}"

# Main text color
theme[main_fg]="{c['BASE0']}"

# Title color for boxes
theme[title]="{c['BASE1']}"

# Highlight color for keyboard shortcuts
theme[hi_fg]="{c['YELLOW']}"

# Background color of selected item in processes box
theme[selected_bg]="{c['BASE02']}"

# Foreground color of selected item in processes box
theme[selected_fg]="{c['BASE1']}"

# Color of inactive/disabled text
theme[inactive_fg]="{c['BASE01']}"

# Color of text appearing on top of graphs, such as uptime and current network graph scaling
theme[graph_text]="{c['BASE00']}"

# Background color of the percentage meters
theme[meter_bg]="{c['BASE02']}"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="{c['GREEN']}"

# Cpu box outline color
theme[cpu_box]="{c['BASE01']}"

# Memory/disks box outline color
theme[mem_box]="{c['BASE01']}"

# Net up/down box outline color
theme[net_box]="{c['BASE01']}"

# Processes box outline color
theme[proc_box]="{c['BASE01']}"

# Box divider line and small boxes line color
theme[div_line]="{c['BASE01']}"

# Temperature graph colors
theme[temp_start]="{c['GREEN']}"
theme[temp_mid]="{c['YELLOW']}"
theme[temp_end]="{c['RED']}"

# CPU graph colors
theme[cpu_start]="{c['GREEN']}"
theme[cpu_mid]="{c['CYAN']}"
theme[cpu_end]="{c['BLUE']}"

# Mem/Disk free meter
theme[free_start]="{c['BASE01']}"
theme[free_mid]="{c['BASE00']}"
theme[free_end]="{c['BASE0']}"

# Mem/Disk cached meter
theme[cached_start]="{c['CYAN']}"
theme[cached_mid]="{c['BLUE']}"
theme[cached_end]="{c['VIOLET']}"

# Mem/Disk available meter
theme[available_start]="{c['GREEN']}"
theme[available_mid]="{c['CYAN']}"
theme[available_end]="{c['BLUE']}"

# Mem/Disk used meter
theme[used_start]="{c['YELLOW']}"
theme[used_mid]="{c['ORANGE']}"
theme[used_end]="{c['RED']}"

# Download graph colors
theme[download_start]="{c['CYAN']}"
theme[download_mid]="{c['BLUE']}"
theme[download_end]="{c['VIOLET']}"

# Upload graph colors
theme[upload_start]="{c['GREEN']}"
theme[upload_mid]="{c['YELLOW']}"
theme[upload_end]="{c['ORANGE']}"

# Process box color gradient for threads, mem and cpu usage
theme[process_start]="{c['GREEN']}"
theme[process_mid]="{c['YELLOW']}"
theme[process_end]="{c['RED']}"
"""


def generate_ghostty_theme_text(theme: dict[str, str]) -> str:
    """Generate a Ghostty theme file in ~/.config/ghostty/themes/."""
    c = {k: v.lower() for k, v in theme.items() if k in CORE_COLOR_KEYS}
    palette_lines = "\n".join(
        f"palette = {idx}={col}"
        for idx, col in enumerate(ansi_palette_hex_list(theme, lowercase=True))
    )
    return f"""{palette_lines}
background = {c['BASE03']}
foreground = {c['BASE0']}
cursor-color = {c['BASE0']}
cursor-text = {c['BASE03']}
selection-background = {c['BASE02']}
selection-foreground = {c['BASE1']}
"""


def generate_ghostty_config_text(theme: dict[str, str]) -> str:
    """Generate the Ghostty configuration file with calibrated palette and keybindings."""
    palette_lines = "\n".join(
        f"palette = {idx}={col}"
        for idx, col in enumerate(ansi_palette_hex_list(theme, lowercase=False))
    )
    keybind_lines = "\n".join(GHOSTTY_KEYBIND_DIRECTIVES)
    return f"""# Ghostty Terminal Configuration ({theme['THEME_LABEL']})
theme = "{theme['GHOSTTY_THEME_NAME']}"
background = {theme['BASE03']}
foreground = {theme['BASE0']}
cursor-color = {theme['BASE0']}
cursor-text = {theme['BASE03']}
selection-background = {theme['BASE02']}
selection-foreground = {theme['BASE1']}
{palette_lines}
font-family = "MesloLGS Nerd Font Mono"
font-size = 12
font-thicken = false
window-padding-x = 0
window-padding-y = 0
window-padding-balance = false
window-decoration = auto
cursor-style = block
cursor-style-blink = false
copy-on-select = clipboard
clipboard-read = allow
clipboard-write = allow
confirm-close-surface = false
shell-integration = detect
shell-integration-features = no-cursor,ssh-env
mouse-hide-while-typing = true
macos-option-as-alt = true
{keybind_lines}
"""


def generate_btop_config_text(theme: dict[str, str], repo_dir: Path | None = None) -> str:
    """Generate btop.conf by updating color_theme on the repository baseline config."""
    if repo_dir is not None:
        base_btop = repo_dir / "dotfiles" / ".config" / "btop" / "btop.conf"
        if base_btop.is_file():
            raw = base_btop.read_text(encoding="utf-8")
            return re.sub(
                r'^color_theme\s*=\s*"[^"]*"',
                f'color_theme = "{theme["BTOP_THEME_NAME"]}"',
                raw,
                count=1,
                flags=re.MULTILINE,
            )
    return f"""# btop configuration ({theme['THEME_LABEL']} TrueColor)
color_theme = "{theme['BTOP_THEME_NAME']}"
theme_background = true
truecolor = true
vim_keys = true
rounded_corners = true
graph_symbol = "braille"
shown_boxes = "cpu mem net proc"
update_ms = 2000
proc_sorting = "cpu lazy"
proc_tree = false
proc_colors = true
proc_gradient = true
save_config_on_exit = false
"""


def generate_git_config_text(theme: dict[str, str]) -> str:
    """Generate XDG ~/.config/git/config with delta TrueColor diff styling."""
    c = {k: v.lower() for k, v in theme.items() if k in ALL_COLOR_KEYS}
    light_val = "true" if theme["THEME_MODE"] == "light" else "false"
    if theme["THEME_ID"] == "solarized-dark":
        plus_bg = "#0d3834"
        plus_emph_bg = c["MIX_GREEN"]
        minus_bg = "#2d222a"
        minus_emph_bg = c["MIX_RED"]
    elif theme.get("THEME_CATEGORY") == "holiday":
        plus_bg = c["MIX_GREEN"]
        plus_emph_seed = "#009e3d" if theme["THEME_MODE"] == "light" else "#2ee66b"
        plus_emph_bg = blend_hex(plus_emph_seed, theme["MIX_GREEN"], 0.28).lower()
        minus_bg = c["MIX_RED"]
        minus_emph_bg = blend_hex(theme["RED"], theme["MIX_RED"], 0.28).lower()
    else:
        plus_bg = c["MIX_GREEN"]
        plus_emph_bg = blend_hex(theme["GREEN"], theme["BASE03"], 0.30).lower()
        minus_bg = c["MIX_RED"]
        minus_emph_bg = blend_hex(theme["RED"], theme["BASE03"], 0.30).lower()
    return f"""# Git configuration (XDG-compliant: ~/.config/git/config)
# Configures delta as the default diff and log pager with authentic {theme['THEME_LABEL']} TrueColor styling

[core]
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true
    light = {light_val}
    syntax-theme = {theme['BAT_THEME_NAME']}
    line-numbers = true
    side-by-side = false
    commit-style = "{c['MAGENTA']}"
    file-style = "{c['CYAN']}"
    file-decoration-style = "{c['BASE01']}" ul
    hunk-header-style = line-number syntax
    hunk-header-line-number-style = "{c['BLUE']}"
    hunk-header-decoration-style = "{c['BASE01']}" box
    plus-style = syntax "{plus_bg}"
    plus-emph-style = syntax "{plus_emph_bg}"
    plus-empty-line-marker-style = normal "{plus_bg}"
    minus-style = syntax "{minus_bg}"
    minus-emph-style = syntax "{minus_emph_bg}"
    minus-empty-line-marker-style = normal "{minus_bg}"
    line-numbers-plus-style = "{c['GREEN']}"
    line-numbers-minus-style = "{c['RED']}"
    line-numbers-left-style = "{c['BASE01']}"
    line-numbers-right-style = "{c['BASE01']}"
    line-numbers-zero-style = "{c['BASE01']}"
    whitespace-error-style = "{c['RED']}" reverse

[merge]
    conflictstyle = zdiff3

[diff]
    colorMoved = default
"""


def generate_tealdeer_config_text(theme: dict[str, str]) -> str:
    """Generate tealdeer config.toml with unbolded TrueColor RGB roles."""
    b0_r, b0_g, b0_b = hex_to_rgb(theme["BASE0"])
    gr_r, gr_g, gr_b = hex_to_rgb(theme["GREEN"])
    cy_r, cy_g, cy_b = hex_to_rgb(theme["CYAN"])
    bl_r, bl_g, bl_b = hex_to_rgb(theme["BLUE"])
    mg_r, mg_g, mg_b = hex_to_rgb(theme["MAGENTA"])
    return f"""# tealdeer (tldr) configuration — {theme['THEME_LABEL']} TrueColor
# Strict unbolded typography to prevent monospace glyph jitter

[display]
compact = false
use_pager = false

[style.description]
foreground = {{ rgb = {{ r = {b0_r}, g = {b0_g}, b = {b0_b} }} }}
bold = false
underline = false
italic = false

[style.command_name]
foreground = {{ rgb = {{ r = {gr_r}, g = {gr_g}, b = {gr_b} }} }}
bold = false
underline = false
italic = false

[style.example_text]
foreground = {{ rgb = {{ r = {bl_r}, g = {bl_g}, b = {bl_b} }} }}
bold = false
underline = false
italic = false

[style.example_code]
foreground = {{ rgb = {{ r = {cy_r}, g = {cy_g}, b = {cy_b} }} }}
bold = false
underline = false
italic = false

[style.example_variable]
foreground = {{ rgb = {{ r = {mg_r}, g = {mg_g}, b = {mg_b} }} }}
bold = false
underline = true
italic = false

[updates]
auto_update = true
auto_update_interval_hours = 720
"""


def generate_active_theme_file_text(theme: dict[str, str]) -> str:
    """Serialize the normalized active theme snapshot for Neovim, Vim, and shells."""
    lines = [
        f"# Active Theme Snapshot: {theme['THEME_ID']}",
        f'THEME_ID="{theme["THEME_ID"]}"',
        f'THEME_LABEL="{theme["THEME_LABEL"]}"',
        f'THEME_DESCRIPTION="{theme["THEME_DESCRIPTION"]}"',
        f'THEME_MODE="{theme["THEME_MODE"]}"',
        f'BAT_THEME_NAME="{theme["BAT_THEME_NAME"]}"',
        f'BTOP_THEME_NAME="{theme["BTOP_THEME_NAME"]}"',
        f'GHOSTTY_THEME_NAME="{theme["GHOSTTY_THEME_NAME"]}"',
    ]
    for key in ALL_COLOR_KEYS:
        lines.append(f'{key}="{theme[key]}"')
    return "\n".join(lines) + "\n"


def compile_truecolor_ls_colors(theme: dict[str, str], repo_dir: Path | None = None) -> str:
    """Compile dotfiles/.dir-colors/dircolors into a 24-bit TrueColor LS_COLORS string."""
    sgr_map = {
        "30": f"38;2;{rgb_semicolon(theme['BASE03'])}",
        "31": f"38;2;{rgb_semicolon(theme['RED'])}",
        "32": f"38;2;{rgb_semicolon(theme['GREEN'])}",
        "33": f"38;2;{rgb_semicolon(theme['YELLOW'])}",
        "34": f"38;2;{rgb_semicolon(theme['BLUE'])}",
        "35": f"38;2;{rgb_semicolon(theme['MAGENTA'])}",
        "36": f"38;2;{rgb_semicolon(theme['CYAN'])}",
        "37": f"38;2;{rgb_semicolon(theme['BASE2'])}",
        "90": f"38;2;{rgb_semicolon(theme['BASE01'])}",
        "91": f"38;2;{rgb_semicolon(theme['ORANGE'])}",
        "92": f"38;2;{rgb_semicolon(theme['BASE01'])}",
        "93": f"38;2;{rgb_semicolon(theme['BASE00'])}",
        "94": f"38;2;{rgb_semicolon(theme['BASE0'])}",
        "95": f"38;2;{rgb_semicolon(theme['VIOLET'])}",
        "96": f"38;2;{rgb_semicolon(theme['BASE1'])}",
        "97": f"38;2;{rgb_semicolon(theme['BASE3'])}",
        "40": f"48;2;{rgb_semicolon(theme['BASE02'])}",
        "41": f"48;2;{rgb_semicolon(theme['RED'])}",
        "42": f"48;2;{rgb_semicolon(theme['GREEN'])}",
        "43": f"48;2;{rgb_semicolon(theme['YELLOW'])}",
        "44": f"48;2;{rgb_semicolon(theme['BLUE'])}",
        "45": f"48;2;{rgb_semicolon(theme['MAGENTA'])}",
        "46": f"48;2;{rgb_semicolon(theme['CYAN'])}",
        "47": f"48;2;{rgb_semicolon(theme['BASE2'])}",
    }
    base0_sgr = f"38;2;{rgb_semicolon(theme['BASE0'])}"

    dc_file = (repo_dir / "dotfiles" / ".dir-colors" / "dircolors") if repo_dir else None
    entries: list[str] = []
    if dc_file and dc_file.is_file():
        for raw_line in dc_file.read_text(encoding="utf-8").splitlines():
            stripped = raw_line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            line = re.split(r"\s+#", stripped, maxsplit=1)[0].strip()
            if not line:
                continue
            parts = line.split(None, 1)
            if len(parts) != 2 or parts[0] == "TERM":
                continue
            key, code = parts[0], parts[1].strip()
            ls_key = DIRCOLORS_KEYWORD_MAP.get(key)
            if ls_key is None:
                ls_key = f"*{key}" if key.startswith(".") else key
            if code == "0":
                ls_val = "0"
            elif code == "00":
                ls_val = "00" if key in ("NORMAL", "MULTIHARDLINK") else base0_sgr
            else:
                ls_val = ";".join(sgr_map.get(tok, tok) for tok in code.split(";"))
            entries.append(f"{ls_key}={ls_val}")
    if not entries:
        entries = [
            "rs=0",
            f"di={sgr_map['34']}",
            f"ln={sgr_map['36']}",
            "mh=00",
            f"pi={sgr_map['33']}",
            f"so={sgr_map['35']}",
            f"do={sgr_map['35']}",
            f"bd={sgr_map['35']}",
            f"cd={sgr_map['35']}",
            f"or={sgr_map['31']}",
            f"mi={sgr_map['31']}",
            f"ex={sgr_map['32']}",
            f"fi={base0_sgr}",
        ]
    return ":".join(entries) + ":"


def generate_theme_env_sh(theme: dict[str, str], repo_dir: Path | None = None) -> str:
    """Generate POSIX/Bash/Zsh environment exports for CLI tools and prompt colors."""
    blue = rgb_semicolon(theme["BLUE"])
    cyan = rgb_semicolon(theme["CYAN"])
    green = rgb_semicolon(theme["GREEN"])
    orange = rgb_semicolon(theme["ORANGE"])
    violet = rgb_semicolon(theme["VIOLET"])
    magenta = rgb_semicolon(theme["MAGENTA"])
    yellow = rgb_semicolon(theme["YELLOW"])
    red = rgb_semicolon(theme["RED"])
    base0 = rgb_semicolon(theme["BASE0"])
    base01 = rgb_semicolon(theme["BASE01"])
    base00 = rgb_semicolon(theme["BASE00"])
    base1 = rgb_semicolon(theme["BASE1"])
    base02 = rgb_semicolon(theme["BASE02"])

    eza_role_pairs = [
        ("di", blue), ("ex", green), ("fi", base0), ("pi", yellow),
        ("so", magenta), ("bd", magenta), ("cd", magenta), ("ln", cyan),
        ("or", red), ("xx", base01), ("da", base0),
    ]
    eza_parts = [f"{code}=38;2;{rgb}" for code, rgb in eza_role_pairs]
    eza_parts.append(f"hd=4;38;2;{base1}")
    eza_tail_pairs = [
        ("lp", base0), ("cc", orange), ("bO", red), ("in", base01), ("bl", base01),
        ("oc", base0), ("ur", base0), ("uw", base0), ("ux", base0), ("ue", base0),
        ("gr", base0), ("gw", base0), ("gx", base0), ("tr", base0), ("tw", base0),
        ("tx", base0), ("su", base0), ("sf", base0), ("xa", base0), ("sn", base0),
        ("nb", base01), ("nk", base0), ("nm", yellow), ("ng", orange), ("nt", red),
        ("sb", base0), ("ub", base01), ("uk", base0), ("um", yellow), ("ug", orange),
        ("ut", red), ("df", base0), ("ds", base0), ("uu", base0), ("uR", red),
        ("un", base0), ("gu", base0), ("gR", red), ("gn", base0), ("lc", base0),
        ("lm", yellow), ("ga", green), ("gm", yellow), ("gd", red), ("gv", base0),
        ("gt", base0), ("gi", base01), ("gc", red), ("Gm", green), ("Go", blue),
        ("Gc", green), ("Gd", yellow), ("sp", orange), ("mp", blue),
        ("im", violet), ("vi", violet), ("mu", violet), ("lo", violet),
        ("cr", magenta), ("do", base0), ("co", orange), ("tm", base01), ("cm", base01),
        ("bu", green), ("sc", base0), ("Sn", base01), ("Su", base0), ("Sr", base0),
        ("St", base0), ("Sl", base0), ("ff", base0),
    ]
    eza_parts.extend(f"{code}=38;2;{rgb}" for code, rgb in eza_tail_pairs)
    eza_str = ":".join(eza_parts)
    ls_str = compile_truecolor_ls_colors(theme, repo_dir)
    fzf_str = build_fzf_color_opts(theme, include_layout=True)
    jq_str = (
        f"38;2;{magenta}:38;2;{magenta}:38;2;{magenta}:38;2;{magenta}:"
        f"38;2;{cyan}:38;2;{base0}:38;2;{base0}:38;2;{green}"
    )

    hmeta = get_holiday_meta(theme)
    os_icon_line = (
        f"export _HS_PROMPT_OS_ICON='{hmeta['icon']}'"
        if hmeta
        else "unset _HS_PROMPT_OS_ICON"
    )

    return f"""# Generated by bin/theme — Active Theme: {theme['THEME_ID']}
export HOME_SETTINGS_THEME="{theme['THEME_ID']}"
export HOME_SETTINGS_THEME_MODE="{theme['THEME_MODE']}"
export BAT_THEME="{theme['BAT_THEME_NAME']}"
export FZF_DEFAULT_OPTS='{fzf_str}'
export EZA_COLORS="{eza_str}"
export EXA_COLORS="$EZA_COLORS"
export JQ_COLORS="{jq_str}"
export LESS="${{LESS:--R}}"
export GROFF_NO_SGR=1
_hs_esc="$(printf '\\033')"
export LESS_TERMCAP_mb="${{_hs_esc}}[38;2;{red}m"
export LESS_TERMCAP_md="${{_hs_esc}}[1;38;2;{blue}m"
export LESS_TERMCAP_me="${{_hs_esc}}[0m"
export LESS_TERMCAP_so="${{_hs_esc}}[38;2;{base1};48;2;{base02}m"
export LESS_TERMCAP_se="${{_hs_esc}}[0m"
export LESS_TERMCAP_us="${{_hs_esc}}[4;38;2;{cyan}m"
export LESS_TERMCAP_ue="${{_hs_esc}}[0m"
export _HS_ESC_ORANGE="${{_hs_esc}}[38;2;{orange}m"
export _HS_ESC_BLUE="${{_hs_esc}}[38;2;{blue}m"
export _HS_ESC_CYAN="${{_hs_esc}}[38;2;{cyan}m"
export _HS_ESC_BASE0="${{_hs_esc}}[38;2;{base0}m"
export _HS_ESC_BASE01="${{_hs_esc}}[38;2;{base01}m"
unset _hs_esc
export LS_COLORS='{ls_str}'
export LSCOLORS="exgxfxdxcxfxfxegedabagacad"
{os_icon_line}
export _HS_PROMPT_BG_BASE02='\\[\\e[48;2;{base02}m\\]'
export _HS_PROMPT_CAP_BASE02='\\[\\e[0m\\e[38;2;{base02}m\\]'
export _HS_PROMPT_CAP_RED='\\[\\e[0m\\e[38;2;{red}m\\]'
export _HS_PROMPT_FG_BASE02='\\[\\e[38;2;{base02}m\\]'
export _HS_PROMPT_FG_BASE01='\\[\\e[38;2;{base01}m\\]'
export _HS_PROMPT_FG_BASE00='\\[\\e[38;2;{base00}m\\]'
export _HS_PROMPT_FG_BASE0='\\[\\e[38;2;{base0}m\\]'
export _HS_PROMPT_FG_BASE1='\\[\\e[38;2;{base1}m\\]'
export _HS_PROMPT_FG_YELLOW='\\[\\e[38;2;{yellow}m\\]'
export _HS_PROMPT_FG_ORANGE='\\[\\e[38;2;{orange}m\\]'
export _HS_PROMPT_FG_RED='\\[\\e[38;2;{red}m\\]'
export _HS_PROMPT_FG_VIOLET='\\[\\e[38;2;{violet}m\\]'
export _HS_PROMPT_FG_BLUE='\\[\\e[38;2;{blue}m\\]'
export _HS_PROMPT_FG_CYAN='\\[\\e[38;2;{cyan}m\\]'
export _HS_PROMPT_FG_GREEN='\\[\\e[38;2;{green}m\\]'
export _HS_LOADED_THEME='{theme['THEME_ID']}'
"""


def generate_zsh_theme_text(theme: dict[str, str]) -> str:
    """Generate Zsh syntax-highlighting, autosuggestion, and zle_highlight styles."""
    return f"""# Generated by bin/theme — Zsh Highlighting & Autosuggestions ({theme['THEME_ID']})
typeset -g _HS_LOADED_THEME="{theme['THEME_ID']}"
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg={theme['BASE01']}"

typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[default]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[unknown-token]="fg={theme['RED']}"
ZSH_HIGHLIGHT_STYLES[reserved-word]="fg={theme['YELLOW']}"
ZSH_HIGHLIGHT_STYLES[alias]="fg={theme['GREEN']}"
ZSH_HIGHLIGHT_STYLES[suffix-alias]="fg={theme['GREEN']}"
ZSH_HIGHLIGHT_STYLES[global-alias]="fg={theme['GREEN']}"
ZSH_HIGHLIGHT_STYLES[builtin]="fg={theme['GREEN']}"
ZSH_HIGHLIGHT_STYLES[function]="fg={theme['GREEN']}"
ZSH_HIGHLIGHT_STYLES[command]="fg={theme['GREEN']}"
ZSH_HIGHLIGHT_STYLES[hashed-command]="fg={theme['GREEN']}"
ZSH_HIGHLIGHT_STYLES[precommand]="fg={theme['BLUE']}"
ZSH_HIGHLIGHT_STYLES[autodirectory]="fg={theme['BLUE']}"
ZSH_HIGHLIGHT_STYLES[path]="fg={theme['BLUE']}"
ZSH_HIGHLIGHT_STYLES[path_prefix]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[path_pathseparator]="fg={theme['BASE01']}"
ZSH_HIGHLIGHT_STYLES[path_prefix_pathseparator]="fg={theme['BASE01']}"
ZSH_HIGHLIGHT_STYLES[globbing]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[history-expansion]="fg={theme['BLUE']}"
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]="fg={theme['CYAN']}"
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]="fg={theme['CYAN']}"
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]="fg={theme['CYAN']}"
ZSH_HIGHLIGHT_STYLES[rc-quote]="fg={theme['CYAN']}"
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]="fg={theme['CYAN']}"
ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]="fg={theme['CYAN']}"
ZSH_HIGHLIGHT_STYLES[command-substitution]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[command-substitution-unquoted]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[command-substitution-quoted]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter-unquoted]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter-quoted]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[process-substitution]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[process-substitution-delimiter]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[back-quoted-argument]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[back-quoted-argument-unquoted]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[back-quoted-argument-delimiter]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[arithmetic-expansion]="fg={theme['MAGENTA']}"
ZSH_HIGHLIGHT_STYLES[assign]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[redirection]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[commandseparator]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[named-fd]="fg={theme['MAGENTA']}"
ZSH_HIGHLIGHT_STYLES[numeric-fd]="fg={theme['MAGENTA']}"
ZSH_HIGHLIGHT_STYLES[arg0]="fg={theme['GREEN']}"
ZSH_HIGHLIGHT_STYLES[comment]="fg={theme['BASE01']}"
ZSH_HIGHLIGHT_STYLES[bracket-level-1]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[bracket-level-2]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[bracket-level-3]="fg={theme['BASE0']}"
ZSH_HIGHLIGHT_STYLES[bracket-error]="fg={theme['RED']}"

if zmodload zsh/pcre >/dev/null 2>&1; then
    setopt rematchpcre
    ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets regexp)
    typeset -gA ZSH_HIGHLIGHT_REGEXP=()
    ZSH_HIGHLIGHT_REGEXP+=("(?<=[=\\s]|^)[0-9]+(\\.[0-9]+)?(?=[\\s;|<>&]|$)(?=(?:[^\\\"]*\\\"[^\\\"]*\\\")*[^\\\"]*$)(?=(?:[^']*'[^']*')*[^']*$)" "fg={theme['MAGENTA']}")
fi

zle_highlight=(region:bg={theme['BASE02']} special:fg={theme['MAGENTA']} isearch:underline,fg={theme['BLUE']})
"""


def generate_p10k_theme_text(theme: dict[str, str]) -> str:
    """Generate Powerlevel10k two-phase token palette remap for live Zsh reload."""
    hmeta_p10k = get_holiday_meta(theme)
    holiday_icon = hmeta_p10k["icon"] if hmeta_p10k else ""
    return f"""# Generated by bin/theme — Powerlevel10k Palette Remap ({theme['THEME_ID']})
() {{
  typeset -gA _HS_P10K_BASE_SCALARS _HS_P10K_BASE_ARRAYS _HS_P10K_BASE_HEX
  local _hs_param _hs_val _hs_hex _hs_tok
  local -a _hs_arr_copy
  if (( ! ${{#_HS_P10K_BASE_SCALARS}} )); then
    for _hs_param in ${{(k)parameters[(I)POWERLEVEL9K_*]}}; do
      [[ "$_hs_param" == "POWERLEVEL9K_GITSTATUS_DIR" || "$_hs_param" == "POWERLEVEL9K_CONFIG_FILE" ]] && continue
      case "${{(Pt)_hs_param}}" in
        scalar*)
          _hs_val="${{(P)_hs_param}}"
          _HS_P10K_BASE_SCALARS[$_hs_param]="$_hs_val"
          [[ "$_hs_val" == *"#"* ]] && _HS_P10K_BASE_HEX[$_hs_param]="$_hs_val"
          ;;
        array*)
          _hs_arr_copy=( "${{(@P)_hs_param}}" )
          if (( ${{#_hs_arr_copy}} == 0 )); then
            _HS_P10K_BASE_ARRAYS[$_hs_param]=$'\\x01EMPTY\\x01'
          else
            _HS_P10K_BASE_ARRAYS[$_hs_param]="${{(pj:\\0:)_hs_arr_copy}}"
          fi
          ;;
      esac
    done
  else
    for _hs_param in ${{(k)parameters[(I)POWERLEVEL9K_*]}}; do
      [[ "$_hs_param" == "POWERLEVEL9K_GITSTATUS_DIR" || "$_hs_param" == "POWERLEVEL9K_CONFIG_FILE" ]] && continue
      if (( ! ${{+_HS_P10K_BASE_SCALARS[$_hs_param]}} && ! ${{+_HS_P10K_BASE_ARRAYS[$_hs_param]}} )); then
        unset "$_hs_param"
      fi
    done
    for _hs_param _hs_val in "${{(@kv)_HS_P10K_BASE_SCALARS}}"; do
      typeset -g "$_hs_param=$_hs_val"
    done
    for _hs_param _hs_val in "${{(@kv)_HS_P10K_BASE_ARRAYS}}"; do
      typeset -ga "$_hs_param"
      if [[ "$_hs_val" == $'\\x01EMPTY\\x01' ]]; then
        set -A "$_hs_param"
      else
        set -A "$_hs_param" "${{(@0)_hs_val}}"
      fi
    done
    if (( ! ${{#_HS_P10K_BASE_HEX}} )); then
      for _hs_param _hs_val in "${{(@kv)_HS_P10K_BASE_SCALARS}}"; do
        [[ "$_hs_val" == *"#"* ]] && _HS_P10K_BASE_HEX[$_hs_param]="$_hs_val"
      done
    fi
  fi
  local -A _hs_p10k_to_role=(
    '#002B36' '__HS_BASE03__'
    '#073642' '__HS_BASE02__'
    '#586E75' '__HS_BASE01__'
    '#657B83' '__HS_BASE00__'
    '#839496' '__HS_BASE0__'
    '#93A1A1' '__HS_BASE1__'
    '#EEE8D5' '__HS_BASE2__'
    '#FDF6E3' '__HS_BASE3__'
    '#B58900' '__HS_YELLOW__'
    '#CB4B16' '__HS_ORANGE__'
    '#DC322F' '__HS_RED__'
    '#D33682' '__HS_MAGENTA__'
    '#6C71C4' '__HS_VIOLET__'
    '#268BD2' '__HS_BLUE__'
    '#2AA198' '__HS_CYAN__'
    '#859900' '__HS_GREEN__'
  )
  local -A _hs_p10k_from_role=(
    '__HS_BASE03__'  '{theme["BASE03"]}'
    '__HS_BASE02__'  '{theme["BASE02"]}'
    '__HS_BASE01__'  '{theme["BASE01"]}'
    '__HS_BASE00__'  '{theme["BASE00"]}'
    '__HS_BASE0__'   '{theme["BASE0"]}'
    '__HS_BASE1__'   '{theme["BASE1"]}'
    '__HS_BASE2__'   '{theme["BASE2"]}'
    '__HS_BASE3__'   '{theme["BASE3"]}'
    '__HS_YELLOW__'  '{theme["YELLOW"]}'
    '__HS_ORANGE__'  '{theme["ORANGE"]}'
    '__HS_RED__'     '{theme["RED"]}'
    '__HS_MAGENTA__' '{theme["MAGENTA"]}'
    '__HS_VIOLET__'  '{theme["VIOLET"]}'
    '__HS_BLUE__'    '{theme["BLUE"]}'
    '__HS_CYAN__'    '{theme["CYAN"]}'
    '__HS_GREEN__'   '{theme["GREEN"]}'
  )
  for _hs_param _hs_val in "${{(@kv)_HS_P10K_BASE_HEX}}"; do
    for _hs_hex _hs_tok in "${{(@kv)_hs_p10k_to_role}}"; do
      if [[ "$_hs_val" == *"$_hs_hex"* ]]; then
        _hs_val="${{_hs_val//$_hs_hex/$_hs_tok}}"
      fi
    done
    for _hs_tok _hs_hex in "${{(@kv)_hs_p10k_from_role}}"; do
      if [[ "$_hs_val" == *"$_hs_tok"* ]]; then
        _hs_val="${{_hs_val//$_hs_tok/$_hs_hex}}"
      fi
    done
    typeset -g "$_hs_param=$_hs_val"
  done
  if [[ -n "{holiday_icon}" ]]; then
    typeset -g POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION='{holiday_icon}'
  else
    unset POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION
  fi
}}
"""


def generate_tmux_theme_text(theme: dict[str, str]) -> str:
    """Generate native zero-fork Tmux status bar, 3-state IDE role pills, and border styles."""
    b03 = theme["BASE03"]
    b02 = theme["BASE02"]
    b01 = theme["BASE01"]
    b00 = theme["BASE00"]
    b0 = theme["BASE0"]
    b1 = theme["BASE1"]
    yellow = theme["YELLOW"]
    orange = theme["ORANGE"]
    red = theme["RED"]
    magenta = theme["MAGENTA"]
    violet = theme["VIOLET"]
    blue = theme["BLUE"]
    cyan = theme["CYAN"]
    green = theme["GREEN"]
    hmeta = get_holiday_meta(theme)
    session_icon = hmeta["icon"] if hmeta else ""
    holiday_right_segment = (
        f"#{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},105}}}},#[fg={b00}#,bg={b02}#,nobold] #[fg={yellow}#,bg={b02}#,nobold]{hmeta['badge']} ,}}"
        if hmeta
        else ""
    )
    attn_right_segment = (
        f"#{{?#{{&&:#{{!=:#{{@ide_attn_summary}},}},#{{!=:#{{@ide_attn_summary}},#{{session_name}}}}}},#[fg={b00}#,bg={b02}#,nobold] #[range=user|attn]#[fg={orange}#,bg={b02}#,nobold]󰂚 #{{@ide_attn_summary}} #[range=right],}}"
    )
    fleet_right_segment = (
        f"#{{?#{{||:#{{>=:#{{@ide_fleet_count}},1}},#{{!=:#{{@ide_session}},}}}},#[fg={b00}#,bg={b02}#,nobold] #[range=user|fleet]#[fg={b0}#,bg={b02}#,nobold]{session_icon} #{{?#{{>=:#{{@ide_fleet_count}},1}},#{{@ide_fleet_count}},1}} · #{{?#{{>=:#{{@ide_fleet_active}},1}},#[fg={cyan}#,bg={b02}#,nobold]#{{@ide_fleet_active}} active#[fg={b0}#,bg={b02}#,nobold],0 active}}#{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},120}}}}, (Alt+w) , }}#[range=right],}}"
    )

    return f"""# Generated by bin/theme — Tmux Status Bar & Borders ({theme['THEME_ID']})
set -g pane-border-style "fg={b01},bg={b03}"
set -g pane-active-border-style "fg={b01},bg={b03}"
set -g popup-border-style "fg={b01},bg={b03}"
set -g popup-style "fg={b0},bg={b03}"
set -g mode-style "fg={b1},bg={b02}"
set -g message-style "fg={b1},bg={b02}"
set -g message-command-style "fg={b1},bg={b02}"
set -g status-style "fg={b0},bg={b02}"
set -g status-right-length 160

set -g status-left "#[fg={blue},bg={b02},nobold] {session_icon} #S #[fg={b00},bg={b02},nobold] "

set -g @ide_tab_ai '#{{?#{{==:#{{@ide_role}},ai}}, #[fg={cyan}#,bg={b02}#,nobold]▸ 󰚩 #[fg={b1}#,bg={b02}#,nobold]#{{?#{{!=:#{{@ide_ai_cli}},}},#{{@ide_ai_cli}},AI}}#{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},95}}}}, (Alt+a),}}, #{{?#{{||:#{{==:#{{@ide_ai_state}},approval}},#{{&&:#{{==:#{{@ide_ai_attn}},1}},#{{!=:#{{@ide_ai_state}},done}}}}}},#[fg={orange}#,bg={b02}#,nobold],#{{?#{{&&:#{{==:#{{@ide_ai_state}},done}},#{{==:#{{@ide_ai_attn}},1}}}},#[fg={green}#,bg={b02}#,nobold],#{{?#{{==:#{{@ide_ai_state}},quota}},#[fg={yellow}#,bg={b02}#,nobold],#{{?#{{==:#{{@ide_ai_state}},running}},#[fg={cyan}#,bg={b02}#,nobold],#[fg=#{{?#{{==:#{{@ide_ai_parked}},1}},{b01},{b0}}}#,bg={b02}#,nobold]}}}}}}}}󰚩 #{{?#{{!=:#{{@ide_ai_cli}},}},#{{@ide_ai_cli}},AI}}#{{?#{{==:#{{@ide_ai_parked}},1}},#{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},95}}}}, [Alt+A], [A]}},#{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},95}}}}, (Alt+a),}}}}}}'
set -g @ide_tab_ed '#{{?#{{==:#{{@ide_role}},editor}},#[fg={blue}#,bg={b02}#,nobold]▸  #[fg={b1}#,bg={b02}#,nobold]Editor#{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},95}}}}, (Alt+e),}},#{{?#{{==:#{{@ide_ed_parked}},1}},#[fg={b01}#,bg={b02}#,nobold] Editor #{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},95}}}},[Alt+E],[E]}},#[fg={b0}#,bg={b02}#,nobold] Editor#{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},95}}}}, (Alt+e),}}}}}}'
set -g @ide_tab_term '#{{?#{{==:#{{@ide_role}},term}},#[fg={green}#,bg={b02}#,nobold]▸  #[fg={b1}#,bg={b02}#,nobold]Shell#{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},95}}}}, (Alt+t) , }},#{{?#{{==:#{{@ide_term_parked}},1}},#[fg={b01}#,bg={b02}#,nobold] Shell #{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},95}}}},[Alt+T] ,[T] }},#[fg={b0}#,bg={b02}#,nobold] Shell#{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},95}}}}, (Alt+t) , }}}}}}'

setw -g window-status-format "#{{?#{{m/r:^_ide_park_,#W}},,#[fg={b01}#,bg={b02}#,nobold] #I:#W }}"
setw -g window-status-current-format "#{{?#{{==:#W,ide}},#[range=user|tab_ai]#{{E:@ide_tab_ai}}#[norange]#[fg={b01}#,bg={b02}#,nobold] · #[range=user|tab_editor]#{{E:@ide_tab_ed}}#[norange]#[fg={b01}#,bg={b02}#,nobold] · #[range=user|tab_term]#{{E:@ide_tab_term}}#[norange]#{{?window_zoomed_flag,#[fg={b00}#,bg={b02}#,nobold] #[range=user|tab_zoom]#[fg={orange}#,bg={b02}#,nobold]󰁌 ZOOM#{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},95}}}}, (Alt+z) , }}#[norange],}},#[fg={b1}#,bg={b02}#,nobold] #I:#W#{{?window_zoomed_flag, #[fg={orange}]󰁌 ZOOM,}} }}"
setw -g window-status-separator ""

set -g status-right "#{{?client_prefix,#[fg={b00}#,bg={b02}#,nobold] #[fg={orange}#,bg={b02}#,nobold]󰘳 PREFIX #[fg={b00}#,bg={b02}#,nobold] #[fg={b0}#,bg={b02}#,nobold]#{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},120}}}},HJKL resize · |/- split · b bar · ? keys ,? keys }},#{{?pane_in_mode,#[fg={b00}#,bg={b02}#,nobold] #[fg={magenta}#,bg={b02}#,nobold]󰆏 COPY#{{?#{{!=:#{{scroll_position}},}}, [#{{scroll_position}}/#{{history_size}}],}} #[fg={b00}#,bg={b02}#,nobold] #[fg={b0}#,bg={b02}#,nobold]#{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},120}}}},a send to AI · Alt+c copy · Esc clear ,a->AI · Esc }},#{{?pane_synchronized,#[fg={b00}#,bg={b02}#,nobold] #[fg={red}#,bg={b02}#,nobold]󰓦 SYNC ,}}#{{?#{{&&:#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},105}}}},#{{||:#{{!=:#{{SSH_CONNECTION}},}},#{{!=:#{{SSH_TTY}},}}}}}},#[fg={b00}#,bg={b02}#,nobold] #[fg={violet}#,bg={b02}#,nobold]󰣀 #h ,}}#{{?#{{&&:#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},105}}}},#{{&&:#{{!=:#{{@ide_workdir}},}},#{{!=:#{{@ide_workdir}},#{{@ide_initial_root}}}}}}}},#[fg={b00}#,bg={b02}#,nobold] #[fg={blue}#,bg={b02}#,nobold]󰉋 #{{b:@ide_workdir}} ,}}{attn_right_segment}{fleet_right_segment}{holiday_right_segment}#[fg={b00}#,bg={b02}#,nobold] #[range=user|help]#[fg={b0}#,bg={b02}#,nobold]󰋖 #{{?#{{||:#{{e|<=:#{{client_width}},0}},#{{e|>=:#{{client_width}},120}}}},Help (Alt+?) ,? }}#[range=right]}}}}"
"""
