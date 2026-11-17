# Bash Zero-Fork Git Config Parser, 5-Forge PR/MR Hyperlink Resolver, & Single-Line Shelf Prompt
# Compatible with Bash 3.2+ across TrueColor, 16-color ANSI, and Linux VT consoles.

# Helper to parse Git config files in pure Bash (zero subprocess forks)
_solarized_parse_git_config() {
    local cfg_file="$1" is_repo_cfg="${2:-0}" depth="${3:-0}"
    if [ "$depth" -gt 4 ] || [ ! -r "$cfg_file" ]; then
        return 0
    fi
    local s
    for s in ${seen_cfgs[@]+"${seen_cfgs[@]}"}; do
        [ "$s" = "$cfg_file" ] && return 0
    done
    seen_cfgs+=("$cfg_file")

    local section_type="" section_name="" seen_url_in_section=0 cfg_line="" next_line="" pre_bracket="" hdr="" key="" val=""
    while IFS= read -r cfg_line || [ -n "$cfg_line" ]; do
        cfg_line="${cfg_line%$'\r'}"
        local lead_trim="${cfg_line#"${cfg_line%%[![:space:]]*}"}"
        [[ -z "$lead_trim" || "$lead_trim" == [#\;]* ]] && continue
        while [[ "$cfg_line" == *\\ ]]; do
            local ci=0 cn="${#cfg_line}" cin_q=0 cesc=0 cch=""
            while [ "$ci" -lt "$cn" ]; do
                cch="${cfg_line:$ci:1}"
                if [ "$cesc" = "1" ]; then
                    cesc=0
                elif [ "$cch" = "\\" ]; then
                    cesc=1
                elif [ "$cch" = "\"" ]; then
                    cin_q=$((1 - cin_q))
                elif [ "$cin_q" = "0" ] && { [ "$cch" = "#" ] || [ "$cch" = ";" ]; }; then
                    cesc=0
                    break
                fi
                ci=$((ci + 1))
            done
            [ "$cesc" = "1" ] || break
            next_line=""
            IFS= read -r next_line || break
            next_line="${next_line%$'\r'}"
            cfg_line="${cfg_line%\\}${next_line}"
        done
        cfg_line="${cfg_line#"${cfg_line%%[![:space:]]*}"}"
        [[ -z "$cfg_line" || "$cfg_line" == [#\;]* ]] && continue

        if [[ "$cfg_line" == \[*\]* ]]; then
            seen_url_in_section=0
            pre_bracket="${cfg_line#\[}"
            pre_bracket="${pre_bracket%%\]*}"
            if [[ "$pre_bracket" == *\"* ]]; then
                local h_rest="${cfg_line#\[}"
                h_rest="${h_rest#"${h_rest%%[![:space:]]*}"}"
                section_type="${h_rest%%[[:space:]\"]*}"
                local q_body="${h_rest#*\"}"
                section_name=""
                if [[ "$q_body" != *\\* && "$q_body" == *\"\]* ]]; then
                    section_name="${q_body%%\"\]*}"
                else
                    local qi=0 qn="${#q_body}" qch="" qnx=""
                    while [ "$qi" -lt "$qn" ]; do
                        qch="${q_body:$qi:1}"
                        if [ "$qch" = "\\" ] && [ $((qi + 1)) -lt "$qn" ]; then
                            qnx="${q_body:$((qi + 1)):1}"
                            case "$qnx" in
                                n) section_name="${section_name}"$'\n' ;;
                                t) section_name="${section_name}"$'\t' ;;
                                b) section_name="${section_name}"$'\b' ;;
                                *) section_name="${section_name}${qnx}" ;;
                            esac
                            qi=$((qi + 2))
                            continue
                        elif [ "$qch" = "\"" ]; then
                            break
                        fi
                        section_name="${section_name}${qch}"
                        qi=$((qi + 1))
                    done
                fi
            else
                hdr="$pre_bracket"
                hdr="${hdr#"${hdr%%[![:space:]]*}"}"
                hdr="${hdr%"${hdr##*[![:space:]]}"}"
                if [[ "$hdr" == *.* ]]; then
                    section_type="${hdr%%.*}"
                    section_name="${hdr#*.}"
                else
                    section_type="$hdr"
                    section_name=""
                fi
            fi
            case "$section_type" in
                [rR][eE][mM][oO][tT][eE])           section_type="remote" ;;
                [bB][rR][aA][nN][cC][hH])           section_type="branch" ;;
                [uU][rR][lL])                       section_type="url" ;;
                [iI][nN][cC][lL][uU][dD][eE])       section_type="include" ;;
                [iI][nN][cC][lL][uU][dD][eE][iI][fF])
                    section_type=""
                    local cond_pat="" cond_icase=0
                    if [[ "$section_name" == gitdir/i:* ]]; then
                        cond_pat="${section_name#gitdir/i:}"
                        cond_icase=1
                    elif [[ "$section_name" == gitdir:* ]]; then
                        cond_pat="${section_name#gitdir:}"
                    elif [[ "$section_name" == onbranch:* ]]; then
                        cond_pat="${section_name#onbranch:}"
                        [[ "$cond_pat" == */ ]] && cond_pat="${cond_pat}*"
                        # shellcheck disable=SC2053
                        if [[ "$raw_branch" == $cond_pat ]]; then
                            section_type="include"
                        fi
                        cond_pat=""
                    fi
                    if [ -n "$cond_pat" ]; then
                        if [[ "$cond_pat" == \~/* ]]; then
                            cond_pat="$HOME/${cond_pat#\~/}"
                        elif [[ "$cond_pat" == ./* ]]; then
                            cond_pat="${cfg_file%/*}/${cond_pat#./}"
                        elif [[ "$cond_pat" != /* ]]; then
                            cond_pat="*/$cond_pat"
                        fi
                        [[ "$cond_pat" == */ ]] && cond_pat="${cond_pat}*"
                        local cond_pat_alt="${cond_pat//\/\*\*\//\/}"
                        local had_nocase=0
                        shopt -q nocasematch && had_nocase=1
                        [ "$cond_icase" = "1" ] && shopt -s nocasematch
                        # shellcheck disable=SC2053
                        if [[ "$gitdir/" == $cond_pat || "$workdir/.git/" == $cond_pat || "$gitdir/" == $cond_pat_alt || "$workdir/.git/" == $cond_pat_alt ]]; then
                            section_type="include"
                        fi
                        [ "$cond_icase" = "1" ] && [ "$had_nocase" = "0" ] && shopt -u nocasematch
                    fi
                    ;;
                *)                                  section_type="" ;;
            esac
            continue
        fi

        [[ -z "$section_type" || "$cfg_line" != *=* ]] && continue
        key="${cfg_line%%=*}"
        key="${key%"${key##*[![:space:]]}"}"
        case "$key" in
            [uU][rR][lL])                         key="url" ;;
            [rR][eE][mM][oO][tT][eE])             key="remote" ;;
            [mM][eE][rR][gG][eE])                 key="merge" ;;
            [pP][rR])                             key="pr" ;;
            [pP][rR][uU][rR][lL])                 key="prurl" ;;
            [fF][oO][rR][gG][eE])                 key="forge" ;;
            [iI][nN][sS][tT][eE][aA][dD][oO][fF]) key="insteadof" ;;
            [pP][aA][tT][hH])                     key="path" ;;
            *)                                    continue ;;
        esac
        val="${cfg_line#*=}"
        val="${val#"${val%%[![:space:]]*}"}"
        if [[ "$val" != *\"* && "$val" != *\\* ]]; then
            val="${val%%[#\;]*}"
            val="${val%"${val##*[![:space:]]}"}"
        else
            local vi=0 vn="${#val}" vin_q=0 vparsed="" vlast="" vch="" vnx=""
            while [ "$vi" -lt "$vn" ]; do
                vch="${val:$vi:1}"
                if [ "$vin_q" = "1" ]; then
                    if [ "$vch" = "\\" ] && [ $((vi + 1)) -lt "$vn" ]; then
                        vnx="${val:$((vi + 1)):1}"
                        case "$vnx" in
                            n) vparsed="${vparsed}"$'\n' ;;
                            t) vparsed="${vparsed}"$'\t' ;;
                            b) vparsed="${vparsed}"$'\b' ;;
                            *) vparsed="${vparsed}${vnx}" ;;
                        esac
                        vlast="$vparsed"
                        vi=$((vi + 2))
                        continue
                    elif [ "$vch" = "\"" ]; then
                        vin_q=0
                        vlast="$vparsed"
                        vi=$((vi + 1))
                        continue
                    fi
                    vparsed="${vparsed}${vch}"
                    vlast="$vparsed"
                else
                    if [ "$vch" = "#" ] || [ "$vch" = ";" ]; then
                        break
                    elif [ "$vch" = "\"" ]; then
                        vin_q=1
                        vi=$((vi + 1))
                        continue
                    elif [ "$vch" = "\\" ] && [ $((vi + 1)) -lt "$vn" ]; then
                        vnx="${val:$((vi + 1)):1}"
                        case "$vnx" in
                            n) vparsed="${vparsed}"$'\n' ;;
                            t) vparsed="${vparsed}"$'\t' ;;
                            b) vparsed="${vparsed}"$'\b' ;;
                            *) vparsed="${vparsed}${vnx}" ;;
                        esac
                        vlast="$vparsed"
                        vi=$((vi + 2))
                        continue
                    fi
                    vparsed="${vparsed}${vch}"
                    case "$vch" in
                        [[:space:]]) ;;
                        *) vlast="$vparsed" ;;
                    esac
                fi
                vi=$((vi + 1))
            done
            val="$vlast"
        fi
        [ -z "$val" ] && continue

        if [ "$section_type" = "remote" ] && [ "$key" = "url" ]; then
            if [ "$seen_url_in_section" = "0" ]; then
                remote_names+=("$section_name")
                remote_urls+=("$val")
                seen_url_in_section=1
                if [ "$is_repo_cfg" = "1" ] && [ -z "$first_remote_name" ]; then
                    first_remote_name="$section_name"
                fi
            fi
        elif [ "$section_type" = "remote" ] && [ "$key" = "forge" ]; then
            remote_forge_names+=("$section_name")
            remote_forge_vals+=("$val")
        elif [ "$section_type" = "branch" ] && [ "$section_name" = "$raw_branch" ]; then
            if [ "$key" = "remote" ]; then
                branch_remote="$val"
            elif [ "$key" = "pr" ]; then
                if [[ "$val" =~ ^[1-9][0-9]*$ ]]; then
                    branch_pr="$val"
                fi
            elif [ "$key" = "prurl" ]; then
                branch_pr_url="$val"
            elif [ "$key" = "merge" ]; then
                local m_num=""
                case "$val" in
                    refs/pull/*/head)
                        m_num="${val#refs/pull/}"
                        m_num="${m_num%/head}"
                        if [[ "$m_num" =~ ^[1-9][0-9]*$ ]]; then
                            [ -z "$branch_pr" ] && branch_pr="$m_num"
                            merge_forge_hint="github"
                        fi
                        ;;
                    refs/merge-requests/*/head)
                        m_num="${val#refs/merge-requests/}"
                        m_num="${m_num%/head}"
                        if [[ "$m_num" =~ ^[1-9][0-9]*$ ]]; then
                            [ -z "$branch_pr" ] && branch_pr="$m_num"
                            merge_forge_hint="gitlab"
                        fi
                        ;;
                    refs/pull-requests/*/from|refs/pull-requests/*/head)
                        m_num="${val#refs/pull-requests/}"
                        m_num="${m_num%%/*}"
                        if [[ "$m_num" =~ ^[1-9][0-9]*$ ]]; then
                            [ -z "$branch_pr" ] && branch_pr="$m_num"
                            merge_forge_hint="bitbucket-server"
                        fi
                        ;;
                esac
            fi
        elif [ "$section_type" = "url" ] && [ "$key" = "insteadof" ]; then
            insteadof_prefixes+=("$val")
            insteadof_bases+=("$section_name")
        elif [ "$section_type" = "include" ] && [ "$key" = "path" ]; then
            local inc_path="$val"
            if [[ "$inc_path" == \~/* ]]; then
                inc_path="$HOME/${inc_path#\~/}"
            elif [[ "$inc_path" != /* ]]; then
                inc_path="${cfg_file%/*}/$inc_path"
            fi
            _solarized_parse_git_config "$inc_path" "$is_repo_cfg" "$((depth + 1))"
        fi
    done < "$cfg_file"
}

# Pure-Bash cross-platform PR/MR web URL builder across all 5 major Git forge families:
# GitHub, GitLab, Bitbucket Cloud, Bitbucket Server / Data Center, and Gitea / Forgejo / Codeberg.
# Usage: _solarized_vcs_build_pr_url [-v out_var] <remote_url> <pr_num> [forge_hint]
_solarized_vcs_build_pr_url() {
    local out_var=""
    if [ "${1:-}" = "-v" ]; then
        out_var="$2"
        shift 2
    fi
    REPLY=""
    [ -n "$out_var" ] && printf -v "$out_var" '%s' ""
    local raw_url="${1:-}" pr_num="${2:-}" forge_hint="${3:-}"
    if [ -z "$raw_url" ] || ! [[ "$pr_num" =~ ^[1-9][0-9]*$ ]]; then
        return 1
    fi

    local scheme="https" rest="$raw_url"
    local has_scheme=0 is_http=0
    case "$rest" in
        http://*)
            scheme="http"
            rest="${rest#http://}"
            has_scheme=1
            is_http=1
            ;;
        https://*)
            scheme="https"
            rest="${rest#https://}"
            has_scheme=1
            is_http=1
            ;;
        ssh://*|git://*|git+ssh://*)
            rest="${rest#*://}"
            has_scheme=1
            ;;
        file://*)
            rest="localhost/${rest#file://}"
            has_scheme=1
            ;;
        /*)
            rest="localhost${rest}"
            has_scheme=1
            ;;
    esac

    local host="" repo_path=""
    if [ "$has_scheme" -eq 1 ]; then
        [[ "$rest" == */* ]] || return 1
        host="${rest%%/*}"
        repo_path="${rest#*/}"
        host="${host#*@}"
        if [ "$is_http" -eq 0 ] && [[ "$host" == *:* && "$host" != *"]" ]]; then
            host="${host%:*}"
        fi
    elif [[ "$rest" == *:* ]] && { [[ "$rest" != */* ]] || [[ "${rest%%:*}" != */* ]]; }; then
        host="${rest%%:*}"
        repo_path="${rest#*:}"
        host="${host#*@}"
    elif [[ "$rest" == */* ]]; then
        host="${rest%%/*}"
        repo_path="${rest#*/}"
        host="${host#*@}"
    else
        return 1
    fi

    while [[ "$repo_path" == /* ]]; do
        repo_path="${repo_path#/}"
    done
    while [[ "$repo_path" == */ ]]; do
        repo_path="${repo_path%/}"
    done
    repo_path="${repo_path%.git}"
    while [[ "$repo_path" == */ ]]; do
        repo_path="${repo_path%/}"
    done
    if [ -z "$host" ] || [ -z "$repo_path" ]; then
        return 1
    fi

    local forge=""
    case "$forge_hint" in
        [gG][iI][tT][hH][uU][bB])                                                 forge="github" ;;
        [gG][iI][tT][lL][aA][bB])                                                 forge="gitlab" ;;
        [bB][iI][tT][bB][uU][cC][kK][eE][tT]-[cC][lL][oO][uU][dD]|bitbucket_cloud) forge="bitbucket-cloud" ;;
        [bB][iI][tT][bB][uU][cC][kK][eE][tT]-[sS][eE][rR][vV][eE][rR]|bitbucket_server|bitbucket-dc|[sS][tT][aA][sS][hH]) forge="bitbucket-server" ;;
        [gG][iI][tT][eE][aA]|[fF][oO][rR][gG][eE][jJ][oO]|[cC][oO][dD][eE][bB][eE][rR][gG]) forge="gitea" ;;
    esac
    if [ -z "$forge" ]; then
        case "$host" in
            *[gG][iI][tT][hH][uU][bB]*)                                           forge="github" ;;
            *[gG][iI][tT][lL][aA][bB]*)                                           forge="gitlab" ;;
            [bB][iI][tT][bB][uU][cC][kK][eE][tT].[oO][rR][gG])                    forge="bitbucket-cloud" ;;
            *[bB][iI][tT][bB][uU][cC][kK][eE][tT]*|*[sS][tT][aA][sS][hH]*)        forge="bitbucket-server" ;;
            *[cC][oO][dD][eE][bB][eE][rR][gG]*|*[gG][iI][tT][eE][aA]*|*[fF][oO][rR][gG][eE][jJ][oO]*) forge="gitea" ;;
            *)                                                                    forge="github" ;;
        esac
    fi

    local built_url=""
    case "$forge" in
        github)
            built_url="${scheme}://${host}/${repo_path}/pull/${pr_num}"
            ;;
        gitlab)
            built_url="${scheme}://${host}/${repo_path}/-/merge_requests/${pr_num}"
            ;;
        bitbucket-cloud)
            built_url="https://bitbucket.org/${repo_path}/pull-requests/${pr_num}"
            ;;
        bitbucket-server)
            local bb_path="${repo_path#scm/}"
            [[ "$bb_path" == */scm/* ]] && bb_path="${bb_path#*/scm/}"
            local proj="" repo=""
            if [[ "$bb_path" == */* ]]; then
                repo="${bb_path##*/}"
                local bb_rem="${bb_path%/*}"
                proj="${bb_rem##*/}"
            else
                proj="$bb_path"
                repo="$bb_path"
            fi
            if [[ "$proj" == \~* ]]; then
                built_url="${scheme}://${host}/users/${proj#\~}/repos/${repo}/pull-requests/${pr_num}"
            else
                local proj_upper="" _pi _pc
                for ((_pi = 0; _pi < ${#proj}; _pi++)); do
                    _pc="${proj:$_pi:1}"
                    case "$_pc" in
                        a) _pc=A ;; b) _pc=B ;; c) _pc=C ;; d) _pc=D ;; e) _pc=E ;; f) _pc=F ;;
                        g) _pc=G ;; h) _pc=H ;; i) _pc=I ;; j) _pc=J ;; k) _pc=K ;; l) _pc=L ;;
                        m) _pc=M ;; n) _pc=N ;; o) _pc=O ;; p) _pc=P ;; q) _pc=Q ;; r) _pc=R ;;
                        s) _pc=S ;; t) _pc=T ;; u) _pc=U ;; v) _pc=V ;; w) _pc=W ;; x) _pc=X ;;
                        y) _pc=Y ;; z) _pc=Z ;;
                    esac
                    proj_upper="${proj_upper}${_pc}"
                done
                built_url="${scheme}://${host}/projects/${proj_upper}/repos/${repo}/pull-requests/${pr_num}"
            fi
            ;;
        gitea)
            built_url="${scheme}://${host}/${repo_path}/pulls/${pr_num}"
            ;;
        *)
            built_url="${scheme}://${host}/${repo_path}/pull/${pr_num}"
            ;;
    esac

    REPLY="$built_url"
    if [ -n "$out_var" ]; then
        printf -v "$out_var" '%s' "$built_url"
    else
        printf '%s\n' "$built_url"
    fi
    return 0
}

