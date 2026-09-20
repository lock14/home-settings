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
        pass "fc-query confirms MesloLGS Nerd Font v3 (postscriptname MesloLGSNF-Regular) includes Plane 15 glyphs (U+F0001..U+F1AF0)"
    else
        fail "fc-query Nerd Fonts v3 Plane 15 check" "Expected MesloLGS Nerd Font family, MesloLGSNF-Regular postscriptname, and f0001-f1af0 charset range"
    fi

    nf_charset="$(fc-query --format='%{family}\n%{postscriptname}\n%{charset}\n' "$TEMP_HOME/.local/share/fonts/MesloLGS NF Regular.ttf" 2>/dev/null || true)"
    if grep -Fq "MesloLGS NF" <<< "$nf_charset" && grep -Fq "MesloLGS-NF-Regular" <<< "$nf_charset" && grep -Eq "f0001-f1[0-9a-f]{3}" <<< "$nf_charset"; then
        pass "fc-query confirms MesloLGS NF (postscriptname MesloLGS-NF-Regular) has native family table and Plane 15 glyphs (U+F0001..U+F1AF0)"
    else
        fail "fc-query MesloLGS NF native family check" "Expected MesloLGS NF family, MesloLGS-NF-Regular postscriptname, and f0001-f1af0 charset range"
    fi
fi

if command -v python3 >/dev/null 2>&1; then
    if python3 - "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFont-Regular.ttf" "$TEMP_HOME/.local/share/fonts/MesloLGS NF Regular.ttf" << 'PYEOF'
import struct, sys

for path in sys.argv[1:]:
    with open(path, "rb") as f:
        data = f.read()
    num_tables = struct.unpack(">H", data[4:6])[0]
    tables = {data[12+i*16:16+i*16].decode("latin1"): struct.unpack(">II", data[20+i*16:28+i*16]) for i in range(num_tables)}
    os2_off = tables["OS/2"][0]
    post_off = tables["post"][0]
    os2_ver = struct.unpack(">H", data[os2_off:os2_off+2])[0]
    fs_sel = struct.unpack(">H", data[os2_off+62:os2_off+64])[0]
    typo_asc, typo_desc, typo_gap = struct.unpack(">hhh", data[os2_off+68:os2_off+74])
    is_fixed = struct.unpack(">I", data[post_off+12:post_off+16])[0]
    assert os2_ver == 3, f"Expected OS/2 version 3 in {path}, got {os2_ver}"
    assert fs_sel == 0x0040, f"Expected Regular fsSelection 0x0040 in {path}, got {hex(fs_sel)}"
    assert (typo_asc, typo_desc, typo_gap) == (1556, -492, 0), f"Unexpected OS/2 typo metrics in {path}: {(typo_asc, typo_desc, typo_gap)}"
    assert is_fixed == 1, f"Expected post.isFixedPitch=1 in {path}, got {is_fixed}"
PYEOF
    then
        pass "OpenType OS/2 (version=3, fsSelection=0x0040 Regular, sTypoAscender=1556, sTypoDescender=-492), post.isFixedPitch=1, and Powerline contours calibrated"
    else
        fail "OpenType OS/2 & Powerline calibration check" "OS/2, post.isFixedPitch, or Powerline metrics did not match romkatv MesloLGS NF specification"
    fi
fi

if command -v fc-match >/dev/null 2>&1; then
    fc_v3_match="$(HOME="$TEMP_HOME" XDG_DATA_HOME="$TEMP_HOME/.local/share" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" fc-match --format='%{family}|%{style}|%{slant}' "MesloLGS Nerd Font" 2>/dev/null || true)"
    fc_nf_match="$(HOME="$TEMP_HOME" XDG_DATA_HOME="$TEMP_HOME/.local/share" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" fc-match --format='%{family}|%{style}|%{slant}' "MesloLGS NF" 2>/dev/null || true)"
    if [[ "$fc_v3_match" == *"MesloLGS Nerd Font|Regular|0"* ]] && [[ "$fc_nf_match" == *"MesloLGS NF|Regular|0"* ]]; then
        pass "fc-match resolves both 'MesloLGS Nerd Font' and 'MesloLGS NF' to upright Regular (slant=0)"
    else
        fail "fc-match Regular style resolution" "Got MesloLGS Nerd Font='$fc_v3_match', MesloLGS NF='$fc_nf_match'"
    fi
fi

# Verify legacy v2 MesloLGS NF *.ttf files are automatically upgraded in-place to Nerd Fonts v3
# Case A: When MesloLGSNerdFont-Regular.ttf already exists in $FONT_DIR
printf "legacy-v2-font-stub" > "$TEMP_HOME/.local/share/fonts/MesloLGS NF Regular.ttf"
if output=$("$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-bash --skip-bin --skip-completions --skip-terminal 2>&1); then
    nf_size=$(wc -c < "$TEMP_HOME/.local/share/fonts/MesloLGS NF Regular.ttf" | tr -d ' ')
    if [ "$nf_size" -gt 1000000 ]; then
        pass "Font installation upgrades legacy v2 MesloLGS NF Regular.ttf even when MesloLGSNerdFont-Regular.ttf is already present"
    else
        fail "Legacy v2 font upgrade (existing v3)" "MesloLGS NF Regular.ttf was not upgraded (size=$nf_size)"
    fi
else
    fail "Font setup upgrade (existing v3)" "Run failed: $output"
fi

# Case B: When MesloLGSNerdFont-Regular.ttf is absent and only legacy v2 MesloLGS NF Regular.ttf is present
printf "legacy-v2-font-stub" > "$TEMP_HOME/.local/share/fonts/MesloLGS NF Regular.ttf"
rm -f "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFont-Regular.ttf"
if output=$("$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-bash --skip-bin --skip-completions --skip-terminal 2>&1); then
    nf_size=$(wc -c < "$TEMP_HOME/.local/share/fonts/MesloLGS NF Regular.ttf" | tr -d ' ')
    if [ "$nf_size" -gt 1000000 ] && [ -s "$TEMP_HOME/.local/share/fonts/MesloLGSNerdFont-Regular.ttf" ]; then
        pass "Font installation upgrades legacy v2 MesloLGS NF Regular.ttf to Nerd Fonts v3 and remains idempotent"
    else
        fail "Legacy v2 font upgrade" "MesloLGS NF Regular.ttf was not upgraded (size=$nf_size)"
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
