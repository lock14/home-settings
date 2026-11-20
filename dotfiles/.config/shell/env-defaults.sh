#!/bin/sh
# Shared XDG Base Directory paths and Solarized Dark environment defaults.
# Sourced by dotfiles/.environment-variables and dotfiles/.bashrc-addendum.

_hs_prepend_path() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) export PATH="$1:$PATH" ;;
    esac
}

if [ "${_HS_ENV_PRESERVE_EXISTING:-0}" = "1" ]; then
    if [ -z "${_HS_CALLER_COLORTERM_SET:-}" ]; then
        export COLORTERM="truecolor"
    else
        export COLORTERM="${_HS_CALLER_COLORTERM_VAL:-}"
    fi
    export FORCE_HYPERLINK="${FORCE_HYPERLINK:-1}"
else
    export COLORTERM=truecolor
    export FORCE_HYPERLINK=1
fi

# Standard user binaries and Mise runtime shims
if [ "${_HS_ENV_PRESERVE_EXISTING:-0}" = "1" ]; then
    _hs_prepend_path "$HOME/.local/bin"
else
    export PATH="$HOME/.local/bin:$PATH"
    export MISE_YES=1
    if [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims" ]; then
        export PATH="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:$PATH"
    fi
fi

# Go workspace and build cache (XDG Base Directory compliant)
export GOPATH="${XDG_DATA_HOME:-$HOME/.local/share}/go"
export GOCACHE="${XDG_CACHE_HOME:-$HOME/.cache}/go-build"
if [ "${_HS_ENV_PRESERVE_EXISTING:-0}" = "1" ]; then
    _hs_prepend_path "$GOPATH/bin"
else
    export PATH="$GOPATH/bin:$PATH"
fi

# Lean 4 / Elan toolchain home (XDG Base Directory compliant)
export ELAN_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/elan"
if [ "${_HS_ENV_PRESERVE_EXISTING:-0}" = "1" ]; then
    _hs_prepend_path "$ELAN_HOME/bin"
else
    export PATH="$ELAN_HOME/bin:$PATH"
fi
unset -f _hs_prepend_path

# Default editor (prefer nvim if available, fallback to vim then vi)
if command -v nvim >/dev/null 2>&1; then
    export EDITOR=nvim
elif command -v vim >/dev/null 2>&1; then
    export EDITOR=vim
elif command -v vi >/dev/null 2>&1; then
    export EDITOR=vi
fi
export VISUAL="${EDITOR:-vi}"

# Default AI CLI agent for Hybrid IDE workspace (agy | claude | codex)
export IDE_AI_CLI="${IDE_AI_CLI:-agy}"

# Pin SSH_AUTH_SOCK to stable ~/.ssh/ssh_auth_sock symlink when present (survives tmux and SSH reconnects)
if [ -S "$HOME/.ssh/ssh_auth_sock" ] || { [ -L "$HOME/.ssh/ssh_auth_sock" ] && [ ! -S "${SSH_AUTH_SOCK:-}" ]; }; then
    export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"
fi

# Default Solarized Dark TrueColor tool palettes
_hs_def_eza="di=38;2;38;139;210:ex=38;2;133;153;0:fi=38;2;131;148;150:pi=38;2;181;137;0:so=38;2;211;54;130:bd=38;2;211;54;130:cd=38;2;211;54;130:ln=38;2;42;161;152:or=38;2;220;50;47:xx=38;2;88;110;117:da=38;2;131;148;150:hd=4;38;2;147;161;161:lp=38;2;131;148;150:cc=38;2;203;75;22:bO=38;2;220;50;47:in=38;2;88;110;117:bl=38;2;88;110;117:oc=38;2;131;148;150:ur=38;2;131;148;150:uw=38;2;131;148;150:ux=38;2;131;148;150:ue=38;2;131;148;150:gr=38;2;131;148;150:gw=38;2;131;148;150:gx=38;2;131;148;150:tr=38;2;131;148;150:tw=38;2;131;148;150:tx=38;2;131;148;150:su=38;2;131;148;150:sf=38;2;131;148;150:xa=38;2;131;148;150:sn=38;2;131;148;150:nb=38;2;88;110;117:nk=38;2;131;148;150:nm=38;2;181;137;0:ng=38;2;203;75;22:nt=38;2;220;50;47:sb=38;2;131;148;150:ub=38;2;88;110;117:uk=38;2;131;148;150:um=38;2;181;137;0:ug=38;2;203;75;22:ut=38;2;220;50;47:df=38;2;131;148;150:ds=38;2;131;148;150:uu=38;2;131;148;150:uR=38;2;220;50;47:un=38;2;131;148;150:gu=38;2;131;148;150:gR=38;2;220;50;47:gn=38;2;131;148;150:lc=38;2;131;148;150:lm=38;2;181;137;0:ga=38;2;133;153;0:gm=38;2;181;137;0:gd=38;2;220;50;47:gv=38;2;131;148;150:gt=38;2;131;148;150:gi=38;2;88;110;117:gc=38;2;220;50;47:Gm=38;2;133;153;0:Go=38;2;38;139;210:Gc=38;2;133;153;0:Gd=38;2;181;137;0:sp=38;2;203;75;22:mp=38;2;38;139;210:im=38;2;108;113;196:vi=38;2;108;113;196:mu=38;2;108;113;196:lo=38;2;108;113;196:cr=38;2;211;54;130:do=38;2;131;148;150:co=38;2;203;75;22:tm=38;2;88;110;117:cm=38;2;88;110;117:bu=38;2;133;153;0:sc=38;2;131;148;150:Sn=38;2;88;110;117:Su=38;2;131;148;150:Sr=38;2;131;148;150:St=38;2;131;148;150:Sl=38;2;131;148;150:ff=38;2;131;148;150"
_hs_def_fzf='--color=bg+:#073642,bg:#002B36,spinner:#859900,hl:#586E75 --color=fg:#839496,header:#586E75,info:#B58900,pointer:#859900 --color=marker:#859900,fg+:#93A1A1,prompt:#B58900,hl+:#268BD2 --layout=reverse --border=rounded --info=inline'
_hs_def_jq="38;2;211;54;130:38;2;211;54;130:38;2;211;54;130:38;2;211;54;130:38;2;42;161;152:38;2;131;148;150:38;2;131;148;150:38;2;133;153;0"
_hs_def_zo_fzf="--height=50% --layout=reverse --border=rounded --inline-info --preview='eza -la --icons=auto --color=always --group-directories-first {2..} 2>/dev/null || ls -la {2..}' --preview-window='right:50%:wrap'"

if [ "${_HS_ENV_PRESERVE_EXISTING:-0}" = "1" ]; then
    export BAT_THEME="${BAT_THEME:-Solarized-Dark-TrueColor}"
    export BAT_OPTS="${BAT_OPTS:---italic-text=always}"
    export EZA_COLORS="${EZA_COLORS:-$_hs_def_eza}"
    export EXA_COLORS="$EZA_COLORS"
    export LSCOLORS="${LSCOLORS:-exgxfxdxcxfxfxegedabagacad}"
    export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-$_hs_def_fzf}"
    export JQ_COLORS="${JQ_COLORS:-$_hs_def_jq}"
    export _ZO_ECHO="${_ZO_ECHO:-1}"
    export _ZO_RESOLVE_SYMLINKS="${_ZO_RESOLVE_SYMLINKS:-1}"
    export _ZO_FZF_OPTS="${_ZO_FZF_OPTS:-$_hs_def_zo_fzf}"
    export GROFF_NO_SGR="${GROFF_NO_SGR:-1}"
