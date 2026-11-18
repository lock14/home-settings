#!/usr/bin/env bash
# Test suite for bin/theme unified multi-theme color scheme manager and terminal profile provisioners

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/tests/test-helper.sh"

echo "========================================"
echo "Running Theme Manager & Palette Tests"
echo "========================================"

THEME_TEST_HOME=""
BAK_TEST_HOME=""
MACOS_MOCK_HOME=""
GT_TEST_HOME=""
FZF_MOCK_BIN=""
LIVE_TMUX_TMP=""
LIVE_NVIM_PID=""
STANDALONE_NVIM_PID=""

cleanup_test_theme() {
    if [ -n "${LIVE_NVIM_PID:-}" ]; then
        kill "$LIVE_NVIM_PID" 2>/dev/null || true
    fi
    if [ -n "${STANDALONE_NVIM_PID:-}" ]; then
        kill "$STANDALONE_NVIM_PID" 2>/dev/null || true
    fi
    if [ -n "${LIVE_TMUX_TMP:-}" ] && [ -d "$LIVE_TMUX_TMP" ]; then
        tmux -S "$LIVE_TMUX_TMP/tmux-$(id -u)/default" kill-server >/dev/null 2>&1 || true
        rm -rf "$LIVE_TMUX_TMP"
    fi
    local d
    for d in "$THEME_TEST_HOME" "$BAK_TEST_HOME" "$MACOS_MOCK_HOME" "$GT_TEST_HOME" "$FZF_MOCK_BIN"; do
        if [ -n "$d" ] && [ -d "$d" ]; then
            rm -rf "$d"
        fi
    done
    _hs_cleanup_test_runtime_dir
}
trap cleanup_test_theme EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# Test 1: bin/theme unified multi-theme color scheme manager
echo -e "\n[1/1] Testing bin/theme unified multi-theme manager..."
unset HOME_SETTINGS_THEME HOME_SETTINGS_THEME_MODE HOME_SETTINGS_THEME_FILE THEME_NVIM_SOCKET_DIR THEME_SKIP_NVIM_SOCKET
THEME_TEST_HOME="$(mktemp -d)"
export THEME_TEST_Cfg="$THEME_TEST_HOME/.config"
export THEME_TEST_Cache="$THEME_TEST_HOME/.cache"
mkdir -p "$THEME_TEST_Cfg" "$THEME_TEST_Cache"

THEME_HELP="$("$SCRIPT_DIR/bin/theme" --help 2>&1)"
if grep -Fq "Usage: theme [OPTIONS] [THEME_NAME]" <<< "$THEME_HELP" && \
   grep -Fq -- "--list" <<< "$THEME_HELP" && \
   grep -Fq -- "--plain" <<< "$THEME_HELP" && \
   grep -Fq -- "--current" <<< "$THEME_HELP" && \
   grep -Fq -- "--set" <<< "$THEME_HELP" && \
   grep -Fq -- "--preview" <<< "$THEME_HELP" && \
   grep -Fq -- "--env" <<< "$THEME_HELP" && \
   grep -Fq -- "--create" <<< "$THEME_HELP" && \
   grep -Fq -- "--path" <<< "$THEME_HELP" && \
   grep -Fq -- "--dry-run" <<< "$THEME_HELP" && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --invalid-flag >/dev/null 2>&1 && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --set nonexistent-theme >/dev/null 2>&1 && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" "" >/dev/null 2>&1 && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --set="" >/dev/null 2>&1 && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --set --help >/dev/null 2>&1 && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --create --sync-assets >/dev/null 2>&1; then
    pass "bin/theme supports -h/--help (including --plain) and rejects unknown flags, empty names, missing option values (--set --help), and nonexistent themes"
else
    fail "bin/theme CLI validation" "Unexpected --help or error handling output"
fi

# Verify default --current and --list across all 17 built-in themes (9 classic + 8 US Holiday)
CUR_DEFAULT="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --current)"
LIST_PLAIN="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --list --plain)"
LIST_FULL="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --list)"
managed_themes=(
    "solarized-dark"
    "solarized-light"
    "catppuccin-mocha"
    "catppuccin-latte"
    "gruvbox-dark"
    "tokyonight-night"
    "kanagawa-wave"
    "nord"
    "onedark"
    "new-years"
    "valentines"
    "st-patricks"
    "easter"
    "independence-day"
    "halloween"
    "thanksgiving"
    "christmas"
)
all_listed=true
for t in "${managed_themes[@]}"; do
    if ! grep -Fxq "$t" <<< "$LIST_PLAIN" || ! grep -Fq "$t" <<< "$LIST_FULL"; then
        all_listed=false
        fail "bin/theme --list" "Missing managed theme '$t' in --list output"
    fi
done
if [ "$CUR_DEFAULT" = "solarized-dark" ] && [ "$all_listed" = true ] && grep -Fq "* solarized-dark" <<< "$LIST_FULL"; then
    pass "bin/theme defaults to solarized-dark and lists all 17 built-in themes (9 classic + 8 US Holiday)"
else
    fail "bin/theme default & list" "cur='$CUR_DEFAULT' all_listed='$all_listed'"
fi

# Verify --holiday resolves nearest upcoming US Holiday (e.g. Oct 25 -> halloween, Nov 20 -> thanksgiving)
HOLIDAY_OCT="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" THEME_HOLIDAY_DATE="2026-10-25" "$SCRIPT_DIR/bin/theme" --holiday --dry-run)"
HOLIDAY_NOV="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" THEME_HOLIDAY_DATE="2026-11-20" "$SCRIPT_DIR/bin/theme" --holiday --dry-run)"
if grep -Fq "Halloween (halloween" <<< "$HOLIDAY_OCT" && grep -Fq "Thanksgiving (thanksgiving" <<< "$HOLIDAY_NOV"; then
    pass "bin/theme --holiday resolves the nearest upcoming US Holiday theme (fixed and movable dates)"
else
    fail "bin/theme --holiday" "Unexpected holiday resolution: oct='$HOLIDAY_OCT' nov='$HOLIDAY_NOV'"
fi

# Verify --preview and --env for managed themes (including pre-compiled TrueColor LS_COLORS with literal *# glob)
PREVIEW_MOCHA="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --preview catppuccin-mocha)"
ENV_NORD="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --env nord)"
if grep -Fq "Catppuccin Mocha" <<< "$PREVIEW_MOCHA" && \
   grep -Fq "catppuccin-mocha | dark | builtin" <<< "$PREVIEW_MOCHA" && \
   grep -Fq $'\033[38;2;' <<< "$PREVIEW_MOCHA" && \
   grep -Fq "Converged Semantic Code Preview:" <<< "$PREVIEW_MOCHA" && \
   grep -Fq 'export HOME_SETTINGS_THEME="nord"' <<< "$ENV_NORD" && \
   grep -Fq 'export BAT_THEME="Nord-TrueColor"' <<< "$ENV_NORD" && \
   grep -Fq "export LS_COLORS='" <<< "$ENV_NORD" && \
   grep -Fq ':di=38;2;129;161;193:' <<< "$ENV_NORD" && \
   grep -Fq ':*#=38;2;132;146;172:' <<< "$ENV_NORD" && \
   grep -Fq 'export FZF_DEFAULT_OPTS=' <<< "$ENV_NORD" && \
   grep -Fq 'export EZA_COLORS=' <<< "$ENV_NORD" && \
   grep -Fq 'export JQ_COLORS=' <<< "$ENV_NORD"; then
    pass "bin/theme --preview renders TrueColor palette & syntax sample and --env emits POSIX shell exports including complete TrueColor LS_COLORS (*# preserved)"
