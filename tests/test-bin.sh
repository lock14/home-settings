#!/usr/bin/env bash
# Test suite for user binaries (bin/ -> ~/.local/bin/) and compatibility shims

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/tests/test-helper.sh"

echo "========================================"
echo "Running User Binaries & Shims Tests"
echo "========================================"

# Test 1: Module syntax check
echo -e "\n[1/8] Checking module syntax..."
if bash -n "$SCRIPT_DIR/modules/20-bin.sh"; then
    pass "Syntax valid: modules/20-bin.sh"
else
    fail "modules/20-bin.sh" "bash -n returned non-zero"
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

# Test 2: Symlink creation into temporary HOME
echo -e "\n[2/8] Testing binaries symlinking into ~/.local/bin..."
TEMP_HOME=$(mktemp -d)
TMUX_TEST_TMPDIR=$(mktemp -d)
QUIT_TMPDIR=""
MOUSE_TMPDIR=""
export TMUX_TMPDIR="$TMUX_TEST_TMPDIR"
# Tear down the isolated tmux servers (by their explicit sockets, never via $TMUX) even when a check aborts
# or the run is interrupted, so no test server or Editor outlives the suite
cleanup_test_bin() {
    local dir
    for dir in "$TMUX_TEST_TMPDIR" "$QUIT_TMPDIR" "$MOUSE_TMPDIR"; do
        if [ -n "$dir" ]; then
            tmux -S "$dir/tmux-$(id -u)/default" kill-server >/dev/null 2>&1 || true
            rm -rf "$dir"
        fi
    done
    rm -rf "$TEMP_HOME"
}
trap cleanup_test_bin EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

HOME="$TEMP_HOME" "$SCRIPT_DIR/modules/20-bin.sh" >/dev/null 2>&1

for f in "$SCRIPT_DIR"/bin/*; do
    if [ -f "$f" ]; then
        name="$(basename "$f")"
        assert_symlink "$TEMP_HOME/.local/bin/$name" "$SCRIPT_DIR/bin/$name" "Symlinked: $name"
    fi
done

# Test 3: Compatibility shims (fdfind -> fd, batcat -> bat)
echo -e "\n[3/8] Testing Debian tool compatibility shims..."
TEMP_SHIM_DIR=$(mktemp -d)
touch "$TEMP_SHIM_DIR/fdfind" "$TEMP_SHIM_DIR/batcat"
chmod +x "$TEMP_SHIM_DIR/fdfind" "$TEMP_SHIM_DIR/batcat"

TEMP_SHIM_HOME=$(mktemp -d)
(
    PATH="$TEMP_SHIM_DIR:$PATH"
    HOME="$TEMP_SHIM_HOME"
    "$SCRIPT_DIR/modules/20-bin.sh" >/dev/null 2>&1
)

assert_symlink "$TEMP_SHIM_HOME/.local/bin/fd" "$TEMP_SHIM_DIR/fdfind" "Created fd shim for fdfind"
assert_symlink "$TEMP_SHIM_HOME/.local/bin/bat" "$TEMP_SHIM_DIR/batcat" "Created bat shim for batcat"

rm -rf "$TEMP_SHIM_DIR" "$TEMP_SHIM_HOME"

# Test 4: Uninstallation of binaries and shims
echo -e "\n[4/8] Testing binaries uninstallation..."
HOME="$TEMP_HOME" "$SCRIPT_DIR/modules/99-uninstall.sh" bin >/dev/null 2>&1

all_bin_unlinked=true
for f in "$SCRIPT_DIR"/bin/*; do
    if [ -f "$f" ]; then
        name="$(basename "$f")"
        if [ -L "$TEMP_HOME/.local/bin/$name" ]; then
            all_bin_unlinked=false
            fail "Unlink check" "$TEMP_HOME/.local/bin/$name is still linked"
        fi
    fi
done

if [ "$all_bin_unlinked" = true ]; then
    pass "All managed user binaries successfully removed by uninstaller"
fi

# Test 5: bin/sum process substitution and whitespace-padded delimited columns
echo -e "\n[5/8] Testing bin/sum edge cases (process substitution & padded columns)..."
SUM_PROC_OUT="$("$SCRIPT_DIR/bin/sum" -k 5 <(printf "r1 c2 c3 c4 10\nr2 c2 c3 c4 25\n"))"
assert_eq "$SUM_PROC_OUT" "35" "bin/sum supports process substitution (<(cmd)) with column selection (-k 5)"

SUM_PAD_OUT="$(printf "alpha | 12.5 \r\nbeta | 27.5 \r\n" | "$SCRIPT_DIR/bin/sum" -d '|' -k 2)"
assert_eq "$SUM_PAD_OUT" "40" "bin/sum trims whitespace and CR around delimited columns (-d '|' -k 2)"

COMMA_FILE="$TEMP_HOME/data,1.txt"
printf "15\n25\n" > "$COMMA_FILE"
SUM_COMMA_FILE_OUT="$("$SCRIPT_DIR/bin/sum" "$COMMA_FILE")"
assert_eq "$SUM_COMMA_FILE_OUT" "40" "bin/sum reads files whose paths contain commas"

SUM_NUM_ARGS_OUT="$("$SCRIPT_DIR/bin/sum" 10 -2.5 +7.5)"
assert_eq "$SUM_NUM_ARGS_OUT" "15" "bin/sum sums direct signed numeric CLI tokens"

sum_missing_stdout=""
sum_missing_stderr=""
if sum_missing_stdout="$("$SCRIPT_DIR/bin/sum" "$TEMP_HOME/no-such-file.txt" 2>"$TEMP_HOME/sum_missing.err")"; then
    fail "bin/sum nonexistent file argument" "Expected non-zero exit on nonexistent file, got stdout='$sum_missing_stdout'"
else
    sum_missing_stderr="$(cat "$TEMP_HOME/sum_missing.err")"
    if [ -z "$sum_missing_stdout" ] && grep -Fq "Error:" <<< "$sum_missing_stderr" && \
       ! "$SCRIPT_DIR/bin/sum" "$TEMP_HOME" >/dev/null 2>&1; then
        pass "bin/sum fails with non-zero exit and stderr diagnostic on nonexistent or directory arguments instead of printing 0"
    else
        fail "bin/sum error output" "Expected empty stdout and Error stderr, got stdout='$sum_missing_stdout' stderr='$sum_missing_stderr'"
    fi
fi

# Test 6: bin/ide CLI validation & headless tmux session orchestration
echo -e "\n[6/8] Testing bin/ide workspace launcher..."
IDE_HELP="$(IDE_PY_BIN="$(command -v python3)" "$SCRIPT_DIR/bin/ide" --help)"
if grep -q -- '--3pane' <<< "$IDE_HELP" && \
   grep -Fq -- '--open <FILE> [LINE]' <<< "$IDE_HELP" && \
   grep -Fq -- '--preview <FILE> [LINE]' <<< "$IDE_HELP" && \
   grep -q -- '--kill' <<< "$IDE_HELP" && \
   grep -q -- '--toggle-editor' <<< "$IDE_HELP" && \
   grep -q -- '--toggle-term' <<< "$IDE_HELP" && \
   grep -q -- '--toggle-ai' <<< "$IDE_HELP" && \
   grep -q -- '--swap' <<< "$IDE_HELP" && \
   grep -q -- '--sessions' <<< "$IDE_HELP" && \
   grep -q -- '--send' <<< "$IDE_HELP" && \
   grep -q -- '--plain' <<< "$IDE_HELP" && \
   grep -q -- '--monitor' <<< "$IDE_HELP" && \
   grep -q -- '--keys' <<< "$IDE_HELP" && \
   grep -q -- '--next-attention' <<< "$IDE_HELP" && \
   grep -q -- '--agent-state' <<< "$IDE_HELP" && \
   ! grep -q -- '--on-bell' <<< "$IDE_HELP"; then
    pass "bin/ide --help (with IDE_PY_BIN override) displays usage for 2-pane, --3pane, --open/--preview [LINE], --sessions, --next-attention, --agent-state, --send, --toggle-editor/term/ai, --swap, --keys, --kill, and --list [--plain]"
else
    fail "bin/ide --help" "Expected --3pane, --open/--preview [LINE], --sessions, --next-attention, --agent-state, --send, --toggle-editor/term/ai, --swap, --keys, --kill, and --plain (without --on-bell) in bin/ide --help output"
fi

IDE_KEYS_OUT="$("$SCRIPT_DIR/bin/ide" --keys)"
IDE_KEYS_COMPOUND_OUT="$("$SCRIPT_DIR/bin/ide" --2pane --keys)"
IDE_KEYS_PTY_OK="$(python3 - "$SCRIPT_DIR/bin/ide" <<'PY'
import fcntl, os, pty, select, subprocess, sys, termios, time
ide_bin = sys.argv[1]
def set_ctty(sfd):
    os.setsid()
    fcntl.ioctl(sfd, termios.TIOCSCTTY, 0)

def wait_noncanon(fd, deadline):
    while time.monotonic() < deadline:
        try:
            if not (termios.tcgetattr(fd)[3] & termios.ICANON):
                return True
        except OSError:
            return False
        time.sleep(0.005)
    return False

for close_seq in (b"q", b"Q", b"?", b" ", b"\r", b"\x1b", b"\x1b?", b"\x03", b"\x04"):
    mfd, sfd = pty.openpty()
    proc = subprocess.Popen(
        [ide_bin, "--keys"],
        stdin=sfd, stdout=sfd, stderr=sfd, close_fds=True,
        preexec_fn=lambda sfd=sfd: set_ctty(sfd),
    )
    os.close(sfd)
    out = b""
    deadline = time.monotonic() + 2.0
    while b"This key cheatsheet" not in out and time.monotonic() < deadline:
        r, _, _ = select.select([mfd], [], [], 0.05)
        if r:
            out += os.read(mfd, 4096)
    wait_noncanon(mfd, deadline)
    os.write(mfd, b"\x1b[A")
    time.sleep(0.05)
    wait_noncanon(mfd, time.monotonic() + 2.0)
    if proc.poll() is not None:
        os.close(mfd)
        print("FAIL:closed_on_arrow")
        sys.exit(0)
    os.write(mfd, close_seq)
    rc = proc.wait(timeout=2.0)
    os.close(mfd)
    if rc != 0:
        print(f"FAIL:seq={close_seq!r}:rc={rc}")
        sys.exit(0)
print("OK")
PY
)"
if grep -Fq "IDE Workspace & Editor Keybindings" <<< "$IDE_KEYS_OUT" && \
   [ "$IDE_KEYS_OUT" = "$IDE_KEYS_COMPOUND_OUT" ] && \
   ! "$SCRIPT_DIR/bin/ide" --keys --unknown-flag >/dev/null 2>&1 && \
   ! "$SCRIPT_DIR/bin/ide" --ai invalid-agent --keys >/dev/null 2>&1 && \
   grep -Fq "Alt+h / j / k / l" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Alt+s / Prefix+s" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Alt+Shift+S" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Alt+m / Prefix+m" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Click top bar" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Alt+Shift+E" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Alt+Shift+T" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Space a  (Visual)" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Space il (Normal)" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Space id (Normal)" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "a   (copy-mode)" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "mini.files" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "h/l or Left/Right" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Space m" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Mouse4/5 or C-o/i" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Alt+? / Prefix+?" <<< "$IDE_KEYS_OUT" && \
   [ "$(printf '%s\n' "$IDE_KEYS_OUT" | wc -l | tr -d ' ')" -le 28 ] && \
   [ "$(grep -c 'show_keys_cheatsheet()' "$SCRIPT_DIR/bin/ide")" -eq 1 ] && \
   [ "$IDE_KEYS_PTY_OK" = "OK" ]; then
    pass "bin/ide --keys renders the single-source-of-truth Solarized Dark 2-column keybinding cheatsheet (including session switcher, Alt+Shift+S attention jump, focus, swap, resize, context dispatch, mini.files, Space m, jumplist, clipboard, and quit shortcuts) within popup height and drains multi-byte escape sequences on PTY"
else
    fail "bin/ide --keys" "Missing expected keybinding sections, duplicate show_keys_cheatsheet(), line overflow, or PTY key handling failed ($IDE_KEYS_PTY_OK)"
fi

if ! "$SCRIPT_DIR/bin/ide" --unknown-flag >/dev/null 2>&1 && \
   ! "$SCRIPT_DIR/bin/ide" --on-bell >/dev/null 2>&1 && \
   ! "$SCRIPT_DIR/bin/ide" --agent-state >/dev/null 2>&1 && \
   ! "$SCRIPT_DIR/bin/ide" --agent-state bogus >/dev/null 2>&1 && \
   TMUX="" TMUX_PANE="" "$SCRIPT_DIR/bin/ide" --agent-state running >/dev/null 2>&1 && \
   TMUX="" TMUX_PANE="" "$SCRIPT_DIR/bin/ide" --next-attention >/dev/null 2>&1; then
    pass "bin/ide rejects unknown/--on-bell/invalid --agent-state flags while treating --agent-state and --next-attention outside tmux as safe exit-0 no-ops"
else
    fail "bin/ide flag validation" "Expected non-zero on unknown/--on-bell/invalid state and exit-0 outside tmux for --agent-state/--next-attention"
fi

MON_TEST_DIR="$(mktemp -d)"
for m_cmd in btop htop top; do
    printf '#!/bin/sh\necho "MONITOR:%s"\n' "$m_cmd" > "$MON_TEST_DIR/$m_cmd"
    chmod +x "$MON_TEST_DIR/$m_cmd"
done
mon_out_1="$(IDE_STRICT_PATH=1 PATH="$MON_TEST_DIR:/bin" "$SCRIPT_DIR/bin/ide" --monitor)"
mon_out_1c="$(IDE_STRICT_PATH=1 PATH="$MON_TEST_DIR:/bin" "$SCRIPT_DIR/bin/ide" --2pane --top)"
rm -f "$MON_TEST_DIR/btop"
mon_out_2="$(IDE_STRICT_PATH=1 PATH="$MON_TEST_DIR:/bin" "$SCRIPT_DIR/bin/ide" --monitor)"
rm -f "$MON_TEST_DIR/htop"
mon_out_3="$(IDE_STRICT_PATH=1 PATH="$MON_TEST_DIR:/bin" "$SCRIPT_DIR/bin/ide" --monitor)"
rm -f "$MON_TEST_DIR/top"
if [ "$mon_out_1" = "MONITOR:btop" ] && [ "$mon_out_1c" = "MONITOR:btop" ] && \
   [ "$mon_out_2" = "MONITOR:htop" ] && [ "$mon_out_3" = "MONITOR:top" ] && \
   ! IDE_STRICT_PATH=1 PATH="$MON_TEST_DIR" "$SCRIPT_DIR/bin/ide" --monitor >/dev/null 2>&1; then
    pass "bin/ide --monitor / --top resolves system monitor in strict btop -> htop -> top fallback order and fails cleanly when none are installed"
else
    fail "bin/ide --monitor fallback" "Expected btop -> htop -> top fallback, got 1='$mon_out_1' 1c='$mon_out_1c' 2='$mon_out_2' 3='$mon_out_3'"
fi
rm -rf "$MON_TEST_DIR"

if "$SCRIPT_DIR/bin/ide" --swap diagonal >/dev/null 2>&1; then
    fail "bin/ide invalid --swap direction" "Expected non-zero exit status on invalid --swap direction"
else
    pass "bin/ide rejects invalid --swap directions (enforces left, right, up, down)"
fi

if "$SCRIPT_DIR/bin/ide" "$TEMP_HOME/does-not-exist-dir" >/dev/null 2>&1; then
    fail "bin/ide missing directory" "Expected non-zero exit status on non-existent directory"
else
    pass "bin/ide rejects non-existent workspace directory"
fi

if "$SCRIPT_DIR/bin/ide" --ai invalid-agent "$TEMP_HOME" >/dev/null 2>&1; then
    fail "bin/ide invalid --ai value" "Expected non-zero exit status on unsupported --ai agent"
else
    pass "bin/ide rejects unsupported --ai agent values (enforces agy, claude, codex)"
fi

# Ctrl+click link rules come only from an untracked rules file (default ~/.config/ide/links.sh, or $IDE_LINK_RULES)
LINK_TEST_DIR="$TEMP_HOME/link-rules-test"
LINK_LOG="$LINK_TEST_DIR/opened.log"
mkdir -p "$LINK_TEST_DIR/bin" "$TEMP_HOME/.config/ide"
cat > "$LINK_TEST_DIR/bin/xdg-open" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$LINK_LOG"
EOF
chmod +x "$LINK_TEST_DIR/bin/xdg-open"
cat > "$TEMP_HOME/.config/ide/links.sh" <<'EOF'
ide_resolve_link() {
    if [[ "$1" =~ ^tkt/([0-9]+)$ ]]; then
        printf 'https://tickets.example.test/%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}
EOF
run_link_rules_case() {
    env -u XDG_CONFIG_HOME -u IDE_LINK_RULES -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT HOME="$TEMP_HOME" PATH="$LINK_TEST_DIR/bin:$PATH" DISPLAY=:99 "$@" \
        >/dev/null 2>&1 || true
}
# Default rules location; surrounding punctuation is stripped from the clicked word
run_link_rules_case "$SCRIPT_DIR/bin/ide" --open-link "" "(tkt/4242)," "$LINK_TEST_DIR"
# Words the rules decline fall through to local file handling (no such file, so nothing opens)
run_link_rules_case "$SCRIPT_DIR/bin/ide" --open-link "" "tkt/draft" "$LINK_TEST_DIR"
# $IDE_LINK_RULES replaces the default location; a missing rules file means no private rules at all
run_link_rules_case env IDE_LINK_RULES="$LINK_TEST_DIR/missing.sh" "$SCRIPT_DIR/bin/ide" --open-link "" "tkt/4343" "$LINK_TEST_DIR"
for _ in $(seq 1 40); do
    [ -s "$LINK_LOG" ] && break
    sleep 0.05
done
sleep 0.2
link_log_out="$(cat "$LINK_LOG" 2>/dev/null || true)"
if [ "$link_log_out" = "https://tickets.example.test/4242" ]; then
    pass "bin/ide --open-link resolves Ctrl+click words through untracked ide_resolve_link rules (~/.config/ide/links.sh or \$IDE_LINK_RULES) and falls through when they decline"
else
    fail "bin/ide private link rules" "Expected only https://tickets.example.test/4242 to be opened, got: ${link_log_out:-<nothing>}"
fi
rm -rf "$LINK_TEST_DIR" "$TEMP_HOME/.config/ide"

if command -v tmux >/dev/null 2>&1; then
    QUIT_TMPDIR="$(mktemp -d)"
    MOUSE_TMPDIR="$(mktemp -d)"
    export TMUX_TMPDIR="$TMUX_TEST_TMPDIR"
    export XDG_RUNTIME_DIR="$TMUX_TEST_TMPDIR"
    unset TMUX TMUX_PANE

    IDE_AI_STUB_DIR="$TEMP_HOME/ai_stubs"
    mkdir -p "$IDE_AI_STUB_DIR"
    for ai_stub in agy claude codex; do
        printf '#!/bin/sh\nexec sleep 300\n' > "$IDE_AI_STUB_DIR/$ai_stub"
        chmod +x "$IDE_AI_STUB_DIR/$ai_stub"
    done
    OLD_TMUX_PATH="$PATH"
    OLD_TMUX_SHELL="${SHELL:-}"
    export PATH="$IDE_AI_STUB_DIR:$PATH"
    export SHELL="/bin/bash"

    MAIN_WS_OUT="$TEMP_HOME/main_ws_results.txt"
    QUIT_WS_OUT="$TEMP_HOME/quit_ws_results.txt"
    MOUSE_WS_OUT="$TEMP_HOME/mouse_ws_results.txt"

    # Sub-suite A: 2-pane, ide_session_name, and 3-pane workspace lifecycle (on $TMUX_TEST_TMPDIR)
    (
        IDE_WS_2P="$TEMP_HOME/ws_2pane_test"
        IDE_WS_3P="$TEMP_HOME/ws_3pane_test"
        mkdir -p "$IDE_WS_2P" "$IDE_WS_3P"

        env -u IDE_AI_CLI "$SCRIPT_DIR/bin/ide" --2pane --detach "$IDE_WS_2P"
        if tmux has-session -t "=ws_2pane_test" 2>/dev/null; then
            pane_cnt="$(tmux list-panes -t "=ws_2pane_test:" | wc -l | tr -d ' ')"
            win_cnt="$(tmux list-windows -t "=ws_2pane_test" | wc -l | tr -d ' ')"
            env_out="$(tmux show-environment -t "=ws_2pane_test" 2>/dev/null || true)"
            if [ "$pane_cnt" = "2" ] && [ "$win_cnt" = "1" ] && grep -q "NVIM_IDE_SOCKET=" <<< "$env_out" && grep -q "NVIM_IDE_PANE=" <<< "$env_out" && grep -q "IDE_AI_PANE=" <<< "$env_out" && grep -q "IDE_AI_CLI=agy" <<< "$env_out" && grep -q "FORCE_HYPERLINK=1" <<< "$env_out"; then
                echo "PASS:bin/ide --2pane layout spawns 2 side-by-side panes (50% AI | 50% Editor) in a single window and exports NVIM_IDE_SOCKET, NVIM_IDE_PANE, IDE_AI_PANE, IDE_AI_CLI=agy, and FORCE_HYPERLINK=1"
            else
                echo "FAIL:bin/ide 2-pane layout:Expected 2 panes in 1 window and NVIM_IDE_* / IDE_AI_PANE / IDE_AI_CLI=agy / FORCE_HYPERLINK=1 env vars, got panes=$pane_cnt wins=$win_cnt env=$env_out"
            fi
            "$SCRIPT_DIR/bin/ide" --kill "ws_2pane_test" >/dev/null 2>&1
        else
            echo "FAIL:bin/ide 2-pane creation:Session ws_2pane_test was not created"
        fi

        # Verify custom session naming via ide_session_name in $IDE_LINK_RULES
        CUSTOM_RULES_FILE="$TEMP_HOME/custom_session_rules.sh"
        CUSTOM_CLIENT_DIR="$TEMP_HOME/cloud_clients/feature_alpha/monorepo_root"
        mkdir -p "$CUSTOM_CLIENT_DIR"
        cat > "$CUSTOM_RULES_FILE" <<'SH'
ide_session_name() {
    local dir="$1"
    if [[ "$dir" == */cloud_clients/*/* ]]; then
        local rem="${dir#*/cloud_clients/}"
        printf '%s\n' "${rem%%/*}"
        return 0
    fi
    return 1
}
SH
        IDE_LINK_RULES="$CUSTOM_RULES_FILE" "$SCRIPT_DIR/bin/ide" --2pane --detach "$CUSTOM_CLIENT_DIR"
        if tmux has-session -t "=feature_alpha" 2>/dev/null; then
            echo "PASS:bin/ide derives custom tmux session name via ide_session_name in \$IDE_LINK_RULES"
            "$SCRIPT_DIR/bin/ide" --kill "feature_alpha" >/dev/null 2>&1
        else
            echo "FAIL:bin/ide ide_session_name hook:Expected session 'feature_alpha' to be created for $CUSTOM_CLIENT_DIR"
        fi
        rm -rf "$CUSTOM_RULES_FILE" "$TEMP_HOME/cloud_clients"

        "$SCRIPT_DIR/bin/ide" --ai claude --detach "$IDE_WS_3P"
        if tmux has-session -t "=ws_3pane_test" 2>/dev/null; then
            pane_cnt_3="$(tmux list-panes -t "=ws_3pane_test:" | wc -l | tr -d ' ')"
            win_cnt_3="$(tmux list-windows -t "=ws_3pane_test" | wc -l | tr -d ' ')"
            env_out_3="$(tmux show-environment -t "=ws_3pane_test" 2>/dev/null || true)"
            ed_pane="$(tmux show-options -qv -t "=ws_3pane_test:" @ide_editor_pane)"
            ai_pane="$(tmux show-options -qv -t "=ws_3pane_test:" @ide_ai_pane)"
            term_pane="$(tmux show-options -qv -t "=ws_3pane_test:" @ide_term_pane)"
            main_win="$(tmux show-options -qv -t "=ws_3pane_test:" @ide_main_win)"
            initial_active="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
            win_width="$(tmux display-message -p -t "$main_win" "#{window_width}")"
            term_width="$(tmux display-message -p -t "$term_pane" "#{pane_width}")"
            if [ "$pane_cnt_3" = "3" ] && [ "$win_cnt_3" = "1" ] && [ "$initial_active" = "$ai_pane" ] && [ "$term_width" = "$win_width" ] && grep -q "IDE_TERM_PANE=" <<< "$env_out_3" && grep -q "IDE_AI_PANE=" <<< "$env_out_3" && grep -q "IDE_AI_CLI=claude" <<< "$env_out_3" && grep -q "FORCE_HYPERLINK=1" <<< "$env_out_3" && ! grep -q "IDE_TREE_PANE=" <<< "$env_out_3"; then
                echo "PASS:bin/ide default 3-pane layout spawns all 3 panes (Top-Left 50%x75% AI Agent, Top-Right 50%x75% Editor, Bottom 100%x25% Full-Width Shell) in a single window with initial focus on AI"
            else
                echo "FAIL:bin/ide 3-pane layout:Expected 3 panes in 1 window, initial_active=$ai_pane (got $initial_active), term_width=$win_width (got $term_width), IDE_TERM_PANE, IDE_AI_PANE, and IDE_AI_CLI=claude, got panes=$pane_cnt_3 wins=$win_cnt_3 env=$env_out_3"
            fi

            # Simulate outer client attach-session clearing session env vars
            tmux set-environment -t "=ws_3pane_test" -r NVIM_IDE_PANE

            # Test focus toggles (--toggle, --show-term, --show-editor), bounce-back, and zoom preservation
            "$SCRIPT_DIR/bin/ide" --toggle "ws_3pane_test"
            active_after_t1="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
            pane_cnt_after_t1="$(tmux list-panes -t "$main_win" | wc -l | tr -d ' ')"

            "$SCRIPT_DIR/bin/ide" --toggle "ws_3pane_test"
            active_after_t2="$(tmux display-message -p -t "$main_win" "#{pane_id}")"

            "$SCRIPT_DIR/bin/ide" --show-term "ws_3pane_test"
            active_after_term1="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
            "$SCRIPT_DIR/bin/ide" --show-term "ws_3pane_test"
            active_after_term2="$(tmux display-message -p -t "$main_win" "#{pane_id}")"

            "$SCRIPT_DIR/bin/ide" --show-editor "ws_3pane_test"
            active_after_ed1="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
            "$SCRIPT_DIR/bin/ide" --show-editor "ws_3pane_test"
            active_after_ed2="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
            zoom_no_ed="$(tmux display-message -p -t "$main_win" "#{window_zoomed_flag}")"

            "$SCRIPT_DIR/bin/ide" --show-editor "ws_3pane_test"
            tmux resize-pane -Z -t "$ed_pane"
            zoom_in_ed="$(tmux display-message -p -t "$main_win" "#{window_zoomed_flag}")"
            "$SCRIPT_DIR/bin/ide" --toggle "ws_3pane_test"
            active_zoom_ai="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
            zoom_in_ai="$(tmux display-message -p -t "$main_win" "#{window_zoomed_flag}")"
            "$SCRIPT_DIR/bin/ide" --show-editor "ws_3pane_test"
            active_zoom_ed="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
            zoom_back_ed="$(tmux display-message -p -t "$main_win" "#{window_zoomed_flag}")"
            tmux resize-pane -Z -t "$ed_pane"
            zoom_after_unzoom="$(tmux display-message -p -t "$main_win" "#{window_zoomed_flag}")"

            if [ "$pane_cnt_after_t1" = "3" ] && \
               [ "$active_after_t1" = "$ed_pane" ] && \
               [ "$active_after_t2" = "$ai_pane" ] && \
               [ "$active_after_term1" = "$term_pane" ] && \
               [ "$active_after_term2" = "$ai_pane" ] && \
               [ "$active_after_ed1" = "$ed_pane" ] && \
               [ "$active_after_ed2" = "$ai_pane" ] && \
               [ "$zoom_no_ed" = "0" ] && \
               [ "$zoom_in_ed" = "1" ] && \
               [ "$active_zoom_ai" = "$ai_pane" ] && [ "$zoom_in_ai" = "1" ] && \
               [ "$active_zoom_ed" = "$ed_pane" ] && [ "$zoom_back_ed" = "1" ] && \
               [ "$zoom_after_unzoom" = "0" ]; then
                echo "PASS:bin/ide --toggle, --show-term, and --show-editor focus and bounce back across AI, Editor, and Shell panes while preserving zoom state"
            else
                echo "FAIL:bin/ide focus/zoom toggles:Unexpected focus/zoom state: t1=$active_after_t1(exp $ed_pane) t2=$active_after_t2(exp $ai_pane) term1=$active_after_term1(exp $term_pane) term2=$active_after_term2(exp $ai_pane) ed1=$active_after_ed1 ed2=$active_after_ed2 z_no=$zoom_no_ed z_ed=$zoom_in_ed z_ai=$zoom_in_ai($active_zoom_ai) z_back=$zoom_back_ed($active_zoom_ed) unzoom=$zoom_after_unzoom"
            fi

            # Test non-destructive pane parking/unparking (--toggle-term, --toggle-editor, --toggle-ai) and last-pane guard
            ed_pid_0="$(tmux display-message -p -t "$ed_pane" "#{pane_pid}")"
            term_pid_0="$(tmux display-message -p -t "$term_pane" "#{pane_pid}")"
            ai_pid_0="$(tmux display-message -p -t "$ai_pane" "#{pane_pid}")"
            term_h_0="$(tmux display-message -p -t "$term_pane" "#{pane_height}")"
            main_allow_rename="$(tmux show-options -wqv -t "$main_win" allow-rename 2>/dev/null || true)"
            "$SCRIPT_DIR/bin/ide" --toggle-term "ws_3pane_test"
            panes_after_park_term="$(tmux list-panes -t "$main_win" | wc -l | tr -d ' ')"
            park_term_win="$(tmux display-message -p -t "$term_pane" "#{window_name}" 2>/dev/null || true)"
            term_parked_flag1="$(tmux show-options -qv -t "=ws_3pane_test:" @ide_term_parked 2>/dev/null || true)"
            "$SCRIPT_DIR/bin/ide" --toggle-editor "ws_3pane_test"
            panes_after_park_ed="$(tmux list-panes -t "$main_win" | wc -l | tr -d ' ')"
            park_ed_win="$(tmux display-message -p -t "$ed_pane" "#{window_name}" 2>/dev/null || true)"
            ed_parked_flag1="$(tmux show-options -qv -t "=ws_3pane_test:" @ide_ed_parked 2>/dev/null || true)"
            # Refuses to hide the last visible pane (AI)
            "$SCRIPT_DIR/bin/ide" --toggle-ai "ws_3pane_test"
            panes_after_last_guard="$(tmux list-panes -t "$main_win" | wc -l | tr -d ' ')"
            # --status-click on the Editor badge unparks Editor and focuses it; --toggle-term unparks Shell at the bottom full-width
            "$SCRIPT_DIR/bin/ide" --status-click "45" "ws_3pane_test"
            active_after_unpark_ed="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
            ed_parked_flag0="$(tmux show-options -qv -t "=ws_3pane_test:" @ide_ed_parked 2>/dev/null || true)"
            # Verify --status-click caps status-left width at 48 for session names > 42 chars
            long_sess="ws_3pane_test_very_long_session_name_exceeding_48_chars"
            tmux rename-session -t "=ws_3pane_test" "$long_sess"
            "$SCRIPT_DIR/bin/ide" --status-click "52" "$long_sess"
            active_after_long_click="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
            tmux rename-session -t "=$long_sess" "ws_3pane_test"
            "$SCRIPT_DIR/bin/ide" --toggle-term "ws_3pane_test"
            term_parked_flag0="$(tmux show-options -qv -t "=ws_3pane_test:" @ide_term_parked 2>/dev/null || true)"
            panes_after_unpark_all="$(tmux list-panes -t "$main_win" | wc -l | tr -d ' ')"
            term_w_restored="$(tmux display-message -p -t "$term_pane" "#{pane_width}")"
            term_h_restored="$(tmux display-message -p -t "$term_pane" "#{pane_height}")"
            ed_pid_1="$(tmux display-message -p -t "$ed_pane" "#{pane_pid}")"
            term_pid_1="$(tmux display-message -p -t "$term_pane" "#{pane_pid}")"
            ai_pid_1="$(tmux display-message -p -t "$ai_pane" "#{pane_pid}")"
            if [ "$main_allow_rename" = "off" ] && \
               [ "$panes_after_park_term" = "2" ] && [ "$park_term_win" = "_ide_park_term" ] && [ "$term_parked_flag1" = "1" ] && \
               [ "$panes_after_park_ed" = "1" ] && [ "$park_ed_win" = "_ide_park_editor" ] && [ "$ed_parked_flag1" = "1" ] && \
               [ "$panes_after_last_guard" = "1" ] && [ "$active_after_unpark_ed" = "$ed_pane" ] && [ "$ed_parked_flag0" = "0" ] && \
               [ "$active_after_long_click" = "$ai_pane" ] && \
               [ "$panes_after_unpark_all" = "3" ] && [ "$term_parked_flag0" = "0" ] && [ "$term_w_restored" = "$win_width" ] && [ "$term_h_restored" = "$term_h_0" ] && \
               [ "$ed_pid_0" = "$ed_pid_1" ] && [ "$term_pid_0" = "$term_pid_1" ] && [ "$ai_pid_0" = "$ai_pid_1" ]; then
                echo "PASS:bin/ide --toggle-term, --toggle-editor, --toggle-ai, and --status-click non-destructively park/unpark panes via _ide_park_<role>, track @ide_*_parked, lock main_win rename, guard the last visible pane, and restore geometry and PIDs"
            else
                echo "FAIL:bin/ide pane parking/unparking:Unexpected state: main_rename=$main_allow_rename park_term=$panes_after_park_term($park_term_win,flag=$term_parked_flag1->$term_parked_flag0) park_ed=$panes_after_park_ed($park_ed_win,flag=$ed_parked_flag1->$ed_parked_flag0) guard=$panes_after_last_guard unpark_ed=$active_after_unpark_ed long_click=$active_after_long_click all=$panes_after_unpark_all w=$term_w_restored/$win_width h=$term_h_restored/$term_h_0 pids=$ed_pid_0/$ed_pid_1,$term_pid_0/$term_pid_1,$ai_pid_0/$ai_pid_1"
            fi

            # Test directional pane swapping (--swap right|left|down|up) including horizontal wrap,
            # plus parking/unparking both top panes while vertically swapped (`--swap down`)
            tmux select-pane -t "$ai_pane"
            "$SCRIPT_DIR/bin/ide" --swap right "ws_3pane_test"
            ed_left_swap1="$(tmux display-message -p -t "$ed_pane" "#{pane_left}")"
            ai_left_swap1="$(tmux display-message -p -t "$ai_pane" "#{pane_left}")"
            swapped_flag1="$(tmux show-options -qv -t "ws_3pane_test" @ide_swapped 2>/dev/null || true)"
            "$SCRIPT_DIR/bin/ide" --swap right "ws_3pane_test"
            ed_left_swap2="$(tmux display-message -p -t "$ed_pane" "#{pane_left}")"
            ai_left_swap2="$(tmux display-message -p -t "$ai_pane" "#{pane_left}")"
            "$SCRIPT_DIR/bin/ide" --swap down "ws_3pane_test"
            ai_top_down="$(tmux display-message -p -t "$ai_pane" "#{pane_top}")"
            term_top_down="$(tmux display-message -p -t "$term_pane" "#{pane_top}")"
            "$SCRIPT_DIR/bin/ide" --toggle-term "ws_3pane_test"
            park_allow_rename="$(tmux show-options -wqv -t "$term_pane" allow-rename 2>/dev/null || true)"
            "$SCRIPT_DIR/bin/ide" --toggle-editor "ws_3pane_test"
            "$SCRIPT_DIR/bin/ide" --toggle-editor "ws_3pane_test"
            "$SCRIPT_DIR/bin/ide" --toggle-term "ws_3pane_test"
            term_top_restored="$(tmux display-message -p -t "$term_pane" "#{pane_top}")"
            ed_top_restored="$(tmux display-message -p -t "$ed_pane" "#{pane_top}")"
            ai_top_restored="$(tmux display-message -p -t "$ai_pane" "#{pane_top}")"
            ai_w_restored="$(tmux display-message -p -t "$ai_pane" "#{pane_width}")"
            tmux select-pane -t "$ai_pane"
            "$SCRIPT_DIR/bin/ide" --swap up "ws_3pane_test"
            ai_top_up="$(tmux display-message -p -t "$ai_pane" "#{pane_top}")"
            term_top_up="$(tmux display-message -p -t "$term_pane" "#{pane_top}")"
            if [ "$ed_left_swap1" = "0" ] && [ "${ai_left_swap1:-0}" -gt 0 ] && [ "$swapped_flag1" = "1" ] && \
               [ "$ai_left_swap2" = "0" ] && [ "${ed_left_swap2:-0}" -gt 0 ] && \
               [ "${ai_top_down:-0}" -gt 0 ] && [ "$term_top_down" = "0" ] && \
               [ "$park_allow_rename" = "off" ] && \
               [ "$term_top_restored" = "0" ] && [ "$ed_top_restored" = "0" ] && \
               [ "${ai_top_restored:-0}" -gt 0 ] && [ "$ai_w_restored" = "$win_width" ] && \
               [ "$ai_top_up" = "0" ] && [ "${term_top_up:-0}" -gt 0 ]; then
                echo "PASS:bin/ide --swap right/left/down/up directionally swaps panes, wraps horizontally across the top split, and preserves vertically-swapped layouts across multi-pane parking/unparking"
            else
                echo "FAIL:bin/ide --swap:Unexpected swap coordinates: swap1(ed=$ed_left_swap1,ai=$ai_left_swap1,flag=$swapped_flag1) swap2(ed=$ed_left_swap2,ai=$ai_left_swap2) down(ai_top=$ai_top_down,term_top=$term_top_down) restored(term_top=$term_top_restored,ed_top=$ed_top_restored,ai_top=$ai_top_restored,ai_w=$ai_w_restored/$win_width,rename=$park_allow_rename) up(ai_top=$ai_top_up,term_top=$term_top_up)"
            fi

            "$SCRIPT_DIR/bin/ide" --ai codex --detach "$IDE_WS_3P"
            env_out_codex="$(tmux show-environment -t "ws_3pane_test" 2>/dev/null || true)"
            "$SCRIPT_DIR/bin/ide" --ai openai --detach "$IDE_WS_3P"
            env_out_openai="$(tmux show-environment -t "ws_3pane_test" 2>/dev/null || true)"
            IDE_AI_CLI="agy" "$SCRIPT_DIR/bin/ide" --detach "$IDE_WS_3P"
            env_out_reattach="$(tmux show-environment -t "ws_3pane_test" 2>/dev/null || true)"
            opt_out_reattach="$(tmux show-options -qv -t "ws_3pane_test" @ide_ai_cli 2>/dev/null || true)"
            if grep -q "IDE_AI_CLI=codex" <<< "$env_out_codex" && \
               grep -q "IDE_AI_CLI=codex" <<< "$env_out_openai" && \
               grep -q "IDE_AI_CLI=codex" <<< "$env_out_reattach" && \
               [ "$opt_out_reattach" = "codex" ] && \
               tmux display-message -p -t "$ai_pane" "#{pane_id}" >/dev/null 2>&1; then
                echo "PASS:bin/ide updates IDE_AI_CLI across codex/openai normalization, keeps AI pane alive on respawn, and preserves @ide_ai_cli on reattach without --ai"
            else
                echo "FAIL:bin/ide IDE_AI_CLI update:Failed to update/preserve IDE_AI_CLI=codex (opt=$opt_out_reattach)"
            fi

            # Verify native Neovim auto-reload (`autoread` + `SolarizedAutoRead` `checktime`) and `<leader>e` / `<leader>E` (`mini.files`)
            if command -v nvim >/dev/null 2>&1; then
                mkdir -p "$IDE_WS_3P/subdir"
                printf "before\n" > "$IDE_WS_3P/subdir/nested.txt"
                autoread_out="$(cd "$IDE_WS_3P" && nvim --headless -u "$SCRIPT_DIR/dotfiles/.config/nvim/init.lua" \
                    -c "edit $IDE_WS_3P/subdir/nested.txt" \
                    -c "lua vim.fn.writefile({ 'after_external_edit' }, '$IDE_WS_3P/subdir/nested.txt'); vim.cmd('checktime'); local line1 = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ''; local ar = vim.o.autoread and '1' or '0'; local me = vim.fn.maparg('<leader>e', 'n') ~= '' and '1' or '0'; local mE = vim.fn.maparg('<leader>E', 'n') ~= '' and '1' or '0'; io.stdout:write('AR:' .. ar .. ' LINE:' .. line1 .. ' ME:' .. me .. ' MEE:' .. mE)" \
                    -c "qa!" 2>&1 || true)"
                if grep -Fq "AR:1 LINE:after_external_edit ME:1 MEE:1" <<< "$autoread_out"; then
                    echo "PASS:Neovim enables autoread + checktime for external AI edits and binds <leader>e / <leader>E to mini.files explorer"
                else
                    echo "FAIL:Neovim autoread / mini.files keymaps:Expected AR:1 LINE:after_external_edit ME:1 MEE:1, got: $autoread_out"
                fi
            else
                echo "PASS:Neovim autoread and mini.files skipped headless runtime check (nvim not installed on runner)"
            fi

            # Verify `bin/ide --cd <subdir>` (including over a live PTY outside tmux) and `bin/ide --cd --reset` update @ide_workdir and #{session_path} without respawning the AI pane
            mkdir -p "$IDE_WS_3P/subdir/sub2"
            ai_pid_before_cd="$(tmux display-message -p -t "$ai_pane" "#{pane_pid}")"
            "$SCRIPT_DIR/bin/ide" --cd "$IDE_WS_3P/subdir" "ws_3pane_test" >/dev/null 2>&1
            wdir_after_dive="$(tmux show-options -qv -t "ws_3pane_test" @ide_workdir 2>/dev/null || true)"
            pty_cd_ok="1"
            if command -v python3 >/dev/null 2>&1; then
                pty_cd_ok="$(python3 - "$SCRIPT_DIR/bin/ide" "$IDE_WS_3P/subdir/sub2" "ws_3pane_test" <<'PY'
