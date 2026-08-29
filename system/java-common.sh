#!/bin/bash
# Shared helper functions for Java and IDE configuration across modern Linux distros (Ubuntu 22.04+, Fedora 38+)

# Determine normalized system architecture
get_system_arch() {
    local arch
    arch="$(dpkg --print-architecture 2>/dev/null || true)"
    if [ -z "$arch" ]; then
        case "$(uname -m)" in
            x86_64) arch="amd64" ;;
            aarch64|arm64) arch="arm64" ;;
            *) arch="$(uname -m)" ;;
        esac
    fi
    echo "$arch"
}

# Normalize and validate JDK version. Only actively supported non-EOL LTS releases are allowed (Java 17, 21).
normalize_jdk_version() {
    local input="$1"
    local ver="$input"

    ver="${ver#openjdk-}"
    ver="${ver#java-}"
    ver="${ver#1.}"
    ver="${ver%.0}"
    ver="${ver%-jdk}"
    ver="${ver%-openjdk}"
    ver="${ver%-devel}"

    case "$ver" in
        17|21|25)
            echo "$ver"
            ;;
        8|11)
            echo "eol"
            ;;
        *)
            echo "unsupported"
            ;;
    esac
}

# Validate IDE selection
validate_ide_name() {
    local ide="$1"
    case "$ide" in
        intellij|intellij-ultimate|eclipse|netbeans|code|none)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
