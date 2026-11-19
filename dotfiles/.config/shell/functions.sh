# Shared Interactive Shell Functions (Zsh and Bash 3.2+ compatible)
# Provides stale CWD recovery, Hybrid IDE Tmux/Neovim RPC helpers (`v`, `icd`),
# `fs`, `gsync`, `theme` query classification, and 6-path legacy `fzf` discovery.

# Self-healing recovery when the current working directory descriptor (.) becomes
# stale or disconnected (such as after a FUSE or network workspace mount restarts)
# while the logical path $PWD is accessible again.
_hs_recover_stale_cwd() {
    if { [ ! -d . ] || [ ! . -ef "${PWD:-}" ]; } && [[ "${PWD:-}" == /* ]] && [ -d "$PWD" ]; then
        if [ -n "${ZSH_VERSION:-}" ]; then
            setopt localoptions noautopushd nochaselinks nochasedots noposixcd nocdablevars
            local _hs_has_oldpwd="${OLDPWD+1}" _hs_oldpwd="${OLDPWD:-}"
            if builtin cd -q -- "$PWD"; then
                if [ -n "$_hs_has_oldpwd" ]; then
                    OLDPWD="$_hs_oldpwd"
                else
                    unset OLDPWD
                fi
            fi
        else
            local _hs_has_oldpwd="${OLDPWD+1}" _hs_oldpwd="${OLDPWD:-}"
            if builtin cd -L -- "$PWD"; then
                if [ -n "$_hs_has_oldpwd" ]; then
                    OLDPWD="$_hs_oldpwd"
                else
                    unset OLDPWD
                fi
            fi
        fi
    fi
}

# Verify exact caller Tmux pane or session ID and server PID before querying IDE options.
_ide_tmux_target() {
    local with_meta=0
    if [ "${1:-}" = "-m" ]; then
        with_meta=1
    fi
    [[ "${TMUX:-}" == *,*,* ]] && command -v tmux >/dev/null 2>&1 || return 1
    local tmux_rest="${TMUX%,*}"
    local tmux_pid="${tmux_rest##*,}"
    local tmux_sid="${TMUX##*,}"
    tmux_sid="${tmux_sid#\$}"
    local tmux_target="${TMUX_PANE:-}"
    if [ -z "$tmux_target" ] && [[ "$tmux_sid" =~ ^[0-9]+$ ]]; then
        tmux_target="\$$tmux_sid"
    fi
    [ -n "$tmux_target" ] || return 1
    local id_fmt='#{session_id}'
    [[ "$tmux_target" == %* ]] && id_fmt='#{pane_id}'
    if [ "$with_meta" = "1" ]; then
        local srv_info srv_prefix
        srv_info="$(tmux display-message -p -t "$tmux_target" "#{pid}:${id_fmt}"$'\t'"#{@ide_socket}"$'\t'"#{@ide_editor_pane}"$'\t'"#{@ide_role}"$'\t'"#{pane_pid}" 2>/dev/null || true)"
        srv_prefix="${srv_info%%$'\t'*}"
        [ "$srv_prefix" = "$tmux_pid:$tmux_target" ] || return 1
        printf '%s' "${tmux_target}"$'\t'"${srv_info#*$'\t'}"
        return 0
    fi
    local srv_info
    srv_info="$(tmux display-message -p -t "$tmux_target" "#{pid}:${id_fmt}" 2>/dev/null || true)"
    [ "$srv_info" = "$tmux_pid:$tmux_target" ] || return 1
    printf '%s' "$tmux_target"
}

# Hybrid IDE RPC-aware editor launcher (`v [files...]`).
# Routes file opens into the active Tmux and Neovim IDE pane when $NVIM_IDE_SOCKET is live,
# while keeping $EDITOR=nvim intact so `git commit` and `gcommit` block properly.
unalias v 2>/dev/null || true
v() {
    _hs_recover_stale_cwd
    local sock="${NVIM_IDE_SOCKET:-}"
    local pane="${NVIM_IDE_PANE:-}"
    local tmux_sock=""
    local -a abs_args=()
    local -a plus_cmds=()
    local local_only=0
    local expect_cmd=0
    local end_of_opts=0
    local arg dir base p_cmd esc_cmd
    for arg in "$@"; do
        if [ "$expect_cmd" = "1" ]; then
            plus_cmds+=("$arg")
            expect_cmd=0
            continue
        fi
        if [ "$end_of_opts" = "0" ]; then
            if [ "$arg" = "--" ]; then
                end_of_opts=1
                continue
            elif [[ "$arg" == +* ]]; then
                p_cmd="${arg#+}"
                [ -z "$p_cmd" ] && p_cmd="$"
                plus_cmds+=("$p_cmd")
                continue
            elif [ "$arg" = "-c" ] || [ "$arg" = "--cmd" ]; then
                expect_cmd=1
                continue
            elif [[ "$arg" == -* ]]; then
                local_only=1
                break
            fi
        fi
        if [[ "$arg" == /* ]]; then
            abs_args+=("$arg")
        elif [ -n "${ZSH_VERSION:-}" ]; then
            eval 'abs_args+=("${arg:A}")'
        else
            case "$arg" in
                */*)
                    dir="${arg%/*}"
                    [ -z "$dir" ] && dir="/"
                    base="${arg##*/}"
                    ;;
                *)
                    dir="."
                    base="$arg"
                    ;;
            esac
            if [ "$base" = "." ] || [ "$base" = ".." ]; then
                if [ -d "$arg" ]; then
                    abs_args+=("$(builtin cd -P -- "$arg" && pwd -P)")
                else
                    abs_args+=("$PWD/$arg")
                fi
            elif [ -d "$dir" ]; then
                abs_args+=("$(builtin cd -P -- "$dir" && pwd -P)/$base")
            else
                abs_args+=("$PWD/${arg#./}")
            fi
        fi
    done
    [ "$expect_cmd" = "1" ] && local_only=1

    local tmux_target="" tmux_meta="" tmux_meta_rest="" tmux_ed_pane="" tmux_role="" tmux_pane_pid="" is_editor_pane=0
    if [ -n "${TMUX:-}" ]; then
        tmux_meta="$(_ide_tmux_target -m || true)"
    fi
    if [ -n "$tmux_meta" ]; then
        tmux_target="${tmux_meta%%$'\t'*}"
        tmux_meta_rest="${tmux_meta#*$'\t'}"
        tmux_sock="${tmux_meta_rest%%$'\t'*}"
        tmux_meta_rest="${tmux_meta_rest#*$'\t'}"
        tmux_ed_pane="${tmux_meta_rest%%$'\t'*}"
        tmux_meta_rest="${tmux_meta_rest#*$'\t'}"
        tmux_role="${tmux_meta_rest%%$'\t'*}"
        tmux_pane_pid="${tmux_meta_rest#*$'\t'}"
        if [ -z "$tmux_sock" ]; then
            local env_sock
            env_sock="$(tmux show-environment -t "$tmux_target" NVIM_IDE_SOCKET 2>/dev/null || true)"
            if [[ "$env_sock" == NVIM_IDE_SOCKET=* ]]; then
                tmux_sock="${env_sock#NVIM_IDE_SOCKET=}"
            fi
        fi
        [ -z "$sock" ] && sock="$tmux_sock"
        if [ -z "$pane" ]; then
            pane="$tmux_ed_pane"
            if [ -z "$pane" ]; then
                local env_pane
                env_pane="$(tmux show-environment -t "$tmux_target" NVIM_IDE_PANE 2>/dev/null || true)"
                if [[ "$env_pane" == NVIM_IDE_PANE=* ]]; then
                    pane="${env_pane#NVIM_IDE_PANE=}"
                fi
            fi
        fi
        if [[ "${TMUX_PANE:-}" == %* ]]; then
            if { [ -n "$tmux_ed_pane" ] && [ "$TMUX_PANE" = "$tmux_ed_pane" ]; } || [ "$tmux_role" = "editor" ]; then
                is_editor_pane=1
            fi
        fi
    fi

    local ide_bin="" has_timeout=0 can_heal=0
    command -v timeout >/dev/null 2>&1 && has_timeout=1
    if [ -n "${TMUX:-}" ]; then
        if [ -x "$HOME/.local/bin/ide" ]; then
            ide_bin="$HOME/.local/bin/ide"
        elif command -v ide >/dev/null 2>&1; then
            ide_bin="$(command -v ide)"
        fi
    fi
    if [ -n "$tmux_meta" ] && [ -n "$ide_bin" ]; then
        if [ "$is_editor_pane" = "0" ] || [ -n "${NVIM:-}" ] || { [ -n "$tmux_pane_pid" ] && [ "$$" != "$tmux_pane_pid" ]; }; then
            can_heal=1
        fi
    fi

    if [ "$can_heal" = "1" ] && [ -n "$sock" ] && [ ! -S "$sock" ]; then
        if [ "$local_only" = "0" ] || [ "$is_editor_pane" = "1" ]; then
            "$ide_bin" --heal-socket >/dev/null 2>&1 || true
        fi
    fi

    if [ -n "$sock" ] && [ -S "$sock" ] && command -v nvim >/dev/null 2>&1; then
        if [ "$local_only" = "0" ]; then
            local rpc_check_expr='exists("*luaeval") ? luaeval("(function() local u=vim.uv or vim.loop; if u then local p=nil; for _,c in ipairs({vim.env.PWD or \"\",vim.env.IDE_WORKDIR or \"\",vim.env.IDE_INITIAL_ROOT or \"\"}) do if c and c~=\"\" and vim.fn.isdirectory(c)==1 then p=c; break end end; if p then local d,s=u.fs_stat(\".\"),u.fs_stat(p); if not u.cwd() or not d or d.nlink==0 or (vim.fn.haslocaldir()==0 and vim.fn.haslocaldir(-1,0)==0 and s and (d.dev~=s.dev or d.ino~=s.ino)) then pcall(vim.fn.chdir,p); vim.env.PWD=p end end end; pcall(vim.cmd,\"silent! checktime\"); return 1 end)()") : len(execute("silent! checktime"))+1'
            local rpc_ready=0 rpc_rc=0
            if [ "$has_timeout" = "1" ]; then
                timeout 3 nvim --headless --server "$sock" --remote-expr "$rpc_check_expr" >/dev/null 2>&1 || rpc_rc=$?
            else
                nvim --headless --server "$sock" --remote-expr "$rpc_check_expr" >/dev/null 2>&1 || rpc_rc=$?
            fi
            if [ "$rpc_rc" = "0" ]; then
                rpc_ready=1
            elif [ "$rpc_rc" != "124" ] && [ "$rpc_rc" != "137" ]; then
                rm -f "$sock" 2>/dev/null || true
                if [ "$can_heal" = "1" ] && "$ide_bin" --heal-socket >/dev/null 2>&1 && [ -S "$sock" ]; then
                    rpc_rc=0
                    if [ "$has_timeout" = "1" ]; then
                        timeout 3 nvim --headless --server "$sock" --remote-expr "$rpc_check_expr" >/dev/null 2>&1 || rpc_rc=$?
                    else
                        nvim --headless --server "$sock" --remote-expr "$rpc_check_expr" >/dev/null 2>&1 || rpc_rc=$?
                    fi
                    if [ "$rpc_rc" = "0" ]; then
                        rpc_ready=1
                    elif [ "$rpc_rc" != "124" ] && [ "$rpc_rc" != "137" ]; then
                        rm -f "$sock" 2>/dev/null || true
                    fi
                fi
            fi
            if [ "$rpc_ready" = "1" ]; then
                if [ "${#abs_args[@]}" -gt 0 ]; then
                    if [ "$has_timeout" = "1" ]; then
                        timeout 5 nvim --server "$sock" --remote "${abs_args[@]}"
                    else
                        nvim --server "$sock" --remote "${abs_args[@]}"
                    fi
                fi
                if [ "${#plus_cmds[@]}" -gt 0 ]; then
                    for p_cmd in "${plus_cmds[@]}"; do
                        esc_cmd="${p_cmd//\\/\\\\}"
                        esc_cmd="${esc_cmd//\"/\\\"}"
                        if [ "$has_timeout" = "1" ]; then
                            timeout 3 nvim --headless --server "$sock" --remote-expr "execute(\"$esc_cmd\")" >/dev/null 2>&1 || true
                        else
                            nvim --headless --server "$sock" --remote-expr "execute(\"$esc_cmd\")" >/dev/null 2>&1 || true
                        fi
                    done
                fi
                if [ -n "${TMUX:-}" ] && { [ -z "$tmux_sock" ] || [ "$sock" = "$tmux_sock" ]; }; then
                    local cur_pane="${TMUX_PANE:-}"
                    if [ -z "$pane" ] || [ "$cur_pane" != "$pane" ]; then
                        if [ -n "$ide_bin" ]; then
                            IDE_SKIP_CHECKTIME=1 "$ide_bin" --focus-editor >/dev/null 2>&1 || true
                        elif [ -n "$pane" ]; then
                            tmux select-window -t "$pane" 2>/dev/null || true
                            tmux select-pane -t "$pane" 2>/dev/null || true
                        fi
                    fi
                fi
                return 0
            fi
        else
            local ping_rc=0
            if [ "$has_timeout" = "1" ]; then
                timeout 3 nvim --headless --server "$sock" --remote-expr "1" >/dev/null 2>&1 || ping_rc=$?
            else
                nvim --headless --server "$sock" --remote-expr "1" >/dev/null 2>&1 || ping_rc=$?
            fi
            if [ "$ping_rc" != "0" ] && [ "$ping_rc" != "124" ] && [ "$ping_rc" != "137" ]; then
                rm -f "$sock" 2>/dev/null || true
            fi
        fi
    fi

    if command -v nvim >/dev/null 2>&1; then
        local use_listen=0
        if [ "$is_editor_pane" = "1" ] && [ -z "${NVIM:-}" ] && [ -n "$sock" ] && [ ! -e "$sock" ] && [ ! -L "$sock" ]; then
            use_listen=1
            local v_arg v_skip_val=0
            for v_arg in "$@"; do
                if [ "$v_skip_val" = "1" ]; then
                    v_skip_val=0
                    continue
                fi
                [ "$v_arg" = "--" ] && break
                case "$v_arg" in
                    -c|--cmd|-u|-i|-s|-S|--startuptime)
                        v_skip_val=1
                        ;;
                    --listen|--listen=*|--server|--server=*|--remote*|--headless|--embed|--api-info|-l|-v|--version|-h|--help|-\?|-e|-E|-es|-Es)
                        use_listen=0
                        break
                        ;;
                esac
            done
        fi
        if [ "$use_listen" = "1" ]; then
            local sock_dir="${sock%/*}"
            if [ -n "$sock_dir" ] && [ "$sock_dir" != "$sock" ] && [ ! -d "$sock_dir" ]; then
                { mkdir -p "$sock_dir" && chmod 700 "$sock_dir"; } 2>/dev/null || true
            fi
            command nvim --listen "$sock" "$@"
        else
            command nvim "$@"
        fi
    elif command -v vim >/dev/null 2>&1; then
        command vim "$@"
    else
        command vi "$@"
    fi
}

