#!/bin/bash
# Stage 20: User utilities synchronization (bin/ -> ~/.local/bin/).

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$MODULE_DIR/.." && pwd)"
REPO_DIR="$(cd "$SETUP_DIR/.." && pwd)"

# shellcheck source=/dev/null
. "$SETUP_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$SETUP_DIR/lib/symlink.sh"

DRY_RUN="${DRY_RUN:-false}"
BIN_DIR="$REPO_DIR/bin"
DEST_DIR="$HOME/.local/bin"

echo "  Symlinking bin utilities to ~/.local/bin..."

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] Symlinking bin/* into $DEST_DIR"
else
    mkdir -p "$DEST_DIR"
    # Only regular top-level executables in bin/ are linked; internal packages live in libexec/.
    for f in "$BIN_DIR"/*; do
        [ -f "$f" ] || continue
        chmod +x "$f"
        link_file "$f" "$DEST_DIR/$(basename "$f")"
    done

    # Compatibility shims for Debian/Ubuntu package naming conventions
    for shim_pair in "fd:fdfind" "bat:batcat"; do
        shim_name="${shim_pair%%:*}"
        distro_cmd="${shim_pair#*:}"
        if [ ! -e "$DEST_DIR/$shim_name" ] && command -v "$distro_cmd" >/dev/null 2>&1; then
            link_file "$(command -v "$distro_cmd")" "$DEST_DIR/$shim_name"
        fi
    done
fi
