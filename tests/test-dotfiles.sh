#!/usr/bin/env bash
# Test suite for declarative dotfiles auto-discovery, drop-in directories, and linking

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/tests/test-helper.sh"

echo "========================================"
echo "Running Declarative Dotfiles Tests"
echo "========================================"

# Test 1: Module syntax check
echo -e "\n[1/5] Checking module syntax..."
if bash -n "$SCRIPT_DIR/modules/10-dotfiles.sh"; then
    pass "Syntax valid: modules/10-dotfiles.sh"
else
    fail "modules/10-dotfiles.sh" "bash -n returned non-zero"
fi

# Test 2: Auto-discovery in temporary HOME
echo -e "\n[2/5] Testing declarative dotfiles auto-discovery..."
TEMP_HOME=$(mktemp -d)
trap 'rm -rf "$TEMP_HOME"' EXIT

HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" "$SCRIPT_DIR/modules/10-dotfiles.sh" >/dev/null 2>&1

expected_top_level=(
    ".environment-variables"
    ".bashrc-addendum"
    ".zshrc-addendum"
    ".aliases"
    ".zsh-functions"
    ".zsh-completions"
    ".p10k.zsh"
    ".vimrc"
    ".tmux.conf"
)

for df in "${expected_top_level[@]}"; do
    assert_symlink "$TEMP_HOME/$df" "" "Auto-discovered and symlinked: $df"
done

if [ -f "$TEMP_HOME/.tmux.conf" ] && \
   grep -q 'default-terminal "tmux-256color"' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'RGB:extkeys:usstyle:clipboard' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'allow-passthrough on' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'copy-command' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'MouseDragEnd1Pane' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'Smulx=' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'Setulc=' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'pane-border-style "fg=#586E75,bg=#002B36"' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'pane-active-border-style "fg=#586E75,bg=#002B36"' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'popup-border-style "fg=#586E75,bg=#002B36"' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'mode-style "fg=#93A1A1,bg=#073642"' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'status-style "fg=#839496,bg=#073642"' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'pane_current_command' "$TEMP_HOME/.tmux.conf" && \
   grep -q '{top-right}' "$TEMP_HOME/.tmux.conf" && \
   grep -q '{bottom-right}' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-h' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-z resize-pane -Z' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-a' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'IDE_AI_CLI' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'claude' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'codex' "$TEMP_HOME/.tmux.conf"; then
    pass ".tmux.conf configures Solarized Dark framing, TrueColor undercurls, xclip/OSC52 clipboard pipeline, role-aware 3-pane navigation, and Alt+z/Alt+a bindings"
else
    fail ".tmux.conf verification" "Missing expected Solarized Dark, clipboard, navigation, or keybinding settings in .tmux.conf"
fi

if command -v tmux >/dev/null 2>&1; then
    TMUX_TEST_SOCK="test-tmux-cfg-$$"
    if tmux -L "$TMUX_TEST_SOCK" -f "$TEMP_HOME/.tmux.conf" new-session -d -s cfg_test >/dev/null 2>&1; then
        tmux -L "$TMUX_TEST_SOCK" kill-server >/dev/null 2>&1 || true
        pass ".tmux.conf loads cleanly into live headless tmux server without errors"
    else
        tmux -L "$TMUX_TEST_SOCK" kill-server >/dev/null 2>&1 || true
        fail ".tmux.conf live load" "tmux reported errors loading dotfiles/.tmux.conf"
    fi
fi

if [ ! -e "$TEMP_HOME/.zsh-aliases" ]; then
    pass "Legacy .zsh-aliases symlink is cleanly retired"
else
    fail "Legacy .zsh-aliases" "Found retired .zsh-aliases symlink"
fi

assert_symlink "$TEMP_HOME/.dir-colors/dircolors" "" "Auto-discovered and symlinked: .dir-colors/dircolors"
assert_symlink "$TEMP_HOME/.config/nvim" "" "Auto-discovered and symlinked: .config/nvim"
if [ -f "$TEMP_HOME/.config/nvim/ftplugin/java.lua" ] && grep -q 'jdtls' "$TEMP_HOME/.config/nvim/ftplugin/java.lua"; then
    pass "Auto-discovered and symlinked: .config/nvim/ftplugin/java.lua"
else
    fail "Java ftplugin symlink" "Expected .config/nvim/ftplugin/java.lua in mirrored dotfiles"
fi
if [ -f "$TEMP_HOME/.config/nvim/after/queries/javascript/highlights.scm" ] && \
   grep -q '"process"' "$TEMP_HOME/.config/nvim/after/queries/javascript/highlights.scm" && \
   [ -f "$TEMP_HOME/.config/nvim/after/queries/typescript/highlights.scm" ] && \
   grep -q '"process"' "$TEMP_HOME/.config/nvim/after/queries/typescript/highlights.scm"; then
    pass "Auto-discovered and symlinked: JavaScript and TypeScript Tree-sitter query overrides"
else
    fail "JS/TS queries symlink" "Expected after/queries/javascript and after/queries/typescript in mirrored .config/nvim"
fi
assert_symlink "$TEMP_HOME/.config/ghostty" "" "Auto-discovered and symlinked: .config/ghostty"
assert_symlink "$TEMP_HOME/.config/clangd" "" "Auto-discovered and symlinked: .config/clangd"
if [ -f "$TEMP_HOME/.config/clangd/config.yaml" ] && \
   grep -q 'std=gnu++20' "$TEMP_HOME/.config/clangd/config.yaml" && \
   grep -q 'std=gnu23' "$TEMP_HOME/.config/clangd/config.yaml"; then
    pass "clangd config contains gnu++20 and gnu23 fallback compile flags"
else
    fail "clangd config verification" "Missing or invalid .config/clangd/config.yaml"
fi

if [ -f "$TEMP_HOME/.config/ghostty/config" ] && \
   grep -q 'theme = "Solarized Dark"' "$TEMP_HOME/.config/ghostty/config" && \
   grep -q 'font-family = "MesloLGS Nerd Font Mono"' "$TEMP_HOME/.config/ghostty/config" && \
   grep -q 'macos-option-as-alt = true' "$TEMP_HOME/.config/ghostty/config"; then
    pass "Ghostty config contains Solarized Dark theme, MesloLGS Nerd Font Mono font family, and macos-option-as-alt = true"
else
    fail "Ghostty config verification" "Ghostty config missing expected theme, font, or macos-option-as-alt"
fi

if [ -f "$TEMP_HOME/.config/ghostty/themes/Solarized Dark" ]; then
    pass "Ghostty themes directory contains Solarized Dark theme"
else
    fail "Ghostty themes verification" "Missing Solarized Dark theme in themes directory"
fi

if command -v ghostty >/dev/null 2>&1; then
    if XDG_CONFIG_HOME="$TEMP_HOME/.config" ghostty +validate-config --config-file="$TEMP_HOME/.config/ghostty/config" >/dev/null 2>&1; then
        pass "Ghostty config passes native ghostty +validate-config"
    else
        fail "Ghostty validation" "ghostty +validate-config failed on installed config"
    fi
fi

