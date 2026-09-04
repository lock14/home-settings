#!/bin/bash
# Stage 99: Clean uninstallation of managed dotfiles, binaries, and fonts.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# Source helper libraries
# shellcheck source=/dev/null
. "$REPO_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/os.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/symlink.sh"

OS="${OS:-$(detect_os)}"
DRY_RUN="${DRY_RUN:-false}"
UNINSTALL_TARGET="${1:-all}"

uninstall_dotfiles() {
    echo "  Removing managed dotfile symlinks..."
    local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
    local dotfiles=(
        "$HOME/.environment-variables"
        "$HOME/.bashrc-addendum"
        "$HOME/.zshrc-addendum"
        "$HOME/.aliases"
        "$HOME/.zsh-aliases"
        "$HOME/.zsh-functions"
        "$HOME/.zsh-completions"
        "$HOME/.p10k.zsh"
        "$HOME/.vimrc"
        "$HOME/.dir-colors/dircolors"
        "$xdg_config/bat/themes/Solarized-Dark-TrueColor.tmTheme"
        "$xdg_config/mise/config.toml"
    )

    # Dynamically find any additional top-level dotfiles from repository
    if [ -d "$REPO_DIR/dotfiles" ]; then
        for src in "$REPO_DIR/dotfiles"/.*; do
            [ -e "$src" ] || continue
            local name
            name="$(basename "$src")"
            case "$name" in
                .|..|.git|.gitignore|.config|.dir-colors) continue ;;
            esac
            if [ -f "$src" ]; then
                dotfiles+=("$HOME/$name")
            fi
        done
    fi

    for f in "${dotfiles[@]}"; do
        unlink_path "$f"
    done

    local nvim_target="$xdg_config/nvim"
    unlink_path "$nvim_target"

    echo "  Dotfile symlinks uninstalled."
}

uninstall_bin() {
    echo "  Removing bin utilities from $HOME/.local/bin..."
    local local_bin="$HOME/.local/bin"
    if [ -d "$local_bin" ]; then
        local bin_dir="$REPO_DIR/bin"
        if [ -d "$bin_dir" ]; then
            for f in "$bin_dir"/*; do
                [ -e "$f" ] || continue
                unlink_path "$local_bin/$(basename "$f")"
            done
        fi
        for shim in "$local_bin/fd" "$local_bin/bat"; do
            if [ -L "$shim" ]; then
                local shim_target
                shim_target="$(readlink "$shim" 2>/dev/null || true)"
                if [[ "$shim_target" == *"fdfind"* ]] || [[ "$shim_target" == *"batcat"* ]]; then
                    unlink_path "$shim"
                fi
            fi
        done
    fi
    echo "  User binaries uninstalled."
}

uninstall_fonts() {
    local font_dir
    if [ "$OS" = "macos" ]; then
        font_dir="$HOME/Library/Fonts"
    else
        font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
    fi
    echo "  Removing MesloLGS NF fonts from $font_dir..."
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] rm -f $font_dir/MesloLGS NF*.ttf"
    else
        rm -f "$font_dir/MesloLGS NF"*.ttf || true
        if command -v fc-cache >/dev/null 2>&1; then
            fc-cache -f "$font_dir" >/dev/null 2>&1 || true
        fi
    fi
    echo "  MesloLGS NF fonts uninstalled."
}

case "$UNINSTALL_TARGET" in
    dotfiles)
        uninstall_dotfiles
        ;;
    bin)
        uninstall_bin
        ;;
    fonts)
        uninstall_fonts
        ;;
    all|*)
        echo -e "\nUninstalling all home-settings components..."
        uninstall_dotfiles
        uninstall_bin
        uninstall_fonts
        echo -e "\n====================================================="
        echo " Uninstallation complete! "
        echo "====================================================="
        ;;
esac
