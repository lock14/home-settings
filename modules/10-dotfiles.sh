#!/bin/bash
# Stage 10: Declarative dotfile auto-discovery and mirroring to $HOME.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# Source helper libraries
# shellcheck source=/dev/null
. "$REPO_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/symlink.sh"

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
    if [ -f "$src" ]; then
        link_file "$src" "$HOME/$name"
    fi
done

# 2. Backward compatibility alias symlink (.zsh-aliases -> .aliases)
link_file "$HOME/.aliases" "$HOME/.zsh-aliases"

# 3. Discover and link directory-based dotfiles (.dir-colors)
if [ -d "$DOTFILES_DIR/.dir-colors" ]; then
    mkdir -p "$HOME/.dir-colors"
    for f in "$DOTFILES_DIR/.dir-colors"/*; do
        [ -e "$f" ] || continue
        link_file "$f" "$HOME/.dir-colors/$(basename "$f")"
    done
fi

# 4. Discover and link .config subtrees (e.g. nvim)
if [ -d "$DOTFILES_DIR/.config" ]; then
    mkdir -p "$XDG_CONFIG"
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
fi

# 5. Bat TrueColor Syntax Highlighting Theme
BAT_THEME_SRC="$REPO_DIR/colors/Solarized-Dark-TrueColor.tmTheme"
if [ -f "$BAT_THEME_SRC" ]; then
    echo "  Configuring Bat TrueColor theme..."
    link_file "$BAT_THEME_SRC" "$XDG_CONFIG/bat/themes/Solarized-Dark-TrueColor.tmTheme"
    if [ "$DRY_RUN" = false ]; then
        if command -v mise >/dev/null 2>&1 && mise which bat >/dev/null 2>&1; then
            mise exec -- bat cache --build >/dev/null 2>&1 || true
        elif command -v bat >/dev/null 2>&1; then
            bat cache --build >/dev/null 2>&1 || true
        elif command -v batcat >/dev/null 2>&1; then
            batcat cache --build >/dev/null 2>&1 || true
        fi
    fi
fi

# 6. Polyglot Toolchains Configuration (Mise)
if [ -f "$REPO_DIR/.mise.toml" ]; then
    link_file "$REPO_DIR/.mise.toml" "$XDG_CONFIG/mise/config.toml"
fi
