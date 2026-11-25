#!/bin/bash
# Stage 99: Clean uninstallation of managed dotfiles, binaries, and fonts.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$MODULE_DIR/.." && pwd)"
REPO_DIR="$(cd "$SETUP_DIR/.." && pwd)"

# shellcheck source=/dev/null
. "$SETUP_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$SETUP_DIR/lib/os.sh"
# shellcheck source=/dev/null
. "$SETUP_DIR/lib/symlink.sh"
# shellcheck source=/dev/null
. "$SETUP_DIR/lib/shell-env.sh"

OS="${OS:-$(detect_os)}"
DRY_RUN="${DRY_RUN:-false}"
UNINSTALL_TARGET="${1:-all}"

unlink_glob_targets() {
    local src_dir="$1"
    local glob_pat="$2"
    local dest_dir="$3"
    [ -d "$src_dir" ] || return 0
    local item
    # shellcheck disable=SC2231
    for item in "$src_dir"/$glob_pat; do
        [ -e "$item" ] || continue
        unlink_path "$dest_dir/$(basename "$item")"
    done
}

uninstall_dotfiles() {
    echo "  Removing managed dotfile symlinks..."
    local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"

    unlink_path "$xdg_config/mise/config.toml"
    unlink_glob_targets "$REPO_DIR/colors" '*.tmTheme' "$xdg_config/bat/themes"
    unlink_glob_targets "$REPO_DIR/dotfiles/.dir-colors" '*' "$HOME/.dir-colors"
    unlink_glob_targets "$REPO_DIR/syntaxes" '*.sublime-syntax' "$xdg_config/bat/syntaxes"

    local src
    while IFS= read -r src; do
        [ -n "$src" ] || continue
        unlink_path "$HOME/$(basename "$src")"
    done < <(list_managed_top_dotfiles "$REPO_DIR/dotfiles")
    unlink_path "$HOME/.zsh-aliases"

    # Unlink all managed .config entries dynamically (including shell, nvim, ghostty, btop, etc.)
    if [ -d "$REPO_DIR/dotfiles/.config" ]; then
        local item cfg_name
        for item in "$REPO_DIR/dotfiles/.config"/*; do
            [ -e "$item" ] || continue
            cfg_name="$(basename "$item")"
            if [ "$cfg_name" = "git" ] && [ -d "$item" ]; then
                if [ -L "$xdg_config/git" ]; then
                    unlink_path "$xdg_config/git"
                else
                    unlink_glob_targets "$item" '*' "$xdg_config/git"
                    [ "$DRY_RUN" = true ] || rmdir "$xdg_config/git" 2>/dev/null || true
                fi
                continue
            fi
            unlink_path "$xdg_config/$cfg_name"
        done
    fi

    if [ "$OS" = "macos" ]; then
        unlink_path "$HOME/Library/Application Support/com.mitchellh.ghostty/config" "$xdg_config/ghostty"
        unlink_path "$HOME/Library/Application Support/com.mitchellh.ghostty/keybinds.conf" "$xdg_config/ghostty"
        unlink_path "$HOME/Library/Application Support/com.mitchellh.ghostty/themes" "$xdg_config/ghostty"
    fi

    # Remove # home-settings source blocks added to ~/.zshrc and ~/.bashrc by setup/modules/60-shell.sh
    remove_shell_rc_hook "$HOME/.zshrc" ".zshrc-addendum"
    remove_shell_rc_hook "$HOME/.bashrc" ".bashrc-addendum"

    # Remove managed AI CLI lifecycle hooks (agy, claude, codex) while preserving user settings
    if [ -f "$MODULE_DIR/75-ai-hooks.sh" ]; then
        bash "$MODULE_DIR/75-ai-hooks.sh" --uninstall
    fi

    # Clean up empty bat directories, generated theme state, and legacy plugin directories
    if [ "$DRY_RUN" = false ]; then
        rmdir "$xdg_config/bat/syntaxes" "$xdg_config/bat/themes" "$xdg_config/bat" 2>/dev/null || true
        rm -f \
            "$xdg_config/home-settings/theme" \
            "$xdg_config/home-settings/active-theme.theme" \
            "$xdg_config/home-settings/theme-env.sh" \
            "$xdg_config/home-settings/zsh-theme.zsh" \
            "$xdg_config/home-settings/p10k-theme.zsh" \
            "$xdg_config/home-settings/tmux-theme.conf" \
            "$xdg_config/home-settings/delta-theme.gitconfig" 2>/dev/null || true
        rm -rf "$xdg_config/home-settings/active" 2>/dev/null || true
        rmdir "$xdg_config/home-settings/themes" "$xdg_config/home-settings" 2>/dev/null || true
        local xdg_cache="${XDG_CACHE_HOME:-$HOME/.cache}"
        rm -rf "$xdg_cache/home-settings/pycache" "$xdg_cache/home-settings/fzf-cap.cache" 2>/dev/null || true
        rmdir "$xdg_cache/home-settings" 2>/dev/null || true

        rebuild_bat_cache
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
            local f
            for f in "$bin_dir"/*; do
                [ -f "$f" ] || continue
                unlink_path "$local_bin/$(basename "$f")"
            done
        fi
        local shim shim_target
        for shim in "$local_bin/fd" "$local_bin/bat"; do
            if [ -L "$shim" ]; then
                shim_target="$(readlink "$shim" 2>/dev/null || true)"
                if [[ "$shim_target" == *"fdfind"* ]] || [[ "$shim_target" == *"batcat"* ]]; then
                    unlink_path "$shim" "$shim_target"
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
            unlink_path "$xdg_config/fontconfig"
        elif [ -L "$xdg_config/fontconfig/conf.d" ]; then
            unlink_path "$xdg_config/fontconfig/conf.d"
        elif [ -L "$fc_alias_dest" ]; then
            unlink_path "$fc_alias_dest"
        elif [ -e "$fc_alias_dest" ] && ! [ "$fc_alias_dest" -ef "$fc_alias_src" ]; then
            rm -f "$fc_alias_dest"
        fi
        if command -v fc-cache >/dev/null 2>&1; then
            fc-cache -f "$font_dir" >/dev/null 2>&1 || true
        fi
    fi
    echo "  MesloLGS Nerd Font Mono fonts uninstalled."
}

case "$UNINSTALL_TARGET" in
    all|"")
        echo -e "\nUninstalling all home-settings components..."
        uninstall_dotfiles
        uninstall_bin
        uninstall_fonts
        echo -e "\n====================================================="
        echo " Uninstallation complete! "
        echo "====================================================="
        ;;
    *)
        do_dotfiles=false
        do_bin=false
        do_fonts=false
        IFS=',' read -r -a _u_items <<< "$UNINSTALL_TARGET"
        for _u_tok in "${_u_items[@]}"; do
            case "$_u_tok" in
                dotfiles) do_dotfiles=true ;;
                bin)      do_bin=true ;;
                fonts)    do_fonts=true ;;
                all)      do_dotfiles=true; do_bin=true; do_fonts=true ;;
                *)
                    echo "Error: Unknown uninstall target '$_u_tok' (expected: all, dotfiles, fonts, or bin)" >&2
                    exit 1
                    ;;
            esac
        done
        if [ "$do_dotfiles" = true ]; then uninstall_dotfiles; fi
        if [ "$do_bin" = true ]; then uninstall_bin; fi
        if [ "$do_fonts" = true ]; then uninstall_fonts; fi
        ;;
esac
