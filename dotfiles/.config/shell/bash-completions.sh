# Bash Tab Completion for `terraform` and `tf` (Bash 3.2+ compatible)
# Consumes shared flag and subcommand catalogs from terraform-flags.sh.

_hs_tf_complete_paths() {
    local mode="$1" pfx="$2" val="$3" wb_pfx="$4" base_dir="$5" has_compopt="$6" is_quoted="$7"
    local cg_flag="-f"
    [ "$mode" = "dir" ] && cg_flag="-d"
    local raw_list=""
    if [ -n "$base_dir" ]; then
        raw_list="$(cd "$base_dir" && compgen "$cg_flag" -- "$val" || true)"
    else
        raw_list="$(compgen "$cg_flag" -- "$val" || true)"
    fi
    [ -n "$raw_list" ] || return 0
    if [ "$has_compopt" -eq 1 ]; then
        builtin compopt -o filenames 2>/dev/null || true
    fi
    local item="" phys="" full="" rel="" esc_rel="" tilde_ch=$'\176' all_slash=1 need_nospace=0
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        if [ -n "$base_dir" ]; then
            phys="$base_dir/$item"
        elif [ "$item" = "$tilde_ch" ]; then
            phys="$HOME"
        elif [[ "$item" == "${tilde_ch}/"* ]]; then
            phys="$HOME/${item#"${tilde_ch}/"}"
        else
            phys="$item"
        fi
        full="${pfx}${item}"
        rel="${full#"$wb_pfx"}"
        if [ "$has_compopt" -eq 1 ]; then
            if [ -d "$phys" ]; then
                if [ ! -d "$rel" ]; then
                    rel="${rel}/"
                    need_nospace=1
                fi
            else
                all_slash=0
            fi
            COMPREPLY+=("$rel")
        elif [ -n "${COMP_LINE:-}" ] && [ "$is_quoted" -eq 0 ]; then
            if [[ "$rel" == "${tilde_ch}/"* ]]; then
                printf -v esc_rel '%q' "${rel#"${tilde_ch}/"}"
                esc_rel="${tilde_ch}/${esc_rel}"
            elif [ "$rel" = "$tilde_ch" ]; then
                esc_rel="$tilde_ch"
            else
                printf -v esc_rel '%q' "$rel"
            fi
            [ -d "$phys" ] && esc_rel="${esc_rel}/"
            COMPREPLY+=("$esc_rel")
        else
            COMPREPLY+=("$rel")
        fi
    done <<< "$raw_list"
    if [ "$has_compopt" -eq 1 ] && [ "${#COMPREPLY[@]}" -gt 0 ] && [ "$all_slash" -eq 1 ] && [ "$need_nospace" -eq 1 ]; then
        builtin compopt -o nospace 2>/dev/null || true
    fi
}

