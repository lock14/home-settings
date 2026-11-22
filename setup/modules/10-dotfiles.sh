#!/bin/bash
# Stage 10: Declarative dotfile auto-discovery and mirroring to $HOME.

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

OS="${OS:-$(detect_os)}"
DRY_RUN="${DRY_RUN:-false}"
DOTFILES_DIR="$REPO_DIR/dotfiles"
XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

bat_cache_needs_rebuild() {
    local cache_dir="$1"
    if [ ! -f "$cache_dir/themes.bin" ] || [ ! -f "$cache_dir/syntaxes.bin" ]; then
        return 0
    fi
    local asset
    for asset in "$REPO_DIR/colors"/*.tmTheme; do
        [ -e "$asset" ] || continue
        [ "$asset" -nt "$cache_dir/themes.bin" ] && return 0
    done
    for asset in "$REPO_DIR/syntaxes"/*.sublime-syntax; do
        [ -e "$asset" ] || continue
        [ "$asset" -nt "$cache_dir/syntaxes.bin" ] && return 0
    done
    return 1
}

echo "  Symlinking dotfiles from $DOTFILES_DIR to $HOME..."

# 1. Discover and link all top-level files in dotfiles/
while IFS= read -r src; do
    [ -n "$src" ] || continue
    name="$(basename "$src")"
    case "$name" in
        .vimrc)
            [ "${SKIP_VIM:-false}" = true ] && continue
            ;;
        .zshrc-addendum|.zsh-functions|.p10k.zsh)
            [ "${SKIP_ZSH:-false}" = true ] && continue
            ;;
        .zsh-completions)
            [ "${SKIP_COMPLETIONS:-false}" = true ] && continue
            ;;
        .bashrc-addendum)
            [ "${SKIP_BASH:-false}" = true ] && continue
            ;;
    esac
    link_file "$src" "$HOME/$name"
done < <(list_managed_top_dotfiles "$DOTFILES_DIR")

# 2. Discover and link directory-based dotfiles (.dir-colors)
link_glob_files "$DOTFILES_DIR/.dir-colors" '*' "$HOME/.dir-colors"

# 3. Discover and link .config subtrees (including nvim, shell, ghostty, btop, etc.)
if [ -d "$DOTFILES_DIR/.config" ]; then
    [ "$DRY_RUN" = true ] || mkdir -p "$XDG_CONFIG"
    for item in "$DOTFILES_DIR/.config"/*; do
        [ -e "$item" ] || continue
        target_name="$(basename "$item")"
        if [ "$target_name" = "nvim" ] && [ "${SKIP_NVIM:-false}" = true ]; then
            continue
        fi
        if [ "$target_name" = "git" ] && [ -d "$item" ]; then
            # Keep ~/.config/git as a physical directory so user-local ignore/attributes survive
            if [ -L "$XDG_CONFIG/git" ]; then
                if _is_managed_symlink "$XDG_CONFIG/git"; then
                    unlink_path "$XDG_CONFIG/git"
                elif [ "$DRY_RUN" = false ]; then
                    backup_existing_path "$XDG_CONFIG/git" >/dev/null
                fi
            fi
            link_glob_files "$item" '*' "$XDG_CONFIG/git"
            continue
        fi
        if [ -d "$item" ]; then
            link_dir "$item" "$XDG_CONFIG/$target_name"
        elif [ -f "$item" ]; then
            link_file "$item" "$XDG_CONFIG/$target_name"
        fi
    done
    prune_dangling_managed_symlinks "$XDG_CONFIG" "$DOTFILES_DIR/.config"
fi

# 4. Ghostty macOS Application Support compatibility symlink
if [ "$OS" = "macos" ] && [ -d "$DOTFILES_DIR/.config/ghostty" ]; then
    GHOSTTY_MAC_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
    [ "$DRY_RUN" = true ] || mkdir -p "$GHOSTTY_MAC_DIR"
    link_file "$XDG_CONFIG/ghostty/config" "$GHOSTTY_MAC_DIR/config"
    if [ -d "$XDG_CONFIG/ghostty/themes" ] || [ -d "$DOTFILES_DIR/.config/ghostty/themes" ]; then
        link_dir "$XDG_CONFIG/ghostty/themes" "$GHOSTTY_MAC_DIR/themes"
    fi
fi

# 5. Bat TrueColor Syntax Highlighting Themes & Granular Syntaxes
if [ -d "$REPO_DIR/colors" ]; then
    echo "  Configuring Bat TrueColor themes..."
    link_glob_files "$REPO_DIR/colors" '*.tmTheme' "$XDG_CONFIG/bat/themes"
fi
link_glob_files "$REPO_DIR/syntaxes" '*.sublime-syntax' "$XDG_CONFIG/bat/syntaxes"

if [ "$DRY_RUN" = false ] && { [ -f "$REPO_DIR/colors/Solarized-Dark-TrueColor.tmTheme" ] || [ -d "$REPO_DIR/syntaxes" ]; }; then
    if bat_cache_needs_rebuild "${XDG_CACHE_HOME:-$HOME/.cache}/bat"; then
        rebuild_bat_cache
    fi
fi

# 6. Polyglot Toolchains Configuration (Mise)
if [ -f "$REPO_DIR/.mise.toml" ]; then
    link_file "$REPO_DIR/.mise.toml" "$XDG_CONFIG/mise/config.toml"
fi

# 7. Apply explicit or previously persisted color theme without touching live server sockets
EXPLICIT_THEME="${HOME_SETTINGS_THEME:-${THEME_NAME:-}}"
if [ -n "$EXPLICIT_THEME" ] && [ -x "$REPO_DIR/bin/theme" ]; then
    if [ "$DRY_RUN" = true ]; then
        "$REPO_DIR/bin/theme" --dry-run --no-live --set="$EXPLICIT_THEME"
    else
        "$REPO_DIR/bin/theme" --no-live --set="$EXPLICIT_THEME" >/dev/null
    fi
elif [ "$DRY_RUN" = false ] && [ -x "$REPO_DIR/bin/theme" ]; then
    SAVED_THEME="$(resolve_persisted_theme "$XDG_CONFIG")"
    if [ -n "$SAVED_THEME" ]; then
        "$REPO_DIR/bin/theme" --no-live --set="$SAVED_THEME" >/dev/null || true
    fi
fi

# Live servers are intentionally never reloaded here: this module runs under temporary $HOME
# directories in test suites, and hot-reloading running servers would mutate live sessions.
