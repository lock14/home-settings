#!/bin/bash
# Stage 50: Legacy Vim configuration, Pathogen, and plugin bundles.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# Source helper libraries
# shellcheck source=/dev/null
. "$REPO_DIR/lib/log.sh"

DRY_RUN="${DRY_RUN:-false}"

echo "  Configuring Vim plugins..."

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] Setting up Vim configuration and Pathogen bundles (solarized, auto-pairs, ultisnips, supertab, vim-snippets)"
else
    mkdir -p "$HOME/.vim/autoload" "$HOME/.vim/bundle"
    if [ ! -f "$HOME/.vim/autoload/pathogen.vim" ]; then
        if [ -f "$REPO_DIR/.vim/autoload/pathogen.vim" ]; then
            cp "$REPO_DIR/.vim/autoload/pathogen.vim" "$HOME/.vim/autoload/pathogen.vim"
        else
            curl -LSsfo "$HOME/.vim/autoload/pathogen.vim" https://tpo.pe/pathogen.vim || true
        fi
    fi

    clone_bundle() {
        local repo="$1"
        local dest="$2"
        if [ -d "$dest/.git" ]; then
            git -C "$dest" pull --ff-only || true
        else
            if [ -d "$dest" ]; then
                rm -rf "$dest"
            fi
            git clone --depth=1 "$repo" "$dest" || true
        fi
    }

    clone_bundle "https://github.com/altercation/vim-colors-solarized.git" "$HOME/.vim/bundle/vim-colors-solarized" &
    clone_bundle "https://github.com/jiangmiao/auto-pairs.git" "$HOME/.vim/bundle/auto-pairs" &
    clone_bundle "https://github.com/SirVer/ultisnips.git" "$HOME/.vim/bundle/ultisnips" &
    clone_bundle "https://github.com/ervandew/supertab.git" "$HOME/.vim/bundle/supertab" &
    clone_bundle "https://github.com/honza/vim-snippets.git" "$HOME/.vim/bundle/vim-snippets" &
    wait
fi
