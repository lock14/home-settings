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

# Run installer (fonts only)
if output=$("$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-tools --skip-vim --skip-zsh --skip-bash --skip-bin --skip-completions 2>&1); then
    pass "setup.sh font installation succeeded on Linux"
else
    fail "setup.sh font installation on Linux" "Failed: $output"
fi

expected_fonts=(
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

# Test idempotency (should run cleanly without error)
if output=$("$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-tools --skip-vim --skip-zsh --skip-bash --skip-bin --skip-completions 2>&1); then
    pass "Font installation is idempotent"
else
    fail "Font setup idempotency" "Second run failed: $output"
fi

# Test 3: Font installation on macOS target
echo -e "\n[3/3] Testing font installation on macOS target..."
MAC_TEMP_HOME=$(mktemp -d)
trap 'rm -rf "$TEMP_HOME" "$MAC_TEMP_HOME"' EXIT

export HOME="$MAC_TEMP_HOME"
if output=$("$SCRIPT_DIR/setup.sh" --os macos --dotfiles-only --skip-tools --skip-vim --skip-zsh --skip-bash --skip-bin --skip-completions 2>&1); then
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

export HOME="$OLD_HOME"

test_summary
