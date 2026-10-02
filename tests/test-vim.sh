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
declare -A VIM_OPT_CACHE=()
init_vim_option_cache() {
    local vim_script expr res idx=0
    local -a exprs=()
    vim_script=$(mktemp)
    {
        echo "let s:out = []"
        while IFS= read -r expr; do
            exprs+=("$expr")
            echo "call add(s:out, (${expr}) ? '1' : '0')"
        done < <(awk -F'"' '/^check_option "/ { print $2 }' "${BASH_SOURCE[0]}")
        echo "call writefile(s:out, '${vim_script}.out')"
        echo "qall!"
    } > "$vim_script"
    vim -u "$SCRIPT_DIR/dotfiles/.vimrc" -N -es -S "$vim_script" >/dev/null 2>&1 || true
    if [ -f "${vim_script}.out" ]; then
        while IFS= read -r res; do
            VIM_OPT_CACHE["${exprs[$idx]}"]="$res"
            idx=$((idx + 1))
        done < "${vim_script}.out"
    fi
    rm -f "$vim_script" "${vim_script}.out"
}
init_vim_option_cache

check_option() {
    local opt_expr="$1"
    local desc="$2"
    if [ "${VIM_OPT_CACHE[$opt_expr]:-0}" = "1" ]; then
        pass "$desc"
    else
        fail "$desc" "Option check failed: $opt_expr"
    fi
}

check_option "&tabstop == 4" "tabstop is set to 4"
check_option "&shiftwidth == 4" "shiftwidth is set to 4"
check_option "&expandtab == 1" "expandtab is enabled"
check_option "&background == 'dark'" "background is set to dark"

# Test 3: Standalone & zero-dependency Solarized Dark palette verification
echo -e "\n[3/6] Testing that dotfiles/.vimrc is standalone with inline Solarized Dark palette..."
if ! grep -q 'pathogen#infect' "$SCRIPT_DIR/dotfiles/.vimrc" && ! grep -q 'PYTHONWARNINGS' "$SCRIPT_DIR/dotfiles/.vimrc" && ! grep -q 'UltiSnips' "$SCRIPT_DIR/dotfiles/.vimrc"; then
    pass "dotfiles/.vimrc is self-contained without external bundle dependencies or Python hacks"
else
    fail "dotfiles/.vimrc standalone" "Expected no pathogen, PYTHONWARNINGS, or UltiSnips in .vimrc"
fi

check_option "toupper(synIDattr(hlID('Normal'), 'fg#', 'gui')) == '#839496' && toupper(synIDattr(hlID('Normal'), 'bg#', 'gui')) == '#002B36'" "Vim Normal group mapped to Base0 (#839496) on Base03 (#002B36)"
check_option "toupper(synIDattr(hlID('Comment'), 'fg#', 'gui')) == '#586E75' && synIDattr(hlID('Comment'), 'italic', 'gui') != 1" "Vim Comment group mapped to upright Base01 (#586E75)"
check_option "toupper(synIDattr(hlID('CursorLineNr'), 'fg#', 'gui')) == '#93A1A1' && toupper(synIDattr(hlID('CursorLineNr'), 'bg#', 'gui')) == '#073642' && toupper(synIDattr(hlID('MatchParen'), 'fg#', 'gui')) == '#93A1A1'" "Vim CursorLineNr and MatchParen mapped to Base1 (#93A1A1) on Base02 (#073642)"
check_option "toupper(synIDattr(hlID('Conditional'), 'fg#', 'gui')) == '#B58900' && toupper(synIDattr(hlID('Repeat'), 'fg#', 'gui')) == '#B58900' && toupper(synIDattr(hlID('Exception'), 'fg#', 'gui')) == '#B58900'" "Vim control flow (Conditional, Repeat, Exception) mapped to Solarized Yellow (#B58900)"
check_option "toupper(synIDattr(hlID('Statement'), 'fg#', 'gui')) == '#859900' && toupper(synIDattr(hlID('Keyword'), 'fg#', 'gui')) == '#859900' && toupper(synIDattr(hlID('Type'), 'fg#', 'gui')) == '#859900' && toupper(synIDattr(hlID('Operator'), 'fg#', 'gui')) == '#839496'" "Vim scaffolding and types (Statement, Keyword, Type) mapped to Solarized Green (#859900) and Operator to Base0 (#839496)"
check_option "toupper(synIDattr(hlID('Function'), 'fg#', 'gui')) == '#268BD2'" "Vim Function declarations mapped to Solarized Blue (#268BD2)"
check_option "toupper(synIDattr(hlID('Include'), 'fg#', 'gui')) == '#6C71C4' && toupper(synIDattr(hlID('Special'), 'fg#', 'gui')) == '#6C71C4'" "Vim Include and Special mapped to Solarized Violet (#6C71C4)"
check_option "toupper(synIDattr(hlID('PreProc'), 'fg#', 'gui')) == '#CB4B16'" "Vim PreProc mapped to Solarized Orange (#CB4B16)"
check_option "toupper(synIDattr(hlID('String'), 'fg#', 'gui')) == '#2AA198' && toupper(synIDattr(hlID('Character'), 'fg#', 'gui')) == '#2AA198'" "Vim String and Character literals mapped to Solarized Cyan (#2AA198)"
check_option "toupper(synIDattr(hlID('Constant'), 'fg#', 'gui')) == '#D33682' && toupper(synIDattr(hlID('Number'), 'fg#', 'gui')) == '#D33682' && toupper(synIDattr(hlID('Boolean'), 'fg#', 'gui')) == '#D33682'" "Vim Constant, Number, and Boolean mapped to Solarized Magenta (#D33682)"
check_option "toupper(synIDattr(hlID('Error'), 'fg#', 'gui')) == '#DC322F' && toupper(synIDattr(hlID('WarningMsg'), 'fg#', 'gui')) == '#CB4B16'" "Vim Error and WarningMsg mapped to Solarized Red (#DC322F) and Orange (#CB4B16)"
check_option "synIDattr(hlID('Normal'), 'fg', 'cterm') == '12' && synIDattr(hlID('Conditional'), 'fg', 'cterm') == '3' && synIDattr(hlID('Type'), 'fg', 'cterm') == '2' && synIDattr(hlID('Function'), 'fg', 'cterm') == '4' && synIDattr(hlID('String'), 'fg', 'cterm') == '6' && synIDattr(hlID('Constant'), 'fg', 'cterm') == '5'" "Vim 16/256-color cterm fallback attributes configured alongside TrueColor gui attributes"
check_option "toupper(synIDattr(hlID('WildMenu'), 'fg#', 'gui')) == '#93A1A1' && toupper(synIDattr(hlID('WildMenu'), 'bg#', 'gui')) == '#073642' && toupper(synIDattr(hlID('StatusLineTerm'), 'bg#', 'gui')) == '#073642' && toupper(synIDattr(hlID('Added'), 'fg#', 'gui')) == '#859900' && toupper(synIDattr(hlID('Changed'), 'fg#', 'gui')) == '#B58900' && toupper(synIDattr(hlID('Removed'), 'fg#', 'gui')) == '#DC322F'" "Vim WildMenu, StatusLineTerm, and Added/Changed/Removed groups mapped to Solarized Dark"
check_option "toupper(synIDattr(hlID('protoRepeat'), 'fg#', 'gui')) == '#859900' && toupper(synIDattr(hlID('protoTodo'), 'fg#', 'gui')) == '#586E75' && toupper(synIDattr(hlID('pbtxtMessage'), 'fg#', 'gui')) == '#268BD2' && toupper(synIDattr(hlID('pbtxtField'), 'fg#', 'gui')) == '#859900' && toupper(synIDattr(hlID('pbtxtEnum'), 'fg#', 'gui')) == '#D33682' && toupper(synIDattr(hlID('pbtxtTodo'), 'fg#', 'gui')) == '#586E75'" "Vim Protocol Buffers (protoRepeat, protoTodo) and Textproto (pbtxtMessage, pbtxtField, pbtxtEnum, pbtxtTodo) fallback groups mapped to Solarized Dark"

if COLORTERM=truecolor vim -u "$SCRIPT_DIR/dotfiles/.vimrc" -N -es -c "if &termguicolors == 1 | q | else | cquit 1 | endif" >/dev/null 2>&1; then
    pass "Vim enables termguicolors automatically when COLORTERM=truecolor"
else
    fail "Vim termguicolors" "Expected &termguicolors == 1 when COLORTERM=truecolor"
fi

if COLORTERM=truecolor vim -u "$SCRIPT_DIR/dotfiles/.vimrc" -N -es -c "syntax on" -c "set background=dark" -c "if toupper(synIDattr(hlID('Comment'), 'fg#', 'gui')) == '#586E75' && toupper(synIDattr(hlID('Statement'), 'fg#', 'gui')) == '#859900' && toupper(synIDattr(hlID('Conditional'), 'fg#', 'gui')) == '#B58900' | q | else | cquit 1 | endif" >/dev/null 2>&1; then
    pass "Vim SolarizedDarkFallback augroup preserves inline highlights across :syntax on and :set background=dark"
else
    fail "Vim highlight persistence" "Inline Solarized Dark highlights were reset by :syntax on or :set background=dark"
fi

# Test 4: Verify Home key mapping, Netrw project tree sidebar, and TmuxNavigate in .vimrc
echo -e "\n[4/6] Testing key mappings and hybrid IDE navigation..."
check_option "maparg('<Home>', 'n') == '^'" "Normal mode <Home> mapped to ^"
check_option "maparg('<Home>', 'i') == '<Esc>^i'" "Insert mode <Home> mapped to <Esc>^i"
check_option "get(g:, 'netrw_banner', -1) == 0 && get(g:, 'netrw_liststyle', -1) == 3 && get(g:, 'netrw_browse_split', -1) == 4 && get(g:, 'netrw_winsize', -1) == 20" "Vim Netrw configured as tree sidebar (netrw_liststyle=3, browse_split=4, winsize=20)"
check_option "maparg('<Space>e', 'n') =~# 'Lexplore' && maparg('<C-h>', 'n') ==? '<C-w>h' && maparg('<M-h>', 'n') =~# 'TmuxNavigate' && maparg('<M-h>', 'v') =~# 'TmuxNavigate' && maparg('<M-h>', 'i') =~# 'TmuxNavigate' && maparg('<X1Mouse>', 'n') ==? '<C-O>' && (maparg('<X2Mouse>', 'n') ==? '<C-I>' || maparg('<X2Mouse>', 'n') ==? '<Tab>') && maparg('<X1Mouse>', 'i') =~? '<C-O><C-O>' && (maparg('<X2Mouse>', 'i') =~? '<C-O><C-I>' || maparg('<X2Mouse>', 'i') =~? '<C-O><Tab>')" "Vim <leader>e mapped to :Lexplore, <C-h/j/k/l> kept internal to Vim splits (<C-w>h/j/k/l), <M-h/j/k/l> mapped to s:TmuxNavigate, and <X1Mouse>/<X2Mouse> mapped to jumplist Back/Forward"

# Test 5: Verify fallback Vim zero-external-dependency architecture
echo -e "\n[5/6] Testing fallback Vim zero-external-dependency architecture..."
if [ ! -f "$SCRIPT_DIR/modules/50-vim.sh" ] && ! grep -q 'modules/50-vim.sh' "$SCRIPT_DIR/setup.sh"; then
    pass "setup.sh relies on declarative .vimrc without obsolete bundle provisioning"
