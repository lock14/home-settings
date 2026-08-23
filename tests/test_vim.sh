#!/usr/bin/env bash
# Test suite for Vim configuration (.vimrc, vim-setup.sh)

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
echo "Running Vim Configuration Tests"
echo "========================================"

# Test 1: Vimrc loads without errors
echo -e "\n[1/4] Testing .vimrc loading without syntax errors..."
if vim -u "$SCRIPT_DIR/.vimrc" -N -es -c "q" >/dev/null 2>&1; then
    pass ".vimrc loaded cleanly without errors"
else
    fail ".vimrc load" "Vim reported errors when loading .vimrc"
fi

# Test 2: Indentation and tab settings
echo -e "\n[2/4] Testing Vim indentation & formatting options..."
check_option() {
    local opt_expr="$1"
    local desc="$2"
    if vim -u "$SCRIPT_DIR/.vimrc" -N -es -c "if $opt_expr | q | else | cquit 1 | endif" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc" "Option check failed: $opt_expr"
    fi
}

check_option "&tabstop == 4" "tabstop is set to 4"
check_option "&shiftwidth == 4" "shiftwidth is set to 4"
check_option "&expandtab == 1" "expandtab is enabled"
check_option "&background == 'dark'" "background is set to dark"

# Test 3: UltiSnips and AutoPairs variables
echo -e "\n[3/4] Testing UltiSnips and plugin settings..."
check_option "g:UltiSnipsExpandTrigger == '<tab>'" "UltiSnipsExpandTrigger is <tab>"
check_option "g:UltiSnipsJumpForwardTrigger == '<c-j>'" "UltiSnipsJumpForwardTrigger is <c-j>"
check_option "g:UltiSnipsJumpBackwardTrigger == '<c-k>'" "UltiSnipsJumpBackwardTrigger is <c-k>"
check_option "g:AutoPairsShortcutJump == '<c-l>'" "AutoPairsShortcutJump is <c-l>"

# Test 4: Verify Home key mapping
echo -e "\n[4/4] Testing key mappings..."
check_option "maparg('<Home>', 'n') == '^'" "Normal mode <Home> mapped to ^"
check_option "maparg('<Home>', 'i') == '<Esc>^i'" "Insert mode <Home> mapped to <Esc>^i"

echo -e "\n========================================"
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
