#!/bin/bash
# Shared test assertion, sandbox isolation, mock-bin, and headless Neovim library for home-settings.

TESTS_PASSED=0
TESTS_FAILED=0

COLOR_PASS="\033[32m"
COLOR_FAIL="\033[31m"
COLOR_RESET="\033[0m"

if [ -n "${ZSH_VERSION:-}" ]; then
    # shellcheck disable=SC2296
    _HS_HELPER_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    _HS_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Isolate all test suites from any live caller tmux session, IDE RPC socket, runtime socket directory,
# zoxide database, workspace hooks, or active theme exports by default.
unset TMUX TMUX_PANE NVIM_IDE_SOCKET NVIM_IDE_PANE NVIM NVIM_LISTEN_ADDRESS \
      IDE_SESSION IDE_AI_CLI IDE_AI_PANE IDE_INITIAL_ROOT IDE_WORKDIR IDE_MAIN_WIN \
      IDE_LAYOUT_MODE IDE_AI_PARKED IDE_ED_PARKED IDE_TERM_PARKED IDE_CLIENT IDE_NOTIFY \
      _ZO_DATA_DIR IDE_WORKSPACE_DIRS IDE_LINK_RULES \
      HOME_SETTINGS_THEME HOME_SETTINGS_THEME_MODE HOME_SETTINGS_THEME_FILE \
      THEME_NVIM_SOCKET_DIR BAT_THEME _HS_LOADED_THEME _HS_PROMPT_OS_ICON PYTHONPYCACHEPREFIX

_HS_TEST_RUNTIME_DIR="$(mktemp -d /tmp/hs-rt.XXXXXX)"
chmod 700 "$_HS_TEST_RUNTIME_DIR" 2>/dev/null || true
mkdir -p "$_HS_TEST_RUNTIME_DIR/tmp"
export XDG_RUNTIME_DIR="$_HS_TEST_RUNTIME_DIR"
export THEME_TMP_DIR="$_HS_TEST_RUNTIME_DIR/tmp"

# Register an isolated tmux TMPDIR so its server socket and directory are torn down on exit.
register_tmux_tmpdir() {
    local dir
    for dir in "$@"; do
        [ -n "$dir" ] || continue
        if [ -n "${_HS_TEST_RUNTIME_DIR:-}" ] && [ -d "$_HS_TEST_RUNTIME_DIR" ]; then
            printf '%s\n' "$dir" >> "$_HS_TEST_RUNTIME_DIR/.tmux_sockets"
        fi
    done
}

# Register one or more temporary directories to be removed automatically on exit.
register_cleanup_dir() {
    local dir
    for dir in "$@"; do
        [ -n "$dir" ] || continue
        if [ -n "${_HS_TEST_RUNTIME_DIR:-}" ] && [ -d "$_HS_TEST_RUNTIME_DIR" ]; then
            printf '%s\n' "$dir" >> "$_HS_TEST_RUNTIME_DIR/.cleanups"
        fi
    done
}

# Create a temporary directory, register it for automatic cleanup, and print its path.
make_sandbox_dir() {
    local dir
    dir="$(mktemp -d)"
    register_cleanup_dir "$dir"
    printf '%s\n' "$dir"
}

# Create a temporary directory with pre-initialized XDG subdirectories for isolated HOME tests.
make_sandbox_home() {
    local home_dir
    home_dir="$(make_sandbox_dir)"
    mkdir -p "$home_dir/.config" "$home_dir/.cache" "$home_dir/.local/share"
    printf '%s\n' "$home_dir"
}

# Create an isolated TMUX_TMPDIR registered for automatic server shutdown and directory removal.
make_tmux_sandbox_dir() {
    local dir
    dir="$(mktemp -d /tmp/hs-tmux.XXXXXX)"
    chmod 700 "$dir" 2>/dev/null || true
    register_tmux_tmpdir "$dir"
    printf '%s\n' "$dir"
}

