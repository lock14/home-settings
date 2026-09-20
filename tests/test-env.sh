#!/usr/bin/env bash
# Test suite for environment variables and bash configurations

# shellcheck disable=SC2030,SC2031
set -euo pipefail
export MISE_YES=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/tests/test-helper.sh"

echo "========================================"
echo "Running Environment & Bash Tests"
echo "========================================"

# Test 1: Bash syntax checks
echo -e "\n[1/4] Checking script syntax with 'bash -n'..."
for f in "$SCRIPT_DIR/setup.sh" "$SCRIPT_DIR/dotfiles/.bashrc-addendum" "$SCRIPT_DIR/dotfiles/.environment-variables" "$SCRIPT_DIR/dotfiles/.aliases"; do
    if bash -n "$f"; then
        pass "Syntax valid: $(basename "$f")"
    else
        fail "Syntax check failed: $(basename "$f")" "bash -n returned non-zero"
    fi
done

# Test 2: Verify environment-variables PATH configuration
echo -e "\n[2/4] Testing dotfiles/.environment-variables exports..."
OLD_HOME="$HOME"
OLD_PATH="$PATH"
OLD_XDG_DATA_HOME="${XDG_DATA_HOME:-}"
OLD_XDG_CACHE_HOME="${XDG_CACHE_HOME:-}"
TEMP_HOME=$(mktemp -d)

cleanup_env_test() {
    chmod -R u+w "$TEMP_HOME" 2>/dev/null || true
    rm -rf "$TEMP_HOME"
    export HOME="$OLD_HOME"
    export PATH="$OLD_PATH"
    if [ -n "$OLD_XDG_DATA_HOME" ]; then export XDG_DATA_HOME="$OLD_XDG_DATA_HOME"; else unset XDG_DATA_HOME; fi
    if [ -n "$OLD_XDG_CACHE_HOME" ]; then export XDG_CACHE_HOME="$OLD_XDG_CACHE_HOME"; else unset XDG_CACHE_HOME; fi
}
trap cleanup_env_test EXIT

export HOME="$TEMP_HOME"
unset GOPATH XDG_DATA_HOME XDG_CACHE_HOME SVN_EDITOR
# shellcheck source=/dev/null
source "$SCRIPT_DIR/dotfiles/.environment-variables"

if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    pass "\$HOME/.local/bin present in PATH"
else
    fail "\$HOME/.local/bin in PATH" "Expected $HOME/.local/bin in PATH, got: $PATH"
fi

if [[ ":$PATH:" != *":$HOME/software/bin:"* ]]; then
    pass "\$HOME/software/bin is cleanly excluded from standard PATH"
else
    fail "\$HOME/software/bin in PATH" "\$HOME/software/bin should not be in standard PATH"
fi

if [ "${COLORTERM:-}" = "truecolor" ]; then
    pass "COLORTERM is set to truecolor"
else
    fail "COLORTERM export" "Expected truecolor, got: ${COLORTERM:-}"
fi

if [ "${BAT_THEME:-}" = "Solarized-Dark-TrueColor" ]; then
    pass "BAT_THEME is set to Solarized-Dark-TrueColor"
else
    fail "BAT_THEME export" "Expected Solarized-Dark-TrueColor, got: ${BAT_THEME:-}"
fi

if [[ "${BAT_OPTS:-}" == *"--italic-text=always"* ]]; then
    pass "BAT_OPTS is configured with --italic-text=always"
else
    fail "BAT_OPTS export" "Expected --italic-text=always in BAT_OPTS, got: ${BAT_OPTS:-}"
fi

if [ -n "${LSCOLORS:-}" ] && [ "${LSCOLORS:-}" = "exgxfxdxcxfxfxegedabagacad" ]; then
    pass "LSCOLORS configured with Solarized Dark palette for macOS BSD ls parity"
else
    fail "LSCOLORS export" "Expected exgxfxdxcxfxfxegedabagacad in LSCOLORS, got: ${LSCOLORS:-}"
fi

