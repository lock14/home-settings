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

# The module runs below under a temporary $HOME, so it must never reach live tmux servers or IDE editors
if ! grep -Eq '^[^#]*(tmux |luafile|--remote-expr|nvim-ide-)' "$SCRIPT_DIR/modules/10-dotfiles.sh"; then
    pass "modules/10-dotfiles.sh never hot-reloads live tmux servers or Neovim IDE editors (hermetic under a temporary HOME)"
else
    fail "modules/10-dotfiles.sh hermeticity" "Found tmux / luafile / --remote-expr / nvim-ide- socket calls that would mutate live sessions from tests"
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
   grep -q 'set -g terminal-features ""' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'RGB:extkeys:usstyle:clipboard:hyperlinks' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'set -s extended-keys on' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'allow-passthrough on' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'copy-command' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'MouseDragEnd1Pane.*copy-pipe-no-clear' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -T copy-mode-vi M-c send-keys -X copy-pipe-and-cancel' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -T copy-mode-vi M-v' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-v' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n MouseDown1Pane select-pane -t = \\; send-keys -M' "$TEMP_HOME/.tmux.conf" && \
   ! grep -Eq '[[:space:]]MouseDown1Pane.*run-shell' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -T copy-mode-vi C-MouseDown1Pane.*mouse_hyperlink' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -T copy-mode-vi M-MouseDown1Pane.*mouse_hyperlink' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n C-MouseDown1Pane.*mouse_hyperlink' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-MouseDown1Pane.*mouse_hyperlink' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n MouseDown8Pane.*send-keys C-o' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n MouseDown9Pane.*send-keys C-i' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'Smulx=' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'Setulc=' "$TEMP_HOME/.tmux.conf" && \
   ! grep -q 'Hls@' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'set-environment -g FORCE_HYPERLINK 1' "$TEMP_HOME/.tmux.conf" && \
   ! grep -q 'update-environment.*FORCE_HYPERLINK' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'pane-border-style "fg=#586E75,bg=#002B36"' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'pane-active-border-style "fg=#586E75,bg=#002B36"' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'popup-border-style "fg=#586E75,bg=#002B36"' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'mode-style "fg=#93A1A1,bg=#073642"' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'set -g status-position top' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'status-style "fg=#839496,bg=#073642"' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'client_prefix' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'pane_in_mode' "$TEMP_HOME/.tmux.conf" && \
   grep -q '@ide_role' "$TEMP_HOME/.tmux.conf" && \
   grep -q '_ide_park_' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind b set-option status' "$TEMP_HOME/.tmux.conf" && \
   ! grep -Eq '\bbold\b' "$TEMP_HOME/.tmux.conf" && \
   ! grep -q '_swap' "$TEMP_HOME/.tmux.conf" && \
   ! grep -Eq '^[[:space:]]*bind(-key)?[[:space:]]+-n[[:space:]]+C-[hjkl]\b' "$TEMP_HOME/.tmux.conf" && \
   ! grep -Eq '^[[:space:]]*bind(-key)?[[:space:]]+-n[[:space:]]+M-[123]\b' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'unbind -n M-1' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'unbind -n M-2' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'unbind -n M-3' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-h' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-j' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-k' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-l' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-z resize-pane -Z' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-a' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-e' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-t' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-E.*--toggle-editor' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-T.*--toggle-term' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-H.*--swap left' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-J.*--swap down' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-K.*--swap up' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-L.*--swap right' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'set -g @ide_is_editor' "$TEMP_HOME/.tmux.conf" && \
   [ "$(grep -c '#{E:@ide_is_editor}' "$TEMP_HOME/.tmux.conf")" -ge 6 ] && \
   [ "$(grep -c 'm/ri:\^g?(view' "$TEMP_HOME/.tmux.conf")" -eq 1 ] && \
   grep -q 'bind -n M-Left resize-pane -L 5' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n MouseDrag1Border resize-pane -M' "$TEMP_HOME/.tmux.conf" && \
   grep -q '@ide_tab_ai' "$TEMP_HOME/.tmux.conf" && \
   grep -q '@ide_tab_ed' "$TEMP_HOME/.tmux.conf" && \
   grep -q '@ide_tab_term' "$TEMP_HOME/.tmux.conf" && \
   grep -q '@ide_ed_parked' "$TEMP_HOME/.tmux.conf" && \
   grep -q '@ide_term_parked' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n M-?.*--keys' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind ?.*--keys' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n MouseDown1StatusLeft choose-tree -Zs' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n MouseDown1Status.*--status-click' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n MouseDown1StatusRight.*--keys' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'bind -n MouseDown3Status display-menu' "$TEMP_HOME/.tmux.conf" && \
   grep -q 'IDE_AI_CLI' "$TEMP_HOME/.tmux.conf"; then
    pass ".tmux.conf configures Solarized Dark top header bar (fixed status-left, 3-state @ide_tab_* role switcher with parked indicators, mode-contextual status-right, Alt+? cheatsheet popup, clickable status bar), deduplicated @ide_is_editor predicate, extended-keys, TrueColor undercurls, xclip/OSC52 clipboard pipeline, 4-layer Alt focus/swap/toggle bindings, and mouse/arrow border resizing"
else
    fail ".tmux.conf verification" "Missing expected Solarized Dark top bar, @ide_tab_* 3-state badges, Alt+? cheatsheet popup, @ide_is_editor deduplication, extended-keys, clipboard, 4-layer keybinding, or mouse/arrow border resize settings in .tmux.conf"
fi

if command -v tmux >/dev/null 2>&1; then
    TMUX_TEST_SOCK="test-tmux-cfg-$$"
    if tmux -L "$TMUX_TEST_SOCK" -f "$TEMP_HOME/.tmux.conf" new-session -d -s cfg_test -n ide "exec sleep 30" >/dev/null 2>&1; then
        cfg_pane="$(tmux -L "$TMUX_TEST_SOCK" display-message -p -t "=cfg_test:" '#{pane_id}')"
        for _ in $(seq 1 20); do
            [ "$(tmux -L "$TMUX_TEST_SOCK" display-message -p -t "$cfg_pane" '#{pane_current_command}')" = "sleep" ] && break
            sleep 0.02
        done
        tmux -L "$TMUX_TEST_SOCK" set-option -p -t "$cfg_pane" @ide_role editor
        tmux -L "$TMUX_TEST_SOCK" set-option -t "=cfg_test:" @ide_ai_cli agy
        tmux -L "$TMUX_TEST_SOCK" set-option -t "=cfg_test:" @ide_ai_parked 0
        tmux -L "$TMUX_TEST_SOCK" set-option -t "=cfg_test:" @ide_ed_parked 0
        tmux -L "$TMUX_TEST_SOCK" set-option -t "=cfg_test:" @ide_term_parked 1
        tmux -L "$TMUX_TEST_SOCK" set-option -t "=cfg_test:" @ide_initial_root "/tmp/ws"
        tmux -L "$TMUX_TEST_SOCK" set-option -t "=cfg_test:" @ide_workdir "/tmp/ws"
        eval_editor_non_shell="$(tmux -L "$TMUX_TEST_SOCK" display-message -p -t "$cfg_pane" '#{E:@ide_is_editor}')"
        eval_sleft="$(tmux -L "$TMUX_TEST_SOCK" display-message -p -t "$cfg_pane" '#{E:status-left}')"
        eval_wcur="$(tmux -L "$TMUX_TEST_SOCK" display-message -p -t "$cfg_pane" '#{E:window-status-current-format}')"
        eval_sright_root="$(tmux -L "$TMUX_TEST_SOCK" display-message -p -t "$cfg_pane" '#{E:status-right}')"
        tmux -L "$TMUX_TEST_SOCK" set-option -t "=cfg_test:" @ide_workdir "/tmp/ws/subdir"
        eval_sright_sub="$(tmux -L "$TMUX_TEST_SOCK" display-message -p -t "$cfg_pane" '#{E:status-right}')"
        tmux -L "$TMUX_TEST_SOCK" set-option -p -t "$cfg_pane" @ide_role ai
        eval_ai_non_editor="$(tmux -L "$TMUX_TEST_SOCK" display-message -p -t "$cfg_pane" '#{E:@ide_is_editor}')"
        tmux -L "$TMUX_TEST_SOCK" kill-server >/dev/null 2>&1 || true
        if [ "$eval_editor_non_shell" = "1" ] && [ "$eval_ai_non_editor" = "0" ] && \
           grep -Fq "cfg_test" <<< "$eval_sleft" && \
           grep -Fq "agy (Alt+a)" <<< "$eval_wcur" && \
           grep -Fq "▸ " <<< "$eval_wcur" && \
           grep -Fq "Editor (Alt+e)" <<< "$eval_wcur" && \
           grep -Fq "Shell [Alt+T]" <<< "$eval_wcur" && \
           grep -Fq "Help (Alt+?)" <<< "$eval_sright_root" && \
           ! grep -Fq "subdir" <<< "$eval_sright_root" && \
           grep -Fq "subdir" <<< "$eval_sright_sub"; then
            pass ".tmux.conf loads cleanly into live headless tmux server and evaluates #{E:@ide_is_editor}, fixed status-left, 3-state window-status-current-format, and conditional status-right"
        else
            fail ".tmux.conf live evaluation" "Unexpected evaluation: editor=$eval_editor_non_shell ai=$eval_ai_non_editor sleft='$eval_sleft' wcur='$eval_wcur' sright_root='$eval_sright_root' sright_sub='$eval_sright_sub'"
        fi
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
   grep -q 'vim_keys = true' "$TEMP_HOME/.config/btop/btop.conf" && \
   grep -q 'save_config_on_exit = false' "$TEMP_HOME/.config/btop/btop.conf"; then
    pass "btop config contains solarized_dark theme, truecolor = true, vim_keys = true, and save_config_on_exit = false"
