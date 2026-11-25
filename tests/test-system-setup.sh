#!/usr/bin/env bash
# Test suite for unified cross-platform setup engine (Ubuntu, Fedora, macOS, Mise, Java LTS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/tests/test-helper.sh"

echo "========================================"
echo "Running System & Cross-Platform Engine Tests"
echo "========================================"

# Test 1: Script and module syntax checks
echo -e "\n[1/6] Checking syntax of setup.sh, setup/lib/*.sh, setup/modules/*.sh, tests/{run,lint}.sh, bin/, and libexec/..."
assert_script_syntax "$SCRIPT_DIR/setup.sh" "setup.sh"
assert_script_syntax "$SCRIPT_DIR/tests/run.sh" "tests/run.sh"
assert_script_syntax "$SCRIPT_DIR/tests/lint.sh" "tests/lint.sh"

for lib_f in "$SCRIPT_DIR"/setup/lib/*.sh; do
    [ -f "$lib_f" ] && assert_script_syntax "$lib_f" "setup/lib/$(basename "$lib_f")"
done

for f in "$SCRIPT_DIR"/bin/*; do
    [ -f "$f" ] && assert_script_syntax "$f" "$(basename "$f")"
done

for py_mod in "$SCRIPT_DIR"/libexec/*_lib/*.py "$SCRIPT_DIR"/tests/lint/*.py; do
    [ -f "$py_mod" ] && assert_script_syntax "$py_mod" "${py_mod#"$SCRIPT_DIR"/}"
done

for m in "$SCRIPT_DIR"/setup/modules/*.sh; do
    [ -f "$m" ] && assert_script_syntax "$m" "$(basename "$m")"
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

assert_cmd_fails "setup.sh rejects invalid OS" "$SCRIPT_DIR/setup.sh" --os unsupported_distro
assert_cmd_fails "setup.sh rejects missing OS argument" "$SCRIPT_DIR/setup.sh" --os
assert_cmd_fails "setup.sh rejects invalid GUI app" "$SCRIPT_DIR/setup.sh" --os ubuntu --gui invalid_ide
assert_cmd_fails "setup.sh rejects empty --gui=" "$SCRIPT_DIR/setup.sh" --os ubuntu --gui=
assert_cmd_fails "setup.sh rejects invalid DB engine" "$SCRIPT_DIR/setup.sh" --os ubuntu --db invalid_engine
assert_cmd_fails "setup.sh rejects missing DB argument" "$SCRIPT_DIR/setup.sh" --os ubuntu --db
assert_cmd_fails "setup.sh rejects invalid --skip stage" "$SCRIPT_DIR/setup.sh" --os ubuntu --skip bogus_stage
assert_cmd_fails "setup.sh rejects retired legacy flags" "$SCRIPT_DIR/setup.sh" --dotfiles-only

# Isolate HOME and XDG directories so setup.sh invocations never touch the caller's real $HOME
TEMP_SETUP_HOME="$(make_sandbox_home)"
export HOME="$TEMP_SETUP_HOME"
export XDG_CONFIG_HOME="$TEMP_SETUP_HOME/.config"
export XDG_CACHE_HOME="$TEMP_SETUP_HOME/.cache"
export XDG_DATA_HOME="$TEMP_SETUP_HOME/.local/share"

# Clear pre-created sandbox XDG dirs before Test 3 so --dry-run zero-mutation check starts from an empty HOME
rm -rf "$TEMP_SETUP_HOME/.config" "$TEMP_SETUP_HOME/.cache" "$TEMP_SETUP_HOME/.local"

# Test 3: Dry-run Execution across Platforms
echo -e "\n[3/6] Testing Dry-run execution across Ubuntu, Fedora, and macOS..."

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --dry-run 2>&1); then
    if [[ "$output" == *"[DryRun]"* ]] && [[ "$output" == *"Target OS : ubuntu"* ]] && [[ "$output" == *"tmux"* ]] && [[ "$output" == *"imagemagick"* ]] && [[ "$output" != *"google-chrome"* ]] && [[ "$output" != *"snap install"* ]] && [[ "$output" == *"postgresql-client"* ]]; then
        pass "setup.sh --os ubuntu --dry-run executes cleanly with tmux, imagemagick, client DB tools, and skips GUI apps"
    else
        fail "setup.sh ubuntu dry-run output" "Unexpected output: $output"
    fi
else
    fail "setup.sh ubuntu dry-run" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --db postgres --dry-run 2>&1); then
    if [[ "$output" == *"postgresql postgresql-contrib"* ]]; then
        pass "setup.sh --db postgres provisions PostgreSQL server and contrib"
    else
        fail "setup.sh --db postgres output" "Missing PostgreSQL server commands: $output"
    fi
else
    fail "setup.sh --db postgres" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --db mariadb --dry-run 2>&1); then
    if [[ "$output" == *"mariadb-server mariadb-client"* ]]; then
        pass "setup.sh --db mariadb provisions MariaDB server"
    else
        fail "setup.sh --db mariadb output" "Missing MariaDB server commands: $output"
    fi
else
    fail "setup.sh --db mariadb" "Command failed: $output"
fi

if out_pg_my=$("$SCRIPT_DIR/setup.sh" --os ubuntu --db postgres,mariadb -n 2>&1) && \
   out_my_pg=$("$SCRIPT_DIR/setup.sh" --os ubuntu --db mariadb --db postgres --dry-run 2>&1) && \
   out_dbeq_pg_my=$("$SCRIPT_DIR/setup.sh" --os ubuntu --db=postgres,mariadb --dry-run 2>&1) && \
   out_skip_pg=$("$SCRIPT_DIR/setup.sh" --os ubuntu --skip db --db postgres --dry-run 2>&1); then
    if [[ "$out_pg_my" == *"Database  : Server: all"* ]] && \
       [[ "$out_pg_my" == *"postgresql postgresql-contrib"* ]] && \
       [[ "$out_pg_my" == *"mariadb-server mariadb-client"* ]] && \
       [[ "$out_my_pg" == *"Database  : Server: all"* ]] && \
       [[ "$out_my_pg" == *"postgresql postgresql-contrib"* ]] && \
       [[ "$out_my_pg" == *"mariadb-server mariadb-client"* ]] && \
       [[ "$out_dbeq_pg_my" == *"Database  : Server: all"* ]] && \
       [[ "$out_skip_pg" == *"postgresql postgresql-contrib"* ]]; then
        pass "setup.sh combines --db postgres,mariadb and repeated --db into DB_CHOICE=all and re-enables DB after --skip db"
    else
        fail "setup.sh combined --db" "Expected both PostgreSQL and MariaDB servers: $out_pg_my"
    fi
else
    fail "setup.sh combined DB flags" "Command failed"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --skip db --dry-run 2>&1); then
    if [[ "$output" != *"postgresql-client"* ]] && [[ "$output" != *"mariadb-client"* ]]; then
        pass "setup.sh --skip db skips all database clients and servers"
    else
        fail "setup.sh --skip db output" "Database packages should be skipped: $output"
    fi
else
    fail "setup.sh --skip db" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --skip terminal --dry-run 2>&1); then
    if [[ "$output" != *"Configuring GNOME Terminal"* ]]; then
        pass "setup.sh --skip terminal skips terminal profile configuration"
    else
        fail "setup.sh --skip terminal output" "Terminal configuration should be skipped: $output"
    fi
else
    fail "setup.sh --skip terminal" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os ubuntu --gui --dry-run 2>&1); then
    if [[ "$output" == *"google-chrome"* ]] && [[ "$output" == *"snap install code"* ]] && \
       { [[ "$output" == *"snap install ghostty"* ]] || [[ "$output" == *"apt-get install -y ghostty"* ]] || [[ "$output" == *"ghostty_latest_"*".deb"* ]]; }; then
        pass "setup.sh --gui enables Chrome, Ghostty, and VS Code by default"
    else
        fail "setup.sh --gui dry-run output" "Missing expected GUI application commands: $output"
    fi
else
    fail "setup.sh --gui dry-run" "Command failed: $output"
fi

if out_none=$("$SCRIPT_DIR/setup.sh" --os ubuntu --gui=none --dry-run 2>&1) && \
   out_gui_subset=$("$SCRIPT_DIR/setup.sh" --os ubuntu --gui ghostty,chrome --dry-run 2>&1) && \
   out_multi_ide=$("$SCRIPT_DIR/setup.sh" --os ubuntu --gui=code,intellij --dry-run 2>&1) && \
   out_reset_none=$("$SCRIPT_DIR/setup.sh" --os ubuntu --gui --gui none --dry-run 2>&1); then
    if [[ "$out_none" != *"snap install code"* ]] && \
       [[ "$out_gui_subset" == *"google-chrome"* ]] && [[ "$out_gui_subset" != *"snap install code"* ]] && \
       [[ "$out_multi_ide" == *"IDE Choice: code,intellij"* ]] && [[ "$out_multi_ide" == *"snap install code"* ]] && [[ "$out_multi_ide" == *"intellij-idea-community"* ]] && \
       [[ "$out_reset_none" == *"IDE Choice: none"* ]] && [[ "$out_reset_none" != *"google-chrome"* ]]; then
        pass "setup.sh --gui supports explicit CSV subsets, multi-IDE installs (code,intellij), and --gui none resets"
    else
        fail "setup.sh --gui CSV subsets" "Unexpected --gui subset behavior: subset='$out_gui_subset' multi='$out_multi_ide' reset='$out_reset_none'"
    fi
else
    fail "setup.sh --gui subset dry-run" "Command failed"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os macos --gui ghostty --dry-run 2>&1); then
    if [[ "$output" == *"brew install --cask ghostty"* ]]; then
        pass "setup.sh --os macos --gui ghostty installs Ghostty cask"
    else
        fail "setup.sh macos --gui ghostty output" "Missing Ghostty cask: $output"
    fi
else
    fail "setup.sh macos --gui ghostty" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os fedora --gui=ghostty --dry-run 2>&1); then
    if [[ "$output" == *"copr enable scottames/ghostty"* ]] && [[ "$output" == *"install ghostty"* ]]; then
        pass "setup.sh --os fedora --gui=ghostty enables COPR and installs Ghostty"
    else
        fail "setup.sh fedora --gui=ghostty output" "Missing Ghostty Fedora commands: $output"
    fi
else
    fail "setup.sh fedora --gui=ghostty" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os fedora --dry-run 2>&1); then
    if [[ "$output" == *"[DryRun]"* ]] && [[ "$output" == *"Target OS : fedora"* ]] && [[ "$output" == *"ImageMagick"* ]] && [[ "$output" != *"google-chrome"* ]] && [[ "$output" != *"install ghostty"* ]]; then
        pass "setup.sh --os fedora --dry-run executes cleanly with Fedora packages including ImageMagick (no GUI apps)"
    else
        fail "setup.sh fedora dry-run output" "Missing expected output markers: $output"
    fi
else
    fail "setup.sh fedora dry-run" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os macos --dry-run 2>&1); then
    if [[ "$output" == *"[DryRun]"* ]] && [[ "$output" == *"Target OS : macos"* ]] && [[ "$output" == *"brew install"* ]] && [[ "$output" == *"imagemagick"* ]] && [[ "$output" != *"--cask"* ]]; then
        pass "setup.sh --os macos --dry-run executes cleanly with Homebrew packages including imagemagick (no GUI casks)"
    else
        fail "setup.sh macos dry-run output" "Missing expected output markers: $output"
    fi
else
    fail "setup.sh macos dry-run" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --os macos --gui chrome --dry-run 2>&1); then
    if [[ "$output" == *"brew install --cask google-chrome"* ]]; then
        pass "setup.sh --os macos --gui chrome installs Chrome cask"
    else
        fail "setup.sh macos --gui chrome output" "Missing Chrome cask: $output"
    fi
else
    fail "setup.sh macos --gui chrome" "Command failed: $output"
fi

if output=$("$SCRIPT_DIR/setup.sh" --user --dry-run 2>&1) && sys_only_out=$("$SCRIPT_DIR/setup.sh" --os ubuntu --system-only -n 2>&1); then
    if [[ "$output" == *"Skipping System-Level Provisioning"* ]] && [[ "$output" == *"Running User Dotfiles"* ]] && [[ "$sys_only_out" == *"Running System-Level Provisioning"* ]] && [[ "$sys_only_out" != *"Running User Dotfiles"* ]]; then
        pass "setup.sh --user skips system provisioning and --system-only -n skips user environment"
    else
        fail "setup.sh --user / --system-only dry-run output" "Unexpected output: $output / $sys_only_out"
    fi
else
    fail "setup.sh --user / --system-only dry-run" "Command failed: ${output:-}"
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

if output=$("$SCRIPT_DIR/setup.sh" --uninstall=dotfiles --dry-run 2>&1) && combo_uninst=$("$SCRIPT_DIR/setup.sh" --uninstall dotfiles,bin -n 2>&1); then
    if [[ "$output" == *"Removing managed dotfile symlinks"* ]] && [[ "$output" == *"Dotfile symlinks uninstalled"* ]] && \
       [[ "$combo_uninst" == *"Dotfile symlinks uninstalled"* ]] && [[ "$combo_uninst" == *"User binaries uninstalled"* ]] && [[ "$combo_uninst" != *"MesloLGS Nerd Font Mono fonts uninstalled"* ]]; then
        pass "setup.sh --uninstall=dotfiles and --uninstall dotfiles,bin -n work cleanly"
    else
        fail "setup.sh --uninstall=dotfiles dry-run output" "Missing expected output: $output / $combo_uninst"
    fi
else
    fail "setup.sh --uninstall=dotfiles dry-run" "Command failed: $output"
fi

if [ -z "$(ls -A "$TEMP_SETUP_HOME" 2>/dev/null)" ]; then
    pass "setup.sh --dry-run leaves HOME completely untouched (zero directories created)"
else
    fail "setup.sh --dry-run filesystem mutation" "Expected empty $TEMP_SETUP_HOME, found: $(ls -A "$TEMP_SETUP_HOME")"
fi

TEMP_UNINSTALL_HOME=$(mktemp -d)
mkdir -p "$TEMP_UNINSTALL_HOME/.config/mise" "$TEMP_UNINSTALL_HOME/.config/bat/themes" "$TEMP_UNINSTALL_HOME/.config/bat/syntaxes"
ln -s "$SCRIPT_DIR/.mise.toml" "$TEMP_UNINSTALL_HOME/.config/mise/config.toml"
dry_out=$(HOME="$TEMP_UNINSTALL_HOME" XDG_CONFIG_HOME="$TEMP_UNINSTALL_HOME/.config" "$SCRIPT_DIR/setup.sh" --uninstall=dotfiles --dry-run 2>&1)
if [[ "$dry_out" == *"mise/config.toml"* ]] && [ -d "$TEMP_UNINSTALL_HOME/.config/bat/themes" ] && [ -d "$TEMP_UNINSTALL_HOME/.config/bat/syntaxes" ]; then
    pass "setup.sh --uninstall=dotfiles --dry-run cleans ~/.config/mise/config.toml symlink without deleting bat dirs"
else
    fail "setup.sh uninstall=dotfiles mise cleanup" "Expected mise/config.toml in dry-run output and preserved bat dirs: $dry_out"
fi
rm -rf "$TEMP_UNINSTALL_HOME"

if output=$("$SCRIPT_DIR/setup.sh" --uninstall=bin --dry-run 2>&1); then
    if [[ "$output" == *"Removing bin utilities"* ]] && [[ "$output" == *"User binaries uninstalled"* ]]; then
        pass "setup.sh --uninstall=bin --dry-run works"
    else
        fail "setup.sh uninstall=bin dry-run output" "Missing expected output: $output"
    fi
else
    fail "setup.sh uninstall=bin dry-run" "Command failed: $output"
fi

TEMP_BIN_HOME=$(mktemp -d)
mkdir -p "$TEMP_BIN_HOME/.local/bin"
ln -s "/usr/bin/fdfind" "$TEMP_BIN_HOME/.local/bin/fd"
bin_dry_out=$(HOME="$TEMP_BIN_HOME" "$SCRIPT_DIR/setup.sh" --uninstall=bin --dry-run 2>&1)
if [[ "$bin_dry_out" == *".local/bin/fd"* ]]; then
    pass "setup.sh --uninstall=bin cleans compatibility shims (fd/bat)"
else
    fail "setup.sh uninstall=bin shim cleanup" "Expected fd shim in dry-run output: $bin_dry_out"
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
    chsh_check=$(HOME="$TEMP_SHELL_HOME" MOD_SH="$SCRIPT_DIR/setup/modules/60-shell.sh" python3 -c '
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

HOME="$TEMP_SHELL_HOME" "$SCRIPT_DIR/setup.sh" --uninstall=dotfiles >/dev/null 2>&1 || true
if [ ! -d "$TEMP_SHELL_HOME/.oh-my-zsh/custom/plugins/fzf-zsh-plugin" ] && [ ! -d "$TEMP_SHELL_HOME/.vim/bundle" ]; then
    pass "setup.sh --uninstall=dotfiles purges legacy fzf-zsh-plugin and .vim/bundle directories"
else
    fail "setup.sh --uninstall=dotfiles legacy directory purge" "Expected legacy directories to be deleted"
fi
rm -rf "$TEMP_SHELL_HOME"

# Test 4: Mise Configuration Validity
echo -e "\n[4/6] Testing .mise.toml toolchain definition..."
if [ -f "$SCRIPT_DIR/.mise.toml" ]; then
    if grep -q 'java = "lts"' "$SCRIPT_DIR/.mise.toml" && grep -q 'node = "lts"' "$SCRIPT_DIR/.mise.toml" && grep -Fq '"npm:typescript" = "6"' "$SCRIPT_DIR/.mise.toml" && grep -Fq '"npm:typescript-language-server" = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -Fq '"npm:pyright" = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -Fq '"npm:bash-language-server" = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -Fq '"npm:yaml-language-server" = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -Fq '"npm:vscode-langservers-extracted" = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'go = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'maven = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'python = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'rust = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'elan = "github:leanprover/elan"' "$SCRIPT_DIR/.mise.toml" && grep -q 'elan = { version = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'terraform = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'ripgrep = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'neovim = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'eza = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'bat = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'btop = { version = "latest", os = \["linux"\] }' "$SCRIPT_DIR/.mise.toml" && grep -q 'delta = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'dust = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'fd = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'fzf = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'gh = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'jq = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'sd = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'shellcheck = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'tealdeer = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'yq = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'zoxide = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'glow = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'tree-sitter = "latest"' "$SCRIPT_DIR/.mise.toml" && grep -q 'go.set_gobin = false' "$SCRIPT_DIR/.mise.toml" && grep -q 'go.set_gopath = false' "$SCRIPT_DIR/.mise.toml" && grep -Fq 'mise/shims' "$SCRIPT_DIR/setup.sh" && grep -Fq '$ELAN_HOME/bin' "$SCRIPT_DIR/setup.sh"; then
        pass ".mise.toml defaults to LTS for Java/Node, declarative npm LSPs (TypeScript 6 tsserver + latest language servers), latest for CLI tools and Elan/Lean 4, protects Go paths (gobin/gopath = false), and setup.sh exports mise/shims and ELAN_HOME/bin on PATH"
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

passwd_alnum=$("$SCRIPT_DIR/bin/gen-passwd" -u -l -n 40)
if [ "${#passwd_alnum}" -eq 40 ] && [[ "$passwd_alnum" =~ ^[A-Za-z0-9]+$ ]]; then
    pass "gen-passwd -u -l -n 40 generates 40-char alphanumeric strings"
else
    fail "gen-passwd -u -l -n 40 generation" "Generated unexpected characters or length: $passwd_alnum"
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

printf '5' > "$TEMP_SUM_DIR/no_nl.txt"
sum_delim_out=$("$SCRIPT_DIR/bin/sum" -d ',' '1,2,3' '4,5,6')
sum_csv_pos_out=$("$SCRIPT_DIR/bin/sum" 1,2,3,4,5)
sum_stats_out=$("$SCRIPT_DIR/bin/sum" -s 5 10 15 20)
if [ "$sum_csv_pos_out" != "15" ] || ! grep -Fq "mean: 12.5" <<< "$sum_stats_out" || ! grep -Fq "sum: 50" <<< "$sum_stats_out"; then
    fail "sum csv positional / summary stats" "Expected 15 and summary stats, got csv=$sum_csv_pos_out stats=$sum_stats_out"
fi
sum_col_delim_out=$("$SCRIPT_DIR/bin/sum" -d ':' -k 2 'a:10' 'b:20')
sum_neg_out=$("$SCRIPT_DIR/bin/sum" -5 10)
sum_flag_neg_out=$("$SCRIPT_DIR/bin/sum" -a -5 15)
sum_tdot_out=$("$SCRIPT_DIR/bin/sum" 5. 10)
sum_tdot_h_out=$("$SCRIPT_DIR/bin/sum" -H 5.K)
sum_mixed_nonl_out=$("$SCRIPT_DIR/bin/sum" "$TEMP_SUM_DIR/no_nl.txt" 10)
if [ "$sum_delim_out" = "21" ] && \
   [ "$sum_col_delim_out" = "30" ] && \
   [ "$sum_neg_out" = "5" ] && \
   [ "$sum_flag_neg_out" = "5" ] && \
   [ "$sum_tdot_out" = "15" ] && \
   [ "$sum_tdot_h_out" = "5120" ] && \
   [ "$sum_mixed_nonl_out" = "15" ] && \
   ! "$SCRIPT_DIR/bin/sum" "$TEMP_SUM_DIR/missing.txt" >/dev/null 2>&1 && \
   ! "$SCRIPT_DIR/bin/sum" -d ',' "$TEMP_SUM_DIR/missing.csv" >/dev/null 2>&1 && \
   ! "$SCRIPT_DIR/bin/sum" -d ':' -k 2 "$TEMP_SUM_DIR/no:such:file" >/dev/null 2>&1; then
    pass "sum handles -d/-k inline delimited arguments, leading negative numbers, trailing-dot floats/units, no-newline files, and errors on nonexistent files"
else
    fail "sum edge cases" "Unexpected results: delim=$sum_delim_out col=$sum_col_delim_out neg=$sum_neg_out/$sum_flag_neg_out tdot=$sum_tdot_out/$sum_tdot_h_out nonl=$sum_mixed_nonl_out"
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
mkdir -p "$TEMP_DOC_DIR/.github/workflows" "$TEMP_DOC_DIR/bin" "$TEMP_DOC_DIR/tests/fixtures/sample-code" "$TEMP_DOC_DIR/dotfiles/.config/ghostty" "$TEMP_DOC_DIR/dotfiles/.config/nvim"
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

cat > "$TEMP_DOC_DIR/tests/fixtures/sample-code/sample.md" <<'EOF'
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
       grep -Fq 'Ghostty keybinding "Ctrl+Shift+T" missing config directive "keybind = ctrl+shift+t=new_tab"' <<< "$bad_doc_out" && \
       grep -Fq 'Ghostty keybinding "Alt+Left/Right/Up/Down" missing config directive' <<< "$bad_doc_out" && \
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
        pass "lint_documentation detects personal paths, emojis, stacked formatting, unmatched backticks, underscore italics, prose slashes/ampersands/plus connectors, Latin abbreviations, tight/empty headings, untagged fences, tree comment connectors, CLI/setup.sh/keybinding/Ghostty/sample.md drift, broken links/anchors, and invalid JSON blocks"
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

# Verify embedded Python AST lint passes on repo and catches syntax errors + Python 3.9 incompatibilities
if py_ast_out=$(lint_python_embeds "$SCRIPT_DIR" 2>&1); then
    pass "lint_python_embeds validates all embedded Python AST blocks across repository scripts for Python 3.9+ compatibility"
else
    fail "lint_python_embeds repo validation" "$py_ast_out"
fi

TEMP_PY_AST_DIR=$(mktemp -d)
mkdir -p "$TEMP_PY_AST_DIR/bin"
printf '%s\n' '#!/usr/bin/env bash' 'python3 - <<'"'PY'" 'def broken(:' '    pass' 'PY' > "$TEMP_PY_AST_DIR/bin/bad-py"
TEMP_PY_VAR_AST_DIR=$(mktemp -d)
mkdir -p "$TEMP_PY_VAR_AST_DIR/bin"
printf '%s\n' '#!/usr/bin/env bash' "IFS= read -r -d '' RESOLVE_THEME_PY <<""'PY' || true" 'def broken_var(:' '    pass' 'PY' > "$TEMP_PY_VAR_AST_DIR/bin/bad-var-py"
TEMP_PY39_ANNOT_DIR=$(mktemp -d)
mkdir -p "$TEMP_PY39_ANNOT_DIR/bin"
printf '%s\n' '#!/usr/bin/env bash' 'python3 - <<'"'PY'" 'def bad_union(x: int | None) -> str | None:' '    return None' 'PY' > "$TEMP_PY39_ANNOT_DIR/bin/bad-pep604"
TEMP_PY39_ISINST_DIR=$(mktemp -d)
mkdir -p "$TEMP_PY39_ISINST_DIR/bin"
printf '%s\n' '#!/usr/bin/env bash' 'python3 - <<'"'PY'" 'from __future__ import annotations' 'isinstance(1, int | str)' 'PY' > "$TEMP_PY39_ISINST_DIR/bin/bad-isinst"
TEMP_PY39_MATCH_DIR=$(mktemp -d)
mkdir -p "$TEMP_PY39_MATCH_DIR/bin"
printf '%s\n' '#!/usr/bin/env bash' 'python3 - <<'"'PY'" 'match 1:' '    case 1: pass' 'PY' > "$TEMP_PY39_MATCH_DIR/bin/bad-match"
TEMP_PY39_RTUNION_DIR=$(mktemp -d)
mkdir -p "$TEMP_PY39_RTUNION_DIR/bin"
printf '%s\n' '#!/usr/bin/env bash' 'python3 - <<'"'PY'" 'from __future__ import annotations' 'T = str | None' 'PY' > "$TEMP_PY39_RTUNION_DIR/bin/bad-rt-union"
TEMP_PY39_ZIP_DIR=$(mktemp -d)
mkdir -p "$TEMP_PY39_ZIP_DIR/bin"
printf '%s\n' '#!/usr/bin/env bash' 'python3 - <<'"'PY'" 'from __future__ import annotations' 'list(zip([1], [2], strict=True))' 'PY' > "$TEMP_PY39_ZIP_DIR/bin/bad-zip"
TEMP_PY39_OK_DIR=$(mktemp -d)
mkdir -p "$TEMP_PY39_OK_DIR/bin"
printf '%s\n' '#!/usr/bin/env bash' 'python3 - <<'"'PY'" 'from __future__ import annotations' 'def ok_union(x: int | None) -> str | None:' '    flags = 1 | 2' '    return str(flags)' 'PY' > "$TEMP_PY39_OK_DIR/bin/ok-pep604"
if lint_python_embeds "$TEMP_PY_AST_DIR" >/dev/null 2>&1 || \
   lint_python_embeds "$TEMP_PY_VAR_AST_DIR" >/dev/null 2>&1 || \
   lint_python_embeds "$TEMP_PY39_ANNOT_DIR" >/dev/null 2>&1 || \
   lint_python_embeds "$TEMP_PY39_ISINST_DIR" >/dev/null 2>&1 || \
   lint_python_embeds "$TEMP_PY39_MATCH_DIR" >/dev/null 2>&1 || \
   lint_python_embeds "$TEMP_PY39_RTUNION_DIR" >/dev/null 2>&1 || \
   lint_python_embeds "$TEMP_PY39_ZIP_DIR" >/dev/null 2>&1 || \
   ! lint_python_embeds "$TEMP_PY39_OK_DIR" >/dev/null 2>&1; then
    fail "lint_python_embeds error & Python 3.9 detection" "Expected failure on syntax/match/un-postponed PEP 604/runtime union/zip(strict) and success with postponed annotations + bitwise OR"
else
    pass "lint_python_embeds catches syntax errors, Python 3.10+ match/zip(strict), un-postponed PEP 604 annotations, and runtime type unions while allowing postponed annotations and integer bitwise OR"
fi
rm -rf "$TEMP_PY_AST_DIR" "$TEMP_PY_VAR_AST_DIR" "$TEMP_PY39_ANNOT_DIR" "$TEMP_PY39_ISINST_DIR" "$TEMP_PY39_MATCH_DIR" "$TEMP_PY39_RTUNION_DIR" "$TEMP_PY39_ZIP_DIR" "$TEMP_PY39_OK_DIR"

# Verify unlink_path foreign/traversal symlink preservation, dangling relative symlink cleanup, and 99-uninstall.sh ~/.zshrc & ~/.bashrc hook removal + permission preservation
TEMP_OWN_HOME=$(mktemp -d)
mkdir -p "$TEMP_OWN_HOME/.config" "$TEMP_OWN_HOME/.local/bin" "$TEMP_OWN_HOME/foreign"
printf 'foreign-vimrc\n' > "$TEMP_OWN_HOME/foreign/.vimrc"
mkdir -p "$TEMP_OWN_HOME/foreign/nvim"
printf 'foreign-sum\n' > "$TEMP_OWN_HOME/foreign/sum"
ln -s "$SCRIPT_DIR/dotfiles/.tmux.conf" "$TEMP_OWN_HOME/.tmux.conf"
ln -s "$TEMP_OWN_HOME/foreign/.vimrc" "$TEMP_OWN_HOME/.vimrc"
ln -s "$SCRIPT_DIR/../../outside_foreign_target_xyz" "$TEMP_OWN_HOME/.aliases"
rel_to_repo="$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$SCRIPT_DIR/dotfiles/deleted_subdir_xyz/.p10k.zsh" "$TEMP_OWN_HOME")"
ln -s "$rel_to_repo" "$TEMP_OWN_HOME/.p10k.zsh"
ln -s "$TEMP_OWN_HOME/foreign/nvim" "$TEMP_OWN_HOME/.config/nvim"
ln -s "$SCRIPT_DIR/bin/ide" "$TEMP_OWN_HOME/.local/bin/ide"
ln -s "/usr/bin/fdfind" "$TEMP_OWN_HOME/.local/bin/fd"
ln -s "$TEMP_OWN_HOME/foreign/sum" "$TEMP_OWN_HOME/.local/bin/sum"
cat > "$TEMP_OWN_HOME/.zshrc" <<'EOF'
export USER_CUSTOM_BEFORE="1"

# home-settings
[ -f ~/.zshrc-addendum ] && source ~/.zshrc-addendum

export USER_CUSTOM_AFTER="1"
EOF
cat > "$TEMP_OWN_HOME/.bashrc" <<'EOF'
export BASH_CUSTOM_BEFORE="1"

# home-settings: Source modular Bash configuration
[ -f "$HOME/.bashrc-addendum" ] && . "$HOME/.bashrc-addendum"

export BASH_CUSTOM_AFTER="1"
EOF
chmod 0644 "$TEMP_OWN_HOME/.zshrc" "$TEMP_OWN_HOME/.bashrc"
HOME="$TEMP_OWN_HOME" XDG_CONFIG_HOME="$TEMP_OWN_HOME/.config" "$SCRIPT_DIR/setup.sh" --uninstall --dry-run >/dev/null 2>&1
if [ ! -L "$TEMP_OWN_HOME/.tmux.conf" ] || ! grep -Fq ".zshrc-addendum" "$TEMP_OWN_HOME/.zshrc" || ! grep -Fq ".bashrc-addendum" "$TEMP_OWN_HOME/.bashrc"; then
    fail "setup.sh --uninstall --dry-run mutation" "Expected --dry-run to leave symlinks and shell rc hooks untouched"
else
    HOME="$TEMP_OWN_HOME" XDG_CONFIG_HOME="$TEMP_OWN_HOME/.config" "$SCRIPT_DIR/setup.sh" --uninstall >/dev/null 2>&1
    zshrc_mode="$(python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$TEMP_OWN_HOME/.zshrc")"
    bashrc_mode="$(python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$TEMP_OWN_HOME/.bashrc")"
    if [ ! -L "$TEMP_OWN_HOME/.tmux.conf" ] && \
       [ ! -L "$TEMP_OWN_HOME/.p10k.zsh" ] && \
       [ ! -L "$TEMP_OWN_HOME/.local/bin/ide" ] && \
       [ ! -L "$TEMP_OWN_HOME/.local/bin/fd" ] && \
       [ -L "$TEMP_OWN_HOME/.vimrc" ] && \
       [ -L "$TEMP_OWN_HOME/.aliases" ] && \
       [ -L "$TEMP_OWN_HOME/.config/nvim" ] && \
       [ -L "$TEMP_OWN_HOME/.local/bin/sum" ] && \
       [ "$zshrc_mode" = "0o644" ] && \
       [ "$bashrc_mode" = "0o644" ] && \
       ! grep -Fq "home-settings" "$TEMP_OWN_HOME/.zshrc" && \
       ! grep -Fq ".zshrc-addendum" "$TEMP_OWN_HOME/.zshrc" && \
       grep -Fq 'USER_CUSTOM_BEFORE="1"' "$TEMP_OWN_HOME/.zshrc" && \
       grep -Fq 'USER_CUSTOM_AFTER="1"' "$TEMP_OWN_HOME/.zshrc" && \
       ! grep -Fq "home-settings" "$TEMP_OWN_HOME/.bashrc" && \
       ! grep -Fq ".bashrc-addendum" "$TEMP_OWN_HOME/.bashrc" && \
       grep -Fq 'BASH_CUSTOM_BEFORE="1"' "$TEMP_OWN_HOME/.bashrc" && \
       grep -Fq 'BASH_CUSTOM_AFTER="1"' "$TEMP_OWN_HOME/.bashrc"; then
        pass "setup.sh --uninstall removes managed/dangling-relative symlinks and # home-settings blocks while preserving foreign/traversal symlinks, user rc lines, and 0644 file permissions"
    else
        fail "setup.sh --uninstall ownership & rc cleanup" "Failed ownership/traversal/permission checks: zshrc_mode=$zshrc_mode bashrc_mode=$bashrc_mode"
    fi
fi
rm -rf "$TEMP_OWN_HOME"

# Test setup.sh --theme validation, --theme --dry-run guard, empty/flag injection guards, stage-10 application, and 70-terminal.sh persisted theme fallback
TEMP_THEME_SETUP_HOME=$(mktemp -d)
if HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" "$SCRIPT_DIR/setup.sh" --user --theme --dry-run >/dev/null 2>&1 || \
   HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" "$SCRIPT_DIR/setup.sh" --user --theme "" >/dev/null 2>&1 || \
   HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" "$SCRIPT_DIR/setup.sh" --user --theme="" >/dev/null 2>&1 || \
   HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" HOME_SETTINGS_THEME="--list" "$SCRIPT_DIR/setup.sh" --dry-run --user >/dev/null 2>&1; then
    fail "setup.sh --theme invalid/empty/flag guard" "Expected non-zero exit on --theme --dry-run, --theme '', --theme='', and HOME_SETTINGS_THEME=--list"
elif [ -e "$TEMP_THEME_SETUP_HOME/.tmux.conf" ]; then
    fail "setup.sh --theme --dry-run no-mutation" "Expected zero dotfiles mutations when --theme guard rejects arguments"
else
    pass "setup.sh --theme rejects leading-dash flags, empty strings, and flag-like HOME_SETTINGS_THEME values without mutating HOME"
fi

if HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" "$SCRIPT_DIR/setup.sh" --user --theme nonexistent-theme-xyz >/dev/null 2>&1; then
    fail "setup.sh --theme unknown validation" "Expected non-zero exit on unknown --theme value"
else
    pass "setup.sh --theme validates theme existence upfront before running stages"
fi

if setup_theme_out=$(HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" XDG_CACHE_HOME="$TEMP_THEME_SETUP_HOME/.cache" THEME_UPDATE_TERMINAL_PROFILE=0 THEME_LIVE_NVIM=0 TMUX="" "$SCRIPT_DIR/setup.sh" --user --skip fonts,tools,vim,nvim,zsh,terminal --theme nord 2>&1) && \
   grep -Fq "Theme     : nord" <<< "$setup_theme_out" && \
   [ "$(cat "$TEMP_THEME_SETUP_HOME/.config/home-settings/theme" 2>/dev/null || true)" = "nord" ] && \
   grep -Fq 'THEME_ID="nord"' "$TEMP_THEME_SETUP_HOME/.config/home-settings/active-theme.theme"; then
    pass "setup.sh --user --theme nord applies requested theme in stage 10 and displays Theme in summary banner"
else
    fail "setup.sh --user --theme nord" "Theme was not persisted or applied in stage 10: ${setup_theme_out:-}"
fi

mkdir -p "$TEMP_THEME_SETUP_HOME/mock-bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TEMP_THEME_SETUP_HOME/mock-bin/dconf"
cat > "$TEMP_THEME_SETUP_HOME/mock-bin/gsettings" <<'EOF'
#!/usr/bin/env bash
printf 'org.gnome.Terminal.ProfilesList\n'
i=0
while [ "$i" -lt 2500 ]; do
    printf 'org.example.schema.padding.%04d\n' "$i"
    i=$((i + 1))
done
EOF
chmod +x "$TEMP_THEME_SETUP_HOME/mock-bin/dconf" "$TEMP_THEME_SETUP_HOME/mock-bin/gsettings"
term_persisted_macos="$(env -u HOME_SETTINGS_THEME DRY_RUN=true OS=macos HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" "$SCRIPT_DIR/setup/modules/70-terminal.sh" 2>&1 || true)"
term_persisted_linux="$(env -u HOME_SETTINGS_THEME PATH="$TEMP_THEME_SETUP_HOME/mock-bin:$PATH" DRY_RUN=true OS=ubuntu DISPLAY=":99" HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" "$SCRIPT_DIR/setup/modules/70-terminal.sh" 2>&1 || true)"
if grep -Fq "Configure 'Nord' in Terminal.app Window Settings" <<< "$term_persisted_macos" && \
   grep -Fq "Apply Nord profile" <<< "$term_persisted_linux"; then
    pass "modules/70-terminal.sh honors persisted ~/.config/home-settings/theme on both macOS and Linux (including SIGPIPE-safe multi-kilobyte gsettings list-schemas output)"
else
    fail "modules/70-terminal.sh persisted theme" "Expected Nord profile in dry-run output: macos='$term_persisted_macos' linux='$term_persisted_linux'"
fi

# Verify modules/60-shell.sh backs up pre-existing non-Oh-My-Zsh ~/.zshrc (e.g. stock prompt adam1 skeleton),
# initializes the Oh-My-Zsh template with Powerlevel10k + plugins, and preserves Oh-My-Zsh ~/.zshrc on re-run
TEMP_ZSHRC_HOME=$(mktemp -d)
mkdir -p \
    "$TEMP_ZSHRC_HOME/mock-bin" \
    "$TEMP_ZSHRC_HOME/.oh-my-zsh/templates" \
    "$TEMP_ZSHRC_HOME/.oh-my-zsh/custom/themes/powerlevel10k/.git" \
    "$TEMP_ZSHRC_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/.git" \
    "$TEMP_ZSHRC_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/.git" \
    "$TEMP_ZSHRC_HOME/.oh-my-zsh/custom/plugins/zsh-completions/.git"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TEMP_ZSHRC_HOME/mock-bin/git"
chmod +x "$TEMP_ZSHRC_HOME/mock-bin/git"
cat > "$TEMP_ZSHRC_HOME/.oh-my-zsh/templates/zshrc.zsh-template" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh
EOF
cat > "$TEMP_ZSHRC_HOME/.zshrc" <<'EOF'
autoload -Uz promptinit
promptinit
prompt adam1
# source $ZSH/oh-my-zsh.sh
EOF
zshrc_mig_out="$(PATH="$TEMP_ZSHRC_HOME/mock-bin:$PATH" HOME="$TEMP_ZSHRC_HOME" ZSH="$TEMP_ZSHRC_HOME/.oh-my-zsh" ZSH_CUSTOM="$TEMP_ZSHRC_HOME/.oh-my-zsh/custom" SKIP_ZSH=false SKIP_BASH=true SKIP_COMPLETIONS=true "$SCRIPT_DIR/setup/modules/60-shell.sh" 2>&1 || true)"
zshrc_baks=("$TEMP_ZSHRC_HOME"/.zshrc.bak.*)
if [ "${#zshrc_baks[@]}" -eq 1 ] && [ -f "${zshrc_baks[0]}" ] && \
   grep -Fq "prompt adam1" "${zshrc_baks[0]}" && \
   grep -Fq 'ZSH_THEME="powerlevel10k/powerlevel10k"' "$TEMP_ZSHRC_HOME/.zshrc" && \
   grep -Fq 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)' "$TEMP_ZSHRC_HOME/.zshrc" && \
   grep -Fq 'source $ZSH/oh-my-zsh.sh' "$TEMP_ZSHRC_HOME/.zshrc" && \
   grep -Fq '[ -f ~/.zshrc-addendum ] && source ~/.zshrc-addendum' "$TEMP_ZSHRC_HOME/.zshrc"; then
    printf '\n# user-custom-marker\n' >> "$TEMP_ZSHRC_HOME/.zshrc"
    PATH="$TEMP_ZSHRC_HOME/mock-bin:$PATH" HOME="$TEMP_ZSHRC_HOME" ZSH="$TEMP_ZSHRC_HOME/.oh-my-zsh" ZSH_CUSTOM="$TEMP_ZSHRC_HOME/.oh-my-zsh/custom" SKIP_ZSH=false SKIP_BASH=true SKIP_COMPLETIONS=true "$SCRIPT_DIR/setup/modules/60-shell.sh" >/dev/null 2>&1 || true
    zshrc_baks_after=("$TEMP_ZSHRC_HOME"/.zshrc.bak.*)
    if [ "${#zshrc_baks_after[@]}" -eq 1 ] && grep -Fq "# user-custom-marker" "$TEMP_ZSHRC_HOME/.zshrc"; then
        printf '[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"\n# cond-omz-marker\n' > "$TEMP_ZSHRC_HOME/.zshrc"
        PATH="$TEMP_ZSHRC_HOME/mock-bin:$PATH" HOME="$TEMP_ZSHRC_HOME" ZSH="$TEMP_ZSHRC_HOME/.oh-my-zsh" ZSH_CUSTOM="$TEMP_ZSHRC_HOME/.oh-my-zsh/custom" SKIP_ZSH=false SKIP_BASH=true SKIP_COMPLETIONS=true "$SCRIPT_DIR/setup/modules/60-shell.sh" >/dev/null 2>&1 || true
        zshrc_baks_cond=("$TEMP_ZSHRC_HOME"/.zshrc.bak.*)
        if [ "${#zshrc_baks_cond[@]}" -eq 1 ] && grep -Fq "# cond-omz-marker" "$TEMP_ZSHRC_HOME/.zshrc"; then
            pass "modules/60-shell.sh backs up non-Oh-My-Zsh ~/.zshrc to initialize Powerlevel10k template and preserves existing Oh-My-Zsh ~/.zshrc on re-run"
        else
            fail "modules/60-shell.sh conditional oh-my-zsh preservation" "Expected conditional oh-my-zsh.sh ~/.zshrc to be preserved without extra backup"
        fi
    else
        fail "modules/60-shell.sh Oh-My-Zsh preservation on re-run" "Expected existing Oh-My-Zsh ~/.zshrc to be preserved without extra backup"
    fi
else
    fail "modules/60-shell.sh non-Oh-My-Zsh migration" "Expected backup and Oh-My-Zsh Powerlevel10k template initialization; out='$zshrc_mig_out'"
fi
rm -rf "$TEMP_ZSHRC_HOME"

# Verify parse_subshell_results fails when 0 PASS:/FAIL: lines are parsed, Fedora --with-chrome gates on amd64, and modules/40-mise.sh fails if mise binary is not executable
if (
    TESTS_FAILED=0
    parse_subshell_results <<< "" >/dev/null 2>&1
    [ "$TESTS_FAILED" -eq 1 ]
) && (
    TESTS_FAILED=0
    parse_subshell_results <<< "unrelated noise line" >/dev/null 2>&1
    [ "$TESTS_FAILED" -eq 1 ]
); then
    pass "parse_subshell_results fails when 0 PASS:/FAIL: lines are parsed from subshell output"
else
    fail "parse_subshell_results empty guard" "Expected parse_subshell_results to record a failure on 0 parsed lines"
fi

fed_amd64_out="$(OS=fedora ARCH=amd64 INSTALL_CHROME=true SKIP_PACKAGES=true SKIP_DB=true DRY_RUN=true "$SCRIPT_DIR/setup/modules/00-packages.sh" 2>&1)"
fed_arm64_out="$(OS=fedora ARCH=arm64 INSTALL_CHROME=true SKIP_PACKAGES=true SKIP_DB=true DRY_RUN=true "$SCRIPT_DIR/setup/modules/00-packages.sh" 2>&1)"
if [[ "$fed_amd64_out" == *"google-chrome-stable"* ]] && \
   [[ "$fed_arm64_out" == *"Notice: Google Chrome official rpm is amd64 only (current: arm64). Skipping."* ]] && \
   [[ "$fed_arm64_out" != *"google-chrome-stable"* ]]; then
    pass "modules/00-packages.sh gates Fedora Google Chrome installation on amd64 and logs notice on non-amd64"
else
    fail "modules/00-packages.sh Fedora Chrome arch gate" "Unexpected output: amd64='$fed_amd64_out' arm64='$fed_arm64_out'"
fi

MISE_FAIL_BIN="$TEMP_THEME_SETUP_HOME/mise-fail-bin"
mkdir -p "$MISE_FAIL_BIN"
for util in bash sh dirname basename mkdir rm ln cp mv cat grep tr wc readlink date; do
    if command -v "$util" >/dev/null 2>&1; then
        ln -sf "$(command -v "$util")" "$MISE_FAIL_BIN/$util"
    fi
done
printf '#!/bin/sh\nexit 0\n' > "$MISE_FAIL_BIN/curl"
chmod +x "$MISE_FAIL_BIN/curl"
if PATH="$MISE_FAIL_BIN" HOME="$TEMP_THEME_SETUP_HOME" DRY_RUN=false "$SCRIPT_DIR/setup/modules/40-mise.sh" >/dev/null 2>&1; then
    fail "modules/40-mise.sh missing binary guard" "Expected non-zero exit when mise binary is not executable"
else
    pass "modules/40-mise.sh exits non-zero when mise binary is not executable"
fi

# Verify modules/99-uninstall.sh preserves user-authored custom themes in ~/.config/home-settings/themes/ while removing generated theme state
mkdir -p "$TEMP_THEME_SETUP_HOME/.config/home-settings/themes" "$TEMP_THEME_SETUP_HOME/.config/home-settings/active/ghostty"
printf 'THEME_LABEL="User Custom"\n' > "$TEMP_THEME_SETUP_HOME/.config/home-settings/themes/my-custom.theme"
HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" DRY_RUN=false "$SCRIPT_DIR/setup.sh" --uninstall >/dev/null 2>&1 || true
if [ -f "$TEMP_THEME_SETUP_HOME/.config/home-settings/themes/my-custom.theme" ] && \
   [ ! -e "$TEMP_THEME_SETUP_HOME/.config/home-settings/active-theme.theme" ] && \
   [ ! -e "$TEMP_THEME_SETUP_HOME/.config/home-settings/theme-env.sh" ] && \
   [ ! -e "$TEMP_THEME_SETUP_HOME/.config/home-settings/tmux-theme.conf" ] && \
   [ ! -d "$TEMP_THEME_SETUP_HOME/.config/home-settings/active" ]; then
    rm -f "$TEMP_THEME_SETUP_HOME/.config/home-settings/themes/my-custom.theme"
    HOME="$TEMP_THEME_SETUP_HOME" XDG_CONFIG_HOME="$TEMP_THEME_SETUP_HOME/.config" DRY_RUN=false "$SCRIPT_DIR/setup.sh" --uninstall >/dev/null 2>&1 || true
    if [ ! -d "$TEMP_THEME_SETUP_HOME/.config/home-settings" ]; then
        pass "modules/99-uninstall.sh preserves user custom themes in ~/.config/home-settings/themes/ while removing generated theme artifacts and cleaning empty directories"
    else
        fail "modules/99-uninstall.sh empty dir cleanup" "Expected ~/.config/home-settings to be removed when no custom themes remain"
    fi
else
    fail "modules/99-uninstall.sh custom theme preservation" "Custom theme was deleted or generated state remained after --uninstall"
fi

rm -rf "$TEMP_THEME_SETUP_HOME"

# Verify lint_python_embeds and lint_documentation support modular libexec/*_lib/*.py, Python-shebang bin/*, and dotfiles/.config/nvim/lua/**/*.lua
TEMP_MOD_LINT_BAD="$(make_sandbox_dir)"
mkdir -p "$TEMP_MOD_LINT_BAD/libexec/theme_lib"
printf '%s\n' 'def bad_pkg_fn(x: int | None) -> str | None:' '    return None' > "$TEMP_MOD_LINT_BAD/libexec/theme_lib/bad.py"

