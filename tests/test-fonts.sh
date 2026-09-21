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
    "MesloLGSNerdFontMono-Regular.ttf"
    "MesloLGSNerdFontMono-Bold.ttf"
    "MesloLGSNerdFontMono-Italic.ttf"
    "MesloLGSNerdFontMono-BoldItalic.ttf"
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
    nf_charset="$(fc-query --format='%{family}\n%{postscriptname}\n' "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFontMono-Regular.ttf" 2>/dev/null || true)"
    if grep -Fq "MesloLGS Nerd Font Mono" <<< "$nf_charset" && grep -Fq "MesloLGSNFM-Regular" <<< "$nf_charset"; then
        pass "fc-query confirms ryanoasis MesloLGS Nerd Font Mono (postscriptname MesloLGSNFM-Regular) is installed"
    else
        fail "fc-query MesloLGS Nerd Font Mono check" "Expected MesloLGS Nerd Font Mono family and MesloLGSNFM-Regular postscriptname, got: $nf_charset"
    fi

    # Verify Plane-15 charset support for modern CLI glyphs (eza icons)
    raw_cs="$(fc-query --format='%{charset}\n' "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFontMono-Regular.ttf" 2>/dev/null || true)"
    if grep -Eiq "(f0001|f1af0)" <<< "$raw_cs"; then
        pass "fc-query confirms Nerd Fonts v3 Plane-15 glyph support (f0001-f1af0) in MesloLGSNerdFontMono-Regular.ttf"
    else
        fail "fc-query Plane-15 glyph check" "Expected Plane-15 charset range (f0001-f1af0) in font"
    fi

    # Verify modern dev icon coverage for eza (YAML U+E8EB, TOML U+E6B2)
    if grep -Eiq "(e700-e958|e8eb)" <<< "$raw_cs" && grep -Eiq "(e5fa-e6bb|e6b2)" <<< "$raw_cs"; then
        pass "fc-query confirms modern dev icon coverage (YAML U+E8EB, TOML U+E6B2) in MesloLGSNerdFontMono-Regular.ttf"
    else
        fail "fc-query YAML/TOML icon check" "Expected ranges covering e8eb and e6b2 in MesloLGSNerdFontMono-Regular.ttf"
    fi
fi

if [ -f "$TEMP_HOME/.config/fontconfig/conf.d/10-meslo-nerd-font.conf" ]; then
    pass "Fontconfig alias 10-meslo-nerd-font.conf installed"
else
    fail "Fontconfig alias missing" "Expected $TEMP_HOME/.config/fontconfig/conf.d/10-meslo-nerd-font.conf"
fi

if command -v fc-match >/dev/null 2>&1; then
    fc_conf="$TEMP_HOME/test-fc.conf"
    cat << EOF > "$fc_conf"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <include>/etc/fonts/fonts.conf</include>
  <dir>$TEMP_HOME/.local/share/fonts</dir>
  <include>$TEMP_HOME/.config/fontconfig/conf.d/10-meslo-nerd-font.conf</include>
</fontconfig>
EOF
    matched_mono="$(FONTCONFIG_FILE="$fc_conf" fc-match --format='%{family}|%{file}\n' "MesloLGS Nerd Font Mono" 2>/dev/null || true)"
    matched_v3="$(FONTCONFIG_FILE="$fc_conf" fc-match --format='%{family}|%{file}\n' "MesloLGS Nerd Font" 2>/dev/null || true)"
    matched_legacy="$(FONTCONFIG_FILE="$fc_conf" fc-match --format='%{family}|%{file}\n' "MesloLGS NF" 2>/dev/null || true)"
    if grep -Fq "MesloLGS Nerd Font Mono" <<< "$matched_mono" && grep -Fq "MesloLGSNerdFontMono-Regular.ttf" <<< "$matched_mono"; then
        pass "fc-match resolves 'MesloLGS Nerd Font Mono' to MesloLGSNerdFontMono-Regular.ttf"
    else
        fail "fc-match 'MesloLGS Nerd Font Mono'" "Expected MesloLGSNerdFontMono-Regular.ttf, got: $matched_mono"
    fi
    if grep -Fq "MesloLGS Nerd Font Mono" <<< "$matched_v3" && grep -Fq "MesloLGSNerdFontMono-Regular.ttf" <<< "$matched_v3"; then
        pass "fc-match resolves 'MesloLGS Nerd Font' alias to MesloLGSNerdFontMono-Regular.ttf"
    else
        fail "fc-match 'MesloLGS Nerd Font' alias" "Expected MesloLGSNerdFontMono-Regular.ttf, got: $matched_v3"
    fi
    if grep -Fq "MesloLGS Nerd Font Mono" <<< "$matched_legacy" && grep -Fq "MesloLGSNerdFontMono-Regular.ttf" <<< "$matched_legacy"; then
        pass "fc-match resolves legacy 'MesloLGS NF' alias to MesloLGSNerdFontMono-Regular.ttf"
    else
        fail "fc-match 'MesloLGS NF' alias" "Expected MesloLGSNerdFontMono-Regular.ttf, got: $matched_legacy"
    fi
    rm -f "$fc_conf"