else
    fail "btop config verification" "Missing expected solarized_dark theme, truecolor, vim_keys, or save_config_on_exit = false in .config/btop/btop.conf"
fi

if [ -f "$TEMP_HOME/.config/btop/themes/solarized_dark.theme" ] && \
   grep -q 'theme\[main_bg\]="#002b36"' "$TEMP_HOME/.config/btop/themes/solarized_dark.theme" && \
   grep -q 'theme\[main_fg\]="#839496"' "$TEMP_HOME/.config/btop/themes/solarized_dark.theme" && \
   grep -q 'theme\[title\]="#93a1a1"' "$TEMP_HOME/.config/btop/themes/solarized_dark.theme" && \
   grep -q 'theme\[cpu_box\]="#586e75"' "$TEMP_HOME/.config/btop/themes/solarized_dark.theme" && \
   grep -q 'theme\[hi_fg\]="#b58900"' "$TEMP_HOME/.config/btop/themes/solarized_dark.theme"; then
    pass "btop theme contains authentic Solarized Dark palette tokens"
else
    fail "btop theme verification" "Missing or invalid solarized_dark.theme in .config/btop/themes"
fi

assert_symlink "$TEMP_HOME/.config/git" "" "Auto-discovered and symlinked: .config/git"
if [ -f "$TEMP_HOME/.config/git/config" ] && \
   grep -q 'pager = delta' "$TEMP_HOME/.config/git/config" && \
   grep -q 'diffFilter = delta --color-only' "$TEMP_HOME/.config/git/config" && \
   grep -q 'syntax-theme = Solarized-Dark-TrueColor' "$TEMP_HOME/.config/git/config" && \
   grep -q 'hunk-header-style = line-number syntax' "$TEMP_HOME/.config/git/config" && \
   grep -q 'hunk-header-line-number-style = "#268bd2"' "$TEMP_HOME/.config/git/config" && \
   grep -q 'plus-style = syntax "#0d3834"' "$TEMP_HOME/.config/git/config" && \
   grep -q 'minus-style = syntax "#2d222a"' "$TEMP_HOME/.config/git/config" && \
   ! grep -Eq '\bbold\b' "$TEMP_HOME/.config/git/config" && \
   grep -q 'line-numbers-plus-style = "#859900"' "$TEMP_HOME/.config/git/config" && \
   grep -q 'line-numbers-minus-style = "#dc322f"' "$TEMP_HOME/.config/git/config"; then
    pass "git config configures delta with Solarized-Dark-TrueColor theme, diffFilter, distinct +/- backgrounds, unbolded typography, and line numbers"
else
    fail "git config verification" "Missing expected delta pager configuration in .config/git/config"
fi
if command -v delta >/dev/null 2>&1; then
    DELTA_OUT="$(printf 'diff --git a/sample.toml b/sample.toml\n--- a/sample.toml\n+++ b/sample.toml\n@@ -1,1 +1,1 @@\n-bold = true\n+bold = false\n' | GIT_CONFIG_GLOBAL="$TEMP_HOME/.config/git/config" delta --paging=never 2>/dev/null || true)"
    if grep -Fq $'\033[38;2;38;139;210m1\033[0m:' <<< "$DELTA_OUT" && \
       grep -Fq $'\033[48;2;45;34;42' <<< "$DELTA_OUT" && \
       grep -Fq $'\033[48;2;13;56;52' <<< "$DELTA_OUT"; then
        pass "delta live rendering emits Solarized Blue hunk line numbers (#268bd2) and distinct minus (#2d222a) and plus (#0d3834) line backgrounds"
    else
        fail "delta live rendering" "Expected TrueColor hunk line number and distinct +/- background ANSI sequences from delta"
    fi
fi
assert_symlink "$TEMP_HOME/.config/tealdeer" "" "Auto-discovered and symlinked: .config/tealdeer"
if [ -f "$TEMP_HOME/.config/tealdeer/config.toml" ] && \
   grep -q '\[style\.command_name\]' "$TEMP_HOME/.config/tealdeer/config.toml" && \
   grep -q 'bold = false' "$TEMP_HOME/.config/tealdeer/config.toml" && \
   grep -q '\[style\.description\]' "$TEMP_HOME/.config/tealdeer/config.toml" && \
   grep -q 'r = 131, g = 148, b = 150' "$TEMP_HOME/.config/tealdeer/config.toml" && \
   grep -q 'r = 211, g = 54, b = 130' "$TEMP_HOME/.config/tealdeer/config.toml" && \
   grep -q 'auto_update = true' "$TEMP_HOME/.config/tealdeer/config.toml"; then
    pass "tealdeer config contains unbolded Solarized Dark TrueColor styling (Magenta variables) and auto_update = true"
else
    fail "tealdeer config verification" "Missing or invalid config.toml in .config/tealdeer"
fi
if command -v tldr >/dev/null 2>&1; then
    TLDR_SAMPLE="$TEMP_HOME/sample-tldr.md"
    printf '# tar\n\n> Archiving utility.\n\n- Create an archive:\n\n`tar cf {{target.tar}}`\n' > "$TLDR_SAMPLE"
    TLDR_OUT="$(tldr --no-auto-update --config-path "$TEMP_HOME/.config/tealdeer/config.toml" --color=always --render "$TLDR_SAMPLE" 2>/dev/null || true)"
    if grep -Fq $'\033[38;2;133;153;0mtar\033[0m' <<< "$TLDR_OUT" && \
       grep -Fq $'\033[4;38;2;211;54;130mtarget.tar\033[0m' <<< "$TLDR_OUT"; then
        pass "tealdeer live rendering emits unbolded Solarized Green command_name (#859900) and underlined Magenta example_variable (#d33682)"
    else
        fail "tealdeer live rendering" "Expected unbolded Green command and underlined Magenta variable ANSI sequences from tldr --render"
    fi
fi

assert_symlink "$TEMP_HOME/.config/fontconfig" "" "Auto-discovered and symlinked: .config/fontconfig"
if [ -f "$TEMP_HOME/.config/fontconfig/conf.d/10-meslo-nerd-font.conf" ] && \
   grep -q 'MesloLGS Nerd Font Mono' "$TEMP_HOME/.config/fontconfig/conf.d/10-meslo-nerd-font.conf"; then
    pass "fontconfig conf.d contains 10-meslo-nerd-font.conf alias mapping"
else
    fail "fontconfig conf.d verification" "Missing or invalid .config/fontconfig/conf.d/10-meslo-nerd-font.conf"
fi

