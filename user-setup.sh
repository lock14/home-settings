#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run full dotfile install
make -C "$SCRIPT_DIR" install

# Configure GNOME Terminal colors if applicable
if command -v gnome-terminal &>/dev/null && [ -n "${DISPLAY:-${WAYLAND_DISPLAY:-}}" ]; then
    if [ -x "$SCRIPT_DIR/gnome-terminal-setup.sh" ]; then
        "$SCRIPT_DIR/gnome-terminal-setup.sh" || true
    fi
fi

