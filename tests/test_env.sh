#!/usr/bin/env bash
# Test suite for environment variables and bash configurations

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
echo "Running Environment & Bash Tests"
echo "========================================"

# Test 1: Bash syntax checks
echo -e "\n[1/3] Checking script syntax with 'bash -n'..."
for f in "$SCRIPT_DIR/bashrc-addendum" "$SCRIPT_DIR/bash-setup.sh" "$SCRIPT_DIR/user-setup.sh" "$SCRIPT_DIR/gnome-terminal-setup.sh"; do
    if bash -n "$f"; then
        pass "Syntax valid: $(basename "$f")"
    else
        fail "Syntax check failed: $(basename "$f")" "bash -n returned non-zero"
    fi
done

# Test 2: Verify environment_variables PATH configuration
echo -e "\n[2/3] Testing environment_variables exports..."
(
    TEMP_HOME=$(mktemp -d)
    trap 'chmod -R u+w "$TEMP_HOME" 2>/dev/null || true; rm -rf "$TEMP_HOME"' EXIT

    export HOME="$TEMP_HOME"
    source "$SCRIPT_DIR/environment_variables"

    if [[ ":$PATH:" == *":$HOME/bin:"* ]]; then
        pass "\$HOME/bin present in PATH"
    else
        fail "\$HOME/bin in PATH" "Expected $HOME/bin in PATH, got: $PATH"
    fi

    if [[ ":$PATH:" == *":$HOME/software/bin:"* ]]; then
        pass "\$HOME/software/bin present in PATH"
    else
        fail "\$HOME/software/bin in PATH" "Expected $HOME/software/bin in PATH, got: $PATH"
    fi

    if [ "${EDITOR:-}" = "vim" ]; then
        pass "EDITOR is set to vim"
    else
        fail "EDITOR export" "Expected vim, got: ${EDITOR:-}"
    fi
)

# Test 3: Verify bashrc-addendum sourcing
echo -e "\n[3/3] Testing bashrc-addendum..."
(
    TEMP_HOME=$(mktemp -d)
    trap 'chmod -R u+w "$TEMP_HOME" 2>/dev/null || true; rm -rf "$TEMP_HOME"' EXIT

    export HOME="$TEMP_HOME"
    cp "$SCRIPT_DIR/environment_variables" "$HOME/.environment_variables"

    source "$SCRIPT_DIR/bashrc-addendum"

    if [ "${EDITOR:-}" = "vim" ]; then
        pass "bashrc-addendum sourced .environment_variables"
    else
        fail "bashrc-addendum sourcing" ".environment_variables was not sourced"
    fi
)

echo -e "\n========================================"
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