assert_symlink "$TEMP_HOME/.config/bat/themes/Solarized-Dark-TrueColor.tmTheme" "" "Symlinked Bat theme"
for syn in "$SCRIPT_DIR/syntaxes"/*.sublime-syntax; do
    [ -e "$syn" ] || continue
    syn_name="$(basename "$syn")"
    assert_symlink "$TEMP_HOME/.config/bat/syntaxes/$syn_name" "" "Symlinked Bat syntax: $syn_name"
done
if grep -q '\.bashrc-addendum' "$TEMP_HOME/.config/bat/syntaxes/Bash.sublime-syntax" && \
   grep -q '\.zshrc-addendum' "$TEMP_HOME/.config/bat/syntaxes/Bash.sublime-syntax"; then
    pass "Bash.sublime-syntax maps .bashrc-addendum and .zshrc-addendum file extensions"
else
    fail "Bash.sublime-syntax file_extensions" "Missing .bashrc-addendum or .zshrc-addendum in Bash.sublime-syntax"
fi

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
   grep -q "keyword.control.directive.proto" "$THEME_FILE" && \
   grep -q "entity.name.function.rpc.proto" "$THEME_FILE" && \
   grep -q "entity.name.section.message.textproto" "$THEME_FILE" && \
   grep -q "support.type.property-name.textproto" "$THEME_FILE" && \
   grep -q "source.kotlin storage.type.primitive" "$THEME_FILE" && \
   grep -q "source.kotlin meta.interpolation" "$THEME_FILE" && \
   grep -q "source.swift storage.type.primitive" "$THEME_FILE" && \
   grep -q "source.swift meta.interpolation" "$THEME_FILE" && \
   grep -q "source.lua keyword.declaration" "$THEME_FILE" && \
   grep -q "source.dockerfile keyword.other.special-method" "$THEME_FILE" && \
   grep -q "source.makefile entity.name.function.target" "$THEME_FILE" && \
   grep -q "variable, variable.other, variable.parameter" "$THEME_FILE"; then
    pass "Solarized-Dark-TrueColor.tmTheme defines complete Markdown, C/C++, Java, Kotlin, Swift, Lua, Dockerfile, Makefile, Diff, Go, Python, Rust, Bash, XML, HTML, JSON, YAML, TOML, CSS, Properties, Protobuf, Textproto, Namespace, Attribute, and Error scopes"
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
    bat_render() {
        HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" XDG_CACHE_HOME="$TEMP_HOME/.cache" BAT_THEME="Solarized-Dark-TrueColor" "$BAT_BIN" --color=always --style=plain --paging=never "$@"
    }
    MD_OUT="$(printf "# Header 1\n## Header 2\n### Header 3\n#### Header 4\n**bold text**\n" | bat_render -l md - 2>/dev/null || true)"
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

    C_OUT="$(echo -e "#include <stdio.h>" | bat_render -l c - 2>/dev/null || true)"
    if grep -Fq "$SOL_ORANGE" <<< "$C_OUT"; then
        pass "bat renders C/C++ preprocessor directives in Solarized Orange"
    else
        fail "bat C preprocessor rendering" "Expected Orange preprocessor directive in bat output"
    fi

    DIFF_OUT="$(echo -e "--- a\n+++ b\n-old\n+new" | bat_render -l diff - 2>/dev/null || true)"
    if grep -Fq "$SOL_GREEN" <<< "$DIFF_OUT" && grep -Fq "$SOL_RED" <<< "$DIFF_OUT"; then
        pass "bat renders Unified Diffs with Solarized Green additions and Red deletions"
    else
        fail "bat Diff rendering" "Expected Green additions and Red deletions in bat diff output"
    fi

    QUOTE_OUT="$(printf "> quote text\n" | bat_render -l md - 2>/dev/null || true)"
    if grep -Fq "$SOL_BASE0" <<< "$QUOTE_OUT" && grep -Fq "$SOL_BASE01" <<< "$QUOTE_OUT"; then
        pass "bat renders Markdown blockquotes in Solarized Base0 with Base01 marker"
    else
        fail "bat blockquote rendering" "Expected Base0 text and Base01 marker in bat blockquote output"
    fi

    GO_OUT="$(printf "type MyStruct struct {}\n" | bat_render -l go - 2>/dev/null || true)"
    if grep -Fq "$SOL_BASE0" <<< "$GO_OUT"; then
        pass "bat renders custom struct types in calm Base0"
    else
        fail "bat custom type rendering" "Expected Base0 struct type in bat output"
    fi

    C_TYPE_OUT="$(printf "int x = 42;\n" | bat_render -l c - 2>/dev/null || true)"
    if grep -Fq "$SOL_GREEN" <<< "$C_TYPE_OUT"; then
        pass "bat renders primitive C types (int, char, etc.) in Solarized Green"
    else
        fail "bat primitive type rendering" "Expected Green primitive type in bat output"
    fi

    C_STR_OUT="$(printf 'printf("Hello %%s\\n");\n' | bat_render -l c - 2>/dev/null || true)"
    if grep -Fq "$SOL_CYAN" <<< "$C_STR_OUT"; then
        pass "bat renders string format specifiers and escapes in Solarized Cyan"
    else
        fail "bat string escape rendering" "Expected Cyan string escape in bat output"
    fi

    C_DECL_OUT="$(printf "typedef struct {\n    int x;\n} Node;\n" | bat_render -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}typedef" <<< "$C_DECL_OUT" && grep -Fq "${SOL_GREEN}struct" <<< "$C_DECL_OUT"; then
        pass "bat renders C declaration keywords (typedef, struct) in Solarized Green"
    else
        fail "bat C declaration rendering" "Expected Green typedef/struct in bat output"
    fi

    ESC_ITALIC="$(printf "\033[3;")"
    C_MACRO_OUT="$(printf '#define CLAMP(x, low, high) (((x) > (high)) ? (high) : (x))\n' | BAT_OPTS="--italic-text=always" bat_render -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}#define" <<< "$C_MACRO_OUT" && \
       grep -Fq "${SOL_BASE0}x" <<< "$C_MACRO_OUT" && \
       ! grep -Fq "$ESC_ITALIC" <<< "$C_MACRO_OUT"; then
        pass "bat renders macro parameters and body expressions in upright Solarized Base0 (grey) matching Neovim"
    else
        fail "bat macro parameter rendering" "Expected upright Base0 grey parameters and body expressions in macro"
    fi

    C_COMMENT_OUT="$(printf '/* sample comment */\n' | BAT_OPTS="--italic-text=always" bat_render -l c - 2>/dev/null || true)"
    if grep -Fq "$SOL_BASE01" <<< "$C_COMMENT_OUT" && ! grep -Fq "$ESC_ITALIC" <<< "$C_COMMENT_OUT"; then
        pass "bat renders C comments in upright Solarized Base01 without italics"
    else
        fail "bat comment rendering" "Expected upright Base01 comment without italics in bat output"
    fi

    MD_ITALIC_OUT="$(printf '*explicit italic*\n' | BAT_OPTS="--italic-text=always" bat_render -l md - 2>/dev/null || true)"
    if grep -Fq "$ESC_ITALIC" <<< "$MD_ITALIC_OUT"; then
        pass "bat renders explicitly tagged Markdown *italic* with true italics"
    else
        fail "bat markdown italic rendering" "Expected italics on explicitly tagged Markdown"
    fi

    # --- 2.2 C Syntax Verification ---
    C_PREPROC_OUT="$(printf '#ifndef LOG_LEVEL\n#define LOG_LEVEL 2\n#endif\n#ifdef __linux__\n#undef LOG_LEVEL\n' | bat_render -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}#ifndef" <<< "$C_PREPROC_OUT" && \
       grep -Fq "${SOL_ORANGE}LOG_LEVEL" <<< "$C_PREPROC_OUT" && \
       grep -Fq "${SOL_ORANGE}#ifdef" <<< "$C_PREPROC_OUT" && \
       grep -Fq "${SOL_ORANGE}__linux__" <<< "$C_PREPROC_OUT" && \
       grep -Fq "${SOL_ORANGE}#undef" <<< "$C_PREPROC_OUT"; then
        pass "bat renders preprocessor macro identifiers in conditional directives (#ifndef LOG_LEVEL, #ifdef, #undef) in Solarized Orange"
    else
        fail "bat preprocessor conditional macro rendering" "Expected Solarized Orange macro identifiers in preprocessor conditionals"
    fi

    C_CONST_OUT="$(printf 'int res = EXIT_FAILURE;\n' | bat_render -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_MAGENTA}EXIT_FAILURE" <<< "$C_CONST_OUT"; then
        pass "bat renders named uppercase constants (EXIT_FAILURE, etc.) in Solarized Magenta"
    else
        fail "bat constant rendering" "Expected Magenta named constants in bat output"
    fi

    C_CUSTOM_TYPE_OUT="$(printf 'WorkerNode *node = malloc(sizeof(WorkerNode));\n' | bat_render -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_BASE0}WorkerNode" <<< "$C_CUSTOM_TYPE_OUT"; then
        pass "bat renders custom PascalCase types (WorkerNode, etc.) in calm Solarized Base0"
    else
        fail "bat custom type rendering" "Expected Base0 custom PascalCase type in bat output"
    fi

    C_WORD_OP_OUT="$(printf 'sizeof(int);\n' | bat_render -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}sizeof" <<< "$C_WORD_OP_OUT"; then
        pass "bat renders word operators (sizeof, etc.) in Solarized Green matching Neovim"
    else
        fail "bat word operator rendering" "Expected Green sizeof in bat output"
    fi

    C_FUNC_CALL_OUT="$(printf 'emit_log(0, "test");\n' | bat_render -l c - 2>/dev/null || true)"
    if grep -Fq "${SOL_BASE0}emit_log" <<< "$C_FUNC_CALL_OUT"; then
        pass "bat renders user function calls (emit_log, etc.) in calm Solarized Base0 matching Neovim"
    else
        fail "bat function call rendering" "Expected Base0 emit_log call in bat output"
    fi

    C_SAMPLE_OUT="$(bat_render -l c "$SCRIPT_DIR/sample-code/sample.c" 2>/dev/null || true)"
    if grep -Fq "${SOL_YELLOW}if" <<< "$C_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}return" <<< "$C_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}switch" <<< "$C_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}case" <<< "$C_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}default" <<< "$C_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}for" <<< "$C_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}static_assert" <<< "$C_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}constexpr" <<< "$C_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}alignof" <<< "$C_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}[[" <<< "$C_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}nodiscard" <<< "$C_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}]]" <<< "$C_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}nullptr" <<< "$C_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}10101100" <<< "$C_SAMPLE_OUT"; then
        pass "bat renders C23 showcase (sample.c): control flow (if, return, switch, case, default, for) in Yellow, C23 keywords (static_assert, constexpr, alignof) in Green, unified [[nodiscard]] attribute in Violet, and nullptr / binary literals in Magenta matching Neovim"
    else
        fail "bat C23 sample rendering" "Expected Yellow control flow, Green static_assert/constexpr/alignof, Violet [[nodiscard]], and Magenta nullptr/0b10101100U in bat sample.c output"
    fi

    # --- 2.3 C++ Syntax Verification ---
    CPP_TEMPLATE_OUT="$(printf 'template <Printable T>\nclass Node {\nstd::vector<T> items;\n};\n' | bat_render -l cpp - 2>/dev/null || true)"
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

    CPP_DECL_NS_OUT="$(printf 'namespace core::telemetry {\n}\n' | bat_render -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}namespace" <<< "$CPP_DECL_NS_OUT" && \
       grep -Fq "${SOL_VIOLET}core" <<< "$CPP_DECL_NS_OUT" && \
       grep -Fq "${SOL_VIOLET}telemetry" <<< "$CPP_DECL_NS_OUT"; then
        pass "bat renders namespace declaration keywords in Solarized Green and namespace identifiers (core, telemetry) in Solarized Violet matching Neovim"
    else
        fail "bat namespace definition rendering" "Expected Green namespace keyword and Violet core::telemetry identifiers in bat output"
    fi

    CPP_NS_OUT="$(printf 'using namespace core::telemetry;\nstd::string s;\n' | bat_render -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}using" <<< "$CPP_NS_OUT" && \
       grep -Fq "${SOL_VIOLET}core" <<< "$CPP_NS_OUT" && \
       grep -Fq "${SOL_VIOLET}telemetry" <<< "$CPP_NS_OUT" && \
       grep -Fq "${SOL_BASE0}std" <<< "$CPP_NS_OUT"; then
        pass "bat renders using namespace keywords in Solarized Green, namespace targets (core, telemetry) in Solarized Violet, and qualifiers (std) in calm Base0 Grey matching Neovim"
    else
        fail "bat using namespace rendering" "Expected Green using keyword, Violet namespace targets, and Base0 qualifiers in bat output"
    fi

    CPP_CONST_OUT="$(printf 'NodeState state_{NodeState::Initializing};\nreturn std::nullopt;\n' | bat_render -l cpp - 2>/dev/null || true)"
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

    CPP_CONCEPT_OUT="$(printf '{ std::cout << t } -> std::same_as<std::ostream&>;\n' | bat_render -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_BASE0}same_as" <<< "$CPP_CONCEPT_OUT"; then
        pass "bat renders standard C++20 concepts (same_as) in calm Solarized Base0 matching Neovim"
    else
        fail "bat C++20 concept rendering" "Expected Base0 same_as concept in bat output"
    fi

    CPP_ENUM_OUT="$(printf 'enum class NodeState : uint8_t {\n};\n' | bat_render -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_BASE0}NodeState" <<< "$CPP_ENUM_OUT" && \
       grep -Fq "${SOL_GREEN}uint8_t" <<< "$CPP_ENUM_OUT"; then
        pass "bat renders enum class types in calm Solarized Base0 and underlying primitive types (uint8_t) in Solarized Green matching Neovim"
    else
        fail "bat enum type rendering" "Expected Base0 enum name and Green underlying type in bat output"
    fi

    CPP_QUAL_FUNC_OUT="$(printf 'void test() {\n    std::move(metric);\n    std::for_each(items.begin(), items.end());\n}\n' | bat_render -l cpp - 2>/dev/null || true)"
    if grep -Fq "${SOL_BASE0}std" <<< "$CPP_QUAL_FUNC_OUT" && \
       grep -Fq "${SOL_BASE0}move" <<< "$CPP_QUAL_FUNC_OUT" && \
       grep -Fq "${SOL_BASE0}for_each" <<< "$CPP_QUAL_FUNC_OUT"; then
        pass "bat renders namespace-qualified function calls (std::move, std::for_each) with Base0 Grey namespace and function matching Neovim"
    else
        fail "bat qualified function rendering" "Expected Base0 Grey std and Base0 move/for_each in bat output"
    fi

    CPP_SAMPLE_OUT="$(bat_render -l cpp "$SCRIPT_DIR/sample-code/sample.cpp" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}[[" <<< "$CPP_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}nodiscard" <<< "$CPP_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}]]" <<< "$CPP_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}static_assert" <<< "$CPP_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}noexcept" <<< "$CPP_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}switch" <<< "$CPP_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}case" <<< "$CPP_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}default" <<< "$CPP_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}describe_state" <<< "$CPP_SAMPLE_OUT"; then
        pass "bat renders C++20/23 showcase (sample.cpp): attributes ([[nodiscard]]) in Violet, static_assert/noexcept in Green, switch/case/default in Yellow, and method declarations (describe_state) in Blue matching Neovim"
    else
        fail "bat C++ sample rendering" "Expected Violet [[nodiscard]], Green static_assert/noexcept, Yellow switch/case/default, and Blue describe_state in bat sample.cpp output"
    fi

    # --- 2.4 Diff Syntax Verification ---
    DIFF_SAMPLE_OUT="$(bat_render -l diff "$SCRIPT_DIR/sample-code/sample.diff" 2>/dev/null || true)"
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
    GO_SAMPLE_OUT="$(bat_render -l go "$SCRIPT_DIR/sample-code/sample.go" 2>/dev/null || true)"
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
       grep -Fq "${SOL_GREEN}comparable" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}LevelDebug" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}MaskAll" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}NewClusterNode" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}ResolveDefault" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}for" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}range" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}return" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}select" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}defer" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}case" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}default" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}panic" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}make" <<< "$GO_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}\`json:\"port\"\`" <<< "$GO_SAMPLE_OUT"; then
        pass "bat renders Converged Ergonomic Go: structural scaffolding & primitive/constraint types (Green package/type/func/struct/interface/int/string/comparable), control flow (Yellow if/for/range/return/select/defer/case/default), function calls & builtins (Base0 panic/make), custom types in calm Base0 (Context/ClusterNode), generic & method declarations (Blue NewClusterNode/ResolveDefault), package identity & imports (Violet main/import), constants & sentinels (Magenta LevelDebug/MaskAll/iota/nil), struct tags (Cyan), and qualifiers (Base0 context.) matching Neovim"
    else
        fail "bat Go rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.go output"
    fi

    # --- 2.6 Java Syntax Verification ---
    JAVA_SAMPLE_OUT="$(bat_render -l java "$SCRIPT_DIR/sample-code/sample.java" 2>/dev/null || true)"
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
       grep -Fq "${SOL_MAGENTA}this" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}super" <<< "$JAVA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}///" <<< "$JAVA_SAMPLE_OUT"; then
        pass "bat renders Converged Ergonomic Java: structural scaffolding & primitive types (Green public/class/implements/new/int), control flow (Yellow if/throw/when/default), constructor delegation (Base0 super), custom types in calm Base0 (Instant/OrderRecord), method declarations (Blue findById), annotations & imports (Violet @interface/@Service/import), constants, numbers & receivers (Magenta DEFAULT_BUFFER_SIZE/1L/100.0/this), and comments (Base01 ///) matching Neovim"
    else
        fail "bat Java rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.java output"
    fi

    # --- 2.7 Python Syntax Verification ---
    PYTHON_SAMPLE_OUT="$(bat_render -l py "$SCRIPT_DIR/sample-code/sample.py" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}from" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}asyncio" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}typing" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Callable" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}EndpointMetrics" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}MetricTagMap" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}type" <<< "$PYTHON_SAMPLE_OUT" && \
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
       grep -Fq "${SOL_BLUE}classify_status" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}async" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}try" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}return" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}await" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}finally" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}match" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}case" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@dataclass" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@property" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}self" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}None" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}MetricsCollector" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}__init__" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}__name__" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}.4f" <<< "$PYTHON_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}\"\"\"" <<< "$PYTHON_SAMPLE_OUT"; then
        pass "bat renders Python imports/modules/decorators (Violet), PEP 695 type statement & built-in types (Green type/int/float/str/bool/dict/list/set/tuple), custom types/classes (Base0 Callable/EndpointMetrics/MetricTagMap), constants/self/None (Magenta), scaffolding (Green def/async), control flow & pattern matching (Yellow try/return/await/if/match/case), format specifiers (.4f in Cyan), and declarations (Blue) matching Neovim"
    else
        fail "bat Python rendering" "Expected Modern Python Solarized TrueColor highlights in bat sample.py output"
    fi

    # --- 2.8 Rust Syntax Verification ---
    RUST_SAMPLE_OUT="$(bat_render -l rs "$SCRIPT_DIR/sample-code/sample.rs" 2>/dev/null || true)"
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
       grep -Fq "${SOL_BLUE}active_port" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}'a" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}self" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}struct" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}ServerNode" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Some" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}None" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}where" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}impl" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}match" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}else" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}return" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}write" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}let" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}mut" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}println" <<< "$RUST_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}///" <<< "$RUST_SAMPLE_OUT"; then
        pass "bat renders Rust imports/attributes (Violet), custom types & Option::Some constructor (Base0), primitive types & scaffolding/lifetimes (Green), control flow & let-else (Yellow), constants/variants/self/None (Magenta), and macro/function declarations (Blue) matching Neovim"
    else
        fail "bat Rust rendering" "Expected Modern Rust Solarized TrueColor highlights in bat sample.rs output"
    fi

    # --- 2.9 Bash Syntax Verification ---
    SH_SAMPLE_OUT="$(bat_render -l sh "$SCRIPT_DIR/sample-code/sample.sh" 2>/dev/null || true)"
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
       grep -Fq "${SOL_MAGENTA}SERVICE_TIERS" <<< "$SH_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}unknown" <<< "$SH_SAMPLE_OUT" && \
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
        pass "bat renders Converged Ergonomic Shell: shebang (Orange), scaffolding & declarations (Green), control flow (Yellow), function declarations (Blue), invocations & commands (calm Base0), expansion sigils & fallback defaults (\$ / \${ / unknown in Base0), constants & signals (Magenta), and strings & subscripts (Cyan) matching Neovim"
    else
        fail "bat Shell rendering" "Expected Converged Ergonomic Shell Solarized TrueColor highlights in bat sample.sh output"
    fi

    # --- 2.10 SQL Syntax Verification ---
    SQL_SAMPLE_OUT="$(bat_render -l sql "$SCRIPT_DIR/sample-code/sample.sql" 2>/dev/null || true)"
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
       grep -Fq "${SOL_GREEN}JSONB" <<< "$SQL_SAMPLE_OUT" && \
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
       grep -Fq "${SOL_GREEN}INSERT INTO" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}VALUES" <<< "$SQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}RETURNING" <<< "$SQL_SAMPLE_OUT" && \
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
        pass "bat renders SQL keywords and data types (Green JSONB/INSERT/INTO/VALUES/RETURNING), relation entities (Base0), conditionals (Yellow), function calls (Base0), DEFAULT/ASC/DESC keywords (Green), booleans/sentinels/numbers (Magenta), and calm Base0 column qualifiers matching Neovim"
    else
        fail "bat SQL rendering" "Expected Converged Ergonomic SQL Solarized TrueColor highlights in bat sample.sql output"
    fi

    # --- 2.11 Terraform / HCL Syntax Verification ---
    TF_SAMPLE_OUT="$(bat_render -l tf "$SCRIPT_DIR/sample-code/sample.tf" 2>/dev/null || true)"
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
       grep -Fq "${SOL_GREEN}moved" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}check" <<< "$TF_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}assert" <<< "$TF_SAMPLE_OUT" && \
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
        pass "bat renders Terraform declaration keywords & scope accessors (Green moved/check/resource/var), block schemas & data types (Base0 assert/lifecycle/string), control flow (Yellow), function calls (Base0), booleans/numbers (Magenta), strings (Cyan), and calm Base0 attributes/interpolation delimiters matching Neovim"
    else
        fail "bat Terraform rendering" "Expected Converged Ergonomic Terraform Solarized TrueColor highlights in bat sample.tf output"
    fi

    # --- 2.12 Markdown Syntax Verification ---
    MD_SAMPLE_OUT="$(bat_render -l md "$SCRIPT_DIR/sample-code/sample.md" 2>/dev/null || true)"
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
       grep -Fq "${SOL_RED}[!CAUTION]" <<< "$MD_SAMPLE_OUT" && \
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
       grep -Fq "${SOL_CYAN}<https://github.com/example/home-settings>" <<< "$MD_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}<maintainers@example.com>" <<< "$MD_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_YELLOW}Workstation Architecture" <<< "$MD_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_YELLOW}1. Executive Summary" <<< "$MD_SAMPLE_OUT"; then
        pass "bat renders Markdown showcase (sample.md) with Semantic Architecture: H1 Orange, H2 Blue, H3 Violet, H4 Base1, H5/H6 Base0, Base01 hashmarks/quote markers, GitHub alerts ([!NOTE], [!TIP], [!IMPORTANT], [!WARNING], [!CAUTION]), task checkboxes, Base1 table headers with Base01 borders, Cyan autolinks, embedded Bash with Magenta \$HOME and Base0 commands, embedded Go with Green func/package, Violet main, Blue declarations, Base0 calls (errors.New), Magenta nil, and exclusive Yellow control flow"
    else
        fail "bat Markdown showcase rendering" "Expected Semantic Architecture TrueColor highlights in bat sample.md output"
    fi

    # --- 2.13 TypeScript & JavaScript Syntax Verification ---
    TS_SAMPLE_OUT="$(bat_render -l ts "$SCRIPT_DIR/sample-code/sample.ts" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}export" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}enum" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}type" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}interface" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}class" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}boolean" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}number" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}string" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}readonly" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}keyof" <<< "$TS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}satisfies" <<< "$TS_SAMPLE_OUT" && \
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
       grep -Fq "${SOL_BASE0}ProfileAttributeKey" <<< "$TS_SAMPLE_OUT" && \
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
        pass "bat renders TypeScript showcase (sample.ts) with Converged Ergonomic Solarized: imports/exports in Violet, declarations, type operators (keyof/satisfies) & primitive types in Green, exclusive control flow in Yellow, method declarations in Blue, invocations & custom types in Base0, and constants/numbers in Magenta matching Neovim"
    else
        fail "bat TypeScript rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.ts output"
    fi

    JS_SAMPLE_OUT="$(bat_render -l js "$SCRIPT_DIR/sample-code/sample.js" 2>/dev/null || true)"
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
    XML_SAMPLE_OUT="$(bat_render -l xml "$SCRIPT_DIR/sample-code/sample.xml" 2>/dev/null || true)"
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
    HTML_SAMPLE_OUT="$(bat_render -l html "$SCRIPT_DIR/sample-code/sample.html" 2>/dev/null || true)"
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
    JSON_SAMPLE_OUT="$(bat_render -l json "$SCRIPT_DIR/sample-code/sample.json" 2>/dev/null || true)"
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
    YAML_SAMPLE_OUT="$(bat_render -l yaml "$SCRIPT_DIR/sample-code/sample.yaml" 2>/dev/null || true)"
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
    TOML_SAMPLE_OUT="$(bat_render -l toml "$SCRIPT_DIR/sample-code/sample.toml" 2>/dev/null || true)"
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
    CSS_SAMPLE_OUT="$(bat_render -l css "$SCRIPT_DIR/sample-code/sample.css" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}@layer" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@font-face" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@keyframes" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@container" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@media" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@supports" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}body" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}dashboard-grid" <<< "$CSS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}main-viewport" <<< "$CSS_SAMPLE_OUT" && \
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
        pass "bat renders CSS showcase (sample.css) with Converged Ergonomic Solarized: at-rules (@layer/@container/@media/@supports) in Orange, selectors (tags, classes, #main-viewport) in Blue, pseudo-classes/elements in Violet, nesting parent '&' and attribute selector names in Base0, attribute strings in Cyan, container queries in Orange/Base0/Magenta, properties in Green (zero Yellow), custom properties unbroken in Base0, keyword values (ui-monospace, monospace, auto, auto-fill) in Base0, strings in Cyan, numbers/hex in Magenta, and delimiters in calm Base0 matching Neovim"
    else
        fail "bat CSS rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.css output"
    fi

    # --- 2.20 Java Properties Syntax Verification ---
    PROPERTIES_SAMPLE_OUT="$(bat_render -l properties "$SCRIPT_DIR/sample-code/sample.properties" 2>/dev/null || true)"
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

    # --- 2.21 Protocol Buffers (.proto) Syntax Verification ---
    PROTO_SAMPLE_OUT="$(bat_render -l proto "$SCRIPT_DIR/sample-code/sample.proto" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}syntax" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}proto3" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}package" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}telemetry" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}import" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}public" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}option" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}message" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}enum" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}oneof" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}service" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}rpc" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}IngestBatch" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}returns" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}uint64" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}TelemetryBatch" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}sequence_num" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}service" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}max" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}NODE_STATE_ACTIVE" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}NODE_STATE_DRAINING" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}-1" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}true" <<< "$PROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}//" <<< "$PROTO_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_YELLOW}" <<< "$PROTO_SAMPLE_OUT"; then
        pass "bat renders Protocol Buffers showcase (sample.proto) with Converged Ergonomic Solarized: syntax directive in Orange, import and package namespace in Violet, structural keywords/returns/scalar types in Green (zero Yellow), RPC methods in Blue, user types and fields/option keys in calm Base0, enum constants/numbers/booleans in Magenta, strings in Cyan, and comments in Base01 matching Neovim"
    else
        fail "bat Protocol Buffers (.proto) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.proto output"
    fi

    # --- 2.22 Protocol Buffers Text Format (.textproto) Syntax Verification ---
    TEXTPROTO_SAMPLE_OUT="$(bat_render -l textproto "$SCRIPT_DIR/sample-code/sample.textproto" 2>/dev/null || true)"
    if grep -Fq "${SOL_BLUE}recorded_at" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}route_quotas" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}metrics" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}extensions" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}batch_id" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}sequence_num" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}quantile_bounds" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}routing_extension" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}SystemHealthPayload" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}NODE_STATE_ACTIVE" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0.375" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}-12" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0x10" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}-inf" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}nan" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}true" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}batch-2025-09-14-0001" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}#" <<< "$TEXTPROTO_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_YELLOW}" <<< "$TEXTPROTO_SAMPLE_OUT"; then
        pass "bat renders Protocol Buffers Text Format showcase (sample.textproto) with Converged Ergonomic Solarized: message block headers in Blue, scalar/array keys in Green (zero Yellow), bracketed extension/Any type URLs in Violet, enum constants/numbers/unified floats/special floats/booleans in Magenta, strings in Cyan, delimiters in calm Base0, and comments in Base01 matching Neovim"
    else
        fail "bat Protocol Buffers Text Format (.textproto) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.textproto output"
    fi

    # --- 2.23 Kotlin (.kt) Syntax Verification ---
    KOTLIN_SAMPLE_OUT="$(bat_render -l kt "$SCRIPT_DIR/sample-code/sample.kt" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}@file:JvmName" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@JvmInline" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}package" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}core" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}telemetry" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}import" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}coroutines" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}*" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}value" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}sealed" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}data" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}companion" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}init" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}constructor" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}where" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}String" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}UInt" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}Any" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}List" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Map" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}formatEvent" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}flushBatch" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}isRecent" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}when" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}suspend" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}continue@" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}is" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}!is" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}!in" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}as?" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}DEFAULT_CAPACITY" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0xCAFE_BABEu" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}field" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}it" <<< "$KOTLIN_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}\${" <<< "$KOTLIN_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_BLUE}coroutines" <<< "$KOTLIN_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_GREEN}List" <<< "$KOTLIN_SAMPLE_OUT"; then
        pass "bat renders Kotlin showcase (sample.kt) with Converged Ergonomic Solarized: unified annotations (@file:JvmName, @JvmInline), package namespace & import keyword in Violet, calm Base0 import segments with Magenta wildcard (*), structural keywords/modifiers/scalar primitives (Int, UInt, String, Any) in Green, container/domain types (List, Map, NodeId) in calm Base0, function declarations (including extension fun TelemetryEvent.isRecent) in Blue, control flow, labeled jumps & suspend in Yellow, unified word operators (is, !is, in, !in, as?) in Green, constants/numbers/receivers (this, super, it, field) in Magenta, and string interpolation neutralized to Base0 inside Cyan strings matching Neovim"
    else
        fail "bat Kotlin (.kt) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.kt output"
    fi

    # --- 2.24 Swift (.swift) Syntax Verification ---
    SWIFT_SAMPLE_OUT="$(bat_render -l swift "$SCRIPT_DIR/sample-code/sample.swift" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}#if" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}canImport" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}#else" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}#endif" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}#available" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}import" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}Foundation" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@available" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@discardableResult" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@Sendable" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}actor" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}protocol" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}associatedtype" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}struct" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}init" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}deinit" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}UInt64" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}Bool" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}is" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}as?" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Sendable" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Equatable" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}inspectStatus" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}dispatch" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}guard" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}defer" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}fallthrough" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}async" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}throws" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}try" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}await" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}MAX_RETRY_LIMIT" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0xCAFE_BABE" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}self" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}\$0" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}nil" <<< "$SWIFT_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}\\(" <<< "$SWIFT_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_GREEN}Sendable" <<< "$SWIFT_SAMPLE_OUT"; then
        pass "bat renders Swift showcase (sample.swift) with Converged Ergonomic Solarized: compiler directives (#if canImport, #else, #endif, #available) in Orange, module imports & attributes (@available, @discardableResult, @Sendable) in Violet, structural keywords (actor, protocol, associatedtype, struct, init, deinit, enum case), word operators (is, as, as?, closure in) & scalar primitives (Int, UInt64, Double, Bool, String) in Green, protocol/domain types (Sendable, Equatable, MetricFrame) in calm Base0, method declarations in Blue, control flow & concurrency (guard, defer, switch/case/default/fallthrough, async, throws, try, await) in Yellow, constants/numbers/receivers (self, \$0, nil) in Magenta, and string interpolation neutralized to Base0 inside Cyan strings matching Neovim"
    else
        fail "bat Swift (.swift) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.swift output"
    fi

    # --- 2.25 Zig (.zig) Syntax Verification ---
    ZIG_SAMPLE_OUT="$(bat_render -l zig "$SCRIPT_DIR/sample-code/sample.zig" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}std" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@import" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}pub" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}const" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}struct" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}enum" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}union" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}error" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}comptime" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}usize" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}u32" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}f64" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}bool" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}test" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}isUrgent" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}RingBuffer" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}dispatchBatch" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}switch" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}return" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}try" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}catch" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}defer" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}errdefer" <<< "$ZIG_SAMPLE_OUT" && \
        grep -Fq "${SOL_YELLOW}while" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}for" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}orelse" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}inline" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}DEFAULT_CAPACITY" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}0xCAFE_BABE" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}undefined" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}null" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}true" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}self" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}_" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}critical" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}TelemetryCollector" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}@memset" <<< "$ZIG_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}id" <<< "$ZIG_SAMPLE_OUT"; then
        pass "bat renders Zig showcase (sample.zig) with Converged Ergonomic Solarized: @import & module bindings in Violet, structural keywords, word operators (orelse) & primitive types in Green, fn declarations (including generic comptime type functions) in Blue, control flow & defer/errdefer/try/catch in Yellow, constants/numbers/null/undefined/self/_ & enum shorthand (.critical) in Magenta, and user types, struct field initializers (.id = 1) & @builtins in calm Base0 matching Neovim"
    else
        fail "bat Zig (.zig) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.zig output"
    fi

    # --- 2.26 C# (.cs) Syntax Verification ---
    CS_SAMPLE_OUT="$(bat_render -l cs "$SCRIPT_DIR/sample-code/sample.cs" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}using" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}namespace" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}Core" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}Telemetry" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}[" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}AttributeUsage" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}Serializable" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}public" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}sealed" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}record" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}interface" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}where" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}get" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}init" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}ushort" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}int" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}new" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}FormatEvent" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}FlushBatchAsync" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}switch" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}when" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}async" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}await" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}foreach" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}in" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}DEFAULT_CAPACITY" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}null" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}default" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}this" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}_" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_CYAN}:F2" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}metricName" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}MetricSample" <<< "$CS_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Where" <<< "$CS_SAMPLE_OUT"; then
        pass "bat renders C# 12/13 showcase (sample.cs) with Converged Ergonomic Solarized: using directives, namespace targets & unified [Attribute] blocks in Violet, structural keywords (namespace, record, interface, where, get, init, new) & primitives (ushort, int) in Green, method declarations in Blue, control flow & async/await/foreach-in/when in Yellow, constants/null/default/this/discard (_) in Magenta, format specifiers (:F2) in Cyan, and interpolated expressions, records & LINQ calls in calm Base0 matching Neovim"
    else
        fail "bat C# (.cs) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.cs output"
    fi

    # --- 2.27 Scala 3 (.scala) Syntax Verification ---
    SCALA_SAMPLE_OUT="$(bat_render -l scala "$SCRIPT_DIR/sample-code/sample.scala" 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}package" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}core" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}telemetry" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}import" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}*" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@tailrec" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@main" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}opaque" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}enum" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}derives" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}trait" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}object" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}extension" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}given" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}using" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}Int" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}Boolean" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}Unit" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}isUrgent" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}flushBatch" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}runTelemetryPreview" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}match" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}case" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}for" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}yield" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}finally" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}DEFAULT_CAPACITY" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}None" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}Nil" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}this" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}name" <<< "$SCALA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}TelemetryEvent" <<< "$SCALA_SAMPLE_OUT"; then
        pass "bat renders Scala 3 showcase (sample.scala) with Converged Ergonomic Solarized: package targets, import keyword & @annotations in Violet, structural keywords (opaque, enum, derives, trait, object, extension, given, using) & scalar primitives (Int, Boolean, Unit) in Green, def declarations in Blue, control flow (match, pattern case, for, yield, finally) in Yellow, constants/None/Nil/this/wildcards in Magenta, and user/collection types & interpolated variables in calm Base0 matching Neovim"
    else
        fail "bat Scala 3 (.scala) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.scala output"
    fi

    # --- 2.28 Ruby (.rb) Syntax Verification ---
    RUBY_SAMPLE_OUT="$(bat_render -l rb "$SCRIPT_DIR/sample-code/sample.rb" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}require" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}module" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}Telemetry" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}Loggable" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}class" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}BaseCollector" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}include" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}extend" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}attr_reader" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}def" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}end" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}do" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}initialize" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}instance_count" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}classify_event" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}case" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}in" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}when" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}unless" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}rescue" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}ensure" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}:metric" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}:heartbeat" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}:ok" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}DEFAULT_CAPACITY" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}self" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}super" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}type" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}@endpoint" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}@@collector_instances" <<< "$RUBY_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}metric_name" <<< "$RUBY_SAMPLE_OUT"; then
        pass "bat renders Ruby showcase (sample.rb) with Converged Ergonomic Solarized: require & module declaration names in Violet, structural keywords (module, class, def, end, do, include, extend, attr_reader) in Green, method declarations in Blue, control flow & pattern matching (case/in/when/unless/rescue/ensure) in Yellow, :symbols/constants/self/super in Magenta, and classes, @instance_vars, @@class_vars, hash symbol keys (type:) & #{...} interpolations in calm Base0 matching Neovim"
    else
        fail "bat Ruby (.rb) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.rb output"
    fi

    # --- 2.29 GraphQL (.graphql) Syntax Verification ---
    GRAPHQL_SAMPLE_OUT="$(bat_render -l graphql "$SCRIPT_DIR/sample-code/sample.graphql" 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}schema" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}scalar" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}directive" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}enum" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}interface" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}type" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}implements" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}union" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}input" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}query" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}mutation" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}subscription" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}fragment" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}Int" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}String" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}Boolean" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}ID" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}primaryHost" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}hostname" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}GetTelemetrySnapshot" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}IngestTelemetryBatch" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}NodeSummaryFields" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@specifiedBy" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@rateLimit" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@deprecated" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}FIELD_DEFINITION" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}HEALTH_STATE_ACTIVE" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}-0.25" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}null" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}DateTime" <<< "$GRAPHQL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}\$region" <<< "$GRAPHQL_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_YELLOW}" <<< "$GRAPHQL_SAMPLE_OUT"; then
        pass "bat renders GraphQL showcase (sample.graphql) with Converged Ergonomic Solarized: schema/operation keywords, built-in scalars & field keys in Green, operation/fragment declarations in Blue, @directives in Violet, enum values/locations/numbers/booleans/null in Magenta, custom types & \$variables in calm Base0, and zero Yellow matching Neovim"
    else
        fail "bat GraphQL (.graphql) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.graphql output"
    fi

    # --- 2.30 Open-Source Bazel / Starlark (.bzl & BUILD.bazel) Syntax Verification ---
    BZL_SAMPLE_OUT="$(bat_render -l bzl "$SCRIPT_DIR/sample-code/sample.bzl" 2>/dev/null || true)"
    BUILD_SAMPLE_OUT="$(bat_render "$SCRIPT_DIR/sample-code/BUILD.bazel" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}load" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}Open-source Bazel Starlark rules and macros for telemetry schema codegen." <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}Rule implementation generating C++ headers from telemetry schemas." <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}Macro defining a telemetry C++ library and optional unit test target." <<< "$BZL_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_CYAN}Rule implementation generating C++ headers" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}DEFAULT_COPTS" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}MAX_SCHEMA_FILES" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}64" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}True" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}def" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}not" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}in" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}_telemetry_schema_library_impl" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}telemetry_cc_library" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}for" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}return" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}provider" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}depset" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}rule" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}select" <<< "$BZL_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}load" <<< "$BUILD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE01}Open-source Bazel BUILD target definitions" <<< "$BUILD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}package" <<< "$BUILD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}glob" <<< "$BUILD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}proto_library" <<< "$BUILD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}cc_binary" <<< "$BUILD_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}cc_test" <<< "$BUILD_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}DEFAULT_COPTS" <<< "$BUILD_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}for" <<< "$BUILD_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}in" <<< "$BUILD_SAMPLE_OUT"; then
        pass "bat renders Starlark/Bazel showcases (sample.bzl & BUILD.bazel) with Converged Ergonomic Solarized: load() in Violet, module/function/macro docstrings in Base01, def & logical word operators in Green, function/macro declarations in Blue, control flow in Yellow, constants/numbers/booleans in Magenta, and package/glob/rule/depset/select target calls in calm Base0 matching Neovim"
    else
        fail "bat Starlark (.bzl & BUILD.bazel) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.bzl and BUILD.bazel output"
    fi

    # --- 2.31 Open Policy Agent Rego (.rego) Syntax Verification ---
    REGO_SAMPLE_OUT="$(bat_render -l rego "$SCRIPT_DIR/sample-code/sample.rego" 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}package" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}telemetry" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}authz" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}import" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}cluster_topology" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}MAX_BURST_RATE" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}5000" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}false" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}null" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}-10" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}default" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}contains" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}some" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}in" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}not" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}with" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}as" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}allow" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}violations" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}is_rate_limited" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}else" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}every" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}msg" <<< "$REGO_SAMPLE_OUT" && \
       ! grep -Fq "${SOL_BLUE}msg" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}sprintf" <<< "$REGO_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}count" <<< "$REGO_SAMPLE_OUT"; then
        pass "bat renders OPA Rego showcase (sample.rego) with Converged Ergonomic Solarized: import & package/import module paths in Violet, package/default/some/contains/with/as/in/not in Green, rule/function declarations in Blue, if/else/every in Yellow, constants/numbers/booleans/null in Magenta, and set element variables (msg) & builtin calls in calm Base0 matching Neovim"
    else
        fail "bat OPA Rego (.rego) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.rego output"
    fi

    # 2.32 Lua (.lua) Converged Ergonomic Solarized Verification
    LUA_SAMPLE_OUT="$(bat_render "$SCRIPT_DIR/sample-code/sample.lua" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}#!/usr/bin/env lua" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}local" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}function" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}not" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}and" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}or" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}then" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}for" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}in" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}do" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}repeat" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}until" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}return" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}goto" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}<const>" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}<close>" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}DEFAULT_TIMEOUT_MS" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}__index" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}__tostring" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}self" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}true" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}false" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}nil" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}make_scope_guard" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}new" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}push" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}flush_batch" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}setmetatable" <<< "$LUA_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}ipairs" <<< "$LUA_SAMPLE_OUT"; then
        pass "bat renders Lua showcase (sample.lua) with Converged Ergonomic Solarized: shebang in Orange, <const>/<close> in Violet, local/function/and/or/not in Green, if/then/for/in/do/repeat/until/return/goto in Yellow, function/method declarations in Blue, metamethods/self/SCREAMING_SNAKE/literals in Magenta, and stdlib calls in calm Base0 matching Neovim"
    else
        fail "bat Lua (.lua) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.lua output"
    fi

    # 2.33 Dockerfile (sample.Dockerfile) Converged Ergonomic Solarized Verification
    DOCKER_SAMPLE_OUT="$(bat_render "$SCRIPT_DIR/sample-code/sample.Dockerfile" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}# syntax=docker/dockerfile:1" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}FROM" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}AS" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}ARG" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}ENV" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}WORKDIR" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}COPY" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}RUN" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}USER" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}EXPOSE" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}HEALTHCHECK" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}ENTRYPOINT" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}CMD" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}--mount=type=cache,target=/go/pkg/mod" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}--from=builder" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}--chown=10001:10001" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}builder" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}runtime" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}8080" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}10001" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$DOCKER_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}fi" <<< "$DOCKER_SAMPLE_OUT"; then
        pass "bat renders Dockerfile showcase (sample.Dockerfile) with Converged Ergonomic Solarized: BuildKit syntax directive in Orange, FROM/AS/RUN/COPY/ENV/ARG/ENTRYPOINT/CMD in Green, stage aliases in Blue, --mount/--from/--chown flags in calm Base0, numeric ports/UIDs/constants in Magenta, and embedded RUN shell control flow in Yellow matching Neovim"
    else
        fail "bat Dockerfile rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.Dockerfile output"
    fi

    # 2.34 Makefile (sample.mk) Converged Ergonomic Solarized Verification
    MAKE_SAMPLE_OUT="$(bat_render "$SCRIPT_DIR/sample-code/sample.mk" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}-include" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}.PHONY" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}export" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}ifeq" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}else" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}endif" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_ORANGE}@" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}all" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}build" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}test" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}clean" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}.DEFAULT_GOAL" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}\$@" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}\$<" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}shell" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}wildcard" <<< "$MAKE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}patsubst" <<< "$MAKE_SAMPLE_OUT"; then
        pass "bat renders Makefile showcase (sample.mk) with Converged Ergonomic Solarized: -include in Violet, .PHONY/export in Green, ifeq/else/endif in Yellow, recipe @/-/+ prefixes in Orange, targets in Blue, .DEFAULT_GOAL and automatic variables (\$@/\$<) in Magenta, and built-in functions in calm Base0 matching Neovim"
    else
        fail "bat Makefile (.mk) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.mk output"
    fi

    # 2.35 Elixir (.ex) Converged Ergonomic Solarized Verification
    ELIXIR_SAMPLE_OUT="$(bat_render "$SCRIPT_DIR/sample-code/sample.ex" 2>/dev/null || true)"
    if grep -Fq "${SOL_GREEN}defmodule" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}Core.Telemetry.Collector" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}use" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}GenServer" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}require" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}import" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}alias" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@moduledoc" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@spec" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@type" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}@impl" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}defstruct" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}defguard" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}def" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}defp" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}fn" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}do" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}end" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}start_link" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}classify_score" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}ingest_batch" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}with" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}when" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}case" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}else" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}try" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}rescue" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}for" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}:ok" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}:critical" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}source:" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}__MODULE__" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}nil" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}|>" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Enum" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}MetricSample" <<< "$ELIXIR_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}#{" <<< "$ELIXIR_SAMPLE_OUT"; then
        pass "bat renders Elixir showcase (sample.ex) with Converged Ergonomic Solarized: defmodule/use/import/alias/require targets & @attributes in Violet, def/defp/defstruct/defguard/fn/do/end in Green, function declarations in Blue, with/case/if/else/when/try/rescue/for in Yellow, :atoms/keyword:/nil/true/false/__MODULE__ in Magenta, and |> pipe, in-code module qualifiers (Enum, MetricSample) & #{...} interpolation in calm Base0 matching Neovim"
    else
        fail "bat Elixir (.ex) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.ex output"
    fi

    # 2.36 Haskell (.hs) Converged Ergonomic Solarized Verification
    HASKELL_SAMPLE_OUT="$(bat_render "$SCRIPT_DIR/sample-code/sample.hs" 2>/dev/null || true)"
    if grep -Fq "${SOL_ORANGE}{-# LANGUAGE OverloadedStrings, DeriveGeneric #-}" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}module" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}Core.Telemetry" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}import" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}qualified" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}Data.Map.Strict" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}data" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}newtype" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}type" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}class" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}instance" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}deriving" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}where" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}let" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}in" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}forall" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}Int" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}Double" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}Bool" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}String" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}clampScore" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}classifySample" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}summarizeBatch" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}case" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}of" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}then" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}else" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}do" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}Nothing" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}otherwise" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}MetricSample" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Maybe" <<< "$HASKELL_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Just" <<< "$HASKELL_SAMPLE_OUT"; then
        pass "bat renders Haskell showcase (sample.hs) with Converged Ergonomic Solarized: {-# LANGUAGE #-} pragma in Orange, module/import/qualified & module paths in Violet, data/newtype/type/class/instance/deriving/where/let/in/forall & scalar primitives (Int, Double, Bool, String) in Green, function signatures & definitions in Blue, case/of/if/then/else/do in Yellow, Nothing/otherwise/numbers in Magenta, and custom types/constructors (MetricSample, Maybe, Just) & qualified prefixes in calm Base0 matching Neovim"
    else
        fail "bat Haskell (.hs) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.hs output"
    fi

    # 2.37 OCaml (.ml) Converged Ergonomic Solarized Verification
    OCAML_SAMPLE_OUT="$(bat_render "$SCRIPT_DIR/sample-code/sample.ml" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}open" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}Printf" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}TELEMETRY" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}Collector" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}module" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}sig" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}struct" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}end" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}type" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}let" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}rec" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}val" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}mutable" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}fun" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}'a" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}float" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}int" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}bool" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}string" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}clamp_score" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}classify" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}process_batch" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}match" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}with" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}when" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}then" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}else" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}\`Active" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}\`Draining" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}None" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}option" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}list" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Some" <<< "$OCAML_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}List" <<< "$OCAML_SAMPLE_OUT"; then
        pass "bat renders OCaml showcase (sample.ml) with Converged Ergonomic Solarized: open & formal module/signature names in Violet, module/sig/struct/end/type/let/rec/val/mutable/fun, type variables ('a) & scalar primitives (int, float, bool, string) in Green, function declarations in Blue, match/with/when/if/then/else in Yellow, polymorphic variants (\`Active)/None/numbers in Magenta, and container types (option, list), constructors (Some, Ok) & qualified calls (List.fold_left) in calm Base0 matching Neovim"
    else
        fail "bat OCaml (.ml) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.ml output"
    fi

    # 2.38 Clojure (.clj) Converged Ergonomic Solarized Verification
    CLOJURE_SAMPLE_OUT="$(bat_render "$SCRIPT_DIR/sample-code/sample.clj" 2>/dev/null || true)"
    if grep -Fq "${SOL_VIOLET}ns" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}core.telemetry.collector" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}:require" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}:import" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}^:private" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_VIOLET}^String" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}defonce" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}defprotocol" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}defrecord" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}defmacro" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}defn-" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}defn" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}let" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_GREEN}loop" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}with-telemetry-span" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}normalize-node-id" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}classify-sample" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BLUE}summarize-batch" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}try" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}finally" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}when-let" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}cond" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}if" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}case" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_YELLOW}recur" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}:telemetry/critical" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}nil" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_MAGENTA}#\"^node-[a-z0-9-]+$\"" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}Measurable" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}MetricSample" <<< "$CLOJURE_SAMPLE_OUT" && \
       grep -Fq "${SOL_BASE0}->" <<< "$CLOJURE_SAMPLE_OUT"; then
        pass "bat renders Clojure showcase (sample.clj) with Converged Ergonomic Solarized: ns/namespace/:require/:import & ^metadata in Violet, defn/defn-/def/defonce/defmacro/defprotocol/defrecord/let/loop in Green, declared function/macro/protocol-method names in Blue, if/when-let/cond/case/recur/try/finally in Yellow, :keywords/nil/numbers/#\"...\" regexes in Magenta, and custom types (Measurable, MetricSample), threading macros (->) & calls in calm Base0 matching Neovim"
    else
        fail "bat Clojure (.clj) rendering" "Expected Converged Ergonomic Solarized TrueColor highlights in bat sample.clj output"
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

if [ -L "$TEMP_HOME/.config/ghostty" ] || [ -L "$TEMP_HOME/.config/nvim" ] || [ -L "$TEMP_HOME/.config/btop" ] || [ -L "$TEMP_HOME/.config/git" ] || [ -L "$TEMP_HOME/.config/tealdeer" ] || [ -L "$TEMP_HOME/.config/clangd" ] || [ -L "$TEMP_HOME/.config/fontconfig" ]; then
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
