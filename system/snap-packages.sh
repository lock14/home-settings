#!/bin/bash
# Common Snap package provisioning across Linux distributions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/java-common.sh"

IDE="intellij-ultimate"
SKIP_IDE=false
SKIP_APPS=false
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -i, --ide <name>      IDE to install (intellij, intellij-ultimate, eclipse, netbeans, none)
      --skip-ide        Skip IDE installation
      --skip-apps       Skip additional desktop apps (VS Code, Postman, Slack)
      --dry-run         Print commands without executing
  -h, --help            Show this help message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -i|--ide)
            IDE="$2"
            shift 2
            ;;
        --skip-ide)
            SKIP_IDE=true
            shift
            ;;
        --skip-apps)
            SKIP_APPS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if ! validate_ide_name "$IDE"; then
    echo "Error: '$IDE' is not a supported IDE. Choose from: intellij, intellij-ultimate, eclipse, netbeans, code, none" >&2
    exit 1
fi

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] $*"
    else
        "$@"
    fi
}

# Verify snap command is available
if ! command -v snap &>/dev/null && [ "$DRY_RUN" = false ]; then
    echo "Warning: 'snap' command is not available in PATH. Skipping snap provisioning." >&2
    exit 0
fi

echo "==> Provisioning Snap packages..."

# Install selected IDE
if [ "$SKIP_IDE" = false ] && [ "$IDE" != "none" ]; then
    case "$IDE" in
        intellij)
            echo "  Installing IntelliJ IDEA Community..."
            run_cmd sudo snap install intellij-idea-community --classic
            ;;
        intellij-ultimate)
            echo "  Installing IntelliJ IDEA Ultimate..."
            run_cmd sudo snap install intellij-idea-ultimate --classic
            ;;
        eclipse)
            echo "  Installing Eclipse..."
            run_cmd sudo snap install eclipse --classic
            ;;
        netbeans)
            echo "  Installing Apache NetBeans..."
            run_cmd sudo snap install netbeans --classic
            ;;
        code)
            echo "  Installing VS Code..."
            run_cmd sudo snap install code --classic
            ;;
    esac
fi

# Install developer desktop applications
if [ "$SKIP_APPS" = false ]; then
    echo "  Installing VS Code..."
    run_cmd sudo snap install code --classic

    echo "  Installing Postman..."
    run_cmd sudo snap install postman

    echo "  Installing Slack..."
    run_cmd sudo snap install slack --classic
fi

echo "==> Snap provisioning completed."
