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
