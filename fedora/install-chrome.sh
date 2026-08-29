#!/bin/bash
# Fedora Google Chrome installation

set -euo pipefail

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

echo "==> [Fedora] Installing Google Chrome..."

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] sudo dnf -y install fedora-workstation-repositories"
    echo "  [DryRun] sudo dnf config-manager enable google-chrome"
    echo "  [DryRun] sudo dnf -y install google-chrome-stable"
else
    sudo dnf -y install fedora-workstation-repositories

    # Enable repository (compatible with both DNF4 and DNF5)
    sudo dnf config-manager setopt google-chrome.enabled=1 2>/dev/null || \
    sudo dnf config-manager --enable google-chrome 2>/dev/null || \
    sudo dnf config-manager --set-enabled google-chrome 2>/dev/null || \
    sudo dnf config-manager enable google-chrome 2>/dev/null || true

    sudo dnf -y install google-chrome-stable
    sudo dnf -y install chrome-gnome-shell || true
fi

echo "==> [Fedora] Google Chrome installation complete."