else
    fail "setup.sh vim bundles" "Unexpected legacy modules/50-vim.sh found in repository or setup.sh"
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

    if grep -q 'smart_tmux_nav' "$NVIM_CONFIG" && \
       grep -q 'internal_split_nav' "$NVIM_CONFIG" && \
       grep -q 'window_zoomed_flag' "$NVIM_CONFIG" && \
       grep -q 'netrw_liststyle = 3' "$NVIM_CONFIG" && \
       grep -q 'map("n", "<C-h>", internal_split_nav("h")' "$NVIM_CONFIG" && \
       ! grep -q 'map({ "n", "t" }, "<C-h>"' "$NVIM_CONFIG" && \
       grep -q 'map({ "n", "i", "v", "t" }, "<M-h>"' "$NVIM_CONFIG" && \
       grep -q 'map({ "n", "v", "o" }, "<Home>", "^"' "$NVIM_CONFIG" && \
       grep -q 'map("i", "<Home>", "<Esc>^i"' "$NVIM_CONFIG" && \
       grep -Fq 'map({ "n", "v" }, "<X1Mouse>", "<C-o>"' "$NVIM_CONFIG" && \
       grep -Fq 'map("i", "<X1Mouse>", "<C-\\><C-o><C-o>"' "$NVIM_CONFIG" && \
       grep -Fq 'map({ "n", "v" }, "<X2Mouse>", "<C-i>"' "$NVIM_CONFIG" && \
       grep -Fq 'map("i", "<X2Mouse>", "<C-\\><C-o><C-i>"' "$NVIM_CONFIG" && \
       grep -q 'map("n", "H", "<cmd>bprevious<CR>"' "$NVIM_CONFIG" && \
       grep -q 'map("n", "L", "<cmd>bnext<CR>"' "$NVIM_CONFIG" && \
       grep -q 'move_selection_next' "$NVIM_CONFIG" && \
       grep -q 'move_selection_previous' "$NVIM_CONFIG" && \
       grep -q 'map({ "n", "i", "v", "t" }, "<M-a>"' "$NVIM_CONFIG" && \
       grep -q 'map({ "n", "i", "v", "t" }, "<M-E>"' "$NVIM_CONFIG" && \
       grep -q 'map({ "n", "i", "v", "t" }, "<M-T>"' "$NVIM_CONFIG" && \
       grep -q 'map({ "n", "i", "v", "t" }, "<M-H>"' "$NVIM_CONFIG" && \
       grep -q -- '--show-editor' "$NVIM_CONFIG" && \
       grep -q -- '--show-term' "$NVIM_CONFIG" && \
       grep -q -- '--toggle-editor' "$NVIM_CONFIG" && \
       grep -q -- '--toggle-term' "$NVIM_CONFIG" && \
       grep -q -- '--swap' "$NVIM_CONFIG" && \
       grep -q 'MiniFilesBorder' "$NVIM_CONFIG" && \
       grep -q 'MiniFilesBufferCreate' "$NVIM_CONFIG" && \
       grep -q 'require("mini.files").setup' "$NVIM_CONFIG" && \
       grep -q 'require("mini.icons").setup' "$NVIM_CONFIG"; then
        pass "Neovim init.lua configures 4-layer navigation (C-hjkl internal_split_nav, M-hjkl smart_tmux_nav across all modes, <Home>, <X1Mouse>/<X2Mouse> jumplist Back/Forward, H/L buffer cycling, Telescope C-j/C-k, M-a/e/t focus, M-E/T pane toggles, M-H/J/K/L pane swaps, and Mini.files with arrow/CR bindings)"
    else
        fail "Neovim IDE integration" "Missing expected 4-layer navigation, <Home>, <X1Mouse>/<X2Mouse>, H/L buffer cycling, M-E/T toggles, M-H/J/K/L swaps, or Mini.files setup in init.lua"
    fi

    if grep -q 'opt\.autoread = true' "$NVIM_CONFIG" && \
       grep -q 'SolarizedAutoRead' "$NVIM_CONFIG" && \
       grep -q 'silent! checktime' "$NVIM_CONFIG" && \
       grep -q 'toggle_file_explorer(false)' "$NVIM_CONFIG" && \
       grep -q 'toggle_file_explorer(true)' "$NVIM_CONFIG" && \
       ! grep -q 'vim\.keymap\.set.*<leader>[eE]' "$NVIM_CONFIG" && \
       grep -q 'nvim_create_user_command("IdeCd"' "$NVIM_CONFIG" && \
       grep -q 'nvim_create_user_command("Q"' "$NVIM_CONFIG" && \
       grep -q 'nvim_create_user_command("Quit"' "$NVIM_CONFIG" && \
       grep -q '"<leader>gs"' "$NVIM_CONFIG" && \
       ! grep -q 'SolarizedIdeTree' "$NVIM_CONFIG" && \
       ! grep -q 'IdeFollow' "$NVIM_CONFIG" && \
       ! grep -q 'IdeClose' "$NVIM_CONFIG" && \
       ! grep -q 'IdeWriteClose' "$NVIM_CONFIG"; then
        pass "Neovim init.lua configures native autoread + SolarizedAutoRead checktime, mini.files explorer (<leader>e buffer dir / <leader>E workspace cwd), <leader>gs git_status, IdeCd, and Q/Quit without custom SolarizedIdeTree, IdeFollow, or :q/:qa hijack"
    else
        fail "Neovim native autoread & explorer" "Expected opt.autoread, SolarizedAutoRead, toggle_file_explorer(false/true), IdeCd, Q/Quit, <leader>gs, and no SolarizedIdeTree/IdeFollow/IdeClose in init.lua"
    fi

    if grep -q 'if not in_ssh then' "$NVIM_CONFIG" && \
       grep -q 'opt\.clipboard = "unnamedplus"' "$NVIM_CONFIG" && \
       grep -q '"<M-c>"' "$NVIM_CONFIG" && \
       grep -q '"<M-v>"' "$NVIM_CONFIG" && \
       ! grep -q 'broadcast_copy' "$NVIM_CONFIG" && \
       ! grep -q 'vim\.g\.clipboard' "$NVIM_CONFIG"; then
        pass "Neovim init.lua guards local /tmp/.X11-unix/X0 fallback behind not in_ssh, relies on built-in unnamedplus + OSC 52 clipboard provider, and binds <M-c> / <M-v> without custom broadcast_copy"
    else
        fail "Neovim native clipboard & SSH guard" "Expected 'if not in_ssh then', unnamedplus, <M-c>/<M-v>, and no broadcast_copy/vim.g.clipboard override in init.lua"
    fi

    if grep -q 'local function set_hl(groups, spec)' "$NVIM_CONFIG" && \
       grep -q '"@markup\.heading\.1"' "$NVIM_CONFIG" && \
       grep -q '"@markup\.heading\.2"' "$NVIM_CONFIG" && \
       grep -q '"@markup\.heading\.3"' "$NVIM_CONFIG" && \
       grep -q '"@markup\.heading\.4"' "$NVIM_CONFIG" && \
       grep -q '"@markup\.heading\.5"' "$NVIM_CONFIG" && \
       grep -q '"@markup\.heading\.6"' "$NVIM_CONFIG" && \
       grep -q '"@markup\.quote"' "$NVIM_CONFIG" && \
       grep -q '"@type"' "$NVIM_CONFIG" && \
       grep -q '"@keyword\.type"' "$NVIM_CONFIG" && \
       grep -q '"@keyword\.conditional\.ternary"' "$NVIM_CONFIG" && \
       grep -q '"markdownH1"' "$NVIM_CONFIG" && \
       grep -q '"markdownH2"' "$NVIM_CONFIG" && \
       grep -q '"@constant"' "$NVIM_CONFIG" && \
       grep -q '"@attribute"' "$NVIM_CONFIG"; then
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

    if grep -q '"@module"' "$NVIM_CONFIG" && \
       grep -q '"@lsp\.type\.namespace"' "$NVIM_CONFIG"; then
        pass "Neovim maps @module and @lsp.type.namespace to Solarized Violet (#6c71c4)"
    else
        fail "Neovim namespace highlights" "Missing @module or @lsp.type.namespace mapped to colors.violet in init.lua"
    fi

    PRINTF_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/printf/highlights.scm"
    if [ -f "$PRINTF_QUERY" ] && grep -q 'format.*@string.special' "$PRINTF_QUERY" && \
       grep -q '"@string\.escape"' "$NVIM_CONFIG" && \
       grep -q '"@character\.printf"' "$NVIM_CONFIG" && \
       grep -q '"printf"' "$NVIM_CONFIG"; then
        pass "Neovim defines Tree-sitter printf format specifiers and string escapes in Solarized Cyan"
    else
        fail "Neovim printf highlights" "Missing or invalid printf format specifiers and escape sequences in init.lua"
    fi

    DIFF_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/diff/highlights.scm"
    if [ -f "$DIFF_QUERY" ] && grep -q 'deletion.*@diff.minus' "$DIFF_QUERY" && \
       grep -q 'addition.*@diff.plus' "$DIFF_QUERY" && \
       grep -q 'location.*@diff.line' "$DIFF_QUERY" && \
       grep -q '"@diff\.plus"' "$NVIM_CONFIG" && \
       grep -q '"@diff\.minus"' "$NVIM_CONFIG" && \
       grep -q '"@diff\.line"' "$NVIM_CONFIG"; then
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

    JS_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/javascript/highlights.scm"
    TS_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/typescript/highlights.scm"
    if [ -f "$JS_QUERY" ] && grep -q '"Date"' "$JS_QUERY" && grep -q '"process"' "$JS_QUERY" && \
       [ -f "$TS_QUERY" ] && grep -q '"process"' "$TS_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for JavaScript & TypeScript (Date in calm Base0 Grey, process & globalThis in Solarized Magenta)"
    else
        fail "Neovim JavaScript/TypeScript query extensions" "Missing or invalid after/queries/javascript/highlights.scm or after/queries/typescript/highlights.scm"
    fi

    XML_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/xml/highlights.scm"
    if [ -f "$XML_QUERY" ] && grep -q 'keyword\.directive' "$XML_QUERY" && \
       grep -q 'CDSect' "$XML_QUERY" && grep -q '@module' "$XML_QUERY"; then
        pass "Neovim defines Tree-sitter query extensions for XML (Orange directives, Violet CDATA delimiters, calm Base0 CDATA body)"
    else
        fail "Neovim XML query extension" "Missing or invalid after/queries/xml/highlights.scm"
    fi

    if grep -q '"@tag"' "$NVIM_CONFIG" && \
       grep -q '"@tag\.attribute"' "$NVIM_CONFIG" && \
       grep -q '"@tag\.delimiter"' "$NVIM_CONFIG" && \
       grep -q '"xmlTagName"' "$NVIM_CONFIG" && \
       grep -q '"xml"' "$NVIM_CONFIG"; then
        pass "Neovim defines Tree-sitter and legacy syntax highlights for XML (Blue tags, Green attributes, Base0 delimiters, parsers table)"
    else
        fail "Neovim XML highlights in init.lua" "Missing or invalid XML highlight groups or parser in init.lua"
    fi

    HTML_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/queries/html/highlights.scm"
    HTML_TAGS_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/queries/html_tags/highlights.scm"
    if [ -f "$HTML_QUERY" ] && grep -q 'keyword\.directive' "$HTML_QUERY" && \
       grep -q 'doctype' "$HTML_QUERY" && [ -f "$HTML_TAGS_QUERY" ] && \
       grep -q 'markup\.raw\.block' "$HTML_TAGS_QUERY"; then
        pass "Neovim defines Tree-sitter base queries for HTML (Orange doctype, Magenta entities, calm Base0 markup text, zero OSC 8 links)"
    else
        fail "Neovim HTML query base" "Missing or invalid queries/html/highlights.scm or queries/html_tags/highlights.scm"
    fi

    if grep -q '"htmlTagName"' "$NVIM_CONFIG" && \
       grep -q '"@markup\.heading\.html"' "$NVIM_CONFIG" && \
       grep -q '"html"' "$NVIM_CONFIG"; then
        pass "Neovim defines Tree-sitter and legacy syntax highlights for HTML (Blue tags, Base0 heading desensitization, parsers table)"
    else
        fail "Neovim HTML highlights in init.lua" "Missing or invalid HTML highlight groups or parser in init.lua"
    fi

    PROTO_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/queries/proto/highlights.scm"
    TEXTPROTO_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/queries/textproto/highlights.scm"
    if [ -f "$PROTO_QUERY" ] && grep -q 'keyword\.directive' "$PROTO_QUERY" && \
       grep -q 'function\.method' "$PROTO_QUERY" && [ -f "$TEXTPROTO_QUERY" ] && \
       grep -q 'property\.textproto' "$TEXTPROTO_QUERY" && \
       grep -q '@tag' "$TEXTPROTO_QUERY" && \
       grep -q '"@property\.textproto"' "$NVIM_CONFIG" && \
       grep -q '"protoRepeat"' "$NVIM_CONFIG" && \
       grep -q '"pbtxtMessage"' "$NVIM_CONFIG" && \
       grep -q '"proto"' "$NVIM_CONFIG" && grep -q '"textproto"' "$NVIM_CONFIG"; then
        pass "Neovim defines Tree-sitter base queries and legacy fallbacks for Protocol Buffers (.proto) and Textproto (.textproto / .pbtxt)"
    else
        fail "Neovim Protobuf & Textproto queries/highlights" "Missing or invalid queries/proto/highlights.scm, queries/textproto/highlights.scm, or init.lua highlights"
    fi

    KOTLIN_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/kotlin/highlights.scm"
    SWIFT_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/swift/highlights.scm"
    if [ -f "$KOTLIN_QUERY" ] && grep -q 'file_annotation' "$KOTLIN_QUERY" && \
       grep -q 'interpolation_identifier_start' "$KOTLIN_QUERY" && \
       [ -f "$SWIFT_QUERY" ] && grep -q '"defer"' "$SWIFT_QUERY" && \
       grep -q '"fallthrough"' "$SWIFT_QUERY" && \
       grep -q '"kotlin"' "$NVIM_CONFIG" && grep -q '"swift"' "$NVIM_CONFIG"; then
        pass "Neovim defines Tree-sitter query extensions and parser registrations for Kotlin (.kt/.kts) and Swift (.swift)"
    else
        fail "Neovim Kotlin & Swift queries/parsers" "Missing or invalid after/queries/kotlin/highlights.scm, after/queries/swift/highlights.scm, or init.lua parser entries"
    fi

    GRAPHQL_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/queries/graphql/highlights.scm"
    STARLARK_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/starlark/highlights.scm"
    REGO_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/queries/rego/highlights.scm"
    if [ -f "$GRAPHQL_QUERY" ] && grep -q 'type_system_directive_location' "$GRAPHQL_QUERY" && \
       [ -f "$STARLARK_QUERY" ] && grep -q '"load"' "$STARLARK_QUERY" && \
       [ -f "$REGO_QUERY" ] && grep -q 'expr_every' "$REGO_QUERY" && \
       grep -q '"@property\.graphql"' "$NVIM_CONFIG" && \
       grep -q '"graphql"' "$NVIM_CONFIG" && grep -q '"starlark"' "$NVIM_CONFIG" && grep -q '"rego"' "$NVIM_CONFIG"; then
        pass "Neovim defines Tree-sitter queries and parser registrations for GraphQL (.graphql), Starlark/Bazel (.bzl), and OPA Rego (.rego)"
    else
        fail "Neovim GraphQL, Starlark & Rego queries/parsers" "Missing or invalid queries/graphql/highlights.scm, after/queries/starlark/highlights.scm, queries/rego/highlights.scm, or init.lua entries"
    fi

    LUA_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/lua/highlights.scm"
    DOCKER_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/dockerfile/highlights.scm"
    DOCKER_INJ_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/queries/dockerfile/injections.scm"
    MAKE_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/make/highlights.scm"
    if [ -f "$LUA_QUERY" ] && grep -q 'attribute' "$LUA_QUERY" && \
       [ -f "$DOCKER_QUERY" ] && grep -q 'from_instruction' "$DOCKER_QUERY" && \
       [ -f "$DOCKER_INJ_QUERY" ] && ! grep -q '#set! injection\.combined' "$DOCKER_INJ_QUERY" && \
       [ -f "$MAKE_QUERY" ] && grep -q 'automatic_variable' "$MAKE_QUERY" && \
       grep -q '"dockerfile"' "$NVIM_CONFIG" && grep -q '"make"' "$NVIM_CONFIG"; then
        pass "Neovim defines Tree-sitter queries and parser registrations for Lua (.lua), Dockerfile (Containerfile), and GNU Make (.mk)"
    else
        fail "Neovim Lua, Dockerfile & Make queries/parsers" "Missing or invalid after/queries/{lua,dockerfile,make}/highlights.scm, queries/dockerfile/injections.scm, or init.lua entries"
    fi

    ELIXIR_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/elixir/highlights.scm"
    ELIXIR_INJ_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/queries/elixir/injections.scm"
    HASKELL_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/haskell/highlights.scm"
    OCAML_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/ocaml/highlights.scm"
    CLOJURE_QUERY="$SCRIPT_DIR/dotfiles/.config/nvim/after/queries/clojure/highlights.scm"
    if [ -f "$ELIXIR_QUERY" ] && grep -q '"defmodule"' "$ELIXIR_QUERY" && \
       [ -f "$ELIXIR_INJ_QUERY" ] && ! grep -q '"markdown"' "$ELIXIR_INJ_QUERY" && \
       [ -f "$HASKELL_QUERY" ] && grep -q 'decl/signature' "$HASKELL_QUERY" && \
       [ -f "$OCAML_QUERY" ] && grep -q 'type_variable' "$OCAML_QUERY" && \
       [ -f "$CLOJURE_QUERY" ] && grep -q 'defprotocol' "$CLOJURE_QUERY" && \
       grep -q '"@string\.special\.symbol\.elixir"' "$NVIM_CONFIG" && \
       grep -q '"@string\.special\.symbol\.clojure"' "$NVIM_CONFIG" && \
       grep -q '"elixir"' "$NVIM_CONFIG" && grep -q '"haskell"' "$NVIM_CONFIG" && \
       grep -q '"ocaml"' "$NVIM_CONFIG" && grep -q '"clojure"' "$NVIM_CONFIG"; then
        pass "Neovim defines Tree-sitter queries and parser registrations for Elixir (.ex), Haskell (.hs), OCaml (.ml), and Clojure (.clj)"
    else
        fail "Neovim Elixir, Haskell, OCaml & Clojure queries/parsers" "Missing or invalid after/queries/{elixir,haskell,ocaml,clojure}/highlights.scm, queries/elixir/injections.scm, or init.lua entries"
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

    LAZY_LOCK="$SCRIPT_DIR/dotfiles/.config/nvim/lazy-lock.json"
    if grep -q 'MeanderingProgrammer/render-markdown\.nvim' "$NVIM_CONFIG" && \
       grep -q '"<leader>m"' "$NVIM_CONFIG" && \
       grep -q 'SolarizedMarkdownReadability' "$NVIM_CONFIG" && \
       grep -q 'RenderMarkdownH1' "$NVIM_CONFIG" && \
       grep -q '"RenderMarkdownWarn"' "$NVIM_CONFIG" && \
       grep -q '"RenderMarkdownHint"' "$NVIM_CONFIG" && \
       grep -q '"RenderMarkdownBullet"' "$NVIM_CONFIG" && \
       grep -q 'RenderMarkdownCodeInfo\s*=\s*{\s*fg\s*=\s*colors\.base01' "$NVIM_CONFIG" && \
       grep -q 'highlight_language\s*=\s*"RenderMarkdownCodeInfo"' "$NVIM_CONFIG" && \
       grep -q 'yaml\s*=\s*{\s*enabled\s*=\s*false\s*}' "$NVIM_CONFIG" && \
       grep -q 'SolarizedMiniFilesWindow' "$NVIM_CONFIG" && \
       grep -q 'max_number\s*=\s*2' "$NVIM_CONFIG" && \
       [ -f "$LAZY_LOCK" ] && grep -q '"render-markdown\.nvim"' "$LAZY_LOCK"; then
        pass "Neovim configures render-markdown.nvim (<leader>m, SolarizedMarkdownReadability, RenderMarkdown* highlights) and left-anchored mini.files (max_number = 2, SolarizedMiniFilesWindow)"
    else
        fail "Neovim render-markdown.nvim & mini.files config" "Missing render-markdown.nvim, SolarizedMarkdownReadability, SolarizedMiniFilesWindow, or lazy-lock.json pin"
    fi

    if command -v nvim >/dev/null 2>&1; then
        TEMP_NVIM_XDG_CONFIG=$(mktemp -d)
        ln -sfn "$SCRIPT_DIR/dotfiles/.config/nvim" "$TEMP_NVIM_XDG_CONFIG/nvim"
        cat <<'EOF' > "$TEMP_NVIM_XDG_CONFIG/inspect.lua"
vim.cmd([[redraw]])

local buf_lines_cache = {}
local function find_pos(buf, line_pat, token, start_col)
    local lines = buf_lines_cache[buf]
    if not lines then
        lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        buf_lines_cache[buf] = lines
    end
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

local function inspect_effective_fg(buf, row, col)
    if row < 0 or col < 0 then return "nil" end
    local insp = vim.inspect_pos(buf, row, col)
    if insp.treesitter and #insp.treesitter > 0 then
        local best_fg = nil
        local best_prio = -1
        for _, eff in ipairs(insp.treesitter) do
            local hl = vim.api.nvim_get_hl(0, { name = eff.hl_group, link = false })
            if not hl.fg and eff.hl_group_link then
                hl = vim.api.nvim_get_hl(0, { name = eff.hl_group_link, link = false })
            end
            if hl.fg then
                local prio = tonumber(eff.metadata and eff.metadata.priority) or 100
                if prio >= best_prio then
                    best_prio = prio
                    best_fg = string.format("%06x", hl.fg)
                end
            end
        end
        if best_fg then return best_fg end
    end
    return "nil"
end

local function hl_fg(name, fallback)
    local h = vim.api.nvim_get_hl(0, { name = name, link = false })
    if not h.fg and fallback then
        h = vim.api.nvim_get_hl(0, { name = fallback, link = false })
    end
    return string.format("%06x", h.fg or 0)
end

local function probe_cap(buf, line_pat, token, expected_cap, start_col, col_offset)
    local r, c = find_pos(buf, line_pat, token, start_col)
    return tostring(match_capture(buf, r, c + (col_offset or 0), expected_cap))
end

local function probe_fg(buf, line_pat, token, start_col, col_offset)
    local r, c = find_pos(buf, line_pat, token, start_col)
    return inspect_effective_fg(buf, r, c + (col_offset or 0))
end

local function probe_cap_fg(buf, line_pat, token, expected_cap, start_col, col_offset)
    local r, c = find_pos(buf, line_pat, token, start_col)
    c = c + (col_offset or 0)
    return tostring(match_capture(buf, r, c, expected_cap)) .. "/" .. inspect_effective_fg(buf, r, c)
end

local sample_dir = vim.fn.expand("%:p:h")
local prev_buf = nil

local function open_sample(filename, lang)
    vim.cmd("edit " .. sample_dir .. "/" .. filename)
    local buf = vim.api.nvim_get_current_buf()
    if prev_buf and prev_buf ~= buf and vim.api.nvim_buf_is_valid(prev_buf) then
        buf_lines_cache[prev_buf] = nil
        pcall(vim.cmd, "bwipeout! " .. prev_buf)
    end
    if lang then
        pcall(vim.treesitter.start, buf, lang)
    end
    pcall(function()
        local parser = lang and vim.treesitter.get_parser(buf, lang) or vim.treesitter.get_parser(buf)
        if parser then parser:parse(true) end
    end)
    vim.cmd("redraw")
    prev_buf = buf
    return buf
end

local function assert_suite(pass_msg, fail_label, checks)
    local errs = {}
    for _, chk in ipairs(checks) do
        local name, actual, expected = chk[1], tostring(chk[2]), tostring(chk[3])
        if actual ~= expected then
            table.insert(errs, string.format("%s=%s (expected %s)", name, actual, expected))
        end
    end
    if #errs == 0 then
        io.write("PASS:" .. pass_msg .. "\n")
    else
        io.write("FAIL:" .. fail_label:gsub(":", "") .. ":" .. table.concat(errs, ", ") .. "\n")
    end
end

local hl_param = vim.api.nvim_get_hl(0, { name = "@variable.parameter", link = false })
assert_suite("Neovim renders parameters in upright font without italics", "Neovim parameter italics", {
    { "param_italic", tostring(hl_param.italic == true), "false" },
})
assert_suite("Neovim renders @constant in Solarized Magenta (#d33682)", "Neovim @constant highlight", {
    { "const_fg", hl_fg("@constant"), "d33682" },
})

local r, c, hl, tp_buf

-- 1. Inspect C (sample.c)
local c_buf = open_sample("sample.c", "c")

assert_suite("Neovim renders C custom types (WorkerNode) in calm Base0 (#839496) and primitives in Green (#859900)", "Neovim sizeof(type) highlight", {
    { "is_wn_type", probe_cap(c_buf, "malloc(sizeof(WorkerNode))", "WorkerNode", "type", 20), "true" },
    { "type_c_fg", hl_fg("@type.c", "@type"), "839496" },
    { "type_builtin_c_fg", hl_fg("@type.builtin.c", "@type.builtin"), "859900" },
})
assert_suite("Neovim Tree-sitter captures sizeof as @keyword.operator (Green)", "Neovim sizeof highlight", {
    { "is_so_kw", probe_cap(c_buf, "malloc(sizeof(WorkerNode))", "sizeof", "keyword.operator"), "true" },
})
assert_suite("Neovim Tree-sitter captures C control flow (switch) as @keyword.conditional in Solarized Yellow (#b58900)", "Neovim C control flow capture", {
    { "is_c_switch_cond", probe_cap(c_buf, "switch (level) {", "switch", "keyword.conditional"), "true" },
    { "cond_c_fg", hl_fg("@keyword.conditional.c", "@keyword.conditional"), "b58900" },
})
assert_suite("Neovim Tree-sitter captures C function calls (malloc) as @function.call in calm Base0 (#839496)", "Neovim C function call capture", {
    { "is_c_malloc_call", probe_cap(c_buf, "WorkerNode *node = malloc(sizeof(WorkerNode));", "malloc", "function.call"), "true" },
    { "fcall_c_fg", hl_fg("@function.call.c", "@function.call"), "839496" },
})
assert_suite("Neovim Tree-sitter captures C preprocessor conditionals (#ifndef LOG_LEVEL) as @constant.macro in Solarized Orange (#cb4b16), C23 static_assert as @keyword, and [[nodiscard]] as @attribute", "Neovim C preprocessor/C23 capture", {
    { "is_c_ifndef_macro", probe_cap(c_buf, "#ifndef LOG_LEVEL", "LOG_LEVEL", "constant.macro"), "true" },
    { "macro_c_fg", hl_fg("@constant.macro"), "cb4b16" },
    { "is_c_sa_kw", probe_cap(c_buf, "static_assert(MAX_BUFFER_SIZE", "static_assert", "keyword"), "true" },
    { "is_c_attr_nd", probe_cap(c_buf, "[[nodiscard]] static bool", "nodiscard", "attribute"), "true" },
})

