#!/bin/bash
# =============================================================================
# bootstrap.sh - Zero-dependency turnkey bootstrapper for home-settings
# Supports modern Unix systems (Ubuntu 22.04+/24.04+ LTS, Fedora 38+/40+, macOS)
#
# Usage (Stream & Run):
#   curl -fsSL https://raw.githubusercontent.com/lock14/home-settings/main/bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/lock14/home-settings/main/bootstrap.sh | bash -s -- --dotfiles-only
# =============================================================================

set -euo pipefail

echo "====================================================="
echo "       home-settings Turnkey Bootstrapper            "
echo "====================================================="

# 1. Verify Git prerequisite
if ! command -v git >/dev/null 2>&1; then
    echo -e "\n[1/3] Git not found. Attempting package installation..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y && sudo apt-get install -y git curl
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf -y install git curl
    elif command -v brew >/dev/null 2>&1; then
        brew install git curl
    else
        echo "Error: git is required to clone home-settings. Please install git and rerun." >&2
        exit 1
    fi
else
    echo -e "\n[1/3] Git prerequisite satisfied."
fi

# 2. Determine target repository location
REPO_URL="https://github.com/lock14/home-settings.git"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
CURRENT_DIR="$(pwd)"

if [ -n "$SCRIPT_SOURCE" ] && [ -f "$(dirname "$SCRIPT_SOURCE")/setup.sh" ]; then
    TARGET_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    echo -e "\n[2/3] Using existing repository clone at $TARGET_DIR."
elif [ -f "$CURRENT_DIR/setup.sh" ]; then
    TARGET_DIR="$CURRENT_DIR"
    echo -e "\n[2/3] Using current directory at $TARGET_DIR."
else
    TARGET_DIR="$HOME/home-settings"
    if [ ! -d "$TARGET_DIR" ]; then
        echo -e "\n[2/3] Cloning home-settings to $TARGET_DIR..."
        git clone "$REPO_URL" "$TARGET_DIR"
    else
        echo -e "\n[2/3] Updating existing home-settings at $TARGET_DIR..."
        git -C "$TARGET_DIR" pull --rebase origin main 2>/dev/null || git -C "$TARGET_DIR" pull --rebase origin master 2>/dev/null || true
    fi
fi

# 3. Execute setup orchestrator
SETUP_SCRIPT="$TARGET_DIR/setup.sh"
if [ ! -f "$SETUP_SCRIPT" ]; then
    echo "Error: Setup script not found at $SETUP_SCRIPT" >&2
    exit 1
fi

chmod +x "$SETUP_SCRIPT"

echo -e "\n[3/3] Invoking master setup orchestrator..."
if [ $# -gt 0 ]; then
    "$SETUP_SCRIPT" "$@"
else
    "$SETUP_SCRIPT" --bootstrap
fi
