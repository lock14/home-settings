#!/bin/bash
# Shared symlink creation, ownership verification, and Bat cache helpers.

_link_path() {
    local flags="$1"
    local src="$2"
    local dst="$3"

    if [ "${DRY_RUN:-false}" = true ]; then
        echo "  [DryRun] ln $flags $src $dst"
    else
        mkdir -p "$(dirname "$dst")"
        if [ -e "$dst" ] && [ ! -L "$dst" ]; then
            local bak
            if declare -F backup_existing_path >/dev/null 2>&1; then
                bak="$(backup_existing_path "$dst")"
            else
                local base_bak
                local idx=1
                base_bak="${dst}.bak.$(date +%s)"
                bak="$base_bak"
                while [ -e "$bak" ] || [ -L "$bak" ]; do
                    bak="${base_bak}.${idx}"
                    idx=$((idx + 1))
                done
                mv "$dst" "$bak"
            fi
            echo "  Backing up pre-existing path to $bak"
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

# Symlink all matching files in src_dir into dest_dir (creating dest_dir when live).
link_glob_files() {
    local src_dir="$1"
    local glob_pat="$2"
    local dest_dir="$3"
    [ -d "$src_dir" ] || return 0
    [ "${DRY_RUN:-false}" = true ] || mkdir -p "$dest_dir"
    local item
    # shellcheck disable=SC2231
    for item in "$src_dir"/$glob_pat; do
        [ -e "$item" ] || continue
        link_file "$item" "$dest_dir/$(basename "$item")"
    done
}

# Print top-level regular dotfile paths managed from dotfiles_dir (one per line).
list_managed_top_dotfiles() {
    local dotfiles_dir="$1"
    [ -d "$dotfiles_dir" ] || return 0
    local src name
    for src in "$dotfiles_dir"/.* "$dotfiles_dir"/*; do
        [ -e "$src" ] || continue
        name="$(basename "$src")"
        case "$name" in
            .|..|.git|.gitignore|.config|.dir-colors|'*') continue ;;
        esac
        if [ -f "$src" ]; then
            printf '%s\n' "$src"
        fi
    done
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

# Remove dangling symlinks directly inside dest_dir whose target points under source_prefix.
prune_dangling_managed_symlinks() {
    local dest_dir="$1"
    local source_prefix="$2"
    [ -d "$dest_dir" ] || return 0
    local existing target_link
    for existing in "$dest_dir"/*; do
        if [ -L "$existing" ] && [ ! -e "$existing" ]; then
            target_link="$(readlink "$existing" 2>/dev/null || true)"
            if [[ "$target_link" == *"$source_prefix"* ]]; then
                unlink_path "$existing"
            fi
        fi
    done
}

rebuild_bat_cache() {
    local mise_bin="${1:-}"
    if [ -n "$mise_bin" ] && "$mise_bin" which bat >/dev/null 2>&1; then
        "$mise_bin" exec -- bat cache --build >/dev/null
    elif command -v bat >/dev/null 2>&1; then
        bat cache --build >/dev/null
    elif command -v batcat >/dev/null 2>&1; then
        batcat cache --build >/dev/null
    elif command -v mise >/dev/null 2>&1 && mise which bat >/dev/null 2>&1; then
        mise exec -- bat cache --build >/dev/null
    fi
}