TEMP_MOD_SHEBANG_BAD="$(make_sandbox_dir)"
mkdir -p "$TEMP_MOD_SHEBANG_BAD/bin"
printf '%s\n' '#!/usr/bin/python3 -B' 'match 1:' '    case 1: pass' > "$TEMP_MOD_SHEBANG_BAD/bin/theme"

TEMP_MOD_LINT_OK="$(make_sandbox_dir)"
mkdir -p "$TEMP_MOD_LINT_OK/bin" "$TEMP_MOD_LINT_OK/libexec/ide_lib" "$TEMP_MOD_LINT_OK/libexec/theme_lib" "$TEMP_MOD_LINT_OK/dotfiles/.config/nvim/lua/solarized" "$TEMP_MOD_LINT_OK/dotfiles/.config/ghostty"
printf '%s\n' '#!/usr/bin/python3 -B' 'from __future__ import annotations' 'from ide_lib.core import run' > "$TEMP_MOD_LINT_OK/bin/ide"
printf '%s\n' 'from __future__ import annotations' 'def run(x: int | None = None) -> int:' '    return x or 0' > "$TEMP_MOD_LINT_OK/libexec/ide_lib/core.py"
cat > "$TEMP_MOD_LINT_OK/bin/theme" <<'EOF'
#!/usr/bin/env bash
exec python3 -B -c "import sys" "$@"
EOF
cat > "$TEMP_MOD_LINT_OK/libexec/theme_lib/cli.py" <<'EOF'
from __future__ import annotations
USAGE_TEXT = """Usage: theme
  --list          List themes
"""
EOF
cat > "$TEMP_MOD_LINT_OK/libexec/theme_lib/generators.py" <<'EOF'
from __future__ import annotations
GHOSTTY_TEMPLATE = """
keybind = ctrl+shift+d=new_split:auto
keybind = ctrl+shift+w=close_surface
keybind = ctrl+shift+enter=toggle_split_zoom
keybind = ctrl+shift+h=goto_split:left
keybind = ctrl+shift+j=goto_split:bottom
keybind = ctrl+shift+k=goto_split:top
keybind = ctrl+shift+l=goto_split:right
keybind = ctrl+shift+t=new_tab
keybind = alt+left=text:\\x1b[1;3D
keybind = alt+right=text:\\x1b[1;3C
keybind = alt+up=text:\\x1b[1;3A
keybind = alt+down=text:\\x1b[1;3B
keybind = alt+shift+left=text:\\x1b[1;4D
keybind = alt+shift+right=text:\\x1b[1;4C
keybind = alt+shift+up=text:\\x1b[1;4A
keybind = alt+shift+down=text:\\x1b[1;4B
"""
EOF
cp "$SCRIPT_DIR/dotfiles/.config/ghostty/config" "$TEMP_MOD_LINT_OK/dotfiles/.config/ghostty/config"
cp "$SCRIPT_DIR/dotfiles/.config/ghostty/keybinds.conf" "$TEMP_MOD_LINT_OK/dotfiles/.config/ghostty/keybinds.conf"
printf '%s\n' 'require("solarized.keymaps")' > "$TEMP_MOD_LINT_OK/dotfiles/.config/nvim/init.lua"
printf '%s\n' 'vim.keymap.set("n", "<leader>qm", "<cmd>echo 1<CR>")' > "$TEMP_MOD_LINT_OK/dotfiles/.config/nvim/lua/solarized/keymaps.lua"
cat > "$TEMP_MOD_LINT_OK/README.md" <<'EOF'
# Modular test