else
    fail "bin/theme --preview / --env" "Missing expected preview or env output"
fi

# Verify --dry-run does not mutate state
DRY_OUT="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --dry-run tokyonight-night)"
if grep -Fq "[DRY-RUN] Theme: TokyoNight Night (tokyonight-night" <<< "$DRY_OUT" && \
   [ ! -f "$THEME_TEST_Cfg/home-settings/theme" ]; then
    pass "bin/theme --dry-run previews planned mutations without writing state files"
else
    fail "bin/theme --dry-run" "State file created during --dry-run or missing output: $DRY_OUT"
fi

# Verify sync_symlink backs up pre-existing physical ~/.config directories and files to .bak.<ts> without data loss
BAK_TEST_HOME="$(mktemp -d)"
mkdir -p "$BAK_TEST_HOME/.config/ghostty" "$BAK_TEST_HOME/.config/btop" "$BAK_TEST_HOME/.config/tealdeer" "$BAK_TEST_HOME/.config/git"
echo "user-ghostty" > "$BAK_TEST_HOME/.config/ghostty/local.conf"
echo "user-btop" > "$BAK_TEST_HOME/.config/btop/local.conf"
echo "user-tealdeer" > "$BAK_TEST_HOME/.config/tealdeer/local.toml"
echo "user-gitconfig" > "$BAK_TEST_HOME/.config/git/config"
echo "*.secret" > "$BAK_TEST_HOME/.config/git/ignore"
HOME="$BAK_TEST_HOME" XDG_CONFIG_HOME="$BAK_TEST_HOME/.config" XDG_CACHE_HOME="$BAK_TEST_HOME/.cache" "$SCRIPT_DIR/bin/theme" --set nord --no-live >/dev/null 2>&1
bak_gt=("$BAK_TEST_HOME"/.config/ghostty.bak.*)
bak_bt=("$BAK_TEST_HOME"/.config/btop.bak.*)
bak_td=("$BAK_TEST_HOME"/.config/tealdeer.bak.*)
bak_gc=("$BAK_TEST_HOME"/.config/git/config.bak.*)
if [ -L "$BAK_TEST_HOME/.config/ghostty" ] && [ -f "${bak_gt[0]}/local.conf" ] && \
   [ -L "$BAK_TEST_HOME/.config/btop" ] && [ -f "${bak_bt[0]}/local.conf" ] && \
   [ -L "$BAK_TEST_HOME/.config/tealdeer" ] && [ -f "${bak_td[0]}/local.toml" ] && \
   [ -d "$BAK_TEST_HOME/.config/git" ] && [ ! -L "$BAK_TEST_HOME/.config/git" ] && \
   [ -L "$BAK_TEST_HOME/.config/git/config" ] && [ -f "${bak_gc[0]}" ] && \
   [ -f "$BAK_TEST_HOME/.config/git/ignore" ]; then
    pass "bin/theme sync_symlink backs up pre-existing physical ~/.config/{ghostty,btop,tealdeer} directories and ~/.config/git/config to .bak.<ts> while preserving ~/.config/git/ignore"
else
    fail "bin/theme physical directory backup" "Missing .bak.<ts> backups or clobbered ~/.config/git/ignore"
fi
rm -rf "$BAK_TEST_HOME"

# Provision dotfiles into THEME_TEST_HOME and test switching across all 17 managed themes while preserving ~/.config/git/{ignore,attributes}
HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/modules/10-dotfiles.sh" >/dev/null 2>&1
echo "*.swp" > "$THEME_TEST_Cfg/git/ignore"
echo "*.lock linguist-generated" > "$THEME_TEST_Cfg/git/attributes"

all_switches_ok=true
for t in "${managed_themes[@]}"; do
    HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" --set "$t" --no-live >/dev/null 2>&1
    cur_after="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --current)"
    if [ "$cur_after" != "$t" ] || \
       [ ! -f "$THEME_TEST_Cfg/home-settings/active-theme.theme" ] || \
       [ ! -f "$THEME_TEST_Cfg/home-settings/theme-env.sh" ] || \
       [ ! -f "$THEME_TEST_Cfg/home-settings/zsh-theme.zsh" ] || \
       [ ! -f "$THEME_TEST_Cfg/home-settings/p10k-theme.zsh" ] || \
       [ ! -f "$THEME_TEST_Cfg/home-settings/tmux-theme.conf" ] || \
       ! grep -Fq '#{&&:#{==:#{@ide_ai_state},done},#{==:#{@ide_ai_attn},1}}' "$THEME_TEST_Cfg/home-settings/tmux-theme.conf" || \
       [ ! -L "$THEME_TEST_Cfg/ghostty" ] || \
       [ ! -L "$THEME_TEST_Cfg/btop" ] || \
       [ ! -d "$THEME_TEST_Cfg/git" ] || [ -L "$THEME_TEST_Cfg/git" ] || \
       [ ! -L "$THEME_TEST_Cfg/git/config" ] || \
       [ ! -f "$THEME_TEST_Cfg/git/ignore" ] || \
       [ ! -f "$THEME_TEST_Cfg/git/attributes" ] || \
       [ ! -L "$THEME_TEST_Cfg/tealdeer" ]; then
        all_switches_ok=false
        fail "bin/theme switch $t" "Failed to materialize state or config symlinks for '$t' (cur='$cur_after')"
        break
    fi
done

# Check light mode vs dark mode config propagation (e.g. solarized-light vs catppuccin-mocha)
HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" solarized-light --no-live >/dev/null 2>&1
if grep -Fq "light = true" "$THEME_TEST_Cfg/git/config" && \
   grep -Fq "syntax-theme = Solarized-Light-TrueColor" "$THEME_TEST_Cfg/git/config" && \
   grep -Fq 'commit-style = "#d33682"' "$THEME_TEST_Cfg/git/config" && \
   grep -Fq 'file-style = "#2aa198"' "$THEME_TEST_Cfg/git/config" && \
   grep -Fq 'plus-style = syntax "#e5ecd0"' "$THEME_TEST_Cfg/git/config" && \
   ! grep -Fq 'plus-emph-style = syntax "#e5ecd0"' "$THEME_TEST_Cfg/git/config" && \
   grep -Fq 'color_theme = "solarized_light"' "$THEME_TEST_Cfg/btop/btop.conf" && \
   grep -Fq 'proc_mem_bytes = true' "$THEME_TEST_Cfg/btop/btop.conf" && \
   grep -Fq 'theme = "Solarized Light"' "$THEME_TEST_Cfg/ghostty/config" && \
   grep -Fq 'cursor-text = #fdf6e3' "$SCRIPT_DIR/dotfiles/.config/ghostty/themes/Solarized Light" && \
   grep -Fq 'm/r:^_ide_park_,#W' "$THEME_TEST_Cfg/home-settings/tmux-theme.conf" && \
   grep -Fq "r = 38, g = 139, b = 210" <<< "$(grep -A1 '\[style\.example_text\]' "$THEME_TEST_Cfg/tealdeer/config.toml")" && \
   grep -Fq "r = 42, g = 161, b = 152" <<< "$(grep -A1 '\[style\.example_code\]' "$THEME_TEST_Cfg/tealdeer/config.toml")"; then
    :
else
    all_switches_ok=false
    fail "bin/theme solarized-light config propagation" "Expected light=true, cursor-text=BASE03, distinct plus-emph-style, full btop.conf, _ide_park_ tmux guard, and Blue/Cyan tealdeer styles"
fi