if [ -n "${EZA_COLORS:-}" ] && [ "${EXA_COLORS:-}" = "${EZA_COLORS:-}" ] && \
   [[ "${EZA_COLORS}" == *"Su=38;2;131;148;150"* ]] && \
   [[ "${EZA_COLORS}" == *"ff=38;2;131;148;150"* ]] && \
   [[ "${EZA_COLORS}" == *"sn=38;2;131;148;150"* ]] && \
   [[ "${EZA_COLORS}" == *"do=38;2;131;148;150"* ]] && \
   [[ "${EZA_COLORS}" == *"sc=38;2;131;148;150"* ]] && \
   [[ "${EZA_COLORS}" == *"hd=4;38;2;147;161;161"* ]] && \
   [[ "${EZA_COLORS}" == *"co=38;2;203;75;22"* ]] && \
   [[ "${EZA_COLORS}" == *"cr=38;2;211;54;130"* ]] && \
   [[ "${EZA_COLORS}" == *"Gm=38;2;133;153;0"* ]] && \
   [[ "${EZA_COLORS}" == *"Gd=38;2;181;137;0"* ]] && \
   [[ "${EZA_COLORS}" == *"gm=38;2;181;137;0"* ]] && \
   [[ "${EZA_COLORS}" != *"1;38;2;181;137;0"* ]]; then
    pass "EZA_COLORS and EXA_COLORS configured with Solarized Dark palette (unbolded, Base0 documents/code, Base1 header, Orange archives, Magenta crypto, Green main branch, Yellow modified)"
else
    fail "EZA_COLORS export" "Expected Solarized Dark in EZA_COLORS with unbolded codes, got: ${EZA_COLORS:-}"
fi

if command -v nvim >/dev/null 2>&1; then
    if [ "${EDITOR:-}" = "nvim" ]; then
        pass "EDITOR is set to nvim (nvim detected)"
    else
        fail "EDITOR export" "Expected nvim, got: ${EDITOR:-}"
    fi
elif command -v vim >/dev/null 2>&1; then
    if [ "${EDITOR:-}" = "vim" ]; then
        pass "EDITOR is set to vim (fallback when nvim is absent)"
    else
        fail "EDITOR export" "Expected vim, got: ${EDITOR:-}"
    fi
else
    if [ "${EDITOR:-}" = "vi" ]; then
        pass "EDITOR is set to vi (fallback when nvim and vim are absent)"
    else
        fail "EDITOR export" "Expected vi, got: ${EDITOR:-}"
    fi
fi

if [ "${GOPATH:-}" = "$TEMP_HOME/.local/share/go" ] && [[ ":$PATH:" == *":$TEMP_HOME/.local/share/go/bin:"* ]]; then
    pass "GOPATH and \$GOPATH/bin set cleanly to XDG location ($TEMP_HOME/.local/share/go)"
else
    fail "GOPATH export" "Expected $TEMP_HOME/.local/share/go, got GOPATH=${GOPATH:-}, PATH=$PATH"
fi

if [ "${GOCACHE:-}" = "$TEMP_HOME/.cache/go-build" ]; then
    pass "GOCACHE set cleanly to XDG location ($TEMP_HOME/.cache/go-build)"
else
    fail "GOCACHE export" "Expected $TEMP_HOME/.cache/go-build, got GOCACHE=${GOCACHE:-}"
fi

if [[ "${FZF_DEFAULT_OPTS:-}" == *"#002B36"* ]] && [[ "${FZF_DEFAULT_OPTS:-}" == *"#839496"* ]]; then
    pass "FZF_DEFAULT_OPTS configured with Solarized Dark palette"
else
    fail "FZF_DEFAULT_OPTS export" "Expected Solarized Dark palette in FZF_DEFAULT_OPTS, got: ${FZF_DEFAULT_OPTS:-}"
fi

if command -v rg >/dev/null 2>&1 || command -v fd >/dev/null 2>&1; then
    if [ -n "${FZF_DEFAULT_COMMAND:-}" ] && [ -n "${FZF_CTRL_T_COMMAND:-}" ]; then
        pass "FZF_DEFAULT_COMMAND and FZF_CTRL_T_COMMAND cleanly configured ($FZF_DEFAULT_COMMAND)"
    else
        fail "FZF commands" "Expected non-empty FZF_DEFAULT_COMMAND and FZF_CTRL_T_COMMAND"
    fi
fi

if [ -z "${SVN_EDITOR:-}" ]; then
    pass "Legacy SVN_EDITOR is cleanly omitted"
