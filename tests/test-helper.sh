#!/bin/bash
# Shared test assertion library for home-settings test suites.

TESTS_PASSED=0
TESTS_FAILED=0

COLOR_PASS="\033[32m"
COLOR_FAIL="\033[31m"
COLOR_RESET="\033[0m"

# Ethan Schoonover Solarized Dark TrueColor ANSI 24-bit Escape Sequences
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

export SOL_BASE03 SOL_BASE02 SOL_BASE01 SOL_BASE00 SOL_BASE0 SOL_BASE1 SOL_BASE2 SOL_BASE3
export SOL_YELLOW SOL_ORANGE SOL_RED SOL_MAGENTA SOL_VIOLET SOL_BLUE SOL_CYAN SOL_GREEN

pass() {
    echo -e "  ${COLOR_PASS}✔ PASS:${COLOR_RESET} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "  ${COLOR_FAIL}✘ FAIL:${COLOR_RESET} $1"
    if [ $# -ge 2 ] && [ -n "$2" ]; then
        echo "    $2"
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

test_summary() {
    echo -e "\n========================================"
    echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "========================================"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
}
