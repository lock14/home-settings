#!/usr/bin/env bash
# Test suite for environment variables and bash configurations

# shellcheck disable=SC2030,SC2031
set -euo pipefail
export MISE_YES=1

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
for f in "$SCRIPT_DIR/setup.sh" "$SCRIPT_DIR/dotfiles/.bashrc-addendum" "$SCRIPT_DIR/dotfiles/.environment-variables" "$SCRIPT_DIR/dotfiles/.aliases"; do
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

    if [ "${COLORTERM:-}" = "truecolor" ]; then
        pass "COLORTERM is set to truecolor"
    else
        fail "COLORTERM export" "Expected truecolor, got: ${COLORTERM:-}"
    fi

    if [ "${BAT_THEME:-}" = "Solarized-Dark-TrueColor" ]; then
        pass "BAT_THEME is set to Solarized-Dark-TrueColor"
    else
        fail "BAT_THEME export" "Expected Solarized-Dark-TrueColor, got: ${BAT_THEME:-}"
    fi

    if [ -n "${EZA_COLORS:-}" ] && [ "${EXA_COLORS:-}" = "${EZA_COLORS:-}" ]; then
        pass "EZA_COLORS and EXA_COLORS configured with Solarized Dark palette"
    else
        fail "EZA_COLORS export" "Expected Solarized Dark in EZA_COLORS, got: ${EZA_COLORS:-}"
    fi

    if command -v nvim >/dev/null 2>&1; then
        if [ "${EDITOR:-}" = "nvim" ]; then
            pass "EDITOR is set to nvim (nvim detected)"
        else
            fail "EDITOR export" "Expected nvim, got: ${EDITOR:-}"
        fi
    else
        if [ "${EDITOR:-}" = "vim" ]; then
            pass "EDITOR is set to vim (fallback when nvim is absent)"
        else
            fail "EDITOR export" "Expected vim, got: ${EDITOR:-}"
        fi
    fi

    if [ "${GOPATH:-}" = "$TEMP_HOME/.local/share/go" ] && [[ ":$PATH:" == *":$TEMP_HOME/.local/share/go/bin:"* ]]; then
        pass "GOPATH and \$GOPATH/bin set cleanly to XDG location ($TEMP_HOME/.local/share/go)"
    else
        fail "GOPATH export" "Expected $TEMP_HOME/.local/share/go, got GOPATH=${GOPATH:-}, PATH=$PATH"
    fi

    if [ "${GOCACHE:-}" = "$TEMP_HOME/.cache/go-build" ]; then
        pass "GOCACHE set cleanly to XDG location ($TEMP_HOME/.cache/go-build)"
    else
        fail "GOCACHE export" "Expected $TEMP_HOME/.cache/go-build, got GOCACHE=${GOCACHE:-}"
    fi

    if [[ "${FZF_DEFAULT_OPTS:-}" == *"#002B36"* ]] && [[ "${FZF_DEFAULT_OPTS:-}" == *"#839496"* ]]; then
        pass "FZF_DEFAULT_OPTS configured with Solarized Dark palette"
    else
        fail "FZF_DEFAULT_OPTS export" "Expected Solarized Dark palette in FZF_DEFAULT_OPTS, got: ${FZF_DEFAULT_OPTS:-}"
    fi
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

    if [ "${EDITOR:-}" = "vim" ] || [ "${EDITOR:-}" = "nvim" ]; then
        pass "bashrc-addendum sourced .environment-variables"
    else
        fail "bashrc-addendum sourcing" ".environment-variables was not sourced (EDITOR=${EDITOR:-})"
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