fi

# Verify that any conflicting MesloLGS-NF-*.ttf, legacy MesloLGS NF *.ttf, or stray numbered [0-9]MesloLGS*.ttf files and dangling fontconfig symlinks are cleaned up and replaced with MesloLGSNerdFontMono-*.ttf
printf "conflicting-hyphen-font" > "$TEMP_HOME/.local/share/fonts/MesloLGS-NF-Regular.ttf"
printf "stray-numbered-font" > "$TEMP_HOME/.local/share/fonts/1MesloLGS NF Italic.ttf"
printf "legacy-romkatv-font" > "$TEMP_HOME/.local/share/fonts/MesloLGS NF Regular.ttf"
ln -sfn "$TEMP_HOME/nonexistent-fontconfig" "$TEMP_HOME/.config/fontconfig"
printf "stub" > "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFontMono-Regular.ttf"
if output=$("$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-bash --skip-bin --skip-completions --skip-terminal 2>&1); then
    nf_size=$(wc -c < "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFontMono-Regular.ttf" | tr -d ' ')
    if [ ! -e "$TEMP_HOME/.local/share/fonts/MesloLGS-NF-Regular.ttf" ] && [ ! -e "$TEMP_HOME/.local/share/fonts/1MesloLGS NF Italic.ttf" ] && [ ! -e "$TEMP_HOME/.local/share/fonts/MesloLGS NF Regular.ttf" ] && [ -e "$TEMP_HOME/.config/fontconfig" ] && [ "$nf_size" -gt 2900000 ]; then
        pass "Font setup removes conflicting MesloLGS-NF-*.ttf, stray numbered fonts, legacy MesloLGS NF, resolves broken fontconfig symlink, and installs valid MesloLGSNerdFontMono-Regular.ttf ($nf_size bytes)"
    else
        fail "Font cleanup and restoration" "Expected conflicting/stray/legacy files removed, broken symlink resolved, and size > 2.9M (got size=$nf_size)"
    fi
else
    fail "Font setup cleanup run" "Second run failed: $output"
fi

# Verify font inode preservation on repeated runs (prevents unlinking fonts out from under running terminal emulators)
inode_before=$(stat -c '%i' "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFontMono-Regular.ttf" 2>/dev/null || stat -f '%i' "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFontMono-Regular.ttf")
if output=$("$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-bash --skip-bin --skip-completions --skip-terminal 2>&1); then
    inode_after=$(stat -c '%i' "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFontMono-Regular.ttf" 2>/dev/null || stat -f '%i' "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFontMono-Regular.ttf")
    if [ "$inode_before" = "$inode_after" ]; then
        pass "Font setup preserves existing valid font file inode ($inode_before == $inode_after) without unlinking under running apps"
    else
        fail "Font inode stability" "Expected unchanged inode $inode_before, got $inode_after"
    fi
else
    fail "Font setup idempotency" "Third run failed: $output"
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
    if [ "$mac_ps_name" = "MesloLGSNFM-Regular" ]; then
        pass "colors/Solarized-Dark.terminal archived NSFont PostScript name is MesloLGSNFM-Regular (matching ryanoasis MesloLGS Nerd Font Mono)"
    else
        fail "colors/Solarized-Dark.terminal PostScript font name" "Expected MesloLGSNFM-Regular, got '$mac_ps_name'"
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