# Verify dotfiles/.tmux.conf sources ~/.config/home-settings/tmux-theme.conf even when XDG_CONFIG_HOME is unset
if command -v tmux >/dev/null 2>&1; then
    TMUX_THEME_SOCK="$THEME_TEST_HOME/tmux-theme.sock"
    (
        unset XDG_CONFIG_HOME
        HOME="$THEME_TEST_HOME" tmux -S "$TMUX_THEME_SOCK" -f "$SCRIPT_DIR/dotfiles/.tmux.conf" new-session -d -s theme_chk "cat" >/dev/null 2>&1
    )
    TMUX_LOADED_STYLE="$(HOME="$THEME_TEST_HOME" tmux -S "$TMUX_THEME_SOCK" show-options -g -v status-style 2>/dev/null || true)"
    HOME="$THEME_TEST_HOME" tmux -S "$TMUX_THEME_SOCK" kill-server >/dev/null 2>&1 || true
    rm -f "$TMUX_THEME_SOCK"
    if [ "$TMUX_LOADED_STYLE" != "fg=#657B83,bg=#EEE8D5" ]; then
        all_switches_ok=false
        fail "dotfiles/.tmux.conf theme sourcing with unset XDG_CONFIG_HOME" "Expected 'fg=#657B83,bg=#EEE8D5', got '$TMUX_LOADED_STYLE'"
    fi
fi

# Switch back to solarized-dark and verify symlinks point back to repo dotfiles without dirtying git repo
HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" solarized-dark --no-live >/dev/null 2>&1
if [ "$all_switches_ok" = true ] && \
   [ "$(readlink "$THEME_TEST_Cfg/btop")" = "$SCRIPT_DIR/dotfiles/.config/btop" ] && \
   [ -d "$THEME_TEST_Cfg/git" ] && [ ! -L "$THEME_TEST_Cfg/git" ] && \
   [ "$(readlink "$THEME_TEST_Cfg/git/config")" = "$SCRIPT_DIR/dotfiles/.config/git/config" ] && \
   [ "$(cat "$THEME_TEST_Cfg/git/ignore")" = "*.swp" ]; then
    pass "bin/theme switches cleanly across all 17 managed themes (dark & light), preserves ~/.config/git/{ignore,attributes}, and updates ghostty, btop, delta, tealdeer, tmux, and shell state without dirtying tracked dotfiles"
else
    fail "bin/theme 17-theme cycle" "Failed switching or restoring symlinks"
fi

# Verify monotonic luminance ramp, canvas & shelf contrast, and semantic utility separation across ALL 17 built-in themes
if python3 -B - "$SCRIPT_DIR" "$THEME_TEST_HOME" "$THEME_TEST_Cfg" "$THEME_TEST_Cache" <<'PY'; then
from __future__ import annotations

import pathlib
import re
import subprocess
import sys

sys.dont_write_bytecode = True
repo = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(repo / "bin"))

from theme_lib.palette import (
    CLASSIC_THEMES as classic,
    HOLIDAY_THEMES as holidays,
    contrast_ratio as contrast,
    hex_to_rgb,
    hue_difference as hue_diff,
    parse_theme_file,
    relative_luminance,
    rgb_distance as rgb_dist,
)

test_home = sys.argv[2]
test_cfg = sys.argv[3]
test_cache = sys.argv[4]

accents = ["YELLOW", "ORANGE", "RED", "MAGENTA", "VIOLET", "BLUE", "CYAN", "GREEN"]
ramp_keys = ["BASE03", "BASE02", "BASE01", "BASE00", "BASE0", "BASE1"]

for slug in classic + holidays:
    p = repo / "colors" / "themes" / f"{slug}.theme"
    d = parse_theme_file(p, default_slug=slug, source="builtin")

    is_light = d.get("THEME_MODE", "dark") == "light"
    lums = [relative_luminance(d[k]) for k in ramp_keys]
    for idx in range(len(ramp_keys) - 1):
        if is_light and not (lums[idx] > lums[idx + 1]):
            raise SystemExit(f"{slug}: non-monotonic light ramp {ramp_keys[idx]} ({d[ramp_keys[idx]]}) -> {ramp_keys[idx+1]} ({d[ramp_keys[idx+1]]})")
        if not is_light and not (lums[idx] < lums[idx + 1]):
            raise SystemExit(f"{slug}: non-monotonic dark ramp {ramp_keys[idx]} ({d[ramp_keys[idx]]}) -> {ramp_keys[idx+1]} ({d[ramp_keys[idx+1]]})")

    if contrast(d["BASE01"], d["BASE03"]) < 2.3 or contrast(d["BASE01"], d["BASE02"]) < 2.0:
        raise SystemExit(f"{slug}: BASE01 ({d['BASE01']}) contrast too low against BASE03/BASE02")
    if contrast(d["BASE00"], d["BASE02"]) < 2.5 or contrast(d["BASE00"], d["BASE03"]) < 2.9:
        raise SystemExit(f"{slug}: BASE00 ({d['BASE00']}) contrast too low against BASE02/BASE03")
    if slug in ("nord", "catppuccin-latte") or slug in holidays:
        for rk in ("BASE01", "BASE00", "BASE0", "BASE1"):
            if contrast(d[rk], d["BASE02"]) < 3.0 or contrast(d[rk], d["BASE03"]) < 3.0:
                raise SystemExit(f"{slug}: {rk} ({d[rk]}) contrast < 3.0 against BASE02 ({d['BASE02']}) or BASE03 ({d['BASE03']})")

    gr_d = rgb_dist(d["GREEN"], d["RED"])
    gr_h = hue_diff(d["GREEN"], d["RED"])
    yr_d = rgb_dist(d["YELLOW"], d["RED"])
    yr_h = hue_diff(d["YELLOW"], d["RED"])
    yg_d = rgb_dist(d["YELLOW"], d["GREEN"])
    mix_d = rgb_dist(d["MIX_GREEN"], d["MIX_RED"])

    if gr_d < 190 or gr_h < 28:
        raise SystemExit(f"{slug}: GREEN ({d['GREEN']}) vs RED ({d['RED']}) too close: dist={gr_d:.1f} hue={gr_h:.1f}")
    if yr_d < (220 if slug in holidays else 120) or yr_h < 25:
        raise SystemExit(f"{slug}: YELLOW ({d['YELLOW']}) vs RED ({d['RED']}) too close: dist={yr_d:.1f} hue={yr_h:.1f}")
    if yg_d < (200 if slug in holidays else 80):
        raise SystemExit(f"{slug}: YELLOW ({d['YELLOW']}) vs GREEN ({d['GREEN']}) too close: dist={yg_d:.1f}")
    if mix_d < 30:
        raise SystemExit(f"{slug}: MIX_GREEN ({d['MIX_GREEN']}) vs MIX_RED ({d['MIX_RED']}) too close: dist={mix_d:.1f}")

    rg, gg, bg = hex_to_rgb(d["MIX_GREEN"])
    rr, gr, br = hex_to_rgb(d["MIX_RED"])
    if (gg - rg) <= (gr - rr) + 15:
        raise SystemExit(f"{slug}: MIX_GREEN ({d['MIX_GREEN']}) vs MIX_RED ({d['MIX_RED']}) lacks green/red polarity")

    or_r, or_g, or_b = hex_to_rgb(d["ORANGE"])
    if not (or_r > or_g > or_b):
        raise SystemExit(f"{slug}: ORANGE ({d['ORANGE']}) is not a warm orange/ember hue (R > G > B)")

    if contrast(d["BASE0"], d["BASE03"]) < (7.0 if slug in holidays else 4.0):
        raise SystemExit(f"{slug}: BASE0 contrast against BASE03 too low")

    for i in range(len(accents)):
        min_c = 3.0 if (slug in holidays or slug == "catppuccin-latte") else 2.8
        min_shelf_c = 3.0 if slug == "catppuccin-latte" else 2.2
        if contrast(d[accents[i]], d["BASE03"]) < min_c:
            raise SystemExit(f"{slug}: {accents[i]} ({d[accents[i]]}) contrast against BASE03 < {min_c}")
        if contrast(d[accents[i]], d["BASE02"]) < min_shelf_c:
            raise SystemExit(f"{slug}: {accents[i]} ({d[accents[i]]}) contrast against BASE02 shelf < {min_shelf_c}")
        if slug in holidays:
            for j in range(i + 1, len(accents)):
                pair_d = rgb_dist(d[accents[i]], d[accents[j]])
                if pair_d < 100:
                    raise SystemExit(f"{slug}: {accents[i]} ({d[accents[i]]}) vs {accents[j]} ({d[accents[j]]}) dist={pair_d:.1f} < 100")