import os, pty, subprocess, sys
ide_bin, sub2, sess = sys.argv[1], sys.argv[2], sys.argv[3]
mfd, sfd = pty.openpty()
env = dict(os.environ)
env.pop("TMUX", None)
env.pop("TMUX_PANE", None)
try:
    r = subprocess.run([ide_bin, "--cd", sub2, sess], stdin=sfd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env, timeout=5.0)
    print("1" if r.returncode == 0 else f"rc={r.returncode}")
except subprocess.TimeoutExpired:
    print("timeout")
finally:
    os.close(mfd)
    os.close(sfd)
PY
)"
            fi
            wdir_after_pty_dive="$(tmux show-options -qv -t "ws_3pane_test" @ide_workdir 2>/dev/null || true)"
            sess_path_after_pty_dive="$(tmux display-message -p -t "=ws_3pane_test:" "#{session_path}" 2>/dev/null || true)"
            "$SCRIPT_DIR/bin/ide" --cd --reset "ws_3pane_test" >/dev/null 2>&1
            wdir_after_reset="$(tmux show-options -qv -t "ws_3pane_test" @ide_workdir 2>/dev/null || true)"
            ai_pid_after_cd="$(tmux display-message -p -t "$ai_pane" "#{pane_pid}")"
            expected_dive_dir="$(cd "$IDE_WS_3P/subdir" && pwd -P)"
            expected_sub2_dir="$(cd "$IDE_WS_3P/subdir/sub2" && pwd -P)"
            expected_init_dir="$(cd "$IDE_WS_3P" && pwd -P)"
            if [ "$wdir_after_dive" = "$expected_dive_dir" ] && [ "$pty_cd_ok" = "1" ] && [ "$wdir_after_pty_dive" = "$expected_sub2_dir" ] && [ "$sess_path_after_pty_dive" = "$expected_sub2_dir" ] && [ "$wdir_after_reset" = "$expected_init_dir" ] && [ "$ai_pid_before_cd" = "$ai_pid_after_cd" ]; then
                echo "PASS:bin/ide --cd <dir> and --reset synchronize @ide_workdir and #{session_path} across Editor and Shell (without hanging on PTY outside tmux) without killing or respawning the AI Agent pane"
            else
                echo "FAIL:bin/ide --cd:Expected dive=$expected_dive_dir pty_cd=1($pty_cd_ok) sub2=$expected_sub2_dir($wdir_after_pty_dive/$sess_path_after_pty_dive) reset=$expected_init_dir($wdir_after_reset) ai_pid=$ai_pid_before_cd==$ai_pid_after_cd"
            fi

            # Verify `bin/ide --open-link` resolves session socket for file://#L<line>, filepath:line, trailing-colon compiler diagnostics (filepath:line:col:),
            # markdown [label](file:///...#L<start>-L<end>) in word, line-wrapped markdown [`label`](file:///truncated..., file URLs with parentheses,
            # Read(...) tool headers, collapsed 3-arg invocations (even when CWD has a subdir matching session_name), and workspace basename resolution
            printf "line1\nline2\nline3\n" > "$IDE_WS_3P/subdir/nested.txt"
            mkdir -p "$IDE_WS_3P/app/(auth)"
            printf "auth1\nauth2\nauth3\n" > "$IDE_WS_3P/app/(auth)/route.ts"
            sock_3p="$(tmux show-options -qv -t "ws_3pane_test" @ide_socket 2>/dev/null || true)"
            link_nvim_pid=""
            if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ]; then
                if ! wait_for_nvim_socket "$sock_3p" 10 1; then
                    nvim --headless --listen "$sock_3p" >/dev/null 2>&1 &
                    link_nvim_pid=$!
                    wait_for_nvim_socket "$sock_3p" 30 1 || true
                fi
            fi
            "$SCRIPT_DIR/bin/ide" --toggle "ws_3pane_test"
            if "$SCRIPT_DIR/bin/ide" --open-link "file://$IDE_WS_3P/subdir/nested.txt#L2" "" "$IDE_WS_3P" "ws_3pane_test"; then
                line_after_href="2"
                if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                    line_after_href="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                fi
                if "$SCRIPT_DIR/bin/ide" --open-link "" "(subdir/nested.txt:3:1):" "$IDE_WS_3P" "ws_3pane_test"; then
                    line_after_word="3"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_word="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    "$SCRIPT_DIR/bin/ide" --open-link "" "[nested.txt](file://$IDE_WS_3P/subdir/nested.txt#L1-L3)" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_md="1"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_md="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    "$SCRIPT_DIR/bin/ide" --open-link "" "[\`nested.txt:3\`](file://$IDE_WS_3P/subdir/truncated_wrap" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_wrap="3"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_wrap="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    "$SCRIPT_DIR/bin/ide" --toggle-editor "ws_3pane_test"
                    "$SCRIPT_DIR/bin/ide" --open-link "" "nested.txt#L2-L3" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_base="2"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_base="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    mkdir -p "$IDE_WS_3P/ws_3pane_test"
                    (cd "$IDE_WS_3P" && "$SCRIPT_DIR/bin/ide" --open-link "nested.txt:3" "$IDE_WS_3P" "ws_3pane_test")
                    rmdir "$IDE_WS_3P/ws_3pane_test"
                    line_after_collapsed="3"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_collapsed="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    "$SCRIPT_DIR/bin/ide" --open-link "" "Read($IDE_WS_3P/subdir/nested.txt:1)" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_tool="1"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_tool="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    "$SCRIPT_DIR/bin/ide" --open-link "" "[route.ts](file://$IDE_WS_3P/app/(auth)/route.ts#L2)" "$IDE_WS_3P" "ws_3pane_test"
                    buf_after_paren_file="route.ts:2"
                    buf_after_jump_back="nested.txt:1"
                    buf_after_jump_fwd="route.ts:2"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        bname="$(basename "$(nvim --headless --server "$sock_3p" --remote-expr "expand('%:p')" 2>/dev/null | tr -d '\r\n\"' || true)")"
                        bline="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                        buf_after_paren_file="${bname}:${bline}"
                        nvim --headless --server "$sock_3p" --remote-send "<C-\\><C-n><C-o>" >/dev/null 2>&1 || true
                        bname_back="$(basename "$(nvim --headless --server "$sock_3p" --remote-expr "expand('%:p')" 2>/dev/null | tr -d '\r\n\"' || true)")"
                        bline_back="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                        buf_after_jump_back="${bname_back}:${bline_back}"
                        nvim --headless --server "$sock_3p" --remote-send "<C-\\><C-n><C-i>" >/dev/null 2>&1 || true
                        bname_fwd="$(basename "$(nvim --headless --server "$sock_3p" --remote-expr "expand('%:p')" 2>/dev/null | tr -d '\r\n\"' || true)")"
                        bline_fwd="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                        buf_after_jump_fwd="${bname_fwd}:${bline_fwd}"
                    fi
                    "$SCRIPT_DIR/bin/ide" --open-link "file://myhost.local$IDE_WS_3P/subdir/nested.txt#L2:1-L3:5" "" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_host_col_hash="2"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_host_col_hash="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    "$SCRIPT_DIR/bin/ide" --open-link "" "subdir/nested.txt:L3" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_colon_l="3"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_colon_l="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    "$SCRIPT_DIR/bin/ide" --open-link "file://$IDE_WS_3P/subdir/nested.txt#section:1" "\`nested.txt:2-3\`" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_href_word_line="2"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_href_word_line="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    printf "h1\nh2\nh3\n" > "$IDE_WS_3P/subdir/foo#bar.txt"
                    "$SCRIPT_DIR/bin/ide" --open-link "" "subdir/foo#bar.txt:3" "$IDE_WS_3P" "ws_3pane_test"
                    buf_after_hash_file="foo#bar.txt:3"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        bname="$(basename "$(nvim --headless --server "$sock_3p" --remote-expr "expand('%:p')" 2>/dev/null | tr -d '\r\n\"' || true)")"
                        bline="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                        buf_after_hash_file="${bname}:${bline}"
                    fi
                    printf "# Intro\n\n### Linux & macOS\n" > "$IDE_WS_3P/subdir/doc.md"
                    "$SCRIPT_DIR/bin/ide" --open-link "subdir/doc.md#linux--macos" "" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_md_file_anchor="3"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_md_file_anchor="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    "$SCRIPT_DIR/bin/ide" --open-link "#intro" "" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_md_anchor="1"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_md_anchor="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    OSC8_RULES_FILE="$TEMP_HOME/osc8_file_rules.sh"
                    cat > "$OSC8_RULES_FILE" <<SH
ide_resolve_link() {
    if [[ "\$1" =~ ^https://code\.example\.test/view/([^?]+)\?l=([0-9]+)\$ ]]; then
        printf 'file://%s/%s#L%s\n' "$IDE_WS_3P" "\${BASH_REMATCH[1]}" "\${BASH_REMATCH[2]}"
        return 0
    fi
    if [[ "\$1" == "//pkg/subdir/nested.txt:3" ]]; then
        printf 'file://%s/subdir/nested.txt#L3\n' "$IDE_WS_3P"
        return 0
    fi
    if [[ "\$1" == "//pkg/subdir/..." ]]; then
        printf 'file://%s/subdir/nested.txt#L1\n' "$IDE_WS_3P"
        return 0
    fi
    return 1
}
SH
                    IDE_LINK_RULES="$OSC8_RULES_FILE" "$SCRIPT_DIR/bin/ide" --open-link "https://code.example.test/view/subdir/nested.txt?l=2" "nested.txt" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_osc8_rule="2"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_osc8_rule="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    IDE_LINK_RULES="$OSC8_RULES_FILE" "$SCRIPT_DIR/bin/ide" --open-link "" "\`//pkg/subdir/nested.txt:3\`" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_root_ref="3"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_root_ref="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    IDE_LINK_RULES="$OSC8_RULES_FILE" "$SCRIPT_DIR/bin/ide" --open-link "" "(//pkg/subdir/...)." "$IDE_WS_3P" "ws_3pane_test"
                    line_after_root_wildcard="1"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_root_wildcard="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    rm -f "$OSC8_RULES_FILE"
                    # Verify line-wrapped URLs in an unfocused tmux pane (e.g. broken after 'home-' onto an indented next line in $term_pane while $ed_pane is active)
                    # are stitched back together when clicking either the first line or the continuation line,
                    # and 1st-character split OSC 8 links (\e]8;id=...;file://...\e\\p\e]8;;\e\\arse_file_target) are recovered when clicking chars 2..N.
                    WRAP_BROWSER_OUT="$TEMP_HOME/wrap_browser.out"
                    WRAP_BROWSER_BIN="$TEMP_HOME/wrap_browser.sh"
                    printf '#!/usr/bin/env bash\necho "$1" >> "%s"\n' "$WRAP_BROWSER_OUT" > "$WRAP_BROWSER_BIN"
                    chmod +x "$WRAP_BROWSER_BIN"
                    tmux select-pane -t "$ed_pane"
                    tmux send-keys -t "$term_pane" " printf '  Submitted PR (https://github.com/lock14/home-\\n  settings/pull/118)\\n  \\033]8;id=test;file://$IDE_WS_3P/subdir/nested.txt#L3\\033\\\\p\\033]8;;\\033\\\\arse_file_target\\n  \\033]8;id=sep;file://$IDE_WS_3P/subdir/nested.txt#L2\\033\\\\#\\033]8;;\\033\\\\{mouse_hyperlink}\\n  \\033]8;id=wrap;file://$IDE_WS_3P/subdir/nested.txt#L3\\033\\\\w\\033]8;;\\033\\\\rapped_sym_\\n  continuation\\n  \\033[36m\\033]8;id=sgr;file://$IDE_WS_3P/subdir/nested.txt#L1\\033\\\\C\\033]8;;\\033\\\\lass\\033[39m.\\033[32mmethod\\033[0m\\n  \\033[32mfeat/pr-link\\033]8;;https://gitlab.com/org/project/-/merge_requests/42\\033\\\\\\033[90m@\\033[32m42\\033]8;;\\033\\\\*\\033[0m\\n'" C-m
                    for _ in $(seq 1 100); do
                        tmux capture-pane -p -t "$term_pane" 2>/dev/null | grep -Fq "feat/pr-link@42" && break
                        sleep 0.02
                    done
                    IDE_BROWSER="$WRAP_BROWSER_BIN" "$SCRIPT_DIR/bin/ide" --open-link "" "https://github.com/lock14/home-" "$IDE_WS_3P" "ws_3pane_test"
                    IDE_BROWSER="$WRAP_BROWSER_BIN" "$SCRIPT_DIR/bin/ide" --open-link "" "settings/pull/118" "$IDE_WS_3P" "ws_3pane_test"
                    IDE_BROWSER="$WRAP_BROWSER_BIN" "$SCRIPT_DIR/bin/ide" --open-link "" "feat/pr-link@42*" "$IDE_WS_3P" "ws_3pane_test"
                    for _ in $(seq 1 100); do
                        [ "$(wc -l < "$WRAP_BROWSER_OUT" 2>/dev/null | tr -d ' ')" = "3" ] && break
                        sleep 0.02
                    done
                    wrap_url_line1="$(sed -n '1p' "$WRAP_BROWSER_OUT" 2>/dev/null || true)"
                    wrap_url_line2="$(sed -n '2p' "$WRAP_BROWSER_OUT" 2>/dev/null || true)"
                    sfx_osc8_pr_url="$(sed -n '3p' "$WRAP_BROWSER_OUT" 2>/dev/null || true)"
                    rm -f "$WRAP_BROWSER_OUT" "$WRAP_BROWSER_BIN"
                    tmux select-pane -t "$term_pane"
                    "$SCRIPT_DIR/bin/ide" --open-link "" "parse_file_target" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_split_osc8="3"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_split_osc8="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    tmux select-pane -t "$term_pane"
                    "$SCRIPT_DIR/bin/ide" --open-link "" "Class.method" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_split_sgr="1"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_split_sgr="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    tmux select-pane -t "$term_pane"
                    "$SCRIPT_DIR/bin/ide" --open-link "" "mouse_hyperlink" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_split_sep="2"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_split_sep="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    tmux select-pane -t "$term_pane"
                    "$SCRIPT_DIR/bin/ide" --open-link "" "continuation" "$IDE_WS_3P" "ws_3pane_test"
                    line_after_split_wrap="3"
                    if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                        line_after_split_wrap="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    fi
                    tmux select-pane -t "$ed_pane"
                    active_after_link="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
                    if [ "$active_after_link" = "$ed_pane" ] && [ "$line_after_href" = "2" ] && [ "$line_after_word" = "3" ] && [ "$line_after_md" = "1" ] && [ "$line_after_wrap" = "3" ] && [ "$line_after_base" = "2" ] && [ "$line_after_collapsed" = "3" ] && [ "$line_after_tool" = "1" ] && [ "$buf_after_paren_file" = "route.ts:2" ] && [ "$buf_after_jump_back" = "nested.txt:1" ] && [ "$buf_after_jump_fwd" = "route.ts:2" ] && [ "$line_after_host_col_hash" = "2" ] && [ "$line_after_colon_l" = "3" ] && [ "$line_after_href_word_line" = "2" ] && [ "$buf_after_hash_file" = "foo#bar.txt:3" ] && [ "$line_after_md_file_anchor" = "3" ] && [ "$line_after_md_anchor" = "1" ] && [ "$line_after_osc8_rule" = "2" ] && [ "$line_after_root_ref" = "3" ] && [ "$line_after_root_wildcard" = "1" ] && [ "$wrap_url_line1" = "https://github.com/lock14/home-settings/pull/118" ] && [ "$wrap_url_line2" = "https://github.com/lock14/home-settings/pull/118" ] && [ "$sfx_osc8_pr_url" = "https://gitlab.com/org/project/-/merge_requests/42" ] && [ "$line_after_split_osc8" = "3" ] && [ "$line_after_split_sgr" = "1" ] && [ "$line_after_split_sep" = "2" ] && [ "$line_after_split_wrap" = "3" ]; then
                        echo "PASS:bin/ide --open-link handles file://#L<line>, file://host/path#L<line>:<col>-L<end>:<col>, filepath:L<line>, file:// href + word:line-end, filenames with '#', Markdown #anchor and file.md#anchor heading jumps, ide_resolve_link http(s)://->file:// & //pkg/... rewrites, compiler paths (filepath:line:col:), markdown [label](file:///...#L1-L3), single-step jumplist Back/Forward (<C-o>/<C-i>, Mouse4/Mouse5), line-wrapped URLs across unfocused panes, 1st-character and suffix split OSC 8 links (recover_split_osc8_href including mid-token SGR, word-separator prefixes, <branch>@<N> PR links, and wrapped continuations), file URLs with parentheses, Read(...) tool headers, collapsed empty-href args (with matching CWD subdir), and workspace basenames (unparking Editor if hidden)"
                    else
                        echo "FAIL:bin/ide --open-link focus/line:Expected active=$ed_pane, paren=route.ts:2, jump_back=nested.txt:1, jump_fwd=route.ts:2, hash=foo#bar.txt:3, md_anchor=3/1, osc8_rule=2/3/1, wrapped URLs=https://github.com/lock14/home-settings/pull/118, sfx_pr=https://gitlab.com/org/project/-/merge_requests/42, split_osc8=3/1/2/3, and lines 2/3/1/3/2/3/1/2/3/2, got active=$active_after_link href=$line_after_href word=$line_after_word md=$line_after_md wrap=$line_after_wrap base=$line_after_base collapsed=$line_after_collapsed tool=$line_after_tool paren=$buf_after_paren_file back=$buf_after_jump_back fwd=$buf_after_jump_fwd host_col=$line_after_host_col_hash colon_l=$line_after_colon_l href_word=$line_after_href_word_line hash=$buf_after_hash_file md_anchor=$line_after_md_file_anchor/$line_after_md_anchor osc8_rule=$line_after_osc8_rule/$line_after_root_ref/$line_after_root_wildcard wrap1=$wrap_url_line1 wrap2=$wrap_url_line2 sfx_pr=$sfx_osc8_pr_url split_osc8=$line_after_split_osc8/$line_after_split_sgr/$line_after_split_sep/$line_after_split_wrap"
                    fi
                else
                    echo "FAIL:bin/ide --open-link filepath:line:col::Command failed on filepath:line:col:"
                fi
            else
                echo "FAIL:bin/ide --open-link file://#L<line>:Command failed on file://#L<line>"
            fi

            # Verify `bin/ide --open <file> [line]`, `--preview <file> [line]`, `file:line:col`, `file#Lline`, and literal colon filenames
            printf "c1\nc2\nc3\n" > "$IDE_WS_3P/subdir/colon:file.txt"
            tmux select-pane -t "$ai_pane"
            "$SCRIPT_DIR/bin/ide" --open "$IDE_WS_3P/subdir/nested.txt" 3 "ws_3pane_test"
            open_pos_focus="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
            open_pos_line="3"
            if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                open_pos_line="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
            fi
            tmux select-pane -t "$ai_pane"
            (cd /tmp && "$SCRIPT_DIR/bin/ide" --open "subdir/nested.txt:2:1" "ws_3pane_test")
            open_col_focus="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
            open_col_line="2"
            if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                open_col_line="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
            fi
            tmux select-pane -t "$ai_pane"
            "$SCRIPT_DIR/bin/ide" --preview "$IDE_WS_3P/subdir/nested.txt" 1 "ws_3pane_test"
            prev_pos_focus="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
            prev_pos_line="1"
            if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                prev_pos_line="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
            fi
            (cd /tmp && "$SCRIPT_DIR/bin/ide" --preview "subdir/nested.txt#L3" "ws_3pane_test")
            prev_hash_focus="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
            prev_hash_line="3"
            if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                prev_hash_line="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
            fi
            "$SCRIPT_DIR/bin/ide" --open "$IDE_WS_3P/subdir/colon:file.txt" 2 "ws_3pane_test"
            colon_buf="colon:file.txt:2"
            if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                cbname="$(basename "$(NVIM_LOG_FILE=/dev/null nvim --headless --server "$sock_3p" --remote-expr "expand('%:p')" 2>/dev/null | tr -d '\r\n\"' || true)")"
                cbline="$(NVIM_LOG_FILE=/dev/null nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                colon_buf="${cbname}:${cbline}"
            fi
            mkdir -p "$IDE_WS_3P/dir:v1"
            printf "m1\nm2\nm3\n" > "$IDE_WS_3P/dir:v1/colon:mod.txt"
            "$SCRIPT_DIR/bin/ide" --open "$IDE_WS_3P/dir:v1/colon:mod.txt:3" "ws_3pane_test"
            colon_dir_buf="colon:mod.txt:3"
            if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                cdbname="$(basename "$(NVIM_LOG_FILE=/dev/null nvim --headless --server "$sock_3p" --remote-expr "expand('%:p')" 2>/dev/null | tr -d '\r\n\"' || true)")"
                cdbline="$(NVIM_LOG_FILE=/dev/null nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                colon_dir_buf="${cdbname}:${cdbline}"
            fi
            if [ "$open_pos_focus" = "$ed_pane" ] && [ "$open_pos_line" = "3" ] && \
               [ "$open_col_focus" = "$ed_pane" ] && [ "$open_col_line" = "2" ] && \
               [ "$prev_pos_focus" = "$ai_pane" ] && [ "$prev_pos_line" = "1" ] && \
               [ "$prev_hash_focus" = "$ai_pane" ] && [ "$prev_hash_line" = "3" ] && \
               [ "$colon_buf" = "colon:file.txt:2" ] && \
               [ "$colon_dir_buf" = "colon:mod.txt:3" ]; then
                echo "PASS:bin/ide --open and --preview support optional [LINE], file:line:col, file#Lline, workspace-relative paths, and literal colon paths/filenames while preserving non-focus preview"
            else
                echo "FAIL:bin/ide --open/--preview:Expected ed=$ed_pane ai=$ai_pane lines 3/2/1/3 colon:file.txt:2 colon:mod.txt:3, got open_pos=$open_pos_focus:$open_pos_line open_col=$open_col_focus:$open_col_line prev_pos=$prev_pos_focus:$prev_pos_line prev_hash=$prev_hash_focus:$prev_hash_line colon=$colon_buf colon_dir=$colon_dir_buf"
            fi

            if [ -n "$link_nvim_pid" ]; then
                kill "$link_nvim_pid" 2>/dev/null || true
                rm -f "$sock_3p"
            fi

            # Verify `bin/ide --copy`, `bin/ide --paste`, SSH URL OSC 52 copy, and local <-> SSH session re-attachment env sync
            COPY_MOCK_DIR="$(mktemp -d)"
            cat > "$COPY_MOCK_DIR/xsel" <<'SH'
#!/usr/bin/env bash
[ "${DISPLAY:-}" = ":99" ] || exit 1
if [ "${1:-}" = "-ib" ]; then
    cat > "$COPY_XSEL_OUT"
    exit 0
fi
if [ "${1:-}" = "-ob" ]; then
    printf "from-xsel-clipboard"
    exit 0
fi
if [ "${1:-}" = "-op" ]; then
    printf "from-xsel-primary"
    exit 0
fi
exit 1
SH
            cat > "$COPY_MOCK_DIR/open" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$COPY_BROWSER_OUT"
exit 0
SH
            cat > "$COPY_MOCK_DIR/xdg-open" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$COPY_BROWSER_OUT"
exit 0
SH
            chmod +x "$COPY_MOCK_DIR/xsel" "$COPY_MOCK_DIR/open" "$COPY_MOCK_DIR/xdg-open"
            tmux set-environment -t "=ws_3pane_test" -r DISPLAY 2>/dev/null || true
            for ssh_v in SSH_CONNECTION SSH_TTY SSH_CLIENT; do
                tmux set-environment -g -r "$ssh_v" 2>/dev/null || true
                tmux set-environment -t "=ws_3pane_test" -r "$ssh_v" 2>/dev/null || true
            done
            tmux set-environment -g DISPLAY ":99"
            printf "solarized-clipboard-payload" | env -u DISPLAY -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT COPY_XSEL_OUT="$COPY_MOCK_DIR/xsel_out" PATH="$COPY_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/ide" --copy
            copy_tmux_got="$(tmux show-buffer 2>/dev/null || true)"
            copy_xsel_got="$(cat "$COPY_MOCK_DIR/xsel_out" 2>/dev/null || true)"
            rm -f "$COPY_MOCK_DIR/xsel_out"
            printf "ssh-copy-payload" | env -u DISPLAY SSH_CONNECTION="10.0.0.1 1234 10.0.0.2 22" COPY_XSEL_OUT="$COPY_MOCK_DIR/xsel_out" PATH="$COPY_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/ide" --copy
            copy_ssh_tmux_got="$(tmux show-buffer 2>/dev/null || true)"
            copy_ssh_xsel_got="$(cat "$COPY_MOCK_DIR/xsel_out" 2>/dev/null || true)"
            env -u DISPLAY -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT PATH="$COPY_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/ide" --paste "$term_pane"
            paste_local_got="$(tmux show-buffer 2>/dev/null || true)"
            tmux set-buffer "from-tmux-ssh-buf"
            env -u DISPLAY SSH_CONNECTION="10.0.0.1 1234 10.0.0.2 22" PATH="$COPY_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/ide" --paste "$term_pane"
            paste_ssh_got="$(tmux show-buffer 2>/dev/null || true)"
            # Simulate re-attaching to the existing local session over SSH (`ide --detach "$IDE_WS_3P"`)
            env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY SSH_CONNECTION="10.0.0.1 4321 10.0.0.2 22" "$SCRIPT_DIR/bin/ide" --detach "$IDE_WS_3P"
            rm -f "$COPY_MOCK_DIR/xsel_out"
            printf "ssh-reattach-copy" | env -u DISPLAY -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT COPY_XSEL_OUT="$COPY_MOCK_DIR/xsel_out" PATH="$COPY_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/ide" --copy
            copy_ssh_sess_tmux_got="$(tmux show-buffer 2>/dev/null || true)"
            copy_ssh_sess_xsel_got="$(cat "$COPY_MOCK_DIR/xsel_out" 2>/dev/null || true)"
            tmux set-buffer "from-tmux-ssh-sess-env"
            env -u DISPLAY -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT PATH="$COPY_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/ide" --paste "$term_pane"
            paste_ssh_sess_got="$(tmux show-buffer 2>/dev/null || true)"
            env -u DISPLAY -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT -u IDE_BROWSER COPY_BROWSER_OUT="$COPY_MOCK_DIR/browser_out" PATH="$COPY_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/ide" --open-link "https://example.com/ssh-osc52" "" "$IDE_WS_3P" "ws_3pane_test"
            ssh_url_buf_got="$(tmux show-buffer 2>/dev/null || true)"
            ssh_browser_got="$(cat "$COPY_MOCK_DIR/browser_out" 2>/dev/null || true)"
            # Simulate re-attaching back on local desktop (`DISPLAY=:99`, no `SSH_*`, clearing stale `WAYLAND_DISPLAY=wayland-stale`)
            tmux set-environment -t "=ws_3pane_test" WAYLAND_DISPLAY "wayland-stale"
            tmux set-environment -g WAYLAND_DISPLAY "wayland-stale"
            env -u WAYLAND_DISPLAY -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT DISPLAY=":99" "$SCRIPT_DIR/bin/ide" --detach "$IDE_WS_3P"
            wayland_after_reattach="$(tmux show-environment -t "=ws_3pane_test" WAYLAND_DISPLAY 2>/dev/null || true)$(tmux show-environment -g WAYLAND_DISPLAY 2>/dev/null || true)"
            rm -f "$COPY_MOCK_DIR/xsel_out"
            printf "local-reattach-copy" | env -u DISPLAY -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT COPY_XSEL_OUT="$COPY_MOCK_DIR/xsel_out" PATH="$COPY_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/ide" --copy
            copy_reattach_local_xsel_got="$(cat "$COPY_MOCK_DIR/xsel_out" 2>/dev/null || true)"
            tmux set-buffer "stale-ssh-buf"
            env -u DISPLAY -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT PATH="$COPY_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/ide" --paste "$term_pane"
            paste_reattach_local_got="$(tmux show-buffer 2>/dev/null || true)"
            tmux set-environment -t "=ws_3pane_test" -r DISPLAY 2>/dev/null || true
            tmux set-environment -gu DISPLAY 2>/dev/null || true
            rm -rf "$COPY_MOCK_DIR"
            if [ "$copy_tmux_got" = "solarized-clipboard-payload" ] && [ "$copy_xsel_got" = "solarized-clipboard-payload" ] && \
               [ "$copy_ssh_tmux_got" = "ssh-copy-payload" ] && [ -z "$copy_ssh_xsel_got" ] && \
               [ "$paste_local_got" = "from-xsel-clipboard" ] && [ "$paste_ssh_got" = "from-tmux-ssh-buf" ] && \
               [ "$copy_ssh_sess_tmux_got" = "ssh-reattach-copy" ] && [ -z "$copy_ssh_sess_xsel_got" ] && \
               [ "$paste_ssh_sess_got" = "from-tmux-ssh-sess-env" ] && \
               [ "$ssh_url_buf_got" = "https://example.com/ssh-osc52" ] && [ -z "$ssh_browser_got" ] && \
               [[ "$wayland_after_reattach" != *"wayland-stale"* ]] && \
               [ "$copy_reattach_local_xsel_got" = "local-reattach-copy" ] && \
               [ "$paste_reattach_local_got" = "from-xsel-clipboard" ]; then
                echo "PASS:bin/ide --copy discovers DISPLAY from tmux and broadcasts to OSC 52 + X11 (skipping X11 over SSH), --paste prioritizes CLIPBOARD over PRIMARY on local desktop and tmux buffer over SSH, --open-link copies URLs via OSC 52 without launching local browsers over SSH, and local <-> SSH re-attachment synchronizes session & global env"
            else
                echo "FAIL:bin/ide --copy / --paste:Expected copy='solarized-clipboard-payload', ssh_copy='ssh-copy-payload' (xsel=''), paste_local='from-xsel-clipboard', paste_ssh='from-tmux-ssh-buf', copy_ssh_sess='ssh-reattach-copy' (xsel=''), paste_ssh_sess='from-tmux-ssh-sess-env', ssh_url='https://example.com/ssh-osc52' (browser=''), wayland!='WAYLAND_DISPLAY=wayland-stale', copy_reattach_local='local-reattach-copy', reattach_local='from-xsel-clipboard', got tmux='$copy_tmux_got' xsel='$copy_xsel_got' ssh_tmux='$copy_ssh_tmux_got' ssh_xsel='$copy_ssh_xsel_got' local='$paste_local_got' ssh='$paste_ssh_got' ssh_sess_copy='$copy_ssh_sess_tmux_got/$copy_ssh_sess_xsel_got' ssh_sess='$paste_ssh_sess_got' ssh_url='$ssh_url_buf_got' browser='$ssh_browser_got' wayland='$wayland_after_reattach' copy_reattach='$copy_reattach_local_xsel_got' reattach_local='$paste_reattach_local_got'"
            fi

            # Verify untagged pane recovery and self-healing Editor
            tmux set-option -u -t "ws_3pane_test" @ide_term_pane 2>/dev/null || true
            tmux set-environment -t "ws_3pane_test" -r IDE_TERM_PANE 2>/dev/null || true
            tmux set-option -p -u -t "$term_pane" @ide_role 2>/dev/null || true
            "$SCRIPT_DIR/bin/ide" --show-term "ws_3pane_test"
            recovered_term_pane="$(tmux show-options -qv -t "ws_3pane_test" @ide_term_pane 2>/dev/null || true)"
            recovered_pane_cnt="$(tmux list-panes -t "$main_win" | wc -l | tr -d ' ')"

            tmux kill-pane -t "$ed_pane" 2>/dev/null || true
            "$SCRIPT_DIR/bin/ide" --focus-editor "ws_3pane_test"
            healed_ed_pane="$(tmux show-options -qv -t "ws_3pane_test" @ide_editor_pane 2>/dev/null || true)"
            healed_ed_left="$(tmux display-message -p -t "$healed_ed_pane" "#{pane_left}" 2>/dev/null || echo 0)"
            healed_ed_top="$(tmux display-message -p -t "$healed_ed_pane" "#{pane_top}" 2>/dev/null || echo 1)"
            healed_pane_cnt="$(tmux list-panes -t "$main_win" | wc -l | tr -d ' ')"
            tmux respawn-pane -k -t "$healed_ed_pane" 2>/dev/null || true
            tmux set-option -p -u -t "$healed_ed_pane" @ide_nvim_launch_ts 2>/dev/null || true
            rm -f "$sock_3p"
            REVIVE_STUB_DIR="$TEMP_HOME/revive_nvim_stub"
            mkdir -p "$REVIVE_STUB_DIR"
            printf '#!/usr/bin/env bash\nexit 0\n' > "$REVIVE_STUB_DIR/nvim"
            chmod +x "$REVIVE_STUB_DIR/nvim"
            PATH="$PATH:$REVIVE_STUB_DIR" "$SCRIPT_DIR/bin/ide" --show-editor "ws_3pane_test"
            rm -rf "$REVIVE_STUB_DIR"
            revived_active_pane="$(tmux display-message -p -t "$main_win" "#{pane_id}" 2>/dev/null || true)"
            if [ "$recovered_pane_cnt" = "3" ] && [ "$recovered_term_pane" = "$term_pane" ] && \
               [ "$healed_pane_cnt" = "3" ] && [ "${healed_ed_left:-0}" -gt 0 ] && [ "${healed_ed_top:-1}" = "0" ] && \
               [ "$revived_active_pane" = "$healed_ed_pane" ]; then
                echo "PASS:bin/ide recovers untagged existing panes without duplicating, self-heals Right Full-Height Editor pane if closed, and revives exited Neovim in-place on --show-editor"
            else
                echo "FAIL:bin/ide Editor pane self-heal / untagged recovery:Expected recovered_term=$term_pane (got $recovered_term_pane, panes=$recovered_pane_cnt), 3 panes with healed Right Editor at left>0,top=0 (got panes=$healed_pane_cnt left=$healed_ed_left top=$healed_ed_top), and revived Editor active=$healed_ed_pane (got active=$revived_active_pane)"
            fi

            # Verify resolve_nvim_bin numerical version sorting (0.11.0 chosen over 0.9.5 when multiple versions exist)
            MISE_SORT_DIR="$(mktemp -d)"
            mkdir -p "$MISE_SORT_DIR/mise/shims" "$MISE_SORT_DIR/mise/installs/neovim/0.9.5/bin" "$MISE_SORT_DIR/mise/installs/neovim/0.11.0/bin"
            printf '#!/usr/bin/env bash\nexit 0\n' > "$MISE_SORT_DIR/mise/shims/nvim"
            printf '#!/usr/bin/env bash\nexit 0\n' > "$MISE_SORT_DIR/mise/installs/neovim/0.9.5/bin/nvim"
            printf '#!/usr/bin/env bash\nexit 0\n' > "$MISE_SORT_DIR/mise/installs/neovim/0.11.0/bin/nvim"
            chmod +x "$MISE_SORT_DIR/mise/shims/nvim" "$MISE_SORT_DIR/mise/installs/neovim/0.9.5/bin/nvim" "$MISE_SORT_DIR/mise/installs/neovim/0.11.0/bin/nvim"
            resolved_ver="$(PATH="$MISE_SORT_DIR/mise/shims:/usr/bin:/bin" python3 - "$SCRIPT_DIR/bin/ide" <<'PYTEST'
import sys, types
with open(sys.argv[1], "r", encoding="utf-8") as f:
    lines = f.read().splitlines()
start = next(i for i, l in enumerate(lines) if "<<'PY'" in l) + 1
end = next(i for i in range(start, len(lines)) if lines[i] == "PY")
code = "\n".join(lines[start:end])
mod = types.ModuleType("ide_mod")
exec(compile(code, sys.argv[1], "exec"), mod.__dict__)
print(mod.resolve_nvim_bin() or "")
PYTEST
)"
            rm -rf "$MISE_SORT_DIR"
            if [[ "$resolved_ver" == *"/0.11.0/bin/nvim" ]]; then
                echo "PASS:bin/ide resolve_nvim_bin sorts mise neovim versions numerically (0.11.0 preferred over 0.9.5)"
            else
                echo "FAIL:bin/ide resolve_nvim_bin version sort:Expected */0.11.0/bin/nvim, got '$resolved_ver'"
            fi

            "$SCRIPT_DIR/bin/ide" --quit --force "ws_3pane_test" >/dev/null 2>&1
            if ! tmux has-session -t "ws_3pane_test" 2>/dev/null; then
                echo "PASS:bin/ide --quit terminates the entire IDE workspace session cleanly"
            else
                echo "FAIL:bin/ide --quit:Session ws_3pane_test still exists after --quit"
                "$SCRIPT_DIR/bin/ide" --kill "ws_3pane_test" >/dev/null 2>&1
            fi
        else
            echo "FAIL:bin/ide 3-pane creation:Session ws_3pane_test was not created"
        fi
    ) > "$MAIN_WS_OUT" &
    PID_MAIN_WS=$!

    # Sub-suite B: `ide --quit` isolation, Editor `:Q` self-quit, Editor argument forwarding, untargeted quit guards, and exact `=NAME` targets (on $QUIT_TMPDIR)
    (
        export TMUX_TMPDIR="$QUIT_TMPDIR"
        export XDG_RUNTIME_DIR="$QUIT_TMPDIR"
        unset TMUX TMUX_PANE
        session_alive() { tmux has-session -t "=$1" 2>/dev/null; }
        all_alive() {
            local s
            for s in "$@"; do session_alive "$s" || return 1; done
        }
        pane_of() { tmux display-message -p -t "$1:" '#{pane_id}' 2>/dev/null || true; }
        tmux_env_of() { tmux display-message -p -t "$1:" '#{socket_path},#{pid},#{session_id}' 2>/dev/null | tr -d '$' || true; }
        tmux new-session -d -s "plain-bystander" -x 120 -y 40
        tmux new-session -d -s "ide-bystander" -x 120 -y 40
        tmux set-option -t "=ide-bystander:" @ide_session "ide-bystander"

        if command -v nvim >/dev/null 2>&1; then
            QUIT_HOME="$TEMP_HOME/quit_stub_home"
            QUIT_LOG="$TEMP_HOME/quit_stub.log"
            QUIT_SOCK="$TEMP_HOME/quit_editor.sock"
            mkdir -p "$QUIT_HOME/.local/bin"
            printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\n' "$QUIT_LOG" > "$QUIT_HOME/.local/bin/ide"
            chmod +x "$QUIT_HOME/.local/bin/ide"
            : > "$QUIT_LOG"
            tmux new-session -d -s "quit-editor" -x 120 -y 40 -e "NVIM_IDE_SOCKET=$QUIT_SOCK" \
                "nvim -u '$SCRIPT_DIR/dotfiles/.config/nvim/init.lua' --listen '$QUIT_SOCK' -c \"lua vim.env.HOME = '$QUIT_HOME'\""
            tmux set-option -t "=quit-editor:" @ide_socket "$QUIT_SOCK"

            SELF_HOME="$TEMP_HOME/quit_self_home"
            SELF_LOG="$TEMP_HOME/quit_self.log"
            SELF_SOCK="$TEMP_HOME/quit_self.sock"
            mkdir -p "$SELF_HOME/.local/bin"
            printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\nexec %q "$@"\n' "$SELF_LOG" "$SCRIPT_DIR/bin/ide" > "$SELF_HOME/.local/bin/ide"
            chmod +x "$SELF_HOME/.local/bin/ide"
            : > "$SELF_LOG"
            tmux new-session -d -s "quit-self" -x 120 -y 40 -e "NVIM_IDE_SOCKET=$SELF_SOCK" -e "IDE_SESSION=quit-self" \
                "nvim -u '$SCRIPT_DIR/dotfiles/.config/nvim/init.lua' --listen '$SELF_SOCK' -c \"lua vim.env.HOME = '$SELF_HOME'\""
            tmux split-window -d -t "quit-self:" "sleep 600"
            tmux set-option -t "=quit-self:" @ide_socket "$SELF_SOCK"

            ARGS_HOME="$TEMP_HOME/editor_args_home"
            ARGS_LOG="$TEMP_HOME/editor_args.log"
            ARGS_DIR="$TEMP_HOME/editor_args_dir"
            mkdir -p "$ARGS_HOME/.local/bin" "$ARGS_DIR"
            printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\n' "$ARGS_LOG" > "$ARGS_HOME/.local/bin/ide"
            chmod +x "$ARGS_HOME/.local/bin/ide"
            : > "$ARGS_LOG"
            cat > "$TEMP_HOME/editor_args.lua" <<LUA
vim.env.HOME = [[$ARGS_HOME]]
local function as(sess, fn) vim.env.IDE_SESSION = sess; pcall(fn) end
as("args-sess", function() vim.cmd("Q") end)
as("args-sess", function() vim.cmd("Q!") end)
as("args-sess", function() vim.cmd("IdeCd $ARGS_DIR") end)
as("args-sess", function() vim.fn.maparg("<leader>a", "n", false, true).callback() end)
as("args-sess", function() vim.fn.maparg("<M-E>", "n", false, true).callback() end)
as("args-sess", function() vim.fn.maparg("<M-H>", "n", false, true).callback() end)
as(nil, function() vim.cmd("Q") end)
as("", function() vim.cmd("Q") end)
local captured_popup_cmd = nil
local orig_jobstart = vim.fn.jobstart
vim.fn.jobstart = function(cmd, opts)
    if type(cmd) == "table" and cmd[1] == "tmux" then
        captured_popup_cmd = table.concat(cmd, "|")
        return 1
    end
    return orig_jobstart(cmd, opts)
end
vim.env.HOME = [[$ARGS_HOME/space home]]
vim.env.TMUX_PANE = "%42"
vim.fn.maparg("<leader>?", "n", false, true).callback()
vim.fn.writefile({ captured_popup_cmd or "" }, [[$TEMP_HOME/popup_cmd.log]])
vim.cmd("qa!")
LUA
            env TMUX="$TEMP_HOME/no-such-tmux,1,0" NVIM_IDE_SOCKET="$TEMP_HOME/no-such.sock" timeout 30 \
                nvim --headless -u "$SCRIPT_DIR/dotfiles/.config/nvim/init.lua" -c "source $TEMP_HOME/editor_args.lua" -c 'qa!' >/dev/null 2>&1 &
            PID_ARGS_NVIM=$!

            wait_for_nvim_socket "$QUIT_SOCK" 200 1 || true
            "$SCRIPT_DIR/bin/ide" --quit "quit-editor" >/dev/null 2>&1 || true
            for _ in $(seq 1 40); do
                session_alive "quit-editor" || break
                sleep 0.05
            done
            quit_log="$(cat "$QUIT_LOG")"
            if [ -z "$quit_log" ] && ! session_alive "quit-editor" && \
               all_alive "ide-bystander" "plain-bystander"; then
                echo "PASS:bin/ide --quit closes the Editor via <Cmd>qall!<CR> without spawning a second ide --quit, and other sessions survive"
            else
                echo "FAIL:bin/ide --quit Editor close:Expected no ide calls from the Editor (got: ${quit_log:-none}), quit-editor gone, and both bystanders alive"
            fi

            wait_for_nvim_socket "$SELF_SOCK" 200 1 || true
            nvim --headless --server "$SELF_SOCK" --remote-send "<C-\\><C-n>:Q<CR>" >/dev/null 2>&1 || true
            for _ in $(seq 1 60); do
                session_alive "quit-self" || break
                sleep 0.05
            done
            sleep 0.05
            self_log="$(cat "$SELF_LOG")"
            if [ "$self_log" = "--quit quit-self" ] && ! session_alive "quit-self" && \
               all_alive "ide-bystander" "plain-bystander"; then
                echo "PASS:Quitting from inside the Editor (:Q, :Quit, <leader>q, <M-q>) runs exactly one ide --quit naming its own session, which outlives the Editor it closes and kills only that session"
            else
                echo "FAIL:Editor-initiated ide --quit:Expected exactly one '--quit quit-self' call (got: ${self_log:-none}), quit-self gone, and both bystanders alive; sessions now: $(tmux list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
            fi

            wait "$PID_ARGS_NVIM" 2>/dev/null || true
            for _ in $(seq 1 50); do
                [ "$(wc -l < "$ARGS_LOG" | tr -d ' ')" -ge 8 ] && break
                sleep 0.05
            done
            args_log="$(LC_ALL=C sort "$ARGS_LOG")"
            args_expected="$(printf '%s\n' "--cd $ARGS_DIR args-sess" "--quit" "--quit" "--quit --force args-sess" "--quit args-sess" "--swap left args-sess" "--toggle args-sess" "--toggle-editor args-sess" | LC_ALL=C sort)"
            popup_cmd="$(cat "$TEMP_HOME/popup_cmd.log" 2>/dev/null || true)"
            popup_expected="tmux|display-popup|-t|%42|-E|-w|90|-h|30|'$ARGS_HOME/space home/.local/bin/ide' --keys"
            if [ "$args_log" = "$args_expected" ] && [ "$popup_cmd" = "$popup_expected" ]; then
                echo "PASS:The Editor names its own session in every ide call (--quit [--force] NAME, --cd DIR NAME, --toggle NAME, --toggle-editor NAME, --swap DIR NAME), passes -t \$TMUX_PANE and shell-escaped path in open_ide_keys_popup, and omits session when \$IDE_SESSION is empty"
            else
                echo "FAIL:Editor ide call arguments:Expected: $(tr '\n' '|' <<< "$args_expected") got: $(tr '\n' '|' <<< "$args_log") popup=$popup_cmd"
            fi
        else
            echo "PASS:bin/ide --quit Editor close skipped headless runtime check (nvim not installed on runner)"
        fi

        # Untargeted quits look up the caller's own pane (or a run-shell job's session id, with or without leading $) exactly, and only act on ide sessions
        tmux new-session -d -s "gone-sess" -x 120 -y 40
        tmux set-option -t "=gone-sess:" @ide_session "gone-sess"
        gone_pane="$(pane_of "gone-sess")"
        gone_env="$(tmux_env_of "gone-sess")"
        tmux kill-session -t "=gone-sess"
        for s in recent-sess auto-pane auto-job auto-job-dollar; do
            tmux new-session -d -s "$s" -x 120 -y 40
            tmux set-option -t "=$s:" @ide_session "$s"
        done
        env TMUX="$gone_env" TMUX_PANE="$gone_pane" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
        gone_ok=0
        all_alive plain-bystander ide-bystander recent-sess auto-pane auto-job auto-job-dollar && gone_ok=1
        env TMUX="$(tmux_env_of plain-bystander)" TMUX_PANE="$(pane_of plain-bystander)" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
        IFS=, read -r recent_sock _ recent_id <<< "$(tmux_env_of recent-sess)"
        env TMUX="$recent_sock,1,$recent_id" TMUX_PANE="$(pane_of recent-sess)" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
        env TMUX="$(tmux_env_of auto-pane)" TMUX_PANE="$(pane_of auto-pane)" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
        env -u TMUX_PANE TMUX="$(tmux_env_of auto-job)" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
        env -u TMUX_PANE TMUX="$(tmux display-message -p -t "=auto-job-dollar:" '#{socket_path},#{pid},#{session_id}' 2>/dev/null || true)" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
        if [ "$gone_ok" = "1" ] && all_alive plain-bystander ide-bystander recent-sess && \
           ! session_alive "auto-pane" && ! session_alive "auto-job" && ! session_alive "auto-job-dollar"; then
            echo "PASS:Untargeted bin/ide --quit never guesses: from a pane whose session is gone, a plain tmux session, or a replaced server it quits nothing, and from an ide pane or run-shell job (with or without \$ session_id prefix) it quits exactly that session"
        else
            echo "FAIL:bin/ide untargeted --quit:Expected nothing quit from a gone pane (ok=$gone_ok), plain-bystander/ide-bystander/recent-sess alive, auto-pane/auto-job/auto-job-dollar quit; sessions now: $(tmux list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
        fi

        # Exact session names
        for s in foobar ai-foobar foo api-gateway; do
            tmux new-session -d -s "$s" -x 120 -y 40
        done
        "$SCRIPT_DIR/bin/ide" --kill "foo" >/dev/null 2>&1 || true
        "$SCRIPT_DIR/bin/ide" --kill "foo" >/dev/null 2>&1 || true
        "$SCRIPT_DIR/bin/ide" --toggle "foo" >/dev/null 2>&1 || true
        mkdir -p "$TEMP_HOME/api"
        env -u IDE_AI_CLI XDG_RUNTIME_DIR="$QUIT_TMPDIR" "$SCRIPT_DIR/bin/ide" --2pane --detach "$TEMP_HOME/api" >/dev/null 2>&1 || true
        foobar_panes="$(tmux list-panes -s -t "=foobar:" 2>/dev/null | wc -l | tr -d ' ' || true)"
        gateway_panes="$(tmux list-panes -s -t "=api-gateway:" 2>/dev/null | wc -l | tr -d ' ' || true)"
        if ! session_alive "foo" && all_alive foobar ai-foobar api api-gateway && \
           [ "$foobar_panes" = "1" ] && [ "$gateway_panes" = "1" ]; then
            echo "PASS:bin/ide targets tmux sessions by exact name (=NAME): no prefix matches when killing, toggling, or launching sessions"
        else
            echo "FAIL:bin/ide exact session names:Expected foo gone and foobar (1 pane), ai-foobar, api, api-gateway (1 pane) alive; got foobar_panes=$foobar_panes gateway_panes=$gateway_panes sessions: $(tmux list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
        fi
        "$SCRIPT_DIR/bin/ide" --kill "api" >/dev/null 2>&1 || true
        tmux kill-server >/dev/null 2>&1 || true
    ) > "$QUIT_WS_OUT" &
    PID_QUIT_WS=$!

    # Sub-suite C: Mouse resizing & Ctrl/Alt+LeftClick link opening (on $MOUSE_TMPDIR)
    (
        if command -v python3 >/dev/null 2>&1; then
            MOUSE_HOME="$TEMP_HOME/mouse_home"
            IDE_WS_MOUSE="$MOUSE_HOME/ws_mouse"
            MOUSE_CLICK_LOG="$MOUSE_HOME/mouse_click.log"
            mkdir -p "$IDE_WS_MOUSE" "$MOUSE_HOME/.local/bin"
            printf '#!/usr/bin/env bash\nif [ "${1:-}" = "--open-link" ]; then printf "argc=%%s 2=<%%s> 3=<%%s> 4=<%%s> 5=<%%s>\\n" "$#" "${2:-}" "${3:-}" "${4:-}" "${5:-}" >> %q; fi\nexec %q "$@"\n' \
                "$MOUSE_CLICK_LOG" "$SCRIPT_DIR/bin/ide" > "$MOUSE_HOME/.local/bin/ide"
            chmod +x "$MOUSE_HOME/.local/bin/ide"
            : > "$MOUSE_CLICK_LOG"
            mouse_out="$(
                export TMUX_TMPDIR="$MOUSE_TMPDIR"
                export XDG_RUNTIME_DIR="$MOUSE_TMPDIR"
                export HOME="$MOUSE_HOME"
                tmux -f "$SCRIPT_DIR/dotfiles/.tmux.conf" new-session -d -s mouse-holder -x 120 -y 40
                env -u IDE_AI_CLI "$SCRIPT_DIR/bin/ide" --detach "$IDE_WS_MOUSE" >/dev/null 2>&1
                echo "binding=$(tmux list-keys -T root MouseDrag1Border 2>&1)"
                echo "md1=$(tmux list-keys -T root MouseDown1Pane 2>&1)"
                echo "md8=$(tmux list-keys -T root MouseDown8Pane 2>&1)"
                echo "md9=$(tmux list-keys -T root MouseDown9Pane 2>&1)"
                python3 - "$SCRIPT_DIR/bin/ide" "ws_mouse" "$MOUSE_CLICK_LOG" 2>&1 <<'PY'
import fcntl, os, select, struct, subprocess, sys, termios, threading, time

ide, sess, click_log = sys.argv[1], sys.argv[2], sys.argv[3]

def tmux(*args):
    return subprocess.run(["tmux", *args], capture_output=True, text=True).stdout.strip()

panes = [tmux("show-options", "-qv", "-t", f"={sess}:", o) for o in ("@ide_ai_pane", "@ide_editor_pane", "@ide_term_pane")]

def sizes():
    fmt = "#{pane_left} #{pane_top} #{pane_width} #{pane_height}"
    return [tuple(int(v) for v in tmux("display-message", "-p", "-t", p, fmt).split()) for p in panes]

# A 120x41 terminal: the top status bar plus 40 pane rows
master, slave = os.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 41, 120, 0, 0))

