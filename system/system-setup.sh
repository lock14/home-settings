#!/bin/bash
# Master system setup orchestrator for modern Linux workstations (Ubuntu 22.04+ & Fedora 38+)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/java-common.sh"

JDK_INPUT="21"
IDE_INPUT="intellij-ultimate"
TARGET_OS=""
DRY_RUN=false
SKIP_PACKAGES=false
SKIP_CHROME=false
SKIP_JDK=false
SKIP_SNAPS=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Master system provisioner for Ubuntu (22.04+ LTS) and Fedora (38+) workstations.

Options:
  -j, --jdk <ver>       Active Java LTS version to install: 17, 21 (default: 21)
  -i, --ide <name>      IDE to install: intellij, intellij-ultimate, eclipse, netbeans, code, none (default: intellij-ultimate)
      --os <distro>     Target OS adapter: ubuntu, fedora (auto-detected if omitted)
      --skip-packages   Skip OS package manager updates and core CLI package installs
      --skip-chrome     Skip Google Chrome installation
      --skip-jdk        Skip OpenJDK installation and alternatives setup
      --skip-snaps      Skip Snap desktop application installs
      --dry-run         Print actions without modifying the system
  -h, --help            Show this help message
EOF
}

# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        -j|--jdk)
            JDK_INPUT="$2"
            shift 2
            ;;
        -i|--ide)
            IDE_INPUT="$2"
            shift 2
            ;;
        --os)
            TARGET_OS="$2"
            shift 2
            ;;
        --skip-packages)
            SKIP_PACKAGES=true
            shift
            ;;
        --skip-chrome)
            SKIP_CHROME=true
            shift
            ;;
        --skip-jdk)
            SKIP_JDK=true
            shift
            ;;
        --skip-snaps)
            SKIP_SNAPS=true
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

# Detect OS if not explicitly specified
detect_os() {
    if [ -n "$TARGET_OS" ]; then
        echo "$TARGET_OS"
        return 0
    fi

    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        case "${ID:-}" in
            ubuntu|debian|pop|linuxmint)
                echo "ubuntu"
                return 0
                ;;
            fedora|rhel|centos|rocky|almalinux)
                echo "fedora"
                return 0
                ;;
        esac

        # Check ID_LIKE
        case "${ID_LIKE:-}" in
            *ubuntu*|*debian*)
                echo "ubuntu"
                return 0
                ;;
            *fedora*|*rhel*)
                echo "fedora"
                return 0
                ;;
        esac
    fi

    # Fallback heuristic
    if command -v apt-get &>/dev/null; then
        echo "ubuntu"
    elif command -v dnf &>/dev/null; then
        echo "fedora"
    else
        echo "unknown"
    fi
}

OS_NAME="$(detect_os)"

if [ "$OS_NAME" != "ubuntu" ] && [ "$OS_NAME" != "fedora" ]; then
    echo "Error: Unsupported or unrecognized distribution: '$OS_NAME'. Please specify --os ubuntu or --os fedora." >&2
    exit 1
fi

VER="$(normalize_jdk_version "$JDK_INPUT")"
if [ "$VER" = "eol" ]; then
    echo "Error: JDK version '$JDK_INPUT' is End-of-Life (EOL). Only actively supported LTS versions (17, 21) are supported." >&2
    exit 1
elif [ "$VER" = "unsupported" ]; then
    echo "Error: '$JDK_INPUT' is not a supported Java LTS version. Choose from: 17, 21" >&2
    exit 1
fi

if ! validate_ide_name "$IDE_INPUT"; then
    echo "Error: '$IDE_INPUT' is not a supported IDE. Choose from: intellij, intellij-ultimate, eclipse, netbeans, code, none" >&2
    exit 1
fi

echo "====================================================="
echo "        Linux Workstation System Provisioning        "
echo "====================================================="
echo "Target OS : $OS_NAME"
echo "JDK Choice: OpenJDK $VER (LTS)"
echo "IDE Choice: $IDE_INPUT"
if [ "$DRY_RUN" = true ]; then
    echo "Mode      : DRY RUN (no modifications will be made)"
fi
echo "====================================================="

DISTRO_DIR="$REPO_DIR/$OS_NAME"
DRY_RUN_ARG=()
if [ "$DRY_RUN" = true ]; then
    DRY_RUN_ARG=("--dry-run")
fi

# 1. OS Packages
if [ "$SKIP_PACKAGES" = false ]; then
    echo -e "\n[1/4] Installing $OS_NAME system packages..."
    "$DISTRO_DIR/os-packages.sh" "${DRY_RUN_ARG[@]}"
else
    echo -e "\n[1/4] Skipping system packages."
fi

# 2. Google Chrome
if [ "$SKIP_CHROME" = false ]; then
    echo -e "\n[2/4] Installing Google Chrome on $OS_NAME..."
    "$DISTRO_DIR/install-chrome.sh" "${DRY_RUN_ARG[@]}"
else
    echo -e "\n[2/4] Skipping Google Chrome."
fi

# 3. OpenJDK Setup
if [ "$SKIP_JDK" = false ]; then
    echo -e "\n[3/4] Installing OpenJDK $VER (LTS) on $OS_NAME..."
    "$DISTRO_DIR/install-jdk.sh" --version "$VER" "${DRY_RUN_ARG[@]}"
else
    echo -e "\n[3/4] Skipping OpenJDK."
fi

# 4. Snap Desktop Packages & IDE
if [ "$SKIP_SNAPS" = false ]; then
    echo -e "\n[4/4] Installing Snap developer applications..."
    "$SCRIPT_DIR/snap-packages.sh" --ide "$IDE_INPUT" "${DRY_RUN_ARG[@]}"
else
    echo -e "\n[4/4] Skipping Snap applications."
fi

echo -e "\n====================================================="
echo " System provisioning complete for $OS_NAME!           "
echo "====================================================="
