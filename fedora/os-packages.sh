#!/bin/bash
# Fedora-specific OS package provisioning

set -euo pipefail

DRY_RUN=false
SKIP_UPGRADE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-upgrade)
            SKIP_UPGRADE=true
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

echo "==> [Fedora] Provisioning DNF packages..."

if [ "$SKIP_UPGRADE" = false ]; then
    echo "  Upgrading system packages..."
    run_cmd sudo dnf upgrade --refresh -y
fi

PACKAGES=(
    git
    curl
    wget
    vim
    maven
    dconf
    gnome-tweak-tool
    mariadb-server
    mariadb
    snapd
)

echo "  Installing core Fedora workstation packages: ${PACKAGES[*]}..."
run_cmd sudo dnf -y install "${PACKAGES[@]}"

# Setup snapd support
echo "  Configuring snapd environment..."
if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] sudo ln -sf /var/lib/snapd/snap /snap"
else
    sudo ln -sf /var/lib/snapd/snap /snap
fi

echo "==> [Fedora] DNF package provisioning completed."