assert_symlink "$TEMP_HOME/.config/btop" "" "Auto-discovered and symlinked: .config/btop"
if [ -f "$TEMP_HOME/.config/btop/btop.conf" ] && \
   grep -q 'color_theme = "solarized_dark"' "$TEMP_HOME/.config/btop/btop.conf" && \
   grep -q 'truecolor = true' "$TEMP_HOME/.config/btop/btop.conf" && \
   grep -q 'vim_keys = true' "$TEMP_HOME/.config/btop/btop.conf"; then
    pass "btop config contains solarized_dark theme, truecolor = true, and vim_keys = true"
else
    fail "btop config verification" "Missing expected solarized_dark theme, truecolor, or vim_keys in .config/btop/btop.conf"
fi

if [ -f "$TEMP_HOME/.config/btop/themes/solarized_dark.theme" ] && \
   grep -q 'theme\[main_bg\]="#002b36"' "$TEMP_HOME/.config/btop/themes/solarized_dark.theme" && \
   grep -q 'theme\[main_fg\]="#839496"' "$TEMP_HOME/.config/btop/themes/solarized_dark.theme" && \
   grep -q 'theme\[cpu_box\]="#586e75"' "$TEMP_HOME/.config/btop/themes/solarized_dark.theme" && \
   grep -q 'theme\[hi_fg\]="#b58900"' "$TEMP_HOME/.config/btop/themes/solarized_dark.theme"; then
    pass "btop theme contains authentic Solarized Dark palette tokens"
else
    fail "btop theme verification" "Missing or invalid solarized_dark.theme in .config/btop/themes"
fi

assert_symlink "$TEMP_HOME/.config/git" "" "Auto-discovered and symlinked: .config/git"
if [ -f "$TEMP_HOME/.config/git/config" ] && \
   grep -q 'pager = delta' "$TEMP_HOME/.config/git/config" && \
   grep -q 'syntax-theme = Solarized-Dark-TrueColor' "$TEMP_HOME/.config/git/config" && \
   grep -q 'line-numbers-plus-style = "#859900"' "$TEMP_HOME/.config/git/config" && \
   grep -q 'line-numbers-minus-style = "#dc322f"' "$TEMP_HOME/.config/git/config"; then
    pass "git config configures delta with Solarized-Dark-TrueColor theme and line numbers"
else
    fail "git config verification" "Missing expected delta pager configuration in .config/git/config"
fi

assert_symlink "$TEMP_HOME/.config/lazygit" "" "Auto-discovered and symlinked: .config/lazygit"
if [ -f "$TEMP_HOME/.config/lazygit/config.yml" ] && \
   grep -q 'pager: delta --dark --paging=never' "$TEMP_HOME/.config/lazygit/config.yml" && \
   grep -q "activeBorderColor:" "$TEMP_HOME/.config/lazygit/config.yml" && \
   grep -q "'#268bd2'" "$TEMP_HOME/.config/lazygit/config.yml" && \
   grep -q "'#073642'" "$TEMP_HOME/.config/lazygit/config.yml" && \
   grep -q 'nerdFontsVersion: "3"' "$TEMP_HOME/.config/lazygit/config.yml"; then
    pass "lazygit config contains Solarized Dark TrueColor theme and delta pager integration"
else
    fail "lazygit config verification" "Missing or invalid config.yml in .config/lazygit"
fi

assert_symlink "$TEMP_HOME/.config/tealdeer" "" "Auto-discovered and symlinked: .config/tealdeer"
if [ -f "$TEMP_HOME/.config/tealdeer/config.toml" ] && \
   grep -q '\[style\.command_name\]' "$TEMP_HOME/.config/tealdeer/config.toml" && \
   grep -q '\[style\.description\]' "$TEMP_HOME/.config/tealdeer/config.toml" && \
   grep -q 'r = 131, g = 148, b = 150' "$TEMP_HOME/.config/tealdeer/config.toml"; then
    pass "tealdeer config contains Solarized Dark TrueColor styling"
else
    fail "tealdeer config verification" "Missing or invalid config.toml in .config/tealdeer"
fi

assert_symlink "$TEMP_HOME/.config/bat/themes/Solarized-Dark-TrueColor.tmTheme" "" "Symlinked Bat theme"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/C.sublime-syntax" "" "Symlinked Bat C syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/C++.sublime-syntax" "" "Symlinked Bat C++ syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Diff.sublime-syntax" "" "Symlinked Bat Diff syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Go.sublime-syntax" "" "Symlinked Bat Go syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Java.sublime-syntax" "" "Symlinked Bat Java syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Python.sublime-syntax" "" "Symlinked Bat Python syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Rust.sublime-syntax" "" "Symlinked Bat Rust syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Bash.sublime-syntax" "" "Symlinked Bat Bash syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/SQL.sublime-syntax" "" "Symlinked Bat SQL syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Terraform.sublime-syntax" "" "Symlinked Bat Terraform syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Markdown.sublime-syntax" "" "Symlinked Bat Markdown syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/TypeScript.sublime-syntax" "" "Symlinked Bat TypeScript syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/XML.sublime-syntax" "" "Symlinked Bat XML syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/HTML.sublime-syntax" "" "Symlinked Bat HTML syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/JSON.sublime-syntax" "" "Symlinked Bat JSON syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/TOML.sublime-syntax" "" "Symlinked Bat TOML syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/CSS.sublime-syntax" "" "Symlinked Bat CSS syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/JavaProperties.sublime-syntax" "" "Symlinked Bat Java Properties syntax"

THEME_FILE="$SCRIPT_DIR/colors/Solarized-Dark-TrueColor.tmTheme"
if grep -q "<string>markup.heading" "$THEME_FILE" && \
   grep -q "<string>markup.bold" "$THEME_FILE" && \
   grep -q "<string>markup.italic" "$THEME_FILE" && \
   grep -q "<string>markup.raw.inline" "$THEME_FILE" && \
   grep -q "<string>markup.underline.link" "$THEME_FILE" && \
   grep -q "<string>markup.quote" "$THEME_FILE" && \
   grep -q "<string>punctuation.definition.list_item" "$THEME_FILE" && \
   grep -q "meta.preprocessor" "$THEME_FILE" && \
   grep -q "storage.type.annotation" "$THEME_FILE" && \
   grep -q "<string>markup.inserted" "$THEME_FILE" && \
   grep -q "<string>constant.character.escape, constant.other.placeholder" "$THEME_FILE" && \
   grep -q "<string>invalid, invalid.illegal" "$THEME_FILE" && \
   grep -q "<string>entity.name.namespace, entity.name.module, support.module, entity.name.scope-resolution" "$THEME_FILE" && \
   grep -q "entity.other.inherited-class" "$THEME_FILE" && \
   grep -q "entity.name.attribute" "$THEME_FILE" && \
   grep -q "string.special.path.diff" "$THEME_FILE" && \
   grep -q "meta.diff.range" "$THEME_FILE" && \
   grep -q "variable.language" "$THEME_FILE" && \
   grep -q "storage.type.function" "$THEME_FILE" && \
   grep -q "storage.type.impl" "$THEME_FILE" && \
   grep -q "variable.other.constant" "$THEME_FILE" && \
   grep -q "text.xml entity.name.tag" "$THEME_FILE" && \
   grep -q "text.xml keyword.other.directive" "$THEME_FILE" && \
   grep -q "text.html entity.name.tag" "$THEME_FILE" && \
   grep -q "text.html keyword.other.directive.doctype" "$THEME_FILE" && \
   grep -q "entity.name.tag.json" "$THEME_FILE" && \
   grep -q "entity.name.tag.yaml" "$THEME_FILE" && \
   grep -q "entity.name.section.table.toml" "$THEME_FILE" && \
   grep -q "entity.name.tag.toml" "$THEME_FILE" && \
   grep -q "keyword.control.at-rule.css" "$THEME_FILE" && \
   grep -q "support.type.property-name.css" "$THEME_FILE" && \
   grep -q "variable, variable.other, variable.parameter" "$THEME_FILE"; then
    pass "Solarized-Dark-TrueColor.tmTheme defines complete Markdown, C/C++, Java, Diff, Go, Python, Rust, Bash, XML, HTML, JSON, YAML, TOML, CSS, Namespace, Attribute, and Error scopes"
