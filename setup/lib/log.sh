#!/bin/bash
# Shared logging, dry-run execution, privilege, retry, and atomic file helpers.

# Solarized Dark aligned ANSI escape palette
COLOR_RESET="\033[0m"
COLOR_INFO="\033[34m"    # Blue (#268BD2)
COLOR_SUCCESS="\033[32m" # Green (#859900)
COLOR_WARN="\033[33m"    # Yellow (#B58900)
COLOR_ERROR="\033[31m"   # Red (#DC322F)

log_header() {
    printf '\n%b==>%b %s\n' "$COLOR_INFO" "$COLOR_RESET" "$*"
}

log_step() {
    printf '  %b➜%b %s\n' "$COLOR_INFO" "$COLOR_RESET" "$*"
}

log_success() {
    printf '  %b✔%b %s\n' "$COLOR_SUCCESS" "$COLOR_RESET" "$*"
}

log_warn() {
    printf '  %b⚠%b %s\n' "$COLOR_WARN" "$COLOR_RESET" "$*" >&2
}

log_error() {
    printf '  %b✘%b %s\n' "$COLOR_ERROR" "$COLOR_RESET" "$*" >&2
}

# Execute a command, or preview it when DRY_RUN=true.
run_cmd() {
    if [ "${DRY_RUN:-false}" = true ]; then
        echo "  [DryRun] $*"
    else
        "$@"
    fi
}

# Execute a command with root privileges (via sudo when non-root), honoring DRY_RUN.
run_elevated() {
    if [ "${DRY_RUN:-false}" = true ]; then
        if [ "$(id -u)" -eq 0 ]; then
            echo "  [DryRun] $*"
        else
            echo "  [DryRun] sudo $*"
        fi
    else
        if [ "$(id -u)" -eq 0 ]; then
            "$@"
        else
            sudo "$@"
        fi
    fi
}

# Pre-authenticate an interactive sudo session when privileged operations are required.
ensure_sudo() {
    if [ "${DRY_RUN:-false}" = false ] && [ "$(id -u)" -ne 0 ]; then
        if ! sudo -n true 2>/dev/null; then
            log_step "Elevated permissions required. Authenticating sudo session..."
            sudo -v
        fi
    fi
}

# Retry a transient command up to max_attempts times with delay_sec between tries.
retry_cmd() {
    local max_attempts="$1"
    local delay_sec="$2"
    shift 2
    local attempt=1
    while true; do
        if "$@"; then
            return 0
        fi
        if [ "$attempt" -ge "$max_attempts" ]; then
            return 1
        fi
        if [ "$delay_sec" -gt 0 ]; then
            sleep "$delay_sec"
        fi
        attempt=$((attempt + 1))
    done
}

# Move an existing path to a collision-free timestamped backup and print the backup path.
backup_existing_path() {
    local dst="$1"
    local base_bak bak idx=1
    base_bak="${dst}.bak.$(date +%s)"
    bak="$base_bak"
    while [ -e "$bak" ] || [ -L "$bak" ]; do
        bak="${base_bak}.${idx}"
        idx=$((idx + 1))
    done
    mv "$dst" "$bak"
    printf '%s\n' "$bak"
}

# Return the exact byte count of a regular file, or 0 when absent.
file_byte_size() {
    local p="$1"
    if [ -f "$p" ]; then
        wc -c < "$p" | tr -d '[:space:]'
    else
        printf '0\n'
    fi
}

# Copy src to dest via an atomic sibling temporary file so open inodes stay intact.
atomic_copy_file() {
    local src="$1"
    local dest="$2"
    local tmp_dest="${dest}.tmp.$$.${BASHPID:-$RANDOM}"
    if cp -f "$src" "$tmp_dest" && mv -f "$tmp_dest" "$dest"; then
        return 0
    fi
    rm -f "$tmp_dest"
    return 1
}

# Download url to dest via an atomic temporary file and clean up on failure.
atomic_download_url() {
    local url="$1"
    local dest="$2"
    local tmp_dest="${dest}.tmp.$$.${BASHPID:-$RANDOM}"
    if curl -fsSL "$url" -o "$tmp_dest" && mv -f "$tmp_dest" "$dest"; then
        return 0
    fi
    rm -f "$tmp_dest"
    return 1
}
