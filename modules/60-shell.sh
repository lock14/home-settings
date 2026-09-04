#!/bin/bash
# Stage 60: Shell environment (Oh-My-Zsh, Powerlevel10k, Bash hooks, Completions).

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# Source helper libraries
# shellcheck source=/dev/null
. "$REPO_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/os.sh"

OS="${OS:-$(detect_os)}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_ZSH="${SKIP_ZSH:-false}"
SKIP_BASH="${SKIP_BASH:-false}"
SKIP_COMPLETIONS="${SKIP_COMPLETIONS:-false}"

# Zsh, Oh-My-Zsh & Powerlevel10k
if [ "$SKIP_ZSH" = false ]; then
    echo "  Configuring Zsh, Oh-My-Zsh, plugins, and Powerlevel10k..."
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] Installing Oh-My-Zsh, Powerlevel10k, zsh-autosuggestions, syntax-highlighting, and completions"
    else
        ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
        if [ ! -d "$ZSH_DIR" ]; then
            RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true
        fi

        ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
        mkdir -p "$ZSH_CUSTOM_DIR/themes" "$ZSH_CUSTOM_DIR/plugins"

        clone_zsh() {
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

        clone_zsh "https://github.com/romkatv/powerlevel10k.git" "$ZSH_CUSTOM_DIR/themes/powerlevel10k" &
        clone_zsh "https://github.com/zsh-users/zsh-autosuggestions.git" "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" &
        clone_zsh "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" &
        clone_zsh "https://github.com/zsh-users/zsh-completions.git" "$ZSH_CUSTOM_DIR/plugins/zsh-completions" &
        clone_zsh "https://github.com/unixorn/fzf-zsh-plugin.git" "$ZSH_CUSTOM_DIR/plugins/fzf-zsh-plugin" &
        wait

        if [ ! -f "$HOME/.zshrc" ]; then
            if [ -f "$ZSH_DIR/templates/zshrc.zsh-template" ]; then
                cp "$ZSH_DIR/templates/zshrc.zsh-template" "$HOME/.zshrc"
            else
                touch "$HOME/.zshrc"
            fi
        fi

        if [ "$OS" = "macos" ]; then
            sed -i '' 's|ZSH_THEME="robbyrussell"|ZSH_THEME="powerlevel10k/powerlevel10k"|g' "$HOME/.zshrc" 2>/dev/null || true
            sed -i '' 's|plugins=(git)|plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)|g' "$HOME/.zshrc" 2>/dev/null || true
        else
            sed -i 's|ZSH_THEME="robbyrussell"|ZSH_THEME="powerlevel10k/powerlevel10k"|g' "$HOME/.zshrc" 2>/dev/null || true
            sed -i 's|plugins=(git)|plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)|g' "$HOME/.zshrc" 2>/dev/null || true
        fi
        grep -qxF '[ -f ~/.zshrc-addendum ] && source ~/.zshrc-addendum' "$HOME/.zshrc" || \
            printf '\n# home-settings\n[ -f ~/.zshrc-addendum ] && source ~/.zshrc-addendum\n' >> "$HOME/.zshrc"
    fi
fi

# Bash Configuration
if [ "$SKIP_BASH" = false ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] Adding source ~/.bashrc-addendum to ~/.bashrc"
    else
        if [ ! -f "$HOME/.bashrc" ]; then
            touch "$HOME/.bashrc"
        fi
        grep -qxF '[ -f ~/.bashrc-addendum ] && source ~/.bashrc-addendum' "$HOME/.bashrc" || \
            printf '\n# home-settings\n[ -f ~/.bashrc-addendum ] && source ~/.bashrc-addendum\n' >> "$HOME/.bashrc"
    fi
fi

# CLI Completions (gh, kubectl, helm)
if [ "$SKIP_COMPLETIONS" = false ]; then
    COMPLETIONS_DIR="$HOME/.zsh/completions"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] Generating CLI tab completions in $COMPLETIONS_DIR"
    else
        mkdir -p "$COMPLETIONS_DIR"
        if command -v gh &>/dev/null; then gh completion -s zsh > "$COMPLETIONS_DIR/_gh" || true; fi
        if command -v kubectl &>/dev/null; then kubectl completion zsh > "$COMPLETIONS_DIR/_kubectl" || true; fi
        if command -v helm &>/dev/null; then helm completion zsh > "$COMPLETIONS_DIR/_helm" || true; fi
    fi
fi

# Default Login Shell
CURRENT_SHELL="$(getent passwd "${USER:-$(whoami)}" 2>/dev/null | cut -d: -f7 || echo "${SHELL:-}")"
ZSH_BIN="$(command -v zsh 2>/dev/null || true)"
if [ -n "$ZSH_BIN" ] && [ "$CURRENT_SHELL" != "$ZSH_BIN" ] && [ -t 0 ] && command -v chsh &>/dev/null; then
    echo "  Changing default login shell to Zsh ($ZSH_BIN)..."
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] chsh -s $ZSH_BIN"
    else
        chsh -s "$ZSH_BIN" || true
    fi
fi
