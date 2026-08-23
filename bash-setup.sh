#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Append bashrc-addendum source line to ~/.bashrc if not already present
if [ -f "$HOME/.bashrc" ]; then
    grep -qxF 'source ~/.bashrc-addendum' "$HOME/.bashrc" 2>/dev/null || \
        printf '\n# home-settings\n[ -f ~/.bashrc-addendum ] && source ~/.bashrc-addendum\n' >> "$HOME/.bashrc"
fi

# Symlink bashrc-addendum and environment_variables
ln -sf "$SCRIPT_DIR/bashrc-addendum" "$HOME/.bashrc-addendum"
ln -sf "$SCRIPT_DIR/environment_variables" "$HOME/.environment_variables"

