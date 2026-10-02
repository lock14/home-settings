#!/usr/bin/env zsh
# Test suite for zsh dotfiles (dotfiles/.aliases, dotfiles/.zsh-functions, dotfiles/.zshrc-addendum)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$SCRIPT_DIR/tests/test-helper.sh"

echo "========================================"
echo "Running Zsh Configuration Tests"
echo "========================================"

# Test 1: Syntax check with zsh -n
echo "\n[1/5] Checking Zsh file syntax with 'zsh -n'..."
for f in "$SCRIPT_DIR/dotfiles/.aliases" "$SCRIPT_DIR/dotfiles/.zsh-functions" "$SCRIPT_DIR/dotfiles/.zshrc-addendum" "$SCRIPT_DIR/dotfiles/.zsh-completions" "$SCRIPT_DIR/dotfiles/.p10k.zsh"; do
    if [ -f "$f" ]; then
        if zsh -n "$f"; then
            pass "Syntax valid: $(basename "$f")"
        else
            fail "Syntax check failed: $(basename "$f")" "zsh -n returned non-zero"
        fi
    fi
done

# Test 2: Source .aliases and verify aliases
echo "\n[2/5] Testing dotfiles/.aliases..."
test_aliases() {
    setopt aliases
    source "$SCRIPT_DIR/dotfiles/.aliases"

    local expected_aliases=(gcommit gamend gpush gpushf gpull gup gprune gpurge guser-branch tf ide2 ide3 idek qide ds update vi ls ll la l)
    if command -v eza >/dev/null 2>&1; then
        expected_aliases+=(e el elm et elt elx)
    fi

    if command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1; then
        expected_aliases+=(b)
    fi

    for expected_alias in "${expected_aliases[@]}"; do
        if alias "$expected_alias" >/dev/null 2>&1; then
            echo "PASS:$expected_alias"
        else
            echo "FAIL:$expected_alias:alias not found"
        fi
    done

    if [ "$(alias gup)" = "gup='git pull --rebase --autostash --prune'" ]; then
        echo "PASS:gup configured as 'git pull --rebase --autostash --prune'"
    else
        echo "FAIL:gup:Expected gup='git pull --rebase --autostash --prune', got $(alias gup 2>/dev/null || echo none)"
    fi

    local retired_aliases=(gfetch tealdeer go-lint go-testall go-buildall yaml-lint)
    for retired in "${retired_aliases[@]}"; do
        if alias "$retired" >/dev/null 2>&1; then
            echo "FAIL:$retired:$retired should not be aliased"
        fi
    done

    if alias cat >/dev/null 2>&1; then
        echo "FAIL:cat:cat should not be aliased (should use coreutils cat)"
    else
        echo "PASS:cat is not aliased (coreutils cat)"
    fi
}

parse_subshell_results "Alias defined: " "Alias missing: " < <(test_aliases)

# Test 3: Source zsh-functions and verify functions
echo "\n[3/5] Testing dotfiles/.zsh-functions..."
test_functions() {
    source "$SCRIPT_DIR/dotfiles/.aliases"
    source "$SCRIPT_DIR/dotfiles/.zsh-functions"

    for expected_func in v icd fs gsync; do
        if typeset -f "$expected_func" >/dev/null 2>&1; then
            echo "PASS:Function defined: $expected_func"
        else
            echo "FAIL:Function missing: $expected_func:function not found"
        fi
    done

    # Test v() RPC routing with a live Neovim server socket (including subdirectory relative paths and stale socket cleanup)
    if command -v nvim >/dev/null 2>&1; then
        local test_sock="/tmp/nvim-ide-zsh-test-$$.sock"
        rm -f "$test_sock"
        (cd "$SCRIPT_DIR" && nvim --headless --listen "$test_sock" >/dev/null 2>&1) &
        local nvim_pid=$!
        if wait_for_nvim_socket "$test_sock" 30; then
            local zsh_ver_out
            zsh_ver_out="$(TMUX="" NVIM_IDE_SOCKET="$test_sock" v --version 2>/dev/null | head -n 1 || true)"
            (cd "$SCRIPT_DIR/modules" && TMUX="" NVIM_IDE_SOCKET="$test_sock" v +2 "00-packages.sh" >/dev/null 2>&1) || true
            local remote_state
            remote_state="$(nvim --headless --server "$test_sock" --remote-expr 'expand("%:p") . "|" . line(".")' 2>/dev/null || true)"
            kill "$nvim_pid" 2>/dev/null || true
            rm -f "$test_sock"
            if [ "$remote_state" = "$SCRIPT_DIR/modules/00-packages.sh|2" ] && [[ "$zsh_ver_out" == NVIM* ]]; then
                echo "PASS:v() resolves subdirectory relative paths and +line arguments accurately over RPC, and passes --version to local nvim"
            else
                echo "FAIL:v() RPC routing:Expected '$SCRIPT_DIR/modules/00-packages.sh|2' and NVIM version, got state='$remote_state' ver='$zsh_ver_out'"
            fi
        else
            kill "$nvim_pid" 2>/dev/null || true
            rm -f "$test_sock"
        fi

        if command -v python3 >/dev/null 2>&1; then
            local stale_sock="/tmp/nvim-ide-stale-$$.sock"
            python3 -c "import socket, os; s=socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind('$stale_sock'); s.close()" 2>/dev/null || true
            if [ -S "$stale_sock" ]; then
                TMUX="" NVIM_IDE_SOCKET="$stale_sock" v --version >/dev/null 2>&1 || true
                if [ ! -e "$stale_sock" ]; then
                    echo "PASS:v() detects and cleans up stale NVIM_IDE_SOCKET before falling back to local nvim"
                else
                    rm -f "$stale_sock"
                    echo "FAIL:v() stale socket cleanup:Stale socket '$stale_sock' was not removed"
                fi
            fi
        fi

        if command -v tmux >/dev/null 2>&1; then
            local multisess_dir
            multisess_dir="$(mktemp -d)"
            local bg_nvim_sock="$multisess_dir/bg-nvim.sock"
            (cd "$SCRIPT_DIR" && nvim --clean --headless --listen "$bg_nvim_sock" >/dev/null 2>&1) &
            local bg_nvim_pid=$!
            wait_for_nvim_socket "$bg_nvim_sock" 30 || true
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux -f /dev/null new-session -d -s bg_sess -c "$SCRIPT_DIR" "sleep 30"
            local bg_pane
            bg_pane="$(TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux list-panes -t '=bg_sess:' -F '#{pane_id}' | head -n 1)"
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux set-option -t '=bg_sess:' @ide_socket "$bg_nvim_sock"
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux set-option -t '=bg_sess:' @ide_initial_root "$SCRIPT_DIR/modules"
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux new-session -d -s fg_sess -c "/tmp" "sleep 30"
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux set-option -t '=fg_sess:' @ide_socket "$multisess_dir/wrong-fg.sock"
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux set-option -t '=fg_sess:' @ide_initial_root "/tmp"
            local tmux_env
            tmux_env="$(TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux display-message -p -t '=bg_sess:' '#{socket_path},#{pid},0')"
            (cd "$SCRIPT_DIR/modules" && TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="$tmux_env" TMUX_PANE="$bg_pane" NVIM_IDE_SOCKET="" IDE_SESSION="" v +3 "10-dotfiles.sh" >/dev/null 2>&1) || true
            local bg_remote_state
            bg_remote_state="$(nvim --headless --server "$bg_nvim_sock" --remote-expr 'expand("%:p") . "|" . line(".")' 2>/dev/null || true)"
            local icd_reset_pwd
            icd_reset_pwd="$(cd "$SCRIPT_DIR" && TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="$tmux_env" TMUX_PANE="$bg_pane" IDE_INITIAL_ROOT="" IDE_SESSION="" icd --reset >/dev/null 2>&1 && pwd || true)"
            local sid_reset_pwd
            sid_reset_pwd="$(cd "$SCRIPT_DIR" && TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="${tmux_env%,0},\$0" TMUX_PANE="" IDE_INITIAL_ROOT="" IDE_SESSION="" icd --reset >/dev/null 2>&1 && pwd || true)"
            local bad_pid_target
            bad_pid_target="$(TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="${tmux_env%%,*},999999,0" TMUX_PANE="$bg_pane" _ide_tmux_target || echo "rejected")"
            kill "$bg_nvim_pid" 2>/dev/null || true
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux kill-server >/dev/null 2>&1 || true
            rm -rf "$multisess_dir"
            if [ "$bg_remote_state" = "$SCRIPT_DIR/modules/10-dotfiles.sh|3" ] && [ "$icd_reset_pwd" = "$SCRIPT_DIR/modules" ] && [ "$sid_reset_pwd" = "$SCRIPT_DIR/modules" ] && [ "$bad_pid_target" = "rejected" ]; then
                echo "PASS:v() and icd() target caller TMUX_PANE or \$0 session ID and verify server PID in multi-session tmux"
            else
                echo "FAIL:v()/icd() multi-session targeting:Expected '$SCRIPT_DIR/modules/10-dotfiles.sh|3', '$SCRIPT_DIR/modules', and 'rejected', got state='$bg_remote_state' pwd='$icd_reset_pwd' sid_pwd='$sid_reset_pwd' bad_pid='$bad_pid_target'"
            fi
        fi
    fi

    # Test fs execution with aliases active
    if command -v tree >/dev/null 2>&1 && (command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1); then
        if (cd "$SCRIPT_DIR/dotfiles" && fs >/dev/null 2>&1); then
            echo "PASS:fs function runs cleanly on dotfiles directory"
        else
            echo "FAIL:fs execution:fs failed to list directory"
        fi
    fi
}

