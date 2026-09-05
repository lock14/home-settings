#!/bin/bash
# Stage 00: Native package management, database servers, and desktop applications.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# Source helper libraries
# shellcheck source=/dev/null
. "$REPO_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/os.sh"

OS="${OS:-$(detect_os)}"
ARCH="${ARCH:-$(detect_arch)}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_PACKAGES="${SKIP_PACKAGES:-false}"
SKIP_DB="${SKIP_DB:-false}"
DB_CHOICE="${DB_CHOICE:-none}"
INSTALL_CHROME="${INSTALL_CHROME:-false}"
INSTALL_APPS="${INSTALL_APPS:-false}"
IDE_NAME="${IDE_NAME:-none}"

if [ "$SKIP_PACKAGES" = false ]; then
    echo "  Installing core system packages for $OS..."
    case "$OS" in
        ubuntu)
            pkgs="git curl wget vim neovim zsh fzf fontconfig dconf-cli shellcheck command-not-found bat fd-find ripgrep zoxide tree"
            if [ "$SKIP_DB" = false ]; then
                pkgs="$pkgs postgresql-client mariadb-client"
            fi
            run_cmd sudo apt-get update -y
            # shellcheck disable=SC2086
            run_cmd sudo apt-get install -y $pkgs
            ;;
        fedora)
            pkgs="git curl wget vim neovim zsh fzf fontconfig dconf snapd util-linux-user bat fd-find ripgrep zoxide eza tree"
            if [ "$SKIP_DB" = false ]; then
                pkgs="$pkgs postgresql mariadb"
            fi
            run_cmd sudo dnf makecache
            # shellcheck disable=SC2086
            run_cmd sudo dnf -y install $pkgs
            if [ "$DRY_RUN" = true ]; then
                echo "  [DryRun] sudo ln -sf /var/lib/snapd/snap /snap"
            else
                sudo ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
                if command -v systemctl >/dev/null 2>&1; then
                    sudo systemctl enable --now snapd.socket 2>/dev/null || true
                fi
            fi
            ;;
        macos)
            if ! command -v brew &>/dev/null; then
                echo "  Homebrew not found. Installing Homebrew..."
                if [ "$DRY_RUN" = false ]; then
                    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                    if [ -x "/opt/homebrew/bin/brew" ]; then
                        eval "$(/opt/homebrew/bin/brew shellenv)"
                    elif [ -x "/usr/local/bin/brew" ]; then
                        eval "$(/usr/local/bin/brew shellenv)"
                    fi
                fi
            fi
            pkgs="git curl wget vim neovim zsh fzf fontconfig shellcheck bat fd ripgrep zoxide eza tree"
            if [ "$SKIP_DB" = false ]; then
                pkgs="$pkgs libpq"
            fi
            # shellcheck disable=SC2086
            run_cmd brew install $pkgs
            ;;
    esac
fi

# Database Server Provisioning (Opt-in)
if [ "$SKIP_DB" = false ] && [ "$DB_CHOICE" != "none" ]; then
    echo "  Provisioning database server ($DB_CHOICE) on $OS..."
    case "$OS" in
        ubuntu)
            if [ "$DB_CHOICE" = "postgres" ] || [ "$DB_CHOICE" = "all" ]; then
                run_cmd sudo apt-get install -y postgresql postgresql-contrib
            fi
            if [ "$DB_CHOICE" = "mariadb" ] || [ "$DB_CHOICE" = "all" ]; then
                run_cmd sudo apt-get install -y mariadb-server mariadb-client
            fi
            ;;
        fedora)
            if [ "$DB_CHOICE" = "postgres" ] || [ "$DB_CHOICE" = "all" ]; then
                run_cmd sudo dnf -y install postgresql-server postgresql-contrib
            fi
            if [ "$DB_CHOICE" = "mariadb" ] || [ "$DB_CHOICE" = "all" ]; then
                run_cmd sudo dnf -y install mariadb-server mariadb
            fi
            ;;
        macos)
            if [ "$DB_CHOICE" = "postgres" ] || [ "$DB_CHOICE" = "all" ]; then
                run_cmd brew install postgresql@16
            fi
            if [ "$DB_CHOICE" = "mariadb" ] || [ "$DB_CHOICE" = "all" ]; then
                run_cmd brew install mariadb
            fi
            ;;
    esac