else
    export BAT_THEME="Solarized-Dark-TrueColor"
    export BAT_OPTS="--italic-text=always"
    export EZA_COLORS="$_hs_def_eza"
    export EXA_COLORS="$EZA_COLORS"
    export LSCOLORS="exgxfxdxcxfxfxegedabagacad"
    export FZF_DEFAULT_OPTS="$_hs_def_fzf"
    if command -v rg >/dev/null 2>&1; then
        export FZF_DEFAULT_COMMAND='rg --files --hidden --glob !.git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    elif command -v fd >/dev/null 2>&1; then
        export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    fi
    export JQ_COLORS="$_hs_def_jq"
    export _ZO_ECHO=1
    export _ZO_RESOLVE_SYMLINKS=1
    export _ZO_FZF_OPTS="$_hs_def_zo_fzf"
    export GROFF_NO_SGR=1
fi
unset _hs_def_eza _hs_def_fzf _hs_def_jq _hs_def_zo_fzf

# Solarized Dark manpage and pager colors (zero forks in Bash and Zsh)
export LESS="${LESS:--R}"
if [ -n "${BASH_VERSION:-}${ZSH_VERSION:-}" ]; then
    eval "_hs_esc=\$'\033'"
else
    _hs_esc="$(printf '\033')"
fi
export LESS_TERMCAP_mb="${_hs_esc}[38;2;220;50;47m"
export LESS_TERMCAP_md="${_hs_esc}[1;38;2;38;139;210m"
export LESS_TERMCAP_me="${_hs_esc}[0m"
export LESS_TERMCAP_so="${_hs_esc}[38;2;147;161;161;48;2;7;54;66m"
export LESS_TERMCAP_se="${_hs_esc}[0m"
export LESS_TERMCAP_us="${_hs_esc}[4;38;2;42;161;152m"
export LESS_TERMCAP_ue="${_hs_esc}[0m"
unset _hs_esc

if [ "${_HS_ENV_PRESERVE_EXISTING:-0}" != "1" ]; then
    # Source active color theme overrides (managed by bin/theme)
    if [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/home-settings/theme-env.sh" ]; then
        # shellcheck source=/dev/null
        . "${XDG_CONFIG_HOME:-$HOME/.config}/home-settings/theme-env.sh"
    fi

    # Source custom environment drop-ins (~/.environment-variables.d/*.sh)
    if [ -d "$HOME/.environment-variables.d" ]; then
        _source_env_dropins() {
            if [ -n "${ZSH_VERSION:-}" ]; then
                setopt local_options null_glob
            fi
            for _f in "$HOME/.environment-variables.d"/*.sh; do
                if [ -r "$_f" ]; then
                    # shellcheck source=/dev/null
                    . "$_f"
                fi
            done
            unset _f
        }
        _source_env_dropins
        unset -f _source_env_dropins
    fi
fi
