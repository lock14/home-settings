#!/bin/bash
# Stage 20: User utilities synchronization (bin/ -> ~/.local/bin/).

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# Source helper libraries
# shellcheck source=/dev/null
. "$REPO_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/symlink.sh"

DRY_RUN="${DRY_RUN:-false}"
BIN_DIR="$REPO_DIR/bin"
DEST_DIR="$HOME/.local/bin"

echo "  Symlinking bin utilities to ~/.local/bin..."

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] Symlinking bin/* into $DEST_DIR"
else
    mkdir -p "$DEST_DIR"
    for f in "$BIN_DIR"/*; do
        if [ -f "$f" ]; then
            chmod +x "$f"
            link_file "$f" "$DEST_DIR/$(basename "$f")"
        fi
    done

    # Compatibility shims for Debian/Ubuntu package naming conventions
    if [ ! -e "$DEST_DIR/fd" ] && command -v fdfind >/dev/null 2>&1; then
        link_file "$(command -v fdfind)" "$DEST_DIR/fd"
    fi
    if [ ! -e "$DEST_DIR/bat" ] && command -v batcat >/dev/null 2>&1; then
        link_file "$(command -v batcat)" "$DEST_DIR/bat"
    fi
fi
