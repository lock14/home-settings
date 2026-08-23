#!/bin/bash

set -o errexit   # abort on nonzero exitstatus.
set -o nounset   # abort on unbound variable.
set -o pipefail  # don't hide errors within pipes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install packages if missing and package manager with sudo is available
if ! command -v zsh &>/dev/null || ! command -v fzf &>/dev/null; then
    if command -v sudo &>/dev/null && command -v apt &>/dev/null; then
        sudo apt --yes install zsh fzf || true
        sudo apt --yes install command-not-found || true
    elif command -v sudo &>/dev/null && command -v dnf &>/dev/null; then
        sudo dnf -y install zsh fzf || true
        sudo dnf -y install PackageKit-command-not-found || true
    else
        echo "Note: zsh or fzf is missing, and automatic installation was skipped." >&2
    fi
fi

# Symlink Zsh dotfiles
ln -sf "$SCRIPT_DIR/zsh_aliases" "$HOME/.zsh_aliases"
ln -sf "$SCRIPT_DIR/zsh_functions" "$HOME/.zsh_functions"
ln -sf "$SCRIPT_DIR/zshrc_addendum" "$HOME/.zshrc_addendum"
ln -sf "$SCRIPT_DIR/zsh_completions" "$HOME/.zsh_completions"
if [ -f "$SCRIPT_DIR/p10k.zsh" ]; then
    ln -sf "$SCRIPT_DIR/p10k.zsh" "$HOME/.p10k.zsh"
fi

# Install MesloLGS NF fonts for Powerlevel10k
if [ -x "$SCRIPT_DIR/font-setup.sh" ]; then
    "$SCRIPT_DIR/font-setup.sh"
fi

# Install and configure completions (zsh-completions, gh, kubectl, helm, gcloud)
if [ -x "$SCRIPT_DIR/completions-setup.sh" ]; then
    "$SCRIPT_DIR/completions-setup.sh"
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
if [ -t 0 ] && command -v chsh &>/dev/null && command -v zsh &>/dev/null && [ "${SHELL:-}" != "$(command -v zsh)" ]; then
    chsh -s "$(command -v zsh)" || true
fi


