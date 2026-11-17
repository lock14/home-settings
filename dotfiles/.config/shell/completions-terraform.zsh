#!/bin/zsh
# Zsh Tab Completion for `terraform` CLI and `tf` Alias
# Consumes shared flag and subcommand catalogs from terraform-flags.sh.

_terraform_subcmd_flags() {
    _hs_tf_subcmd_flags "${1:-}"
    reply=(${=REPLY})
}

_terraform() {
    local cur="${PREFIX-${words[CURRENT]:-}}"
    local prev="" subcmd="" subcmd2="" chdir_dir="" after_ddash=0 idx=2 w=""
    (( CURRENT > 1 )) && prev="${words[CURRENT-1]:-}"
    while (( idx < CURRENT )); do
        w="${words[idx]:-}"
        if [[ "$w" == "--" ]]; then
            after_ddash=1
            break
        fi
        case "$w" in
            -chdir=*)
                chdir_dir="${(Q)${w#-chdir=}}"
                if [[ "$chdir_dir" == "~" ]]; then
                    chdir_dir="$HOME"
                elif [[ "$chdir_dir" == "~/"* ]]; then
                    chdir_dir="$HOME/${chdir_dir#\~/}"
                fi
                (( idx++ ))
                continue
                ;;
            -plugin-dir|-plugin-cache-dir|-from-module|-test-directory|-config|-fs-mirror|-var|-var-file|-out|-state|-state-out|-backup|-backup-out|-backend-config|-generate-config-out|-filter|-junit-xml|-target|-replace|-parallelism|-lock-timeout|-lockfile|-id|-platform|-net-mirror|-cloud-run|-module-depth|-type|-format|-scope)
                (( idx += 2 ))
                continue
                ;;
            -*)
                (( idx++ ))
                continue
                ;;
        esac
        if [ -z "$subcmd" ]; then
            subcmd="$w"
        elif [ -z "$subcmd2" ]; then
            case "$subcmd:$w" in
                state:(identities|list|mv|pull|push|replace-provider|rm|show)|workspace:(delete|list|new|select|show)|providers:(lock|mirror|schema)|metadata:functions|stacks:(init|providers-lock|validate|create|list|version|fmt|configuration|deployment-group|deployment-run|deployment-step|diagnostics))
                    subcmd2="$w"
                    ;;
            esac
        fi
        (( idx++ ))
    done
    local -a chdir_opt=()
    if [ -n "$chdir_dir" ] && [ -d "$chdir_dir" ]; then
        chdir_opt=(-W "${chdir_dir:a}")
    fi
    if (( after_ddash )); then
        if [[ "$cur" != /* && "$cur" != \~* ]] && (( ${#chdir_opt} )); then
            _files "${chdir_opt[@]}"
        else
            _files
        fi
        return
    fi

    local path_val=""
    case "$cur" in
        -chdir=*)
            (( ${+compstate} && $+builtins[compset] )) && compset -P 1 '*=' || true
            _files -/
            return
            ;;
        -plugin-dir=*|-plugin-cache-dir=*|-from-module=*|-test-directory=*|-config=*|-fs-mirror=*)
            path_val="${cur#*=}"
            (( ${+compstate} && $+builtins[compset] )) && compset -P 1 '*=' || true
            if [[ "$path_val" != /* && "$path_val" != \~* ]] && (( ${#chdir_opt} )); then
                _files "${chdir_opt[@]}" -/
            else
                _files -/
            fi
            return
            ;;
        -var-file=*|-out=*|-state=*|-state-out=*|-backup=*|-backup-out=*|-backend-config=*|-generate-config-out=*|-filter=*|-junit-xml=*|-plan=*)
            path_val="${cur#*=}"
            (( ${+compstate} && $+builtins[compset] )) && compset -P 1 '*=' || true
            if [[ "$path_val" != /* && "$path_val" != \~* ]] && (( ${#chdir_opt} )); then
                _files "${chdir_opt[@]}"
            else
                _files
            fi
            return
            ;;
    esac
    case "$prev" in
        -plugin-dir|-plugin-cache-dir|-from-module|-test-directory|-config|-fs-mirror)
            if [[ "$cur" != /* && "$cur" != \~* ]] && (( ${#chdir_opt} )); then
                _files "${chdir_opt[@]}" -/
            else
                _files -/
            fi
            return
            ;;
        -var-file|-out|-state|-state-out|-backup|-backup-out|-backend-config|-generate-config-out|-filter|-junit-xml)
            if [[ "$cur" != /* && "$cur" != \~* ]] && (( ${#chdir_opt} )); then
                _files "${chdir_opt[@]}"
            else
                _files
            fi
            return
            ;;
    esac

    local -a line_words=("terraform")
    if (( CURRENT > 2 )); then
        line_words+=("${words[2,CURRENT-1]}")
    fi
    line_words+=("$cur")
    local comp_line="${(j: :)line_words}"

    local tf_bin=""
    if whence -p terraform >/dev/null 2>&1; then
        tf_bin="$(whence -p terraform)"
    fi

    local -a cands=() plain_cands=() eq_cands=() reply=()
    local raw_tf="" esc_cur="${(b)cur}"
    if [ -n "$tf_bin" ] && raw_tf="$(MISE_NOT_FOUND_AUTO_INSTALL=false COMP_LINE="$comp_line" COMP_POINT="${#comp_line}" "$tf_bin" 2>/dev/null)"; then
        cands=(${(f)raw_tf})
        cands=(${cands:#})
    fi

    if [[ "$cur" == -*=* ]]; then
        if (( ! ${#cands} )); then
            local flag_name="${cur%%=*}" flag_val="${cur#*=}"
            local -a enum_vals=()
            _hs_tf_enum_values "$flag_name" "$subcmd"
            enum_vals=(${=REPLY})
            if (( ${#enum_vals} )); then
                if (( ${+compstate} )); then
                    cands=("${enum_vals[@]}")
                else
                    cands=(${(M)enum_vals:#${(b)flag_val}*})
                fi
            fi
        fi
    elif [[ "$cur" == -* ]]; then
        if [ -n "$subcmd" ]; then
            _terraform_subcmd_flags "${subcmd}${subcmd2:+ $subcmd2}"
        else
            reply=(-chdir= -help -version)
        fi
        if (( ${#reply} )); then
            if (( ! ${+compstate} )); then
                cands=(${(M)cands:#${esc_cur}*})
            fi
            local ci f base_f
            for (( ci = 1; ci <= ${#cands}; ci++ )); do
                if [[ "${cands[ci]}" != *= ]] && (( ${reply[(Ie)${cands[ci]}=]} )); then
                    cands[ci]="${cands[ci]}="
                fi
            done
            local -a src_flags=("${reply[@]}")
            if (( ! ${+compstate} )); then
                src_flags=(${(M)reply:#${esc_cur}*})
            fi
            for f in "${src_flags[@]}"; do
                base_f="${f%=}"
                if (( ! ${cands[(Ie)$f]} && ! ${cands[(Ie)$base_f]} && ! ${cands[(Ie)${base_f}=]} )); then
                    cands+=("$f")
                fi
            done
        fi
    elif [ -z "$subcmd" ] && (( ! ${#cands} )); then
        cands=(${=_HS_TF_ROOT_SUBCMDS})
        if (( ! ${+compstate} )) && [ -n "$cur" ]; then
            cands=(${(M)cands:#${esc_cur}*})
        fi
    elif [ -n "$subcmd" ] && [ -z "$subcmd2" ] && (( ! ${#cands} )); then
        _hs_tf_nested_subcmds "$subcmd"
        cands=(${=REPLY})
        if (( ${#cands} && ! ${+compstate} )) && [ -n "$cur" ]; then
            cands=(${(M)cands:#${esc_cur}*})
        fi
    fi

    if (( ${#cands} )); then
        if [[ "$cur" == *=* ]]; then
            local eq_pfx="${cur%%=*}="
            cands=("${(@)cands#${(b)eq_pfx}}")
            (( ${+compstate} && $+builtins[compset] )) && compset -P 1 '*=' || true
        fi
        cands=("${(@)cands//:/\\:}")
        plain_cands=(${cands:#*=})
        eq_cands=(${(M)cands:#*=})
        if (( ${#plain_cands} )); then
            _describe -t terraform 'terraform completion' plain_cands
        fi
        if (( ${#eq_cands} )); then
            _describe -t options 'terraform option' eq_cands -S ''
        fi
    elif [[ "$cur" != -* ]]; then
        if [[ "$cur" != /* && "$cur" != \~* ]] && (( ${#chdir_opt} )); then
            _files "${chdir_opt[@]}"
        else
            _files
        fi
    fi
}
if (( $+functions[compdef] )); then
    compdef _terraform terraform tf 2>/dev/null || true
fi