Keys: `Ctrl+Shift+D`, `Ctrl+Shift+W`, `Ctrl+Shift+Enter`, `Ctrl+Shift+H/J/K/L`, `Ctrl+Shift+T`, `Alt+Left/Right/Up/Down`, `Alt+Shift+Left/Right/Up/Down`, `Space w`, `Space h`, `Space e`, `Space E`, `Space m`, `Space ff`, `Space fg`, `Space fb`, `Space gs`, `Space rn`, `Space ca`, `Space d`, `Space a`, `Space q`, `Space ?`, `Space cd`, `gd`, `gr`, `K`, `gx`, `Home`, `H`, `L`.

## Standalone utilities

| Script | Flags |
| :--- | :--- |
| `theme` | `--list` |
| `Ctrl+Shift+D` | `Ctrl+Shift+W` `Ctrl+Shift+Enter` `Ctrl+Shift+H/J/K/L` `Ctrl+Shift+T` `Alt+Left/Right/Up/Down` `Alt+Shift+Left/Right/Up/Down` |
| `Space w` | `Space h` `Space e` `Space E` `Space m` `Space ff` `Space fg` `Space fb` `Space gs` `Space rn` `Space ca` `Space d` `Space a` `Space q` `Space ?` `Space cd` `gd` `gr` `K` `gx` `Home` `H` `L` |
EOF

