#!/usr/bin/env bash
# Test suite for modular system setup, distro adapters, and master setup orchestrator (LTS Java 17, 21)

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
echo "Running System & Distro Setup Tests"
echo "========================================"

# Test 1: Bash syntax checks
echo -e "\n[1/5] Checking syntax with 'bash -n'..."
SCRIPTS_TO_TEST=(
    "$SCRIPT_DIR/setup.sh"
    "$SCRIPT_DIR/system/system-setup.sh"
    "$SCRIPT_DIR/system/snap-packages.sh"
    "$SCRIPT_DIR/system/java-common.sh"
    "$SCRIPT_DIR/ubuntu/ubuntu_18+_setup.sh"
    "$SCRIPT_DIR/ubuntu/os-packages.sh"
    "$SCRIPT_DIR/ubuntu/install-chrome.sh"
    "$SCRIPT_DIR/ubuntu/install-jdk.sh"
    "$SCRIPT_DIR/ubuntu/install-jdk"
    "$SCRIPT_DIR/ubuntu/bin/switch-java-version"
    "$SCRIPT_DIR/fedora/fedora_30+_setup.sh"
    "$SCRIPT_DIR/fedora/fedora_presteps.sh"
    "$SCRIPT_DIR/fedora/os-packages.sh"
    "$SCRIPT_DIR/fedora/install-chrome.sh"
    "$SCRIPT_DIR/fedora/install-jdk.sh"
    "$SCRIPT_DIR/fedora/bin/change-java-version"
    "$SCRIPT_DIR/fedora/bin/switch-java-version"
    "$SCRIPT_DIR/common-bin/switch-java-version"
)

for f in "${SCRIPTS_TO_TEST[@]}"; do
    if bash -n "$f"; then
        pass "Syntax valid: $(basename "$f")"
    else
        fail "Syntax check failed: $(basename "$f")" "bash -n returned non-zero"
    fi
done

# Test 2: CLI Validation on system-setup.sh and Java LTS enforcement
echo -e "\n[2/5] Testing parameter validation in system-setup.sh..."

if "$SCRIPT_DIR/system/system-setup.sh" --help >/dev/null 2>&1; then
    pass "system-setup.sh --help exits cleanly"
else
    fail "system-setup.sh --help" "Expected exit code 0"
fi

if output=$("$SCRIPT_DIR/system/system-setup.sh" --os unsupported_distro 2>&1); then
    fail "system-setup.sh invalid OS" "Expected error on invalid OS, got success: $output"
else
    pass "system-setup.sh rejects invalid OS"
fi

# Reject EOL Java versions
if output=$("$SCRIPT_DIR/system/system-setup.sh" --os ubuntu --jdk 8 2>&1); then
    fail "system-setup.sh EOL JDK 8" "Expected error on EOL JDK 8, got success: $output"
else
    if [[ "$output" == *"End-of-Life"* ]] || [[ "$output" == *"EOL"* ]]; then
        pass "system-setup.sh rejects EOL Java 8"
    else
        fail "system-setup.sh EOL Java 8 message" "Expected EOL message, got: $output"
    fi
fi

if output=$("$SCRIPT_DIR/system/system-setup.sh" --os ubuntu --jdk openjdk-11 2>&1); then
    fail "system-setup.sh EOL JDK 11" "Expected error on EOL JDK 11, got success: $output"
else
    if [[ "$output" == *"End-of-Life"* ]] || [[ "$output" == *"EOL"* ]]; then
        pass "system-setup.sh rejects EOL Java 11"
    else
        fail "system-setup.sh EOL Java 11 message" "Expected EOL message, got: $output"
    fi
fi

if output=$("$SCRIPT_DIR/system/system-setup.sh" --os ubuntu --jdk 999 2>&1); then
    fail "system-setup.sh invalid JDK" "Expected error on invalid JDK, got success: $output"
else
    pass "system-setup.sh rejects invalid JDK version"
fi

