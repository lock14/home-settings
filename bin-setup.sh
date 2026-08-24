#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# user stuff
mkdir -p "$HOME/bin"
rsync -av "$SCRIPT_DIR/common-bin/" "$HOME/bin"

