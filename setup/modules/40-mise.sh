#!/bin/bash
# Stage 40: Mise runtime manager & polyglot toolchains.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$MODULE_DIR/.." && pwd)"
REPO_DIR="$(cd "$SETUP_DIR/.." && pwd)"

# shellcheck source=/dev/null
. "$SETUP_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$SETUP_DIR/lib/os.sh"
# shellcheck source=/dev/null
. "$SETUP_DIR/lib/symlink.sh"

DRY_RUN="${DRY_RUN:-false}"

echo "  Configuring Mise runtime manager (Java LTS, Go, Terraform)..."

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] Installing mise and provisioning runtimes from .mise.toml"
    exit 0
fi

if ! command -v mise >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/mise" ]; then
    echo "  Installing standalone mise binary..."
    curl -fsSL https://mise.run | sh
fi

MISE_BIN="$(command -v mise || echo "$HOME/.local/bin/mise")"
if [ ! -x "$MISE_BIN" ]; then
    echo "Error: mise binary not found or not executable at $MISE_BIN" >&2
    exit 1
fi

mise_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mise"
mkdir -p "$mise_config_dir"
if [ -f "$REPO_DIR/.mise.toml" ]; then
    link_file "$REPO_DIR/.mise.toml" "$mise_config_dir/config.toml"
    "$MISE_BIN" trust "$REPO_DIR/.mise.toml" >/dev/null
    "$MISE_BIN" trust "$mise_config_dir/config.toml" >/dev/null
fi

echo "  Installing Mise toolchains from .mise.toml..."
export ELAN_HOME="${ELAN_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/elan}"
mkdir -p "$ELAN_HOME/toolchains"
retry_cmd 2 0 "$MISE_BIN" install -y
prepend_existing_paths "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims"

# Ensure Lean 4 stable toolchain is initialized when elan is installed
if "$MISE_BIN" which elan >/dev/null 2>&1; then
    elan_out="$("$MISE_BIN" exec -- elan show 2>/dev/null || true)"
    if ! grep -Fq "(default)" <<< "$elan_out"; then
        retry_cmd 2 0 "$MISE_BIN" exec -- elan default stable
    fi
elif command -v elan >/dev/null 2>&1; then
    elan_out="$(elan show 2>/dev/null || true)"
    if ! grep -Fq "(default)" <<< "$elan_out"; then
        retry_cmd 2 0 elan default stable
    fi
fi

# Rebuild bat cache with modern Mise bat and remove obsolete distro shims
if "$MISE_BIN" which bat >/dev/null 2>&1; then
    rebuild_bat_cache "$MISE_BIN"
    if [ -L "$HOME/.local/bin/bat" ] && [ "$(readlink "$HOME/.local/bin/bat")" = "$(command -v batcat 2>/dev/null)" ]; then
        rm -f "$HOME/.local/bin/bat"
    fi
fi
