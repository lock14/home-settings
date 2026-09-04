#!/bin/bash
# Shared OS and architecture detection library for home-settings.

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

detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "$arch" ;;
    esac
}