mod_doc_err="$(lint_documentation "$TEMP_MOD_LINT_OK" 2>&1 || true)"
if ! lint_python_embeds "$TEMP_MOD_LINT_BAD" >/dev/null 2>&1 && \
   ! lint_python_embeds "$TEMP_MOD_SHEBANG_BAD" >/dev/null 2>&1 && \
   lint_python_embeds "$TEMP_MOD_LINT_OK" >/dev/null 2>&1 && \
   grep -Fq 'keybinding "Space qm"' <<< "$mod_doc_err" && \
   ! grep -Fq 'Ghostty keybinding' <<< "$mod_doc_err" && \
   ! grep -Fq 'theme option "--list" missing' <<< "$mod_doc_err"; then
    pass "lint_python_embeds and lint_documentation validate standalone bin/*_lib/*.py modules, Python-shebang bin/* entrypoints, and modular nvim/lua/**/*.lua keymaps"
else
    fail "Modular lint_python_embeds / lint_documentation" "Unexpected modular lint result: doc_err='$mod_doc_err'"
fi

# Verify shared lib/ primitives (backup_existing_path collision-free suffixes, retry_cmd, resolve_script_dir, prepend_path)
TEMP_LIB_SANDBOX="$(make_sandbox_dir)"
lib_unit_ok="$(
    set -euo pipefail
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/setup/lib/log.sh"
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/setup/lib/os.sh"
    printf 'v1\n' > "$TEMP_LIB_SANDBOX/conf"
    b1="$(backup_existing_path "$TEMP_LIB_SANDBOX/conf")"
    printf 'v2\n' > "$TEMP_LIB_SANDBOX/conf"
    # Force a collision with b1's exact timestamp if within the same second, or create matching base
    : > "${TEMP_LIB_SANDBOX}/conf.bak.$(date +%s)"
    b2="$(backup_existing_path "$TEMP_LIB_SANDBOX/conf")"
    tries_file="$TEMP_LIB_SANDBOX/tries"
    flaky_fn() {
        local n=0
        [ -f "$tries_file" ] && n="$(cat "$tries_file")"
        n=$((n + 1))
        printf '%s' "$n" > "$tries_file"
        [ "$n" -ge 2 ]
    }
    retry_cmd 3 0 flaky_fn
    mkdir -p "$TEMP_LIB_SANDBOX/real/bin" "$TEMP_LIB_SANDBOX/links"
    printf '#!/bin/sh\n' > "$TEMP_LIB_SANDBOX/real/bin/tool"
    ln -s "../real/bin/tool" "$TEMP_LIB_SANDBOX/links/tool-link"
    resolved_dir="$(resolve_script_dir "$TEMP_LIB_SANDBOX/links/tool-link")"
    exp_dir="$(cd -P "$TEMP_LIB_SANDBOX/real/bin" && pwd)"
    PATH="/usr/bin:/bin"
    prepend_path "/custom/a" "/custom/b" "/custom/a"
    if [ -f "$b1" ] && [ -f "$b2" ] && [ "$b1" != "$b2" ] && \
       [ "$(cat "$tries_file")" = "2" ] && \
       [ "$resolved_dir" = "$exp_dir" ] && \
       [ "$PATH" = "/custom/b:/custom/a:/usr/bin:/bin" ]; then
        printf 'OK\n'
    else
        printf 'BAD:%s|%s|%s|%s\n' "$b1" "$b2" "$resolved_dir" "$PATH"
    fi
)"
assert_eq "OK" "$lib_unit_ok" "Shared lib/ helpers handle collision-free backups, transient retries, chained symlink resolution, and deduplicated PATH prepending"

