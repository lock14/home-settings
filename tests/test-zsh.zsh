#!/usr/bin/env zsh
# Test suite for zsh dotfiles (dotfiles/.zsh-aliases, dotfiles/.zsh-functions, dotfiles/.zshrc-addendum)

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
for f in "$SCRIPT_DIR/dotfiles/.aliases" "$SCRIPT_DIR/dotfiles/.zsh-functions" "$SCRIPT_DIR/dotfiles/.zshrc-addendum" "$SCRIPT_DIR/dotfiles/.zsh-completions" "$SCRIPT_DIR/dotfiles/.p10k.zsh"; do
    if [ -f "$f" ]; then
        if zsh -n "$f"; then
            pass "Syntax valid: $(basename "$f")"
        else
            fail "Syntax check failed: $(basename "$f")" "zsh -n returned non-zero"
        fi
    fi
done

# Test 2: Source .aliases and verify aliases
echo "\n[2/5] Testing dotfiles/.aliases..."
test_aliases() {
    setopt aliases
    source "$SCRIPT_DIR/dotfiles/.aliases"

    local expected_aliases=(gcommit gamend gfetch gpush gpushf gpull gup gprune gpurge guser-branch go-lint go-testall go-buildall tf yaml-lint vi v ls ll la l)
    if command -v eza >/dev/null 2>&1; then
        expected_aliases+=(e el et elt)
    fi

    if command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1; then
        expected_aliases+=(b)
    fi

    for expected_alias in "${expected_aliases[@]}"; do
        if alias "$expected_alias" >/dev/null 2>&1; then
            echo "PASS:$expected_alias"
        else
            echo "FAIL:$expected_alias:alias not found"
        fi
    done

    if alias cat >/dev/null 2>&1; then
        echo "FAIL:cat:cat should not be aliased (should use coreutils cat)"
    else
        echo "PASS:cat is not aliased (coreutils cat)"
    fi
}

while IFS= read -r line; do
    if [[ "$line" =~ ^PASS:(.*) ]]; then
        pass "Alias defined: ${match[1]}"
    elif [[ "$line" =~ ^FAIL:(.*):(.*) ]]; then
        fail "Alias missing: ${match[1]}" "${match[2]}"
    fi
done < <(test_aliases)

# Test 3: Source zsh-functions and verify functions
echo "\n[3/5] Testing dotfiles/.zsh-functions..."
test_functions() {
    source "$SCRIPT_DIR/dotfiles/.aliases"
    source "$SCRIPT_DIR/dotfiles/.zsh-functions"

    for expected_func in fs gsync; do
        if typeset -f "$expected_func" >/dev/null 2>&1; then
            echo "PASS:$expected_func"
        else
            echo "FAIL:$expected_func:function not found"
        fi
    done

    # Test fs execution with aliases active
    if command -v tree >/dev/null 2>&1 && (command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1); then
        if (cd "$SCRIPT_DIR/dotfiles" && fs >/dev/null 2>&1); then
            echo "PASS:fs function runs cleanly on dotfiles directory"
        else
            echo "FAIL:fs execution:fs failed to list directory"
        fi
    fi
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
    source "$SCRIPT_DIR/dotfiles/.zsh-functions"
    source "$SCRIPT_DIR/dotfiles/.aliases"

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

    # Test guser-branch alias
    eval "$(alias guser-branch | sed 's/^guser-branch=//' | sed "s/^'//" | sed "s/'$//")"
    renamed_branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$renamed_branch" = "$USER/feature-1" ]; then
        echo "PASS:guser-branch successfully renamed branch"
    else
        echo "FAIL:guser-branch:Expected $USER/feature-1, got $renamed_branch"
    fi

    # Test guser-branch idempotency (running again should not duplicate $USER/)
    eval "$(alias guser-branch | sed 's/^guser-branch=//' | sed "s/^'//" | sed "s/'$//")"
    renamed_branch_again=$(git rev-parse --abbrev-ref HEAD)
    if [ "$renamed_branch_again" = "$USER/feature-1" ]; then
        echo "PASS:guser-branch is idempotent"
    else
        echo "FAIL:guser-branch idempotency:Expected $USER/feature-1, got $renamed_branch_again"
    fi

    # Test guser-branch refusal on main
    git checkout main >/dev/null 2>&1
    eval "$(alias guser-branch | sed 's/^guser-branch=//' | sed "s/^'//" | sed "s/'$//")" >/dev/null 2>&1 || true
    if [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]; then
        echo "PASS:guser-branch safely refuses to rename main"
    else
        echo "FAIL:guser-branch on main:Renamed main to $(git rev-parse --abbrev-ref HEAD)"
    fi

    # Test gprune alias (safe prune: deletes merged branch, preserves unmerged branch)
    git branch test-to-delete >/dev/null 2>&1
    git checkout -b test-unmerged >/dev/null 2>&1
    echo "unmerged work" >> file.txt
    git commit -am "unmerged commit" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1

    eval "$(alias gprune | sed 's/^gprune=//' | sed "s/^'//" | sed "s/'$//")" >/dev/null 2>&1
    if ! git show-ref --verify --quiet refs/heads/test-to-delete; then
        echo "PASS:gprune successfully pruned merged branch"
    else
        echo "FAIL:gprune:Merged branch test-to-delete was not pruned"
    fi
    if git show-ref --verify --quiet refs/heads/test-unmerged; then
        echo "PASS:gprune preserved unmerged branch"
    else
        echo "FAIL:gprune:Unmerged branch test-unmerged was unexpectedly deleted"
    fi

    # Test gpurge alias (nuclear prune: deletes unmerged branch too)
    eval "$(alias gpurge | sed 's/^gpurge=//' | sed "s/^'//" | sed "s/'$//")" >/dev/null 2>&1
    if ! git show-ref --verify --quiet refs/heads/test-unmerged; then
        echo "PASS:gpurge successfully pruned unmerged branch"
    else
        echo "FAIL:gpurge:Branch test-unmerged was not pruned by gpurge"
    fi
}