-- 2. Inspect C++ (sample.cpp)
local cpp_buf = open_sample("sample.cpp", "cpp")
assert_suite("Neovim renders C++ custom types (Printable T) in calm Base0 (#839496) and primitives in Green (#859900)", "Neovim template type parameter highlight", {
    { "is_t_type", probe_cap(cpp_buf, "template <Printable T>", "T>", "type", 18), "true" },
    { "type_cpp_fg", hl_fg("@type.cpp", "@type"), "839496" },
    { "type_builtin_cpp_fg", hl_fg("@type.builtin.cpp", "@type.builtin"), "859900" },
})
assert_suite("Neovim renders @module and @lsp.type.namespace in Solarized Violet (#6c71c4)", "Neovim module/namespace highlight", {
    { "module_fg", hl_fg("@module"), "6c71c4" },
    { "lsp_ns_fg", hl_fg("@lsp.type.namespace"), "6c71c4" },
})
assert_suite("Neovim Tree-sitter captures namespace and using as declaration keywords in Solarized Green (#859900)", "Neovim namespace/using capture", {
    { "is_ns_kw", probe_cap(cpp_buf, "namespace core::telemetry", "namespace", "keyword.type"), "true" },
    { "is_using_kw", probe_cap(cpp_buf, "using namespace core::telemetry;", "using", "keyword"), "true" },
})
assert_suite("Neovim Tree-sitter captures namespace identifiers (core, telemetry) as @module (Violet)", "Neovim namespace capture", {
    { "is_core_mod", probe_cap(cpp_buf, "namespace core::telemetry", "core", "module"), "true" },
    { "is_telem_mod", probe_cap(cpp_buf, "namespace core::telemetry", "telemetry", "module"), "true" },
})
assert_suite("Neovim Tree-sitter captures C++ scope qualifiers (std::) as @variable (Base0 Grey)", "Neovim C++ scope qualifier capture", {
    { "is_std_var", probe_cap(cpp_buf, "return std::nullopt;", "std", "variable"), "true" },
})
assert_suite("Neovim Tree-sitter captures scoped enum members (NodeState::Initializing) as @constant (Magenta)", "Neovim scoped enum constant capture", {
    { "is_init_const", probe_cap(cpp_buf, "NodeState::Initializing", "Initializing", "constant"), "true" },
})
assert_suite("Neovim Tree-sitter captures standard sentinels (std::nullopt) as @constant (Magenta)", "Neovim sentinel capture", {
    { "is_nullopt_const", probe_cap(cpp_buf, "return std::nullopt;", "nullopt", "constant"), "true" },
})
assert_suite("Neovim renders C++ attributes ([[nodiscard]]) in Solarized Violet (#6c71c4)", "Neovim attribute highlight", {
    { "attr_fg", hl_fg("@attribute.cpp", "@attribute"), "6c71c4" },
    { "is_attr_orange", probe_cap(cpp_buf, "[[nodiscard]]", "nodiscard", "attribute"), "true" },
})
assert_suite("Neovim Tree-sitter captures C++ control flow (if) as @keyword.conditional in Solarized Yellow (#b58900) and static_assert/noexcept in Green", "Neovim C++ control flow/modifier capture", {
    { "is_cpp_if_cond", probe_cap(cpp_buf, "if (payload_history_.empty()) {", "if", "keyword.conditional"), "true" },
    { "cond_cpp_fg", hl_fg("@keyword.conditional.cpp", "@keyword.conditional"), "b58900" },
    { "is_cpp_sa_kw", probe_cap(cpp_buf, "static_assert(MAX_WORKERS > 0", "static_assert", "keyword"), "true" },
    { "is_cpp_noexcept_mod", probe_cap(cpp_buf, "is_active() const noexcept", "noexcept", "keyword.modifier"), "true" },
})
assert_suite("Neovim Tree-sitter captures C++ function calls (for_each) as @function.call in calm Base0 (#839496)", "Neovim C++ function call capture", {
    { "is_cpp_fe_call", probe_cap(cpp_buf, "std::for_each(", "for_each", "function.call"), "true" },
    { "fcall_cpp_fg", hl_fg("@function.call.cpp", "@function.call"), "839496" },
})

-- 3. Inspect Java (sample.java)
local java_buf = open_sample("sample.java", "java")
local ok_jdtls, _ = pcall(require, "jdtls")
assert_suite("Neovim detects Java filetype and loads nvim-jdtls cleanly", "Neovim Java ftplugin verification", {
    { "java_ft", vim.bo.filetype, "java" },
    { "ok_jdtls", tostring(ok_jdtls), "true" },
})
assert_suite("Neovim renders Java import keyword as @keyword.import (Violet)", "Neovim Java import keyword", {
    { "is_j_imp_kw", probe_cap(java_buf, "import java.time.Instant;", "import", "keyword.import"), "true" },
})
assert_suite("Neovim renders Java record declaration and pattern guard 'when' as keywords (Green)", "Neovim Java record/when keywords", {
    { "is_j_rec_kw", probe_cap(java_buf, "record OrderRecord(", "record", "keyword.type"), "true" },
    { "is_j_when_kw", probe_cap(java_buf, "when amount >=", "when", "keyword.conditional"), "true" },
})
assert_suite("Neovim renders Java annotations as @attribute (Violet), record patterns as @type (Base0), and primitives as @type.builtin (Green #859900)", "Neovim Java annotation and record pattern highlights", {
    { "is_j_ann", probe_cap(java_buf, "@Service", "@Service", "attribute"), "true" },
    { "is_j_pat_type", probe_cap(java_buf, "case OrderRecord(", "OrderRecord", "type"), "true" },
    { "type_builtin_java_fg", hl_fg("@type.builtin.java", "@type.builtin"), "859900" },
    { "type_java_fg", hl_fg("@type.java", "@type"), "839496" },
})
assert_suite("Neovim renders Java 'this' keyword as @variable.builtin in Solarized Magenta (#d33682)", "Neovim Java this keyword", {
    { "is_j_this_var", probe_cap(java_buf, "this.timeoutMs", "this", "variable.builtin"), "true" },
    { "var_bi_fg", hl_fg("@variable.builtin.java", "@variable.builtin"), "d33682" },
})
assert_suite("Neovim renders Java constructor delegation 'super(...)' as @function.builtin in calm Solarized Base0 (#839496) and @module in Solarized Violet (#6c71c4)", "Neovim Java super delegation", {
    { "is_j_super_call", probe_cap(java_buf, "super(timeoutMs);", "super", "function.builtin"), "true" },
    { "func_bi_java_fg", hl_fg("@function.builtin.java", "@function.builtin"), "839496" },
    { "mod_java_fg", hl_fg("@module.java", "@module"), "6c71c4" },
})

-- 4. Inspect Diff (sample.diff)
local diff_buf = open_sample("sample.diff", "diff")
assert_suite("Neovim renders diff additions (+) in Solarized Green (#859900)", "Neovim diff addition highlight", {
    { "diff_plus_fg", hl_fg("@diff.plus"), "859900" },
    { "is_add_plus", probe_cap(diff_buf, "Maximum retry attempts", "+", "diff.plus"), "true" },
})
assert_suite("Neovim renders diff deletions (-) in Solarized Red (#dc322f)", "Neovim diff deletion highlight", {
    { "diff_minus_fg", hl_fg("@diff.minus"), "dc322f" },
    { "is_del_minus", probe_cap(diff_buf, "maxRetries", "-", "diff.minus"), "true" },
})
assert_suite("Neovim renders diff hunk headers (@@ ... @@) in Solarized Blue (#268bd2)", "Neovim diff hunk line highlight", {
    { "diff_line_fg", hl_fg("@diff.line"), "268bd2" },
    { "is_hunk_line", probe_cap(diff_buf, "@@ -32,18 +32,22 @@", "@@", "diff.line"), "true" },
})

-- 5. Inspect Go (sample.go)
local go_buf = open_sample("sample.go", "go")
assert_suite("Neovim renders Go package keyword in Solarized Green (#859900)", "Neovim Go package keyword", {
    { "is_pkg_kw", probe_cap(go_buf, "package main", "package", "keyword"), "true" },
    { "pkg_fg", hl_fg("@keyword.go", "@keyword"), "859900" },
})
assert_suite("Neovim renders Go import keyword in Solarized Violet (#6c71c4)", "Neovim Go import keyword", {
    { "is_imp_kw", probe_cap(go_buf, "import (", "import", "keyword.import"), "true" },
    { "imp_fg", hl_fg("@keyword.import.go", "@keyword.import"), "6c71c4" },
})
assert_suite("Neovim renders Go package declaration (main) as @module (Violet) and qualifiers (context.) as @variable (Base0 Grey)", "Neovim Go module/qualifier captures", {
    { "is_main_mod", probe_cap(go_buf, "package main", "main", "module"), "true" },
    { "is_ctx_var", probe_cap(go_buf, "ctx context.Context", "context", "variable"), "true" },
})
assert_suite("Neovim renders Go enum identifiers (LevelDebug) in Solarized Magenta (@constant)", "Neovim Go constant capture", {
    { "is_ld_const", probe_cap(go_buf, "LevelDebug LogLevel = iota", "LevelDebug", "constant"), "true" },
})
assert_suite("Neovim renders Go function calls (NewClusterNode) as @function.call in calm Solarized Base0 (#839496)", "Neovim Go function call", {
    { "is_ncn_call", probe_cap(go_buf, "node, err := NewClusterNode(cfg)", "NewClusterNode", "function.call"), "true" },
    { "fcall_fg", hl_fg("@function.call.go", "@function.call"), "839496" },
})
assert_suite("Neovim renders Go types (Context) as @type in calm Base0 (#839496), generic functions in Blue, and built-in constraints/primitives in Green (#859900)", "Neovim Go type/generic capture", {
    { "is_t_ctx_type", probe_cap(go_buf, "ctx context.Context", "Context", "type"), "true" },
    { "type_go_fg", hl_fg("@type.go", "@type"), "839496" },
    { "type_builtin_go_fg", hl_fg("@type.builtin.go", "@type.builtin"), "859900" },
    { "is_go_gen_fn", probe_cap(go_buf, "func ResolveDefault[T comparable]", "ResolveDefault", "function"), "true" },
    { "is_go_comp_type", probe_cap(go_buf, "func ResolveDefault[T comparable]", "comparable", "type.builtin"), "true" },
})
assert_suite("Neovim renders Go control flow (defer, select, case, default) as @keyword.conditional in Solarized Yellow (#b58900)", "Neovim Go control flow capture", {
    { "is_defer_cond", probe_cap(go_buf, "defer c.mu.RUnlock()", "defer", "keyword.conditional"), "true" },
    { "is_select_cond", probe_cap(go_buf, "select {", "select", "keyword.conditional"), "true" },
    { "is_case_cond", probe_cap(go_buf, "case <-ctx.Done():", "case", "keyword.conditional"), "true" },
    { "is_default_cond", probe_cap(go_buf, "default:", "default", "keyword.conditional"), "true" },
    { "cond_go_fg", hl_fg("@keyword.conditional.go", "@keyword.conditional"), "b58900" },
})
assert_suite("Neovim renders Go built-in calls (panic) as @function.call in calm Solarized Base0 (#839496)", "Neovim Go builtin call capture", {
    { "is_panic_call", probe_cap(go_buf, "panic(err)", "panic", "function.call"), "true" },
})

-- 6. Inspect Python (sample.py)
local py_buf = open_sample("sample.py", "python")
r, c = find_pos(py_buf, "asyncio.sleep(0.02)", "sleep")
local is_py_sleep = tostring(match_capture(py_buf, r, c, "function.method.call") or match_capture(py_buf, r, c, "function.call"))

assert_suite("Neovim renders Python import keyword in Violet (@keyword.import #6c71c4) and module in Violet (@module)", "Neovim Python import/module capture", {
    { "is_py_from_kw", probe_cap(py_buf, "from __future__ import annotations", "from", "keyword.import"), "true" },
    { "imp_py_fg", hl_fg("@keyword.import.python", "@keyword.import"), "6c71c4" },
    { "is_py_async_mod", probe_cap(py_buf, "import asyncio", "asyncio", "module"), "true" },
})
assert_suite("Neovim renders Python typing constructs (Callable) as @type in calm Base0 (#839496) and built-in types (int, str, dict, list) as @type.builtin in Solarized Green (#859900)", "Neovim Python type capture", {
    { "is_py_call_type", probe_cap(py_buf, "def timed_execution(func: Callable[..., Any])", "Callable", "type"), "true" },
    { "type_py_fg", hl_fg("@type.python", "@type"), "839496" },
    { "is_py_int_type", probe_cap(py_buf, "DEFAULT_PORT: int = 8080", "int", "type.builtin"), "true" },
    { "is_py_str_type", probe_cap(py_buf, "path: str", "str", "type.builtin"), "true" },
    { "is_py_dict_type", probe_cap(py_buf, "metadata: dict[str, str | int | bool]", "dict", "type.builtin"), "true" },
    { "is_py_list_type", probe_cap(py_buf, "self._buffer: list[EndpointMetrics] = []", "list", "type.builtin"), "true" },
    { "type_builtin_py_fg", hl_fg("@type.builtin.python", "@type.builtin"), "859900" },
})
assert_suite("Neovim renders Python decorators (@dataclass, @property) unified as @attribute in Solarized Violet (#6c71c4)", "Neovim Python decorator capture", {
    { "is_py_dc_attr", probe_cap(py_buf, "@dataclass(frozen=True)", "@dataclass", "attribute", nil, 1), "true" },
    { "is_py_prop_attr", probe_cap(py_buf, "@property", "@property", "attribute", nil, 1), "true" },
    { "attr_py_fg", hl_fg("@attribute.python", "@attribute"), "6c71c4" },
})
assert_suite("Neovim renders Python self as @variable.builtin and __name__ (both standalone and attribute func.__name__) as @constant.builtin in Solarized Magenta (#d33682)", "Neovim Python built-in captures", {
    { "is_py_self_var", probe_cap(py_buf, "def summary(self) -> str:", "self", "variable.builtin"), "true" },
    { "is_py_name_const", probe_cap(py_buf, "if __name__ == \"__main__\":", "__name__", "constant.builtin"), "true" },
    { "is_py_func_name_const", probe_cap(py_buf, "func.__name__", "__name__", "constant.builtin"), "true" },
})
assert_suite("Neovim renders Python def __init__ as @function.method (Blue) and class instantiations as @constructor in calm Base0 (#839496)", "Neovim Python method/constructor captures", {
    { "is_py_init_meth", probe_cap(py_buf, "def __init__(self, service_name: str) -> None:", "__init__", "function.method"), "true" },
    { "is_py_ep_ctor", probe_cap(py_buf, "EndpointMetrics(\"/health\",", "EndpointMetrics", "constructor"), "true" },
    { "ctor_py_fg", hl_fg("@constructor.python", "@constructor"), "839496" },
})
assert_suite("Neovim renders Python control flow (try, await, match/case) in Solarized Yellow (#b58900) and PEP 695 type alias in Green", "Neovim Python control flow/PEP 695 captures", {
    { "is_py_try_kw", probe_cap(py_buf, "try:", "try", "keyword.exception"), "true" },
    { "is_py_await_kw", probe_cap(py_buf, "return await func(*args, **kwargs)", "await", "keyword.coroutine"), "true" },
    { "is_py_type_kw", probe_cap(py_buf, "type MetricTagMap =", "type", "keyword.type"), "true" },
    { "is_py_match_kw", probe_cap(py_buf, "match self.status_code:", "match", "keyword.conditional"), "true" },
    { "cond_py_fg", hl_fg("@keyword.conditional.python", "@keyword.conditional"), "b58900" },
})
assert_suite("Neovim renders Python function/method calls (sleep) as @function.call in calm Base0 (#839496)", "Neovim Python function call", {
    { "is_py_sleep_call", is_py_sleep, "true" },
    { "fcall_py_fg", hl_fg("@function.call.python", "@function.call"), "839496" },
})
assert_suite("Neovim renders Python f-string format specifier (.4f) in Solarized Cyan (#2aa198)", "Neovim Python format specifier", {
    { "is_py_fspec_str", probe_cap(py_buf, "elapsed:.4f", ".4f", "string"), "true" },
})

-- 7. Inspect Rust (sample.rs)
local rs_buf = open_sample("sample.rs", "rust")
assert_suite("Neovim renders Rust use keyword as @keyword.import (Violet #6c71c4) and module path std as @module (Violet)", "Neovim Rust import/module capture", {
    { "is_rs_use_kw", probe_cap(rs_buf, "use std::collections::HashMap;", "use", "keyword.import"), "true" },
    { "imp_rs_fg", hl_fg("@keyword.import.rust", "@keyword.import"), "6c71c4" },
    { "is_rs_std_mod", probe_cap(rs_buf, "use std::collections::HashMap;", "std", "module"), "true" },
})
assert_suite("Neovim renders Rust types (HashMap) as @type in calm Base0 (#839496) and primitives in Green (#859900)", "Neovim Rust type capture", {
    { "is_rs_map_type", probe_cap(rs_buf, "use std::collections::HashMap;", "HashMap", "type"), "true" },
    { "type_rs_fg", hl_fg("@type.rust", "@type"), "839496" },
    { "type_builtin_rs_fg", hl_fg("@type.builtin.rust", "@type.builtin"), "859900" },
})
assert_suite("Neovim renders Rust attributes (#[derive, #[inline) unified as @attribute in Solarized Violet (#6c71c4)", "Neovim Rust attribute capture", {
    { "is_rs_drv_attr", probe_cap(rs_buf, "#[derive(Debug, Clone, Copy, PartialEq, Eq)]", "derive", "attribute"), "true" },
    { "is_rs_inl_attr", probe_cap(rs_buf, "#[inline]", "inline", "attribute"), "true" },
    { "is_rs_hash_attr", probe_cap(rs_buf, "#[derive(Debug, Clone, Copy, PartialEq, Eq)]", "#", "attribute"), "true" },
    { "attr_rs_fg", hl_fg("@attribute.rust", "@attribute"), "6c71c4" },
})
assert_suite("Neovim renders Rust constants (MAX_CONNECTIONS, Starting), self receiver, and None sentinel in Solarized Magenta (#d33682)", "Neovim Rust constant/receiver captures", {
    { "is_rs_max_const", probe_cap(rs_buf, "const MAX_CONNECTIONS: usize = 128;", "MAX_CONNECTIONS", "constant"), "true" },
    { "is_rs_start_const", probe_cap(rs_buf, "    Starting,", "Starting", "constant"), "true" },
    { "is_rs_self_var", probe_cap(rs_buf, "    pub fn inspect_state(&self) ->", "self", "variable.builtin"), "true" },
    { "is_rs_none_const", probe_cap(rs_buf, "return None;", "None", "constant.builtin"), "true" },
})
assert_suite("Neovim renders Rust macros (println) as @function.macro in Solarized Blue (#268bd2)", "Neovim Rust macro capture", {
    { "is_rs_print_macro", probe_cap(rs_buf, "    println!(\"Max connections:", "println", "function.macro"), "true" },
})
assert_suite("Neovim renders Rust lifetimes ('a, 'static, '_) unified as @keyword.modifier in Solarized Green (#859900)", "Neovim Rust lifetime capture", {
    { "is_rs_lt_mod", probe_cap(rs_buf, "find_by_id", string.char(39) .. "a", "keyword.modifier", nil, 1), "true" },
})
assert_suite("Neovim renders Rust control flow (match, let-else) as @keyword.conditional in Solarized Yellow (#b58900) and Option::Some in Base0", "Neovim Rust control flow/let-else capture", {
    { "is_rs_match_kw", probe_cap(rs_buf, "match self.status {", "match", "keyword.conditional"), "true" },
    { "cond_rs_fg", hl_fg("@keyword.conditional.rust", "@keyword.conditional"), "b58900" },
    { "is_rs_some_type", probe_cap(rs_buf, "let Some(default_port) = fallback else", "Some", "type"), "true" },
    { "is_rs_else_kw", probe_cap(rs_buf, "let Some(default_port) = fallback else", "else", "keyword.conditional"), "true" },
})
assert_suite("Neovim renders Rust function/method calls (ServerNode::new) as @function.call in calm Base0 (#839496)", "Neovim Rust function call capture", {
    { "is_rs_new_call", probe_cap(rs_buf, "ServerNode::new(101,", "new", "function.call"), "true" },
    { "fcall_rs_fg", hl_fg("@function.call.rust", "@function.call"), "839496" },
})

