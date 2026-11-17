#!/bin/bash
# Shared OS/architecture detection, path management, and platform helpers.

# Resolve the physical directory containing a script path across symlink chains.
resolve_script_dir() {
    local source_path="$1"
    local source_dir
    while [ -L "$source_path" ]; do
        source_dir="$(cd -P "$(dirname "$source_path")" && pwd)"
        source_path="$(readlink "$source_path")"
        [[ "$source_path" != /* ]] && source_path="$source_dir/$source_path"
    done
    cd -P "$(dirname "$source_path")" && pwd
}

# Detect normalized OS family: ubuntu, fedora, arch, macos, or unknown.
detect_os() {
    if [ -n "${TARGET_OS:-}" ]; then
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
            ubuntu|debian|pop|linuxmint|elementary|kali)
                echo "ubuntu"
                return 0
                ;;
            fedora|rhel|centos|rocky|almalinux)
                echo "fedora"
                return 0
                ;;
            arch|manjaro|endeavouros)
                echo "arch"
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
            *arch*)
                echo "arch"
                return 0
                ;;
        esac
    fi

    if command -v apt-get >/dev/null 2>&1; then
        echo "ubuntu"
    elif command -v dnf >/dev/null 2>&1; then
        echo "fedora"
    elif command -v pacman >/dev/null 2>&1; then
        echo "arch"
    elif command -v brew >/dev/null 2>&1; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Detect normalized CPU architecture: amd64, arm64, or raw uname -m.
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "$arch" ;;
    esac
}

# Prepend each non-empty directory to PATH if not already present.
prepend_path() {
    local dir
    for dir in "$@"; do
        [ -n "$dir" ] || continue
        case ":$PATH:" in
            *":$dir:"*) ;;
            *) PATH="$dir:$PATH" ;;
        esac
    done
    export PATH
}

# Prepend each existing directory to PATH if not already present.
prepend_existing_paths() {
    local dir
    for dir in "$@"; do
        if [ -n "$dir" ] && [ -d "$dir" ]; then
            prepend_path "$dir"
        fi
    done
}

# Run in-place sed portably across GNU sed (Linux) and BSD sed (macOS).
sed_in_place() {
    local target_file="$1"
    shift
    if [ "${OS:-}" = "macos" ]; then
        sed -i '' "$@" "$target_file"
    else
        sed -i "$@" "$target_file"
    fi
}

# Resolve active theme name from env overrides or persisted state file.
resolve_persisted_theme() {
    local xdg_config="${1:-${XDG_CONFIG_HOME:-$HOME/.config}}"
    local resolved="${HOME_SETTINGS_THEME:-${THEME_NAME:-}}"
    if [ -z "$resolved" ] && [ -f "$xdg_config/home-settings/theme" ]; then
        resolved="$(tr -d '[:space:]' < "$xdg_config/home-settings/theme" || true)"
    fi
    printf '%s' "$resolved"
}
