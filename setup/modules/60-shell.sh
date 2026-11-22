#!/bin/bash
# Stage 60: Shell environment (Oh-My-Zsh, Powerlevel10k, Bash hooks, Completions).

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$MODULE_DIR/.." && pwd)"
REPO_DIR="$(cd "$SETUP_DIR/.." && pwd)"

# shellcheck source=/dev/null
. "$SETUP_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$SETUP_DIR/lib/os.sh"
# shellcheck source=/dev/null
. "$SETUP_DIR/lib/shell-env.sh"

OS="${OS:-$(detect_os)}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_TOOLS="${SKIP_TOOLS:-false}"
SKIP_ZSH="${SKIP_ZSH:-false}"
SKIP_BASH="${SKIP_BASH:-false}"
SKIP_COMPLETIONS="${SKIP_COMPLETIONS:-false}"

# 1. Zsh, Oh-My-Zsh & Powerlevel10k
if [ "$SKIP_ZSH" = false ]; then
    echo "  Configuring Zsh, Oh-My-Zsh, plugins, and Powerlevel10k..."
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] Installing Oh-My-Zsh, Powerlevel10k, zsh-autosuggestions, syntax-highlighting, and completions"
    else
        ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
        if [ ! -d "$ZSH_DIR" ]; then
            RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        fi

        ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
        mkdir -p "$ZSH_CUSTOM_DIR/themes" "$ZSH_CUSTOM_DIR/plugins"

        zsh_repos=(
            "https://github.com/romkatv/powerlevel10k.git|$ZSH_CUSTOM_DIR/themes/powerlevel10k"
            "https://github.com/zsh-users/zsh-autosuggestions.git|$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
            "https://github.com/zsh-users/zsh-syntax-highlighting.git|$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
            "https://github.com/zsh-users/zsh-completions.git|$ZSH_CUSTOM_DIR/plugins/zsh-completions"
        )
        zsh_pids=()
        for spec in "${zsh_repos[@]}"; do
            sync_git_plugin_repo "${spec%%|*}" "${spec#*|}" &
            zsh_pids+=("$!")
        done
        for pid in "${zsh_pids[@]}"; do
            wait "$pid"
        done

        if [ ! -f "$HOME/.zshrc" ]; then
            if [ -f "$ZSH_DIR/templates/zshrc.zsh-template" ]; then
                cp "$ZSH_DIR/templates/zshrc.zsh-template" "$HOME/.zshrc"
            else
                touch "$HOME/.zshrc"
            fi
        elif [ -f "$ZSH_DIR/templates/zshrc.zsh-template" ] && \
             ! grep -Eq '^[[:space:]]*([^#]*[;&|][[:space:]]*)?(source|\.)[[:space:]][^#]*(oh-my-zsh\.sh|powerlevel10k\.zsh-theme)' "$HOME/.zshrc"; then
            zshrc_bak="$(backup_existing_path "$HOME/.zshrc")"
            cp "$ZSH_DIR/templates/zshrc.zsh-template" "$HOME/.zshrc"
            echo "  Backed up existing non-Oh-My-Zsh ~/.zshrc to $zshrc_bak and initialized Oh-My-Zsh template."
        fi

        sed_in_place "$HOME/.zshrc" 's|ZSH_THEME="robbyrussell"|ZSH_THEME="powerlevel10k/powerlevel10k"|g'
        sed_in_place "$HOME/.zshrc" 's|plugins=(git)|plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)|g'
        sed_in_place "$HOME/.zshrc" -E 's/[[:space:]]*fzf-zsh-plugin//g'
        ensure_shell_rc_hook "$HOME/.zshrc" ".zshrc-addendum"
    fi
fi

# 2. Bash Configuration
if [ "$SKIP_BASH" = false ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] Adding source ~/.bashrc-addendum to ~/.bashrc"
    else
        ensure_shell_rc_hook "$HOME/.bashrc" ".bashrc-addendum"
    fi
fi

# 3. CLI Completions
if [ "$SKIP_COMPLETIONS" = false ]; then
    COMPLETIONS_DIR="$HOME/.zsh/completions"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] Generating CLI tab completions in $COMPLETIONS_DIR"
    else
        strict_completions=true
        [ "$SKIP_TOOLS" = true ] && strict_completions=false
        sync_zsh_cli_completions "$COMPLETIONS_DIR" "$strict_completions" "$REPO_DIR/.mise.toml"
    fi
fi

# 4. Default Login Shell
if [ "$SKIP_ZSH" = false ]; then
    CURRENT_SHELL="$(getent passwd "${USER:-$(whoami)}" 2>/dev/null | cut -d: -f7 || echo "${SHELL:-}")"
    ZSH_BIN="$(command -v zsh 2>/dev/null || true)"
    if [ -n "$ZSH_BIN" ] && [ "$CURRENT_SHELL" != "$ZSH_BIN" ] && [ -t 0 ] && command -v chsh >/dev/null 2>&1; then
        echo "  Changing default login shell to Zsh ($ZSH_BIN)..."
        run_cmd chsh -s "$ZSH_BIN" || true
    fi
fi
