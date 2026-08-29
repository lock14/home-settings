#!/bin/bash
# Ubuntu OpenJDK installation and alternatives setup (LTS: 17, 21)

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

ARCH="$(get_system_arch)"

echo "==> [Ubuntu] Installing OpenJDK $VER LTS (arch: $ARCH)..."

JDK_PKG="openjdk-${VER}-jdk"
SRC_PKG="openjdk-${VER}-source"
ALT_NAME_1="java-1.${VER}.0-openjdk-${ARCH}"
ALT_NAME_2="java-${VER}-openjdk-${ARCH}"

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] sudo apt-get --yes install $JDK_PKG $SRC_PKG"
    echo "  [DryRun] sudo update-java-alternatives -s $ALT_NAME_1 || sudo update-java-alternatives -s $ALT_NAME_2"
else
    # Install package with resilient fallbacks
    sudo apt-get --yes install "$JDK_PKG" "$SRC_PKG" 2>/dev/null || \
    sudo apt-get --yes install "$JDK_PKG" 2>/dev/null || \
    sudo apt-get --yes install openjdk-17-jdk 2>/dev/null || true

    echo "  Setting Java alternative for OpenJDK $VER..."
    sudo update-java-alternatives -s "$ALT_NAME_1" 2>/dev/null || \
    sudo update-java-alternatives -s "$ALT_NAME_2" 2>/dev/null || true
fi

echo "==> [Ubuntu] OpenJDK $VER LTS installation complete."