if output=$("$SCRIPT_DIR/system/system-setup.sh" --os ubuntu --ide invalid_ide 2>&1); then
    fail "system-setup.sh invalid IDE" "Expected error on invalid IDE, got success: $output"
else
    pass "system-setup.sh rejects invalid IDE"
fi

# Test 3: Dry-run Execution
echo -e "\n[3/5] Testing Dry-run execution..."

if output=$("$SCRIPT_DIR/system/system-setup.sh" --os ubuntu --dry-run 2>&1); then
    if [[ "$output" == *"[DryRun]"* ]] && [[ "$output" == *"OpenJDK 21 (LTS)"* ]]; then
        pass "system-setup.sh --os ubuntu --dry-run defaults to OpenJDK 21 LTS"
    else
        fail "system-setup.sh ubuntu dry-run output" "Missing expected DryRun markers: $output"
    fi
else
    fail "system-setup.sh ubuntu dry-run" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/system/system-setup.sh" --os fedora --jdk 17 --dry-run 2>&1); then
    if [[ "$output" == *"[DryRun]"* ]] && [[ "$output" == *"OpenJDK 17 (LTS)"* ]]; then
        pass "system-setup.sh --os fedora --jdk 17 --dry-run works for Java 17 LTS"
    else
        fail "system-setup.sh fedora dry-run output" "Missing expected DryRun markers: $output"
    fi
else
    fail "system-setup.sh fedora dry-run" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --dry-run 2>&1); then
    if [[ "$output" == *"Mode: DRY RUN"* ]] && [[ "$output" == *"OpenJDK 21 (LTS)"* ]]; then
        pass "setup.sh --dry-run executed successfully with Java 21 LTS default"
    else
        fail "setup.sh dry-run output" "Missing expected output markers: $output"
    fi
else
    fail "setup.sh dry-run" "Command failed: $output"
fi

# Test 4: Common Java switcher validation
echo -e "\n[4/5] Testing common-bin/switch-java-version validation..."

if "$SCRIPT_DIR/common-bin/switch-java-version" -h >/dev/null 2>&1; then
    pass "switch-java-version -h exits cleanly"
else
    fail "switch-java-version -h" "Expected exit code 0"
fi

if output=$("$SCRIPT_DIR/common-bin/switch-java-version" -j 8 2>&1); then
    fail "switch-java-version EOL version" "Expected non-zero exit code on EOL Java 8"
else
    pass "switch-java-version rejects EOL Java 8"
fi

if output=$("$SCRIPT_DIR/common-bin/switch-java-version" -j 11 2>&1); then
    fail "switch-java-version EOL version" "Expected non-zero exit code on EOL Java 11"
else
    pass "switch-java-version rejects EOL Java 11"
fi

if output=$("$SCRIPT_DIR/common-bin/switch-java-version" -j invalid 2>&1); then
    fail "switch-java-version invalid version" "Expected non-zero exit code"
else
    pass "switch-java-version rejects invalid version"
fi

# Test 5: Backward compatibility shims
echo -e "\n[5/5] Testing backward-compatibility shims..."

if output=$("$SCRIPT_DIR/ubuntu/ubuntu_18+_setup.sh" --dry-run 2>&1); then
    if [[ "$output" == *"Target OS : ubuntu"* ]] && [[ "$output" == *"OpenJDK 21 (LTS)"* ]]; then
        pass "ubuntu_18+_setup.sh delegates cleanly to system-setup.sh"
    else
        fail "ubuntu_18+_setup.sh delegation output" "Unexpected output: $output"
    fi
else
    fail "ubuntu_18+_setup.sh delegation" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/fedora/fedora_30+_setup.sh" --dry-run 2>&1); then
    if [[ "$output" == *"Target OS : fedora"* ]] && [[ "$output" == *"OpenJDK 21 (LTS)"* ]]; then
        pass "fedora_30+_setup.sh delegates cleanly to system-setup.sh"
    else
        fail "fedora_30+_setup.sh delegation output" "Unexpected output: $output"
    fi
else
    fail "fedora_30+_setup.sh delegation" "Command failed: $output"
fi

echo -e "\n========================================"
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