else
    fail "SVN_EDITOR" "SVN_EDITOR should not be exported"
fi

# Test fallback to vi when nvim and vim are absent
MOCK_BIN=$(mktemp -d)
touch "$MOCK_BIN/vi" && chmod +x "$MOCK_BIN/vi"
OLD_MOCK_PATH="$PATH"
export PATH="$MOCK_BIN"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/dotfiles/.environment-variables"
if [ "${EDITOR:-}" = "vi" ]; then
    pass "EDITOR falls back to vi when nvim and vim are absent"
else
    fail "EDITOR fallback to vi" "Expected vi, got ${EDITOR:-}"
fi
export PATH="$OLD_MOCK_PATH"
rm -rf "$MOCK_BIN"

# Test 3: Verify bashrc-addendum sourcing & standalone server fallback mode
echo -e "\n[3/4] Testing dotfiles/.bashrc-addendum (full workstation & standalone server modes)..."
cp "$SCRIPT_DIR/dotfiles/.environment-variables" "$HOME/.environment-variables"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/dotfiles/.bashrc-addendum"

if [ "${EDITOR:-}" = "vim" ] || [ "${EDITOR:-}" = "nvim" ] || [ "${EDITOR:-}" = "vi" ]; then
    pass "bashrc-addendum sourced .environment-variables when present"
else
    fail "bashrc-addendum sourcing" ".environment-variables was not sourced (EDITOR=${EDITOR:-})"
fi

# Test standalone server mode in a fresh empty HOME with zero sibling dotfiles
STANDALONE_HOME=$(mktemp -d)
(
    export HOME="$STANDALONE_HOME"
    unset EDITOR VISUAL COLORTERM LS_COLORS LSCOLORS HISTSIZE HISTFILESIZE HISTCONTROL LESS_TERMCAP_md LESS_TERMCAP_us SSH_CLIENT SSH_TTY SSH_CONNECTION
    shopt -s expand_aliases
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/dotfiles/.bashrc-addendum"

    if [ "${COLORTERM:-}" = "truecolor" ] && [ -n "${EDITOR:-}" ] && [ "${VISUAL:-}" = "${EDITOR:-}" ] && \
       [ "${GOPATH:-}" = "$STANDALONE_HOME/.local/share/go" ] && [ "${GOCACHE:-}" = "$STANDALONE_HOME/.cache/go-build" ] && \
       [ "${HISTSIZE:-}" = "50000" ] && [ "${HISTFILESIZE:-}" = "100000" ] && \
       [[ "${HISTCONTROL:-}" == *"ignoreboth"* ]] && [ -n "${LESS_TERMCAP_md:-}" ] && [ -n "${LESS_TERMCAP_us:-}" ]; then
        echo "PASS:Standalone .bashrc-addendum exports COLORTERM, EDITOR/VISUAL, XDG GOPATH/GOCACHE, history settings, and Solarized LESS_TERMCAP manpage colors"
    else
        echo "FAIL:Standalone env fallback:Missing expected exports (COLORTERM=${COLORTERM:-}, EDITOR=${EDITOR:-}, GOPATH=${GOPATH:-}, HISTSIZE=${HISTSIZE:-})"
    fi

    if [[ "${LS_COLORS:-}" == *"di=34:"* ]] && [[ "${LS_COLORS:-}" == *"ln=36:"* ]] && \
       [[ "${LS_COLORS:-}" == *"ex=32:"* ]] && [[ "${LS_COLORS:-}" == *"*.tar=91:"* ]] && \
       [[ "${LS_COLORS:-}" == *"*.png=95:"* ]] && [[ "${LS_COLORS:-}" == *"*.key=35:"* ]] && \
       [[ "${LS_COLORS:-}" == *"*.pem=35:"* ]] && [[ "${LS_COLORS:-}" == *"*.txt=00:"* ]] && \
       [ "${LSCOLORS:-}" = "exgxfxdxcxfxfxegedabagacad" ]; then
        echo "PASS:Standalone .bashrc-addendum configures calibrated inline Solarized Dark LS_COLORS and LSCOLORS"
    else
        echo "FAIL:Standalone LS_COLORS:Unexpected LS_COLORS or LSCOLORS in standalone mode"
    fi

    if alias gcommit >/dev/null 2>&1 && alias gamend >/dev/null 2>&1 && \
       alias gprune >/dev/null 2>&1 && alias gpurge >/dev/null 2>&1 && \
       alias guser-branch >/dev/null 2>&1 && alias ll >/dev/null 2>&1 && \
       alias grep >/dev/null 2>&1 && declare -F gsync >/dev/null 2>&1; then
        echo "PASS:Standalone .bashrc-addendum defines Git workflow aliases (gcommit, gamend, gprune, gpurge, guser-branch), ls/grep aliases, and gsync function"
    else
        echo "FAIL:Standalone aliases/gsync:Missing expected standalone aliases or gsync function"
    fi

    # Test Solarized Dark PS1 shelf prompt states (local vs SSH, clean vs dirty git, detached HEAD, non-git dir, TERM=linux fallback, exit status 0 vs non-zero)
    cd "$STANDALONE_HOME"
    true
    _solarized_bash_prompt
    ps1_nongit_ok="$PS1"

    MOCK_REPO="$STANDALONE_HOME/repo"
    mkdir -p "$MOCK_REPO"
    cd "$MOCK_REPO"
    git init -b main >/dev/null 2>&1
    git config user.email "test@example.com"
    git config user.name "Test User"
    git config commit.gpgsign false
    echo "init" > README.md
    git add README.md && git commit -m "initial" >/dev/null 2>&1
    short_sha=$(git rev-parse --short HEAD)

    true
    _solarized_bash_prompt
    ps1_clean_ok="$PS1"

    git checkout --detach HEAD >/dev/null 2>&1
    true
    _solarized_bash_prompt
    ps1_detached_ok="$PS1"
    git checkout main >/dev/null 2>&1

    cd "$MOCK_REPO/.git"
    true
    _solarized_bash_prompt
    ps1_dotgit_dir="$PS1"
    cd "$MOCK_REPO"

    git checkout -q -b 'feat/$(echo_INJECTED)'
    true
    _solarized_bash_prompt
    ps1_branch_escaped="${PS1@P}"
    git checkout -q main
    git branch -D 'feat/$(echo_INJECTED)' >/dev/null 2>&1

    OSTYPE=darwin23 _solarized_bash_prompt
    ps1_macos="$PS1"

    COLORTERM="" TERM=xterm-256color _solarized_bash_prompt
    ps1_16color_utf8="$PS1"

    TERM=linux _solarized_bash_prompt
    ps1_linux_vt="$PS1"

    export SSH_CONNECTION="192.0.2.1 54321 192.0.2.2 22"
    echo "dirty" >> README.md
    false || _solarized_bash_prompt
    ps1_ssh_dirty_err="$PS1"

    if [[ "$ps1_clean_ok" == *"48;2;7;54;66m"* ]] && \
       [[ "$ps1_clean_ok" == *"38;2;131;148;150m\\]"* ]] && \
       [[ "$ps1_clean_ok" == *"38;2;88;110;117m\\]"* ]] && \
       [[ "$ps1_clean_ok" == *"38;2;38;139;210m\\]\\w"* ]] && \
       [[ "$ps1_clean_ok" == *"38;2;133;153;0m\\]  main"* ]] && \
       [[ "$ps1_clean_ok" == *"38;2;7;54;66m\\]"* ]] && \
       [[ "$ps1_clean_ok" == *"38;2;133;153;0m\\]❯"* ]] && \
       [[ "$ps1_clean_ok" != *"│"* ]] && \
       [[ "$ps1_macos" == *"38;2;131;148;150m\\]"* ]] && \
       [[ "$ps1_16color_utf8" == *"\\e[40m\\]"* ]] && \
       [[ "$ps1_16color_utf8" == *"\\e[90m\\]"* ]] && \
       [[ "$ps1_16color_utf8" == *"\\e[0m\\e[30m\\]"* ]] && \
       [[ "$ps1_nongit_ok" == *"48;2;7;54;66m"* ]] && \
       [[ "$ps1_nongit_ok" == *"38;2;38;139;210m\\]\\w \\["* ]] && \
       [[ "$ps1_nongit_ok" != *""* ]] && \
       [[ "$ps1_dotgit_dir" != *""* ]] && \
       [[ "$ps1_branch_escaped" == *'feat/$(echo_INJECTED)'* ]] && \
       [[ "$ps1_detached_ok" == *"38;2;133;153;0m\\]  ${short_sha}"* ]] && \
       [[ "$ps1_linux_vt" == *"\\e[40m\\]"* ]] && \
       [[ "$ps1_linux_vt" == *"\\e[90m\\]>"* ]] && \
       [[ "$ps1_linux_vt" == *"\\e[32m\\]>"* ]] && \
       [[ "$ps1_linux_vt" != *""* ]] && \
       [[ "$ps1_linux_vt" != *""* ]] && \
       [[ "$ps1_linux_vt" != *""* ]] && \
       [[ "$ps1_linux_vt" != *""* ]] && \
       [[ "$ps1_ssh_dirty_err" == *"38;2;131;148;150m\\]"* ]] && \
       [[ "$ps1_ssh_dirty_err" == *"38;2;181;137;0m\\]\\u@\\h"* ]] && \
       [[ "$ps1_ssh_dirty_err" == *"38;2;181;137;0m\\]  main*"* ]] && \
       [[ "$ps1_ssh_dirty_err" == *"38;2;7;54;66m\\]"* ]] && \
       [[ "$ps1_ssh_dirty_err" == *"38;2;220;50;47m\\]❯"* ]] && \
       [[ "$ps1_ssh_dirty_err" != *"│"* ]]; then
        echo 'PASS:Standalone _solarized_bash_prompt renders Base02 (#073642) shelf, Base01 (#586E75) \uE0B1 () directional chevrons, Base02 \uE0B0 () end-cap, Base0 OS icon + Base0/Yellow host, Blue dir, Green/Yellow \uF1D3/\uF126 ( ) git status, TERM=linux fallback, and zero box-drawing bars (│)'
    else
        echo "FAIL:Standalone PS1 shelf prompt:Unexpected PS1 sequences (clean=$ps1_clean_ok | nongit=$ps1_nongit_ok | dotgit=$ps1_dotgit_dir | escaped=$ps1_branch_escaped | detached=$ps1_detached_ok | linux=$ps1_linux_vt | ssh_dirty=$ps1_ssh_dirty_err)"
    fi

    # Test VCS remote host icons (GitHub \uF113 , GitLab \uF296 , Bitbucket \uF171 , generic Git \uF1D3 , tracked branch remote, inline comments, linked worktree, and TERM=linux)
    unset SSH_CONNECTION
    git checkout -- README.md
    git remote add origin "https://github.com/octocat/Hello-World.git"
    true
    _solarized_bash_prompt
    ps1_gh_clean="$PS1"

    echo "dirty" >> README.md
    true
    _solarized_bash_prompt
    ps1_gh_dirty="$PS1"
    git checkout -- README.md

    TERM=linux _solarized_bash_prompt
    ps1_gh_linux="$PS1"

    git remote set-url origin "git@gitlab.com:gitlab-org/gitlab.git"
    true
    _solarized_bash_prompt
    ps1_gl_clean="$PS1"

    git remote set-url origin "https://bitbucket.org/atlassian/stash.git"
    true
    _solarized_bash_prompt
    ps1_bb_clean="$PS1"

    git remote remove origin
    cat > "$STANDALONE_HOME/.gitconfig" <<'EOF'
[url "https://github.com/"]
	insteadOf = gh:
[url "https://gitlab.com/"]
	insteadOf = forge:
[includeIf "gitdir:~/repo/"]
	path = ~/work-includeif.cfg
EOF
    cat > "$STANDALONE_HOME/work-includeif.cfg" <<'EOF'
[url "https://[::1]/bitbucket/"]
	insteadOf = bb6:
EOF
    cat > "$STANDALONE_HOME/included-remotes.cfg" <<'EOF'
[remote "corp/gitlab"]
	url = \
		https://gitlab.com/corp/service.git ; gitlab instance
EOF
    cat >> "$MOCK_REPO/.git/config" <<'EOF'
[include]
	path = ../../included-remotes.cfg
[url "https://github.com/"]
	insteadOf = forge:
[remote "origin"] # primary remote with inline comment
	url = https://git.example.com/team/project.git # mirror of github (inline comment must be ignored)
[remote "upstream"]
	url = https://gitlab.com/team/project.git ; upstream gitlab
EOF
    true
    _solarized_bash_prompt
    ps1_generic_comment="$PS1"

    git config branch.main.remote "corp/gitlab"
    true
    _solarized_bash_prompt
    ps1_tracked_upstream="$PS1"
    git config --unset branch.main.remote

    git config remote.origin.url "gh:lock14/home-settings.git"
    true
    _solarized_bash_prompt
    ps1_insteadof_gh="$PS1"

    git config remote.origin.url "forge:lock14/home-settings.git"
    true
    _solarized_bash_prompt
    ps1_insteadof_override="$PS1"

    git config remote.origin.url "bb6:atlassian/stash.git"
    true
    _solarized_bash_prompt
    ps1_includeif_bb6="$PS1"

    git config remote.origin.url "https://github.com/lock14/home-settings.git"
    git config --add remote.origin.url "https://backup.internal.example/lock14/home-settings.git"
    true
    _solarized_bash_prompt
    ps1_multi_url_gh="$PS1"

    rm -f "$STANDALONE_HOME/.gitconfig" "$STANDALONE_HOME/work-includeif.cfg" "$STANDALONE_HOME/included-remotes.cfg"

    git config --replace-all remote.origin.url "git@github.com:lock14/home-settings.git"
    WT_REPO="$STANDALONE_HOME/wt-repo"
    git worktree add -b wt-branch "$WT_REPO" >/dev/null 2>&1
    cd "$WT_REPO"
    true
    _solarized_bash_prompt
    ps1_wt_gh="$PS1"
    cd "$MOCK_REPO"
    git worktree remove --force "$WT_REPO" >/dev/null 2>&1 || rm -rf "$WT_REPO"

    if [[ "$ps1_gh_clean" == *"38;2;133;153;0m\\]  main"* ]] && \
       [[ "$ps1_gh_dirty" == *"38;2;181;137;0m\\]  main*"* ]] && \
       [[ "$ps1_gl_clean" == *"38;2;133;153;0m\\]  main"* ]] && \
       [[ "$ps1_bb_clean" == *"38;2;133;153;0m\\]  main"* ]] && \
       [[ "$ps1_generic_comment" == *"38;2;133;153;0m\\]  main"* ]] && \
       [[ "$ps1_tracked_upstream" == *"38;2;133;153;0m\\]  main"* ]] && \
       [[ "$ps1_insteadof_gh" == *"38;2;133;153;0m\\]  main"* ]] && \
       [[ "$ps1_insteadof_override" == *"38;2;133;153;0m\\]  main"* ]] && \
       [[ "$ps1_includeif_bb6" == *"38;2;133;153;0m\\]  main"* ]] && \
       [[ "$ps1_multi_url_gh" == *"38;2;133;153;0m\\]  main"* ]] && \
       [[ "$ps1_wt_gh" == *"38;2;133;153;0m\\]  wt-branch"* ]] && \
       [[ "$ps1_gh_linux" != *""* ]] && \
       [[ "$ps1_gh_linux" != *""* ]] && \
       [[ "$ps1_gh_linux" == *"\\e[32m\\]main"* ]]; then
        echo 'PASS:Standalone _solarized_bash_prompt resolves .git/config (and worktree commondir) in pure Bash for GitHub (), GitLab (), Bitbucket (), and default Git () icons'
    else
        echo "FAIL:Standalone PS1 remote host icons:Unexpected remote icons (gh=$ps1_gh_clean | gh_dirty=$ps1_gh_dirty | gl=$ps1_gl_clean | bb=$ps1_bb_clean | generic=$ps1_generic_comment | tracked=$ps1_tracked_upstream | insteadof=$ps1_insteadof_gh | override=$ps1_insteadof_override | includeif=$ps1_includeif_bb6 | multi=$ps1_multi_url_gh | wt=$ps1_wt_gh | linux=$ps1_gh_linux)"
    fi

    # Test interactive Bash PROMPT_COMMAND coexistence with zoxide/mise and exit status propagation
    interactive_out=$(HOME="$STANDALONE_HOME" bash --norc -i -c "source '$SCRIPT_DIR/dotfiles/.bashrc-addendum'; false; eval \"\$PROMPT_COMMAND\"; p_err=\"\$PS1\"; true; eval \"\$PROMPT_COMMAND\"; p_ok=\"\$PS1\"; printf 'PC=%s\nERR=%s\nOK=%s\n' \"\${PROMPT_COMMAND[*]}\" \"\$p_err\" \"\$p_ok\"" 2>/dev/null)
    if grep -Fq "_solarized_bash_prompt" <<< "$interactive_out" && \
       grep -Fq "220;50;47m" <<< "$interactive_out" && \
       grep -Fq "133;153;0m" <<< "$interactive_out" && \
       { ! command -v zoxide >/dev/null 2>&1 || grep -Fq "__zoxide_hook" <<< "$interactive_out"; } && \
       { ! command -v mise >/dev/null 2>&1 || grep -Fq "_mise_hook" <<< "$interactive_out"; }; then
        echo "PASS:Interactive .bashrc-addendum preserves zoxide/mise PROMPT_COMMAND hooks and propagates command exit status"
    else
        echo "FAIL:Interactive PROMPT_COMMAND:Missing hooks or exit status propagation ($interactive_out)"
    fi

    # Test minimal server vi-only fallback (neither nvim nor vim installed)
    VI_ONLY_BIN="$STANDALONE_HOME/vi-only-bin"
    mkdir -p "$VI_ONLY_BIN"
    ln -s "$(command -v uname)" "$VI_ONLY_BIN/uname"
    touch "$VI_ONLY_BIN/vi" && chmod +x "$VI_ONLY_BIN/vi"
    vi_only_out=$(HOME="$STANDALONE_HOME" PATH="$VI_ONLY_BIN" "$BASH" -c "shopt -s expand_aliases; source '$SCRIPT_DIR/dotfiles/.bashrc-addendum'; printf 'EDITOR=%s|ALIAS_VI=%s|ALIAS_V=%s\n' \"\${EDITOR:-}\" \"\$(alias vi 2>/dev/null || echo none)\" \"\$(alias v 2>/dev/null || echo none)\"")
    if [[ "$vi_only_out" == *"EDITOR=vi|ALIAS_VI=none|ALIAS_V=alias v='vi'"* ]]; then
        echo "PASS:Standalone .bashrc-addendum preserves working vi and aliases v='vi' when nvim and vim are absent"
    else
        echo "FAIL:Standalone vi-only fallback:Unexpected alias/editor state ($vi_only_out)"
    fi
) > "$STANDALONE_HOME/results.txt"

