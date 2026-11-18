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

# Install Ghostty terminal emulator across macOS (Homebrew cask), Ubuntu/Debian (APT, Snap, or .deb), and Fedora (COPR).
apt_has_remote_candidate() {
    local pkg="$1"
    command -v apt-cache >/dev/null 2>&1 || return 1
    local policy
    policy="$(LC_ALL=C apt-cache policy "$pkg" 2>/dev/null || true)"
    [ -n "$policy" ] || return 1
    awk '
        /^  Candidate:/ {
            if ($2 == "" || $2 == "(none)") exit 1
            has_cand = 1
        }
        in_table && /^[[:space:]]+[0-9]+[[:space:]]+/ && index($2, "/") > 0 && $2 != "/var/lib/dpkg/status" {
            has_remote = 1
        }
        /^  Version table:/ { in_table = 1 }
        END { exit !(has_cand && has_remote) }
    ' <<< "$policy"
}

dpkg_installed_version() {
    local pkg="$1"
    command -v dpkg-query >/dev/null 2>&1 || return 0
    local status_ver
    status_ver="$(dpkg-query -W -f='${Status}\t${Version}\n' "$pkg" 2>/dev/null || true)"
    case "$status_ver" in
        "install ok installed	"*)
            printf '%s' "${status_ver#*	}"
            ;;
    esac
}

apt_pkg_candidate_version() {
    local pkg="$1"
    local ver=""
    if command -v apt-cache >/dev/null 2>&1; then
        local policy
        policy="$(LC_ALL=C apt-cache policy "$pkg" 2>/dev/null || true)"
        ver="$(awk '/^  Candidate:/ && $2 != "" && $2 != "(none)" { print $2; exit }' <<< "$policy")"
    fi
    if [ -z "$ver" ]; then
        ver="$(dpkg_installed_version "$pkg")"
    fi
    printf '%s' "$ver"
}

resolve_ghostty_deb_suites() {
    local os_release="${GHOSTTY_OS_RELEASE:-/etc/os-release}"
    local distro_id="" distro_like="" ver_id="" ver_code="" ubu_ver="" ubu_code="" deb_code=""
    if [ -f "$os_release" ]; then
        eval "$(
            # shellcheck source=/dev/null
            . "$os_release" 2>/dev/null || true
            printf 'distro_id=%q\ndistro_like=%q\nver_id=%q\nver_code=%q\nubu_ver=%q\nubu_code=%q\ndeb_code=%q\n' \
                "${ID:-}" "${ID_LIKE:-}" "${VERSION_ID:-}" "${VERSION_CODENAME:-}" \
                "${UBUNTU_VERSION_ID:-}" "${UBUNTU_CODENAME:-}" "${DEBIAN_CODENAME:-}"
        )"
    fi

    if [ -z "$deb_code" ]; then
        local resolved_ubu="${ubu_ver:-}"
        if [ -z "$resolved_ubu" ]; then
            case "${ubu_code:-$ver_code}" in
                stonking) resolved_ubu="26.10" ;;
                resolute) resolved_ubu="26.04" ;;
                noble)    resolved_ubu="24.04" ;;
                jammy)    resolved_ubu="22.04" ;;
            esac
        fi
        if [ -z "$resolved_ubu" ]; then
            case "$distro_id" in
                ubuntu|pop|tuxedo|neon) resolved_ubu="$ver_id" ;;
            esac
        fi
        case "$resolved_ubu" in
            26.10) echo "26.10 26.04"; return 0 ;;
            26.04) echo "26.04"; return 0 ;;
            24.04) echo "24.04"; return 0 ;;
            22.04) echo "22.04"; return 0 ;;
        esac
    fi

    case "${deb_code:-$ver_code}" in
        forky)    echo "forky trixie"; return 0 ;;
        trixie)   echo "trixie bookworm"; return 0 ;;
        bookworm) echo "bookworm"; return 0 ;;
    esac

    if command -v dpkg >/dev/null 2>&1 && { [ -n "${GHOSTTY_OS_RELEASE:-}" ] || [[ "$distro_id $distro_like" == *debian* ]] || [[ "$distro_id $distro_like" == *ubuntu* ]]; }; then
        local libc_ver gtk_ver
        libc_ver="$(apt_pkg_candidate_version libc6)"
        gtk_ver="$(apt_pkg_candidate_version libgtk-4-1)"
        if [ -n "$libc_ver" ] && dpkg --compare-versions "$libc_ver" ge "2.43" && \
           { [ -z "$gtk_ver" ] || dpkg --compare-versions "$gtk_ver" ge "4.21.5"; }; then
            echo "forky trixie"
            return 0
        fi
        if [ -n "$libc_ver" ] && dpkg --compare-versions "$libc_ver" ge "2.38" && \
           { [ -z "$gtk_ver" ] || dpkg --compare-versions "$gtk_ver" ge "4.15.4"; }; then
            echo "trixie bookworm"
            return 0
        fi
        if [ -n "$libc_ver" ] && dpkg --compare-versions "$libc_ver" ge "2.36"; then
            echo "bookworm"
            return 0
        fi
    fi

    echo "trixie"
}

