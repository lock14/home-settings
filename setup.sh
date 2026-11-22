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
. "$SCRIPT_DIR/setup/lib/log.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/setup/lib/os.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/setup/lib/symlink.sh"

# Default configurations
export ACTION="install"
export IDE_NAME="none"
export IDE_EXPLICIT=false
export TARGET_OS=""
export DRY_RUN=false
export DB_CHOICE="none"
export SKIP_DB=false

# Granular skip and feature flags
export SKIP_SYSTEM=false
export SKIP_PACKAGES=false
export INSTALL_CHROME=false
export INSTALL_APPS=false
export INSTALL_GHOSTTY=false
export SKIP_USER=false
export SKIP_FONTS=false
export SKIP_TOOLS=false
export SKIP_NVIM=false
export SKIP_VIM=false
export SKIP_ZSH=false
export SKIP_BASH=false
export SKIP_BIN=false
export SKIP_COMPLETIONS=false
export SKIP_TERMINAL=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Modular Cross-Platform Workstation Provisioner & Dotfiles Engine.

Primary Workflows:
  (default)               Full machine setup (native packages + user environment)
  --user                  Configure user dotfiles, utilities, fonts, and tools only (no sudo required)
  --dotfiles-only         Alias for --user (user-space setup without OS package provisioning)
  --system                Full turnkey setup with native packages (alias for default)
  --system-only           Provision OS packages and CLI runtimes only
  --dry-run               Preview actions without modifying the system
  --uninstall             Uninstall all managed dotfiles, fonts, and user binaries

Granular Uninstallation:
  --uninstall-dotfiles    Remove managed dotfile symlinks only
  --uninstall-fonts       Remove MesloLGS Nerd Font Mono fonts only
  --uninstall-bin         Remove symlinked user utilities from ~/.local/bin only

System & Package Options:
  --os <distro>           Target OS override: ubuntu (Debian/apt), fedora (RHEL/dnf), macos (Homebrew)
  --skip-system           Skip OS package updates and system provisioning
  --skip-packages         Skip core system package manager installs

Database Options (Client tools installed by default):
  --db <engine>           Database server engine to install: postgres, mariadb, all, none (default: none)
  --with-postgres, --with-postgresql
                          Install PostgreSQL server & client tools
  --with-mariadb          Install MariaDB server & client tools
  --skip-db               Skip all database client and server installations

GUI & Desktop Options (Optional, disabled by default):
  --with-gui              Install all GUI desktop applications (Chrome, Ghostty, IDE/VS Code)
  --with-ghostty          Install Ghostty terminal emulator
  --skip-ghostty          Skip Ghostty terminal emulator installation
  --with-chrome           Install Google Chrome
  --skip-chrome           Skip Google Chrome installation
  --with-apps             Install desktop apps (VS Code / IDE)
  --skip-apps             Skip desktop apps installation (VS Code / IDE)
  -i, --ide <name>        IDE to install: intellij, intellij-ultimate, code, none (default: none)

User Environment Options:
  --theme <name>          Initial color theme to apply (default: solarized-dark)
  --skip-user             Skip user dotfiles and environment configuration
  --skip-fonts            Skip MesloLGS Nerd Font Mono font installation
  --skip-tools            Skip Mise polyglot toolchain runtime installation
  --skip-nvim             Skip Neovim configuration and plugins
  --skip-vim              Skip fallback Vim configuration (.vimrc)
  --skip-zsh              Skip Zsh dotfiles, Oh-My-Zsh, plugins, and Powerlevel10k
  --skip-bash             Skip Bash configuration and environment variables
  --skip-bin              Skip ~/.local/bin user utilities synchronization
  --skip-completions      Skip CLI tab completions generation
  --skip-terminal         Skip terminal emulator profile configuration (GNOME Terminal & macOS Terminal.app)

General Options:
  -h, --help              Show this help message
EOF
}

require_opt_arg() {
    local flag="$1"
    local val="${2:-}"
    local hint="$3"
    if [ -z "$val" ] || [[ "$val" == -* ]]; then
        echo "Error: $flag requires $hint" >&2
        exit 1
    fi
}

