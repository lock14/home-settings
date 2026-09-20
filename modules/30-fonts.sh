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

    # Remove any conflicting Nerd Fonts v3, hyphenated, or stray numbered font files
    rm -f "$FONT_DIR"/MesloLGSNerdFont-*.ttf "$CACHE_DIR"/MesloLGSNerdFont-*.ttf
    rm -f "$FONT_DIR"/MesloLGS-NF-*.ttf "$CACHE_DIR"/MesloLGS-NF-*.ttf
    rm -f "$FONT_DIR"/[0-9]MesloLGS*.ttf "$CACHE_DIR"/[0-9]MesloLGS*.ttf

    # Ensure fontconfig alias is provisioned on Linux and clean any dangling symlinks
    if [ "$OS" != "macos" ]; then
        xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
        if [ -L "$xdg_config/fontconfig" ] && [ ! -e "$xdg_config/fontconfig" ]; then
            rm -f "$xdg_config/fontconfig"
        fi
        fontconfig_dir="$xdg_config/fontconfig/conf.d"
        mkdir -p "$fontconfig_dir"
        fc_alias_src="$REPO_DIR/dotfiles/.config/fontconfig/conf.d/10-meslo-nerd-font.conf"
        fc_alias_dest="$fontconfig_dir/10-meslo-nerd-font.conf"
        if [ -f "$fc_alias_src" ] && [ ! -e "$fc_alias_dest" ]; then
            cp -f "$fc_alias_src" "$fc_alias_dest"
        fi
    fi

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
        encoded_font="${font// /%20}"

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
                target_tmp="$target.tmp.$$.${BASHPID:-$RANDOM}"
                cp -f "$cached" "$target_tmp" && mv -f "$target_tmp" "$target"
            else
                (
                    tmp_file="$cached.tmp.$$.${BASHPID:-$RANDOM}"
                    target_tmp="$target.tmp.$$.${BASHPID:-$RANDOM}"
                    trap 'rm -f "$tmp_file" "$target_tmp"' EXIT
                    if curl -fsSL "$BASE_FONT_URL/$encoded_font" -o "$tmp_file"; then
                        mv -f "$tmp_file" "$cached"
                        cp -f "$cached" "$target_tmp" && mv -f "$target_tmp" "$target"
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
    if [ "$OS" = "macos" ] && command -v atsutil &>/dev/null; then
        # Ensure the macOS font server is awake (never kill fontd while terminal apps are running)
        atsutil server -ping >/dev/null 2>&1 || true
    fi
    if command -v fc-cache &>/dev/null; then
        fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
        if [ "$OS" != "macos" ] && [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig" ]; then
            fc-cache -f "${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig" >/dev/null 2>&1 || true
        fi
    fi

fi