# Verify setup.sh Stage 50 (modules/50-nvim.sh) --dry-run, --skip nvim, and missing/old nvim guards
TEMP_NVIM_STAGE_HOME="$(make_sandbox_dir)"
nvim_dry_default="$(HOME="$TEMP_NVIM_STAGE_HOME" XDG_CONFIG_HOME="$TEMP_NVIM_STAGE_HOME/.config" XDG_DATA_HOME="$TEMP_NVIM_STAGE_HOME/.local/share" "$SCRIPT_DIR/setup.sh" --user --dry-run 2>&1)"
nvim_dry_skipped="$(HOME="$TEMP_NVIM_STAGE_HOME" XDG_CONFIG_HOME="$TEMP_NVIM_STAGE_HOME/.config" XDG_DATA_HOME="$TEMP_NVIM_STAGE_HOME/.local/share" "$SCRIPT_DIR/setup.sh" --user --skip nvim --dry-run 2>&1)"
NVIM_MISSING_BIN="$TEMP_NVIM_STAGE_HOME/missing-nvim-bin"
NVIM_OLD_MOCK_BIN="$TEMP_NVIM_STAGE_HOME/old-nvim-bin"
mkdir -p "$NVIM_MISSING_BIN" "$NVIM_OLD_MOCK_BIN"
for util in bash sh dirname basename mkdir rm ln cp mv cat grep tr wc readlink date; do
    if command -v "$util" >/dev/null 2>&1; then
        ln -sf "$(command -v "$util")" "$NVIM_MISSING_BIN/$util"
        ln -sf "$(command -v "$util")" "$NVIM_OLD_MOCK_BIN/$util"
    fi
