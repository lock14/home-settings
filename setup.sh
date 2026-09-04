#!/bin/bash
# Master modular setup and dotfiles engine for home-settings.
# Supports Ubuntu 22.04+ / 24.04+ LTS, Fedora 38+ / 40+, and macOS (Apple Silicon & Intel).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"
REPO_URL="https://github.com/lock14/home-settings.git"

# Self-bootstrapping: If piped through curl or run without repository assets, clone and re-exec
if [ ! -d "$SCRIPT_DIR/dotfiles" ] || [ ! -f "$SCRIPT_DIR/.mise.toml" ]; then
    TARGET_DIR="$HOME/home-settings"
    echo "====================================================="
    echo "       home-settings Master Setup & Provisioner      "
    echo "====================================================="

    if ! command -v git >/dev/null 2>&1; then
        echo "  Git not found. Installing git prerequisite..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -y && sudo apt-get install -y git curl
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf -y install git curl
        elif command -v brew >/dev/null 2>&1; then
            brew install git curl
        else
            echo "Error: git is required to clone home-settings." >&2
            exit 1
        fi
    fi

    if [ ! -d "$TARGET_DIR" ]; then
        echo "  Cloning repository to $TARGET_DIR..."
        git clone "$REPO_URL" "$TARGET_DIR"
    else
        echo "  Updating repository at $TARGET_DIR..."
        git -C "$TARGET_DIR" pull --rebase origin main || true
    fi

    chmod +x "$TARGET_DIR/setup.sh"
    exec "$TARGET_DIR/setup.sh" "$@"
fi

# Source shared helper libraries
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/os.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/symlink.sh"

# Default configurations
export ACTION="install"
export IDE_NAME="none"
export TARGET_OS=""
export DRY_RUN=false
export BOOTSTRAP_MODE=false
export DB_CHOICE="none"
export SKIP_DB=false

# Granular skip and feature flags
export SKIP_SYSTEM=false
export SKIP_PACKAGES=false
export INSTALL_CHROME=false
export INSTALL_APPS=false
export SKIP_USER=false
export SKIP_FONTS=false
export SKIP_TOOLS=false
export SKIP_NVIM=false
export SKIP_VIM=false
export SKIP_ZSH=false
export SKIP_BASH=false
export SKIP_BIN=false
export SKIP_COMPLETIONS=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Modular Cross-Platform Workstation Provisioner & Dotfiles Engine.

Primary Workflows:
  (default)               User-space setup (dotfiles, bin, fonts, tools, shell) [No sudo]
  --system                Full turnkey setup (native OS packages + user environment)
  --bootstrap             Full new machine bootstrap (base packages, shell, tools, dotfiles)
  --dotfiles-only         Configure user dotfiles, fonts, and tools only (alias for default)
  --system-only           Provision OS packages and CLI runtimes only
  --dry-run               Preview actions without modifying the system
  --uninstall             Uninstall all managed dotfiles, fonts, and user binaries

Granular Uninstallation:
  --uninstall-dotfiles    Remove managed dotfile symlinks only
  --uninstall-fonts       Remove MesloLGS NF fonts only
  --uninstall-bin         Remove symlinked user utilities from ~/.local/bin only

System & Package Options:
  --os <distro>           Target OS override: ubuntu (Debian/apt), fedora (RHEL/dnf), macos (Homebrew)
  --skip-system           Skip OS package updates and system provisioning
  --skip-packages         Skip core system package manager installs

Database Options (Client tools installed by default):
  --db <engine>           Database server engine to install: postgres, mariadb, all, none (default: none)
  --with-postgres         Install PostgreSQL server & client tools
  --with-mariadb          Install MariaDB server & client tools
  --skip-db               Skip all database client and server installations

GUI & Desktop Options (Optional, disabled by default):
  --with-gui              Install all GUI desktop applications (Chrome, IDE/VS Code)
  --with-chrome           Install Google Chrome
  --with-apps             Install desktop apps (VS Code / IDE)
  -i, --ide <name>        IDE to install: intellij, intellij-ultimate, code, none (default: none)

User Environment Options:
  --skip-user             Skip user dotfiles and environment configuration
  --skip-fonts            Skip MesloLGS NF font installation
  --skip-tools            Skip Mise polyglot toolchain runtime installation
  --skip-nvim             Skip Neovim configuration and plugins
  --skip-vim              Skip Vim configuration and plugins
  --skip-zsh              Skip Zsh dotfiles, Oh-My-Zsh, plugins, and Powerlevel10k
  --skip-bash             Skip Bash configuration and environment variables
  --skip-bin              Skip ~/.local/bin user utilities synchronization
  --skip-completions      Skip CLI tab completions generation

General Options:
  -h, --help              Show this help message
EOF
}

