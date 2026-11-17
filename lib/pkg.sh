#!/bin/bash
# Shared cross-platform native and universal package manager primitives.

# Ensure Homebrew is installed and initialized on macOS hosts.
ensure_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        echo "  Homebrew not found. Installing Homebrew..."
        if [ "${DRY_RUN:-false}" = false ]; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            if [ -x "/opt/homebrew/bin/brew" ]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [ -x "/usr/local/bin/brew" ]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
        fi
    fi
}

# Configure classic Snap symlink and socket on Fedora/RHEL systems.
ensure_fedora_snapd() {
    if [ "${DRY_RUN:-false}" = true ]; then
        echo "  [DryRun] sudo ln -sf /var/lib/snapd/snap /snap"
    else
        run_elevated ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
        if command -v systemctl >/dev/null 2>&1; then
            run_elevated systemctl enable --now snapd.socket 2>/dev/null || true
        fi
    fi
}

# Install native packages for ubuntu, fedora, or macos (pass --refresh before -- to update metadata).
pkg_install_native() {
    local os="$1"
    shift
    local refresh=false
    if [ "${1:-}" = "--refresh" ]; then
        refresh=true
        shift
    fi
    [ "${1:-}" = "--" ] && shift
    [ $# -gt 0 ] || return 0

    case "$os" in
        ubuntu)
            if [ "$refresh" = true ]; then
                run_elevated apt-get update -y
            fi
            run_elevated apt-get install -y "$@"
            ;;
        fedora)
            if [ "$refresh" = true ]; then
                run_elevated dnf makecache
            fi
            run_elevated dnf -y install "$@"
            ;;
        macos)
            run_cmd brew install "$@"
            ;;
    esac
}

# Install a classic Snap package on Linux when snapd is available.
install_snap_classic() {
    local snap_pkg="$1"
    local label="${2:-Snap applications}"
    if command -v snap >/dev/null 2>&1 || [ "${DRY_RUN:-false}" = true ]; then
        run_elevated snap install "$snap_pkg" --classic
    else
        echo "  Notice: snap command not found. Skipping ${label}."
    fi
}

# Install Google Chrome across Ubuntu (amd64 .deb), Fedora (amd64 RPM repo), and macOS (Homebrew cask).
install_google_chrome() {
    local os="$1"
    local arch="$2"
    case "$os" in
        ubuntu)
            if [ "$arch" = "amd64" ]; then
                local chrome_url="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
                if [ "${DRY_RUN:-false}" = true ]; then
                    local dry_deb="/tmp/google-chrome-stable_current_amd64.deb"
                    echo "  [DryRun] wget $chrome_url -O $dry_deb"
                    echo "  [DryRun] sudo apt-get install -y $dry_deb"
                else
                    local tmp_deb
                    tmp_deb="$(mktemp /tmp/google-chrome-stable_current_amd64.XXXXXX.deb)"
                    wget -q "$chrome_url" -O "$tmp_deb"
                    run_elevated apt-get install -y "$tmp_deb" || run_elevated dpkg -i "$tmp_deb"
                    rm -f "$tmp_deb"
                fi
            else
                echo "  Notice: Google Chrome official deb is amd64 only (current: $arch). Skipping."
            fi
            ;;
        fedora)
            if [ "$arch" = "amd64" ]; then
                if [ "${DRY_RUN:-false}" = true ]; then
                    echo "  [DryRun] sudo dnf -y install fedora-workstation-repositories"
                    echo "  [DryRun] sudo dnf config-manager enable google-chrome"
                    echo "  [DryRun] sudo dnf -y install google-chrome-stable"
                else
                    run_elevated dnf -y install fedora-workstation-repositories
                    run_elevated dnf config-manager setopt google-chrome.enabled=1 || \
                        run_elevated dnf config-manager --enable google-chrome
                    run_elevated dnf -y install google-chrome-stable
                fi
            else
                echo "  Notice: Google Chrome official rpm is amd64 only (current: $arch). Skipping."
            fi
            ;;
        macos)
            run_cmd brew install --cask google-chrome
            ;;
    esac
}

# Install optional desktop IDE (intellij, intellij-ultimate, code) across Linux Snap and macOS Homebrew Cask.
install_desktop_ide() {
    local os="$1"
    local ide_name="$2"
    case "$os" in
        ubuntu|fedora)
            case "$ide_name" in
                intellij) install_snap_classic intellij-idea-community ;;
                intellij-ultimate) install_snap_classic intellij-idea-ultimate ;;
                code) install_snap_classic code ;;
            esac
            ;;
        macos)
            case "$ide_name" in
                intellij) run_cmd brew install --cask intellij-idea-ce ;;
                intellij-ultimate) run_cmd brew install --cask intellij-idea ;;
                code) run_cmd brew install --cask visual-studio-code ;;
            esac
            ;;
    esac
}

