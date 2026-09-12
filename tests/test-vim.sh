#!/usr/bin/env bash
# Test suite for Vim configuration (dotfiles/.vimrc, vim-snippets integration)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/tests/test-helper.sh"

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

if ! grep -E '^highlight Diff[A-Za-z]+.*[ \t]+$' "$SCRIPT_DIR/dotfiles/.vimrc" >/dev/null 2>&1; then
    pass "dotfiles/.vimrc diff highlight definitions contain no trailing whitespace"
else
    fail "dotfiles/.vimrc trailing whitespace" "Trailing whitespace found in Diff highlight definitions"
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
check_option "g:SuperTabDefaultCompletionType == '<c-n>'" "SuperTabDefaultCompletionType is <c-n>"
check_option "g:AutoPairsShortcutJump == '<c-l>'" "AutoPairsShortcutJump is <c-l>"

# Test 4: Verify Home key mapping
echo -e "\n[4/6] Testing key mappings..."
check_option "maparg('<Home>', 'n') == '^'" "Normal mode <Home> mapped to ^"
check_option "maparg('<Home>', 'i') == '<Esc>^i'" "Insert mode <Home> mapped to <Esc>^i"

# Test 5: Verify Vim bundle provisioning
echo -e "\n[5/6] Testing Vim bundle provisioning..."
if grep -q 'honza/vim-snippets' "$SCRIPT_DIR/setup.sh" || grep -q 'honza/vim-snippets' "$SCRIPT_DIR/modules/50-vim.sh"; then
    pass "setup.sh provisions curated honza/vim-snippets bundle"
else
    fail "setup.sh vim-snippets" "Expected honza/vim-snippets in setup.sh or modules/50-vim.sh"
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

    if grep -q '@markup.heading\.1.*colors\.orange' "$NVIM_CONFIG" && \
       grep -q '@markup.heading\.2.*colors\.yellow' "$NVIM_CONFIG" && \
       grep -q '@markup.heading\.3.*colors\.blue' "$NVIM_CONFIG" && \
       grep -q '@markup.heading\.4.*colors\.violet' "$NVIM_CONFIG" && \
       grep -q '@markup.heading\.5.*colors\.magenta' "$NVIM_CONFIG" && \
       grep -q '@markup.heading\.6.*colors\.base1' "$NVIM_CONFIG" && \
       grep -q '@markup\.quote.*colors\.blue' "$NVIM_CONFIG" && \
       grep -q '@type.*colors\.yellow' "$NVIM_CONFIG" && \
       grep -q '@keyword\.type.*colors\.green' "$NVIM_CONFIG" && \
       grep -q '@keyword\.conditional\.ternary.*colors\.base0' "$NVIM_CONFIG" && \
       grep -q 'markdownH1.*colors\.orange' "$NVIM_CONFIG" && \
       grep -q '\["@constant"\] = { fg = colors\.magenta }' "$NVIM_CONFIG" && \
       grep -q '@attribute' "$NVIM_CONFIG"; then
        pass "Neovim init.lua defines first-principles markup headings, blue quotes, yellow types, green declaration keywords, magenta constants, and calm operators matching bat"
    else
        fail "Neovim markup overrides" "Missing or misconfigured @markup.heading.1-6, @markup.quote, @type, @keyword.type, @constant, or markdownH1 in init.lua"
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

    C_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/c/highlights.scm"
    if [ -f "$C_QUERY" ] && grep -q 'preproc_defined.*"defined".*@keyword' "$C_QUERY" && grep -q 'sizeof_expression' "$C_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for C preprocessor defined keyword and sizeof custom types"
    else
        fail "Neovim C query extension" "Missing or invalid after/queries/c/highlights.scm"
    fi

    CPP_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/cpp/highlights.scm"
    if [ -f "$CPP_QUERY" ] && grep -q 'preproc_defined.*"defined".*@keyword' "$CPP_QUERY" && grep -q 'sizeof_expression' "$CPP_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for C++ preprocessor defined keyword and sizeof custom types"
    else
        fail "Neovim C++ query extension" "Missing or invalid after/queries/cpp/highlights.scm"
    fi

    PRINTF_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/printf/highlights.scm"
    if [ -f "$PRINTF_QUERY" ] && grep -q 'format.*@string.special' "$PRINTF_QUERY" && \
       grep -q '@string\.escape.*colors\.cyan' "$NVIM_CONFIG" && \
       grep -q '@character\.printf.*colors\.cyan' "$NVIM_CONFIG" && \
       grep -q '"printf"' "$NVIM_CONFIG"; then
        pass "Neovim defines Tree-sitter printf format specifiers and string escapes in Solarized Cyan"
    else
        fail "Neovim printf highlights" "Missing or invalid printf format specifiers and escape sequences in init.lua"
    fi

    if command -v nvim >/dev/null 2>&1; then
        NVIM_RESULTS="$(nvim --headless -c "edit $SCRIPT_DIR/sample-code/sample.c" -c 'lua
vim.cmd([[redraw]])
local hl_param = vim.api.nvim_get_hl(0, {name = "@variable.parameter", link = false})
local param_italic = tostring(hl_param.italic == true)

local hl_const = vim.api.nvim_get_hl(0, {name = "@constant", link = false})
local const_fg = string.format("%06x", hl_const.fg or 0)

local line = vim.api.nvim_buf_get_lines(0, 54, 55, false)[1]

local col_wn = string.find(line, "WorkerNode", 30) - 1
local caps_wn = vim.treesitter.get_captures_at_pos(0, 54, col_wn)
local is_wn_type = false
for _, c in ipairs(caps_wn) do
    if c.capture == "type" then is_wn_type = true break end
end

local col_so = string.find(line, "sizeof") - 1
local caps_so = vim.treesitter.get_captures_at_pos(0, 54, col_so)
local is_so_kw = false
for _, c in ipairs(caps_so) do
    if c.capture == "keyword.operator" then is_so_kw = true break end
end

io.write(string.format("%s|%s|%s|%s", param_italic, const_fg, tostring(is_wn_type), tostring(is_so_kw)))
' -c 'q' 2>/dev/null || true)"

        IFS='|' read -r PARAM_ITALIC CONST_FG IS_WN_TYPE IS_SO_KW <<< "$NVIM_RESULTS"

        if [ "$PARAM_ITALIC" != "true" ]; then
            pass "Neovim renders parameters in upright font without italics"
        else
            fail "Neovim parameter italics" "Expected upright parameter highlight in Neovim, got italic=$PARAM_ITALIC"
        fi

        if [ "$CONST_FG" = "d33682" ]; then
            pass "Neovim renders @constant in Solarized Magenta (#d33682)"
        else
            fail "Neovim @constant highlight" "Expected fg=d33682 for @constant, got fg=$CONST_FG"
        fi

        if [ "$IS_WN_TYPE" = "true" ]; then
            pass "Neovim Tree-sitter captures sizeof(WorkerNode) as @type (Yellow)"
        else
            fail "Neovim sizeof(type) highlight" "Expected sizeof(WorkerNode) to be captured as @type, got $IS_WN_TYPE"
        fi

        if [ "$IS_SO_KW" = "true" ]; then
            pass "Neovim Tree-sitter captures sizeof as @keyword.operator (Green)"
        else
            fail "Neovim sizeof highlight" "Expected sizeof to be captured as @keyword.operator, got $IS_SO_KW"
        fi
    fi
else
    fail "Neovim init.lua missing" "Expected dotfiles/.config/nvim/init.lua"
fi

test_summary