# Dive IDE Workspace (`icd [dir|--reset|~]`):
# Synchronizes the working directory across the current shell and Main Neovim Editor
# without killing or respawning the active AI Agent pane.
icd() {
    _hs_recover_stale_cwd
    local ide_bin="$HOME/.local/bin/ide"
    if [ ! -x "$ide_bin" ] && command -v ide >/dev/null 2>&1; then
        ide_bin="$(command -v ide)"
    fi

    if [ "${1:-}" = "--reset" ] || [ "${1:-}" = "~" ]; then
        local init_root="${IDE_INITIAL_ROOT:-}"
        if [ -z "$init_root" ] && [ -n "${TMUX:-}" ]; then
            local tmux_target
            tmux_target="$(_ide_tmux_target || true)"
            if [ -n "$tmux_target" ]; then
                init_root="$(tmux show-options -qv -t "$tmux_target" @ide_initial_root 2>/dev/null || true)"
            fi
        fi
        if [ -n "$init_root" ] && [ -d "$init_root" ]; then
            builtin cd -- "$init_root" || return 1
        else
            builtin cd || return 1
        fi
    elif [ "$#" -gt 0 ]; then
        builtin cd -- "$1" || return 1
    fi

    if [ -n "${TMUX:-}" ] && [ -x "$ide_bin" ]; then
        IDE_CD_SKIP_SHELL=1 "$ide_bin" --cd "$PWD"
    fi
}

