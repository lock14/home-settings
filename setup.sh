#!/bin/bash
# Master cross-platform setup and dotfiles engine for home-settings.
# Supports Ubuntu 22.04+ / 24.04+ LTS, Fedora 38+ / 40+, and macOS (Apple Silicon & Intel).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"
REPO_URL="https://github.com/lock14/home-settings.git"

# Self-bootstrapping: If piped through curl or run without repository assets, clone and re-exec
if [ ! -d "$SCRIPT_DIR/dotfiles" ]; then
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
        git -C "$TARGET_DIR" pull --rebase origin main 2>/dev/null || true
    fi

    chmod +x "$TARGET_DIR/setup.sh"
    exec "$TARGET_DIR/setup.sh" "$@"
fi

# Default configurations
ACTION="install"
JDK_VERSION="21"
IDE_NAME="none"
TARGET_OS=""
DRY_RUN=false
BOOTSTRAP_MODE=false
DB_CHOICE="none"
SKIP_DB=false

# Granular skip and feature flags
SKIP_SYSTEM=false
SKIP_PACKAGES=false
INSTALL_CHROME=false
INSTALL_APPS=false
SKIP_USER=false
SKIP_FONTS=false
SKIP_TOOLS=false
SKIP_NVIM=false
SKIP_VIM=false
SKIP_ZSH=false
SKIP_BASH=false
SKIP_BIN=false
SKIP_COMPLETIONS=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Cross-Platform Master Setup Engine (Debian/Ubuntu, Fedora/RHEL, macOS).

Execution Modes:
  --bootstrap             Full new machine bootstrap (base packages, shell, tools, dotfiles)
  --dotfiles-only         Configure user dotfiles, fonts, and tools only (no sudo required)
  --system-only           Provision OS packages and CLI runtimes only
  --dry-run               Preview actions without modifying the system

Uninstallation Modes:
  --uninstall             Uninstall all managed dotfiles, fonts, and user binaries
  --uninstall-dotfiles    Remove managed dotfile symlinks only
  --uninstall-fonts       Remove MesloLGS NF fonts only
  --uninstall-bin         Remove symlinked user utilities from ~/.local/bin only

System Options:
  --os <distro>           Target OS override: ubuntu (Debian/apt), fedora (RHEL/dnf), macos (Homebrew)
  -j, --jdk <ver>         Active Java LTS version: 17, 21 (default: 21)
  --skip-system           Skip OS package updates and system provisioning
  --skip-packages         Skip core system package manager installs

Database Options (Optional, client tools installed by default):
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
            TARGET_OS="$2"
            shift 2
            ;;
        -j|--jdk)
            JDK_VERSION="$2"
            shift 2
            ;;
        -i|--ide)
            IDE_NAME="$2"
            INSTALL_APPS=true
            shift 2
            ;;
        --db)
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

# Detect operating system
detect_os() {
    if [ -n "$TARGET_OS" ]; then
        echo "$TARGET_OS"
        return 0
    fi

    if [[ "${OSTYPE:-}" == "darwin"* ]]; then
        echo "macos"
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

    if command -v apt-get &>/dev/null; then
        echo "ubuntu"
    elif command -v dnf &>/dev/null; then
        echo "fedora"
    elif command -v brew &>/dev/null; then
        echo "macos"
    else
        echo "unknown"
    fi
}

OS="$(detect_os)"
if [ "$OS" != "ubuntu" ] && [ "$OS" != "fedora" ] && [ "$OS" != "macos" ]; then
    echo "Error: Unsupported or unrecognized distribution: '$OS'. Please specify --os ubuntu, --os fedora, or --os macos." >&2
    exit 1
fi

# Detect architecture
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "$arch" ;;
    esac
}
ARCH="$(detect_arch)"

