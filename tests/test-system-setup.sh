#!/usr/bin/env bash
# Test suite for unified cross-platform setup engine (Ubuntu, Fedora, macOS, Mise, Java LTS 17/21)

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
echo "Running System & Cross-Platform Engine Tests"
echo "========================================"

# Test 1: Bash syntax checks
echo -e "\n[1/4] Checking syntax with 'bash -n'..."
if bash -n "$SCRIPT_DIR/setup.sh"; then
    pass "Syntax valid: setup.sh"
else
    fail "Syntax check failed: setup.sh" "bash -n returned non-zero"
fi

for f in "$SCRIPT_DIR"/common-bin/*; do
    if [ -f "$f" ]; then
        if bash -n "$f"; then
            pass "Syntax valid: $(basename "$f")"
        else
            fail "Syntax check failed: $(basename "$f")" "bash -n returned non-zero"
        fi
    fi
done

# Test 2: CLI Validation on setup.sh
echo -e "\n[2/4] Testing parameter validation in setup.sh..."

if "$SCRIPT_DIR/setup.sh" --help >/dev/null 2>&1; then
    pass "setup.sh --help exits cleanly"
else
    fail "setup.sh --help" "Expected exit code 0"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os unsupported_distro 2>&1); then
    fail "setup.sh invalid OS" "Expected error on invalid OS, got success: $output"
else
    pass "setup.sh rejects invalid OS"
fi

# Reject EOL Java versions
if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --jdk 8 2>&1); then
    fail "setup.sh EOL JDK 8" "Expected error on EOL JDK 8, got success: $output"
else
    if [[ "$output" == *"End-of-Life"* ]] || [[ "$output" == *"EOL"* ]]; then
        pass "setup.sh rejects EOL Java 8"
    else
        fail "setup.sh EOL Java 8 message" "Expected EOL message, got: $output"
    fi
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --jdk openjdk-11 2>&1); then
    fail "setup.sh EOL JDK 11" "Expected error on EOL JDK 11, got success: $output"
else
    if [[ "$output" == *"End-of-Life"* ]] || [[ "$output" == *"EOL"* ]]; then
        pass "setup.sh rejects EOL Java 11"
    else
        fail "setup.sh EOL Java 11 message" "Expected EOL message, got: $output"
    fi
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --jdk 999 2>&1); then
    fail "setup.sh invalid JDK" "Expected error on invalid JDK, got success: $output"
else
    pass "setup.sh rejects invalid JDK version"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --ide invalid_ide 2>&1); then
    fail "setup.sh invalid IDE" "Expected error on invalid IDE, got success: $output"
else
    pass "setup.sh rejects invalid IDE"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --db invalid_engine 2>&1); then
    fail "setup.sh invalid DB" "Expected error on invalid DB engine, got success: $output"
else
    pass "setup.sh rejects invalid DB engine"
fi

# Test 3: Dry-run Execution across Platforms
echo -e "\n[3/4] Testing Dry-run execution across Ubuntu, Fedora, and macOS..."

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --dry-run 2>&1); then
    if [[ "$output" == *"[DryRun]"* ]] && [[ "$output" == *"Target OS : ubuntu"* ]] && [[ "$output" != *"google-chrome"* ]] && [[ "$output" != *"snap install"* ]] && [[ "$output" == *"postgresql-client"* ]]; then
        pass "setup.sh --os ubuntu --dry-run executes cleanly with client DB tools and skips GUI apps"
    else
        fail "setup.sh ubuntu dry-run output" "Unexpected output: $output"
    fi
else
    fail "setup.sh ubuntu dry-run" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --with-postgres --dry-run 2>&1); then
    if [[ "$output" == *"postgresql postgresql-contrib"* ]]; then
        pass "setup.sh --with-postgres provisions PostgreSQL server and contrib"
    else
        fail "setup.sh with-postgres output" "Missing PostgreSQL server commands: $output"
    fi
else
    fail "setup.sh with-postgres" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --with-mariadb --dry-run 2>&1); then
    if [[ "$output" == *"mariadb-server mariadb-client"* ]]; then
        pass "setup.sh --with-mariadb provisions MariaDB server"
    else
        fail "setup.sh with-mariadb output" "Missing MariaDB server commands: $output"
    fi
else
    fail "setup.sh with-mariadb" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --skip-db --dry-run 2>&1); then
    if [[ "$output" != *"postgresql-client"* ]] && [[ "$output" != *"mariadb-client"* ]]; then
        pass "setup.sh --skip-db skips all database clients and servers"
    else
        fail "setup.sh skip-db output" "Database packages should be skipped: $output"
    fi
else
    fail "setup.sh skip-db" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --with-gui --ide code --dry-run 2>&1); then
    if [[ "$output" == *"google-chrome"* ]] && [[ "$output" == *"snap install code"* ]]; then
        pass "setup.sh --with-gui enables Chrome and desktop applications"
    else
        fail "setup.sh with-gui dry-run output" "Missing expected GUI application commands: $output"
    fi
else
    fail "setup.sh with-gui dry-run" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os fedora --jdk 17 --dry-run 2>&1); then
    if [[ "$output" == *"[DryRun]"* ]] && [[ "$output" == *"Target OS : fedora"* ]] && [[ "$output" == *"Java 17"* ]] && [[ "$output" != *"google-chrome"* ]]; then
        pass "setup.sh --os fedora --jdk 17 --dry-run executes cleanly with Fedora packages (no GUI apps)"
    else
        fail "setup.sh fedora dry-run output" "Missing expected output markers: $output"
    fi
else
    fail "setup.sh fedora dry-run" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os macos --dry-run 2>&1); then
    if [[ "$output" == *"[DryRun]"* ]] && [[ "$output" == *"Target OS : macos"* ]] && [[ "$output" == *"brew install"* ]] && [[ "$output" != *"--cask"* ]]; then
        pass "setup.sh --os macos --dry-run executes cleanly with Homebrew packages (no GUI casks)"
    else
        fail "setup.sh macos dry-run output" "Missing expected output markers: $output"
    fi
else
    fail "setup.sh macos dry-run" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os macos --with-chrome --dry-run 2>&1); then
    if [[ "$output" == *"brew install --cask google-chrome"* ]]; then
        pass "setup.sh --os macos --with-chrome installs Chrome cask"
    else
        fail "setup.sh macos with-chrome output" "Missing Chrome cask: $output"
    fi
else
    fail "setup.sh macos with-chrome" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --bootstrap --dry-run 2>&1); then
    if [[ "$output" == *"Mode      : BOOTSTRAP"* ]] && [[ "$output" == *"[DryRun]"* ]]; then
        pass "setup.sh --bootstrap --dry-run works"
    else
        fail "setup.sh bootstrap dry-run output" "Missing expected bootstrap markers: $output"
    fi
else
    fail "setup.sh bootstrap dry-run" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --dotfiles-only --dry-run 2>&1); then
    if [[ "$output" == *"Skipping System-Level Provisioning"* ]] && [[ "$output" == *"Running User Dotfiles"* ]]; then
        pass "setup.sh --dotfiles-only skips system provisioning"
    else
        fail "setup.sh dotfiles-only output" "Unexpected output: $output"
    fi
else
    fail "setup.sh dotfiles-only" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --uninstall --dry-run 2>&1); then
    if [[ "$output" == *"Uninstalling all home-settings components"* ]] && [[ "$output" == *"[DryRun]"* ]]; then
        pass "setup.sh --uninstall --dry-run works"
    else
        fail "setup.sh uninstall dry-run output" "Missing expected uninstallation output: $output"
    fi
else
    fail "setup.sh uninstall dry-run" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --uninstall-dotfiles --dry-run 2>&1); then
    if [[ "$output" == *"Removing managed dotfile symlinks"* ]]; then
        pass "setup.sh --uninstall-dotfiles --dry-run works"
    else
        fail "setup.sh uninstall-dotfiles dry-run output" "Missing expected output: $output"
    fi
else
    fail "setup.sh uninstall-dotfiles dry-run" "Command failed: $output"
fi

# Test 4: Mise Configuration Validity
echo -e "\n[4/4] Testing .mise.toml toolchain definition..."
if [ -f "$SCRIPT_DIR/.mise.toml" ]; then
    if grep -q 'java = "lts"' "$SCRIPT_DIR/.mise.toml" && grep -q 'node = "lts"' "$SCRIPT_DIR/.mise.toml" && grep -q 'go = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'maven = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'python = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'neovim = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'eza = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'bat = "latest"' "$SCRIPT_DIR/.mise.toml"; then
        pass ".mise.toml defaults to LTS for Java/Node, and latest stable for Go, Python, Maven, Neovim, Eza, Bat"
    else
        fail ".mise.toml definition" "Missing expected tool configurations"
    fi
else
    fail ".mise.toml missing" "Expected .mise.toml at repository root"
fi

echo -e "\n========================================"
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
