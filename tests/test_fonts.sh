#!/usr/bin/env bash
# Test suite for font-setup.sh and MesloLGS NF fonts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "  \033[32m✔ PASS:\033[0m $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "  \033[31m✘ FAIL:\033[0m $1"
    echo "    $2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo "========================================"
echo "Running Font Setup Tests"
echo "========================================"

# Test 1: Bash syntax check
echo -e "\n[1/2] Checking font-setup.sh syntax..."
if bash -n "$SCRIPT_DIR/font-setup.sh"; then
    pass "Syntax valid: font-setup.sh"
else
    fail "Syntax check failed: font-setup.sh" "bash -n returned non-zero"
fi

# Test 2: Font download & installation in temp directory
echo -e "\n[2/2] Testing font-setup.sh execution and file verification..."
TEMP_HOME=$(mktemp -d)
trap 'rm -rf "$TEMP_HOME"' EXIT

OLD_HOME="$HOME"
export HOME="$TEMP_HOME"
export XDG_DATA_HOME="$TEMP_HOME/.local/share"

# Run installer
"$SCRIPT_DIR/font-setup.sh" >/dev/null 2>&1

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
if "$SCRIPT_DIR/font-setup.sh" >/dev/null 2>&1; then
    pass "font-setup.sh is idempotent"
else
    fail "font-setup.sh idempotency" "Second run failed"
fi

export HOME="$OLD_HOME"


echo -e "\n========================================"
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
