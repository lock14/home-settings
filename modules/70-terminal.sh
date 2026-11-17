#!/bin/bash
# Stage 70: Terminal emulator configuration (GNOME Terminal, macOS Terminal.app).

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# shellcheck source=/dev/null
. "$REPO_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/os.sh"

OS="${OS:-$(detect_os)}"
DRY_RUN="${DRY_RUN:-false}"

configure_terminal() {
    local resolved_theme
    resolved_theme="$(resolve_persisted_theme "${XDG_CONFIG_HOME:-$HOME/.config}")"

    local -a cli_args=()
    [ -n "$resolved_theme" ] && cli_args+=("--theme=$resolved_theme")
    [ "$DRY_RUN" = true ] && cli_args+=("--dry-run")

    if [ "$OS" = "macos" ]; then
        echo "  Configuring macOS Terminal.app..."
        "$REPO_DIR/bin/macos-terminal-solarized" ${cli_args[@]+"${cli_args[@]}"}
        return 0
    fi

    if command -v dconf >/dev/null 2>&1 && command -v gsettings >/dev/null 2>&1; then
        local schemas
        schemas="$(gsettings list-schemas 2>/dev/null || true)"
        if grep -Fq "org.gnome.Terminal.ProfilesList" <<< "$schemas"; then
            echo "  Configuring GNOME Terminal..."
            "$REPO_DIR/bin/gnome-terminal-solarized" ${cli_args[@]+"${cli_args[@]}"}
        fi
    fi
}

configure_terminal
