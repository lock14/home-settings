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
       grep -q 'namespace_definition' "$CPP_QUERY" && \
       grep -q 'qualified_identifier' "$CPP_QUERY" && \
       grep -q 'using_declaration' "$CPP_QUERY" && \
       grep -q 'nullopt' "$CPP_QUERY" && \
       grep -q '@attribute' "$CPP_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for C++ preproc defined, sizeof types, templates, using declarations, sentinels, and attributes"
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

    DIFF_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/diff/highlights.scm"
    if [ -f "$DIFF_QUERY" ] && grep -q 'deletion.*@diff.minus' "$DIFF_QUERY" && \
       grep -q 'addition.*@diff.plus' "$DIFF_QUERY" && \
       grep -q 'location.*@diff.line' "$DIFF_QUERY" && \
       grep -q '\["@diff\.plus"\]\s*=\s*{\s*fg\s*=\s*colors\.green' "$NVIM_CONFIG" && \
       grep -q '\["@diff\.minus"\]\s*=\s*{\s*fg\s*=\s*colors\.red' "$NVIM_CONFIG" && \
       grep -q '\["@diff\.line"\]\s*=\s*{\s*fg\s*=\s*colors\.blue' "$NVIM_CONFIG"; then
        pass "Neovim defines Tree-sitter query extensions and highlights for diff (Green additions, Red deletions, Blue hunk lines)"
    else
        fail "Neovim diff query extension" "Missing or invalid after/queries/diff/highlights.scm or init.lua diff overrides"
    fi

    GO_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/go/highlights.scm"
    if [ -f "$GO_QUERY" ] && grep -q '"package" @keyword' "$GO_QUERY" && grep -Fq '"^[nN]ew.+$"' "$GO_QUERY" && grep -q 'qualified_type' "$GO_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for Go (Green package, Blue factory function calls, Base0 qualifiers)"
    else
        fail "Neovim Go query extension" "Missing or invalid after/queries/go/highlights.scm"
    fi

    JAVA_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/java/highlights.scm"
    if [ -f "$JAVA_QUERY" ] && grep -q '"import" @keyword\.import' "$JAVA_QUERY" && \
       grep -q '"record" @keyword\.type' "$JAVA_QUERY" && \
       grep -q 'record_pattern' "$JAVA_QUERY" && \
       grep -q '"when" @keyword\.conditional' "$JAVA_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for Java (Orange import, Green record/when, Yellow record patterns)"
    else
        fail "Neovim Java query extension" "Missing or invalid after/queries/java/highlights.scm"
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

local function find_pos(buf, line_pat, token, start_col)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, l in ipairs(lines) do
        if l:find(line_pat, 1, true) then
            local s = l:find(token, start_col or 1, true)
            if s then return i - 1, s - 1 end
        end
    end
    return -1, -1
end

