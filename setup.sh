#!/bin/bash
# Master cross-platform setup and dotfiles engine for home-settings.
# Supports Ubuntu 22.04+ / 24.04+ LTS, Fedora 38+ / 40+, and macOS (Apple Silicon & Intel).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configurations
JDK_VERSION="21"
IDE_NAME="none"
TARGET_OS=""
DRY_RUN=false
BOOTSTRAP_MODE=false

# Granular skip and feature flags
SKIP_SYSTEM=false
SKIP_PACKAGES=false
INSTALL_CHROME=false
INSTALL_APPS=false
SKIP_USER=false
SKIP_FONTS=false
SKIP_TOOLS=false
SKIP_VIM=false
SKIP_ZSH=false
SKIP_BASH=false
SKIP_BIN=false
SKIP_COMPLETIONS=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Cross-Platform Master Setup Engine (Ubuntu, Fedora, macOS).

Execution Modes:
  --bootstrap             Full new machine bootstrap (base packages, shell, tools, dotfiles)
  --dotfiles-only         Configure user dotfiles, fonts, and tools only (no sudo required)
  --system-only           Provision OS packages and CLI runtimes only
  --dry-run               Preview actions without modifying the system

System Options:
  --os <distro>           Target OS override: ubuntu, fedora, macos (auto-detected by default)
  -j, --jdk <ver>         Active Java LTS version: 17, 21 (default: 21)
  --skip-system           Skip OS package updates and system provisioning
  --skip-packages         Skip core system package manager installs

GUI & Desktop Options (Optional, disabled by default):
  --with-gui              Install all GUI desktop applications (Chrome, IDE/VS Code)
  --with-chrome           Install Google Chrome
  --with-apps             Install desktop apps (VS Code / IDE)
  -i, --ide <name>        IDE to install: intellij, intellij-ultimate, code, none (default: none)

User Environment Options:
  --skip-user             Skip user dotfiles and environment configuration
  --skip-fonts            Skip MesloLGS NF font installation
  --skip-tools            Skip Mise polyglot toolchain runtime installation
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

echo "====================================================="
echo "       Home-Settings Cross-Platform Setup            "
echo "====================================================="
echo "Target OS : $OS"
echo "Arch      : $ARCH"
echo "JDK Choice: OpenJDK / Temurin $JDK_CLEAN (LTS)"
echo "IDE Choice: $IDE_NAME"
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
# 1. System Provisioning (OS packages, Chrome, Apps)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$SKIP_SYSTEM" = false ]; then
    echo -e "\n[1/2] Running System-Level Provisioning..."

    if [ "$SKIP_PACKAGES" = false ]; then
        echo "  Installing core system packages for $OS..."
        case "$OS" in
            ubuntu)
                run_cmd sudo apt-get update -y
                run_cmd sudo apt-get install -y git curl wget vim zsh fzf fontconfig dconf-cli mariadb-server mariadb-client shellcheck command-not-found
                ;;
            fedora)
                run_cmd sudo dnf -y upgrade --refresh
                run_cmd sudo dnf -y install git curl wget vim zsh fzf fontconfig dconf mariadb-server mariadb snapd util-linux-user
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
                run_cmd brew install git curl wget vim zsh fzf fontconfig shellcheck
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
    if [ "$DRY_RUN" = true ]; then
        echo "  [DryRun] Symlinking .environment-variables, .bashrc-addendum, .zshrc-addendum, .zsh-aliases, .zsh-functions, .zsh-completions, .p10k.zsh, .vimrc, .dir-colors/dircolors"
    else
        ln -sf "$DOTFILES_DIR/.environment-variables" "$HOME/.environment-variables"
        ln -sf "$DOTFILES_DIR/.bashrc-addendum"       "$HOME/.bashrc-addendum"
        ln -sf "$DOTFILES_DIR/.zshrc-addendum"        "$HOME/.zshrc-addendum"
        ln -sf "$DOTFILES_DIR/.zsh-aliases"           "$HOME/.zsh-aliases"
        ln -sf "$DOTFILES_DIR/.zsh-functions"         "$HOME/.zsh-functions"
        ln -sf "$DOTFILES_DIR/.zsh-completions"       "$HOME/.zsh-completions"
        ln -sf "$DOTFILES_DIR/.p10k.zsh"              "$HOME/.p10k.zsh"
        ln -sf "$DOTFILES_DIR/.vimrc"                 "$HOME/.vimrc"
        mkdir -p "$HOME/.dir-colors"
        ln -sf "$DOTFILES_DIR/.dir-colors/dircolors"  "$HOME/.dir-colors/dircolors"
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
                if [ ! -f "$target" ]; then
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
                mkdir -p "$HOME/.config/mise"
                if [ -f "$SCRIPT_DIR/.mise.toml" ]; then
                    ln -sf "$SCRIPT_DIR/.mise.toml" "$HOME/.config/mise/config.toml"
                fi
                # Install runtimes
                "$MISE_BIN" install -y 2>/dev/null || true
            fi
        fi
    fi

    # 5. Vim Configuration & Plugins
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

    # 6. Zsh, Oh-My-Zsh & Powerlevel10k
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
                sed -i 's|ZSH_THEME="robbyrussell"|ZSH_THEME="powerlevel10k/powerlevel10k"|g' "$HOME/.zshrc" 2>/dev/null || true
                grep -qxF '[ -f ~/.zshrc-addendum ] && source ~/.zshrc-addendum' "$HOME/.zshrc" 2>/dev/null || \
                    printf '\n# home-settings\n[ -f ~/.zshrc-addendum ] && source ~/.zshrc-addendum\n' >> "$HOME/.zshrc"
            fi
        fi
    fi

    # 7. Bash Configuration
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

    # 8. CLI Completions (gh, kubectl, helm)
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

    # 9. Default Login Shell
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
