#!/bin/zsh
# Powerlevel10k Monorepo Subtree Project Dominance & Segment Hook Installer
# Sourced by dotfiles/.p10k.zsh after p10k-vcs.zsh.

  # Nearest-root project dominance & subtree scoping for right-prompt toolchain segments.
  # Prevents repo-root package.json files (e.g. ~/workspace/package.json) or $HOME files from
  # bleeding into nested non-Node subdirectories (e.g. ~/workspace/terraform/prod-cluster).
  function _p9k_solarized_project_active() {
    emulate -L zsh -o extended_glob
    local tool=''
    case ${1:-} in
      node|node_version)           tool=node ;;
      package)                     tool=package ;;
      terraform|terraform_version) tool=terraform ;;
      go|go_version)               tool=go ;;
      rust|rust_version)           tool=rust ;;
      java|java_version)           tool=java ;;
      python|python_version)       tool=python ;;
      *) return 1 ;;
    esac

    local home_dir=${HOME%/}
    local cur_dir=${PWD%/}
    [[ -z $cur_dir ]] && cur_dir=/
    [[ $cur_dir == "$home_dir" || $cur_dir == / || $cur_dir == /tmp ]] && return 1

    local -a dirs=()
    local d=$cur_dir
    while [[ -n $d && $d != / && $d != /tmp && $d != "$home_dir" && $d != "${home_dir:h}" ]]; do
      dirs+=("$d")
      local parent=${d:h}
      [[ $parent == "$d" ]] && break
      d=$parent
    done
    (( $#dirs == 0 )) && return 1

    local node_pat='package.json|package-lock.json|yarn.lock|pnpm-lock.yaml|bun.lockb|.node-version|.nvmrc|tsconfig.json|jsconfig.json|*.(js|mjs|cjs|ts|mts|cts|jsx|tsx)'
    local pkg_pat='package.json'
    local node_root_pat='package.json|package-lock.json|yarn.lock|pnpm-lock.yaml|bun.lockb|.node-version|.nvmrc|tsconfig.json|jsconfig.json'
    local tf_pat='*.tf|*.tfvars|*.tftpl|.terraform.lock.hcl|.terraform-version'
    local go_pat='go.mod|go.work|*.go'
    local rust_pat='Cargo.toml|*.rs'
    local java_pat='pom.xml|build.gradle|build.gradle.kts|build.sbt|deps.edn|project.clj|build.boot|*.(java|gradle|class|jar|clj|cljc)'
    local py_pat='pyproject.toml|setup.py|Pipfile|*.py'

    local target_pat=''
    case $tool in
      node)      target_pat=$node_pat ;;
      package)   target_pat=$pkg_pat ;;
      terraform) target_pat=$tf_pat ;;
      go)        target_pat=$go_pat ;;
      rust)      target_pat=$rust_pat ;;
      java)      target_pat=$java_pat ;;
      python)    target_pat=$py_pat ;;
    esac

    local -i target_idx=0 i
    local -a m=()
    for (( i = 1; i <= $#dirs; ++i )); do
      m=( "${dirs[i]}"/(${~target_pat})(#qN-.Y1) )
      if (( $#m > 0 )); then
        target_idx=$i
        break
      fi
    done
    (( target_idx == 0 )) && return 1
    (( target_idx == 1 )) && return 0

    local -i check_idx=$target_idx
    if [[ $tool == (node|package) ]]; then
      local -i root_idx=0
      for (( i = 1; i <= $#dirs; ++i )); do
        m=( "${dirs[i]}"/(${~node_root_pat})(#qN-.Y1) )
        if (( $#m > 0 )); then
          root_idx=$i
          break
        fi
      done
      (( root_idx == 0 )) && root_idx=$target_idx
      (( root_idx > check_idx )) && check_idx=$root_idx

      local -i js_subtree_ok=0
      # Active if any directory strictly below the Node root (1 <= i < root_idx) has Node/JS/TS files
      for (( i = 1; i < root_idx; ++i )); do
        m=( "${dirs[i]}"/(${~node_pat})(#qN-.Y1) )
        if (( $#m > 0 )); then
          js_subtree_ok=1
          break
        fi
      done
      # Or if an immediate child directory of $PWD contains Node/JS/TS files (e.g. support-site/assets/site.js)
      if (( ! js_subtree_ok )); then
        m=( "${dirs[1]}"/*/(${~node_pat})(#qN-.Y1) )
        (( $#m > 0 )) && js_subtree_ok=1
      fi
      # Or if the top-level subtree under the Node project root is a standard JS/TS directory
      if (( ! js_subtree_ok )); then
        local root_dir=${dirs[root_idx]}
        local rel=${cur_dir#"${root_dir}/"}
        local top_seg=${rel%%/*}
        [[ $top_seg == (src|lib|dist|build|out|app|apps|packages|components|pages|routes|public|client|server|web|site|*-site|frontend|backend|scripts|assets|styles|static|config|configs|utils|helpers|hooks|types|test|tests|__tests__|spec|e2e|cypress|playwright|node_modules) ]] && js_subtree_ok=1
      fi
      (( js_subtree_ok )) || return 1
    fi

    local -a other_pats=()
    [[ $tool != terraform ]] && other_pats+=("$tf_pat")
    [[ $tool != go ]]        && other_pats+=("$go_pat")
    [[ $tool != rust ]]      && other_pats+=("$rust_pat")
    [[ $tool != java ]]      && other_pats+=("$java_pat")
    [[ $tool != python ]]    && other_pats+=("$py_pat")
    [[ $tool != (node|package) ]] && other_pats+=("$node_root_pat")
    local combined_other_pat=${(j:|:)other_pats}

    for (( i = 1; i < check_idx; ++i )); do
      m=( "${dirs[i]}"/(${~combined_other_pat})(#qN-.Y1) )
      (( $#m > 0 )) && return 1
      if (( i == 1 )); then
        if [[ $tool != (node|package) ]] || () { local -a nm=( "${dirs[1]}"/(${~node_pat})(#qN-.Y1) ); (( $#nm == 0 )); }; then
          m=( "${dirs[1]}"/*/(${~combined_other_pat})(#qN-.Y1) )
          (( $#m > 0 )) && return 1
        fi
      fi
    done

    return 0
  }

  function _p9k_solarized_install_segments() {
    function prompt_vcs() {
      _p9k_solarized_prompt_vcs "$@"
    }
    typeset -ga preexec_functions
    if (( ! ${preexec_functions[(I)_p9k_solarized_vcs_preexec]} )); then
      preexec_functions+=(_p9k_solarized_vcs_preexec)
    fi

    if (( $+functions[_p9k_orig_prompt_terraform_version] )); then
      functions -c _p9k_orig_prompt_terraform_version prompt_terraform_version 2>/dev/null
      unfunction _p9k_orig_prompt_terraform_version 2>/dev/null
    fi

    if (( $+functions[prompt_node_version] )) && [[ ${functions[prompt_node_version]} != *_p9k_solarized_project_active* ]]; then
      functions -c prompt_node_version _p9k_orig_prompt_node_version 2>/dev/null
    fi
    if (( $+functions[_p9k_orig_prompt_node_version] )); then
      function prompt_node_version() {
        if [[ ${POWERLEVEL9K_NODE_VERSION_PROJECT_ONLY:-true} == true ]]; then
          _p9k_solarized_project_active node || return 0
        fi
        local -i _POWERLEVEL9K_NODE_VERSION_PROJECT_ONLY=0
        setopt local_options no_function_argzero
        _p9k_orig_prompt_node_version "$@"
      }
    fi

    if (( $+functions[prompt_package] )) && [[ ${functions[prompt_package]} != *_p9k_solarized_project_active* ]]; then
      functions -c prompt_package _p9k_orig_prompt_package 2>/dev/null
    fi
    if (( $+functions[_p9k_orig_prompt_package] )); then
      function prompt_package() {
        if ! _p9k_solarized_project_active package; then
          unset P9K_PACKAGE_NAME P9K_PACKAGE_VERSION
          return 0
        fi
        setopt local_options no_function_argzero
        _p9k_orig_prompt_package "$@"
      }
    fi

    if (( $+functions[prompt_go_version] )) && [[ ${functions[prompt_go_version]} != *_p9k_solarized_project_active* ]]; then
      functions -c prompt_go_version _p9k_orig_prompt_go_version 2>/dev/null
    fi
    if (( $+functions[_p9k_orig_prompt_go_version] )); then
      function prompt_go_version() {
        if [[ ${POWERLEVEL9K_GO_VERSION_PROJECT_ONLY:-true} == true ]]; then
          _p9k_solarized_project_active go || return 0
        fi
        local -i _POWERLEVEL9K_GO_VERSION_PROJECT_ONLY=0
        setopt local_options no_function_argzero
        _p9k_orig_prompt_go_version "$@"
      }
    fi

    if (( $+functions[prompt_java_version] )) && [[ ${functions[prompt_java_version]} != *_p9k_solarized_project_active* ]]; then
      functions -c prompt_java_version _p9k_orig_prompt_java_version 2>/dev/null
    fi
    if (( $+functions[_p9k_orig_prompt_java_version] )); then
      function prompt_java_version() {
        if [[ ${POWERLEVEL9K_JAVA_VERSION_PROJECT_ONLY:-true} == true ]]; then
          _p9k_solarized_project_active java || return 0
        fi
        local -i _POWERLEVEL9K_JAVA_VERSION_PROJECT_ONLY=0
        setopt local_options no_function_argzero
        _p9k_orig_prompt_java_version "$@"
      }
    fi

    if (( $+functions[_p9k_rust_version_prefetch] )) && [[ ${functions[_p9k_rust_version_prefetch]} != *_p9k_solarized_project_active* ]]; then
      functions -c _p9k_rust_version_prefetch _p9k_orig_rust_version_prefetch 2>/dev/null
    fi
    if (( $+functions[_p9k_orig_rust_version_prefetch] )); then
      function _p9k_rust_version_prefetch() {
        if [[ ${POWERLEVEL9K_RUST_VERSION_PROJECT_ONLY:-true} == true ]]; then
          if ! _p9k_solarized_project_active rust; then
            unset P9K_RUST_VERSION
            return 0
          fi
        fi
        local -i _POWERLEVEL9K_RUST_VERSION_PROJECT_ONLY=0
        setopt local_options no_function_argzero
        _p9k_orig_rust_version_prefetch "$@"
      }
    fi

    if (( $+functions[prompt_rust_version] )) && [[ ${functions[prompt_rust_version]} != *_p9k_solarized_project_active* ]]; then
      functions -c prompt_rust_version _p9k_orig_prompt_rust_version 2>/dev/null
    fi
    if (( $+functions[_p9k_orig_prompt_rust_version] )); then
      function prompt_rust_version() {
        if [[ ${POWERLEVEL9K_RUST_VERSION_PROJECT_ONLY:-true} == true ]]; then
          if ! _p9k_solarized_project_active rust; then
            unset P9K_RUST_VERSION
            return 0
          fi
        fi
        setopt local_options no_function_argzero
        _p9k_orig_prompt_rust_version "$@"
        [[ -n ${_p9k__prompt_side:-} ]] && (( ${_p9k__segment_index:-0} )) && \
          typeset -g "_p9k__segment_val_${_p9k__prompt_side}[_p9k__segment_index]="
      }
    fi
  }

  _p9k_solarized_install_segments

  function p10k-on-init() {
    if (( $+functions[_p9k_solarized_install_segments] )); then
      _p9k_solarized_install_segments
    fi
  }
