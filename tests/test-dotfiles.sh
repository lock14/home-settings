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

HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" "$SCRIPT_DIR/modules/10-dotfiles.sh" >/dev/null 2>&1

expected_top_level=(
    ".environment-variables"
    ".bashrc-addendum"
    ".zshrc-addendum"
    ".aliases"
    ".zsh-aliases"
    ".zsh-functions"
    ".zsh-completions"
    ".p10k.zsh"
    ".vimrc"
)

for df in "${expected_top_level[@]}"; do
    assert_symlink "$TEMP_HOME/$df" "" "Auto-discovered and symlinked: $df"
done

assert_symlink "$TEMP_HOME/.dir-colors/dircolors" "" "Auto-discovered and symlinked: .dir-colors/dircolors"
assert_symlink "$TEMP_HOME/.config/nvim" "" "Auto-discovered and symlinked: .config/nvim"
assert_symlink "$TEMP_HOME/.config/ghostty" "" "Auto-discovered and symlinked: .config/ghostty"

if [ -f "$TEMP_HOME/.config/ghostty/config" ] && grep -q 'theme = "Solarized Dark"' "$TEMP_HOME/.config/ghostty/config" && grep -q 'font-family = "MesloLGS NF"' "$TEMP_HOME/.config/ghostty/config"; then
    pass "Ghostty config contains Solarized Dark theme and MesloLGS NF font"
else
    fail "Ghostty config verification" "Ghostty config missing expected theme or font"
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