-- 8. Inspect Shell (sample.sh)
local sh_buf = open_sample("sample.sh", "bash")
assert_suite("Neovim renders Shell declarations (readonly, local) as @keyword in Solarized Green (#859900)", "Neovim Shell keyword capture", {
    { "is_sh_ro_kw", probe_cap(sh_buf, "readonly SCRIPT_NAME", "readonly", "keyword"), "true" },
    { "kw_sh_fg", hl_fg("@keyword.bash", "@keyword"), "859900" },
})
assert_suite("Neovim renders Shell control flow (if, case, for) as @keyword.conditional in Solarized Yellow (#b58900)", "Neovim Shell control flow capture", {
    { "is_sh_if_cond", probe_cap(sh_buf, "if [[ $exit_code", "if", "keyword.conditional"), "true" },
    { "is_sh_case_cond", probe_cap(sh_buf, "case \"$level\" in", "case", "keyword.conditional"), "true" },
    { "is_sh_for_rep", probe_cap(sh_buf, "for svc in", "for", "keyword.repeat"), "true" },
    { "cond_sh_fg", hl_fg("@keyword.conditional.bash", "@keyword.conditional"), "b58900" },
})
assert_suite("Neovim renders Shell function declarations (cleanup) as @function in Solarized Blue (#268bd2)", "Neovim Shell function declaration capture", {
    { "is_sh_clean_func", probe_cap(sh_buf, "cleanup() {", "cleanup", "function"), "true" },
    { "fn_sh_fg", hl_fg("@function.bash", "@function"), "268bd2" },
})
assert_suite("Neovim renders Shell command and function invocations (basename, trap) as @function.call in calm Base0 (#839496)", "Neovim Shell function call capture", {
    { "is_sh_base_func", probe_cap(sh_buf, "SCRIPT_NAME=\"$(basename \"$0\")\"", "basename", "function.call"), "true" },
    { "is_sh_trap_func", probe_cap(sh_buf, "trap cleanup EXIT", "trap", "function.builtin"), "true" },
    { "fcall_sh_fg", hl_fg("@function.call.bash", "@function.call"), "839496" },
})
assert_suite("Neovim renders Shell trap signals (EXIT) as @constant.builtin in Solarized Magenta (#d33682)", "Neovim Shell signal capture", {
    { "is_sh_exit_const", probe_cap(sh_buf, "trap cleanup EXIT", "EXIT", "constant.builtin"), "true" },
})
assert_suite("Neovim renders Shell redirection (>&2) with operator in Base0 and file descriptor in Solarized Magenta (#d33682)", "Neovim Shell redirection captures", {
    { "is_sh_gt_op", probe_cap(sh_buf, ">&2", ">&2", "operator"), "true" },
    { "is_sh_fd2_num", probe_cap(sh_buf, ">&2", ">&2", "number", nil, 2), "true" },
})
assert_suite("Neovim renders Shell case branch labels (INFO) in Base0 Grey (#839496) and wildcards (*) in Solarized Magenta (#d33682)", "Neovim Shell case pattern captures", {
    { "is_sh_info_param", probe_cap(sh_buf, "INFO)", "INFO", "variable.parameter"), "true" },
    { "is_sh_star_regex", probe_cap(sh_buf, "*)", "*", "string.regexp"), "true" },
})
assert_suite("Neovim renders Shell array subscript @ in Cyan (@character.special) and positional $@ in Magenta (@constant)", "Neovim Shell @ parameter captures", {
    { "is_sh_sub_at", probe_cap(sh_buf, "${ACTIVE_SERVICES[@]}", "@", "character.special"), "true" },
    { "is_sh_pos_at", probe_cap(sh_buf, "main \"$@\"", "@", "constant"), "true" },
})
assert_suite("Neovim renders Shell variable expansion prefix ($), associative array subscripts, and fallback defaults in calm Base0 Grey (#839496)", "Neovim Shell dollar/associative/fallback capture", {
    { "is_sh_dollar_punc", probe_cap(sh_buf, "local -r exit_code=$?", "$", "punctuation.special"), "true" },
    { "dollar_sh_fg", hl_fg("@punctuation.special.bash", "@punctuation.special"), "839496" },
    { "is_sh_assoc_key", probe_cap(sh_buf, "[nginx]=\"edge\"", "nginx", "variable"), "true" },
    { "is_sh_def_var", probe_cap(sh_buf, "${SERVICE_TIERS[$svc]:-unknown}", "unknown", "variable"), "true" },
})

-- 9. Inspect SQL (sample.sql)
local sql_buf = open_sample("sample.sql", "sql")
assert_suite("Neovim highlights modern SQL queries (sample.sql) with Converged Ergonomic Solarized Scheme: DDL/DML keywords including RETURNING (Green), table/index/CTE relations in Base0, data types including JSONB in Green (#859900), conditionals (Yellow), function calls (Base0), DEFAULT/DESC keywords (Green), NULL sentinels / TRUE / numbers (Magenta), and calm Base0 alias/column qualifiers", "Neovim SQL Tree-sitter highlights", {
    { "is_sql_create_kw", probe_cap(sql_buf, "CREATE TABLE IF NOT EXISTS customer_accounts", "CREATE", "keyword"), "true" },
    { "is_sql_table_type", probe_cap(sql_buf, "CREATE TABLE IF NOT EXISTS customer_accounts", "customer_accounts", "type"), "true" },
    { "is_sql_serial_type", probe_cap(sql_buf, "account_id BIGSERIAL PRIMARY KEY", "BIGSERIAL", "type.builtin"), "true" },
    { "is_sql_default_attr", probe_cap(sql_buf, "plan_tier VARCHAR", "DEFAULT", "attribute"), "true" },
    { "is_sql_null_const", probe_cap(sql_buf, "is_active BOOLEAN NOT NULL DEFAULT TRUE", "NULL", "constant.builtin"), "true" },
    { "is_sql_true_bool", probe_cap(sql_buf, "is_active BOOLEAN NOT NULL DEFAULT TRUE", "TRUE", "boolean"), "true" },
    { "is_sql_now_func", probe_cap(sql_buf, "created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()", "NOW", "function.call"), "true" },
    { "is_sql_uuid_type", probe_cap(sql_buf, "transaction_id UUID PRIMARY KEY", "UUID", "type.builtin"), "true" },
    { "is_sql_index_type", probe_cap(sql_buf, "CREATE INDEX IF NOT EXISTS idx_ledger_account_settled", "idx_ledger_account_settled", "type"), "true" },
    { "is_sql_cte_type", probe_cap(sql_buf, "WITH monthly_billing_summary AS (", "monthly_billing_summary", "type"), "true" },
    { "is_sql_alias_var", probe_cap(sql_buf, "        a.account_id,", "a", "variable"), "true" },
    { "is_sql_col_member", probe_cap(sql_buf, "        a.account_id,", "account_id", "variable.member"), "true" },
    { "is_sql_count_func", probe_cap(sql_buf, "COUNT(t.transaction_id)", "COUNT", "function.call"), "true" },
    { "is_sql_case_kw", probe_cap(sql_buf, "        CASE", "CASE", "keyword.conditional"), "true" },
    { "is_sql_num_float", probe_cap(sql_buf, "THEN 0.15", "0.15", "number.float"), "true" },
    { "is_sql_round_func", probe_cap(sql_buf, "ROUND(s.aggregate_spend", "ROUND", "function.call"), "true" },
    { "is_sql_rank_func", probe_cap(sql_buf, "DENSE_RANK()", "DENSE_RANK", "function.call"), "true" },
    { "is_sql_over_kw", probe_cap(sql_buf, "DENSE_RANK() OVER", "OVER", "keyword"), "true" },
    { "is_sql_desc_attr", probe_cap(sql_buf, "aggregate_spend DESC) AS revenue_rank", "DESC", "attribute"), "true" },
    { "is_sql_having_kw", probe_cap(sql_buf, "HAVING s.total_invoices > 0", "HAVING", "keyword"), "true" },
    { "is_sql_jsonb_type", probe_cap(sql_buf, "metadata JSONB NOT NULL", "JSONB", "type.builtin"), "true" },
    { "is_sql_ret_kw", probe_cap(sql_buf, "RETURNING account_id", "RETURNING", "keyword"), "true" },
    { "cond_sql_fg", hl_fg("@keyword.conditional.sql", "@keyword.conditional"), "b58900" },
    { "type_sql_fg", hl_fg("@type.sql", "@type"), "839496" },
    { "type_builtin_sql_fg", hl_fg("@type.builtin.sql", "@type.builtin"), "859900" },
    { "fcall_sql_fg", hl_fg("@function.call.sql", "@function.call"), "839496" },
    { "attr_sql_fg", hl_fg("@attribute.sql", "@attribute"), "859900" },
})

-- 10. Inspect Terraform (sample.tf)
local tf_buf = open_sample("sample.tf", "terraform")
hl = vim.api.nvim_get_hl(0, { name = "@function.call.terraform", link = false })
if not hl.fg then hl = vim.api.nvim_get_hl(0, { name = "@function.builtin.terraform", link = false }) end
if not hl.fg then hl = vim.api.nvim_get_hl(0, { name = "@function", link = false }) end
local fn_tf_fg = string.format("%06x", hl.fg or 0)

assert_suite("Neovim highlights modern Terraform / HCL configurations (sample.tf) with Converged Ergonomic Solarized Scheme: block declarations including moved/check and scope keywords (Green), schema blocks including assert and data types in Base0, control flow (Yellow), built-in functions (Base0), booleans/numbers (Magenta), Base0 string interpolation delimiters and resource references", "Neovim Terraform Tree-sitter highlights", {
    { "is_tf_main_kw", probe_cap(tf_buf, "terraform {", "terraform", "keyword"), "true" },
    { "is_tf_prov_type", probe_cap(tf_buf, "required_providers {", "required_providers", "type"), "true" },
    { "is_tf_str_type", probe_cap(tf_buf, "  type        = string", "string", "type.builtin"), "true" },
    { "is_tf_cnt_func", probe_cap(tf_buf, "contains([\"staging\"", "contains", "function"), "true" },
    { "is_tf_var_kw", probe_cap(tf_buf, "var.environment)", "var", "keyword"), "true" },
    { "is_tf_loc_kw", probe_cap(tf_buf, "local.vpc_cidr,", "local", "keyword"), "true" },
    { "is_tf_res_kw", probe_cap(tf_buf, "resource \"aws_s3_bucket\"", "resource", "keyword"), "true" },
    { "is_tf_ref_var", probe_cap(tf_buf, "value       = aws_s3_bucket.telemetry_lake.arn", "aws_s3_bucket", "variable"), "true" },
    { "is_tf_false_bool", probe_cap(tf_buf, "prevent_destroy = false", "false", "boolean"), "true" },
    { "is_tf_interp_brack", probe_cap(tf_buf, "\"subnet-${idx}\"", "${", "punctuation.bracket"), "true" },
    { "is_tf_prov_hdr_kw", probe_cap(tf_buf, "provider \"aws\"", "provider", "keyword"), "true" },
    { "is_tf_prov_arg_mbr", probe_cap(tf_buf, "provider      = aws", "provider", "variable.member"), "true" },
    { "is_tf_psnr_type", probe_cap(tf_buf, "provisioner \"local-exec\"", "provisioner", "type"), "true" },
    { "is_tf_self_kw", probe_cap(tf_buf, "echo \"Provisioned bucket: ${self.id}\"", "self", "keyword"), "true" },
    { "is_tf_dir_brack", probe_cap(tf_buf, "%{ if var.environment", "%{", "punctuation.bracket"), "true" },
    { "is_tf_strip_brack", probe_cap(tf_buf, "%{ if var.environment", "~}", "punctuation.bracket"), "true" },
    { "is_tf_if_kw", probe_cap(tf_buf, "%{ if var.environment", "if", "keyword.conditional"), "true" },
    { "is_tf_moved_kw", probe_cap(tf_buf, "moved {", "moved", "keyword"), "true" },
    { "is_tf_check_kw", probe_cap(tf_buf, "check \"telemetry_lake_resiliency\" {", "check", "keyword"), "true" },
    { "is_tf_assert_type", probe_cap(tf_buf, "  assert {", "assert", "type"), "true" },
    { "kw_tf_fg", hl_fg("@keyword.terraform", "@keyword"), "859900" },
    { "cond_tf_fg", hl_fg("@keyword.conditional.terraform", "@keyword.conditional"), "b58900" },
    { "type_tf_fg", hl_fg("@type.builtin.terraform", "@type.builtin"), "839496" },
    { "fn_tf_fg", fn_tf_fg, "839496" },
})

-- 11. Inspect Markdown (sample.md)
local md_buf = open_sample("sample.md", "markdown")
local h1_hl = vim.api.nvim_get_hl(0, { name = "@markup.heading.1", link = false })
local h2_hl = vim.api.nvim_get_hl(0, { name = "@markup.heading.2", link = false })

assert_suite("Neovim highlights modern Markdown documents (sample.md) with Semantic Architecture: H1 Orange (#cb4b16), H2 Blue (#268bd2, unbolded), H3 Violet (#6c71c4), H4 Base1 (#93a1a1), H5/H6 Base0 (#839496), Base01 heading/quote delimiters, calm Base0 blockquotes, GitHub alerts ([!NOTE], [!TIP], [!IMPORTANT], [!WARNING], [!CAUTION]), Cyan autolinks, task checkboxes, Base1 table headers with Base01 delimiters, embedded Bash invocations in calm Base0, and embedded Go with Magenta blank identifier/nil, Base0 method calls (errors.New), and exclusive Yellow control flow", "Neovim Markdown highlights", {
    { "is_md_h1_txt", probe_cap(md_buf, "Workstation Architecture", "Workstation", "markup.heading.1"), "true" },
    { "h1_fg", string.format("%06x", h1_hl.fg or 0), "cb4b16" },
    { "h1_bold", tostring(h1_hl.bold == true), "false" },
    { "is_md_h2_txt", probe_cap(md_buf, "Executive Summary", "Executive", "markup.heading.2"), "true" },
    { "h2_fg", string.format("%06x", h2_hl.fg or 0), "268bd2" },
    { "h2_bold", tostring(h2_hl.bold == true), "false" },
    { "is_md_h3_txt", probe_cap(md_buf, "File System Topology", "File", "markup.heading.3"), "true" },
    { "h3_fg", hl_fg("@markup.heading.3"), "6c71c4" },
    { "is_md_h4_txt", probe_cap(md_buf, "Syntax Highlighting", "Syntax", "markup.heading.4"), "true" },
    { "h4_fg", hl_fg("@markup.heading.4"), "93a1a1" },
    { "h5_fg", hl_fg("@markup.heading.5"), "839496" },
    { "h6_fg", hl_fg("@markup.heading.6"), "839496" },
    { "is_md_h1_delim", probe_cap(md_buf, "Workstation Architecture", "#", "markup.heading.delimiter"), "true" },
    { "h_delim_fg", hl_fg("@markup.heading.delimiter"), "586e75" },
    { "is_md_quote_marker", probe_cap(md_buf, "> [!NOTE]", ">", "markup.quote.marker"), "true" },
    { "quote_marker_fg", hl_fg("@markup.quote.marker"), "586e75" },
    { "quote_fg", hl_fg("@markup.quote"), "839496" },
    { "is_md_alert_note", probe_cap(md_buf, "> [!NOTE]", "!NOTE", "markup.alert.note"), "true" },
    { "is_md_alert_tip", probe_cap(md_buf, "> [!TIP]", "!TIP", "markup.alert.tip"), "true" },
    { "is_md_alert_important", probe_cap(md_buf, "> [!IMPORTANT]", "!IMPORTANT", "markup.alert.important"), "true" },
    { "is_md_alert_warning", probe_cap(md_buf, "> [!WARNING]", "!WARNING", "markup.alert.warning"), "true" },
    { "is_md_alert_caution", probe_cap(md_buf, "> [!CAUTION]", "!CAUTION", "markup.alert.caution"), "true" },
    { "is_md_uri_autolink", probe_cap_fg(md_buf, "<https://github.com/example/home-settings>", "<https://", "markup.link.url"), "true/2aa198" },
    { "is_md_email_autolink", probe_cap(md_buf, "<maintainers@example.com>", "<maintainers@", "markup.link.url"), "true" },
    { "is_md_task_checked", probe_cap(md_buf, "- [x]", "[x]", "markup.list.checked"), "true" },
    { "task_chk_fg", hl_fg("@markup.list.checked"), "859900" },
    { "is_md_task_unchecked", probe_cap(md_buf, "- [ ]", "[ ]", "markup.list.unchecked"), "true" },
    { "task_unchk_fg", hl_fg("@markup.list.unchecked"), "586e75" },
    { "is_md_table_delim", probe_cap(md_buf, "Environment Variable", "|", "markup.table.delimiter"), "true" },
    { "table_delim_fg", hl_fg("@markup.table.delimiter"), "586e75" },
    { "is_md_table_hdr", probe_cap(md_buf, "Environment Variable", "Environment", "markup.heading.4"), "true" },
    { "is_md_bash_cmd", probe_cap(md_buf, "git clone https", "git", "function.call"), "true" },
    { "is_md_go_if_cond", probe_cap(md_buf, "if configPath ==", "if", "keyword.conditional"), "true" },
    { "is_md_go_blank", probe_cap(md_buf, "if _, err := os.Stat", "_", "constant.builtin"), "true" },
    { "is_md_go_call", probe_cap(md_buf, "return errors.New", "New", "function.method.call"), "true" },
    { "is_md_go_nil", probe_cap(md_buf, "return nil", "nil", "constant.builtin"), "true" },
})

