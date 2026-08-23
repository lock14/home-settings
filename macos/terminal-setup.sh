#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIGURE_TERMINAL_APP=true
CONFIGURE_ITERM2=false
CONFIGURE_GHOSTTY=false
DRY_RUN=false

usage() {
    cat << 'EOF'
usage: terminal-setup.sh [options]

Configure macOS terminal emulators with Solarized Dark and MesloLGS NF font.
Apple Terminal.app is always configured by default.

Options:
  --terminal-only   Configure only Apple Terminal.app
  --iterm2          Configure iTerm2 (creates Dynamic Profile)
  --ghostty         Configure Ghostty (creates ~/.config/ghostty/config)
  --all             Configure Terminal.app, iTerm2, and Ghostty
  --dry-run         Print actions without making changes
  -h, --help        Show this help message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --terminal-only)
            CONFIGURE_TERMINAL_APP=true
            ;;
        --iterm2)
            CONFIGURE_ITERM2=true
            ;;
        --ghostty)
            CONFIGURE_GHOSTTY=true
            ;;
        --all)
            CONFIGURE_TERMINAL_APP=true
            CONFIGURE_ITERM2=true
            CONFIGURE_GHOSTTY=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "error: unknown option '$1'" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

# Auto-detect installed emulators if not explicitly toggled
if [ -d "/Applications/iTerm.app" ] || [ -d "$HOME/Applications/iTerm.app" ]; then
    CONFIGURE_ITERM2=true
fi
if [ -d "/Applications/Ghostty.app" ] || [ -d "$HOME/Applications/Ghostty.app" ] || command -v ghostty &>/dev/null; then
    CONFIGURE_GHOSTTY=true
fi

# 1. Configure Apple Terminal.app (Always)
if [ "$CONFIGURE_TERMINAL_APP" = true ]; then
    echo "Configuring Apple Terminal.app..."
    TERMINAL_PROFILE="$SCRIPT_DIR/Solarized Dark.terminal"
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Import $TERMINAL_PROFILE and set as default profile"
    else
        if [ "$(uname -s)" = "Darwin" ] && command -v defaults &>/dev/null; then
            if command -v open &>/dev/null && [ -f "$TERMINAL_PROFILE" ]; then
                open "$TERMINAL_PROFILE" || true
            fi
            defaults write com.apple.Terminal "Default Window Settings" -string "Solarized Dark" 2>/dev/null || true
            defaults write com.apple.Terminal "Startup Window Settings" -string "Solarized Dark" 2>/dev/null || true
            echo "Apple Terminal.app configured with Solarized Dark and MesloLGS NF."
        else
            echo "Note: Non-macOS environment detected. Terminal.app configuration skipped."
        fi
    fi
fi

# 2. Configure iTerm2 (Optional / Dynamic Profile)
if [ "$CONFIGURE_ITERM2" = true ]; then
    echo "Configuring iTerm2 Dynamic Profile..."
    ITERM_PROFILE_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    ITERM_TARGET="$ITERM_PROFILE_DIR/solarized-dark.json"
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Copy $SCRIPT_DIR/iterm2-profile.json -> $ITERM_TARGET"
    else
        mkdir -p "$ITERM_PROFILE_DIR"
        cp -f "$SCRIPT_DIR/iterm2-profile.json" "$ITERM_TARGET"
        echo "iTerm2 Dynamic Profile installed at $ITERM_TARGET"
    fi
fi

# 3. Configure Ghostty (Optional / Config file)
if [ "$CONFIGURE_GHOSTTY" = true ]; then
    echo "Configuring Ghostty..."
    GHOSTTY_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
    GHOSTTY_TARGET="$GHOSTTY_CONFIG_DIR/config"
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Copy $SCRIPT_DIR/ghostty-config -> $GHOSTTY_TARGET"
    else
        mkdir -p "$GHOSTTY_CONFIG_DIR"
        cp -f "$SCRIPT_DIR/ghostty-config" "$GHOSTTY_TARGET"
        echo "Ghostty configuration installed at $GHOSTTY_TARGET"
    fi
fi

echo "Terminal appearance setup complete."
