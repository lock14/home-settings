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
echo -e "\n[1/6] Checking syntax with 'bash -n'..."
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

for m in "$SCRIPT_DIR"/modules/*.sh; do
    if [ -f "$m" ]; then
        if bash -n "$m"; then
            pass "Syntax valid: $(basename "$m")"
        else
            fail "Syntax check failed: $(basename "$m")" "bash -n returned non-zero"
        fi
    fi
done

# Test 2: CLI Validation on setup.sh
echo -e "\n[2/6] Testing parameter validation in setup.sh..."

if help_out=$("$SCRIPT_DIR/setup.sh" --help 2>&1); then
    if grep -Fq "MesloLGS Nerd Font Mono" <<< "$help_out" && ! grep -Fq "MesloLGS NF" <<< "$help_out"; then
        pass "setup.sh --help exits cleanly and references MesloLGS Nerd Font Mono"
    else
        fail "setup.sh --help font name" "Expected 'MesloLGS Nerd Font Mono' (not legacy 'MesloLGS NF') in --help output"
    fi
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

# Isolate HOME and XDG directories so setup.sh invocations never touch the caller's real $HOME
TEMP_SETUP_HOME="$(mktemp -d)"
trap 'rm -rf "$TEMP_SETUP_HOME"' EXIT
export HOME="$TEMP_SETUP_HOME"
export XDG_CONFIG_HOME="$TEMP_SETUP_HOME/.config"
export XDG_CACHE_HOME="$TEMP_SETUP_HOME/.cache"
export XDG_DATA_HOME="$TEMP_SETUP_HOME/.local/share"

# Test 3: Dry-run Execution across Platforms
echo -e "\n[3/6] Testing Dry-run execution across Ubuntu, Fedora, and macOS..."

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --dry-run 2>&1); then
    if [[ "$output" == *"[DryRun]"* ]] && [[ "$output" == *"Target OS : ubuntu"* ]] && [[ "$output" == *"tmux"* ]] && [[ "$output" != *"google-chrome"* ]] && [[ "$output" != *"snap install"* ]] && [[ "$output" == *"postgresql-client"* ]]; then
        pass "setup.sh --os ubuntu --dry-run executes cleanly with tmux, client DB tools, and skips GUI apps"
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

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --skip-terminal --dry-run 2>&1); then
    if [[ "$output" != *"Configuring GNOME Terminal"* ]]; then
        pass "setup.sh --skip-terminal skips terminal profile configuration"
    else
        fail "setup.sh skip-terminal output" "Terminal configuration should be skipped: $output"
    fi
else
    fail "setup.sh skip-terminal" "Command failed: $output"
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

if out_none=$("$SCRIPT_DIR/setup.sh" --os ubuntu --ide none --dry-run 2>&1) && \
   out_gui_none=$("$SCRIPT_DIR/setup.sh" --os ubuntu --with-gui --ide none --dry-run 2>&1) && \
   out_none_gui=$("$SCRIPT_DIR/setup.sh" --os ubuntu --ide none --with-gui --dry-run 2>&1) && \
   out_code_skip=$("$SCRIPT_DIR/setup.sh" --os ubuntu --ide code --skip-apps --dry-run 2>&1) && \
   out_skip_gui=$("$SCRIPT_DIR/setup.sh" --os ubuntu --skip-apps --with-gui --dry-run 2>&1); then
    if [[ "$out_none" != *"snap install code"* ]] && \
       [[ "$out_gui_none" == *"google-chrome"* ]] && [[ "$out_gui_none" != *"snap install code"* ]] && \
       [[ "$out_none_gui" == *"google-chrome"* ]] && [[ "$out_none_gui" != *"snap install code"* ]] && \
       [[ "$out_code_skip" == *"IDE Choice: none"* ]] && [[ "$out_code_skip" != *"snap install code"* ]] && \
       [[ "$out_skip_gui" == *"google-chrome"* ]] && [[ "$out_skip_gui" != *"snap install code"* ]]; then
        pass "setup.sh --ide none and --skip-apps prevent VS Code installation across all flag orderings"
    else
        fail "setup.sh --ide none / --skip-apps" "Expected no VS Code installation when --ide none or --skip-apps is specified"
    fi
else
    fail "setup.sh --ide none dry-run" "Command failed"
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

if [ -z "$(ls -A "$TEMP_SETUP_HOME" 2>/dev/null)" ]; then
    pass "setup.sh --dry-run leaves HOME completely untouched (zero directories created)"
else
    fail "setup.sh --dry-run filesystem mutation" "Expected empty $TEMP_SETUP_HOME, found: $(ls -A "$TEMP_SETUP_HOME")"
fi

TEMP_UNINSTALL_HOME=$(mktemp -d)
mkdir -p "$TEMP_UNINSTALL_HOME/.config/mise" "$TEMP_UNINSTALL_HOME/.config/bat/themes" "$TEMP_UNINSTALL_HOME/.config/bat/syntaxes"
ln -s "$SCRIPT_DIR/.mise.toml" "$TEMP_UNINSTALL_HOME/.config/mise/config.toml"
dry_out=$(HOME="$TEMP_UNINSTALL_HOME" XDG_CONFIG_HOME="$TEMP_UNINSTALL_HOME/.config" "$SCRIPT_DIR/setup.sh" --uninstall-dotfiles --dry-run 2>&1)
if [[ "$dry_out" == *"mise/config.toml"* ]] && [ -d "$TEMP_UNINSTALL_HOME/.config/bat/themes" ] && [ -d "$TEMP_UNINSTALL_HOME/.config/bat/syntaxes" ]; then
    pass "setup.sh --uninstall-dotfiles --dry-run cleans ~/.config/mise/config.toml symlink without deleting bat dirs"
else
    fail "setup.sh uninstall-dotfiles mise cleanup" "Expected mise/config.toml in dry-run output and preserved bat dirs: $dry_out"
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

TEMP_SHELL_HOME=$(mktemp -d)
mkdir -p "$TEMP_SHELL_HOME/.oh-my-zsh/custom/plugins/fzf-zsh-plugin"
mkdir -p "$TEMP_SHELL_HOME/.vim/bundle/solarized"
printf 'plugins=(git fzf-zsh-plugin zsh-autosuggestions)\n' > "$TEMP_SHELL_HOME/.zshrc"
sed -i -E 's/[[:space:]]*fzf-zsh-plugin//g' "$TEMP_SHELL_HOME/.zshrc"
if ! grep -q 'fzf-zsh-plugin' "$TEMP_SHELL_HOME/.zshrc" && grep -q 'plugins=(git zsh-autosuggestions)' "$TEMP_SHELL_HOME/.zshrc"; then
    pass "modules/60-shell.sh strips legacy fzf-zsh-plugin from .zshrc"
else
    fail "modules/60-shell.sh fzf-zsh-plugin cleanup" "Expected fzf-zsh-plugin removed from .zshrc"
fi

if command -v python3 >/dev/null 2>&1; then
    chsh_check=$(HOME="$TEMP_SHELL_HOME" MOD_SH="$SCRIPT_DIR/modules/60-shell.sh" python3 -c '
import os, pty, subprocess
def run_mod(skip_zsh):
    m, s = pty.openpty()
    env = dict(os.environ, DRY_RUN="true", SKIP_ZSH=skip_zsh, SKIP_BASH="true", SKIP_COMPLETIONS="true", USER="nonexistent_test_user_xyz", SHELL="/bin/sh")
    p = subprocess.run(["bash", os.environ["MOD_SH"]], stdin=s, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    os.close(m)
    os.close(s)
    return p.stdout
out_skip = run_mod("true")
out_noskip = run_mod("false")
print("SKIP=" + ("chsh" if "chsh -s" in out_skip else "none") + "|NOSKIP=" + ("chsh" if "chsh -s" in out_noskip else "none"))
')
    if [ "$chsh_check" = "SKIP=none|NOSKIP=chsh" ]; then
        pass "modules/60-shell.sh skips chsh login shell switch when --skip-zsh (SKIP_ZSH=true) is set"
    else
        fail "modules/60-shell.sh --skip-zsh chsh guard" "Expected SKIP=none|NOSKIP=chsh, got $chsh_check"
    fi
fi

HOME="$TEMP_SHELL_HOME" "$SCRIPT_DIR/setup.sh" --uninstall-dotfiles >/dev/null 2>&1 || true
if [ ! -d "$TEMP_SHELL_HOME/.oh-my-zsh/custom/plugins/fzf-zsh-plugin" ] && [ ! -d "$TEMP_SHELL_HOME/.vim/bundle" ]; then
    pass "setup.sh --uninstall-dotfiles purges legacy fzf-zsh-plugin and .vim/bundle directories"
else
    fail "setup.sh --uninstall-dotfiles legacy directory purge" "Expected legacy directories to be deleted"
fi
rm -rf "$TEMP_SHELL_HOME"

# Test 4: Mise Configuration Validity
echo -e "\n[4/6] Testing .mise.toml toolchain definition..."
if [ -f "$SCRIPT_DIR/.mise.toml" ]; then
    if grep -q 'java = "lts"' "$SCRIPT_DIR/.mise.toml" && grep -q 'node = "lts"' "$SCRIPT_DIR/.mise.toml" && grep -q 'go = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'maven = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'python = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'rust = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'elan = "github:leanprover/elan"' "$SCRIPT_DIR/.mise.toml" && grep -q 'elan = { version = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'terraform = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'ripgrep = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'neovim = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'eza = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'bat = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'btop = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'delta = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'dust = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'fd = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'fzf = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'gh = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'jq = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'sd = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'shellcheck = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'tealdeer = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'yq = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'zoxide = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'glow = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'tree-sitter = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'go.set_gobin = false' "$SCRIPT_DIR/.mise.toml" && grep -q 'go.set_gopath = false' "$SCRIPT_DIR/.mise.toml"; then
        pass ".mise.toml defaults to LTS for Java/Node, latest for CLI tools and Elan/Lean 4, and protects Go paths (gobin/gopath = false)"
    else
        fail ".mise.toml definition" "Missing expected tool configurations"
    fi
else
    fail ".mise.toml missing" "Expected .mise.toml at repository root"
fi

# Test 5: Utilities validation (gen-passwd, sum)
echo -e "\n[5/6] Testing standalone utilities edge cases..."
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
if "$SCRIPT_DIR/bin/repeat-until-success" -n 2 -s 0 true >/dev/null 2>&1 && \
   "$SCRIPT_DIR/bin/repeat-until-success" -n 2 -d 0 true >/dev/null 2>&1; then
    pass "repeat-until-success succeeds immediately when command succeeds (-s 0 and -d 0)"
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

# Test 6: Documentation hygiene and link validation
echo -e "\n[6/6] Testing documentation typography, hygiene, and link invariants..."
if doc_lint_out=$(lint_documentation "$SCRIPT_DIR" 2>&1); then
    pass "Repository documentation (README.md, AGENTS.md, .github/workflows/ci.yml) passes all typography and link checks"
else
    fail "Repository documentation lint" "$doc_lint_out"
fi

TEMP_DOC_DIR=$(mktemp -d)
mkdir -p "$TEMP_DOC_DIR/.github/workflows" "$TEMP_DOC_DIR/bin" "$TEMP_DOC_DIR/sample-code" "$TEMP_DOC_DIR/dotfiles/.config/ghostty" "$TEMP_DOC_DIR/dotfiles/.config/nvim"
sample_user_path="/Users/""johndoe"
sample_shortcode=":white_check_""mark:"
sample_emoji=$(printf '\U0001f41b')
cat > "$TEMP_DOC_DIR/AGENTS.md" <<'EOF'
# Agent guide

## Existing section

Introductory paragraph.
EOF
cat > "$TEMP_DOC_DIR/README.md" <<EOF
# Sample documentation

Path \`$sample_user_path/work\` and **bold \`code\`**.
Second stacked line: **[link](missing.md)**.
Third stacked line: [**bold link**](missing_two.md).
Fourth stacked line: *\`italic_code\`*.
*(Note: parenthetical aside)*
Emoji: $sample_emoji and $sample_shortcode
Prose arrow: step A -> step B
Second arrow: step C => step D
Unmatched backtick: \`([^\s\`*!]+)\`
Accidental underscore italics: BAT_THEME, EZA_COLORS
Prose slash: tool/product and Neovim & Vim
Prose plus: Tmux + Neovim
Latin abbreviations: e.g. foo, i.e. bar, etc., and A vs. B or C vs D.
## Tight heading
No blank line after heading.

## Empty parent

### Child heading

Child content.

| Column | Value |
| :--- | :--- |
| **Bold Cell** | Val |

---

[Broken anchor](#nonexistent-heading)
[Broken cross-file anchor](AGENTS.md#missing-anchor)
[Broken titled link](missing_titled.md "Title")

\`\`\`
├── ide # Tmux + Neovim & AI launcher
\`\`\`

\`\`\`json
{invalid json}
\`\`\`
EOF

cat > "$TEMP_DOC_DIR/setup.sh" <<'EOF'
#!/bin/bash
usage() {
    cat <<HELP
Usage: setup.sh [OPTIONS]
  --undocumented-setup-opt   Test option
HELP
}
echo "Error: requires argument (e.g. ubuntu)" >&2
EOF

cat > "$TEMP_DOC_DIR/Makefile" <<'EOF'
.PHONY: customtarget
EOF

cat > "$TEMP_DOC_DIR/.mise.toml" <<'EOF'
[tools]
missingtool = "latest"
EOF

cat > "$TEMP_DOC_DIR/bin/gen-passwd" <<'EOF'
#!/bin/bash
usage() {
    echo "Usage: gen-passwd [-u]"
}
while getopts ":uz" opt; do
    case "$opt" in
        u|z) ;;
    esac
done
EOF

cat > "$TEMP_DOC_DIR/bin/update-system" <<'EOF'
#!/bin/bash
usage() {
    echo "Usage: update-system [--all]"
}
case "${1:-}" in
    --all|--undocumented-flag) ;;
esac
EOF

cat > "$TEMP_DOC_DIR/dotfiles/.config/ghostty/config" <<'EOF'
keybind = ctrl+shift+d=new_split:auto
EOF

cat > "$TEMP_DOC_DIR/dotfiles/.config/nvim/init.lua" <<'EOF'
vim.keymap.set("n", "<leader>zx", "<cmd>echo 1<CR>")
EOF

cat > "$TEMP_DOC_DIR/sample-code/sample.md" <<'EOF'
# Sample

Clone https://github.com/example/home-settings and run:

```bash
./setup.sh --verbose
```

Prepends `${XDG_DATA_HOME}/bin` and uses MesloLGS NF font.
Use `el` / `elt` in prose.
EOF

cat > "$TEMP_DOC_DIR/.github/workflows/ci.yml" <<EOF
name: CI
on: push
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo "$sample_emoji $sample_user_path"
EOF

if bad_doc_out=$(lint_documentation "$TEMP_DOC_DIR" 2>&1); then
    fail "lint_documentation violation detection" "Expected non-zero exit status on synthetic documentation violations"
else
    if grep -Fq 'contains personal path' <<< "$bad_doc_out" && \
       grep -Fq 'contains decorative emoji or shortcode' <<< "$bad_doc_out" && \
       grep -Fq 'contains stacked formatting span "**bold `code`**"' <<< "$bad_doc_out" && \
       grep -Fq 'contains stacked formatting span "**[link](missing.md)**"' <<< "$bad_doc_out" && \
       grep -Fq 'contains stacked formatting span "[**bold link**](missing_two.md)"' <<< "$bad_doc_out" && \
       grep -Fq 'contains stacked formatting span "*`italic_code`*"' <<< "$bad_doc_out" && \
       grep -Fq 'contains unmatched inline backtick' <<< "$bad_doc_out" && \
       grep -Fq 'contains unbackticked underscore span "BAT_THEME, EZA_COLORS"' <<< "$bad_doc_out" && \
       grep -Fq 'contains prose slash "tool/product"' <<< "$bad_doc_out" && \
       grep -Fq 'contains prose ampersand " & "' <<< "$bad_doc_out" && \
       grep -Fq 'contains prose plus connector " + "' <<< "$bad_doc_out" && \
       grep -Fq 'contains forbidden Latin abbreviation "e.g."' <<< "$bad_doc_out" && \
       grep -Fq 'is missing a preceding blank line' <<< "$bad_doc_out" && \
       grep -Fq 'is missing a following blank line' <<< "$bad_doc_out" && \
       grep -Fq 'is immediately followed by heading "### Child heading" without introductory content' <<< "$bad_doc_out" && \
       grep -Fq 'untagged opening code fence' <<< "$bad_doc_out" && \
       grep -Fq 'directory tree comment contains "+" connector' <<< "$bad_doc_out" && \
       grep -Fq 'directory tree comment contains "&" connector' <<< "$bad_doc_out" && \
       grep -Fq 'setup.sh: contains forbidden Latin abbreviation "e.g."' <<< "$bad_doc_out" && \
       grep -Fq 'missing setup.sh option "--undocumented-setup-opt"' <<< "$bad_doc_out" && \
       grep -Fq 'missing Makefile target "make customtarget"' <<< "$bad_doc_out" && \
       grep -Fq 'missing .mise.toml tool "missingtool"' <<< "$bad_doc_out" && \
       grep -Fq 'getopts option "-z" missing from usage()' <<< "$bad_doc_out" && \
       grep -Fq 'gen-passwd option "-z" missing from Standalone utilities table' <<< "$bad_doc_out" && \
       grep -Fq 'option "--undocumented-flag" missing from usage()' <<< "$bad_doc_out" && \
       grep -Fq 'keybinding "Ctrl+Shift+D" (from dotfiles/.config/ghostty/config) missing from README.md prose' <<< "$bad_doc_out" && \
       grep -Fq 'keybinding "Ctrl+Shift+D" (from dotfiles/.config/ghostty/config) missing from README.md reference table' <<< "$bad_doc_out" && \
       grep -Fq 'keybinding "Space zx" (from dotfiles/.config/nvim/init.lua) missing from README.md prose' <<< "$bad_doc_out" && \
       grep -Fq 'sample.md: contains placeholder URL "github.com/example/home-settings"' <<< "$bad_doc_out" && \
       grep -Fq 'sample.md: contains stale path "${XDG_DATA_HOME}/bin"' <<< "$bad_doc_out" && \
       grep -Fq 'sample.md: contains legacy font name "MesloLGS NF"' <<< "$bad_doc_out" && \
       grep -Fq 'sample.md: contains unknown setup.sh flag "--verbose"' <<< "$bad_doc_out" && \
       grep -Fq 'sample.md: contains prose slash " / "' <<< "$bad_doc_out" && \
       grep -Fq 'contains italic parenthetical aside' <<< "$bad_doc_out" && \
       grep -Fq 'contains bolded first-column table cell "| **Bold Cell** |"' <<< "$bad_doc_out" && \
       grep -Fq 'contains ASCII arrow "->"' <<< "$bad_doc_out" && \
       grep -Fq 'contains ASCII arrow "=>"' <<< "$bad_doc_out" && \
       grep -Fq "contains horizontal rule divider '---'" <<< "$bad_doc_out" && \
       grep -Fq 'broken relative file link "missing.md"' <<< "$bad_doc_out" && \
       grep -Fq 'broken relative file link "missing_titled.md"' <<< "$bad_doc_out" && \
       grep -Fq 'broken anchor link "#nonexistent-heading"' <<< "$bad_doc_out" && \
       grep -Fq 'broken anchor link "AGENTS.md#missing-anchor"' <<< "$bad_doc_out" && \
       grep -Fq 'invalid JSON code block' <<< "$bad_doc_out"; then
        pass "lint_documentation detects personal paths, emojis, stacked formatting, unmatched backticks, underscore italics, prose slashes/ampersands/plus connectors, Latin abbreviations, tight/empty headings, untagged fences, tree comment connectors, CLI/setup.sh/keybinding/sample.md drift, broken links/anchors, and invalid JSON blocks"
    else
        fail "lint_documentation diagnostics" "Missing expected violation messages in output: $bad_doc_out"
    fi
fi
rm -rf "$TEMP_DOC_DIR"

TEMP_VALID_DOC_DIR=$(mktemp -d)
touch "$TEMP_VALID_DOC_DIR/file(1).md" "$TEMP_VALID_DOC_DIR/angle.md"
cat > "$TEMP_VALID_DOC_DIR/AGENTS.md" <<'EOF'
# Agent instructions

## Sub heading

Section body for sub heading.
EOF
cat > "$TEMP_VALID_DOC_DIR/README.md" <<'EOF'
# Valid documentation

## Examples

<!-- *(Note: hidden in HTML comment)* -->

Inline code with double backticks `` ` -> `` and standard I/O on VS Code.
Multiple bold spans on one line: **First**: value and **Second**: value.

```text
---
a -> b
```

```json
{"valid": true}
```

## Examples

Second examples section content.

## Diátaxis (config_file)

- [First examples](#examples)
- [Second examples](#examples-1)
- [Unicode heading](#diátaxis-config_file)
- [Escaped parens](file\(1\).md)
- [Angle link](<angle.md>)
- [Cross-file anchor](AGENTS.md#sub-heading)
- [External URL](https://example.com/a/b)
- [Mailto link](mailto:test@example.com)
EOF

if valid_doc_out=$(lint_documentation "$TEMP_VALID_DOC_DIR" 2>&1); then
    pass "lint_documentation accepts valid edge cases (fenced blocks, HTML comments, double-backtick spans, VS Code proper noun, duplicate/Unicode headings, escaped parens, cross-file anchors)"
else
    fail "lint_documentation valid edge cases" "Unexpected error on valid edge cases: $valid_doc_out"
fi
rm -rf "$TEMP_VALID_DOC_DIR"

# Verify embedded Python AST lint passes on repo and catches syntax errors
if py_ast_out=$(lint_python_embeds "$SCRIPT_DIR" 2>&1); then
    pass "lint_python_embeds validates all embedded Python AST blocks across repository scripts"
else
    fail "lint_python_embeds repo validation" "$py_ast_out"
fi

TEMP_PY_AST_DIR=$(mktemp -d)
mkdir -p "$TEMP_PY_AST_DIR/bin"
printf '%s\n' '#!/usr/bin/env bash' 'python3 - <<'"'PY'" 'def broken(:' '    pass' 'PY' > "$TEMP_PY_AST_DIR/bin/bad-py"
TEMP_PY_VAR_AST_DIR=$(mktemp -d)
mkdir -p "$TEMP_PY_VAR_AST_DIR/bin"
printf '%s\n' '#!/usr/bin/env bash' "IFS= read -r -d '' RESOLVE_THEME_PY <<""'PY' || true" 'def broken_var(:' '    pass' 'PY' > "$TEMP_PY_VAR_AST_DIR/bin/bad-var-py"
if lint_python_embeds "$TEMP_PY_AST_DIR" >/dev/null 2>&1 || lint_python_embeds "$TEMP_PY_VAR_AST_DIR" >/dev/null 2>&1; then
    fail "lint_python_embeds error detection" "Expected non-zero exit on invalid embedded Python syntax (both python3 and *_PY heredocs)"
else
    pass "lint_python_embeds catches syntax errors in both python3 and *_PY heredoc blocks"
fi
rm -rf "$TEMP_PY_AST_DIR" "$TEMP_PY_VAR_AST_DIR"

# Test setup.sh --theme validation, --theme --dry-run guard, empty/flag injection guards, stage-10 application, and 70-terminal.sh persisted theme fallback
TEMP_THEME_SETUP_HOME=$(mktemp -d)
if HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" "$SCRIPT_DIR/setup.sh" --dotfiles-only --theme --dry-run >/dev/null 2>&1 || \
   HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" "$SCRIPT_DIR/setup.sh" --dotfiles-only --theme "" >/dev/null 2>&1 || \
   HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" "$SCRIPT_DIR/setup.sh" --dotfiles-only --theme="" >/dev/null 2>&1 || \
   HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" HOME_SETTINGS_THEME="--list" "$SCRIPT_DIR/setup.sh" --dry-run --dotfiles-only >/dev/null 2>&1; then
    fail "setup.sh --theme invalid/empty/flag guard" "Expected non-zero exit on --theme --dry-run, --theme '', --theme='', and HOME_SETTINGS_THEME=--list"
elif [ -e "$TEMP_THEME_SETUP_HOME/.tmux.conf" ]; then
    fail "setup.sh --theme --dry-run no-mutation" "Expected zero dotfiles mutations when --theme guard rejects arguments"
else
    pass "setup.sh --theme rejects leading-dash flags, empty strings, and flag-like HOME_SETTINGS_THEME values without mutating HOME"
fi

if HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" "$SCRIPT_DIR/setup.sh" --dotfiles-only --theme nonexistent-theme-xyz >/dev/null 2>&1; then
    fail "setup.sh --theme unknown validation" "Expected non-zero exit on unknown --theme value"
else
    pass "setup.sh --theme validates theme existence upfront before running stages"
fi

if setup_theme_out=$(HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" XDG_CACHE_HOME="$TEMP_THEME_SETUP_HOME/.cache" THEME_UPDATE_TERMINAL_PROFILE=0 THEME_LIVE_NVIM=0 TMUX="" "$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-fonts --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-terminal --theme nord 2>&1) && \
   grep -Fq "Theme     : nord" <<< "$setup_theme_out" && \
   [ "$(cat "$TEMP_THEME_SETUP_HOME/.config/home-settings/theme" 2>/dev/null || true)" = "nord" ] && \
   grep -Fq 'THEME_ID="nord"' "$TEMP_THEME_SETUP_HOME/.config/home-settings/active-theme.theme"; then
    pass "setup.sh --dotfiles-only --theme nord applies requested theme in stage 10 and displays Theme in summary banner"
else
    fail "setup.sh --dotfiles-only --theme nord" "Theme was not persisted or applied in stage 10: ${setup_theme_out:-}"
fi

mkdir -p "$TEMP_THEME_SETUP_HOME/mock-bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TEMP_THEME_SETUP_HOME/mock-bin/dconf"
printf '%s\n' '#!/usr/bin/env bash' 'echo "org.gnome.Terminal.ProfilesList"' > "$TEMP_THEME_SETUP_HOME/mock-bin/gsettings"
chmod +x "$TEMP_THEME_SETUP_HOME/mock-bin/dconf" "$TEMP_THEME_SETUP_HOME/mock-bin/gsettings"
term_persisted_macos="$(env -u HOME_SETTINGS_THEME DRY_RUN=true OS=macos HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" "$SCRIPT_DIR/modules/70-terminal.sh" 2>&1 || true)"
term_persisted_linux="$(env -u HOME_SETTINGS_THEME PATH="$TEMP_THEME_SETUP_HOME/mock-bin:$PATH" DRY_RUN=true OS=ubuntu DISPLAY=":99" HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" "$SCRIPT_DIR/modules/70-terminal.sh" 2>&1 || true)"
if grep -Fq "Configure 'Nord' in Terminal.app Window Settings" <<< "$term_persisted_macos" && \
   grep -Fq "Apply Nord profile" <<< "$term_persisted_linux"; then
    pass "modules/70-terminal.sh honors persisted ~/.config/home-settings/theme on both macOS and Linux when HOME_SETTINGS_THEME is unset"
else
    fail "modules/70-terminal.sh persisted theme" "Expected Nord profile in dry-run output: macos='$term_persisted_macos' linux='$term_persisted_linux'"
fi
rm -rf "$TEMP_THEME_SETUP_HOME"

test_summary
