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
        "$xdg_config/mise/config.toml"
    )

    if [ -d "$REPO_DIR/colors" ]; then
        for tmtheme in "$REPO_DIR/colors"/*.tmTheme; do
            [ -e "$tmtheme" ] || continue
            dotfiles+=("$xdg_config/bat/themes/$(basename "$tmtheme")")
        done
    fi

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
    if [ -d "$REPO_DIR/dotfiles/.config" ]; then
        for item in "$REPO_DIR/dotfiles/.config"/*; do
            [ -e "$item" ] || continue
            local cfg_name
            cfg_name="$(basename "$item")"
            if [ "$cfg_name" = "git" ] && [ -d "$item" ]; then
                if [ -L "$xdg_config/git" ]; then
                    unlink_path "$xdg_config/git"
                else
                    for git_f in "$item"/*; do
                        [ -e "$git_f" ] || continue
                        unlink_path "$xdg_config/git/$(basename "$git_f")"
                    done
                    if [ "$DRY_RUN" = false ]; then
                        rmdir "$xdg_config/git" 2>/dev/null || true
                    fi
                fi
                continue
            fi
            unlink_path "$xdg_config/$cfg_name"
        done
    fi

    if [ "$OS" = "macos" ]; then
        unlink_path "$HOME/Library/Application Support/com.mitchellh.ghostty/config" "$xdg_config/ghostty"
        unlink_path "$HOME/Library/Application Support/com.mitchellh.ghostty/themes" "$xdg_config/ghostty"
    fi

    # Remove # home-settings source blocks added to ~/.zshrc and ~/.bashrc by modules/60-shell.sh
    local rc_pair rc_file addendum tmp_rc
    for rc_pair in \
        "$HOME/.zshrc|.zshrc-addendum" \
        "$HOME/.bashrc|.bashrc-addendum"; do
        rc_file="${rc_pair%%|*}"
        addendum="${rc_pair#*|}"
        if [ -f "$rc_file" ] && [ ! -L "$rc_file" ] && grep -Fq "$addendum" "$rc_file"; then
            if [ "$DRY_RUN" = true ]; then
                echo "  [DryRun] Remove home-settings source block from $rc_file"
            else
                tmp_rc="$(mktemp "${rc_file}.tmp.XXXXXX")"
                cp -p "$rc_file" "$tmp_rc" 2>/dev/null || true
                awk -v addendum="$addendum" '
                    function is_comment(s) {
                        return (s ~ /^#[[:space:]]*home-settings([[:space:]:].*)?$/)
                    }
                    function is_hook(s) {
                        return (index(s, addendum) > 0 &&
                                s ~ /^\[[[:space:]]+-f[[:space:]]+"?(~|\$HOME)"?\/\.(zsh|bash)rc-addendum"?[[:space:]]+\][[:space:]]+&&[[:space:]]+(source|\.)[[:space:]]+"?(~|\$HOME)"?\/\.(zsh|bash)rc-addendum"?[[:space:]]*$/)
                    }
                    { lines[++n] = $0 }
                    END {
                        for (i = 1; i <= n; i++) {
                            if (is_comment(lines[i]) && i < n && is_hook(lines[i + 1])) {
                                if (out_n > 0 && out[out_n] == "" && (i + 1 == n || out_n == 1 || lines[i + 2] == "")) {
                                    out_n--
                                }
                                i++
                                continue
                            }
                            if (is_hook(lines[i])) {
                                continue
                            }
                            out[++out_n] = lines[i]
                        }
                        for (j = 1; j <= out_n; j++) {
                            print out[j]
                        }
                    }
                ' "$rc_file" > "$tmp_rc"
                mv -f "$tmp_rc" "$rc_file"
            fi
        fi
    done

    # Clean up empty bat directories and generated theme state if they exist
    if [ "$DRY_RUN" = false ]; then
        rmdir "$xdg_config/bat/syntaxes" 2>/dev/null || true
        rmdir "$xdg_config/bat/themes" 2>/dev/null || true
        rmdir "$xdg_config/bat" 2>/dev/null || true
        rm -f \
            "$xdg_config/home-settings/theme" \
            "$xdg_config/home-settings/active-theme.theme" \
            "$xdg_config/home-settings/theme-env.sh" \
            "$xdg_config/home-settings/zsh-theme.zsh" \
            "$xdg_config/home-settings/p10k-theme.zsh" \
            "$xdg_config/home-settings/tmux-theme.conf" \
            "$xdg_config/home-settings/delta-theme.gitconfig" 2>/dev/null || true
        rm -rf "$xdg_config/home-settings/active" 2>/dev/null || true
        rmdir "$xdg_config/home-settings/themes" 2>/dev/null || true
        rmdir "$xdg_config/home-settings" 2>/dev/null || true
    fi

    # Rebuild bat cache to purge uninstalled syntaxes and themes
    if [ "$DRY_RUN" = false ]; then
        rebuild_bat_cache
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
