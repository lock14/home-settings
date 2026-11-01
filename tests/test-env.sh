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
for f in "$SCRIPT_DIR/dotfiles/.bashrc-addendum" "$SCRIPT_DIR/dotfiles/.environment-variables" "$SCRIPT_DIR/dotfiles/.aliases"; do
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
    export COLORTERM="truecolor"
}
trap cleanup_env_test EXIT

export HOME="$TEMP_HOME"
unset GOPATH XDG_DATA_HOME XDG_CACHE_HOME SVN_EDITOR COLORTERM BAT_THEME BAT_OPTS LSCOLORS EZA_COLORS EXA_COLORS FZF_DEFAULT_OPTS JQ_COLORS _ZO_ECHO _ZO_RESOLVE_SYMLINKS _ZO_FZF_OPTS
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

if (unset IDE_AI_CLI && . "$SCRIPT_DIR/dotfiles/.environment-variables" && [ "${IDE_AI_CLI:-}" = "agy" ]); then
    pass "IDE_AI_CLI defaults to 'agy' in .environment-variables"
else
    fail "IDE_AI_CLI export" "Expected 'agy', got: ${IDE_AI_CLI:-}"
fi

if (IDE_AI_CLI="claude" && . "$SCRIPT_DIR/dotfiles/.environment-variables" && [ "$IDE_AI_CLI" = "claude" ]); then
    pass "IDE_AI_CLI preserves caller override (claude / codex)"
else
    fail "IDE_AI_CLI override" "Expected IDE_AI_CLI override to be preserved"
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

if [ "${ELAN_HOME:-}" = "$TEMP_HOME/.local/share/elan" ] && [[ ":$PATH:" == *":$TEMP_HOME/.local/share/elan/bin:"* ]]; then
    pass "ELAN_HOME and \$ELAN_HOME/bin set cleanly to XDG location ($TEMP_HOME/.local/share/elan)"
else
    fail "ELAN_HOME export" "Expected $TEMP_HOME/.local/share/elan, got ELAN_HOME=${ELAN_HOME:-}, PATH=$PATH"
fi

if [[ "${FZF_DEFAULT_OPTS:-}" == *"#002B36"* ]] && [[ "${FZF_DEFAULT_OPTS:-}" == *"#839496"* ]]; then
    pass "FZF_DEFAULT_OPTS configured with Solarized Dark palette"
else
    fail "FZF_DEFAULT_OPTS export" "Expected Solarized Dark palette in FZF_DEFAULT_OPTS, got: ${FZF_DEFAULT_OPTS:-}"
fi

if [ -n "${JQ_COLORS:-}" ] && \
   [ "${JQ_COLORS}" = "38;2;211;54;130:38;2;211;54;130:38;2;211;54;130:38;2;211;54;130:38;2;42;161;152:38;2;131;148;150:38;2;131;148;150:38;2;133;153;0" ]; then
    pass "JQ_COLORS configured with authentic 24-bit TrueColor Solarized Dark palette"
else
    fail "JQ_COLORS export" "Expected Solarized Dark TrueColor in JQ_COLORS, got: ${JQ_COLORS:-}"
fi

if [ "${_ZO_ECHO:-}" = "1" ] && [ "${_ZO_RESOLVE_SYMLINKS:-}" = "1" ] && \
   [[ "${_ZO_FZF_OPTS:-}" == *"--preview="* ]] && [[ "${_ZO_FZF_OPTS:-}" == *"eza"* ]]; then
    pass "Zoxide environment variables configured (_ZO_ECHO=1, _ZO_RESOLVE_SYMLINKS=1, _ZO_FZF_OPTS eza preview)"
else
    fail "Zoxide environment variables" "Expected _ZO_ECHO=1, _ZO_RESOLVE_SYMLINKS=1, and _ZO_FZF_OPTS with eza preview"
fi

if [ "${LESS:-}" = "-R" ] && [ "${GROFF_NO_SGR:-}" = "1" ] && \
   [ -n "${LESS_TERMCAP_mb:-}" ] && [ -n "${LESS_TERMCAP_md:-}" ] && \
   [ -n "${LESS_TERMCAP_so:-}" ] && [ -n "${LESS_TERMCAP_us:-}" ]; then
    pass "Solarized Dark LESS_TERMCAP_* manpage colors and GROFF_NO_SGR=1 exported in .environment-variables"
else
    fail "LESS_TERMCAP in .environment-variables" "Expected LESS=-R, GROFF_NO_SGR=1, and LESS_TERMCAP_* in .environment-variables"
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
    unset EDITOR VISUAL COLORTERM LS_COLORS LSCOLORS HISTSIZE HISTFILESIZE HISTCONTROL LESS_TERMCAP_md LESS_TERMCAP_us GROFF_NO_SGR JQ_COLORS _ZO_ECHO _ZO_RESOLVE_SYMLINKS _ZO_FZF_OPTS SSH_CLIENT SSH_TTY SSH_CONNECTION
    shopt -s expand_aliases
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/dotfiles/.bashrc-addendum"

    if [ "${COLORTERM:-}" = "truecolor" ] && [ -n "${EDITOR:-}" ] && [ "${VISUAL:-}" = "${EDITOR:-}" ] && \
       [ "${GOPATH:-}" = "$STANDALONE_HOME/.local/share/go" ] && [ "${GOCACHE:-}" = "$STANDALONE_HOME/.cache/go-build" ] && \
       [ "${HISTSIZE:-}" = "50000" ] && [ "${HISTFILESIZE:-}" = "100000" ] && \
       [[ "${HISTCONTROL:-}" == *"ignoreboth"* ]] && [ "${GROFF_NO_SGR:-}" = "1" ] && \
       [ -n "${LESS_TERMCAP_md:-}" ] && [ -n "${LESS_TERMCAP_us:-}" ] && \
       [ -n "${JQ_COLORS:-}" ] && [ "${_ZO_ECHO:-}" = "1" ] && [ "${_ZO_RESOLVE_SYMLINKS:-}" = "1" ] && [ -n "${_ZO_FZF_OPTS:-}" ]; then
        echo "PASS:Standalone .bashrc-addendum exports COLORTERM, EDITOR/VISUAL, XDG GOPATH/GOCACHE, history settings, JQ_COLORS, Zoxide vars, and Solarized LESS_TERMCAP manpage colors"
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
       [[ "$(alias gpush 2>/dev/null)" == *"git push -u origin HEAD"* ]] && \
       [[ "$(alias gpushf 2>/dev/null)" == *"git push -u --force-with-lease origin HEAD"* ]] && \
       alias gup >/dev/null 2>&1 && ! alias gfetch >/dev/null 2>&1 && \
       alias gprune >/dev/null 2>&1 && alias gpurge >/dev/null 2>&1 && \
       alias guser-branch >/dev/null 2>&1 && alias ll >/dev/null 2>&1 && \
       alias ds >/dev/null 2>&1 && ! alias tealdeer >/dev/null 2>&1 && \
       alias ide2 >/dev/null 2>&1 && alias ide3 >/dev/null 2>&1 && \
       alias idek >/dev/null 2>&1 && alias qide >/dev/null 2>&1 && \
       alias update >/dev/null 2>&1 && alias grep >/dev/null 2>&1 && \
       declare -F gsync >/dev/null 2>&1 && declare -F v >/dev/null 2>&1 && \
       declare -F icd >/dev/null 2>&1; then
        echo "PASS:Standalone .bashrc-addendum defines Git workflow aliases (gcommit, gamend, gup, gprune, gpurge, guser-branch), ds/IDE/update shortcuts, ls/grep aliases, gsync, icd(), and RPC-aware v() function"
    else
        echo "FAIL:Standalone aliases/gsync:Missing expected standalone aliases, gsync, icd(), or v() function"
    fi

    if command -v nvim >/dev/null 2>&1; then
        bash_test_sock="/tmp/nvim-ide-bash-test-$$.sock"
        rm -f "$bash_test_sock"
        (cd "$SCRIPT_DIR" && nvim --clean --headless --listen "$bash_test_sock" >/dev/null 2>&1) &
        bash_nvim_pid=$!
        if wait_for_nvim_socket "$bash_test_sock" 30; then
            ver_out="$(TMUX="" NVIM_IDE_SOCKET="$bash_test_sock" v --version 2>/dev/null | head -n 1 || true)"
            (cd "$SCRIPT_DIR/modules" && TMUX="" NVIM_IDE_SOCKET="$bash_test_sock" v +2 "00-packages.sh" >/dev/null 2>&1) || true
            bash_remote_state="$(nvim --headless --server "$bash_test_sock" --remote-expr 'expand("%:p") . "|" . line(".")' 2>/dev/null || true)"
            kill "$bash_nvim_pid" 2>/dev/null || true
            rm -f "$bash_test_sock"
            if [ "$bash_remote_state" = "$SCRIPT_DIR/modules/00-packages.sh|2" ] && [[ "$ver_out" == NVIM* ]]; then
                echo "PASS:Standalone .bashrc-addendum v() resolves relative paths and +line arguments over RPC, and passes --version to local nvim"
            else
                echo "FAIL:Standalone v() RPC:Expected '$SCRIPT_DIR/modules/00-packages.sh|2' and NVIM version, got state='$bash_remote_state' ver='$ver_out'"
            fi
        else
            kill "$bash_nvim_pid" 2>/dev/null || true
            rm -f "$bash_test_sock"
        fi

        if command -v tmux >/dev/null 2>&1; then
            multisess_dir="$(mktemp -d)"
            bg_nvim_sock="$multisess_dir/bg-nvim.sock"
            (cd "$SCRIPT_DIR" && nvim --clean --headless --listen "$bg_nvim_sock" >/dev/null 2>&1) &
            bg_nvim_pid=$!
            wait_for_nvim_socket "$bg_nvim_sock" 30 || true
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux -f /dev/null new-session -d -s bg_sess -c "$SCRIPT_DIR" "sleep 30"
            bg_pane="$(TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux list-panes -t '=bg_sess:' -F '#{pane_id}' | head -n 1)"
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux set-option -t '=bg_sess:' @ide_socket "$bg_nvim_sock"
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux set-option -t '=bg_sess:' @ide_initial_root "$SCRIPT_DIR/modules"
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux new-session -d -s fg_sess -c "/tmp" "sleep 30"
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux set-option -t '=fg_sess:' @ide_socket "$multisess_dir/wrong-fg.sock"
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux set-option -t '=fg_sess:' @ide_initial_root "/tmp"
            tmux_env="$(TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux display-message -p -t '=bg_sess:' '#{socket_path},#{pid},0')"
            (cd "$SCRIPT_DIR/modules" && TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="$tmux_env" TMUX_PANE="$bg_pane" NVIM_IDE_SOCKET="" IDE_SESSION="" v +3 "10-dotfiles.sh" >/dev/null 2>&1) || true
            bg_remote_state="$(nvim --headless --server "$bg_nvim_sock" --remote-expr 'expand("%:p") . "|" . line(".")' 2>/dev/null || true)"
            icd_reset_pwd="$(cd "$SCRIPT_DIR" && TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="$tmux_env" TMUX_PANE="$bg_pane" IDE_INITIAL_ROOT="" IDE_SESSION="" icd --reset >/dev/null 2>&1 && pwd || true)"
            sid_reset_pwd="$(cd "$SCRIPT_DIR" && TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="${tmux_env%,0},\$0" TMUX_PANE="" IDE_INITIAL_ROOT="" IDE_SESSION="" icd --reset >/dev/null 2>&1 && pwd || true)"
            bad_pid_target="$(TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="${tmux_env%%,*},999999,0" TMUX_PANE="$bg_pane" _ide_tmux_target || echo "rejected")"
            kill "$bg_nvim_pid" 2>/dev/null || true
            TMUX_TMPDIR="$multisess_dir" XDG_RUNTIME_DIR="$multisess_dir" TMUX="" tmux kill-server >/dev/null 2>&1 || true
            rm -rf "$multisess_dir"
            if [ "$bg_remote_state" = "$SCRIPT_DIR/modules/10-dotfiles.sh|3" ] && [ "$icd_reset_pwd" = "$SCRIPT_DIR/modules" ] && [ "$sid_reset_pwd" = "$SCRIPT_DIR/modules" ] && [ "$bad_pid_target" = "rejected" ]; then
                echo "PASS:Standalone .bashrc-addendum v() and icd() target caller TMUX_PANE or \$0 session ID and verify server PID in multi-session tmux"
            else
                echo "FAIL:Standalone v()/icd() multi-session targeting:Expected '$SCRIPT_DIR/modules/10-dotfiles.sh|3', '$SCRIPT_DIR/modules', and 'rejected', got state='$bg_remote_state' pwd='$icd_reset_pwd' sid_pwd='$sid_reset_pwd' bad_pid='$bad_pid_target'"
            fi
        fi
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

    SOLARIZED_PROMPT_UID=0 _solarized_bash_prompt
    ps1_root="$PS1"

    expected_host_os_icon="$(_solarized_detect_os_icon)"

    if [[ "$ps1_clean_ok" == *"48;2;7;54;66m"* ]] && \
       [[ "$ps1_clean_ok" == *"38;2;131;148;150m\\]${expected_host_os_icon}"* ]] && \
       [[ "$ps1_clean_ok" == *"38;2;101;123;131m\\]"* ]] && \
       [[ "$ps1_clean_ok" == *"38;2;38;139;210m\\]\\w"* ]] && \
       [[ "$ps1_clean_ok" == *"38;2;133;153;0m\\]  main"* ]] && \
       [[ "$ps1_clean_ok" == *"38;2;7;54;66m\\]"* ]] && \
       [[ "$ps1_clean_ok" != *"❯"* ]] && \
       [[ "$ps1_clean_ok" != *"│"* ]] && \
       [[ "$ps1_clean_ok" != *"\\u@\\h"* ]] && \
       [[ "$ps1_macos" == *"38;2;131;148;150m\\]"* ]] && \
       [[ "$ps1_16color_utf8" == *"\\e[40m\\]"* ]] && \
       [[ "$ps1_16color_utf8" == *"\\e[90m\\]"* ]] && \
       [[ "$ps1_16color_utf8" == *"\\e[0m\\e[30m\\]"* ]] && \
       [[ "$ps1_nongit_ok" == *"48;2;7;54;66m"* ]] && \
       [[ "$ps1_nongit_ok" == *"38;2;38;139;210m\\]\\w \\["* ]] && \
       [[ "$ps1_nongit_ok" != *""* ]] && \
       [[ "$ps1_nongit_ok" != *"\\u@\\h"* ]] && \
       [[ "$ps1_nongit_ok" != *"❯"* ]] && \
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
       [[ "$ps1_ssh_dirty_err" == *"38;2;131;148;150m\\]${expected_host_os_icon}"* ]] && \
       [[ "$ps1_ssh_dirty_err" == *"38;2;147;161;161m\\]\\u@\\h"* ]] && \
       [[ "$ps1_ssh_dirty_err" == *"38;2;181;137;0m\\]  main*"* ]] && \
       [[ "$ps1_ssh_dirty_err" == *"38;2;220;50;47m\\]"* ]] && \
       [[ "$ps1_ssh_dirty_err" != *"38;2;7;54;66m\\]"* ]] && \
       [[ "$ps1_ssh_dirty_err" != *"❯"* ]] && \
       [[ "$ps1_ssh_dirty_err" != *"│"* ]] && \
       [[ "$ps1_root" == *"38;2;220;50;47m\\]\\u@\\h"* ]]; then
        echo 'PASS:Standalone _solarized_bash_prompt renders Base02 (#073642) shelf, Base00 (#657B83) \uE0B1 () directional chevrons, dynamic Base02/Red \uE0B0 () end-cap, Base0 OS icon + Base1 host in SSH, Blue dir, Green/Yellow \uF1D3/\uF126 ( ) git status, TERM=linux fallback, and zero box-drawing bars (│)'
    else
        echo "FAIL:Standalone PS1 shelf prompt:Unexpected PS1 sequences (clean=$ps1_clean_ok | nongit=$ps1_nongit_ok | dotgit=$ps1_dotgit_dir | escaped=$ps1_branch_escaped | detached=$ps1_detached_ok | linux=$ps1_linux_vt | ssh_dirty=$ps1_ssh_dirty_err | root=$ps1_root)"
    fi

    mock_os_release="$STANDALONE_HOME/mock-os-release"

    echo 'ID=ubuntu' > "$mock_os_release"
    os_ubuntu=$(SOLARIZED_PROMPT_OS_RELEASE="$mock_os_release" _solarized_detect_os_icon)

    echo 'ID=debian' > "$mock_os_release"
    os_debian=$(SOLARIZED_PROMPT_OS_RELEASE="$mock_os_release" _solarized_detect_os_icon)

    echo 'ID=fedora' > "$mock_os_release"
    os_fedora=$(SOLARIZED_PROMPT_OS_RELEASE="$mock_os_release" _solarized_detect_os_icon)

    echo 'ID=arch' > "$mock_os_release"
    os_arch=$(SOLARIZED_PROMPT_OS_RELEASE="$mock_os_release" _solarized_detect_os_icon)

    echo 'ID=rocky' > "$mock_os_release"
    os_rocky=$(SOLARIZED_PROMPT_OS_RELEASE="$mock_os_release" _solarized_detect_os_icon)

    echo 'ID=almalinux' > "$mock_os_release"
    os_alma=$(SOLARIZED_PROMPT_OS_RELEASE="$mock_os_release" _solarized_detect_os_icon)

    echo 'ID=pop' > "$mock_os_release"
    os_pop=$(SOLARIZED_PROMPT_OS_RELEASE="$mock_os_release" _solarized_detect_os_icon)

    echo 'ID=alpine' > "$mock_os_release"
    os_alpine=$(SOLARIZED_PROMPT_OS_RELEASE="$mock_os_release" _solarized_detect_os_icon)

    echo 'ID=nixos' > "$mock_os_release"
    os_nixos=$(SOLARIZED_PROMPT_OS_RELEASE="$mock_os_release" _solarized_detect_os_icon)

    echo 'ID=custom_distro' > "$mock_os_release"
    os_unknown=$(SOLARIZED_PROMPT_OS_RELEASE="$mock_os_release" _solarized_detect_os_icon)

    printf 'ID=elementary\nID_LIKE=ubuntu\n' > "$mock_os_release"
    os_idlike=$(SOLARIZED_PROMPT_OS_RELEASE="$mock_os_release" _solarized_detect_os_icon)

    os_darwin=$(OSTYPE=darwin23 _solarized_detect_os_icon)
    os_freebsd=$(OSTYPE=freebsd14 _solarized_detect_os_icon)
    os_override=$(SOLARIZED_PROMPT_OS_ICON='⭐' _solarized_detect_os_icon)
    _HS_PROMPT_OS_ICON='🎆' _solarized_bash_prompt
    ps1_holiday_icon="$PS1"

    if [ "$os_ubuntu" = "" ] && \
       [ "$os_debian" = "" ] && \
       [ "$os_fedora" = "" ] && \
       [ "$os_arch" = "" ] && \
       [ "$os_rocky" = "" ] && \
       [ "$os_alma" = "" ] && \
       [ "$os_pop" = "" ] && \
       [ "$os_alpine" = "" ] && \
       [ "$os_nixos" = "" ] && \
       [ "$os_unknown" = "" ] && \
       [ "$os_idlike" = "" ] && \
       [ "$os_darwin" = "" ] && \
       [ "$os_freebsd" = "" ] && \
       [ "$os_override" = "⭐" ] && \
       [[ "$ps1_holiday_icon" == *"🎆"* ]]; then
        echo 'PASS:_solarized_detect_os_icon accurately resolves Ubuntu (), Debian (), Fedora (), Arch (), Rocky (), AlmaLinux (), Pop!_OS (), Alpine (), NixOS (), macOS (), FreeBSD (), ID_LIKE inheritance, generic Linux fallback (), and _HS_PROMPT_OS_ICON holiday emblems'
    else
        echo "FAIL:_solarized_detect_os_icon:Unexpected icon resolutions (ubuntu=$os_ubuntu debian=$os_debian fedora=$os_fedora arch=$os_arch rocky=$os_rocky alma=$os_alma pop=$os_pop alpine=$os_alpine nixos=$os_nixos unknown=$os_unknown idlike=$os_idlike darwin=$os_darwin freebsd=$os_freebsd override=$os_override holiday=$ps1_holiday_icon)"
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

    # Test VCS prompt PR/MR OSC 8 hyperlink resolution across all 5 forge families, Tier 0 config, Tier 1/2/3 discovery, worktree commondir sharing, TERM=linux fallback, and promptvars safety
    b_inv="STALE"
    b_zero="STALE"
    _solarized_vcs_build_pr_url -v b_gh "git@github.com:octocat/Hello-World.git" "42"
    _solarized_vcs_build_pr_url -v b_gl "git@gitlab.com:group/sub/project.git" "17"
    _solarized_vcs_build_pr_url -v b_bb "https://x-token-auth:secret@bitbucket.org/team/repo.git" "8"
    _solarized_vcs_build_pr_url -v b_bbs "https://bitbucket.corp.example.com/scm/proj/my-repo.git" "123"
    _solarized_vcs_build_pr_url -v b_bbs_u "ssh://git@bitbucket.corp.example.com:7999/~jdoe/my-repo.git" "5"
    _solarized_vcs_build_pr_url -v b_cb "git@codeberg.org:owner/repo.git" "55"
    _solarized_vcs_build_pr_url -v b_gt "https://git.ByExample.org/org/service.git" "7" "gitea"
    _solarized_vcs_build_pr_url -v b_inv "not-a-valid-remote" "42" || true
    _solarized_vcs_build_pr_url -v b_zero "https://github.com/octocat/Hello-World.git" "0" || true
    if [ "$b_gh" = "https://github.com/octocat/Hello-World/pull/42" ] && \
       [ "$b_gl" = "https://gitlab.com/group/sub/project/-/merge_requests/17" ] && \
       [ "$b_bb" = "https://bitbucket.org/team/repo/pull-requests/8" ] && \
       [ "$b_bbs" = "https://bitbucket.corp.example.com/projects/PROJ/repos/my-repo/pull-requests/123" ] && \
       [ "$b_bbs_u" = "https://bitbucket.corp.example.com/users/jdoe/repos/my-repo/pull-requests/5" ] && \
       [ "$b_cb" = "https://codeberg.org/owner/repo/pulls/55" ] && \
       [ "$b_gt" = "https://git.ByExample.org/org/service/pulls/7" ] && \
       [ -z "$b_inv" ] && [ -z "$b_zero" ]; then
        echo "PASS:Standalone _solarized_vcs_build_pr_url normalizes GitHub, GitLab (with subgroups), Bitbucket Cloud, Bitbucket Server/DC, and Gitea/Forgejo/Codeberg PR/MR URLs and rejects invalid/zero inputs"
    else
        echo "FAIL:Standalone _solarized_vcs_build_pr_url:Got gh='$b_gh' gl='$b_gl' bb='$b_bb' bbs='$b_bbs' bbs_u='$b_bbs_u' cb='$b_cb' gt='$b_gt' inv='$b_inv' zero='$b_zero'"
    fi

    PR_BARE_REMOTE="$STANDALONE_HOME/pr-bare-remote.git"
    PR_CLONE_REPO="$STANDALONE_HOME/pr-clone-repo"
    PR_CACHE_DIR="$STANDALONE_HOME/pr-cache"
    git init --bare -b main "$PR_BARE_REMOTE" >/dev/null 2>&1
    git clone "$PR_BARE_REMOTE" "$PR_CLONE_REPO" >/dev/null 2>&1
    (
        export GIT_PR_CACHE_DIR="$PR_CACHE_DIR"
        export GIT_PR_CACHE_TTL=3600
        cd "$PR_CLONE_REPO"
        git config user.email "test@example.com"
        git config user.name "Test User"
        git config commit.gpgsign false
        echo "base" > README.md && git add README.md && git commit -m "base" >/dev/null 2>&1
        git push -u origin main >/dev/null 2>&1
        git checkout -q -b feat/pr-link
        echo "feature" >> README.md && git commit -am "feature" >/dev/null 2>&1
        git push -u origin feat/pr-link >/dev/null 2>&1
        feat_sha=$(git rev-parse HEAD)

        git config branch.feat/pr-link.pr 108
        git config branch.feat/pr-link.prurl 'https://github.com/octocat/Hello-World/pull/108?q=$(echo_INJECTED)'
        true
        _solarized_bash_prompt
        ps1_tier0_expanded="${PS1@P}"
        git config --unset branch.feat/pr-link.pr
        git config --unset branch.feat/pr-link.prurl

        git --git-dir="$PR_BARE_REMOTE" update-ref refs/pull/42/head "$feat_sha"
        mkdir -p "$PR_CLONE_REPO/sub/dir"
        (cd "$PR_CLONE_REPO/sub/dir" && _solarized_vcs_refresh_pr_cache)
        true
        _solarized_bash_prompt
        ps1_pr_clean="$PS1"

        # Linked worktree shares normalized commondir cache with main worktree
        PR_WT_REPO="$STANDALONE_HOME/pr-wt-repo"
        git worktree add -b feat/wt-pr "$PR_WT_REPO" >/dev/null 2>&1
        (
            cd "$PR_WT_REPO"
            echo "wt" >> README.md && git commit -am "wt" >/dev/null 2>&1
            git push -u origin feat/wt-pr >/dev/null 2>&1
            wt_sha=$(git rev-parse HEAD)
            git --git-dir="$PR_BARE_REMOTE" update-ref refs/pull/88/head "$wt_sha"
            _solarized_vcs_refresh_pr_cache
        )
        wt_state_count=$(find "$PR_CACHE_DIR" -maxdepth 1 -name '*.state' | wc -l | tr -d ' ')
        git worktree remove --force "$PR_WT_REPO" >/dev/null 2>&1 || rm -rf "$PR_WT_REPO"

        echo "dirty" >> README.md
        true
        _solarized_bash_prompt
        ps1_pr_dirty="$PS1"
        git checkout -- README.md

        TERM=linux _solarized_bash_prompt
        ps1_pr_linux="$PS1"

        git --git-dir="$PR_BARE_REMOTE" update-ref refs/heads/main "$feat_sha"
        rm -f "$PR_CACHE_DIR"/*.state
        _solarized_vcs_refresh_pr_cache
        true
        _solarized_bash_prompt
        ps1_pr_merged="$PS1"

        # Tier 1 (glab JSON with author.web_url before MR web_url) and Tier 3 (Bitbucket Cloud curl with ssh port 22)
        MOCK_CLI_DIR="$STANDALONE_HOME/mock-forge-clis"
        mkdir -p "$MOCK_CLI_DIR"
        cat > "$MOCK_CLI_DIR/glab" <<'EOF'
#!/usr/bin/env bash
printf '[{"id":999,"iid":51,"author":{"id":7,"web_url":"https://gitlab.com/jdoe"},"web_url":"https://gitlab.com/group/proj/-/merge_requests/51"}]\n'
EOF
        cat > "$MOCK_CLI_DIR/curl" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == "https://api.bitbucket.org/2.0/repositories/team/repo/pullrequests"* ]]; then
        printf '{"values":[{"type":"pullrequest","id":64,"links":{"html":{"href":"https://bitbucket.org/team/repo/pull-requests/64"}},"author":{"id":999}}]}\n'
        exit 0
    fi
done
exit 1
EOF
        chmod +x "$MOCK_CLI_DIR/glab" "$MOCK_CLI_DIR/curl"

        rm -f "$PR_CACHE_DIR"/*.state
        git remote set-url origin "git@gitlab.com:group/proj.git"
        PATH="$MOCK_CLI_DIR:$PATH" _solarized_vcs_refresh_pr_cache
        true
        _solarized_bash_prompt
        ps1_tier1_glab="$PS1"

        rm -f "$PR_CACHE_DIR"/*.state
        git remote set-url origin "ssh://git@bitbucket.org:22/team/repo.git"
        PATH="$MOCK_CLI_DIR:$PATH" _solarized_vcs_refresh_pr_cache
        true
        _solarized_bash_prompt
        ps1_tier3_bb="$PS1"
        rm -rf "$MOCK_CLI_DIR"

        if [[ "$ps1_tier0_expanded" == *'https://github.com/octocat/Hello-World/pull/108?q=$(echo_INJECTED)'* ]] && \
           [[ "$ps1_tier0_expanded" != *"INJECTED"* || "$ps1_tier0_expanded" == *'$(echo_INJECTED)'* ]] && \
           [[ "$ps1_pr_clean" == *"feat/pr-link\\[\\e]8;;https://localhost"* && "$ps1_pr_clean" == *"/pull/42\\a\\]\\[\\e[38;2;88;110;117m\\]@\\[\\e[38;2;133;153;0m\\]42\\[\\e]8;;\\a\\]"* ]] && \
           [ "$wt_state_count" = "1" ] && \
           [[ "$ps1_pr_dirty" == *"/pull/42\\a\\]\\[\\e[38;2;88;110;117m\\]@\\[\\e[38;2;181;137;0m\\]42\\[\\e]8;;\\a\\]*"* ]] && \
           [[ "$ps1_pr_linux" == *"feat/pr-link\\[\\e[90m\\]@\\[\\e[32m\\]42"* ]] && \
           [[ "$ps1_pr_linux" != *"\\e]8;;"* ]] && \
           [[ "$ps1_pr_merged" != *"@42"* ]] && \
           [[ "$ps1_tier1_glab" == *"https://gitlab.com/group/proj/-/merge_requests/51\\a\\]\\[\\e[38;2;88;110;117m\\]@\\[\\e[38;2;133;153;0m\\]51"* ]] && \
           [[ "$ps1_tier3_bb" == *"https://bitbucket.org/team/repo/pull-requests/64\\a\\]\\[\\e[38;2;88;110;117m\\]@\\[\\e[38;2;133;153;0m\\]64"* ]]; then
            echo "PASS:Standalone _solarized_bash_prompt renders clickable OSC 8 @<N> PR/MR links (Base01 @ + Green/Yellow N before dirty *), resolves Tier 1/2/3 & worktree commondir, guards against merged PRs and promptvars injection, and omits OSC 8 on TERM=linux"
        else
            echo "FAIL:Standalone _solarized_bash_prompt PR/MR links:Got tier0='$ps1_tier0_expanded' clean='$ps1_pr_clean' wt_states='$wt_state_count' dirty='$ps1_pr_dirty' linux='$ps1_pr_linux' merged='$ps1_pr_merged' glab='$ps1_tier1_glab' bb='$ps1_tier3_bb'"
        fi
    )
    cd "$MOCK_REPO"

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
    vi_only_out=$(HOME="$STANDALONE_HOME" PATH="$VI_ONLY_BIN" "$BASH" -c "shopt -s expand_aliases; source '$SCRIPT_DIR/dotfiles/.bashrc-addendum'; printf 'EDITOR=%s|ALIAS_VI=%s|FUNC_V=%s\n' \"\${EDITOR:-}\" \"\$(alias vi 2>/dev/null || echo none)\" \"\$(declare -F v 2>/dev/null || echo none)\"")
    if [[ "$vi_only_out" == *"EDITOR=vi|ALIAS_VI=none|FUNC_V=v"* ]]; then
        echo "PASS:Standalone .bashrc-addendum preserves working vi and defines v() fallback when nvim and vim are absent"
    else
        echo "FAIL:Standalone vi-only fallback:Unexpected alias/editor state ($vi_only_out)"
    fi

    # Test theme() wrapper function in Bash reloads environment exports (including TrueColor LS_COLORS) and PS1 prompt colors, skips reload on read-only queries and fzf cancel, and completes --holiday and --plain
    mkdir -p "$STANDALONE_HOME/.local/bin"
    ln -sf "$SCRIPT_DIR/bin/theme" "$STANDALONE_HOME/.local/bin/theme"
    bash_theme_out=$(HOME="$STANDALONE_HOME" XDG_CONFIG_HOME="$STANDALONE_HOME/.config" MISE_DISABLED=1 "$BASH" -c "
        set -euo pipefail
        source '$SCRIPT_DIR/dotfiles/.bashrc-addendum'
        theme --set catppuccin-mocha --no-live >/dev/null
        cm_ls=\"\${LS_COLORS:-}\"
        '$SCRIPT_DIR/bin/theme' --set halloween --no-live >/dev/null
        theme --plain >/dev/null
        after_plain=\"\${HOME_SETTINGS_THEME:-}\"
        theme --preview=nord >/dev/null
        after_prev=\"\${HOME_SETTINGS_THEME:-}\"
        fzf_cancel_bin=\"$STANDALONE_HOME/fzf-cancel\"
        mkdir -p \"\$fzf_cancel_bin\"
        printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 130\n' > \"\$fzf_cancel_bin/fzf\"
        chmod +x \"\$fzf_cancel_bin/fzf\"
        THEME_FORCE_FZF=1 PATH=\"\$fzf_cancel_bin:\$PATH\" theme --no-live >/dev/null 2>&1
        after_cancel=\"\${HOME_SETTINGS_THEME:-}\"
        _solarized_bash_prompt
        COMP_WORDS=(theme --); COMP_CWORD=1; _theme_bash_complete
        printf 'CM_LS=%s|AFTER_Q=%s/%s/%s|THEME=%s|BAT=%s|ICON=%s|HW_LS=%s|COMP=%s|PS1=%s\n' \"\$cm_ls\" \"\$after_plain\" \"\$after_prev\" \"\$after_cancel\" \"\${HOME_SETTINGS_THEME:-}\" \"\${BAT_THEME:-}\" \"\${_HS_PROMPT_OS_ICON:-}\" \"\${LS_COLORS:-}\" \"\${COMPREPLY[*]}\" \"\$PS1\"
    ")
    if [[ "$bash_theme_out" == *"CM_LS="*"di=38;2;137;180;250:"* ]] && \
       [[ "$bash_theme_out" == *"AFTER_Q=catppuccin-mocha/catppuccin-mocha/catppuccin-mocha|"* ]] && \
       [[ "$bash_theme_out" == *"THEME=halloween|BAT=Halloween-TrueColor|ICON=🎃|"* ]] && \
       [[ "$bash_theme_out" == *"HW_LS="*"di=38;2;85;255;71:"* ]] && \
       [[ "$bash_theme_out" == *"--holiday"* ]] && \
       [[ "$bash_theme_out" == *"--plain"* ]] && \
       [[ "$bash_theme_out" == *"48;2;40;16;64m"* ]]; then
        echo "PASS:Bash theme() wrapper updates TrueColor LS_COLORS and PS1, skips reloads on read-only queries (--plain, --preview=*) and fzf Esc cancel, auto-syncs cross-pane, and completes --holiday and --plain"
    else
        echo "FAIL:Bash theme() wrapper:Unexpected state ($bash_theme_out)"
    fi

    # Test 2-file standalone copied .bashrc-addendum: 1:1 17-theme parity without repo/bin/theme
    TWOFILE_DIR="$STANDALONE_HOME/twofile-isolated"
    mkdir -p "$TWOFILE_DIR"
    cp "$SCRIPT_DIR/dotfiles/.bashrc-addendum" "$TWOFILE_DIR/.bashrc-addendum"
    bash_17_fail=""
    for tf in "$SCRIPT_DIR"/colors/themes/*.theme; do
        t_id="$(awk -F'"' '/^THEME_ID=/ {print $2}' "$tf")"
        t_mode="$(awk -F'"' '/^THEME_MODE=/ {print $2}' "$tf")"
        t_bat="$(awk -F'"' '/^BAT_THEME_NAME=/ {print $2}' "$tf")"
        t_b03="$(awk -F'"' '/^BASE03=/ {print toupper($2)}' "$tf")"
        t_b02_rgb="$(awk -F'"' '/^BASE02=/ {h=substr($2,2); printf "%d;%d;%d", strtonum("0x" substr(h,1,2)), strtonum("0x" substr(h,3,2)), strtonum("0x" substr(h,5,2))}' "$tf" 2>/dev/null || python3 -c "h='$(awk -F'\"' '/^BASE02=/ {print $2}' "$tf")'[1:]; print(f'{int(h[0:2],16)};{int(h[2:4],16)};{int(h[4:6],16)}')")"
        t_blu_rgb="$(awk -F'"' '/^BLUE=/ {h=substr($2,2); printf "%d;%d;%d", strtonum("0x" substr(h,1,2)), strtonum("0x" substr(h,3,2)), strtonum("0x" substr(h,5,2))}' "$tf" 2>/dev/null || python3 -c "h='$(awk -F'\"' '/^BLUE=/ {print $2}' "$tf")'[1:]; print(f'{int(h[0:2],16)};{int(h[2:4],16)};{int(h[4:6],16)}')")"
        chk_out="$(HOME="$TWOFILE_DIR/empty" XDG_CONFIG_HOME="/nonexistent" HOME_SETTINGS_THEME_FILE="" HOME_SETTINGS_THEME="$t_id" COLORTERM="truecolor" PATH="/usr/bin:/bin" "$BASH" -c "
            set -euo pipefail
            source '$TWOFILE_DIR/.bashrc-addendum'
            printf '%s|%s|%s|%s|%s\n' \"\${HOME_SETTINGS_THEME_MODE:-}\" \"\${BAT_THEME:-}\" \"\${FZF_DEFAULT_OPTS:-}\" \"\${LS_COLORS:-}\" \"\${PS1:-}\"
        ")"
        if [[ "$chk_out" != "$t_mode|$t_bat|"* ]] || \
           [[ "$chk_out" != *"bg:$t_b03"* ]] || \
           [[ "$chk_out" != *"di=38;2;${t_blu_rgb}:"* ]] || \
           [[ "$chk_out" != *"48;2;${t_b02_rgb}m"* ]]; then
            bash_17_fail="$t_id ($chk_out)"
            break
        fi
    done
    if [ -z "$bash_17_fail" ]; then
        echo "PASS:Standalone copied .bashrc-addendum embeds all 17 built-in themes with 1:1 BAT_THEME, FZF_DEFAULT_OPTS, TrueColor LS_COLORS, and PS1 parity"
    else
        echo "FAIL:Standalone .bashrc-addendum 17-theme parity:Mismatch on $bash_17_fail"
    fi

    # Test HOME_SETTINGS_THEME_FILE / BAT_THEME_NAME injection safety, unquoted #RRGGBB values, subshell isolation, and bidirectional TrueColor LS_COLORS guard
    PWN_FILE="$TWOFILE_DIR/pwned-by-theme"
    PWN_FILE2="$TWOFILE_DIR/pwned-by-bat-env"
    EVIL_THEME="$TWOFILE_DIR/evil.theme"
    cat > "$EVIL_THEME" <<EOF
THEME_ID="evil-bash"
THEME_LABEL="\$(touch '$PWN_FILE')"
BAT_THEME_NAME="\$(touch '$PWN_FILE2')"
BASE03="\$(touch '$PWN_FILE')"
BASE02=#112233
BLUE=#445566 # inline comment
EOF
    sec_and_guard_out="$(HOME="$TWOFILE_DIR/sec-home" XDG_CONFIG_HOME="/nonexistent" COLORTERM="truecolor" PATH="/usr/bin:/bin" "$BASH" -c "
        set -euo pipefail
        HOME_SETTINGS_THEME_FILE='$EVIL_THEME' source '$TWOFILE_DIR/.bashrc-addendum'
        tc_ls=\"\${LS_COLORS:-}\"
        tc_ps1=\"\${PS1:-}\"
        tc_fzf=\"\${FZF_DEFAULT_OPTS:-}\"
        COLORTERM='' _solarized_bash_prompt
        downgraded_ls=\"\${LS_COLORS:-}\"
        COLORTERM='truecolor' _solarized_bash_prompt
        restored_ls=\"\${LS_COLORS:-}\"
        sub_mode=\"\$(HOME='$TWOFILE_DIR/unconfigured-sub' XDG_CONFIG_HOME='/nonexistent' HOME_SETTINGS_THEME_FILE='' HOME_SETTINGS_THEME='' HOME_SETTINGS_THEME_MODE='light' _HS_LOADED_THEME='solarized-light' '$BASH' -c \"source '$TWOFILE_DIR/.bashrc-addendum' && printf '%s' \\\${HOME_SETTINGS_THEME_MODE:-<unset>}\")\"
        printf 'TC_LS=%s|TC_PS1=%s|FZF=%s|DG_LS=%s|RS_LS=%s|SUB_MODE=%s\n' \"\$tc_ls\" \"\$tc_ps1\" \"\$tc_fzf\" \"\$downgraded_ls\" \"\$restored_ls\" \"\$sub_mode\"
    ")"
    mkdir -p "$TWOFILE_DIR/sec2-home/.config/themes"
    cp "$EVIL_THEME" "$TWOFILE_DIR/sec2-home/.config/themes/evil-bash.theme"
    bat_inj_out="$(HOME="$TWOFILE_DIR/sec2-home" XDG_CONFIG_HOME="$TWOFILE_DIR/sec2-home/.config" COLORTERM="truecolor" PATH="/usr/bin:/bin" "$BASH" -c "
        set -euo pipefail
        source '$TWOFILE_DIR/.bashrc-addendum'
        theme --set evil-bash --no-live >/dev/null
    " && HOME="$TWOFILE_DIR/sec2-home" XDG_CONFIG_HOME="$TWOFILE_DIR/sec2-home/.config" COLORTERM="truecolor" PATH="/usr/bin:/bin" "$BASH" -c "
        set -euo pipefail
        source '$TWOFILE_DIR/.bashrc-addendum'
        printf '%s\n' \"\${BAT_THEME:-}\"
    ")"
    linux_ls_out="$(HOME="$TWOFILE_DIR/sec-home" XDG_CONFIG_HOME="/nonexistent" HOME_SETTINGS_THEME="nord" TERM="linux" COLORTERM="truecolor" PATH="/usr/bin:/bin" "$BASH" -c "
        set -euo pipefail
        source '$TWOFILE_DIR/.bashrc-addendum'
        printf '%s\n' \"\${LS_COLORS:-}\"
    ")"
    pref_th_out="$(HOME="$TWOFILE_DIR/unconfigured-sub" XDG_CONFIG_HOME="/nonexistent" HOME_SETTINGS_THEME_FILE="" HOME_SETTINGS_THEME="" COLORTERM="truecolor" PATH="/usr/bin:/bin" "$BASH" -c "
        set -euo pipefail
        HOME_SETTINGS_THEME='nord' source '$TWOFILE_DIR/.bashrc-addendum'
        _solarized_bash_prompt
        printf '%s:%s\n' \"\${HOME_SETTINGS_THEME:-<unset>}\" \"\${BAT_THEME:-<unset>}\"
    ")"
    dg_ls_only="${sec_and_guard_out#*DG_LS=}"
    dg_ls_only="${dg_ls_only%%|RS_LS=*}"
    if [ ! -e "$PWN_FILE" ] && [ ! -e "$PWN_FILE2" ] && \
       [ "$bat_inj_out" = "Evil-Bash-TrueColor" ] && \
       [ "$pref_th_out" = "nord:Nord-TrueColor" ] && \
       [[ "$sec_and_guard_out" == *"TC_LS="*"di=38;2;68;85;102:"* ]] && \
       [[ "$sec_and_guard_out" == *"48;2;17;34;51m"* ]] && \
       [[ "$sec_and_guard_out" == *"bg+:#112233"* ]] && \
       [[ "$dg_ls_only" == *"di=34:"* ]] && \
       [[ "$dg_ls_only" != *"38;2;"* ]] && \
       [[ "$sec_and_guard_out" == *"RS_LS="*"di=38;2;68;85;102:"* ]] && \
       [[ "$sec_and_guard_out" == *"SUB_MODE=<unset>"* ]] && \
       [[ "$linux_ls_out" == *"di=34:"* ]] && [[ "$linux_ls_out" != *"38;2;"* ]]; then
        echo "PASS:Standalone .bashrc-addendum neutralizes first- and second-order theme-env.sh injection, preserves unquoted #RRGGBB values, isolates subshell state, and downgrades/restores TrueColor LS_COLORS"
    else
        echo "FAIL:HOME_SETTINGS_THEME_FILE/BAT_THEME_NAME security & LS_COLORS guard:pwn1=$([ -e "$PWN_FILE" ] && echo yes || echo no) pwn2=$([ -e "$PWN_FILE2" ] && echo yes || echo no) bat='$bat_inj_out' pref='$pref_th_out' out=$sec_and_guard_out linux=$linux_ls_out"
    fi

    # Test standalone theme() fallback when bin/theme is absent, Vim :Theme cross-pane sync, --create, fzf --preview, same-second custom .conf reload, partial-write guard, and state-deletion reset
    cp "$SCRIPT_DIR/dotfiles/.vimrc" "$TWOFILE_DIR/.vimrc"
    VIM_BIN_PATH="$(type -P vim || true)"
    SA_TH_HOME="$TWOFILE_DIR/sa-home"
    mkdir -p "$SA_TH_HOME/.config/themes" "$TWOFILE_DIR/mock-fzf-bin"
    cat > "$TWOFILE_DIR/mock-fzf-bin/fzf" <<'MOCKFZF'
#!/bin/sh
prev_cmd=""
for arg in "$@"; do
    case "$arg" in
        --preview=*) prev_cmd="${arg#--preview=}" ;;
    esac
done
stdin_data="$(cat)"
if [ -n "$prev_cmd" ]; then
    eval_cmd="$(printf '%s' "$prev_cmd" | sed "s/{1}/'nord'/g")"
    prev_out="$(/bin/sh -c "$eval_cmd" 2>&1 || true)"
    printf '%s\n' "$prev_out" > "${MOCK_FZF_PREVIEW_OUT:?}"
fi
printf '%s\n' "$stdin_data" | grep '^kanagawa-wave ' | head -n 1
MOCKFZF
    chmod +x "$TWOFILE_DIR/mock-fzf-bin/fzf"
    cat > "$SA_TH_HOME/.config/themes/aurora-borealis.conf" <<'EOF'
export THEME_ID='aurora-borealis'
THEME_LABEL='Aurora Borealis'
THEME_MODE='dark'
BASE03='#0B132B'
BASE02='#1C2541'
BLUE='#5BC0BE'
EOF
    sa_theme_out="$(HOME="$SA_TH_HOME" XDG_CONFIG_HOME="$SA_TH_HOME/.config" COLORTERM="truecolor" VIM_BIN_PATH="$VIM_BIN_PATH" MOCK_FZF_PREVIEW_OUT="$TWOFILE_DIR/fzf-prev.txt" PATH="/usr/bin:/bin" "$BASH" -c "
        set -euo pipefail
        source '$TWOFILE_DIR/.bashrc-addendum'
        shopt -s failglob
        list_cnt=\"\$(theme --list --plain | wc -l | tr -d ' ')\"
        theme --set nord --no-live >/dev/null
        _solarized_bash_prompt
        fg_preserved=0
        if shopt -q failglob && ! shopt -q nullglob; then
            fg_preserved=1
        fi
        shopt -u failglob
        cur1=\"\$(theme --current)\"
        nontty_list=\"\$(theme </dev/null)\"
        theme --preview=gruvbox-dark >/dev/null
        theme --env=solarized-light >/dev/null
        theme --dry-run=halloween >/dev/null
        cur_after_ro=\"\${HOME_SETTINGS_THEME:-}\"
        bad_rc=0
        theme --set no-such-theme-xyz >/dev/null 2>&1 || bad_rc=\$?
        extra_rc=0
        theme nord gruvbox-dark >/dev/null 2>&1 || extra_rc=\$?
        cur_after_bad=\"\${HOME_SETTINGS_THEME:-}\"
        export HOME_SETTINGS_THEME_FILE='$SA_TH_HOME/.config/themes/aurora-borealis.conf'
        _solarized_bash_prompt
        tfile_before=\"\${HOME_SETTINGS_THEME:-}\"
        theme --set nord --no-live >/dev/null
        tfile_override=\"\${HOME_SETTINGS_THEME:-}:\${HOME_SETTINGS_THEME_FILE:-<unset>}\"
        _solarized_vcs_build_pr_url 'https://stash.example.com/scm/core_plat/gateway.git' '42' 'bitbucket-server' >/dev/null
        bb_pr_url=\"\$REPLY\"
        # Cross-pane standalone Vim :Theme -> Bash prompt sync
        vim_sync='skipped'
        if [ -n \"\${VIM_BIN_PATH:-}\" ]; then
            \"\$VIM_BIN_PATH\" -u '$TWOFILE_DIR/.vimrc' -N -es -c 'Theme gruvbox-dark' -c 'qall!' </dev/null >/dev/null 2>&1
            _solarized_bash_prompt
            vim_sync=\"\${HOME_SETTINGS_THEME:-}:\${BAT_THEME:-}\"
        else
            printf 'gruvbox-dark\n' > '$SA_TH_HOME/.config/home-settings/theme'
            _solarized_bash_prompt
            vim_sync=\"\${HOME_SETTINGS_THEME:-}:\${BAT_THEME:-}\"
        fi
        # Stale complete theme-env.sh fallback when external writer updates theme file
        theme --set nord --no-live >/dev/null
        printf 'catppuccin-mocha\n' > '$SA_TH_HOME/.config/home-settings/theme'
        rm -f '$SA_TH_HOME/.config/home-settings/active-theme.theme'
        _solarized_bash_prompt
        stale_sync=\"\${HOME_SETTINGS_THEME:-}:\${BAT_THEME:-}\"
        # Standalone theme --create / --from / --force & interactive fzf --preview
        created_file=\"\$(theme --create remote-berry --from nord)\"
        dup_rc=0
        theme --create remote-berry >/dev/null 2>&1 || dup_rc=\$?
        theme --create remote-berry --from gruvbox-dark --force >/dev/null
        theme --set remote-berry --no-live >/dev/null
        created_state=\"\${HOME_SETTINGS_THEME:-}:\${BAT_THEME:-}:\${dup_rc}\"
        rm -f \"\$created_file\"
        THEME_FORCE_FZF=1 PATH='$TWOFILE_DIR/mock-fzf-bin':\"\$PATH\" theme --no-live >/dev/null
        fzf_picked=\"\${HOME_SETTINGS_THEME:-}\"
        THEME_HOLIDAY_DATE=2024-02-29 theme --holiday --no-live >/dev/null
        leap_state=\"\${HOME_SETTINGS_THEME:-}\"
        THEME_HOLIDAY_DATE=2026-11-20 theme --holiday --no-live >/dev/null
        tg_state=\"\${HOME_SETTINGS_THEME:-}:\${_HS_PROMPT_OS_ICON:-}\"
        THEME_HOLIDAY_DATE=2026-12-28 theme --holiday --no-live >/dev/null
        ny_state=\"\${HOME_SETTINGS_THEME:-}:\${_HS_PROMPT_OS_ICON:-}\"
        bad_feb_rc=0
        THEME_HOLIDAY_DATE=2026-02-29 theme --holiday --no-live >/dev/null 2>&1 || bad_feb_rc=\$?
        bad_apr_rc=0
        THEME_HOLIDAY_DATE=2026-04-31 theme --holiday --no-live >/dev/null 2>&1 || bad_apr_rc=\$?
        # Read-only XDG_CONFIG_HOME under interactive non-errexit mode must fail with exit 1 without false Applied output or state clobbering
        mkdir -p '$TWOFILE_DIR/ro-xdg'
        chmod 500 '$TWOFILE_DIR/ro-xdg'
        set +e
        ro_set_out=\"\$(XDG_CONFIG_HOME='$TWOFILE_DIR/ro-xdg' theme --set nord --no-live 2>&1)\"
        ro_set_rc=\$?
        ro_create_out=\"\$(HOME_SETTINGS_USER_THEMES_DIR='$TWOFILE_DIR/ro-xdg/themes' theme --create nope-ro 2>&1)\"
        ro_create_rc=\$?
        set -e
        chmod 700 '$TWOFILE_DIR/ro-xdg'
        ro_applied_leak=0
        [[ \"\$ro_set_out\" == *'Applied theme:'* || -n \"\${ro_create_out%%*cannot write*}\" && \"\$ro_create_rc\" -eq 0 ]] && ro_applied_leak=1
        ro_preserved=\"\${HOME_SETTINGS_THEME:-}\"
        # Partial-write guard: corrupt theme-env.sh without _HS_LOADED_THEME footer while changing theme file
        printf 'aurora-borealis\n' > '$SA_TH_HOME/.config/home-settings/theme'
        printf 'export BAT_THEME=\"PARTIAL_CORRUPT\"\n' > '$SA_TH_HOME/.config/home-settings/theme-env.sh'
        rm -f '$SA_TH_HOME/.config/themes/aurora-borealis.conf'
        _solarized_bash_prompt
        partial_bat=\"\${BAT_THEME:-}\"
        # Also verify empty user themes dir under set -u
        empty_list_cnt=\"\$(theme --list --plain | wc -l | tr -d ' ')\"
        # Restore custom theme and apply via standalone theme()
        cat > '$SA_TH_HOME/.config/themes/aurora-borealis.conf' <<'INNER'
THEME_ID='aurora-borealis'
THEME_MODE='dark'
BASE03='#0B132B'
BASE02='#1C2541'
BLUE='#5BC0BE'
INNER
        theme --set aurora-borealis --no-live >/dev/null
        ab_ls1=\"\${LS_COLORS:-}\"
        # Edit custom theme file in place WITHOUT sleep (same-second edit) and verify zero-fork prompt auto-reload
        cat > '$SA_TH_HOME/.config/themes/aurora-borealis.conf' <<'INNER2'
THEME_ID='aurora-borealis'
THEME_MODE='dark'
BASE03='#0B132B'
BASE02='#223344'
BLUE='#11AAEE'
INNER2
        _solarized_bash_prompt
        ab_ls2=\"\${LS_COLORS:-}\"
        ab_ps1=\"\${PS1:-}\"
        COMP_WORDS=(theme aurora); COMP_CWORD=1; _theme_bash_complete
        ab_comp=\"\${COMPREPLY[*]}\"
        # Delete state directory and verify live pane resets to unconfigured Solarized Dark
        rm -rf '$SA_TH_HOME/.config/home-settings'
        _solarized_bash_prompt
        reset_ls=\"\${LS_COLORS:-}\"
        reset_th=\"\${HOME_SETTINGS_THEME:-<unset>}\"
        nontty_has_star=0
        [[ \"\$nontty_list\" == *'* nord'* ]] && nontty_has_star=1
        printf 'CNT=%s/%s|FG=%s|CUR=%s/%s/%s|NONTTY=%s|BAD=%s/%s|TFO=%s/%s|BB=%s|VIMSYNC=%s|STALESYNC=%s|CREATE=%s|FZF=%s|LEAP=%s|TG=%s|NY=%s|BADCAL=%s/%s|RO=%s/%s/%s/%s|PARTIAL=%s|LS1=%s|LS2=%s|PS1=%s|COMP=%s|RESET=%s/%s\n' \"\$list_cnt\" \"\$empty_list_cnt\" \"\$fg_preserved\" \"\$cur1\" \"\$cur_after_ro\" \"\$cur_after_bad\" \"\$nontty_has_star\" \"\$bad_rc\" \"\$extra_rc\" \"\$tfile_before\" \"\$tfile_override\" \"\$bb_pr_url\" \"\$vim_sync\" \"\$stale_sync\" \"\$created_state\" \"\$fzf_picked\" \"\$leap_state\" \"\$tg_state\" \"\$ny_state\" \"\$bad_feb_rc\" \"\$bad_apr_rc\" \"\$ro_set_rc\" \"\$ro_create_rc\" \"\$ro_applied_leak\" \"\$ro_preserved\" \"\$partial_bat\" \"\$ab_ls1\" \"\$ab_ls2\" \"\$ab_ps1\" \"\$ab_comp\" \"\$reset_th\" \"\$reset_ls\"
    ")"
    fzf_prev_content=""
    [ -r "$TWOFILE_DIR/fzf-prev.txt" ] && IFS= read -r -d '' fzf_prev_content < "$TWOFILE_DIR/fzf-prev.txt" || true
    bash4_hits=0
    if grep -Eq '(\$\{[A-Za-z_][A-Za-z0-9_]*(\^\^|,,)\}|declare[[:space:]]+-A|local[[:space:]]+-A|\b(mapfile|readarray)\b)' "$TWOFILE_DIR/.bashrc-addendum"; then
        bash4_hits=1
    fi
    if [ "$bash4_hits" -eq 0 ] && \
       [[ "$sa_theme_out" == *"CNT=18/17|FG=1|CUR=nord/nord/nord|NONTTY=1|BAD=1/1|TFO=aurora-borealis/nord:<unset>|BB=https://stash.example.com/projects/CORE_PLAT/repos/gateway/pull-requests/42|VIMSYNC=gruvbox-dark:Gruvbox-Dark-TrueColor|STALESYNC=catppuccin-mocha:Catppuccin-Mocha-TrueColor|CREATE=remote-berry:Remote-Berry-TrueColor:1|FZF=kanagawa-wave|LEAP=st-patricks|TG=thanksgiving:🦃|NY=new-years:🥂|BADCAL=1/1|RO=1/1/0/new-years|"* ]] && \
       [[ "$fzf_prev_content" == *"Nord (nord)"* ]] && \
       [[ "$sa_theme_out" != *"PARTIAL=PARTIAL_CORRUPT"* ]] && \
       [[ "$sa_theme_out" == *"LS1="*"di=38;2;91;192;190:"* ]] && \
       [[ "$sa_theme_out" == *"LS2="*"di=38;2;17;170;238:"* ]] && \
       [[ "$sa_theme_out" == *"48;2;34;51;68m"* ]] && \
       [[ "$sa_theme_out" == *"COMP=aurora-borealis|"* ]] && \
       [[ "$sa_theme_out" == *"RESET=<unset>/"*"di=34:"* ]]; then
        echo "PASS:Standalone theme() manages all 17 built-in + custom themes (--create/--from/--force, fzf --preview, non-TTY list), syncs cross-pane with Vim :Theme, reloads same-second edits, guards partial/read-only writes, and resets cleanly"
    else
        echo "FAIL:Standalone theme() fallback & cross-pane sync:bash4=$bash4_hits out='$sa_theme_out' fzf_prev='$fzf_prev_content'"
    fi

    # Test conflicted Git merge state (Orange #CB4B16 / ANSI 91 / linux 33 with ~ suffix) and Readline colored-stats
    CONFLICT_REPO="$TWOFILE_DIR/conflict-repo"
    git init -b main "$CONFLICT_REPO" >/dev/null 2>&1
    (
        export HOME="$SA_TH_HOME"
        export XDG_CONFIG_HOME="$SA_TH_HOME/.config"
        cd "$CONFLICT_REPO"
        git config user.email "test@example.com"
        git config user.name "Test User"
        git config commit.gpgsign false
        git remote add origin "https://github.com/octocat/Hello-World.git"
        printf 'clean\n' > a-modified.txt
        printf 'base\n' > z-conflict.txt
        git add a-modified.txt z-conflict.txt && git commit -m "base" >/dev/null 2>&1
        git checkout -q -b side
        printf 'side\n' > z-conflict.txt
        git commit -am "side" >/dev/null 2>&1
        git checkout -q main
        git checkout -q -b feat/conflict-pr
        printf 'ours\n' > z-conflict.txt
        git commit -am "ours" >/dev/null 2>&1
        git config branch.feat/conflict-pr.pr 77
        git merge side >/dev/null 2>&1 || true
        printf 'modified-first\n' > a-modified.txt

        true
        COLORTERM="truecolor" _solarized_bash_prompt
        ps1_conf_tc="$PS1"

        true
        COLORTERM="" TERM="xterm-256color" _solarized_bash_prompt
        ps1_conf_16="$PS1"

        true
        TERM="linux" _solarized_bash_prompt
        ps1_conf_linux="$PS1"

        printf 'set colored-completion-prefix on\n' > "$TWOFILE_DIR/test-inputrc"
        readline_vars="$(INPUTRC="$TWOFILE_DIR/test-inputrc" HOME="$SA_TH_HOME" "$BASH" --norc -i -c "source '$TWOFILE_DIR/.bashrc-addendum'; bind -v" </dev/null 2>/dev/null || true)"

        if [[ "$ps1_conf_tc" == *"38;2;203;75;22m\\]  feat/conflict-pr"* ]] && \
           [[ "$ps1_conf_tc" == *"@\\[\\e[38;2;203;75;22m\\]77\\[\\e]8;;\\a\\]~"* ]] && \
           [[ "$ps1_conf_16" == *"\\e[91m\\]  feat/conflict-pr"* ]] && \
           [[ "$ps1_conf_16" == *"~"* ]] && \
           [[ "$ps1_conf_linux" == *"\\e[33m\\]feat/conflict-pr\\[\\e[90m\\]@\\[\\e[33m\\]77~"* ]] && \
           { ! grep -Fq "colored-stats" <<< "$readline_vars" || grep -Fq "set colored-stats on" <<< "$readline_vars"; } && \
           ! grep -Fq "set colored-completion-prefix on" <<< "$readline_vars"; then
            echo "PASS:Standalone _solarized_bash_prompt renders conflicted Git merges in Orange (#CB4B16 / ANSI 91 / VT 33) with ~ suffix even alongside modified files, and interactive Bash enables Readline colored-stats while forcing colored-completion-prefix off"
        else
            echo "FAIL:Conflicted Git prompt & Readline colored-stats:tc='$ps1_conf_tc' c16='$ps1_conf_16' linux='$ps1_conf_linux' rl='$readline_vars'"
        fi
    )
) > "$STANDALONE_HOME/results.txt"

parse_subshell_results < "$STANDALONE_HOME/results.txt"
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
