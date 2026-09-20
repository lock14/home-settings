#!/usr/bin/env bash
# Test suite for font setup and MesloLGS NF fonts across Linux and macOS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/tests/test-helper.sh"

echo "========================================"
echo "Running Font Setup Tests"
echo "========================================"

export HOME_SETTINGS_FONT_CACHE="${HOME_SETTINGS_FONT_CACHE:-/tmp/home-settings-fonts-cache}"
mkdir -p "$HOME_SETTINGS_FONT_CACHE"

# Test 1: Bash syntax check
echo -e "\n[1/3] Checking setup.sh syntax..."
if bash -n "$SCRIPT_DIR/setup.sh"; then
    pass "Syntax valid: setup.sh"
else
    fail "Syntax check failed: setup.sh" "bash -n returned non-zero"
fi

# Test 2: Font download & installation in temp directory (Linux)
echo -e "\n[2/3] Testing font installation on Linux target..."
TEMP_HOME=$(mktemp -d)
trap 'rm -rf "$TEMP_HOME"' EXIT

OLD_HOME="$HOME"
export HOME="$TEMP_HOME"
export XDG_DATA_HOME="$TEMP_HOME/.local/share"
export XDG_CONFIG_HOME="$TEMP_HOME/.config"
export XDG_CACHE_HOME="$TEMP_HOME/.cache"

# Run installer (fonts only)
if output=$("$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-bash --skip-bin --skip-completions --skip-terminal 2>&1); then
    pass "setup.sh font installation succeeded on Linux"
else
    fail "setup.sh font installation on Linux" "Failed: $output"
fi

expected_fonts=(
    "MesloLGSNerdFont-Regular.ttf"
    "MesloLGSNerdFont-Bold.ttf"
    "MesloLGSNerdFont-Italic.ttf"
    "MesloLGSNerdFont-BoldItalic.ttf"
    "MesloLGS NF Regular.ttf"
    "MesloLGS NF Bold.ttf"
    "MesloLGS NF Italic.ttf"
    "MesloLGS NF Bold Italic.ttf"
)

for font in "${expected_fonts[@]}"; do
    font_path="$TEMP_HOME/.local/share/fonts/$font"
    if [ -f "$font_path" ] && [ -s "$font_path" ]; then
        pass "Font installed: $font ($(du -h "$font_path" | cut -f1))"
    else
        fail "Font missing or empty: $font" "Expected file at $font_path"
    fi
done

if command -v fc-query >/dev/null 2>&1; then
    font_charset="$(fc-query --format='%{family}\n%{postscriptname}\n%{charset}\n' "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFont-Regular.ttf" 2>/dev/null || true)"
    if grep -Fq "MesloLGS Nerd Font" <<< "$font_charset" && grep -Fq "MesloLGSNF-Regular" <<< "$font_charset" && grep -Eq "f0001-f1[0-9a-f]{3}" <<< "$font_charset"; then
        pass "fc-query confirms MesloLGS Nerd Font v3 (postscriptname MesloLGSNF-Regular) includes Plane 15 glyphs (U+F0001..U+F1AF0, covering U+F03E3, U+F0683, U+F1062)"
    else
        fail "fc-query Nerd Fonts v3 Plane 15 check" "Expected MesloLGS Nerd Font family, MesloLGSNF-Regular postscriptname, and f0001-f1af0 charset range"
    fi
fi

if command -v fc-match >/dev/null 2>&1; then
    fc_v3_family="$(HOME="$TEMP_HOME" XDG_DATA_HOME="$TEMP_HOME/.local/share" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" fc-match --format='%{family}' "MesloLGS Nerd Font" 2>/dev/null || true)"
    fc_nf_family="$(HOME="$TEMP_HOME" XDG_DATA_HOME="$TEMP_HOME/.local/share" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" fc-match --format='%{family}' "MesloLGS NF" 2>/dev/null || true)"
    if [[ "$fc_v3_family" == *"MesloLGS Nerd Font"* ]] && [[ "$fc_nf_family" == *"MesloLGS Nerd Font"* ]]; then
        pass "fc-match resolves both 'MesloLGS Nerd Font' and 'MesloLGS NF' to Nerd Fonts v3 via 10-meslo-nerd-font.conf"
    else
        fail "fc-match fontconfig alias resolution" "Got MesloLGS Nerd Font='$fc_v3_family', MesloLGS NF='$fc_nf_family'"
    fi
fi