fi

# Google Chrome installation (Opt-in)
if [ "$INSTALL_CHROME" = true ]; then
    echo "  Installing Google Chrome on $OS..."
    case "$OS" in
        ubuntu)
            if [ "$ARCH" = "amd64" ]; then
                CHROME_DEB="/tmp/google-chrome-stable_current_amd64.deb"
                if [ "$DRY_RUN" = true ]; then
                    echo "  [DryRun] wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O $CHROME_DEB"
                    echo "  [DryRun] sudo apt-get install -y $CHROME_DEB"
                else
                    wget -q "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" -O "$CHROME_DEB"
                    sudo apt-get install -y "$CHROME_DEB" || sudo dpkg -i "$CHROME_DEB"
                    rm -f "$CHROME_DEB"
                fi
            else
                echo "  Notice: Google Chrome official deb is amd64 only (current: $ARCH). Skipping."
            fi
            ;;
        fedora)
            if [ "$DRY_RUN" = true ]; then
                echo "  [DryRun] sudo dnf -y install fedora-workstation-repositories"
                echo "  [DryRun] sudo dnf config-manager enable google-chrome"
                echo "  [DryRun] sudo dnf -y install google-chrome-stable"
            else
                sudo dnf -y install fedora-workstation-repositories || true
                sudo dnf config-manager setopt google-chrome.enabled=1 || \
                sudo dnf config-manager --enable google-chrome || true
                sudo dnf -y install google-chrome-stable || true
            fi
            ;;
        macos)
            run_cmd brew install --cask google-chrome
            ;;
    esac
fi

# Desktop applications (Opt-in)
if [ "$INSTALL_APPS" = true ]; then
    echo "  Installing developer desktop applications..."
    case "$OS" in
        ubuntu|fedora)
            if command -v snap &>/dev/null || [ "$DRY_RUN" = true ]; then
                if [ "$IDE_NAME" != "none" ]; then
                    case "$IDE_NAME" in
                        intellij) run_cmd sudo snap install intellij-idea-community --classic ;;
                        intellij-ultimate) run_cmd sudo snap install intellij-idea-ultimate --classic ;;
                        code) run_cmd sudo snap install code --classic ;;
                    esac
                else
                    run_cmd sudo snap install code --classic
                fi
            else
                echo "  Notice: snap command not found. Skipping Snap applications."
            fi
            ;;
        macos)
            if [ "$IDE_NAME" != "none" ]; then
                case "$IDE_NAME" in
                    intellij) run_cmd brew install --cask intellij-idea-ce ;;
                    intellij-ultimate) run_cmd brew install --cask intellij-idea ;;
                    code) run_cmd brew install --cask visual-studio-code ;;
                esac
            else
                run_cmd brew install --cask visual-studio-code
            fi
            ;;
    esac
fi

# Ghostty terminal emulator installation (Opt-in)
if [ "${INSTALL_GHOSTTY:-false}" = true ]; then
    echo "  Installing Ghostty terminal emulator on $OS..."
    case "$OS" in
        macos)
            run_cmd brew install --cask ghostty
            ;;
        ubuntu)
            if command -v snap &>/dev/null || [ "$DRY_RUN" = true ]; then
                run_cmd sudo snap install ghostty --classic
            else
                echo "  Notice: snap command not found. Skipping Ghostty install."
            fi
            ;;
        fedora)
            if [ "$DRY_RUN" = true ]; then
                echo "  [DryRun] sudo dnf -y copr enable scottames/ghostty"
                echo "  [DryRun] sudo dnf -y install ghostty"
            else
                sudo dnf -y copr enable scottames/ghostty || true
                sudo dnf -y install ghostty || true
            fi
            ;;
    esac
fi
