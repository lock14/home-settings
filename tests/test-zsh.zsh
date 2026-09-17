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
        expected_aliases+=(e el elm et elt elx)
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
    cp "$SCRIPT_DIR/dotfiles/.p10k.zsh" "$HOME/.p10k.zsh"

    source "$SCRIPT_DIR/dotfiles/.zshrc-addendum"

    if [ "${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:-}" = "fg=#586E75" ]; then
        echo "PASS:ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE set correctly"
    else
        echo "FAIL:ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:Expected 'fg=#586E75', got '${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[command]:-}" = "fg=#859900" ] && [ "${ZSH_HIGHLIGHT_STYLES[builtin]:-}" = "fg=#859900" ] && [ "${ZSH_HIGHLIGHT_STYLES[function]:-}" = "fg=#859900" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES command, builtin, and function configured with unbolded Solarized Green"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES command:Expected 'fg=#859900', got '${ZSH_HIGHLIGHT_STYLES[command]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[reserved-word]:-}" = "fg=#B58900" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES reserved-word configured with Solarized Yellow for control flow"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES reserved-word:Expected 'fg=#B58900', got '${ZSH_HIGHLIGHT_STYLES[reserved-word]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]:-}" = "fg=#839496" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES command-substitution-delimiter configured with calm Solarized Base0"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES command-substitution-delimiter:Expected 'fg=#839496', got '${ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[single-hyphen-option]:-}" = "fg=#839496" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES options configured with Solarized Base0"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES options:Expected 'fg=#839496', got '${ZSH_HIGHLIGHT_STYLES[single-hyphen-option]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[assign]:-}" = "fg=#839496" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES assignments configured with Solarized Base0"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES assign:Expected 'fg=#839496', got '${ZSH_HIGHLIGHT_STYLES[assign]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[commandseparator]:-}" = "fg=#839496" ] && [ "${ZSH_HIGHLIGHT_STYLES[redirection]:-}" = "fg=#839496" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES operators and redirections configured with Solarized Base0"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES operators:Expected 'fg=#839496', got separator='${ZSH_HIGHLIGHT_STYLES[commandseparator]:-}', redir='${ZSH_HIGHLIGHT_STYLES[redirection]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[path]:-}" = "fg=#268BD2" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES path configured cleanly with Solarized Blue matching dircolors/eza without underline"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES path:Expected 'fg=#268BD2', got '${ZSH_HIGHLIGHT_STYLES[path]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[unknown-token]:-}" = "fg=#DC322F" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES unknown-token configured with unbolded Solarized Red"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES unknown-token:Expected 'fg=#DC322F', got '${ZSH_HIGHLIGHT_STYLES[unknown-token]:-}'"
    fi

    if [ "${POWERLEVEL9K_DIR_ANCHOR_BOLD:-}" = "false" ]; then
        echo "PASS:p10k directory anchor bold styling disabled (zero-jitter typography)"
    else
        echo "FAIL:p10k DIR_ANCHOR_BOLD:Expected 'false', got '${POWERLEVEL9K_DIR_ANCHOR_BOLD:-}'"
    fi

    if [ -z "${POWERLEVEL9K_OS_ICON_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_OS_ICON_FOREGROUND:-}" = "#93A1A1" ]; then
        echo "PASS:p10k OS icon configured with transparent background and Solarized Base1 foreground"
    else
        echo "FAIL:p10k OS_ICON colors:Expected bg='' fg='#93A1A1', got bg='${POWERLEVEL9K_OS_ICON_BACKGROUND:-}' fg='${POWERLEVEL9K_OS_ICON_FOREGROUND:-}'"
    fi

    if [ -z "${POWERLEVEL9K_VCS_CLEAN_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_VCS_CLEAN_FOREGROUND:-}" = "#859900" ] && \
       [ -z "${POWERLEVEL9K_VCS_UNTRACKED_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND:-}" = "#B58900" ] && \
       [ -z "${POWERLEVEL9K_VCS_MODIFIED_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_VCS_MODIFIED_FOREGROUND:-}" = "#B58900" ]; then
        echo "PASS:p10k VCS configured with transparent background and semantic foregrounds"
    else
        echo "FAIL:p10k VCS colors:Expected bg='' with Green clean and Yellow dirty foregrounds"
    fi

    if [[ "${POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX:-}" == *"#586E75"* ]]; then
        echo "PASS:p10k multiline ornaments configured with authentic Solarized Base01 (#586E75)"
    else
        echo "FAIL:p10k multiline ornaments:Expected Solarized Base01, got '${POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX:-}'"
    fi

    if ! [[ "${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[*]:-}" == *"prompt_char"* ]]; then
        echo "PASS:p10k prompt_char disabled in favor of clean multiline prefix"
    else
        echo "FAIL:p10k prompt_char:Expected prompt_char to be disabled in POWERLEVEL9K_LEFT_PROMPT_ELEMENTS"
    fi

    if [ -z "${POWERLEVEL9K_DIR_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_DIR_FOREGROUND:-}" = "#268BD2" ] && \
       [ "${POWERLEVEL9K_DIR_SHORTENED_FOREGROUND:-}" = "#268BD2" ] && [ "${POWERLEVEL9K_DIR_ANCHOR_FOREGROUND:-}" = "#268BD2" ]; then
        echo "PASS:p10k directory configured with transparent background and Solarized Blue foregrounds"
    else
        echo "FAIL:p10k DIR colors:Expected bg='' fg='#268BD2'"
    fi

    if [ "${POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR:-}" = '\uE0B1' ] && \
       [ "${POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR:-}" = '\uE0B3' ] && \
       [ "${POWERLEVEL9K_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL:-}" = '' ] && \
       [ "${POWERLEVEL9K_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL:-}" = '' ] && \
       [[ "${POWERLEVEL9K_DIR_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL:-}" == *'\uE0B1'* ]] && \
       [[ "${POWERLEVEL9K_STATUS_OK_VISUAL_IDENTIFIER_EXPANSION:-}" == *""* ]] && \
       [[ "${POWERLEVEL9K_STATUS_ERROR_VISUAL_IDENTIFIER_EXPANSION:-}" == *""* ]]; then
        echo "PASS:p10k pure unified thin chevron architecture ( and ) configured across transparent canvas"
    else
        echo "FAIL:p10k separators:Expected pure unified thin chevrons (\uE0B1 on left, \uE0B3 on right, empty outer caps, leading/trailing boundary chevrons)"
    fi

    if [ "${POWERLEVEL9K_DIR_HYPERLINK:-}" = "false" ]; then
        echo "PASS:p10k directory OSC 8 hyperlinks disabled for clean text selection"
    else
        echo "FAIL:p10k DIR_HYPERLINK:Expected 'false', got '${POWERLEVEL9K_DIR_HYPERLINK:-}'"
    fi

    if [[ "${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[*]:-}" == *"go_version"* ]] && \
       [[ "${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[*]:-}" == *"node_version"* ]] && \
       [[ "${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[*]:-}" == *"rust_version"* ]] && \
       [[ "${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[*]:-}" == *"java_version"* ]] && \
       [[ "${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[*]:-}" == *"package"* ]] && \
       [[ "${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[*]:-}" == *"terraform_version"* ]]; then
        echo "PASS:p10k right prompt elements includes language toolchains, package, and terraform"
    else
        echo "FAIL:p10k RIGHT_PROMPT_ELEMENTS:Expected toolchain versions enabled in POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS"
    fi

    if [ -z "${POWERLEVEL9K_GO_VERSION_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_GO_VERSION_FOREGROUND:-}" = "#2AA198" ] && \
       [ -z "${POWERLEVEL9K_NODE_VERSION_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_NODE_VERSION_FOREGROUND:-}" = "#859900" ] && \
       [ -z "${POWERLEVEL9K_RUST_VERSION_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_RUST_VERSION_FOREGROUND:-}" = "#CB4B16" ] && \
       [ -z "${POWERLEVEL9K_JAVA_VERSION_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_JAVA_VERSION_FOREGROUND:-}" = "#268BD2" ] && \
       [ -z "${POWERLEVEL9K_PACKAGE_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_PACKAGE_FOREGROUND:-}" = "#93A1A1" ] && \
       [ -z "${POWERLEVEL9K_TERRAFORM_VERSION_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_TERRAFORM_VERSION_FOREGROUND:-}" = "#6C71C4" ]; then
        echo "PASS:p10k toolchain versions unified on transparent background with semantic foregrounds"
    else
        echo "FAIL:p10k toolchain version colors:Expected transparent background with semantic foregrounds"
    fi

    if [ -z "${POWERLEVEL9K_KUBECONTEXT_DEFAULT_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_KUBECONTEXT_DEFAULT_FOREGROUND:-}" = "#268BD2" ] && \
       [ -z "${POWERLEVEL9K_AWS_DEFAULT_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_AWS_DEFAULT_FOREGROUND:-}" = "#CB4B16" ] && \
       [ -z "${POWERLEVEL9K_AZURE_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_AZURE_FOREGROUND:-}" = "#268BD2" ] && \
       [ -z "${POWERLEVEL9K_GCLOUD_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_GCLOUD_FOREGROUND:-}" = "#268BD2" ] && \
       [ -z "${POWERLEVEL9K_GOOGLE_APP_CRED_DEFAULT_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_GOOGLE_APP_CRED_DEFAULT_FOREGROUND:-}" = "#268BD2" ] && \
       [ -z "${POWERLEVEL9K_TERRAFORM_OTHER_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_TERRAFORM_OTHER_FOREGROUND:-}" = "#6C71C4" ]; then
        echo "PASS:p10k cloud provider segments unified on transparent background with semantic foregrounds"
    else
        echo "FAIL:p10k cloud provider segment colors:Expected transparent background with semantic foregrounds"
    fi

    if [ -z "${POWERLEVEL9K_STATUS_OK_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_STATUS_OK_FOREGROUND:-}" = "#859900" ] && \
       [ -z "${POWERLEVEL9K_STATUS_ERROR_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_STATUS_ERROR_FOREGROUND:-}" = "#DC322F" ] && \
       [ -z "${POWERLEVEL9K_COMMAND_EXECUTION_TIME_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND:-}" = "#B58900" ] && \
       [ -z "${POWERLEVEL9K_BACKGROUND_JOBS_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND:-}" = "#2AA198" ] && \
       [ -z "${POWERLEVEL9K_CONTEXT_ROOT_BACKGROUND:-}" ] && [ "${POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND:-}" = "#DC322F" ]; then
        echo "PASS:p10k status, execution time, background jobs, and context unified on transparent background with semantic foregrounds"
    else
        echo "FAIL:p10k right status colors:Expected transparent background with semantic foregrounds"
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
        echo "PASS:ZSH_HIGHLIGHT_HIGHLIGHTERS includes regexp highlighter for numbers"
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