done
if command -v git >/dev/null 2>&1; then
    ln -sf "$(command -v git)" "$NVIM_OLD_MOCK_BIN/git"
fi
write_mock_bin "$NVIM_OLD_MOCK_BIN" "nvim" '
for arg in "$@"; do
    case "$arg" in
        *"vim."*) exit 0 ;;
        *"!has(\"nvim-0.10\")"*cquit*) exit 1 ;;
    esac
done
exit 0'
nvim_missing_out="$(PATH="$NVIM_MISSING_BIN" HOME="$TEMP_NVIM_STAGE_HOME/empty-home" XDG_DATA_HOME="$TEMP_NVIM_STAGE_HOME/empty-home/.local/share" DRY_RUN=false /bin/bash "$SCRIPT_DIR/setup/modules/50-nvim.sh" 2>&1)"
nvim_old_out="$(PATH="$NVIM_OLD_MOCK_BIN" HOME="$TEMP_NVIM_STAGE_HOME/empty-home" XDG_DATA_HOME="$TEMP_NVIM_STAGE_HOME/empty-home/.local/share" DRY_RUN=false /bin/bash "$SCRIPT_DIR/setup/modules/50-nvim.sh" 2>&1)"
if [[ "$nvim_dry_default" == *"[DryRun] Syncing Neovim plugins from lazy-lock.json"* ]] && \
   [[ "$nvim_dry_skipped" != *"Syncing Neovim plugins from lazy-lock.json"* ]] && \
   [ ! -e "$TEMP_NVIM_STAGE_HOME/.local" ] && \
   [[ "$nvim_missing_out" == *"Notice: nvim or git not found on PATH; skipping headless plugin sync."* ]] && \
   [[ "$nvim_old_out" == *"Notice: Neovim < 0.10 detected; skipping headless plugin sync."* ]]; then
    pass "modules/50-nvim.sh honors --dry-run and --skip-nvim without mutating HOME and skips cleanly when git/nvim is missing or Neovim < 0.10"
else
    fail "modules/50-nvim.sh dry-run & guards" "default='$nvim_dry_default' skipped='$nvim_dry_skipped' missing='$nvim_missing_out' old='$nvim_old_out'"
fi

# Verify Ubuntu/Debian 3-tier Ghostty provisioning (APT repo -> Snap -> .deb fallback with suite & libc/gtk probing)
TEMP_GHOSTTY_STAGE="$(make_sandbox_dir)"
GHOSTTY_MOCK_BIN="$TEMP_GHOSTTY_STAGE/bin"
GHOSTTY_MOCK_DATA="$TEMP_GHOSTTY_STAGE/data"
mkdir -p "$GHOSTTY_MOCK_BIN" "$GHOSTTY_MOCK_DATA"
for util in bash sh awk sed grep tr cut head wc cat cp mv rm chmod mktemp uname id printf sleep curl; do
    if command -v "$util" >/dev/null 2>&1; then
        ln -sf "$(command -v "$util")" "$GHOSTTY_MOCK_BIN/$util"
    fi
done

printf 'dummy-deb-payload\n' > "$GHOSTTY_MOCK_DATA/ghostty_1.4.0-0.ppa2_amd64_forky.deb"
printf 'dummy-deb-payload\n' > "$GHOSTTY_MOCK_DATA/ghostty_1.3.1-0.ppa2_arm64_24.04.deb"
cat > "$GHOSTTY_MOCK_DATA/releases.json" <<EOF
[
  {
    "tag_name": "1.4.0-0-ppa2",
    "assets": [
      {"browser_download_url": "file://$GHOSTTY_MOCK_DATA/ghostty_1.4.0-0.ppa2_amd64_forky.deb"},
      {"browser_download_url": "file://$GHOSTTY_MOCK_DATA/ghostty_1.4.0-0.ppa2_amd64_trixie.deb"}
    ]
  },
  {
    "tag_name": "1.3.1-0-ppa2",
    "assets": [
      {"browser_download_url": "file://$GHOSTTY_MOCK_DATA/ghostty_1.3.1-0.ppa2_arm64_24.04.deb"}
    ]
  }
]
EOF

write_mock_bin "$GHOSTTY_MOCK_BIN" "sudo" '
echo "[sudo] $*"
"$@"'
write_mock_bin "$GHOSTTY_MOCK_BIN" "apt-get" '
for arg in "$@"; do
    if [ -f "$arg" ]; then
        if [ -r "$arg" ]; then
            perm="$(ls -l "$arg" 2>/dev/null | awk "{print \$1}")"
            echo "[apt-get-deb] $arg perm=$perm"
            exit 0
        fi
    fi
done
echo "[apt-get] $*"
exit 0'
if command -v ls >/dev/null 2>&1; then
    ln -sf "$(command -v ls)" "$GHOSTTY_MOCK_BIN/ls"
fi
write_mock_bin "$GHOSTTY_MOCK_BIN" "apt-cache" '
pkg="${2:-}"
case "$pkg" in
    ghostty)
        case "${MOCK_APT_GHOSTTY:-none}" in
            remote)
                printf "ghostty:\n  Installed: (none)\n  Candidate: 1.4.0-1\n  Version table:\n     1.4.0-1 500\n        500 http://archive.ubuntu.com/ubuntu resolute/universe amd64 Packages\n"
                ;;
            dpkg_only)
                printf "ghostty:\n  Installed: 1.4.0-0~ppa2\n  Candidate: 1.4.0-0~ppa2\n  Version table:\n *** 1.4.0-0~ppa2 100\n        100 /var/lib/dpkg/status\n"
                ;;
            *)
                printf "ghostty:\n  Installed: (none)\n  Candidate: (none)\n  Version table:\n"
                ;;
        esac
        ;;
    libc6)
        printf "libc6:\n  Installed: %s\n  Candidate: %s\n" "${MOCK_LIBC_VER:-2.43-1}" "${MOCK_LIBC_VER:-2.43-1}"
        ;;
    libgtk-4-1)
        printf "libgtk-4-1:\n  Installed: (none)\n  Candidate: %s\n" "${MOCK_GTK_VER:-4.22.4-1}"
        ;;
esac'
write_mock_bin "$GHOSTTY_MOCK_BIN" "dpkg-query" '
pkg="${3:-}"
if [ "$pkg" = "ghostty" ] && [ -n "${MOCK_DPKG_GHOSTTY_VER:-}" ]; then
    printf "install ok installed\t%s\n" "$MOCK_DPKG_GHOSTTY_VER"
fi
exit 0'
# Portable dpkg --compare-versions mock using python3 so tests pass on macOS as well as Linux
if command -v python3 >/dev/null 2>&1; then
    ln -sf "$(command -v python3)" "$GHOSTTY_MOCK_BIN/python3"
fi
write_mock_bin "$GHOSTTY_MOCK_BIN" "dpkg" '
if [ "${1:-}" = "--compare-versions" ]; then
    python3 - "$2" "$3" "$4" <<'\''PY'\''
import re, sys
a, op, b = sys.argv[1], sys.argv[2], sys.argv[3]
def key(v):
    v = v.split("-", 1)[0] if "~ppa" not in v else v
    parts = re.split(r"(~|[0-9]+)", v)
    out = []
    for p in parts:
        if p == "": continue
        elif p == "~": out.append((-1, ""))
        elif p.isdigit(): out.append((1, int(p)))
        else: out.append((0, p))
    return out
ka, kb = key(a), key(b)
sys.exit(0 if (ka >= kb if op == "ge" else ka == kb) else 1)
PY
    exit $?
fi
echo "[dpkg] $*"'

cat > "$GHOSTTY_MOCK_DATA/os-debian-rolling" <<'EOF'
ID=debian
VERSION_CODENAME=sid
EOF
cat > "$GHOSTTY_MOCK_DATA/os-mint-noble" <<'EOF'
ID=linuxmint
VERSION_ID="22"
UBUNTU_CODENAME=noble
EOF
cat > "$GHOSTTY_MOCK_DATA/os-debian-trixie" <<'EOF'
ID=debian
VERSION_CODENAME=trixie
EOF

ghostty_tier1_out="$(
    PATH="$GHOSTTY_MOCK_BIN" MOCK_APT_GHOSTTY=remote \
        GHOSTTY_DEB_REPO_BASE="file://$GHOSTTY_MOCK_DATA" GHOSTTY_DEB_API_URL="file://$GHOSTTY_MOCK_DATA/releases.json" \
        DRY_RUN=false \
        /bin/bash -c '. "'"$SCRIPT_DIR"'/setup/lib/log.sh"; . "'"$SCRIPT_DIR"'/setup/lib/os.sh"; . "'"$SCRIPT_DIR"'/setup/lib/pkg.sh"; install_ghostty ubuntu amd64' 2>&1
)"
ghostty_deb_rolling_out="$(
    PATH="$GHOSTTY_MOCK_BIN" MOCK_APT_GHOSTTY=dpkg_only GHOSTTY_OS_RELEASE="$GHOSTTY_MOCK_DATA/os-debian-rolling" \
        GHOSTTY_DEB_REPO_BASE="file://$GHOSTTY_MOCK_DATA" GHOSTTY_DEB_API_URL="file://$GHOSTTY_MOCK_DATA/releases.json" \
        MOCK_LIBC_VER="2.43-7" MOCK_GTK_VER="4.22.4-1" DRY_RUN=false \
        /bin/bash -c '. "'"$SCRIPT_DIR"'/setup/lib/log.sh"; . "'"$SCRIPT_DIR"'/setup/lib/os.sh"; . "'"$SCRIPT_DIR"'/setup/lib/pkg.sh"; install_ghostty ubuntu amd64' 2>&1
)"
ghostty_deb_idempotent_out="$(
    PATH="$GHOSTTY_MOCK_BIN" MOCK_APT_GHOSTTY=dpkg_only MOCK_DPKG_GHOSTTY_VER="1.4.0-0~ppa2" \
        GHOSTTY_OS_RELEASE="$GHOSTTY_MOCK_DATA/os-debian-rolling" \
        GHOSTTY_DEB_REPO_BASE="file://$GHOSTTY_MOCK_DATA" GHOSTTY_DEB_API_URL="file://$GHOSTTY_MOCK_DATA/releases.json" \
        DRY_RUN=false \
        /bin/bash -c '. "'"$SCRIPT_DIR"'/setup/lib/log.sh"; . "'"$SCRIPT_DIR"'/setup/lib/os.sh"; . "'"$SCRIPT_DIR"'/setup/lib/pkg.sh"; install_ghostty ubuntu amd64' 2>&1
)"
ghostty_deb_mint24_out="$(
    PATH="$GHOSTTY_MOCK_BIN" GHOSTTY_OS_RELEASE="$GHOSTTY_MOCK_DATA/os-mint-noble" \
        GHOSTTY_DEB_REPO_BASE="file://$GHOSTTY_MOCK_DATA" GHOSTTY_DEB_API_URL="file://$GHOSTTY_MOCK_DATA/releases.json" \
        DRY_RUN=false \
        /bin/bash -c '. "'"$SCRIPT_DIR"'/setup/lib/log.sh"; . "'"$SCRIPT_DIR"'/setup/lib/os.sh"; . "'"$SCRIPT_DIR"'/setup/lib/pkg.sh"; install_ghostty ubuntu arm64' 2>&1
)"
ghostty_deb_arch_skip_out="$(
    PATH="$GHOSTTY_MOCK_BIN" GHOSTTY_OS_RELEASE="$GHOSTTY_MOCK_DATA/os-debian-trixie" DRY_RUN=false \
        /bin/bash -c '. "'"$SCRIPT_DIR"'/setup/lib/log.sh"; . "'"$SCRIPT_DIR"'/setup/lib/os.sh"; . "'"$SCRIPT_DIR"'/setup/lib/pkg.sh"; install_ghostty ubuntu riscv64' 2>&1
)"

# Add mock snap that fails in live mode to verify automatic fallback to .deb
write_mock_bin "$GHOSTTY_MOCK_BIN" "snap" '
echo "[snap] $*"
exit 1'
ghostty_snap_dry_out="$(
    PATH="$GHOSTTY_MOCK_BIN" DRY_RUN=true \
        /bin/bash -c '. "'"$SCRIPT_DIR"'/setup/lib/log.sh"; . "'"$SCRIPT_DIR"'/setup/lib/os.sh"; . "'"$SCRIPT_DIR"'/setup/lib/pkg.sh"; install_ghostty ubuntu amd64' 2>&1
)"
ghostty_snap_fallback_out="$(
    PATH="$GHOSTTY_MOCK_BIN" GHOSTTY_OS_RELEASE="$GHOSTTY_MOCK_DATA/os-debian-rolling" \
        GHOSTTY_DEB_REPO_BASE="file://$GHOSTTY_MOCK_DATA" GHOSTTY_DEB_API_URL="file://$GHOSTTY_MOCK_DATA/releases.json" \
        DRY_RUN=false \
        /bin/bash -c '. "'"$SCRIPT_DIR"'/setup/lib/log.sh"; . "'"$SCRIPT_DIR"'/setup/lib/os.sh"; . "'"$SCRIPT_DIR"'/setup/lib/pkg.sh"; install_ghostty ubuntu amd64' 2>&1
)"

if [[ "$ghostty_tier1_out" == *"[apt-get] install -y ghostty"* ]] && \
   [[ "$ghostty_deb_rolling_out" == *"[apt-get-deb] /tmp/ghostty_amd64_forky."*".deb perm=-rw-r--r--"* ]] && \
   [[ "$ghostty_deb_idempotent_out" == *"Ghostty (1.4.0-0~ppa2) is already installed and up to date."* ]] && \
   [[ "$ghostty_deb_idempotent_out" != *"[apt-get-deb]"* ]] && \
   [[ "$ghostty_deb_mint24_out" == *"[apt-get-deb] /tmp/ghostty_arm64_24.04."*".deb perm=-rw-r--r--"* ]] && \
   [[ "$ghostty_deb_arch_skip_out" == *"Notice: Ghostty prebuilt .deb packages support amd64 and arm64 only (current: riscv64)."* ]] && \
   [[ "$ghostty_snap_dry_out" == *"snap install ghostty --classic"* ]] && \
   [[ "$ghostty_snap_fallback_out" == *"Snap Ghostty install failed; falling back to .deb package"* ]] && \
   [[ "$ghostty_snap_fallback_out" == *"[apt-get-deb] /tmp/ghostty_amd64_forky."*".deb"* ]]; then
    pass "install_ghostty on ubuntu resolves native APT candidates, Snap (with failure fallback), and Snap-less Debian/Ubuntu .deb packages idempotently"