# Verify generated zsh-theme.zsh, git/config, p10k-theme.zsh, theme-env.sh, and tmux-theme.conf for holiday vs classic
env = {"HOME": test_home, "XDG_CONFIG_HOME": test_cfg, "XDG_CACHE_HOME": test_cache, "PATH": "/usr/bin:/bin"}
cfg_root = pathlib.Path(test_cfg)
for slug in ("independence-day", "christmas", "valentines", "easter", "halloween"):
    subprocess.run([str(repo / "bin" / "theme"), "--set", slug, "--no-live"], env=env, stdout=subprocess.DEVNULL, check=True)
    zsh_txt = (cfg_root / "home-settings" / "zsh-theme.zsh").read_text(encoding="utf-8")
    cmd_col = re.search(r'ZSH_HIGHLIGHT_STYLES\[command\]="fg=(#[0-9A-Fa-f]{6})"', zsh_txt).group(1)
    unk_col = re.search(r'ZSH_HIGHLIGHT_STYLES\[unknown-token\]="fg=(#[0-9A-Fa-f]{6})"', zsh_txt).group(1)
    res_col = re.search(r'ZSH_HIGHLIGHT_STYLES\[reserved-word\]="fg=(#[0-9A-Fa-f]{6})"', zsh_txt).group(1)
    if rgb_dist(cmd_col, unk_col) < 190 or rgb_dist(res_col, unk_col) < 190 or rgb_dist(cmd_col, res_col) < 150:
        raise SystemExit(f"{slug}: zsh-theme.zsh command/reserved-word/unknown-token collision: {cmd_col}, {res_col}, {unk_col}")

    git_txt = (cfg_root / "git" / "config").read_text(encoding="utf-8")
    plus_emph = re.search(r'plus-emph-style = syntax "(#[0-9a-f]{6})"', git_txt).group(1)
    minus_emph = re.search(r'minus-emph-style = syntax "(#[0-9a-f]{6})"', git_txt).group(1)
    pe_r, pe_g, _ = hex_to_rgb(plus_emph)
    me_r, me_g, _ = hex_to_rgb(minus_emph)
    if (pe_g - pe_r) <= (me_g - me_r) + 20:
        raise SystemExit(f"{slug}: git delta plus-emph-style ({plus_emph}) vs minus-emph-style ({minus_emph}) lacks green/red polarity")

    env_txt = (cfg_root / "home-settings" / "theme-env.sh").read_text(encoding="utf-8")
    p10k_txt = (cfg_root / "home-settings" / "p10k-theme.zsh").read_text(encoding="utf-8")
    tmux_txt = (cfg_root / "home-settings" / "tmux-theme.conf").read_text(encoding="utf-8")
    if "export _HS_PROMPT_OS_ICON=" not in env_txt or "POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION=" not in p10k_txt or "" in tmux_txt:
        raise SystemExit(f"{slug}: missing holiday emblem in theme-env.sh, p10k-theme.zsh, or tmux-theme.conf")

subprocess.run([str(repo / "bin" / "theme"), "--set", "solarized-dark", "--no-live"], env=env, stdout=subprocess.DEVNULL, check=True)
env_txt = (cfg_root / "home-settings" / "theme-env.sh").read_text(encoding="utf-8")
p10k_txt = (cfg_root / "home-settings" / "p10k-theme.zsh").read_text(encoding="utf-8")
tmux_txt = (cfg_root / "home-settings" / "tmux-theme.conf").read_text(encoding="utf-8")
if "unset _HS_PROMPT_OS_ICON" not in env_txt or "unset POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION" not in p10k_txt or " #S" not in tmux_txt:
    raise SystemExit("solarized-dark: failed to restore neutral OS/Tmux icons")
PY
    pass "All 17 built-in themes maintain monotonic BASE03..BASE1 luminance ramps, canvas & shelf contrast, strict semantic utility separation, opposing MIX_GREEN/MIX_RED diff polarity, and holiday prompt/Tmux emblems"
else
    fail "17-theme monotonic ramp, contrast & semantic utility" "One or more themes violated ramp monotonicity, contrast, or diff polarity invariants"
fi

# Verify custom user themes (--path, --create, --from, --force, apply custom theme, re-apply regeneration, and reject invalid hex)
USER_THEMES_PATH="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --path)"
assert_eq "$USER_THEMES_PATH" "$THEME_TEST_Cfg/themes" "bin/theme --path outputs XDG user themes directory"

HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --create cyber-custom --from kanagawa-wave >/dev/null 2>&1
if [ -f "$THEME_TEST_Cfg/themes/cyber-custom.theme" ] && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --create cyber-custom >/dev/null 2>&1 && \
   HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --create cyber-custom --from nord --force >/dev/null 2>&1; then
    sed -i.bak 's/^BASE03=.*/BASE03="#112233"/' "$THEME_TEST_Cfg/themes/cyber-custom.theme"
    rm -f "$THEME_TEST_Cfg/themes/cyber-custom.theme.bak"
    HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" cyber-custom --no-live >/dev/null 2>&1
    # Edit custom theme and re-apply to verify Ghostty and btop custom theme files are regenerated (M2)
    sed -i.bak 's/^BASE03=.*/BASE03="#1A2B3C"/' "$THEME_TEST_Cfg/themes/cyber-custom.theme"
    rm -f "$THEME_TEST_Cfg/themes/cyber-custom.theme.bak"
    HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" cyber-custom --no-live >/dev/null 2>&1
    if [ "$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --current)" = "cyber-custom" ] && \
       grep -Fq 'BASE03="#1A2B3C"' "$THEME_TEST_Cfg/home-settings/active-theme.theme" && \
       [ -f "$THEME_TEST_Cfg/bat/themes/Cyber-Custom-TrueColor.tmTheme" ] && \
       grep -Fq '#1a2b3c' "$THEME_TEST_Cfg/btop/themes/cyber_custom.theme" && \
       grep -Fq 'background = #1a2b3c' "$THEME_TEST_Cfg/ghostty/themes/Cyber Custom"; then
        pass "bin/theme --create scaffolds custom user theme (--from / --force) and regenerates custom .tmTheme, btop, and ghostty assets on re-apply"
    else
        fail "bin/theme custom theme apply/re-apply" "Custom theme assets or state were not regenerated on re-apply"
    fi
else
    fail "bin/theme --create" "Failed to scaffold or guard custom user theme file"
fi

