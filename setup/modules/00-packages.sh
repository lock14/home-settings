#!/bin/bash
# Stage 00: Native package management, database servers, and desktop applications.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# shellcheck source=/dev/null
. "$SETUP_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$SETUP_DIR/lib/os.sh"
# shellcheck source=/dev/null
. "$SETUP_DIR/lib/pkg.sh"

OS="${OS:-$(detect_os)}"
ARCH="${ARCH:-$(detect_arch)}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_PACKAGES="${SKIP_PACKAGES:-false}"
SKIP_DB="${SKIP_DB:-false}"
DB_CHOICE="${DB_CHOICE:-none}"
INSTALL_CHROME="${INSTALL_CHROME:-false}"
INSTALL_APPS="${INSTALL_APPS:-false}"
INSTALL_GHOSTTY="${INSTALL_GHOSTTY:-false}"
IDE_NAME="${IDE_NAME:-none}"
IDE_NAMES="${IDE_NAMES:-}"

UBUNTU_CORE_PKGS=(
    git curl wget vim neovim tmux zsh fzf fontconfig dconf-cli
    xclip wl-clipboard shellcheck command-not-found bat fd-find
    ripgrep zoxide tree libatomic1 imagemagick
)
FEDORA_CORE_PKGS=(
    git curl wget vim neovim tmux zsh fzf fontconfig dconf
    xclip wl-clipboard snapd util-linux-user ShellCheck bat fd-find
    ripgrep zoxide eza tree libatomic ImageMagick
)
MACOS_CORE_PKGS=(
    git curl wget vim neovim tmux zsh fzf fontconfig shellcheck
    bat btop fd ripgrep zoxide eza tree imagemagick
)

# 1. Core System Packages & Lightweight Database Clients
if [ "$SKIP_PACKAGES" = false ]; then
    echo "  Installing core system packages for $OS..."
    pkgs=()
    case "$OS" in
        ubuntu)
            pkgs=("${UBUNTU_CORE_PKGS[@]}")
            [ "$SKIP_DB" = false ] && pkgs+=(postgresql-client mariadb-client)
            pkg_install_native ubuntu --refresh -- "${pkgs[@]}"
            ;;
        fedora)
            pkgs=("${FEDORA_CORE_PKGS[@]}")
            [ "$SKIP_DB" = false ] && pkgs+=(postgresql mariadb)
            pkg_install_native fedora --refresh -- "${pkgs[@]}"
            ensure_fedora_snapd
            ;;
        macos)
            ensure_homebrew
            pkgs=("${MACOS_CORE_PKGS[@]}")
            [ "$SKIP_DB" = false ] && pkgs+=(libpq)
            pkg_install_native macos -- "${pkgs[@]}"
            ;;
    esac
fi

# 2. Database Server Provisioning (Opt-in only)
if [ "$SKIP_DB" = false ] && [ "$DB_CHOICE" != "none" ]; then
    echo "  Provisioning database server ($DB_CHOICE) on $OS..."
    if [ "$DB_CHOICE" = "postgres" ] || [ "$DB_CHOICE" = "all" ]; then
        case "$OS" in
            ubuntu) pkg_install_native ubuntu -- postgresql postgresql-contrib ;;
            fedora) pkg_install_native fedora -- postgresql-server postgresql-contrib ;;
            macos)  pkg_install_native macos -- postgresql@16 ;;
        esac
    fi
    if [ "$DB_CHOICE" = "mariadb" ] || [ "$DB_CHOICE" = "all" ]; then
        case "$OS" in
            ubuntu) pkg_install_native ubuntu -- mariadb-server mariadb-client ;;
            fedora) pkg_install_native fedora -- mariadb-server mariadb ;;
            macos)  pkg_install_native macos -- mariadb ;;
        esac
    fi
fi

# 3. Optional Desktop Applications (Opt-in only)
if [ "$INSTALL_CHROME" = true ]; then
    echo "  Installing Google Chrome on $OS..."
    install_google_chrome "$OS" "$ARCH"
fi

if [ "$INSTALL_APPS" = true ]; then
    ide_list="${IDE_NAMES:-$IDE_NAME}"
    if [ -n "$ide_list" ] && [ "$ide_list" != "none" ]; then
        echo "  Installing developer desktop applications..."
        IFS=',' read -r -a ide_targets <<< "$ide_list"
        for ide_item in "${ide_targets[@]}"; do
            [ -n "$ide_item" ] && [ "$ide_item" != "none" ] && install_desktop_ide "$OS" "$ide_item"
        done
    fi
fi

if [ "$INSTALL_GHOSTTY" = true ]; then
    echo "  Installing Ghostty terminal emulator on $OS..."
    install_ghostty "$OS" "$ARCH"
fi