# Asynchronous / callable PR/MR state discovery worker in Bash (Tier 1 Forge CLIs, Tier 2 git ls-remote
# virtual PR refs with merged-PR guard, Tier 3 Bitbucket Cloud API, atomic cache state update).
_solarized_vcs_refresh_pr_cache() {
    local workdir="${1:-${GIT_WORK_TREE:-$PWD}}"
    local gitdir="${2:-${GIT_DIR:-}}"
    local branch="${3:-}"
    local remote_name="${4:-}"
    local remote_url="${5:-}"
    local forge_hint="${6:-}"
    local cache_file="${7:-}"
    local upstream_forge_url="${8:-}"

    if [ ! -d "$HOME" ] || [ ! -d "$workdir" ]; then
        return 0
    fi

    if [ -z "$gitdir" ]; then
        while [ -n "$workdir" ] && [ "$workdir" != "/" ] && [ ! -e "$workdir/.git" ] && [ ! -L "$workdir/.git" ]; do
            workdir="${workdir%/*}"
            [ -n "$workdir" ] || workdir="/"
        done
        if [ -d "$workdir/.git" ]; then
            gitdir="$workdir/.git"
        elif [ -r "$workdir/.git" ]; then
            local gd_line=""
            IFS= read -r gd_line < "$workdir/.git" || true
            gd_line="${gd_line%$'\r'}"
            if [[ "$gd_line" == "gitdir: "* ]]; then
                gd_line="${gd_line#gitdir: }"
                [[ "$gd_line" == /* ]] && gitdir="$gd_line" || gitdir="$workdir/$gd_line"
            fi
        fi
    fi
    [ -n "$gitdir" ] || return 1

    if [ -z "$branch" ]; then
        branch=$(git --git-dir="$gitdir" symbolic-ref --short HEAD 2>/dev/null) || return 1
    fi
    if [ -z "$branch" ] || [ "$branch" = "(detached)" ]; then
        return 1
    fi

    if [ -z "$remote_name" ]; then
        remote_name=$(git --git-dir="$gitdir" config "branch.${branch}.remote" 2>/dev/null || true)
        if [ -z "$remote_name" ] || [ "$remote_name" = "." ]; then
            remote_name="origin"
        fi
    fi
    if [ -z "$remote_url" ]; then
        remote_url=$(git --git-dir="$gitdir" config "remote.${remote_name}.url" 2>/dev/null || git --git-dir="$gitdir" config remote.origin.url 2>/dev/null || true)
    fi
    [ -n "$remote_url" ] || return 1

    if [ -z "$forge_hint" ]; then
        forge_hint=$(git --git-dir="$gitdir" config "remote.${remote_name}.forge" 2>/dev/null || git --git-dir="$gitdir" config remote.origin.forge 2>/dev/null || true)
    fi
    if [ -z "$upstream_forge_url" ] && [ "$remote_name" != "upstream" ]; then
        upstream_forge_url=$(git --git-dir="$gitdir" config remote.upstream.url 2>/dev/null || true)
    fi

    if [ -z "$cache_file" ]; then
        local commondir="$gitdir"
        if [ -r "$gitdir/commondir" ]; then
            local common_line=""
            IFS= read -r common_line < "$gitdir/commondir" || true
            common_line="${common_line%$'\r'}"
            common_line="${common_line%/}"
            if [ -n "$common_line" ] && [ "$common_line" != "." ]; then
                if [[ "$common_line" == /* ]]; then
                    commondir="$common_line"
                else
                    local c_base="${gitdir%/}" c_rel="$common_line"
                    while [[ "$c_rel" == ../* || "$c_rel" == ".." ]]; do
                        c_base="${c_base%/*}"
                        if [ "$c_rel" = ".." ]; then
                            c_rel=""
                        else
                            c_rel="${c_rel#../}"
                        fi
                    done
                    [ -n "$c_rel" ] && commondir="$c_base/$c_rel" || commondir="$c_base"
                fi
            fi
        fi
        local c_dir="${GIT_PR_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/git-pr-prompt}"
        local repo_key="${commondir//[^A-Za-z0-9._-]/_}"
        cache_file="$c_dir/${repo_key}.state"
    fi

    local cache_dir="${cache_file%/*}"
    mkdir -p "$cache_dir" 2>/dev/null || return 1
    local now="${EPOCHSECONDS:-}"
    if [ -z "$now" ]; then
        printf -v now '%(%s)T' -1 2>/dev/null || now="$(date +%s 2>/dev/null || echo 0)"
    fi
    printf '%s\n' "$now" > "${cache_file}.lock" 2>/dev/null || true

    local forge=""
    case "$forge_hint" in
        [gG][iI][tT][hH][uU][bB])                                                 forge="github" ;;
        [gG][iI][tT][lL][aA][bB])                                                 forge="gitlab" ;;
        [bB][iI][tT][bB][uU][cC][kK][eE][tT]-[cC][lL][oO][uU][dD]|bitbucket_cloud) forge="bitbucket-cloud" ;;
        [bB][iI][tT][bB][uU][cC][kK][eE][tT]-[sS][eE][rR][vV][eE][rR]|bitbucket_server|bitbucket-dc|[sS][tT][aA][sS][hH]) forge="bitbucket-server" ;;
        [gG][iI][tT][eE][aA]|[fF][oO][rR][gG][eE][jJ][oO]|[cC][oO][dD][eE][bB][eE][rR][gG]) forge="gitea" ;;
    esac
    if [ -z "$forge" ]; then
        case "$remote_url" in
            *[gG][iI][tT][hH][uU][bB]*)                                           forge="github" ;;
            *[gG][iI][tT][lL][aA][bB]*)                                           forge="gitlab" ;;
            *[bB][iI][tT][bB][uU][cC][kK][eE][tT].[oO][rR][gG]*)                  forge="bitbucket-cloud" ;;
            *[bB][iI][tT][bB][uU][cC][kK][eE][tT]*|*[sS][tT][aA][sS][hH]*)        forge="bitbucket-server" ;;
            *[cC][oO][dD][eE][bB][eE][rR][gG]*|*[gG][iI][tT][eE][aA]*|*[fF][oO][rR][gG][eE][jJ][oO]*) forge="gitea" ;;
        esac
    fi

    local found_num="" found_url=""
    local is_local_remote=0
    case "$remote_url" in
        /*|./*|../*|file://*) is_local_remote=1 ;;
    esac

    # Tier 1: Forge CLIs (gh, glab, tea) when remote is not a local filesystem path
    if [ "$is_local_remote" -eq 0 ]; then
        if [ "$forge" = "github" ] && command -v gh >/dev/null 2>&1; then
            local gh_out=""
            gh_out=$(cd "$workdir" 2>/dev/null && GH_PROMPT_DISABLED=1 gh pr view --json number,url,state -q 'select(.state == "OPEN") | "\(.number)|\(.url)"' 2>/dev/null || true)
            gh_out="${gh_out%%$'\n'*}"
            gh_out="${gh_out%$'\r'}"
            if [[ "$gh_out" == *"|"* ]]; then
                local gh_num="${gh_out%%|*}"
                local gh_url="${gh_out#*|}"
                if [[ "$gh_num" =~ ^[1-9][0-9]*$ ]]; then
                    found_num="$gh_num"
                    found_url="$gh_url"
                fi
            fi
        elif [ "$forge" = "gitlab" ] && command -v glab >/dev/null 2>&1; then
            local glab_out=""
            glab_out=$(cd "$workdir" 2>/dev/null && glab mr list --source-branch "$branch" -F json 2>/dev/null || true)
            local iid_re='"iid"[[:space:]]*:[[:space:]]*([1-9][0-9]*)'
            local url_re='"web_url"[[:space:]]*:[[:space:]]*"(https?://[^"\\]*/-/merge_requests/([1-9][0-9]*))"'
            if [[ "$glab_out" =~ $url_re ]]; then
                found_url="${BASH_REMATCH[1]}"
                found_num="${BASH_REMATCH[2]}"
            elif [[ "$glab_out" =~ $iid_re ]]; then
                found_num="${BASH_REMATCH[1]}"
                _solarized_vcs_build_pr_url -v found_url "$remote_url" "$found_num" "gitlab" || true
            fi
        elif [ "$forge" = "gitea" ] && command -v tea >/dev/null 2>&1; then
            local tea_out="" t_idx="" t_head="" t_url=""
            tea_out=$(cd "$workdir" 2>/dev/null && tea pr list --state open --fields index,head,url -o simple 2>/dev/null || true)
            while IFS=$' \t' read -r t_idx t_head t_url _ || [ -n "$t_idx" ]; do
                t_idx="${t_idx#\#}"
                if [[ "$t_idx" =~ ^[1-9][0-9]*$ ]] && { [ "$t_head" = "$branch" ] || [[ "$t_head" == *":$branch" ]]; }; then
                    found_num="$t_idx"
                    if [[ "$t_url" == https://* || "$t_url" == http://* ]]; then
                        found_url="$t_url"
                    else
                        _solarized_vcs_build_pr_url -v found_url "$remote_url" "$found_num" "gitea" || true
                    fi
                    break
                fi
            done <<< "$tea_out"
        fi
    fi

    # Tier 2: Pure `git ls-remote` virtual PR refs (GitHub, GitLab, Bitbucket Server/DC, Gitea/Forgejo/Codeberg)
    if [ -z "$found_num" ] && { [ "$forge" != "bitbucket-cloud" ] || [ "$is_local_remote" -eq 1 ]; }; then
        local ls_out=""
        ls_out=$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=5}" \
            git --git-dir="$gitdir" ls-remote "$remote_url" \
            "HEAD" "refs/heads/main" "refs/heads/master" "refs/heads/trunk" "refs/heads/develop" \
            "refs/heads/$branch" "refs/pull/*/head" "refs/merge-requests/*/head" "refs/pull-requests/*/from" 2>/dev/null || true)
        if [ -n "$ls_out" ]; then
            local branch_remote_sha="" default_shas=" " r_sha="" r_ref=""
            local -a pr_nums=() pr_shas=() pr_kinds=()
            while IFS=$' \t' read -r r_sha r_ref || [ -n "$r_sha" ]; do
                [ -z "$r_sha" ] || [ -z "$r_ref" ] && continue
                if [ "$r_ref" = "refs/heads/$branch" ]; then
                    branch_remote_sha="$r_sha"
                elif [ "$r_ref" = "HEAD" ] || [ "$r_ref" = "refs/heads/main" ] || [ "$r_ref" = "refs/heads/master" ] || [ "$r_ref" = "refs/heads/trunk" ] || [ "$r_ref" = "refs/heads/develop" ]; then
                    default_shas="${default_shas}${r_sha} "
                else
                    local p_num="" p_kind=""
                    case "$r_ref" in
                        refs/pull/*/head)
                            p_num="${r_ref#refs/pull/}"
                            p_num="${p_num%/head}"
                            p_kind=""
                            ;;
                        refs/merge-requests/*/head)
                            p_num="${r_ref#refs/merge-requests/}"
                            p_num="${p_num%/head}"
                            p_kind="gitlab"
                            ;;
                        refs/pull-requests/*/from)
                            p_num="${r_ref#refs/pull-requests/}"
                            p_num="${p_num%/from}"
                            p_kind="bitbucket-server"
                            ;;
                    esac
                    if [[ "$p_num" =~ ^[1-9][0-9]*$ ]]; then
                        pr_nums+=("$p_num")
                        pr_shas+=("$r_sha")
                        pr_kinds+=("$p_kind")
                    fi
                fi
            done <<< "$ls_out"

            if [ -n "$branch_remote_sha" ] && [[ "$default_shas" != *" ${branch_remote_sha} "* ]]; then
                local best_num=0 best_kind="" idx
                for ((idx = 0; idx < ${#pr_nums[@]}; idx++)); do
                    if [ "${pr_shas[$idx]}" = "$branch_remote_sha" ] && [ "${pr_nums[$idx]}" -gt "$best_num" ]; then
                        best_num="${pr_nums[$idx]}"
                        best_kind="${pr_kinds[$idx]}"
                    fi
                done
                if [ "$best_num" -gt 0 ]; then
                    found_num="$best_num"
                    _solarized_vcs_build_pr_url -v found_url "$remote_url" "$found_num" "${forge_hint:-$best_kind}" || true
                elif [ -n "$upstream_forge_url" ] && [ "$upstream_forge_url" != "$remote_url" ]; then
                    local up_ls_out=""
                    up_ls_out=$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=5}" \
                        git --git-dir="$gitdir" ls-remote "$upstream_forge_url" \
                        "HEAD" "refs/heads/main" "refs/heads/master" "refs/heads/trunk" "refs/heads/develop" \
                        "refs/pull/*/head" "refs/merge-requests/*/head" "refs/pull-requests/*/from" 2>/dev/null || true)
                    if [ -n "$up_ls_out" ]; then
                        local up_default_shas=" " up_best_num=0 up_best_kind=""
                        local -a up_nums=() up_shas=() up_kinds=()
                        while IFS=$' \t' read -r r_sha r_ref || [ -n "$r_sha" ]; do
                            [ -z "$r_sha" ] || [ -z "$r_ref" ] && continue
                            if [ "$r_ref" = "HEAD" ] || [ "$r_ref" = "refs/heads/main" ] || [ "$r_ref" = "refs/heads/master" ] || [ "$r_ref" = "refs/heads/trunk" ] || [ "$r_ref" = "refs/heads/develop" ]; then
                                up_default_shas="${up_default_shas}${r_sha} "
                            else
                                local p_num="" p_kind=""
                                case "$r_ref" in
                                    refs/pull/*/head)
                                        p_num="${r_ref#refs/pull/}"
                                        p_num="${p_num%/head}"
                                        p_kind=""
                                        ;;
                                    refs/merge-requests/*/head)
                                        p_num="${r_ref#refs/merge-requests/}"
                                        p_num="${p_num%/head}"
                                        p_kind="gitlab"
                                        ;;
                                    refs/pull-requests/*/from)
                                        p_num="${r_ref#refs/pull-requests/}"
                                        p_num="${p_num%/from}"
                                        p_kind="bitbucket-server"
                                        ;;
                                esac
                                if [[ "$p_num" =~ ^[1-9][0-9]*$ ]]; then
                                    up_nums+=("$p_num")
                                    up_shas+=("$r_sha")
                                    up_kinds+=("$p_kind")
                                fi
                            fi
                        done <<< "$up_ls_out"
                        if [[ "$up_default_shas" != *" ${branch_remote_sha} "* ]]; then
                            for ((idx = 0; idx < ${#up_nums[@]}; idx++)); do
                                if [ "${up_shas[$idx]}" = "$branch_remote_sha" ] && [ "${up_nums[$idx]}" -gt "$up_best_num" ]; then
                                    up_best_num="${up_nums[$idx]}"
                                    up_best_kind="${up_kinds[$idx]}"
                                fi
                            done
                            if [ "$up_best_num" -gt 0 ]; then
                                found_num="$up_best_num"
                                _solarized_vcs_build_pr_url -v found_url "$upstream_forge_url" "$found_num" "$up_best_kind" || true
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi

    # Tier 3: Bitbucket Cloud (bitbucket.org) REST API fallback
    if [ -z "$found_num" ] && [ "$forge" = "bitbucket-cloud" ] && [ "$is_local_remote" -eq 0 ] && command -v curl >/dev/null 2>&1; then
        local bb_probe="" bb_rest=""
        _solarized_vcs_build_pr_url -v bb_probe "$remote_url" 1 "bitbucket-cloud" || true
        bb_rest="${bb_probe#https://bitbucket.org/}"
        bb_rest="${bb_rest%/pull-requests/1}"
        if [[ "$bb_rest" == */* ]]; then
            local -a curl_args=(-fsSL --max-time 5)
            if [ -n "${BITBUCKET_TOKEN:-}" ]; then
                curl_args+=(-H "Authorization: Bearer $BITBUCKET_TOKEN")
            elif [ -r "$HOME/.netrc" ]; then
                curl_args+=(-n)
            fi
            local bb_json=""
            bb_json=$(curl "${curl_args[@]}" "https://api.bitbucket.org/2.0/repositories/${bb_rest}/pullrequests?q=source.branch.name=%22${branch}%22+AND+state=%22OPEN%22&pagelen=1" 2>/dev/null || true)
            local bb_id_re='"id"[[:space:]]*:[[:space:]]*([1-9][0-9]*)'
            local bb_href_re='"href"[[:space:]]*:[[:space:]]*"(https?://[^"\\]*/pull-requests/[1-9][0-9]*)"'
            if [[ "$bb_json" =~ $bb_id_re ]]; then
                found_num="${BASH_REMATCH[1]}"
                if [[ "$bb_json" =~ $bb_href_re ]]; then
                    found_url="${BASH_REMATCH[1]}"
                else
                    _solarized_vcs_build_pr_url -v found_url "$remote_url" "$found_num" "bitbucket-cloud" || true
                fi
            fi
        fi
    fi

    if [ ! -d "$HOME" ] || [ ! -d "$cache_dir" ]; then
        return 0
    fi
    local tmp_file="${cache_file}.tmp.$$"
    {
        if [ -r "$cache_file" ]; then
            local existing_line=""
            while IFS= read -r existing_line || [ -n "$existing_line" ]; do
                if [ -z "$existing_line" ] || [[ "$existing_line" == "${branch}|"* ]]; then
                    continue
                fi
                printf '%s\n' "$existing_line"
            done < "$cache_file"
        fi
        printf '%s|%s|%s|%s\n' "$branch" "${found_num:-NONE}" "$found_url" "$now"
    } > "$tmp_file" 2>/dev/null && mv -f "$tmp_file" "$cache_file" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null
    rm -f "${cache_file}.lock" 2>/dev/null || true
    return 0
}

# 3.5. Intelligent Distro-Aware OS Glyph Resolver (Zero-Fork Pure Bash)
_solarized_detect_os_icon() {
    if [ -n "${SOLARIZED_PROMPT_OS_ICON+x}" ]; then
        printf '%s' "$SOLARIZED_PROMPT_OS_ICON"
        return 0
    fi

    if [[ "${OSTYPE:-}" == darwin* ]] || { [ -z "${OSTYPE:-}" ] && [ "$(uname -s 2>/dev/null)" = "Darwin" ]; }; then
        printf '%s' $'\xef\x85\xb9'    # \uF179 macOS
        return 0
    fi

    if [[ "${OSTYPE:-}" == *bsd* ]]; then
        printf '%s' $'\xef\x8c\x8c'    # \uF30C FreeBSD
        return 0
    fi

    local os_file="${SOLARIZED_PROMPT_OS_RELEASE:-}"
    if [ -z "$os_file" ]; then
        if [ -r /etc/os-release ]; then
            os_file="/etc/os-release"
        elif [ -r /usr/lib/os-release ]; then
            os_file="/usr/lib/os-release"
        fi
    fi

    local id="" id_like="" line=""
    if [ -n "$os_file" ] && [ -r "$os_file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                ID=*)
                    id="${line#ID=}"
                    id="${id%\"}"
                    id="${id#\"}"
                    id="${id%\'}"
                    id="${id#\'}"
                    ;;
                ID_LIKE=*)
                    id_like="${line#ID_LIKE=}"
                    id_like="${id_like%\"}"
                    id_like="${id_like#\"}"
                    id_like="${id_like%\'}"
                    id_like="${id_like#\'}"
                    ;;
            esac
        done < "$os_file"
    fi

    case "$id" in
        ubuntu)                 printf '%s' $'\xef\x8c\x9b' ;; # \uF31B
        debian)                 printf '%s' $'\xef\x8c\x86' ;; # \uF306
        fedora)                 printf '%s' $'\xef\x8c\x8a' ;; # \uF30A
        arch|archarm)           printf '%s' $'\xef\x8c\x83' ;; # \uF303
        manjaro)                printf '%s' $'\xef\x8c\x92' ;; # \uF312
        pop)                    printf '%s' $'\xef\x8c\xaa' ;; # \uF32A
        linuxmint|mint)         printf '%s' $'\xef\x8c\x8e' ;; # \uF30E
        rhel)                   printf '%s' $'\xef\x8c\x96' ;; # \uF316
        centos)                 printf '%s' $'\xef\x8c\x84' ;; # \uF304
        rocky)                  printf '%s' $'\xef\x8c\xab' ;; # \uF32B
        almalinux)              printf '%s' $'\xef\x8c\x9d' ;; # \uF31D
        opensuse*|suse|sles)    printf '%s' $'\xef\x8c\x94' ;; # \uF314
        alpine)                 printf '%s' $'\xef\x8c\x80' ;; # \uF300
        nixos)                  printf '%s' $'\xef\x8c\x93' ;; # \uF313
        raspbian)               printf '%s' $'\xef\x8c\x95' ;; # \uF315
        gentoo)                 printf '%s' $'\xef\x8c\x8d' ;; # \uF30D
        void)                   printf '%s' $'\xef\x8c\xae' ;; # \uF32E
        *)
            case "$id_like" in
                *ubuntu*)       printf '%s' $'\xef\x8c\x9b' ;;
                *debian*)       printf '%s' $'\xef\x8c\x86' ;;
                *fedora*)       printf '%s' $'\xef\x8c\x8a' ;;
                *rhel*)         printf '%s' $'\xef\x8c\x96' ;;
                *centos*)       printf '%s' $'\xef\x8c\x84' ;;
                *arch*)         printf '%s' $'\xef\x8c\x83' ;;
                *suse*)         printf '%s' $'\xef\x8c\x94' ;;
                *)              printf '%s' $'\xef\x85\xbc' ;; # \uF17C Default Linux Tux
            esac
            ;;
    esac
}