_hs_cleanup_test_runtime_dir() {
    local reg_entry uid_num
    if [ -n "${_HS_TEST_RUNTIME_DIR:-}" ] && [ -d "$_HS_TEST_RUNTIME_DIR" ]; then
        if [ -f "$_HS_TEST_RUNTIME_DIR/.tmux_sockets" ]; then
            uid_num="$(id -u)"
            while IFS= read -r reg_entry; do
                [ -n "$reg_entry" ] || continue
                TMUX="" TMUX_PANE="" tmux -S "$reg_entry/tmux-${uid_num}/default" kill-server >/dev/null 2>&1 || true
                rm -rf "$reg_entry" 2>/dev/null || { chmod -R u+w "$reg_entry" 2>/dev/null || true; rm -rf "$reg_entry" 2>/dev/null || true; }
            done < "$_HS_TEST_RUNTIME_DIR/.tmux_sockets"
        fi
        if [ -f "$_HS_TEST_RUNTIME_DIR/.cleanups" ]; then
            while IFS= read -r reg_entry; do
                [ -n "$reg_entry" ] && [ -e "$reg_entry" ] && {
                    rm -rf "$reg_entry" 2>/dev/null || { chmod -R u+w "$reg_entry" 2>/dev/null || true; rm -rf "$reg_entry" 2>/dev/null || true; }
                }
            done < "$_HS_TEST_RUNTIME_DIR/.cleanups"
        fi
        rm -rf "$_HS_TEST_RUNTIME_DIR" 2>/dev/null || true
    fi
}
trap _hs_cleanup_test_runtime_dir EXIT

# Preserve mise data/cache/state paths when individual tests override HOME or XDG_*,
# and disable background Go/gopls telemetry writes into ephemeral XDG_CONFIG_HOME directories.
export MISE_DATA_DIR="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}"
export MISE_CACHE_DIR="${MISE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/mise}"
export MISE_STATE_DIR="${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}"
export GOTELEMETRY="off"
export NVIM_LOG_FILE="${NVIM_LOG_FILE:-/dev/null}"

# Ethan Schoonover Solarized Dark TrueColor ANSI 24-bit Escape Sequences
case "${COLORTERM:-}" in
    truecolor|24bit) ;;
    *) export COLORTERM="truecolor" ;;
esac
SOL_BASE03=$'\033[38;2;0;43;54m'       # #002B36
SOL_BASE02=$'\033[38;2;7;54;66m'       # #073642
SOL_BASE01=$'\033[38;2;88;110;117m'    # #586E75
SOL_BASE00=$'\033[38;2;101;123;131m'   # #657B83
SOL_BASE0=$'\033[38;2;131;148;150m'    # #839496
SOL_BASE1=$'\033[38;2;147;161;161m'    # #93A1A1
SOL_BASE2=$'\033[38;2;238;232;213m'    # #EEE8D5
SOL_BASE3=$'\033[38;2;253;246;227m'    # #FDF6E3

SOL_YELLOW=$'\033[38;2;181;137;0m'     # #B58900
SOL_ORANGE=$'\033[38;2;203;75;22m'     # #CB4B16
SOL_RED=$'\033[38;2;220;50;47m'        # #DC322F
SOL_MAGENTA=$'\033[38;2;211;54;130m'   # #D33682
SOL_VIOLET=$'\033[38;2;108;113;196m'   # #6C71C4
SOL_BLUE=$'\033[38;2;38;139;210m'      # #268BD2
SOL_CYAN=$'\033[38;2;42;161;152m'      # #2AA198
SOL_GREEN=$'\033[38;2;133;153;0m'      # #859900
SOL_RESET=$'\033[0m'

export SOL_BASE03 SOL_BASE02 SOL_BASE01 SOL_BASE00 SOL_BASE0 SOL_BASE1 SOL_BASE2 SOL_BASE3
export SOL_YELLOW SOL_ORANGE SOL_RED SOL_MAGENTA SOL_VIOLET SOL_BLUE SOL_CYAN SOL_GREEN SOL_RESET

