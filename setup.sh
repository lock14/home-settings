#!/bin/bash
# Master setup script for home-settings (*nix dotfiles and workstation automation).
# Orchestrates system package provisioning (Ubuntu 22.04+ / Fedora 38+) and user configuration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults: Modern Java 21 LTS and IntelliJ IDEA Ultimate
JDK_VERSION="21"
IDE_NAME="intellij-ultimate"
TARGET_OS=""
DRY_RUN=false

# System setup skip flags
SKIP_SYSTEM=false
SKIP_PACKAGES=false
SKIP_CHROME=false
SKIP_JDK=false
SKIP_SNAPS=false

# User setup skip flags
SKIP_USER=false
SKIP_FONTS=false
SKIP_VIM=false
SKIP_ZSH=false
SKIP_BASH=false
SKIP_BIN=false
SKIP_COMPLETIONS=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Master setup orchestrator for home-settings (*nix / Ubuntu 22.04+ / Fedora 38+).

System Provisioning Options:
  -j, --jdk <ver>           Active Java LTS version to install: 17, 21 (default: 21)
  -i, --ide <name>          IDE to install: intellij, intellij-ultimate, eclipse, netbeans, code, none (default: intellij-ultimate)
      --os <distro>         Target OS adapter: ubuntu, fedora (auto-detected if omitted)
      --skip-system         Skip entire OS system provisioning (packages, chrome, jdk, snaps)
      --dotfiles-only       Alias for --skip-system
      --skip-packages       Skip OS package manager updates and core CLI package installs
      --skip-chrome         Skip Google Chrome installation
      --skip-jdk            Skip OpenJDK installation and alternatives setup
      --skip-snaps          Skip Snap desktop application installs

User Environment Options:
      --skip-user           Skip entire user environment configuration
      --system-only         Alias for --skip-user
      --skip-fonts          Skip font installation (MesloLGS NF)
      --skip-vim            Skip Vim configuration and Pathogen plugins
      --skip-zsh            Skip Zsh dotfiles, Oh-My-Zsh, plugins, and Powerlevel10k
      --skip-bash           Skip Bash configuration and environment variables
      --skip-bin            Skip ~/bin user utilities synchronization
      --skip-completions    Skip CLI tab completions setup

General Options:
      --dry-run             Print actions without executing
  -h, --help                Show this help message
EOF
}

# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        -j|--jdk)
            JDK_VERSION="$2"
            shift 2
            ;;
        -i|--ide)
            IDE_NAME="$2"
            shift 2
            ;;
        --os)
            TARGET_OS="$2"
            shift 2
            ;;
        --skip-system|--dotfiles-only)
            SKIP_SYSTEM=true
            shift
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
        --skip-user|--system-only)
            SKIP_USER=true
            shift
            ;;
        --skip-fonts)
            SKIP_FONTS=true
            shift
            ;;
        --skip-vim)
            SKIP_VIM=true
            shift
            ;;
        --skip-zsh)
            SKIP_ZSH=true
            shift
            ;;
        --skip-bash)
            SKIP_BASH=true
            shift
            ;;
        --skip-bin)
            SKIP_BIN=true
            shift
            ;;
        --skip-completions)
            SKIP_COMPLETIONS=true
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

echo "====================================================="
echo "             Home Settings Setup Automation          "
echo "====================================================="
if [ "$DRY_RUN" = true ]; then
    echo " Mode: DRY RUN (no files or packages will be modified)"
fi
echo "====================================================="

# 1. System-Level Provisioning (requires sudo)
if [ "$SKIP_SYSTEM" = false ]; then
    echo -e "\n[Step 1/2] Running System-Level Provisioning..."
    SYSTEM_ARGS=(
        "--jdk" "$JDK_VERSION"
        "--ide" "$IDE_NAME"
    )
    if [ -n "$TARGET_OS" ]; then
        SYSTEM_ARGS+=("--os" "$TARGET_OS")
    fi
    if [ "$SKIP_PACKAGES" = true ]; then SYSTEM_ARGS+=("--skip-packages"); fi
    if [ "$SKIP_CHROME" = true ]; then SYSTEM_ARGS+=("--skip-chrome"); fi
    if [ "$SKIP_JDK" = true ]; then SYSTEM_ARGS+=("--skip-jdk"); fi
    if [ "$SKIP_SNAPS" = true ]; then SYSTEM_ARGS+=("--skip-snaps"); fi
    if [ "$DRY_RUN" = true ]; then SYSTEM_ARGS+=("--dry-run"); fi

    "$SCRIPT_DIR/system/system-setup.sh" "${SYSTEM_ARGS[@]}"
else
    echo -e "\n[Step 1/2] Skipping System-Level Provisioning."
fi

# 2. User-Level Configuration & Dotfiles
if [ "$SKIP_USER" = false ]; then
    echo -e "\n[Step 2/2] Running User Dotfiles & Environment Setup..."

    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] Would install dotfiles (environment, LS_COLORS)"
        if [ "$SKIP_FONTS" = false ]; then echo "  [DryRun] Would install MesloLGS NF fonts"; fi
        if [ "$SKIP_COMPLETIONS" = false ]; then echo "  [DryRun] Would install completions"; fi
        if [ "$SKIP_ZSH" = false ]; then echo "  [DryRun] Would install Zsh configuration and plugins"; fi
        if [ "$SKIP_BASH" = false ]; then echo "  [DryRun] Would install Bash configuration"; fi
        if [ "$SKIP_VIM" = false ]; then echo "  [DryRun] Would install Vim configuration and plugins"; fi
        if [ "$SKIP_BIN" = false ]; then echo "  [DryRun] Would install common-bin utilities to ~/bin"; fi
    else
        # Environment & colors
        make -C "$SCRIPT_DIR" install-env

        # Fonts
        if [ "$SKIP_FONTS" = false ]; then
            "$SCRIPT_DIR/font-setup.sh"
        fi

        # Completions
        if [ "$SKIP_COMPLETIONS" = false ]; then
            "$SCRIPT_DIR/completions-setup.sh"
        fi

        # Zsh
        if [ "$SKIP_ZSH" = false ]; then
            "$SCRIPT_DIR/zsh-setup.sh"
        fi

        # Bash
        if [ "$SKIP_BASH" = false ]; then
            "$SCRIPT_DIR/bash-setup.sh"
        fi

        # Vim
        if [ "$SKIP_VIM" = false ]; then
            "$SCRIPT_DIR/vim-setup.sh"
        fi

        # User Bin
        if [ "$SKIP_BIN" = false ]; then
            "$SCRIPT_DIR/bin-setup.sh"
        fi

        # GNOME Terminal color profile (if running under graphical session)
        if command -v gnome-terminal &>/dev/null && [ -n "${DISPLAY:-}" ]; then
            "$SCRIPT_DIR/gnome-terminal-setup.sh" || true
        fi
    fi
else
    echo -e "\n[Step 2/2] Skipping User-Level Configuration."
fi

echo -e "\n====================================================="
echo " Setup complete! Restart your shell or run: exec zsh "
echo "====================================================="
