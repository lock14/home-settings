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
if [ -f "$TEMP_HOME/.config/nvim/ftplugin/java.lua" ] && grep -q 'jdtls' "$TEMP_HOME/.config/nvim/ftplugin/java.lua"; then
    pass "Auto-discovered and symlinked: .config/nvim/ftplugin/java.lua"
else
    fail "Java ftplugin symlink" "Expected .config/nvim/ftplugin/java.lua in mirrored dotfiles"
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
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Diff.sublime-syntax" "" "Symlinked Bat Diff syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Go.sublime-syntax" "" "Symlinked Bat Go syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Java.sublime-syntax" "" "Symlinked Bat Java syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Python.sublime-syntax" "" "Symlinked Bat Python syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Rust.sublime-syntax" "" "Symlinked Bat Rust syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Bash.sublime-syntax" "" "Symlinked Bat Bash syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/SQL.sublime-syntax" "" "Symlinked Bat SQL syntax"
assert_symlink "$TEMP_HOME/.config/bat/syntaxes/Terraform.sublime-syntax" "" "Symlinked Bat Terraform syntax"

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
   grep -q "variable, variable.other, variable.parameter" "$THEME_FILE"; then
    pass "Solarized-Dark-TrueColor.tmTheme defines complete Markdown, C/C++, Java, Diff, Go, Python, Rust, Bash, Namespace, Attribute, and Error scopes"
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
    if grep -Fq "${ORANGE_BOLD}#" <<< "$MD_OUT" && \
       grep -Fq "${ORANGE_BOLD}Header 1" <<< "$MD_OUT" && \
       grep -Fq "${YELLOW_BOLD}##" <<< "$MD_OUT" && \
       grep -Fq "${YELLOW_BOLD}Header 2" <<< "$MD_OUT" && \
       grep -Fq "${BLUE_BOLD}###" <<< "$MD_OUT" && \
       grep -Fq "${BLUE_BOLD}Header 3" <<< "$MD_OUT" && \
       grep -Fq "$BASE1_BOLD" <<< "$MD_OUT"; then
        pass "bat renders Markdown headings (H1 Orange, H2 Yellow, H3 Blue with matching hashmarks) and Base1 bold text"
    else
        fail "bat Markdown rendering" "Expected H1 Orange, H2 Yellow, H3 Blue, and Base1 bold in bat output"
    fi

    C_OUT="$(echo -e "#include <stdio.h>" | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "$SOL_ORANGE" <<< "$C_OUT"; then
        pass "bat renders C/C++ preprocessor directives in Solarized Orange"
    else
        fail "bat C preprocessor rendering" "Expected Orange preprocessor directive in bat output"
    fi

    DIFF_OUT="$(echo -e "--- a\n+++ b\n-old\n+new" | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l diff - 2>/dev/null || true)"
    if grep -Fq "$SOL_GREEN" <<< "$DIFF_OUT" && grep -Fq "$SOL_RED" <<< "$DIFF_OUT"; then
        pass "bat renders Unified Diffs with Solarized Green additions and Red deletions"
    else
        fail "bat Diff rendering" "Expected Green additions and Red deletions in bat diff output"
    fi

    QUOTE_OUT="$(printf "> quote text\n" | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l md - 2>/dev/null || true)"
    if grep -Fq "$SOL_BLUE" <<< "$QUOTE_OUT"; then
        pass "bat renders Markdown blockquotes in Solarized Blue"
    else
        fail "bat blockquote rendering" "Expected Blue blockquote in bat output"
    fi

    GO_OUT="$(printf "type MyStruct struct {}\n" | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l go - 2>/dev/null || true)"
    if grep -Fq "$SOL_YELLOW" <<< "$GO_OUT"; then
        pass "bat renders custom struct types in Solarized Yellow"
    else
        fail "bat custom type rendering" "Expected Yellow struct type in bat output"
    fi

    C_TYPE_OUT="$(printf "int x = 42;\n" | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "$SOL_YELLOW" <<< "$C_TYPE_OUT"; then
        pass "bat renders primitive C types (int, char, etc.) in Solarized Yellow"
    else
        fail "bat primitive type rendering" "Expected Yellow primitive type in bat output"
    fi

    C_STR_OUT="$(printf 'printf("Hello %%s\\n");\n' | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "$SOL_CYAN" <<< "$C_STR_OUT"; then
        pass "bat renders string format specifiers and escapes in Solarized Cyan"
    else
        fail "bat string escape rendering" "Expected Cyan string escape in bat output"
    fi

    C_DECL_OUT="$(printf "typedef struct {\n    int x;\n} Node;\n" | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}typedef" <<< "$C_DECL_OUT" && grep -Fq "${SOL_GREEN}struct" <<< "$C_DECL_OUT"; then
        pass "bat renders C declaration keywords (typedef, struct) in Solarized Green"
    else
        fail "bat C declaration rendering" "Expected Green typedef/struct in bat output"
    fi

    ESC_ITALIC="$(printf "\033[3;")"
    C_MACRO_OUT="$(printf '#define CLAMP(x, low, high) (((x) > (high)) ? (high) : (x))\n' | BAT_THEME="Solarized-Dark-TrueColor" BAT_OPTS="--italic-text=always" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}#define" <<< "$C_MACRO_OUT" && \
       grep -Fq "${SOL_BASE0}x" <<< "$C_MACRO_OUT" && \
       ! grep -Fq "$ESC_ITALIC" <<< "$C_MACRO_OUT"; then
        pass "bat renders macro parameters and body expressions in upright Solarized Base0 (grey) matching Neovim"
    else
        fail "bat macro parameter rendering" "Expected upright Base0 grey parameters and body expressions in macro"
    fi

    C_COMMENT_OUT="$(printf '/* sample comment */\n' | BAT_THEME="Solarized-Dark-TrueColor" BAT_OPTS="--italic-text=always" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "$SOL_BASE01" <<< "$C_COMMENT_OUT" && ! grep -Fq "$ESC_ITALIC" <<< "$C_COMMENT_OUT"; then
        pass "bat renders C comments in upright Solarized Base01 without italics"
    else
        fail "bat comment rendering" "Expected upright Base01 comment without italics in bat output"
    fi

    MD_ITALIC_OUT="$(printf '*explicit italic*\n' | BAT_THEME="Solarized-Dark-TrueColor" BAT_OPTS="--italic-text=always" "$BAT_BIN" --color=always -l md - 2>/dev/null || true)"
    if grep -Fq "$ESC_ITALIC" <<< "$MD_ITALIC_OUT"; then
        pass "bat renders explicitly tagged Markdown *italic* with true italics"
    else
        fail "bat markdown italic rendering" "Expected italics on explicitly tagged Markdown"
    fi

    # --- 2.2 C Syntax Verification ---
    C_CONST_OUT="$(printf 'int res = EXIT_FAILURE;\n' | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_MAGENTA}EXIT_FAILURE" <<< "$C_CONST_OUT"; then
        pass "bat renders named uppercase constants (EXIT_FAILURE, etc.) in Solarized Magenta"
    else
        fail "bat constant rendering" "Expected Magenta named constants in bat output"
    fi

    C_CUSTOM_TYPE_OUT="$(printf 'WorkerNode *node = malloc(sizeof(WorkerNode));\n' | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_YELLOW}WorkerNode" <<< "$C_CUSTOM_TYPE_OUT"; then
        pass "bat renders custom PascalCase types (WorkerNode, etc.) in Solarized Yellow"
    else
        fail "bat custom type rendering" "Expected Yellow custom PascalCase type in bat output"
    fi

    C_WORD_OP_OUT="$(printf 'sizeof(int);\n' | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}sizeof" <<< "$C_WORD_OP_OUT"; then
        pass "bat renders word operators (sizeof, etc.) in Solarized Green matching Neovim"
    else
        fail "bat word operator rendering" "Expected Green sizeof in bat output"
    fi

    C_FUNC_CALL_OUT="$(printf 'emit_log(0, "test");\n' | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_BLUE}emit_log" <<< "$C_FUNC_CALL_OUT"; then
        pass "bat renders user function calls (emit_log, etc.) in Solarized Blue matching Neovim"
    else
        fail "bat function call rendering" "Expected Blue emit_log call in bat output"
    fi

    # --- 2.3 C++ Syntax Verification ---
    CPP_TEMPLATE_OUT="$(printf 'template <Printable T>\nclass Node {\nstd::vector<T> items;\n};\n' | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_YELLOW}T" <<< "$CPP_TEMPLATE_OUT"; then
        pass "bat renders C++ template type parameters (T in template <... T> and vector<T>) in Solarized Yellow matching Neovim"
    else
        fail "bat template type parameter rendering" "Expected Yellow template type parameter in bat output"
    fi

    if grep -Fq "${SOL_YELLOW}Printable" <<< "$CPP_TEMPLATE_OUT"; then
        pass "bat renders C++ concept names (Printable) in Solarized Yellow matching Neovim"
    else
        fail "bat concept name rendering" "Expected Yellow concept name in bat output"
    fi

    if grep -Fq "${SOL_YELLOW}vector" <<< "$CPP_TEMPLATE_OUT"; then
        pass "bat renders C++ STL container types (vector, optional) in Solarized Yellow matching Neovim"
    else
        fail "bat STL container rendering" "Expected Yellow STL container type in bat output"
    fi

    CPP_NS_OUT="$(printf 'namespace core::telemetry {}\nusing namespace core::telemetry;\nstd::string s;\n' | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}core" <<< "$CPP_NS_OUT" && \
       grep -Fq "${SOL_VIOLET}telemetry" <<< "$CPP_NS_OUT" && \
       grep -Fq "${SOL_BASE0}std" <<< "$CPP_NS_OUT"; then
        pass "bat renders namespace declarations (core, telemetry) in Solarized Violet and qualifiers (std) in calm Base0 Grey matching Neovim"
    else
        fail "bat namespace rendering" "Expected Violet namespace declarations and Base0 qualifiers in bat output"
    fi

    CPP_CONST_OUT="$(printf 'NodeState state_{NodeState::Initializing};\nreturn std::nullopt;\n' | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
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

    CPP_CONCEPT_OUT="$(printf '{ std::cout << t } -> std::same_as<std::ostream&>;\n' | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_YELLOW}same_as" <<< "$CPP_CONCEPT_OUT"; then
        pass "bat renders standard C++20 concepts (same_as) in Solarized Yellow matching Neovim"
    else
        fail "bat C++20 concept rendering" "Expected Yellow same_as concept in bat output"
    fi

    CPP_ENUM_OUT="$(printf 'enum class NodeState : uint8_t {\n};\n' | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_YELLOW}NodeState" <<< "$CPP_ENUM_OUT" && \
       grep -Fq "${SOL_YELLOW}uint8_t" <<< "$CPP_ENUM_OUT"; then
        pass "bat renders enum class types and underlying types (uint8_t) in Solarized Yellow matching Neovim"
    else
        fail "bat enum type rendering" "Expected Yellow enum name and underlying type in bat output"
    fi

    CPP_QUAL_FUNC_OUT="$(printf 'std::move(metric);\nstd::for_each(items.begin(), items.end());\n' | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_BASE0}std" <<< "$CPP_QUAL_FUNC_OUT" && \
       grep -Fq "${SOL_BLUE}move" <<< "$CPP_QUAL_FUNC_OUT" && \
       grep -Fq "${SOL_BLUE}for_each" <<< "$CPP_QUAL_FUNC_OUT"; then
        pass "bat renders namespace-qualified function calls (std::move, std::for_each) with Base0 Grey namespace and Blue function matching Neovim"
    else
        fail "bat qualified function rendering" "Expected Base0 Grey std and Blue move/for_each in bat output"
    fi

    CPP_ATTR_OUT="$(printf '[[nodiscard]] constexpr uint64_t id();\n' | BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}[[" <<< "$CPP_ATTR_OUT" && \
       grep -Fq "${SOL_ORANGE}nodiscard" <<< "$CPP_ATTR_OUT" && \
       grep -Fq "${SOL_ORANGE}]]" <<< "$CPP_ATTR_OUT"; then
        pass "bat renders C++ attributes ([[nodiscard]]) in Solarized Orange matching Neovim"
    else
        fail "bat attribute rendering" "Expected Orange [[nodiscard]] in bat output"
    fi

    # --- 2.4 Diff Syntax Verification ---
    DIFF_SAMPLE_OUT="$(BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l diff "$SCRIPT_DIR/sample-code/sample.diff" 2>/dev/null || true)"
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
    GO_SAMPLE_OUT="$(BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l go "$SCRIPT_DIR/sample-code/sample.go" 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}package" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}main" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}import" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}type" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}func" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}struct" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}interface" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}context" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}Context" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}LevelDebug" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}MaskAll" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}ClusterNode" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}map" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}chan" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}NewClusterNode" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}\`json:\"port\"\`" <<< "$GO_SAMPLE_OUT"; then
        pass "bat renders Go package (Green), main (Violet), import (Orange), declarations (Green), qualifiers (Base0 Grey), constants (Magenta), types/composite literals (Yellow), and calls (Blue) matching Neovim"
    else
        fail "bat Go rendering" "Expected Model 2 Solarized TrueColor highlights in bat sample.go output"
    fi

    # --- 2.6 Java Syntax Verification ---
    JAVA_SAMPLE_OUT="$(BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l java "$SCRIPT_DIR/sample-code/sample.java" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}import" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}java" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}Instant" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}@interface" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}class" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}interface" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}record" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}OrderRecord" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}1L" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@Service" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@Override" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}when" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}100.0" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}this" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}super" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}///" <<< "$JAVA_SAMPLE_OUT"; then
        pass "bat renders Java import (Orange), paths (Base0), types (Yellow), declarations (Green class/interface/record), annotations (Orange), guards (Green when), numbers (Magenta 1L/100.0), this (Magenta), super call (Blue), and doc comments (Base01 ///) matching Neovim"
    else
        fail "bat Java rendering" "Expected Modern Java Solarized TrueColor highlights in bat sample.java output"
    fi

    # --- 2.7 Python Syntax Verification ---
    PYTHON_SAMPLE_OUT="$(BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l py "$SCRIPT_DIR/sample-code/sample.py" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}from" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}asyncio" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}typing" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}Callable" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}EndpointMetrics" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}DEFAULT_PORT" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0xFF00_AA55" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}3.1415926535" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}def" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}timed_execution" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}async" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@dataclass" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@property" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}self" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}None" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}MetricsCollector" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}__init__" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}__name__" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}\"\"\"" <<< "$PYTHON_SAMPLE_OUT"; then
        pass "bat renders Python imports (Orange), modules (Violet), typing/classes (Yellow), unbroken numbers (Magenta), decorators (Orange), instance self/None/__name__ (Magenta), def/async (Green), and calls (Blue) matching Neovim"
    else
        fail "bat Python rendering" "Expected Modern Python Solarized TrueColor highlights in bat sample.py output"
    fi

    # --- 2.8 Rust Syntax Verification ---
    RUST_SAMPLE_OUT="$(BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l rs "$SCRIPT_DIR/sample-code/sample.rs" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}use" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}std" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}collections" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}HashMap" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}const" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}MAX_CONNECTIONS" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}usize" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0xCAFE_BABE" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}#[" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}derive" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}]" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}Debug" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}pub" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}enum" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}NodeStatus" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}Starting" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}trait" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}Repository" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}T" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}fn" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}find_by_id" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}'a" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}self" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}struct" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}ServerNode" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}where" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}impl" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}write" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}let" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}mut" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}println" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}///" <<< "$RUST_SAMPLE_OUT"; then
        pass "bat renders Rust imports (Orange), modules (Violet), types/traits (Yellow), keywords/lifetimes (Green), constants/variants/self (Magenta), calls/macros (Blue), and attributes (Orange) matching Neovim"
    else
        fail "bat Rust rendering" "Expected Modern Rust Solarized TrueColor highlights in bat sample.rs output"
    fi

    # --- 2.9 Bash Syntax Verification ---
    SH_SAMPLE_OUT="$(BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l sh "$SCRIPT_DIR/sample-code/sample.sh" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}#!/bin/bash" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}set" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}SCRIPT_NAME" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}basename" <<< "$SH_SAMPLE_OUT" && \
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
       grep -Fq "${SOL_GREEN}if" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}then" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}printf" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}trap" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}EXIT" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}log_status" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}1" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}2" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}case" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}esac" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}render_banner" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}cat" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}EOF" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}check_services" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}for" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}in" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}do" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}done" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}mkdir" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}main" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}>&${SOL_RESET}${SOL_MAGENTA}2" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}INFO${SOL_RESET}${SOL_BASE0})" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}*${SOL_RESET}${SOL_BASE0})" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}[${SOL_RESET}${SOL_CYAN}@${SOL_RESET}${SOL_BASE0}]" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}@" <<< "$SH_SAMPLE_OUT"; then
        pass "bat renders Shell shebang (Orange), keywords (Green), functions/commands (Blue), constants/numbers/signals (Magenta), redirections, case patterns, and heredocs/strings (Cyan) matching Neovim"
    else
        fail "bat Shell rendering" "Expected Modern Shell Solarized TrueColor highlights in bat sample.sh output"
    fi

    # --- 2.10 SQL Syntax Verification ---
    SQL_SAMPLE_OUT="$(BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l sql "$SCRIPT_DIR/sample-code/sample.sql" 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}CREATE" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}TABLE" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}customer_accounts" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}BIGSERIAL" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}PRIMARY KEY" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}VARCHAR" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}128" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}NOT" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}NULL" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}DEFAULT" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}'standard'" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}CHECK" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}IN" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}NUMERIC" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0.00" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}BOOLEAN" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}TRUE" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}TIMESTAMPTZ" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}NOW" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}UUID" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}gen_random_uuid" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}BIGINT" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}REFERENCES" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}CASCADE" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}CHAR" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}idx_ledger_account_settled" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}DESC" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}WITH" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}monthly_billing_summary" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}SELECT" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}COUNT" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}COALESCE" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}SUM" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}100.0" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}CASE" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}WHEN" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0.15" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}DATE_TRUNC" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}INTERVAL" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}ROUND" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}DENSE_RANK" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}OVER" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}HAVING" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}ASC" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}LIMIT" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}25" <<< "$SQL_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_MAGENTA}account_id" <<< "$SQL_SAMPLE_OUT"; then
        pass "bat renders SQL keywords (Green), relation entities and data types (Yellow), functions (Blue), DEFAULT/ASC/DESC directives (Orange), booleans/sentinels/numbers (Magenta), and calm Base0 column qualifiers matching Neovim"
    else
        fail "bat SQL rendering" "Expected Modern SQL Solarized TrueColor highlights in bat sample.sql output"
    fi

    # --- 2.11 Terraform / HCL Syntax Verification ---
    TF_SAMPLE_OUT="$(BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always -l tf "$SCRIPT_DIR/sample-code/sample.tf" 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}terraform" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}required_providers" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}variable" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}string" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}validation" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}contains" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}var" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}number" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}3" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}locals" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}local" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}for" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}in" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}range" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}cidrsubnet" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}resource" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}aws_s3_bucket" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}telemetry_lake" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}merge" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}lifecycle" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}false" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}output" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}provider" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}provider" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}provisioner" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}self" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}%{" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}~}" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}if" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}endif" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}\${" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}}" <<< "$TF_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_CYAN}source" <<< "$TF_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_CYAN}CostCenter" <<< "$TF_SAMPLE_OUT"; then
        pass "bat renders Terraform declaration keywords & scope accessors (Green), block schemas & data types (Yellow), functions (Blue), booleans/numbers (Magenta), strings (Cyan), and calm Base0 attributes/interpolation delimiters matching Neovim"
    else
        fail "bat Terraform rendering" "Expected Modern Terraform Solarized TrueColor highlights in bat sample.tf output"
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
