#!/bin/bash
# bootstrap.sh - Zero-dependency new machine setup orchestrator
# Works on Debian/Ubuntu, Fedora/RHEL, Arch, and macOS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for terminal output
BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

info() {
    echo -e "${BLUE}${BOLD}[INFO]${RESET} $*"
}

success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${RESET} $*"
}

warn() {
    echo -e "${YELLOW}${BOLD}[WARN]${RESET} $*"
}

error() {
    echo -e "${RED}${BOLD}[ERROR]${RESET} $*" >&2
}

echo -e "${BOLD}======================================================${RESET}"
echo -e "${BOLD}         Home-Settings Bootstrap & Setup              ${RESET}"
echo -e "${BOLD}======================================================${RESET}"

# 1. Acquire sudo privileges once (if sudo is present and not already root)
SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        info "Requesting sudo privileges for package installation..."
        sudo -v
        # Keep sudo alive during script execution in the background
        while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_KEEP_ALIVE_PID=$!
        trap 'kill "$SUDO_KEEP_ALIVE_PID" 2>/dev/null || true' EXIT
        SUDO="sudo"
    else
        warn "sudo not found. Continuing without root privileges..."
    fi
fi

# 2. Detect package manager & install base prerequisites
info "Checking and installing required system packages..."

if [ -n "$SUDO" ] || [ "${EUID:-$(id -u)}" -eq 0 ]; then
    if command -v apt &>/dev/null; then
        info "Debian/Ubuntu detected (apt). Updating package lists..."
        if command -v add-apt-repository &>/dev/null; then
            $SUDO add-apt-repository -y universe 2>/dev/null || true
        fi
        $SUDO apt update -y
        info "Installing base packages (make, git, curl, wget, zsh, fzf, vim, fontconfig)..."
        $SUDO apt install -y make git curl wget zsh fzf vim fontconfig command-not-found || {
            warn "Some packages failed in batch install. Trying individually..."
            for pkg in make git curl wget zsh fzf vim fontconfig command-not-found; do
                $SUDO apt install -y "$pkg" 2>/dev/null || warn "Could not install $pkg"
            done
        }
    elif command -v dnf &>/dev/null; then
        info "Fedora/RHEL detected (dnf). Installing base packages..."
        $SUDO dnf -y install make git curl wget zsh fzf vim fontconfig PackageKit-command-not-found util-linux-user || {
            for pkg in make git curl wget zsh fzf vim fontconfig PackageKit-command-not-found util-linux-user; do
                $SUDO dnf -y install "$pkg" 2>/dev/null || warn "Could not install $pkg"
            done
        }
    elif command -v pacman &>/dev/null; then
        info "Arch Linux detected (pacman). Installing base packages..."
        $SUDO pacman -Syu --noconfirm make git curl wget zsh fzf vim fontconfig || true
    elif command -v brew &>/dev/null; then
        info "macOS Homebrew detected. Installing base packages..."
        brew install make git curl zsh fzf vim fontconfig 2>/dev/null || true
    else
        warn "No supported package manager detected. Please ensure make, git, curl, zsh, fzf, and vim are installed."
    fi
fi

# Ensure ~/.local/bin exists
mkdir -p "$HOME/.local/bin"

# 3. Fallback for fzf if missing from package manager
if ! command -v fzf &>/dev/null; then
    info "fzf not found in system packages. Installing standalone binary to ~/.local/bin/fzf..."
    if [ ! -d "$HOME/.fzf" ]; then
        git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf" 2>/dev/null || true
        if [ -x "$HOME/.fzf/install" ]; then
            "$HOME/.fzf/install" --bin --no-update-rc 2>/dev/null || true
            if [ -f "$HOME/.fzf/bin/fzf" ]; then
                ln -sf "$HOME/.fzf/bin/fzf" "$HOME/.local/bin/fzf"
            fi
        fi
    fi
fi

# 4. Set default shell to Zsh
CURRENT_SHELL="$(getent passwd "${USER:-$(whoami)}" 2>/dev/null | cut -d: -f7 || echo "${SHELL:-}")"
ZSH_BIN="$(command -v zsh 2>/dev/null || true)"

if [ -n "$ZSH_BIN" ] && [ "$CURRENT_SHELL" != "$ZSH_BIN" ]; then
    info "Setting default login shell to $ZSH_BIN..."
    if [ -n "$SUDO" ]; then
        $SUDO chsh -s "$ZSH_BIN" "${USER:-$(whoami)}" 2>/dev/null || true
    elif [ "${EUID:-$(id -u)}" -eq 0 ]; then
        chsh -s "$ZSH_BIN" "${USER:-$(whoami)}" 2>/dev/null || true
    elif [ -t 0 ] && command -v chsh &>/dev/null; then
        chsh -s "$ZSH_BIN" 2>/dev/null || true
    fi
fi

# 5. Run dotfile and configuration install via make
info "Installing dotfiles, shell configs, vim plugins, and fonts..."
make -C "$SCRIPT_DIR" install

# 6. Configure GNOME Terminal colors if applicable
if command -v gnome-terminal &>/dev/null && [ -n "${DISPLAY:-${WAYLAND_DISPLAY:-}}" ]; then
    if [ -x "$SCRIPT_DIR/gnome-terminal-setup.sh" ]; then
        info "Configuring GNOME Terminal Solarized color palette..."
        "$SCRIPT_DIR/gnome-terminal-setup.sh" 2>/dev/null || true
    fi
fi

echo ""
echo -e "${GREEN}${BOLD}======================================================${RESET}"
echo -e "${GREEN}${BOLD}       Bootstrap & Setup Completed Successfully!     ${RESET}"
echo -e "${GREEN}${BOLD}======================================================${RESET}"
echo -e "To start using your new environment immediately, run:"
echo -e "  ${BOLD}exec zsh${RESET}"
echo ""
