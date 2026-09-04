#!/bin/bash
# Shared terminal logging and command execution helper for home-settings.

# Colors (ANSI)
COLOR_RESET="\033[0m"
COLOR_INFO="\033[34m"    # Blue
COLOR_SUCCESS="\033[32m" # Green
COLOR_WARN="\033[33m"    # Yellow
COLOR_ERROR="\033[31m"   # Red

log_info() {
    echo -e "${COLOR_INFO}==>${COLOR_RESET} $*"
}

log_step() {
    echo -e "  ${COLOR_INFO}➜${COLOR_RESET} $*"
}

log_success() {
    echo -e "  ${COLOR_SUCCESS}✔${COLOR_RESET} $*"
}

log_warn() {
    echo -e "  ${COLOR_WARN}⚠${COLOR_RESET} $*" >&2
}

log_error() {
    echo -e "  ${COLOR_ERROR}✘${COLOR_RESET} $*" >&2
}

log_dry() {
    echo "  [DryRun] $*"
}

run_cmd() {
    if [ "${DRY_RUN:-false}" = true ]; then
        echo "  [DryRun] $*"
    else
        "$@"
    fi
}
