#!/bin/bash
# Stage 30: MesloLGS NF (romkatv/powerlevel10k-media) downloading and caching.

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

    # Remove any conflicting Nerd Fonts v3 files, old spaced filenames (which macOS CoreText
    # com.apple.FontRegistry.user.plist marks as disabled duplicates), or fontconfig alias symlinks
    rm -f "$FONT_DIR"/MesloLGSNerdFont-*.ttf "$CACHE_DIR"/MesloLGSNerdFont-*.ttf
    rm -f "$FONT_DIR"/"MesloLGS NF"*.ttf
    rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d/10-meslo-nerd-font.conf"

    BASE_FONT_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
    FONT_SPECS=(
        "MesloLGS%20NF%20Regular.ttf|MesloLGS-NF-Regular.ttf|MesloLGS NF Regular.ttf"
        "MesloLGS%20NF%20Bold.ttf|MesloLGS-NF-Bold.ttf|MesloLGS NF Bold.ttf"
        "MesloLGS%20NF%20Italic.ttf|MesloLGS-NF-Italic.ttf|MesloLGS NF Italic.ttf"
        "MesloLGS%20NF%20Bold%20Italic.ttf|MesloLGS-NF-Bold-Italic.ttf|MesloLGS NF Bold Italic.ttf"
    )
    pids=()
    for spec in "${FONT_SPECS[@]}"; do
        IFS='|' read -r encoded_remote target_name legacy_cache_name <<< "$spec"
        target="$FONT_DIR/$target_name"
        cached="$CACHE_DIR/$target_name"
        legacy_cached="$CACHE_DIR/$legacy_cache_name"

        if [ ! -s "$cached" ] && [ -s "$legacy_cached" ]; then
            lsize=$(wc -c < "$legacy_cached" | tr -d ' ')
            if [ "$lsize" -gt 1000000 ] && [ "$lsize" -lt 2700000 ]; then
                cp -f "$legacy_cached" "$cached"
            fi
        fi

        # Purge any >2.7MB Nerd Fonts v3 overwrite or stub so authentic romkatv MesloLGS NF (~2.59MB) is restored
        if [ -f "$cached" ]; then
            csize=$(wc -c < "$cached" | tr -d ' ')
            if [ "$csize" -gt 2700000 ] || [ "$csize" -lt 1000000 ]; then
                rm -f "$cached"
            fi
        fi
        if [ -f "$target" ]; then
            tsize=$(wc -c < "$target" | tr -d ' ')
            if [ "$tsize" -gt 2700000 ] || [ "$tsize" -lt 1000000 ]; then
                rm -f "$target"
            fi
        fi

        if [ ! -s "$target" ]; then
            if [ -s "$cached" ]; then
                cp -f "$cached" "$target"
            else
                (
                    tmp_file="$cached.tmp.$$.${BASHPID:-$RANDOM}"
                    trap 'rm -f "$tmp_file"' EXIT
                    if curl -fsSL "$BASE_FONT_URL/$encoded_remote" -o "$tmp_file"; then
                        mv -f "$tmp_file" "$cached" && cp -f "$cached" "$target"
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
    if [ "$OS" = "macos" ]; then
        defaults delete com.apple.FontRegistry.user >/dev/null 2>&1 || true
        rm -f "$HOME/Library/Preferences/com.apple.FontRegistry.user.plist" 2>/dev/null || true
        if command -v atsutil &>/dev/null; then
            atsutil databases -removeUser >/dev/null 2>&1 || true
            atsutil server -shutdown >/dev/null 2>&1 || true
            atsutil server -ping >/dev/null 2>&1 || true
        fi
        killall fontd >/dev/null 2>&1 || true
    fi
    if command -v fc-cache &>/dev/null; then
        fc-cache -rf "$FONT_DIR" >/dev/null 2>&1 || fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
    fi
fi