def controlling_tty():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)

client = subprocess.Popen(["tmux", "attach-session", "-t", f"={sess}"], stdin=slave, stdout=slave, stderr=slave,
                          preexec_fn=controlling_tty, env=dict(os.environ, TERM="xterm-256color"))
os.close(slave)
attached = True
outer_bytes = bytearray()

def drain():
    while attached:
        if select.select([master], [], [], 0.05)[0]:
            try:
                outer_bytes.extend(os.read(master, 65536))
            except OSError:
                return

threading.Thread(target=drain, daemon=True).start()
for _ in range(50):
    if tmux("display-message", "-p", "-t", panes[0], "#{window_width}x#{window_height}") == "120x40":
        break
    time.sleep(0.05)

def send(seq):
    os.write(master, seq.encode())
    time.sleep(0.05)

def drag(x0, y0, x1, y1):
    send(f"\x1b[<0;{x0 + 1};{y0 + 2}M")
    send(f"\x1b[<32;{(x0 + x1) // 2 + 1};{(y0 + y1) // 2 + 2}M")
    send(f"\x1b[<32;{x1 + 1};{y1 + 2}M")
    send(f"\x1b[<0;{x1 + 1};{y1 + 2}m")

before = sizes()
(al, at, aw, ah), (el, et, ew, eh), (sl, st, sw, sh) = before
drag(al + aw, at + 3, al + aw - 10, at + 3)
drag(2, st - 1, 2, st - 6)
dragged = sizes()
drag_ok = dragged[0][2] == aw - 10 and dragged[1][2] == ew + 10 and dragged[2][3] == sh + 5
for args in (
    ["--toggle", sess],
    ["--show-term", sess],
    ["--show-term", sess],
    ["--toggle", sess],
    ["--toggle-editor", sess],
    ["--toggle-editor", sess],
    ["--toggle-term", sess],
    ["--toggle-term", sess],
):
    subprocess.run([ide, *args], capture_output=True)
