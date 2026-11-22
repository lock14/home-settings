#!/bin/bash
# Stage 30: MesloLGS Nerd Font (ryanoasis/nerd-fonts v3) downloading and caching.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$MODULE_DIR/.." && pwd)"
REPO_DIR="$(cd "$SETUP_DIR/.." && pwd)"

# shellcheck source=/dev/null
. "$SETUP_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$SETUP_DIR/lib/os.sh"

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
    exit 0
fi

CACHE_DIR="${HOME_SETTINGS_FONT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/home-settings/fonts}"
mkdir -p "$FONT_DIR" "$CACHE_DIR"

cleanup_font_tmp() {
    rm -f "$CACHE_DIR"/*.tmp.$$.* "$FONT_DIR"/*.tmp.$$.* 2>/dev/null || true
}
trap cleanup_font_tmp EXIT

remove_font_globs() {
    local f
    for f in "$@"; do
        if [ -e "$f" ]; then
            rm -f "$f"
            fonts_changed=1
        fi
    done
}

font_is_valid() {
    [ "$(file_byte_size "$1")" -ge "$MIN_FONT_BYTES" ]
}

# 1. Remove conflicting hyphenated or stray numbered font files
fonts_changed=0
remove_font_globs \
    "$FONT_DIR"/MesloLGS-NF-*.ttf "$CACHE_DIR"/MesloLGS-NF-*.ttf \
    "$FONT_DIR"/[0-9]MesloLGS*.ttf "$CACHE_DIR"/[0-9]MesloLGS*.ttf

# 2. Ensure fontconfig alias is provisioned on Linux and clean any dangling symlinks
if [ "$OS" != "macos" ]; then
    xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
    if [ -L "$xdg_config/fontconfig" ] && [ ! -e "$xdg_config/fontconfig" ]; then
        rm -f "$xdg_config/fontconfig"
    fi
    fontconfig_dir="$xdg_config/fontconfig/conf.d"
    mkdir -p "$fontconfig_dir"
    fc_alias_src="$REPO_DIR/dotfiles/.config/fontconfig/conf.d/10-meslo-nerd-font.conf"
    fc_alias_dest="$fontconfig_dir/10-meslo-nerd-font.conf"
    if [ -f "$fc_alias_src" ] && [ ! "$fc_alias_src" -ef "$fc_alias_dest" ]; then
        atomic_copy_file "$fc_alias_src" "$fc_alias_dest"
    fi
fi

# 3. Validate cached archive and download atomically only when a font is missing
ARCHIVE_VERSION="v3.5.1"
ARCHIVE_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${ARCHIVE_VERSION}/Meslo.tar.xz"
CACHED_ARCHIVE="$CACHE_DIR/Meslo-${ARCHIVE_VERSION}.tar.xz"
MIN_ARCHIVE_BYTES=4500000
MIN_FONT_BYTES=2500000
FONTS=(
    "MesloLGSNerdFontMono-Regular.ttf"
    "MesloLGSNerdFontMono-Bold.ttf"
    "MesloLGSNerdFontMono-Italic.ttf"
    "MesloLGSNerdFontMono-BoldItalic.ttf"
)

if [ -f "$CACHED_ARCHIVE" ] && [ "$(file_byte_size "$CACHED_ARCHIVE")" -lt "$MIN_ARCHIVE_BYTES" ]; then
    rm -f "$CACHED_ARCHIVE"
fi

need_download=0
for font in "${FONTS[@]}"; do
    if ! font_is_valid "$FONT_DIR/$font" && ! font_is_valid "$CACHE_DIR/$font"; then
        need_download=1
        break
    fi
done

if [ "$need_download" -eq 1 ] && [ ! -s "$CACHED_ARCHIVE" ]; then
    atomic_download_url "$ARCHIVE_URL" "$CACHED_ARCHIVE"
fi

# 4. Extract missing fonts into cache and install to target atomically (preserving open inodes)
for font in "${FONTS[@]}"; do
    target="$FONT_DIR/$font"
    cached="$CACHE_DIR/$font"

    if ! font_is_valid "$cached" && [ -s "$CACHED_ARCHIVE" ]; then
        tar -xf "$CACHED_ARCHIVE" -C "$CACHE_DIR" "$font"
    fi

    if ! font_is_valid "$target" && [ -s "$cached" ]; then
        atomic_copy_file "$cached" "$target"
        fonts_changed=1
    fi

    if ! font_is_valid "$target"; then
        echo "Error: Font installation failed or incomplete for $font at $target" >&2
        exit 1
    fi
done

# 5. Clean up legacy unpatched romkatv fonts and symbols fallback font once v3 is safely in place
remove_font_globs \
    "$FONT_DIR/MesloLGS NF"*.ttf "$CACHE_DIR/MesloLGS NF"*.ttf \
    "$FONT_DIR"/SymbolsNerdFont*.ttf "$CACHE_DIR"/SymbolsNerdFont*.ttf

if [ "$OS" = "macos" ] && command -v atsutil >/dev/null 2>&1; then
    atsutil server -ping >/dev/null 2>&1 || true
elif [ "$OS" != "macos" ] && [ "$fonts_changed" -eq 1 ] && command -v fc-cache >/dev/null 2>&1; then
    fc-cache "$FONT_DIR" >/dev/null
fi
