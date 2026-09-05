#!/usr/bin/env bash
# Test suite for unified cross-platform setup engine (Ubuntu, Fedora, macOS, Mise, Java LTS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/tests/test-helper.sh"

echo "========================================"
echo "Running System & Cross-Platform Engine Tests"
echo "========================================"

# Test 1: Bash syntax checks
echo -e "\n[1/5] Checking syntax with 'bash -n'..."
if bash -n "$SCRIPT_DIR/setup.sh"; then
    pass "Syntax valid: setup.sh"
else
    fail "Syntax check failed: setup.sh" "bash -n returned non-zero"
fi

for f in "$SCRIPT_DIR"/bin/*; do
    if [ -f "$f" ]; then
        if bash -n "$f"; then
            pass "Syntax valid: $(basename "$f")"
        else
            fail "Syntax check failed: $(basename "$f")" "bash -n returned non-zero"
        fi
    fi
done

# Test 2: CLI Validation on setup.sh
echo -e "\n[2/5] Testing parameter validation in setup.sh..."

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

if output=$("$SCRIPT_DIR/setup.sh" --os 2>&1); then
    fail "setup.sh missing OS argument" "Expected error on missing OS argument, got success: $output"
else
    pass "setup.sh rejects missing OS argument"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --ide invalid_ide 2>&1); then
    fail "setup.sh invalid IDE" "Expected error on invalid IDE, got success: $output"
else
    pass "setup.sh rejects invalid IDE"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --ide 2>&1); then
    fail "setup.sh missing IDE argument" "Expected error on missing IDE argument, got success: $output"
else
    pass "setup.sh rejects missing IDE argument"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --db invalid_engine 2>&1); then
    fail "setup.sh invalid DB" "Expected error on invalid DB engine, got success: $output"
else
    pass "setup.sh rejects invalid DB engine"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --db 2>&1); then
    fail "setup.sh missing DB argument" "Expected error on missing DB argument, got success: $output"
else
    pass "setup.sh rejects missing DB argument"
fi

# Test 3: Dry-run Execution across Platforms
echo -e "\n[3/5] Testing Dry-run execution across Ubuntu, Fedora, and macOS..."

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
    if [[ "$output" == *"google-chrome"* ]] && [[ "$output" == *"snap install code"* ]] && [[ "$output" == *"snap install ghostty"* ]]; then
        pass "setup.sh --with-gui enables Chrome, Ghostty, and desktop applications"
    else
        fail "setup.sh with-gui dry-run output" "Missing expected GUI application commands: $output"
    fi
else
    fail "setup.sh with-gui dry-run" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os macos --with-ghostty --dry-run 2>&1); then
    if [[ "$output" == *"brew install --cask ghostty"* ]]; then
        pass "setup.sh --os macos --with-ghostty installs Ghostty cask"
    else
        fail "setup.sh macos with-ghostty output" "Missing Ghostty cask: $output"
    fi
else
    fail "setup.sh macos with-ghostty" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os fedora --with-ghostty --dry-run 2>&1); then
    if [[ "$output" == *"copr enable scottames/ghostty"* ]] && [[ "$output" == *"install ghostty"* ]]; then
        pass "setup.sh --os fedora --with-ghostty enables COPR and installs Ghostty"
    else
        fail "setup.sh fedora with-ghostty output" "Missing Ghostty Fedora commands: $output"
    fi
else
    fail "setup.sh fedora with-ghostty" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os fedora --dry-run 2>&1); then
    if [[ "$output" == *"[DryRun]"* ]] && [[ "$output" == *"Target OS : fedora"* ]] && [[ "$output" != *"google-chrome"* ]] && [[ "$output" != *"install ghostty"* ]]; then
        pass "setup.sh --os fedora --dry-run executes cleanly with Fedora packages (no GUI apps)"
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
    if [[ "$output" == *"Removing managed dotfile symlinks"* ]] && [[ "$output" == *"Dotfile symlinks uninstalled"* ]]; then
        pass "setup.sh --uninstall-dotfiles --dry-run works"
    else
        fail "setup.sh uninstall-dotfiles dry-run output" "Missing expected output: $output"
    fi
else
    fail "setup.sh uninstall-dotfiles dry-run" "Command failed: $output"
fi

TEMP_UNINSTALL_HOME=$(mktemp -d)
mkdir -p "$TEMP_UNINSTALL_HOME/.config/mise"
ln -s "$SCRIPT_DIR/.mise.toml" "$TEMP_UNINSTALL_HOME/.config/mise/config.toml"
dry_out=$(HOME="$TEMP_UNINSTALL_HOME" XDG_CONFIG_HOME="$TEMP_UNINSTALL_HOME/.config" "$SCRIPT_DIR/setup.sh" --uninstall-dotfiles --dry-run 2>&1)
if [[ "$dry_out" == *"mise/config.toml"* ]]; then
    pass "setup.sh --uninstall-dotfiles cleans ~/.config/mise/config.toml symlink"
else
    fail "setup.sh uninstall-dotfiles mise cleanup" "Expected mise/config.toml in dry-run output: $dry_out"
fi
rm -rf "$TEMP_UNINSTALL_HOME"

if output=$("$SCRIPT_DIR/setup.sh" --uninstall-bin --dry-run 2>&1); then
    if [[ "$output" == *"Removing bin utilities"* ]] && [[ "$output" == *"User binaries uninstalled"* ]]; then
        pass "setup.sh --uninstall-bin --dry-run works"
    else
        fail "setup.sh uninstall-bin dry-run output" "Missing expected output: $output"
    fi
else
    fail "setup.sh uninstall-bin dry-run" "Command failed: $output"
fi

TEMP_BIN_HOME=$(mktemp -d)
mkdir -p "$TEMP_BIN_HOME/.local/bin"
ln -s "/usr/bin/fdfind" "$TEMP_BIN_HOME/.local/bin/fd"
bin_dry_out=$(HOME="$TEMP_BIN_HOME" "$SCRIPT_DIR/setup.sh" --uninstall-bin --dry-run 2>&1)
if [[ "$bin_dry_out" == *".local/bin/fd"* ]]; then
    pass "setup.sh --uninstall-bin cleans compatibility shims (fd/bat)"
else
    fail "setup.sh uninstall-bin shim cleanup" "Expected fd shim in dry-run output: $bin_dry_out"
fi
rm -rf "$TEMP_BIN_HOME"

# Test 4: Mise Configuration Validity
echo -e "\n[4/5] Testing .mise.toml toolchain definition..."
if [ -f "$SCRIPT_DIR/.mise.toml" ]; then
    if grep -q 'java = "lts"' "$SCRIPT_DIR/.mise.toml" && grep -q 'node = "lts"' "$SCRIPT_DIR/.mise.toml" && grep -q 'go = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'maven = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'python = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'neovim = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'eza = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'bat = "latest"' "$SCRIPT_DIR/.mise.toml"; then
        pass ".mise.toml defaults to LTS for Java/Node, and latest stable for Go, Python, Maven, Neovim, Eza, Bat"
    else
        fail ".mise.toml definition" "Missing expected tool configurations"
    fi
else
    fail ".mise.toml missing" "Expected .mise.toml at repository root"
fi

# Test 5: Utilities validation (gen-passwd, sum)
echo -e "\n[5/5] Testing standalone utilities edge cases..."
passwd_symbols=$("$SCRIPT_DIR/bin/gen-passwd" -s 32)
if [ "${#passwd_symbols}" -eq 32 ] && [[ ! "$passwd_symbols" =~ [0-9a-zA-Z[:space:]] ]]; then
    pass "gen-passwd -s generates pure symbols without numbers or letters"
else
    fail "gen-passwd -s symbol generation" "Generated unexpected characters: $passwd_symbols"
fi

passwd_upper=$("$SCRIPT_DIR/bin/gen-passwd" -u 32)
if [ "${#passwd_upper}" -eq 32 ] && [[ "$passwd_upper" =~ ^[A-Z]+$ ]]; then
    pass "gen-passwd -u generates only uppercase letters"
else
    fail "gen-passwd -u generation" "Generated unexpected characters: $passwd_upper"
fi

passwd_lower=$("$SCRIPT_DIR/bin/gen-passwd" -l 32)
if [ "${#passwd_lower}" -eq 32 ] && [[ "$passwd_lower" =~ ^[a-z]+$ ]]; then
    pass "gen-passwd -l generates only lowercase letters"
else
    fail "gen-passwd -l generation" "Generated unexpected characters: $passwd_lower"
fi

passwd_nums=$("$SCRIPT_DIR/bin/gen-passwd" -n 32)
if [ "${#passwd_nums}" -eq 32 ] && [[ "$passwd_nums" =~ ^[0-9]+$ ]]; then
    pass "gen-passwd -n generates only digits"
else
    fail "gen-passwd -n generation" "Generated unexpected characters: $passwd_nums"
fi

passwd_sym_num=$("$SCRIPT_DIR/bin/gen-passwd" -s -n 32)
if [ "${#passwd_sym_num}" -eq 32 ] && [[ ! "$passwd_sym_num" =~ [a-zA-Z[:space:]] ]]; then
    pass "gen-passwd -s -n generates symbols and numbers without letters"
else
    fail "gen-passwd -s -n generation" "Generated unexpected characters: $passwd_sym_num"
fi

if ! "$SCRIPT_DIR/bin/gen-passwd" 0 >/dev/null 2>&1; then
    pass "gen-passwd rejects non-positive length"
else
    fail "gen-passwd 0" "Command accepted length 0"
fi

if ! "$SCRIPT_DIR/bin/gen-passwd" abc >/dev/null 2>&1; then
    pass "gen-passwd rejects non-numeric length"
else
    fail "gen-passwd abc" "Command accepted non-numeric length"
fi

TEMP_SUM_DIR=$(mktemp -d)
touch "$TEMP_SUM_DIR/1"
touch "$TEMP_SUM_DIR/10K"
sum_out=$(cd "$TEMP_SUM_DIR" && "$SCRIPT_DIR/bin/sum" 1 2 3)
if [ "$sum_out" = "6" ]; then
    pass "sum correctly treats numeric args as numbers even when matching file exists"
else
    fail "sum numeric file collision" "Expected 6, got $sum_out"
fi

sum_human_out=$(cd "$TEMP_SUM_DIR" && "$SCRIPT_DIR/bin/sum" -H -f '%.0f' 10K 5M)
if [ "$sum_human_out" = "5253120" ]; then
    pass "sum -H correctly sums human-readable suffixes even when matching file exists"
else
    fail "sum human suffix collision" "Expected 5253120, got $sum_human_out"
fi
rm -rf "$TEMP_SUM_DIR"

# Test repeat-until-success
if "$SCRIPT_DIR/bin/repeat-until-success" -n 2 -s 0 true >/dev/null 2>&1; then
    pass "repeat-until-success succeeds immediately when command succeeds"
else
    fail "repeat-until-success true" "Command failed unexpectedly"
fi

if ! "$SCRIPT_DIR/bin/repeat-until-success" -n 2 -s 0 false >/dev/null 2>&1; then
    pass "repeat-until-success exits non-zero when max retries are exceeded"
else
    fail "repeat-until-success false" "Command was expected to fail"
fi

if ! "$SCRIPT_DIR/bin/repeat-until-success" -n 0 -s 0 true >/dev/null 2>&1; then
    pass "repeat-until-success rejects non-positive max attempts"
else
    fail "repeat-until-success -n 0" "Command accepted invalid attempt count"
fi

if ! "$SCRIPT_DIR/bin/repeat-until-success" -n 1 -s -1 true >/dev/null 2>&1; then
    pass "repeat-until-success rejects negative sleep seconds"
else
    fail "repeat-until-success -s -1" "Command accepted negative sleep duration"
fi

# Test mvn-release
if "$SCRIPT_DIR/bin/mvn-release" --help >/dev/null 2>&1; then
    pass "mvn-release --help exits cleanly"
else
    fail "mvn-release --help" "Help output failed"
fi

if ! "$SCRIPT_DIR/bin/mvn-release" invalid_type >/dev/null 2>&1; then
    pass "mvn-release rejects invalid release type"
else
    fail "mvn-release invalid type" "Expected error on invalid release type"
fi

TEMP_MVN_DIR=$(mktemp -d)
mvn_out=$(cd "$TEMP_MVN_DIR" && "$SCRIPT_DIR/bin/mvn-release" 2>&1 || true)
if [[ "$mvn_out" == *"error: must be run inside a git repository"* ]]; then
    pass "mvn-release rejects execution outside git repository"
else
    fail "mvn-release outside git" "Unexpected output: $mvn_out"
fi

(
    cd "$TEMP_MVN_DIR"
    git init -b main >/dev/null 2>&1
    git config user.email "test@example.com"
    git config user.name "Tester"
)
mvn_no_pom=$(cd "$TEMP_MVN_DIR" && "$SCRIPT_DIR/bin/mvn-release" 2>&1 || true)
if [[ "$mvn_no_pom" == *"error: pom.xml not found in current directory"* ]]; then
    pass "mvn-release rejects execution without pom.xml"
else
    fail "mvn-release without pom" "Unexpected output: $mvn_no_pom"
fi

(
    cd "$TEMP_MVN_DIR"
    touch pom.xml
    git add pom.xml
    git commit -m "add pom" >/dev/null 2>&1
    git checkout -b feature-test >/dev/null 2>&1
)
mvn_bad_branch=$(cd "$TEMP_MVN_DIR" && "$SCRIPT_DIR/bin/mvn-release" 2>&1 || true)
if [[ "$mvn_bad_branch" == *"the current branch must be set to"* ]]; then
    pass "mvn-release rejects non-release branches"
else
    fail "mvn-release bad branch" "Unexpected output: $mvn_bad_branch"
fi
rm -rf "$TEMP_MVN_DIR"

test_summary