# Parse CLI arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall)
            ACTION="uninstall"
            shift
            ;;
        --uninstall-dotfiles)
            ACTION="uninstall-dotfiles"
            shift
            ;;
        --uninstall-fonts)
            ACTION="uninstall-fonts"
            shift
            ;;
        --uninstall-bin)
            ACTION="uninstall-bin"
            shift
            ;;
        --bootstrap)
            BOOTSTRAP_MODE=true
            shift
            ;;
        --system)
            SKIP_SYSTEM=false
            SKIP_USER=false
            shift
            ;;
        --dotfiles-only|--skip-system)
            SKIP_SYSTEM=true
            shift
            ;;
        --system-only|--skip-user)
            SKIP_USER=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --os)
            if [ $# -lt 2 ]; then
                echo "Error: --os requires an argument (e.g. ubuntu, fedora, macos)" >&2
                exit 1
            fi
            TARGET_OS="$2"
            shift 2
            ;;
        -i|--ide)
            if [ $# -lt 2 ]; then
                echo "Error: $1 requires an argument (e.g. intellij, intellij-ultimate, code, none)" >&2
                exit 1
            fi
            IDE_NAME="$2"
            INSTALL_APPS=true
            shift 2
            ;;
        --db)
            if [ $# -lt 2 ]; then
                echo "Error: --db requires an argument (e.g. postgres, mariadb, all, none)" >&2
                exit 1
            fi
            DB_CHOICE="$2"
            shift 2
            ;;
        --with-postgres|--with-postgresql)
            DB_CHOICE="postgres"
            shift
            ;;
        --with-mariadb)
            DB_CHOICE="mariadb"
            shift
            ;;
        --skip-db)
            SKIP_DB=true
            DB_CHOICE="none"
            shift
            ;;
        --with-gui)
            INSTALL_CHROME=true
            INSTALL_APPS=true
            shift
            ;;
        --with-chrome)
            INSTALL_CHROME=true
            shift
            ;;
        --with-apps)
            INSTALL_APPS=true
            shift
            ;;
        --skip-chrome)
            INSTALL_CHROME=false
            shift
            ;;
        --skip-apps)
            INSTALL_APPS=false
            shift
            ;;
        --skip-packages)
            SKIP_PACKAGES=true
            shift
            ;;
        --skip-fonts)
            SKIP_FONTS=true
            shift
            ;;
        --skip-tools)
            SKIP_TOOLS=true
            shift
            ;;
        --skip-nvim)
            SKIP_NVIM=true
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
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

OS="$(detect_os)"
export OS
if [ "$OS" != "ubuntu" ] && [ "$OS" != "fedora" ] && [ "$OS" != "macos" ]; then
    echo "Error: Unsupported or unrecognized distribution: '$OS'. Please specify --os ubuntu, --os fedora, or --os macos." >&2
    exit 1
fi

ARCH="$(detect_arch)"
export ARCH

# Handle uninstallation actions
if [ "$ACTION" != "install" ]; then
    case "$ACTION" in
        uninstall)
            "$SCRIPT_DIR/modules/99-uninstall.sh" all
            ;;
        uninstall-dotfiles)
            "$SCRIPT_DIR/modules/99-uninstall.sh" dotfiles
            ;;
        uninstall-fonts)
            "$SCRIPT_DIR/modules/99-uninstall.sh" fonts
            ;;
        uninstall-bin)
            "$SCRIPT_DIR/modules/99-uninstall.sh" bin
            ;;
    esac
    exit 0
fi

# Validate IDE
case "$IDE_NAME" in
    intellij|intellij-ultimate|code|none) ;;
    *)
        echo "Error: '$IDE_NAME' is not a supported IDE. Choose from: intellij, intellij-ultimate, code, none" >&2
        exit 1
        ;;
esac

# Validate Database Engine
case "$DB_CHOICE" in
    postgres|postgresql) DB_CHOICE="postgres" ;;
    mariadb|all|none) ;;
    *)
        echo "Error: '$DB_CHOICE' is not a supported database engine. Choose from: postgres, mariadb, all, none" >&2
        exit 1
        ;;
esac

echo "====================================================="
echo "       Home-Settings Cross-Platform Setup            "
echo "====================================================="
echo "Target OS : $OS"
echo "Arch      : $ARCH"
echo "IDE Choice: $IDE_NAME"
echo "Database  : Server: $DB_CHOICE (Clients: $([ "$SKIP_DB" = true ] && echo "skipped" || echo "enabled"))"
if [ "$BOOTSTRAP_MODE" = true ]; then
    echo "Mode      : BOOTSTRAP (Full turnkey machine setup)"
fi
if [ "$DRY_RUN" = true ]; then
    echo "Mode      : DRY RUN (preview only, no modifications)"
fi
echo "====================================================="
export PATH="$HOME/.local/bin:$PATH"

# ─────────────────────────────────────────────────────────────────────────────
# 1. System Provisioning (OS packages, Database, Chrome, Apps)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$SKIP_SYSTEM" = false ]; then
    echo -e "\n[1/2] Running System-Level Provisioning..."
    "$SCRIPT_DIR/modules/00-packages.sh"
else
    echo -e "\n[1/2] Skipping System-Level Provisioning."
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. User-Level Configuration (Dotfiles, Fonts, Tools, Shell, Vim)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$SKIP_USER" = false ]; then
    echo -e "\n[2/2] Running User Dotfiles & Environment Setup..."

    # Dotfiles auto-discovery and linking
    "$SCRIPT_DIR/modules/10-dotfiles.sh"

    # User binaries
    if [ "$SKIP_BIN" = false ]; then
        "$SCRIPT_DIR/modules/20-bin.sh"
    fi

    # Fonts
    if [ "$SKIP_FONTS" = false ]; then
        "$SCRIPT_DIR/modules/30-fonts.sh"
    fi

    # Mise polyglot toolchains
    if [ "$SKIP_TOOLS" = false ]; then
        "$SCRIPT_DIR/modules/40-mise.sh"
    fi

    # Legacy Vim plugins (provisions honza/vim-snippets, solarized, auto-pairs, ultisnips, supertab)
    if [ "$SKIP_VIM" = false ]; then
        "$SCRIPT_DIR/modules/50-vim.sh"
    fi

    # Shell environment (Zsh, Bash, Completions)
    "$SCRIPT_DIR/modules/60-shell.sh"
fi

echo -e "\n====================================================="
echo " Setup complete! Restart your shell or run: exec zsh "
echo "====================================================="
