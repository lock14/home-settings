#!/bin/bash
set -euo pipefail

DEST="$HOME/gnome-terminal-colors-solarized"
if [ ! -d "$DEST" ]; then
    git clone https://github.com/aruhier/gnome-terminal-colors-solarized.git "$DEST"
else
    git -C "$DEST" pull --ff-only || true
fi

if [ -f "$DEST/install.sh" ]; then
    "$DEST/install.sh"
fi