_terraform_bash_complete() {
    COMPREPLY=()
    local -a toks=() tok_quoted=()
    local cur_tok="" wb_pfx="" prev="" in_sq=0 in_dq=0
    local pt=0 line_upto=""

    if [ -n "${COMP_LINE+x}" ] && [ -n "${COMP_LINE:-}" ]; then
        pt="${COMP_POINT:-${#COMP_LINE}}"
        [ "$pt" -lt 0 ] && pt=0
        [ "$pt" -gt "${#COMP_LINE}" ] && pt="${#COMP_LINE}"
        line_upto="${COMP_LINE:0:$pt}"
        local i=0 len="${#line_upto}" ch="" esc=0 in_tok=0 cur_q=0
        while [ "$i" -lt "$len" ]; do
            ch="${line_upto:$i:1}"
            if [ "$esc" -eq 1 ]; then
                cur_tok="${cur_tok}${ch}"
                in_tok=1
                cur_q=1
                esc=0
            elif [ "$in_sq" -eq 1 ]; then
                if [ "$ch" = "'" ]; then
                    in_sq=0
                else
                    cur_tok="${cur_tok}${ch}"
                fi
            elif [ "$in_dq" -eq 1 ]; then
                if [ "$ch" = '"' ]; then
                    in_dq=0
                elif [ "$ch" = '\' ]; then
                    esc=1
                else
                    cur_tok="${cur_tok}${ch}"
                fi
            else
                case "$ch" in
                    ' '|$'\t'|$'\n')
                        if [ "$in_tok" -eq 1 ]; then
                            toks+=("$cur_tok")
                            tok_quoted+=("$cur_q")
                            cur_tok=""
                            cur_q=0
                            wb_pfx=""
                            in_tok=0
                        fi
                        ;;
                    '\')
                        esc=1
                        in_tok=1
                        cur_q=1
                        ;;
                    "'")
                        in_sq=1
                        in_tok=1
                        cur_q=1
                        [[ "${COMP_WORDBREAKS-}" == *"'"* ]] && wb_pfx="$cur_tok"
                        ;;
                    '"')
                        in_dq=1
                        in_tok=1
                        cur_q=1
                        [[ "${COMP_WORDBREAKS-}" == *'"'* ]] && wb_pfx="$cur_tok"
                        ;;
                    *)
                        cur_tok="${cur_tok}${ch}"
                        in_tok=1
                        [[ "${COMP_WORDBREAKS-}" == *"$ch"* ]] && wb_pfx="$cur_tok"
                        ;;
                esac
            fi
            i=$((i + 1))
        done
    else
        local -a g_toks=()
        local wi=0 cword="${COMP_CWORD:-0}" w="" glue_next=0 last_gi=0
        while [ "$wi" -le "$cword" ]; do
            w="${COMP_WORDS[$wi]:-}"
            if [ "${#g_toks[@]}" -eq 0 ]; then
                g_toks+=("$w")
                glue_next=0
            elif [ "$w" = "=" ] || [ "$w" = ":" ]; then
                last_gi=$(( ${#g_toks[@]} - 1 ))
                g_toks[last_gi]="${g_toks[$last_gi]}${w}"
                [ "$wi" -eq "$cword" ] && wb_pfx="${g_toks[$last_gi]}"
                glue_next=1
            elif [ "$glue_next" -eq 1 ]; then
                last_gi=$(( ${#g_toks[@]} - 1 ))
                [ "$wi" -eq "$cword" ] && wb_pfx="${g_toks[$last_gi]}"
                g_toks[last_gi]="${g_toks[$last_gi]}${w}"
                glue_next=0
            else
                g_toks+=("$w")
            fi
            wi=$((wi + 1))
        done
        if [ "${#g_toks[@]}" -gt 0 ]; then
            last_gi=$(( ${#g_toks[@]} - 1 ))
            cur_tok="${g_toks[$last_gi]}"
            wi=0
            while [ "$wi" -lt "$last_gi" ]; do
                toks+=("${g_toks[$wi]}")
                tok_quoted+=(0)
                wi=$((wi + 1))
            done
        fi
    fi

    if [ "${#toks[@]}" -ge 1 ]; then
        prev="${toks[$(( ${#toks[@]} - 1 ))]}"
    fi

    local subcmd="" subcmd2="" chdir_dir="" tilde_ch=$'\176' after_ddash=0 idx=1 sw="" sw_q=0
    while [ "$idx" -lt "${#toks[@]}" ]; do
        sw="${toks[$idx]}"
        sw_q="${tok_quoted[$idx]:-0}"
        if [ "$sw" = "--" ] && [ "$sw_q" -eq 0 ]; then
            after_ddash=1
            break
        fi
        case "$sw" in
            -chdir=*)
                chdir_dir="${sw#-chdir=}"
                if [ "$chdir_dir" = "$tilde_ch" ]; then
                    chdir_dir="$HOME"
                elif [[ "$chdir_dir" == "${tilde_ch}/"* ]]; then
                    chdir_dir="$HOME/${chdir_dir#"${tilde_ch}/"}"
                fi
                idx=$((idx + 1))
                continue
                ;;
            -plugin-dir|-plugin-cache-dir|-from-module|-test-directory|-config|-fs-mirror|-var|-var-file|-out|-state|-state-out|-backup|-backup-out|-backend-config|-generate-config-out|-filter|-junit-xml|-target|-replace|-parallelism|-lock-timeout|-lockfile|-id|-platform|-net-mirror|-cloud-run|-module-depth|-type|-format|-scope)
                idx=$((idx + 2))
                continue
                ;;
            -*)
                idx=$((idx + 1))
                continue
                ;;
        esac
        if [ -z "$subcmd" ]; then
            subcmd="$sw"
        elif [ -z "$subcmd2" ]; then
            case "$subcmd:$sw" in
                state:identities|state:list|state:mv|state:pull|state:push|state:replace-provider|state:rm|state:show|\
                workspace:delete|workspace:list|workspace:new|workspace:select|workspace:show|\
                providers:lock|providers:mirror|providers:schema|\
                metadata:functions|\
                stacks:init|stacks:providers-lock|stacks:validate|stacks:create|stacks:list|stacks:version|stacks:fmt|stacks:configuration|stacks:deployment-group|stacks:deployment-run|stacks:deployment-step|stacks:diagnostics)
                    subcmd2="$sw"
                    ;;
            esac
        fi
        idx=$((idx + 1))
    done

    local has_compopt=0 is_quoted=0
    if [ "${_HS_TF_FORCE_BASH32:-0}" != "1" ] && (( BASH_VERSINFO[0] >= 4 )); then
        has_compopt=1
    fi
    if [ "$in_sq" -eq 1 ] || [ "$in_dq" -eq 1 ]; then
        is_quoted=1
    fi
    local eff_chdir=""
    if [ -n "$chdir_dir" ] && [ -d "$chdir_dir" ]; then
        eff_chdir="$chdir_dir"
    fi

    if [ "$after_ddash" -eq 1 ]; then
        if [ -n "${COMP_LINE:-}" ] && [ -n "$eff_chdir" ] && [[ "$cur_tok" != /* && "$cur_tok" != "$tilde_ch"* ]]; then
            _hs_tf_complete_paths "file" "" "$cur_tok" "$wb_pfx" "$eff_chdir" "$has_compopt" "$is_quoted"
        fi
        return 0
    fi

    local pfx="" val="" path_base=""
    case "$cur_tok" in
        -chdir=*)
            pfx="${cur_tok%%=*}="
            val="${cur_tok#*=}"
            _hs_tf_complete_paths "dir" "$pfx" "$val" "$wb_pfx" "" "$has_compopt" "$is_quoted"
            return 0
            ;;
        -plugin-dir=*|-plugin-cache-dir=*|-from-module=*|-test-directory=*|-config=*|-fs-mirror=*)
            pfx="${cur_tok%%=*}="
            val="${cur_tok#*=}"
            [[ "$val" != /* && "$val" != "$tilde_ch"* ]] && path_base="$eff_chdir"
            _hs_tf_complete_paths "dir" "$pfx" "$val" "$wb_pfx" "$path_base" "$has_compopt" "$is_quoted"
            return 0
            ;;
        -var-file=*|-out=*|-state=*|-state-out=*|-backup=*|-backup-out=*|-backend-config=*|-generate-config-out=*|-filter=*|-junit-xml=*|-plan=*)
            pfx="${cur_tok%%=*}="
            val="${cur_tok#*=}"
            [[ "$val" != /* && "$val" != "$tilde_ch"* ]] && path_base="$eff_chdir"
            _hs_tf_complete_paths "file" "$pfx" "$val" "$wb_pfx" "$path_base" "$has_compopt" "$is_quoted"
            return 0
            ;;
    esac
    case "$prev" in
        -plugin-dir|-plugin-cache-dir|-from-module|-test-directory|-config|-fs-mirror)
            [[ "$cur_tok" != /* && "$cur_tok" != "$tilde_ch"* ]] && path_base="$eff_chdir"
            _hs_tf_complete_paths "dir" "" "$cur_tok" "$wb_pfx" "$path_base" "$has_compopt" "$is_quoted"
            return 0
            ;;
        -var-file|-out|-state|-state-out|-backup|-backup-out|-backend-config|-generate-config-out|-filter|-junit-xml)
            [[ "$cur_tok" != /* && "$cur_tok" != "$tilde_ch"* ]] && path_base="$eff_chdir"
            _hs_tf_complete_paths "file" "" "$cur_tok" "$wb_pfx" "$path_base" "$has_compopt" "$is_quoted"
            return 0
            ;;
    esac

    local comp_line="" comp_point=0
    if [ -n "$line_upto" ]; then
        comp_line="${line_upto#"${line_upto%%[![:space:]]*}"}"
        if [[ "$comp_line" == tf[[:space:]]* ]]; then
            comp_line="terraform${comp_line#tf}"
        fi
        comp_point="${#comp_line}"
    else
        comp_line="terraform"
        idx=1
        while [ "$idx" -lt "${#toks[@]}" ]; do
            comp_line="${comp_line} ${toks[$idx]}"
            idx=$((idx + 1))
        done
        comp_line="${comp_line} ${cur_tok}"
        comp_point="${#comp_line}"
    fi

    local tf_bin=""
    if type -P terraform >/dev/null 2>&1; then
        tf_bin="$(type -P terraform)"
    fi
    if [ -n "$tf_bin" ]; then
        local raw_out="" cand="" full_cand="" eq_pfx="" eq_val=""
        if [[ "$cur_tok" == -*=* ]]; then
            eq_pfx="${cur_tok%%=*}="
            eq_val="${cur_tok#*=}"
        fi
        if raw_out="$(MISE_NOT_FOUND_AUTO_INSTALL=false COMP_LINE="$comp_line" COMP_POINT="$comp_point" "$tf_bin" 2>/dev/null)"; then
            if [ -n "$raw_out" ]; then
                while IFS= read -r cand; do
                    [ -n "$cand" ] || continue
                    if [ -n "$eq_pfx" ] && [[ "$cand" != "$eq_pfx"* ]]; then
                        if [ -z "$eq_val" ] || [[ "$cand" == "$eq_val"* ]]; then
                            full_cand="${eq_pfx}${cand}"
                            COMPREPLY+=("${full_cand#"$wb_pfx"}")
                        fi
                    elif [ -z "$cur_tok" ] || [[ "$cand" == "$cur_tok"* ]]; then
                        COMPREPLY+=("${cand#"$wb_pfx"}")
                    fi
                done <<< "$raw_out"
            fi
        fi
    fi

    if [[ "$cur_tok" == -*=* ]]; then
        if [ "${#COMPREPLY[@]}" -eq 0 ]; then
            local flag_name="${cur_tok%%=*}" flag_val="${cur_tok#*=}" enum_words="" ev="" full_ev=""
            _hs_tf_enum_values "$flag_name" "$subcmd"
            enum_words="$REPLY"
            for ev in $enum_words; do
                if [ -z "$flag_val" ] || [[ "$ev" == "$flag_val"* ]]; then
                    full_ev="${flag_name}=${ev}"
                    COMPREPLY+=("${full_ev#"$wb_pfx"}")
                fi
            done
        fi
        return 0
    fi

    if [[ "$cur_tok" == -* ]]; then
        local static_flags="" sf="" base_sf="" k=0 existing="" full_ex="" dup=0
        if [ -n "$subcmd" ]; then
            _hs_tf_subcmd_flags "${subcmd}${subcmd2:+ $subcmd2}"
            static_flags="$REPLY"
        else
            static_flags="-chdir= -help -version"
        fi
        if [ -n "$static_flags" ]; then
            k=0
            while [ "$k" -lt "${#COMPREPLY[@]}" ]; do
                existing="${wb_pfx}${COMPREPLY[$k]}"
                if [[ "$existing" != *= ]] && [[ " $static_flags " == *" ${existing}="* ]]; then
                    full_ex="${existing}="
                    COMPREPLY[k]="${full_ex#"$wb_pfx"}"
                fi
                k=$((k + 1))
            done
            local had_dyn="${#COMPREPLY[@]}"
            for sf in $static_flags; do
                if [[ "$sf" == "$cur_tok"* ]]; then
                    dup=0
                    if [ "$had_dyn" -gt 0 ]; then
                        base_sf="${sf%=}"
                        k=0
                        while [ "$k" -lt "$had_dyn" ]; do
                            existing="${wb_pfx}${COMPREPLY[$k]}"
                            if [ "$existing" = "$sf" ] || [ "$existing" = "$base_sf" ] || [ "$existing" = "${base_sf}=" ]; then
                                dup=1
                                break
                            fi
                            k=$((k + 1))
                        done
                    fi
                    [ "$dup" -eq 0 ] && COMPREPLY+=("${sf#"$wb_pfx"}")
                fi
            done
        fi
    elif [ -z "$subcmd" ] && [ "${#COMPREPLY[@]}" -eq 0 ]; then
        local sc=""
        for sc in $_HS_TF_ROOT_SUBCMDS; do
            if [ -z "$cur_tok" ] || [[ "$sc" == "$cur_tok"* ]]; then
                COMPREPLY+=("${sc#"$wb_pfx"}")
            fi
        done
    elif [ -n "$subcmd" ] && [ -z "$subcmd2" ] && [ "${#COMPREPLY[@]}" -eq 0 ]; then
        local nested_cmds="" nc=""
        _hs_tf_nested_subcmds "$subcmd"
        nested_cmds="$REPLY"
        for nc in $nested_cmds; do
            if [ -z "$cur_tok" ] || [[ "$nc" == "$cur_tok"* ]]; then
                COMPREPLY+=("${nc#"$wb_pfx"}")
            fi
        done
    fi

    if [ "${#COMPREPLY[@]}" -eq 0 ] && [[ "$cur_tok" != -* ]] && [ -n "$subcmd" ] && [ -n "$eff_chdir" ] && [[ "$cur_tok" != /* && "$cur_tok" != "$tilde_ch"* ]]; then
        _hs_tf_complete_paths "file" "" "$cur_tok" "$wb_pfx" "$eff_chdir" "$has_compopt" "$is_quoted"
        return 0
    fi

    if [ "$has_compopt" -eq 1 ] && [ "${#COMPREPLY[@]}" -eq 1 ] && [[ "${COMPREPLY[0]}" == *= ]]; then
        builtin compopt -o nospace 2>/dev/null || true
    fi
    return 0
}
complete -o default -F _terraform_bash_complete terraform tf 2>/dev/null || true
