#!/bin/bash
# Stage 10: Declarative dotfile auto-discovery and mirroring to $HOME.

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
DOTFILES_DIR="$REPO_DIR/dotfiles"
XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

echo "  Symlinking dotfiles from $DOTFILES_DIR to $HOME..."

# 1. Discover and link all top-level files in dotfiles/
for src in "$DOTFILES_DIR"/.* "$DOTFILES_DIR"/*; do
    [ -e "$src" ] || continue
    name="$(basename "$src")"
    case "$name" in
        .|..|.git|.gitignore|.config|.dir-colors|'*')
            continue
            ;;
    esac
    if [ "$name" = ".vimrc" ] && [ "${SKIP_VIM:-false}" = true ]; then
        continue
    fi
    if [ -f "$src" ]; then
        link_file "$src" "$HOME/$name"
    fi
done

# 2. Discover and link directory-based dotfiles (.dir-colors)
if [ -d "$DOTFILES_DIR/.dir-colors" ]; then
    [ "$DRY_RUN" = true ] || mkdir -p "$HOME/.dir-colors"
    for f in "$DOTFILES_DIR/.dir-colors"/*; do
        [ -e "$f" ] || continue
        link_file "$f" "$HOME/.dir-colors/$(basename "$f")"
    done
fi

# 3. Discover and link .config subtrees (e.g. nvim)
if [ -d "$DOTFILES_DIR/.config" ]; then
    [ "$DRY_RUN" = true ] || mkdir -p "$XDG_CONFIG"
    for item in "$DOTFILES_DIR/.config"/*; do
        [ -e "$item" ] || continue
        target_name="$(basename "$item")"
        if [ "$target_name" = "nvim" ] && [ "${SKIP_NVIM:-false}" = true ]; then
            continue
        fi
        if [ -d "$item" ]; then
            link_dir "$item" "$XDG_CONFIG/$target_name"
        elif [ -f "$item" ]; then
            link_file "$item" "$XDG_CONFIG/$target_name"
        fi
    done
    # Prune dangling symlinks in $XDG_CONFIG pointing into dotfiles/.config
    for existing in "$XDG_CONFIG"/*; do
        if [ -L "$existing" ] && [ ! -e "$existing" ]; then
            target_link="$(readlink "$existing" 2>/dev/null || true)"
            if [[ "$target_link" == *"$DOTFILES_DIR/.config"* ]]; then
                unlink_path "$existing"
            fi
        fi
    done
fi

# 4. Ghostty macOS Application Support compatibility symlink
if [ "$OS" = "macos" ] && [ -d "$DOTFILES_DIR/.config/ghostty" ]; then
    GHOSTTY_MAC_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
    [ "$DRY_RUN" = true ] || mkdir -p "$GHOSTTY_MAC_DIR"
    link_file "$XDG_CONFIG/ghostty/config" "$GHOSTTY_MAC_DIR/config"
    if [ -d "$DOTFILES_DIR/.config/ghostty/themes" ]; then
        link_dir "$DOTFILES_DIR/.config/ghostty/themes" "$GHOSTTY_MAC_DIR/themes"
    fi
fi

# 5. Bat TrueColor Syntax Highlighting Theme & Granular Syntaxes
BAT_THEME_SRC="$REPO_DIR/colors/Solarized-Dark-TrueColor.tmTheme"
if [ -f "$BAT_THEME_SRC" ]; then
    echo "  Configuring Bat TrueColor theme..."
    link_file "$BAT_THEME_SRC" "$XDG_CONFIG/bat/themes/Solarized-Dark-TrueColor.tmTheme"
fi

if [ -d "$REPO_DIR/syntaxes" ]; then
    [ "$DRY_RUN" = true ] || mkdir -p "$XDG_CONFIG/bat/syntaxes"
    for syn in "$REPO_DIR/syntaxes"/*.sublime-syntax; do
        [ -e "$syn" ] || continue
        link_file "$syn" "$XDG_CONFIG/bat/syntaxes/$(basename "$syn")"
    done
fi

if [ -f "$BAT_THEME_SRC" ] || [ -d "$REPO_DIR/syntaxes" ]; then
    if [ "$DRY_RUN" = false ]; then
        BAT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bat"
        need_bat_build=false
        if [ ! -f "$BAT_CACHE_DIR/themes.bin" ] || [ ! -f "$BAT_CACHE_DIR/syntaxes.bin" ]; then
            need_bat_build=true
        elif [ -f "$BAT_THEME_SRC" ] && [ "$BAT_THEME_SRC" -nt "$BAT_CACHE_DIR/themes.bin" ]; then
            need_bat_build=true
        else
            for syn in "$REPO_DIR/syntaxes"/*.sublime-syntax; do
                [ -e "$syn" ] || continue
                if [ "$syn" -nt "$BAT_CACHE_DIR/syntaxes.bin" ]; then
                    need_bat_build=true
                    break
                fi
            done
        fi
        if [ "$need_bat_build" = true ]; then
            rebuild_bat_cache
        fi
    fi
fi

# 6. Polyglot Toolchains Configuration (Mise)
if [ -f "$REPO_DIR/.mise.toml" ]; then
    link_file "$REPO_DIR/.mise.toml" "$XDG_CONFIG/mise/config.toml"
fi

# Live servers are intentionally never touched here: this module also runs under a temporary
# $HOME in tests, and hot-reloading running tmux or Neovim servers would mutate live sessions.
# `ide` re-sources ~/.tmux.conf on every launch/attach (or press `prefix r`); restart an IDE
# Editor pane to pick up init.lua changes.