enable_default_apps_unless_explicit() {
    if [ "$IDE_EXPLICIT" = false ]; then
        IDE_NAME="code"
        INSTALL_APPS=true
    elif [ "$IDE_NAME" != "none" ]; then
        INSTALL_APPS=true
    fi
}

merge_db_choice() {
    local engine="$1"
    SKIP_DB=false
    case "$DB_CHOICE" in
        none|"$engine") DB_CHOICE="$engine" ;;
        *) DB_CHOICE="all" ;;
    esac
}

# Parse CLI arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --theme)
            require_opt_arg "--theme" "${2:-}" "a theme name (such as solarized-dark, catppuccin-mocha, nord)"
            export HOME_SETTINGS_THEME="$2"
            shift 2
            ;;
        --theme=*)
            require_opt_arg "--theme" "${1#--theme=}" "a theme name (such as solarized-dark, catppuccin-mocha, nord)"
            export HOME_SETTINGS_THEME="${1#--theme=}"
            shift
            ;;
        --uninstall|--uninstall-dotfiles|--uninstall-fonts|--uninstall-bin)
            ACTION="${1#--}"
            shift
            ;;
        --system|--bootstrap)
            SKIP_SYSTEM=false
            SKIP_USER=false
            shift
            ;;
        --user|--dotfiles-only|--skip-system)
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
            require_opt_arg "--os" "${2:-}" "an argument (such as ubuntu, fedora, or macos)"
            TARGET_OS="$2"
            shift 2
            ;;
        -i|--ide)
            require_opt_arg "$1" "${2:-}" "an argument (such as intellij, intellij-ultimate, code, or none)"
            IDE_NAME="$2"
            IDE_EXPLICIT=true
            if [ "$IDE_NAME" = "none" ]; then
                INSTALL_APPS=false
            else
                INSTALL_APPS=true
            fi
            shift 2
            ;;
        --db)
            require_opt_arg "--db" "${2:-}" "an argument (such as postgres, mariadb, all, or none)"
            DB_CHOICE="$2"
            [ "$DB_CHOICE" = "postgresql" ] && DB_CHOICE="postgres"
            [ "$DB_CHOICE" != "none" ] && SKIP_DB=false
            shift 2
            ;;
        --db=*)
            require_opt_arg "--db" "${1#*=}" "an argument (such as postgres, mariadb, all, or none)"
            DB_CHOICE="${1#*=}"
            [ "$DB_CHOICE" = "postgresql" ] && DB_CHOICE="postgres"
            [ "$DB_CHOICE" != "none" ] && SKIP_DB=false
            shift
            ;;
        --with-postgres|--with-postgresql)
            merge_db_choice "postgres"
            shift
            ;;
        --with-mariadb)
            merge_db_choice "mariadb"
            shift
            ;;
        --skip-db)
            SKIP_DB=true
            DB_CHOICE="none"
            shift
            ;;
        --with-gui)
            INSTALL_CHROME=true
            INSTALL_GHOSTTY=true
            enable_default_apps_unless_explicit
            shift
            ;;
        --with-ghostty)   INSTALL_GHOSTTY=true; shift ;;
        --skip-ghostty)   INSTALL_GHOSTTY=false; shift ;;
        --with-chrome)    INSTALL_CHROME=true; shift ;;
        --skip-chrome)    INSTALL_CHROME=false; shift ;;
        --with-apps)      enable_default_apps_unless_explicit; shift ;;
        --skip-apps)      INSTALL_APPS=false; IDE_NAME="none"; IDE_EXPLICIT=true; shift ;;
        --skip-packages)  SKIP_PACKAGES=true; shift ;;
        --skip-fonts)     SKIP_FONTS=true; shift ;;
        --skip-tools)     SKIP_TOOLS=true; shift ;;
        --skip-nvim)      SKIP_NVIM=true; shift ;;
        --skip-vim)       SKIP_VIM=true; shift ;;
        --skip-zsh)       SKIP_ZSH=true; shift ;;
        --skip-bash)      SKIP_BASH=true; shift ;;
        --skip-bin)       SKIP_BIN=true; shift ;;
        --skip-completions) SKIP_COMPLETIONS=true; shift ;;
        --skip-terminal)  SKIP_TERMINAL=true; shift ;;
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
case "$OS" in
    ubuntu|fedora|macos) ;;
    *)
        echo "Error: Unsupported or unrecognized distribution: '$OS'. Please specify --os ubuntu, --os fedora, or --os macos." >&2
        exit 1
        ;;