# Verify macOS Ghostty Application Support symlinking + SIGUSR2 reload (M1), OS=macos terminal broadcast, and macos-terminal-solarized cfprefsd-safe export/import + .conf encoding (M3)
MACOS_MOCK_HOME="$(mktemp -d)"
MACOS_MOCK_BIN="$MACOS_MOCK_HOME/mock-bin"
mkdir -p "$MACOS_MOCK_HOME/Library/Application Support" "$MACOS_MOCK_HOME/Library/Preferences" "$MACOS_MOCK_HOME/.config/themes" "$MACOS_MOCK_BIN"
cat > "$MACOS_MOCK_BIN/pkill" <<'SH'
#!/usr/bin/env bash
echo "pkill $*" >> "$MACOS_PKILL_LOG"
exit 0
SH
cat > "$MACOS_MOCK_BIN/defaults" <<'SH'
#!/usr/bin/env bash
echo "defaults $*" >> "$MACOS_DEFAULTS_LOG"
if [ "${1:-}" = "export" ] && [ "${2:-}" = "com.apple.Terminal" ] && [ "${3:-}" = "-" ]; then
    if [ -f "$HOME/Library/Preferences/com.apple.Terminal.plist" ]; then
        cat "$HOME/Library/Preferences/com.apple.Terminal.plist"
    else
        python3 - <<'PY'
import plistlib, sys
plistlib.dump({"Window Settings": {"ExistingCustomProfile": {"FontAntialias": True}}}, sys.stdout.buffer)
PY
    fi
    exit 0
fi
if [ "${1:-}" = "import" ] && [ "${2:-}" = "com.apple.Terminal" ] && [ -f "${3:-}" ]; then
    exit 0
fi
if [ "${1:-}" = "write" ]; then
    exit 1
fi
exit 0
SH
cat > "$MACOS_MOCK_BIN/pgrep" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$MACOS_MOCK_BIN/pkill" "$MACOS_MOCK_BIN/defaults" "$MACOS_MOCK_BIN/pgrep"
cat > "$MACOS_MOCK_HOME/.config/themes/conf-file.conf" <<'EOF'
export THEME_ID='decoupled-macos' # decoupled slug in .conf
THEME_LABEL="Mac Custom 🌙" # non-BMP label
BASE03='#122334' # custom bg
EOF
MACOS_PKILL_LOG="$MACOS_MOCK_HOME/pkill.log" MACOS_DEFAULTS_LOG="$MACOS_MOCK_HOME/defaults.log" OS=macos THEME_LIVE_NVIM=0 NVIM_IDE_SOCKET="" TMUX="" TMUX_TMPDIR="" PATH="$MACOS_MOCK_BIN:$PATH" HOME="$MACOS_MOCK_HOME" XDG_CONFIG_HOME="$MACOS_MOCK_HOME/.config" XDG_CACHE_HOME="$MACOS_MOCK_HOME/.cache" "$SCRIPT_DIR/bin/theme" --set nord >/dev/null 2>&1
if [ -L "$MACOS_MOCK_HOME/Library/Application Support/com.mitchellh.ghostty/config" ] && \
   [ -L "$MACOS_MOCK_HOME/Library/Application Support/com.mitchellh.ghostty/themes" ] && \
   grep -Fq -- "-USR2" "$MACOS_MOCK_HOME/pkill.log" && \
   grep -Fq "ghostty" "$MACOS_MOCK_HOME/pkill.log"; then
    pass "bin/theme links macOS ~/Library/Application Support/com.mitchellh.ghostty/{config,themes} and broadcasts SIGUSR2 reload"
else
    fail "bin/theme macOS Ghostty support" "Missing Application Support symlinks or SIGUSR2 pkill reload"
fi

if [ -f "$MACOS_MOCK_HOME/Library/Preferences/com.apple.Terminal.plist" ] && \
   MACOS_DEFAULTS_LOG="$MACOS_MOCK_HOME/defaults.log" OS=macos PATH="$MACOS_MOCK_BIN:$PATH" HOME="$MACOS_MOCK_HOME" XDG_CONFIG_HOME="$MACOS_MOCK_HOME/.config" "$SCRIPT_DIR/bin/macos-terminal-solarized" --theme decoupled-macos >/dev/null 2>&1 && \
   ! MACOS_DEFAULTS_LOG="$MACOS_MOCK_HOME/defaults.log" OS=macos PATH="$MACOS_MOCK_BIN:$PATH" HOME="$MACOS_MOCK_HOME" XDG_CONFIG_HOME="$MACOS_MOCK_HOME/.config" "$SCRIPT_DIR/bin/macos-terminal-solarized" --theme nonexistent-xyz >/dev/null 2>&1 && \
   grep -Fq "defaults export com.apple.Terminal -" "$MACOS_MOCK_HOME/defaults.log" && \
   grep -Fq "defaults import com.apple.Terminal" "$MACOS_MOCK_HOME/defaults.log" && \
   ! grep -Fq "defaults write" "$MACOS_MOCK_HOME/defaults.log" && \
   python3 - "$MACOS_MOCK_HOME/Library/Preferences/com.apple.Terminal.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    pl = plistlib.load(f)
assert "ExistingCustomProfile" in pl["Window Settings"]
assert "Nord" in pl["Window Settings"]
prof_nord = pl["Window Settings"]["Nord"]
bg_nord = plistlib.loads(prof_nord["BackgroundColor"])
rgb_nord = bg_nord["$objects"][1]["NSRGB"].decode("ascii").rstrip("\x00")
assert tuple(round(float(x) * 255) for x in rgb_nord.split()) == (0x2E, 0x34, 0x40)
assert len([k for k in prof_nord if k.startswith("ANSI") and k.endswith("Color")]) == 16
assert "blackColour" not in prof_nord
assert pl["Default Window Settings"] == "Mac Custom 🌙"
assert pl["Startup Window Settings"] == "Mac Custom 🌙"
prof_custom = pl["Window Settings"]["Mac Custom 🌙"]
bg_custom = plistlib.loads(prof_custom["BackgroundColor"])
rgb_custom = bg_custom["$objects"][1]["NSRGB"].decode("ascii").rstrip("\x00")
assert tuple(round(float(x) * 255) for x in rgb_custom.split()) == (0x12, 0x23, 0x34)
PY
then
    pass "bin/macos-terminal-solarized preserves cfprefsd profiles via defaults export/import, encodes 22 sRGB NSColor slots (including OS=macos broadcast and .conf custom themes), and rejects unknown themes"
else
    fail "bin/macos-terminal-solarized plist encoding" "Failed cfprefsd export/import, Nord/.conf profile encoding, or unknown theme rejection"
fi
rm -rf "$MACOS_MOCK_HOME"

# Verify dbus-run-session gnome-terminal-solarized across all 17 built-in themes, non-BMP emoji labels, .conf decoupled custom themes, and unknown theme rejection (H2/T3)
if command -v dbus-run-session >/dev/null 2>&1 && command -v dconf >/dev/null 2>&1; then
    GT_TEST_HOME="$(mktemp -d)"
    mkdir -p "$GT_TEST_HOME/.config/themes" "$GT_TEST_HOME/run" "$GT_TEST_HOME/mock-bin"
    chmod 700 "$GT_TEST_HOME/run"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "org.gnome.Terminal.ProfilesList"' > "$GT_TEST_HOME/mock-bin/gsettings"
    chmod +x "$GT_TEST_HOME/mock-bin/gsettings"
    cat > "$GT_TEST_HOME/.config/themes/partial-custom.theme" <<'EOF'
THEME_ID="partial-custom"
THEME_LABEL="O'Brien's Partial Theme"
BASE03="#101820"
EOF
    cat > "$GT_TEST_HOME/.config/themes/spooky-file.conf" <<'EOF'
export THEME_ID='spooky-emoji' # decoupled ID
THEME_LABEL="Spooky 🎃 Night" # non-BMP UTF-8 emoji
export BASE03='#140a1e' # dark purple
EOF
    cat > "$GT_TEST_HOME/run-gt.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
script_dir="$1"
shift
prof_path="/org/gnome/terminal/legacy/profiles:/:321fa646-e6ab-45a1-88d8-00aa66d158d8"
for slug in "$@"; do
    "$script_dir/bin/gnome-terminal-solarized" --theme "$slug" >/dev/null
