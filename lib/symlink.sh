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
        if [ -e "$dst" ] && [ ! -L "$dst" ]; then
            local base_bak bak idx
            base_bak="${dst}.bak.$(date +%s)"
            bak="$base_bak"
            idx=1
            while [ -e "$bak" ] || [ -L "$bak" ]; do
                bak="${base_bak}.${idx}"
                idx=$((idx + 1))
            done
            echo "  Backing up pre-existing path to $bak"
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

_canonicalize_ownership_path() {
    local p="$1"
    [ -n "$p" ] || return 1
    if [[ "$p" != /* ]]; then
        p="$(pwd -P 2>/dev/null || pwd)/$p"
    fi
    local parent base parent_phys
    parent="$(dirname "$p")"
    base="$(basename "$p")"
    if [ "$base" != "." ] && [ "$base" != ".." ] && [ -d "$parent" ]; then
        if [ -d "$p" ]; then
            cd -P "$p" 2>/dev/null && pwd && return 0
        fi
        parent_phys="$(cd -P "$parent" 2>/dev/null && pwd || true)"
        if [ -n "$parent_phys" ]; then
            printf '%s\n' "${parent_phys%/}/$base"
            return 0
        fi
    fi

    local cur="" seg next IFS='/'
    local -a parts=()
    read -r -a parts <<< "$p"
    for seg in "${parts[@]}"; do
        case "$seg" in
            ""|".")
                continue
                ;;
            "..")
                cur="${cur%/*}"
                ;;
            *)
                next="${cur}/${seg}"
                if [ -d "$next" ]; then
                    cur="$(cd -P "$next" 2>/dev/null && pwd || printf '%s' "$next")"
                    cur="${cur%/}"
                else
                    cur="$next"
                fi
                ;;
        esac
    done
    printf '%s\n' "${cur:-/}"
}

_is_managed_symlink() {
    local target="$1"
    local allowed_target="${2:-}"
    local raw_link
    raw_link="$(readlink "$target" 2>/dev/null || true)"
    [ -n "$raw_link" ] || return 1

    if [ -n "$allowed_target" ] && [ "$raw_link" = "$allowed_target" ]; then
        return 0
    fi

    local target_dir abs_link canon_link
    target_dir="$(cd -P "$(dirname "$target")" 2>/dev/null && pwd || dirname "$target")"
    if [[ "$raw_link" == /* ]]; then
        abs_link="$raw_link"
    else
        abs_link="${target_dir%/}/$raw_link"
    fi
    canon_link="$(_canonicalize_ownership_path "$abs_link" || true)"
    [ -n "$canon_link" ] || return 1

    local hs_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/home-settings"
    local raw_prefix canon_prefix
    for raw_prefix in "${REPO_DIR:-}" "$hs_cfg" "$allowed_target"; do
        [ -n "$raw_prefix" ] || continue
        canon_prefix="$(_canonicalize_ownership_path "$raw_prefix" || true)"
        [ -n "$canon_prefix" ] || continue
        if [ "$canon_link" = "$canon_prefix" ] || [[ "$canon_link" == "${canon_prefix%/}/"* ]]; then
            return 0
        fi
    done
    return 1
}

unlink_path() {
    local target="$1"
    local allowed_target="${2:-}"
    if [ -L "$target" ] && _is_managed_symlink "$target" "$allowed_target"; then
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
