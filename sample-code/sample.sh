#!/bin/bash
# ==============================================================================
# Solarized Dark Shell Syntax Highlighting Showcase
# Demonstrates functions, arrays, expansions, arithmetic, and trap handlers.
# ==============================================================================
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly WORK_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sample-runner"
readonly MAX_RETRIES=5
declare -a ACTIVE_SERVICES=("nginx" "redis" "postgresql" "app-worker")

cleanup() {
    local -r exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        printf "\033[38;2;133;153;0m[%s] Process completed successfully.\033[0m\n" "$SCRIPT_NAME"
    else
        printf "\033[38;2;220;50;47m[%s] Process terminated with error: %d\033[0m\n" "$SCRIPT_NAME" "$exit_code" >&2
    fi
}
trap cleanup EXIT

log_status() {
    local -r level="$1"
    local -r message="$2"
    local color="\033[38;2;131;148;150m"

    case "$level" in
        INFO)  color="\033[38;2;38;139;210m" ;;  # Solarized Blue
        WARN)  color="\033[38;2;181;137;0m" ;;  # Solarized Yellow
        ERROR) color="\033[38;2;220;50;47m" ;;  # Solarized Red
        *)     color="\033[38;2;133;153;0m" ;;  # Solarized Green
    esac

    printf "%b[%s]\033[0m [%s] %s\n" "$color" "$level" "$SCRIPT_NAME" "$message"
}

render_banner() {
    cat << 'EOF'
   ____       _            _             _ 
  / ___|  ___ | | __ _ _ __(_)_______  __| |
  \___ \ / _ \| |/ _` | '__| |_  / _ \/ _` |
   ___) | (_) | | (_| | |  | |/ /  __/ (_| |
  |____/ \___/|_|\__,_|_|  |_/___\___|\__,_|
EOF
}

check_services() {
    local total=0
    local failed=0

    for svc in "${ACTIVE_SERVICES[@]}"; do
        total=$(( total + 1 ))
        if [[ "$svc" == "redis" || "$svc" == "nginx" ]]; then
            log_status "INFO" "Service '${svc}' is healthy."
        else
            log_status "WARN" "Service '${svc}' is standby."
        fi
    done

    printf "Health check summary: %d checked, %d offline.\n" "$total" "$failed"
}

main() {
    render_banner
    mkdir -p "$WORK_DIR"
    log_status "INFO" "Initializing workspace at: ${WORK_DIR} (max retries: ${MAX_RETRIES})"
    check_services
}

main "$@"
