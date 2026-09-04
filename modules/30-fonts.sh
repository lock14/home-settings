#!/bin/bash
# Stage 30: MesloLGS NF font downloading and caching.

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

if [ "$OS" = "macos" ]; then
    FONT_DIR="$HOME/Library/Fonts"
else
    FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
fi

echo "  Installing MesloLGS NF fonts into $FONT_DIR..."

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] Downloading MesloLGS NF (Regular, Bold, Italic, Bold Italic) to $FONT_DIR"
else
    mkdir -p "$FONT_DIR"
    CACHE_DIR="${HOME_SETTINGS_FONT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/home-settings/fonts}"
    mkdir -p "$CACHE_DIR"
    BASE_FONT_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
    FONTS=(
        "MesloLGS NF Regular.ttf"
        "MesloLGS NF Bold.ttf"
        "MesloLGS NF Italic.ttf"
        "MesloLGS NF Bold Italic.ttf"
    )
    pids=()
    for font in "${FONTS[@]}"; do
        target="$FONT_DIR/$font"
        cached="$CACHE_DIR/$font"
        if [ ! -s "$target" ]; then
            if [ -s "$cached" ]; then
                cp "$cached" "$target"
            else
                encoded_font="${font// /%20}"
                ( curl -fsSL "$BASE_FONT_URL/$encoded_font" -o "$cached.tmp.$$" && mv -f "$cached.tmp.$$" "$cached" && cp "$cached" "$target" ) &
                pids+=($!)
            fi
        fi
    done
    if [ ${#pids[@]} -gt 0 ]; then
        for pid in "${pids[@]}"; do
            wait "$pid"
        done
    fi
    if command -v fc-cache &>/dev/null; then
        fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
    fi
fi
