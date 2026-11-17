#!/bin/zsh
# Zsh Tab Completion for `ide` Workspace Launcher, Session Switcher, & Aliases
# Sourced by dotfiles/.zsh-completions.

# Completion for `ide` workspace launcher, session switcher, and session aliases
_ide_load_sessions() {
    reply=()
    local ide_bin=""
    if [ -x "$HOME/.local/bin/ide" ]; then
        ide_bin="$HOME/.local/bin/ide"
    elif whence -p ide >/dev/null 2>&1; then
        ide_bin="$(whence -p ide)"
    fi
    if [ -n "$ide_bin" ]; then
        reply=(${(f)"$("$ide_bin" --list --plain 2>/dev/null)"})
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
    (( ${#raw_dirs} )) || return 0

    local d norm parent b c child_key
    local -A seen=() scanned_parents=() live_children=()
    local -a p_entries=()
    for d in "${raw_dirs[@]}"; do
        d="${d#"${d%%[![:space:]]*}"}"
        d="${d%"${d##*[![:space:]]}"}"
        [[ -z "$d" ]] && continue
        [[ "$d" == "~" ]] && d="$HOME"
        [[ "$d" == "~/"* ]] && d="$HOME/${d#\~/}"
        norm="${d:a}"
        [[ -z "$norm" || "$norm" == "/" ]] && continue
        parent="${norm:h}"
        b="${norm:t}"
        [[ -z "$b" ]] && continue
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
        [[ -n "${live_children[$child_key]:-}" ]] || continue
        if [[ -z "${seen[$b]:-}" ]]; then
            seen[$b]=1
            reply+=("$b")
        fi
    done
}

_ide() {
    local -a opts send_opts list_opts subcmds agents agent_states swap_dirs sessions reply
    opts=(
        '--3pane:Launch default 3-pane layout (AI, Editor, and Shell)'
        '--2pane:Launch 2-pane layout (AI and Editor)'
        '--ai:Select AI CLI agent (agy, claude, or codex)'
        '--agent:Select AI CLI agent (agy, claude, or codex)'
        '--open:Open file in the Main Editor pane via RPC and focus Editor'
        '--preview:Preview file in the Main Editor pane via RPC without changing focus'
        '--cd:Dive into directory across Editor and Shell'
        '-n:Open interactive new-workspace directory picker'
        '--new:Open interactive new-workspace directory picker'
        '-s:Open interactive multi-session IDE workspace switcher'
        '--sessions:Open interactive multi-session IDE workspace switcher'
        '--next-attention:Jump to oldest IDE session waiting for AI attention'
        '--agent-state:Record deterministic AI lifecycle state (running, approval, quota, done, or idle)'
        '--message:Optional notification message text (with --agent-state)'
        '--ack-ai:Acknowledge AI attention across one or more IDE sessions'
        '--open-pr:Open cached pull or merge request URL for an IDE session'
        '--send:Dispatch context (--stdin, --ref, --text) to AI Agent'
        '--stdin:Read context payload from standard input (with --send)'
        '--ref:Format file and line reference relative to AI CWD (with --send)'
        '--text:Send literal text payload to AI Agent (with --send)'
        '--no-focus:Keep current pane focus when dispatching with --send'
        '--switch:Focus AI pane and switch client to target session (with --send)'
        '--toggle:Toggle focus between AI Agent and Text Editor'
        '--show-editor:Focus Text Editor pane or bounce back'
        '--show-ai:Focus AI Agent pane or bounce back'
        '--show-term:Focus Interactive Shell pane or bounce back'
        '--toggle-editor:Hide or show Text Editor pane'
        '--toggle-ai:Hide or show AI Agent pane'
        '--toggle-term:Hide or show Interactive Shell pane'
        '--swap:Swap active pane with neighbor (left, down, up, or right)'
        '--monitor:Launch system monitor with btop, htop, and top fallback'
        '--top:Launch system monitor with btop, htop, and top fallback'
        '--keys:Display IDE keybinding cheatsheet'
        '-r:Refresh tmux top bar and Editor themes and CWDs across IDE sessions'
        '--refresh:Refresh tmux top bar and Editor themes and CWDs across IDE sessions'
        '--reload:Refresh tmux top bar and Editor themes and CWDs across IDE sessions'
        '-q:Safely quit IDE workspace session'
        '--quit:Safely quit IDE workspace session'
        '-f:Force-quit when used with --quit'
        '--force:Force-quit when used with --quit'
        '--detach:Create or update workspace session in background without attaching'
        '--kill:Force-quit IDE session without unsaved-buffer check'
        '--list:List active IDE workspace sessions'
        '--plain:Print session names only (one per line) when listing'
        '-h:Show help message'
        '--help:Show help message'
    )
    send_opts=(
        '--stdin:Read context payload from standard input'
        '--ref:Format file and line reference relative to AI CWD'
        '--text:Send literal text payload to AI Agent'
        '--no-focus:Keep current pane focus when dispatching'
        '--switch:Focus AI pane and switch client to target session'
    )
    list_opts=(
        '--plain:Print session names only (one per line)'
    )
    subcmds=(
        'cd:Dive into directory across Editor and Shell'
        'refresh:Refresh tmux top bar and Editor themes and CWDs across IDE sessions'
        'quit:Safely quit IDE workspace session(s)'
        'kill:Force-quit IDE workspace session(s) without unsaved-buffer check'
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
    swap_dirs=(
        'left:Swap active pane left'
        'down:Swap active pane down'
        'up:Swap active pane up'
        'right:Swap active pane right'
    )

    local prev="" prev2="" prev3=""
    (( CURRENT > 1 )) && prev="${words[CURRENT-1]:-}"
    (( CURRENT > 2 )) && prev2="${words[CURRENT-2]:-}"
    (( CURRENT > 3 )) && prev3="${words[CURRENT-3]:-}"
    case "${words[CURRENT]:-}" in
        --ai=*|--agent=*)
            (( ${+compstate} && $+builtins[compset] )) && compset -P 1 '*=' || true
            _describe -t agents 'AI agent CLI' agents
            return
            ;;
        --agent-state=*)
            (( ${+compstate} && $+builtins[compset] )) && compset -P 1 '*=' || true
            _describe -t states 'AI lifecycle state' agent_states
            return
            ;;
        --swap=*)
            (( ${+compstate} && $+builtins[compset] )) && compset -P 1 '*=' || true
            _describe -t directions 'swap direction' swap_dirs
            return
            ;;
        --open=*|--preview=*|--ref=*)
            (( ${+compstate} && $+builtins[compset] )) && compset -P 1 '*=' || true
            _files
            return
            ;;
        --open-pr=*)
            (( ${+compstate} && $+builtins[compset] )) && compset -P 1 '*=' || true
            _ide_load_sessions; sessions=("${reply[@]}")
            if (( ${#sessions} )); then
                _describe -t sessions 'IDE session' sessions
            fi
            return
            ;;
        --text=*|--message=*)
            return
            ;;
    esac
    case "$prev" in
        --ai|--agent)
            _describe -t agents 'AI agent CLI' agents
            return
            ;;
        --agent-state)
            _describe -t states 'AI lifecycle state' agent_states
            return
            ;;
        --swap)
            _describe -t directions 'swap direction' swap_dirs
            return
            ;;
        --list)
            _describe -t options 'ide list option' list_opts
            return
            ;;
        --open|--preview|--ref)
            _files
            return
            ;;
        --text|--message)
            return
            ;;
        cd|--cd)
            _files -/
            return
            ;;
        refresh|-r|--refresh|--reload|-s|--sessions|--next-attention|--open-pr|--toggle|--show-editor|--show-ai|--show-term|--focus-editor|--focus-ai|--focus-term|--toggle-editor|--toggle-ai|--toggle-term)
            if [[ "${words[CURRENT]:-}" == -* ]]; then
                _describe -t options 'ide option' opts
            else
                _ide_load_sessions; sessions=("${reply[@]}")
                if (( ${#sessions} )); then
                    _describe -t sessions 'IDE session' sessions
                fi
            fi
            return
            ;;
    esac

    local in_send=0 has_send_payload=0 in_quit_kill=0 in_ack_ai=0 in_agent_state=0 in_new=0 in_no_pos=0 is_launch_pos=0 idx=2 w=""
    [[ "${words[1]:-}" == (qide|idek|quit) ]] && in_quit_kill=1
    [[ "${words[1]:-}" == (ide|ide2|ide3) ]] && is_launch_pos=1
    while (( idx < CURRENT )); do
        w="${words[idx]:-}"
        case "$w" in
            --2pane|--3pane|--detach|--|--ai=*|--agent=*)
                ;;
            --ai|--agent)
                (( idx++ ))
                ;;
            --message)
                is_launch_pos=0
                (( idx++ ))
                ;;
            -q|--quit|--kill)
                in_quit_kill=1
                is_launch_pos=0
                ;;
            -n|--new)
                in_new=1
                is_launch_pos=0
                ;;
            --keys|--help-keys|--monitor|--top|--btop|-h|--help|--list|--plain)
                in_no_pos=1
                is_launch_pos=0
                ;;
            --ack-ai)
                in_ack_ai=1
                is_launch_pos=0
                ;;
            quit|kill)
                (( idx == 2 )) && in_quit_kill=1
                is_launch_pos=0
                ;;
            --send|--switch|--no-focus)
                in_send=1
                is_launch_pos=0
                ;;
            --stdin|--ref=*|--text=*)
                in_send=1
                has_send_payload=1
                is_launch_pos=0
                ;;
            --ref|--text)
                in_send=1
                is_launch_pos=0
                if (( idx + 1 < CURRENT )); then
                    has_send_payload=1
                    (( idx++ ))
                fi
                ;;
            --agent-state=*)
                in_agent_state=1
                is_launch_pos=0
                ;;
            --agent-state)
                in_agent_state=1
                is_launch_pos=0
                (( idx++ ))
                ;;
            -*)
                is_launch_pos=0
                ;;
            *)
                is_launch_pos=0
                if (( in_send )); then
                    has_send_payload=1
                fi
                ;;
        esac
        (( idx++ ))
    done

    if (( in_new || in_no_pos )); then
        if [[ "${words[CURRENT]:-}" == -* ]]; then
            _describe -t options 'ide option' opts
        fi
        return
    fi

    if (( in_send )); then
        if (( ! has_send_payload )) || [[ "${words[CURRENT]:-}" == -* ]]; then
            _describe -t options 'ide send option' send_opts
        else
            _ide_load_sessions; sessions=("${reply[@]}")
            if (( ${#sessions} )); then
                _describe -t sessions 'IDE session' sessions
            fi
        fi
        return
    fi

    if (( in_quit_kill || in_ack_ai )); then
        if [[ "${words[CURRENT]:-}" == -* ]]; then
            _describe -t options 'ide option' opts
        else
            _ide_load_sessions; sessions=("${reply[@]}")
            if (( ${#sessions} )); then
                local -a rem_sessions=()
                local s_cand used_idx is_used
                for s_cand in "${sessions[@]}"; do
                    is_used=0
                    for (( used_idx = 2; used_idx < CURRENT; used_idx++ )); do
                        if [[ "${words[used_idx]:-}" == "$s_cand" ]]; then
                            is_used=1
                            break
                        fi
                    done
                    (( ! is_used )) && rem_sessions+=("$s_cand")
                done
                if (( ${#rem_sessions} )); then
                    _describe -t sessions 'IDE session' rem_sessions
                else
                    _describe -t sessions 'IDE session' sessions
                fi
            fi
        fi
        return
    fi

    if (( in_agent_state )); then
        if [[ "${words[CURRENT]:-}" == -* ]]; then
            _describe -t options 'ide option' opts
        else
            _ide_load_sessions; sessions=("${reply[@]}")
            if (( ${#sessions} )); then
                _describe -t sessions 'IDE session' sessions
            fi
        fi
        return
    fi

    if [[ ( "$prev2" == ("--swap"|"--agent-state"|"--open"|"--preview"|"cd"|"--cd") || ( "$prev3" == ("--open"|"--preview") && "$prev" == (\+|)<-> ) ) && "${words[CURRENT]:-}" != -* ]]; then
        _ide_load_sessions; sessions=("${reply[@]}")
        if (( ${#sessions} )); then
            _describe -t sessions 'IDE session' sessions
        fi
        return
    fi

    if [[ "${words[CURRENT]:-}" == -* ]]; then
        _describe -t options 'ide option' opts
    elif (( is_launch_pos )); then
        if (( CURRENT == 2 )) && [[ "${words[1]:-}" == ide ]]; then
            _describe -t subcommands 'ide subcommand' subcmds
        fi
        _ide_load_sessions; sessions=("${reply[@]}")
        if (( ${#sessions} )); then
            _describe -t sessions 'IDE session' sessions
        fi
        if [[ "${words[CURRENT]:-}" != */* && "${words[CURRENT]:-}" != .* && "${words[CURRENT]:-}" != \~* ]]; then
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
                (( ! dup_ws )) && rem_workspaces+=("${ws_cand//:/\\:}")
            done
            if (( ${#rem_workspaces} )); then
                _describe -t workspaces 'workspace' rem_workspaces
            fi
        fi
        _files -/
    fi
}
if (( $+functions[compdef] )); then
    compdef _ide ide ide2 ide3 qide idek quit 2>/dev/null || true
fi
