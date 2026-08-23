#!/bin/bash

set -o errexit   # abort on nonzero exitstatus.
set -o nounset   # abort on unbound variable.
set -o pipefail  # don't hide errors within pipes

# Detect package manager (apt for Ubuntu/Debian, dnf for Fedora)
if command -v apt &>/dev/null; then
    PKG_INSTALL="sudo apt --yes install"
elif command -v dnf &>/dev/null; then
    PKG_INSTALL="sudo dnf -y install"
else
    echo "Unsupported package manager. Only apt and dnf are supported." >&2
    exit 1
fi

# install necessary packages
$PKG_INSTALL zsh
$PKG_INSTALL fzf
if command -v apt &>/dev/null; then
    $PKG_INSTALL command-not-found || true
elif command -v dnf &>/dev/null; then
    $PKG_INSTALL PackageKit-command-not-found || true
fi

# install oh-my-zsh (unattended) if not already installed
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
if [ ! -d "$ZSH_DIR" ]; then
    RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

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

# install desired themes and plugins
clone_or_update "https://github.com/romkatv/powerlevel10k.git" "$ZSH_CUSTOM_DIR/themes/powerlevel10k"
clone_or_update "https://github.com/zsh-users/zsh-autosuggestions.git" "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
clone_or_update "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
clone_or_update "https://github.com/unixorn/fzf-zsh-plugin.git" "$ZSH_CUSTOM_DIR/plugins/fzf-zsh-plugin"

# configure ~/.zshrc if present
if [ -f "$HOME/.zshrc" ]; then
    sed -i 's|ZSH_THEME="robbyrussell"|ZSH_THEME="powerlevel10k/powerlevel10k"|g' "$HOME/.zshrc"
    sed -i 's|plugins=(git)|plugins=(git command-not-found zsh-autosuggestions zsh-syntax-highlighting fzf-zsh-plugin)|g' "$HOME/.zshrc"
fi

# switch shell to zsh
if command -v chsh &>/dev/null && [ "${SHELL:-}" != "$(command -v zsh)" ]; then
    chsh -s "$(command -v zsh)"
fi

