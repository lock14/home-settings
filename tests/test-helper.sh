#!/bin/bash
# Shared test assertion library for home-settings test suites.

TESTS_PASSED=0
TESTS_FAILED=0

COLOR_PASS="\033[32m"
COLOR_FAIL="\033[31m"
COLOR_RESET="\033[0m"

# Isolate all test suites from any live caller tmux session by default
unset TMUX TMUX_PANE

# Preserve mise data/cache/state paths when individual tests override HOME or XDG_*
export MISE_DATA_DIR="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}"
export MISE_CACHE_DIR="${MISE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/mise}"
export MISE_STATE_DIR="${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}"

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

wait_for_nvim_socket() {
    local sock="$1"
    local max_tries="${2:-30}"
    local check_rpc="${3:-0}"
    local tries=0
    while [ "$tries" -lt "$max_tries" ]; do
        if [ -S "$sock" ]; then
            if [ "$check_rpc" != "1" ] || nvim --headless --server "$sock" --remote-expr "1" >/dev/null 2>&1; then
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
# Neovim hanging in its event loop), and a bounded timeout.
run_nvim_headless() {
    local timeout_sec="${NVIM_HEADLESS_TIMEOUT:-30}"
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_sec" nvim --headless "$@" -c "qall!" </dev/null
    else
        nvim --headless "$@" -c "qall!" </dev/null
    fi
}

parse_subshell_results() {
    local pass_prefix="${1:-}"
    local fail_prefix="${2:-}"
    local line rest
    while IFS= read -r line; do
        if [[ "$line" == PASS:* ]]; then
            pass "${pass_prefix}${line#PASS:}"
        elif [[ "$line" == FAIL:* ]]; then
            rest="${line#FAIL:}"
            fail "${fail_prefix}${rest%%:*}" "${rest#*:}"
        fi
    done
}

test_summary() {
    printf '\n========================================\n'
    printf 'Summary: %s passed, %s failed\n' "$TESTS_PASSED" "$TESTS_FAILED"
    printf '========================================\n'

    if [ "$TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
}