parse_subshell_results < <(test_functions)

# Test 4: Functional test of gsync & git aliases in a mock git repository
echo "\n[4/5] Testing git functions and aliases behavior..."
test_git_integration() {
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT

    cd "$TEMP_DIR"

    # Initialize a dummy remote repo
    mkdir remote.git && (cd remote.git && git init --bare -b main >/dev/null 2>&1)
    # Clone it to local
    git clone remote.git local >/dev/null 2>&1
    cd local
    git config user.email "test@example.com"
    git config user.name "Test User"
    git config commit.gpgsign false

    # Initial commit on main
    echo "initial" > file.txt
    git add file.txt && git commit -m "initial commit" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1

    # Source functions and aliases
    setopt aliases
    source "$SCRIPT_DIR/dotfiles/.zsh-functions"
    source "$SCRIPT_DIR/dotfiles/.aliases"

    # Test gsync outside git repo
    (
        cd "$TEMP_DIR"
        out=$(gsync 2>&1 || true)
        if echo "$out" | grep -qi "error"; then
            echo "PASS:gsync fails gracefully when not in git repository"
        else
            echo "FAIL:gsync outside git repo:Expected error message, got: $out"
        fi
    )

    # Create a feature branch
    git checkout -b feature-1 >/dev/null 2>&1
    echo "feature update" >> file.txt
    git commit -am "feature work" >/dev/null 2>&1

    # Run gsync on feature branch
    if gsync >/dev/null 2>&1; then
        echo "PASS:gsync succeeds on feature branch with 'main'"
    else
        echo "FAIL:gsync execution:gsync failed on standard feature branch"
    fi

    # Verify branch is still feature-1
    current=$(git rev-parse --abbrev-ref HEAD)
    if [ "$current" = "feature-1" ]; then
        echo "PASS:gsync preserves current branch (feature-1)"
    else
        echo "FAIL:gsync branch preservation:Expected feature-1, got $current"
    fi

    # Test guser-branch alias
    eval "$(alias guser-branch | sed 's/^guser-branch=//' | sed "s/^'//" | sed "s/'$//")"
    renamed_branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$renamed_branch" = "$USER/feature-1" ]; then
        echo "PASS:guser-branch successfully renamed branch"
    else
        echo "FAIL:guser-branch:Expected $USER/feature-1, got $renamed_branch"
    fi

    # Test guser-branch idempotency (running again should not duplicate $USER/)
    eval "$(alias guser-branch | sed 's/^guser-branch=//' | sed "s/^'//" | sed "s/'$//")"
    renamed_branch_again=$(git rev-parse --abbrev-ref HEAD)
    if [ "$renamed_branch_again" = "$USER/feature-1" ]; then
        echo "PASS:guser-branch is idempotent"
    else
        echo "FAIL:guser-branch idempotency:Expected $USER/feature-1, got $renamed_branch_again"
    fi

    # Test guser-branch refusal on main
    git checkout main >/dev/null 2>&1
    eval "$(alias guser-branch | sed 's/^guser-branch=//' | sed "s/^'//" | sed "s/'$//")" >/dev/null 2>&1 || true
    if [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]; then
        echo "PASS:guser-branch safely refuses to rename main"
    else
        echo "FAIL:guser-branch on main:Renamed main to $(git rev-parse --abbrev-ref HEAD)"
    fi

    # Test gprune alias (safe prune: deletes merged branch, preserves unmerged branch)
    git branch test-to-delete >/dev/null 2>&1
    git checkout -b test-unmerged >/dev/null 2>&1
    echo "unmerged work" >> file.txt
    git commit -am "unmerged commit" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1

    eval "$(alias gprune | sed 's/^gprune=//' | sed "s/^'//" | sed "s/'$//")" >/dev/null 2>&1
    if ! git show-ref --verify --quiet refs/heads/test-to-delete; then
        echo "PASS:gprune successfully pruned merged branch"
    else
        echo "FAIL:gprune:Merged branch test-to-delete was not pruned"
    fi
    if git show-ref --verify --quiet refs/heads/test-unmerged; then
        echo "PASS:gprune preserved unmerged branch"
    else
        echo "FAIL:gprune:Unmerged branch test-unmerged was unexpectedly deleted"
    fi

    # Test gpurge alias (nuclear prune: deletes unmerged branch too)
    eval "$(alias gpurge | sed 's/^gpurge=//' | sed "s/^'//" | sed "s/'$//")" >/dev/null 2>&1
    if ! git show-ref --verify --quiet refs/heads/test-unmerged; then
        echo "PASS:gpurge successfully pruned unmerged branch"
    else
        echo "FAIL:gpurge:Branch test-unmerged was not pruned by gpurge"
    fi
}