# 4. Zero-Dependency Solarized Dark Single-Line Shelf Prompt Builder
_solarized_bash_prompt() {
    local exit_code=$?
    if declare -F _hs_recover_stale_cwd >/dev/null 2>&1; then
        _hs_recover_stale_cwd
    fi
    if [[ "$-" == *i* ]] && [ -n "${_HS_POST_SOURCE_SYNC:-}" ] && [ -n "${HISTFILE:-}" ]; then
        local _hs_hist_dir="${HISTFILE%/*}"
        [ "$_hs_hist_dir" = "$HISTFILE" ] && _hs_hist_dir="."
        if { [ ! -d "$HISTFILE" ] && [ -w "$HISTFILE" ]; } || { [ ! -e "$HISTFILE" ] && [ ! -L "$HISTFILE" ] && [ -d "$_hs_hist_dir" ] && [ -w "$_hs_hist_dir" ]; }; then
            builtin history -a
        fi
    fi
    _hs_bash_sync_theme_state 0
    local c_reset='\[\e[0m\]'
    local bg_shelf="${_HS_PROMPT_BG_BASE02:-\[\e[48;2;7;54;66m\]}"
    local c_shelf_cap="${_HS_PROMPT_CAP_BASE02:-\[\e[0m\e[38;2;7;54;66m\]}"
    local c_base01="${_HS_PROMPT_FG_BASE01:-\[\e[38;2;88;110;117m\]}"
    local c_base00="${_HS_PROMPT_FG_BASE00:-\[\e[38;2;101;123;131m\]}"
    local c_base0="${_HS_PROMPT_FG_BASE0:-\[\e[38;2;131;148;150m\]}"
    local c_base1="${_HS_PROMPT_FG_BASE1:-\[\e[38;2;147;161;161m\]}"
    local c_blue="${_HS_PROMPT_FG_BLUE:-\[\e[38;2;38;139;210m\]}"
    local c_green="${_HS_PROMPT_FG_GREEN:-\[\e[38;2;133;153;0m\]}"
    local c_yellow="${_HS_PROMPT_FG_YELLOW:-\[\e[38;2;181;137;0m\]}"
    local c_orange="${_HS_PROMPT_FG_ORANGE:-\[\e[38;2;203;75;22m\]}"
    local c_red="${_HS_PROMPT_FG_RED:-\[\e[38;2;220;50;47m\]}"
    local subsep=$'\xee\x82\xb1'   # \uE0B1 thin directional chevron
    local endcap=$'\xee\x82\xb0'   # \uE0B0 solid right-pointing wedge cap
    local git_icon=$'\xef\x84\xa6 ' # \uF126 branch icon
    local sym=$'\xe2\x9d\xaf'      # \u276F prompt chevron (used only in non-endcap fallback)
    local os_icon=""
    if [ -n "${_HS_PROMPT_OS_ICON:-}" ] && [ -z "${SOLARIZED_PROMPT_OS_RELEASE:-}" ] && [ -z "${SOLARIZED_PROMPT_OS_ICON+x}" ]; then
        os_icon="$_HS_PROMPT_OS_ICON"
    elif [ -n "${_SOLARIZED_PROMPT_OS_ICON_CACHED:-}" ] && [ "${_SOLARIZED_PROMPT_OSTYPE_CACHED:-}" = "${OSTYPE:-}" ] && [ -z "${SOLARIZED_PROMPT_OS_RELEASE:-}" ] && [ -z "${SOLARIZED_PROMPT_OS_ICON+x}" ]; then
        os_icon="$_SOLARIZED_PROMPT_OS_ICON_CACHED"
    else
        os_icon="$(_solarized_detect_os_icon)"
        if [ -z "${SOLARIZED_PROMPT_OS_RELEASE:-}" ] && [ -z "${SOLARIZED_PROMPT_OS_ICON+x}" ]; then
            _SOLARIZED_PROMPT_OS_ICON_CACHED="$os_icon"
            _SOLARIZED_PROMPT_OSTYPE_CACHED="${OSTYPE:-}"
        fi
    fi

    if [ "${TERM:-}" = "linux" ] || { [ "${COLORTERM:-}" != "truecolor" ] && [ "${COLORTERM:-}" != "24bit" ]; }; then
        bg_shelf='\[\e[40m\]'
        c_shelf_cap='\[\e[0m\e[30m\]'
        c_base01='\[\e[90m\]'
        c_base00='\[\e[90m\]'
        c_base0='\[\e[37m\]'
        c_base1='\[\e[97m\]'
        c_blue='\[\e[34m\]'
        c_green='\[\e[32m\]'
        c_yellow='\[\e[33m\]'
        c_orange='\[\e[91m\]'
        c_red='\[\e[31m\]'
        if [ "${TERM:-}" = "linux" ]; then
            c_orange='\[\e[33m\]'
            subsep='>'
            endcap=''
            git_icon=''
            os_icon=''
            sym='>'
        fi
    fi

    local current_uid="${SOLARIZED_PROMPT_UID:-${EUID:-$(id -u 2>/dev/null || echo 1000)}}"
    local show_user_host=0
    local host_color=""
    if [ "$current_uid" -eq 0 ]; then
        host_color="$c_red"
        show_user_host=1
    elif [ -n "${SSH_CLIENT:-}${SSH_TTY:-}${SSH_CONNECTION:-}" ]; then
        host_color="$c_base1"
        show_user_host=1
    fi

    local context_segment=""
    if [ "$show_user_host" -eq 1 ]; then
        if [ -n "$os_icon" ]; then
            context_segment="${c_base0}${os_icon} ${host_color}\u@\h"
        else
            context_segment="${host_color}\u@\h"
        fi
    elif [ -n "$os_icon" ]; then
        context_segment="${c_base0}${os_icon}"
    fi

    local sep=" ${c_base00}${subsep} "
    local lead_segment=""
    if [ -n "$context_segment" ]; then
        lead_segment="${context_segment}${sep}"
    fi
    local git_segment=""
    local workdir="${GIT_WORK_TREE:-$PWD}"
    local gitdir="${GIT_DIR:-}"
    if [ -z "$gitdir" ] && { [ -n "${GIT_WORK_TREE:-}" ] || [[ "$PWD" != */.git && "$PWD" != */.git/* ]]; }; then
        while [ -n "$workdir" ] && [ "$workdir" != "/" ] && [ ! -e "$workdir/.git" ] && [ ! -L "$workdir/.git" ]; do
            workdir="${workdir%/*}"
            [ -n "$workdir" ] || workdir="/"
        done
        if [ -d "$workdir/.git" ]; then
            gitdir="$workdir/.git"
        elif [ -r "$workdir/.git" ]; then
            local gd_line=""
            IFS= read -r gd_line < "$workdir/.git" || true
            gd_line="${gd_line%$'\r'}"
            if [[ "$gd_line" == "gitdir: "* ]]; then
                gd_line="${gd_line#gitdir: }"
                if [[ "$gd_line" == /* ]]; then
                    gitdir="$gd_line"
                else
                    gitdir="$workdir/$gd_line"
                fi
            fi
        fi
    fi

    if [ -n "$gitdir" ] && command -v git >/dev/null 2>&1; then
        local status_out=""
        if status_out=$(git --no-optional-locks status --porcelain=v2 --branch --ignore-submodules=dirty 2>/dev/null); then
            local raw_branch="" branch_oid="" branch_upstream="" is_dirty=0 is_conflicted=0 is_detached=0 s_line="" branch=""
            while IFS= read -r s_line || [ -n "$s_line" ]; do
                if [[ "$s_line" == "# branch.head "* ]]; then
                    raw_branch="${s_line#\# branch.head }"
                elif [[ "$s_line" == "# branch.oid "* ]]; then
                    branch_oid="${s_line#\# branch.oid }"
                elif [[ "$s_line" == "# branch.upstream "* ]]; then
                    branch_upstream="${s_line#\# branch.upstream }"
                elif [[ "$s_line" == "u "* ]]; then
                    is_conflicted=1
                    is_dirty=1
                    break
                elif [[ "$s_line" != \#* ]]; then
                    is_dirty=1
                fi
            done <<< "$status_out"

            if [ "$raw_branch" = "(detached)" ]; then
                is_detached=1
                raw_branch=$(git rev-parse --short HEAD 2>/dev/null || printf '%s' "${branch_oid:0:7}")
            fi

            if [ -n "$raw_branch" ]; then
                local vcs_host_icon="" pr_num="" pr_url=""
                local commondir="$gitdir"
                if [ -r "$gitdir/commondir" ]; then
                    local common_line=""
                    IFS= read -r common_line < "$gitdir/commondir" || true
                    common_line="${common_line%$'\r'}"
                    common_line="${common_line%/}"
                    if [ -n "$common_line" ] && [ "$common_line" != "." ]; then
                        if [[ "$common_line" == /* ]]; then
                            commondir="$common_line"
                        else
                            local c_base="${gitdir%/}" c_rel="$common_line"
                            while [[ "$c_rel" == ../* || "$c_rel" == ".." ]]; do
                                c_base="${c_base%/*}"
                                if [ "$c_rel" = ".." ]; then
                                    c_rel=""
                                else
                                    c_rel="${c_rel#../}"
                                fi
                            done
                            [ -n "$c_rel" ] && commondir="$c_base/$c_rel" || commondir="$c_base"
                        fi
                    fi
                fi

                local branch_remote="" first_remote_name="" branch_pr="" branch_pr_url="" merge_forge_hint=""
                local -a remote_names=() remote_urls=() remote_forge_names=() remote_forge_vals=() insteadof_prefixes=() insteadof_bases=() seen_cfgs=()
                if [ -n "${GIT_CONFIG_GLOBAL:-}" ]; then
                    _solarized_parse_git_config "$GIT_CONFIG_GLOBAL" 0
                else
                    _solarized_parse_git_config "${XDG_CONFIG_HOME:-$HOME/.config}/git/config" 0
                    _solarized_parse_git_config "$HOME/.gitconfig" 0
                fi
                if [ -n "$commondir" ]; then
                    _solarized_parse_git_config "$commondir/config" 1
                fi
                if [ -n "$gitdir" ]; then
                    if [ "$gitdir" != "$commondir" ]; then
                        _solarized_parse_git_config "$gitdir/config" 1
                    fi
                    _solarized_parse_git_config "$gitdir/config.worktree" 1
                fi

                local upstream_remote=""
                if [[ "$branch_upstream" == */* ]]; then
                    upstream_remote="${branch_upstream%%/*}"
                fi

                local target_remote="origin"
                if [ -n "$branch_remote" ] && [ "$branch_remote" != "." ]; then
                    target_remote="$branch_remote"
                elif [ -n "$upstream_remote" ]; then
                    target_remote="$upstream_remote"
                fi

                local target_url="" upstream_url="" origin_url="" first_remote_url="" upstream_forge_url="" i
                for ((i = 0; i < ${#remote_names[@]}; i++)); do
                    if [ "${remote_names[$i]}" = "$target_remote" ]; then
                        target_url="${remote_urls[$i]}"
                    fi
                    if [ -n "$upstream_remote" ] && [ "${remote_names[$i]}" = "$upstream_remote" ]; then
                        upstream_url="${remote_urls[$i]}"
                    fi
                    if [ "${remote_names[$i]}" = "origin" ]; then
                        origin_url="${remote_urls[$i]}"
                    fi
                    if [ "${remote_names[$i]}" = "upstream" ]; then
                        upstream_forge_url="${remote_urls[$i]}"
                    fi
                    if [ -n "$first_remote_name" ] && [ "${remote_names[$i]}" = "$first_remote_name" ]; then
                        first_remote_url="${remote_urls[$i]}"
                    fi
                done

                local target_forge="" origin_forge="" first_remote_forge=""
                for ((i = 0; i < ${#remote_forge_names[@]}; i++)); do
                    if [ "${remote_forge_names[$i]}" = "$target_remote" ]; then
                        target_forge="${remote_forge_vals[$i]}"
                    fi
                    if [ "${remote_forge_names[$i]}" = "origin" ]; then
                        origin_forge="${remote_forge_vals[$i]}"
                    fi
                    if [ -n "$first_remote_name" ] && [ "${remote_forge_names[$i]}" = "$first_remote_name" ]; then
                        first_remote_forge="${remote_forge_vals[$i]}"
                    fi
                done
                local forge_hint="${target_forge:-${origin_forge:-${first_remote_forge:-$merge_forge_hint}}}"

                local remote_url="${target_url:-${upstream_url:-${origin_url:-$first_remote_url}}}"
                if [ -n "$remote_url" ] && [ "${#insteadof_prefixes[@]}" -gt 0 ]; then
                    local best_pfx="" best_base="" pfx
                    for ((i = 0; i < ${#insteadof_prefixes[@]}; i++)); do
                        pfx="${insteadof_prefixes[$i]}"
                        if [[ "$remote_url" == "$pfx"* ]] && [ "${#pfx}" -ge "${#best_pfx}" ]; then
                            best_pfx="$pfx"
                            best_base="${insteadof_bases[$i]}"
                        fi
                    done
                    if [ -n "$best_pfx" ]; then
                        remote_url="${best_base}${remote_url#"$best_pfx"}"
                    fi
                fi
                if [ -n "$upstream_forge_url" ] && [ "${#insteadof_prefixes[@]}" -gt 0 ]; then
                    local u_best_pfx="" u_best_base="" u_pfx
                    for ((i = 0; i < ${#insteadof_prefixes[@]}; i++)); do
                        u_pfx="${insteadof_prefixes[$i]}"
                        if [[ "$upstream_forge_url" == "$u_pfx"* ]] && [ "${#u_pfx}" -ge "${#u_best_pfx}" ]; then
                            u_best_pfx="$u_pfx"
                            u_best_base="${insteadof_bases[$i]}"
                        fi
                    done
                    if [ -n "$u_best_pfx" ]; then
                        upstream_forge_url="${u_best_base}${upstream_forge_url#"$u_best_pfx"}"
                    fi
                fi

                if [ "${TERM:-}" != "linux" ]; then
                    case "$remote_url" in
                        *[gG][iI][tT][hH][uU][bB]*)                 vcs_host_icon=$'\xef\x84\x93 ' ;; # \uF113 GitHub
                        *[gG][iI][tT][lL][aA][bB]*)                 vcs_host_icon=$'\xef\x8a\x96 ' ;; # \uF296 GitLab
                        *[bB][iI][tT][bB][uU][cC][kK][eE][tT]*)     vcs_host_icon=$'\xef\x85\xb1 ' ;; # \uF171 Bitbucket
                        *)                                          vcs_host_icon=$'\xef\x87\x93 ' ;; # \uF1D3 Default Git
                    esac
                fi

                if [ "$is_detached" -eq 0 ]; then
                    if [ -n "$branch_pr" ] && [[ "$branch_pr" =~ ^[1-9][0-9]*$ ]]; then
                        pr_num="$branch_pr"
                        if [ -n "$branch_pr_url" ]; then
                            pr_url="$branch_pr_url"
                        elif [ -n "$remote_url" ]; then
                            _solarized_vcs_build_pr_url -v pr_url "$remote_url" "$pr_num" "$forge_hint" || true
                        fi
                    elif [ "$raw_branch" != "main" ] && [ "$raw_branch" != "master" ] && [ "$raw_branch" != "trunk" ] && [ "$raw_branch" != "develop" ] && [ -n "$commondir" ]; then
                        local cache_dir="${GIT_PR_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/git-pr-prompt}"
                        local repo_key="${commondir//[^A-Za-z0-9._-]/_}"
                        local cache_file="$cache_dir/${repo_key}.state"
                        local cache_fresh=0 now="${EPOCHSECONDS:-}"
                        if [ -z "$now" ]; then
                            printf -v now '%(%s)T' -1 2>/dev/null || now="$(date +%s 2>/dev/null || echo 0)"
                        fi
                        if [ -r "$cache_file" ]; then
                            local c_branch="" c_num="" c_url="" c_ts=""
                            while IFS='|' read -r c_branch c_num c_url c_ts || [ -n "$c_branch" ]; do
                                if [ "$c_branch" = "$raw_branch" ]; then
                                    if [[ "$c_num" =~ ^[1-9][0-9]*$ ]]; then
                                        pr_num="$c_num"
                                        if [ -n "$c_url" ]; then
                                            pr_url="$c_url"
                                        elif [ -n "$remote_url" ]; then
                                            _solarized_vcs_build_pr_url -v pr_url "$remote_url" "$c_num" "$forge_hint" || true
                                        fi
                                    fi
                                    if [[ "$c_ts" =~ ^[0-9]+$ ]] && [ "$((now - c_ts))" -lt "${GIT_PR_CACHE_TTL:-120}" ]; then
                                        cache_fresh=1
                                    fi
                                    break
                                fi
                            done < "$cache_file"
                        fi
                        if [ "$cache_fresh" -eq 0 ] && [ -n "$remote_url" ] && [ "${SOLARIZED_VCS_PR_ASYNC:-1}" != "0" ]; then
                            local lock_active=0
                            if [ -r "${cache_file}.lock" ]; then
                                local lock_ts=""
                                IFS= read -r lock_ts < "${cache_file}.lock" 2>/dev/null || true
                                if [[ "$lock_ts" =~ ^[0-9]+$ ]] && [ "$((now - lock_ts))" -lt 30 ]; then
                                    lock_active=1
                                fi
                            fi
                            if [ "$lock_active" -eq 0 ]; then
                                ( ( _solarized_vcs_refresh_pr_cache "$workdir" "$gitdir" "$raw_branch" "$target_remote" "$remote_url" "$forge_hint" "$cache_file" "$upstream_forge_url" ) </dev/null >/dev/null 2>&1 & )
                            fi
                        fi
                    fi
                fi

                branch="${raw_branch//\\/\\\\}"
                branch="${branch//\$/\\\\\$}"
                branch="${branch//\`/\\\\\`}"
                local git_color="$c_green"
                local dirty_suffix=""
                if [ "$is_conflicted" = "1" ]; then
                    git_color="$c_orange"
                    dirty_suffix="~"
                elif [ "$is_dirty" = "1" ]; then
                    git_color="$c_yellow"
                    dirty_suffix="*"
                fi
                local pr_badge=""
                if [ -n "$pr_num" ]; then
                    pr_badge="${c_base01}@${git_color}${pr_num}"
                    if [ "${TERM:-}" != "linux" ] && [ "${SOLARIZED_PROMPT_HYPERLINK:-true}" = "true" ] && [[ "$pr_url" =~ ^https?://[^[:cntrl:][:space:]]+$ ]]; then
                        local pr_url_esc="${pr_url//\\/\\\\}"
                        pr_url_esc="${pr_url_esc//\$/\\\\\$}"
                        pr_url_esc="${pr_url_esc//\`/\\\\\`}"
                        pr_badge='\[\e]8;;'"${pr_url_esc}"'\a\]'"${pr_badge}"'\[\e]8;;\a\]'
                    fi
                fi
                git_segment="${sep}${git_color}${vcs_host_icon}${git_icon}${branch}${pr_badge}${dirty_suffix}"
            fi
        fi
    fi

    local shelf_end="${c_reset}"
    if [ -n "$endcap" ]; then
        if [ "$exit_code" -ne 0 ]; then
            if [ "${TERM:-}" = "linux" ] || { [ "${COLORTERM:-}" != "truecolor" ] && [ "${COLORTERM:-}" != "24bit" ]; }; then
                c_shelf_cap='\[\e[0m\e[31m\]'
            else
                c_shelf_cap="${_HS_PROMPT_CAP_RED:-\[\e[0m\e[38;2;220;50;47m\]}"
            fi
        fi
        shelf_end="${c_shelf_cap}${endcap}${c_reset}"
        PS1="${bg_shelf} ${lead_segment}${c_blue}\w${git_segment} ${shelf_end} "
    else
        local prompt_symbol="${c_green}${sym}${c_reset}"
        if [ "$exit_code" -ne 0 ]; then
            prompt_symbol="${c_red}${sym}${c_reset}"
        fi
        PS1="${bg_shelf} ${lead_segment}${c_blue}\w${git_segment} ${shelf_end} ${prompt_symbol} "
    fi
}