tmux("resize-pane", "-Z", "-t", panes[1])
tmux("resize-pane", "-Z", "-t", panes[1])
kept = sizes()

outer_bytes.clear()
tmux("respawn-pane", "-k", "-t", panes[0], "printf '\\033[2J\\033[H\\033]8;;file:///tmp/osc8_target.lua#L42\\033\\\\OSC8LINK\\033]8;;\\033\\\\\\nPLAINWORD.lua:7\\n'; sleep 30")
time.sleep(0.3)
send("\x1b[<16;2;2M\x1b[<16;2;2m")
for _ in range(30):
    if os.path.exists(click_log) and open(click_log).read().count("\n") >= 1:
        break
    time.sleep(0.05)
time.sleep(0.4)
send("\x1b[<16;2;3M\x1b[<16;2;3m")
for _ in range(30):
    if os.path.exists(click_log) and open(click_log).read().count("\n") >= 2:
        break
    time.sleep(0.05)
time.sleep(0.4)
send("\x1b[<8;2;2M\x1b[<8;2;2m")
for _ in range(30):
    if os.path.exists(click_log) and open(click_log).read().count("\n") >= 3:
        break
    time.sleep(0.05)

attached = False
client.terminate()
outer_osc8 = "passed" if b"\x1b]8;" in outer_bytes else "missing"
print(f"drag={'ok' if drag_ok else before + dragged} kept={'ok' if kept == dragged else kept} outer_osc8={outer_osc8}")
PY
            )" || true
            tmux -S "$MOUSE_TMPDIR/tmux-$(id -u)/default" kill-server >/dev/null 2>&1 || true
            mouse_click_logged="$(cat "$MOUSE_CLICK_LOG" 2>/dev/null || true)"
            if grep -q '^binding=.*MouseDrag1Border resize-pane -M' <<< "$mouse_out" && \
               grep -q '^md1=.*MouseDown1Pane select-pane -t = \\; send-keys -M' <<< "$mouse_out" && \
               grep -q '^md8=.*MouseDown8Pane.*send-keys C-o' <<< "$mouse_out" && \
               grep -q '^md9=.*MouseDown9Pane.*send-keys C-i' <<< "$mouse_out" && \
               grep -q '^drag=ok kept=ok outer_osc8=passed$' <<< "$mouse_out" && \
               [ "$(grep -Fc 'argc=5 2=<file:///tmp/osc8_target.lua#L42> 3=<OSC8LINK>' <<< "$mouse_click_logged")" -ge 2 ] && \
               grep -Fq 'argc=5 2=<> 3=<PLAINWORD.lua:7>' <<< "$mouse_click_logged"; then
                echo "PASS:tmux resizes IDE panes by mouse (preserving dragged sizes across focus switches, parking/unparking, and zoom), pins native MouseDown1Pane, binds MouseDown8Pane/MouseDown9Pane (Mouse4/Mouse5) to Editor jumplist C-o/C-i, passes OSC 8 through to the outer terminal, and routes Ctrl+LeftClick (C-MouseDown1Pane) and Alt+LeftClick (M-MouseDown1Pane) for OSC 8 hyperlinks and plain-text file:line tokens"
            else
                echo "FAIL:tmux mouse border resize & Ctrl/Alt+LeftClick:Expected MouseDrag1Border resize-pane -M, MouseDown1Pane select-pane -t = \\; send-keys -M, MouseDown8Pane/9Pane C-o/C-i, drag=ok kept=ok outer_osc8=passed, and C-MouseDown1Pane + M-MouseDown1Pane for OSC8LINK + PLAINWORD.lua:7; got out=$mouse_out click=${mouse_click_logged:-<empty>}"
            fi
        fi
    ) > "$MOUSE_WS_OUT" &
    PID_MOUSE_WS=$!

    wait "$PID_MAIN_WS" "$PID_QUIT_WS" "$PID_MOUSE_WS" 2>/dev/null || true
    parse_subshell_results < "$MAIN_WS_OUT"
    parse_subshell_results < "$QUIT_WS_OUT"
    parse_subshell_results < "$MOUSE_WS_OUT"

    export PATH="$OLD_TMUX_PATH"
    if [ -n "$OLD_TMUX_SHELL" ]; then
        export SHELL="$OLD_TMUX_SHELL"
    fi
    tmux -S "$TMUX_TEST_TMPDIR/tmux-$(id -u)/default" kill-server >/dev/null 2>&1 || true
    tmux -S "$QUIT_TMPDIR/tmux-$(id -u)/default" kill-server >/dev/null 2>&1 || true
    tmux -S "$MOUSE_TMPDIR/tmux-$(id -u)/default" kill-server >/dev/null 2>&1 || true
    rm -rf "$TMUX_TEST_TMPDIR" "$QUIT_TMPDIR" "$MOUSE_TMPDIR" "$IDE_AI_STUB_DIR"
    TMUX_TEST_TMPDIR=""
    QUIT_TMPDIR=""
    MOUSE_TMPDIR=""
fi

# Test 7: bin/update-system CLI validation & cross-platform dry-run orchestration
echo -e "\n[7/8] Testing bin/update-system maintenance orchestrator..."
UPDATE_HELP="$("$SCRIPT_DIR/bin/update-system" --help)"
if grep -q -- '--dry-run' <<< "$UPDATE_HELP" && \
   grep -q -- '--system-only' <<< "$UPDATE_HELP" && \
   grep -q -- '--skip-snaps' <<< "$UPDATE_HELP" && \
   grep -q -- '--with-dev' <<< "$UPDATE_HELP" && \
   grep -q -- '--all' <<< "$UPDATE_HELP"; then
    pass "bin/update-system --help displays complete usage flags and workflows"
else
    fail "bin/update-system --help" "Expected complete options in bin/update-system --help output"
fi

if "$SCRIPT_DIR/bin/update-system" --unrecognized-flag >/dev/null 2>&1; then
    fail "bin/update-system invalid flag" "Expected non-zero exit status on unknown flag"
else
    pass "bin/update-system rejects unknown CLI flags"
fi

if "$SCRIPT_DIR/bin/update-system" --os >/dev/null 2>&1; then
    fail "bin/update-system missing --os arg" "Expected non-zero exit status when --os has no argument"
else
    pass "bin/update-system rejects --os without argument"
fi

if "$SCRIPT_DIR/bin/update-system" --os solaris >/dev/null 2>&1; then
    fail "bin/update-system invalid OS" "Expected non-zero exit status on unsupported OS family"
else
    pass "bin/update-system rejects unsupported operating system families"
fi

# Test Ubuntu dry-run plan
UBUNTU_OUT="$("$SCRIPT_DIR/bin/update-system" --os ubuntu --dry-run)"
if grep -Fq "apt-get update" <<< "$UBUNTU_OUT" && \
   grep -Fq "apt-get upgrade -y" <<< "$UBUNTU_OUT" && \
   grep -Fq "apt-get autoremove -y" <<< "$UBUNTU_OUT" && \
   grep -Fq "apt-get autoclean" <<< "$UBUNTU_OUT" && \
   grep -Fq "snap refresh" <<< "$UBUNTU_OUT" && \
   grep -Fq "flatpak update -y" <<< "$UBUNTU_OUT"; then
    pass "bin/update-system --os ubuntu --dry-run dispatches apt update, upgrade -y, autoremove, autoclean, snap refresh, and flatpak update"
else
    fail "bin/update-system ubuntu dry-run" "Missing expected Ubuntu update commands"
fi

# Test Fedora dry-run plan
FEDORA_OUT="$("$SCRIPT_DIR/bin/update-system" --os fedora --dry-run)"
if grep -Fq "dnf upgrade --refresh -y" <<< "$FEDORA_OUT" && \
   grep -Fq "dnf autoremove -y" <<< "$FEDORA_OUT" && \
   grep -Fq "dnf clean packages -y" <<< "$FEDORA_OUT"; then
    pass "bin/update-system --os fedora --dry-run dispatches dnf upgrade --refresh, autoremove, and package cleanup"
else
    fail "bin/update-system fedora dry-run" "Missing expected Fedora dnf update commands"
fi

# Test macOS dry-run plan
MACOS_OUT="$("$SCRIPT_DIR/bin/update-system" --os macos --dry-run)"
if grep -Fq "brew update" <<< "$MACOS_OUT" && \
   grep -Fq "brew upgrade" <<< "$MACOS_OUT" && \
   grep -Fq "brew cleanup -s" <<< "$MACOS_OUT" && \
   grep -Fq "brew autoremove" <<< "$MACOS_OUT" && \
   grep -Fq "mas upgrade" <<< "$MACOS_OUT" && \
   ! grep -Fq "sudo brew" <<< "$MACOS_OUT" && \
   ! grep -Fq "snap refresh" <<< "$MACOS_OUT"; then
    pass "bin/update-system --os macos --dry-run dispatches user-space brew commands and mas upgrade without sudo brew or snap"
else
    fail "bin/update-system macos dry-run" "Missing expected macOS update commands or found privileged brew"
fi

# Test Arch Linux dry-run plan
ARCH_OUT="$("$SCRIPT_DIR/bin/update-system" --os arch --dry-run)"
if grep -Fq "pacman -Syu --noconfirm" <<< "$ARCH_OUT" && \
   grep -Fq "pacman -Sc --noconfirm" <<< "$ARCH_OUT"; then
    pass "bin/update-system --os arch --dry-run dispatches pacman -Syu and cache cleanup"
else
    fail "bin/update-system arch dry-run" "Missing expected Arch pacman update commands"
fi

# Test component toggles (--system-only, --skip-snaps, --skip-flatpak, --with-dev, --no-cleanup, -i)
SYS_ONLY_OUT="$("$SCRIPT_DIR/bin/update-system" --os ubuntu --system-only --dry-run)"
if ! grep -Fq "snap refresh" <<< "$SYS_ONLY_OUT" && ! grep -Fq "flatpak update" <<< "$SYS_ONLY_OUT"; then
    pass "bin/update-system --system-only cleanly skips Snaps and Flatpaks"
else
    fail "bin/update-system --system-only" "Found snap or flatpak commands in system-only mode"
fi

SKIP_SNAPS_OUT="$("$SCRIPT_DIR/bin/update-system" --os ubuntu --skip-snaps --dry-run)"
if ! grep -Fq "snap refresh" <<< "$SKIP_SNAPS_OUT" && grep -Fq "flatpak update -y" <<< "$SKIP_SNAPS_OUT"; then
    pass "bin/update-system --skip-snaps selectively skips snap refresh while maintaining flatpak"
else
    fail "bin/update-system --skip-snaps" "Failed to selectively skip snap"
fi

SKIP_FLATPAK_OUT="$("$SCRIPT_DIR/bin/update-system" --os ubuntu --skip-flatpak --dry-run)"
if grep -Fq "snap refresh" <<< "$SKIP_FLATPAK_OUT" && ! grep -Fq "flatpak update" <<< "$SKIP_FLATPAK_OUT"; then
    pass "bin/update-system --skip-flatpak selectively skips flatpak updates while maintaining snap"
else
    fail "bin/update-system --skip-flatpak" "Failed to selectively skip flatpak"
fi

TEMP_OMZ_DEV_HOME="$(mktemp -d)"
mkdir -p "$TEMP_OMZ_DEV_HOME/.oh-my-zsh/tools" \
         "$TEMP_OMZ_DEV_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/.git" \
         "$TEMP_OMZ_DEV_HOME/.oh-my-zsh/custom/plugins/gitfile-plugin" \
         "$TEMP_OMZ_DEV_HOME/.oh-my-zsh/custom/themes/powerlevel10k/.git" \
         "$TEMP_OMZ_DEV_HOME/.oh-my-zsh/custom/plugins/local-non-git"
printf 'gitdir: /tmp/mock-gitdir\n' > "$TEMP_OMZ_DEV_HOME/.oh-my-zsh/custom/plugins/gitfile-plugin/.git"
touch "$TEMP_OMZ_DEV_HOME/.oh-my-zsh/tools/upgrade.sh"
DEV_OUT="$(env -u ZSH -u ZSH_CUSTOM HOME="$TEMP_OMZ_DEV_HOME" "$SCRIPT_DIR/bin/update-system" --os ubuntu --with-dev --dry-run)"
rm -rf "$TEMP_OMZ_DEV_HOME"
if grep -Fq "mise plugins update" <<< "$DEV_OUT" && \
   grep -Fq "mise upgrade" <<< "$DEV_OUT" && \
   grep -Fq "rustup update" <<< "$DEV_OUT" && \
   grep -Fq "upgrade.sh" <<< "$DEV_OUT" && \
   grep -Fq "zsh-autosuggestions pull --ff-only" <<< "$DEV_OUT" && \
   grep -Fq "gitfile-plugin pull --ff-only" <<< "$DEV_OUT" && \
   grep -Fq "powerlevel10k pull --ff-only" <<< "$DEV_OUT" && \
   ! grep -Fq "local-non-git" <<< "$DEV_OUT"; then
    pass "bin/update-system --with-dev dispatches Mise, Rustup, Oh-My-Zsh, and custom Git (.git dir and gitfile) plugin/theme updates"
else
    fail "bin/update-system --with-dev" "Missing expected developer toolchain or custom Zsh plugin/theme commands: $DEV_OUT"
fi

TEMP_OMZ_LIVE="$(mktemp -d)"
mkdir -p "$TEMP_OMZ_LIVE/mock-bin" "$TEMP_OMZ_LIVE/custom/plugins"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TEMP_OMZ_LIVE/mock-bin/brew"
chmod +x "$TEMP_OMZ_LIVE/mock-bin/brew"
git init -q "$TEMP_OMZ_LIVE/origin-repo"
git -C "$TEMP_OMZ_LIVE/origin-repo" config user.email "test@example.com"
git -C "$TEMP_OMZ_LIVE/origin-repo" config user.name "Test"
git -C "$TEMP_OMZ_LIVE/origin-repo" config commit.gpgsign false
printf 'v1\n' > "$TEMP_OMZ_LIVE/origin-repo/f.txt"
git -C "$TEMP_OMZ_LIVE/origin-repo" add f.txt
git -C "$TEMP_OMZ_LIVE/origin-repo" -c commit.gpgsign=false commit -q -m "c1"
git clone -q "$TEMP_OMZ_LIVE/origin-repo" "$TEMP_OMZ_LIVE/custom/plugins/pinned-plugin"
git -C "$TEMP_OMZ_LIVE/custom/plugins/pinned-plugin" checkout -q --detach HEAD
git clone -q "$TEMP_OMZ_LIVE/origin-repo" "$TEMP_OMZ_LIVE/custom/plugins/ff-plugin"
printf 'v2\n' > "$TEMP_OMZ_LIVE/origin-repo/f.txt"
git -C "$TEMP_OMZ_LIVE/origin-repo" -c commit.gpgsign=false commit -q -am "c2"
if LIVE_DEV_OUT="$(env -u ZSH PATH="$TEMP_OMZ_LIVE/mock-bin:/usr/bin:/bin" HOME="$TEMP_OMZ_LIVE" ZSH_CUSTOM="$TEMP_OMZ_LIVE/custom" "$SCRIPT_DIR/bin/update-system" --os macos --system-only --with-dev 2>&1)" && \
   [ "$(cat "$TEMP_OMZ_LIVE/custom/plugins/ff-plugin/f.txt")" = "v2" ] && \
   grep -Fq "Skipped fast-forward update for pinned-plugin" <<< "$LIVE_DEV_OUT"; then
    pass "bin/update-system --with-dev fast-forwards standalone ZSH_CUSTOM repos and warns without aborting on detached-HEAD plugins"
else
    fail "bin/update-system --with-dev live custom pull" "Unexpected result: ${LIVE_DEV_OUT:-failed}"
fi
rm -rf "$TEMP_OMZ_LIVE"

NO_CLEANUP_OUT="$("$SCRIPT_DIR/bin/update-system" --os ubuntu --no-cleanup --dry-run)"
if ! grep -Fq "autoremove" <<< "$NO_CLEANUP_OUT" && ! grep -Fq "autoclean" <<< "$NO_CLEANUP_OUT"; then
    pass "bin/update-system --no-cleanup skips autoremove and cache cleaning phases"
else
    fail "bin/update-system --no-cleanup" "Found autoremove or autoclean in --no-cleanup mode"
fi

INTERACTIVE_OUT="$("$SCRIPT_DIR/bin/update-system" --os ubuntu -i --dry-run)"
if grep -Fq "apt-get upgrade" <<< "$INTERACTIVE_OUT" && ! grep -Fq "apt-get upgrade -y" <<< "$INTERACTIVE_OUT"; then
    pass "bin/update-system -i (--interactive) suppresses automatic -y flag for interactive confirmation"
else
    fail "bin/update-system -i" "Found automatic -y flag in interactive mode"
fi

# Test 8: bin/gnome-terminal-solarized dry-run and legacy profile UUID / font upgrade
echo -e "\n[8/8] Testing bin/gnome-terminal-solarized profile provisioning..."
GT_MOCK_DIR="$(mktemp -d)"
cat > "$GT_MOCK_DIR/dconf" <<'SH'
#!/usr/bin/env bash
echo "dconf $*" >> "${GT_MOCK_LOG:-/dev/null}"
if [ "${1:-}" = "read" ] && [ "${2:-}" = "/org/gnome/terminal/legacy/profiles:/list" ]; then
    echo "['11f5ebd6-faab-4bd3-8336-868a6b52ac0d', 'other-profile-uuid']"
elif [ "${1:-}" = "list" ] && [ "${2:-}" = "/org/gnome/terminal/legacy/profiles:/" ]; then
    printf ":other-profile-uuid/\n:321fa646-e6ab-45a1-88d8-00aa66d158d8/\n"
elif [ "${1:-}" = "read" ] && [[ "${2:-}" == *"/font" ]]; then
    echo "'MesloLGS NF 12'"
fi
exit 0
SH
cat > "$GT_MOCK_DIR/gsettings" <<'SH'
#!/usr/bin/env bash
echo "gsettings $*" >> "${GT_MOCK_LOG:-/dev/null}"
if [ "${1:-}" = "list-schemas" ]; then
    echo "org.gnome.Terminal.ProfilesList"
fi
exit 0
SH
chmod +x "$GT_MOCK_DIR/dconf" "$GT_MOCK_DIR/gsettings"
GT_DRY_OUT="$(PATH="$GT_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/gnome-terminal-solarized" --dry-run)"
if grep -Fq "Solarized Dark" <<< "$GT_DRY_OUT" && \
   grep -Fq "321fa646-e6ab-45a1-88d8-00aa66d158d8" <<< "$GT_DRY_OUT" && \
   grep -Fq "11f5ebd6-faab-4bd3-8336-868a6b52ac0d" <<< "$GT_DRY_OUT"; then
    pass "bin/gnome-terminal-solarized --dry-run outputs Solarized Dark profile UUID (321fa646-...) and legacy UUID cleanup (11f5ebd6-...)"
else
    fail "bin/gnome-terminal-solarized --dry-run" "Missing expected dry-run output: $GT_DRY_OUT"
fi