pass() {
    printf '  %b✔ PASS:%b %s\n' "$COLOR_PASS" "$COLOR_RESET" "$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    printf '  %b✘ FAIL:%b %s\n' "$COLOR_FAIL" "$COLOR_RESET" "$1"
    if [ $# -ge 2 ] && [ -n "$2" ]; then
        printf '    %s\n' "$2"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local desc="$3"

    if [ "$expected" = "$actual" ]; then
        pass "$desc"
    else
        fail "$desc" "Expected '$expected', got '$actual'"
    fi
}

assert_match() {
    local pattern="$1"
    local string="$2"
    local desc="$3"

    if [[ "$string" == *"$pattern"* ]]; then
        pass "$desc"
    else
        fail "$desc" "Expected string to contain '$pattern', got: $string"
    fi
}

assert_file() {
    local path="$1"
    local desc="${2:-File exists: $path}"

    if [ -f "$path" ]; then
        pass "$desc"
    else
        fail "$desc" "Expected file to exist at: $path"
    fi
}

assert_symlink() {
    local path="$1"
    local target="${2:-}"
    local desc="${3:-Symlink exists: $path}"

    if [ -L "$path" ]; then
        if [ -n "$target" ]; then
            local actual_target
            actual_target="$(readlink "$path")"
            if [[ "$actual_target" == *"$target"* ]]; then
                pass "$desc"
            else
                fail "$desc" "Symlink points to '$actual_target', expected '$target'"
            fi
        else
            pass "$desc"
        fi
    else
        fail "$desc" "Expected symlink at: $path"
    fi
}

# Assert that a command exits with a non-zero status.
assert_cmd_fails() {
    local desc="$1"
    shift
    local out=""
    if out="$("$@" 2>&1)"; then
        fail "$desc" "Expected non-zero exit status, got success: $out"
    else
        pass "$desc"
    fi
}

# Create an executable mock binary in mock_dir/name with the given body (defaults to exit 0).
write_mock_bin() {
    local mock_dir="$1"
    local bin_name="$2"
    local body="${3:-exit 0}"
    mkdir -p "$mock_dir"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$mock_dir/$bin_name"
    chmod +x "$mock_dir/$bin_name"
}

# Validate syntax of a Bash, Zsh, or Python 3.9+ script according to extension or shebang.
check_script_syntax() {
    local path="$1"
    [ -f "$path" ] || return 1
    case "$path" in
        *.py)
            python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), filename=sys.argv[1], feature_version=(3, 9))' "$path"
            return $?
            ;;
        *.zsh)
            zsh -n "$path"
            return $?
            ;;
    esac

    local first_line=""
    IFS= read -r first_line < "$path" || first_line=""
    case "$first_line" in
        '#!'*python*)
            python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), filename=sys.argv[1], feature_version=(3, 9))' "$path"
            ;;
        '#!'*zsh*)
            zsh -n "$path"
            ;;
        *)
            bash -n "$path"
            ;;
    esac
}

# Assert that a script passes syntax validation for its language runtime.
assert_script_syntax() {
    local path="$1"
    local label="${2:-$(basename "$path")}"
    if check_script_syntax "$path"; then
        pass "Syntax valid: $label"
    else
        fail "Syntax check failed: $label" "Syntax validator returned non-zero for $path"
    fi
}

_hs_find_bin() {
    local p=""
    if [ -n "${ZSH_VERSION:-}" ]; then
        p="$(whence -p "$1" 2>/dev/null || true)"
    else
        p="$(type -P "$1" 2>/dev/null || true)"
    fi
    if [ -n "$p" ] && [ -f "$p" ] && [ -x "$p" ]; then
        printf '%s' "$p"
    fi
}

_HS_NVIM_BIN="$(_hs_find_bin nvim)"
_HS_TIMEOUT_BIN="$(_hs_find_bin timeout)"