done
"$script_dir/bin/gnome-terminal-solarized" --theme new-years >/dev/null
ny_name="$(dconf read "$prof_path/visible-name")"
[[ "$ny_name" == *"New Year"* ]]
"$script_dir/bin/gnome-terminal-solarized" --theme partial-custom >/dev/null
pc_name="$(dconf read "$prof_path/visible-name")"
pc_bg="$(dconf read "$prof_path/background-color")"
[[ "$pc_name" == *"O'Brien"* ]]
[[ "$pc_bg" == *"#101820"* ]]
"$script_dir/bin/gnome-terminal-solarized" --theme spooky-emoji >/dev/null
spooky_name="$(dconf read "$prof_path/visible-name")"
spooky_bg="$(dconf read "$prof_path/background-color")"
[[ "$spooky_name" == *"Spooky 🎃 Night"* ]]
[[ "$spooky_bg" == *"#140A1E"* ]]
if "$script_dir/bin/gnome-terminal-solarized" --theme nonexistent-theme-xyz >/dev/null 2>&1; then
    exit 1
fi
EOF
    chmod +x "$GT_TEST_HOME/run-gt.sh"
    if PATH="$GT_TEST_HOME/mock-bin:$PATH" XDG_RUNTIME_DIR="$GT_TEST_HOME/run" HOME="$GT_TEST_HOME" XDG_CONFIG_HOME="$GT_TEST_HOME/.config" XDG_CACHE_HOME="$GT_TEST_HOME/.cache" dbus-run-session -- "$GT_TEST_HOME/run-gt.sh" "$SCRIPT_DIR" "${managed_themes[@]}" >/dev/null 2>&1; then
        pass "bin/gnome-terminal-solarized writes valid GVariant dconf profiles across all 17 themes, apostrophe & non-BMP emoji labels, .conf custom themes, and rejects unknown themes"
    else
        fail "bin/gnome-terminal-solarized dbus-run-session" "Failed writing dconf profile across 17 themes, emoji/.conf custom themes, or rejecting unknown theme"
    fi
    rm -rf "$GT_TEST_HOME"
fi

# Verify invalid hex code in custom theme is rejected cleanly
cat > "$THEME_TEST_Cfg/themes/broken-hex.theme" <<'EOF'
THEME_ID="broken-hex"
BASE03="not-a-hex"
EOF
if ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --set broken-hex --no-live >/dev/null 2>&1; then
    pass "bin/theme rejects custom theme file containing malformed hex color values"
else
    fail "bin/theme malformed hex validation" "Expected non-zero exit for invalid hex color"
fi
rm -f "$THEME_TEST_Cfg/themes/broken-hex.theme"

# Verify interactive fzf picker when invoked with no arguments
FZF_MOCK_BIN="$(mktemp -d)"
cat > "$FZF_MOCK_BIN/fzf" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == --preview=* ]]; then
        echo "$arg" > "$FZF_MOCK_LOG"
    fi
done
cat >/dev/null
printf '* gruvbox-dark  Gruvbox Dark  [dark]  Warm retro groove dark palette\n'
SH
chmod +x "$FZF_MOCK_BIN/fzf"
FZF_MOCK_LOG="$FZF_MOCK_BIN/preview.log" THEME_FORCE_FZF=1 PATH="$FZF_MOCK_BIN:$PATH" HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" --no-live >/dev/null 2>&1
if [ "$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --current)" = "gruvbox-dark" ] && \
   grep -Fq -- "--preview {1}" "$FZF_MOCK_BIN/preview.log"; then
    pass "bin/theme (no args) launches interactive fzf picker with live '--preview {1}' and applies selected theme"
else
    fail "bin/theme fzf picker" "Expected gruvbox-dark to be applied via fzf picker"
fi
rm -rf "$FZF_MOCK_BIN"

