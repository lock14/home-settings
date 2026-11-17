#!/bin/zsh
# Zsh Color Theme Wrapper (`theme`) & Cross-Pane Precmd Synchronizer (`_hs_sync_active_theme`)
# Sourced by dotfiles/.zsh-functions; consumes `_hs_theme_is_query_call` from functions.sh.

_hs_reload_zsh_theme_files() {
    local hs_dir="${XDG_CONFIG_HOME:-$HOME/.config}/home-settings"
    [ -r "$hs_dir/theme-env.sh" ] && source "$hs_dir/theme-env.sh"
    [ -r "$hs_dir/zsh-theme.zsh" ] && source "$hs_dir/zsh-theme.zsh"
    if [ -r "$hs_dir/p10k-theme.zsh" ]; then
        source "$hs_dir/p10k-theme.zsh"
        local p10k_local="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/p10k.local.zsh"
        [ -r "$p10k_local" ] && source "$p10k_local"
        (( ! $+functions[p10k] )) || p10k reload
    fi
}

theme() {
    local theme_bin=""
    if [ -x "$HOME/.local/bin/theme" ]; then
        theme_bin="$HOME/.local/bin/theme"
    elif whence -p theme >/dev/null 2>&1; then
        theme_bin="$(whence -p theme)"
    else
        echo "Error: 'theme' binary not found in ~/.local/bin or PATH." >&2
        return 1
    fi

    local is_query=0
    if (( $+functions[_hs_theme_is_query_call] )) && _hs_theme_is_query_call "$@"; then
        is_query=1
    fi

    local rc=0
    THEME_SHELL_WRAPPER=1 "$theme_bin" "$@" || rc=$?
    if [ "$rc" -eq 130 ]; then
        return 0
    fi
    if [ "$rc" -eq 0 ] && [ "$is_query" -eq 0 ]; then
        _hs_reload_zsh_theme_files
    fi
    return "$rc"
}

_hs_sync_active_theme() {
    local hs_dir="${XDG_CONFIG_HOME:-$HOME/.config}/home-settings"
    local theme_file="$hs_dir/theme"
    [ -r "$theme_file" ] || return 0
    local active_theme=""
    IFS= read -r active_theme < "$theme_file" || true
    active_theme="${active_theme//$''/}"
    if [ -n "$active_theme" ] && [ "${_HS_LOADED_THEME:-}" != "$active_theme" ]; then
        _HS_LOADED_THEME="$active_theme"
        _hs_reload_zsh_theme_files
    fi
}