# Verify legacy v2 MesloLGS NF *.ttf files are automatically upgraded in-place to Nerd Fonts v3
# Case A: When MesloLGSNerdFont-Regular.ttf already exists in $FONT_DIR
printf "legacy-v2-font-stub" > "$TEMP_HOME/.local/share/fonts/MesloLGS NF Regular.ttf"
if output=$("$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-bash --skip-bin --skip-completions --skip-terminal 2>&1); then
    if cmp -s "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFont-Regular.ttf" "$TEMP_HOME/.local/share/fonts/MesloLGS NF Regular.ttf"; then
        pass "Font installation upgrades legacy v2 MesloLGS NF Regular.ttf even when MesloLGSNerdFont-Regular.ttf is already present"
    else
        fail "Legacy v2 font upgrade (existing v3)" "MesloLGS NF Regular.ttf did not match MesloLGSNerdFont-Regular.ttf after upgrade"
    fi
else
    fail "Font setup upgrade (existing v3)" "Run failed: $output"
fi

# Case B: When MesloLGSNerdFont-Regular.ttf is absent and only legacy v2 MesloLGS NF Regular.ttf is present
printf "legacy-v2-font-stub" > "$TEMP_HOME/.local/share/fonts/MesloLGS NF Regular.ttf"
rm -f "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFont-Regular.ttf"
if output=$("$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-bash --skip-bin --skip-completions --skip-terminal 2>&1); then
    if cmp -s "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFont-Regular.ttf" "$TEMP_HOME/.local/share/fonts/MesloLGS NF Regular.ttf"; then
        pass "Font installation upgrades legacy v2 MesloLGS NF Regular.ttf to Nerd Fonts v3 and remains idempotent"
    else
        fail "Legacy v2 font upgrade" "MesloLGS NF Regular.ttf did not match MesloLGSNerdFont-Regular.ttf after upgrade"
    fi
else
    fail "Font setup idempotency / upgrade" "Second run failed: $output"
fi

# Test 3: Font installation on macOS target
echo -e "\n[3/3] Testing font installation on macOS target..."
MAC_TEMP_HOME=$(mktemp -d)
trap 'rm -rf "$TEMP_HOME" "$MAC_TEMP_HOME"' EXIT

export HOME="$MAC_TEMP_HOME"
export XDG_DATA_HOME="$MAC_TEMP_HOME/.local/share"
export XDG_CONFIG_HOME="$MAC_TEMP_HOME/.config"
export XDG_CACHE_HOME="$MAC_TEMP_HOME/.cache"
if output=$("$SCRIPT_DIR/setup.sh" --os macos --dotfiles-only --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-bash --skip-bin --skip-completions --skip-terminal 2>&1); then
    pass "setup.sh font installation succeeded on macOS target"
else
    fail "setup.sh font installation on macOS" "Failed: $output"
fi

for font in "${expected_fonts[@]}"; do
    mac_font_path="$MAC_TEMP_HOME/Library/Fonts/$font"
    if [ -f "$mac_font_path" ] && [ -s "$mac_font_path" ]; then
        pass "macOS Font installed: $font ($(du -h "$mac_font_path" | cut -f1))"
    else
        fail "macOS Font missing: $font" "Expected file at $mac_font_path"
    fi
done

if command -v python3 >/dev/null 2>&1; then
    mac_ps_name="$(python3 -c '
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    d = plistlib.load(f)
arch = plistlib.loads(d["Font"])
print(arch["$objects"][2])
' "$SCRIPT_DIR/colors/Solarized-Dark.terminal" 2>/dev/null || true)"
    if [ "$mac_ps_name" = "MesloLGSNF-Regular" ]; then
        pass "colors/Solarized-Dark.terminal archived NSFont PostScript name is MesloLGSNF-Regular (matching Nerd Fonts v3)"
    else
        fail "colors/Solarized-Dark.terminal PostScript font name" "Expected MesloLGSNF-Regular, got '$mac_ps_name'"
    fi
fi

# Verify failed background curl downloads clean up temporary files and exit non-zero
FAIL_FONT_HOME=$(mktemp -d)
FAIL_FONT_CACHE=$(mktemp -d)
MOCK_CURL_DIR=$(mktemp -d)
cat << 'EOF' > "$MOCK_CURL_DIR/curl"
#!/bin/sh
for arg in "$@"; do
    if [ "${prev:-}" = "-o" ]; then
        echo "partial" > "$arg"
    fi
    prev="$arg"
done
exit 1
EOF
chmod +x "$MOCK_CURL_DIR/curl"

if PATH="$MOCK_CURL_DIR:$PATH" HOME="$FAIL_FONT_HOME" XDG_DATA_HOME="$FAIL_FONT_HOME/.local/share" HOME_SETTINGS_FONT_CACHE="$FAIL_FONT_CACHE" "$SCRIPT_DIR/modules/30-fonts.sh" >/dev/null 2>&1; then
    fail "modules/30-fonts.sh failure handling" "Expected non-zero exit when curl fails"
else
    tmp_leftovers=("$FAIL_FONT_CACHE"/*.tmp*)
    if [ ! -e "${tmp_leftovers[0]}" ]; then
        pass "modules/30-fonts.sh cleans up temporary files and exits non-zero when curl fails"
    else
        fail "modules/30-fonts.sh temp file cleanup" "Leftover temporary file found: ${tmp_leftovers[0]}"
    fi
fi
rm -rf "$FAIL_FONT_HOME" "$FAIL_FONT_CACHE" "$MOCK_CURL_DIR"

export HOME="$OLD_HOME"

test_summary
