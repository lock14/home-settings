#!/usr/bin/env bash
# Test suite for Zsh completions (dotfiles/.zsh-completions, setup.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/tests/test-helper.sh"

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

if zsh -n "$SCRIPT_DIR/dotfiles/.zsh-completions"; then
    pass "Syntax valid: dotfiles/.zsh-completions"
else
    fail "Syntax check failed: dotfiles/.zsh-completions" "zsh -n returned non-zero"
fi

# Test 2: Execution in temporary environment
echo -e "\n[2/3] Testing dotfiles installation..."
TEMP_HOME=$(mktemp -d)
trap 'rm -rf "$TEMP_HOME"' EXIT

OLD_HOME="$HOME"
export HOME="$TEMP_HOME"

# Run setup (dotfiles only)
if output=$("$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-fonts --skip-tools --skip-vim --skip-zsh 2>&1); then
    :
else
    fail "setup.sh dotfiles-only" "Execution failed: $output"
fi

if [ -L "$TEMP_HOME/.zsh-completions" ]; then
    pass "Symlink created: ~/.zsh-completions"
else
    fail "Symlink missing" "Expected ~/.zsh-completions symlink"
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

if output=$(PATH="$MOCK_BIN:$PATH" "$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-fonts --skip-tools --skip-vim --skip-zsh 2>&1); then
    :
else
    fail "setup.sh completions generation" "Execution failed: $output"
fi

if [ -f "$TEMP_HOME/.zsh/completions/_gh" ] && grep -q "mock gh completion" "$TEMP_HOME/.zsh/completions/_gh"; then
    pass "Generated completion: ~/.zsh/completions/_gh"
else
    fail "CLI completion generation" "Failed to generate ~/.zsh/completions/_gh"
fi

# Idempotency check
if output=$(PATH="$MOCK_BIN:$PATH" "$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-fonts --skip-tools --skip-vim --skip-zsh 2>&1); then
    pass "setup.sh completions are idempotent"
else
    fail "setup.sh idempotency" "Second run failed: $output"
fi

export HOME="$OLD_HOME"

test_summary