else
    fail "Bat theme scope completeness" "Missing required scopes in Solarized-Dark-TrueColor.tmTheme"
fi

BAT_BIN=""
if command -v bat >/dev/null 2>&1; then
    BAT_BIN="bat"
elif command -v batcat >/dev/null 2>&1; then
    BAT_BIN="batcat"
fi

if [ -n "$BAT_BIN" ]; then
    export COLORTERM="truecolor"
    MD_OUT="$(printf "# Header 1\n## Header 2\n### Header 3\n#### Header 4\n**bold text**\n" | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l md - 2>/dev/null || true)"
    BASE1_BOLD="$(printf "\033[1;38;2;147;161;161m")"
    if grep -Fq "${SOL_BASE01}#" <<< "$MD_OUT" && \
       grep -Fq "${SOL_ORANGE}Header 1" <<< "$MD_OUT" && \
       grep -Fq "${SOL_BASE01}##" <<< "$MD_OUT" && \
       grep -Fq "${SOL_BLUE}Header 2" <<< "$MD_OUT" && \
       grep -Fq "${SOL_BASE01}###" <<< "$MD_OUT" && \
       grep -Fq "${SOL_VIOLET}Header 3" <<< "$MD_OUT" && \
       grep -Fq "${SOL_BASE01}####" <<< "$MD_OUT" && \
       grep -Fq "${SOL_BASE1}Header 4" <<< "$MD_OUT" && \
       grep -Fq "$BASE1_BOLD" <<< "$MD_OUT" && \
       ! grep -Fq "$SOL_YELLOW" <<< "$MD_OUT"; then
        pass "bat renders Markdown headings with Semantic Architecture (H1 Orange, H2 Blue, H3 Violet, H4 Base1, Base01 markers, no Yellow) and Base1 bold text"
    else
        fail "bat Markdown rendering" "Expected H1 Orange, H2 Blue, H3 Violet, H4 Base1, Base01 markers, no Yellow, and Base1 bold in bat output"
    fi

    C_OUT="$(echo -e "#include <stdio.h>" | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "$SOL_ORANGE" <<< "$C_OUT"; then
        pass "bat renders C/C++ preprocessor directives in Solarized Orange"
    else
        fail "bat C preprocessor rendering" "Expected Orange preprocessor directive in bat output"
    fi

    DIFF_OUT="$(echo -e "--- a\n+++ b\n-old\n+new" | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l diff - 2>/dev/null || true)"
    if grep -Fq "$SOL_GREEN" <<< "$DIFF_OUT" && grep -Fq "$SOL_RED" <<< "$DIFF_OUT"; then
        pass "bat renders Unified Diffs with Solarized Green additions and Red deletions"
    else
        fail "bat Diff rendering" "Expected Green additions and Red deletions in bat diff output"
    fi

    QUOTE_OUT="$(printf "> quote text\n" | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l md - 2>/dev/null || true)"
    if grep -Fq "$SOL_BASE0" <<< "$QUOTE_OUT" && grep -Fq "$SOL_BASE01" <<< "$QUOTE_OUT"; then
        pass "bat renders Markdown blockquotes in Solarized Base0 with Base01 marker"
    else
        fail "bat blockquote rendering" "Expected Base0 text and Base01 marker in bat blockquote output"
    fi

    GO_OUT="$(printf "type MyStruct struct {}\n" | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l go - 2>/dev/null || true)"
    if grep -Fq "$SOL_BASE0" <<< "$GO_OUT"; then
        pass "bat renders custom struct types in calm Base0"
    else
        fail "bat custom type rendering" "Expected Base0 struct type in bat output"
    fi

    C_TYPE_OUT="$(printf "int x = 42;\n" | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "$SOL_GREEN" <<< "$C_TYPE_OUT"; then
        pass "bat renders primitive C types (int, char, etc.) in Solarized Green"
    else
        fail "bat primitive type rendering" "Expected Green primitive type in bat output"
    fi

    C_STR_OUT="$(printf 'printf("Hello %%s\\n");\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "$SOL_CYAN" <<< "$C_STR_OUT"; then
        pass "bat renders string format specifiers and escapes in Solarized Cyan"
    else
        fail "bat string escape rendering" "Expected Cyan string escape in bat output"
    fi

    C_DECL_OUT="$(printf "typedef struct {\n    int x;\n} Node;\n" | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}typedef" <<< "$C_DECL_OUT" && grep -Fq "${SOL_GREEN}struct" <<< "$C_DECL_OUT"; then
        pass "bat renders C declaration keywords (typedef, struct) in Solarized Green"
    else
        fail "bat C declaration rendering" "Expected Green typedef/struct in bat output"
    fi

    ESC_ITALIC="$(printf "\033[3;")"
    C_MACRO_OUT="$(printf '#define CLAMP(x, low, high) (((x) > (high)) ? (high) : (x))\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" BAT_OPTS="--italic-text=always" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}#define" <<< "$C_MACRO_OUT" && \
       grep -Fq "${SOL_BASE0}x" <<< "$C_MACRO_OUT" && \
       ! grep -Fq "$ESC_ITALIC" <<< "$C_MACRO_OUT"; then
        pass "bat renders macro parameters and body expressions in upright Solarized Base0 (grey) matching Neovim"
    else
        fail "bat macro parameter rendering" "Expected upright Base0 grey parameters and body expressions in macro"
    fi

    C_COMMENT_OUT="$(printf '/* sample comment */\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" BAT_OPTS="--italic-text=always" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "$SOL_BASE01" <<< "$C_COMMENT_OUT" && ! grep -Fq "$ESC_ITALIC" <<< "$C_COMMENT_OUT"; then
        pass "bat renders C comments in upright Solarized Base01 without italics"
    else
        fail "bat comment rendering" "Expected upright Base01 comment without italics in bat output"
    fi

    MD_ITALIC_OUT="$(printf '*explicit italic*\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" BAT_OPTS="--italic-text=always" "$BAT_BIN" --color=always -l md - 2>/dev/null || true)"
    if grep -Fq "$ESC_ITALIC" <<< "$MD_ITALIC_OUT"; then
        pass "bat renders explicitly tagged Markdown *italic* with true italics"
    else
        fail "bat markdown italic rendering" "Expected italics on explicitly tagged Markdown"
    fi

    # --- 2.2 C Syntax Verification ---
    C_PREPROC_OUT="$(printf '#ifndef LOG_LEVEL\n#define LOG_LEVEL 2\n#endif\n#ifdef __linux__\n#undef LOG_LEVEL\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}#ifndef" <<< "$C_PREPROC_OUT" && \
       grep -Fq "${SOL_ORANGE}LOG_LEVEL" <<< "$C_PREPROC_OUT" && \
       grep -Fq "${SOL_ORANGE}#ifdef" <<< "$C_PREPROC_OUT" && \
       grep -Fq "${SOL_ORANGE}__linux__" <<< "$C_PREPROC_OUT" && \
       grep -Fq "${SOL_ORANGE}#undef" <<< "$C_PREPROC_OUT"; then
        pass "bat renders preprocessor macro identifiers in conditional directives (#ifndef LOG_LEVEL, #ifdef, #undef) in Solarized Orange"
    else
        fail "bat preprocessor conditional macro rendering" "Expected Solarized Orange macro identifiers in preprocessor conditionals"
    fi

    C_CONST_OUT="$(printf 'int res = EXIT_FAILURE;\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_MAGENTA}EXIT_FAILURE" <<< "$C_CONST_OUT"; then
        pass "bat renders named uppercase constants (EXIT_FAILURE, etc.) in Solarized Magenta"
    else
        fail "bat constant rendering" "Expected Magenta named constants in bat output"
    fi

    C_CUSTOM_TYPE_OUT="$(printf 'WorkerNode *node = malloc(sizeof(WorkerNode));\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_BASE0}WorkerNode" <<< "$C_CUSTOM_TYPE_OUT"; then
        pass "bat renders custom PascalCase types (WorkerNode, etc.) in calm Solarized Base0"
    else
        fail "bat custom type rendering" "Expected Base0 custom PascalCase type in bat output"
    fi

    C_WORD_OP_OUT="$(printf 'sizeof(int);\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}sizeof" <<< "$C_WORD_OP_OUT"; then
        pass "bat renders word operators (sizeof, etc.) in Solarized Green matching Neovim"
    else
        fail "bat word operator rendering" "Expected Green sizeof in bat output"
    fi

    C_FUNC_CALL_OUT="$(printf 'emit_log(0, "test");\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_BASE0}emit_log" <<< "$C_FUNC_CALL_OUT"; then
        pass "bat renders user function calls (emit_log, etc.) in calm Solarized Base0 matching Neovim"
    else
        fail "bat function call rendering" "Expected Base0 emit_log call in bat output"
    fi

    C_CTRL_OUT="$(printf 'if (node == NULL) return EXIT_FAILURE;\nswitch (level) { case 0: break; default: break; }\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_YELLOW}if" <<< "$C_CTRL_OUT" && \
       grep -Fq "${SOL_YELLOW}return" <<< "$C_CTRL_OUT" && \
       grep -Fq "${SOL_YELLOW}switch" <<< "$C_CTRL_OUT" && \
       grep -Fq "${SOL_YELLOW}case" <<< "$C_CTRL_OUT"; then
        pass "bat renders C control flow (if, return, switch, case) in Solarized Yellow matching Neovim"
    else
        fail "bat C control flow rendering" "Expected Yellow if, return, switch, case in bat output"
    fi

    # --- 2.3 C++ Syntax Verification ---
    CPP_TEMPLATE_OUT="$(printf 'template <Printable T>\nclass Node {\nstd::vector<T> items;\n};\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_BASE0}T" <<< "$CPP_TEMPLATE_OUT"; then
        pass "bat renders C++ template type parameters (T in template <... T> and vector<T>) in calm Solarized Base0 matching Neovim"
    else
        fail "bat template type parameter rendering" "Expected Base0 template type parameter in bat output"
    fi

    if grep -Fq "${SOL_BASE0}Printable" <<< "$CPP_TEMPLATE_OUT"; then
        pass "bat renders C++ concept names (Printable) in calm Solarized Base0 matching Neovim"
    else
        fail "bat concept name rendering" "Expected Base0 concept name in bat output"
    fi

    if grep -Fq "${SOL_BASE0}vector" <<< "$CPP_TEMPLATE_OUT"; then
        pass "bat renders C++ STL container types (vector, optional) in calm Solarized Base0 matching Neovim"
    else
        fail "bat STL container rendering" "Expected Base0 STL container type in bat output"
    fi

    CPP_DECL_NS_OUT="$(printf 'namespace core::telemetry {\n}\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}namespace" <<< "$CPP_DECL_NS_OUT" && \
       grep -Fq "${SOL_VIOLET}core" <<< "$CPP_DECL_NS_OUT" && \
       grep -Fq "${SOL_VIOLET}telemetry" <<< "$CPP_DECL_NS_OUT"; then
        pass "bat renders namespace declaration keywords in Solarized Green and namespace identifiers (core, telemetry) in Solarized Violet matching Neovim"
    else
        fail "bat namespace definition rendering" "Expected Green namespace keyword and Violet core::telemetry identifiers in bat output"
    fi

    CPP_NS_OUT="$(printf 'using namespace core::telemetry;\nstd::string s;\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}using" <<< "$CPP_NS_OUT" && \
       grep -Fq "${SOL_VIOLET}core" <<< "$CPP_NS_OUT" && \
       grep -Fq "${SOL_VIOLET}telemetry" <<< "$CPP_NS_OUT" && \
       grep -Fq "${SOL_BASE0}std" <<< "$CPP_NS_OUT"; then
        pass "bat renders using namespace keywords in Solarized Green, namespace targets (core, telemetry) in Solarized Violet, and qualifiers (std) in calm Base0 Grey matching Neovim"
    else
        fail "bat using namespace rendering" "Expected Green using keyword, Violet namespace targets, and Base0 qualifiers in bat output"
    fi

    CPP_CONST_OUT="$(printf 'NodeState state_{NodeState::Initializing};\nreturn std::nullopt;\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_MAGENTA}Initializing" <<< "$CPP_CONST_OUT" && \
       grep -Fq "${SOL_MAGENTA}nullopt" <<< "$CPP_CONST_OUT"; then
        pass "bat renders scoped enum constants (NodeState::Initializing) and sentinels (std::nullopt) in Solarized Magenta matching Neovim"
    else
        fail "bat scoped constant rendering" "Expected Magenta scoped constants and sentinels in bat output"
    fi

    if grep -Fq "${SOL_BASE0} state_" <<< "$CPP_CONST_OUT" && ! grep -Fq "${SOL_BLUE}state_" <<< "$CPP_CONST_OUT"; then
        pass "bat renders member variable uniform initialization (state_{...}) in upright Solarized Base0 (grey) matching Neovim"
    else
        fail "bat uniform initialization rendering" "Expected Base0 grey variable in uniform initialization"
    fi

    CPP_CONCEPT_OUT="$(printf '{ std::cout << t } -> std::same_as<std::ostream&>;\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_BASE0}same_as" <<< "$CPP_CONCEPT_OUT"; then
        pass "bat renders standard C++20 concepts (same_as) in calm Solarized Base0 matching Neovim"
    else
        fail "bat C++20 concept rendering" "Expected Base0 same_as concept in bat output"
    fi

    CPP_ENUM_OUT="$(printf 'enum class NodeState : uint8_t {\n};\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_BASE0}NodeState" <<< "$CPP_ENUM_OUT" && \
       grep -Fq "${SOL_GREEN}uint8_t" <<< "$CPP_ENUM_OUT"; then
        pass "bat renders enum class types in calm Solarized Base0 and underlying primitive types (uint8_t) in Solarized Green matching Neovim"
    else
        fail "bat enum type rendering" "Expected Base0 enum name and Green underlying type in bat output"
    fi

    CPP_QUAL_FUNC_OUT="$(printf 'void test() {\n    std::move(metric);\n    std::for_each(items.begin(), items.end());\n}\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_BASE0}std" <<< "$CPP_QUAL_FUNC_OUT" && \
       grep -Fq "${SOL_BASE0}move" <<< "$CPP_QUAL_FUNC_OUT" && \
       grep -Fq "${SOL_BASE0}for_each" <<< "$CPP_QUAL_FUNC_OUT"; then
        pass "bat renders namespace-qualified function calls (std::move, std::for_each) with Base0 Grey namespace and function matching Neovim"
    else
        fail "bat qualified function rendering" "Expected Base0 Grey std and Base0 move/for_each in bat output"
    fi

    CPP_ATTR_OUT="$(printf '[[nodiscard]] constexpr uint64_t id();\n' | HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}[[" <<< "$CPP_ATTR_OUT" && \
       grep -Fq "${SOL_VIOLET}nodiscard" <<< "$CPP_ATTR_OUT" && \
       grep -Fq "${SOL_VIOLET}]]" <<< "$CPP_ATTR_OUT"; then
        pass "bat renders C++ attributes ([[nodiscard]]) in Solarized Violet matching Neovim"
    else
        fail "bat attribute rendering" "Expected Violet [[nodiscard]] in bat output"
    fi

    # --- 2.4 Diff Syntax Verification ---
    DIFF_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l diff "$SCRIPT_DIR/sample-code/sample.diff" 2>/dev/null || true)"
    if grep -Fq "${SOL_BLUE}diff" <<< "$DIFF_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}a/src/service/cluster_manager.go" <<< "$DIFF_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}4b825dc" <<< "$DIFF_SAMPLE_OUT" && \
       grep -Fq "${SOL_RED}---" <<< "$DIFF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}+++" <<< "$DIFF_SAMPLE_OUT" && \
       (grep -Fq "${SOL_BLUE}@@ -32,18 +32,20 @@" <<< "$DIFF_SAMPLE_OUT" || \
        grep -Fq "${SOL_BLUE}@@ -32,18 +32,22 @@" <<< "$DIFF_SAMPLE_OUT"); then
        if grep -Fq "${SOL_RED}-" <<< "$DIFF_SAMPLE_OUT" && \
           grep -Fq "${SOL_GREEN}+" <<< "$DIFF_SAMPLE_OUT"; then
            pass "bat renders diff additions (Green), deletions (Red), hunk headers (Blue), paths (Cyan), and hashes (Magenta) matching Neovim"
        else
            fail "bat diff rendering" "Expected Red - and Green + in bat diff output"
        fi
    else
        fail "bat diff rendering" "Expected Blue diff/@@, Red ---, Green +++, Cyan path, Magenta hash in bat output"
    fi

    # --- 2.5 Go Syntax Verification ---
    GO_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l go "$SCRIPT_DIR/sample-code/sample.go" 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}package" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}main" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}import" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}type" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}func" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}struct" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}interface" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}context" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Context" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}ClusterNode" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}int" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}string" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}LevelDebug" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}MaskAll" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}NewClusterNode" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}return" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}select" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}defer" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}case" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}default" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}panic" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}make" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}\`json:\"port\"\`" <<< "$GO_SAMPLE_OUT"; then
        pass "bat renders Converged Ergonomic Go: structural scaffolding & primitive types (Green package/type/func/struct/interface/int/string), control flow (Yellow if/return/select/defer/case/default), function calls & builtins (Base0 panic/make), custom types in calm Base0 (Context/ClusterNode), method declarations (Blue NewClusterNode), package identity & imports (Violet main/import), constants & sentinels (Magenta LevelDebug/MaskAll/iota/nil), struct tags (Cyan), and qualifiers (Base0 context.) matching Neovim"
    else
        fail "bat Go rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.go output"
    fi

    # --- 2.6 Java Syntax Verification ---
    JAVA_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l java "$SCRIPT_DIR/sample-code/sample.java" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}import" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}java" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Instant" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@interface" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}public" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}class" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}interface" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}record" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}implements" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}int" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}OrderRecord" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}DEFAULT_BUFFER_SIZE" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}1L" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@Service" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@Override" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}findById" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}throw" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}when" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}default" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}100.0" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}new" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}this" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}super" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}///" <<< "$JAVA_SAMPLE_OUT"; then
        pass "bat renders Converged Ergonomic Java: structural scaffolding & primitive types (Green public/class/implements/new/this/super/int), control flow (Yellow if/throw/when/default), custom types in calm Base0 (Instant/OrderRecord), method declarations (Blue findById), annotations & imports (Violet @interface/@Service/import), constants & numbers (Magenta DEFAULT_BUFFER_SIZE/1L/100.0), and comments (Base01 ///) matching Neovim"
    else
        fail "bat Java rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.java output"
    fi

    # --- 2.7 Python Syntax Verification ---
    PYTHON_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l py "$SCRIPT_DIR/sample-code/sample.py" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}from" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}asyncio" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}typing" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Callable" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}EndpointMetrics" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}int" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}float" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}str" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}bool" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}dict" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}list" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}set" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}tuple" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}DEFAULT_PORT" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0xFF00_AA55" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}3.1415926535" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}def" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}timed_execution" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}async" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}try" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}return" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}await" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}finally" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@dataclass" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@property" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}self" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}None" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}MetricsCollector" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}__init__" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}__name__" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}.4f" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}\"\"\"" <<< "$PYTHON_SAMPLE_OUT"; then
        pass "bat renders Python imports/modules/decorators (Violet), built-in types (Green int/float/str/bool/dict/list/set/tuple), custom types/classes (Base0 Callable/EndpointMetrics), constants/self/None (Magenta), scaffolding (Green def/async), control flow (Yellow try/return/await/if), format specifiers (.4f in Cyan), and declarations (Blue) matching Neovim"
    else
        fail "bat Python rendering" "Expected Modern Python Solarized TrueColor highlights in bat sample.py output"
    fi

    # --- 2.8 Rust Syntax Verification ---
    RUST_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l rs "$SCRIPT_DIR/sample-code/sample.rs" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}use" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}std" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}collections" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}HashMap" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}const" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}MAX_CONNECTIONS" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}usize" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0xCAFE_BABE" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}#[" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}derive" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}]" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Debug" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}pub" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}enum" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}NodeStatus" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}Starting" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}trait" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Repository" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}T" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}fn" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}find_by_id" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}'a" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}self" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}struct" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}ServerNode" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}where" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}impl" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}match" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}write" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}let" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}mut" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}println" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}///" <<< "$RUST_SAMPLE_OUT"; then
        pass "bat renders Rust imports/attributes (Violet), custom types (Base0), primitive types & scaffolding/lifetimes (Green), control flow (Yellow), constants/variants/self (Magenta), and macro/function declarations (Blue) matching Neovim"
    else
        fail "bat Rust rendering" "Expected Modern Rust Solarized TrueColor highlights in bat sample.rs output"
    fi

    # --- 2.9 Bash Syntax Verification ---
    SH_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l sh "$SCRIPT_DIR/sample-code/sample.sh" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}#!/bin/bash" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}set" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}SCRIPT_NAME" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}basename" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}readonly" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}WORK_DIR" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}XDG_CACHE_HOME" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}HOME" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}MAX_RETRIES" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}5" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}declare" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}ACTIVE_SERVICES" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}nginx" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}cleanup" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}local" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}?" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}then" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}printf" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}trap" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}EXIT" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}log_status" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}log_status" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}1" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}2" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}case" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}esac" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}render_banner" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}cat" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}EOF" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}check_services" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}check_services" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}for" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}in" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}do" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}done" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}mkdir" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}main" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}main" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}>&${SOL_RESET}${SOL_MAGENTA}2" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}INFO${SOL_RESET}${SOL_BASE0})" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}*${SOL_RESET}${SOL_BASE0})" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}[${SOL_RESET}${SOL_CYAN}@${SOL_RESET}${SOL_BASE0}]" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}\$" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}\${" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}@" <<< "$SH_SAMPLE_OUT"; then
        pass "bat renders Converged Ergonomic Shell: shebang (Orange), scaffolding & declarations (Green), control flow (Yellow), function declarations (Blue), invocations & commands (calm Base0), expansion sigils (\$ and \${ in Base0), constants & signals (Magenta), and strings & subscripts (Cyan) matching Neovim"
    else
        fail "bat Shell rendering" "Expected Converged Ergonomic Shell Solarized TrueColor highlights in bat sample.sh output"
    fi

    # --- 2.10 SQL Syntax Verification ---
    SQL_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l sql "$SCRIPT_DIR/sample-code/sample.sql" 2>/dev/null || true)"
    if       grep -Fq "${SOL_GREEN}CREATE" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}TABLE" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}customer_accounts" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}BIGSERIAL" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}PRIMARY KEY" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}VARCHAR" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}128" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}NOT" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}NULL" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}DEFAULT" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}'standard'" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}CHECK" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}IN" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}NUMERIC" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0.00" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}BOOLEAN" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}TRUE" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}TIMESTAMPTZ" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}NOW" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}UUID" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}gen_random_uuid" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}BIGINT" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}REFERENCES" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}CASCADE" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}CHAR" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}idx_ledger_account_settled" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}DESC" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}WITH" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}monthly_billing_summary" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}SELECT" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}COUNT" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}COALESCE" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}SUM" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}100.0" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}CASE" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}WHEN" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0.15" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}DATE_TRUNC" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}INTERVAL" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}ROUND" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}DENSE_RANK" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}OVER" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}HAVING" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}ASC" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}LIMIT" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}25" <<< "$SQL_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_MAGENTA}account_id" <<< "$SQL_SAMPLE_OUT"; then
        pass "bat renders SQL keywords and data types (Green), relation entities (Base0), conditionals (Yellow), function calls (Base0), DEFAULT/ASC/DESC keywords (Green), booleans/sentinels/numbers (Magenta), and calm Base0 column qualifiers matching Neovim"
    else
        fail "bat SQL rendering" "Expected Converged Ergonomic SQL Solarized TrueColor highlights in bat sample.sql output"
    fi

    # --- 2.11 Terraform / HCL Syntax Verification ---
    TF_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l tf "$SCRIPT_DIR/sample-code/sample.tf" 2>/dev/null || true)"
    if       grep -Fq "${SOL_GREEN}terraform" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}required_providers" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}variable" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}string" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}validation" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}contains" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}var" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}number" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}3" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}locals" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}local" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}for" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}in" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}range" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}cidrsubnet" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}resource" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}aws_s3_bucket" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}telemetry_lake" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}merge" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}lifecycle" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}false" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}output" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}provider" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}provider" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}provisioner" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}self" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}%{" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}~}" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}endif" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}\${" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}}" <<< "$TF_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_CYAN}source" <<< "$TF_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_CYAN}CostCenter" <<< "$TF_SAMPLE_OUT"; then
        pass "bat renders Terraform declaration keywords & scope accessors (Green), block schemas & data types (Base0), control flow (Yellow), function calls (Base0), booleans/numbers (Magenta), strings (Cyan), and calm Base0 attributes/interpolation delimiters matching Neovim"
    else
        fail "bat Terraform rendering" "Expected Converged Ergonomic Terraform Solarized TrueColor highlights in bat sample.tf output"
    fi

    MD_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l md "$SCRIPT_DIR/sample-code/sample.md" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}Workstation Architecture" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}1. Executive Summary" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}2.1 File System Topology" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE1}2.2.1 Syntax Highlighting" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}2.2.1.1 Error Token" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Operational Verification Checklist" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}#" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}##" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}###" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}>" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}[!NOTE]" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}[!TIP]" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}[!IMPORTANT]" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}[!WARNING]" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}[x]" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}[ ]" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE1}Environment" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE1}Variable" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}|" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}git" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}cd" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}HOME" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}package" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}main" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}ValidateWorkstation" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}errors" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}New" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}return" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}nil" <<< "$MD_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_YELLOW}Workstation Architecture" <<< "$MD_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_YELLOW}1. Executive Summary" <<< "$MD_SAMPLE_OUT"; then
        pass "bat renders Markdown showcase (sample.md) with Semantic Architecture: H1 Orange, H2 Blue, H3 Violet, H4 Base1, H5/H6 Base0, Base01 hashmarks/quote markers, GitHub alerts ([!NOTE], [!TIP], [!IMPORTANT], [!WARNING]), task checkboxes, Base1 table headers with Base01 borders, embedded Bash with Magenta \$HOME and Base0 commands, embedded Go with Green func/package, Violet main, Blue declarations, Base0 calls (errors.New), Magenta nil, and exclusive Yellow control flow"
    else
        fail "bat Markdown showcase rendering" "Expected Semantic Architecture TrueColor highlights in bat sample.md output"
    fi

    TS_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l ts "$SCRIPT_DIR/sample-code/sample.ts" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}export" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}enum" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}type" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}interface" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}class" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}boolean" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}number" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}string" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}readonly" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}public" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}const" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}async" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}request" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}getState" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}try" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}await" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}return" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}catch" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}throw" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}new" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}this" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}true" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}8080" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}UserRole" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}ConnectionState" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}ApiResponse" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}ServiceGateway" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}requestUrl" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}mockData" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}message" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}setTimeout" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}encodeURIComponent" <<< "$TS_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_YELLOW}UserRole" <<< "$TS_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_MAGENTA}requestUrl" <<< "$TS_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_GREEN}return" <<< "$TS_SAMPLE_OUT"; then
        pass "bat renders TypeScript showcase (sample.ts) with Converged Ergonomic Solarized: imports/exports in Violet, declarations & primitive types in Green, exclusive control flow in Yellow, method declarations in Blue, invocations & custom types in Base0, and constants/numbers in Magenta matching Neovim"
    else
        fail "bat TypeScript rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.ts output"
    fi

    JS_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l js "$SCRIPT_DIR/sample-code/sample.js" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}import" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}export" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}class" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}const" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}async" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}await" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}try" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}yield" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}of" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}this" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}console" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}process" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Date" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}^\\/health[z]?$" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}i" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Symbol" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}iterator" <<< "$JS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}inspectSymbol" <<< "$JS_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_GREEN}Date" <<< "$JS_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_BASE0}console" <<< "$JS_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_BASE0}process" <<< "$JS_SAMPLE_OUT" && \
        ! grep -Fq "${SOL_BLUE}Symbol.iterator" <<< "$JS_SAMPLE_OUT" && \
        ! grep -Fq "${SOL_BLUE}inspectSymbol" <<< "$JS_SAMPLE_OUT"; then
        pass "bat renders JavaScript showcase (sample.js) with Converged Ergonomic Solarized: Date in Base0, console & process in Magenta, regex body in Magenta with Cyan flags and Base0 delimiters, *[Symbol.iterator] with calm Base0 operator and computed members, and loop 'of' keyword in Yellow matching Neovim"
    else
        fail "bat JavaScript rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.js output"
    fi

    # --- 2.14 XML Syntax Verification ---
    XML_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l xml "$SCRIPT_DIR/sample-code/sample.xml" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}xml" <<< "$XML_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}xml-stylesheet" <<< "$XML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}deployment" <<< "$XML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}mon:monitoring" <<< "$XML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}sec:security" <<< "$XML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}script" <<< "$XML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}version" <<< "$XML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}xmlns:mon" <<< "$XML_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}urn:deployment:v2" <<< "$XML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}&amp;" <<< "$XML_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}<![CDATA[" <<< "$XML_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}]]>" <<< "$XML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}        #!/bin/sh" <<< "$XML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}<!--" <<< "$XML_SAMPLE_OUT"; then
        pass "bat renders XML showcase (sample.xml) with Converged Ergonomic Solarized: directives in Orange, element tags in Blue, tag attributes in Green, tag delimiters in Base0, attribute strings in Cyan, entity references in Magenta, CDATA boundaries in Violet with calm Base0 payload, and comments in Base01 matching Neovim"
    else
        fail "bat XML rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.xml output"
    fi

    # --- 2.15 HTML Syntax Verification ---
    HTML_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l html "$SCRIPT_DIR/sample-code/sample.html" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}DOCTYPE" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}html" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}header" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}footer" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}script" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}charset" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}data-status" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}solarized-dark" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}&copy;" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}&mdash;" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Gateway Dashboard" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}<!--" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}document" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}addEventListener" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}const" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}console" <<< "$HTML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}log" <<< "$HTML_SAMPLE_OUT"; then
        pass "bat renders HTML5 showcase (sample.html) with Converged Ergonomic Solarized: doctype in Orange, element tags in Blue, tag attributes in Green, tag delimiters in Base0, attribute strings in Cyan, entities in Magenta, document text in calm Base0 Grey, comments in Base01, and embedded script in JS/TS scheme matching Neovim"
    else
        fail "bat HTML rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.html output"
    fi

    # --- 2.16 JSON Syntax Verification ---
    JSON_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l json "$SCRIPT_DIR/sample-code/sample.json" 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}\$schema" <<< "$JSON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}apiVersion" <<< "$JSON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}metadata" <<< "$JSON_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}https://api.example.com" <<< "$JSON_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}v2" <<< "$JSON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}3" <<< "$JSON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}true" <<< "$JSON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}false" <<< "$JSON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}null" <<< "$JSON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}{" <<< "$JSON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}:" <<< "$JSON_SAMPLE_OUT"; then
        pass "bat renders JSON showcase (sample.json) with Converged Ergonomic Solarized: object mapping keys in Green, string values in Cyan, numeric values, booleans & null in Magenta, and delimiters/brackets in calm Base0 Grey matching Neovim"
    else
        fail "bat JSON rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.json output"
    fi

    # --- 2.17 YAML Syntax Verification ---
    YAML_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l yaml "$SCRIPT_DIR/sample-code/sample.yaml" 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}apiVersion" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}kind" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}metadata" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}apps/v1" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}Deployment" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}!!str" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}42" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}null" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}true" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}<<" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}common-labels" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}resource-defaults" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}pod-security" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}&" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}*" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}#" <<< "$YAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}---" <<< "$YAML_SAMPLE_OUT"; then
        pass "bat renders YAML showcase (sample.yaml) with Converged Ergonomic Solarized: mapping keys & merge keys (<<) in Green, anchors & aliases in Base01 Dim with calm Base0 sigils (&, *), string values in Cyan, explicit type tags (!!str) in Base0 Grey (zero Yellow), numbers/booleans/null in Magenta, comments in Base01, and document markers in Base0 Grey matching Neovim"
    else
        fail "bat YAML rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.yaml output"
    fi

    # --- 2.18 TOML Syntax Verification ---
    TOML_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l toml "$SCRIPT_DIR/sample-code/sample.toml" 2>/dev/null || true)"
    if grep -Fq "${SOL_BLUE}package" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}server" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}rate_limits" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}name" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}version" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}pool" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}min_size" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}authorization" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}solarized-gateway" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}8080" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}true" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}2025-09-14T08:30:00Z" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}inf" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}nan" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}[" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}]" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}=" <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}." <<< "$TOML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}#" <<< "$TOML_SAMPLE_OUT"; then
        pass "bat renders TOML showcase (sample.toml) with Converged Ergonomic Solarized: table headers in Blue, mapping & inline keys in Green, string values in Cyan, numeric values, booleans, floats (inf, nan) & date-times in Magenta, brackets & delimiters in calm Base0, and comments in Base01 matching Neovim"
    else
        fail "bat TOML rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.toml output"
    fi

    # --- 2.19 CSS Syntax Verification ---
    CSS_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l css "$SCRIPT_DIR/sample-code/sample.css" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}@layer" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@font-face" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@keyframes" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@container" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@media" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}body" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}dashboard-grid" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}*" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}root" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}hover" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}before" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}font-family" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}color" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}background" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}--color-base03" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}MesloLGS NF" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}#002b36" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}400" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}ui-monospace" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}monospace" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}auto" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}auto-fill" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}&" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}data-status" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}healthy" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}content" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}640" <<< "$CSS_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_YELLOW}font-family" <<< "$CSS_SAMPLE_OUT"; then
        pass "bat renders CSS showcase (sample.css) with Converged Ergonomic Solarized: at-rules in Orange, selectors in Blue, pseudo-classes/elements in Violet, nesting parent '&' and attribute selector names in Base0, attribute strings in Cyan, container queries in Orange/Base0/Magenta, properties in Green (zero Yellow), custom properties unbroken in Base0, keyword values (ui-monospace, monospace, auto, auto-fill) in Base0, strings in Cyan, numbers/hex in Magenta, and delimiters in calm Base0 matching Neovim"
    else
        fail "bat CSS rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.css output"
    fi

    # --- 2.20 Java Properties Syntax Verification ---
    PROPERTIES_SAMPLE_OUT="$(HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l properties "$SCRIPT_DIR/sample-code/sample.properties" 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}spring.application.name" <<< "$PROPERTIES_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}server.port" <<< "$PROPERTIES_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}8080" <<< "$PROPERTIES_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0.15" <<< "$PROPERTIES_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}true" <<< "$PROPERTIES_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}solarized-gateway" <<< "$PROPERTIES_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}=" <<< "$PROPERTIES_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}:" <<< "$PROPERTIES_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}#" <<< "$PROPERTIES_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}!" <<< "$PROPERTIES_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}\${" <<< "$PROPERTIES_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_YELLOW}" <<< "$PROPERTIES_SAMPLE_OUT"; then
        pass "bat renders Java Properties showcase (sample.properties) with Converged Ergonomic Solarized: keys in Green, integer/float numbers and booleans in Magenta, strings in Cyan, delimiters and variable references in calm Base0, and comments in Base01 matching Neovim"
    else
        fail "bat Java Properties rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.properties output"
    fi
fi

# Test 3: Safe handling of pre-existing physical directory (prevents nested symlinks)
echo -e "\n[3/5] Testing safe directory replacement and backup..."
TEMP_HOME_BAK=$(mktemp -d)
mkdir -p "$TEMP_HOME_BAK/.config/nvim"
echo "custom config" > "$TEMP_HOME_BAK/.config/nvim/custom.txt"

HOME="$TEMP_HOME_BAK" XDG_CONFIG_HOME="$TEMP_HOME_BAK/.config" XDG_CACHE_HOME="$TEMP_HOME_BAK/.cache" "$SCRIPT_DIR/modules/10-dotfiles.sh" >/dev/null 2>&1

if [ -L "$TEMP_HOME_BAK/.config/nvim" ]; then
    pass "Replaced physical nvim directory with symlink"
else
    fail "Physical directory replacement" "Expected ~/.config/nvim to be a symlink"
fi

bak_dirs=("$TEMP_HOME_BAK"/.config/nvim.bak.*)
if [ -d "${bak_dirs[0]}" ] && [ -f "${bak_dirs[0]}/custom.txt" ]; then
    pass "Pre-existing physical directory backed up safely: $(basename "${bak_dirs[0]}")"
else
    fail "Directory backup failed" "Backup directory not found or missing contents"
fi
rm -rf "$TEMP_HOME_BAK"

# Test 4: Drop-in extension directories (.d/)
echo -e "\n[4/5] Testing drop-in extension directories..."
TEMP_DROPIN_HOME=$(mktemp -d)
mkdir -p "$TEMP_DROPIN_HOME/.environment-variables.d"
mkdir -p "$TEMP_DROPIN_HOME/.aliases.d"
mkdir -p "$TEMP_DROPIN_HOME/.zsh-functions.d"

echo "export TEST_DROPIN_VAR='dropin_success'" > "$TEMP_DROPIN_HOME/.environment-variables.d/custom.sh"
echo "alias test_dropin_alias='echo dropin_alias_ok'" > "$TEMP_DROPIN_HOME/.aliases.d/custom.sh"
echo "test_dropin_func() { echo 'dropin_func_ok'; }" > "$TEMP_DROPIN_HOME/.zsh-functions.d/custom.zsh"

# Source environment variables with drop-in (evaluate in parent shell so TESTS_FAILED increments are preserved)
if (
    HOME="$TEMP_DROPIN_HOME"
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/dotfiles/.environment-variables"
    [ "${TEST_DROPIN_VAR:-}" = "dropin_success" ]
); then
    pass ".environment-variables cleanly sources ~/.environment-variables.d/*.sh"
else
    fail "Drop-in env var failed" "Expected TEST_DROPIN_VAR=dropin_success"
fi

# Source aliases with drop-in (evaluate in parent shell so TESTS_FAILED increments are preserved)
if (
    HOME="$TEMP_DROPIN_HOME"
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/dotfiles/.aliases"
    alias test_dropin_alias >/dev/null 2>&1
); then
    pass ".aliases cleanly sources ~/.aliases.d/*.sh"
else
    fail "Drop-in alias failed" "test_dropin_alias was not defined"
fi

# Source zsh-functions with drop-in (in zsh)
if zsh -c "HOME='$TEMP_DROPIN_HOME'; source '$SCRIPT_DIR/dotfiles/.zsh-functions'; type test_dropin_func >/dev/null 2>&1"; then
    pass ".zsh-functions cleanly sources ~/.zsh-functions.d/*.zsh"
else
    fail "Drop-in zsh function failed" "test_dropin_func was not defined in zsh"
fi
rm -rf "$TEMP_DROPIN_HOME"

# Verify empty drop-in directories (~/.environment-variables.d, ~/.aliases.d) do not fail under Zsh NOMATCH or Bash
TEMP_EMPTY_DROPIN_HOME=$(mktemp -d)
mkdir -p "$TEMP_EMPTY_DROPIN_HOME/.environment-variables.d" "$TEMP_EMPTY_DROPIN_HOME/.aliases.d" "$TEMP_EMPTY_DROPIN_HOME/.zsh-functions.d"
if zsh -c "setopt NOMATCH; HOME='$TEMP_EMPTY_DROPIN_HOME'; source '$SCRIPT_DIR/dotfiles/.environment-variables'; source '$SCRIPT_DIR/dotfiles/.aliases'; source '$SCRIPT_DIR/dotfiles/.zsh-functions'" >/dev/null 2>&1 && \
   bash -c "HOME='$TEMP_EMPTY_DROPIN_HOME'; . '$SCRIPT_DIR/dotfiles/.environment-variables'; . '$SCRIPT_DIR/dotfiles/.aliases'" >/dev/null 2>&1; then
    pass "Empty drop-in directories (~/.environment-variables.d, ~/.aliases.d, ~/.zsh-functions.d) source cleanly in Zsh (NOMATCH) and Bash"
else
    fail "Empty drop-in directories" "Sourcing .environment-variables, .aliases, or .zsh-functions failed when drop-in directories are empty"
fi
rm -rf "$TEMP_EMPTY_DROPIN_HOME"

# Test 5: Uninstallation of dotfiles
echo -e "\n[5/5] Testing dotfiles uninstallation..."
HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" "$SCRIPT_DIR/modules/99-uninstall.sh" dotfiles >/dev/null 2>&1

all_unlinked=true
for df in "${expected_top_level[@]}"; do
    if [ -L "$TEMP_HOME/$df" ]; then
        all_unlinked=false
        fail "Unlink check" "$TEMP_HOME/$df is still linked"
    fi
done

if [ -L "$TEMP_HOME/.config/ghostty" ] || [ -L "$TEMP_HOME/.config/nvim" ] || [ -L "$TEMP_HOME/.config/btop" ] || [ -L "$TEMP_HOME/.config/git" ] || [ -L "$TEMP_HOME/.config/lazygit" ] || [ -L "$TEMP_HOME/.config/tealdeer" ]; then
    all_unlinked=false
    fail "Unlink check" ".config subtrees still linked"
fi

for syn in "$SCRIPT_DIR/syntaxes"/*.sublime-syntax; do
    [ -e "$syn" ] || continue
    if [ -L "$TEMP_HOME/.config/bat/syntaxes/$(basename "$syn")" ]; then
        all_unlinked=false
        fail "Unlink check" "$TEMP_HOME/.config/bat/syntaxes/$(basename "$syn") is still linked"
    fi
done

if [ -L "$TEMP_HOME/.config/bat/themes/Solarized-Dark-TrueColor.tmTheme" ]; then
    all_unlinked=false
    fail "Unlink check" "Bat theme is still linked"
fi

if [ -L "$TEMP_HOME/.config/mise/config.toml" ]; then
    all_unlinked=false
    fail "Unlink check" "Mise config is still linked"
fi

if [ "$all_unlinked" = true ]; then
    pass "All managed dotfile symlinks successfully removed by uninstaller"
fi

test_summary
