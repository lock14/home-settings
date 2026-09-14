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
       grep -q '@markup.heading\.2.*colors\.blue' "$NVIM_CONFIG" && \
       grep -q '@markup.heading\.3.*colors\.violet' "$NVIM_CONFIG" && \
       grep -q '@markup.heading\.4.*colors\.base1' "$NVIM_CONFIG" && \
       grep -q '@markup.heading\.5.*colors\.base0' "$NVIM_CONFIG" && \
       grep -q '@markup.heading\.6.*colors\.base0' "$NVIM_CONFIG" && \
       grep -q '@markup\.quote.*colors\.base0' "$NVIM_CONFIG" && \
       grep -q '@type.*colors\.base0' "$NVIM_CONFIG" && \
       grep -q '@keyword\.type.*colors\.green' "$NVIM_CONFIG" && \
       grep -q '@keyword\.conditional\.ternary.*colors\.base0' "$NVIM_CONFIG" && \
       grep -q 'markdownH1.*colors\.orange' "$NVIM_CONFIG" && \
       grep -q 'markdownH2.*colors\.blue' "$NVIM_CONFIG" && \
       grep -q '\["@constant"\] = { fg = colors\.magenta }' "$NVIM_CONFIG" && \
       grep -q '@attribute' "$NVIM_CONFIG"; then
        pass "Neovim init.lua defines first-principles markup headings (H1 Orange, H2 Blue, H3 Violet, H4 Base1, H5/H6 Base0), Base0 quotes, calm base0 types, green declaration keywords, magenta constants, and calm operators matching bat"
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

    PYTHON_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/python/highlights.scm"
    if [ -f "$PYTHON_QUERY" ] && grep -q 'decorator' "$PYTHON_QUERY" && \
       grep -q '@function\.method' "$PYTHON_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for Python (Violet decorators, Blue def __init__ method)"
    else
        fail "Neovim Python query extension" "Missing or invalid after/queries/python/highlights.scm"
    fi

    RUST_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/rust/highlights.scm"
    if [ -f "$RUST_QUERY" ] && grep -q 'attribute' "$RUST_QUERY" && grep -q 'lifetime' "$RUST_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for Rust (Violet attributes, Green lifetimes)"
    else
        fail "Neovim Rust query extension" "Missing or invalid after/queries/rust/highlights.scm"
    fi

    BASH_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/bash/highlights.scm"
    if [ -f "$BASH_QUERY" ] && grep -q 'trap' "$BASH_QUERY" && grep -q 'simple_expansion' "$BASH_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for Bash (Magenta trap signals, Magenta positional parameters)"
    else
        fail "Neovim Bash query extension" "Missing or invalid after/queries/bash/highlights.scm"
    fi

    SQL_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/sql/highlights.scm"
    if [ -f "$SQL_QUERY" ] && grep -q 'keyword_null' "$SQL_QUERY" && grep -q 'object_reference' "$SQL_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for SQL (Magenta NULL, Base0 qualifiers, Base1 index relations)"
    else
        fail "Neovim SQL query extension" "Missing or invalid after/queries/sql/highlights.scm"
    fi

    TF_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/terraform/highlights.scm"
    if [ -f "$TF_QUERY" ] && grep -q 'template_interpolation_start' "$TF_QUERY" && grep -q 'variable_expr' "$TF_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for Terraform (Green scope keywords, Base0 delimiters & resource refs)"
    else
        fail "Neovim Terraform query extension" "Missing or invalid after/queries/terraform/highlights.scm"
    fi

    MD_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/markdown/highlights.scm"
    MD_INLINE_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/markdown_inline/highlights.scm"
    if [ -f "$MD_QUERY" ] && grep -q 'atx_h1_marker' "$MD_QUERY" && grep -q 'pipe_table_header' "$MD_QUERY" && \
       [ -f "$MD_INLINE_QUERY" ] && grep -q '!NOTE' "$MD_INLINE_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for Markdown & Inline Markdown (Base01 heading/quote delimiters, Base01 table borders, GitHub alerts)"
    else
        fail "Neovim Markdown query extension" "Missing or invalid after/queries/markdown/highlights.scm or after/queries/markdown_inline/highlights.scm"
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
local hl_const = vim.api.nvim_get_hl(0, {name = "@constant", link = false})

local results = {
    param_italic = tostring(hl_param.italic == true),
    const_fg = string.format("%06x", hl_const.fg or 0),
}

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

local r, c, hl

-- 1. Inspect C (sample.c)
local c_buf = 0
r, c = find_pos(c_buf, "malloc(sizeof(WorkerNode))", "WorkerNode", 20)
results["is_wn_type"] = tostring(match_capture(c_buf, r, c, "type"))

r, c = find_pos(c_buf, "malloc(sizeof(WorkerNode))", "sizeof")
results["is_so_kw"] = tostring(match_capture(c_buf, r, c, "keyword.operator"))

r, c = find_pos(c_buf, "switch (level) {", "switch")
results["is_c_switch_cond"] = tostring(match_capture(c_buf, r, c, "keyword.conditional"))

r, c = find_pos(c_buf, "WorkerNode *node = malloc(sizeof(WorkerNode));", "malloc")
results["is_c_malloc_call"] = tostring(match_capture(c_buf, r, c, "function.call"))

r, c = find_pos(c_buf, "#ifndef LOG_LEVEL", "LOG_LEVEL")
results["is_c_ifndef_macro"] = tostring(match_capture(c_buf, r, c, "constant.macro"))