# Install Ghostty terminal emulator across macOS, Ubuntu (Snap), and Fedora (COPR).
install_ghostty() {
    local os="$1"
    case "$os" in
        macos)
            run_cmd brew install --cask ghostty
            ;;
        ubuntu)
            install_snap_classic ghostty "Ghostty install"
            ;;
        fedora)
            if [ "${DRY_RUN:-false}" = true ]; then
                echo "  [DryRun] sudo dnf -y copr enable scottames/ghostty"
                echo "  [DryRun] sudo dnf -y install ghostty"
            else
                run_elevated dnf -y copr enable scottames/ghostty
                run_elevated dnf -y install ghostty
            fi
            ;;
    esac
}

# Upgrade native OS packages and optionally clean stale dependencies/caches.
pkg_upgrade_native() {
    local os="$1"
    local non_interactive="$2"
    local do_cleanup="$3"
    local include_macos_system="${4:-false}"
    local -a yes_flag=()
    [ "$non_interactive" = true ] && yes_flag=(-y)

    case "$os" in
        ubuntu)
            log_step "Updating APT package indices..."
            run_elevated apt-get update

            log_step "Upgrading installed packages..."
            run_elevated apt-get upgrade ${yes_flag[@]+"${yes_flag[@]}"}

            if [ "$do_cleanup" = true ]; then
                log_step "Autoremoving unused APT packages..."
                run_elevated apt-get autoremove ${yes_flag[@]+"${yes_flag[@]}"}

                log_step "Cleaning APT package cache..."
                run_elevated apt-get autoclean
            fi
            ;;
        fedora)
            log_step "Updating DNF package metadata and upgrading packages..."
            run_elevated dnf upgrade --refresh ${yes_flag[@]+"${yes_flag[@]}"}

            if [ "$do_cleanup" = true ]; then
                log_step "Autoremoving unused DNF packages..."
                run_elevated dnf autoremove ${yes_flag[@]+"${yes_flag[@]}"}

                log_step "Cleaning DNF package cache..."
                run_elevated dnf clean packages ${yes_flag[@]+"${yes_flag[@]}"}
            fi
            ;;
        macos)
            if command -v brew >/dev/null 2>&1 || [ "${DRY_RUN:-false}" = true ]; then
                log_step "Updating Homebrew formulae and casks..."
                run_cmd brew update

                log_step "Upgrading Homebrew packages and casks..."
                run_cmd brew upgrade

                if [ "$do_cleanup" = true ]; then
                    log_step "Removing stale Homebrew lockfiles and downloads..."
                    run_cmd brew cleanup -s

                    log_step "Autoremoving unused Homebrew dependencies..."
                    run_cmd brew autoremove
                fi
            else
                log_warn "Homebrew (brew) command not found on macOS host."
            fi

            if [ "$include_macos_system" = true ]; then
                log_step "Checking Apple Software Update..."
                run_elevated softwareupdate -ia --verbose
            fi
            ;;
        arch)
            local -a noconfirm_flag=()
            [ "$non_interactive" = true ] && noconfirm_flag=(--noconfirm)

            log_step "Upgrading Arch Linux packages (Pacman)..."
            run_elevated pacman -Syu ${noconfirm_flag[@]+"${noconfirm_flag[@]}"}

            if [ "$do_cleanup" = true ]; then
                log_step "Cleaning Pacman package cache..."
                run_elevated pacman -Sc ${noconfirm_flag[@]+"${noconfirm_flag[@]}"}
            fi
            ;;
    esac
}

# Upgrade universal application runtimes (Snap, Flatpak, Mac App Store).
pkg_upgrade_universal() {
    local os="$1"
    local non_interactive="$2"
    local do_cleanup="$3"
    local skip_snaps="$4"
    local skip_flatpak="$5"
    local -a yes_flag=()
    [ "$non_interactive" = true ] && yes_flag=(-y)

    if [ "$os" != "macos" ] && [ "$skip_snaps" = false ]; then
        if command -v snap >/dev/null 2>&1 || [ "${DRY_RUN:-false}" = true ]; then
            log_header "Snap Packages"
            log_step "Refreshing installed Snap packages..."
            run_elevated snap refresh
            log_success "Snap packages updated."
        fi
    fi

    if [ "$os" != "macos" ] && [ "$skip_flatpak" = false ]; then
        if command -v flatpak >/dev/null 2>&1 || [ "${DRY_RUN:-false}" = true ]; then
            log_header "Flatpak Packages"
            log_step "Updating installed Flatpaks..."
            run_cmd flatpak update ${yes_flag[@]+"${yes_flag[@]}"}

            if [ "$do_cleanup" = true ]; then
                log_step "Uninstalling unused Flatpak runtimes..."
                run_cmd flatpak uninstall --unused ${yes_flag[@]+"${yes_flag[@]}"}
            fi
            log_success "Flatpak packages updated."
        fi
    fi

    if [ "$os" = "macos" ]; then
        if command -v mas >/dev/null 2>&1 || [ "${DRY_RUN:-false}" = true ]; then
            log_header "Mac App Store"
            log_step "Upgrading Mac App Store applications..."
            run_cmd mas upgrade
            log_success "Mac App Store applications updated."
        fi
    fi
}
