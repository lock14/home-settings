#!/bin/bash
# Ubuntu Google Chrome installation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../system/java-common.sh"

DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] $*"
    else
        "$@"
    fi
}

ARCH="$(get_system_arch)"

echo "==> [Ubuntu] Installing Google Chrome..."

if [ "$ARCH" != "amd64" ]; then
    echo "  Notice: Google Chrome official package is only available for amd64 architecture (current: $ARCH). Skipping."
    exit 0
fi

DOWNLOAD_DIR="${TMPDIR:-/tmp}/chrome-install"
mkdir -p "$DOWNLOAD_DIR"
DEB_PATH="$DOWNLOAD_DIR/google-chrome-stable_current_amd64.deb"

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O $DEB_PATH"
    echo "  [DryRun] sudo apt-get --yes install $DEB_PATH || sudo dpkg -i $DEB_PATH"
else
    echo "  Downloading Google Chrome deb..."
    wget -q "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" -O "$DEB_PATH"
    echo "  Installing package..."
    sudo apt-get --yes install "$DEB_PATH" || sudo dpkg -i "$DEB_PATH"
    rm -f "$DEB_PATH"
fi

echo "==> [Ubuntu] Google Chrome installation complete."