hl = vim.api.nvim_get_hl(0, {name = "@constant.macro", link = false})
results["macro_c_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@type.c", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@type", link = false}) end
results["type_c_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@type.builtin.c", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@type.builtin", link = false}) end
results["type_builtin_c_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@keyword.conditional.c", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@keyword.conditional", link = false}) end
results["cond_c_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@function.call.c", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@function.call", link = false}) end
results["fcall_c_fg"] = string.format("%06x", hl.fg or 0)

-- 2. Inspect C++ (sample.cpp)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.cpp")
vim.cmd([[redraw]])
local cpp_buf = vim.api.nvim_get_current_buf()

hl = vim.api.nvim_get_hl(0, {name = "@module", link = false})
results["module_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@lsp.type.namespace", link = false})
results["lsp_ns_fg"] = string.format("%06x", hl.fg or 0)

r, c = find_pos(cpp_buf, "template <Printable T>", "T>", 18)
results["is_t_type"] = tostring(match_capture(cpp_buf, r, c, "type"))

r, c = find_pos(cpp_buf, "namespace core::telemetry", "namespace")
results["is_ns_kw"] = tostring(match_capture(cpp_buf, r, c, "keyword.type"))

r, c = find_pos(cpp_buf, "using namespace core::telemetry;", "using")
results["is_using_kw"] = tostring(match_capture(cpp_buf, r, c, "keyword"))

r, c = find_pos(cpp_buf, "namespace core::telemetry", "core")
results["is_core_mod"] = tostring(match_capture(cpp_buf, r, c, "module"))

r, c = find_pos(cpp_buf, "namespace core::telemetry", "telemetry")
results["is_telem_mod"] = tostring(match_capture(cpp_buf, r, c, "module"))

r, c = find_pos(cpp_buf, "NodeState::Initializing", "Initializing")
results["is_init_const"] = tostring(match_capture(cpp_buf, r, c, "constant"))

r, c = find_pos(cpp_buf, "return std::nullopt;", "nullopt")
results["is_nullopt_const"] = tostring(match_capture(cpp_buf, r, c, "constant"))

r, c = find_pos(cpp_buf, "return std::nullopt;", "std")
results["is_std_var"] = tostring(match_capture(cpp_buf, r, c, "variable"))

r, c = find_pos(cpp_buf, "[[nodiscard]]", "nodiscard")
results["is_attr_orange"] = tostring(match_capture(cpp_buf, r, c, "attribute"))

hl = vim.api.nvim_get_hl(0, {name = "@attribute.cpp", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@attribute", link = false}) end
results["attr_fg"] = string.format("%06x", hl.fg or 0)

r, c = find_pos(cpp_buf, "if (payload_history_.empty()) {", "if")
results["is_cpp_if_cond"] = tostring(match_capture(cpp_buf, r, c, "keyword.conditional"))

r, c = find_pos(cpp_buf, "std::for_each(", "for_each")
results["is_cpp_fe_call"] = tostring(match_capture(cpp_buf, r, c, "function.call"))

hl = vim.api.nvim_get_hl(0, {name = "@type.cpp", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@type", link = false}) end
results["type_cpp_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@type.builtin.cpp", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@type.builtin", link = false}) end
results["type_builtin_cpp_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@keyword.conditional.cpp", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@keyword.conditional", link = false}) end
results["cond_cpp_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@function.call.cpp", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@function.call", link = false}) end
results["fcall_cpp_fg"] = string.format("%06x", hl.fg or 0)

-- 3. Inspect Java (sample.java)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.java")
vim.cmd("redraw")
local java_buf = vim.api.nvim_get_current_buf()
results["java_ft"] = vim.bo.filetype
local ok_jdtls, _ = pcall(require, "jdtls")
results["ok_jdtls"] = tostring(ok_jdtls)

r, c = find_pos(java_buf, "import java.time.Instant;", "import")
results["is_j_imp_kw"] = tostring(match_capture(java_buf, r, c, "keyword.import"))

r, c = find_pos(java_buf, "record OrderRecord(", "record")
results["is_j_rec_kw"] = tostring(match_capture(java_buf, r, c, "keyword.type"))

r, c = find_pos(java_buf, "@Service", "@Service")
results["is_j_ann"] = tostring(match_capture(java_buf, r, c, "attribute"))

r, c = find_pos(java_buf, "case OrderRecord(", "OrderRecord")
results["is_j_pat_type"] = tostring(match_capture(java_buf, r, c, "type"))

r, c = find_pos(java_buf, "when amount >=", "when")
results["is_j_when_kw"] = tostring(match_capture(java_buf, r, c, "keyword.conditional"))

r, c = find_pos(java_buf, "this.timeoutMs", "this")
results["is_j_this_var"] = tostring(match_capture(java_buf, r, c, "variable.builtin"))
hl = vim.api.nvim_get_hl(0, {name = "@variable.builtin", link = false})
results["var_bi_fg"] = string.format("%06x", hl.fg or 0)

r, c = find_pos(java_buf, "super(timeoutMs);", "super")
results["is_j_super_call"] = tostring(match_capture(java_buf, r, c, "function.builtin"))

hl = vim.api.nvim_get_hl(0, {name = "@type.java", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@type", link = false}) end
results["type_java_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@type.builtin.java", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@type.builtin", link = false}) end
results["type_builtin_java_fg"] = string.format("%06x", hl.fg or 0)

-- 4. Inspect Diff (sample.diff)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.diff")
vim.cmd("redraw")
local diff_buf = vim.api.nvim_get_current_buf()

hl = vim.api.nvim_get_hl(0, {name = "@diff.plus", link = false})
results["diff_plus_fg"] = string.format("%06x", hl.fg or 0)
hl = vim.api.nvim_get_hl(0, {name = "@diff.minus", link = false})
results["diff_minus_fg"] = string.format("%06x", hl.fg or 0)
hl = vim.api.nvim_get_hl(0, {name = "@diff.line", link = false})
results["diff_line_fg"] = string.format("%06x", hl.fg or 0)

r, c = find_pos(diff_buf, "maxRetries", "-")
results["is_del_minus"] = tostring(match_capture(diff_buf, r, c, "diff.minus"))

r, c = find_pos(diff_buf, "Maximum retry attempts", "+")
results["is_add_plus"] = tostring(match_capture(diff_buf, r, c, "diff.plus"))

r, c = find_pos(diff_buf, "@@ -32,18 +32,22 @@", "@@")
results["is_hunk_line"] = tostring(match_capture(diff_buf, r, c, "diff.line"))

-- 5. Inspect Go (sample.go)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.go")
vim.cmd("redraw")
local go_buf = vim.api.nvim_get_current_buf()

r, c = find_pos(go_buf, "package main", "package")
results["is_pkg_kw"] = tostring(match_capture(go_buf, r, c, "keyword"))
hl = vim.api.nvim_get_hl(0, {name = "@keyword.go", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@keyword", link = false}) end
results["pkg_fg"] = string.format("%06x", hl.fg or 0)

r, c = find_pos(go_buf, "import (", "import")
results["is_imp_kw"] = tostring(match_capture(go_buf, r, c, "keyword.import"))
hl = vim.api.nvim_get_hl(0, {name = "@keyword.import.go", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@keyword.import", link = false}) end
results["imp_fg"] = string.format("%06x", hl.fg or 0)

r, c = find_pos(go_buf, "package main", "main")
results["is_main_mod"] = tostring(match_capture(go_buf, r, c, "module"))

r, c = find_pos(go_buf, "ctx context.Context", "context")
results["is_ctx_var"] = tostring(match_capture(go_buf, r, c, "variable"))

r, c = find_pos(go_buf, "LevelDebug LogLevel = iota", "LevelDebug")
results["is_ld_const"] = tostring(match_capture(go_buf, r, c, "constant"))

r, c = find_pos(go_buf, "node, err := NewClusterNode(cfg)", "NewClusterNode")
results["is_ncn_call"] = tostring(match_capture(go_buf, r, c, "function.call"))
hl = vim.api.nvim_get_hl(0, {name = "@function.call.go", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@function.call", link = false}) end
results["fcall_fg"] = string.format("%06x", hl.fg or 0)

r, c = find_pos(go_buf, "defer c.mu.RUnlock()", "defer")
results["is_defer_cond"] = tostring(match_capture(go_buf, r, c, "keyword.conditional"))
hl = vim.api.nvim_get_hl(0, {name = "@keyword.conditional.go", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@keyword.conditional", link = false}) end
results["cond_go_fg"] = string.format("%06x", hl.fg or 0)

r, c = find_pos(go_buf, "select {", "select")
results["is_select_cond"] = tostring(match_capture(go_buf, r, c, "keyword.conditional"))

r, c = find_pos(go_buf, "case <-ctx.Done():", "case")
results["is_case_cond"] = tostring(match_capture(go_buf, r, c, "keyword.conditional"))

r, c = find_pos(go_buf, "default:", "default")
results["is_default_cond"] = tostring(match_capture(go_buf, r, c, "keyword.conditional"))

r, c = find_pos(go_buf, "panic(err)", "panic")
results["is_panic_call"] = tostring(match_capture(go_buf, r, c, "function.call"))

r, c = find_pos(go_buf, "ctx context.Context", "Context")
results["is_t_ctx_type"] = tostring(match_capture(go_buf, r, c, "type"))
hl = vim.api.nvim_get_hl(0, {name = "@type.go", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@type", link = false}) end
results["type_go_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@type.builtin.go", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@type.builtin", link = false}) end
results["type_builtin_go_fg"] = string.format("%06x", hl.fg or 0)

-- 6. Inspect Python (sample.py)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.py")
vim.cmd("redraw")
local py_buf = vim.api.nvim_get_current_buf()

r, c = find_pos(py_buf, "from __future__ import annotations", "from")
results["is_py_from_kw"] = tostring(match_capture(py_buf, r, c, "keyword.import"))

r, c = find_pos(py_buf, "import asyncio", "asyncio")
results["is_py_async_mod"] = tostring(match_capture(py_buf, r, c, "module"))

r, c = find_pos(py_buf, "def timed_execution(func: Callable[..., Any])", "Callable")
results["is_py_call_type"] = tostring(match_capture(py_buf, r, c, "type"))

r, c = find_pos(py_buf, "DEFAULT_PORT: int = 8080", "int")
results["is_py_int_type"] = tostring(match_capture(py_buf, r, c, "type.builtin"))

r, c = find_pos(py_buf, "path: str", "str")
results["is_py_str_type"] = tostring(match_capture(py_buf, r, c, "type.builtin"))

r, c = find_pos(py_buf, "metadata: dict[str, str | int | bool]", "dict")
results["is_py_dict_type"] = tostring(match_capture(py_buf, r, c, "type.builtin"))

r, c = find_pos(py_buf, "self._buffer: list[EndpointMetrics] = []", "list")
results["is_py_list_type"] = tostring(match_capture(py_buf, r, c, "type.builtin"))

r, c = find_pos(py_buf, "@dataclass(frozen=True)", "@dataclass")
results["is_py_dc_attr"] = tostring(match_capture(py_buf, r, c + 1, "attribute"))

r, c = find_pos(py_buf, "@property", "@property")
results["is_py_prop_attr"] = tostring(match_capture(py_buf, r, c + 1, "attribute"))

r, c = find_pos(py_buf, "def summary(self) -> str:", "self")
results["is_py_self_var"] = tostring(match_capture(py_buf, r, c, "variable.builtin"))

r, c = find_pos(py_buf, "def __init__(self, service_name: str) -> None:", "__init__")
results["is_py_init_meth"] = tostring(match_capture(py_buf, r, c, "function.method"))

r, c = find_pos(py_buf, "EndpointMetrics(\"/health\",", "EndpointMetrics")
results["is_py_ep_ctor"] = tostring(match_capture(py_buf, r, c, "constructor"))

r, c = find_pos(py_buf, "if __name__ == \"__main__\":", "__name__")
results["is_py_name_const"] = tostring(match_capture(py_buf, r, c, "constant.builtin"))

r, c = find_pos(py_buf, "func.__name__", "__name__")
results["is_py_func_name_const"] = tostring(match_capture(py_buf, r, c, "constant.builtin"))

r, c = find_pos(py_buf, "elapsed:.4f", ".4f")
results["is_py_fspec_str"] = tostring(match_capture(py_buf, r, c, "string"))

-- 7. Inspect Rust (sample.rs)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.rs")
vim.cmd("redraw")
local rs_buf = vim.api.nvim_get_current_buf()

r, c = find_pos(rs_buf, "use std::collections::HashMap;", "use")
results["is_rs_use_kw"] = tostring(match_capture(rs_buf, r, c, "keyword.import"))

r, c = find_pos(rs_buf, "use std::collections::HashMap;", "std")
results["is_rs_std_mod"] = tostring(match_capture(rs_buf, r, c, "module"))

r, c = find_pos(rs_buf, "use std::collections::HashMap;", "HashMap")
results["is_rs_map_type"] = tostring(match_capture(rs_buf, r, c, "type"))

r, c = find_pos(rs_buf, "const MAX_CONNECTIONS: usize = 128;", "MAX_CONNECTIONS")
results["is_rs_max_const"] = tostring(match_capture(rs_buf, r, c, "constant"))

r, c = find_pos(rs_buf, "#[derive(Debug, Clone, Copy, PartialEq, Eq)]", "derive")
results["is_rs_drv_attr"] = tostring(match_capture(rs_buf, r, c, "attribute"))

r, c = find_pos(rs_buf, "#[derive(Debug, Clone, Copy, PartialEq, Eq)]", "#")
results["is_rs_hash_attr"] = tostring(match_capture(rs_buf, r, c, "attribute"))

r, c = find_pos(rs_buf, "#[inline]", "inline")
results["is_rs_inl_attr"] = tostring(match_capture(rs_buf, r, c, "attribute"))

r, c = find_pos(rs_buf, "    Starting,", "Starting")
results["is_rs_start_const"] = tostring(match_capture(rs_buf, r, c, "constant"))

r, c = find_pos(rs_buf, "    pub fn inspect_state(&self) ->", "self")
results["is_rs_self_var"] = tostring(match_capture(rs_buf, r, c, "variable.builtin"))

r, c = find_pos(rs_buf, "    println!(\"Max connections:", "println")
results["is_rs_print_macro"] = tostring(match_capture(rs_buf, r, c, "function.macro"))

r, c = find_pos(rs_buf, "find_by_id", string.char(39) .. "a")
results["is_rs_lt_mod"] = tostring(match_capture(rs_buf, r, c + 1, "keyword.modifier"))

-- 8. Inspect Shell (sample.sh)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.sh")
vim.cmd("redraw")
local sh_buf = vim.api.nvim_get_current_buf()

r, c = find_pos(sh_buf, "readonly SCRIPT_NAME", "readonly")
results["is_sh_ro_kw"] = tostring(match_capture(sh_buf, r, c, "keyword"))

r, c = find_pos(sh_buf, "readonly SCRIPT_NAME", "SCRIPT_NAME")
results["is_sh_sn_const"] = tostring(match_capture(sh_buf, r, c, "constant"))

r, c = find_pos(sh_buf, "SCRIPT_NAME=\"$(basename \"$0\")\"", "basename")
results["is_sh_base_func"] = tostring(match_capture(sh_buf, r, c, "function.call"))

r, c = find_pos(sh_buf, "SCRIPT_NAME=\"$(basename \"$0\")\"", "0")
results["is_sh_p0_const"] = tostring(match_capture(sh_buf, r, c, "constant.builtin"))

r, c = find_pos(sh_buf, "trap cleanup EXIT", "trap")
results["is_sh_trap_func"] = tostring(match_capture(sh_buf, r, c, "function.builtin"))

r, c = find_pos(sh_buf, "trap cleanup EXIT", "EXIT")
results["is_sh_exit_const"] = tostring(match_capture(sh_buf, r, c, "constant.builtin"))

r, c = find_pos(sh_buf, "cleanup() {", "cleanup")
results["is_sh_clean_func"] = tostring(match_capture(sh_buf, r, c, "function"))

r, c = find_pos(sh_buf, "local -r exit_code=$?", "exit_code")
results["is_sh_ec_var"] = tostring(match_capture(sh_buf, r, c, "variable"))

r, c = find_pos(sh_buf, "if [[ $exit_code", "if")
results["is_sh_if_cond"] = tostring(match_capture(sh_buf, r, c, "keyword.conditional"))

r, c = find_pos(sh_buf, "for svc in", "for")
results["is_sh_for_rep"] = tostring(match_capture(sh_buf, r, c, "keyword.repeat"))

r, c = find_pos(sh_buf, "case \"$level\" in", "case")
results["is_sh_case_cond"] = tostring(match_capture(sh_buf, r, c, "keyword.conditional"))

hl = vim.api.nvim_get_hl(0, {name = "@keyword.conditional.bash", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@keyword.conditional", link = false}) end
results["cond_sh_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@keyword.bash", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@keyword", link = false}) end
results["kw_sh_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@function.bash", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@function", link = false}) end
results["fn_sh_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@function.call.bash", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@function.call", link = false}) end
results["fcall_sh_fg"] = string.format("%06x", hl.fg or 0)

-- Note: Populate additional probe assertions directly on the results table
-- to avoid triggering the Lua 5.1 / LuaJIT 200 local variable chunk limit (E5107).
r_sh, c_sh = find_pos(py_buf, "try:", "try")
results["is_py_try_kw"] = tostring(match_capture(py_buf, r_sh, c_sh, "keyword.exception"))

r_sh, c_sh = find_pos(py_buf, "return await func(*args, **kwargs)", "await")
results["is_py_await_kw"] = tostring(match_capture(py_buf, r_sh, c_sh, "keyword.coroutine"))

r_sh, c_sh = find_pos(py_buf, "asyncio.sleep(0.02)", "sleep")
results["is_py_sleep_call"] = tostring(match_capture(py_buf, r_sh, c_sh, "function.method.call") or match_capture(py_buf, r_sh, c_sh, "function.call"))

hl_const = vim.api.nvim_get_hl(0, {name = "@type.python", link = false})
if not hl_const.fg then hl_const = vim.api.nvim_get_hl(0, {name = "@type", link = false}) end
results["type_py_fg"] = string.format("%06x", hl_const.fg or 0)

hl_const = vim.api.nvim_get_hl(0, {name = "@type.builtin.python", link = false})
if not hl_const.fg then hl_const = vim.api.nvim_get_hl(0, {name = "@type.builtin", link = false}) end
results["type_builtin_py_fg"] = string.format("%06x", hl_const.fg or 0)

hl_const = vim.api.nvim_get_hl(0, {name = "@attribute.python", link = false})
if not hl_const.fg then hl_const = vim.api.nvim_get_hl(0, {name = "@attribute", link = false}) end
results["attr_py_fg"] = string.format("%06x", hl_const.fg or 0)

hl_const = vim.api.nvim_get_hl(0, {name = "@keyword.import.python", link = false})
if not hl_const.fg then hl_const = vim.api.nvim_get_hl(0, {name = "@keyword.import", link = false}) end
results["imp_py_fg"] = string.format("%06x", hl_const.fg or 0)

hl_const = vim.api.nvim_get_hl(0, {name = "@keyword.conditional.python", link = false})
if not hl_const.fg then hl_const = vim.api.nvim_get_hl(0, {name = "@keyword.conditional", link = false}) end
results["cond_py_fg"] = string.format("%06x", hl_const.fg or 0)

hl_const = vim.api.nvim_get_hl(0, {name = "@function.call.python", link = false})
if not hl_const.fg then hl_const = vim.api.nvim_get_hl(0, {name = "@function.call", link = false}) end
results["fcall_py_fg"] = string.format("%06x", hl_const.fg or 0)

hl_const = vim.api.nvim_get_hl(0, {name = "@constructor.python", link = false})
if not hl_const.fg then hl_const = vim.api.nvim_get_hl(0, {name = "@constructor", link = false}) end
results["ctor_py_fg"] = string.format("%06x", hl_const.fg or 0)

r_sh, c_sh = find_pos(rs_buf, "match self.status {", "match")
results["is_rs_match_kw"] = tostring(match_capture(rs_buf, r_sh, c_sh, "keyword.conditional"))

r_sh, c_sh = find_pos(rs_buf, "ServerNode::new(101,", "new")
results["is_rs_new_call"] = tostring(match_capture(rs_buf, r_sh, c_sh, "function.call"))

hl_const = vim.api.nvim_get_hl(0, {name = "@type.rust", link = false})
if not hl_const.fg then hl_const = vim.api.nvim_get_hl(0, {name = "@type", link = false}) end
results["type_rs_fg"] = string.format("%06x", hl_const.fg or 0)

hl_const = vim.api.nvim_get_hl(0, {name = "@type.builtin.rust", link = false})
if not hl_const.fg then hl_const = vim.api.nvim_get_hl(0, {name = "@type.builtin", link = false}) end
results["type_builtin_rs_fg"] = string.format("%06x", hl_const.fg or 0)

hl_const = vim.api.nvim_get_hl(0, {name = "@attribute.rust", link = false})
if not hl_const.fg then hl_const = vim.api.nvim_get_hl(0, {name = "@attribute", link = false}) end
results["attr_rs_fg"] = string.format("%06x", hl_const.fg or 0)

hl_const = vim.api.nvim_get_hl(0, {name = "@keyword.import.rust", link = false})
if not hl_const.fg then hl_const = vim.api.nvim_get_hl(0, {name = "@keyword.import", link = false}) end
results["imp_rs_fg"] = string.format("%06x", hl_const.fg or 0)

hl_const = vim.api.nvim_get_hl(0, {name = "@keyword.conditional.rust", link = false})
if not hl_const.fg then hl_const = vim.api.nvim_get_hl(0, {name = "@keyword.conditional", link = false}) end
results["cond_rs_fg"] = string.format("%06x", hl_const.fg or 0)

hl_const = vim.api.nvim_get_hl(0, {name = "@function.call.rust", link = false})
if not hl_const.fg then hl_const = vim.api.nvim_get_hl(0, {name = "@function.call", link = false}) end
results["fcall_rs_fg"] = string.format("%06x", hl_const.fg or 0)

r_sh, c_sh = find_pos(sh_buf, ">&2", ">&2")
results["is_sh_gt_op"] = tostring(match_capture(sh_buf, r_sh, c_sh, "operator"))
results["is_sh_fd2_num"] = tostring(match_capture(sh_buf, r_sh, c_sh + 2, "number"))

r_sh, c_sh = find_pos(sh_buf, "INFO)", "INFO")
results["is_sh_info_param"] = tostring(match_capture(sh_buf, r_sh, c_sh, "variable.parameter"))

r_sh, c_sh = find_pos(sh_buf, "*)", "*")
results["is_sh_star_regex"] = tostring(match_capture(sh_buf, r_sh, c_sh, "string.regexp"))

r_sh, c_sh = find_pos(sh_buf, "${ACTIVE_SERVICES[@]}", "@")
results["is_sh_sub_at"] = tostring(match_capture(sh_buf, r_sh, c_sh, "character.special"))

r_sh, c_sh = find_pos(sh_buf, "main \"$@\"", "@")
results["is_sh_pos_at"] = tostring(match_capture(sh_buf, r_sh, c_sh, "constant"))

r_sh, c_sh = find_pos(sh_buf, "local -r exit_code=$?", "$")
results["is_sh_dollar_punc"] = tostring(match_capture(sh_buf, r_sh, c_sh, "punctuation.special"))
hl = vim.api.nvim_get_hl(0, {name = "@punctuation.special.bash", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@punctuation.special", link = false}) end
results["dollar_sh_fg"] = string.format("%06x", hl.fg or 0)

-- 9. Inspect SQL (sample.sql)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.sql")
vim.cmd("redraw")
local sql_buf = vim.api.nvim_get_current_buf()

r, c = find_pos(sql_buf, "CREATE TABLE IF NOT EXISTS customer_accounts", "CREATE")
results["is_sql_create_kw"] = tostring(match_capture(sql_buf, r, c, "keyword"))

r, c = find_pos(sql_buf, "CREATE TABLE IF NOT EXISTS customer_accounts", "customer_accounts")
results["is_sql_table_type"] = tostring(match_capture(sql_buf, r, c, "type"))

r, c = find_pos(sql_buf, "account_id BIGSERIAL PRIMARY KEY", "BIGSERIAL")
results["is_sql_serial_type"] = tostring(match_capture(sql_buf, r, c, "type.builtin"))

r, c = find_pos(sql_buf, "plan_tier VARCHAR", "DEFAULT")
results["is_sql_default_attr"] = tostring(match_capture(sql_buf, r, c, "attribute"))

r, c = find_pos(sql_buf, "is_active BOOLEAN NOT NULL DEFAULT TRUE", "NULL")
results["is_sql_null_const"] = tostring(match_capture(sql_buf, r, c, "constant.builtin"))

r, c = find_pos(sql_buf, "is_active BOOLEAN NOT NULL DEFAULT TRUE", "TRUE")
results["is_sql_true_bool"] = tostring(match_capture(sql_buf, r, c, "boolean"))

r, c = find_pos(sql_buf, "created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()", "NOW")
results["is_sql_now_func"] = tostring(match_capture(sql_buf, r, c, "function.call"))

r, c = find_pos(sql_buf, "transaction_id UUID PRIMARY KEY", "UUID")
results["is_sql_uuid_type"] = tostring(match_capture(sql_buf, r, c, "type.builtin"))

r, c = find_pos(sql_buf, "CREATE INDEX IF NOT EXISTS idx_ledger_account_settled", "idx_ledger_account_settled")
results["is_sql_index_type"] = tostring(match_capture(sql_buf, r, c, "type"))

r, c = find_pos(sql_buf, "WITH monthly_billing_summary AS (", "monthly_billing_summary")
results["is_sql_cte_type"] = tostring(match_capture(sql_buf, r, c, "type"))

r, c = find_pos(sql_buf, "        a.account_id,", "a")
results["is_sql_alias_var"] = tostring(match_capture(sql_buf, r, c, "variable"))

r, c = find_pos(sql_buf, "        a.account_id,", "account_id")
results["is_sql_col_member"] = tostring(match_capture(sql_buf, r, c, "variable.member"))

r, c = find_pos(sql_buf, "COUNT(t.transaction_id)", "COUNT")
results["is_sql_count_func"] = tostring(match_capture(sql_buf, r, c, "function.call"))

r, c = find_pos(sql_buf, "        CASE", "CASE")
results["is_sql_case_kw"] = tostring(match_capture(sql_buf, r, c, "keyword.conditional"))

r, c = find_pos(sql_buf, "THEN 0.15", "0.15")
results["is_sql_num_float"] = tostring(match_capture(sql_buf, r, c, "number.float"))

r, c = find_pos(sql_buf, "ROUND(s.aggregate_spend", "ROUND")
results["is_sql_round_func"] = tostring(match_capture(sql_buf, r, c, "function.call"))

r, c = find_pos(sql_buf, "DENSE_RANK()", "DENSE_RANK")
results["is_sql_rank_func"] = tostring(match_capture(sql_buf, r, c, "function.call"))

r, c = find_pos(sql_buf, "DENSE_RANK() OVER", "OVER")
results["is_sql_over_kw"] = tostring(match_capture(sql_buf, r, c, "keyword"))

r, c = find_pos(sql_buf, "aggregate_spend DESC) AS revenue_rank", "DESC")
results["is_sql_desc_attr"] = tostring(match_capture(sql_buf, r, c, "attribute"))

r, c = find_pos(sql_buf, "HAVING s.total_invoices > 0", "HAVING")
results["is_sql_having_kw"] = tostring(match_capture(sql_buf, r, c, "keyword"))

hl = vim.api.nvim_get_hl(0, {name = "@keyword.conditional.sql", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@keyword.conditional", link = false}) end
results["cond_sql_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@type.sql", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@type", link = false}) end
results["type_sql_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@type.builtin.sql", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@type.builtin", link = false}) end
results["type_builtin_sql_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@function.call.sql", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@function.call", link = false}) end
results["fcall_sql_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@attribute.sql", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@attribute", link = false}) end
results["attr_sql_fg"] = string.format("%06x", hl.fg or 0)

-- 10. Inspect Terraform (sample.tf)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.tf")
vim.cmd([[redraw]])
local tf_buf = vim.api.nvim_get_current_buf()

r, c = find_pos(tf_buf, "terraform {", "terraform")
results["is_tf_main_kw"] = tostring(match_capture(tf_buf, r, c, "keyword"))

r, c = find_pos(tf_buf, "required_providers {", "required_providers")
results["is_tf_prov_type"] = tostring(match_capture(tf_buf, r, c, "type"))

r, c = find_pos(tf_buf, "  type        = string", "string")
results["is_tf_str_type"] = tostring(match_capture(tf_buf, r, c, "type.builtin"))

r, c = find_pos(tf_buf, "contains([\"staging\"", "contains")
results["is_tf_cnt_func"] = tostring(match_capture(tf_buf, r, c, "function"))

r, c = find_pos(tf_buf, "var.environment)", "var")
results["is_tf_var_kw"] = tostring(match_capture(tf_buf, r, c, "keyword"))

r, c = find_pos(tf_buf, "local.vpc_cidr,", "local")
results["is_tf_loc_kw"] = tostring(match_capture(tf_buf, r, c, "keyword"))

r, c = find_pos(tf_buf, "resource \"aws_s3_bucket\"", "resource")
results["is_tf_res_kw"] = tostring(match_capture(tf_buf, r, c, "keyword"))

r, c = find_pos(tf_buf, "value       = aws_s3_bucket.telemetry_lake.arn", "aws_s3_bucket")
results["is_tf_ref_var"] = tostring(match_capture(tf_buf, r, c, "variable"))

r, c = find_pos(tf_buf, "prevent_destroy = false", "false")
results["is_tf_false_bool"] = tostring(match_capture(tf_buf, r, c, "boolean"))

r, c = find_pos(tf_buf, "\"subnet-${idx}\"", "${")
results["is_tf_interp_brack"] = tostring(match_capture(tf_buf, r, c, "punctuation.bracket"))

r, c = find_pos(tf_buf, "provider \"aws\"", "provider")
results["is_tf_prov_hdr_kw"] = tostring(match_capture(tf_buf, r, c, "keyword"))

r, c = find_pos(tf_buf, "provider      = aws", "provider")
results["is_tf_prov_arg_mbr"] = tostring(match_capture(tf_buf, r, c, "variable.member"))

r, c = find_pos(tf_buf, "provisioner \"local-exec\"", "provisioner")
results["is_tf_psnr_type"] = tostring(match_capture(tf_buf, r, c, "type"))

r, c = find_pos(tf_buf, "echo \"Provisioned bucket: ${self.id}\"", "self")
results["is_tf_self_kw"] = tostring(match_capture(tf_buf, r, c, "keyword"))

r, c = find_pos(tf_buf, "%{ if var.environment", "%{")
results["is_tf_dir_brack"] = tostring(match_capture(tf_buf, r, c, "punctuation.bracket"))

r, c = find_pos(tf_buf, "%{ if var.environment", "~}")
results["is_tf_strip_brack"] = tostring(match_capture(tf_buf, r, c, "punctuation.bracket"))

r, c = find_pos(tf_buf, "%{ if var.environment", "if")
results["is_tf_if_kw"] = tostring(match_capture(tf_buf, r, c, "keyword.conditional"))

hl = vim.api.nvim_get_hl(0, {name = "@keyword.terraform", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@keyword", link = false}) end
results["kw_tf_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@keyword.conditional.terraform", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@keyword.conditional", link = false}) end
results["cond_tf_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@type.builtin.terraform", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@type.builtin", link = false}) end
results["type_tf_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@function.call.terraform", link = false})
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@function.builtin.terraform", link = false}) end
if not hl.fg then hl = vim.api.nvim_get_hl(0, {name = "@function", link = false}) end
results["fn_tf_fg"] = string.format("%06x", hl.fg or 0)

-- 11. Inspect Markdown (sample.md)
vim.cmd("edit " .. vim.fn.expand("%:p:h") .. "/sample.md")
vim.cmd("redraw")
local md_buf = vim.api.nvim_get_current_buf()
vim.treesitter.start(md_buf, "markdown")
local md_hl = vim.treesitter.highlighter.active[md_buf]
if md_hl and md_hl.tree then
    md_hl.tree:parse(true)
end

r, c = find_pos(md_buf, "Workstation Architecture", "#")
results["is_md_h1_delim"] = tostring(match_capture(md_buf, r, c, "markup.heading.delimiter"))

r, c = find_pos(md_buf, "Workstation Architecture", "Workstation")
results["is_md_h1_txt"] = tostring(match_capture(md_buf, r, c, "markup.heading.1"))

r, c = find_pos(md_buf, "Executive Summary", "##")
results["is_md_h2_delim"] = tostring(match_capture(md_buf, r, c, "markup.heading.delimiter"))

r, c = find_pos(md_buf, "Executive Summary", "Executive")
results["is_md_h2_txt"] = tostring(match_capture(md_buf, r, c, "markup.heading.2"))

r, c = find_pos(md_buf, "File System Topology", "###")
results["is_md_h3_delim"] = tostring(match_capture(md_buf, r, c, "markup.heading.delimiter"))

r, c = find_pos(md_buf, "File System Topology", "File")
results["is_md_h3_txt"] = tostring(match_capture(md_buf, r, c, "markup.heading.3"))

r, c = find_pos(md_buf, "Syntax Highlighting", "####")
results["is_md_h4_delim"] = tostring(match_capture(md_buf, r, c, "markup.heading.delimiter"))

r, c = find_pos(md_buf, "Syntax Highlighting", "Syntax")
results["is_md_h4_txt"] = tostring(match_capture(md_buf, r, c, "markup.heading.4"))

r, c = find_pos(md_buf, "> [!NOTE]", ">")
results["is_md_quote_marker"] = tostring(match_capture(md_buf, r, c, "markup.quote.marker"))

r, c = find_pos(md_buf, "> [!NOTE]", "!NOTE")
results["is_md_alert_note"] = tostring(match_capture(md_buf, r, c, "markup.alert.note"))

r, c = find_pos(md_buf, "> [!TIP]", "!TIP")
results["is_md_alert_tip"] = tostring(match_capture(md_buf, r, c, "markup.alert.tip"))

r, c = find_pos(md_buf, "> [!WARNING]", "!WARNING")
results["is_md_alert_warning"] = tostring(match_capture(md_buf, r, c, "markup.alert.warning"))

r, c = find_pos(md_buf, "- [x]", "[x]")
results["is_md_task_checked"] = tostring(match_capture(md_buf, r, c, "markup.list.checked"))

r, c = find_pos(md_buf, "- [ ]", "[ ]")
results["is_md_task_unchecked"] = tostring(match_capture(md_buf, r, c, "markup.list.unchecked"))

r, c = find_pos(md_buf, "Environment Variable", "|")
results["is_md_table_delim"] = tostring(match_capture(md_buf, r, c, "markup.table.delimiter"))

r, c = find_pos(md_buf, "Environment Variable", "Environment")
results["is_md_table_hdr"] = tostring(match_capture(md_buf, r, c, "markup.heading.4"))

r, c = find_pos(md_buf, "git clone https", "git")
results["is_md_bash_cmd"] = tostring(match_capture(md_buf, r, c, "function.call"))

r, c = find_pos(md_buf, "if configPath ==", "if")
results["is_md_go_if_cond"] = tostring(match_capture(md_buf, r, c, "keyword.conditional"))

r, c = find_pos(md_buf, "if _, err := os.Stat", "_")
results["is_md_go_blank"] = tostring(match_capture(md_buf, r, c, "constant.builtin"))

r, c = find_pos(md_buf, "return errors.New", "New")
results["is_md_go_call"] = tostring(match_capture(md_buf, r, c, "function.method.call"))

r, c = find_pos(md_buf, "return nil", "nil")
results["is_md_go_nil"] = tostring(match_capture(md_buf, r, c, "constant.builtin"))

hl = vim.api.nvim_get_hl(0, {name = "@markup.heading.1", link = false})
results["h1_fg"] = string.format("%06x", hl.fg or 0)
results["h1_bold"] = tostring(hl.bold == true)

hl = vim.api.nvim_get_hl(0, {name = "@markup.heading.2", link = false})
results["h2_fg"] = string.format("%06x", hl.fg or 0)
results["h2_bold"] = tostring(hl.bold == true)

hl = vim.api.nvim_get_hl(0, {name = "@markup.heading.3", link = false})
results["h3_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@markup.heading.4", link = false})
results["h4_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@markup.heading.5", link = false})
results["h5_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@markup.heading.6", link = false})
results["h6_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@markup.heading.delimiter", link = false})
results["h_delim_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@markup.quote", link = false})
results["quote_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@markup.quote.marker", link = false})
results["quote_marker_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@markup.list.checked", link = false})
results["task_chk_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@markup.list.unchecked", link = false})
results["task_unchk_fg"] = string.format("%06x", hl.fg or 0)

hl = vim.api.nvim_get_hl(0, {name = "@markup.table.delimiter", link = false})
results["table_delim_fg"] = string.format("%06x", hl.fg or 0)

for k, v in pairs(results) do
    io.write(string.format("%s=%s\n", k, v))
end
' -c 'qall!' 2>/dev/null || true)"

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

        if [ "${RES[is_wn_type]}" = "true" ] && [ "${RES[type_c_fg]}" = "839496" ] && [ "${RES[type_builtin_c_fg]}" = "859900" ]; then
            pass "Neovim renders C custom types (WorkerNode) in calm Base0 (#839496) and primitives in Green (#859900)"
        else
            fail "Neovim sizeof(type) highlight" "Expected sizeof(WorkerNode) to be captured as @type fg=839496 and builtin fg=859900, got cap=${RES[is_wn_type]} fg=${RES[type_c_fg]} builtin=${RES[type_builtin_c_fg]}"
        fi

        if [ "${RES[is_so_kw]}" = "true" ]; then
            pass "Neovim Tree-sitter captures sizeof as @keyword.operator (Green)"
        else
            fail "Neovim sizeof highlight" "Expected sizeof to be captured as @keyword.operator, got ${RES[is_so_kw]}"
        fi

        if [ "${RES[is_c_switch_cond]}" = "true" ] && [ "${RES[cond_c_fg]}" = "b58900" ]; then
            pass "Neovim Tree-sitter captures C control flow (switch) as @keyword.conditional in Solarized Yellow (#b58900)"
        else
            fail "Neovim C control flow capture" "Expected switch as @keyword.conditional fg=b58900, got cap=${RES[is_c_switch_cond]} fg=${RES[cond_c_fg]}"
        fi

        if [ "${RES[is_c_malloc_call]}" = "true" ] && [ "${RES[fcall_c_fg]}" = "839496" ]; then
            pass "Neovim Tree-sitter captures C function calls (malloc) as @function.call in calm Base0 (#839496)"
        else
            fail "Neovim C function call capture" "Expected malloc as @function.call fg=839496, got cap=${RES[is_c_malloc_call]} fg=${RES[fcall_c_fg]}"
        fi

        if [ "${RES[is_c_ifndef_macro]}" = "true" ] && [ "${RES[macro_c_fg]}" = "cb4b16" ]; then
            pass "Neovim Tree-sitter captures C preprocessor conditionals (#ifndef LOG_LEVEL) as @constant.macro in Solarized Orange (#cb4b16)"
        else
            fail "Neovim C preprocessor conditional capture" "Expected LOG_LEVEL as @constant.macro fg=cb4b16, got cap=${RES[is_c_ifndef_macro]} fg=${RES[macro_c_fg]}"
        fi

        if [ "${RES[is_t_type]}" = "true" ] && [ "${RES[type_cpp_fg]}" = "839496" ] && [ "${RES[type_builtin_cpp_fg]}" = "859900" ]; then
            pass "Neovim renders C++ custom types (Printable T) in calm Base0 (#839496) and primitives in Green (#859900)"
        else
            fail "Neovim template type parameter highlight" "Expected template <Printable T> to be captured as @type fg=839496 and builtin fg=859900, got cap=${RES[is_t_type]} fg=${RES[type_cpp_fg]} builtin=${RES[type_builtin_cpp_fg]}"
        fi

        if [ "${RES[module_fg]}" = "6c71c4" ] && [ "${RES[lsp_ns_fg]}" = "6c71c4" ]; then
            pass "Neovim renders @module and @lsp.type.namespace in Solarized Violet (#6c71c4)"
        else
            fail "Neovim module/namespace highlight" "Expected fg=6c71c4, got module=${RES[module_fg]} lsp_ns=${RES[lsp_ns_fg]}"
        fi

        if [ "${RES[is_ns_kw]}" = "true" ] && [ "${RES[is_using_kw]}" = "true" ]; then
            pass "Neovim Tree-sitter captures namespace and using as declaration keywords in Solarized Green (#859900)"
        else
            fail "Neovim namespace/using capture" "Expected @keyword.type/@keyword (Green), got ns=${RES[is_ns_kw]} using=${RES[is_using_kw]}"
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

        if [ "${RES[attr_fg]}" = "6c71c4" ] && [ "${RES[is_attr_orange]}" = "true" ]; then
            pass "Neovim renders C++ attributes ([[nodiscard]]) in Solarized Violet (#6c71c4)"
        else
            fail "Neovim attribute highlight" "Expected fg=6c71c4 and capture=attribute, got fg=${RES[attr_fg]} cap=${RES[is_attr_orange]}"
        fi

        if [ "${RES[is_cpp_if_cond]}" = "true" ] && [ "${RES[cond_cpp_fg]}" = "b58900" ]; then
            pass "Neovim Tree-sitter captures C++ control flow (if) as @keyword.conditional in Solarized Yellow (#b58900)"
        else
            fail "Neovim C++ control flow capture" "Expected if as @keyword.conditional fg=b58900, got cap=${RES[is_cpp_if_cond]} fg=${RES[cond_cpp_fg]}"
        fi

        if [ "${RES[is_cpp_fe_call]}" = "true" ] && [ "${RES[fcall_cpp_fg]}" = "839496" ]; then
            pass "Neovim Tree-sitter captures C++ function calls (for_each) as @function.call in calm Base0 (#839496)"
        else
            fail "Neovim C++ function call capture" "Expected for_each as @function.call fg=839496, got cap=${RES[is_cpp_fe_call]} fg=${RES[fcall_cpp_fg]}"
        fi

        if [ "${RES[java_ft]}" = "java" ] && [ "${RES[ok_jdtls]}" = "true" ]; then
            pass "Neovim detects Java filetype and loads nvim-jdtls cleanly"
        else
            fail "Neovim Java ftplugin verification" "Expected java filetype and jdtls loaded, got ft=${RES[java_ft]} ok=${RES[ok_jdtls]}"
        fi

        if [ "${RES[is_j_imp_kw]}" = "true" ]; then
            pass "Neovim renders Java import keyword as @keyword.import (Violet)"
        else
            fail "Neovim Java import keyword" "Expected @keyword.import for import, got ${RES[is_j_imp_kw]}"
        fi

        if [ "${RES[is_j_rec_kw]}" = "true" ] && [ "${RES[is_j_when_kw]}" = "true" ]; then
            pass "Neovim renders Java record declaration and pattern guard 'when' as keywords (Green)"
        else
            fail "Neovim Java record/when keywords" "Expected @keyword.type for record and @keyword.conditional for when, got rec=${RES[is_j_rec_kw]} when=${RES[is_j_when_kw]}"
        fi

        if [ "${RES[is_j_ann]}" = "true" ] && [ "${RES[is_j_pat_type]}" = "true" ] && [ "${RES[type_builtin_java_fg]}" = "859900" ] && [ "${RES[type_java_fg]}" = "839496" ]; then
            pass "Neovim renders Java annotations as @attribute (Violet), record patterns as @type (Base0), and primitives as @type.builtin (Green #859900)"
        else
            fail "Neovim Java annotation and record pattern highlights" "Expected @attribute for annotations, @type fg=839496 for record patterns, and @type.builtin fg=859900, got ann=${RES[is_j_ann]} pat=${RES[is_j_pat_type]} type=${RES[type_java_fg]} bi=${RES[type_builtin_java_fg]}"
        fi

        if [ "${RES[is_j_this_var]}" = "true" ] && [ "${RES[var_bi_fg]}" = "d33682" ]; then
            pass "Neovim renders Java 'this' keyword as @variable.builtin in Solarized Magenta (#d33682)"
        else
            fail "Neovim Java this keyword" "Expected @variable.builtin fg=d33682, got cap=${RES[is_j_this_var]} fg=${RES[var_bi_fg]}"
        fi

        if [ "${RES[is_j_super_call]}" = "true" ]; then
            pass "Neovim renders Java constructor delegation 'super(...)' as @function.builtin in Solarized Blue (#268bd2)"
        else
            fail "Neovim Java super delegation" "Expected @function.builtin for super(...), got ${RES[is_j_super_call]}"
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

        if [ "${RES[is_imp_kw]}" = "true" ] && [ "${RES[imp_fg]}" = "6c71c4" ]; then
            pass "Neovim renders Go import keyword in Solarized Violet (#6c71c4)"
        else
            fail "Neovim Go import keyword" "Expected @keyword.import fg=6c71c4, got cap=${RES[is_imp_kw]} fg=${RES[imp_fg]}"
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

        if [ "${RES[is_ncn_call]}" = "true" ] && [ "${RES[fcall_fg]}" = "839496" ]; then
            pass "Neovim renders Go function calls (NewClusterNode) as @function.call in calm Solarized Base0 (#839496)"
        else
            fail "Neovim Go function call" "Expected @function.call fg=839496 for NewClusterNode, got cap=${RES[is_ncn_call]} fg=${RES[fcall_fg]}"
        fi

        if [ "${RES[is_t_ctx_type]}" = "true" ] && [ "${RES[type_go_fg]}" = "839496" ] && [ "${RES[type_builtin_go_fg]}" = "859900" ]; then
            pass "Neovim renders Go types (Context) as @type in calm Base0 (#839496) and primitives in Green (#859900)"
        else
            fail "Neovim Go type capture" "Expected @type fg=839496 for Context and builtin fg=859900, got cap=${RES[is_t_ctx_type]} fg=${RES[type_go_fg]} bi=${RES[type_builtin_go_fg]}"
        fi

        if [ "${RES[is_defer_cond]}" = "true" ] && \
           [ "${RES[is_select_cond]}" = "true" ] && \
           [ "${RES[is_case_cond]}" = "true" ] && \
           [ "${RES[is_default_cond]}" = "true" ] && \
           [ "${RES[cond_go_fg]}" = "b58900" ]; then
            pass "Neovim renders Go control flow (defer, select, case, default) as @keyword.conditional in Solarized Yellow (#b58900)"
        else
            fail "Neovim Go control flow capture" "Expected @keyword.conditional fg=b58900 for defer, select, case, default; got defer=${RES[is_defer_cond]} select=${RES[is_select_cond]} case=${RES[is_case_cond]} default=${RES[is_default_cond]} fg=${RES[cond_go_fg]}"
        fi

        if [ "${RES[is_panic_call]}" = "true" ]; then
            pass "Neovim renders Go built-in calls (panic) as @function.call in calm Solarized Base0 (#839496)"
        else
            fail "Neovim Go builtin call capture" "Expected @function.call for panic, got ${RES[is_panic_call]}"
        fi

        if [ "${RES[is_py_from_kw]}" = "true" ] && [ "${RES[imp_py_fg]}" = "6c71c4" ] && [ "${RES[is_py_async_mod]}" = "true" ]; then
            pass "Neovim renders Python import keyword in Violet (@keyword.import #6c71c4) and module in Violet (@module)"
        else
            fail "Neovim Python import/module capture" "Expected @keyword.import fg=6c71c4 for from and @module for asyncio, got from=${RES[is_py_from_kw]} fg=${RES[imp_py_fg]} mod=${RES[is_py_async_mod]}"
        fi

        if [ "${RES[is_py_call_type]}" = "true" ] && [ "${RES[type_py_fg]}" = "839496" ] && \
           [ "${RES[is_py_int_type]}" = "true" ] && [ "${RES[is_py_str_type]}" = "true" ] && \
           [ "${RES[is_py_dict_type]}" = "true" ] && [ "${RES[is_py_list_type]}" = "true" ] && \
           [ "${RES[type_builtin_py_fg]}" = "859900" ]; then
            pass "Neovim renders Python typing constructs (Callable) as @type in calm Base0 (#839496) and built-in types (int, str, dict, list) as @type.builtin in Solarized Green (#859900)"
        else
            fail "Neovim Python type capture" "Expected @type fg=839496 for Callable and builtin fg=859900 for int/str/dict/list, got call=${RES[is_py_call_type]} int=${RES[is_py_int_type]} str=${RES[is_py_str_type]} dict=${RES[is_py_dict_type]} list=${RES[is_py_list_type]} fg=${RES[type_py_fg]} bi=${RES[type_builtin_py_fg]}"
        fi

        if [ "${RES[is_py_dc_attr]}" = "true" ] && [ "${RES[is_py_prop_attr]}" = "true" ] && [ "${RES[attr_py_fg]}" = "6c71c4" ]; then
            pass "Neovim renders Python decorators (@dataclass, @property) unified as @attribute in Solarized Violet (#6c71c4)"
        else
            fail "Neovim Python decorator capture" "Expected @attribute fg=6c71c4 for @dataclass and @property, got dc=${RES[is_py_dc_attr]} prop=${RES[is_py_prop_attr]} fg=${RES[attr_py_fg]}"
        fi

        if [ "${RES[is_py_self_var]}" = "true" ] && [ "${RES[is_py_name_const]}" = "true" ] && [ "${RES[is_py_func_name_const]}" = "true" ]; then
            pass "Neovim renders Python self as @variable.builtin and __name__ (both standalone and attribute func.__name__) as @constant.builtin in Solarized Magenta (#d33682)"
        else
            fail "Neovim Python built-in captures" "Expected @variable.builtin for self and @constant.builtin for __name__, got self=${RES[is_py_self_var]} name=${RES[is_py_name_const]} func_name=${RES[is_py_func_name_const]}"
        fi

        if [ "${RES[is_py_init_meth]}" = "true" ] && [ "${RES[is_py_ep_ctor]}" = "true" ] && [ "${RES[ctor_py_fg]}" = "839496" ]; then
            pass "Neovim renders Python def __init__ as @function.method (Blue) and class instantiations as @constructor in calm Base0 (#839496)"
        else
            fail "Neovim Python method/constructor captures" "Expected @function.method for __init__ and @constructor fg=839496 for EndpointMetrics, got init=${RES[is_py_init_meth]} ep=${RES[is_py_ep_ctor]} fg=${RES[ctor_py_fg]}"
        fi

        if [ "${RES[is_py_try_kw]}" = "true" ] && [ "${RES[is_py_await_kw]}" = "true" ] && [ "${RES[cond_py_fg]}" = "b58900" ]; then
            pass "Neovim renders Python control flow (try, await) as @keyword.conditional/@keyword.coroutine in Solarized Yellow (#b58900)"
        else
            fail "Neovim Python control flow captures" "Expected try and await in Yellow #b58900, got try=${RES[is_py_try_kw]} await=${RES[is_py_await_kw]} fg=${RES[cond_py_fg]}"
        fi

        if [ "${RES[is_py_sleep_call]}" = "true" ] && [ "${RES[fcall_py_fg]}" = "839496" ]; then
            pass "Neovim renders Python function/method calls (sleep) as @function.call in calm Base0 (#839496)"
        else
            fail "Neovim Python function call" "Expected @function.call fg=839496 for sleep, got ${RES[is_py_sleep_call]} fg=${RES[fcall_py_fg]}"
        fi

        if [ "${RES[is_py_fspec_str]}" = "true" ]; then
            pass "Neovim renders Python f-string format specifier (.4f) in Solarized Cyan (#2aa198)"
        else
            fail "Neovim Python format specifier" "Expected string capture in Cyan for .4f, got ${RES[is_py_fspec_str]}"
        fi

        if [ "${RES[is_rs_use_kw]}" = "true" ] && [ "${RES[imp_rs_fg]}" = "6c71c4" ] && [ "${RES[is_rs_std_mod]}" = "true" ]; then
            pass "Neovim renders Rust use keyword as @keyword.import (Violet #6c71c4) and module path std as @module (Violet)"
        else
            fail "Neovim Rust import/module capture" "Expected @keyword.import fg=6c71c4 for use and @module for std, got use=${RES[is_rs_use_kw]} fg=${RES[imp_rs_fg]} std=${RES[is_rs_std_mod]}"
        fi

        if [ "${RES[is_rs_map_type]}" = "true" ] && [ "${RES[type_rs_fg]}" = "839496" ] && [ "${RES[type_builtin_rs_fg]}" = "859900" ]; then
            pass "Neovim renders Rust types (HashMap) as @type in calm Base0 (#839496) and primitives in Green (#859900)"
        else
            fail "Neovim Rust type capture" "Expected @type fg=839496 for HashMap and builtin fg=859900, got ${RES[is_rs_map_type]} fg=${RES[type_rs_fg]} bi=${RES[type_builtin_rs_fg]}"
        fi

        if [ "${RES[is_rs_drv_attr]}" = "true" ] && [ "${RES[is_rs_inl_attr]}" = "true" ] && [ "${RES[is_rs_hash_attr]}" = "true" ] && [ "${RES[attr_rs_fg]}" = "6c71c4" ]; then
            pass "Neovim renders Rust attributes (#[derive, #[inline) unified as @attribute in Solarized Violet (#6c71c4)"
        else
            fail "Neovim Rust attribute capture" "Expected @attribute fg=6c71c4 for #[derive and #[inline, got drv=${RES[is_rs_drv_attr]} inl=${RES[is_rs_inl_attr]} hash=${RES[is_rs_hash_attr]} fg=${RES[attr_rs_fg]}"
        fi

        if [ "${RES[is_rs_max_const]}" = "true" ] && [ "${RES[is_rs_start_const]}" = "true" ] && [ "${RES[is_rs_self_var]}" = "true" ]; then
            pass "Neovim renders Rust constants (MAX_CONNECTIONS, Starting) and self receiver in Solarized Magenta (#d33682)"
        else
            fail "Neovim Rust constant/receiver captures" "Expected @constant and @variable.builtin, got max=${RES[is_rs_max_const]} start=${RES[is_rs_start_const]} self=${RES[is_rs_self_var]}"
        fi

        if [ "${RES[is_rs_print_macro]}" = "true" ]; then
            pass "Neovim renders Rust macros (println) as @function.macro in Solarized Blue (#268bd2)"
        else
            fail "Neovim Rust macro capture" "Expected @function.macro for println, got ${RES[is_rs_print_macro]}"
        fi

        if [ "${RES[is_rs_lt_mod]}" = "true" ]; then
            pass "Neovim renders Rust lifetimes ('a, 'static, '_) unified as @keyword.modifier in Solarized Green (#859900)"
        else
            fail "Neovim Rust lifetime capture" "Expected @keyword.modifier for 'a, got ${RES[is_rs_lt_mod]}"
        fi

        if [ "${RES[is_rs_match_kw]}" = "true" ] && [ "${RES[cond_rs_fg]}" = "b58900" ]; then
            pass "Neovim renders Rust control flow (match) as @keyword.conditional in Solarized Yellow (#b58900)"
        else
            fail "Neovim Rust control flow capture" "Expected @keyword.conditional fg=b58900 for match, got ${RES[is_rs_match_kw]} fg=${RES[cond_rs_fg]}"
        fi

        if [ "${RES[is_rs_new_call]}" = "true" ] && [ "${RES[fcall_rs_fg]}" = "839496" ]; then
            pass "Neovim renders Rust function/method calls (ServerNode::new) as @function.call in calm Base0 (#839496)"
        else
            fail "Neovim Rust function call capture" "Expected @function.call fg=839496 for new, got ${RES[is_rs_new_call]} fg=${RES[fcall_rs_fg]}"
        fi

        if [ "${RES[is_sh_ro_kw]}" = "true" ] && [ "${RES[kw_sh_fg]}" = "859900" ]; then
            pass "Neovim renders Shell declarations (readonly, local) as @keyword in Solarized Green (#859900)"
        else
            fail "Neovim Shell keyword capture" "Expected @keyword fg=859900 for readonly, got cap=${RES[is_sh_ro_kw]} fg=${RES[kw_sh_fg]}"
        fi

        if [ "${RES[is_sh_if_cond]}" = "true" ] && [ "${RES[is_sh_case_cond]}" = "true" ] && [ "${RES[cond_sh_fg]}" = "b58900" ]; then
            pass "Neovim renders Shell control flow (if, case, for) as @keyword.conditional in Solarized Yellow (#b58900)"
        else
            fail "Neovim Shell control flow capture" "Expected if and case as @keyword.conditional fg=b58900, got if=${RES[is_sh_if_cond]} case=${RES[is_sh_case_cond]} fg=${RES[cond_sh_fg]}"
        fi

        if [ "${RES[is_sh_clean_func]}" = "true" ] && [ "${RES[fn_sh_fg]}" = "268bd2" ]; then
            pass "Neovim renders Shell function declarations (cleanup) as @function in Solarized Blue (#268bd2)"
        else
            fail "Neovim Shell function declaration capture" "Expected @function fg=268bd2 for cleanup, got cap=${RES[is_sh_clean_func]} fg=${RES[fn_sh_fg]}"
        fi

        if [ "${RES[is_sh_base_func]}" = "true" ] && [ "${RES[fcall_sh_fg]}" = "839496" ]; then
            pass "Neovim renders Shell command and function invocations (basename, trap) as @function.call in calm Base0 (#839496)"
        else
            fail "Neovim Shell function call capture" "Expected @function.call fg=839496 for basename, got cap=${RES[is_sh_base_func]} fg=${RES[fcall_sh_fg]}"
        fi

        if [ "${RES[is_sh_exit_const]}" = "true" ]; then
            pass "Neovim renders Shell trap signals (EXIT) as @constant.builtin in Solarized Magenta (#d33682)"
        else
            fail "Neovim Shell signal capture" "Expected @constant.builtin for EXIT in trap, got ${RES[is_sh_exit_const]}"
        fi

        if [ "${RES[is_sh_gt_op]}" = "true" ] && [ "${RES[is_sh_fd2_num]}" = "true" ]; then
            pass "Neovim renders Shell redirection (>&2) with operator in Base0 and file descriptor in Solarized Magenta (#d33682)"
        else
            fail "Neovim Shell redirection captures" "Expected @operator for >& and @number for 2, got gt=${RES[is_sh_gt_op]} fd2=${RES[is_sh_fd2_num]}"
        fi

        if [ "${RES[is_sh_info_param]}" = "true" ] && [ "${RES[is_sh_star_regex]}" = "true" ]; then
            pass "Neovim renders Shell case branch labels (INFO) in Base0 Grey (#839496) and wildcards (*) in Solarized Magenta (#d33682)"
        else
            fail "Neovim Shell case pattern captures" "Expected @variable.parameter for INFO and @string.regexp for *, got info=${RES[is_sh_info_param]} star=${RES[is_sh_star_regex]}"
        fi

        if [ "${RES[is_sh_sub_at]}" = "true" ] && [ "${RES[is_sh_pos_at]}" = "true" ]; then
            pass "Neovim renders Shell array subscript @ in Cyan (@character.special) and positional \$@ in Magenta (@constant)"
        else
            fail "Neovim Shell @ parameter captures" "Expected @character.special for [@] and @constant for \$@, got sub=${RES[is_sh_sub_at]} pos=${RES[is_sh_pos_at]}"
        fi

        if [ "${RES[is_sh_dollar_punc]}" = "true" ] && [ "${RES[dollar_sh_fg]}" = "839496" ]; then
            pass "Neovim renders Shell variable expansion prefix ($) as @punctuation.special in calm Base0 Grey (#839496)"
        else
            fail "Neovim Shell dollar prefix capture" "Expected @punctuation.special fg=839496 for $, got cap=${RES[is_sh_dollar_punc]} fg=${RES[dollar_sh_fg]}"
        fi

        if [ "${RES[is_sql_create_kw]}" = "true" ] && \
           [ "${RES[is_sql_table_type]}" = "true" ] && \
           [ "${RES[is_sql_serial_type]}" = "true" ] && \
           [ "${RES[is_sql_default_attr]}" = "true" ] && \
           [ "${RES[is_sql_null_const]}" = "true" ] && \
           [ "${RES[is_sql_true_bool]}" = "true" ] && \
           [ "${RES[is_sql_now_func]}" = "true" ] && \
           [ "${RES[is_sql_uuid_type]}" = "true" ] && \
           [ "${RES[is_sql_index_type]}" = "true" ] && \
           [ "${RES[is_sql_cte_type]}" = "true" ] && \
           [ "${RES[is_sql_alias_var]}" = "true" ] && \
           [ "${RES[is_sql_col_member]}" = "true" ] && \
           [ "${RES[is_sql_count_func]}" = "true" ] && \
           [ "${RES[is_sql_case_kw]}" = "true" ] && \
           [ "${RES[is_sql_num_float]}" = "true" ] && \
           [ "${RES[is_sql_round_func]}" = "true" ] && \
           [ "${RES[is_sql_rank_func]}" = "true" ] && \
           [ "${RES[is_sql_over_kw]}" = "true" ] && \
           [ "${RES[is_sql_desc_attr]}" = "true" ] && \
           [ "${RES[is_sql_having_kw]}" = "true" ] && \
           [ "${RES[cond_sql_fg]}" = "b58900" ] && \
           [ "${RES[type_sql_fg]}" = "839496" ] && \
           [ "${RES[type_builtin_sql_fg]}" = "859900" ] && \
           [ "${RES[fcall_sql_fg]}" = "839496" ] && \
           [ "${RES[attr_sql_fg]}" = "859900" ]; then
            pass "Neovim highlights modern SQL queries (sample.sql) with Converged Ergonomic Solarized Scheme: DDL keywords (Green), table/index/CTE relations in Base0, data types in Green (#859900), conditionals (Yellow), function calls (Base0), DEFAULT/DESC keywords (Green), NULL sentinels / TRUE / numbers (Magenta), and calm Base0 alias/column qualifiers"
        else
            fail "Neovim SQL Tree-sitter highlights" "Expected complete Tree-sitter capture matches in sample.sql (cond=${RES[cond_sql_fg]} type=${RES[type_sql_fg]} builtin=${RES[type_builtin_sql_fg]} fcall=${RES[fcall_sql_fg]} attr=${RES[attr_sql_fg]})"
        fi

        if [ "${RES[is_tf_main_kw]}" = "true" ] && \
           [ "${RES[is_tf_prov_type]}" = "true" ] && \
           [ "${RES[is_tf_str_type]}" = "true" ] && \
           [ "${RES[is_tf_cnt_func]}" = "true" ] && \
           [ "${RES[is_tf_var_kw]}" = "true" ] && \
           [ "${RES[is_tf_loc_kw]}" = "true" ] && \
           [ "${RES[is_tf_res_kw]}" = "true" ] && \
           [ "${RES[is_tf_ref_var]}" = "true" ] && \
           [ "${RES[is_tf_false_bool]}" = "true" ] && \
           [ "${RES[is_tf_interp_brack]}" = "true" ] && \
           [ "${RES[is_tf_prov_hdr_kw]}" = "true" ] && \
           [ "${RES[is_tf_prov_arg_mbr]}" = "true" ] && \
           [ "${RES[is_tf_psnr_type]}" = "true" ] && \
           [ "${RES[is_tf_self_kw]}" = "true" ] && \
           [ "${RES[is_tf_dir_brack]}" = "true" ] && \
           [ "${RES[is_tf_strip_brack]}" = "true" ] && \
           [ "${RES[is_tf_if_kw]}" = "true" ] && \
           [ "${RES[kw_tf_fg]}" = "859900" ] && \
           [ "${RES[cond_tf_fg]}" = "b58900" ] && \
           [ "${RES[type_tf_fg]}" = "839496" ] && \
           [ "${RES[fn_tf_fg]}" = "839496" ]; then
            pass "Neovim highlights modern Terraform / HCL configurations (sample.tf) with Converged Ergonomic Solarized Scheme: block declarations and scope keywords (Green), schema blocks and data types in Base0, control flow (Yellow), built-in functions (Base0), booleans/numbers (Magenta), Base0 string interpolation delimiters and resource references"
        else
            fail "Neovim Terraform Tree-sitter highlights" "Expected complete Tree-sitter capture matches in sample.tf (kw=${RES[kw_tf_fg]} cond=${RES[cond_tf_fg]} type=${RES[type_tf_fg]} fn=${RES[fn_tf_fg]})"
        fi

        if [ "${RES[is_md_h1_txt]}" = "true" ] && [ "${RES[h1_fg]}" = "cb4b16" ] && [ "${RES[h1_bold]}" != "true" ] && \
           [ "${RES[is_md_h2_txt]}" = "true" ] && [ "${RES[h2_fg]}" = "268bd2" ] && [ "${RES[h2_bold]}" != "true" ] && \
           [ "${RES[is_md_h3_txt]}" = "true" ] && [ "${RES[h3_fg]}" = "6c71c4" ] && \
           [ "${RES[is_md_h4_txt]}" = "true" ] && [ "${RES[h4_fg]}" = "93a1a1" ] && \
           [ "${RES[h5_fg]}" = "839496" ] && [ "${RES[h6_fg]}" = "839496" ] && \
           [ "${RES[is_md_h1_delim]}" = "true" ] && [ "${RES[h_delim_fg]}" = "586e75" ] && \
           [ "${RES[is_md_quote_marker]}" = "true" ] && [ "${RES[quote_marker_fg]}" = "586e75" ] && \
           [ "${RES[quote_fg]}" = "839496" ] && \
           [ "${RES[is_md_alert_note]}" = "true" ] && \
           [ "${RES[is_md_alert_tip]}" = "true" ] && \
           [ "${RES[is_md_alert_warning]}" = "true" ] && \
           [ "${RES[is_md_task_checked]}" = "true" ] && [ "${RES[task_chk_fg]}" = "859900" ] && \
           [ "${RES[is_md_task_unchecked]}" = "true" ] && [ "${RES[task_unchk_fg]}" = "586e75" ] && \
           [ "${RES[is_md_table_delim]}" = "true" ] && [ "${RES[table_delim_fg]}" = "586e75" ] && \
           [ "${RES[is_md_table_hdr]}" = "true" ] && \
           [ "${RES[is_md_bash_cmd]}" = "true" ] && \
           [ "${RES[is_md_go_if_cond]}" = "true" ] && \
           [ "${RES[is_md_go_blank]}" = "true" ] && \
           [ "${RES[is_md_go_call]}" = "true" ] && \
           [ "${RES[is_md_go_nil]}" = "true" ]; then
            pass "Neovim highlights modern Markdown documents (sample.md) with Semantic Architecture: H1 Orange (#cb4b16), H2 Blue (#268bd2, unbolded), H3 Violet (#6c71c4), H4 Base1 (#93a1a1), H5/H6 Base0 (#839496), Base01 heading/quote delimiters, calm Base0 blockquotes, GitHub alerts ([!NOTE], [!TIP], [!WARNING]), task checkboxes, Base1 table headers with Base01 delimiters, embedded Bash invocations in calm Base0, and embedded Go with Magenta blank identifier/nil, Base0 method calls (errors.New), and exclusive Yellow control flow"
        else
            fail "Neovim Markdown highlights" "Expected complete Tree-sitter capture matches in sample.md (h1=${RES[h1_fg]} h2=${RES[h2_fg]} delim=${RES[h_delim_fg]} note=${RES[is_md_alert_note]} tbl_hdr=${RES[is_md_table_hdr]} bash_cmd=${RES[is_md_bash_cmd]} go_if=${RES[is_md_go_if_cond]} go_call=${RES[is_md_go_call]})"
        fi
    fi
else
    fail "Neovim init.lua missing" "Expected dotfiles/.config/nvim/init.lua"
fi

test_summary