local function match_capture(buf, row, col, expected)
    if row < 0 or col < 0 then return false end
    local caps = vim.treesitter.get_captures_at_pos(buf, row, col)
    if #caps == 0 then return false end
    if caps[#caps].capture == expected then return true end
    for _, c in ipairs(caps) do
        if c.capture == expected then return true end
    end
    return false
end

-- 1. Inspect C (sample.c)
local c_buf = 0
local r_wn, c_wn = find_pos(c_buf, "malloc(sizeof(WorkerNode))", "WorkerNode", 20)
local is_wn_type = match_capture(c_buf, r_wn, c_wn, "type")

local r_so, c_so = find_pos(c_buf, "malloc(sizeof(WorkerNode))", "sizeof")
local is_so_kw = match_capture(c_buf, r_so, c_so, "keyword.operator")

-- 2. Inspect C++ (sample.cpp)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.cpp")
vim.cmd([[redraw]])
local cpp_buf = vim.api.nvim_get_current_buf()

local hl_module = vim.api.nvim_get_hl(0, {name = "@module", link = false})
local module_fg = string.format("%06x", hl_module.fg or 0)

local hl_lsp_ns = vim.api.nvim_get_hl(0, {name = "@lsp.type.namespace", link = false})
local lsp_ns_fg = string.format("%06x", hl_lsp_ns.fg or 0)

local r_t, c_t = find_pos(cpp_buf, "template <Printable T>", "T>", 18)
local is_t_type = match_capture(cpp_buf, r_t, c_t, "type")

local r_core, c_core = find_pos(cpp_buf, "namespace core::telemetry", "core")
local is_core_mod = match_capture(cpp_buf, r_core, c_core, "module")

local r_telem, c_telem = find_pos(cpp_buf, "namespace core::telemetry", "telemetry")
local is_telem_mod = match_capture(cpp_buf, r_telem, c_telem, "module")

local r_init, c_init = find_pos(cpp_buf, "NodeState::Initializing", "Initializing")
local is_init_const = match_capture(cpp_buf, r_init, c_init, "constant")

local r_null, c_null = find_pos(cpp_buf, "return std::nullopt;", "nullopt")
local is_nullopt_const = match_capture(cpp_buf, r_null, c_null, "constant")

local r_std, c_std = find_pos(cpp_buf, "return std::nullopt;", "std")
local is_std_var = match_capture(cpp_buf, r_std, c_std, "variable")

local r_attr, c_attr = find_pos(cpp_buf, "[[nodiscard]]", "nodiscard")
local is_attr_orange = match_capture(cpp_buf, r_attr, c_attr, "attribute")

local hl_attr = vim.api.nvim_get_hl(0, {name = "@attribute", link = false})
local attr_fg = string.format("%06x", hl_attr.fg or 0)

-- 3. Inspect Java (sample.java)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.java")
vim.cmd("redraw")
local java_buf = vim.api.nvim_get_current_buf()
local java_ft = vim.bo.filetype
local ok_jdtls, _ = pcall(require, "jdtls")

local r_j_imp, c_j_imp = find_pos(java_buf, "import java.time.Instant;", "import")
local is_j_imp_kw = match_capture(java_buf, r_j_imp, c_j_imp, "keyword.import")

local r_j_rec, c_j_rec = find_pos(java_buf, "record OrderRecord(", "record")
local is_j_rec_kw = match_capture(java_buf, r_j_rec, c_j_rec, "keyword.type")

local r_j_ann, c_j_ann = find_pos(java_buf, "@Service", "@Service")
local is_j_ann = match_capture(java_buf, r_j_ann, c_j_ann, "attribute")

local r_j_pat, c_j_pat = find_pos(java_buf, "case OrderRecord(", "OrderRecord")
local is_j_pat_type = match_capture(java_buf, r_j_pat, c_j_pat, "type")

local r_j_when, c_j_when = find_pos(java_buf, "when amount >=", "when")
local is_j_when_kw = match_capture(java_buf, r_j_when, c_j_when, "keyword.conditional")

-- 4. Inspect Diff (sample.diff)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.diff")
vim.cmd("redraw")
local diff_buf = vim.api.nvim_get_current_buf()

local hl_plus = vim.api.nvim_get_hl(0, {name = "@diff.plus", link = false})
local diff_plus_fg = string.format("%06x", hl_plus.fg or 0)
local hl_minus = vim.api.nvim_get_hl(0, {name = "@diff.minus", link = false})
local diff_minus_fg = string.format("%06x", hl_minus.fg or 0)
local hl_line = vim.api.nvim_get_hl(0, {name = "@diff.line", link = false})
local diff_line_fg = string.format("%06x", hl_line.fg or 0)

local r_del, c_del = find_pos(diff_buf, "maxRetries", "-")
local is_del_minus = match_capture(diff_buf, r_del, c_del, "diff.minus")

local r_add, c_add = find_pos(diff_buf, "Maximum retry attempts", "+")
local is_add_plus = match_capture(diff_buf, r_add, c_add, "diff.plus")

local r_hunk, c_hunk = find_pos(diff_buf, "@@ -32,18 +32,22 @@", "@@")
local is_hunk_line = match_capture(diff_buf, r_hunk, c_hunk, "diff.line")

-- 5. Inspect Go (sample.go)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.go")
vim.cmd("redraw")
local go_buf = vim.api.nvim_get_current_buf()

local r_pkg, c_pkg = find_pos(go_buf, "package main", "package")
local is_pkg_kw = match_capture(go_buf, r_pkg, c_pkg, "keyword")
local hl_kw = vim.api.nvim_get_hl(0, {name = "@keyword", link = false})
local pkg_fg = string.format("%06x", hl_kw.fg or 0)

local r_imp, c_imp = find_pos(go_buf, "import (", "import")
local is_imp_kw = match_capture(go_buf, r_imp, c_imp, "keyword.import")
local hl_imp = vim.api.nvim_get_hl(0, {name = "@keyword.import", link = false})
local imp_fg = string.format("%06x", hl_imp.fg or 0)

local r_main, c_main = find_pos(go_buf, "package main", "main")
local is_main_mod = match_capture(go_buf, r_main, c_main, "module")

local r_ctx, c_ctx = find_pos(go_buf, "ctx context.Context", "context")
local is_ctx_var = match_capture(go_buf, r_ctx, c_ctx, "variable")

local r_ld, c_ld = find_pos(go_buf, "LevelDebug LogLevel = iota", "LevelDebug")
local is_ld_const = match_capture(go_buf, r_ld, c_ld, "constant")

local r_ncn, c_ncn = find_pos(go_buf, "node, err := NewClusterNode(cfg)", "NewClusterNode")
local is_ncn_call = match_capture(go_buf, r_ncn, c_ncn, "function.call")
local hl_fcall = vim.api.nvim_get_hl(0, {name = "@function.call", link = false})
local fcall_fg = string.format("%06x", hl_fcall.fg or 0)

local results = {
    param_italic = param_italic,
    const_fg = const_fg,
    is_wn_type = tostring(is_wn_type),
    is_so_kw = tostring(is_so_kw),
    is_t_type = tostring(is_t_type),
    java_ft = java_ft,
    ok_jdtls = tostring(ok_jdtls),
    is_j_imp_kw = tostring(is_j_imp_kw),
    is_j_rec_kw = tostring(is_j_rec_kw),
    is_j_ann = tostring(is_j_ann),
    is_j_pat_type = tostring(is_j_pat_type),
    is_j_when_kw = tostring(is_j_when_kw),
    module_fg = module_fg,
    lsp_ns_fg = lsp_ns_fg,
    is_core_mod = tostring(is_core_mod),
    is_init_const = tostring(is_init_const),
    is_nullopt_const = tostring(is_nullopt_const),
    is_telem_mod = tostring(is_telem_mod),
    is_std_var = tostring(is_std_var),
    attr_fg = attr_fg,
    is_attr_orange = tostring(is_attr_orange),
    diff_plus_fg = diff_plus_fg,
    is_add_plus = tostring(is_add_plus),
    diff_minus_fg = diff_minus_fg,
    is_del_minus = tostring(is_del_minus),
    diff_line_fg = diff_line_fg,
    is_hunk_line = tostring(is_hunk_line),
    is_pkg_kw = tostring(is_pkg_kw),
    pkg_fg = pkg_fg,
    is_imp_kw = tostring(is_imp_kw),
    imp_fg = imp_fg,
    is_main_mod = tostring(is_main_mod),
    is_ctx_var = tostring(is_ctx_var),
    is_ld_const = tostring(is_ld_const),
    is_ncn_call = tostring(is_ncn_call),
    fcall_fg = fcall_fg,
}
for k, v in pairs(results) do
    io.write(string.format("%s=%s\n", k, v))
end
' -c 'q' 2>/dev/null || true)"

        declare -A RES=()
        while IFS='=' read -r k v; do
            [ -n "$k" ] && RES["$k"]="$v"
        done <<< "$NVIM_RESULTS"

        if [ "${RES[param_italic]}" != "true" ]; then
            pass "Neovim renders parameters in upright font without italics"
        else
            fail "Neovim parameter italics" "Expected upright parameter highlight in Neovim, got italic=${RES[param_italic]}"
        fi

        if [ "${RES[const_fg]}" = "d33682" ]; then
            pass "Neovim renders @constant in Solarized Magenta (#d33682)"
        else
            fail "Neovim @constant highlight" "Expected fg=d33682 for @constant, got fg=${RES[const_fg]}"
        fi

        if [ "${RES[is_wn_type]}" = "true" ]; then
            pass "Neovim Tree-sitter captures sizeof(WorkerNode) as @type (Yellow)"
        else
            fail "Neovim sizeof(type) highlight" "Expected sizeof(WorkerNode) to be captured as @type, got ${RES[is_wn_type]}"
        fi

        if [ "${RES[is_so_kw]}" = "true" ]; then
            pass "Neovim Tree-sitter captures sizeof as @keyword.operator (Green)"
        else
            fail "Neovim sizeof highlight" "Expected sizeof to be captured as @keyword.operator, got ${RES[is_so_kw]}"
        fi

        if [ "${RES[is_t_type]}" = "true" ]; then
            pass "Neovim Tree-sitter captures template <Printable T> as @type (Yellow)"
        else
            fail "Neovim template type parameter highlight" "Expected template <Printable T> to be captured as @type, got ${RES[is_t_type]}"
        fi

        if [ "${RES[module_fg]}" = "6c71c4" ] && [ "${RES[lsp_ns_fg]}" = "6c71c4" ]; then
            pass "Neovim renders @module and @lsp.type.namespace in Solarized Violet (#6c71c4)"
        else
            fail "Neovim module/namespace highlight" "Expected fg=6c71c4, got module=${RES[module_fg]} lsp_ns=${RES[lsp_ns_fg]}"
        fi

        if [ "${RES[is_core_mod]}" = "true" ] && [ "${RES[is_telem_mod]}" = "true" ]; then
            pass "Neovim Tree-sitter captures namespace identifiers (core, telemetry) as @module (Violet)"
        else
            fail "Neovim namespace capture" "Expected @module for core and telemetry, got core=${RES[is_core_mod]} telem=${RES[is_telem_mod]}"
        fi

        if [ "${RES[is_std_var]}" = "true" ]; then
            pass "Neovim Tree-sitter captures C++ scope qualifiers (std::) as @variable (Base0 Grey)"
        else
            fail "Neovim C++ scope qualifier capture" "Expected @variable for std:: qualifier, got ${RES[is_std_var]}"
        fi

        if [ "${RES[is_init_const]}" = "true" ]; then
            pass "Neovim Tree-sitter captures scoped enum members (NodeState::Initializing) as @constant (Magenta)"
        else
            fail "Neovim scoped enum constant capture" "Expected @constant for NodeState::Initializing, got ${RES[is_init_const]}"
        fi

        if [ "${RES[is_nullopt_const]}" = "true" ]; then
            pass "Neovim Tree-sitter captures standard sentinels (std::nullopt) as @constant (Magenta)"
        else
            fail "Neovim sentinel capture" "Expected @constant for std::nullopt, got ${RES[is_nullopt_const]}"
        fi

        if [ "${RES[attr_fg]}" = "cb4b16" ] && [ "${RES[is_attr_orange]}" = "true" ]; then
            pass "Neovim renders C++ attributes ([[nodiscard]]) in Solarized Orange (#cb4b16)"
        else
            fail "Neovim attribute highlight" "Expected fg=cb4b16 and capture=attribute, got fg=${RES[attr_fg]} cap=${RES[is_attr_orange]}"
        fi

        if [ "${RES[java_ft]}" = "java" ] && [ "${RES[ok_jdtls]}" = "true" ]; then
            pass "Neovim detects Java filetype and loads nvim-jdtls cleanly"
        else
            fail "Neovim Java ftplugin verification" "Expected java filetype and jdtls loaded, got ft=${RES[java_ft]} ok=${RES[ok_jdtls]}"
        fi

        if [ "${RES[is_j_imp_kw]}" = "true" ]; then
            pass "Neovim renders Java import keyword as @keyword.import (Orange)"
        else
            fail "Neovim Java import keyword" "Expected @keyword.import for import, got ${RES[is_j_imp_kw]}"
        fi

        if [ "${RES[is_j_rec_kw]}" = "true" ] && [ "${RES[is_j_when_kw]}" = "true" ]; then
            pass "Neovim renders Java record declaration and pattern guard 'when' as keywords (Green)"
        else
            fail "Neovim Java record/when keywords" "Expected @keyword.type for record and @keyword.conditional for when, got rec=${RES[is_j_rec_kw]} when=${RES[is_j_when_kw]}"
        fi

        if [ "${RES[is_j_ann]}" = "true" ] && [ "${RES[is_j_pat_type]}" = "true" ]; then
            pass "Neovim renders Java annotations as @attribute (Orange) and record patterns as @type (Yellow)"
        else
            fail "Neovim Java annotation and record pattern highlights" "Expected @attribute for annotations and @type for record patterns, got ann=${RES[is_j_ann]} pat=${RES[is_j_pat_type]}"
        fi

        if [ "${RES[diff_plus_fg]}" = "859900" ] && [ "${RES[is_add_plus]}" = "true" ]; then
            pass "Neovim renders diff additions (+) in Solarized Green (#859900)"
        else
            fail "Neovim diff addition highlight" "Expected fg=859900 and capture=diff.plus, got fg=${RES[diff_plus_fg]} cap=${RES[is_add_plus]}"
        fi

        if [ "${RES[diff_minus_fg]}" = "dc322f" ] && [ "${RES[is_del_minus]}" = "true" ]; then
            pass "Neovim renders diff deletions (-) in Solarized Red (#dc322f)"
        else
            fail "Neovim diff deletion highlight" "Expected fg=dc322f and capture=diff.minus, got fg=${RES[diff_minus_fg]} cap=${RES[is_del_minus]}"
        fi

        if [ "${RES[diff_line_fg]}" = "268bd2" ] && [ "${RES[is_hunk_line]}" = "true" ]; then
            pass "Neovim renders diff hunk headers (@@ ... @@) in Solarized Blue (#268bd2)"
        else
            fail "Neovim diff hunk line highlight" "Expected fg=268bd2 and capture=diff.line, got fg=${RES[diff_line_fg]} cap=${RES[is_hunk_line]}"
        fi

        if [ "${RES[is_pkg_kw]}" = "true" ] && [ "${RES[pkg_fg]}" = "859900" ]; then
            pass "Neovim renders Go package keyword in Solarized Green (#859900)"
        else
            fail "Neovim Go package keyword" "Expected @keyword fg=859900, got cap=${RES[is_pkg_kw]} fg=${RES[pkg_fg]}"
        fi

        if [ "${RES[is_imp_kw]}" = "true" ] && [ "${RES[imp_fg]}" = "cb4b16" ]; then
            pass "Neovim renders Go import keyword in Solarized Orange (#cb4b16)"
        else
            fail "Neovim Go import keyword" "Expected @keyword.import fg=cb4b16, got cap=${RES[is_imp_kw]} fg=${RES[imp_fg]}"
        fi

        if [ "${RES[is_main_mod]}" = "true" ] && [ "${RES[is_ctx_var]}" = "true" ]; then
            pass "Neovim renders Go package declaration (main) as @module (Violet) and qualifiers (context.) as @variable (Base0 Grey)"
        else
            fail "Neovim Go module/qualifier captures" "Expected @module for main and @variable for context, got main=${RES[is_main_mod]} ctx=${RES[is_ctx_var]}"
        fi

        if [ "${RES[is_ld_const]}" = "true" ]; then
            pass "Neovim renders Go enum identifiers (LevelDebug) in Solarized Magenta (@constant)"
        else
            fail "Neovim Go constant capture" "Expected @constant for LevelDebug, got ${RES[is_ld_const]}"
        fi

        if [ "${RES[is_ncn_call]}" = "true" ] && [ "${RES[fcall_fg]}" = "268bd2" ]; then
            pass "Neovim renders Go factory function calls (NewClusterNode) as @function.call in Solarized Blue (#268bd2)"
        else
            fail "Neovim Go factory function call" "Expected @function.call fg=268bd2 for NewClusterNode, got cap=${RES[is_ncn_call]} fg=${RES[fcall_fg]}"
        fi
    fi
else
    fail "Neovim init.lua missing" "Expected dotfiles/.config/nvim/init.lua"
fi

test_summary

