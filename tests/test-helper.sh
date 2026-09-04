#!/bin/bash
# Shared test assertion library for home-settings test suites.

TESTS_PASSED=0
TESTS_FAILED=0

COLOR_PASS="\033[32m"
COLOR_FAIL="\033[31m"
COLOR_RESET="\033[0m"

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