esac

ARCH="$(detect_arch)"
export ARCH

# Handle uninstallation actions
if [ "$ACTION" != "install" ]; then
    case "$ACTION" in
        uninstall)          "$SCRIPT_DIR/setup/modules/99-uninstall.sh" all ;;
        uninstall-dotfiles) "$SCRIPT_DIR/setup/modules/99-uninstall.sh" dotfiles ;;
        uninstall-fonts)    "$SCRIPT_DIR/setup/modules/99-uninstall.sh" fonts ;;
        uninstall-bin)      "$SCRIPT_DIR/setup/modules/99-uninstall.sh" bin ;;
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

# Validate Color Theme (if explicitly specified via --theme or HOME_SETTINGS_THEME)
if [ -n "${HOME_SETTINGS_THEME:-}" ]; then
    if [[ "$HOME_SETTINGS_THEME" == -* ]]; then
        echo "Error: Invalid theme name '$HOME_SETTINGS_THEME'" >&2
        exit 1
    fi
    if [ -x "$SCRIPT_DIR/bin/theme" ] && ! "$SCRIPT_DIR/bin/theme" --dry-run --no-live --set="$HOME_SETTINGS_THEME" >/dev/null; then
        exit 1
    fi
fi

echo "====================================================="
echo "       Home-Settings Cross-Platform Setup            "
echo "====================================================="
echo "Target OS : $OS"
echo "Arch      : $ARCH"
echo "IDE Choice: $IDE_NAME"
echo "Database  : Server: $DB_CHOICE (Clients: $([ "$SKIP_DB" = true ] && echo "skipped" || echo "enabled"))"
[ -n "${HOME_SETTINGS_THEME:-}" ] && echo "Theme     : $HOME_SETTINGS_THEME"
[ "$DRY_RUN" = true ] && echo "Mode      : DRY RUN (preview only, no modifications)"
echo "====================================================="

export ELAN_HOME="${ELAN_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/elan}"
prepend_path "$HOME/.local/bin"

# 1. System Provisioning (OS packages, Database, Chrome, Apps)
if [ "$SKIP_SYSTEM" = false ]; then
    echo -e "\n[1/2] Running System-Level Provisioning..."
    "$SCRIPT_DIR/setup/modules/00-packages.sh"
else
    echo -e "\n[1/2] Skipping System-Level Provisioning."
fi

# 2. User-Level Configuration (Dotfiles, Fonts, Tools, Shell, Terminal)
if [ "$SKIP_USER" = false ]; then
    echo -e "\n[2/2] Running User Dotfiles & Environment Setup..."
    "$SCRIPT_DIR/setup/modules/10-dotfiles.sh"
    [ "$SKIP_BIN" = false ] && "$SCRIPT_DIR/setup/modules/20-bin.sh"
    [ "$SKIP_FONTS" = false ] && "$SCRIPT_DIR/setup/modules/30-fonts.sh"
    [ "$SKIP_TOOLS" = false ] && "$SCRIPT_DIR/setup/modules/40-mise.sh"

    # Expose Mise shims and Elan toolchain binaries on PATH for Neovim sync and shell completions
    prepend_path "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims" "$ELAN_HOME/bin"

    [ "$SKIP_NVIM" = false ] && "$SCRIPT_DIR/setup/modules/50-nvim.sh"
    "$SCRIPT_DIR/setup/modules/60-shell.sh"
    [ "$SKIP_TERMINAL" = false ] && "$SCRIPT_DIR/setup/modules/70-terminal.sh"
fi

echo -e "\n====================================================="
echo " Setup complete! Restart your shell or run: exec zsh "
echo "====================================================="
