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

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] $*"
    else
        "$@"
    fi
}

echo "==> [Fedora] Installing Google Chrome..."

run_cmd sudo dnf -y install fedora-workstation-repositories
run_cmd sudo dnf config-manager --set-enabled google-chrome
run_cmd sudo dnf -y install google-chrome-stable
run_cmd sudo dnf -y install chrome-gnome-shell || true

echo "==> [Fedora] Google Chrome installation complete."
