#!/usr/bin/env bash
# Test suite for Vim configuration (dotfiles/.vimrc, vim-snippets integration)

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
echo -e "\n[1/6] Testing dotfiles/.vimrc loading without syntax errors..."
if vim -u "$SCRIPT_DIR/dotfiles/.vimrc" -N -es -c "q" >/dev/null 2>&1; then
    pass ".vimrc loaded cleanly without errors"
else
    fail ".vimrc load" "Vim reported errors when loading dotfiles/.vimrc"
fi

# Test 2: Indentation and tab settings
echo -e "\n[2/6] Testing Vim indentation & formatting options..."
check_option() {
    local opt_expr="$1"
    local desc="$2"
    if vim -u "$SCRIPT_DIR/dotfiles/.vimrc" -N -es -c "if $opt_expr | q | else | cquit 1 | endif" >/dev/null 2>&1; then
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
echo -e "\n[3/6] Testing UltiSnips and plugin settings..."
check_option "g:UltiSnipsExpandTrigger == '<tab>'" "UltiSnipsExpandTrigger is <tab>"
check_option "g:UltiSnipsJumpForwardTrigger == '<c-j>'" "UltiSnipsJumpForwardTrigger is <c-j>"
check_option "g:UltiSnipsJumpBackwardTrigger == '<c-k>'" "UltiSnipsJumpBackwardTrigger is <c-k>"
check_option "g:AutoPairsShortcutJump == '<c-l>'" "AutoPairsShortcutJump is <c-l>"

# Test 4: Verify Home key mapping
echo -e "\n[4/6] Testing key mappings..."
check_option "maparg('<Home>', 'n') == '^'" "Normal mode <Home> mapped to ^"
check_option "maparg('<Home>', 'i') == '<Esc>^i'" "Insert mode <Home> mapped to <Esc>^i"

# Test 5: Verify setup.sh configures honza/vim-snippets
echo -e "\n[5/6] Testing Vim bundle provisioning in setup.sh..."
if grep -q 'honza/vim-snippets' "$SCRIPT_DIR/setup.sh"; then
    pass "setup.sh provisions curated honza/vim-snippets bundle"
else
    fail "setup.sh vim-snippets" "Expected honza/vim-snippets in setup.sh"
fi

# Test 6: Verify Neovim init.lua configuration
echo -e "\n[6/6] Testing Neovim init.lua configuration..."
NVIM_CONFIG="$SCRIPT_DIR/dotfiles/.config/nvim/init.lua"
if [ -f "$NVIM_CONFIG" ]; then
    pass "Neovim init.lua exists at dotfiles/.config/nvim/init.lua"

    if grep -q 'maxmx03/solarized.nvim' "$NVIM_CONFIG" && grep -q 'nvim-treesitter' "$NVIM_CONFIG" && grep -q 'nvim-telescope/telescope.nvim' "$NVIM_CONFIG" && grep -q 'mason-lspconfig' "$NVIM_CONFIG"; then
        pass "Neovim init.lua contains Solarized, Treesitter, Telescope, and Mason LSP"
    else
        fail "Neovim plugins" "Missing expected plugin declarations in init.lua"
    fi

    if command -v nvim >/dev/null 2>&1; then
        if nvim --headless -u NONE -c "lua local f, err = loadfile('$NVIM_CONFIG'); if not f then error(err) end" +qall >/dev/null 2>&1; then
            pass "Neovim verified init.lua syntax cleanly"
        else
            fail "Neovim init.lua syntax" "Neovim reported errors when parsing init.lua"
        fi
    elif command -v luajit >/dev/null 2>&1; then
        if luajit -bl "$NVIM_CONFIG" >/dev/null 2>&1; then
            pass "Lua syntax valid: init.lua"
        else
            fail "Lua syntax error" "init.lua failed syntax check"
        fi
    elif command -v lua >/dev/null 2>&1; then
        if lua -e "assert(loadfile('$NVIM_CONFIG'))" >/dev/null 2>&1; then
            pass "Lua syntax valid: init.lua"
        else
            fail "Lua syntax error" "init.lua failed syntax check"
        fi
    fi
else
    fail "Neovim init.lua missing" "Expected dotfiles/.config/nvim/init.lua"
fi

echo -e "\n========================================"
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi

