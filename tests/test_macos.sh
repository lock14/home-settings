#!/usr/bin/env bash
# Test suite for macOS setup scripts, Brewfile, and terminal configurations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "  \033[32m✔ PASS:\033[0m $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "  \033[31m✘ FAIL:\033[0m $1"
    echo "    $2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo "========================================"
echo "Running macOS Setup & Terminal Tests"
echo "========================================"

# Test 1: Bash syntax checks
echo -e "\n[1/6] Checking macOS script syntax with 'bash -n'..."
for f in "$SCRIPT_DIR/macos/macos_setup.sh" "$SCRIPT_DIR/macos/terminal-setup.sh"; do
    if [ -f "$f" ]; then
        if bash -n "$f"; then
            pass "Syntax valid: $(basename "$f")"
        else
            fail "Syntax check failed: $(basename "$f")" "bash -n returned non-zero"
        fi
    else
        fail "File missing: $(basename "$f")" "Expected file to exist"
    fi
done

# Test 2: Help flag & Argument validation in macos_setup.sh
echo -e "\n[2/6] Testing macos_setup.sh CLI arguments..."
# Help flag
if "$SCRIPT_DIR/macos/macos_setup.sh" -h | grep -q "usage: macos_setup.sh"; then
    pass "macos_setup.sh -h displays usage"
else
    fail "macos_setup.sh -h" "Expected usage output"
fi

if "$SCRIPT_DIR/macos/macos_setup.sh" --help | grep -q "usage: macos_setup.sh"; then
    pass "macos_setup.sh --help displays usage"
else
    fail "macos_setup.sh --help" "Expected usage output"
fi

# Invalid JDK
if "$SCRIPT_DIR/macos/macos_setup.sh" -j invalid-jdk 2>/dev/null; then
    fail "Invalid JDK validation" "Script should have rejected invalid-jdk"
else
    pass "Invalid JDK correctly rejected"
fi

# Missing JDK argument
if "$SCRIPT_DIR/macos/macos_setup.sh" --jdk 2>/dev/null; then
    fail "Missing JDK argument" "Script should have rejected missing argument for --jdk"
else
    pass "Missing argument for --jdk correctly rejected"
fi

# Invalid IDE
if "$SCRIPT_DIR/macos/macos_setup.sh" -i invalid-ide 2>/dev/null; then
    fail "Invalid IDE validation" "Script should have rejected invalid-ide"
else
    pass "Invalid IDE correctly rejected"
fi

# Missing IDE argument
if "$SCRIPT_DIR/macos/macos_setup.sh" --ide 2>/dev/null; then
    fail "Missing IDE argument" "Script should have rejected missing argument for --ide"
else
    pass "Missing argument for --ide correctly rejected"
fi

# Unknown flag
if "$SCRIPT_DIR/macos/macos_setup.sh" --unknown-option 2>/dev/null; then
    fail "Unknown option validation" "Script should have rejected unknown option"
else
    pass "Unknown option correctly rejected"
fi

# Test 3: Dry-run execution of macos_setup.sh (testing space and equals long options)
echo -e "\n[3/6] Testing macos_setup.sh dry-run mode and option styles..."
# Space-separated long options
dry_run_space=$("$SCRIPT_DIR/macos/macos_setup.sh" --dry-run --jdk openjdk-17 --ide vscode --iterm2 --ghostty --apps)
if echo "$dry_run_space" | grep -q "openjdk@17" && echo "$dry_run_space" | grep -q "visual-studio-code"; then
    pass "Space-separated long options (--jdk openjdk-17 --ide vscode) parsed correctly"
else
    fail "Space-separated long options" "Failed to parse options in output: $dry_run_space"
fi

# Equals-separated long options
dry_run_equals=$("$SCRIPT_DIR/macos/macos_setup.sh" --dry-run --jdk=openjdk-21 --ide=intellij --iterm2)
if echo "$dry_run_equals" | grep -q "openjdk@21" && echo "$dry_run_equals" | grep -q "intellij-idea-ce"; then
    pass "Equals-separated long options (--jdk=openjdk-21 --ide=intellij) parsed correctly"
