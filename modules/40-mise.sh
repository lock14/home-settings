#!/bin/bash
# Stage 40: Mise runtime manager & polyglot toolchains.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# Source helper libraries
# shellcheck source=/dev/null
. "$REPO_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/symlink.sh"

DRY_RUN="${DRY_RUN:-false}"

echo "  Configuring Mise runtime manager (Java LTS, Go, Terraform)..."

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] Installing mise and provisioning runtimes from .mise.toml"
else
    if ! command -v mise &>/dev/null && [ ! -x "$HOME/.local/bin/mise" ]; then
        echo "  Installing standalone mise binary..."
        curl -fsSL https://mise.run | sh
    fi

    MISE_BIN="$(command -v mise || echo "$HOME/.local/bin/mise")"
    if [ -x "$MISE_BIN" ]; then
        # Link repository config into XDG config
        mise_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mise"
        mkdir -p "$mise_config_dir"
        if [ -f "$REPO_DIR/.mise.toml" ]; then
            link_file "$REPO_DIR/.mise.toml" "$mise_config_dir/config.toml"
            "$MISE_BIN" trust "$REPO_DIR/.mise.toml" >/dev/null 2>&1 || true
            "$MISE_BIN" trust "$mise_config_dir/config.toml" >/dev/null 2>&1 || true
        fi

        # Install runtimes
        echo "  Installing Mise toolchains from .mise.toml..."
        "$MISE_BIN" install -y || true
        if [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims" ]; then
            export PATH="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:$PATH"
        fi

        # Rebuild bat cache with modern Mise bat and remove obsolete distro shims
        if "$MISE_BIN" which bat >/dev/null 2>&1; then
            "$MISE_BIN" exec -- bat cache --build >/dev/null 2>&1 || true
            if [ -L "$HOME/.local/bin/bat" ] && [ "$(readlink "$HOME/.local/bin/bat")" = "$(command -v batcat 2>/dev/null)" ]; then
                rm -f "$HOME/.local/bin/bat"
            fi
        fi
    fi
fi
