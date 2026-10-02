#!/bin/bash
# Shared symlink creation and cleanup helper for home-settings.

_link_path() {
    local flags="$1"
    local src="$2"
    local dst="$3"

    if [ "${DRY_RUN:-false}" = true ]; then
        echo "  [DryRun] ln $flags $src $dst"
    else
        mkdir -p "$(dirname "$dst")"
        if [ -d "$dst" ] && [ ! -L "$dst" ]; then
            local bak
            bak="${dst}.bak.$(date +%s)"
            echo "  Backing up pre-existing directory to $bak"
            mv "$dst" "$bak"
        fi
        ln "$flags" "$src" "$dst"
    fi
}

link_file() {
    _link_path -sf "$1" "$2"
}

link_dir() {
    _link_path -sfn "$1" "$2"
}

unlink_path() {
    local target="$1"
    if [ -L "$target" ]; then
        if [ "${DRY_RUN:-false}" = true ]; then
            echo "  [DryRun] rm -f $target"
        else
            rm -f "$target"
        fi
    fi
}

rebuild_bat_cache() {
    local mise_bin="${1:-}"
    if [ -n "$mise_bin" ] && "$mise_bin" which bat >/dev/null 2>&1; then
        "$mise_bin" exec -- bat cache --build >/dev/null 2>&1 || true
    elif command -v bat >/dev/null 2>&1; then
        bat cache --build >/dev/null 2>&1 || true
    elif command -v batcat >/dev/null 2>&1; then
        batcat cache --build >/dev/null 2>&1 || true
    elif command -v mise >/dev/null 2>&1 && mise which bat >/dev/null 2>&1; then
        mise exec -- bat cache --build >/dev/null 2>&1 || true
    fi
}