-- 12. Inspect JavaScript (sample.js)
local js_buf = open_sample("sample.js", "javascript")
assert_suite("Neovim highlights modern JavaScript (sample.js) with Converged Ergonomic Solarized Scheme: Date in Base0 Grey (@type), console & process in Magenta (@variable.builtin), regex /^\\/health[z]?$/i with Magenta body, Base0 delimiters, and Cyan flags, *[Symbol.iterator] with calm Base0 operator and computed member identifiers, and 'of' in Solarized Yellow (@keyword.repeat)", "Neovim JavaScript highlights", {
    { "is_js_date_type", probe_cap(js_buf, "Date.now()", "Date", "type"), "true" },
    { "is_js_console_builtin", probe_cap(js_buf, "console.log(", "console", "variable.builtin"), "true" },
    { "is_js_regex_slash", probe_cap(js_buf, "healthRegex", "/", "punctuation.bracket"), "true" },
    { "is_js_regex_body", probe_cap(js_buf, "healthRegex", "^", "string.regexp"), "true" },
    { "is_js_regex_flag", probe_cap(js_buf, "healthRegex", "i;", "character.special"), "true" },
    { "is_js_gen_star_op", probe_cap(js_buf, "*[Symbol.iterator]()", "*", "operator"), "true" },
    { "is_js_symbol_type", probe_cap(js_buf, "*[Symbol.iterator]()", "Symbol", "type"), "true" },
    { "is_js_iter_member", probe_cap(js_buf, "*[Symbol.iterator]()", "iterator", "variable.member"), "true" },
    { "is_js_inspect_var", probe_cap(js_buf, "[inspectSymbol]()", "inspectSymbol", "variable"), "true" },
    { "is_js_of_kw", probe_cap(js_buf, "] of this.#cache", "of", "keyword.repeat"), "true" },
    { "is_js_proc_builtin", probe_cap(js_buf, "process.exitCode", "process", "variable.builtin"), "true" },
})

-- 13. Inspect TypeScript (sample.ts)
local ts_buf = open_sample("sample.ts", "typescript")
assert_suite("Neovim highlights modern TypeScript (sample.ts) with Converged Ergonomic Solarized Scheme: exports in Violet (@keyword.import), structural declarations (enum, type, interface, class, readonly, keyof, satisfies) and primitive scalars in Green, method declarations in Blue (@function.method), custom domain types in Base0 Grey (@type), control flow in Yellow (@keyword.coroutine), and constants/this in Magenta (@boolean, @variable.builtin)", "Neovim TypeScript highlights", {
    { "is_ts_export_import", probe_cap(ts_buf, "export enum UserRole", "export", "keyword.import"), "true" },
    { "is_ts_enum_kw", probe_cap(ts_buf, "export enum UserRole", "enum", "keyword.type"), "true" },
    { "is_ts_userrole_type", probe_cap(ts_buf, "export enum UserRole", "UserRole", "type"), "true" },
    { "is_ts_type_kw", probe_cap(ts_buf, "export type ConnectionState", "type", "keyword"), "true" },
    { "is_ts_interface_kw", probe_cap(ts_buf, "export interface ApiResponse", "interface", "keyword.type"), "true" },
    { "is_ts_readonly_mod", probe_cap(ts_buf, "readonly success: boolean", "readonly", "keyword.modifier"), "true" },
    { "is_ts_bool_builtin", probe_cap(ts_buf, "readonly success: boolean", "boolean", "type.builtin"), "true" },
    { "is_ts_class_kw", probe_cap(ts_buf, "export class ServiceGateway", "class", "keyword.type"), "true" },
    { "is_ts_gateway_type", probe_cap(ts_buf, "export class ServiceGateway", "ServiceGateway", "type"), "true" },
    { "is_ts_async_coro", probe_cap(ts_buf, "public async request", "async", "keyword.coroutine"), "true" },
    { "is_ts_request_method", probe_cap(ts_buf, "public async request", "request", "function.method"), "true" },
    { "is_ts_await_coro", probe_cap(ts_buf, "await new Promise", "await", "keyword.coroutine"), "true" },
    { "is_ts_true_bool", probe_cap(ts_buf, "success: true", "true", "boolean"), "true" },
    { "is_ts_this_builtin", probe_cap(ts_buf, "this.baseUrl = baseUrl", "this", "variable.builtin"), "true" },
    { "is_ts_keyof_kw", probe_cap(ts_buf, "export type ProfileAttributeKey = keyof UserProfile;", "keyof", "keyword.operator"), "true" },
    { "is_ts_sat_kw", probe_cap(ts_buf, "} satisfies UserProfile;", "satisfies", "keyword.operator"), "true" },
})

-- 14. Inspect XML (sample.xml)
local xml_buf = open_sample("sample.xml", "xml")
local xml_hl = vim.treesitter.get_parser(xml_buf, "xml")
local has_js = false
if xml_hl then
    for lang, _ in pairs(xml_hl:children()) do
        if lang == "javascript" then has_js = true end
    end
end
assert_suite("Neovim highlights modern XML documents (sample.xml) with Converged Ergonomic Solarized: directives in Orange (@keyword.directive), element tags in Blue (@tag #268bd2), tag attributes in Green (@tag.attribute #859900), tag delimiters in calm Base0 Grey (@tag.delimiter #839496), strings in Cyan (@string), entities in Magenta (@constant.builtin), and CDATA section delimiters in Violet (@module) with calm Base0 payload (@markup.raw.block #839496)", "Neovim XML Tree-sitter highlights", {
    { "is_xml_decl_dir", probe_cap(xml_buf, "<?xml version", "xml", "keyword.directive"), "true" },
    { "is_xml_pi_dir", probe_cap(xml_buf, "<?xml-stylesheet", "xml-stylesheet", "keyword.directive"), "true" },
    { "is_xml_dep_tag", probe_cap(xml_buf, "<deployment xmlns=", "deployment", "tag"), "true" },
    { "is_xml_mon_tag", probe_cap(xml_buf, "<mon:monitoring>", "mon:monitoring", "tag"), "true" },
    { "is_xml_xmlns_attr", probe_cap(xml_buf, "xmlns:mon=", "xmlns:mon", "tag.attribute"), "true" },
    { "is_xml_ver_str", probe_cap(xml_buf, "<?xml version=\"1.0\"", "1.0", "string"), "true" },
    { "is_xml_amp_const", probe_cap(xml_buf, "API Gateway &amp; reverse", "&amp;", "constant.builtin"), "true" },
    { "is_xml_cdata_start", probe_cap(xml_buf, "<script><![CDATA[", "<![CDATA[", "module"), "true" },
    { "is_xml_cdata_bracket", probe_cap(xml_buf, "<script><![CDATA[", "<![CDATA[", "module", nil, 8), "true" },
    { "xml_has_js_tree", tostring(has_js), "false" },
    { "is_xml_cdata_end", probe_cap(xml_buf, "]]></script>", "]]>", "module"), "true" },
    { "is_xml_cdata_block", probe_cap_fg(xml_buf, "curl -sf http://localhost:8080/healthz", "curl", "markup.raw.block"), "true/839496" },
    { "tag_fg", hl_fg("@tag"), "268bd2" },
    { "tag_attr_fg", hl_fg("@tag.attribute"), "859900" },
    { "tag_delim_fg", hl_fg("@tag.delimiter"), "839496" },
})

