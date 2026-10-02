#!/bin/bash
# Shared symlink creation and cleanup helper for home-settings.

link_file() {
    local src="$1"
    local dst="$2"

    if [ "${DRY_RUN:-false}" = true ]; then
        echo "  [DryRun] ln -sf $src $dst"
    else
        mkdir -p "$(dirname "$dst")"
        if [ -d "$dst" ] && [ ! -L "$dst" ]; then
            local bak
            bak="${dst}.bak.$(date +%s)"
            echo "  Backing up pre-existing directory to $bak"
            mv "$dst" "$bak"
        fi
        ln -sf "$src" "$dst"
    fi
}

link_dir() {
    local src="$1"
    local dst="$2"

    if [ "${DRY_RUN:-false}" = true ]; then
        echo "  [DryRun] ln -sfn $src $dst"
    else
        mkdir -p "$(dirname "$dst")"
        if [ -d "$dst" ] && [ ! -L "$dst" ]; then
            local bak
            bak="${dst}.bak.$(date +%s)"
            echo "  Backing up pre-existing directory to $bak"
            mv "$dst" "$bak"
        fi
        ln -sfn "$src" "$dst"
    fi
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
