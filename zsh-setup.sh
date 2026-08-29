#!/bin/bash

set -o errexit   # abort on nonzero exitstatus.
set -o nounset   # abort on unbound variable.
set -o pipefail  # don't hide errors within pipes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install zsh and dependencies if missing and package manager with sudo is available
if ! command -v zsh &>/dev/null; then
    if command -v sudo &>/dev/null && command -v apt &>/dev/null; then
        sudo apt update -y 2>/dev/null || true
        sudo apt install -y zsh || true
    elif [ "${EUID:-$(id -u)}" -eq 0 ] && command -v apt &>/dev/null; then
        apt update -y 2>/dev/null || true
        apt install -y zsh || true
    elif command -v sudo &>/dev/null && command -v dnf &>/dev/null; then
        sudo dnf -y install zsh || true
    elif [ "${EUID:-$(id -u)}" -eq 0 ] && command -v dnf &>/dev/null; then
        dnf -y install zsh || true
    fi
fi

if ! command -v fzf &>/dev/null; then
    if command -v sudo &>/dev/null && command -v apt &>/dev/null; then
        sudo apt install -y fzf 2>/dev/null || true
        sudo apt install -y command-not-found 2>/dev/null || true
    elif command -v sudo &>/dev/null && command -v dnf &>/dev/null; then
        sudo dnf -y install fzf 2>/dev/null || true
        sudo dnf -y install PackageKit-command-not-found 2>/dev/null || true
    fi
fi

# Check that zsh is installed
if ! command -v zsh &>/dev/null; then
    echo "Error: zsh is not installed. Please run ./bootstrap.sh or install zsh first." >&2
    exit 1
fi

# Symlink Zsh dotfiles
ln -sf "$SCRIPT_DIR/zsh_aliases" "$HOME/.zsh_aliases"
ln -sf "$SCRIPT_DIR/zsh_functions" "$HOME/.zsh_functions"
ln -sf "$SCRIPT_DIR/zshrc_addendum" "$HOME/.zshrc_addendum"
ln -sf "$SCRIPT_DIR/zsh_completions" "$HOME/.zsh_completions"
if [ -f "$SCRIPT_DIR/p10k.zsh" ]; then
    ln -sf "$SCRIPT_DIR/p10k.zsh" "$HOME/.p10k.zsh"
fi


# Install oh-my-zsh (unattended) if not already installed
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

# Install desired themes and plugins
clone_or_update "https://github.com/romkatv/powerlevel10k.git" "$ZSH_CUSTOM_DIR/themes/powerlevel10k"
clone_or_update "https://github.com/zsh-users/zsh-autosuggestions.git" "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
clone_or_update "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
clone_or_update "https://github.com/zsh-users/zsh-completions.git" "$ZSH_CUSTOM_DIR/plugins/zsh-completions"
clone_or_update "https://github.com/unixorn/fzf-zsh-plugin.git" "$ZSH_CUSTOM_DIR/plugins/fzf-zsh-plugin"

# Configure ~/.zshrc if present
if [ -f "$HOME/.zshrc" ]; then
    sed -i 's|ZSH_THEME="robbyrussell"|ZSH_THEME="powerlevel10k/powerlevel10k"|g' "$HOME/.zshrc"
    sed -i 's|plugins=(git)|plugins=(git command-not-found zsh-autosuggestions zsh-syntax-highlighting zsh-completions fzf-zsh-plugin)|g' "$HOME/.zshrc"
    sed -i 's|plugins=(git command-not-found zsh-autosuggestions zsh-syntax-highlighting fzf-zsh-plugin)|plugins=(git command-not-found zsh-autosuggestions zsh-syntax-highlighting zsh-completions fzf-zsh-plugin)|g' "$HOME/.zshrc"
    grep -qxF 'source ~/.zshrc_addendum' "$HOME/.zshrc" 2>/dev/null || \
        printf '\n# home-settings\n[ -f ~/.zshrc_addendum ] && source ~/.zshrc_addendum\n' >> "$HOME/.zshrc"
fi

# Switch shell to zsh if interactive and not already zsh
CURRENT_SHELL="$(getent passwd "${USER:-$(whoami)}" 2>/dev/null | cut -d: -f7 || echo "${SHELL:-}")"
if [ -t 0 ] && command -v chsh &>/dev/null && command -v zsh &>/dev/null && [ "$CURRENT_SHELL" != "$(command -v zsh)" ]; then
    chsh -s "$(command -v zsh)" || true
fi