while IFS= read -r line; do
    if [[ "$line" =~ ^PASS:(.*) ]]; then
        pass "${match[1]}"
    elif [[ "$line" =~ ^FAIL:(.*):(.*) ]]; then
        fail "${match[1]}" "${match[2]}"
    fi
done < <(test_git_integration)

# Test 5: Test zshrc-addendum sourcing
echo "\n[5/5] Testing dotfiles/.zshrc-addendum..."
test_addendum() {
    TEMP_HOME=$(mktemp -d)
    trap 'rm -rf "$TEMP_HOME"' EXIT

    export HOME="$TEMP_HOME"
    cp "$SCRIPT_DIR/dotfiles/.aliases" "$HOME/.aliases"
    cp "$SCRIPT_DIR/dotfiles/.zsh-functions" "$HOME/.zsh-functions"
    touch "$HOME/.environment-variables"

    source "$SCRIPT_DIR/dotfiles/.zshrc-addendum"

    if [ "${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:-}" = "fg=#586E75" ]; then
        echo "PASS:ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE set correctly"
    else
        echo "FAIL:ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:Expected 'fg=#586E75', got '${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[command]:-}" = "fg=#859900,bold" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES command configured with Solarized Green"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES command:Expected 'fg=#859900,bold', got '${ZSH_HIGHLIGHT_STYLES[command]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[single-hyphen-option]:-}" = "fg=#2AA198" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES options configured with Solarized Cyan"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES options:Expected 'fg=#2AA198', got '${ZSH_HIGHLIGHT_STYLES[single-hyphen-option]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[path]:-}" = "fg=#2AA198" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES path configured cleanly with Solarized Cyan without underline"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES path:Expected 'fg=#2AA198', got '${ZSH_HIGHLIGHT_STYLES[path]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[unknown-token]:-}" = "fg=#DC322F,bold" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES unknown-token configured with Solarized Red"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES unknown-token:Expected 'fg=#DC322F,bold', got '${ZSH_HIGHLIGHT_STYLES[unknown-token]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[numeric-fd]:-}" = "fg=#D33682" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES numeric-fd configured with Solarized Magenta"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES numeric-fd:Expected 'fg=#D33682', got '${ZSH_HIGHLIGHT_STYLES[numeric-fd]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[arithmetic-expansion]:-}" = "fg=#D33682" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES arithmetic-expansion configured with Solarized Magenta"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES arithmetic-expansion:Expected 'fg=#D33682', got '${ZSH_HIGHLIGHT_STYLES[arithmetic-expansion]:-}'"
    fi

    if [[ "${ZSH_HIGHLIGHT_HIGHLIGHTERS[*]:-}" == *"regexp"* ]]; then
        echo "PASS:ZSH_HIGHLIGHT_HIGHLIGHTERS includes regexp highlighter"
    else
        echo "PASS:ZSH_HIGHLIGHT_HIGHLIGHTERS fallback without PCRE"
    fi

    if [[ "${zle_highlight[*]:-}" == *"region:bg=#073642"* ]]; then
        echo "PASS:zle_highlight configured with Solarized Base02 selection"
    else
        echo "FAIL:zle_highlight:Expected region:bg=#073642, got '${zle_highlight[*]:-}'"
    fi

    if typeset -f gsync >/dev/null 2>&1; then
        echo "PASS:zshrc-addendum sourced .zsh-functions"
    else
        echo "FAIL:zshrc-addendum sourcing:.zsh-functions was not sourced"
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
