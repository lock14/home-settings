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

# Test 2: Font download & installation in Linux environment
echo -e "\n[2/3] Testing font-setup.sh on Linux paths..."
(
    TEMP_HOME=$(mktemp -d)
    trap 'rm -rf "$TEMP_HOME"' EXIT

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
            pass "Linux Font installed: $font ($(du -h "$font_path" | cut -f1))"
        else
            fail "Linux Font missing or empty: $font" "Expected file at $font_path"
        fi
    done

    # Test idempotency
    if "$SCRIPT_DIR/font-setup.sh" >/dev/null 2>&1; then
        pass "font-setup.sh is idempotent on Linux"
    else
        fail "font-setup.sh idempotency" "Second run failed"
    fi
)

# Test 3: Font download & installation on macOS Darwin paths (mocking uname)
echo -e "\n[3/3] Testing font-setup.sh on macOS Darwin paths..."
(
    TEMP_HOME=$(mktemp -d)
    BIN_MOCK="$TEMP_HOME/bin"
    mkdir -p "$BIN_MOCK"
    trap 'rm -rf "$TEMP_HOME"' EXIT

    # Mock uname -s to return Darwin
    cat > "$BIN_MOCK/uname" << 'EOF'
#!/bin/bash
if [ "${1:-}" = "-s" ]; then
    echo "Darwin"
else
    command uname "$@"
fi
EOF
    chmod +x "$BIN_MOCK/uname"

    export PATH="$BIN_MOCK:$PATH"
    export HOME="$TEMP_HOME"

    "$SCRIPT_DIR/font-setup.sh" >/dev/null 2>&1

    expected_fonts=(
        "MesloLGS NF Regular.ttf"
        "MesloLGS NF Bold.ttf"
        "MesloLGS NF Italic.ttf"
        "MesloLGS NF Bold Italic.ttf"
    )

    for font in "${expected_fonts[@]}"; do
        font_path="$TEMP_HOME/Library/Fonts/$font"
        if [ -f "$font_path" ] && [ -s "$font_path" ]; then
            pass "macOS Font installed: $font ($(du -h "$font_path" | cut -f1))"
        else
            fail "macOS Font missing or empty: $font" "Expected file at $font_path"
        fi
    done
)


echo -e "\n========================================"
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
