#!/bin/bash
set -euo pipefail

FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
mkdir -p "$FONT_DIR"

BASE_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
FONTS=(
    "MesloLGS NF Regular.ttf"
    "MesloLGS NF Bold.ttf"
    "MesloLGS NF Italic.ttf"
    "MesloLGS NF Bold Italic.ttf"
)

echo "Installing MesloLGS NF fonts into $FONT_DIR..."
for font in "${FONTS[@]}"; do
    target="$FONT_DIR/$font"
    if [ ! -f "$target" ]; then
        encoded_font="${font// /%20}"
        echo "Downloading $font..."
        curl -fsSL "$BASE_URL/$encoded_font" -o "$target"
    else
        echo "$font already installed."
    fi
done

if command -v fc-cache &>/dev/null; then
    echo "Updating font cache..."
    fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
fi

echo "MesloLGS NF fonts installed successfully."