GT_MOCK_LOG="$GT_MOCK_DIR/gt.log" PATH="$GT_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/gnome-terminal-solarized" >/dev/null 2>&1
gt_logged="$(cat "$GT_MOCK_DIR/gt.log" 2>/dev/null || true)"
rm -rf "$GT_MOCK_DIR"
if grep -Fq "dconf reset -f /org/gnome/terminal/legacy/profiles:/:11f5ebd6-faab-4bd3-8336-868a6b52ac0d/" <<< "$gt_logged" && \
   grep -Fq "dconf write /org/gnome/terminal/legacy/profiles:/list ['other-profile-uuid', '321fa646-e6ab-45a1-88d8-00aa66d158d8']" <<< "$gt_logged" && \
   grep -Fq "dconf write /org/gnome/terminal/legacy/profiles:/:other-profile-uuid/font 'MesloLGS Nerd Font Mono 12'" <<< "$gt_logged"; then
    pass "bin/gnome-terminal-solarized purges legacy profile UUID (11f5ebd6-...) and upgrades legacy 'MesloLGS NF 12' font to 'MesloLGS Nerd Font Mono 12'"
else
    fail "bin/gnome-terminal-solarized mock provisioning" "Unexpected dconf/gsettings calls: $gt_logged"
fi

MAC_MOCK_DIR="$(mktemp -d)"
cat > "$MAC_MOCK_DIR/uname" <<'SH'
#!/usr/bin/env bash
echo "Darwin"
SH
cat > "$MAC_MOCK_DIR/defaults" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$MAC_MOCK_DIR/uname" "$MAC_MOCK_DIR/defaults"
HOME="$MAC_MOCK_DIR" PATH="$MAC_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/macos-terminal-solarized" >/dev/null 2>&1
mac_plist_ok="$(python3 - "$MAC_MOCK_DIR/Library/Preferences/com.apple.Terminal.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    prefs = plistlib.load(f)
prof = prefs.get("Window Settings", {}).get("Solarized Dark", {})
ok = (
    prefs.get("Default Window Settings") == "Solarized Dark"
    and prefs.get("Startup Window Settings") == "Solarized Dark"
    and prof.get("useOptionAsMetaKey") is True
)
print("OK" if ok else f"FAIL:{prefs}")
PY
)"
rm -rf "$MAC_MOCK_DIR"
if [ "$mac_plist_ok" = "OK" ]; then
    pass "bin/macos-terminal-solarized writes com.apple.Terminal.plist with Solarized Dark default/startup profile and useOptionAsMetaKey = True"
else
    fail "bin/macos-terminal-solarized mock Darwin provisioning" "Unexpected plist state: $mac_plist_ok"
fi

if gt_help="$("$SCRIPT_DIR/bin/gnome-terminal-solarized" --help 2>&1)" && \
   grep -Fq "Usage: gnome-terminal-solarized [OPTIONS]" <<< "$gt_help" && \
   grep -Fq -- "--dry-run" <<< "$gt_help" && \
   ! "$SCRIPT_DIR/bin/gnome-terminal-solarized" --invalid-flag >/dev/null 2>&1; then
    pass "bin/gnome-terminal-solarized supports -h/--help and rejects unknown options"
else
    fail "bin/gnome-terminal-solarized CLI flags" "Expected --help usage output and non-zero exit on --invalid-flag"
fi

if mt_help="$("$SCRIPT_DIR/bin/macos-terminal-solarized" --help 2>&1)" && \
   grep -Fq "Usage: macos-terminal-solarized [OPTIONS]" <<< "$mt_help" && \
   grep -Fq -- "--dry-run" <<< "$mt_help" && \
   ! "$SCRIPT_DIR/bin/macos-terminal-solarized" --invalid-flag >/dev/null 2>&1; then
    pass "bin/macos-terminal-solarized supports -h/--help and rejects unknown options"
else
    fail "bin/macos-terminal-solarized CLI flags" "Expected --help usage output and non-zero exit on --invalid-flag"
fi

if gp_help="$("$SCRIPT_DIR/bin/gen-passwd" --help 2>&1)" && \
   gp_short_help="$("$SCRIPT_DIR/bin/gen-passwd" -u --help 2>&1)" && \
   grep -Fq "Usage: gen-passwd [-u] [-l] [-n] [-s] [-t] [-h] [length]" <<< "$gp_help" && \
   grep -Fq "Usage: gen-passwd [-u] [-l] [-n] [-s] [-t] [-h] [length]" <<< "$gp_short_help" && \
   rus_help="$("$SCRIPT_DIR/bin/repeat-until-success" --help 2>&1)" && \
   rus_short_help="$("$SCRIPT_DIR/bin/repeat-until-success" -n 2 --help 2>&1)" && \
   grep -Fq "Usage: repeat-until-success [-n <attempts>] [-d <seconds>] [-t] [-h] <command> [args...]" <<< "$rus_help" && \
   grep -Fq "Usage: repeat-until-success [-n <attempts>] [-d <seconds>] [-t] [-h] <command> [args...]" <<< "$rus_short_help" && \
   sum_help="$("$SCRIPT_DIR/bin/sum" --help 2>&1)" && \
   sum_short_help="$("$SCRIPT_DIR/bin/sum" -a --help 2>&1)" && \
   grep -Fq "usage: sum [options]" <<< "$sum_help" && \
   grep -Fq "usage: sum [options]" <<< "$sum_short_help"; then
    pass "bin/gen-passwd, bin/repeat-until-success, and bin/sum support --help (both first and after short flags)"
else
    fail "bin utilities --help" "Expected --help usage output from gen-passwd, repeat-until-success, and sum"
fi

# Test 9: bin/theme unified multi-theme color scheme manager
echo -e "\n[9/9] Testing bin/theme unified multi-theme manager..."
unset HOME_SETTINGS_THEME HOME_SETTINGS_THEME_MODE HOME_SETTINGS_THEME_FILE
THEME_TEST_HOME="$(mktemp -d)"
export THEME_TEST_Cfg="$THEME_TEST_HOME/.config"
export THEME_TEST_Cache="$THEME_TEST_HOME/.cache"
mkdir -p "$THEME_TEST_Cfg" "$THEME_TEST_Cache"

THEME_HELP="$("$SCRIPT_DIR/bin/theme" --help 2>&1)"
if grep -Fq "Usage: theme [OPTIONS] [THEME_NAME]" <<< "$THEME_HELP" && \
   grep -Fq -- "--list" <<< "$THEME_HELP" && \
   grep -Fq -- "--plain" <<< "$THEME_HELP" && \
   grep -Fq -- "--current" <<< "$THEME_HELP" && \
   grep -Fq -- "--set" <<< "$THEME_HELP" && \
   grep -Fq -- "--preview" <<< "$THEME_HELP" && \
   grep -Fq -- "--env" <<< "$THEME_HELP" && \
   grep -Fq -- "--create" <<< "$THEME_HELP" && \
   grep -Fq -- "--path" <<< "$THEME_HELP" && \
   grep -Fq -- "--dry-run" <<< "$THEME_HELP" && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --invalid-flag >/dev/null 2>&1 && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --set nonexistent-theme >/dev/null 2>&1 && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" "" >/dev/null 2>&1 && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --set="" >/dev/null 2>&1 && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --set --help >/dev/null 2>&1 && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --create --sync-assets >/dev/null 2>&1; then
    pass "bin/theme supports -h/--help (including --plain) and rejects unknown flags, empty names, missing option values (--set --help), and nonexistent themes"
else
    fail "bin/theme CLI validation" "Unexpected --help or error handling output"
fi

# Verify default --current and --list across all 17 built-in themes (9 classic + 8 US Holiday)
CUR_DEFAULT="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --current)"
LIST_PLAIN="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --list --plain)"
LIST_FULL="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --list)"
managed_themes=(
    "solarized-dark"
    "solarized-light"
    "catppuccin-mocha"
    "catppuccin-latte"
    "gruvbox-dark"
    "tokyonight-night"
    "kanagawa-wave"
    "nord"
    "onedark"
    "new-years"
    "valentines"
    "st-patricks"
    "easter"
    "independence-day"
    "halloween"
    "thanksgiving"
    "christmas"
)
all_listed=true
for t in "${managed_themes[@]}"; do
    if ! grep -Fxq "$t" <<< "$LIST_PLAIN" || ! grep -Fq "$t" <<< "$LIST_FULL"; then
        all_listed=false
        fail "bin/theme --list" "Missing managed theme '$t' in --list output"
    fi
done
if [ "$CUR_DEFAULT" = "solarized-dark" ] && [ "$all_listed" = true ] && grep -Fq "* solarized-dark" <<< "$LIST_FULL"; then
    pass "bin/theme defaults to solarized-dark and lists all 17 built-in themes (9 classic + 8 US Holiday)"
else
    fail "bin/theme default & list" "cur='$CUR_DEFAULT' all_listed='$all_listed'"
fi

# Verify --holiday resolves nearest upcoming US Holiday (e.g. Oct 25 -> halloween, Nov 20 -> thanksgiving)
HOLIDAY_OCT="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" THEME_HOLIDAY_DATE="2026-10-25" "$SCRIPT_DIR/bin/theme" --holiday --dry-run)"
HOLIDAY_NOV="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" THEME_HOLIDAY_DATE="2026-11-20" "$SCRIPT_DIR/bin/theme" --holiday --dry-run)"
if grep -Fq "Halloween (halloween" <<< "$HOLIDAY_OCT" && grep -Fq "Thanksgiving (thanksgiving" <<< "$HOLIDAY_NOV"; then
    pass "bin/theme --holiday resolves the nearest upcoming US Holiday theme (fixed and movable dates)"
else
    fail "bin/theme --holiday" "Unexpected holiday resolution: oct='$HOLIDAY_OCT' nov='$HOLIDAY_NOV'"
fi

# Verify --preview and --env for managed themes (including pre-compiled TrueColor LS_COLORS with literal *# glob)
PREVIEW_MOCHA="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --preview catppuccin-mocha)"
ENV_NORD="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --env nord)"
if grep -Fq "Catppuccin Mocha" <<< "$PREVIEW_MOCHA" && \
   grep -Fq "catppuccin-mocha | dark | builtin" <<< "$PREVIEW_MOCHA" && \
   grep -Fq $'\033[38;2;' <<< "$PREVIEW_MOCHA" && \
   grep -Fq "Converged Semantic Code Preview:" <<< "$PREVIEW_MOCHA" && \
   grep -Fq 'export HOME_SETTINGS_THEME="nord"' <<< "$ENV_NORD" && \
   grep -Fq 'export BAT_THEME="Nord-TrueColor"' <<< "$ENV_NORD" && \
   grep -Fq "export LS_COLORS='" <<< "$ENV_NORD" && \
   grep -Fq ':di=38;2;129;161;193:' <<< "$ENV_NORD" && \
   grep -Fq ':*#=38;2;132;146;172:' <<< "$ENV_NORD" && \
   grep -Fq 'export FZF_DEFAULT_OPTS=' <<< "$ENV_NORD" && \
   grep -Fq 'export EZA_COLORS=' <<< "$ENV_NORD" && \
   grep -Fq 'export JQ_COLORS=' <<< "$ENV_NORD"; then
    pass "bin/theme --preview renders TrueColor palette & syntax sample and --env emits POSIX shell exports including complete TrueColor LS_COLORS (*# preserved)"
else
    fail "bin/theme --preview / --env" "Missing expected preview or env output"
fi

# Verify --dry-run does not mutate state
DRY_OUT="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --dry-run tokyonight-night)"
if grep -Fq "[DRY-RUN] Theme: TokyoNight Night (tokyonight-night" <<< "$DRY_OUT" && \
   [ ! -f "$THEME_TEST_Cfg/home-settings/theme" ]; then
    pass "bin/theme --dry-run previews planned mutations without writing state files"
else
    fail "bin/theme --dry-run" "State file created during --dry-run or missing output: $DRY_OUT"
fi

# Verify sync_symlink backs up pre-existing physical ~/.config directories and files to .bak.<ts> without data loss
BAK_TEST_HOME="$(mktemp -d)"
mkdir -p "$BAK_TEST_HOME/.config/ghostty" "$BAK_TEST_HOME/.config/btop" "$BAK_TEST_HOME/.config/tealdeer" "$BAK_TEST_HOME/.config/git"
echo "user-ghostty" > "$BAK_TEST_HOME/.config/ghostty/local.conf"
echo "user-btop" > "$BAK_TEST_HOME/.config/btop/local.conf"
echo "user-tealdeer" > "$BAK_TEST_HOME/.config/tealdeer/local.toml"
echo "user-gitconfig" > "$BAK_TEST_HOME/.config/git/config"
echo "*.secret" > "$BAK_TEST_HOME/.config/git/ignore"
HOME="$BAK_TEST_HOME" XDG_CONFIG_HOME="$BAK_TEST_HOME/.config" XDG_CACHE_HOME="$BAK_TEST_HOME/.cache" "$SCRIPT_DIR/bin/theme" --set nord --no-live >/dev/null 2>&1
bak_gt=("$BAK_TEST_HOME"/.config/ghostty.bak.*)
bak_bt=("$BAK_TEST_HOME"/.config/btop.bak.*)
bak_td=("$BAK_TEST_HOME"/.config/tealdeer.bak.*)
bak_gc=("$BAK_TEST_HOME"/.config/git/config.bak.*)
if [ -L "$BAK_TEST_HOME/.config/ghostty" ] && [ -f "${bak_gt[0]}/local.conf" ] && \
   [ -L "$BAK_TEST_HOME/.config/btop" ] && [ -f "${bak_bt[0]}/local.conf" ] && \
   [ -L "$BAK_TEST_HOME/.config/tealdeer" ] && [ -f "${bak_td[0]}/local.toml" ] && \
   [ -d "$BAK_TEST_HOME/.config/git" ] && [ ! -L "$BAK_TEST_HOME/.config/git" ] && \
   [ -L "$BAK_TEST_HOME/.config/git/config" ] && [ -f "${bak_gc[0]}" ] && \
   [ -f "$BAK_TEST_HOME/.config/git/ignore" ]; then
    pass "bin/theme sync_symlink backs up pre-existing physical ~/.config/{ghostty,btop,tealdeer} directories and ~/.config/git/config to .bak.<ts> while preserving ~/.config/git/ignore"
else
    fail "bin/theme physical directory backup" "Missing .bak.<ts> backups or clobbered ~/.config/git/ignore"
fi
rm -rf "$BAK_TEST_HOME"

# Provision dotfiles into THEME_TEST_HOME and test switching across all 17 managed themes while preserving ~/.config/git/{ignore,attributes}
HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/modules/10-dotfiles.sh" >/dev/null 2>&1
echo "*.swp" > "$THEME_TEST_Cfg/git/ignore"
echo "*.lock linguist-generated" > "$THEME_TEST_Cfg/git/attributes"

all_switches_ok=true
for t in "${managed_themes[@]}"; do
    HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" --set "$t" --no-live >/dev/null 2>&1
    cur_after="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --current)"
    if [ "$cur_after" != "$t" ] || \
       [ ! -f "$THEME_TEST_Cfg/home-settings/active-theme.theme" ] || \
       [ ! -f "$THEME_TEST_Cfg/home-settings/theme-env.sh" ] || \
       [ ! -f "$THEME_TEST_Cfg/home-settings/zsh-theme.zsh" ] || \
       [ ! -f "$THEME_TEST_Cfg/home-settings/p10k-theme.zsh" ] || \
       [ ! -f "$THEME_TEST_Cfg/home-settings/tmux-theme.conf" ] || \
       ! grep -Fq '#{&&:#{==:#{@ide_ai_state},done},#{==:#{@ide_ai_attn},1}}' "$THEME_TEST_Cfg/home-settings/tmux-theme.conf" || \
       [ ! -L "$THEME_TEST_Cfg/ghostty" ] || \
       [ ! -L "$THEME_TEST_Cfg/btop" ] || \
       [ ! -d "$THEME_TEST_Cfg/git" ] || [ -L "$THEME_TEST_Cfg/git" ] || \
       [ ! -L "$THEME_TEST_Cfg/git/config" ] || \
       [ ! -f "$THEME_TEST_Cfg/git/ignore" ] || \
       [ ! -f "$THEME_TEST_Cfg/git/attributes" ] || \
       [ ! -L "$THEME_TEST_Cfg/tealdeer" ]; then
        all_switches_ok=false
        fail "bin/theme switch $t" "Failed to materialize state or config symlinks for '$t' (cur='$cur_after')"
        break
    fi
done

# Check light mode vs dark mode config propagation (e.g. solarized-light vs catppuccin-mocha)
HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" solarized-light --no-live >/dev/null 2>&1
if grep -Fq "light = true" "$THEME_TEST_Cfg/git/config" && \
   grep -Fq "syntax-theme = Solarized-Light-TrueColor" "$THEME_TEST_Cfg/git/config" && \
   grep -Fq 'commit-style = "#d33682"' "$THEME_TEST_Cfg/git/config" && \
   grep -Fq 'file-style = "#2aa198"' "$THEME_TEST_Cfg/git/config" && \
   grep -Fq 'plus-style = syntax "#e5ecd0"' "$THEME_TEST_Cfg/git/config" && \
   ! grep -Fq 'plus-emph-style = syntax "#e5ecd0"' "$THEME_TEST_Cfg/git/config" && \
   grep -Fq 'color_theme = "solarized_light"' "$THEME_TEST_Cfg/btop/btop.conf" && \
   grep -Fq 'proc_mem_bytes = true' "$THEME_TEST_Cfg/btop/btop.conf" && \
   grep -Fq 'theme = "Solarized Light"' "$THEME_TEST_Cfg/ghostty/config" && \
   grep -Fq 'cursor-text = #fdf6e3' "$SCRIPT_DIR/dotfiles/.config/ghostty/themes/Solarized Light" && \
   grep -Fq 'm/r:^_ide_park_,#W' "$THEME_TEST_Cfg/home-settings/tmux-theme.conf" && \
   grep -Fq "r = 38, g = 139, b = 210" <<< "$(grep -A1 '\[style\.example_text\]' "$THEME_TEST_Cfg/tealdeer/config.toml")" && \
   grep -Fq "r = 42, g = 161, b = 152" <<< "$(grep -A1 '\[style\.example_code\]' "$THEME_TEST_Cfg/tealdeer/config.toml")"; then
    :
else
    all_switches_ok=false
    fail "bin/theme solarized-light config propagation" "Expected light=true, cursor-text=BASE03, distinct plus-emph-style, full btop.conf, _ide_park_ tmux guard, and Blue/Cyan tealdeer styles"
fi

# Verify dotfiles/.tmux.conf sources ~/.config/home-settings/tmux-theme.conf even when XDG_CONFIG_HOME is unset
if command -v tmux >/dev/null 2>&1; then
    TMUX_THEME_SOCK="$THEME_TEST_HOME/tmux-theme.sock"
    (
        unset XDG_CONFIG_HOME
        HOME="$THEME_TEST_HOME" tmux -S "$TMUX_THEME_SOCK" -f "$SCRIPT_DIR/dotfiles/.tmux.conf" new-session -d -s theme_chk "cat" >/dev/null 2>&1
    )
    TMUX_LOADED_STYLE="$(HOME="$THEME_TEST_HOME" tmux -S "$TMUX_THEME_SOCK" show-options -g -v status-style 2>/dev/null || true)"
    HOME="$THEME_TEST_HOME" tmux -S "$TMUX_THEME_SOCK" kill-server >/dev/null 2>&1 || true
    rm -f "$TMUX_THEME_SOCK"
    if [ "$TMUX_LOADED_STYLE" != "fg=#657B83,bg=#EEE8D5" ]; then
        all_switches_ok=false
        fail "dotfiles/.tmux.conf theme sourcing with unset XDG_CONFIG_HOME" "Expected 'fg=#657B83,bg=#EEE8D5', got '$TMUX_LOADED_STYLE'"
    fi
fi

# Switch back to solarized-dark and verify symlinks point back to repo dotfiles without dirtying git repo
HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" solarized-dark --no-live >/dev/null 2>&1
if [ "$all_switches_ok" = true ] && \
   [ "$(readlink "$THEME_TEST_Cfg/btop")" = "$SCRIPT_DIR/dotfiles/.config/btop" ] && \
   [ -d "$THEME_TEST_Cfg/git" ] && [ ! -L "$THEME_TEST_Cfg/git" ] && \
   [ "$(readlink "$THEME_TEST_Cfg/git/config")" = "$SCRIPT_DIR/dotfiles/.config/git/config" ] && \
   [ "$(cat "$THEME_TEST_Cfg/git/ignore")" = "*.swp" ]; then
    pass "bin/theme switches cleanly across all 17 managed themes (dark & light), preserves ~/.config/git/{ignore,attributes}, and updates ghostty, btop, delta, tealdeer, tmux, and shell state without dirtying tracked dotfiles"
else
    fail "bin/theme 17-theme cycle" "Failed switching or restoring symlinks"
fi

# Verify monotonic luminance ramp, canvas & shelf contrast, and semantic utility separation across ALL 17 built-in themes
if python3 - "$SCRIPT_DIR" "$THEME_TEST_HOME" "$THEME_TEST_Cfg" "$THEME_TEST_Cache" <<'PY'; then
import colorsys
import math
import pathlib
import re
import subprocess
import sys

repo = pathlib.Path(sys.argv[1])
test_home = sys.argv[2]
test_cfg = sys.argv[3]
test_cache = sys.argv[4]

def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def rel_lum(rgb):
    def ch(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = rgb
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)

def contrast(h1, h2):
    l1, l2 = rel_lum(hex_to_rgb(h1)), rel_lum(hex_to_rgb(h2))
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)

def rgb_dist(h1, h2):
    r1, g1, b1 = hex_to_rgb(h1)
    r2, g2, b2 = hex_to_rgb(h2)
    rm = (r1 + r2) / 2.0
    dr, dg, db = r1 - r2, g1 - g2, b1 - b2
    return math.sqrt((2 + rm / 256.0) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256.0) * db * db)

def hue_diff(h1, h2):
    r1, g1, b1 = [x / 255.0 for x in hex_to_rgb(h1)]
    r2, g2, b2 = [x / 255.0 for x in hex_to_rgb(h2)]
    hue1, _, _ = colorsys.rgb_to_hsv(r1, g1, b1)
    hue2, _, _ = colorsys.rgb_to_hsv(r2, g2, b2)
    d = abs(hue1 - hue2) * 360.0
    return min(d, 360.0 - d)

classic = [
    "solarized-dark", "solarized-light", "catppuccin-mocha", "catppuccin-latte",
    "gruvbox-dark", "tokyonight-night", "kanagawa-wave", "nord", "onedark",
]
holidays = [
    "new-years", "valentines", "st-patricks", "easter",
    "independence-day", "halloween", "thanksgiving", "christmas",
]
accents = ["YELLOW", "ORANGE", "RED", "MAGENTA", "VIOLET", "BLUE", "CYAN", "GREEN"]
ramp_keys = ["BASE03", "BASE02", "BASE01", "BASE00", "BASE0", "BASE1"]

for slug in classic + holidays:
    p = repo / "colors" / "themes" / f"{slug}.theme"
    d = {}
    for line in p.read_text(encoding="utf-8").splitlines():
        m = re.match(r'^([A-Z0-9_]+)="(.*)"$', line.strip())
        if m:
            d[m.group(1)] = m.group(2)

    is_light = d.get("THEME_MODE", "dark") == "light"
    lums = [rel_lum(hex_to_rgb(d[k])) for k in ramp_keys]
    for idx in range(len(ramp_keys) - 1):
        if is_light and not (lums[idx] > lums[idx + 1]):
            raise SystemExit(f"{slug}: non-monotonic light ramp {ramp_keys[idx]} ({d[ramp_keys[idx]]}) -> {ramp_keys[idx+1]} ({d[ramp_keys[idx+1]]})")
        if not is_light and not (lums[idx] < lums[idx + 1]):
            raise SystemExit(f"{slug}: non-monotonic dark ramp {ramp_keys[idx]} ({d[ramp_keys[idx]]}) -> {ramp_keys[idx+1]} ({d[ramp_keys[idx+1]]})")

    if contrast(d["BASE01"], d["BASE03"]) < 2.3 or contrast(d["BASE01"], d["BASE02"]) < 2.0:
        raise SystemExit(f"{slug}: BASE01 ({d['BASE01']}) contrast too low against BASE03/BASE02")
    if contrast(d["BASE00"], d["BASE02"]) < 2.5 or contrast(d["BASE00"], d["BASE03"]) < 2.9:
        raise SystemExit(f"{slug}: BASE00 ({d['BASE00']}) contrast too low against BASE02/BASE03")
    if slug in ("nord", "catppuccin-latte") or slug in holidays:
        for rk in ("BASE01", "BASE00", "BASE0", "BASE1"):
            if contrast(d[rk], d["BASE02"]) < 3.0 or contrast(d[rk], d["BASE03"]) < 3.0:
                raise SystemExit(f"{slug}: {rk} ({d[rk]}) contrast < 3.0 against BASE02 ({d['BASE02']}) or BASE03 ({d['BASE03']})")

    gr_d = rgb_dist(d["GREEN"], d["RED"])
    gr_h = hue_diff(d["GREEN"], d["RED"])
    yr_d = rgb_dist(d["YELLOW"], d["RED"])
    yr_h = hue_diff(d["YELLOW"], d["RED"])
    yg_d = rgb_dist(d["YELLOW"], d["GREEN"])
    mix_d = rgb_dist(d["MIX_GREEN"], d["MIX_RED"])

    if gr_d < 190 or gr_h < 28:
        raise SystemExit(f"{slug}: GREEN ({d['GREEN']}) vs RED ({d['RED']}) too close: dist={gr_d:.1f} hue={gr_h:.1f}")
    if yr_d < (220 if slug in holidays else 120) or yr_h < 25:
        raise SystemExit(f"{slug}: YELLOW ({d['YELLOW']}) vs RED ({d['RED']}) too close: dist={yr_d:.1f} hue={yr_h:.1f}")
    if yg_d < (200 if slug in holidays else 80):
        raise SystemExit(f"{slug}: YELLOW ({d['YELLOW']}) vs GREEN ({d['GREEN']}) too close: dist={yg_d:.1f}")
    if mix_d < 30:
        raise SystemExit(f"{slug}: MIX_GREEN ({d['MIX_GREEN']}) vs MIX_RED ({d['MIX_RED']}) too close: dist={mix_d:.1f}")

    rg, gg, bg = hex_to_rgb(d["MIX_GREEN"])
    rr, gr, br = hex_to_rgb(d["MIX_RED"])
    if (gg - rg) <= (gr - rr) + 15:
        raise SystemExit(f"{slug}: MIX_GREEN ({d['MIX_GREEN']}) vs MIX_RED ({d['MIX_RED']}) lacks green/red polarity")

    or_r, or_g, or_b = hex_to_rgb(d["ORANGE"])
    if not (or_r > or_g > or_b):
        raise SystemExit(f"{slug}: ORANGE ({d['ORANGE']}) is not a warm orange/ember hue (R > G > B)")

    if contrast(d["BASE0"], d["BASE03"]) < (7.0 if slug in holidays else 4.0):
        raise SystemExit(f"{slug}: BASE0 contrast against BASE03 too low")

    for i in range(len(accents)):
        min_c = 3.0 if (slug in holidays or slug == "catppuccin-latte") else 2.8
        min_shelf_c = 3.0 if slug == "catppuccin-latte" else 2.2
        if contrast(d[accents[i]], d["BASE03"]) < min_c:
            raise SystemExit(f"{slug}: {accents[i]} ({d[accents[i]]}) contrast against BASE03 < {min_c}")
        if contrast(d[accents[i]], d["BASE02"]) < min_shelf_c:
            raise SystemExit(f"{slug}: {accents[i]} ({d[accents[i]]}) contrast against BASE02 shelf < {min_shelf_c}")
        if slug in holidays:
            for j in range(i + 1, len(accents)):
                pair_d = rgb_dist(d[accents[i]], d[accents[j]])
                if pair_d < 100:
                    raise SystemExit(f"{slug}: {accents[i]} ({d[accents[i]]}) vs {accents[j]} ({d[accents[j]]}) dist={pair_d:.1f} < 100")