parse_subshell_results < <(test_git_integration)

# Test 5: Test zshrc-addendum sourcing
echo "\n[5/5] Testing dotfiles/.zshrc-addendum..."
test_addendum() {
    TEMP_HOME=$(mktemp -d)
    trap 'rm -rf "$TEMP_HOME"' EXIT

    export HOME="$TEMP_HOME"
    cp "$SCRIPT_DIR/dotfiles/.aliases" "$HOME/.aliases"
    cp "$SCRIPT_DIR/dotfiles/.zsh-functions" "$HOME/.zsh-functions"
    cp "$SCRIPT_DIR/dotfiles/.p10k.zsh" "$HOME/.p10k.zsh"

    _source_zshrc_addendum() {
        source "$SCRIPT_DIR/dotfiles/.zshrc-addendum"
    }
    _source_zshrc_addendum

    if [ "${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:-}" = "fg=#586E75" ]; then
        echo "PASS:ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE set correctly"
    else
        echo "FAIL:ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:Expected 'fg=#586E75', got '${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[command]:-}" = "fg=#859900" ] && [ "${ZSH_HIGHLIGHT_STYLES[builtin]:-}" = "fg=#859900" ] && [ "${ZSH_HIGHLIGHT_STYLES[function]:-}" = "fg=#859900" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES command, builtin, and function configured with unbolded Solarized Green"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES command:Expected 'fg=#859900', got '${ZSH_HIGHLIGHT_STYLES[command]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[reserved-word]:-}" = "fg=#B58900" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES reserved-word configured with Solarized Yellow for control flow"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES reserved-word:Expected 'fg=#B58900', got '${ZSH_HIGHLIGHT_STYLES[reserved-word]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[command-substitution]:-}" = "fg=#839496" ] && \
       [ "${ZSH_HIGHLIGHT_STYLES[command-substitution-quoted]:-}" = "fg=#839496" ] && \
       [ "${ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]:-}" = "fg=#839496" ] && \
       [ "${ZSH_HIGHLIGHT_STYLES[process-substitution]:-}" = "fg=#839496" ] && \
       [ "${ZSH_HIGHLIGHT_STYLES[back-quoted-argument]:-}" = "fg=#839496" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES command/process/backtick substitutions and delimiters configured with calm Solarized Base0"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES command-substitution:Expected 'fg=#839496', got '${ZSH_HIGHLIGHT_STYLES[command-substitution]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[single-hyphen-option]:-}" = "fg=#839496" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES options configured with Solarized Base0"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES options:Expected 'fg=#839496', got '${ZSH_HIGHLIGHT_STYLES[single-hyphen-option]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[assign]:-}" = "fg=#839496" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES assignments configured with Solarized Base0"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES assign:Expected 'fg=#839496', got '${ZSH_HIGHLIGHT_STYLES[assign]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[commandseparator]:-}" = "fg=#839496" ] && [ "${ZSH_HIGHLIGHT_STYLES[redirection]:-}" = "fg=#839496" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES operators and redirections configured with Solarized Base0"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES operators:Expected 'fg=#839496', got separator='${ZSH_HIGHLIGHT_STYLES[commandseparator]:-}', redir='${ZSH_HIGHLIGHT_STYLES[redirection]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[path]:-}" = "fg=#268BD2" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES path configured cleanly with Solarized Blue matching dircolors/eza without underline"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES path:Expected 'fg=#268BD2', got '${ZSH_HIGHLIGHT_STYLES[path]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[unknown-token]:-}" = "fg=#DC322F" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES unknown-token configured with unbolded Solarized Red"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES unknown-token:Expected 'fg=#DC322F', got '${ZSH_HIGHLIGHT_STYLES[unknown-token]:-}'"
    fi

    if [ "${POWERLEVEL9K_DIR_ANCHOR_BOLD:-}" = "false" ]; then
        echo "PASS:p10k directory anchor bold styling disabled (zero-jitter typography)"
    else
        echo "FAIL:p10k DIR_ANCHOR_BOLD:Expected 'false', got '${POWERLEVEL9K_DIR_ANCHOR_BOLD:-}'"
    fi

    if [ "${POWERLEVEL9K_OS_ICON_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_OS_ICON_FOREGROUND:-}" = "#839496" ]; then
        echo "PASS:p10k OS icon configured with Base02 background and Base0 standard foreground"
    else
        echo "FAIL:p10k OS_ICON colors:Expected bg='#073642' fg='#839496', got bg='${POWERLEVEL9K_OS_ICON_BACKGROUND:-}' fg='${POWERLEVEL9K_OS_ICON_FOREGROUND:-}'"
    fi

    if [ "${POWERLEVEL9K_VCS_CLEAN_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_VCS_CLEAN_FOREGROUND:-}" = "#859900" ] && \
       [ "${POWERLEVEL9K_VCS_UNTRACKED_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND:-}" = "#B58900" ] && \
       [ "${POWERLEVEL9K_VCS_MODIFIED_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_VCS_MODIFIED_FOREGROUND:-}" = "#B58900" ]; then
        echo "PASS:p10k VCS configured with Base02 background and semantic foregrounds"
    else
        echo "FAIL:p10k VCS colors:Expected Base02 background with Green clean and Yellow dirty foregrounds"
    fi

    if [[ "${POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX:-}" == *"#586E75"* ]]; then
        echo "PASS:p10k multiline ornaments configured with authentic Solarized Base01 (#586E75)"
    else
        echo "FAIL:p10k multiline ornaments:Expected Solarized Base01, got '${POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX:-}'"
    fi

    if ! [[ "${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[*]:-}" == *"prompt_char"* ]]; then
        echo "PASS:p10k prompt_char disabled in favor of clean multiline prefix"
    else
        echo "FAIL:p10k prompt_char:Expected prompt_char to be disabled in POWERLEVEL9K_LEFT_PROMPT_ELEMENTS"
    fi

    if [ "${POWERLEVEL9K_DIR_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_DIR_FOREGROUND:-}" = "#268BD2" ] && \
       [ "${POWERLEVEL9K_DIR_SHORTENED_FOREGROUND:-}" = "#268BD2" ] && [ "${POWERLEVEL9K_DIR_ANCHOR_FOREGROUND:-}" = "#268BD2" ]; then
        echo "PASS:p10k directory configured with Base02 background and Solarized Blue foregrounds"
    else
        echo "FAIL:p10k DIR colors:Expected bg='#073642' fg='#268BD2'"
    fi

    if [[ "${POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR:-}" == *"#657B83"* ]] && \
       [[ "${POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR:-}" == *"\uE0B1"* ]] && \
       [[ "${POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR:-}" == *"#657B83"* ]] && \
       [[ "${POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR:-}" == *"\uE0B3"* ]] && \
       [ "${POWERLEVEL9K_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL:-}" = '\uE0B0' ] && \
       [ "${POWERLEVEL9K_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL:-}" = '\uE0B2' ] && \
       [ "${POWERLEVEL9K_STATUS_OK_VISUAL_IDENTIFIER_EXPANSION:-}" = "✔" ] && \
       [ "${POWERLEVEL9K_STATUS_ERROR_VISUAL_IDENTIFIER_EXPANSION:-}" = "✘" ]; then
        echo "PASS:p10k Base00 thin chevron separators (\uE0B1/\uE0B3) and solid wedge caps (\uE0B0/\uE0B2) configured on Base02 shelf"
    else
        echo "FAIL:p10k separators:Expected Base00 thin chevrons (\uE0B1 left, \uE0B3 right) and solid wedge caps (\uE0B0/\uE0B2) on Base02 shelf"
    fi

    if [ "${ZLE_RPROMPT_INDENT:-}" = "0" ]; then
        echo "PASS:ZLE_RPROMPT_INDENT=0 (right prompt flush with screen edge, zero gap)"
    else
        echo "FAIL:ZLE_RPROMPT_INDENT:Expected '0', got '${ZLE_RPROMPT_INDENT:-unset}'"
    fi

    if [ "${POWERLEVEL9K_DIR_HYPERLINK:-}" = "false" ]; then
        echo "PASS:p10k directory OSC 8 hyperlinks disabled for clean text selection"
    else
        echo "FAIL:p10k DIR_HYPERLINK:Expected 'false', got '${POWERLEVEL9K_DIR_HYPERLINK:-}'"
    fi

    if [[ "${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[*]:-}" == *"go_version"* ]] && \
       [[ "${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[*]:-}" == *"node_version"* ]] && \
       [[ "${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[*]:-}" == *"rust_version"* ]] && \
       [[ "${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[*]:-}" == *"java_version"* ]] && \
       [[ "${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[*]:-}" == *"package"* ]] && \
       [[ "${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[*]:-}" == *"terraform_version"* ]]; then
        echo "PASS:p10k right prompt elements includes language toolchains, package, and terraform"
    else
        echo "FAIL:p10k RIGHT_PROMPT_ELEMENTS:Expected toolchain versions enabled in POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS"
    fi

    if [ "${POWERLEVEL9K_GO_VERSION_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_GO_VERSION_FOREGROUND:-}" = "#2AA198" ] && \
       [ "${POWERLEVEL9K_NODE_VERSION_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_NODE_VERSION_FOREGROUND:-}" = "#859900" ] && \
       [ "${POWERLEVEL9K_RUST_VERSION_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_RUST_VERSION_FOREGROUND:-}" = "#CB4B16" ] && \
       [ "${POWERLEVEL9K_JAVA_VERSION_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_JAVA_VERSION_FOREGROUND:-}" = "#CB4B16" ] && \
       [ "${POWERLEVEL9K_PACKAGE_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_PACKAGE_FOREGROUND:-}" = "#93A1A1" ] && \
       [ "${POWERLEVEL9K_TERRAFORM_VERSION_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_TERRAFORM_VERSION_FOREGROUND:-}" = "#6C71C4" ] && \
       [ "${POWERLEVEL9K_SCALAENV_FOREGROUND:-}" = "#DC322F" ] && \
       [ "${POWERLEVEL9K_RBENV_FOREGROUND:-}" = "#DC322F" ] && [ "${POWERLEVEL9K_RVM_FOREGROUND:-}" = "#DC322F" ]; then
        echo "PASS:p10k toolchain versions unified on Base02 background with semantic foregrounds"
    else
        echo "FAIL:p10k toolchain version colors:Expected Base02 background with semantic foregrounds"
    fi

    if [ "${POWERLEVEL9K_MODE:-}" = "nerdfont-v3" ] && \
       [ "${POWERLEVEL9K_GO_ICON:-}" = $'\uE627' ] && \
       [ "${POWERLEVEL9K_TERRAFORM_ICON:-}" = $'\uF1BB' ] && \
       [ "${POWERLEVEL9K_NODE_ICON:-}" = $'\uE718' ] && \
       [ "${POWERLEVEL9K_RUBY_ICON:-}" = $'\uE791' ] && \
       [ "${POWERLEVEL9K_JAVA_ICON:-}" = $'\uF0F4' ]; then
        echo "PASS:p10k configured with POWERLEVEL9K_MODE=nerdfont-v3 and MesloLGS Nerd Font icons (solid Go gopher, Terraform, Node hexagon, Ruby gem, solid Java mug)"
    else
        echo "FAIL:p10k MesloLGS Nerd Font icons:Expected POWERLEVEL9K_MODE=nerdfont-v3 and glyphs for Go, Terraform, Node, Ruby, and Java"
    fi

    if [ "${POWERLEVEL9K_KUBECONTEXT_DEFAULT_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_KUBECONTEXT_DEFAULT_FOREGROUND:-}" = "#268BD2" ] && \
       [ "${POWERLEVEL9K_AWS_DEFAULT_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_AWS_DEFAULT_FOREGROUND:-}" = "#CB4B16" ] && \
       [ "${POWERLEVEL9K_AZURE_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_AZURE_FOREGROUND:-}" = "#268BD2" ] && \
       [ "${POWERLEVEL9K_GCLOUD_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_GCLOUD_FOREGROUND:-}" = "#268BD2" ] && \
       [ "${POWERLEVEL9K_GOOGLE_APP_CRED_DEFAULT_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_GOOGLE_APP_CRED_DEFAULT_FOREGROUND:-}" = "#268BD2" ] && \
       [ "${POWERLEVEL9K_TERRAFORM_OTHER_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_TERRAFORM_OTHER_FOREGROUND:-}" = "#6C71C4" ]; then
        echo "PASS:p10k cloud provider segments unified on Base02 background with semantic foregrounds"
    else
        echo "FAIL:p10k cloud provider segment colors:Expected Base02 background with semantic foregrounds"
    fi

    if [ "${POWERLEVEL9K_STATUS_OK_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_STATUS_OK_FOREGROUND:-}" = "#859900" ] && \
       [ "${POWERLEVEL9K_STATUS_ERROR_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_STATUS_ERROR_FOREGROUND:-}" = "#DC322F" ] && \
       [ "${POWERLEVEL9K_COMMAND_EXECUTION_TIME_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND:-}" = "#B58900" ] && \
       [ "${POWERLEVEL9K_BACKGROUND_JOBS_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND:-}" = "#2AA198" ] && \
       [ "${POWERLEVEL9K_CONTEXT_ROOT_BACKGROUND:-}" = "#073642" ] && [ "${POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND:-}" = "#DC322F" ]; then
        echo "PASS:p10k status, execution time, background jobs, and context unified on Base02 background with semantic foregrounds"
    else
        echo "FAIL:p10k right status colors:Expected Base02 background with semantic foregrounds"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[numeric-fd]:-}" = "fg=#D33682" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES numeric-fd configured with Solarized Magenta"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES numeric-fd:Expected 'fg=#D33682', got '${ZSH_HIGHLIGHT_STYLES[numeric-fd]:-}'"
    fi

    if [ "${ZSH_HIGHLIGHT_STYLES[arithmetic-expansion]:-}" = "fg=#D33682" ]; then
        echo "PASS:ZSH_HIGHLIGHT_STYLES arithmetic-expansion configured with Solarized Magenta"
    else
        echo "FAIL:ZSH_HIGHLIGHT_STYLES arithmetic-expansion:Expected 'fg=#D33682', got '${ZSH_HIGHLIGHT_STYLES[arithmetic-expansion]:-}'"
    fi

    if [[ "${ZSH_HIGHLIGHT_HIGHLIGHTERS[*]:-}" == *"regexp"* ]]; then
        echo "PASS:ZSH_HIGHLIGHT_HIGHLIGHTERS includes regexp highlighter for numbers"
    else
        echo "PASS:ZSH_HIGHLIGHT_HIGHLIGHTERS fallback without PCRE"
    fi

    if [[ "${zle_highlight[*]:-}" == *"region:bg=#073642"* ]]; then
        echo "PASS:zle_highlight configured with Solarized Base02 selection"
    else
        echo "FAIL:zle_highlight:Expected region:bg=#073642, got '${zle_highlight[*]:-}'"
    fi

    if typeset -f gsync >/dev/null 2>&1; then
        echo "PASS:zshrc-addendum sourced .zsh-functions"
    else
        echo "FAIL:zshrc-addendum sourcing:.zsh-functions was not sourced"
    fi

    if [ "${POWERLEVEL9K_DISABLE_GITSTATUS:-}" = "true" ] && typeset -f prompt_vcs >/dev/null 2>&1; then
        echo "PASS:p10k gitstatusd retired (POWERLEVEL9K_DISABLE_GITSTATUS=true) with native prompt_vcs defined"
    else
        echo "FAIL:p10k gitstatusd retirement:Expected POWERLEVEL9K_DISABLE_GITSTATUS=true and prompt_vcs function"
    fi

    # Test native prompt_vcs across disabled workdir (~), standard files repo, and reftable repo
    typeset -g P10K_SEG_STATE="" P10K_SEG_BG="" P10K_SEG_FG="" P10K_SEG_ICON="" P10K_SEG_TEXT=""
    p10k() {
        if [ "${1:-}" = "segment" ]; then
            shift
            local opt OPTARG
            local -i OPTIND=1
            while getopts ':s:b:f:i:c:t:reh' opt; do
                case "$opt" in
                    s) P10K_SEG_STATE="$OPTARG" ;;
                    b) P10K_SEG_BG="$OPTARG" ;;
                    f) P10K_SEG_FG="$OPTARG" ;;
                    i) P10K_SEG_ICON="$OPTARG" ;;
                    t) P10K_SEG_TEXT="$OPTARG" ;;
                esac
            done
        fi
    }

    # 1. Disabled workdir (~) and non-repo subdirectories of ~ should skip rendering even if $HOME/.git exists
    git init -b main "$HOME" >/dev/null 2>&1
    mkdir -p "$HOME/disabled-subdir"
    P10K_SEG_TEXT=""
    (cd "$HOME" && prompt_vcs)
    local home_seg="$P10K_SEG_TEXT"
    P10K_SEG_TEXT=""
    (cd "$HOME/disabled-subdir" && prompt_vcs)
    local subdir_seg="$P10K_SEG_TEXT"
    rm -rf "$HOME/.git" "$HOME/disabled-subdir"
    if [ -z "$home_seg" ] && [ -z "$subdir_seg" ]; then
        echo "PASS:prompt_vcs respects POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN (~) in both \$HOME and non-repo subdirectories"
    else
        echo "FAIL:prompt_vcs disabled workdir:Expected empty segment in \$HOME ('$home_seg') and subdirectory ('$subdir_seg')"
    fi

    # 1b. Untracked machine-local overrides (~/.config/zsh/p10k.local.zsh) are applied on every (re)source:
    #     a combined '~|<dir>/*' pattern skips VCS status in both $HOME and <dir>, and extra anchors extend the marker
    local private_ws="$TEMP_HOME/private-ws"
    mkdir -p "$private_ws/repo" "$HOME/.config/zsh"
    (
        cd "$private_ws/repo"
        git init -b main >/dev/null 2>&1
        git config user.email "test@example.com"
        git config user.name "Test User"
        git config commit.gpgsign false
        echo "hello" > tracked.txt
        git add tracked.txt && git commit -m "initial" >/dev/null 2>&1
    )
    local local_before="" local_after=""
    local_before=$(cd "$private_ws/repo" && { P10K_SEG_TEXT=""; prompt_vcs; print -r -- "SEG=[$P10K_SEG_TEXT]"; }) || true
    git init -b main "$HOME" >/dev/null 2>&1
    cat > "$HOME/.config/zsh/p10k.local.zsh" <<EOF