# Render unignored directory tree via `fd` (or `fdfind`) and `tree --fromfile`.
fs() {
    local fd_cmd=""
    if command -v fd >/dev/null 2>&1; then
        fd_cmd="fd"
    elif command -v fdfind >/dev/null 2>&1; then
        fd_cmd="fdfind"
    else
        echo "Error: 'fd' (or 'fdfind') is not installed." >&2
        return 1
    fi

    if ! command -v tree >/dev/null 2>&1; then
        echo "Error: 'tree' is not installed." >&2
        return 1
    fi

    "$fd_cmd" --no-ignore-vcs "$@" | tree --fromfile
}

# Rebase current branch onto updated origin/main (or origin/master) while preserving working branch.
gsync() {
    local current_branch target_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || {
        echo "Error: not in a git repository" >&2
        return 1
    }

    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo "Error: working directory has uncommitted changes. Please stash or commit before running gsync." >&2
        return 1
    fi

    if git show-ref --verify --quiet refs/heads/main; then
        target_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        target_branch="master"
    else
        echo "Error: neither 'main' nor 'master' branch found locally." >&2
        return 1
    fi

    if [ "$current_branch" = "$target_branch" ]; then
        git pull --rebase origin "$target_branch"
    else
        git checkout "$target_branch" && \
        git pull --rebase origin "$target_branch" && \
        git checkout "$current_branch" && \
        git rebase "$target_branch"
    fi
}

