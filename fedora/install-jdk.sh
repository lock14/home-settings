#!/bin/bash
# Fedora OpenJDK installation and alternatives setup (LTS: 17, 21)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../system/java-common.sh"

JDK_INPUT="21"
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -v, --version <17|21>        Active Java LTS version to install (default: 21)
      --dry-run                Print commands without executing
  -h, --help                   Show this help message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -v|--version|-j|--jdk)
            JDK_INPUT="$2"
            shift 2
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

VER="$(normalize_jdk_version "$JDK_INPUT")"
if [ "$VER" = "eol" ]; then
    echo "Error: JDK version '$JDK_INPUT' is End-of-Life (EOL). Only actively supported LTS versions (17, 21) are supported." >&2
    exit 1
elif [ "$VER" = "unsupported" ]; then
    echo "Error: '$JDK_INPUT' is not a supported Java LTS version. Choose from: 17, 21" >&2
    exit 1
fi

ARCH="$(uname -m)"

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] $*"
    else
        "$@"
    fi
}

echo "==> [Fedora] Installing OpenJDK $VER LTS (arch: $ARCH)..."

PKG="java-${VER}-openjdk-devel"
ALT_TARGET="java-${VER}-openjdk.${ARCH}"

run_cmd sudo dnf -y install "$PKG"

echo "  Setting Java alternative to $ALT_TARGET..."
if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] sudo update-alternatives --set java $ALT_TARGET || true"
    echo "  [DryRun] sudo update-alternatives --set javac $ALT_TARGET || true"
else
    sudo update-alternatives --set java "$ALT_TARGET" 2>/dev/null || true
    sudo update-alternatives --set javac "$ALT_TARGET" 2>/dev/null || true
fi

echo "==> [Fedora] OpenJDK $VER LTS installation complete."