assert_symlink "$TEMP_HOME/.config/bat/themes/Solarized-Dark-TrueColor.tmTheme" "" "Symlinked Bat theme"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/C.sublime-syntax" "" "Symlinked Bat C syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/C++.sublime-syntax" "" "Symlinked Bat C++ syntax"

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
   grep -q "<string>invalid, invalid.illegal" "$THEME_FILE"; then
    pass "Solarized-Dark-TrueColor.tmTheme defines complete Markdown, C/C++, Java, Diff, and Error scopes"
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
    MD_OUT="$(printf "# Header 1\n## Header 2\n### Header 3\n**bold text**\n" | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l md - 2>/dev/null || true)"
    ORANGE_BOLD="$(printf "\033[1;38;2;203;75;22m")"
    YELLOW_BOLD="$(printf "\033[1;38;2;181;137;0m")"
    BLUE_BOLD="$(printf "\033[1;38;2;38;139;210m")"
    BASE1_BOLD="$(printf "\033[1;38;2;147;161;161m")"
    if echo "$MD_OUT" | grep -Fq "${ORANGE_BOLD}#" && \
       echo "$MD_OUT" | grep -Fq "${ORANGE_BOLD}Header 1" && \
       echo "$MD_OUT" | grep -Fq "${YELLOW_BOLD}##" && \
       echo "$MD_OUT" | grep -Fq "${YELLOW_BOLD}Header 2" && \
       echo "$MD_OUT" | grep -Fq "${BLUE_BOLD}###" && \
       echo "$MD_OUT" | grep -Fq "${BLUE_BOLD}Header 3" && \
       echo "$MD_OUT" | grep -Fq "$BASE1_BOLD"; then
        pass "bat renders Markdown headings (H1 Orange, H2 Yellow, H3 Blue with matching hashmarks) and Base1 bold text"
    else
        fail "bat Markdown rendering" "Expected H1 Orange, H2 Yellow, H3 Blue, and Base1 bold in bat output"
    fi

    C_OUT="$(echo -e "#include <stdio.h>" | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    ORANGE_PREPROC="$(printf "\033[38;2;203;75;22m")"
    if echo "$C_OUT" | grep -Fq "$ORANGE_PREPROC"; then
        pass "bat renders C/C++ preprocessor directives in Solarized Orange"
    else
        fail "bat C preprocessor rendering" "Expected Orange preprocessor directive in bat output"
    fi

    DIFF_OUT="$(echo -e "--- a\n+++ b\n-old\n+new" | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l diff - 2>/dev/null || true)"
    GREEN_DIFF="$(printf "\033[38;2;133;153;0m")"
    RED_DIFF="$(printf "\033[38;2;220;50;47m")"
    if echo "$DIFF_OUT" | grep -Fq "$GREEN_DIFF" && echo "$DIFF_OUT" | grep -Fq "$RED_DIFF"; then
        pass "bat renders Unified Diffs with Solarized Green additions and Red deletions"
    else
        fail "bat Diff rendering" "Expected Green additions and Red deletions in bat diff output"
    fi

    QUOTE_OUT="$(printf "> quote text\n" | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l md - 2>/dev/null || true)"
    if echo "$QUOTE_OUT" | grep -q "38;2;38;139;210m"; then
        pass "bat renders Markdown blockquotes in Solarized Blue"
    else
        fail "bat blockquote rendering" "Expected Blue blockquote in bat output"
    fi

    GO_OUT="$(printf "type MyStruct struct {}\n" | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l go - 2>/dev/null || true)"
    YELLOW_TYPE="$(printf "\033[38;2;181;137;0m")"
    if echo "$GO_OUT" | grep -Fq "$YELLOW_TYPE"; then
        pass "bat renders custom struct types in Solarized Yellow"
    else
        fail "bat custom type rendering" "Expected Yellow struct type in bat output"
    fi

    C_TYPE_OUT="$(printf "int x = 42;\n" | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if echo "$C_TYPE_OUT" | grep -Fq "$YELLOW_TYPE"; then
        pass "bat renders primitive C types (int, char, etc.) in Solarized Yellow"
    else
        fail "bat primitive type rendering" "Expected Yellow primitive type in bat output"
    fi

    C_STR_OUT="$(printf 'printf("Hello %%s\\n");\n' | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    CYAN_STR="$(printf "\033[38;2;42;161;152m")"
    if echo "$C_STR_OUT" | grep -Fq "$CYAN_STR"; then
        pass "bat renders string format specifiers and escapes in Solarized Cyan"
    else
        fail "bat string escape rendering" "Expected Cyan string escape in bat output"
    fi

    C_DECL_OUT="$(printf "typedef struct {\n    int x;\n} Node;\n" | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    GREEN_DECL="$(printf "\033[38;2;133;153;0m")"
    if echo "$C_DECL_OUT" | grep -Fq "${GREEN_DECL}typedef" && echo "$C_DECL_OUT" | grep -Fq "${GREEN_DECL}struct"; then
        pass "bat renders C declaration keywords (typedef, struct) in Solarized Green"
    else
        fail "bat C declaration rendering" "Expected Green typedef/struct in bat output"
    fi
fi

# Test 3: Safe handling of pre-existing physical directory (prevents nested symlinks)
echo -e "\n[3/5] Testing safe directory replacement and backup..."
TEMP_HOME_BAK=$(mktemp -d)
mkdir -p "$TEMP_HOME_BAK/.config/nvim"
echo "custom config" > "$TEMP_HOME_BAK/.config/nvim/custom.txt"

HOME="$TEMP_HOME_BAK" XDG_CONFIG_HOME="$TEMP_HOME_BAK/.config" "$SCRIPT_DIR/modules/10-dotfiles.sh" >/dev/null 2>&1

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

# Source environment variables with drop-in
(
    HOME="$TEMP_DROPIN_HOME"
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/dotfiles/.environment-variables"
    if [ "${TEST_DROPIN_VAR:-}" = "dropin_success" ]; then
        pass ".environment-variables cleanly sources ~/.environment-variables.d/*.sh"
    else
        fail "Drop-in env var failed" "Expected TEST_DROPIN_VAR=dropin_success, got '${TEST_DROPIN_VAR:-}'"
    fi
)

# Source aliases with drop-in
(
    HOME="$TEMP_DROPIN_HOME"
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/dotfiles/.aliases"
    if alias test_dropin_alias >/dev/null 2>&1; then
        pass ".aliases cleanly sources ~/.aliases.d/*.sh"
    else
        fail "Drop-in alias failed" "test_dropin_alias was not defined"
    fi
)

# Source zsh-functions with drop-in (in zsh)
if zsh -c "HOME='$TEMP_DROPIN_HOME'; source '$SCRIPT_DIR/dotfiles/.zsh-functions'; type test_dropin_func >/dev/null 2>&1"; then
    pass ".zsh-functions cleanly sources ~/.zsh-functions.d/*.zsh"
else
    fail "Drop-in zsh function failed" "test_dropin_func was not defined in zsh"
fi
rm -rf "$TEMP_DROPIN_HOME"

# Test 5: Uninstallation of dotfiles
echo -e "\n[5/5] Testing dotfiles uninstallation..."
HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" "$SCRIPT_DIR/modules/99-uninstall.sh" dotfiles >/dev/null 2>&1

all_unlinked=true
for df in "${expected_top_level[@]}"; do
    if [ -L "$TEMP_HOME/$df" ]; then
        all_unlinked=false
        fail "Unlink check" "$TEMP_HOME/$df is still linked"
    fi
done

if [ -L "$TEMP_HOME/.config/ghostty" ] || [ -L "$TEMP_HOME/.config/nvim" ]; then
    all_unlinked=false
    fail "Unlink check" ".config subtrees still linked"
fi

if [ "$all_unlinked" = true ]; then
    pass "All managed dotfile symlinks successfully removed by uninstaller"
fi

test_summary
