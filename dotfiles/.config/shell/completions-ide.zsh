#!/bin/zsh
# Zsh Tab Completion for `ide` Workspace Launcher, Subcommands, & Aliases
# Sourced by dotfiles/.zsh-completions.

_ide_load_sessions() {
    reply=()
    local ide_bin=""
    if [ -x "$HOME/.local/bin/ide" ]; then
        ide_bin="$HOME/.local/bin/ide"
    elif whence -p ide >/dev/null 2>&1; then
        ide_bin="$(whence -p ide)"
    fi
    if [ -n "$ide_bin" ]; then
        reply=(${(f)"$("$ide_bin" list --plain 2>/dev/null)"})
    fi
}

_ide_load_workspaces() {
    reply=()
    local -a raw_dirs=()
    local rules_file="${IDE_LINK_RULES:-${XDG_CONFIG_HOME:-$HOME/.config}/ide/links.sh}"
    if [[ -r "$rules_file" ]]; then
        local rules_src=""
        rules_src="$(<"$rules_file")" 2>/dev/null || rules_src=""
        if [[ "$rules_src" == *ide_workspace_dirs* ]]; then
            local hook_out=""
            if command -v timeout >/dev/null 2>&1; then
                hook_out="$(timeout 1 bash -c 'source "$1" >/dev/null 2>&1 || exit 1; declare -F ide_workspace_dirs >/dev/null 2>&1 || exit 1; ide_workspace_dirs' _ "$rules_file" 2>/dev/null)" || hook_out=""
            else
                hook_out="$(bash -c 'source "$1" >/dev/null 2>&1 || exit 1; declare -F ide_workspace_dirs >/dev/null 2>&1 || exit 1; ide_workspace_dirs' _ "$rules_file" 2>/dev/null)" || hook_out=""
            fi
            if [[ -n "$hook_out" ]]; then
                raw_dirs+=(${(f)hook_out})
            fi
        fi
    fi
    if [[ -n "${IDE_WORKSPACE_DIRS:-}" ]]; then
        raw_dirs+=(${(s.:.)IDE_WORKSPACE_DIRS})
    fi
    if ! (( ${#raw_dirs} )); then
        return 0
    fi

    local d norm parent b c child_key
    local -A seen=() scanned_parents=() live_children=()
    local -a p_entries=()
    for d in "${raw_dirs[@]}"; do
        d="${d#"${d%%[![:space:]]*}"}"
        d="${d%"${d##*[![:space:]]}"}"
        if [[ -z "$d" ]]; then continue; fi
        if [[ "$d" == "~" ]]; then d="$HOME"; fi
        if [[ "$d" == "~/"* ]]; then d="$HOME/${d#\~/}"; fi
        norm="${d:a}"
        if [[ -z "$norm" || "$norm" == "/" ]]; then continue; fi
        parent="${norm:h}"
        b="${norm:t}"
        if [[ -z "$b" ]]; then continue; fi
        if [[ -z "${scanned_parents[$parent]:-}" ]]; then
            scanned_parents[$parent]=1
            if [[ -d "$parent" ]]; then
                p_entries=( "$parent"/*(N-/:t) )
                for c in "${p_entries[@]}"; do
                    child_key="$parent/$c"
                    live_children[$child_key]=1
                done
            fi
        fi
        child_key="$parent/$b"
        if [[ -z "${live_children[$child_key]:-}" ]]; then continue; fi
        if [[ -z "${seen[$b]:-}" ]]; then
            seen[$b]=1
            reply+=("$b")
        fi
    done
    return 0
}

_ide_offer_unused_sessions() {
    local start_idx="${1:-2}"
    local -a sessions rem_sessions=()
    local s_cand used_idx is_used
    _ide_load_sessions; sessions=("${reply[@]}")
    if ! (( ${#sessions} )); then
        return 0
    fi
    for s_cand in "${sessions[@]}"; do
        is_used=0
        for (( used_idx = start_idx; used_idx < CURRENT; used_idx++ )); do
            if [[ "${words[used_idx]:-}" == "$s_cand" ]]; then
                is_used=1
                break
            fi
        done
        if (( ! is_used )); then
            rem_sessions+=("$s_cand")
        fi
    done
    if (( ${#rem_sessions} )); then
        _describe -t sessions 'IDE session' rem_sessions
    else
        _describe -t sessions 'IDE session' sessions
    fi
    return 0
}

_ide() {
    local -a root_opts switch_opts list_opts quit_opts open_opts send_opts state_opts cd_opts help_opts subcmds agents agent_states sessions reply
    root_opts=(
        '--2pane:Launch 2-pane side-by-side layout (AI and Editor)'
        '--agent:Select AI CLI agent (agy, claude, or codex)'
        '-d:Create or update workspace session in background without attaching'
        '--detach:Create or update workspace session in background without attaching'
        '-s:Open interactive multi-session IDE workspace switcher'
        '-n:Open interactive new-workspace directory picker'
        '-h:Show help message'
        '--help:Show help message'
    )
    switch_opts=(
        '--2pane:Use 2-pane layout when launching a new workspace'
        '--agent:Select AI CLI agent (agy, claude, or codex)'
        '-d:Create new workspace in background without attaching'
        '--detach:Create new workspace in background without attaching'
        '-h:Show help message'
        '--help:Show help message'
    )
    list_opts=(
        '--plain:Print session names only (one per line)'
        '--json:Print machine-readable JSON array of active workspaces'
        '-h:Show help message'
        '--help:Show help message'
    )
    quit_opts=(
        '-f:Skip unsaved-buffer check and terminate immediately'
        '--force:Skip unsaved-buffer check and terminate immediately'
        '-h:Show help message'
        '--help:Show help message'
    )
    open_opts=(
        '-p:Preview file in Main Editor without changing focus'
        '--preview:Preview file in Main Editor without changing focus'
        '-h:Show help message'
        '--help:Show help message'
    )
    send_opts=(
        '--stdin:Read context payload from standard input'
        '--ref:Format file and line reference relative to AI CWD'
        '--text:Send literal text payload to AI Agent'
        '--no-focus:Keep current pane focus when dispatching'
        '--switch:Focus AI pane and switch client to target session'
        '-h:Show help message'
        '--help:Show help message'
    )
    state_opts=(
        '-m:Optional notification message text'
        '--message:Optional notification message text'
        '-h:Show help message'
        '--help:Show help message'
    )
    cd_opts=(
        '--reset:Return Editor and Shell to initial workspace root'
        '-h:Show help message'
        '--help:Show help message'
    )
    help_opts=(
        '-h:Show help message'
        '--help:Show help message'
    )
    subcmds=(
        'list:List active IDE workspace sessions'
        'switch:Open interactive multi-session IDE workspace switcher'
        'new:Open interactive workspace directory picker'
        'next:Jump to oldest IDE session waiting for AI attention'
        'cd:Set working directory across Editor and Shell panes'
        'refresh:Refresh Tmux chrome, Editor themes, and CWDs'
        'quit:Safely close IDE workspace session(s)'
        'open:Open or preview file in the Main Editor pane'
        'send:Stage prompt context into AI Agent pane'
        'state:Record deterministic AI lifecycle state'
        'ack:Acknowledge AI attention across session(s)'
        'pr:Open cached pull or merge request URL'
        'keys:Display IDE keybinding cheatsheet'
        'monitor:Launch system monitor'
    )
    agents=(
        'agy:Default AI CLI agent'
        'claude:Anthropic Claude Code CLI'
        'codex:OpenAI Codex CLI'
    )
    agent_states=(
        'running:AI agent is actively executing a turn'
        'approval:AI agent is waiting for user approval or input'
        'quota:AI agent is waiting for model quota reset'
        'done:AI agent completed its turn'
        'idle:AI agent is idle at prompt'
    )

    local cur="${words[CURRENT]:-}" prev="" cmd_name="${words[1]:-}"
    if (( CURRENT > 1 )); then
        prev="${words[CURRENT-1]:-}"
    fi

    case "$cur" in
        --agent=*)
            if (( ${+compstate} && $+builtins[compset] )); then
                compset -P 1 '*=' || true
            fi
            _describe -t agents 'AI agent CLI' agents
            return 0
            ;;
        --ref=*)
            if (( ${+compstate} && $+builtins[compset] )); then
                compset -P 1 '*=' || true
            fi
            _files
            return 0
            ;;
        --text=*|--message=*)
            return 0
            ;;
    esac
    case "$prev" in
        --agent)
            _describe -t agents 'AI agent CLI' agents
            return 0
            ;;
        --ref)
            _files
            return 0
            ;;
        --text|-m|--message)
            return 0
            ;;
    esac

    # Handle shell aliases directly (`qide`, `quit`, `idek`)
    if [[ "$cmd_name" == (qide|quit|idek) ]]; then
        if [[ "$cur" == -* ]]; then
            _describe -t options 'ide quit option' quit_opts
        else
            _ide_offer_unused_sessions 2
        fi
        return 0
    fi

    # Scan words before CURRENT to locate active subcommand or launch target
    local subcmd="" sub_idx=0 has_launch_pos=0 end_opts=0 idx=2 w=""
    while (( idx < CURRENT )); do
        w="${words[idx]:-}"
        if (( end_opts )); then
            has_launch_pos=1
            idx=$(( idx + 1 ))
            continue
        fi
        case "$w" in
            --)
                end_opts=1
                ;;
            --2pane|-d|--detach|--agent=*|-h|--help)
                ;;
            --agent)
                idx=$(( idx + 1 ))
                ;;
            -s|switch)
                if (( ! has_launch_pos )); then
                    subcmd="switch"
                    sub_idx=$(( idx + 1 ))
                    break
                fi
                ;;
            -n|new)
                if (( ! has_launch_pos )); then
                    subcmd="new"
                    sub_idx=$(( idx + 1 ))
                    break
                fi
                ;;
            list|next|cd|refresh|quit|open|send|state|ack|pr|keys|monitor)
                if (( ! has_launch_pos )) && [[ "$cmd_name" == "ide" ]]; then
                    subcmd="$w"
                    sub_idx=$(( idx + 1 ))
                    break
                fi
                has_launch_pos=1
                ;;
            -*)
                has_launch_pos=1
                ;;
            *)
                has_launch_pos=1
                ;;
        esac
        idx=$(( idx + 1 ))
    done

    if [[ -n "$subcmd" ]]; then
        local -a pos_args=()
        local p_end=0 s_i=$sub_idx sw="" has_send_payload=0 has_list_fmt=0
        while (( s_i < CURRENT )); do
            sw="${words[s_i]:-}"
            if (( p_end )); then
                pos_args+=("$sw")
                s_i=$(( s_i + 1 ))
                continue
            fi
            case "$subcmd:$sw" in
                *:--)
                    p_end=1
                    ;;
                list:--plain|list:--json)
                    has_list_fmt=1
                    ;;
                switch:--agent|new:--agent)
                    s_i=$(( s_i + 1 ))
                    ;;
                send:--stdin|send:--ref=*|send:--text=*)
                    has_send_payload=1
                    ;;
                send:--ref|send:--text)
                    if (( s_i + 1 < CURRENT )); then
                        has_send_payload=1
                        s_i=$(( s_i + 1 ))
                    fi
                    ;;
                state:-m|state:--message)
                    s_i=$(( s_i + 1 ))
                    ;;
                cd:--reset|cd:-)
                    pos_args+=("$sw")
                    ;;
                *:-*)
                    ;;
                *)
                    pos_args+=("$sw")
                    if [[ "$subcmd" == "send" ]] && (( ! has_send_payload )); then
                        has_send_payload=1
                    fi
                    ;;
            esac
            s_i=$(( s_i + 1 ))
        done

        case "$subcmd" in
            keys|monitor)
                if [[ "$cur" == -* ]]; then
                    _describe -t options 'ide option' help_opts
                fi
                return 0
                ;;
            list)
                if (( ! has_list_fmt )) && (( ${#pos_args} == 0 )); then
                    _describe -t options 'ide list option' list_opts
                fi
                return 0
                ;;
            new)
                if [[ "$cur" == -* ]]; then
                    _describe -t options 'ide new option' switch_opts
                fi
                return 0
                ;;
            switch)
                if [[ "$cur" == -* ]]; then
                    _describe -t options 'ide switch option' switch_opts
                elif (( ${#pos_args} == 0 )); then
                    _ide_load_sessions; sessions=("${reply[@]}")
                    if (( ${#sessions} )); then
                        _describe -t sessions 'IDE session' sessions
                    fi
                fi
                return 0
                ;;
            next|refresh|pr)
                if [[ "$cur" == -* ]]; then
                    _describe -t options 'ide option' help_opts
                elif (( ${#pos_args} == 0 )); then
                    _ide_load_sessions; sessions=("${reply[@]}")
                    if (( ${#sessions} )); then
                        _describe -t sessions 'IDE session' sessions
                    fi
                fi
                return 0
                ;;
            cd)
                if [[ "$cur" == -* ]]; then
                    _describe -t options 'ide cd option' cd_opts
                elif (( ${#pos_args} == 0 )); then
                    _files -/
                elif (( ${#pos_args} == 1 )); then
                    _ide_load_sessions; sessions=("${reply[@]}")
                    if (( ${#sessions} )); then
                        _describe -t sessions 'IDE session' sessions
                    fi
                fi
                return 0
                ;;
            quit)
                if [[ "$cur" == -* ]]; then
                    _describe -t options 'ide quit option' quit_opts
                else
                    _ide_offer_unused_sessions "$sub_idx"
                fi
                return 0
                ;;
            ack)
                if [[ "$cur" == -* ]]; then
                    _describe -t options 'ide ack option' help_opts
                else
                    _ide_offer_unused_sessions "$sub_idx"
                fi
                return 0
                ;;
            open)
                if [[ "$cur" == -* ]] && (( ${#pos_args} == 0 )); then
                    _describe -t options 'ide open option' open_opts
                elif (( ${#pos_args} == 0 )); then
                    _files
                elif (( ${#pos_args} == 1 )) || { (( ${#pos_args} == 2 )) && [[ "${pos_args[2]:-}" == (\+|)<-> ]]; }; then
                    _ide_load_sessions; sessions=("${reply[@]}")
                    if (( ${#sessions} )); then
                        _describe -t sessions 'IDE session' sessions
                    fi
                fi
                return 0
                ;;
            send)
                if (( ! has_send_payload )) || [[ "$cur" == -* ]]; then
                    _describe -t options 'ide send option' send_opts
                elif (( ${#pos_args} <= 1 )); then
                    _ide_load_sessions; sessions=("${reply[@]}")
                    if (( ${#sessions} )); then
                        _describe -t sessions 'IDE session' sessions
                    fi
                fi
                return 0
                ;;
            state)
                if [[ "$cur" == -* ]]; then
                    _describe -t options 'ide state option' state_opts
                elif (( ${#pos_args} == 0 )); then
                    _describe -t states 'AI lifecycle state' agent_states
                elif (( ${#pos_args} == 1 )); then
                    _ide_load_sessions; sessions=("${reply[@]}")
                    if (( ${#sessions} )); then
                        _describe -t sessions 'IDE session' sessions
                    fi
                fi
                return 0
                ;;
        esac
    fi

    # Root launch position (`ide`, `ide2`, `ide3`)
    if [[ "$cur" == -* ]] && (( ! end_opts )); then
        _describe -t options 'ide option' root_opts
        return 0
    fi

    if (( ! has_launch_pos )); then
        if [[ "$cmd_name" == "ide" ]] && (( ! end_opts )) && [[ "$cur" != */* && "$cur" != .* && "$cur" != \~* ]]; then
            _describe -t subcommands 'ide command' subcmds
        fi
        _ide_load_sessions; sessions=("${reply[@]}")
        if (( ${#sessions} )); then
            _describe -t sessions 'IDE session' sessions
        fi
        if [[ "$cur" != */* && "$cur" != .* && "$cur" != \~* ]]; then
            local -a workspaces=() rem_workspaces=()
            local ws_cand s_existing dup_ws
            _ide_load_workspaces; workspaces=("${reply[@]}")
            for ws_cand in "${workspaces[@]}"; do
                dup_ws=0
                for s_existing in "${sessions[@]}"; do
                    if [[ "$s_existing" == "$ws_cand" ]]; then
                        dup_ws=1
                        break
                    fi
                done
                if (( ! dup_ws )); then
                    rem_workspaces+=("${ws_cand//:/\\:}")
                fi
            done
            if (( ${#rem_workspaces} )); then
                _describe -t workspaces 'workspace' rem_workspaces
            fi
        fi
        _files -/
    fi
    return 0
}
if (( $+functions[compdef] )); then
    compdef _ide ide ide2 ide3 qide idek quit 2>/dev/null || true
fi
