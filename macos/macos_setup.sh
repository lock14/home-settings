#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

JDK_PACKAGE="openjdk-11"
IDE="intellij-ultimate"
INSTALL_ITERM2=false
INSTALL_GHOSTTY=false
INSTALL_APPS=false
DRY_RUN=false

usage() {
    cat << 'EOF'
usage: macos_setup.sh [options]

Setup development environment on macOS.

Options:
  -j, --jdk <package>   JDK package to install: openjdk-8, openjdk-11, openjdk-17, openjdk-21 (default: openjdk-11)
  -i, --ide <ide>       IDE to install: intellij, intellij-ultimate, vscode, none (default: intellij-ultimate)
  --iterm2              Install and configure iTerm2
  --ghostty             Install and configure Ghostty
  --apps                Install additional desktop apps (Google Chrome, Slack, Postman)
  --dry-run             Show what would be installed without executing
  -h, --help            Show this help message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -j|--jdk)
            if [ $# -lt 2 ] || [[ "${2:-}" == -* ]]; then
                echo "error: '$1' requires an argument" >&2
                usage >&2
                exit 1
            fi
            JDK_PACKAGE="$2"
            shift
            ;;
        --jdk=*)
            JDK_PACKAGE="${1#*=}"
            ;;
        -i|--ide)
            if [ $# -lt 2 ] || [[ "${2:-}" == -* ]]; then
                echo "error: '$1' requires an argument" >&2
                usage >&2
                exit 1
            fi
            IDE="$2"
            shift
            ;;
        --ide=*)
            IDE="${1#*=}"
            ;;
        --iterm2)
            INSTALL_ITERM2=true
            ;;
        --ghostty)
            INSTALL_GHOSTTY=true
            ;;
        --apps)
            INSTALL_APPS=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "error: unknown option '$1'" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

# Validate JDK
if [ "$JDK_PACKAGE" != "none" ] && [ "$JDK_PACKAGE" != "openjdk-8" ] && [ "$JDK_PACKAGE" != "openjdk-11" ] && [ "$JDK_PACKAGE" != "openjdk-17" ] && [ "$JDK_PACKAGE" != "openjdk-21" ]; then
    echo "error: '$JDK_PACKAGE' is not a supported JDK package. Choose from: openjdk-8, openjdk-11, openjdk-17, openjdk-21, none" >&2
    exit 1
fi

# Validate IDE
if [ "$IDE" != "none" ] && [ "$IDE" != "intellij" ] && [ "$IDE" != "intellij-ultimate" ] && [ "$IDE" != "vscode" ]; then
    echo "error: '$IDE' is not a supported IDE. Choose from: intellij, intellij-ultimate, vscode, none" >&2
    exit 1
fi

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

echo "========================================"
echo "Starting macOS Development Environment Setup"
echo "========================================"

# 1. Ensure Homebrew is installed
if ! command -v brew &>/dev/null; then
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Install Homebrew via official installer"
    else
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [ -x "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -x "/usr/local/bin/brew" ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
else
    echo "Homebrew is already installed."
fi

# 2. Update Homebrew and install base CLI packages
echo "Installing CLI utilities from Brewfile..."
if [ -f "$SCRIPT_DIR/Brewfile" ]; then
    run_cmd brew bundle --file="$SCRIPT_DIR/Brewfile" || true
fi

# 3. Install JDK if requested
if [ "$JDK_PACKAGE" != "none" ]; then
    echo "Installing $JDK_PACKAGE..."
    case "$JDK_PACKAGE" in
        openjdk-8)  run_cmd brew install openjdk@8 || true ;;
        openjdk-11) run_cmd brew install openjdk@11 || true ;;
        openjdk-17) run_cmd brew install openjdk@17 || true ;;
        openjdk-21) run_cmd brew install openjdk@21 || true ;;
    esac
fi

# 4. Install IDE if requested
if [ "$IDE" = "intellij-ultimate" ]; then
    echo "Installing IntelliJ IDEA Ultimate..."
    run_cmd brew install --cask intellij-idea || true
elif [ "$IDE" = "intellij" ]; then
    echo "Installing IntelliJ IDEA Community..."
    run_cmd brew install --cask intellij-idea-ce || true
elif [ "$IDE" = "vscode" ]; then
    echo "Installing Visual Studio Code..."
    run_cmd brew install --cask visual-studio-code || true
fi

# 5. Install optional terminal emulators
TERMINAL_ARGS=()
if [ "$INSTALL_ITERM2" = true ]; then
    echo "Installing iTerm2..."
    run_cmd brew install --cask iterm2 || true
    TERMINAL_ARGS+=("--iterm2")
fi
if [ "$INSTALL_GHOSTTY" = true ]; then
    echo "Installing Ghostty..."
    run_cmd brew install --cask ghostty || true
    TERMINAL_ARGS+=("--ghostty")
fi

# 6. Install optional applications
if [ "$INSTALL_APPS" = true ]; then
    echo "Installing desktop productivity apps..."
    run_cmd brew install --cask google-chrome slack postman || true
fi

# 7. Install MesloLGS NF fonts
echo "Installing MesloLGS NF fonts..."
if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] Run font-setup.sh"
else
    "$REPO_DIR/font-setup.sh"
fi

# 8. Configure Terminal appearance (Terminal.app + optional emulators)
echo "Configuring terminal appearance..."
if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] Run terminal-setup.sh ${TERMINAL_ARGS[*]:-}"
else
    if [ ${#TERMINAL_ARGS[@]} -gt 0 ]; then
        "$SCRIPT_DIR/terminal-setup.sh" "${TERMINAL_ARGS[@]}"
    else
        "$SCRIPT_DIR/terminal-setup.sh"
    fi
fi

# 9. Install dotfiles via Makefile
echo "Installing shell dotfiles, Vim, and bin tools..."
if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] make -C $REPO_DIR install"
else
    make -C "$REPO_DIR" install
fi

echo "========================================"
echo "macOS setup completed successfully!"
echo "Restart your terminal or run: exec zsh"
echo "========================================"
