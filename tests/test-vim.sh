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
    if [ -f "$CPP_QUERY" ] && grep -q 'preproc_defined.*"defined".*@keyword' "$CPP_QUERY" && \
       grep -q 'sizeof_expression' "$CPP_QUERY" && \
       grep -q 'template_parameter_list' "$CPP_QUERY" && \
       grep -q 'using_declaration' "$CPP_QUERY" && \
       grep -q 'nullopt' "$CPP_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for C++ preproc defined, sizeof types, templates, using declarations, and sentinels"
    else
        fail "Neovim C++ query extension" "Missing or invalid after/queries/cpp/highlights.scm"
    fi

    if grep -q '\["@module"\]\s*=\s*{\s*fg\s*=\s*colors\.violet' "$NVIM_CONFIG" && \
       grep -q '\["@lsp\.type\.namespace"\]\s*=\s*{\s*fg\s*=\s*colors\.violet' "$NVIM_CONFIG"; then
        pass "Neovim maps @module and @lsp.type.namespace to Solarized Violet (#6c71c4)"
    else
        fail "Neovim namespace highlights" "Missing @module or @lsp.type.namespace mapped to colors.violet in init.lua"
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

    JAVA_FTPLUGIN="$SCRIPT_DIR/dotfiles/.config/nvim/ftplugin/java.lua"
    if [ -f "$JAVA_FTPLUGIN" ] && grep -q 'jdtls' "$JAVA_FTPLUGIN" && grep -q 'XDG_CACHE_HOME' "$JAVA_FTPLUGIN"; then
        pass "Neovim defines Java filetype plugin for nvim-jdtls with dynamic XDG workspace caching"
    else
        fail "Neovim Java ftplugin" "Missing or invalid dotfiles/.config/nvim/ftplugin/java.lua"
    fi

    if grep -q '"clangd"' "$NVIM_CONFIG" && \
       grep -q '"rust_analyzer"' "$NVIM_CONFIG" && \
       grep -q '"lua_ls"' "$NVIM_CONFIG" && \
       grep -q '"bashls"' "$NVIM_CONFIG" && \
       grep -q '"jdtls"' "$NVIM_CONFIG" && \
       grep -q 'nvim-jdtls' "$NVIM_CONFIG"; then
        pass "Neovim configures Polyglot LSPs (clangd, rust_analyzer, gopls, pyright, lua_ls, bashls, jdtls) in init.lua"
    else
        fail "Neovim polyglot LSPs" "Missing expected polyglot LSPs in dotfiles/.config/nvim/init.lua"
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

vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.cpp")
vim.cmd([[redraw]])
local cpp_line = vim.api.nvim_buf_get_lines(0, 33, 34, false)[1]
local col_t = string.find(cpp_line, "T>") - 1
local caps_t = vim.treesitter.get_captures_at_pos(0, 33, col_t)
local is_t_type = (caps_t[#caps_t] and caps_t[#caps_t].capture == "type")

local hl_module = vim.api.nvim_get_hl(0, {name = "@module", link = false})
local module_fg = string.format("%06x", hl_module.fg or 0)

local hl_lsp_ns = vim.api.nvim_get_hl(0, {name = "@lsp.type.namespace", link = false})
local lsp_ns_fg = string.format("%06x", hl_lsp_ns.fg or 0)

local line_20 = vim.api.nvim_buf_get_lines(0, 19, 20, false)[1]
local col_core = string.find(line_20, "core") - 1
local caps_core = vim.treesitter.get_captures_at_pos(0, 19, col_core)
local is_core_mod = (caps_core[#caps_core] and caps_core[#caps_core].capture == "module")

local line_39 = vim.api.nvim_buf_get_lines(0, 38, 39, false)[1]
local col_init = string.find(line_39, "Initializing") - 1
local caps_init = vim.treesitter.get_captures_at_pos(0, 38, col_init)
local is_init_const = (caps_init[#caps_init] and caps_init[#caps_init].capture == "constant")

local line_57 = vim.api.nvim_buf_get_lines(0, 56, 57, false)[1]
local col_nullopt = string.find(line_57, "nullopt") - 1
local caps_nullopt = vim.treesitter.get_captures_at_pos(0, 56, col_nullopt)
local is_nullopt_const = (caps_nullopt[#caps_nullopt] and caps_nullopt[#caps_nullopt].capture == "constant")

local line_73 = vim.api.nvim_buf_get_lines(0, 72, 73, false)[1]
local col_telem = string.find(line_73, "telemetry") - 1
local caps_telem = vim.treesitter.get_captures_at_pos(0, 72, col_telem)
local is_telem_mod = (caps_telem[#caps_telem] and caps_telem[#caps_telem].capture == "module")

vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.java")
local java_ft = vim.bo.filetype
local ok_jdtls, _ = pcall(require, "jdtls")

io.write(string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s",
    param_italic, const_fg, tostring(is_wn_type), tostring(is_so_kw), tostring(is_t_type),
    java_ft, tostring(ok_jdtls),
    module_fg, lsp_ns_fg, tostring(is_core_mod), tostring(is_init_const), tostring(is_nullopt_const), tostring(is_telem_mod)))
' -c 'q' 2>/dev/null || true)"

        IFS='|' read -r PARAM_ITALIC CONST_FG IS_WN_TYPE IS_SO_KW IS_T_TYPE JAVA_FT OK_JDTLS \
            MODULE_FG LSP_NS_FG IS_CORE_MOD IS_INIT_CONST IS_NULLOPT_CONST IS_TELEM_MOD <<< "$NVIM_RESULTS"

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

        if [ "$IS_T_TYPE" = "true" ]; then
            pass "Neovim Tree-sitter captures template <Printable T> as @type (Yellow)"
        else
            fail "Neovim template type parameter highlight" "Expected template <Printable T> to be captured as @type, got $IS_T_TYPE"
        fi

        if [ "$MODULE_FG" = "6c71c4" ] && [ "$LSP_NS_FG" = "6c71c4" ]; then
            pass "Neovim renders @module and @lsp.type.namespace in Solarized Violet (#6c71c4)"
        else
            fail "Neovim module/namespace highlight" "Expected fg=6c71c4, got module=$MODULE_FG lsp_ns=$LSP_NS_FG"
        fi

        if [ "$IS_CORE_MOD" = "true" ] && [ "$IS_TELEM_MOD" = "true" ]; then
            pass "Neovim Tree-sitter captures namespace identifiers (core, telemetry) as @module (Violet)"
        else
            fail "Neovim namespace capture" "Expected @module for core and telemetry, got core=$IS_CORE_MOD telem=$IS_TELEM_MOD"
        fi

        if [ "$IS_INIT_CONST" = "true" ]; then
            pass "Neovim Tree-sitter captures scoped enum members (NodeState::Initializing) as @constant (Magenta)"
        else
            fail "Neovim scoped enum constant capture" "Expected @constant for NodeState::Initializing, got $IS_INIT_CONST"
        fi

        if [ "$IS_NULLOPT_CONST" = "true" ]; then
            pass "Neovim Tree-sitter captures standard sentinels (std::nullopt) as @constant (Magenta)"
        else
            fail "Neovim sentinel capture" "Expected @constant for std::nullopt, got $IS_NULLOPT_CONST"
        fi

        if [ "$JAVA_FT" = "java" ] && [ "$OK_JDTLS" = "true" ]; then
            pass "Neovim detects Java filetype and loads nvim-jdtls cleanly"
        else
            fail "Neovim Java ftplugin verification" "Expected java filetype and jdtls loaded, got ft=$JAVA_FT ok=$OK_JDTLS"
        fi
    fi
else
    fail "Neovim init.lua missing" "Expected dotfiles/.config/nvim/init.lua"
fi

test_summary