# Verify live Neovim RPC hot-reload across both IDE sockets and standalone */nvim.*.0 sockets (hermetic: THEME_UPDATE_TERMINAL_PROFILE=0 TMUX="" THEME_NVIM_SOCKET_DIR)
if command -v nvim >/dev/null 2>&1; then
    LIVE_NVIM_SOCK_DIR="$THEME_TEST_HOME/nvim-sockets"
    mkdir -p "$LIVE_NVIM_SOCK_DIR/standalone-sub"
    LIVE_NVIM_SOCK="$LIVE_NVIM_SOCK_DIR/nvim-ide-theme-test.sock"
    STANDALONE_NVIM_SOCK="$LIVE_NVIM_SOCK_DIR/standalone-sub/nvim.42424.0"
    ORIG_XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
    rm -f "$LIVE_NVIM_SOCK" "$STANDALONE_NVIM_SOCK"
    (cd "$SCRIPT_DIR" && exec env NVIM_TS_SKIP_AUTO_INSTALL=1 XDG_DATA_HOME="$ORIG_XDG_DATA_HOME" HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" nvim --headless -i NONE -u "$SCRIPT_DIR/dotfiles/.config/nvim/init.lua" --listen "$LIVE_NVIM_SOCK" </dev/null >/dev/null 2>&1) &
    LIVE_NVIM_PID=$!
    (cd "$SCRIPT_DIR" && exec env NVIM_TS_SKIP_AUTO_INSTALL=1 XDG_DATA_HOME="$ORIG_XDG_DATA_HOME" HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" nvim --headless -i NONE -u "$SCRIPT_DIR/dotfiles/.config/nvim/init.lua" --listen "$STANDALONE_NVIM_SOCK" </dev/null >/dev/null 2>&1) &
    STANDALONE_NVIM_PID=$!
    if wait_for_nvim_socket "$LIVE_NVIM_SOCK" 60 1 && wait_for_nvim_socket "$STANDALONE_NVIM_SOCK" 60 1; then
        THEME_UPDATE_TERMINAL_PROFILE=0 TMUX="" TMUX_TMPDIR="" THEME_NVIM_SOCKET_DIR="$LIVE_NVIM_SOCK_DIR" NVIM_IDE_SOCKET="" HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" --set catppuccin-mocha >/dev/null 2>&1
        NVIM_LIVE_STATE="$(timeout 10 nvim --headless --server "$LIVE_NVIM_SOCK" --remote-expr "get(g:, 'home_settings_theme', '') . ':' . toupper(synIDattr(hlID('Normal'), 'bg#', 'gui')) . ':' . toupper(synIDattr(hlID('Normal'), 'fg#', 'gui'))" </dev/null 2>/dev/null || true)"
        NVIM_STANDALONE_STATE="$(timeout 10 nvim --headless --server "$STANDALONE_NVIM_SOCK" --remote-expr "get(g:, 'home_settings_theme', '') . ':' . toupper(synIDattr(hlID('Normal'), 'bg#', 'gui')) . ':' . toupper(synIDattr(hlID('Normal'), 'fg#', 'gui'))" </dev/null 2>/dev/null || true)"
        if [ "$NVIM_LIVE_STATE" = "catppuccin-mocha:#1E1E2E:#CDD6F4" ] && [ "$NVIM_STANDALONE_STATE" = "catppuccin-mocha:#1E1E2E:#CDD6F4" ]; then
            pass "bin/theme hot-reloads both IDE and standalone (*/nvim.*.0) live Neovim servers over RPC (g:home_settings_theme=catppuccin-mocha, Normal=#CDD6F4 on #1E1E2E)"
        else
            fail "bin/theme live Neovim RPC reload" "Expected 'catppuccin-mocha:#1E1E2E:#CDD6F4' on both servers, got IDE='$NVIM_LIVE_STATE' standalone='$NVIM_STANDALONE_STATE'"
        fi
    else
        fail "bin/theme live Neovim socket" "Timed out waiting for headless Neovim servers"
    fi
    kill "$LIVE_NVIM_PID" "$STANDALONE_NVIM_PID" 2>/dev/null || true
    wait "$LIVE_NVIM_PID" "$STANDALONE_NVIM_PID" 2>/dev/null || true
    rm -f "$LIVE_NVIM_SOCK" "$STANDALONE_NVIM_SOCK"
fi

# Verify bin/theme generated Ghostty cursor/keybindings and live tmux global FZF_DEFAULT_OPTS broadcast
if grep -Fq 'cursor-style = block' "$THEME_TEST_Cfg/ghostty/config" && \
   grep -Fq 'cursor-style-blink = false' "$THEME_TEST_Cfg/ghostty/config" && \
   grep -Fq 'shell-integration-features = no-cursor' "$THEME_TEST_Cfg/ghostty/config" && \
   grep -Fq 'keybind = ctrl+shift+t=new_tab' "$THEME_TEST_Cfg/ghostty/config" && \
   grep -Fq 'keybind = alt+left=text:\x1b[1;3D' "$THEME_TEST_Cfg/ghostty/config" && \
   grep -Fq 'keybind = alt+right=text:\x1b[1;3C' "$THEME_TEST_Cfg/ghostty/config" && \
   grep -Fq 'keybind = alt+up=text:\x1b[1;3A' "$THEME_TEST_Cfg/ghostty/config" && \
   grep -Fq 'keybind = alt+down=text:\x1b[1;3B' "$THEME_TEST_Cfg/ghostty/config"; then
    pass "bin/theme generates Ghostty config with steady block cursor (no-cursor) and Ctrl+Shift+T / Alt+Arrow ESC keybindings"
else
    fail "bin/theme Ghostty cursor & keybindings" "Missing steady block cursor (no-cursor) or Ctrl+Shift+T / Alt+Arrow keybindings in generated Ghostty config"
fi

if command -v tmux >/dev/null 2>&1; then
    LIVE_TMUX_TMP="$(mktemp -d)"
    if TMUX="" TMUX_PANE="" TMUX_TMPDIR="$LIVE_TMUX_TMP" tmux -f /dev/null new-session -d -s theme_live_tmux "exec sleep 30" >/dev/null 2>&1; then
        THEME_UPDATE_TERMINAL_PROFILE=0 THEME_LIVE_NVIM=0 TMUX="" TMUX_PANE="" TMUX_TMPDIR="$LIVE_TMUX_TMP" HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" --set nord >/dev/null 2>&1
        tmux_fzf_env="$(TMUX="" TMUX_PANE="" TMUX_TMPDIR="$LIVE_TMUX_TMP" tmux show-environment -g FZF_DEFAULT_OPTS 2>/dev/null || true)"
        TMUX="" TMUX_PANE="" TMUX_TMPDIR="$LIVE_TMUX_TMP" tmux kill-session -t "=theme_live_tmux" >/dev/null 2>&1 || true
        if [[ "$tmux_fzf_env" == "FZF_DEFAULT_OPTS=--color=bg+:#3B4252,bg:#2E3440,"* ]]; then
            pass "bin/theme broadcasts updated FZF_DEFAULT_OPTS into live tmux global environment"
        else
            fail "bin/theme live tmux FZF_DEFAULT_OPTS" "Expected Nord FZF_DEFAULT_OPTS in tmux global env, got '$tmux_fzf_env'"
        fi
    fi
    rm -rf "$LIVE_TMUX_TMP"
fi

# Verify uniform preview card geometry across ALL 17 built-in themes (standalone 94 cols and narrow fzf 72 cols) and Tmux status-right client_width>=105 holiday guard
HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" --set halloween --no-live >/dev/null 2>&1
if grep -Fq '#{>=:#{client_width},105}' "$THEME_TEST_Cfg/home-settings/tmux-theme.conf" && \
   python3 -B - "$SCRIPT_DIR/bin/theme" "$SCRIPT_DIR/bin/ide" "${managed_themes[@]}" <<'PY'
from __future__ import annotations

import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
theme_bin, ide_bin = sys.argv[1], sys.argv[2]
slugs = sys.argv[3:]
bin_dir = Path(theme_bin).resolve().parent
sys.path.insert(0, str(bin_dir))

from theme_lib.preview import visible_len as vlen

for slug in slugs:
    env = dict(os.environ)
    env.pop("FZF_PREVIEW_COLUMNS", None)
    env.pop("FZF_PREVIEW_LINES", None)
    out = subprocess.check_output([theme_bin, "--preview", slug], env=env, text=True).splitlines()
    if {vlen(line) for line in out} != {94}:
        raise SystemExit(f"{slug}: standalone width != 94")
    env["FZF_PREVIEW_COLUMNS"] = "72"
    env["FZF_PREVIEW_LINES"] = "30"
    out_narrow = subprocess.check_output([theme_bin, "--preview", slug], env=env, text=True).splitlines()
    status_lines = [line for line in out_narrow if "Editor" in line]
    if not status_lines or vlen(status_lines[0]) != 72:
        raise SystemExit(f"{slug}: narrow status width != 72")

# Verify status_click in bin/ide (+ bin/ide_lib/*.py) uses visible_width for 2-column holiday emoji and East Asian wide glyphs,
# and bin/theme (+ bin/theme_lib/*.py) emits clickable range tags and discovers $XDG_RUNTIME_DIR/nvim-ide-*.sock while isolating THEME_NVIM_SOCKET_DIR
ide_files = [Path(ide_bin)] + sorted(bin_dir.glob("ide_lib/*.py"))
src = "\n".join(p.read_text(encoding="utf-8") for p in ide_files if p.is_file())
assert "#{status-left}" in src and ("_visible_width(" in src or "visible_width(" in src)
theme_files = [Path(theme_bin)] + sorted(bin_dir.glob("theme_lib/*.py"))
theme_src = "\n".join(p.read_text(encoding="utf-8") for p in theme_files if p.is_file())
assert 'range=user|tab_ai' in theme_src and 'range=user|tab_editor' in theme_src and 'range=user|tab_term' in theme_src and 'range=user|tab_zoom' in theme_src

if shutil.which("nvim"):
    with tempfile.TemporaryDirectory() as xdg_rt_tmp, tempfile.TemporaryDirectory() as iso_sock_tmp:
        sock_a = os.path.join(xdg_rt_tmp, "nvim-ide-peer-a.sock")
        sock_b = os.path.join(xdg_rt_tmp, "nvim-ide-peer-b.sock")
        iso_sock = os.path.join(iso_sock_tmp, "nvim-ide-isolated.sock")
        nvim_log = os.path.join(xdg_rt_tmp, "nvim_rpc.log")
        mock_nvim_dir = os.path.join(xdg_rt_tmp, "bin")
        os.makedirs(mock_nvim_dir, exist_ok=True)
        mock_nvim = os.path.join(mock_nvim_dir, "nvim")
        with open(mock_nvim, "w", encoding="utf-8") as mf:
            mf.write(f"#!/usr/bin/env python3\nimport sys\nwith open({nvim_log!r}, 'a', encoding='utf-8') as f:\n    f.write(' '.join(sys.argv[1:]) + '\\n')\n")
        os.chmod(mock_nvim, 0o755)
        s1 = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s2 = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s3 = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s1.bind(sock_a)
        s2.bind(sock_b)
        s3.bind(iso_sock)
        try:
            rt_env = {
                **env,
                "PATH": f"{mock_nvim_dir}:{env['PATH']}",
                "XDG_RUNTIME_DIR": xdg_rt_tmp,
                "NVIM_IDE_SOCKET": "",
                "THEME_NVIM_SOCKET_DIR": "",
                "THEME_SKIP_NVIM_SOCKET": "",
                "THEME_LIVE_NVIM": "1",
                "THEME_UPDATE_TERMINAL_PROFILE": "0",
                "TMUX": "",
                "TMUX_TMPDIR": "",
            }
            subprocess.run([theme_bin, "--set", "nord"], env=rt_env, stdout=subprocess.DEVNULL, check=True)
            rpc_txt = open(nvim_log, encoding="utf-8").read()
            assert sock_a in rpc_txt and sock_b in rpc_txt, f"bin/theme missed $XDG_RUNTIME_DIR/nvim-ide-*.sock: {rpc_txt!r}"

            # Verify THEME_NVIM_SOCKET_DIR strictly ignores inherited NVIM_IDE_SOCKET and XDG_RUNTIME_DIR
            open(nvim_log, "w", encoding="utf-8").close()
            iso_env = {
                **rt_env,
                "THEME_NVIM_SOCKET_DIR": iso_sock_tmp,
                "NVIM_IDE_SOCKET": sock_a,
            }
            subprocess.run([theme_bin, "--set", "onedark"], env=iso_env, stdout=subprocess.DEVNULL, check=True)
            iso_rpc_txt = open(nvim_log, encoding="utf-8").read()
            assert iso_sock in iso_rpc_txt and sock_a not in iso_rpc_txt and sock_b not in iso_rpc_txt, (
                f"THEME_NVIM_SOCKET_DIR leaked into NVIM_IDE_SOCKET/XDG_RUNTIME_DIR: {iso_rpc_txt!r}"
            )
        finally:
            s1.close()
            s2.close()
            s3.close()
PY
then
    pass "bin/theme renders uniform rectangular preview cards across all 17 themes (standalone 94-col & narrow 72-col fzf), guards Tmux holiday badge with client_width>=105, isolates THEME_NVIM_SOCKET_DIR, and bin/ide status_click accounts for 2-cell holiday emojis"
else
    fail "bin/theme 17-theme preview geometry & Tmux status-bar holiday guards" "Preview card widths, client_width>=105 guard, THEME_NVIM_SOCKET_DIR isolation, or bin/ide status-left emoji width calculation failed"
fi

rm -rf "$THEME_TEST_HOME"

# Verify symlinked invocation in a temp directory resolves bin/theme_lib cleanly across theme & terminal CLIs
SYMLINK_BIN_TMP="$(mktemp -d)"
mkdir -p "$SYMLINK_BIN_TMP/bin" "$SYMLINK_BIN_TMP/hop" "$SYMLINK_BIN_TMP/home/.config"
ln -s "$SCRIPT_DIR/bin/theme" "$SYMLINK_BIN_TMP/bin/theme"
ln -s "../bin/theme" "$SYMLINK_BIN_TMP/hop/theme-chained"
ln -s "$SCRIPT_DIR/bin/gnome-terminal-solarized" "$SYMLINK_BIN_TMP/bin/gnome-terminal-solarized"
ln -s "$SCRIPT_DIR/bin/macos-terminal-solarized" "$SYMLINK_BIN_TMP/bin/macos-terminal-solarized"
sym_list_out="$(HOME="$SYMLINK_BIN_TMP/home" XDG_CONFIG_HOME="$SYMLINK_BIN_TMP/home/.config" "$SYMLINK_BIN_TMP/hop/theme-chained" --list --plain 2>&1)" || sym_list_out=""
sym_dry_out="$(HOME="$SYMLINK_BIN_TMP/home" XDG_CONFIG_HOME="$SYMLINK_BIN_TMP/home/.config" "$SYMLINK_BIN_TMP/bin/theme" --dry-run nord 2>&1)" || sym_dry_out=""
sym_mac_out="$(OS=macos HOME="$SYMLINK_BIN_TMP/home" XDG_CONFIG_HOME="$SYMLINK_BIN_TMP/home/.config" "$SYMLINK_BIN_TMP/bin/macos-terminal-solarized" --theme nord --dry-run 2>&1)" || sym_mac_out=""
rm -rf "$SYMLINK_BIN_TMP"
if grep -Fxq "nord" <<< "$sym_list_out" && \
   grep -Fq "[DRY-RUN] Theme: Nord (nord" <<< "$sym_dry_out" && \
   grep -Fq "Configure 'Nord' in Terminal.app" <<< "$sym_mac_out"; then
    pass "Symlinked bin/theme (including chained relative symlinks) and terminal provisioners resolve bin/theme_lib cleanly"
else
    fail "Symlinked bin/theme_lib resolution" "list='$sym_list_out' dry='$sym_dry_out' mac='$sym_mac_out'"
fi

# Verify bin/theme bypasses slow mise/shims/python3 when /usr/bin/python3 is available and honors THEME_PY_BIN
SHIM_PY_DIR="$(mktemp -d)"
mkdir -p "$SHIM_PY_DIR/mise/shims"
SHIM_HIT_FILE="$SHIM_PY_DIR/shim_invoked"
SHIM_PY_EXE="$SHIM_PY_DIR/mise/shims/python3"
cat > "$SHIM_PY_EXE" <<'SH'
#!/usr/bin/env bash
echo "hit" > "$SHIM_HIT_FILE_ENV"
exit 99
SH
cat > "$SHIM_PY_DIR/custom-py" <<'SH'
#!/usr/bin/env bash
echo "custom" > "$CUSTOM_PY_HIT_ENV"
exec python3 "$@"
SH
chmod +x "$SHIM_PY_EXE" "$SHIM_PY_DIR/custom-py"
shim_bypass_ok=true
if [ -x /usr/bin/python3 ]; then
    plain_shim_out="$(SHIM_HIT_FILE_ENV="$SHIM_HIT_FILE" PATH="$SHIM_PY_DIR/mise/shims:$PATH" HOME="$SHIM_PY_DIR" XDG_CONFIG_HOME="$SHIM_PY_DIR/.config" "$SCRIPT_DIR/bin/theme" --list --plain 2>&1)" || shim_bypass_ok=false
    if [ -e "$SHIM_HIT_FILE" ] || ! grep -Fxq "solarized-dark" <<< "$plain_shim_out"; then
        shim_bypass_ok=false
    fi
fi
CUSTOM_HIT_FILE="$SHIM_PY_DIR/custom_invoked"
cat > "$SHIM_PY_DIR/datetime.py" <<'EOF'
raise RuntimeError("CWD shadowed stdlib datetime")
EOF
custom_py_out="$(cd "$SHIM_PY_DIR" && CUSTOM_PY_HIT_ENV="$CUSTOM_HIT_FILE" THEME_PY_BIN="$SHIM_PY_DIR/custom-py" HOME="$SHIM_PY_DIR" XDG_CONFIG_HOME="$SHIM_PY_DIR/.config" "$SCRIPT_DIR/bin/theme" --current 2>&1)" || shim_bypass_ok=false
custom_hit_seen=false
[ -e "$CUSTOM_HIT_FILE" ] && custom_hit_seen=true
rm -rf "$SHIM_PY_DIR"
if [ "$shim_bypass_ok" = true ] && [ "$custom_hit_seen" = true ] && [ "$custom_py_out" = "solarized-dark" ]; then
    pass "bin/theme prefers /usr/bin/python3 -B over mise/shims/python3, honors THEME_PY_BIN, and isolates sys.path from CWD shadowing"
else
    fail "bin/theme interpreter selection" "Expected /usr/bin/python3 shim bypass, THEME_PY_BIN override support, and CWD sys.path isolation (got '$custom_py_out')"
fi

test_summary
