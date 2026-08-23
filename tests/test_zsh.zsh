#!/usr/bin/env zsh
# Test suite for zsh dotfiles (zsh_aliases, zsh_functions, zshrc_addendum)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo "  \033[32m✔ PASS:\033[0m $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo "  \033[31m✘ FAIL:\033[0m $1"
    echo "    $2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo "========================================"
echo "Running Zsh Configuration Tests"
echo "========================================"

# Test 1: Syntax check with zsh -n
echo "\n[1/5] Checking Zsh file syntax with 'zsh -n'..."
for f in "$SCRIPT_DIR/zsh_aliases" "$SCRIPT_DIR/zsh_functions" "$SCRIPT_DIR/zshrc_addendum" "$SCRIPT_DIR/p10k.zsh"; do
    if [ -f "$f" ]; then
        if zsh -n "$f"; then
            pass "Syntax valid: $(basename "$f")"
        else
            fail "Syntax check failed: $(basename "$f")" "zsh -n returned non-zero"
        fi
    fi
done


# Test 2: Source zsh_aliases and verify aliases
echo "\n[2/5] Testing zsh_aliases..."
test_aliases() {
    setopt aliases
    source "$SCRIPT_DIR/zsh_aliases"

    for expected_alias in gcommit gamend gfetch gpush gpushf gpull gprune gup fix-abcxyz-branch-name go_lint go_testall go_buildall tf yaml_lint; do
        if alias "$expected_alias" >/dev/null 2>&1; then
            echo "PASS:$expected_alias"
        else
            echo "FAIL:$expected_alias:alias not found"
        fi
    done
}

while IFS= read -r line; do
    if [[ "$line" =~ ^PASS:(.*) ]]; then
        pass "Alias defined: ${match[1]}"
    elif [[ "$line" =~ ^FAIL:(.*):(.*) ]]; then
        fail "Alias missing: ${match[1]}" "${match[2]}"
    fi
done < <(test_aliases)

# Test 3: Source zsh_functions and verify functions
echo "\n[3/5] Testing zsh_functions..."
test_functions() {
    source "$SCRIPT_DIR/zsh_functions"

    for expected_func in fs gsync; do
        if typeset -f "$expected_func" >/dev/null 2>&1; then
            echo "PASS:$expected_func"
        else
            echo "FAIL:$expected_func:function not found"
        fi
    done
}

while IFS= read -r line; do
    if [[ "$line" =~ ^PASS:(.*) ]]; then
        pass "Function defined: ${match[1]}"
    elif [[ "$line" =~ ^FAIL:(.*):(.*) ]]; then
        fail "Function missing: ${match[1]}" "${match[2]}"
    fi
done < <(test_functions)

# Test 4: Functional test of gsync & git aliases in a mock git repository
echo "\n[4/5] Testing git functions and aliases behavior..."
test_git_integration() {
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT

    cd "$TEMP_DIR"

    # Initialize a dummy remote repo
    mkdir remote.git && (cd remote.git && git init --bare -b main >/dev/null 2>&1)
    # Clone it to local
    git clone remote.git local >/dev/null 2>&1
    cd local
    git config user.email "test@example.com"
    git config user.name "Test User"
    git config commit.gpgsign false

    # Initial commit on main
    echo "initial" > file.txt
    git add file.txt && git commit -m "initial commit" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1

    # Source functions and aliases
    setopt aliases
    source "$SCRIPT_DIR/zsh_functions"
    source "$SCRIPT_DIR/zsh_aliases"

    # Test gsync outside git repo
    (
        cd "$TEMP_DIR"
        out=$(gsync 2>&1 || true)
        if echo "$out" | grep -qi "error"; then
            echo "PASS:gsync fails gracefully when not in git repository"
        else
            echo "FAIL:gsync outside git repo:Expected error message, got: $out"
        fi
    )

    # Create a feature branch
    git checkout -b feature-1 >/dev/null 2>&1
    echo "feature update" >> file.txt
    git commit -am "feature work" >/dev/null 2>&1

    # Run gsync on feature branch
    if gsync >/dev/null 2>&1; then
        echo "PASS:gsync succeeds on feature branch with 'main'"
    else
        echo "FAIL:gsync execution:gsync failed on standard feature branch"
    fi

    # Verify branch is still feature-1
    current=$(git rev-parse --abbrev-ref HEAD)
    if [ "$current" = "feature-1" ]; then
        echo "PASS:gsync preserves current branch (feature-1)"
    else
        echo "FAIL:gsync branch preservation:Expected feature-1, got $current"
    fi

    # Test fix-abcxyz-branch-name alias
    eval "$(alias fix-abcxyz-branch-name | sed 's/^fix-abcxyz-branch-name=//' | sed "s/^'//" | sed "s/'$//")"
    renamed_branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$renamed_branch" = "$USER/feature-1" ]; then
        echo "PASS:fix-abcxyz-branch-name successfully renamed branch"
    else
        echo "FAIL:fix-abcxyz-branch-name:Expected $USER/feature-1, got $renamed_branch"
    fi

    # Test gprune alias
    git checkout main >/dev/null 2>&1
    git branch test-to-delete >/dev/null 2>&1
    eval "$(alias gprune | sed 's/^gprune=//' | sed "s/^'//" | sed "s/'$//")" >/dev/null 2>&1
    if ! git show-ref --verify --quiet refs/heads/test-to-delete; then
        echo "PASS:gprune successfully pruned non-main branch"
    else
        echo "FAIL:gprune:Branch test-to-delete was not pruned"
    fi
}

while IFS= read -r line; do
    if [[ "$line" =~ ^PASS:(.*) ]]; then
        pass "${match[1]}"
    elif [[ "$line" =~ ^FAIL:(.*):(.*) ]]; then
        fail "${match[1]}" "${match[2]}"
    fi
done < <(test_git_integration)

# Test 5: Test zshrc_addendum sourcing
echo "\n[5/5] Testing zshrc_addendum..."
test_addendum() {
    TEMP_HOME=$(mktemp -d)
    trap 'rm -rf "$TEMP_HOME"' EXIT

    export HOME="$TEMP_HOME"
    cp "$SCRIPT_DIR/zsh_aliases" "$HOME/.zsh_aliases"
    cp "$SCRIPT_DIR/zsh_functions" "$HOME/.zsh_functions"
    touch "$HOME/.environment_variables"

    source "$SCRIPT_DIR/zshrc_addendum"

    if [ "${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:-}" = "fg=10" ]; then
        echo "PASS:ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE set correctly"
    else
        echo "FAIL:ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:Expected 'fg=10', got '${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:-}'"
    fi

    if typeset -f gsync >/dev/null 2>&1; then
        echo "PASS:zshrc_addendum sourced .zsh_functions"
    else
        echo "FAIL:zshrc_addendum sourcing:.zsh_functions was not sourced"
    fi
}

while IFS= read -r line; do
    if [[ "$line" =~ ^PASS:(.*) ]]; then
        pass "${match[1]}"
    elif [[ "$line" =~ ^FAIL:(.*):(.*) ]]; then
        fail "${match[1]}" "${match[2]}"
    fi
done < <(test_addendum)

echo "\n========================================"
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