resolve_ghostty_deb_url() {
    local arch="$1"
    local suites="$2"
    local repo_base="${GHOSTTY_DEB_REPO_BASE:-https://github.com/mkasberg/ghostty-ubuntu}"
    local api_url="${GHOSTTY_DEB_API_URL:-https://api.github.com/repos/mkasberg/ghostty-ubuntu/releases?per_page=30}"
    local eff_url latest_tag ver_dot candidate_url suite

    if [[ "$repo_base" == http://* ]] || [[ "$repo_base" == https://* ]]; then
        eff_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "${repo_base}/releases/latest" 2>/dev/null || true)"
        latest_tag="${eff_url##*/}"
        if [[ "$latest_tag" == *-ppa* ]] && [ "$latest_tag" != "latest" ]; then
            ver_dot="${latest_tag%-ppa*}.ppa${latest_tag##*-ppa}"
            for suite in $suites; do
                candidate_url="${repo_base}/releases/download/${latest_tag}/ghostty_${ver_dot}_${arch}_${suite}.deb"
                if curl -fsSLI -o /dev/null "$candidate_url" 2>/dev/null; then
                    printf '%s\n' "$candidate_url"
                    return 0
                fi
            done
        fi
    fi

    local releases_json match_url
    releases_json="$(curl -fsSL "$api_url" 2>/dev/null || true)"
    if [ -n "$releases_json" ]; then
        for suite in $suites; do
            match_url="$(
                awk -v suffix="_${arch}_${suite}.deb\"" '
                    index($0, "\"browser_download_url\"") && index($0, suffix) {
                        line = $0
                        sub(/^.*"browser_download_url":[[:space:]]*"/, "", line)
                        sub(/".*$/, "", line)
                        if (line ~ /\/ghostty_[^\/]+\.deb$/) {
                            print line
                            exit 0
                        }
                    }
                ' <<< "$releases_json"
            )"
            if [ -n "$match_url" ]; then
                printf '%s\n' "$match_url"
                return 0
            fi
        done
    fi

    if [[ "$repo_base" == http://* ]] || [[ "$repo_base" == https://* ]]; then
        local fallback_tag=""
        for suite in $suites; do
            case "$suite" in
                24.04)          fallback_tag="1.3.1-0-ppa2" ;;
                22.04|bookworm) fallback_tag="1.1.3-0-ppa2" ;;
                *)              fallback_tag="" ;;
            esac
            if [ -n "$fallback_tag" ]; then
                ver_dot="${fallback_tag%-ppa*}.ppa${fallback_tag##*-ppa}"
                candidate_url="${repo_base}/releases/download/${fallback_tag}/ghostty_${ver_dot}_${arch}_${suite}.deb"
                if curl -fsSLI -o /dev/null "$candidate_url" 2>/dev/null; then
                    printf '%s\n' "$candidate_url"
                    return 0
                fi
            fi
        done
    fi

    return 1
}

install_ghostty_ubuntu_deb() {
    local arch="$1"
    case "$arch" in
        amd64|arm64) ;;
        *)
            echo "  Notice: Ghostty prebuilt .deb packages support amd64 and arm64 only (current: $arch). Skipping Ghostty install."
            return 0
            ;;
    esac

    local suites primary_suite
    suites="$(resolve_ghostty_deb_suites)"
    primary_suite="${suites%% *}"

    if [ "${DRY_RUN:-false}" = true ]; then
        local dry_deb="/tmp/ghostty_latest_${arch}_${primary_suite}.deb"
        echo "  [DryRun] curl -fsSL https://github.com/mkasberg/ghostty-ubuntu/releases/latest/download/ghostty_${arch}_${primary_suite}.deb -o $dry_deb"
        run_elevated apt-get install -y "$dry_deb"
        return 0
    fi

    local deb_url
    deb_url="$(resolve_ghostty_deb_url "$arch" "$suites" || true)"
    if [ -z "$deb_url" ]; then
        log_warn "Unable to locate a compatible Ghostty .deb release for ${arch} (${suites}). Skipping Ghostty install."
        return 0
    fi

    local deb_file raw_ver candidate_ver installed_ver
    deb_file="${deb_url##*/}"
    raw_ver="${deb_file#ghostty_}"
    raw_ver="${raw_ver%_"${arch}"_*.deb}"
    if [[ "$raw_ver" == *.ppa* ]]; then
        candidate_ver="${raw_ver%.ppa*}~ppa${raw_ver##*.ppa}"
    else
        candidate_ver="$raw_ver"
    fi
    installed_ver="$(dpkg_installed_version ghostty)"
    if [ -n "$installed_ver" ] && [ -n "$candidate_ver" ] && [ "$candidate_ver" != "$deb_file" ] && \
       command -v dpkg >/dev/null 2>&1 && dpkg --compare-versions "$installed_ver" ge "$candidate_ver" 2>/dev/null; then
        echo "  Ghostty ($installed_ver) is already installed and up to date."
        return 0
    fi

    local tmp_deb
    tmp_deb="$(mktemp "/tmp/ghostty_${arch}_${primary_suite}.XXXXXX.deb")"
    if ! retry_cmd 3 2 atomic_download_url "$deb_url" "$tmp_deb"; then
        rm -f "$tmp_deb"
        log_error "Failed to download Ghostty package from $deb_url"
        return 1
    fi
    chmod 0644 "$tmp_deb"

    local install_rc=0
    run_elevated apt-get install -y "$tmp_deb" || run_elevated dpkg -i "$tmp_deb" || install_rc=$?
    rm -f "$tmp_deb"
    return "$install_rc"
}

install_ghostty() {
    local os="$1"
    local arch="${2:-$(detect_arch)}"
    case "$os" in
        macos)
            run_cmd brew install --cask ghostty
            ;;
        ubuntu)
            if apt_has_remote_candidate ghostty; then
                pkg_install_native ubuntu -- ghostty
            elif command -v snap >/dev/null 2>&1; then
                if [ "${DRY_RUN:-false}" = true ]; then
                    run_elevated snap install ghostty --classic
                elif ! run_elevated snap install ghostty --classic; then
                    log_warn "Snap Ghostty install failed; falling back to .deb package..."
                    install_ghostty_ubuntu_deb "$arch"
                fi
            else
                install_ghostty_ubuntu_deb "$arch"
            fi
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
