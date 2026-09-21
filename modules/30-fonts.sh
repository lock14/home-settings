#!/bin/bash
# Stage 30: MesloLGS Nerd Font (ryanoasis/nerd-fonts v3) downloading and caching.

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

echo "  Installing MesloLGS Nerd Font fonts into $FONT_DIR..."

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] Downloading MesloLGS Nerd Font (Regular, Bold, Italic, Bold Italic) to $FONT_DIR"
else
    mkdir -p "$FONT_DIR"
    CACHE_DIR="${HOME_SETTINGS_FONT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/home-settings/fonts}"
    mkdir -p "$CACHE_DIR"

    # Remove any conflicting hyphenated or stray numbered font files
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
        elif [ -f "$fc_alias_src" ] && ! [ "$fc_alias_src" -ef "$fc_alias_dest" ]; then
            cp -f "$fc_alias_src" "$fc_alias_dest"
        fi
    fi

    ARCHIVE_VERSION="v3.5.1"
    ARCHIVE_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${ARCHIVE_VERSION}/Meslo.tar.xz"
    CACHED_ARCHIVE="$CACHE_DIR/Meslo-${ARCHIVE_VERSION}.tar.xz"
    FONTS=(
        "MesloLGSNerdFontMono-Regular.ttf"
        "MesloLGSNerdFontMono-Bold.ttf"
        "MesloLGSNerdFontMono-Italic.ttf"
        "MesloLGSNerdFontMono-BoldItalic.ttf"
    )

    # Validate cached archive if present (>4.5MB)
    if [ -f "$CACHED_ARCHIVE" ]; then
        asize=$(wc -c < "$CACHED_ARCHIVE" | tr -d ' ')
        if [ "$asize" -lt 4500000 ]; then
            rm -f "$CACHED_ARCHIVE"
        fi
    fi

    # Determine if any font needs extraction or download
    need_download=0
    for font in "${FONTS[@]}"; do
        target="$FONT_DIR/$font"
        cached="$CACHE_DIR/$font"
        if [ ! -s "$target" ] || [ "$(wc -c < "$target" | tr -d ' ')" -lt 2900000 ]; then
            if [ ! -s "$cached" ] || [ "$(wc -c < "$cached" | tr -d ' ')" -lt 2900000 ]; then
                need_download=1
            fi
        fi
    done

    if [ "$need_download" -eq 1 ] && [ ! -s "$CACHED_ARCHIVE" ]; then
        tmp_archive="$CACHED_ARCHIVE.tmp.$$.${BASHPID:-$RANDOM}"
        trap 'rm -f "$tmp_archive"' EXIT
        if curl -fsSL "$ARCHIVE_URL" -o "$tmp_archive"; then
            mv -f "$tmp_archive" "$CACHED_ARCHIVE"
        else
            rm -f "$tmp_archive"
            exit 1
        fi
    fi

    for font in "${FONTS[@]}"; do
        target="$FONT_DIR/$font"
        cached="$CACHE_DIR/$font"

        # Extract from archive into cache if missing
        if [ ! -s "$cached" ] || [ "$(wc -c < "$cached" | tr -d ' ')" -lt 2900000 ]; then
            if [ -s "$CACHED_ARCHIVE" ]; then
                tar -xf "$CACHED_ARCHIVE" -C "$CACHE_DIR" "$font"
            fi
        fi

        # Install from cache to target atomically
        if [ ! -s "$target" ] || [ "$(wc -c < "$target" | tr -d ' ')" -lt 2900000 ]; then
            if [ -s "$cached" ]; then
                target_tmp="$target.tmp.$$.${BASHPID:-$RANDOM}"
                trap 'rm -f "$target_tmp"' EXIT
                cp -f "$cached" "$target_tmp" && mv -f "$target_tmp" "$target"
            fi
        fi
    done

    # Clean up legacy unpatched romkatv fonts and symbols fallback font once v3 is safely in place
    rm -f "$FONT_DIR/MesloLGS NF"*.ttf "$CACHE_DIR/MesloLGS NF"*.ttf
    rm -f "$FONT_DIR"/SymbolsNerdFont*.ttf "$CACHE_DIR"/SymbolsNerdFont*.ttf

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