# Verify generated zsh-theme.zsh, git/config, p10k-theme.zsh, theme-env.sh, and tmux-theme.conf for holiday vs classic
env = {"HOME": test_home, "XDG_CONFIG_HOME": test_cfg, "XDG_CACHE_HOME": test_cache, "PATH": "/usr/bin:/bin"}
cfg_root = pathlib.Path(test_cfg)
for slug in ("independence-day", "christmas", "valentines", "easter", "halloween"):
    subprocess.run([str(repo / "bin" / "theme"), "--set", slug, "--no-live"], env=env, stdout=subprocess.DEVNULL, check=True)
    zsh_txt = (cfg_root / "home-settings" / "zsh-theme.zsh").read_text(encoding="utf-8")
    cmd_col = re.search(r'ZSH_HIGHLIGHT_STYLES\[command\]="fg=(#[0-9A-Fa-f]{6})"', zsh_txt).group(1)
    unk_col = re.search(r'ZSH_HIGHLIGHT_STYLES\[unknown-token\]="fg=(#[0-9A-Fa-f]{6})"', zsh_txt).group(1)
    res_col = re.search(r'ZSH_HIGHLIGHT_STYLES\[reserved-word\]="fg=(#[0-9A-Fa-f]{6})"', zsh_txt).group(1)
    if rgb_dist(cmd_col, unk_col) < 190 or rgb_dist(res_col, unk_col) < 190 or rgb_dist(cmd_col, res_col) < 150:
        raise SystemExit(f"{slug}: zsh-theme.zsh command/reserved-word/unknown-token collision: {cmd_col}, {res_col}, {unk_col}")

    git_txt = (cfg_root / "git" / "config").read_text(encoding="utf-8")
    plus_emph = re.search(r'plus-emph-style = syntax "(#[0-9a-f]{6})"', git_txt).group(1)
    minus_emph = re.search(r'minus-emph-style = syntax "(#[0-9a-f]{6})"', git_txt).group(1)
    pe_r, pe_g, _ = hex_to_rgb(plus_emph)
    me_r, me_g, _ = hex_to_rgb(minus_emph)
    if (pe_g - pe_r) <= (me_g - me_r) + 20:
        raise SystemExit(f"{slug}: git delta plus-emph-style ({plus_emph}) vs minus-emph-style ({minus_emph}) lacks green/red polarity")

    env_txt = (cfg_root / "home-settings" / "theme-env.sh").read_text(encoding="utf-8")
    p10k_txt = (cfg_root / "home-settings" / "p10k-theme.zsh").read_text(encoding="utf-8")
    tmux_txt = (cfg_root / "home-settings" / "tmux-theme.conf").read_text(encoding="utf-8")
    if "export _HS_PROMPT_OS_ICON=" not in env_txt or "POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION=" not in p10k_txt or "" in tmux_txt:
        raise SystemExit(f"{slug}: missing holiday emblem in theme-env.sh, p10k-theme.zsh, or tmux-theme.conf")

subprocess.run([str(repo / "bin" / "theme"), "--set", "solarized-dark", "--no-live"], env=env, stdout=subprocess.DEVNULL, check=True)
env_txt = (cfg_root / "home-settings" / "theme-env.sh").read_text(encoding="utf-8")
p10k_txt = (cfg_root / "home-settings" / "p10k-theme.zsh").read_text(encoding="utf-8")
tmux_txt = (cfg_root / "home-settings" / "tmux-theme.conf").read_text(encoding="utf-8")
if "unset _HS_PROMPT_OS_ICON" not in env_txt or "unset POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION" not in p10k_txt or " #S" not in tmux_txt:
    raise SystemExit("solarized-dark: failed to restore neutral OS/Tmux icons")
PY
    pass "All 17 built-in themes maintain monotonic BASE03..BASE1 luminance ramps, canvas & shelf contrast, strict semantic utility separation, opposing MIX_GREEN/MIX_RED diff polarity, and holiday prompt/Tmux emblems"
else
    fail "17-theme monotonic ramp, contrast & semantic utility" "One or more themes violated ramp monotonicity, contrast, or diff polarity invariants"
fi

# Verify custom user themes (--path, --create, --from, --force, apply custom theme, re-apply regeneration, and reject invalid hex)
USER_THEMES_PATH="$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --path)"
assert_eq "$USER_THEMES_PATH" "$THEME_TEST_Cfg/themes" "bin/theme --path outputs XDG user themes directory"

HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --create cyber-custom --from kanagawa-wave >/dev/null 2>&1
if [ -f "$THEME_TEST_Cfg/themes/cyber-custom.theme" ] && \
   ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --create cyber-custom >/dev/null 2>&1 && \
   HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --create cyber-custom --from nord --force >/dev/null 2>&1; then
    sed -i.bak 's/^BASE03=.*/BASE03="#112233"/' "$THEME_TEST_Cfg/themes/cyber-custom.theme"
    rm -f "$THEME_TEST_Cfg/themes/cyber-custom.theme.bak"
    HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" cyber-custom --no-live >/dev/null 2>&1
    # Edit custom theme and re-apply to verify Ghostty and btop custom theme files are regenerated (M2)
    sed -i.bak 's/^BASE03=.*/BASE03="#1A2B3C"/' "$THEME_TEST_Cfg/themes/cyber-custom.theme"
    rm -f "$THEME_TEST_Cfg/themes/cyber-custom.theme.bak"
    HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" cyber-custom --no-live >/dev/null 2>&1
    if [ "$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --current)" = "cyber-custom" ] && \
       grep -Fq 'BASE03="#1A2B3C"' "$THEME_TEST_Cfg/home-settings/active-theme.theme" && \
       [ -f "$THEME_TEST_Cfg/bat/themes/Cyber-Custom-TrueColor.tmTheme" ] && \
       grep -Fq '#1a2b3c' "$THEME_TEST_Cfg/btop/themes/cyber_custom.theme" && \
       grep -Fq 'background = #1a2b3c' "$THEME_TEST_Cfg/ghostty/themes/Cyber Custom"; then
        pass "bin/theme --create scaffolds custom user theme (--from / --force) and regenerates custom .tmTheme, btop, and ghostty assets on re-apply"
    else
        fail "bin/theme custom theme apply/re-apply" "Custom theme assets or state were not regenerated on re-apply"
    fi
else
    fail "bin/theme --create" "Failed to scaffold or guard custom user theme file"
fi

# Verify macOS Ghostty Application Support symlinking + SIGUSR2 reload (M1), OS=macos terminal broadcast, and macos-terminal-solarized cfprefsd-safe export/import + .conf encoding (M3)
MACOS_MOCK_HOME="$(mktemp -d)"
MACOS_MOCK_BIN="$MACOS_MOCK_HOME/mock-bin"
mkdir -p "$MACOS_MOCK_HOME/Library/Application Support" "$MACOS_MOCK_HOME/Library/Preferences" "$MACOS_MOCK_HOME/.config/themes" "$MACOS_MOCK_BIN"
cat > "$MACOS_MOCK_BIN/pkill" <<'SH'
#!/usr/bin/env bash
echo "pkill $*" >> "$MACOS_PKILL_LOG"
exit 0
SH
cat > "$MACOS_MOCK_BIN/defaults" <<'SH'
#!/usr/bin/env bash
echo "defaults $*" >> "$MACOS_DEFAULTS_LOG"
if [ "${1:-}" = "export" ] && [ "${2:-}" = "com.apple.Terminal" ] && [ "${3:-}" = "-" ]; then
    if [ -f "$HOME/Library/Preferences/com.apple.Terminal.plist" ]; then
        cat "$HOME/Library/Preferences/com.apple.Terminal.plist"
    else
        python3 - <<'PY'
import plistlib, sys
plistlib.dump({"Window Settings": {"ExistingCustomProfile": {"FontAntialias": True}}}, sys.stdout.buffer)
PY
    fi
    exit 0
fi
if [ "${1:-}" = "import" ] && [ "${2:-}" = "com.apple.Terminal" ] && [ -f "${3:-}" ]; then
    exit 0
fi
if [ "${1:-}" = "write" ]; then
    exit 1
fi
exit 0
SH
cat > "$MACOS_MOCK_BIN/pgrep" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$MACOS_MOCK_BIN/pkill" "$MACOS_MOCK_BIN/defaults" "$MACOS_MOCK_BIN/pgrep"
cat > "$MACOS_MOCK_HOME/.config/themes/conf-file.conf" <<'EOF'
export THEME_ID='decoupled-macos' # decoupled slug in .conf
THEME_LABEL="Mac Custom 🌙" # non-BMP label
BASE03='#122334' # custom bg
EOF
MACOS_PKILL_LOG="$MACOS_MOCK_HOME/pkill.log" MACOS_DEFAULTS_LOG="$MACOS_MOCK_HOME/defaults.log" OS=macos THEME_LIVE_NVIM=0 NVIM_IDE_SOCKET="" TMUX="" TMUX_TMPDIR="" PATH="$MACOS_MOCK_BIN:$PATH" HOME="$MACOS_MOCK_HOME" XDG_CONFIG_HOME="$MACOS_MOCK_HOME/.config" XDG_CACHE_HOME="$MACOS_MOCK_HOME/.cache" "$SCRIPT_DIR/bin/theme" --set nord >/dev/null 2>&1
if [ -L "$MACOS_MOCK_HOME/Library/Application Support/com.mitchellh.ghostty/config" ] && \
   [ -L "$MACOS_MOCK_HOME/Library/Application Support/com.mitchellh.ghostty/themes" ] && \
   grep -Fq -- "-USR2" "$MACOS_MOCK_HOME/pkill.log" && \
   grep -Fq "ghostty" "$MACOS_MOCK_HOME/pkill.log"; then
    pass "bin/theme links macOS ~/Library/Application Support/com.mitchellh.ghostty/{config,themes} and broadcasts SIGUSR2 reload"
else
    fail "bin/theme macOS Ghostty support" "Missing Application Support symlinks or SIGUSR2 pkill reload"
fi

if [ -f "$MACOS_MOCK_HOME/Library/Preferences/com.apple.Terminal.plist" ] && \
   MACOS_DEFAULTS_LOG="$MACOS_MOCK_HOME/defaults.log" OS=macos PATH="$MACOS_MOCK_BIN:$PATH" HOME="$MACOS_MOCK_HOME" XDG_CONFIG_HOME="$MACOS_MOCK_HOME/.config" "$SCRIPT_DIR/bin/macos-terminal-solarized" --theme decoupled-macos >/dev/null 2>&1 && \
   ! MACOS_DEFAULTS_LOG="$MACOS_MOCK_HOME/defaults.log" OS=macos PATH="$MACOS_MOCK_BIN:$PATH" HOME="$MACOS_MOCK_HOME" XDG_CONFIG_HOME="$MACOS_MOCK_HOME/.config" "$SCRIPT_DIR/bin/macos-terminal-solarized" --theme nonexistent-xyz >/dev/null 2>&1 && \
   grep -Fq "defaults export com.apple.Terminal -" "$MACOS_MOCK_HOME/defaults.log" && \
   grep -Fq "defaults import com.apple.Terminal" "$MACOS_MOCK_HOME/defaults.log" && \
   ! grep -Fq "defaults write" "$MACOS_MOCK_HOME/defaults.log" && \
   python3 - "$MACOS_MOCK_HOME/Library/Preferences/com.apple.Terminal.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    pl = plistlib.load(f)
assert "ExistingCustomProfile" in pl["Window Settings"]
assert "Nord" in pl["Window Settings"]
prof_nord = pl["Window Settings"]["Nord"]
bg_nord = plistlib.loads(prof_nord["BackgroundColor"])
rgb_nord = bg_nord["$objects"][1]["NSRGB"].decode("ascii").rstrip("\x00")
assert tuple(round(float(x) * 255) for x in rgb_nord.split()) == (0x2E, 0x34, 0x40)
assert len([k for k in prof_nord if k.startswith("ANSI") and k.endswith("Color")]) == 16
assert "blackColour" not in prof_nord
assert pl["Default Window Settings"] == "Mac Custom 🌙"
assert pl["Startup Window Settings"] == "Mac Custom 🌙"
prof_custom = pl["Window Settings"]["Mac Custom 🌙"]
bg_custom = plistlib.loads(prof_custom["BackgroundColor"])
rgb_custom = bg_custom["$objects"][1]["NSRGB"].decode("ascii").rstrip("\x00")
assert tuple(round(float(x) * 255) for x in rgb_custom.split()) == (0x12, 0x23, 0x34)
PY
then
    pass "bin/macos-terminal-solarized preserves cfprefsd profiles via defaults export/import, encodes 22 sRGB NSColor slots (including OS=macos broadcast and .conf custom themes), and rejects unknown themes"
else
    fail "bin/macos-terminal-solarized plist encoding" "Failed cfprefsd export/import, Nord/.conf profile encoding, or unknown theme rejection"
fi
rm -rf "$MACOS_MOCK_HOME"

# Verify dbus-run-session gnome-terminal-solarized across all 17 built-in themes, non-BMP emoji labels, .conf decoupled custom themes, and unknown theme rejection (H2/T3)
if command -v dbus-run-session >/dev/null 2>&1 && command -v dconf >/dev/null 2>&1; then
    GT_TEST_HOME="$(mktemp -d)"
    mkdir -p "$GT_TEST_HOME/.config/themes" "$GT_TEST_HOME/run" "$GT_TEST_HOME/mock-bin"
    chmod 700 "$GT_TEST_HOME/run"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "org.gnome.Terminal.ProfilesList"' > "$GT_TEST_HOME/mock-bin/gsettings"
    chmod +x "$GT_TEST_HOME/mock-bin/gsettings"
    cat > "$GT_TEST_HOME/.config/themes/partial-custom.theme" <<'EOF'
THEME_ID="partial-custom"
THEME_LABEL="O'Brien's Partial Theme"
BASE03="#101820"
EOF
    cat > "$GT_TEST_HOME/.config/themes/spooky-file.conf" <<'EOF'
export THEME_ID='spooky-emoji' # decoupled ID
THEME_LABEL="Spooky 🎃 Night" # non-BMP UTF-8 emoji
export BASE03='#140a1e' # dark purple
EOF
    cat > "$GT_TEST_HOME/run-gt.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
script_dir="$1"
shift
prof_path="/org/gnome/terminal/legacy/profiles:/:321fa646-e6ab-45a1-88d8-00aa66d158d8"
for slug in "$@"; do
    "$script_dir/bin/gnome-terminal-solarized" --theme "$slug" >/dev/null
done
"$script_dir/bin/gnome-terminal-solarized" --theme new-years >/dev/null
ny_name="$(dconf read "$prof_path/visible-name")"
[[ "$ny_name" == *"New Year"* ]]
"$script_dir/bin/gnome-terminal-solarized" --theme partial-custom >/dev/null
pc_name="$(dconf read "$prof_path/visible-name")"
pc_bg="$(dconf read "$prof_path/background-color")"
[[ "$pc_name" == *"O'Brien"* ]]
[[ "$pc_bg" == *"#101820"* ]]
"$script_dir/bin/gnome-terminal-solarized" --theme spooky-emoji >/dev/null
spooky_name="$(dconf read "$prof_path/visible-name")"
spooky_bg="$(dconf read "$prof_path/background-color")"
[[ "$spooky_name" == *"Spooky 🎃 Night"* ]]
[[ "$spooky_bg" == *"#140A1E"* ]]
if "$script_dir/bin/gnome-terminal-solarized" --theme nonexistent-theme-xyz >/dev/null 2>&1; then
    exit 1
fi
EOF
    chmod +x "$GT_TEST_HOME/run-gt.sh"
    if PATH="$GT_TEST_HOME/mock-bin:$PATH" XDG_RUNTIME_DIR="$GT_TEST_HOME/run" HOME="$GT_TEST_HOME" XDG_CONFIG_HOME="$GT_TEST_HOME/.config" XDG_CACHE_HOME="$GT_TEST_HOME/.cache" dbus-run-session -- "$GT_TEST_HOME/run-gt.sh" "$SCRIPT_DIR" "${managed_themes[@]}" >/dev/null 2>&1; then
        pass "bin/gnome-terminal-solarized writes valid GVariant dconf profiles across all 17 themes, apostrophe & non-BMP emoji labels, .conf custom themes, and rejects unknown themes"
    else
        fail "bin/gnome-terminal-solarized dbus-run-session" "Failed writing dconf profile across 17 themes, emoji/.conf custom themes, or rejecting unknown theme"
    fi
    rm -rf "$GT_TEST_HOME"
fi

# Verify invalid hex code in custom theme is rejected cleanly
cat > "$THEME_TEST_Cfg/themes/broken-hex.theme" <<'EOF'
THEME_ID="broken-hex"
BASE03="not-a-hex"
EOF
if ! HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --set broken-hex --no-live >/dev/null 2>&1; then
    pass "bin/theme rejects custom theme file containing malformed hex color values"
else
    fail "bin/theme malformed hex validation" "Expected non-zero exit for invalid hex color"
fi
rm -f "$THEME_TEST_Cfg/themes/broken-hex.theme"

# Verify interactive fzf picker when invoked with no arguments
FZF_MOCK_BIN="$(mktemp -d)"
cat > "$FZF_MOCK_BIN/fzf" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == --preview=* ]]; then
        echo "$arg" > "$FZF_MOCK_LOG"
    fi
done
cat >/dev/null
printf '* gruvbox-dark  Gruvbox Dark  [dark]  Warm retro groove dark palette\n'
SH
chmod +x "$FZF_MOCK_BIN/fzf"
FZF_MOCK_LOG="$FZF_MOCK_BIN/preview.log" THEME_FORCE_FZF=1 PATH="$FZF_MOCK_BIN:$PATH" HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" --no-live >/dev/null 2>&1
if [ "$(HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" "$SCRIPT_DIR/bin/theme" --current)" = "gruvbox-dark" ] && \
   grep -Fq -- "--preview {1}" "$FZF_MOCK_BIN/preview.log"; then
    pass "bin/theme (no args) launches interactive fzf picker with live '--preview {1}' and applies selected theme"
else
    fail "bin/theme fzf picker" "Expected gruvbox-dark to be applied via fzf picker"
fi
rm -rf "$FZF_MOCK_BIN"