else
    fail "install_ghostty ubuntu 3-tier provisioning" "tier1='$ghostty_tier1_out' rolling='$ghostty_deb_rolling_out' idem='$ghostty_deb_idempotent_out' mint24='$ghostty_deb_mint24_out' arch='$ghostty_deb_arch_skip_out' snap_dry='$ghostty_snap_dry_out' snap_fb='$ghostty_snap_fallback_out'"
fi

# Test 7: Managed AI CLI lifecycle hooks (setup/modules/75-ai-hooks.sh & --skip hooks)
HOOKS_HOME="$(make_sandbox_home)"
skip_hooks_out="$(HOME="$HOOKS_HOME" "$SCRIPT_DIR/setup.sh" --os ubuntu --user --skip dotfiles,bin,fonts,tools,nvim,terminal,hooks --dry-run 2>&1)"
mkdir -p "$HOOKS_HOME/.gemini/config" "$HOOKS_HOME/.gemini/antigravity-cli" "$HOOKS_HOME/.claude" "$HOOKS_HOME/.codex"
cat > "$HOOKS_HOME/.gemini/config/hooks.json" <<'EOF'
{
  "custom-lint": {
    "enabled": true
  }
}
EOF
cat > "$HOOKS_HOME/.gemini/antigravity-cli/keybindings.json" <<'EOF'
{
  "voice.toggle": ["alt+k"]
}
EOF
cat > "$HOOKS_HOME/.claude/keybindings.json" <<'EOF'
{
  "bindings": [
    {
      "context": "Chat",
      "bindings": {
        "ctrl+u": "chat:customUserAction"
      }
    }
  ]
}
EOF
cat > "$HOOKS_HOME/.claude/settings.json" <<'EOF'
{
  "model": "opus",
  "permissions": {
    "allow": ["Bash(ls)"]
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {"type": "command", "command": "ide --agent-state done"},
          {"type": "command", "command": "echo custom-stop"}
        ]
      }
    ]
  }
}
EOF
cat > "$HOOKS_HOME/.codex/config.toml" <<'EOF'
model = "o3"
notify = ["ide", "--agent-state", "done"]

[projects."/tmp/sandbox-repo"]
trust_level = "trusted"
EOF
hooks_dry_out="$(HOME="$HOOKS_HOME" DRY_RUN=true bash "$SCRIPT_DIR/setup/modules/75-ai-hooks.sh" 2>&1)"
dry_untouched=false
if grep -Fq -- "--agent-state" "$HOOKS_HOME/.claude/settings.json" && \
   grep -Fq -- "--agent-state" "$HOOKS_HOME/.codex/config.toml" && \
   ! grep -Fq "ide-state" "$HOOKS_HOME/.gemini/config/hooks.json" && \
   ! grep -Fq "subagent.jump_to_waiting" "$HOOKS_HOME/.gemini/antigravity-cli/keybindings.json" && \
   ! grep -Fq "chat:thinkingToggle" "$HOOKS_HOME/.claude/keybindings.json"; then
    dry_untouched=true
fi
HOME="$HOOKS_HOME" DRY_RUN=false bash "$SCRIPT_DIR/setup/modules/75-ai-hooks.sh" >/dev/null
HOME="$HOOKS_HOME" DRY_RUN=false bash "$SCRIPT_DIR/setup/modules/75-ai-hooks.sh" >/dev/null
hooks_merged_ok=false
if python3 -B - "$HOOKS_HOME" <<'PY'; then
import json, os, sys
h = sys.argv[1]
agy = json.load(open(os.path.join(h, ".gemini/config/hooks.json"), encoding="utf-8"))
assert "custom-lint" in agy and "ide-state" in agy, agy
for ev in ("SessionStart", "PreInvocation", "PreToolUse", "PostToolUse", "Stop"):
    assert ev in agy["ide-state"], f"missing {ev} in agy hooks"
agy_kb = json.load(open(os.path.join(h, ".gemini/antigravity-cli/keybindings.json"), encoding="utf-8"))
assert agy_kb == {"voice.toggle": ["alt+k"], "subagent.jump_to_waiting": ["alt+g"]}, agy_kb
cl = json.load(open(os.path.join(h, ".claude/settings.json"), encoding="utf-8"))
assert cl["model"] == "opus" and cl["permissions"]["allow"] == ["Bash(ls)"], cl
cl_raw = json.dumps(cl)
assert "--agent-state" not in cl_raw and "echo custom-stop" in cl_raw and "ide state done" in cl_raw, cl_raw
for ev in ("SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop"):
    assert ev in cl["hooks"], f"missing {ev} in claude hooks"
cl_kb = json.load(open(os.path.join(h, ".claude/keybindings.json"), encoding="utf-8"))
assert cl_kb == {
    "bindings": [
        {
            "context": "Chat",
            "bindings": {
                "ctrl+u": "chat:customUserAction",
                "meta+t": None,
                "alt+g": "chat:thinkingToggle",
            },
        }
    ]
}, cl_kb
cx = open(os.path.join(h, ".codex/config.toml"), encoding="utf-8").read()
assert '--agent-state' not in cx and 'notify = ["ide", "state", "done"]' in cx, cx
assert cx.index('notify = ["ide", "state", "done"]') < cx.index('[projects."/tmp/sandbox-repo"]'), cx
assert 'model = "o3"' in cx and 'trust_level = "trusted"' in cx, cx
PY
    hooks_merged_ok=true
fi
HOME="$HOOKS_HOME" DRY_RUN=false bash "$SCRIPT_DIR/setup/modules/75-ai-hooks.sh" --uninstall >/dev/null
hooks_uninstalled_ok=false
if python3 -B - "$HOOKS_HOME" <<'PY'; then
import json, os, sys
h = sys.argv[1]
agy = json.load(open(os.path.join(h, ".gemini/config/hooks.json"), encoding="utf-8"))
assert "custom-lint" in agy and "ide-state" not in agy, agy
agy_kb = json.load(open(os.path.join(h, ".gemini/antigravity-cli/keybindings.json"), encoding="utf-8"))
assert agy_kb == {"voice.toggle": ["alt+k"]}, agy_kb
cl = json.load(open(os.path.join(h, ".claude/settings.json"), encoding="utf-8"))
assert cl["model"] == "opus" and "echo custom-stop" in json.dumps(cl) and "ide state" not in json.dumps(cl), cl
cl_kb = json.load(open(os.path.join(h, ".claude/keybindings.json"), encoding="utf-8"))
assert cl_kb == {"bindings": [{"context": "Chat", "bindings": {"ctrl+u": "chat:customUserAction"}}]}, cl_kb
cx = open(os.path.join(h, ".codex/config.toml"), encoding="utf-8").read()
assert "ide" not in cx and 'model = "o3"' in cx and '[projects."/tmp/sandbox-repo"]' in cx, cx
PY
    hooks_uninstalled_ok=true
fi
OVR_HOOKS_HOME="$(make_sandbox_home)"
mkdir -p "$OVR_HOOKS_HOME/.gemini/antigravity-cli" "$OVR_HOOKS_HOME/.claude"
printf '%s\n' '{"subagent.jump_to_waiting": ["alt+x"]}' > "$OVR_HOOKS_HOME/.gemini/antigravity-cli/keybindings.json"
printf '%s\n' '{"bindings": [{"context": "Chat", "bindings": {"alt+p": "chat:thinkingToggle"}}]}' > "$OVR_HOOKS_HOME/.claude/keybindings.json"
HOME="$OVR_HOOKS_HOME" DRY_RUN=false bash "$SCRIPT_DIR/setup/modules/75-ai-hooks.sh" >/dev/null
HOME="$OVR_HOOKS_HOME" DRY_RUN=false bash "$SCRIPT_DIR/setup/modules/75-ai-hooks.sh" --uninstall >/dev/null
ovr_preserved_ok=false
if grep -Fq '"alt+x"' "$OVR_HOOKS_HOME/.gemini/antigravity-cli/keybindings.json" && \
   grep -Fq '"alt+p"' "$OVR_HOOKS_HOME/.claude/keybindings.json" && \
   ! grep -Fq '"alt+g"' "$OVR_HOOKS_HOME/.claude/keybindings.json"; then
    ovr_preserved_ok=true
fi
CLEAN_HOOKS_HOME="$(make_sandbox_home)"
HOME="$CLEAN_HOOKS_HOME" DRY_RUN=false bash "$SCRIPT_DIR/setup/modules/75-ai-hooks.sh" >/dev/null
HOME="$CLEAN_HOOKS_HOME" DRY_RUN=false bash "$SCRIPT_DIR/setup/modules/75-ai-hooks.sh" --uninstall >/dev/null
if [[ "$skip_hooks_out" != *"Configuring AI CLI lifecycle hooks"* ]] && \
   [[ "$hooks_dry_out" == *"[DryRun]"* ]] && [ "$dry_untouched" = true ] && \
   [ "$hooks_merged_ok" = true ] && [ "$hooks_uninstalled_ok" = true ] && [ "$ovr_preserved_ok" = true ] && \
   [ ! -e "$CLEAN_HOOKS_HOME/.gemini/config/hooks.json" ] && \
   [ ! -e "$CLEAN_HOOKS_HOME/.gemini/antigravity-cli/keybindings.json" ] && \
   [ ! -e "$CLEAN_HOOKS_HOME/.claude/settings.json" ] && \
   [ ! -e "$CLEAN_HOOKS_HOME/.claude/keybindings.json" ] && \
   [ ! -e "$CLEAN_HOOKS_HOME/.codex/config.toml" ]; then
    pass "setup/modules/75-ai-hooks.sh (--skip hooks) idempotently merges, migrates legacy --agent-state, reconciles agy/claude alt+g keybindings, and cleanly uninstalls while preserving user overrides"
else
    fail "setup/modules/75-ai-hooks.sh lifecycle hooks" "skip='$skip_hooks_out' dry=$dry_untouched merged=$hooks_merged_ok uninst=$hooks_uninstalled_ok ovr=$ovr_preserved_ok"
fi

test_summary
