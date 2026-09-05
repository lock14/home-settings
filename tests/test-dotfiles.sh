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