while IFS= read -r line; do
    if [[ "$line" == PASS:* ]]; then
        pass "${line#PASS:}"
    elif [[ "$line" == FAIL:* ]]; then
        rest="${line#FAIL:}"
        fail "${rest%%:*}" "${rest#*:}"
    fi
done < "$STANDALONE_HOME/results.txt"
rm -rf "$STANDALONE_HOME"

cleanup_env_test
trap - EXIT

# Test 4: Verify LS_COLORS / dircolors configuration
echo -e "\n[4/4] Testing dircolors validity..."
if command -v dircolors >/dev/null 2>&1; then
    if dircolors_out=$(dircolors -b "$SCRIPT_DIR/dotfiles/.dir-colors/dircolors" 2>&1); then
        pass "dircolors database is valid"
        if [[ "$dircolors_out" == *"ln=36:"* ]] && [[ "$dircolors_out" == *"ex=32:"* ]] && \
           [[ "$dircolors_out" == *"*.png=95:"* ]] && [[ "$dircolors_out" == *"*.tar=91:"* ]] && \
           [[ "$dircolors_out" == *"*.key=35:"* ]] && [[ "$dircolors_out" == *"*.pem=35:"* ]] && \
           [[ "$dircolors_out" == *"*.txt=00:"* ]] && ! [[ "$dircolors_out" == *"*.txt=32:"* ]] && \
           ! [[ "$dircolors_out" == *"ex=01;32:"* ]]; then
            pass "dircolors strictly follows Pillars VIII & IX (Cyan symlinks, unbolded Green executables, Violet media ANSI 95, Orange archives ANSI 91, Magenta crypto ANSI 35, Base0 text/code)"
        else
            fail "dircolors semantic mapping" "dircolors does not adhere to 7 Pillars specification: $dircolors_out"
        fi
    else
        fail "dircolors check" "dircolors failed: $dircolors_out"
    fi
else
    pass "dircolors not installed (skipped)"
fi

test_summary
