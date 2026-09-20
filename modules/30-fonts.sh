#!/bin/bash
# Stage 30: MesloLGS Nerd Font (v3) downloading and caching.

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

echo "  Installing MesloLGS Nerd Font (v3) fonts into $FONT_DIR..."

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] Downloading MesloLGS Nerd Font v3 (Regular, Bold, Italic, Bold Italic) to $FONT_DIR"
else
    mkdir -p "$FONT_DIR"
    CACHE_DIR="${HOME_SETTINGS_FONT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/home-settings/fonts}"
    mkdir -p "$CACHE_DIR"
    BASE_FONT_URL="https://github.com/ryanoasis/nerd-fonts/raw/v3.3.0/patched-fonts/Meslo/S"
    FONT_SPECS=(
        "Regular/MesloLGSNerdFont-Regular.ttf|MesloLGSNerdFont-Regular.ttf|MesloLGS NF Regular.ttf"
        "Bold/MesloLGSNerdFont-Bold.ttf|MesloLGSNerdFont-Bold.ttf|MesloLGS NF Bold.ttf"
        "Italic/MesloLGSNerdFont-Italic.ttf|MesloLGSNerdFont-Italic.ttf|MesloLGS NF Italic.ttf"
        "Bold-Italic/MesloLGSNerdFont-BoldItalic.ttf|MesloLGSNerdFont-BoldItalic.ttf|MesloLGS NF Bold Italic.ttf"
    )
    pids=()
    for spec in "${FONT_SPECS[@]}"; do
        IFS='|' read -r remote_rel v3_font _ <<< "$spec"
        target="$FONT_DIR/$v3_font"
        cached="$CACHE_DIR/$v3_font"
        if [ ! -s "$target" ]; then
            if [ -s "$cached" ]; then
                cp "$cached" "$target"
            else
                (
                    tmp_file="$cached.tmp.$$.${BASHPID:-$RANDOM}"
                    trap 'rm -f "$tmp_file"' EXIT
                    if curl -fsSL "$BASE_FONT_URL/$remote_rel" -o "$tmp_file"; then
                        mv -f "$tmp_file" "$cached" && cp "$cached" "$target"
                    else
                        rm -f "$tmp_file"
                        exit 1
                    fi
                ) &
                pids+=($!)
            fi
        elif [ ! -s "$cached" ]; then
            cp -f "$target" "$cached"
        fi
    done
    if [ ${#pids[@]} -gt 0 ]; then
        download_failed=0
        for pid in "${pids[@]}"; do
            if ! wait "$pid"; then
                download_failed=1
            fi
        done
        if [ "$download_failed" -ne 0 ]; then
            exit 1
        fi
    fi
    for spec in "${FONT_SPECS[@]}"; do
        IFS='|' read -r _ v3_font legacy_font <<< "$spec"
        v3_target="$FONT_DIR/$v3_font"
        legacy_target="$FONT_DIR/$legacy_font"
        if [ -s "$v3_target" ]; then
            if [ ! -s "$legacy_target" ] || ! cmp -s "$v3_target" "$legacy_target"; then
                rm -f "$legacy_target"
                cp "$v3_target" "$legacy_target"
            fi
        fi
    done
    if command -v fc-cache &>/dev/null; then
        fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
    fi
fi
