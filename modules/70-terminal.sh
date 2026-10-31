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
    local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
    local resolved_theme="${HOME_SETTINGS_THEME:-}"
    if [ -z "$resolved_theme" ] && [ -f "$xdg_config/home-settings/theme" ]; then
        resolved_theme="$(tr -d '[:space:]' < "$xdg_config/home-settings/theme" || true)"
    fi
    local -a theme_args=()
    if [ -n "$resolved_theme" ]; then
        theme_args=("--theme=$resolved_theme")
    fi

    # GNOME Terminal profile provisioning on Linux
    if [ "$OS" != "macos" ] && command -v dconf >/dev/null 2>&1 && command -v gsettings >/dev/null 2>&1; then
        if gsettings list-schemas 2>/dev/null | grep -q "org.gnome.Terminal.ProfilesList"; then
            echo "  Configuring GNOME Terminal..."
            if [ "$DRY_RUN" = true ]; then
                "$REPO_DIR/bin/gnome-terminal-solarized" ${theme_args[@]+"${theme_args[@]}"} --dry-run
            else
                "$REPO_DIR/bin/gnome-terminal-solarized" ${theme_args[@]+"${theme_args[@]}"}
            fi
        fi
    fi

    # macOS Terminal.app profile provisioning on macOS
    if [ "$OS" = "macos" ]; then
        echo "  Configuring macOS Terminal.app..."
        if [ "$DRY_RUN" = true ]; then
            "$REPO_DIR/bin/macos-terminal-solarized" ${theme_args[@]+"${theme_args[@]}"} --dry-run
        else
            "$REPO_DIR/bin/macos-terminal-solarized" ${theme_args[@]+"${theme_args[@]}"}
        fi
    fi
}

configure_terminal
