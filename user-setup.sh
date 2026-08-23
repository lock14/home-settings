#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run full dotfile install
make -C "$SCRIPT_DIR" install

# Run shell & OS setup scripts
"$SCRIPT_DIR/zsh-setup.sh"
if command -v gnome-terminal &>/dev/null && [ -n "${DISPLAY:-}" ]; then
    "$SCRIPT_DIR/gnome-terminal-setup.sh" || true
fi

