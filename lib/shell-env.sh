#!/bin/bash
# Shared shell RC block management, Oh-My-Zsh git sync, and Zsh CLI completion helpers.

# Clone a shallow Git plugin/theme repository or fast-forward an existing clone.
sync_git_plugin_repo() {
    local repo_url="$1"
    local dest_dir="$2"
    if [ -d "$dest_dir/.git" ]; then
        git -C "$dest_dir" pull --ff-only
    else
        if [ -d "$dest_dir" ]; then
            rm -rf "$dest_dir"
        fi
        git clone --depth=1 "$repo_url" "$dest_dir"
    fi
}

# Idempotently append a # home-settings source hook to a shell RC file (~/.zshrc or ~/.bashrc).
ensure_shell_rc_hook() {
    local rc_file="$1"
    local addendum_name="$2"
    local hook_line="[ -f ~/${addendum_name} ] && source ~/${addendum_name}"
    if [ ! -f "$rc_file" ]; then
        touch "$rc_file"
    fi
    grep -qxF "$hook_line" "$rc_file" || \
        printf '\n# home-settings\n%s\n' "$hook_line" >> "$rc_file"
}

# Remove # home-settings source hooks from a shell RC file while preserving file permissions.
remove_shell_rc_hook() {
    local rc_file="$1"
    local addendum_name="$2"
    if [ ! -f "$rc_file" ] || [ -L "$rc_file" ] || ! grep -Fq "$addendum_name" "$rc_file"; then
        return 0
    fi
    if [ "${DRY_RUN:-false}" = true ]; then
        echo "  [DryRun] Remove home-settings source block from $rc_file"
        return 0
    fi

    local tmp_rc
    tmp_rc="$(mktemp "${rc_file}.tmp.XXXXXX")"
    cp -p "$rc_file" "$tmp_rc" 2>/dev/null || true
    awk -v addendum="$addendum_name" '
        function is_comment(s) {
            return (s ~ /^#[[:space:]]*home-settings([[:space:]:].*)?$/)
        }
        function is_hook(s) {
            return (index(s, addendum) > 0 &&
                    s ~ /^\[[[:space:]]+-f[[:space:]]+"?(~|\$HOME)"?\/\.(zsh|bash)rc-addendum"?[[:space:]]+\][[:space:]]+&&[[:space:]]+(source|\.)[[:space:]]+"?(~|\$HOME)"?\/\.(zsh|bash)rc-addendum"?[[:space:]]*$/)
        }
        { lines[++n] = $0 }
        END {
            for (i = 1; i <= n; i++) {
                if (is_comment(lines[i]) && i < n && is_hook(lines[i + 1])) {
                    if (out_n > 0 && out[out_n] == "" && (i + 1 == n || out_n == 1 || lines[i + 2] == "")) {
                        out_n--
                    }
                    i++
                    continue
                }
                if (is_hook(lines[i])) {
                    continue
                }
                out[++out_n] = lines[i]
            }
            for (j = 1; j <= out_n; j++) {
                print out[j]
            }
        }
    ' "$rc_file" > "$tmp_rc"
    mv -f "$tmp_rc" "$rc_file"
}

# Write a generated Zsh completion file atomically after validating non-empty '#' header output.
write_zsh_completion_atomic() {
    local target="$1"
    shift
    local tmp_comp="${target}.tmp.$$.${BASHPID:-$RANDOM}"
    local first_line=""
    if "$@" > "$tmp_comp" && [ -s "$tmp_comp" ] && IFS= read -r first_line < "$tmp_comp" && [[ "$first_line" == \#* ]]; then
        mv -f "$tmp_comp" "$target"
        return 0
    fi
    rm -f "$tmp_comp"
    return 1
}

# Generate or refresh all supported Zsh CLI completions in completions_dir.
# When strict_mode=true, generator failures propagate non-zero; when false, failures are tolerated
# with MISE_NOT_FOUND_AUTO_INSTALL=false so existing completion files stay intact.
sync_zsh_cli_completions() {
    local completions_dir="$1"
    local strict_mode="${2:-true}"
    local mise_config_path="${3:-}"

    mkdir -p "$completions_dir"

    _run_single_zsh_completion() {
        if [ "$strict_mode" = true ]; then
            write_zsh_completion_atomic "$@"
        elif [ -n "$mise_config_path" ]; then
            MISE_TRUSTED_CONFIG_PATHS="${mise_config_path}${MISE_TRUSTED_CONFIG_PATHS:+:$MISE_TRUSTED_CONFIG_PATHS}" \
            MISE_NOT_FOUND_AUTO_INSTALL=false \
                write_zsh_completion_atomic "$@" 2>/dev/null || true
        else
            MISE_NOT_FOUND_AUTO_INSTALL=false \
                write_zsh_completion_atomic "$@" 2>/dev/null || true
        fi
    }

    if command -v gh >/dev/null 2>&1; then _run_single_zsh_completion "$completions_dir/_gh" gh completion -s zsh; fi
    if command -v kubectl >/dev/null 2>&1; then _run_single_zsh_completion "$completions_dir/_kubectl" kubectl completion zsh; fi
    if command -v helm >/dev/null 2>&1; then _run_single_zsh_completion "$completions_dir/_helm" helm completion zsh; fi
    if command -v elan >/dev/null 2>&1; then _run_single_zsh_completion "$completions_dir/_elan" elan completions zsh; fi
    if command -v mise >/dev/null 2>&1; then _run_single_zsh_completion "$completions_dir/_mise" mise completion zsh; fi
    if command -v delta >/dev/null 2>&1; then BAT_THEME="" _run_single_zsh_completion "$completions_dir/_delta" delta --generate-completion zsh; fi
    if command -v bat >/dev/null 2>&1; then _run_single_zsh_completion "$completions_dir/_bat" bat --completion zsh; fi
    if command -v yq >/dev/null 2>&1; then _run_single_zsh_completion "$completions_dir/_yq" yq shell-completion zsh; fi
    if command -v glow >/dev/null 2>&1; then _run_single_zsh_completion "$completions_dir/_glow" glow completion zsh; fi

    if command -v rustup >/dev/null 2>&1; then
        _run_single_zsh_completion "$completions_dir/_rustup" rustup completions zsh
        if command -v cargo >/dev/null 2>&1; then
            _run_single_zsh_completion "$completions_dir/_cargo" rustup completions zsh cargo
        fi
    elif command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1; then
        local rustc_sysroot=""
        if [ -n "$mise_config_path" ]; then
            rustc_sysroot="$(MISE_TRUSTED_CONFIG_PATHS="${mise_config_path}${MISE_TRUSTED_CONFIG_PATHS:+:$MISE_TRUSTED_CONFIG_PATHS}" MISE_NOT_FOUND_AUTO_INSTALL=false rustc --print sysroot 2>/dev/null || true)"
        else
            rustc_sysroot="$(MISE_NOT_FOUND_AUTO_INSTALL=false rustc --print sysroot 2>/dev/null || true)"
        fi
        if [ -n "$rustc_sysroot" ] && [ -s "$rustc_sysroot/share/zsh/site-functions/_cargo" ]; then
            local tmp_cargo="${completions_dir}/_cargo.tmp.$$.${BASHPID:-$RANDOM}"
            cp -f "$rustc_sysroot/share/zsh/site-functions/_cargo" "$tmp_cargo" && mv -f "$tmp_cargo" "$completions_dir/_cargo"
        fi
    fi

    if command -v tree-sitter >/dev/null 2>&1; then _run_single_zsh_completion "$completions_dir/_tree-sitter" tree-sitter complete --shell zsh; fi
    unset -f _run_single_zsh_completion
}

# Update Oh-My-Zsh core framework and fast-forward any Git-backed custom plugins/themes.
update_oh_my_zsh_stack() {
    local omz_dir="${1:-${ZSH:-$HOME/.oh-my-zsh}}"
    local omz_custom_dir="${2:-${ZSH_CUSTOM:-$omz_dir/custom}}"

    if [ ! -d "$omz_dir" ] && [ ! -d "$omz_custom_dir" ] && [ "${DRY_RUN:-false}" != true ]; then
        return 0
    fi

    if [ -d "$omz_dir" ] || [ "${DRY_RUN:-false}" = true ]; then
        log_step "Updating Oh-My-Zsh framework..."
        if command -v omz >/dev/null 2>&1; then
            run_cmd omz update --unattended
        elif [ -f "$omz_dir/tools/upgrade.sh" ] || [ "${DRY_RUN:-false}" = true ]; then
            run_cmd env ZSH="$omz_dir" sh "$omz_dir/tools/upgrade.sh" --unattended
        fi
    fi

    if [ -d "$omz_custom_dir" ]; then
        local custom_repo
        for custom_repo in "$omz_custom_dir"/plugins/* "$omz_custom_dir"/themes/*; do
            [ -e "$custom_repo/.git" ] || continue
            log_step "Updating Oh-My-Zsh custom repo $(basename "$custom_repo")..."
            if ! run_cmd git -C "$custom_repo" pull --ff-only; then
                log_warn "Skipped fast-forward update for $(basename "$custom_repo") (local changes, detached HEAD, or diverged branch)."
            fi
        done
    fi
    log_success "Oh-My-Zsh updated."
}
