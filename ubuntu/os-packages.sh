#!/bin/bash
# Ubuntu-specific OS package provisioning

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

echo "==> [Ubuntu] Provisioning APT packages..."

if [ "$SKIP_UPGRADE" = false ]; then
    echo "  Updating package indexes and upgrading system packages..."
    run_cmd sudo apt-get --yes update
    run_cmd sudo apt-get --yes full-upgrade
    run_cmd sudo apt-get --yes autoremove
fi

PACKAGES=(
    git
    curl
    wget
    vim
    maven
    dconf-cli
    mariadb-server
    mariadb-client
    shellcheck
)

echo "  Installing core Ubuntu workstation packages: ${PACKAGES[*]}..."
run_cmd sudo apt-get --yes install "${PACKAGES[@]}"

echo "==> [Ubuntu] APT package provisioning completed."
