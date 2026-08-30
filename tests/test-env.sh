#!/usr/bin/env bash
# Test suite for environment variables and bash configurations

# shellcheck disable=SC2030,SC2031
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
echo -e "\n[1/4] Checking script syntax with 'bash -n'..."
for f in "$SCRIPT_DIR/setup.sh" "$SCRIPT_DIR/dotfiles/.bashrc-addendum" "$SCRIPT_DIR/dotfiles/.environment-variables"; do
    if bash -n "$f"; then
        pass "Syntax valid: $(basename "$f")"
    else
        fail "Syntax check failed: $(basename "$f")" "bash -n returned non-zero"
    fi
done

# Test 2: Verify environment-variables PATH configuration
echo -e "\n[2/4] Testing dotfiles/.environment-variables exports..."
(
    TEMP_HOME=$(mktemp -d)
    trap 'chmod -R u+w "$TEMP_HOME" 2>/dev/null || true; rm -rf "$TEMP_HOME"' EXIT

    export HOME="$TEMP_HOME"
    unset GOPATH
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/dotfiles/.environment-variables"

    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
        pass "\$HOME/.local/bin present in PATH"
    else
        fail "\$HOME/.local/bin in PATH" "Expected $HOME/.local/bin in PATH, got: $PATH"
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

    if command -v go >/dev/null 2>&1; then
        if [ -n "${GOPATH:-}" ] && [[ ":$PATH:" == *":$GOPATH/bin:"* ]]; then
            pass "GOPATH and \$GOPATH/bin set cleanly when go is present ($GOPATH)"
        else
            fail "GOPATH export" "Expected GOPATH/bin in PATH, got GOPATH=${GOPATH:-}, PATH=$PATH"
        fi
    fi

    # Test dynamic go env GOPATH resolution with mock go binary
    MOCK_BIN="$TEMP_HOME/mock-bin"
    mkdir -p "$MOCK_BIN"
    cat <<'MOCK' > "$MOCK_BIN/go"
#!/bin/sh
if [ "$1" = "env" ] && [ "$2" = "GOPATH" ]; then
    echo "/custom/test-gopath"
fi
MOCK
    chmod +x "$MOCK_BIN/go"

    (
        export HOME="$TEMP_HOME"
        export PATH="$MOCK_BIN:/usr/bin:/bin"
        unset GOPATH
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/dotfiles/.environment-variables"
        if [ "${GOPATH:-}" = "/custom/test-gopath" ] && [[ ":$PATH:" == *":/custom/test-gopath/bin:"* ]]; then
            pass "go env GOPATH dynamically added to PATH when go is present"
        else
            fail "go env GOPATH dynamic resolution" "Expected /custom/test-gopath in GOPATH and PATH, got GOPATH=${GOPATH:-}, PATH=$PATH"
        fi
    )

    # Test behavior when go is not present
    (
        export HOME="$TEMP_HOME"
        export PATH="/usr/bin:/bin"
        unset GOPATH
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/dotfiles/.environment-variables"
        if [ -z "${GOPATH:-}" ]; then
            pass "GOPATH is not set when go is absent"
        else
            fail "GOPATH absence test" "Expected unset GOPATH when go is absent, got GOPATH=${GOPATH:-}"
        fi
    )
)

# Test 3: Verify bashrc-addendum sourcing
echo -e "\n[3/4] Testing dotfiles/.bashrc-addendum..."
(
    TEMP_HOME=$(mktemp -d)
    trap 'chmod -R u+w "$TEMP_HOME" 2>/dev/null || true; rm -rf "$TEMP_HOME"' EXIT

    export HOME="$TEMP_HOME"
    cp "$SCRIPT_DIR/dotfiles/.environment-variables" "$HOME/.environment-variables"

    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/dotfiles/.bashrc-addendum"

    if [ "${EDITOR:-}" = "vim" ]; then
        pass "bashrc-addendum sourced .environment-variables"
    else
        fail "bashrc-addendum sourcing" ".environment-variables was not sourced"
    fi
)

# Test 4: Verify LS_COLORS / dircolors configuration
echo -e "\n[4/4] Testing dircolors validity..."
if command -v dircolors >/dev/null 2>&1; then
    if dircolors_out=$(dircolors -b "$SCRIPT_DIR/dotfiles/.dir-colors/dircolors" 2>&1); then
        pass "dircolors database is valid"
    else
        fail "dircolors check" "dircolors failed: $dircolors_out"
    fi
else
    pass "dircolors not installed (skipped)"
fi

echo -e "\n========================================"
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