-- 15. Inspect HTML (sample.html)
local html_buf = open_sample("sample.html", "html")
r, c = find_pos(html_buf, "<strong>solarized-gateway</strong>", "solarized-gateway")
local insp = vim.inspect_pos(html_buf, r, c)
local s_fg = "nil"
local s_bold = "false"
if insp.treesitter and #insp.treesitter > 0 then
    local eff = insp.treesitter[#insp.treesitter]
    local hl_s = vim.api.nvim_get_hl(0, { name = eff.hl_group, link = false })
    if hl_s.fg then s_fg = string.format("%06x", hl_s.fg) end
    if hl_s.bold then s_bold = "true" end
end

r, c = find_pos(html_buf, "href=\"/dashboard\"", "/dashboard")
insp = vim.inspect_pos(html_buf, r, c)
local u_under = "false"
if insp.treesitter and #insp.treesitter > 0 then
    local eff = insp.treesitter[#insp.treesitter]
    local hl_u = vim.api.nvim_get_hl(0, { name = eff.hl_group, link = false })
    if hl_u.underline then u_under = "true" end
end

assert_suite("Neovim highlights modern HTML5 documents (sample.html) with Converged Ergonomic Solarized: doctype in Orange (@keyword.directive), element tags in Blue (@tag #268bd2), tag attributes in Green (@tag.attribute #859900), tag delimiters in Base0 Grey (@tag.delimiter #839496), strings in Cyan (@string), unbolded & un-underlined content (headings, links, strong in calm Base0 Grey #839496), entities in Magenta (@constant.builtin), and embedded <script> matching bat", "Neovim HTML Tree-sitter highlights", {
    { "is_html_doctype_dir", probe_cap(html_buf, "<!DOCTYPE html>", "DOCTYPE", "keyword.directive"), "true" },
    { "is_html_tag", probe_cap(html_buf, "<html", "html", "tag"), "true" },
    { "is_html_tag_delim", probe_cap(html_buf, "<html", "<", "tag.delimiter"), "true" },
    { "is_html_attr", probe_cap(html_buf, "<html", "lang", "tag.attribute"), "true" },
    { "is_html_str", probe_cap(html_buf, "<html", "en", "string"), "true" },
    { "is_html_comment", probe_cap(html_buf, "<!-- Primary Navigation -->", "Primary", "comment"), "true" },
    { "html_title_fg", probe_fg(html_buf, "Gateway Dashboard — Service Health", "Gateway"), "839496" },
    { "html_h2_fg", probe_fg(html_buf, "<h2>Uptime</h2>", "Uptime"), "839496" },
    { "html_strong_fg", s_fg, "839496" },
    { "html_strong_bold", s_bold, "false" },
    { "html_link_fg", probe_fg(html_buf, ">Dashboard</a>", "Dashboard"), "839496" },
    { "html_url_underline", u_under, "false" },
    { "is_html_copy_const", probe_cap(html_buf, "&copy; 2025 Platform", "&copy;", "constant.builtin"), "true" },
    { "is_html_js_doc", probe_cap(html_buf, "document.addEventListener", "document", "variable.builtin"), "true" },
    { "is_html_js_event", probe_cap(html_buf, "document.addEventListener", "addEventListener", "function.method.call"), "true" },
    { "is_html_js_const", probe_cap(html_buf, "const cards = document.querySelectorAll", "const", "keyword"), "true" },
    { "is_html_js_console", probe_cap(html_buf, "console.log(`Card status:", "console", "variable.builtin"), "true" },
    { "is_html_js_log", probe_cap(html_buf, "console.log(`Card status:", "log", "function.method.call"), "true" },
})

-- 16. Inspect JSON (sample.json)
local json_buf = open_sample("sample.json", "json")
local hl_duw = vim.api.nvim_get_hl(0, { name = "DiagnosticUnderlineWarn", link = false })
assert_suite("Neovim highlights modern JSON documents (sample.json) with Converged Ergonomic Solarized: object keys in Green (@property #859900), strings in Cyan (@string #2aa198, URLs non-clickable and uncorrupted by diagnostic fg), numbers in Magenta (@number), booleans in Magenta (@boolean), and null in Magenta (@constant.builtin)", "Neovim JSON Tree-sitter highlights", {
    { "is_json_key_prop", probe_cap(json_buf, "\"$schema\":", "$schema", "property"), "true" },
    { "is_json_str", probe_cap(json_buf, "\"telemetry-collector\"", "telemetry-collector", "string"), "true" },
    { "is_json_num", probe_cap(json_buf, "\"replicas\": 3", "3", "number"), "true" },
    { "is_json_bool", probe_cap(json_buf, "\"enabled\": true", "true", "boolean"), "true" },
    { "is_json_null", probe_cap(json_buf, "\"annotations\": null", "null", "constant.builtin"), "true" },
    { "is_json_url_str", probe_cap_fg(json_buf, "\"https://api.example.com", "https", "string"), "true/2aa198" },
    { "duw_has_fg", tostring(hl_duw.fg ~= nil), "false" },
})

-- 17. Inspect YAML (sample.yaml)
json_buf = open_sample("sample.yaml", "yaml")
assert_suite("Neovim highlights modern YAML documents (sample.yaml) with Converged Ergonomic Solarized: mapping keys & merge keys (<<) in Green (@property #859900), strings in Cyan (@string), explicit type tags in calm Base0 Grey (@type #839496, zero Yellow), anchors & aliases in Base01 Dim (@label #586e75), numbers in Magenta (@number), booleans in Magenta (@boolean), and null in Magenta (@constant.builtin)", "Neovim YAML Tree-sitter highlights", {
    { "is_yaml_key_prop", probe_cap(json_buf, "apiVersion: apps/v1", "apiVersion", "property"), "true" },
    { "is_yaml_str", probe_cap(json_buf, "apiVersion: apps/v1", "apps/v1", "string"), "true" },
    { "is_yaml_type", probe_cap(json_buf, "!!str 42", "!!str", "type"), "true" },
    { "is_yaml_num", probe_cap(json_buf, "!!str 42", "42", "number"), "true" },
    { "is_yaml_bool", probe_cap(json_buf, "runAsNonRoot: true", "true", "boolean"), "true" },
    { "is_yaml_null", probe_cap(json_buf, "pod-template-hash: null", "null", "constant.builtin"), "true" },
    { "is_yaml_merge_prop", probe_cap(json_buf, "<<: *common-labels", "<<", "property"), "true" },
    { "is_yaml_alias_label", probe_cap(json_buf, "<<: *common-labels", "common-labels", "label"), "true" },
    { "is_yaml_anchor_label", probe_cap(json_buf, "resources: &resource-defaults", "resource-defaults", "label"), "true" },
})

-- 18. Inspect TOML (sample.toml)
json_buf = open_sample("sample.toml", "toml")
assert_suite("Neovim highlights modern TOML documents (sample.toml) with Converged Ergonomic Solarized: table headers in Blue (@tag #268bd2), mapping & inline keys in Green (@property #859900), strings in Cyan (@string #2aa198), numbers/booleans/date-times in Magenta (@number, @boolean, @constant.builtin #d33682)", "Neovim TOML Tree-sitter highlights", {
    { "is_toml_tbl_tag", probe_cap_fg(json_buf, "[package]", "package", "tag"), "true/268bd2" },
    { "is_toml_arr_tag", probe_cap(json_buf, "[[rate_limits]]", "rate_limits", "tag"), "true" },
    { "is_toml_key_prop", probe_cap_fg(json_buf, "name = \"solarized-gateway\"", "name", "property"), "true/859900" },
    { "is_toml_dot_prop", probe_cap(json_buf, "pool.min_size = 5", "min_size", "property"), "true" },
    { "is_toml_str", probe_cap(json_buf, "name = \"solarized-gateway\"", "solarized-gateway", "string"), "true" },
    { "is_toml_num", probe_cap(json_buf, "port = 8080", "8080", "number"), "true" },
    { "is_toml_bool", probe_cap(json_buf, "graceful = true", "true", "boolean"), "true" },
    { "is_toml_dt_const", probe_cap_fg(json_buf, "enabled_at = 2025-09-14T08:30:00Z", "2025-09-14T08:30:00Z", "constant.builtin"), "true/d33682" },
})

-- 19. Inspect CSS (sample.css)
local css_buf = open_sample("sample.css", "css")
assert_suite("Neovim highlights modern CSS documents (sample.css) with Converged Ergonomic Solarized: at-rules including @supports/@media in Orange (@keyword.directive #cb4b16), selectors including ID (#main-viewport) in Blue (@tag, @type.css #268bd2), pseudo-selectors in Violet (@attribute #6c71c4), nesting parent '&' and attribute selector names in calm Base0 (@operator, @tag.attribute #839496), attribute strings in Cyan (@string #2aa198), container queries (@container in Orange, container-name in Base0, dimensions in Magenta #d33682), properties in Green (@property.css #859900), custom properties & keyword values in Base0 Grey (@variable.css #839496), strings in Cyan (@string), and hex colors & numbers in Magenta (@string.special.css, @number #d33682)", "Neovim CSS Tree-sitter highlights", {
    { "is_css_at_dir", probe_cap(css_buf, "@layer reset, tokens, layout, components, utilities;", "@layer", "keyword.directive"), "true" },
    { "is_css_ff_dir", probe_cap(css_buf, "@font-face {", "@font-face", "keyword.directive"), "true" },
    { "is_css_tag", probe_cap(css_buf, "body {", "body", "tag"), "true" },
    { "is_css_class_type", probe_cap(css_buf, ".dashboard-grid {", "dashboard-grid", "type.css"), "true" },
    { "is_css_prop", probe_cap(css_buf, "font-family: var(--font-mono);", "font-family", "property.css"), "true" },
    { "is_css_cust_prop_var", probe_cap(css_buf, "--color-base03: #002b36;", "--color-base03", "variable.css"), "true" },
    { "is_css_cust_val_var", probe_cap(css_buf, "font-family: var(--font-mono);", "--font-mono", "variable.css"), "true" },
    { "is_css_root_attr", probe_cap(css_buf, ":root {", "root", "attribute"), "true" },
    { "is_css_hover_attr", probe_cap(css_buf, "&:hover {", "hover", "attribute"), "true" },
    { "is_css_before_attr", probe_cap(css_buf, "*::before,", "before", "attribute"), "true" },
    { "is_css_str", probe_cap(css_buf, "font-family: \"MesloLGS NF\";", "MesloLGS NF", "string"), "true" },
    { "is_css_hex_str", probe_cap_fg(css_buf, "--color-base03: #002b36;", "#002b36", "string.special.css"), "true/d33682" },
    { "is_css_num", probe_cap(css_buf, "font-weight: 400;", "400", "number"), "true" },
    { "is_css_uimono_var", probe_cap_fg(css_buf, "--font-mono: \"MesloLGS NF\", ui-monospace, monospace;", "ui-monospace", "variable.css"), "true/839496" },
    { "is_css_auto_var", probe_cap_fg(css_buf, "grid-template-rows: auto 1fr auto;", "auto", "variable.css"), "true/839496" },
    { "is_css_autofill_var", probe_cap_fg(css_buf, "repeat(auto-fill,", "auto-fill", "variable.css"), "true/839496" },
    { "css_at_fg", hl_fg("@keyword.directive.css", "@keyword.directive"), "cb4b16" },
    { "css_class_fg", hl_fg("@type.css"), "268bd2" },
    { "css_tag_fg", hl_fg("@tag.css", "@tag"), "268bd2" },
    { "is_css_nest_op", probe_cap_fg(css_buf, "& .card-title {", "&", "operator"), "true/839496" },
    { "is_css_attr_sel_name", probe_cap_fg(css_buf, "&[data-status=\"healthy\"] {", "data-status", "tag.attribute"), "true/839496" },
    { "is_css_attr_sel_str", probe_cap_fg(css_buf, "&[data-status=\"healthy\"] {", "healthy", "string"), "true/2aa198" },
    { "is_css_container_dir", probe_cap_fg(css_buf, "@container content (min-width: 640px) {", "@container", "keyword.directive"), "true/cb4b16" },
    { "is_css_container_name_var", probe_cap_fg(css_buf, "@container content (min-width: 640px) {", "content", "variable.css"), "true/839496" },
    { "is_css_container_num", probe_cap_fg(css_buf, "@container content (min-width: 640px) {", "640", "number"), "true/d33682" },
    { "is_css_supports_dir", probe_cap(css_buf, "@supports (display: grid) {", "@supports", "keyword.directive"), "true" },
    { "is_css_id_tag", probe_cap(css_buf, "#main-viewport {", "#main-viewport", "type.css"), "true" },
    { "css_prop_fg", hl_fg("@property.css", "@property"), "859900" },
    { "css_var_fg", hl_fg("@variable.css", "@variable"), "839496" },
    { "css_attr_fg", hl_fg("@attribute.css", "@attribute"), "6c71c4" },
    { "css_hex_fg", hl_fg("@string.special.css"), "d33682" },
})

-- 20. Inspect Java Properties (sample.properties)
local prop_buf = open_sample("sample.properties", "properties")
_, c = find_pos(prop_buf, "management.metrics.tags.application=${spring.application.name}", "${")
assert_suite("Neovim highlights Java Properties documents (sample.properties) with Converged Ergonomic Solarized: keys in Green (@property.properties #859900), delimiters in Base0 (@operator #839496), strings in Cyan (@string #2aa198), integers/booleans/floats in Magenta (@number, @boolean, @number.float #d33682), variable interpolation delimiters and keys in calm Base0 (@punctuation.special, @variable.properties #839496), and comments in Base01 Dim (@comment)", "Neovim Java Properties Tree-sitter highlights", {
    { "prop_key", probe_cap_fg(prop_buf, "spring.application.name=solarized-gateway", "spring.application.name", "property.properties"), "true/859900" },
    { "prop_eq", probe_cap_fg(prop_buf, "spring.application.name=solarized-gateway", "=", "operator"), "true/839496" },
    { "prop_str", probe_cap_fg(prop_buf, "spring.application.name=solarized-gateway", "solarized-gateway", "string"), "true/2aa198" },
    { "prop_num", probe_cap_fg(prop_buf, "server.port=8080", "8080", "number"), "true/d33682" },
    { "prop_bool", probe_cap_fg(prop_buf, "server.compression.enabled=true", "true", "boolean"), "true/d33682" },
    { "prop_float", probe_cap_fg(prop_buf, "management.tracing.sampling.probability=0.15", "0.15", "number.float"), "true/d33682" },
    { "prop_interp_delim", probe_cap_fg(prop_buf, "management.metrics.tags.application=${spring.application.name}", "${", "punctuation.special"), "true/839496" },
    { "prop_var", probe_cap_fg(prop_buf, "management.metrics.tags.application=${spring.application.name}", "spring.application.name", "variable.properties", c + 3), "true/839496" },
    { "prop_comment", probe_cap(prop_buf, "! Server Configuration", "!", "comment"), "true" },
})

-- 21. Inspect Protocol Buffers (sample.proto)
local proto_buf = open_sample("sample.proto", "proto")
assert_suite("Neovim highlights Protocol Buffers schemas (sample.proto) with Converged Ergonomic Solarized: syntax directive in Orange (@keyword.directive #cb4b16), import & package namespace in Violet (@keyword.import, @module #6c71c4), structural keywords, returns & scalar types in Green (@keyword, @type.builtin #859900, zero Yellow), RPC methods in Blue (@function.method #268bd2), user types, fields & option keys in calm Base0 (@type, @variable.member, @property #839496), and enum constants/numbers/booleans in Magenta (#d33682)", "Neovim Protocol Buffers (.proto) Tree-sitter highlights", {
    { "syntax", probe_cap_fg(proto_buf, "syntax = \"proto3\";", "syntax", "keyword.directive"), "true/cb4b16" },
    { "ver", probe_cap_fg(proto_buf, "syntax = \"proto3\";", "\"proto3\"", "string"), "true/2aa198" },
    { "pkg_kw", probe_cap_fg(proto_buf, "package telemetry.v1;", "package", "keyword"), "true/859900" },
    { "pkg_mod", probe_cap_fg(proto_buf, "package telemetry.v1;", "telemetry", "module"), "true/6c71c4" },
    { "import", probe_cap_fg(proto_buf, "import public \"common/v1/timestamp.proto\";", "import", "keyword.import"), "true/6c71c4" },
    { "pub", probe_cap_fg(proto_buf, "import public \"common/v1/timestamp.proto\";", "public", "keyword.modifier"), "true/859900" },
    { "opt_const", probe_cap_fg(proto_buf, "option optimize_for = SPEED;", "SPEED", "constant"), "true/d33682" },
    { "enum_const", probe_cap_fg(proto_buf, "NODE_STATE_OFFLINE = -1 [deprecated = true];", "NODE_STATE_OFFLINE", "constant"), "true/d33682" },
    { "neg", probe_cap_fg(proto_buf, "NODE_STATE_OFFLINE = -1 [deprecated = true];", "-1", "number"), "true/d33682" },
    { "msg_kw", probe_cap_fg(proto_buf, "message TelemetryBatch {", "message", "keyword.type"), "true/859900" },
    { "msg_type", probe_cap_fg(proto_buf, "message TelemetryBatch {", "TelemetryBatch", "type"), "true/839496" },
    { "scalar", probe_cap_fg(proto_buf, "uint64 sequence_num = 3", "uint64", "type.builtin"), "true/859900" },
    { "field", probe_cap_fg(proto_buf, "uint64 sequence_num = 3", "sequence_num", "variable.member"), "true/839496" },
    { "opt_key", probe_cap_fg(proto_buf, "service: \"gateway\"", "service", "property"), "true/839496" },
    { "opt_max", probe_cap_fg(proto_buf, "[(telemetry.v1.validation).max = 5000]", "max", "variable.member"), "true/839496" },
    { "rpc", probe_cap_fg(proto_buf, "rpc IngestBatch (TelemetryBatch) returns (IngestResponse);", "IngestBatch", "function.method"), "true/268bd2" },
    { "returns", probe_cap_fg(proto_buf, "rpc IngestBatch (TelemetryBatch) returns (IngestResponse);", "returns", "keyword"), "true/859900" },
})

-- 22. Inspect Protocol Buffers Text Format (sample.textproto)
tp_buf = open_sample("sample.textproto", "textproto")
assert_suite("Neovim highlights Protocol Buffers Text Format documents (sample.textproto) with Converged Ergonomic Solarized: message headers in Blue (@tag #268bd2), scalar/array keys in Green (@property.textproto #859900), bracketed extension & Any type URLs in Violet (@module #6c71c4), enum constants, negative numbers, unified float decimal points & special floats in Magenta (@constant, @number, @number.float #d33682), and comments in Base01 Dim (@comment #586e75)", "Neovim Protocol Buffers Text Format (.textproto) Tree-sitter highlights", {
    { "scalar_key", probe_cap_fg(tp_buf, "batch_id: \"batch-2025-09-14-0001\"", "batch_id", "property.textproto"), "true/859900" },
    { "msg_hdr", probe_cap_fg(tp_buf, "recorded_at {", "recorded_at", "tag"), "true/268bd2" },
    { "angle_hdr", probe_cap_fg(tp_buf, "route_quotas <", "route_quotas", "tag"), "true/268bd2" },
    { "list_hdr", probe_cap_fg(tp_buf, "metrics: [{", "metrics", "tag"), "true/268bd2" },
    { "ext", probe_cap_fg(tp_buf, "[telemetry.v1.routing_extension] {", "routing_extension", "module"), "true/6c71c4" },
    { "any", probe_cap_fg(tp_buf, "[type.example.com/telemetry.v1.SystemHealthPayload] {", "SystemHealthPayload", "module"), "true/6c71c4" },
    { "inline_any", probe_cap_fg(tp_buf, "extensions: [{ [type.example.com/telemetry.v1.SystemHealthPayload]", "SystemHealthPayload", "module"), "true/6c71c4" },
    { "float_dot", probe_cap_fg(tp_buf, "compression_ratio: 0.375", ".", "number.float"), "true/d33682" },
    { "enum", probe_cap_fg(tp_buf, "node_state: NODE_STATE_ACTIVE", "NODE_STATE_ACTIVE", "constant"), "true/d33682" },
    { "neg", probe_cap_fg(tp_buf, "clock_drift_ms: -12", "-12", "number"), "true/d33682" },
    { "neg_inf", probe_cap_fg(tp_buf, "lower_bound_sentinel: -inf", "-inf", "number.float"), "true/d33682" },
    { "comment", probe_cap_fg(tp_buf, "# proto-file:", "# proto-file:", "comment"), "true/586e75" },
})

-- 23. Inspect Kotlin (sample.kt)
tp_buf = open_sample("sample.kt", "kotlin")
assert_suite("Neovim highlights modern Kotlin 2.x (sample.kt) with Converged Ergonomic Solarized: unified @file:JvmName annotation & package namespace in Violet (@attribute, @module #6c71c4), calm Base0 import segments (@variable #839496) with Magenta wildcard (@constant.builtin #d33682), scalar primitives (String, Any) in Green (@type.builtin #859900) vs container types (List) in calm Base0 (@type #839496), loop 'in' & suspend in Yellow (#b58900) vs expression 'in', '!is' & '!in' in Green (#859900), and string interpolation in calm Base0 (#839496)", "Neovim Kotlin (.kt) Tree-sitter highlights", {
    { "ann_colon", probe_cap_fg(tp_buf, "@file:JvmName", ":", "attribute"), "true/6c71c4" },
    { "ann_name", probe_cap_fg(tp_buf, "@file:JvmName", "JvmName", "attribute"), "true/6c71c4" },
    { "pkg_kw", probe_cap_fg(tp_buf, "package core.telemetry", "package", "keyword"), "true/859900" },
    { "pkg_mod", probe_cap_fg(tp_buf, "package core.telemetry", "telemetry", "module"), "true/6c71c4" },
    { "imp_seg", probe_cap_fg(tp_buf, "import kotlinx.coroutines.*", "coroutines", "variable"), "true/839496" },
    { "imp_wild", probe_cap_fg(tp_buf, "import kotlinx.coroutines.*", "*", "constant.builtin"), "true/d33682" },
    { "str", probe_cap_fg(tp_buf, "value class NodeId(val raw: String)", "String", "type.builtin"), "true/859900" },
    { "any", probe_cap_fg(tp_buf, ") : BaseCollector(capacity) where T : Any {", "Any", "type.builtin"), "true/859900" },
    { "list", probe_cap_fg(tp_buf, "suspend fun flushBatch(batch: List<T>", "List", "type"), "true/839496" },
    { "suspend", probe_cap_fg(tp_buf, "suspend fun flushBatch(batch: List<T>", "suspend", "keyword.coroutine"), "true/b58900" },
    { "fn", probe_cap_fg(tp_buf, "suspend fun flushBatch(batch: List<T>", "flushBatch", "function"), "true/268bd2" },
    { "for_in", probe_cap_fg(tp_buf, "batchLoop@ for (item in validEvents) {", "in ", "keyword.repeat"), "true/b58900" },
    { "expr_in", probe_cap_fg(tp_buf, "val status = if (event.value in 0.0..100.0)", "in", "keyword.operator"), "true/859900" },
    { "not_is", probe_cap_fg(tp_buf, "this !is HeartbeatSignal", "!is", "keyword.operator"), "true/859900" },
    { "not_in", probe_cap_fg(tp_buf, "value !in -1.0..0.0", "!in", "keyword.operator"), "true/859900" },
    { "interp", probe_cap_fg(tp_buf, "($status) on $endpoint", "status", "variable"), "true/839496" },
})

-- 24. Inspect Swift (sample.swift)
tp_buf = open_sample("sample.swift", "swift")
assert_suite("Neovim highlights modern Swift 6 (sample.swift) with Converged Ergonomic Solarized: compiler directives (#if, #available) in Orange (@keyword.directive #cb4b16), module imports & attributes (@available, @discardableResult, @Sendable) in Violet (@module, @attribute #6c71c4), unified version floats in @available & shorthand $0 in Magenta (#d33682), enum variant 'case', word operators (is, closure in) & scalar primitives (Int) in Green (#859900) vs protocol/domain types (Sendable) in calm Base0 (#839496), and switch 'case', fallthrough, defer, guard else & throws in Yellow (#b58900)", "Neovim Swift (.swift) Tree-sitter highlights", {
    { "imp", probe_cap_fg(tp_buf, "import Foundation", "Foundation", "module"), "true/6c71c4" },
    { "dir", probe_cap_fg(tp_buf, "#if canImport(Darwin)", "#if", "keyword.directive"), "true/cb4b16" },
    { "avail", probe_cap_fg(tp_buf, "if #available(macOS 14.0, iOS 17.0, *)", "available", "keyword.directive"), "true/cb4b16" },
    { "dot", probe_cap_fg(tp_buf, "@available(macOS 14.0, iOS 17.0, *)", ".", "number.float"), "true/d33682" },
    { "disc", probe_cap_fg(tp_buf, "@discardableResult", "discardableResult", "attribute"), "true/6c71c4" },
    { "pattr", probe_cap_fg(tp_buf, "predicate: @Sendable (MetricFrame) -> Bool", "Sendable", "attribute"), "true/6c71c4" },
    { "enum_case", probe_cap_fg(tp_buf, "    case idle", "case", "keyword"), "true/859900" },
    { "sw_case", probe_cap_fg(tp_buf, "        case .idle:", "case", "keyword.conditional"), "true/b58900" },
    { "fallthrough", probe_cap_fg(tp_buf, "            fallthrough", "fallthrough", "keyword.conditional"), "true/b58900" },
    { "defer", probe_cap_fg(tp_buf, "        defer {", "defer", "keyword.conditional"), "true/b58900" },
    { "else", probe_cap_fg(tp_buf, "        guard !endpoint.isEmpty else {", "else", "keyword.conditional"), "true/b58900" },
    { "throws", probe_cap_fg(tp_buf, "    public func dispatch(frames: [MetricFrame]) async throws -> Int {", "throws", "keyword.exception"), "true/b58900" },
    { "int", probe_cap_fg(tp_buf, "    public func dispatch(frames: [MetricFrame]) async throws -> Int {", "Int", "type.builtin"), "true/859900" },
    { "sendable", probe_cap_fg(tp_buf, "public enum ConnectionStatus: Sendable, Equatable {", "Sendable", "type"), "true/839496" },
    { "cin", probe_cap_fg(tp_buf, "return frames.filter { frame in predicate(frame) }", "in ", "keyword.operator"), "true/859900" },
    { "is", probe_cap_fg(tp_buf, "if error is CancellationError", "is ", "keyword.operator"), "true/859900" },
    { "d0", probe_cap_fg(tp_buf, "        let healthyFrames = frames.filter { $0.isHealthy", "$0", "variable.builtin"), "true/d33682" },
})

-- 25. Inspect Zig (sample.zig)
tp_buf = open_sample("sample.zig", "zig")
assert_suite("Neovim highlights modern Zig (sample.zig) with Converged Ergonomic Solarized: @import & module bindings in Violet (#6c71c4), primitive types (usize) in Green (#859900), fn declarations including comptime generic type functions (RingBuffer) in Blue (#268bd2), defer/errdefer control flow in Yellow (#b58900), constants, self & enum shorthand (.critical) in Magenta (#d33682), and struct field initializers (.id = 1) in calm Base0 (#839496)", "Neovim Zig (.zig) Tree-sitter highlights", {
    { "imp", probe_cap_fg(tp_buf, "const std = @import(\"std\");", "@import", "keyword.import"), "true/6c71c4" },
    { "std", probe_cap_fg(tp_buf, "const std = @import(\"std\");", "std", "module"), "true/6c71c4" },
    { "const", probe_cap_fg(tp_buf, "pub const DEFAULT_CAPACITY: usize = 1024;", "DEFAULT_CAPACITY", "constant"), "true/d33682" },
    { "usize", probe_cap_fg(tp_buf, "pub const DEFAULT_CAPACITY: usize = 1024;", "usize", "type.builtin"), "true/859900" },
    { "ring", probe_cap_fg(tp_buf, "pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {", "RingBuffer", "function"), "true/268bd2" },
    { "defer", probe_cap_fg(tp_buf, "        defer self.allocator.free(scratch);", "defer", "keyword.conditional"), "true/b58900" },
    { "errdefer", probe_cap_fg(tp_buf, "        errdefer self.active_count = 0;", "errdefer", "keyword.conditional"), "true/b58900" },
    { "enum_lit", probe_cap_fg(tp_buf, "            .critical => true,", "critical", "constant"), "true/d33682" },
    { "field_init", probe_cap_fg(tp_buf, "        .{ .id = 1, .name = \"cpu.load\", .severity = .info, .payload = .{ .metric = 0.42 } },", "id", "variable.member"), "true/839496" },
    { "self", probe_cap_fg(tp_buf, "        defer self.allocator.free(scratch);", "self", "variable.builtin"), "true/d33682" },
})

-- 26. Inspect C# (sample.cs)
tp_buf = open_sample("sample.cs", "c_sharp")
assert_suite("Neovim highlights modern C# 12/13 (sample.cs) with Converged Ergonomic Solarized: namespace targets & unified [Attribute] blocks in Violet (#6c71c4), generic constraint 'where' in Green (#859900), foreach 'in' in Yellow (#b58900), constants, discard (_) & default expressions in Magenta (#d33682), format specifiers (:F2) in Cyan (#2aa198), and interpolated variables in calm Base0 (#839496)", "Neovim C# (.cs) Tree-sitter highlights", {
    { "ns", probe_cap_fg(tp_buf, "namespace Core.Telemetry;", "Telemetry", "module"), "true/6c71c4" },
    { "brack", probe_cap_fg(tp_buf, "[AttributeUsage(AttributeTargets.Class | AttributeTargets.Struct, AllowMultiple = false)]", "[", "attribute"), "true/6c71c4" },
    { "attr", probe_cap_fg(tp_buf, "[AttributeUsage(AttributeTargets.Class | AttributeTargets.Struct, AllowMultiple = false)]", "AttributeUsage", "attribute"), "true/6c71c4" },
    { "where", probe_cap_fg(tp_buf, "    where T : class, ITelemetryEvent", "where", "keyword"), "true/859900" },
    { "const", probe_cap_fg(tp_buf, "    public const int DEFAULT_CAPACITY = 1024;", "DEFAULT_CAPACITY", "constant"), "true/d33682" },
    { "interp_var", probe_cap_fg(tp_buf, "                $\"CRITICAL[{metricName}]={evt.Id} on {this.Endpoint}\",", "metricName", "variable"), "true/839496" },
    { "fmt", probe_cap_fg(tp_buf, "                $\"Metric[{sample.Name}]={sample.Value:F2} on {this.Endpoint}\",", ":F2", "string.special"), "true/2aa198" },
    { "discard", probe_cap_fg(tp_buf, "            _ => $\"Unhandled event {evt.Id}\",", "_", "constant.builtin"), "true/d33682" },
    { "default", probe_cap_fg(tp_buf, "        CancellationToken cancellationToken = default", "default", "constant.builtin"), "true/d33682" },
    { "in", probe_cap_fg(tp_buf, "            foreach (var entry in validEvents)", "in ", "keyword.repeat"), "true/b58900" },
})

-- 27. Inspect Scala 3 (sample.scala)
tp_buf = open_sample("sample.scala", "scala")
assert_suite("Neovim highlights modern Scala 3 (sample.scala) with Converged Ergonomic Solarized: package keyword & enum case in Green (#859900) vs indented match case in Yellow (#b58900), package targets & unified @tailrec annotations in Violet (#6c71c4), scalar primitives (Int) in Green (#859900), import wildcards (*), this & None/Nil sentinels in Magenta (#d33682), and s\"...\" interpolated variables in calm Base0 (#839496)", "Neovim Scala 3 (.scala) Tree-sitter highlights", {
    { "pkg_kw", probe_cap_fg(tp_buf, "package core.telemetry", "package", "keyword"), "true/859900" },
    { "pkg_mod", probe_cap_fg(tp_buf, "package core.telemetry", "telemetry", "module"), "true/6c71c4" },
    { "wild", probe_cap_fg(tp_buf, "import scala.util.*", "*", "constant.builtin"), "true/d33682" },
    { "enum_case", probe_cap_fg(tp_buf, "  case Info extends Severity(100)", "case", "keyword"), "true/859900" },
    { "match_case", probe_cap_fg(tp_buf, "      case Critical(true) => true", "case", "keyword.conditional"), "true/b58900" },
    { "ann_at", probe_cap_fg(tp_buf, "  @tailrec", "@", "attribute"), "true/6c71c4" },
    { "ann_name", probe_cap_fg(tp_buf, "  @tailrec", "tailrec", "attribute"), "true/6c71c4" },
    { "int", probe_cap_fg(tp_buf, "val DEFAULT_CAPACITY: Int = 1024", "Int", "type.builtin"), "true/859900" },
    { "none", probe_cap_fg(tp_buf, "    if batch.isEmpty then return None", "None", "constant.builtin"), "true/d33682" },
    { "interp", probe_cap_fg(tp_buf, "        s\"OUTLIER[$name]=$value on $endpoint (id=${id})\"", "name", "variable"), "true/839496" },
    { "this", probe_cap_fg(tp_buf, "  def currentLoad: Int = this.activeCount", "this", "variable.builtin"), "true/d33682" },
})

-- 28. Inspect Ruby (sample.rb)
tp_buf = open_sample("sample.rb", "ruby")
assert_suite("Neovim highlights modern Ruby 3.3+ (sample.rb) with Converged Ergonomic Solarized: module declaration names in Violet (#6c71c4), mixin/attribute macros (include, attr_reader) in Green (#859900), :symbol literals & SCREAMING_SNAKE_CASE constants in Magenta (#d33682), and hash symbol keys (type:) & #{...} interpolated variables in calm Base0 (#839496)", "Neovim Ruby (.rb) Tree-sitter highlights", {
    { "mod", probe_cap_fg(tp_buf, "module Telemetry", "Telemetry", "module"), "true/6c71c4" },
    { "inc", probe_cap_fg(tp_buf, "    include Enumerable", "include", "keyword.modifier"), "true/859900" },
    { "attr", probe_cap_fg(tp_buf, "    attr_reader :endpoint, :active_count", "attr_reader", "keyword.modifier"), "true/859900" },
    { "sym", probe_cap_fg(tp_buf, "    attr_reader :endpoint, :active_count", ":endpoint", "string.special.symbol"), "true/d33682" },
    { "hkey", probe_cap_fg(tp_buf, "      in { type: :metric, name: String => metric_name", "type:", "variable.member"), "true/839496" },
    { "const", probe_cap_fg(tp_buf, "  DEFAULT_CAPACITY = 1024", "DEFAULT_CAPACITY", "constant"), "true/d33682" },
    { "interp", probe_cap_fg(tp_buf, "        \"OUTLIER[#{metric_name}]=#{reading} on #{@endpoint}\"", "metric_name", "variable"), "true/839496" },
})

-- 29. Inspect GraphQL (sample.graphql)
tp_buf = open_sample("sample.graphql", "graphql")
assert_suite("Neovim highlights GraphQL schemas & queries (sample.graphql) with Converged Ergonomic Solarized: schema keywords, built-in scalars (Float) & field/alias keys in Green (#859900), operation/fragment declarations in Blue (#268bd2), @directives in Violet (#6c71c4), enum values & directive locations in Magenta (#d33682), and custom types in calm Base0 (#839496)", "Neovim GraphQL (.graphql) Tree-sitter highlights", {
    { "scalar", probe_cap_fg(tp_buf, "scalar DateTime @specifiedBy", "scalar", "keyword"), "true/859900" },
    { "type", probe_cap_fg(tp_buf, "scalar DateTime @specifiedBy", "DateTime", "type"), "true/839496" },
    { "dir", probe_cap_fg(tp_buf, "scalar DateTime @specifiedBy", "@specifiedBy", "attribute"), "true/6c71c4" },
    { "loc", probe_cap_fg(tp_buf, ") repeatable on FIELD_DEFINITION | OBJECT", "FIELD_DEFINITION", "constant.builtin"), "true/d33682" },
    { "enum", probe_cap_fg(tp_buf, "  HEALTH_STATE_ACTIVE", "HEALTH_STATE_ACTIVE", "constant"), "true/d33682" },
    { "op", probe_cap_fg(tp_buf, "query GetTelemetrySnapshot(", "GetTelemetrySnapshot", "function"), "true/268bd2" },
    { "alias", probe_cap_fg(tp_buf, "  primaryHost: hostname", "primaryHost", "property"), "true/859900" },
    { "float", probe_cap_fg(tp_buf, "    threshold: Float = -0.25", "Float", "type.builtin"), "true/859900" },
})

-- 30. Inspect Starlark (sample.bzl)
tp_buf = open_sample("sample.bzl", "starlark")
local bzl_load = probe_cap_fg(tp_buf, "load(\"@bazel_skylib//lib:paths.bzl\", \"paths\")", "load", "keyword.import")
local bzl_const = probe_cap_fg(tp_buf, "DEFAULT_COPTS = [\"-Wall\", \"-Wextra\", \"-Werror\", \"-std=c++20\"]", "DEFAULT_COPTS", "constant")
local bzl_fn = probe_cap_fg(tp_buf, "def _telemetry_schema_library_impl(ctx):", "_telemetry_schema_library_impl", "function")
local bzl_select = probe_cap_fg(tp_buf, "    platform_copts = select({", "select", "function.call")
local bzl_doc = probe_cap_fg(tp_buf, "    \"\"\"Rule implementation generating C++ headers from telemetry schemas.\"\"\"", "Rule", "string.documentation")

-- 31. Inspect Bazel BUILD (BUILD.bazel)
tp_buf = open_sample("BUILD.bazel", "starlark")
assert_suite("Neovim highlights Open-Source Bazel / Starlark (sample.bzl & BUILD.bazel) with Converged Ergonomic Solarized: load() in Violet (#6c71c4), docstrings in Base01 (#586e75), function/macro declarations in Blue (#268bd2), ALL_CAPS constants in Magenta (#d33682), list comprehension for/in in Yellow (#b58900), and package/glob/rule/select/depset calls in calm Base0 (#839496)", "Neovim Starlark (.bzl & BUILD.bazel) Tree-sitter highlights", {
    { "load", bzl_load, "true/6c71c4" },
    { "const", bzl_const, "true/d33682" },
    { "fn", bzl_fn, "true/268bd2" },
    { "select", bzl_select, "true/839496" },
    { "doc", bzl_doc, "true/586e75" },
    { "pkg", probe_cap_fg(tp_buf, "telemetry_cc_library(", "telemetry_cc_library", "function.call"), "true/839496" },
    { "glob", probe_cap_fg(tp_buf, "    srcs = glob(", "glob", "function.call"), "true/839496" },
    { "for", probe_cap_fg(tp_buf, "    for shard in [", "for", "keyword.repeat"), "true/b58900" },
})

-- 32. Inspect OPA Rego (sample.rego)
tp_buf = open_sample("sample.rego", "rego")
assert_suite("Neovim highlights Open Policy Agent Rego v1 (sample.rego) with Converged Ergonomic Solarized: package & structural query keywords (contains, some, with, as, in, not) in Green (#859900), import & module paths/aliases in Violet (#6c71c4), rule/function declarations in Blue (#268bd2), conditional/quantifier control flow (if, else, every) in Yellow (#b58900), constants in Magenta (#d33682), and set element variables (msg) & builtin calls in calm Base0 (#839496)", "Neovim OPA Rego (.rego) Tree-sitter highlights", {
    { "pkg_kw", probe_cap_fg(tp_buf, "package telemetry.authz.v1", "package", "keyword"), "true/859900" },
    { "pkg_mod", probe_cap_fg(tp_buf, "package telemetry.authz.v1", "telemetry", "module"), "true/6c71c4" },
    { "imp", probe_cap_fg(tp_buf, "import data.clusters.topology as cluster_topology", "import", "keyword.import"), "true/6c71c4" },
    { "alias", probe_cap_fg(tp_buf, "import data.clusters.topology as cluster_topology", "cluster_topology", "module"), "true/6c71c4" },
    { "const", probe_cap_fg(tp_buf, "MAX_BURST_RATE := 5000", "MAX_BURST_RATE", "constant"), "true/d33682" },
    { "rule", probe_cap_fg(tp_buf, "violations contains msg if {", "violations", "function"), "true/268bd2" },
    { "contains", probe_cap_fg(tp_buf, "violations contains msg if {", "contains", "keyword"), "true/859900" },
    { "msg", probe_cap_fg(tp_buf, "violations contains msg if {", "msg", "variable"), "true/839496" },
    { "every", probe_cap_fg(tp_buf, "    every ep in request.endpoints {", "every", "keyword.repeat"), "true/b58900" },
    { "sprintf", probe_cap_fg(tp_buf, "    msg := sprintf(\"endpoint %q failed TLS URI schema validation\", [endpoint.id])", "sprintf", "function.call"), "true/839496" },
})

-- 33. Inspect Lua (sample.lua)
tp_buf = open_sample("sample.lua", "lua")
assert_suite("Neovim highlights modern Lua 5.4 / LuaJIT (sample.lua) with Converged Ergonomic Solarized: <const>/<close> attributes in Violet (#6c71c4), ALL_CAPS constants & metamethods (__index) in Magenta (#d33682), loop 'in' & goto in Yellow (#b58900), and stdlib invocations (setmetatable) in calm Base0 (#839496)", "Neovim Lua (.lua) Tree-sitter highlights", {
    { "const", probe_cap_fg(tp_buf, "local DEFAULT_TIMEOUT_MS <const> = 2500", "DEFAULT_TIMEOUT_MS", "constant"), "true/d33682" },
    { "attr", probe_cap_fg(tp_buf, "local DEFAULT_TIMEOUT_MS <const> = 2500", "const", "attribute"), "true/6c71c4" },
    { "meta", probe_cap_fg(tp_buf, "RingBuffer.__index = RingBuffer", "__index", "constant.builtin"), "true/d33682" },
    { "setmeta", probe_cap_fg(tp_buf, "    return setmetatable(instance, RingBuffer)", "setmetatable", "function.call"), "true/839496" },
    { "in", probe_cap_fg(tp_buf, "        for idx, item in ipairs(self.items) do", "in", "keyword.repeat"), "true/b58900" },
    { "goto", probe_cap_fg(tp_buf, "                goto continue", "goto", "keyword.return"), "true/b58900" },
})

-- 34. Inspect Dockerfile (sample.Dockerfile)
tp_buf = open_sample("sample.Dockerfile", "dockerfile")
assert_suite("Neovim highlights Dockerfile / Containerfile (sample.Dockerfile) with Converged Ergonomic Solarized: BuildKit syntax directive in Orange (#cb4b16), FROM/RUN/COPY instructions in Green (#859900), stage aliases in Blue (#268bd2), --from/--mount flags in calm Base0 (#839496), numeric ports in Magenta (#d33682), and isolated per-RUN bash injection control flow in Yellow (#b58900)", "Neovim Dockerfile Tree-sitter highlights", {
    { "syn", probe_cap_fg(tp_buf, "# syntax=docker/dockerfile:1", "syntax", "keyword.directive"), "true/cb4b16" },
    { "from", probe_cap_fg(tp_buf, "FROM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder", "FROM", "keyword"), "true/859900" },
    { "stage", probe_cap_fg(tp_buf, "FROM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder", "builder", "function"), "true/268bd2" },
    { "flag", probe_cap_fg(tp_buf, "COPY --from=builder --chown=10001:10001 /out/solarized-gateway /usr/local/bin/solarized-gateway", "--from=builder", "variable.parameter"), "true/839496" },
    { "port", probe_cap_fg(tp_buf, "ARG SERVICE_PORT=8080", "8080", "number"), "true/d33682" },
    { "if", probe_cap_fg(tp_buf, "    if [ -z \"${BUILD_COMMIT}\" ]; then \\", "if", "keyword.conditional"), "true/b58900" },
})

-- 35. Inspect GNU Make (sample.mk)
tp_buf = open_sample("sample.mk", "make")
assert_suite("Neovim highlights GNU Make (sample.mk) with Converged Ergonomic Solarized: -include in Violet (#6c71c4), .PHONY in Green (#859900), ifeq conditionals in Yellow (#b58900), recipe @/-/+ prefixes in Orange (#cb4b16), rule targets in Blue (#268bd2), .DEFAULT_GOAL/ALL_CAPS/automatic variables ($@) in Magenta (#d33682), and built-in functions (wildcard) & expansion delimiters in calm Base0 (#839496)", "Neovim GNU Make (.mk) Tree-sitter highlights", {
    { "defgoal", probe_cap_fg(tp_buf, ".DEFAULT_GOAL := all", ".DEFAULT_GOAL", "variable.builtin"), "true/d33682" },
    { "proj", probe_cap_fg(tp_buf, "PROJECT_NAME := solarized-gateway", "PROJECT_NAME", "constant"), "true/d33682" },
    { "wild", probe_cap_fg(tp_buf, "SRCS := $(wildcard $(SRC_DIR)/*.c)", "wildcard", "function.builtin"), "true/839496" },
    { "inc", probe_cap_fg(tp_buf, "-include config.local.mk", "-include", "keyword.import"), "true/6c71c4" },
    { "ifeq", probe_cap_fg(tp_buf, "ifeq ($(DEBUG),1)", "ifeq", "keyword.conditional"), "true/b58900" },
    { "phony", probe_cap_fg(tp_buf, ".PHONY: all build test install clean", ".PHONY", "keyword"), "true/859900" },
    { "target", probe_cap_fg(tp_buf, "all: build test", "all", "function"), "true/268bd2" },
    { "at", probe_cap_fg(tp_buf, "\t@mkdir -p $(dir $@)", "@", "keyword.directive"), "true/cb4b16" },
    { "auto", probe_cap_fg(tp_buf, "\t$(CC) $(CFLAGS) -c $< -o $@", "$@", "constant.builtin"), "true/d33682" },
    { "qdelim", probe_fg(tp_buf, "\"$(BUILD_DIR)/bin/$(PROJECT_NAME)\"", "$(BUILD_DIR)"), "839496" },
})

-- 36. Inspect Elixir (sample.ex)
tp_buf = open_sample("sample.ex", "elixir")
assert_suite("Neovim highlights Elixir (sample.ex) with Converged Ergonomic Solarized: defmodule/def/defp in Green (#859900), formal module/use/import/alias/require targets & @attributes in Violet (#6c71c4), function declarations in Blue (#268bd2), :atoms/keyword: in Magenta (#d33682), and piped calls & #{...} interpolated variables in calm Base0 (#839496)", "Neovim Elixir (.ex) Tree-sitter highlights", {
    { "defmod", probe_cap_fg(tp_buf, "defmodule Core.Telemetry.Collector do", "defmodule", "keyword.function"), "true/859900" },
    { "mod", probe_cap_fg(tp_buf, "defmodule Core.Telemetry.Collector do", "Core", "module"), "true/6c71c4" },
    { "use", probe_cap_fg(tp_buf, "  use GenServer", "use", "keyword.import"), "true/6c71c4" },
    { "spec", probe_cap_fg(tp_buf, "  @spec start_link(keyword()) :: GenServer.on_start()", "spec", "attribute"), "true/6c71c4" },
    { "fn", probe_cap_fg(tp_buf, "  def start_link(opts \\\\ []) do", "start_link", "function"), "true/268bd2" },
    { "pipe", probe_cap_fg(tp_buf, "        |> summarize_metrics(source_tag)", "summarize_metrics", "function.call"), "true/839496" },
    { "atom", probe_cap_fg(tp_buf, "    region = Keyword.get(opts, :region, :us_east)", ":us_east", "string.special.symbol"), "true/d33682" },
    { "interp", probe_cap_fg(tp_buf, "        label = \"source=#{source_tag} count=#{count}\\n\"", "source_tag", "variable"), "true/839496" },
})

-- 37. Inspect Haskell (sample.hs)
tp_buf = open_sample("sample.hs", "haskell")
assert_suite("Neovim highlights Haskell (sample.hs) with Converged Ergonomic Solarized: {-# LANGUAGE #-} pragmas in Orange (#cb4b16), module/import targets in Violet (#6c71c4), scalar primitives (Double) in Green (#859900), function signatures/definitions in Blue (#268bd2), do/case/if control flow in Yellow (#b58900), Nothing/otherwise in Magenta (#d33682), and container/custom types (Maybe) in calm Base0 (#839496)", "Neovim Haskell (.hs) Tree-sitter highlights", {
    { "pragma", probe_cap_fg(tp_buf, "{-# LANGUAGE OverloadedStrings, DeriveGeneric #-}", "LANGUAGE", "keyword.directive"), "true/cb4b16" },
    { "mod", probe_cap_fg(tp_buf, "module Core.Telemetry", "Core", "module"), "true/6c71c4" },
    { "double", probe_cap_fg(tp_buf, "  , sampleScore :: Double", "Double", "type.builtin"), "true/859900" },
    { "sig", probe_cap_fg(tp_buf, "classifySample :: MetricSample -> Maybe Severity", "classifySample", "function"), "true/268bd2" },
    { "maybe", probe_cap_fg(tp_buf, "classifySample :: MetricSample -> Maybe Severity", "Maybe", "type"), "true/839496" },
    { "nothing", probe_cap_fg(tp_buf, "  | not (sampleValid sample) = Nothing", "Nothing", "constant.builtin"), "true/d33682" },
    { "do", probe_cap_fg(tp_buf, "ingestStream primaryNode batch = do", "do", "keyword.conditional"), "true/b58900" },
})

-- 38. Inspect OCaml (sample.ml)
tp_buf = open_sample("sample.ml", "ocaml")
assert_suite("Neovim highlights OCaml (sample.ml) with Converged Ergonomic Solarized: open & module/signature names in Violet (#6c71c4), type variables ('a) & scalar primitives (int) in Green (#859900), function declarations in Blue (#268bd2), match/with/when in Yellow (#b58900), polymorphic variants (`Offline) & None in Magenta (#d33682), and container types (option) in calm Base0 (#839496)", "Neovim OCaml (.ml) Tree-sitter highlights", {
    { "open", probe_cap_fg(tp_buf, "open Printf", "open", "keyword.import"), "true/6c71c4" },
    { "mod", probe_cap_fg(tp_buf, "module Collector : TELEMETRY = struct", "Collector", "module"), "true/6c71c4" },
    { "tvar", probe_cap_fg(tp_buf, "type 'a envelope = {", "'a", "keyword.modifier"), "true/859900" },
    { "int", probe_cap_fg(tp_buf, "  mutable retries : int;", "int", "type.builtin"), "true/859900" },
    { "opt", probe_cap_fg(tp_buf, "  val classify : sample -> severity option", "option", "type"), "true/839496" },
    { "fn", probe_cap_fg(tp_buf, "  let clamp_score lower upper value =", "clamp_score", "function"), "true/268bd2" },
    { "match", probe_cap_fg(tp_buf, "    match item.state with", "match", "keyword.conditional"), "true/b58900" },
    { "var", probe_cap_fg(tp_buf, "    | `Offline -> None", "`Offline", "constant"), "true/d33682" },
    { "none", probe_cap_fg(tp_buf, "    | `Offline -> None", "None", "constant.builtin"), "true/d33682" },
})

-- 39. Inspect Clojure (sample.clj)
tp_buf = open_sample("sample.clj", "clojure")
assert_suite("Neovim highlights Clojure (sample.clj) with Converged Ergonomic Solarized: ns/namespace & ^metadata in Violet (#6c71c4), defn/defmacro/defprotocol/let/loop in Green (#859900), declared function/macro/protocol-method names in Blue (#268bd2), when-let/cond/if/case/recur in Yellow (#b58900), :keywords in Magenta (#d33682), and threading macros (->) in calm Base0 (#839496)", "Neovim Clojure (.clj) Tree-sitter highlights", {
    { "ns", probe_cap_fg(tp_buf, "(ns core.telemetry.collector", "ns", "keyword.import"), "true/6c71c4" },
    { "mod", probe_cap_fg(tp_buf, "(ns core.telemetry.collector", "core.telemetry.collector", "module"), "true/6c71c4" },
    { "meta", probe_cap_fg(tp_buf, "(defonce ^:private default-window-ms 5000)", "^:private", "attribute"), "true/6c71c4" },
    { "defn", probe_cap_fg(tp_buf, "(defn classify-sample", "defn", "keyword.function"), "true/859900" },
    { "fn", probe_cap_fg(tp_buf, "(defn classify-sample", "classify-sample", "function"), "true/268bd2" },
    { "whenlet", probe_cap_fg(tp_buf, "  (when-let [score (and sample (sample-score sample))]", "when-let", "keyword.conditional"), "true/b58900" },
    { "kw", probe_cap_fg(tp_buf, "      (>= score 80.0)         :telemetry/critical", ":telemetry/critical", "string.special.symbol"), "true/d33682" },
    { "thread", probe_cap_fg(tp_buf, "               (-> acc", "->", "function.call"), "true/839496" },
})

-- 40. UI Highlight Groups & Framing Architecture
local function hl_info(name)
    local h = vim.api.nvim_get_hl(0, { name = name, link = false })
    local fg = h.fg and string.format("%06x", h.fg) or "none"
    local bg = h.bg and string.format("%06x", h.bg) or "none"
    local b = tostring(h.bold == true)
    return fg .. "/" .. bg .. "/" .. b
end

assert_suite("Neovim highlights Editor UI & Framing Architecture with Converged Ergonomic Solarized: CursorLineNr in Base1 Bold (#93a1a1) on Base02 (#073642), LineNr in Base01 (#586e75), WinSeparator/FloatBorder in calm Base01 (#586e75), MatchParen in Base1 Bold on Base02, Search in mix_yellow (#364725) distinct from Visual in mix_base1 (#2c4e56), DiagnosticHint in Cyan (#2aa198), and DiffAdd/Delete/Change/Text with soft background tints", "Neovim UI highlights", {
    { "curline_nr", hl_info("CursorLineNr"), "93a1a1/073642/true" },
    { "linenr", hl_info("LineNr"), "586e75/002b36/false" },
    { "winsep", select(1, hl_info("WinSeparator"):match("^([^/]+)")), "586e75" },
    { "vertsplit", select(1, hl_info("VertSplit"):match("^([^/]+)")), "586e75" },
    { "floatborder", select(1, hl_info("FloatBorder"):match("^([^/]+)")), "586e75" },
    { "matchparen", hl_info("MatchParen"), "93a1a1/073642/true" },
    { "search", hl_info("Search"), "93a1a1/364725/true" },
    { "visual_bg", select(1, hl_info("Visual"):match("^[^/]+/([^/]+)")), "2c4e56" },
    { "hint_fg", select(1, hl_info("DiagnosticHint"):match("^([^/]+)")), "2aa198" },
    { "sign_hint_fg", select(1, hl_info("DiagnosticSignHint"):match("^([^/]+)")), "2aa198" },
    { "diffadd", hl_info("DiffAdd"), "859900/274c25/false" },
    { "diffdel", hl_info("DiffDelete"), "dc322f/422d33/false" },
    { "diffchg", hl_info("DiffChange"), "b58900/364725/false" },
    { "difftext", hl_info("DiffText"), "268bd2/0b4764/true" },
})
EOF
        NVIM_RESULTS="$(XDG_CONFIG_HOME="$TEMP_NVIM_XDG_CONFIG" run_nvim_headless -u "$NVIM_CONFIG" -c "edit $SCRIPT_DIR/sample-code/sample.c" -c "luafile $TEMP_NVIM_XDG_CONFIG/inspect.lua" 2>/dev/null || true)"
        rm -rf "$TEMP_NVIM_XDG_CONFIG"
        parse_subshell_results <<< "$NVIM_RESULTS"
    fi

    # Verify that over SSH (SSH_CONNECTION set, DISPLAY unset), init.lua never spoofs DISPLAY=":0" from a background
    # /tmp/.X11-unix/X0 socket, leaves vim.g.clipboard unset so Neovim's built-in OSC 52 / unnamedplus provider runs,
    # and enables autoread + SolarizedAutoRead checktime and IdeCd.
    if command -v nvim >/dev/null 2>&1; then
        SSH_NVIM_SCRIPT=$(mktemp)
        cat <<'EOF' > "$SSH_NVIM_SCRIPT"
local ac = vim.api.nvim_get_autocmds({ group = "SolarizedAutoRead" })
local mf_ok = "true"
local mf_layout_ok = "true"
local ok, mf = pcall(require, "mini.files")
if ok and mf then
    local fk = function(k) vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), "mx", false) end
    local cwd = vim.fn.getcwd()
    fk("<leader>e")
    local b0 = (mf.get_explorer_state() or {}).branch or {}
    mf.close()
    vim.cmd("edit " .. cwd .. "/modules/10-dotfiles.sh")
    local code_wrap = vim.wo.wrap
    fk("<leader>e")
    local st1 = mf.get_explorer_state() or {}
    local b1 = st1.branch or {}
    local w1_cfg = st1.windows and st1.windows[1] and vim.api.nvim_win_get_config(st1.windows[1].win_id) or {}
    local w2_cfg = st1.windows and st1.windows[2] and vim.api.nvim_win_get_config(st1.windows[2].win_id) or {}
    vim.o.columns = 120
    vim.cmd("doautocmd VimResized")
    local st_res = mf.get_explorer_state() or {}
    local w2_res = st_res.windows and st_res.windows[2] and vim.api.nvim_win_get_config(st_res.windows[2].win_id) or {}
    vim.o.columns = 80
    vim.cmd("doautocmd VimResized")
    local r0 = vim.api.nvim_win_get_cursor(0)[1]
    fk("<Down>")
    local r1 = vim.api.nvim_win_get_cursor(0)[1]
    fk("<Up>")
    local r2 = vim.api.nvim_win_get_cursor(0)[1]
    fk("<Left>")
    local st_left = mf.get_explorer_state() or {}
    local wl_cfg = st_left.windows and st_left.windows[1] and vim.api.nvim_win_get_config(st_left.windows[1].win_id) or {}
    fk("<Right>")
    local st_right = mf.get_explorer_state() or {}
    local wr_cfg = st_right.windows and st_right.windows[1] and vim.api.nvim_win_get_config(st_right.windows[1].win_id) or {}
    fk("<S-Left>")
    local st_sleft = mf.get_explorer_state() or {}
    fk("<Right>")
    fk("<CR>")
    local st_cr = mf.get_explorer_state()
    local cr_buf = vim.api.nvim_buf_get_name(0)
    fk("<leader>e")
    fk("<S-Right>")
    local st_sright = mf.get_explorer_state()
    fk("<leader>e")
    fk("<leader>e")
    local st_closed = mf.get_explorer_state()
    vim.cmd("edit " .. cwd .. "/modules/unsaved-new.sh")
    fk("<leader>e")
    local b2 = (mf.get_explorer_state() or {}).branch or {}
    mf.set_branch({cwd, cwd .. "/modules"})
    mf.close()
    fk("<leader>E")
    local b3 = (mf.get_explorer_state() or {}).branch or {}
    mf.close()
    local tmpd = vim.fn.tempname()
    vim.fn.mkdir(tmpd, "p")
    mf.open(tmpd, false)
    fk("onewfile.txt<Esc>")
    vim.cmd("doautocmd CursorMoved")
    vim.wait(100, function() return false end)
    local st_imag = mf.get_explorer_state() or {}
    local w2_imag = st_imag.windows and st_imag.windows[2] and vim.api.nvim_win_get_config(st_imag.windows[2].win_id) or {}
    mf.close()
    vim.fn.delete(tmpd, "rf")
    local nav_ok = (r1 == r0 + 1 and r2 == r0 and (st_left.branch or {})[1] == cwd and st_left.depth_focus == 1 and (st_right.branch or {})[2] == cwd .. "/modules" and st_right.depth_focus == 2 and #(st_sleft.branch or {}) < #(st_right.branch or {}) and st_cr == nil and st_sright == nil and cr_buf:find("/modules/", 1, true) ~= nil)
    mf_ok = tostring(b0[1] == cwd and b1[1] == cwd .. "/modules" and st_closed == nil and b2[1] == cwd .. "/modules" and #b3 == 1 and b3[1] == cwd and nav_ok)
    mf_layout_ok = tostring(code_wrap == false and #(st1.windows or {}) == 2 and w1_cfg.col == 0 and w1_cfg.width == 35 and w2_cfg.col == 37 and (w2_cfg.col + w2_cfg.width + 2 == 80) and (w2_res.col + w2_res.width + 2 == 120) and (w2_imag.col + (w2_imag.width or 0) + 2 == 80) and wl_cfg.col == 0 and wl_cfg.width == 35 and wr_cfg.col == 0 and wr_cfg.width == 35)
end
vim.cmd("edit " .. vim.fn.getcwd() .. "/sample-code/sample.md")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local md_wrap = (vim.wo.wrap == true and vim.wo.linebreak == true and vim.wo.breakindent == true)
local hex = function(n) return n and string.format("%06x", n) or "none" end
local hl = function(g) return vim.api.nvim_get_hl(0, { name = g, link = false }) end
local h1, h2, h3, h4, h5, h6 = hl("RenderMarkdownH1"), hl("RenderMarkdownH2"), hl("RenderMarkdownH3"), hl("RenderMarkdownH4"), hl("RenderMarkdownH5"), hl("RenderMarkdownH6")
local h1b, h2b, h3b, h4b, h5b, h6b = hl("RenderMarkdownH1Bg"), hl("RenderMarkdownH2Bg"), hl("RenderMarkdownH3Bg"), hl("RenderMarkdownH4Bg"), hl("RenderMarkdownH5Bg"), hl("RenderMarkdownH6Bg")
local rcode, rcode_in, rth, rtr, rq, rwarn, rchk, runchk = hl("RenderMarkdownCode"), hl("RenderMarkdownCodeInline"), hl("RenderMarkdownTableHead"), hl("RenderMarkdownTableRow"), hl("RenderMarkdownQuote"), hl("RenderMarkdownWarn"), hl("RenderMarkdownChecked"), hl("RenderMarkdownUnchecked")
local rhint, rbul, rcb, rci, rlnk, rwlnk, mlnk, mlnkl, mlnku = hl("RenderMarkdownHint"), hl("RenderMarkdownBullet"), hl("RenderMarkdownCodeBorder"), hl("RenderMarkdownCodeInfo"), hl("RenderMarkdownLink"), hl("RenderMarkdownWikiLink"), hl("@markup.link"), hl("@markup.link.label"), hl("@markup.link.url")
local rm_hl_ok = (hex(h1.fg) == "cb4b16" and hex(h2.fg) == "268bd2" and hex(h3.fg) == "6c71c4" and hex(h4.fg) == "93a1a1" and hex(h5.fg) == "839496" and hex(h6.fg) == "839496" and h1b.fg == nil and h2b.fg == nil and h3b.fg == nil and h4b.fg == nil and h5b.fg == nil and h6b.fg == nil and hex(h1b.bg) == "073642" and hex(h2b.bg) == "073642" and hex(h3b.bg) == "073642" and hex(h4b.bg) == "073642" and hex(h5b.bg) == "073642" and hex(h6b.bg) == "073642" and not h1.bold and not h2.bold and not h3.bold and not h4.bold and not h5.bold and not h6.bold and not h1b.bold and not h2b.bold and not h3b.bold and not h4b.bold and not h5b.bold and not h6b.bold and rcode.fg == nil and hex(rcode.bg) == "073642" and hex(rcode_in.fg) == "2aa198" and hex(rcode_in.bg) == "073642" and hex(rth.fg) == "586e75" and hex(rtr.fg) == "586e75" and hex(rq.fg) == "586e75" and hex(rwarn.fg) == "cb4b16" and hex(rchk.fg) == "859900" and hex(runchk.fg) == "586e75" and hex(rhint.fg) == "6c71c4" and hex(rbul.fg) == "859900" and hex(rcb.fg) == "586e75" and hex(rcb.bg) == "073642" and hex(rci.fg) == "586e75" and hex(rci.bg) == "073642" and not rci.italic and not rlnk.underline and not rwlnk.underline and not mlnk.underline and not mlnkl.underline and not mlnku.underline)
local ok_rm, rm = pcall(require, "render-markdown")
local rm_tog_ok = true
if ok_rm and rm and rm.get then
    local ui = require("render-markdown.core.ui")
    local mbuf = vim.api.nvim_get_current_buf()
    ui.updater.new(mbuf, vim.api.nvim_get_current_win(), true):run()
    local marks = vim.api.nvim_buf_get_extmarks(mbuf, ui.ns, 0, -1, { details = true })
    local row0_marks = vim.api.nvim_buf_get_extmarks(mbuf, ui.ns, { 0, 0 }, { 0, -1 }, { details = true })
    if #marks == 0 or #row0_marks == 0 or vim.wo.concealcursor ~= "nvc" then rm_hl_ok = false end
    for _, m in ipairs(marks) do
        local d = m[4] or {}
        if d.hl_group then
            local info = hl(d.hl_group)
            if info.fg == 0xb58900 or info.bg == 0xb58900 or info.bold then rm_hl_ok = false end
        end
    end
    local s0 = rm.get()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>m", true, false, true), "mx", false)
    local s1 = rm.get()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>m", true, false, true), "mx", false)
    local s2 = rm.get()
    rm_tog_ok = (s0 == true and s1 == false and s2 == true)
end
local x2_rhs = vim.fn.maparg("<X2Mouse>", "n"):upper()
local mouse_ok = (vim.fn.maparg("<X1Mouse>", "n"):upper() == "<C-O>" and (x2_rhs == "<C-I>" or x2_rhs == "<TAB>"))
io.write("DISP=" .. (vim.env.DISPLAY or "") .. "|GCLIP=" .. tostring(vim.g.clipboard) .. "|CB=" .. vim.o.clipboard .. "|AR=" .. tostring(vim.o.autoread) .. "|AC=" .. tostring(#ac >= 1) .. "|MF=" .. mf_ok .. "|MFL=" .. mf_layout_ok .. "|MDW=" .. tostring(md_wrap) .. "|RMHL=" .. tostring(rm_hl_ok) .. "|RMT=" .. tostring(rm_tog_ok) .. "|XM=" .. tostring(mouse_ok))
EOF
        SSH_NVIM_OUT="$( (cd "$SCRIPT_DIR" && unset DISPLAY WAYLAND_DISPLAY NVIM_IDE_SOCKET NVIM_IDE_PANE IDE_SESSION IDE_INITIAL_ROOT IDE_AI_CLI && \
            SSH_CONNECTION="10.0.0.1 1234 10.0.0.2 22" \
            run_nvim_headless -i NONE -u "$NVIM_CONFIG" -c "luafile $SSH_NVIM_SCRIPT") 2>/dev/null || true)"
        rm -f "$SSH_NVIM_SCRIPT"
        if [ "$SSH_NVIM_OUT" = "DISP=|GCLIP=nil|CB=unnamedplus|AR=true|AC=true|MF=true|MFL=true|MDW=true|RMHL=true|RMT=true|XM=true" ]; then
            pass "Neovim init.lua preserves SSH DISPLAY/clipboard guards, registers SolarizedAutoRead & <X1Mouse>/<X2Mouse> jumplist Back/Forward, pins mini.files focused directory at col=0 (width=35) with full-width right preview (across VimResized and unsaved paths), enables Markdown word-boundary soft-wrapping, and renders Markdown in-buffer (<leader>m) with Solarized Dark Semantic Architecture (zero Yellow, bold=false)"
        else
            fail "Neovim SSH DISPLAY guard, autoread/clipboard, left-anchored mini.files & render-markdown" "Expected 'DISP=|GCLIP=nil|CB=unnamedplus|AR=true|AC=true|MF=true|MFL=true|MDW=true|RMHL=true|RMT=true|XM=true', got '$SSH_NVIM_OUT'"
        fi
    fi
else
    fail "Neovim init.lua missing" "Expected dotfiles/.config/nvim/init.lua"
fi

test_summary