wait_for_nvim_socket() {
    local sock="$1"
    local max_tries="${2:-30}"
    local check_rpc="${3:-0}"
    local tries=0
    local nvim_bin="${NVIM_BIN:-${_HS_NVIM_BIN:-}}"
    [ -z "$nvim_bin" ] && nvim_bin="$(_hs_find_bin nvim)"
    [ -z "$nvim_bin" ] && nvim_bin="nvim"
    local timeout_bin="${_HS_TIMEOUT_BIN:-}"
    [ -z "$timeout_bin" ] && timeout_bin="$(_hs_find_bin timeout)"
    while [ "$tries" -lt "$max_tries" ]; do
        if [ -S "$sock" ]; then
            if [ "$check_rpc" != "1" ]; then
                return 0
            elif [ -n "$timeout_bin" ] && [ "$("$timeout_bin" 5 "$nvim_bin" --headless --server "$sock" --remote-expr "v:vim_did_enter" </dev/null 2>/dev/null || true)" = "1" ]; then
                return 0
            elif [ -z "$timeout_bin" ] && [ "$("$nvim_bin" --headless --server "$sock" --remote-expr "v:vim_did_enter" </dev/null 2>/dev/null || true)" = "1" ]; then
                return 0
            fi
        fi
        sleep 0.05
        tries=$((tries + 1))
    done
    return 1
}

# Run headless Neovim safely with stdin closed (</dev/null), a separate
# trailing -c "qall!" (so Ex/Lua errors in earlier -c commands never leave
# Neovim hanging in its event loop), non-zero exit propagation (`cquit 1`)
# when a `-c "luafile <script>"` command throws an unhandled Lua error,
# and a bounded timeout.
run_nvim_headless() {
    local timeout_sec="${NVIM_HEADLESS_TIMEOUT:-30}"
    local nvim_bin="${NVIM_BIN:-${_HS_NVIM_BIN:-}}"
    [ -z "$nvim_bin" ] && nvim_bin="$(_hs_find_bin nvim)"
    [ -z "$nvim_bin" ] && nvim_bin="nvim"
    local timeout_bin="${_HS_TIMEOUT_BIN:-}"
    [ -z "$timeout_bin" ] && timeout_bin="$(_hs_find_bin timeout)"
    local args=()
    local prev_is_c=0
    local arg script_path escaped_path
    for arg in "$@"; do
        if [ "$prev_is_c" -eq 1 ]; then
            prev_is_c=0
            if [[ "$arg" == "luafile "* ]]; then
                script_path="${arg#luafile }"
                escaped_path="${script_path//\\/\\\\}"
                escaped_path="${escaped_path//\"/\\\"}"
                args+=("lua local ok, err = pcall(dofile, \"${escaped_path}\"); if not ok then io.stderr:write(tostring(err) .. \"\\n\"); vim.cmd(\"cquit 1\") end")
                continue
            fi
        elif [ "$arg" = "-c" ]; then
            prev_is_c=1
        fi
        args+=("$arg")
    done
    if [ -n "$timeout_bin" ]; then
        NVIM_LOG_FILE="${NVIM_LOG_FILE:-/dev/null}" "$timeout_bin" "$timeout_sec" "$nvim_bin" --headless "${args[@]}" -c "qall!" </dev/null
    else
        NVIM_LOG_FILE="${NVIM_LOG_FILE:-/dev/null}" "$nvim_bin" --headless "${args[@]}" -c "qall!" </dev/null
    fi
}

parse_subshell_results() {
    local pass_prefix="${1:-}"
    local fail_prefix="${2:-}"
    local line rest parsed=0
    while IFS= read -r line; do
        if [[ "$line" == PASS:* ]]; then
            pass "${pass_prefix}${line#PASS:}"
            parsed=$((parsed + 1))
        elif [[ "$line" == FAIL:* ]]; then
            rest="${line#FAIL:}"
            fail "${fail_prefix}${rest%%:*}" "${rest#*:}"
            parsed=$((parsed + 1))
        fi
    done
    if [ "$parsed" -eq 0 ]; then
        fail "${fail_prefix}subshell results" "Expected at least one PASS:/FAIL: line from subshell, got 0"
    fi
}

lint_documentation() {
    python3 -B "$_HS_HELPER_DIR/lint/lint_docs.py" "${1:-.}"
}

lint_python_embeds() {
    python3 -B "$_HS_HELPER_DIR/lint/lint_python.py" "${1:-.}"
}

test_summary() {
    _hs_cleanup_test_runtime_dir
    printf '\n========================================\n'
    printf 'Summary: %s passed, %s failed\n' "$TESTS_PASSED" "$TESTS_FAILED"
    printf '========================================\n'

    if [ "$TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
}