uninstall_dotfiles() {
    echo "  Removing managed dotfile symlinks..."
    local dotfiles=(
        "$HOME/.environment-variables"
        "$HOME/.bashrc-addendum"
        "$HOME/.zshrc-addendum"
        "$HOME/.aliases"
        "$HOME/.zsh-aliases"
        "$HOME/.zsh-functions"
        "$HOME/.zsh-completions"
        "$HOME/.p10k.zsh"
        "$HOME/.vimrc"
        "$HOME/.dir-colors/dircolors"
        "${XDG_CONFIG_HOME:-$HOME/.config}/bat/themes/Solarized-Dark-TrueColor.tmTheme"
        "${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml"
    )
    for f in "${dotfiles[@]}"; do
        if [ -L "$f" ]; then
            if [ "$DRY_RUN" = true ]; then
                echo "  [DryRun] rm -f $f"
            else
                rm -f "$f"
            fi
        fi
    done
    local nvim_target="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    if [ -L "$nvim_target" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "  [DryRun] rm -f $nvim_target"
        else
            rm -f "$nvim_target"
        fi
    fi
    echo "  Dotfile symlinks uninstalled."
}

uninstall_bin() {
    echo "  Removing common-bin utilities from $HOME/.local/bin..."
    if [ -d "$HOME/.local/bin" ]; then
        for f in "$SCRIPT_DIR/common-bin"/*; do
            local bin_dest
            bin_dest="$HOME/.local/bin/$(basename "$f")"
            if [ -L "$bin_dest" ]; then
                if [ "$DRY_RUN" = true ]; then
                    echo "  [DryRun] rm -f $bin_dest"
                else
                    rm -f "$bin_dest"
                fi
            fi
        done
    fi
    echo "  User binaries uninstalled."
}

uninstall_fonts() {
    local font_dir
    if [ "$OS" = "macos" ]; then
        font_dir="$HOME/Library/Fonts"
    else
        font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
    fi
    echo "  Removing MesloLGS NF fonts from $font_dir..."
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] rm -f $font_dir/MesloLGS NF*.ttf"
    else
        rm -f "$font_dir/MesloLGS NF"*.ttf 2>/dev/null || true
        if command -v fc-cache >/dev/null 2>&1; then
            fc-cache -f "$font_dir" >/dev/null 2>&1 || true
        fi
    fi
    echo "  MesloLGS NF fonts uninstalled."
}

uninstall_all() {
    echo -e "\nUninstalling all home-settings components..."
    uninstall_dotfiles
    uninstall_bin
    uninstall_fonts
    echo -e "\n====================================================="
    echo " Uninstallation complete! "
    echo "====================================================="
}

# Handle uninstallation actions if requested
if [ "$ACTION" != "install" ]; then
    case "$ACTION" in
        uninstall) uninstall_all ;;
        uninstall-dotfiles) uninstall_dotfiles ;;
        uninstall-fonts) uninstall_fonts ;;
        uninstall-bin) uninstall_bin ;;
    esac
    exit 0
fi

# Validate Java version
normalize_jdk_version() {
    local input="$1"
    local ver="$input"
    ver="${ver#openjdk-}"
    ver="${ver#java-}"
    ver="${ver#temurin-}"
    ver="${ver#1.}"
    ver="${ver%.0}"
    ver="${ver%-jdk}"
    ver="${ver%-openjdk}"
    ver="${ver%-devel}"

    case "$ver" in
        17|21|25) echo "$ver" ;;
        8|11) echo "eol" ;;
        *) echo "unsupported" ;;
    esac
}

JDK_CLEAN="$(normalize_jdk_version "$JDK_VERSION")"
if [ "$JDK_CLEAN" = "eol" ]; then
    echo "Error: JDK version '$JDK_VERSION' is End-of-Life (EOL). Only actively supported LTS versions (17, 21) are supported." >&2
    exit 1
elif [ "$JDK_CLEAN" = "unsupported" ]; then
    echo "Error: '$JDK_VERSION' is not a supported Java LTS version. Choose from: 17, 21" >&2
    exit 1
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
echo "JDK Choice: OpenJDK / Temurin $JDK_CLEAN (LTS)"
echo "IDE Choice: $IDE_NAME"
echo "Database  : Server: $DB_CHOICE (Clients: $([ "$SKIP_DB" = true ] && echo "skipped" || echo "enabled"))"
if [ "$BOOTSTRAP_MODE" = true ]; then
    echo "Mode      : BOOTSTRAP (Full turnkey machine setup)"
fi
if [ "$DRY_RUN" = true ]; then
    echo "Mode      : DRY RUN (preview only, no modifications)"
fi
echo "====================================================="

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] $*"
    else
        "$@"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. System Provisioning (OS packages, Database, Chrome, Apps)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$SKIP_SYSTEM" = false ]; then
    echo -e "\n[1/2] Running System-Level Provisioning..."

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
                fi
                ;;
            macos)
                if ! command -v brew &>/dev/null; then
                    echo "  Homebrew not found. Installing Homebrew..."
                    if [ "$DRY_RUN" = false ]; then
                        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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
                    sudo dnf -y install fedora-workstation-repositories 2>/dev/null || true
                    sudo dnf config-manager setopt google-chrome.enabled=1 2>/dev/null || \
                    sudo dnf config-manager --enable google-chrome 2>/dev/null || true
                    sudo dnf -y install google-chrome-stable 2>/dev/null || true
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
                    # IDE
                    if [ "$IDE_NAME" != "none" ]; then
                        case "$IDE_NAME" in
                            intellij) run_cmd sudo snap install intellij-idea-community --classic ;;
                            intellij-ultimate) run_cmd sudo snap install intellij-idea-ultimate --classic ;;
                            code) run_cmd sudo snap install code --classic ;;
                        esac
                    else
                        # Default editor application when --with-apps is passed without explicit --ide
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
                    # Default editor application when --with-apps is passed without explicit --ide
                    run_cmd brew install --cask visual-studio-code
                fi
                ;;
        esac
    fi
else
    echo -e "\n[1/2] Skipping System-Level Provisioning."
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. User-Level Configuration (Dotfiles, Fonts, Tools, Shell)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$SKIP_USER" = false ]; then
    echo -e "\n[2/2] Running User Dotfiles & Environment Setup..."

    mkdir -p "$HOME/.local/bin"

    # 1. Atomic Dotfile Symlinking
    DOTFILES_DIR="$SCRIPT_DIR/dotfiles"
    echo "  Symlinking dotfiles from $DOTFILES_DIR to $HOME..."
    DOTFILES=(
        ".environment-variables"
        ".bashrc-addendum"
        ".zshrc-addendum"
        ".aliases"
        ".zsh-functions"
        ".zsh-completions"
        ".p10k.zsh"
        ".vimrc"
    )
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] Symlinking ${DOTFILES[*]}, .zsh-aliases, .dir-colors/dircolors"
    else
        for df in "${DOTFILES[@]}"; do
            ln -sf "$DOTFILES_DIR/$df" "$HOME/$df"
        done
        ln -sf "$HOME/.aliases" "$HOME/.zsh-aliases"
        mkdir -p "$HOME/.dir-colors"
        ln -sf "$DOTFILES_DIR/.dir-colors/dircolors" "$HOME/.dir-colors/dircolors"
    fi

    # 2. User Binaries Symlinks
    if [ "$SKIP_BIN" = false ]; then
        echo "  Symlinking common-bin utilities to ~/.local/bin..."
        if [ "$DRY_RUN" = true ]; then
            echo "  [DryRun] Symlinking common-bin/* into $HOME/.local/bin"
        else
            for f in "$SCRIPT_DIR/common-bin"/*; do
                if [ -f "$f" ]; then
                    chmod +x "$f"
                    ln -sf "$f" "$HOME/.local/bin/$(basename "$f")"
                fi
            done
            # Compatibility shims for Debian-family tool naming
            if [ ! -e "$HOME/.local/bin/fd" ] && command -v fdfind >/dev/null 2>&1; then
                ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
            fi
            if [ ! -e "$HOME/.local/bin/bat" ] && command -v batcat >/dev/null 2>&1; then
                ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
            fi
        fi
    fi

    # 3. Fonts (MesloLGS NF)
    if [ "$SKIP_FONTS" = false ]; then
        if [ "$OS" = "macos" ]; then
            FONT_DIR="$HOME/Library/Fonts"
        else
            FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
        fi
        echo "  Installing MesloLGS NF fonts into $FONT_DIR..."
        if [ "$DRY_RUN" = true ]; then
            echo "  [DryRun] Downloading MesloLGS NF (Regular, Bold, Italic, Bold Italic) to $FONT_DIR"
        else
            mkdir -p "$FONT_DIR"
            BASE_FONT_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
            FONTS=(
                "MesloLGS NF Regular.ttf"
                "MesloLGS NF Bold.ttf"
                "MesloLGS NF Italic.ttf"
                "MesloLGS NF Bold Italic.ttf"
            )
            for font in "${FONTS[@]}"; do
                target="$FONT_DIR/$font"
                if [ ! -s "$target" ]; then
                    encoded_font="${font// /%20}"
                    curl -fsSL "$BASE_FONT_URL/$encoded_font" -o "$target" &
                fi
            done
            wait
            if command -v fc-cache &>/dev/null; then
                fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
            fi
        fi
    fi

    # 4. Mise Polyglot Toolchain Manager
    if [ "$SKIP_TOOLS" = false ]; then
        echo "  Configuring Mise runtime manager (Java $JDK_CLEAN, Go, Terraform)..."
        if [ "$DRY_RUN" = true ]; then
            echo "  [DryRun] Installing mise and provisioning runtimes from .mise.toml"
        else
            if ! command -v mise &>/dev/null && [ ! -x "$HOME/.local/bin/mise" ]; then
                echo "  Installing standalone mise binary..."
                curl -fsSL https://mise.run | sh
            fi
            MISE_BIN="$(command -v mise || echo "$HOME/.local/bin/mise")"
            if [ -x "$MISE_BIN" ]; then
                # Link repository config into XDG config if not present
                mise_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mise"
                mkdir -p "$mise_config_dir"
                if [ -f "$SCRIPT_DIR/.mise.toml" ]; then
                    ln -sf "$SCRIPT_DIR/.mise.toml" "$mise_config_dir/config.toml"
                    "$MISE_BIN" trust "$SCRIPT_DIR/.mise.toml" >/dev/null 2>&1 || true
                    "$MISE_BIN" trust "$mise_config_dir/config.toml" >/dev/null 2>&1 || true
                fi
                # Install runtimes
                echo "  Installing Mise toolchains from .mise.toml..."
                "$MISE_BIN" install -y || true
                if [ -d "$HOME/.local/share/mise/shims" ]; then
                    export PATH="$HOME/.local/share/mise/shims:$PATH"
                fi
            fi
        fi
    fi

    # 5. Neovim Configuration (init.lua)
    if [ "$SKIP_NVIM" = false ]; then
        echo "  Configuring Neovim (init.lua)..."
        nvim_target="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
        if [ "$DRY_RUN" = true ]; then
            echo "  [DryRun] Symlinking dotfiles/.config/nvim to $nvim_target"
        else
            mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}"
            if [ -d "$nvim_target" ] && [ ! -L "$nvim_target" ]; then
                bak="${nvim_target}.bak.$(date +%s)"
                echo "  Backing up pre-existing Neovim directory to $bak"
                mv "$nvim_target" "$bak"
            fi
            if [ -d "$DOTFILES_DIR/.config/nvim" ]; then
                ln -sfn "$DOTFILES_DIR/.config/nvim" "$nvim_target"
            fi
        fi
    fi

    # 6. Bat TrueColor Syntax Highlighting Theme
    BAT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bat"
    echo "  Configuring Bat TrueColor theme..."
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] Deploying Solarized-Dark-TrueColor.tmTheme to $BAT_CONFIG_DIR/themes/ and building bat cache"
    else
        mkdir -p "$BAT_CONFIG_DIR/themes"
        if [ -f "$SCRIPT_DIR/colors/Solarized-Dark-TrueColor.tmTheme" ]; then
            ln -sf "$SCRIPT_DIR/colors/Solarized-Dark-TrueColor.tmTheme" "$BAT_CONFIG_DIR/themes/Solarized-Dark-TrueColor.tmTheme"
        fi
        if command -v bat >/dev/null 2>&1; then
            bat cache --clear >/dev/null 2>&1 || true
            bat cache --build >/dev/null 2>&1 || true
        elif command -v batcat >/dev/null 2>&1; then
            batcat cache --clear >/dev/null 2>&1 || true
            batcat cache --build >/dev/null 2>&1 || true
        fi
    fi

    # 7. Legacy Vim Configuration & Plugins
    if [ "$SKIP_VIM" = false ]; then
        echo "  Configuring Vim plugins..."
        if [ "$DRY_RUN" = true ]; then
            echo "  [DryRun] Setting up Vim configuration and Pathogen bundles (solarized, auto-pairs, ultisnips, supertab, vim-snippets)"
        else
            mkdir -p "$HOME/.vim/autoload" "$HOME/.vim/bundle"
            if [ ! -f "$HOME/.vim/autoload/pathogen.vim" ]; then
                curl -LSso "$HOME/.vim/autoload/pathogen.vim" https://tpo.pe/pathogen.vim 2>/dev/null || true
            fi

            clone_bundle() {
                local repo="$1"
                local dest="$2"
                if [ -d "$dest/.git" ]; then
                    git -C "$dest" pull --ff-only 2>/dev/null || true
                else
                    if [ -d "$dest" ]; then
                        rm -rf "$dest"
                    fi
                    git clone --depth=1 "$repo" "$dest" 2>/dev/null || true
                fi
            }

            clone_bundle "https://github.com/altercation/vim-colors-solarized.git" "$HOME/.vim/bundle/vim-colors-solarized" &
            clone_bundle "https://github.com/jiangmiao/auto-pairs.git" "$HOME/.vim/bundle/auto-pairs" &
            clone_bundle "https://github.com/SirVer/ultisnips.git" "$HOME/.vim/bundle/ultisnips" &
            clone_bundle "https://github.com/ervandew/supertab.git" "$HOME/.vim/bundle/supertab" &
            clone_bundle "https://github.com/honza/vim-snippets.git" "$HOME/.vim/bundle/vim-snippets" &
            wait
        fi
    fi

    # 8. Zsh, Oh-My-Zsh & Powerlevel10k
    if [ "$SKIP_ZSH" = false ]; then
        echo "  Configuring Zsh, Oh-My-Zsh, plugins, and Powerlevel10k..."
        if [ "$DRY_RUN" = true ]; then
            echo "  [DryRun] Installing Oh-My-Zsh, Powerlevel10k, zsh-autosuggestions, syntax-highlighting, and completions"
        else
            ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
            if [ ! -d "$ZSH_DIR" ]; then
                RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended 2>/dev/null || true
            fi

            ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
            mkdir -p "$ZSH_CUSTOM_DIR/themes" "$ZSH_CUSTOM_DIR/plugins"

            clone_zsh() {
                local repo="$1"
                local dest="$2"
                if [ -d "$dest/.git" ]; then
                    git -C "$dest" pull --ff-only 2>/dev/null || true
                else
                    if [ -d "$dest" ]; then
                        rm -rf "$dest"
                    fi
                    git clone --depth=1 "$repo" "$dest" 2>/dev/null || true
                fi
            }

            clone_zsh "https://github.com/romkatv/powerlevel10k.git" "$ZSH_CUSTOM_DIR/themes/powerlevel10k" &
            clone_zsh "https://github.com/zsh-users/zsh-autosuggestions.git" "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" &
            clone_zsh "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" &
            clone_zsh "https://github.com/zsh-users/zsh-completions.git" "$ZSH_CUSTOM_DIR/plugins/zsh-completions" &
            clone_zsh "https://github.com/unixorn/fzf-zsh-plugin.git" "$ZSH_CUSTOM_DIR/plugins/fzf-zsh-plugin" &
            wait

            if [ -f "$HOME/.zshrc" ]; then
                if [ "$OS" = "macos" ]; then
                    sed -i '' 's|ZSH_THEME="robbyrussell"|ZSH_THEME="powerlevel10k/powerlevel10k"|g' "$HOME/.zshrc" 2>/dev/null || true
                else
                    sed -i 's|ZSH_THEME="robbyrussell"|ZSH_THEME="powerlevel10k/powerlevel10k"|g' "$HOME/.zshrc" 2>/dev/null || true
                fi
                grep -qxF '[ -f ~/.zshrc-addendum ] && source ~/.zshrc-addendum' "$HOME/.zshrc" 2>/dev/null || \
                    printf '\n# home-settings\n[ -f ~/.zshrc-addendum ] && source ~/.zshrc-addendum\n' >> "$HOME/.zshrc"
            fi
        fi
    fi

    # 9. Bash Configuration
    if [ "$SKIP_BASH" = false ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "  [DryRun] Adding source ~/.bashrc-addendum to ~/.bashrc"
        else
            if [ -f "$HOME/.bashrc" ]; then
                grep -qxF '[ -f ~/.bashrc-addendum ] && source ~/.bashrc-addendum' "$HOME/.bashrc" 2>/dev/null || \
                    printf '\n# home-settings\n[ -f ~/.bashrc-addendum ] && source ~/.bashrc-addendum\n' >> "$HOME/.bashrc"
            fi
        fi
    fi

    # 10. CLI Completions (gh, kubectl, helm)
    if [ "$SKIP_COMPLETIONS" = false ]; then
        COMPLETIONS_DIR="$HOME/.zsh/completions"
        if [ "$DRY_RUN" = true ]; then
            echo "  [DryRun] Generating CLI tab completions in $COMPLETIONS_DIR"
        else
            mkdir -p "$COMPLETIONS_DIR"
            if command -v gh &>/dev/null; then gh completion -s zsh > "$COMPLETIONS_DIR/_gh" 2>/dev/null || true; fi
            if command -v kubectl &>/dev/null; then kubectl completion zsh > "$COMPLETIONS_DIR/_kubectl" 2>/dev/null || true; fi
            if command -v helm &>/dev/null; then helm completion zsh > "$COMPLETIONS_DIR/_helm" 2>/dev/null || true; fi
        fi
    fi

    # 11. Default Login Shell
    CURRENT_SHELL="$(getent passwd "${USER:-$(whoami)}" 2>/dev/null | cut -d: -f7 || echo "${SHELL:-}")"
    ZSH_BIN="$(command -v zsh 2>/dev/null || true)"
    if [ -n "$ZSH_BIN" ] && [ "$CURRENT_SHELL" != "$ZSH_BIN" ] && [ -t 0 ] && command -v chsh &>/dev/null; then
        echo "  Changing default login shell to Zsh ($ZSH_BIN)..."
        if [ "$DRY_RUN" = true ]; then
            echo "  [DryRun] chsh -s $ZSH_BIN"
        else
            chsh -s "$ZSH_BIN" 2>/dev/null || true
        fi
    fi
fi

echo -e "\n====================================================="
echo " Setup complete! Restart your shell or run: exec zsh "
echo "====================================================="