# Return 0 if `theme` arguments represent a read-only query or non-TTY listing (skipping shell reload).
_hs_theme_is_query_call() {
    local arg has_target=0
    for arg in "$@"; do
        case "$arg" in
            -l|--list|--plain|-c|--current|-p|--preview|--preview=*|--env|--env=*|--create|--create=*|--path|-n|--dry-run|--dry-run=*|-h|--help|--sync-assets)
                return 0
                ;;
        esac
        if [ "$arg" != "--no-live" ]; then
            has_target=1
        fi
    done
    if [ "$has_target" -eq 0 ] && { [ ! -t 0 ] || [ ! -t 1 ]; } && [ "${THEME_FORCE_FZF:-0}" != "1" ]; then
        return 0
    fi
    return 1
}

# Initialize `fzf` keybindings and completions for `zsh` or `bash`, falling back across
# ~/.fzf/shell, Homebrew, and standard Linux package paths when fzf < 0.48.0 lacks --zsh/--bash.
_hs_init_fzf() {
    local shell_ext="${1:-bash}"
    command -v fzf >/dev/null 2>&1 || return 1
    if fzf "--${shell_ext}" >/dev/null 2>&1; then
        eval "$(fzf "--${shell_ext}")"
        return 0
    fi
    local fzf_dir
    for fzf_dir in \
        "$HOME/.fzf/shell" \
        /opt/homebrew/opt/fzf/shell \
        /usr/local/opt/fzf/shell \
        /usr/share/fzf/shell \
        /usr/share/fzf \
        /usr/share/doc/fzf/examples; do
        if [ -f "$fzf_dir/key-bindings.${shell_ext}" ]; then
            # shellcheck source=/dev/null
            . "$fzf_dir/key-bindings.${shell_ext}"
            if [ -f "$fzf_dir/completion.${shell_ext}" ]; then
                # shellcheck source=/dev/null
                . "$fzf_dir/completion.${shell_ext}" || true
            fi
            return 0
        fi
    done
    return 1
}