# Verify live Neovim RPC hot-reload across both IDE sockets and standalone */nvim.*.0 sockets (hermetic: THEME_UPDATE_TERMINAL_PROFILE=0 TMUX="" THEME_NVIM_SOCKET_DIR)
if command -v nvim >/dev/null 2>&1; then
    LIVE_NVIM_SOCK_DIR="$THEME_TEST_HOME/nvim-sockets"
    mkdir -p "$LIVE_NVIM_SOCK_DIR/standalone-sub"
    LIVE_NVIM_SOCK="$LIVE_NVIM_SOCK_DIR/nvim-ide-theme-test.sock"
    STANDALONE_NVIM_SOCK="$LIVE_NVIM_SOCK_DIR/standalone-sub/nvim.42424.0"
    ORIG_XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
    rm -f "$LIVE_NVIM_SOCK" "$STANDALONE_NVIM_SOCK"
    (cd "$SCRIPT_DIR" && XDG_DATA_HOME="$ORIG_XDG_DATA_HOME" HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" nvim --headless -u "$SCRIPT_DIR/dotfiles/.config/nvim/init.lua" --listen "$LIVE_NVIM_SOCK" >/dev/null 2>&1) &
    LIVE_NVIM_PID=$!
    (cd "$SCRIPT_DIR" && XDG_DATA_HOME="$ORIG_XDG_DATA_HOME" HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" nvim --headless -u "$SCRIPT_DIR/dotfiles/.config/nvim/init.lua" --listen "$STANDALONE_NVIM_SOCK" >/dev/null 2>&1) &
    STANDALONE_NVIM_PID=$!
    if wait_for_nvim_socket "$LIVE_NVIM_SOCK" 60 1 && wait_for_nvim_socket "$STANDALONE_NVIM_SOCK" 60 1; then
        THEME_UPDATE_TERMINAL_PROFILE=0 TMUX="" TMUX_TMPDIR="" THEME_NVIM_SOCKET_DIR="$LIVE_NVIM_SOCK_DIR" NVIM_IDE_SOCKET="" HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" --set catppuccin-mocha >/dev/null 2>&1
        NVIM_LIVE_STATE="$(nvim --headless --server "$LIVE_NVIM_SOCK" --remote-expr "get(g:, 'home_settings_theme', '') . ':' . toupper(synIDattr(hlID('Normal'), 'bg#', 'gui')) . ':' . toupper(synIDattr(hlID('Normal'), 'fg#', 'gui'))" 2>/dev/null || true)"
        NVIM_STANDALONE_STATE="$(nvim --headless --server "$STANDALONE_NVIM_SOCK" --remote-expr "get(g:, 'home_settings_theme', '') . ':' . toupper(synIDattr(hlID('Normal'), 'bg#', 'gui')) . ':' . toupper(synIDattr(hlID('Normal'), 'fg#', 'gui'))" 2>/dev/null || true)"
        if [ "$NVIM_LIVE_STATE" = "catppuccin-mocha:#1E1E2E:#CDD6F4" ] && [ "$NVIM_STANDALONE_STATE" = "catppuccin-mocha:#1E1E2E:#CDD6F4" ]; then
            pass "bin/theme hot-reloads both IDE and standalone (*/nvim.*.0) live Neovim servers over RPC (g:home_settings_theme=catppuccin-mocha, Normal=#CDD6F4 on #1E1E2E)"
        else
            fail "bin/theme live Neovim RPC reload" "Expected 'catppuccin-mocha:#1E1E2E:#CDD6F4' on both servers, got IDE='$NVIM_LIVE_STATE' standalone='$NVIM_STANDALONE_STATE'"
        fi
    else
        fail "bin/theme live Neovim socket" "Timed out waiting for headless Neovim servers"
    fi
    kill "$LIVE_NVIM_PID" "$STANDALONE_NVIM_PID" 2>/dev/null || true
    rm -f "$LIVE_NVIM_SOCK" "$STANDALONE_NVIM_SOCK"
fi

# Verify bin/theme generated Ghostty keybindings and live tmux global FZF_DEFAULT_OPTS broadcast
if grep -Fq 'keybind = ctrl+shift+t=new_tab' "$THEME_TEST_Cfg/ghostty/config" && \
   grep -Fq 'keybind = alt+left=text:\x1b[1;3D' "$THEME_TEST_Cfg/ghostty/config" && \
   grep -Fq 'keybind = alt+right=text:\x1b[1;3C' "$THEME_TEST_Cfg/ghostty/config" && \
   grep -Fq 'keybind = alt+up=text:\x1b[1;3A' "$THEME_TEST_Cfg/ghostty/config" && \
   grep -Fq 'keybind = alt+down=text:\x1b[1;3B' "$THEME_TEST_Cfg/ghostty/config"; then
    pass "bin/theme generates Ghostty config with Ctrl+Shift+T and Alt+Left/Right/Up/Down ESC keybindings"
else
    fail "bin/theme Ghostty keybindings" "Missing Ctrl+Shift+T or Alt+Arrow keybindings in generated Ghostty config"
fi

if command -v tmux >/dev/null 2>&1; then
    LIVE_TMUX_TMP="$(mktemp -d)"
    if TMUX="" TMUX_TMPDIR="$LIVE_TMUX_TMP" tmux -f /dev/null new-session -d -s theme_live_tmux "exec sleep 30" >/dev/null 2>&1; then
        THEME_UPDATE_TERMINAL_PROFILE=0 THEME_LIVE_NVIM=0 TMUX="" TMUX_TMPDIR="$LIVE_TMUX_TMP" HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" --set nord >/dev/null 2>&1
        tmux_fzf_env="$(TMUX="" TMUX_TMPDIR="$LIVE_TMUX_TMP" tmux show-environment -g FZF_DEFAULT_OPTS 2>/dev/null || true)"
        TMUX="" TMUX_TMPDIR="$LIVE_TMUX_TMP" tmux kill-session -t "=theme_live_tmux" >/dev/null 2>&1 || true
        if [[ "$tmux_fzf_env" == "FZF_DEFAULT_OPTS=--color=bg+:#3B4252,bg:#2E3440,"* ]]; then
            pass "bin/theme broadcasts updated FZF_DEFAULT_OPTS into live tmux global environment"
        else
            fail "bin/theme live tmux FZF_DEFAULT_OPTS" "Expected Nord FZF_DEFAULT_OPTS in tmux global env, got '$tmux_fzf_env'"
        fi
    fi
    rm -rf "$LIVE_TMUX_TMP"
fi

# Verify uniform preview card geometry across ALL 17 built-in themes (standalone 94 cols and narrow fzf 72 cols) and Tmux status-right client_width>=105 holiday guard
HOME="$THEME_TEST_HOME" XDG_CONFIG_HOME="$THEME_TEST_Cfg" XDG_CACHE_HOME="$THEME_TEST_Cache" "$SCRIPT_DIR/bin/theme" --set halloween --no-live >/dev/null 2>&1
if grep -Fq '#{>=:#{client_width},105}' "$THEME_TEST_Cfg/home-settings/tmux-theme.conf" && \
   python3 - "$SCRIPT_DIR/bin/theme" "$SCRIPT_DIR/bin/ide" "${managed_themes[@]}" <<'PY'
import os, re, subprocess, sys
theme_bin, ide_bin = sys.argv[1], sys.argv[2]
slugs = sys.argv[3:]
ANSI_RE = re.compile(r"\033\[[0-9;]*m")
def vlen(s):
    plain = ANSI_RE.sub("", s)
    return sum(2 if (0x1F300 <= ord(c) <= 0x1FAFF or c == "✨") else 1 for c in plain)

for slug in slugs:
    env = dict(os.environ)
    env.pop("FZF_PREVIEW_COLUMNS", None)
    env.pop("FZF_PREVIEW_LINES", None)
    out = subprocess.check_output([theme_bin, "--preview", slug], env=env, text=True).splitlines()
    if {vlen(line) for line in out} != {94}:
        raise SystemExit(f"{slug}: standalone width != 94")
    env["FZF_PREVIEW_COLUMNS"] = "72"
    env["FZF_PREVIEW_LINES"] = "30"
    out_narrow = subprocess.check_output([theme_bin, "--preview", slug], env=env, text=True).splitlines()
    status_lines = [line for line in out_narrow if "Editor" in line]
    if not status_lines or vlen(status_lines[0]) != 72:
        raise SystemExit(f"{slug}: narrow status width != 72")

# Verify status_click in bin/ide accounts for 2-column holiday emoji in status-left
src = open(ide_bin, encoding="utf-8").read()
assert "#{status-left}" in src and "0x1F300 <= ord(ch) <= 0x1FAFF" in src
PY
then
    pass "bin/theme renders uniform rectangular preview cards across all 17 themes (standalone 94-col & narrow 72-col fzf), guards Tmux holiday badge with client_width>=105, and bin/ide status_click accounts for 2-cell holiday emojis"
else
    fail "bin/theme 17-theme preview geometry & Tmux status-bar holiday guards" "Preview card widths, client_width>=105 guard, or bin/ide status-left emoji width calculation failed"
fi

rm -rf "$THEME_TEST_HOME"

# End-to-end hermetic multi-session workspace switcher, parked-window exclusion, live ANSI preview, and context dispatch tests
if command -v tmux >/dev/null 2>&1; then
    FLEET_TEST_OUT="$(python3 - "$SCRIPT_DIR" 2>&1 <<'PY'
import fcntl
import os
import pty
import re
import select
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

repo_dir = sys.argv[1]
ide_src = os.path.join(repo_dir, "bin", "ide")
tmux_conf_src = os.path.join(repo_dir, "dotfiles", ".tmux.conf")

root = tempfile.mkdtemp(prefix="ide-fleet-suite.")
client_proc = None
client_mfd = None
client2_proc = None
client2_mfd = None
base_env = {}

def run_cmd(args, env=None, input_text=None, check=True, cwd=None):
    e = dict(base_env if env is None else env)
    return subprocess.run(
        args,
        input=input_text,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=e,
        cwd=cwd,
        check=check,
    )

def tmux(*args, check=False):
    return run_cmd(["tmux", *args], env={**base_env, "TMUX": "", "TMUX_PANE": ""}, check=check)

def tmux_out(*args):
    r = tmux(*args, check=False)
    return r.stdout.rstrip("\n") if r.returncode == 0 else ""

def wait_until(pred, timeout=3.0, step=0.03):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        val = pred()
        if val:
            return val
        time.sleep(step)
    return pred()

try:
    thome = os.path.join(root, "home")
    tmux_tmp = os.path.join(root, "tmux_tmp")
    xdg_cfg = os.path.join(thome, ".config")
    xdg_cache = os.path.join(thome, ".cache")
    xdg_run = os.path.join(root, "run")
    bin_dir = os.path.join(thome, ".local", "bin")
    for d in (thome, tmux_tmp, xdg_cfg, xdg_cache, xdg_run, bin_dir):
        os.makedirs(d, mode=0o700, exist_ok=True)

    ide_bin = os.path.join(bin_dir, "ide")
    os.symlink(ide_src, ide_bin)
    os.symlink(tmux_conf_src, os.path.join(thome, ".tmux.conf"))

    clean_path = f"{bin_dir}:{os.environ.get('PATH', '/usr/bin:/bin')}"
    base_env = {
        "HOME": thome,
        "PATH": clean_path,
        "TMUX_TMPDIR": tmux_tmp,
        "XDG_CONFIG_HOME": xdg_cfg,
        "XDG_CACHE_HOME": xdg_cache,
        "XDG_RUNTIME_DIR": xdg_run,
        "TERM": "xterm-256color",
        "LANG": os.environ.get("LANG", "C.UTF-8"),
        "NO_COLOR": "1",
    }

    # 1. Server-down safety for --list, --list --plain, --sessions, and --send error paths
    r_plain0 = run_cmd([ide_bin, "--list", "--plain"], env={**base_env, "TMUX": ""}, check=False)
    assert r_plain0.returncode == 0 and r_plain0.stdout.strip() == "", f"plain0={r_plain0}"
    r_list0 = run_cmd([ide_bin, "--list"], env={**base_env, "TMUX": ""}, check=False)
    assert r_list0.returncode == 0 and "No active IDE sessions." in r_list0.stdout, f"list0={r_list0.stdout}"
    r_sess0 = run_cmd([ide_bin, "--sessions"], env={**base_env, "TMUX": ""}, check=False)
    assert r_sess0.returncode == 0 and "No active IDE sessions." in r_sess0.stdout, f"sess0={r_sess0.stdout}"
    r_send_missing_mode = run_cmd([ide_bin, "--send"], env={**base_env, "TMUX": ""}, check=False)
    assert r_send_missing_mode.returncode != 0, "expected non-zero when --send has no payload flag"
    r_send_missing_sess = run_cmd([ide_bin, "--send", "--text", "hi", "missing-sess"], env={**base_env, "TMUX": ""}, check=False)
    assert r_send_missing_sess.returncode != 0, "expected non-zero when --send targets missing session"

    # Boot isolated server with non-IDE session + ai-*/agy-* popup sessions (all must be excluded)
    tmux("-f", os.path.join(thome, ".tmux.conf"), "new-session", "-d", "-s", "plain-non-ide", "-x", "160", "-y", "48", "exec sleep 300", check=True)
    tmux("new-session", "-d", "-s", "ai-alpha-ws", "-x", "120", "-y", "40", "exec sleep 300", check=True)
    tmux("new-session", "-d", "-s", "agy-beta-ws", "-x", "120", "-y", "40", "exec sleep 300", check=True)
    tmux("set-option", "-q", "-t", "=ai-alpha-ws:", "@ide_session", "ai-alpha-ws", check=True)
    tmux("set-option", "-q", "-t", "=agy-beta-ws:", "@ide_session", "agy-beta-ws", check=True)

    def make_ws(name, ai_cmd="exec sleep 300", ed_cmd="exec sleep 300", ai_cli="agy", git_branch="", git_dirty=False, in_home=False):
        ws_parent = os.path.join(thome, "projects") if in_home else os.path.join(root, "ws")
        ws_dir = os.path.join(ws_parent, name)
        os.makedirs(os.path.join(ws_dir, "sub"), exist_ok=True)
        with open(os.path.join(ws_dir, "README.md"), "w", encoding="utf-8") as f:
            f.write(f"# {name}\nline2\nline3\n")
        with open(os.path.join(ws_dir, "sub", "mod.py"), "w", encoding="utf-8") as f:
            f.write("\n".join(f"line_{i}" for i in range(1, 25)) + "\n")
        if git_branch:
            run_cmd(["git", "-C", ws_dir, "init", "-q", "-b", git_branch], check=True)
            run_cmd(["git", "-C", ws_dir, "config", "user.email", "test@example.com"], check=True)
            run_cmd(["git", "-C", ws_dir, "config", "user.name", "Test User"], check=True)
            run_cmd(["git", "-C", ws_dir, "add", "."], check=True)
            run_cmd(["git", "-C", ws_dir, "commit", "-q", "-m", "init"], check=True)
            if git_dirty:
                with open(os.path.join(ws_dir, "README.md"), "a", encoding="utf-8") as f:
                    f.write("dirty\n")

        sock_path = os.path.join(xdg_run, f"nvim-ide-{name}.sock")
        env_flags = [
            "-e", f"IDE_SESSION={name}",
            "-e", f"IDE_AI_CLI={ai_cli}",
            "-e", f"NVIM_IDE_SOCKET={sock_path}",
            "-e", f"IDE_INITIAL_ROOT={ws_dir}",
        ]
        ai_shell = "/bin/sh" if ai_cmd == "exec /bin/sh" else f"/bin/sh -c {shlex.quote(ai_cmd + '; :')}"
        ed_shell = "exec sleep 300" if ed_cmd == "exec sleep 300" else f"/bin/sh -c {shlex.quote(ed_cmd + '; :')}"
        init = tmux_out(
            "new-session", "-d", "-P", "-F", "#{pane_id}\t#{window_id}",
            "-s", name, "-n", "ide", "-c", ws_dir, "-x", "160", "-y", "48",
            *env_flags, ai_shell,
        )
        p_ai, m_win = init.split("\t")
        p_ed = tmux_out("split-window", "-h", "-P", "-F", "#{pane_id}", "-t", p_ai, "-l", "50%", "-c", ws_dir, *env_flags, ed_shell)
        p_tm = tmux_out("split-window", "-f", "-v", "-P", "-F", "#{pane_id}", "-t", m_win, "-l", "25%", "-c", ws_dir, *env_flags, "exec /bin/sh")
        tmux(
            "set-option", "-w", "-t", m_win, "automatic-rename", "off", ";",
            "set-option", "-w", "-t", m_win, "allow-rename", "off", ";",
            "set-option", "-p", "-t", p_ai, "@ide_role", "ai", ";",
            "set-option", "-p", "-t", p_ed, "@ide_role", "editor", ";",
            "set-option", "-p", "-t", p_tm, "@ide_role", "term", ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_session", name, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_ai_cli", ai_cli, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_socket", sock_path, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_initial_root", ws_dir, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_workdir", ws_dir, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_main_win", m_win, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_ai_pane", p_ai, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_editor_pane", p_ed, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_term_pane", p_tm, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_layout_mode", "3pane", ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_ai_parked", "0", ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_ed_parked", "0", ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_term_parked", "0", ";",
            "set-environment", "-t", f"={name}", "IDE_SESSION", name, ";",
            "select-pane", "-t", p_ai,
            check=True,
        )
        return {"dir": ws_dir, "win": m_win, "ai": p_ai, "ed": p_ed, "tm": p_tm}

    def sess_env(sess, pane=""):
        meta = tmux_out("display-message", "-p", "-t", f"={sess}:", "#{socket_path},#{pid},#{session_id}\t#{pane_id}")
        t_env, p_id = meta.split("\t")
        return {**base_env, "TMUX": t_env, "TMUX_PANE": pane or p_id, "IDE_SESSION": sess}

    # 2. Create 3 IDE workspaces with distinct agents, Git states, and home-shortened vs non-home paths
    ws_alpha = make_ws(
        "alpha-ws",
        ai_cmd="printf '\\033[36mALPHA_AI_VIEWPORT_LINE\\033[0m\\n'; sleep 300",
        ed_cmd="printf 'ALPHA_EDITOR_VIEWPORT_LINE\\n'; sleep 300",
        ai_cli="claude",
        git_branch="feat/switcher",
        git_dirty=True,
        in_home=True,
    )
    ws_beta = make_ws(
        "beta-ws",
        ai_cmd="printf 'BETA_AI_READY\\n'; sleep 300",
        ed_cmd="printf 'BETA_EDITOR_VISIBLE_LINE\\n'; sleep 300",
        ai_cli="codex",
        git_branch="main",
        git_dirty=False,
        in_home=True,
    )
    ws_gamma = make_ws(
        "gamma-ws",
        ai_cmd="printf 'GAMMA_SHELL_VIEW\\n'; sleep 300",
        ai_cli="agy",
        git_branch="",
        in_home=False,
    )

    assert wait_until(
        lambda: "ALPHA_AI_VIEWPORT_LINE" in tmux_out("capture-pane", "-p", "-t", ws_alpha["ai"])
        and "BETA_EDITOR_VISIBLE_LINE" in tmux_out("capture-pane", "-p", "-t", ws_beta["ed"])
        and "GAMMA_SHELL_VIEW" in tmux_out("capture-pane", "-p", "-t", ws_gamma["ai"]),
        timeout=4.0,
    ), "timed out waiting for workspace pane viewports"

    # Wait past gamma-ws's integer timestamp so send-keys bumps beta-ws #{window_activity} deterministically
    gamma_ts = max(
        (int(x) for x in tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{session_activity} #{window_activity}").split() if x.isdigit()),
        default=int(time.time()),
    )
    while int(time.time()) <= gamma_ts:
        time.sleep(0.05)
    tmux("send-keys", "-t", ws_beta["tm"], "echo activity_bump", "C-m", check=True)
    assert wait_until(
        lambda: "activity_bump" in tmux_out("capture-pane", "-p", "-t", ws_beta["tm"])
        and int(tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{window_activity}") or "0") > gamma_ts
    )

    plain_lines = run_cmd([ide_bin, "--list", "--plain"], env=sess_env("alpha-ws"), check=True).stdout.splitlines()
    assert plain_lines == ["alpha-ws", "beta-ws", "gamma-ws"], f"unexpected --list --plain order: {plain_lines}"
    assert "plain-non-ide" not in plain_lines and "ai-alpha-ws" not in plain_lines and "agy-beta-ws" not in plain_lines

    list_out = run_cmd([ide_bin, "--list"], env=sess_env("alpha-ws"), check=True).stdout
    list_lines = [ln for ln in list_out.splitlines() if ln.strip()]
    assert "SESSION" in list_lines[0] and "AGENT" in list_lines[0] and "STATE" in list_lines[0] and "BRANCH" in list_lines[0] and "WORKSPACE" in list_lines[0], f"bad header: {list_lines[0]}"
    assert list_lines[1].startswith("* alpha-ws") and "claude" in list_lines[1] and " - " in list_lines[1] and "feat/switcher*" in list_lines[1] and "~/projects/alpha-ws" in list_lines[1], f"bad row1: {list_lines[1]}"
    assert "beta-ws" in list_lines[2] and "codex" in list_lines[2] and " - " in list_lines[2] and "main" in list_lines[2] and "main*" not in list_lines[2] and "~/projects/beta-ws" in list_lines[2], f"bad row2: {list_lines[2]}"
    assert "gamma-ws" in list_lines[3] and "agy" in list_lines[3] and " - " in list_lines[3], f"bad row3: {list_lines[3]}"

    # 3. Live ANSI --session-preview & _ide_park_* exclusion
    prev_alpha = run_cmd([ide_bin, "--session-preview", "alpha-ws"], env={**sess_env("alpha-ws"), "NO_COLOR": ""}, check=True).stdout
    assert "alpha-ws" in prev_alpha and "claude" in prev_alpha and "State:" in prev_alpha and "feat/switcher (" in prev_alpha, f"bad alpha preview header: {prev_alpha}"
    assert "\x1b[36mALPHA_AI_VIEWPORT_LINE" in prev_alpha, f"expected live ANSI sequence from AI pane in preview: {prev_alpha!r}"

    # Park beta-ws AI pane into _ide_park_ai -> preview must skip _ide_park_ai and render visible Editor pane instead!
    run_cmd([ide_bin, "--toggle-ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_parked") == "1"
    prev_beta_parked = run_cmd([ide_bin, "--session-preview", "beta-ws"], env=sess_env("alpha-ws"), check=True).stdout
    assert "BETA_EDITOR_VISIBLE_LINE" in prev_beta_parked and "BETA_AI_READY" not in prev_beta_parked, f"parked _ide_park_ai leaked into preview: {prev_beta_parked}"

    # Non-git preview uses calm BASE01 (#586E75 -> 88;110;117), never Green (#859900 -> 133;153;0)
    prev_gamma = run_cmd([ide_bin, "--session-preview", "gamma-ws"], env={**sess_env("alpha-ws"), "NO_COLOR": ""}, check=True).stdout
    git_line_gamma = next((ln for ln in prev_gamma.splitlines() if "Git      :" in ln), "")
    assert "not a git repository" in git_line_gamma and "38;2;88;110;117mnot a git repository" in git_line_gamma, f"non-git line wrong color: {git_line_gamma!r}"
    prev_missing = run_cmd([ide_bin, "--session-preview", "no-such-ws"], env=sess_env("alpha-ws"), check=True).stdout
    assert "Session is no longer active." in prev_missing

    # 4. Attach real PTY client to alpha-ws & verify status_click() column accuracy on calm 3-state status bar
    def set_ctty(sfd):
        os.setsid()
        fcntl.ioctl(sfd, termios.TIOCSCTTY, 0)

    client_mfd, client_sfd = pty.openpty()
    fcntl.ioctl(client_sfd, termios.TIOCSWINSZ, struct.pack("HHHH", 48, 160, 0, 0))
    client_proc = subprocess.Popen(
        ["tmux", "attach-session", "-t", "=alpha-ws"],
        stdin=client_sfd,
        stdout=client_sfd,
        stderr=client_sfd,
        env={**base_env, "TMUX": "", "TMUX_PANE": ""},
        close_fds=True,
        preexec_fn=lambda sfd=client_sfd: set_ctty(sfd),
    )
    os.close(client_sfd)

    def drain_pty():
        while True:
            r, _, _ = select.select([client_mfd], [], [], 0)
            if not r:
                break
            try:
                if not os.read(client_mfd, 8192):
                    break
            except OSError:
                break

    client_name = wait_until(lambda: (drain_pty() or tmux_out("list-clients", "-t", "=alpha-ws", "-F", "#{client_name}").strip()))
    assert client_name, "failed to attach PTY tmux client to alpha-ws"

    run_cmd([ide_bin, "--focus-editor", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    sleft_raw = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:status-left}")
    wcur_raw = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:window-status-current-format}")
    strip_tags = lambda s: re.sub(r"#\[[^\]]*\]", "", s)
    sleft_plain = strip_tags(sleft_raw)
    wcur_plain = strip_tags(wcur_raw)
    ed_col = len(sleft_plain) + wcur_plain.index("Editor") + 2
    sh_col = len(sleft_plain) + wcur_plain.index("Shell") + 2

    run_cmd([ide_bin, "--status-click", str(sh_col), "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term"
    run_cmd([ide_bin, "--status-click", str(ed_col), "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["tm"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor"

    # 5. Interactive Workspace Switcher (ide -s / --sessions) with mock IDE_FZF_BIN (in-process + live display-popup)
    mock_fzf = os.path.join(root, "mock-fzf.py")
    with open(mock_fzf, "w", encoding="utf-8") as f:
        f.write(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            "lines = [l.rstrip('\\n') for l in sys.stdin if l.strip()]\n"
            "assert all('\\t' in l for l in lines), f'missing tab delimiter: {lines}'\n"
            "rc = int(os.environ.get('MOCK_FZF_EXIT', '0'))\n"
            "if rc != 0:\n"
            "    sys.exit(rc)\n"
            "target = os.environ.get('MOCK_FZF_TARGET', '')\n"
            "key = os.environ.get('MOCK_FZF_KEY', '')\n"
            "picked = next((l for l in lines if l.split('\\t', 1)[0] == target), lines[0])\n"
            "print(key)\n"
            "print(picked)\n"
        )
    os.chmod(mock_fzf, 0o755)

    # alt-s abort (exit 130) returns 0 cleanly without switching
    r_abort = run_cmd(
        [ide_bin, "--sessions", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_EXIT": "130", "IDE_CLIENT": client_name},
        check=False,
    )
    assert r_abort.returncode == 0
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws"

    # Enter (empty --expect key) switches session preserving target's focused pane
    run_cmd([ide_bin, "--focus-editor", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    run_cmd(
        [ide_bin, "-s", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "", "MOCK_FZF_TARGET": "gamma-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    drain_pty()
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "gamma-ws"
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{@ide_role}") == "editor"
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    drain_pty()

    # ctrl-e does NOT bounce when editor is already active
    run_cmd(
        [ide_bin, "-s", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "ctrl-e", "MOCK_FZF_TARGET": "alpha-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor"

    # ctrl-t unparks parked Shell and does NOT bounce when Shell is already active
    run_cmd([ide_bin, "--toggle-term", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_term_parked") == "1"
    run_cmd(
        [ide_bin, "--sessions", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "ctrl-t", "MOCK_FZF_TARGET": "alpha-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_term_parked") == "0"
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term"
    run_cmd(
        [ide_bin, "--sessions", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["tm"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "ctrl-t", "MOCK_FZF_TARGET": "alpha-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term"

    # Live display-popup path: switches attached PTY client to beta-ws and unparks its parked AI pane via ctrl-a!
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_parked") == "1"
    tmux("set-environment", "-g", "IDE_FZF_BIN", mock_fzf, check=True)
    tmux("set-environment", "-g", "MOCK_FZF_KEY", "ctrl-a", check=True)
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "beta-ws", check=True)
    run_cmd(
        [ide_bin, "--sessions", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["tm"]), "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "ctrl-a", "MOCK_FZF_TARGET": "beta-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    drain_pty()
    assert wait_until(lambda: (drain_pty() or tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "beta-ws")), "live display-popup --sessions did not switch client to beta-ws"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_parked") == "0"
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "ai"

    # 6. Context Dispatch (ide --send: --ref, L1==L2, empty no-op, after icd, external path, --text --no-focus, --stdin, live copy-mode-vi 'a', and untouched default tmux buffer)
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("set-buffer", "SACRED_DEFAULT_BUFFER", check=True)
    recv_root = os.path.join(root, "ai_recv_root.txt")
    tmux(
        "respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"],
        f"/bin/sh -c 'stty -echo -icanon min 1 time 0; exec cat > {recv_root}'",
        check=True,
    )
    time.sleep(0.1)
    run_cmd([ide_bin, "--focus-editor", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)

    # Empty payloads (--stdin empty, --text "", --ref "   ") return 0 WITHOUT switching focus away from Editor!
    run_cmd([ide_bin, "--send", "--stdin", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), input_text="", check=True)
    run_cmd([ide_bin, "--send", "--text", "", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    run_cmd([ide_bin, "--send", "--ref", "   ", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor", "empty --send payload spuriously switched focus away from Editor"

    mod_file = os.path.join(ws_alpha["dir"], "sub", "mod.py")
    run_cmd([ide_bin, "--send", "--ref", f"{mod_file}:10-20", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "ai"

    # L1 == L2 normalizes to #L15
    run_cmd([ide_bin, "--send", "--ref", f"{mod_file}:15-15", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)

    # --no-focus keeps Editor focused
    run_cmd([ide_bin, "--focus-editor", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    run_cmd([ide_bin, "--send", "--text", "[NOFOCUS]", "--no-focus", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor"

    # --stdin (all ide --send calls must leave default tmux buffer untouched)
    run_cmd([ide_bin, "--send", "--stdin", "--no-focus", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), input_text="[STDIN_OK]", check=True)
    assert tmux_out("show-buffer") == "SACRED_DEFAULT_BUFFER", f"default tmux buffer clobbered by ide --send: {tmux_out('show-buffer')!r}"
    assert "_ide_send_" not in tmux_out("list-buffers"), "temporary _ide_send_ buffer leaked"

    # Live Tmux copy-mode-vi 'a' binding from Shell pane
    tmux("send-keys", "-t", ws_alpha["tm"], "echo COPY_MODE_PAYLOAD", "C-m", check=True)
    assert wait_until(lambda: "\nCOPY_MODE_PAYLOAD" in "\n" + tmux_out("capture-pane", "-p", "-t", ws_alpha["tm"])), "missing COPY_MODE_PAYLOAD in Shell pane"
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["tm"], check=True)
    tmux("copy-mode", "-t", ws_alpha["tm"], check=True)
    drain_pty()
    tmux("send-keys", "-t", ws_alpha["tm"], "-X", "search-backward", "COPY_MODE_PAYLOAD", check=True)
    tmux("send-keys", "-t", ws_alpha["tm"], "-X", "begin-selection", check=True)
    tmux("send-keys", "-t", ws_alpha["tm"], "-X", "next-space-end", check=True)
    os.write(client_mfd, b"a")

    def root_recv_complete():
        drain_pty()
        if not os.path.isfile(recv_root):
            return False
        data = open(recv_root, encoding="utf-8", errors="replace").read()
        return "COPY_MODE_PAYLOAD" in data
    assert wait_until(root_recv_complete, timeout=3.0), f"copy-mode-vi 'a' payload never reached AI pane: {open(recv_root).read() if os.path.isfile(recv_root) else 'missing'}"
    got_root = open(recv_root, encoding="utf-8", errors="replace").read()
    clean_root = got_root.replace("\x1b[200~", "").replace("\x1b[201~", "")
    assert "@sub/mod.py#L10-L20 @sub/mod.py#L15 [NOFOCUS][STDIN_OK]COPY_MODE_PAYLOAD" == clean_root, f"unexpected AI root stream: {clean_root!r}"
    assert "_ide_send_" not in tmux_out("list-buffers"), "temporary _ide_send_ buffer leaked after copy-mode-vi"

    # Relative path resolution after icd into subdirectory (<ws>/sub) + outside-workspace fallback
    recv_sub = os.path.join(root, "ai_recv_sub.txt")
    sub_dir = os.path.join(ws_alpha["dir"], "sub")
    tmux("set-option", "-q", "-t", "=alpha-ws:", "@ide_workdir", sub_dir, check=True)
    tmux(
        "respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", sub_dir,
        f"/bin/sh -c 'stty -echo -icanon min 1 time 0; exec cat > {recv_sub}'",
        check=True,
    )
    time.sleep(0.1)
    readme_file = os.path.join(ws_alpha["dir"], "README.md")
    ext_file = os.path.join(root, "outside-ws.txt")
    with open(ext_file, "w", encoding="utf-8") as f:
        f.write("ext\n")
    ext_real = os.path.realpath(ext_file)
    run_cmd([ide_bin, "--send", "--ref", f"{mod_file}:7", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    run_cmd([ide_bin, "--send", "--ref", f"{readme_file}:1-3", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    run_cmd([ide_bin, "--send", "--ref", f"{ext_file}:4", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert wait_until(lambda: os.path.isfile(recv_sub) and ext_real in open(recv_sub, encoding="utf-8").read()), "subdir --ref payloads did not arrive"
    clean_sub = open(recv_sub, encoding="utf-8").read().replace("\x1b[200~", "").replace("\x1b[201~", "")
    assert clean_sub == f"@mod.py#L7 @../README.md#L1-L3 @{ext_real}#L4 ", f"unexpected AI subdir stream: {clean_sub!r}"

    # 7. Multi-client Alt+s isolation, non-IDE Alt+s, relative invocation, popup ctrl-x self-quit + reload highlight, --ref/--send edge cases, and dirty-buffer --quit guard
    popup_env_log = os.path.join(root, "popup_env.txt")
    with open(mock_fzf, "w", encoding="utf-8") as f:
        f.write(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            f"with open({popup_env_log!r}, 'w', encoding='utf-8') as out:\n"
            "    out.write(os.environ.get('IDE_CLIENT', '') + '\\t' + os.environ.get('FZF_DEFAULT_OPTS', '') + '\\t' + ' '.join(sys.argv[1:]))\n"
            "lines = [l.rstrip('\\n') for l in sys.stdin if l.strip()]\n"
            "target = os.environ.get('MOCK_FZF_TARGET', '')\n"
            "key = os.environ.get('MOCK_FZF_KEY', '')\n"
            "picked = next((l for l in lines if l.split('\\t', 1)[0] == target), lines[0])\n"
            "print(key)\n"
            "print(picked)\n"
        )
    os.chmod(mock_fzf, 0o755)

    # (7a) Attach second PTY client (client2) to alpha-ws while client1 stays on alpha-ws; press real Alt+s (\x1bs) on client2
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    drain_pty()
    client2_mfd, client2_sfd = pty.openpty()
    fcntl.ioctl(client2_sfd, termios.TIOCSWINSZ, struct.pack("HHHH", 48, 160, 0, 0))
    client2_proc = subprocess.Popen(
        ["tmux", "attach-session", "-t", "=alpha-ws"],
        stdin=client2_sfd,
        stdout=client2_sfd,
        stderr=client2_sfd,
        env={**base_env, "TMUX": "", "TMUX_PANE": ""},
        close_fds=True,
        preexec_fn=lambda sfd=client2_sfd: set_ctty(sfd),
    )
    os.close(client2_sfd)

    def drain_pty_both():
        drain_pty()
        while True:
            r, _, _ = select.select([client2_mfd], [], [], 0)
            if not r:
                break
            try:
                if not os.read(client2_mfd, 8192):
                    break
            except OSError:
                break

    def find_client2():
        drain_pty_both()
        cls = [c.strip() for c in tmux_out("list-clients", "-t", "=alpha-ws", "-F", "#{client_name}").splitlines() if c.strip() and c.strip() != client_name]
        return cls[0] if cls else ""

    client2_name = wait_until(find_client2)
    assert client2_name, "failed to attach second PTY client to alpha-ws"

    tmux("set-environment", "-g", "IDE_FZF_BIN", mock_fzf, check=True)
    tmux("set-environment", "-g", "MOCK_FZF_KEY", "", check=True)
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "beta-ws", check=True)
    if os.path.exists(popup_env_log):
        os.unlink(popup_env_log)
    os.write(client2_mfd, b"\x1bs")
    assert wait_until(lambda: (drain_pty_both() or tmux_out("display-message", "-p", "-t", client2_name, "#{session_name}") == "beta-ws")), "Alt+s on client2 did not switch client2 to beta-ws"
    time.sleep(0.2)
    drain_pty_both()
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws", "Alt+s on client2 wrongly switched client1!"
    recorded_env = open(popup_env_log, encoding="utf-8").read()
    rec_client, rec_default_fzf, _ = recorded_env.split("\t", 2)
    assert rec_client == client2_name and "#{" not in recorded_env, f"unexpanded format or wrong IDE_CLIENT in popup: {recorded_env!r}"
    assert "spinner:#859900" in rec_default_fzf and "prompt:#B58900" in rec_default_fzf, f"unexpected default FZF_DEFAULT_OPTS palette: {rec_default_fzf!r}"

    # Real Alt+s from non-IDE session (plain-non-ide) switches client2 cleanly into gamma-ws
    tmux("switch-client", "-c", client2_name, "-t", "=plain-non-ide", check=True)
    time.sleep(0.1)
    drain_pty_both()
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "gamma-ws", check=True)
    os.write(client2_mfd, b"\x1bs")
    assert wait_until(lambda: (drain_pty_both() or tmux_out("display-message", "-p", "-t", client2_name, "#{session_name}") == "gamma-ws")), "Alt+s on non-IDE session did not switch client2 to gamma-ws"
    time.sleep(0.2)
    drain_pty_both()
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws"

    # (7b) Relative invocation (./.local/bin/ide -s) + build_fzf_env single-quoted theme-env.sh overriding stale FZF_DEFAULT_OPTS
    hs_cfg_dir = os.path.join(thome, ".config", "home-settings")
    os.makedirs(hs_cfg_dir, exist_ok=True)
    theme_env_file = os.path.join(hs_cfg_dir, "theme-env.sh")
    with open(theme_env_file, "w", encoding="utf-8") as tf:
        tf.write("export FZF_DEFAULT_OPTS='--color=bg+:#313244,bg:#1E1E2E,spinner:#A6E3A1 --prompt='\\''WS> '\\'' --border=rounded'\n")
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "beta-ws", check=True)
    run_cmd(
        ["./.local/bin/ide", "-s", "gamma-ws"],
        env={
            **sess_env("gamma-ws", ws_gamma["ed"]),
            "FZF_DEFAULT_OPTS": "--color=bg+:#000000",
            "IDE_FZF_BIN": mock_fzf,
            "MOCK_FZF_KEY": "",
            "MOCK_FZF_TARGET": "beta-ws",
            "IDE_CLIENT": client2_name,
        },
        cwd=thome,
        check=True,
    )
    assert wait_until(lambda: (drain_pty_both() or tmux_out("display-message", "-p", "-t", client2_name, "#{session_name}") == "beta-ws")), "relative ./ide -s popup failed"
    _, rel_fzf_opts, rel_fzf_args = open(popup_env_log, encoding="utf-8").read().split("\t", 2)
    os.unlink(theme_env_file)
    assert "--color=bg+:#313244" in rel_fzf_opts and "--prompt='WS> '" in rel_fzf_opts and "#000000" not in rel_fzf_opts, f"build_fzf_env failed to load single-quoted/escaped theme-env.sh over stale FZF_DEFAULT_OPTS: {rel_fzf_opts!r}"
    assert os.path.abspath(ide_bin) in rel_fzf_args or os.path.realpath(ide_bin) in rel_fzf_args, f"relative path leaked into fzf args: {rel_fzf_args}"

    # Verify session_last_attached promotes recently visited gamma-ws above beta-ws
    beta_max_ts = max(
        (int(x) for x in tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{session_activity} #{session_last_attached} #{window_activity}").split() if x.isdigit()),
        default=int(time.time()),
    )
    while int(time.time()) <= beta_max_ts:
        time.sleep(0.05)
    tmux("switch-client", "-c", client2_name, "-t", "=gamma-ws", check=True)
    drain_pty_both()
    recency_after_switch = run_cmd([ide_bin, "--list", "--plain"], env=sess_env("alpha-ws"), check=True).stdout.splitlines()
    assert recency_after_switch == ["alpha-ws", "gamma-ws", "beta-ws"], f"session_last_attached did not promote gamma-ws: {recency_after_switch}"

    # (7c) Quitting the active session from inside the popup (IDE_IN_POPUP=1, ctrl-x) switches attached client to the most recently active surviving IDE session, and --sessions-lines re-highlights the new session
    ws_killme = make_ws("killme-ws", ai_cmd="sleep 300")
    tmux("switch-client", "-c", client2_name, "-t", "=killme-ws", check=True)
    drain_pty_both()
    run_cmd([ide_bin, "--quit", "killme-ws"], env={**sess_env("killme-ws", ws_killme["ed"]), "IDE_IN_POPUP": "1", "IDE_CLIENT": client2_name}, check=True)
    drain_pty_both()
    surviving_sess = tmux_out("display-message", "-p", "-t", client2_name, "#{session_name}")
    assert surviving_sess in ("alpha-ws", "beta-ws", "gamma-ws"), f"popup self-quit switched to unexpected session: {surviving_sess!r}"
    reloaded_rows = run_cmd([ide_bin, "--sessions-lines", "killme-ws"], env={**base_env, "IDE_IN_POPUP": "1", "IDE_CLIENT": client2_name}, check=True).stdout.splitlines()
    assert reloaded_rows and reloaded_rows[0].split("\t", 1)[0] == surviving_sess and "▸" in reloaded_rows[0], f"reload after ctrl-x did not highlight new client session {surviving_sess}: {reloaded_rows}"

    # (7d) Relative --ref from outside workspace CWD, '#' in filename, reversed flag order (--ref ... --send), and '--' leading-dash text
    tmux("set-option", "-q", "-t", "=alpha-ws:", "@ide_workdir", ws_alpha["dir"], check=True)
    hash_file = os.path.join(ws_alpha["dir"], "sub", "issue#12")
    with open(hash_file, "w", encoding="utf-8") as f:
        f.write("tracked\n")
    recv_edge = os.path.join(root, "ai_recv_edge.txt")
    tmux(
        "respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"],
        f"/bin/sh -c 'stty -echo -icanon min 1 time 0; exec cat > {recv_edge}'",
        check=True,
    )
    time.sleep(0.1)
    run_cmd([ide_bin, "--ref", "sub/mod.py:4-4", "--send", "--no-focus", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), cwd=root, check=True)
    run_cmd([ide_bin, "--send", "--ref", "sub/issue#12", "--no-focus", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), cwd=root, check=True)
    run_cmd([ide_bin, "--send", "--no-focus", "--text", "- leading-dash ", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), cwd=root, check=True)
    run_cmd([ide_bin, "--send", "--no-focus", "--", "--literal-end", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), cwd=root, check=True)
    assert wait_until(lambda: os.path.isfile(recv_edge) and "--literal-end" in open(recv_edge, encoding="utf-8").read()), "edge --send payloads did not arrive"
    clean_edge = open(recv_edge, encoding="utf-8").read().replace("\x1b[200~", "").replace("\x1b[201~", "")
    assert clean_edge == "@sub/mod.py#L4 @sub/issue#12 - leading-dash --literal-end", f"unexpected edge --send stream: {clean_edge!r}"

    # (7e) ide --quit refuses to close workspace when Neovim server has unsaved changes; --quit --force closes it
    if shutil.which("nvim"):
        ws_dirty = make_ws("dirty-ws", ai_cmd="sleep 300")
        dirty_sock = tmux_out("show-options", "-qv", "-t", "=dirty-ws:", "@ide_socket")
        dirty_file = os.path.join(ws_dirty["dir"], "unsaved.txt")
        tmux(
            "respawn-pane", "-k", "-t", ws_dirty["ed"], "-c", ws_dirty["dir"],
            f"nvim --headless -u NONE -i NONE --listen {shlex.quote(dirty_sock)} -c {shlex.quote('edit ' + dirty_file)} -c \"call setline(1, 'dirty')\"",
            check=True,
        )
        assert wait_until(lambda: os.path.exists(dirty_sock)), "dirty-ws nvim socket did not appear"
        time.sleep(0.15)
        r_dirty_quit = run_cmd([ide_bin, "--quit", "dirty-ws"], env={**base_env, "TMUX": ""}, check=False)
        assert r_dirty_quit.returncode != 0, f"expected ide --quit to refuse dirty buffer, got {r_dirty_quit}"
        assert tmux("has-session", "-t", "=dirty-ws", check=False).returncode == 0, "dirty-ws was killed despite unsaved buffer!"
        run_cmd([ide_bin, "--quit", "--force", "dirty-ws"], env={**base_env, "TMUX": ""}, check=True)
        assert tmux("has-session", "-t", "=dirty-ws", check=False).returncode != 0, "dirty-ws survived --quit --force"

    # 8. Deterministic Hook-Only AI Lifecycle State, Zero Heuristic Invention, FIFO --next-attention, Parked AI Preservation, Stale-Hook SHELL Guard, and Top-Bar Width Invariance
    ide_src = open(ide_bin, encoding="utf-8").read()
    for banned_heuristic in ("inspect_fleet_procs", "inspect_ai_viewport", "alert-bell", "--on-bell"):
        assert banned_heuristic not in ide_src, f"heuristic remnant {banned_heuristic!r} found in bin/ide"

    # Detach client2 so client_name is the sole attached viewer on alpha-ws Editor pane
    tmux("detach-client", "-t", client2_name, check=False)
    drain_pty_both()
    tmux("respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"], "/bin/sh -c 'sleep 300; :'", check=True)
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    tmux("select-pane", "-t", ws_gamma["ed"], check=True)
    drain_pty()

    # (8a) Prompt-like text + terminal bell (\a) in gamma-ws AI pane MUST NOT invent WORKING or ATTN without hooks!
    tmux(
        "respawn-pane", "-k", "-t", ws_gamma["ai"], "-c", ws_gamma["dir"],
        "/bin/sh -c 'printf \"Allow tool execution? [Y/n] \\a\\n\"; sleep 300; :'",
        check=True,
    )
    assert wait_until(lambda: "Allow tool execution" in tmux_out("capture-pane", "-p", "-t", ws_gamma["ai"]))
    run_cmd([ide_bin, "--refresh-attn"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") in ("", "0")
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""
    assert tmux_out("show-options", "-gqv", "@ide_fleet_count") == "3"
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "0"

    # (8b) Unfocused @ide_tab_ai character width invariance across all 4 states:
    # neutral -> running (Cyan) -> unacknowledged done (Green) -> approval (Orange), both visible and parked!
    wcur_neutral = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "--agent-state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wcur_running = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "1"
    sright_active = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:status-right}")
    assert "range=user|fleet]#[fg=#839496,bg=#073642,nobold] 3 · #[fg=#2AA198,bg=#073642,nobold]1 active#[fg=#839496,bg=#073642,nobold] (Alt+s)" in sright_active, f"bad active fleet pill: {sright_active!r}"

    run_cmd([ide_bin, "--agent-state", "done", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "done"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1"
    wcur_done = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")

    run_cmd([ide_bin, "--agent-state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wcur_approval = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    assert strip_tags(wcur_neutral) == strip_tags(wcur_running) == strip_tags(wcur_done) == strip_tags(wcur_approval), (
        f"@ide_tab_ai shifted character width! neutral={strip_tags(wcur_neutral)!r} running={strip_tags(wcur_running)!r} done={strip_tags(wcur_done)!r} approval={strip_tags(wcur_approval)!r}"
    )
    assert "fg=#839496,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_neutral, f"expected Base0 neutral tint: {wcur_neutral!r}"
    assert "fg=#2AA198,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_running, f"expected Cyan running tint: {wcur_running!r}"
    assert "fg=#859900,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_done, f"expected Green unacknowledged done tint: {wcur_done!r}"
    assert "fg=#CB4B16,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_approval, f"expected Orange approval tint: {wcur_approval!r}"

    # Verify parked [Alt+a] @ide_tab_ai across all 4 states as well (zero character width shift)
    run_cmd([ide_bin, "--toggle-ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)
    wpark_approval = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "--agent-state", "idle", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wpark_neutral = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "--agent-state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wpark_running = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "--agent-state", "done", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wpark_done = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    assert strip_tags(wpark_neutral) == strip_tags(wpark_running) == strip_tags(wpark_done) == strip_tags(wpark_approval), (
        f"parked @ide_tab_ai shifted character width! neutral={strip_tags(wpark_neutral)!r} running={strip_tags(wpark_running)!r} done={strip_tags(wpark_done)!r} approval={strip_tags(wpark_approval)!r}"
    )
    assert "fg=#586E75,bg=#073642,nobold]󰚩 codex [Alt+a]" in wpark_neutral, f"expected Base01 parked neutral: {wpark_neutral!r}"
    assert "fg=#2AA198,bg=#073642,nobold]󰚩 codex [Alt+a]" in wpark_running, f"expected Cyan parked running: {wpark_running!r}"
    assert "fg=#859900,bg=#073642,nobold]󰚩 codex [Alt+a]" in wpark_done, f"expected Green parked done: {wpark_done!r}"
    assert "fg=#CB4B16,bg=#073642,nobold]󰚩 codex [Alt+a]" in wpark_approval, f"expected Orange parked approval: {wpark_approval!r}"
    run_cmd([ide_bin, "--toggle-ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "--agent-state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)

    # Verify status_click still clicks Editor & Shell accurately when @ide_tab_ai is tinted!
    run_cmd([ide_bin, "--status-click", str(sh_col), "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term"
    run_cmd([ide_bin, "--status-click", str(ed_col), "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["tm"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor"

    # (8c) Foreground done vs Background done + Mixed FIFO queue (beta-ws approval, gamma-ws background done)
    # Foreground done: when alpha-ws is attached and its AI pane IS focused, done sets @ide_ai_attn=0 (not queued)
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    drain_pty()
    run_cmd([ide_bin, "--agent-state", "done", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "done"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "0", "foreground done while viewing AI pane must not set @ide_ai_attn=1!"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn_ts") == ""
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws", "foreground done must not enter @ide_attn_summary!"
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    drain_pty()
    wcur_alpha_fg_done = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:window-status-current-format}")
    assert "fg=#839496,bg=#073642,nobold]󰚩 claude (Alt+a)" in wcur_alpha_fg_done, f"acknowledged foreground done must stay neutral Base0: {wcur_alpha_fg_done!r}"
    list_fg_done = run_cmd([ide_bin, "--list"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True).stdout
    assert any("alpha-ws" in ln and "DONE" in ln for ln in list_fg_done.splitlines()), f"expected DONE for alpha-ws: {list_fg_done}"
    run_cmd([ide_bin, "--agent-state", "idle", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    list_idle = run_cmd([ide_bin, "--list"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True).stdout
    assert any("alpha-ws" in ln and "IDLE" in ln for ln in list_idle.splitlines()), f"expected IDLE for alpha-ws: {list_idle}"

    # Background done: gamma-ws finishes turn while detached -> @ide_ai_attn=1, @ide_attn_summary == "beta-ws +1", FIFO order
    time.sleep(0.03)
    run_cmd([ide_bin, "--agent-state", "done", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_state") == "done"
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws +1"
    sright_attn = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:status-right}")
    assert "range=user|attn]#[fg=#CB4B16,bg=#073642,nobold]󰂚 beta-ws +1 " in sright_attn, f"missing urgent attn pill: {sright_attn!r}"

    fifo_plain = run_cmd([ide_bin, "--list", "--plain"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True).stdout.splitlines()
    assert fifo_plain == ["beta-ws", "gamma-ws", "alpha-ws"], f"mixed ATTN + background DONE FIFO sort failed: {fifo_plain}"

    list_mixed_plain = run_cmd([ide_bin, "--list"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True).stdout.splitlines()
    assert any(ln.lstrip().startswith("! ") and "beta-ws" in ln and "ATTN" in ln for ln in list_mixed_plain), f"missing ! ATTN row: {list_mixed_plain}"
    assert any(ln.lstrip().startswith("! ") and "gamma-ws" in ln and "DONE" in ln for ln in list_mixed_plain), f"missing ! DONE row: {list_mixed_plain}"

    color_env = {k: v for k, v in sess_env("alpha-ws", ws_alpha["ed"]).items() if k != "NO_COLOR"}
    slines_ansi = run_cmd([ide_bin, "--sessions-lines", "alpha-ws"], env=color_env, check=True).stdout.splitlines()
    beta_ansi = next(ln for ln in slines_ansi if ln.startswith("beta-ws\t"))
    gamma_ansi = next(ln for ln in slines_ansi if ln.startswith("gamma-ws\t"))
    assert "\x1b[38;2;203;75;22m󰂚\x1b[0m" in beta_ansi and "\x1b[38;2;203;75;22mbeta-ws" in beta_ansi, f"expected Orange bell & session on ATTN row: {beta_ansi!r}"
    assert "\x1b[38;2;133;153;0m󰂚\x1b[0m" in gamma_ansi and "\x1b[38;2;133;153;0mgamma-ws" in gamma_ansi and "\x1b[38;2;133;153;0mDONE" in gamma_ansi, f"expected Green bell, session & DONE on unacknowledged DONE row: {gamma_ansi!r}"
    l_mfd, l_sfd = pty.openpty()
    try:
        l_proc = subprocess.Popen([ide_bin, "--list"], stdin=subprocess.DEVNULL, stdout=l_sfd, stderr=l_sfd, env=color_env)
        os.close(l_sfd)
        l_chunks = []
        while True:
            try:
                chunk = os.read(l_mfd, 16384)
                if not chunk:
                    break
                l_chunks.append(chunk)
            except OSError:
                break
        assert l_proc.wait(timeout=5.0) == 0
    finally:
        try:
            os.close(l_mfd)
        except OSError:
            pass
    list_mixed_ansi = b"".join(l_chunks).decode("utf-8", "replace").splitlines()
    beta_list_ansi = next(ln for ln in list_mixed_ansi if "beta-ws" in ln)
    gamma_list_ansi = next(ln for ln in list_mixed_ansi if "gamma-ws" in ln)
    assert "\x1b[38;2;203;75;22m󰂚\x1b[0m" in beta_list_ansi and "\x1b[38;2;203;75;22mbeta-ws" in beta_list_ansi, f"expected Orange bell & session in TTY --list: {beta_list_ansi!r}"
    assert "\x1b[38;2;133;153;0m󰂚\x1b[0m" in gamma_list_ansi and "\x1b[38;2;133;153;0mgamma-ws" in gamma_list_ansi, f"expected Green bell & session in TTY --list: {gamma_list_ansi!r}"

    # (8d) ide --next-attention jumps to oldest needs_attn session (beta-ws approval), focuses AI pane, auto-acknowledges, and updates @ide_attn_summary -> "gamma-ws"
    run_cmd([ide_bin, "--next-attention", "alpha-ws"], env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_CLIENT": client_name}, check=True)
    drain_pty()
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "beta-ws"
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "ai"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") in ("", "0")
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "gamma-ws"

    # Real Alt+Shift+S (\x1bS) on attached PTY jumps to next needs_attn session (gamma-ws background done), transitions done -> idle, and clears @ide_attn_summary!
    os.write(client_mfd, b"\x1bS")
    assert wait_until(lambda: (drain_pty() or tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "gamma-ws")), "Alt+Shift+S did not jump to background-done gamma-ws"
    assert wait_until(lambda: (drain_pty() or tmux_out("show-options", "-gqv", "@ide_attn_summary") == "")), "Alt+Shift+S focus hook did not clear @ide_attn_summary"
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{@ide_role}") == "ai"
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_state") == "idle"
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") in ("", "0")

    # Attached session with Editor focused receiving --agent-state done ALSO queues attention & jumps to AI pane!
    tmux("select-pane", "-t", ws_gamma["ed"], check=True)
    drain_pty()
    run_cmd([ide_bin, "--agent-state", "done", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "gamma-ws"
    run_cmd([ide_bin, "--next-attention", "gamma-ws"], env={**sess_env("gamma-ws", ws_gamma["ed"]), "IDE_CLIENT": client_name}, check=True)
    drain_pty()
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{@ide_role}") == "ai"
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") in ("", "0")
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""

    # Calling --next-attention when queue is empty is a safe exit-0 no-op
    run_cmd([ide_bin, "--next-attention", "gamma-ws"], env={**sess_env("gamma-ws", ws_gamma["ai"]), "IDE_CLIENT": client_name}, check=True)
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "gamma-ws"

    # Calling --next-attention outside tmux with TTY stdin but redirected stdout (IDE_NO_ATTACH=0) exits 0 without 'open terminal failed'
    run_cmd([ide_bin, "--agent-state", "done", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1"
    na_mfd, na_sfd = pty.openpty()
    try:
        na_env = {**base_env, "TMUX": "", "TMUX_PANE": "", "IDE_CLIENT": "", "IDE_NO_ATTACH": "0"}
        na_res = subprocess.run([ide_bin, "--next-attention"], stdin=na_sfd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=na_env, text=True, check=False)
        assert na_res.returncode == 0, f"outside-tmux --next-attention with redirected stdout failed: {na_res.stderr!r}"
    finally:
        os.close(na_sfd)
        os.close(na_mfd)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") in ("", "0")

    # (8e) Parked AI pane (_ide_park_ai) preserves live WORKING state
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "--agent-state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    run_cmd([ide_bin, "--toggle-ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_parked") == "1"
    list_parked_run = run_cmd([ide_bin, "--list"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True).stdout
    assert any("beta-ws" in ln and "WORKING" in ln for ln in list_parked_run.splitlines()), f"parked running AI lost WORKING state: {list_parked_run}"
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "1"
    run_cmd([ide_bin, "--toggle-ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)

    # (8f) Stale-hook guard: if AI CLI exits back to bare shell (0 child processes), report SHELL and clear stale @ide_ai_state/@ide_ai_attn!
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "--agent-state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws"
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec /bin/sh", check=True)
    assert wait_until(
        lambda: any("beta-ws" in ln and "SHELL" in ln for ln in run_cmd([ide_bin, "--list"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True).stdout.splitlines()),
        timeout=3.0,
    ), "bare-shell AI pane did not transition to SHELL"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == ""
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") in ("", "0")
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "0"

    # (8g) Exec-launched childless foreground AI process (0 child PIDs, non-shell pane_current_command) retains hook state!
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec sleep 300", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sleep")
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "--agent-state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1", "exec-launched childless AI lost approval state!"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws", "exec-launched childless AI wiped from @ide_attn_summary!"

    # (8h) Real SGR mouse clicks on top status bar: Help (Alt+?) popup, #[range=user|attn], and #[range=user|fleet]
    import unicodedata as _ud
    _ansi_strip_re = re.compile(r"\x1b(?:\[[0-9;?]*[A-Za-z~]|\][^\x07\x1b]*(?:\x07|\x1b\\)|[()][A-Z0-9])")

    def _cell_w(text):
        total = 0
        for ch in text:
            cp = ord(ch)
            if 0xE000 <= cp <= 0xF8FF or 0xF0000 <= cp <= 0x10FFFF:
                total += 1
            elif cp >= 0x10000 or _ud.east_asian_width(ch) in ("W", "F"):
                total += 2
            elif not _ud.combining(ch):
                total += 1
        return total

    def _read_pty_chunk(sec=0.5):
        end_t = time.monotonic() + sec
        buf = []
        while time.monotonic() < end_t:
            rdy, _, _ = select.select([client_mfd], [], [], max(0.01, end_t - time.monotonic()))
            if rdy:
                try:
                    buf.append(os.read(client_mfd, 65536))
                except OSError:
                    break
        return b"".join(buf)

    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("set-environment", "-t", "=alpha-ws", "SSH_CONNECTION", "10.0.0.1 12345 10.0.0.2 22", check=True)
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _read_pty_chunk(0.35)

    c_width = int(tmux_out("display-message", "-p", "-t", client_name, "#{client_width}"))
    sr_raw = subprocess.run(
        ["tmux", "-u", "display-message", "-t", "=alpha-ws:", "-p", "#{T:status-right}"],
        env=base_env, text=True, capture_output=True, check=True,
    ).stdout.rstrip("\n")
    sr_vis = re.sub(r"#\[[^\]]*\]", "", sr_raw)

    def _sr_col(label):
        pos = sr_vis.index(label)
        return c_width - _cell_w(sr_vis[pos:]) + 1

    # Click 0: Non-interactive SSH host segment ("󰣀") in status-right must NOT open the Help popup
    ssh_x = _sr_col("󰣀")
    os.write(client_mfd, f"\x1b[<0;{ssh_x};1M\x1b[<0;{ssh_x};1m".encode())
    ssh_out = _ansi_strip_re.sub("", _read_pty_chunk(0.5).decode("utf-8", "replace"))
    assert "IDE Workspace & Editor Keybindings" not in ssh_out, f"SSH segment click unexpectedly opened Help popup: {ssh_out[-250:]!r}"
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws"

    # Click 1: Help (Alt+?) (#[range=user|help]) while SSH, attn, and fleet segments are rendered to its left
    help_x = _sr_col("Help")
    os.write(client_mfd, f"\x1b[<0;{help_x};1M\x1b[<0;{help_x};1m".encode())
    help_out = _ansi_strip_re.sub("", _read_pty_chunk(0.8).decode("utf-8", "replace"))
    assert "IDE Workspace & Editor Keybindings" in help_out, f"Help SGR click failed: {help_out[-250:]!r}"
    os.write(client_mfd, b"q")
    _read_pty_chunk(0.4)
    tmux("set-environment", "-u", "-t", "=alpha-ws", "SSH_CONNECTION", check=True)

    # Click 2: Urgent #[range=user|attn] pill ("beta-ws") jumps client to beta-ws and auto-acks
    attn_x = _sr_col("beta-ws")
    os.write(client_mfd, f"\x1b[<0;{attn_x};1M\x1b[<0;{attn_x};1m".encode())
    assert wait_until(lambda: (_read_pty_chunk(0.08) or tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "beta-ws")), "attn pill SGR click did not jump to beta-ws"
    assert wait_until(lambda: (_read_pty_chunk(0.05) or tmux_out("show-options", "-gqv", "@ide_attn_summary") == "")), "attn pill SGR click did not clear @ide_attn_summary"

    # Click 3: #[range=user|fleet] pill ("(Alt+s)") opens --sessions popup and switches back to alpha-ws
    tmux("set-environment", "-g", "MOCK_FZF_KEY", "", check=True)
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "alpha-ws", check=True)
    _read_pty_chunk(0.35)
    sr_raw2 = subprocess.run(
        ["tmux", "-u", "display-message", "-t", "=beta-ws:", "-p", "#{T:status-right}"],
        env=base_env, text=True, capture_output=True, check=True,
    ).stdout.rstrip("\n")
    sr_vis2 = re.sub(r"#\[[^\]]*\]", "", sr_raw2)
    fleet_x = c_width - _cell_w(sr_vis2[sr_vis2.index("(Alt+s)"):]) + 1
    os.write(client_mfd, f"\x1b[<0;{fleet_x};1M\x1b[<0;{fleet_x};1m".encode())
    assert wait_until(lambda: (_read_pty_chunk(0.1) or tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws"), timeout=4.0), "fleet pill SGR click did not switch to alpha-ws"
    _read_pty_chunk(0.2)

    # (8i) Zero-fork pure-C if-shell -F guard on pane-focus-in & client-session-changed:
    # Switching between Editor and Shell (or into idle/empty AI panes or non-IDE sessions) must NEVER
    # invoke ~/.local/bin/ide --ack-ai, whereas focusing AI when @ide_ai_attn == 1 (approval or
    # background done) immediately invokes --ack-ai --hook and clears @ide_ai_attn and @ide_attn_summary.
    for s_clean in ("alpha-ws", "beta-ws", "gamma-ws"):
        run_cmd([ide_bin, "--agent-state", "idle", s_clean], env=sess_env(s_clean), check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.25)

    real_ide_path = os.path.realpath(ide_bin)
    ack_hook_log = os.path.join(root, "ack_hook.log")
    open(ack_hook_log, "w", encoding="utf-8").close()
    os.unlink(ide_bin)
    with open(ide_bin, "w", encoding="utf-8") as wf:
        wf.write(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            f"log_p = {ack_hook_log!r}\n"
            f"real_p = {real_ide_path!r}\n"
            "if '--ack-ai' in sys.argv[1:]:\n"
            "    with open(log_p, 'a', encoding='utf-8') as lf:\n"
            "        lf.write(' '.join(sys.argv[1:]) + '\\n')\n"
            "os.execv(real_p, [real_p, *sys.argv[1:]])\n"
        )
    os.chmod(ide_bin, 0o755)

    # Routine focus switches while @ide_ai_state is idle or empty:
    tmux("select-pane", "-t", ws_alpha["tm"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    os.write(client_mfd, b"\x1bt")
    assert wait_until(lambda: (_read_pty_chunk(0.05) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term")), "Alt+t did not focus Shell"
    os.write(client_mfd, b"\x1bk")
    assert wait_until(lambda: (_read_pty_chunk(0.05) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor")), "Alt+k from Shell did not focus Editor"
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("set-option", "-q", "-u", "-t", "=alpha-ws:", "@ide_ai_state", check=True)
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("switch-client", "-c", client_name, "-t", "=plain-non-ide", check=True)
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)

    # Even while @ide_ai_attn == 1 (background done), switching between Editor and Shell must NOT invoke --ack-ai!
    run_cmd([ide_bin, "--agent-state", "done", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "alpha-ws"
    tmux("select-pane", "-t", ws_alpha["tm"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.3)
    logged_false = open(ack_hook_log, encoding="utf-8").read()
    assert logged_false == "", f"if-shell -F guard leaked --ack-ai calls during non-AI/idle switches: {logged_false!r}"

    # Focusing AI pane while @ide_ai_attn == 1 (background done) immediately triggers --ack-ai --hook and clears!
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    assert wait_until(lambda: (_read_pty_chunk(0.05) or "--ack-ai --hook alpha-ws" in open(ack_hook_log, encoding="utf-8").read())), "pane-focus-in on background-done AI did not invoke --ack-ai --hook"
    assert wait_until(lambda: (_read_pty_chunk(0.05) or (tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") in ("", "0") and tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""))), "pane-focus-in did not clear @ide_ai_attn/@ide_attn_summary on done"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "idle"

    # Focusing AI pane while @ide_ai_attn == 1 (approval) immediately triggers --ack-ai --hook and clears!
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.15)
    open(ack_hook_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "--agent-state", "approval", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "alpha-ws"
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    assert wait_until(lambda: (_read_pty_chunk(0.05) or "--ack-ai --hook alpha-ws" in open(ack_hook_log, encoding="utf-8").read())), "pane-focus-in on approval AI did not invoke --ack-ai --hook"
    assert wait_until(lambda: (_read_pty_chunk(0.05) or (tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") in ("", "0") and tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""))), "pane-focus-in did not clear @ide_ai_attn/@ide_attn_summary on approval"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "idle"

    # Switching client to a session whose AI pane is active with @ide_ai_attn == 1 triggers client-session-changed --ack-ai --hook!
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    _read_pty_chunk(0.15)
    open(ack_hook_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "--agent-state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws"
    tmux("switch-client", "-c", client_name, "-t", "=beta-ws", check=True)
    assert wait_until(lambda: (_read_pty_chunk(0.05) or "--ack-ai --hook beta-ws" in open(ack_hook_log, encoding="utf-8").read())), "client-session-changed did not invoke --ack-ai --hook beta-ws"
    assert wait_until(lambda: (_read_pty_chunk(0.05) or (tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") in ("", "0") and tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""))), "client-session-changed did not clear @ide_ai_attn/@ide_attn_summary"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "idle"

    # Crashed 'running' AI CLI (exited to bare /bin/sh without Stop hook):
    # 1) Focusing AI from Editor triggers pane-focus-in running guard (--ack-ai --hook) and clears @ide_ai_state & @ide_fleet_active!
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    _read_pty_chunk(0.15)
    open(ack_hook_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "--agent-state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "1"
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec /bin/sh", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sh")
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    assert wait_until(lambda: (_read_pty_chunk(0.05) or "--ack-ai --hook beta-ws" in open(ack_hook_log, encoding="utf-8").read())), "pane-focus-in on crashed running AI did not invoke --ack-ai --hook"
    assert wait_until(lambda: (_read_pty_chunk(0.05) or (tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "" and tmux_out("show-options", "-gqv", "@ide_fleet_active") == "0"))), "pane-focus-in did not clear stale running state after AI exit"

    # 2) If AI crashes while running AND user is already in AI pane, bouncing out via Alt+a (--toggle) clears stale running & @ide_fleet_active!
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec sleep 300", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sleep")
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    run_cmd([ide_bin, "--agent-state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "1"
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec /bin/sh", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sh")
    run_cmd([ide_bin, "--toggle", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "editor"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "", "bouncing out of crashed running AI via --toggle left stale @ide_ai_state!"
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "0", "bouncing out of crashed running AI via --toggle left stale @ide_fleet_active!"

    print("ALL_FLEET_OK")
finally:
    for mfd in (client2_mfd, client_mfd):
        if mfd is not None:
            try:
                os.close(mfd)
            except OSError:
                pass
    for cproc in (client2_proc, client_proc):
        if cproc is not None:
            try:
                cproc.terminate()
                cproc.wait(timeout=2.0)
            except Exception:
                try:
                    cproc.kill()
                except Exception:
                    pass
    try:
        subprocess.run(
            ["tmux", "kill-server"],
            env={**base_env, "TMUX": "", "TMUX_PANE": ""} if base_env else None,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except Exception:
        pass
    shutil.rmtree(root, ignore_errors=True)
PY
    )" || true
    if grep -Fq "ALL_FLEET_OK" <<< "$FLEET_TEST_OUT"; then
        pass "bin/ide multi-session workspace switcher (--list [--plain], -s/--sessions popup & fzf ctrl-a/e/t/ctrl-x/alt-s, --session-preview), deterministic hook-only AI lifecycle (--agent-state, FIFO --next-attention, Alt+Shift+S, stale-hook SHELL guard, parked AI preservation, zero-shift top-bar tinting), and context dispatch (--send)"
    else
        fail "bin/ide multi-session workspace switcher & lifecycle suite" "Suite failed: $FLEET_TEST_OUT"
    fi
fi

test_summary
