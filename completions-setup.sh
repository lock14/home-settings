#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure completions directory exists
COMPLETIONS_DIR="$HOME/.zsh/completions"
mkdir -p "$COMPLETIONS_DIR"

# 1. Symlink zsh_completions
ln -sf "$SCRIPT_DIR/zsh_completions" "$HOME/.zsh_completions"

# 2. Install zsh-users/zsh-completions plugin for Oh-My-Zsh
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
if [ -d "$HOME/.oh-my-zsh" ]; then
    mkdir -p "$ZSH_CUSTOM_DIR/plugins"
    dest="$ZSH_CUSTOM_DIR/plugins/zsh-completions"
    if [ -d "$dest/.git" ]; then
        echo "Updating zsh-completions..."
        git -C "$dest" pull --ff-only || true
    else
        echo "Cloning zsh-completions..."
        git clone --depth=1 "https://github.com/zsh-users/zsh-completions.git" "$dest"
    fi
fi

# 3. Generate completion definitions for installed CLIs
# GitHub CLI (gh)
if command -v gh &>/dev/null; then
    echo "Generating GitHub CLI completions..."
    gh completion -s zsh > "$COMPLETIONS_DIR/_gh" 2>/dev/null || true
fi

# Kubernetes CLI (kubectl)
if command -v kubectl &>/dev/null; then
    echo "Generating kubectl completions..."
    kubectl completion zsh > "$COMPLETIONS_DIR/_kubectl" 2>/dev/null || true
fi

# Helm CLI (helm)
if command -v helm &>/dev/null; then
    echo "Generating helm completions..."
    helm completion zsh > "$COMPLETIONS_DIR/_helm" 2>/dev/null || true
fi

echo "Zsh completions installed successfully."
