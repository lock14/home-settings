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
        "$HOME/.dir-colors/dircolors"
        "$xdg_config/bat/themes/Solarized-Dark-TrueColor.tmTheme"
        "$xdg_config/mise/config.toml"
    )

    if [ -d "$REPO_DIR/dotfiles/.dir-colors" ]; then
        for f in "$REPO_DIR/dotfiles/.dir-colors"/*; do
            [ -e "$f" ] || continue
            dotfiles+=("$HOME/.dir-colors/$(basename "$f")")
        done
    fi

    if [ -d "$REPO_DIR/syntaxes" ]; then
        for syn in "$REPO_DIR/syntaxes"/*.sublime-syntax; do
            [ -e "$syn" ] || continue
            dotfiles+=("$xdg_config/bat/syntaxes/$(basename "$syn")")
        done
    fi

    # Dynamically find any additional top-level dotfiles from repository
    if [ -d "$REPO_DIR/dotfiles" ]; then
        for src in "$REPO_DIR/dotfiles"/.* "$REPO_DIR/dotfiles"/*; do
            [ -e "$src" ] || continue
            local name
            name="$(basename "$src")"
            case "$name" in
                .|..|.git|.gitignore|.config|.dir-colors|'*') continue ;;
            esac
            if [ -f "$src" ]; then
                dotfiles+=("$HOME/$name")
            fi
        done
    fi

    for f in "${dotfiles[@]}"; do
        unlink_path "$f"
    done
    unlink_path "$HOME/.zsh-aliases"

    # Unlink any managed .config entries dynamically
    local nvim_target="$xdg_config/nvim"
    unlink_path "$nvim_target"
    if [ -d "$REPO_DIR/dotfiles/.config" ]; then
        for item in "$REPO_DIR/dotfiles/.config"/*; do
            [ -e "$item" ] || continue
            unlink_path "$xdg_config/$(basename "$item")"
        done
    fi

    if [ "$OS" = "macos" ]; then
        unlink_path "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
        unlink_path "$HOME/Library/Application Support/com.mitchellh.ghostty/themes"
    fi

    # Clean up empty bat directories if they exist
    rmdir "$xdg_config/bat/syntaxes" 2>/dev/null || true
    rmdir "$xdg_config/bat/themes" 2>/dev/null || true
    rmdir "$xdg_config/bat" 2>/dev/null || true

    # Rebuild bat cache to purge uninstalled syntaxes and themes
    if [ "$DRY_RUN" = false ]; then
        if command -v mise >/dev/null 2>&1 && mise which bat >/dev/null 2>&1; then
            mise exec -- bat cache --build >/dev/null 2>&1 || true
        elif command -v bat >/dev/null 2>&1; then
            bat cache --build >/dev/null 2>&1 || true
        elif command -v batcat >/dev/null 2>&1; then
            batcat cache --build >/dev/null 2>&1 || true
        fi
    fi

    # Clean up legacy fzf-zsh-plugin directory and .vim bundles if present
    if [ "$DRY_RUN" = false ]; then
        rm -rf "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fzf-zsh-plugin" 2>/dev/null || true
        rm -rf "$HOME/.vim/bundle" "$HOME/.vim/autoload" 2>/dev/null || true
    fi

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
    echo "  Removing MesloLGS NF / MesloLGS Nerd Font fonts from $font_dir..."
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] rm -f $font_dir/MesloLGS-NF-*.ttf $font_dir/MesloLGS NF*.ttf $font_dir/MesloLGSNerdFont*.ttf $font_dir/[0-9]MesloLGS*.ttf"
    else
        rm -f "$font_dir"/MesloLGS-NF-*.ttf "$font_dir/MesloLGS NF"*.ttf "$font_dir/MesloLGSNerdFont"*.ttf "$font_dir"/[0-9]MesloLGS*.ttf || true
        local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
        local fc_alias_src="$REPO_DIR/dotfiles/.config/fontconfig/conf.d/10-meslo-nerd-font.conf"
        local fc_alias_dest="$xdg_config/fontconfig/conf.d/10-meslo-nerd-font.conf"
        if [ -L "$xdg_config/fontconfig" ]; then
            rm -f "$xdg_config/fontconfig"
        elif [ -L "$xdg_config/fontconfig/conf.d" ]; then
            rm -f "$xdg_config/fontconfig/conf.d"
        elif [ -L "$fc_alias_dest" ] || { [ -e "$fc_alias_dest" ] && ! [ "$fc_alias_dest" -ef "$fc_alias_src" ]; }; then
            rm -f "$fc_alias_dest"
        fi
        if command -v fc-cache >/dev/null 2>&1; then
            fc-cache -f "$font_dir" >/dev/null 2>&1 || true
        fi
    fi
    echo "  MesloLGS Nerd Font Mono fonts uninstalled."
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
