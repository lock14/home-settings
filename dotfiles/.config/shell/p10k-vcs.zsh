#!/bin/zsh
# Powerlevel10k Native Git VCS Segment, Zero-Fork .git/config Parser, & 5-Forge PR/MR Hyperlinks
# Sourced by dotfiles/.p10k.zsh with POWERLEVEL9K_DISABLE_GITSTATUS=true.

  function my_git_formatter() {
    emulate -L zsh

    if [[ -n $P9K_CONTENT ]]; then
      # If P9K_CONTENT is not empty, use it. It's either "loading" or from vcs_info (not from
      # gitstatus plugin). VCS_STATUS_* parameters are not available in this case.
      typeset -g my_git_format=$P9K_CONTENT
      return
    fi

    # Styling for different parts of Git status on Base02 background.
    local       meta="%F{${POWERLEVEL9K_VCS_LOADING_FOREGROUND:-#586E75}}" # Base01
    local      clean="%F{${POWERLEVEL9K_VCS_CLEAN_FOREGROUND:-#859900}}" # Solarized Green
    local   modified="%F{${POWERLEVEL9K_VCS_MODIFIED_FOREGROUND:-#B58900}}" # Solarized Yellow
    local conflicted="%F{${POWERLEVEL9K_VCS_CONFLICTED_FOREGROUND:-#CB4B16}}" # Solarized Orange

    # Pure Whole-Segment State: unify entire Git segment by dominant repository state
    local state_color=$clean
    (( VCS_STATUS_HAS_UNSTAGED || VCS_STATUS_HAS_STAGED || VCS_STATUS_NUM_UNTRACKED )) && state_color=$modified
    (( VCS_STATUS_NUM_CONFLICTED )) && state_color=$conflicted

    local res

    if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
      local branch=${(V)VCS_STATUS_LOCAL_BRANCH}
      # If local branch name is at most 32 characters long, show it in full.
      # Otherwise show the first 12 … the last 12.
      # Tip: To always show local branch name in full without truncation, delete the next line.
      (( $#branch > 32 )) && branch[13,-13]=$'\u2026'  # <-- this line
      res+="${state_color}${(g::)POWERLEVEL9K_VCS_BRANCH_ICON}${branch//\%/%%}"
    fi

    if [[ -n $VCS_STATUS_TAG
          # Show tag only if not on a branch.
          # Tip: To always show tag, delete the next line.
          && -z $VCS_STATUS_LOCAL_BRANCH  # <-- this line
        ]]; then
      local tag=${(V)VCS_STATUS_TAG}
      # If tag name is at most 32 characters long, show it in full.
      # Otherwise show the first 12 … the last 12.
      # Tip: To always show tag name in full without truncation, delete the next line.
      (( $#tag > 32 )) && tag[13,-13]=$'\u2026'  # <-- this line
      res+="${meta}#${state_color}${tag//\%/%%}"
    fi

    # Display the current Git commit if there is no branch and no tag.
    # Tip: To always display the current Git commit, delete the next line.
    [[ -z $VCS_STATUS_LOCAL_BRANCH && -z $VCS_STATUS_TAG ]] &&  # <-- this line
      res+="${meta}@${state_color}${VCS_STATUS_COMMIT[1,8]}"

    # Show tracking branch name if it differs from local branch.
    if [[ -n ${VCS_STATUS_REMOTE_BRANCH:#$VCS_STATUS_LOCAL_BRANCH} ]]; then
      res+="${meta}:${state_color}${(V)VCS_STATUS_REMOTE_BRANCH//\%/%%}"
    fi

    # Display "wip" if the latest commit's summary contains "wip" or "WIP".
    if [[ $VCS_STATUS_COMMIT_SUMMARY == (|*[^[:alnum:]])(wip|WIP)(|[^[:alnum:]]*) ]]; then
      res+=" ${state_color}wip"
    fi

    # ⇣42 if behind the remote.
    (( VCS_STATUS_COMMITS_BEHIND )) && res+=" ${state_color}"$'\u21E3'"${VCS_STATUS_COMMITS_BEHIND}"
    # ⇡42 if ahead of the remote; no leading space if also behind the remote: ⇣42⇡42.
    (( VCS_STATUS_COMMITS_AHEAD && !VCS_STATUS_COMMITS_BEHIND )) && res+=" "
    (( VCS_STATUS_COMMITS_AHEAD  )) && res+="${state_color}"$'\u21E1'"${VCS_STATUS_COMMITS_AHEAD}"
    # ⇠42 if behind the push remote.
    (( VCS_STATUS_PUSH_COMMITS_BEHIND )) && res+=" ${state_color}"$'\u21E0'"${VCS_STATUS_PUSH_COMMITS_BEHIND}"
    (( VCS_STATUS_PUSH_COMMITS_AHEAD && !VCS_STATUS_PUSH_COMMITS_BEHIND )) && res+=" "
    # ⇢42 if ahead of the push remote; no leading space if also behind: ⇠42⇢42.
    (( VCS_STATUS_PUSH_COMMITS_AHEAD  )) && res+="${state_color}"$'\u21E2'"${VCS_STATUS_PUSH_COMMITS_AHEAD}"
    # *42 if have stashes.
    (( VCS_STATUS_STASHES        )) && res+=" ${state_color}*${VCS_STATUS_STASHES}"
    # 'merge' if the repo is in an unusual state.
    [[ -n $VCS_STATUS_ACTION     ]] && res+=" ${state_color}${VCS_STATUS_ACTION}"
    # ~42 if have merge conflicts.
    (( VCS_STATUS_NUM_CONFLICTED )) && res+=" ${state_color}~${VCS_STATUS_NUM_CONFLICTED}"
    # +42 if have staged changes.
    (( VCS_STATUS_NUM_STAGED     )) && res+=" ${state_color}+${VCS_STATUS_NUM_STAGED}"
    # !42 if have unstaged changes.
    (( VCS_STATUS_NUM_UNSTAGED   )) && res+=" ${state_color}!${VCS_STATUS_NUM_UNSTAGED}"
    # ?42 if have untracked files. It's really a question mark, your font isn't broken.
    # See POWERLEVEL9K_VCS_UNTRACKED_ICON above if you want to use a different icon.
    # Remove the next line if you don't want to see untracked files at all.
    (( VCS_STATUS_NUM_UNTRACKED  )) && res+=" ${state_color}${(g::)POWERLEVEL9K_VCS_UNTRACKED_ICON}${VCS_STATUS_NUM_UNTRACKED}"
    # "─" if the number of unstaged files is unknown. This can happen due to
    # POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY (see below) being set to a non-negative number lower
    # than the number of files in the Git index, or due to bash.showDirtyState being set to false
    # in the repository config. The number of staged and untracked files may also be unknown
    # in this case.
    (( VCS_STATUS_HAS_UNSTAGED == -1 )) && res+=" ${state_color}"$'\u2500'

    typeset -g my_git_format=$res
  }
  functions -M my_git_formatter 2>/dev/null


  # Pure-Zsh cross-platform PR/MR web URL builder across all 5 major Git forge families:
  # GitHub, GitLab, Bitbucket Cloud, Bitbucket Server / Data Center, and Gitea / Forgejo / Codeberg.
  # Usage: _p9k_vcs_build_pr_url [-v out_var] <remote_url> <pr_num> [forge_hint]
  function _p9k_vcs_build_pr_url() {
    emulate -L zsh -o extended_glob
    local out_var=''
    if [[ ${1:-} == '-v' ]]; then
      out_var=$2
      shift 2
    fi
    typeset -g REPLY=''
    [[ -n $out_var ]] && typeset -g "$out_var="
    local raw_url=${1:-} pr_num=${2:-} forge_hint=${(L)3:-}
    if [[ -z $raw_url || $pr_num != <-> ]] || (( pr_num <= 0 )); then
      return 1
    fi

    local scheme='https' rest=$raw_url
    local -i has_scheme=0 is_http=0
    if [[ $rest == http://* ]]; then
      scheme='http'
      rest=${rest#http://}
      has_scheme=1
      is_http=1
    elif [[ $rest == https://* ]]; then
      scheme='https'
      rest=${rest#https://}
      has_scheme=1
      is_http=1
    elif [[ $rest == (ssh|git|git+ssh)://* ]]; then
      rest=${rest#*://}
      has_scheme=1
    elif [[ $rest == file://* ]]; then
      rest="localhost/${rest#file://}"
      has_scheme=1
    elif [[ $rest == /* ]]; then
      rest="localhost${rest}"
      has_scheme=1
    fi

    local host='' repo_path=''
    if (( has_scheme )); then
      [[ $rest == */* ]] || return 1
      host=${rest%%/*}
      repo_path=${rest#*/}
      host=${host#*@}
      if (( ! is_http )) && [[ $host == *:* && $host != *\] ]]; then
        host=${host%:*}
      fi
    elif [[ $rest == *:* && ( $rest != */* || ${rest%%:*} != */* ) ]]; then
      host=${rest%%:*}
      repo_path=${rest#*:}
      host=${host#*@}
    elif [[ $rest == */* ]]; then
      host=${rest%%/*}
      repo_path=${rest#*/}
      host=${host#*@}
    else
      return 1
    fi

    while [[ $repo_path == /* ]]; do
      repo_path=${repo_path#/}
    done
    while [[ $repo_path == */ ]]; do
      repo_path=${repo_path%/}
    done
    repo_path=${repo_path%.git}
    while [[ $repo_path == */ ]]; do
      repo_path=${repo_path%/}
    done
    [[ -n $host && -n $repo_path ]] || return 1

    local host_l=${(L)host}
    local forge=$forge_hint
    if [[ -z $forge ]]; then
      if [[ $host_l == *github* ]]; then
        forge='github'
      elif [[ $host_l == *gitlab* ]]; then
        forge='gitlab'
      elif [[ $host_l == 'bitbucket.org' ]]; then
        forge='bitbucket-cloud'
      elif [[ $host_l == (*bitbucket*|*stash*) ]]; then
        forge='bitbucket-server'
      elif [[ $host_l == (*codeberg*|*gitea*|*forgejo*) ]]; then
        forge='gitea'
      else
        forge='github'
      fi
    fi

    local built_url=''
    case $forge in
      github)
        built_url="${scheme}://${host}/${repo_path}/pull/${pr_num}"
        ;;
      gitlab)
        built_url="${scheme}://${host}/${repo_path}/-/merge_requests/${pr_num}"
        ;;
      bitbucket-cloud|bitbucket_cloud)
        built_url="https://bitbucket.org/${repo_path}/pull-requests/${pr_num}"
        ;;
      bitbucket-server|bitbucket_server|bitbucket-dc|stash)
        local bb_path=${repo_path#scm/}
        [[ $bb_path == */scm/* ]] && bb_path=${bb_path#*/scm/}
        local proj='' repo=''
        if [[ $bb_path == */* ]]; then
          repo=${bb_path##*/}
          local bb_rem=${bb_path%/*}
          proj=${bb_rem##*/}
        else
          proj=$bb_path
          repo=$bb_path
        fi
        if [[ $proj == \~* ]]; then
          built_url="${scheme}://${host}/users/${proj#\~}/repos/${repo}/pull-requests/${pr_num}"
        else
          built_url="${scheme}://${host}/projects/${(U)proj}/repos/${repo}/pull-requests/${pr_num}"
        fi
        ;;
      gitea|forgejo|codeberg)
        built_url="${scheme}://${host}/${repo_path}/pulls/${pr_num}"
        ;;
      *)
        built_url="${scheme}://${host}/${repo_path}/pull/${pr_num}"
        ;;
    esac

    typeset -g REPLY=$built_url
    if [[ -n $out_var ]]; then
      typeset -g "$out_var=$built_url"
    else
      printf '%s\n' "$built_url"
    fi
    return 0
  }

  # Asynchronous / callable PR/MR state discovery worker (Tier 1 Forge CLIs, Tier 2 git ls-remote
  # virtual PR refs with merged-PR guard, Tier 3 Bitbucket Cloud API, atomic cache state update).
  function _p9k_vcs_refresh_pr_cache() {
    emulate -L zsh -o extended_glob
    local workdir=${1:-${GIT_WORK_TREE:-$PWD}}
    local gitdir=${2:-${GIT_DIR:-}}
    local branch=${3:-}
    local remote_name=${4:-}
    local remote_url=${5:-}
    local forge_hint=${(L)6:-}
    local cache_file=${7:-}
    local upstream_forge_url=${8:-}

    [[ -d $HOME && -d $workdir ]] || return 0

    if [[ -z $gitdir ]]; then
      while [[ $workdir != / && ! -e "$workdir/.git" && ! -L "$workdir/.git" ]]; do
        workdir=${workdir:h}
      done
      if [[ -d "$workdir/.git" ]]; then
        gitdir="$workdir/.git"
      elif [[ -r "$workdir/.git" ]]; then
        local gd_line=''
        read -r gd_line < "$workdir/.git" 2>/dev/null
        gd_line=${gd_line%$'\r'}
        if [[ $gd_line == 'gitdir: '* ]]; then
          gd_line=${gd_line#'gitdir: '}
          [[ $gd_line == /* ]] && gitdir=$gd_line || gitdir="$workdir/$gd_line"
        fi
      fi
    fi
    [[ -n $gitdir ]] || return 1

    if [[ -z $branch ]]; then
      branch=$(git --git-dir="$gitdir" symbolic-ref --short HEAD 2>/dev/null) || return 1
    fi
    [[ -n $branch && $branch != '(detached)' ]] || return 1

    if [[ -z $remote_name ]]; then
      remote_name=$(git --git-dir="$gitdir" config "branch.${branch}.remote" 2>/dev/null)
      [[ -z $remote_name || $remote_name == '.' ]] && remote_name='origin'
    fi
    if [[ -z $remote_url ]]; then
      remote_url=$(git --git-dir="$gitdir" config "remote.${remote_name}.url" 2>/dev/null || git --git-dir="$gitdir" config remote.origin.url 2>/dev/null)
    fi
    [[ -n $remote_url ]] || return 1

    if [[ -z $forge_hint ]]; then
      forge_hint=$(git --git-dir="$gitdir" config "remote.${remote_name}.forge" 2>/dev/null || git --git-dir="$gitdir" config remote.origin.forge 2>/dev/null)
      forge_hint=${(L)forge_hint}
    fi
    if [[ -z $upstream_forge_url && $remote_name != 'upstream' ]]; then
      upstream_forge_url=$(git --git-dir="$gitdir" config remote.upstream.url 2>/dev/null)
    fi

    if [[ -z $cache_file ]]; then
      local commondir=$gitdir
      if [[ -r "$gitdir/commondir" ]]; then
        local common_line=''
        read -r common_line < "$gitdir/commondir" 2>/dev/null
        common_line=${common_line%$'\r'}
        if [[ -n $common_line && $common_line != '.' && $common_line != './' ]]; then
          [[ $common_line == /* ]] && commondir=$common_line || commondir="$gitdir/$common_line"
        fi
      fi
      local cache_dir=${GIT_PR_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/git-pr-prompt}
      local repo_key=${${commondir:A}//[^A-Za-z0-9._-]/_}
      cache_file="$cache_dir/${repo_key}.state"
    fi

    local cache_dir=${cache_file:h}
    command mkdir -p "$cache_dir" 2>/dev/null || return 1
    zmodload -F zsh/datetime b:EPOCHSECONDS 2>/dev/null
    local -i now=${EPOCHSECONDS:-$(date +%s 2>/dev/null || echo 0)}
    printf '%s\n' "$now" > "${cache_file}.lock" 2>/dev/null || true

    local forge=$forge_hint
    local remote_l=${(L)remote_url}
    if [[ -z $forge ]]; then
      if [[ $remote_l == *github* ]]; then
        forge='github'
      elif [[ $remote_l == *gitlab* ]]; then
        forge='gitlab'
      elif [[ $remote_l == *bitbucket.org* ]]; then
        forge='bitbucket-cloud'
      elif [[ $remote_l == (*bitbucket*|*stash*) ]]; then
        forge='bitbucket-server'
      elif [[ $remote_l == (*codeberg*|*gitea*|*forgejo*) ]]; then
        forge='gitea'
      fi
    fi

    local found_num='' found_url=''
    local -i is_local_remote=0
    [[ $remote_url == (/*|./*|../*|file://*) ]] && is_local_remote=1

    # Tier 1: Forge CLIs (gh, glab, tea) when remote is not a local filesystem path
    if (( ! is_local_remote )); then
      if [[ $forge == 'github' ]] && command -v gh >/dev/null 2>&1; then
        local gh_out=''
        gh_out=$(cd "$workdir" 2>/dev/null && GH_PROMPT_DISABLED=1 gh pr view --json number,url,state -q 'select(.state == "OPEN") | "\(.number)|\(.url)"' 2>/dev/null)
        gh_out=${${gh_out%%$'\n'*}%$'\r'}
        if [[ $gh_out == (#b)(<->)\|(*) ]] && (( match[1] > 0 )); then
          found_num=$match[1]
          found_url=$match[2]
        fi
      elif [[ $forge == 'gitlab' ]] && command -v glab >/dev/null 2>&1; then
        local glab_out=''
        glab_out=$(cd "$workdir" 2>/dev/null && glab mr list --source-branch "$branch" -F json 2>/dev/null)
        if [[ $glab_out =~ '"web_url"[[:space:]]*:[[:space:]]*"(https?://[^"\\]*/-/merge_requests/([1-9][0-9]*))"' ]]; then
          found_url=${match[1]}
          found_num=${match[2]}
        elif [[ $glab_out =~ '"iid"[[:space:]]*:[[:space:]]*([1-9][0-9]*)' ]]; then
          found_num=${match[1]}
          _p9k_vcs_build_pr_url -v found_url "$remote_url" "$found_num" "gitlab"
        fi
      elif [[ $forge == (gitea|forgejo|codeberg) ]] && command -v tea >/dev/null 2>&1; then
        local tea_out='' t_idx='' t_head='' t_url='' t_rest=''
        tea_out=$(cd "$workdir" 2>/dev/null && tea pr list --state open --fields index,head,url -o simple 2>/dev/null)
        while IFS=$' \t' read -r t_idx t_head t_url t_rest || [[ -n $t_idx ]]; do
          t_idx=${t_idx#\#}
          if [[ $t_idx == <-> ]] && (( t_idx > 0 )) && [[ $t_head == "$branch" || $t_head == *":$branch" ]]; then
            found_num=$t_idx
            if [[ $t_url == https://* || $t_url == http://* ]]; then
              found_url=$t_url
            else
              _p9k_vcs_build_pr_url -v found_url "$remote_url" "$found_num" "gitea"
            fi
            break
          fi
        done <<< "$tea_out"
      fi
    fi

    # Tier 2: Pure `git ls-remote` virtual PR refs (GitHub, GitLab, Bitbucket Server/DC, Gitea/Forgejo/Codeberg)
    if [[ -z $found_num && ( $forge != 'bitbucket-cloud' || $is_local_remote -eq 1 ) ]]; then
      local ls_out=''
      ls_out=$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=5}" \
        git --git-dir="$gitdir" ls-remote "$remote_url" \
        "HEAD" "refs/heads/main" "refs/heads/master" "refs/heads/trunk" "refs/heads/develop" \
        "refs/heads/$branch" "refs/pull/*/head" "refs/merge-requests/*/head" "refs/pull-requests/*/from" 2>/dev/null)
      if [[ -n $ls_out ]]; then
        local branch_remote_sha='' r_sha='' r_ref=''
        local -A default_shas=() pr_ref_shas=() pr_ref_kinds=()
        for line in "${(@f)ls_out}"; do
          r_sha=${line%%[[:space:]]*}
          r_ref=${line##*[[:space:]]}
          [[ -z $r_sha || -z $r_ref ]] && continue
          if [[ $r_ref == "refs/heads/$branch" ]]; then
            branch_remote_sha=$r_sha
          elif [[ $r_ref == ('HEAD'|'refs/heads/main'|'refs/heads/master'|'refs/heads/trunk'|'refs/heads/develop') ]]; then
            default_shas[$r_sha]=1
          elif [[ $r_ref == (#b)refs/pull/(<->)/head ]]; then
            pr_ref_shas[$match[1]]=$r_sha
            pr_ref_kinds[$match[1]]=''
          elif [[ $r_ref == (#b)refs/merge-requests/(<->)/head ]]; then
            pr_ref_shas[$match[1]]=$r_sha
            pr_ref_kinds[$match[1]]='gitlab'
          elif [[ $r_ref == (#b)refs/pull-requests/(<->)/from ]]; then
            pr_ref_shas[$match[1]]=$r_sha
            pr_ref_kinds[$match[1]]='bitbucket-server'
          fi
        done

        if [[ -n $branch_remote_sha && -z ${default_shas[$branch_remote_sha]:-} ]]; then
          local -i best_num=0 cand_num=0
          local best_kind='' k=''
          for k in "${(@k)pr_ref_shas}"; do
            if [[ ${pr_ref_shas[$k]} == "$branch_remote_sha" ]]; then
              cand_num=$k
              if (( cand_num > best_num )); then
                best_num=$cand_num
                best_kind=${pr_ref_kinds[$k]}
              fi
            fi
          done
          if (( best_num > 0 )); then
            found_num=$best_num
            _p9k_vcs_build_pr_url -v found_url "$remote_url" "$found_num" "${forge_hint:-$best_kind}"
          elif [[ -n $upstream_forge_url && $upstream_forge_url != "$remote_url" ]]; then
            local up_ls_out=''
            up_ls_out=$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=5}" \
              git --git-dir="$gitdir" ls-remote "$upstream_forge_url" \
              "HEAD" "refs/heads/main" "refs/heads/master" "refs/heads/trunk" "refs/heads/develop" \
              "refs/pull/*/head" "refs/merge-requests/*/head" "refs/pull-requests/*/from" 2>/dev/null)
            if [[ -n $up_ls_out ]]; then
              local -A up_default_shas=()
              local -i up_best_num=0
              local up_best_kind=''
              for line in "${(@f)up_ls_out}"; do
                r_sha=${line%%[[:space:]]*}
                r_ref=${line##*[[:space:]]}
                if [[ $r_ref == ('HEAD'|'refs/heads/main'|'refs/heads/master'|'refs/heads/trunk'|'refs/heads/develop') ]]; then
                  up_default_shas[$r_sha]=1
                fi
              done
              if [[ -z ${up_default_shas[$branch_remote_sha]:-} ]]; then
                for line in "${(@f)up_ls_out}"; do
                  r_sha=${line%%[[:space:]]*}
                  r_ref=${line##*[[:space:]]}
                  [[ $r_sha == "$branch_remote_sha" ]] || continue
                  if [[ $r_ref == (#b)refs/pull/(<->)/head ]] && (( match[1] > up_best_num )); then
                    up_best_num=$match[1]
                    up_best_kind=''
                  elif [[ $r_ref == (#b)refs/merge-requests/(<->)/head ]] && (( match[1] > up_best_num )); then
                    up_best_num=$match[1]
                    up_best_kind='gitlab'
                  elif [[ $r_ref == (#b)refs/pull-requests/(<->)/from ]] && (( match[1] > up_best_num )); then
                    up_best_num=$match[1]
                    up_best_kind='bitbucket-server'
                  fi
                done
                if (( up_best_num > 0 )); then
                  found_num=$up_best_num
                  _p9k_vcs_build_pr_url -v found_url "$upstream_forge_url" "$found_num" "$up_best_kind"
                fi
              fi
            fi
          fi
        fi
      fi
    fi

    # Tier 3: Bitbucket Cloud (bitbucket.org) REST API fallback
    if [[ -z $found_num && ( $forge == 'bitbucket-cloud' || $remote_l == *bitbucket.org* ) ]] && (( ! is_local_remote )) && command -v curl >/dev/null 2>&1; then
      local bb_probe='' bb_rest=''
      _p9k_vcs_build_pr_url -v bb_probe "$remote_url" 1 "bitbucket-cloud"
      bb_rest=${${bb_probe#https://bitbucket.org/}%/pull-requests/1}
      if [[ $bb_rest == */* ]]; then
        local -a curl_args=(-fsSL --max-time 5)
        if [[ -n ${BITBUCKET_TOKEN:-} ]]; then
          curl_args+=(-H "Authorization: Bearer $BITBUCKET_TOKEN")
        elif [[ -r "$HOME/.netrc" ]]; then
          curl_args+=(-n)
        fi
        local bb_json=''
        bb_json=$(curl "${curl_args[@]}" "https://api.bitbucket.org/2.0/repositories/${bb_rest}/pullrequests?q=source.branch.name=%22${branch}%22+AND+state=%22OPEN%22&pagelen=1" 2>/dev/null)
        if [[ $bb_json =~ '"id"[[:space:]]*:[[:space:]]*([1-9][0-9]*)' ]]; then
          found_num=${match[1]}
          if [[ $bb_json =~ '"href"[[:space:]]*:[[:space:]]*"(https?://[^"\\]*/pull-requests/[1-9][0-9]*)"' ]]; then
            found_url=${match[1]}
          else
            _p9k_vcs_build_pr_url -v found_url "$remote_url" "$found_num" "bitbucket-cloud"
          fi
        fi
      fi
    fi

    [[ -d $HOME && -d $cache_dir ]] || return 0
    local tmp_file="${cache_file}.tmp.$$"
    {
      if [[ -r $cache_file ]]; then
        local existing_line=''
        while IFS= read -r existing_line || [[ -n $existing_line ]]; do
          [[ -z $existing_line || $existing_line == "${branch}|"* ]] && continue
          printf '%s\n' "$existing_line"
        done < "$cache_file"
      fi
      printf '%s|%s|%s|%s\n' "$branch" "${found_num:-NONE}" "$found_url" "$now"
    } > "$tmp_file" 2>/dev/null && command mv -f "$tmp_file" "$cache_file" 2>/dev/null || command rm -f "$tmp_file" 2>/dev/null
    command rm -f "${cache_file}.lock" 2>/dev/null || true
    return 0
  }

  # Invalidate PR state cache immediately on git push / gpush / gpushf / gh pr / glab mr / tea pr / bkt pr
  function _p9k_solarized_vcs_preexec() {
    emulate -L zsh -o extended_glob
    local cmd="${1:-} ${2:-}"
    if [[ $cmd =~ '(^|[[:space:];|&])(git([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+push|gpush|gpushf|gh[[:space:]]+pr|glab[[:space:]]+mr|tea[[:space:]]+pr|bkt[[:space:]]+pr)([[:space:];|&]|$)' ]]; then
      local cache_dir=${GIT_PR_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/git-pr-prompt}
      [[ -d $cache_dir ]] && command rm -f "$cache_dir"/*.state(#qN) "$cache_dir"/*.lock(#qN) 2>/dev/null
    fi
    return 0
  }

  # Native Powerlevel10k VCS segment powered by `git status --porcelain=v2 --branch`.
  # Supports all modern Git repository extensions (reftable, SHA-256, worktrees) in a single fork.
  function _p9k_solarized_prompt_vcs() {
    emulate -L zsh -o extended_glob
    typeset -g my_git_format=''

    local pat=''
    if [[ -n ${POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN:-} ]]; then
      # Expand `~` at the start of the pattern or of any `|`/`(` alternative (e.g. '~|/extra/*').
      pat=${POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN//(#b)((#s)|[|(])\~/${match[1]}$HOME}
      [[ $PWD == $~pat ]] && return 0
    fi

    # Discover Git worktree root in pure Zsh (zero forks) to skip non-repo directories
    # and enforce POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN even inside subdirectories.
    local workdir=$PWD
    if [[ -n ${GIT_WORK_TREE:-} ]]; then
      workdir=${GIT_WORK_TREE:A}
    elif [[ -z ${GIT_DIR:-} ]]; then
      while [[ $workdir != / && ! -e "$workdir/.git" && ! -L "$workdir/.git" ]]; do
        workdir=${workdir:h}
      done
      [[ -e "$workdir/.git" || -L "$workdir/.git" ]] || return 0
    fi
    [[ -n $pat && $workdir == $~pat ]] && return 0

    command -v git >/dev/null 2>&1 || return 0

    local status_out
    status_out=$(git --no-optional-locks status --porcelain=v2 --branch 2>/dev/null) || return 0

    local branch='' oid='' upstream='' line ab a_str b_str
    local -i ahead=0 behind=0 staged=0 unstaged=0 untracked=0 conflicted=0

    for line in "${(@f)status_out}"; do
      if [[ $line == '# branch.head '* ]]; then
        branch=${line#'# branch.head '}
      elif [[ $line == '# branch.oid '* ]]; then
        oid=${line#'# branch.oid '}
      elif [[ $line == '# branch.upstream '* ]]; then
        upstream=${line#'# branch.upstream '}
      elif [[ $line == '# branch.ab '* ]]; then
        ab=${line#'# branch.ab '}
        a_str=${ab%% *}
        b_str=${ab#* }
        ahead=${a_str#+}
        behind=${b_str#-}
      elif [[ $line == [12]\ * ]]; then
        [[ ${line[3]} == [MTADRC] ]] && (( ++staged ))
        [[ ${line[4]} == [MTADRC] ]] && (( ++unstaged ))
      elif [[ $line == u\ * ]]; then
        (( ++conflicted ))
      elif [[ $line == \?\ * ]]; then
        (( ++untracked ))
      fi
    done

    # Resolve .git directory (and commondir for linked worktrees) in pure Zsh (zero forks)
    # to extract remote URL and render the appropriate GitHub / GitLab / Bitbucket / Git icon.
    local gitdir=''
    if [[ -n ${GIT_DIR:-} ]]; then
      gitdir=${GIT_DIR:A}
    elif [[ -d "$workdir/.git" ]]; then
      gitdir="$workdir/.git"
    elif [[ -r "$workdir/.git" ]]; then
      local gd_line=''
      read -r gd_line < "$workdir/.git"
      gd_line=${gd_line%$'\r'}
      if [[ $gd_line == 'gitdir: '* ]]; then
        gd_line=${gd_line#'gitdir: '}
        if [[ $gd_line == /* ]]; then
          gitdir=$gd_line
        else
          gitdir="$workdir/$gd_line"
        fi
      fi
    fi

    local -A remote_urls=() remote_forges=() instead_of=() seen_cfgs=()
    local first_remote_name='' branch_remote='' branch_pr='' branch_pr_url='' merge_forge_hint=''
    function _p9k_vcs_parse_cfg() {
      local cfg_file=$1 is_repo_cfg=${2:-0} depth=${3:-0}
      (( depth > 4 )) || [[ ! -r $cfg_file ]] && return 0
      seen_cfgs[$cfg_file]=1
      local section_type='' section_name='' seen_url_in_section=0 cfg_line='' next_line='' pre_bracket='' hdr='' key='' val=''
      while IFS= read -r cfg_line || [[ -n $cfg_line ]]; do
        cfg_line=${cfg_line%$'\r'}
        local lead_trim=${cfg_line##[[:space:]]#}
        [[ -z $lead_trim || $lead_trim == [#\;]* ]] && continue
        while [[ $cfg_line == *\\ ]]; do
          integer ci=1 cn=${#cfg_line} cin_q=0 cesc=0
          local cch=''
          while (( ci <= cn )); do
            cch=${cfg_line[ci]}
            if (( cesc )); then
              cesc=0
            elif [[ $cch == '\' ]]; then
              cesc=1
            elif [[ $cch == '"' ]]; then
              cin_q=$(( 1 - cin_q ))
            elif (( ! cin_q )) && [[ $cch == '#' || $cch == ';' ]]; then
              cesc=0
              break
            fi
            (( ci++ ))
          done
          (( ! cesc )) && break
          next_line=''
          IFS= read -r next_line || break
          next_line=${next_line%$'\r'}
          cfg_line="${cfg_line%\\}${next_line}"
        done
        cfg_line=${cfg_line##[[:space:]]#}
        [[ -z $cfg_line || $cfg_line == [#\;]* ]] && continue
        if [[ $cfg_line == \[*\]* ]]; then
          seen_url_in_section=0
          pre_bracket=${${cfg_line#\[}%%\]*}
          if [[ $pre_bracket == *\"* ]]; then
            local h_rest=${${cfg_line#\[}##[[:space:]]#}
            section_type=${(L)h_rest%%[[:space:]\"]*}
            local q_body=${h_rest#*\"}
            section_name=''
            if [[ $q_body != *\\* && $q_body == *\"\]* ]]; then
              section_name=${q_body%%\"\]*}
            else
              integer qi=1 qn=${#q_body}
              local qch='' qnx=''
              while (( qi <= qn )); do
                qch=${q_body[qi]}
                if [[ $qch == '\' ]] && (( qi < qn )); then
                  qnx=${q_body[qi+1]}
                  case $qnx in
                    n) section_name+=$'\n' ;;
                    t) section_name+=$'\t' ;;
                    b) section_name+=$'\b' ;;
                    *) section_name+=$qnx ;;
                  esac
                  (( qi += 2 ))
                  continue
                elif [[ $qch == '"' ]]; then
                  break
                fi
                section_name+=$qch
                (( qi++ ))
              done
            fi
          else
            hdr=${pre_bracket##[[:space:]]#}
            hdr=${hdr%%[[:space:]]#}
            if [[ $hdr == *.* ]]; then
              section_type=${(L)hdr%%.*}
              section_name=${hdr#*.}
            else
              section_type=${(L)hdr}
              section_name=''
            fi
          fi
          if [[ $section_type == 'includeif' ]]; then
            section_type=''
            local cond_pat='' cond_icase=0
            if [[ $section_name == gitdir/i:* ]]; then
              cond_pat=${section_name#gitdir/i:}
              cond_icase=1
            elif [[ $section_name == gitdir:* ]]; then
              cond_pat=${section_name#gitdir:}
            elif [[ $section_name == onbranch:* ]]; then
              cond_pat=${section_name#onbranch:}
              [[ $cond_pat == */ ]] && cond_pat="${cond_pat}*"
              [[ $branch == $~cond_pat ]] && section_type='include'
              cond_pat=''
            fi
            if [[ -n $cond_pat ]]; then
              [[ $cond_pat == \~/* ]] && cond_pat="$HOME/${cond_pat#\~/}"
              [[ $cond_pat == ./* ]] && cond_pat="${cfg_file:h}/${cond_pat#./}"
              [[ $cond_pat != /* ]] && cond_pat="*/$cond_pat"
              [[ $cond_pat == */ ]] && cond_pat="${cond_pat}*"
              local cond_pat_alt=${cond_pat//\/\*\*\//\/}
              if (( cond_icase )); then
                [[ "${(L)gitdir}/" == ${(L)~cond_pat} || "${(L)workdir}/.git/" == ${(L)~cond_pat} || "${(L)gitdir}/" == ${(L)~cond_pat_alt} || "${(L)workdir}/.git/" == ${(L)~cond_pat_alt} ]] && section_type='include'
              else
                [[ "$gitdir/" == $~cond_pat || "$workdir/.git/" == $~cond_pat || "$gitdir/" == $~cond_pat_alt || "$workdir/.git/" == $~cond_pat_alt ]] && section_type='include'
              fi
            fi
          elif [[ $section_type != (remote|branch|url|include) ]]; then
            section_type=''
            section_name=''
          fi
          continue
        fi
        [[ -z $section_type || $cfg_line != *=* ]] && continue
        key=${(L)${cfg_line%%=*}%%[[:space:]]#}
        val=${${cfg_line#*=}##[[:space:]]#}
        if [[ $val != *\"* && $val != *\\* ]]; then
          val=${val%%[#\;]*}
          val=${val%%[[:space:]]#}
        else
          integer vi=1 vn=${#val} vin_q=0
          local vparsed='' vlast='' vch='' vnx=''
          while (( vi <= vn )); do
            vch=${val[vi]}
            if (( vin_q )); then
              if [[ $vch == '\' ]] && (( vi < vn )); then
                vnx=${val[vi+1]}
                case $vnx in
                  n) vparsed+=$'\n' ;;
                  t) vparsed+=$'\t' ;;
                  b) vparsed+=$'\b' ;;
                  *) vparsed+=$vnx ;;
                esac
                vlast=$vparsed
                (( vi += 2 ))
                continue
              elif [[ $vch == '"' ]]; then
                vin_q=0
                vlast=$vparsed
                (( vi++ ))
                continue
              fi
              vparsed+=$vch
              vlast=$vparsed
            else
              if [[ $vch == '#' || $vch == ';' ]]; then
                break
              elif [[ $vch == '"' ]]; then
                vin_q=1
                (( vi++ ))
                continue
              elif [[ $vch == '\' ]] && (( vi < vn )); then
                vnx=${val[vi+1]}
                case $vnx in
                  n) vparsed+=$'\n' ;;
                  t) vparsed+=$'\t' ;;
                  b) vparsed+=$'\b' ;;
                  *) vparsed+=$vnx ;;
                esac
                vlast=$vparsed
                (( vi += 2 ))
                continue
              fi
              vparsed+=$vch
              [[ $vch != [[:space:]] ]] && vlast=$vparsed
            fi
            (( vi++ ))
          done
          val=$vlast
        fi
        [[ -z $val ]] && continue
        if [[ $section_type == 'remote' && $key == 'url' ]]; then
          if (( ! seen_url_in_section )); then
            remote_urls[$section_name]=$val
            seen_url_in_section=1
            (( is_repo_cfg )) && : ${first_remote_name:=$section_name}
          fi
        elif [[ $section_type == 'remote' && $key == 'forge' ]]; then
          remote_forges[$section_name]=${(L)val}
        elif [[ $section_type == 'branch' && $section_name == "$branch" ]]; then
          if [[ $key == 'remote' ]]; then
            branch_remote=$val
          elif [[ $key == 'pr' && $val == <-> ]] && (( val > 0 )); then
            branch_pr=$val
          elif [[ $key == 'prurl' ]]; then
            branch_pr_url=$val
          elif [[ $key == 'merge' ]]; then
            if [[ $val == (#b)refs/pull/(<->)/head ]] && (( match[1] > 0 )); then
              [[ -z $branch_pr ]] && branch_pr=$match[1]
              merge_forge_hint='github'
            elif [[ $val == (#b)refs/merge-requests/(<->)/head ]] && (( match[1] > 0 )); then
              [[ -z $branch_pr ]] && branch_pr=$match[1]
              merge_forge_hint='gitlab'
            elif [[ $val == (#b)refs/pull-requests/(<->)/(from|head) ]] && (( match[1] > 0 )); then
              [[ -z $branch_pr ]] && branch_pr=$match[1]
              merge_forge_hint='bitbucket-server'
            fi
          fi
        elif [[ $section_type == 'url' && $key == 'insteadof' ]]; then
          instead_of[$val]=$section_name
        elif [[ $section_type == 'include' && $key == 'path' ]]; then
          local inc_path=$val
          [[ $inc_path == \~/* ]] && inc_path="$HOME/${inc_path#\~/}"
          [[ $inc_path != /* ]] && inc_path="${cfg_file:h}/$inc_path"
          [[ -z ${seen_cfgs[$inc_path]:-} ]] && _p9k_vcs_parse_cfg "$inc_path" "$is_repo_cfg" $(( depth + 1 ))
        fi
      done < "$cfg_file"
    }

    if [[ -n ${GIT_CONFIG_GLOBAL:-} ]]; then
      _p9k_vcs_parse_cfg "$GIT_CONFIG_GLOBAL" 0
    else
      _p9k_vcs_parse_cfg "${XDG_CONFIG_HOME:-$HOME/.config}/git/config" 0
      _p9k_vcs_parse_cfg "$HOME/.gitconfig" 0
    fi
    local commondir=$gitdir
    if [[ -n $gitdir ]]; then
      if [[ -r "$gitdir/commondir" ]]; then
        local common_line=''
        read -r common_line < "$gitdir/commondir"
        common_line=${common_line%$'\r'}
        if [[ -n $common_line && $common_line != '.' && $common_line != './' ]]; then
          if [[ $common_line == /* ]]; then
            commondir=$common_line
          else
            commondir="$gitdir/$common_line"
          fi
          [[ "${commondir:A}/config" != "${gitdir:A}/config" ]] && _p9k_vcs_parse_cfg "$commondir/config" 1
        fi
      fi
      _p9k_vcs_parse_cfg "$gitdir/config" 1
      _p9k_vcs_parse_cfg "$gitdir/config.worktree" 1
    fi
    unfunction _p9k_vcs_parse_cfg 2>/dev/null

    local remote_name=''
    if [[ -n $branch_remote && $branch_remote != '.' && -n ${remote_urls[$branch_remote]:-} ]]; then
      remote_name=$branch_remote
    elif [[ $upstream == */* && -n ${remote_urls[${upstream%%/*}]:-} ]]; then
      remote_name=${upstream%%/*}
    elif [[ -n $branch_remote && $branch_remote != '.' ]]; then
      remote_name=$branch_remote
    elif [[ $upstream == */* ]]; then
      remote_name=${upstream%%/*}
    else
      remote_name='origin'
    fi
    local first_remote_url=${first_remote_name:+${remote_urls[$first_remote_name]:-}}
    local remote_url=${remote_urls[$remote_name]:-${remote_urls[origin]:-$first_remote_url}}
    if [[ -n $remote_url ]] && (( $#instead_of > 0 )); then
      local pfx best_pfx=''
      for pfx in "${(@k)instead_of}"; do
        if [[ $remote_url == "$pfx"* ]] && (( $#pfx > $#best_pfx )); then
          best_pfx=$pfx
        fi
      done
      [[ -n $best_pfx ]] && remote_url="${instead_of[$best_pfx]}${remote_url#$best_pfx}"
    fi
    typeset -g VCS_STATUS_REMOTE_URL=$remote_url

    local first_remote_forge=${first_remote_name:+${remote_forges[$first_remote_name]:-}}
    local forge_hint=${remote_forges[$remote_name]:-${remote_forges[origin]:-${first_remote_forge:-$merge_forge_hint}}}

    # Resolve PR/MR number and URL (Tier 0 .git/config -> Tier 0.5 zero-fork state cache -> async worker)
    local pr_num='' pr_url=''
    if [[ -n $branch && $branch != '(detached)' ]]; then
      if [[ -n $branch_pr && $branch_pr == <-> ]] && (( branch_pr > 0 )); then
        pr_num=$branch_pr
        if [[ -n $branch_pr_url ]]; then
          pr_url=$branch_pr_url
        elif [[ -n $remote_url ]]; then
          _p9k_vcs_build_pr_url -v pr_url "$remote_url" "$pr_num" "$forge_hint"
        fi
      elif [[ $branch != (main|master|trunk|develop) && -n $commondir ]]; then
        local cache_dir=${GIT_PR_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/git-pr-prompt}
        local repo_key=${${commondir:A}//[^A-Za-z0-9._-]/_}
        local cache_file="$cache_dir/${repo_key}.state"
        local -i cache_fresh=0 now=${EPOCHSECONDS:-0}
        if [[ -r $cache_file ]]; then
          local c_branch='' c_num='' c_url='' c_ts=''
          while IFS='|' read -r c_branch c_num c_url c_ts || [[ -n $c_branch ]]; do
            if [[ $c_branch == "$branch" ]]; then
              if [[ $c_num == <-> ]] && (( c_num > 0 )); then
                pr_num=$c_num
                if [[ -n $c_url ]]; then
                  pr_url=$c_url
                elif [[ -n $remote_url ]]; then
                  _p9k_vcs_build_pr_url -v pr_url "$remote_url" "$c_num" "$forge_hint"
                fi
              fi
              if [[ $c_ts == <-> ]] && (( now - c_ts < ${GIT_PR_CACHE_TTL:-120} )); then
                cache_fresh=1
              fi
              break
            fi
          done < "$cache_file"
        fi
        if (( ! cache_fresh )) && [[ -n $remote_url && ${SOLARIZED_VCS_PR_ASYNC:-1} != 0 ]]; then
          local -i lock_active=0
          if [[ -r "${cache_file}.lock" ]]; then
            local lock_ts=''
            read -r lock_ts < "${cache_file}.lock" 2>/dev/null
            if [[ $lock_ts == <-> ]] && (( now - lock_ts < 30 )); then
              lock_active=1
            fi
          fi
          if (( ! lock_active )); then
            local upstream_forge_url=${remote_urls[upstream]:-}
            if [[ -n $upstream_forge_url ]] && (( $#instead_of > 0 )); then
              local u_pfx u_best_pfx=''
              for u_pfx in "${(@k)instead_of}"; do
                if [[ $upstream_forge_url == "$u_pfx"* ]] && (( $#u_pfx > $#u_best_pfx )); then
                  u_best_pfx=$u_pfx
                fi
              done
              [[ -n $u_best_pfx ]] && upstream_forge_url="${instead_of[$u_best_pfx]}${upstream_forge_url#$u_best_pfx}"
            fi
            ( ( _p9k_vcs_refresh_pr_cache "$workdir" "$gitdir" "$branch" "$remote_name" "$remote_url" "$forge_hint" "$cache_file" "$upstream_forge_url" ) </dev/null >/dev/null 2>&1 & )
          fi
        fi
      fi
    fi
    typeset -g VCS_STATUS_PR_NUM=$pr_num VCS_STATUS_PR_URL=$pr_url

    local vcs_icon
    case $remote_url in
      (#i)*github*)
        vcs_icon=${(g::)POWERLEVEL9K_VCS_GIT_GITHUB_ICON:-$'\uF113 '}
        ;;
      (#i)*gitlab*)
        vcs_icon=${(g::)POWERLEVEL9K_VCS_GIT_GITLAB_ICON:-$'\uF296 '}
        ;;
      (#i)*bitbucket*)
        vcs_icon=${(g::)POWERLEVEL9K_VCS_GIT_BITBUCKET_ICON:-$'\uF171 '}
        ;;
      *)
        vcs_icon=${(g::)POWERLEVEL9K_VCS_GIT_ICON:-$'\uF1D3 '}
        ;;
    esac
    [[ ${POWERLEVEL9K_ICON_PADDING:-none} == none ]] && vcs_icon=${vcs_icon%% #}

    local meta_hex=${POWERLEVEL9K_VCS_LOADING_FOREGROUND:-#586E75}
    local clean_hex=${POWERLEVEL9K_VCS_CLEAN_FOREGROUND:-#859900}
    local modified_hex=${POWERLEVEL9K_VCS_MODIFIED_FOREGROUND:-#B58900}
    local conflicted_hex=${POWERLEVEL9K_VCS_CONFLICTED_FOREGROUND:-#CB4B16}
    local vcs_bg_hex=${POWERLEVEL9K_VCS_CLEAN_BACKGROUND:-#073642}
    local       meta="%F{${meta_hex}}"
    local      clean="%F{${clean_hex}}"
    local   modified="%F{${modified_hex}}"
    local conflicted_c="%F{${conflicted_hex}}"

    local state='CLEAN'
    local state_hex=$clean_hex
    local state_color=$clean
    if (( staged > 0 || unstaged > 0 || untracked > 0 )); then
      state='MODIFIED'
      state_hex=$modified_hex
      state_color=$modified
    fi
    if (( conflicted > 0 )); then
      state='CONFLICTED'
      state_hex=$conflicted_hex
      state_color=$conflicted_c
    fi

    local branch_icon=${(g::)POWERLEVEL9K_VCS_BRANCH_ICON:-$'\uF126 '}
    [[ ${POWERLEVEL9K_ICON_PADDING:-none} != none ]] && branch_icon+=' '
    local untracked_icon=${(g::)POWERLEVEL9K_VCS_UNTRACKED_ICON:-'?'}
    local res=''

    if [[ -n $branch && $branch != '(detached)' ]]; then
      local clean_branch=${(V)branch}
      (( $#clean_branch > 32 )) && clean_branch[13,-13]=$'\u2026'
      res+="${state_color}${branch_icon}${clean_branch//\%/%%}"
      local remote_branch=${upstream#*/}
      if [[ -n $upstream && $remote_branch != "$branch" ]]; then
        res+="${meta}:${state_color}${(V)remote_branch//\%/%%}"
      fi
      if [[ -n $pr_num ]]; then
        local pr_esc="${pr_num//\%/%%}"
        local pr_badge="${meta}@${state_color}${pr_esc}"
        if [[ "${POWERLEVEL9K_VCS_HYPERLINK:-true}" == true ]] && (( ${_p9k_term_has_href:-1} )) && [[ $pr_url == https://* || $pr_url == http://* ]]; then
          local url_esc="${pr_url//\%/%%}"
          pr_badge=$'%{\e]8;;'${url_esc}$'\a%}'"${pr_badge}"$'%{\e]8;;\a%}'
        fi
        res+="${pr_badge}"
      fi
    else
      res+="${state_color}${branch_icon}${meta}@${state_color}${oid[1,8]}"
    fi

    (( behind > 0 )) && res+=" ${state_color}"$'\u21E3'"${behind}"
    (( ahead > 0 && behind == 0 )) && res+=" "
    (( ahead > 0 )) && res+="${state_color}"$'\u21E1'"${ahead}"
    (( conflicted > 0 )) && res+=" ${state_color}~${conflicted}"
    (( staged > 0 )) && res+=" ${state_color}+${staged}"
    (( unstaged > 0 )) && res+=" ${state_color}!${unstaged}"
    (( untracked > 0 )) && res+=" ${state_color}${untracked_icon}${untracked}"

    typeset -g my_git_format=$res
    if (( $+functions[p10k] )); then
      if [[ -n ${_p9k__prompt_side:-} ]] || [[ ${functions[p10k]} != *_p9k__prompt_side* ]]; then
        p10k segment -s "$state" -b "$vcs_bg_hex" -f "$state_hex" -i "$vcs_icon" -t "$res"
      else
        local _p9k__prompt_side=left _p9k__segment_name=vcs
        local -i _p9k__segment_index=3 _p9k__line_index=1
        p10k segment -s "$state" -b "$vcs_bg_hex" -f "$state_hex" -i "$vcs_icon" -t "$res"
      fi
    fi
  }
