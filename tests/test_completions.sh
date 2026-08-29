#!/usr/bin/env bash
# Test suite for Zsh completions (dotfiles/.zsh_completions, setup.sh)

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
echo "Running Completions Setup Tests"
echo "========================================"

# Test 1: Syntax validation
echo -e "\n[1/3] Checking script and completion syntax..."
if bash -n "$SCRIPT_DIR/setup.sh"; then
    pass "Syntax valid: setup.sh"
else
    fail "Syntax check failed: setup.sh" "bash -n returned non-zero"
fi

if zsh -n "$SCRIPT_DIR/dotfiles/.zsh_completions"; then
    pass "Syntax valid: dotfiles/.zsh_completions"
else
    fail "Syntax check failed: dotfiles/.zsh_completions" "zsh -n returned non-zero"
fi

# Test 2: Execution in temporary environment
echo -e "\n[2/3] Testing dotfiles installation..."
TEMP_HOME=$(mktemp -d)
trap 'rm -rf "$TEMP_HOME"' EXIT

OLD_HOME="$HOME"
export HOME="$TEMP_HOME"

# Run setup (dotfiles only)
"$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-fonts --skip-tools --skip-vim --skip-zsh >/dev/null 2>&1

if [ -L "$TEMP_HOME/.zsh_completions" ]; then
    pass "Symlink created: ~/.zsh_completions"
else
    fail "Symlink missing" "Expected ~/.zsh_completions symlink"
fi

if [ -d "$TEMP_HOME/.zsh/completions" ]; then
    pass "Directory created: ~/.zsh/completions"
else
    fail "Directory missing" "Expected ~/.zsh/completions"
fi

# Test 3: CLI completion generator with mock CLI
echo -e "\n[3/3] Testing CLI generator with mock CLI..."
MOCK_BIN="$TEMP_HOME/mock_bin"
mkdir -p "$MOCK_BIN"
cat << 'EOF' > "$MOCK_BIN/gh"
#!/bin/sh
if [ "$1" = "completion" ]; then
    echo "# mock gh completion"
    exit 0
fi
EOF
chmod +x "$MOCK_BIN/gh"

PATH="$MOCK_BIN:$PATH" "$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-fonts --skip-tools --skip-vim --skip-zsh >/dev/null 2>&1

if [ -f "$TEMP_HOME/.zsh/completions/_gh" ] && grep -q "mock gh completion" "$TEMP_HOME/.zsh/completions/_gh"; then
    pass "Generated completion: ~/.zsh/completions/_gh"
else
    fail "CLI completion generation" "Failed to generate ~/.zsh/completions/_gh"
fi

# Idempotency check
if PATH="$MOCK_BIN:$PATH" "$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-fonts --skip-tools --skip-vim --skip-zsh >/dev/null 2>&1; then
    pass "setup.sh completions are idempotent"
else
    fail "setup.sh idempotency" "Second run failed"
fi

export HOME="$OLD_HOME"

echo -e "\n========================================"
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