else
    fail "Equals-separated long options" "Failed to parse options in output: $dry_run_equals"
fi

# Option terminator (--)
dry_run_terminator=$("$SCRIPT_DIR/macos/macos_setup.sh" --dry-run --jdk openjdk-8 --)
if echo "$dry_run_terminator" | grep -q "openjdk@8"; then
    pass "Option terminator (--) handled cleanly"
else
    fail "Option terminator" "Failed with -- terminator"
fi

# Test 4: Terminal setup execution and file provisioning
echo -e "\n[4/6] Testing terminal-setup.sh file provisioning..."
(
    TEMP_HOME=$(mktemp -d)
    trap 'rm -rf "$TEMP_HOME"' EXIT

    export HOME="$TEMP_HOME"
    export XDG_CONFIG_HOME="$TEMP_HOME/.config"

    # Run terminal setup with all emulators enabled
    "$SCRIPT_DIR/macos/terminal-setup.sh" --all >/dev/null 2>&1

    # Check iTerm2 Dynamic Profile
    iterm_profile="$TEMP_HOME/Library/Application Support/iTerm2/DynamicProfiles/solarized-dark.json"
    if [ -f "$iterm_profile" ]; then
        if grep -q "MesloLGS-NF-Regular" "$iterm_profile" && grep -q "Solarized Dark" "$iterm_profile"; then
            pass "iTerm2 Dynamic Profile created with Solarized Dark & MesloLGS NF"
        else
            fail "iTerm2 profile contents" "Missing expected font/color keys"
        fi
    else
        fail "iTerm2 profile missing" "Expected file at $iterm_profile"
    fi

    # Check Ghostty config
    ghostty_config="$TEMP_HOME/.config/ghostty/config"
    if [ -f "$ghostty_config" ]; then
        if grep -q 'theme = "solarized-dark"' "$ghostty_config" && grep -q 'font-family = "MesloLGS NF"' "$ghostty_config"; then
            pass "Ghostty config created with solarized-dark & MesloLGS NF"
        else
            fail "Ghostty config contents" "Missing expected theme/font directives"
        fi
    else
        fail "Ghostty config missing" "Expected file at $ghostty_config"
    fi
)

# Test 5: Validate Solarized Dark.terminal XML structure
echo -e "\n[5/6] Validating Solarized Dark.terminal XML profile..."
terminal_xml="$SCRIPT_DIR/macos/Solarized Dark.terminal"
if [ -f "$terminal_xml" ]; then
    if grep -q "<plist version=\"1.0\">" "$terminal_xml" && grep -q "Solarized Dark" "$terminal_xml"; then
        pass "Solarized Dark.terminal is valid XML plist"
    else
        fail "Solarized Dark.terminal content" "Invalid or incomplete plist structure"
    fi
else
    fail "Solarized Dark.terminal missing" "Expected file at $terminal_xml"
fi

# Test 6: Validate Brewfile contents
echo -e "\n[6/6] Validating Brewfile package definitions..."
brewfile="$SCRIPT_DIR/macos/Brewfile"
if [ -f "$brewfile" ]; then
    required_packages=("git" "zsh" "fzf" "gh" "kubectl" "helm" "shellcheck" "yamllint" "go" "maven")
    missing_pkgs=0
    for pkg in "${required_packages[@]}"; do
        if ! grep -qE "brew \"$pkg\"" "$brewfile"; then
            echo "Missing brew package: $pkg"
            missing_pkgs=$((missing_pkgs + 1))
        fi
    done
    if [ "$missing_pkgs" -eq 0 ]; then
        pass "Brewfile contains all required CLI packages"
    else
        fail "Brewfile validation" "$missing_pkgs required packages missing from Brewfile"
    fi
else
    fail "Brewfile missing" "Expected file at $brewfile"
fi

echo -e "\n========================================"
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