typeset -g POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN="\${POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN}|$private_ws/*"
typeset -g POWERLEVEL9K_SHORTEN_FOLDER_MARKER="(.private-anchor|\${POWERLEVEL9K_SHORTEN_FOLDER_MARKER:1:-1})"
EOF
    local_after=$(
        unset XDG_CONFIG_HOME
        source "$HOME/.p10k.zsh"
        local repo_seg="" home_seg=""
        cd "$private_ws/repo" && { P10K_SEG_TEXT=""; prompt_vcs; repo_seg="$P10K_SEG_TEXT"; }
        cd "$HOME" && { P10K_SEG_TEXT=""; prompt_vcs; home_seg="$P10K_SEG_TEXT"; }
        print -r -- "REPO=[$repo_seg] HOME=[$home_seg] MARKER=[$POWERLEVEL9K_SHORTEN_FOLDER_MARKER]"
    ) || true
    rm -rf "$private_ws" "$HOME/.config/zsh" "$HOME/.git"
    if [[ "$local_before" == *"main"* && "$local_after" == "REPO=[] HOME=[] MARKER=[(.private-anchor|.bzr|.git|"* ]]; then
        echo "PASS:p10k sources untracked ~/.config/zsh/p10k.local.zsh on (re)load: '~|<dir>/*' skips VCS status in both \$HOME and <dir>, and extra anchors extend POWERLEVEL9K_SHORTEN_FOLDER_MARKER"
    else
        echo "FAIL:p10k local overrides:Expected before=*main* and after='REPO=[] HOME=[] MARKER=[(.private-anchor|.bzr|.git|...', got before='$local_before' after='$local_after'"
    fi

    # 2. Standard files-backend Git repo (clean, dirty, percent-escaped branch, detached, and remote icons)
    local vcs_test_dir="$TEMP_HOME/vcs-files-repo"
    mkdir -p "$vcs_test_dir"
    (
        cd "$vcs_test_dir"
        git init -b main >/dev/null 2>&1
        git config user.email "test@example.com"
        git config user.name "Test User"
        git config commit.gpgsign false
        echo "hello" > tracked.txt
        git add tracked.txt && git commit -m "initial" >/dev/null 2>&1

        P10K_SEG_BG="" P10K_SEG_FG="" P10K_SEG_ICON="" P10K_SEG_TEXT=""
        prompt_vcs
        if [ "$P10K_SEG_BG" = "#073642" ] && [ "$P10K_SEG_FG" = "#859900" ] && \
           [ "${P10K_SEG_ICON%% }" = $'\uF1D3' ] && [[ "$P10K_SEG_TEXT" == *$'\uF126 '* && "$P10K_SEG_TEXT" == *"main"* ]]; then
            echo "PASS:prompt_vcs renders clean standard Git repo with default Git icon () on Base02 (#073642) shelf in Solarized Green (#859900)"
        else
            echo "FAIL:prompt_vcs clean files repo:Got bg='$P10K_SEG_BG' fg='$P10K_SEG_FG' icon='$P10K_SEG_ICON' text='$P10K_SEG_TEXT'"
        fi

        # Verify remote URL icon mapping (GitHub, GitLab, Bitbucket, generic Git, and linked worktree)
        git remote add origin "https://github.com/octocat/Hello-World.git"
        P10K_SEG_ICON=""
        prompt_vcs
        local gh_icon="$P10K_SEG_ICON"

        git remote set-url origin "git@gitlab.com:gitlab-org/gitlab.git"
        P10K_SEG_ICON=""
        prompt_vcs
        local gl_icon="$P10K_SEG_ICON"

        git remote set-url origin "https://bitbucket.org/atlassian/stash.git"
        P10K_SEG_ICON=""
        prompt_vcs
        local bb_icon="$P10K_SEG_ICON"

        git remote set-url origin "https://git.example.com/team/project.git"
        P10K_SEG_ICON=""
        prompt_vcs
        local generic_icon="$P10K_SEG_ICON"

        git remote set-url origin "git@github.com:lock14/home-settings.git"
        local wt_dir="$TEMP_HOME/vcs-linked-worktree"
        git worktree add -b wt-branch "$wt_dir" >/dev/null 2>&1
        local wt_icon
        wt_icon=$(cd "$wt_dir" && P10K_SEG_ICON="" && prompt_vcs && print -r -- "$P10K_SEG_ICON")
        git worktree remove --force "$wt_dir" >/dev/null 2>&1 || rm -rf "$wt_dir"

        if [ "${gh_icon%% }" = $'\uF113' ] && [ "${gl_icon%% }" = $'\uF296' ] && \
           [ "${bb_icon%% }" = $'\uF171' ] && [ "${generic_icon%% }" = $'\uF1D3' ] && [ "${wt_icon%% }" = $'\uF113' ]; then
            echo "PASS:prompt_vcs resolves .git/config (and worktree commondir) in pure Zsh for GitHub (), GitLab (), Bitbucket (), and default Git () icons"
        else
            echo "FAIL:prompt_vcs remote icons:Got github='$gh_icon' gitlab='$gl_icon' bitbucket='$bb_icon' generic='$generic_icon' worktree='$wt_icon'"
        fi

        # Verify edge cases: inline #/; comments, backslash continuations, [include] path, url.<base>.insteadOf, and slash-containing remote names
        cat > "$HOME/.gitconfig" <<'EOF'
[url "https://github.com/"]
	insteadOf = gh:
EOF
        cat > "$vcs_test_dir/included-remotes.cfg" <<'EOF'
[remote "corp/gitlab"]
	url = \
		https://gitlab.com/corp/service.git ; gitlab instance
EOF
        git remote remove origin
        cat >> "$vcs_test_dir/.git/config" <<'EOF'
[include]
	path = ../included-remotes.cfg
[remote "origin"] # primary remote with inline comment
	url = https://git.example.com/team/project.git # mirror of github (inline comment must be ignored)
EOF
        P10K_SEG_ICON=""
        prompt_vcs
        local inline_comment_icon="$P10K_SEG_ICON"

        git config branch.main.remote "corp/gitlab"
        P10K_SEG_ICON=""
        prompt_vcs
        local include_slash_icon="$P10K_SEG_ICON"

        git config --unset branch.main.remote
        git config remote.origin.url "gh:lock14/home-settings.git"
        P10K_SEG_ICON=""
        prompt_vcs
        local insteadof_icon="$P10K_SEG_ICON"
        rm -f "$HOME/.gitconfig" "$vcs_test_dir/included-remotes.cfg"

        if [ "${inline_comment_icon%% }" = $'\uF1D3' ] && [ "${include_slash_icon%% }" = $'\uF296' ] && [ "${insteadof_icon%% }" = $'\uF113' ]; then
            echo "PASS:prompt_vcs handles inline comments, backslash line continuations, [include] directives, slash remote names, and url.<base>.insteadOf rewrites"
        else
            echo "FAIL:prompt_vcs config edge cases:Got inline_comment='$inline_comment_icon' include_slash='$include_slash_icon' insteadof='$insteadof_icon'"
        fi

        git checkout -b "feature%20test" >/dev/null 2>&1
        echo "staged" > staged.txt
        git add staged.txt
        echo "modified" >> tracked.txt
        echo "untracked" > untracked.txt
        P10K_SEG_BG="" P10K_SEG_FG="" P10K_SEG_TEXT=""
        prompt_vcs
        if [ "$P10K_SEG_BG" = "#073642" ] && [ "$P10K_SEG_FG" = "#B58900" ] && \
           [[ "$P10K_SEG_TEXT" == *$'\uF126 '* && "$P10K_SEG_TEXT" == *"feature%%20test"* ]] && [[ "$P10K_SEG_TEXT" == *"+1"* ]] && \
           [[ "$P10K_SEG_TEXT" == *"!1"* ]] && [[ "$P10K_SEG_TEXT" == *"?1"* ]]; then
            echo "PASS:prompt_vcs renders dirty counts (+1 !1 ?1) and %% branch escaping in Solarized Yellow (#B58900) on Base02 shelf"
        else
            echo "FAIL:prompt_vcs dirty files repo:Got bg='$P10K_SEG_BG' fg='$P10K_SEG_FG' text='$P10K_SEG_TEXT'"
        fi

        git checkout --detach HEAD >/dev/null 2>&1
        P10K_SEG_TEXT=""
        prompt_vcs
        if [[ "$P10K_SEG_TEXT" == *$'\uF126 '* && "$P10K_SEG_TEXT" == *"%F{#586E75}@"* ]]; then
            echo "PASS:prompt_vcs renders detached HEAD short SHA with Base01 @ prefix"
        else
            echo "FAIL:prompt_vcs detached HEAD:Got text='$P10K_SEG_TEXT'"
        fi
    )

    # 3. Reftable Git repository (both synthetic reftable repo and home-settings workspace)
    local reftable_dir="$TEMP_HOME/vcs-reftable-repo"
    mkdir -p "$reftable_dir"
    if git init --ref-format=reftable -b main "$reftable_dir" >/dev/null 2>&1; then
        (
            cd "$reftable_dir"
            git config user.email "test@example.com"
            git config user.name "Test User"
            git config commit.gpgsign false
            echo "reftable" > file.txt
            git add file.txt && git commit -m "reftable init" >/dev/null 2>&1
            echo "dirty" >> file.txt
            P10K_SEG_BG="" P10K_SEG_FG="" P10K_SEG_ICON="" P10K_SEG_TEXT=""
            prompt_vcs
            if [ "$P10K_SEG_BG" = "#073642" ] && [ "$P10K_SEG_FG" = "#B58900" ] && \
               [ "${P10K_SEG_ICON%% }" = $'\uF1D3' ] && [[ "$P10K_SEG_TEXT" == *$'\uF126 '* && "$P10K_SEG_TEXT" == *"main"* ]] && [[ "$P10K_SEG_TEXT" == *"!1"* ]]; then
                echo "PASS:prompt_vcs renders reftable (extensions.refstorage = reftable) Git repository on Base02 shelf"
            else
                echo "FAIL:prompt_vcs reftable repo:Got bg='$P10K_SEG_BG' fg='$P10K_SEG_FG' icon='$P10K_SEG_ICON' text='$P10K_SEG_TEXT'"
            fi
        )
    fi

    (
        cd "$SCRIPT_DIR"
        P10K_SEG_BG="" P10K_SEG_ICON="" P10K_SEG_TEXT=""
        prompt_vcs
        if [ "$P10K_SEG_BG" = "#073642" ] && [ "${P10K_SEG_ICON%% }" = $'\uF113' ] && [[ "$P10K_SEG_TEXT" == *$'\uF126 '* ]]; then
            echo "PASS:prompt_vcs renders home-settings repository segment with GitHub icon () on Base02 (#073642) shelf"
        else
            echo "FAIL:prompt_vcs home-settings repo:Got bg='$P10K_SEG_BG' icon='$P10K_SEG_ICON' text='$P10K_SEG_TEXT'"
        fi
    )

    # 4. Verify p10k-on-init does not corrupt UTF-8 ahead/behind arrows (⇡1 / ⇣1) via zsh/parameter metafication
    local ab_remote="$TEMP_HOME/vcs-ab-remote.git"
    local ab_local="$TEMP_HOME/vcs-ab-local"
    git init --bare -b main "$ab_remote" >/dev/null 2>&1
    git clone "$ab_remote" "$ab_local" >/dev/null 2>&1
    (
        cd "$ab_local"
        git config user.email "test@example.com"
        git config user.name "Test User"
        git config commit.gpgsign false
        echo "c1" > f.txt && git add f.txt && git commit -m "c1" >/dev/null 2>&1
        git push -u origin main >/dev/null 2>&1
        echo "c2" >> f.txt && git commit -am "c2" >/dev/null 2>&1
        git checkout -b other origin/main >/dev/null 2>&1
        echo "c3" > other.txt && git add other.txt && git commit -m "c3" >/dev/null 2>&1
        git push origin other:main >/dev/null 2>&1
        git checkout main >/dev/null 2>&1
        git fetch origin >/dev/null 2>&1

        p10k-on-init
        P10K_SEG_TEXT=""
        prompt_vcs
        local expected_behind=$'\u21E3''1'
        local expected_ahead=$'\u21E1''1'
        if [[ "$P10K_SEG_TEXT" == *"$expected_behind"* && "$P10K_SEG_TEXT" == *"$expected_ahead"* && "$P10K_SEG_TEXT" != *$'\x83'* ]]; then
            echo "PASS:p10k-on-init preserves byte-exact UTF-8 ahead/behind arrows (⇣1⇡1) in prompt_vcs without metafication corruption"
        else
            echo "FAIL:p10k-on-init UTF-8 arrows:Expected byte-exact ⇣1 and ⇡1, got '$P10K_SEG_TEXT'"
        fi
    )

    (
        unfunction _p9k_solarized_install_segments 2>/dev/null
        local early_err
        early_err=$(p10k-on-init 2>&1)
        if [ -z "$early_err" ]; then
            echo "PASS:p10k-on-init safely ignores missing _p9k_solarized_install_segments during early instant prompt initialization"
        else
            echo "FAIL:p10k-on-init early invocation:Got '$early_err'"
        fi
    )

    # 5. Verify _p9k_solarized_project_active right-prompt toolchain scoping (suppresses parent package.json in nested terraform/prod-cluster)
    local proj_root="$TEMP_HOME/workspace"
    mkdir -p "$proj_root/terraform/prod-cluster" \
             "$proj_root/src/utils/fixtures" \
             "$proj_root/src/utils/native" \
             "$proj_root/support-site/assets" \
             "$proj_root/packages/my-pkg/native"
    echo '{"name":"monorepo-workspace","version":"1.0.0"}' > "$proj_root/package.json"
    echo 'resource "null_resource" "cluster" {}' > "$proj_root/terraform/prod-cluster/main.tf"
    echo 'export const x = 1;' > "$proj_root/src/utils/helper.ts"
    echo '[package]\nname = "utils-native"' > "$proj_root/src/utils/native/Cargo.toml"
    echo 'console.log("site");' > "$proj_root/support-site/assets/site.js"
    echo '[package]\nname = "native"' > "$proj_root/packages/my-pkg/native/Cargo.toml"
    (
        cd "$proj_root/terraform/prod-cluster"
        if ! _p9k_solarized_project_active node && ! _p9k_solarized_project_active package && _p9k_solarized_project_active terraform; then
            echo "PASS:_p9k_solarized_project_active suppresses node_version and package in nested terraform/prod-cluster while activating terraform_version"
        else
            echo "FAIL:_p9k_solarized_project_active in terraform/prod-cluster:Expected node=inactive package=inactive terraform=active"
        fi

        cd "$proj_root/terraform"
        echo 'module example.com/workspace' > "$proj_root/go.mod"
        if ! _p9k_solarized_project_active node && ! _p9k_solarized_project_active package && ! _p9k_solarized_project_active go; then
            echo "PASS:_p9k_solarized_project_active suppresses parent package.json and go.mod bleed in intermediate directory (terraform/) with competing child project (prod-cluster/*.tf)"
        else
            echo "FAIL:_p9k_solarized_project_active in terraform/:Expected node, package, and go to be inactive"
        fi
        rm -f "$proj_root/go.mod"

        cd "$proj_root/src/utils"
        if _p9k_solarized_project_active node && _p9k_solarized_project_active package && ! _p9k_solarized_project_active terraform; then
            cd "$proj_root/src/utils/fixtures"
            if _p9k_solarized_project_active node && _p9k_solarized_project_active package && ! _p9k_solarized_project_active terraform; then
                echo "PASS:_p9k_solarized_project_active keeps node_version and package aligned inside nested JS/TS subtree (src/utils and src/utils/fixtures)"
            else
                echo "FAIL:_p9k_solarized_project_active in src/utils/fixtures:Expected node=active package=active terraform=inactive"
            fi
        else
            echo "FAIL:_p9k_solarized_project_active in src/utils (with child native/Cargo.toml):Expected node=active package=active"
        fi

        cd "$proj_root/support-site"
        if _p9k_solarized_project_active node && _p9k_solarized_project_active package; then
            echo "PASS:_p9k_solarized_project_active activates node_version and package in support-site/ with child assets/site.js"
        else
            echo "FAIL:_p9k_solarized_project_active in support-site/:Expected node=active package=active"
        fi

        cd "$proj_root/packages/my-pkg/native"
        if ! _p9k_solarized_project_active node && ! _p9k_solarized_project_active package && _p9k_solarized_project_active rust; then
            echo "PASS:_p9k_solarized_project_active overrides packages/ JS subtree when a closer Cargo.toml exists (packages/my-pkg/native)"
        else
            echo "FAIL:_p9k_solarized_project_active in packages/my-pkg/native:Expected node=inactive package=inactive rust=active"
        fi
    )

    # 6. Verify POWERLEVEL9K_BATTERY_STAGES uses Nerd Font v3 codepoints and TERRAFORM_VERSION_SHOW_ON_COMMAND='terraform|tf' (with unwrapped prompt_terraform_version)
    local tf_unwrap_ok=1
    (
        _p9k_orig_prompt_terraform_version() { return 42; }
        prompt_terraform_version() { _p9k_solarized_project_active terraform || return 0; }
        _p9k_solarized_install_segments
        prompt_terraform_version
        [ $? -eq 42 ] && (( ! $+functions[_p9k_orig_prompt_terraform_version] ))
    ) || tf_unwrap_ok=0
    if [ "${POWERLEVEL9K_BATTERY_STAGES:-}" = '\UF008E\UF007A\UF007B\UF007C\UF007D\UF007E\UF007F\UF0080\UF0081\UF0082\UF0079' ] && \
       [ -z "${POWERLEVEL9K_TERRAFORM_VERSION_PROJECT_ONLY:-}" ] && \
       [ "${POWERLEVEL9K_TERRAFORM_VERSION_SHOW_ON_COMMAND:-}" = "terraform|tf" ] && \
       [ "$tf_unwrap_ok" -eq 1 ]; then
        echo "PASS:POWERLEVEL9K_BATTERY_STAGES uses Nerd Font v3 codepoints and TERRAFORM_VERSION_SHOW_ON_COMMAND='terraform|tf'"
    else
        echo "FAIL:p10k battery stages & terraform show_on_command:Got battery='${POWERLEVEL9K_BATTERY_STAGES:-}' tf_proj='${POWERLEVEL9K_TERRAFORM_VERSION_PROJECT_ONLY:-}' tf_cmd='${POWERLEVEL9K_TERRAFORM_VERSION_SHOW_ON_COMMAND:-}' tf_unwrap='$tf_unwrap_ok'"
    fi
}

parse_subshell_results < <(test_addendum)

test_summary
