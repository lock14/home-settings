#!/bin/bash
# Shared command execution helper for home-settings.

run_cmd() {
    if [ "${DRY_RUN:-false}" = true ]; then
        echo "  [DryRun] $*"
    else
        "$@"
    fi
}

