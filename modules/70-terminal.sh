#!/bin/bash
# Stage 70: Terminal emulator configuration (GNOME Terminal, etc.).

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

configure_terminal() {
    # GNOME Terminal profile provisioning on Linux
    if [ "$OS" != "macos" ] && command -v dconf >/dev/null 2>&1 && command -v gsettings >/dev/null 2>&1; then
        if gsettings list-schemas 2>/dev/null | grep -q "org.gnome.Terminal.ProfilesList"; then
            echo "  Configuring GNOME Terminal..."
            if [ "$DRY_RUN" = true ]; then
                "$REPO_DIR/bin/gnome-terminal-solarized" --dry-run
            else
                "$REPO_DIR/bin/gnome-terminal-solarized"
            fi
        fi
    fi
}

configure_terminal
