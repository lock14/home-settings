#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

# Ensure pathogen autoload and bundle directories exist
mkdir -p "$HOME/.vim/autoload" "$HOME/.vim/bundle"

# Install Pathogen
if [ ! -f "$HOME/.vim/autoload/pathogen.vim" ]; then
    echo "Installing Pathogen..."
    curl -LSso "$HOME/.vim/autoload/pathogen.vim" https://tpo.pe/pathogen.vim
fi

clone_or_update() {
    local repo="$1"
    local dest="$2"
    if [ -d "$dest/.git" ]; then
        echo "Updating $(basename "$dest")..."
        git -C "$dest" pull --ff-only || true
    else
        echo "Cloning $(basename "$dest")..."
        git clone --depth=1 "$repo" "$dest"
    fi
}

# Install / update bundles
clone_or_update "https://github.com/altercation/vim-colors-solarized.git" "$HOME/.vim/bundle/vim-colors-solarized"
clone_or_update "https://github.com/jiangmiao/auto-pairs.git" "$HOME/.vim/bundle/auto-pairs"
clone_or_update "https://github.com/SirVer/ultisnips.git" "$HOME/.vim/bundle/ultisnips"
clone_or_update "https://github.com/ervandew/supertab.git" "$HOME/.vim/bundle/supertab"

# Copy or symlink .vimrc if not managed via Makefile
if [ ! -f "$HOME/.vimrc" ] && [ -f ".vimrc" ]; then
    cp .vimrc "$HOME/.vimrc"
fi
