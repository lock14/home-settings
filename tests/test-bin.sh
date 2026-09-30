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
echo -e "\n[1/4] Checking module syntax..."
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
echo -e "\n[2/4] Testing binaries symlinking into ~/.local/bin..."
TEMP_HOME=$(mktemp -d)
TMUX_TEST_TMPDIR=""
MOUSE_TMPDIR=""
# Tear down the isolated tmux servers (by their explicit sockets, never via $TMUX) even when a check aborts
# or the run is interrupted, so no test server or Editor outlives the suite
cleanup_test_bin() {
    local dir
    for dir in "$TMUX_TEST_TMPDIR" "$MOUSE_TMPDIR"; do
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
echo -e "\n[3/4] Testing Debian tool compatibility shims..."
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
echo -e "\n[4/4] Testing binaries uninstallation..."
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
echo -e "\n[5/5] Testing bin/sum edge cases (process substitution & padded columns)..."
SUM_PROC_OUT="$("$SCRIPT_DIR/bin/sum" -k 5 <(printf "r1 c2 c3 c4 10\nr2 c2 c3 c4 25\n"))"
assert_eq "$SUM_PROC_OUT" "35" "bin/sum supports process substitution (<(cmd)) with column selection (-k 5)"

SUM_PAD_OUT="$(printf "alpha | 12.5 \r\nbeta | 27.5 \r\n" | "$SCRIPT_DIR/bin/sum" -d '|' -k 2)"
assert_eq "$SUM_PAD_OUT" "40" "bin/sum trims whitespace and CR around delimited columns (-d '|' -k 2)"

COMMA_FILE="$TEMP_HOME/data,1.txt"
printf "15\n25\n" > "$COMMA_FILE"
SUM_COMMA_FILE_OUT="$("$SCRIPT_DIR/bin/sum" "$COMMA_FILE")"
assert_eq "$SUM_COMMA_FILE_OUT" "40" "bin/sum reads files whose paths contain commas"

# Test 6: bin/ide CLI validation & headless tmux session orchestration
echo -e "\n[6/6] Testing bin/ide workspace launcher..."
IDE_HELP="$("$SCRIPT_DIR/bin/ide" --help)"
if grep -q -- '--3pane' <<< "$IDE_HELP" && \
   grep -q -- '--kill' <<< "$IDE_HELP" && \
   grep -q -- '--toggle-editor' <<< "$IDE_HELP" && \
   grep -q -- '--toggle-term' <<< "$IDE_HELP" && \
   grep -q -- '--toggle-ai' <<< "$IDE_HELP" && \
   grep -q -- '--swap' <<< "$IDE_HELP" && \
   grep -q -- '--keys' <<< "$IDE_HELP"; then
    pass "bin/ide --help displays usage for 2-pane, --3pane, --toggle-editor/term/ai, --swap, --keys, --kill, and --list"
else
    fail "bin/ide --help" "Expected --3pane, --toggle-editor/term/ai, --swap, --keys, and --kill in bin/ide --help output"
fi

IDE_KEYS_OUT="$("$SCRIPT_DIR/bin/ide" --keys)"
if grep -Fq "IDE Workspace & Editor Keybindings" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Alt+h / j / k / l" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Alt+Shift+E" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Alt+Shift+T" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "mini.files" <<< "$IDE_KEYS_OUT" && \
   grep -Fq "Alt+? / Prefix+?" <<< "$IDE_KEYS_OUT"; then
    pass "bin/ide --keys renders the Solarized Dark 2-column keybinding cheatsheet (including focus, swap, resize, mini.files, clipboard, and quit shortcuts)"
else
    fail "bin/ide --keys" "Missing expected keybinding sections in bin/ide --keys output"
fi

if "$SCRIPT_DIR/bin/ide" --unknown-flag >/dev/null 2>&1; then
    fail "bin/ide invalid flag" "Expected non-zero exit status on unknown flag"
else
    pass "bin/ide rejects unknown CLI flags"
fi

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
    env -u XDG_CONFIG_HOME -u IDE_LINK_RULES HOME="$TEMP_HOME" PATH="$LINK_TEST_DIR/bin:$PATH" DISPLAY=:99 "$@" \
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
    TMUX_TEST_TMPDIR="$(mktemp -d)"
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

    IDE_WS_2P="$TEMP_HOME/ws_2pane_test"
    IDE_WS_3P="$TEMP_HOME/ws_3pane_test"
    mkdir -p "$IDE_WS_2P" "$IDE_WS_3P"

    env -u IDE_AI_CLI "$SCRIPT_DIR/bin/ide" --2pane --detach "$IDE_WS_2P"
    if tmux has-session -t "=ws_2pane_test" 2>/dev/null; then
        pane_cnt="$(tmux list-panes -t "=ws_2pane_test:" | wc -l | tr -d ' ')"
        win_cnt="$(tmux list-windows -t "=ws_2pane_test" | wc -l | tr -d ' ')"
        env_out="$(tmux show-environment -t "=ws_2pane_test" 2>/dev/null || true)"
        if [ "$pane_cnt" = "2" ] && [ "$win_cnt" = "1" ] && grep -q "NVIM_IDE_SOCKET=" <<< "$env_out" && grep -q "NVIM_IDE_PANE=" <<< "$env_out" && grep -q "IDE_AI_PANE=" <<< "$env_out" && grep -q "IDE_AI_CLI=agy" <<< "$env_out"; then
            pass "bin/ide --2pane layout spawns 2 side-by-side panes (50% AI | 50% Editor) in a single window and exports NVIM_IDE_SOCKET, NVIM_IDE_PANE, IDE_AI_PANE, and IDE_AI_CLI=agy"
        else
            fail "bin/ide 2-pane layout" "Expected 2 panes in 1 window and NVIM_IDE_* / IDE_AI_PANE / IDE_AI_CLI=agy env vars, got panes=$pane_cnt wins=$win_cnt env=$env_out"
        fi
        "$SCRIPT_DIR/bin/ide" --kill "ws_2pane_test" >/dev/null 2>&1
    else
        fail "bin/ide 2-pane creation" "Session ws_2pane_test was not created"
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
        pass "bin/ide derives custom tmux session name via ide_session_name in \$IDE_LINK_RULES"
        "$SCRIPT_DIR/bin/ide" --kill "feature_alpha" >/dev/null 2>&1
    else
        fail "bin/ide ide_session_name hook" "Expected session 'feature_alpha' to be created for $CUSTOM_CLIENT_DIR"
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
        if [ "$pane_cnt_3" = "3" ] && [ "$win_cnt_3" = "1" ] && [ "$initial_active" = "$ai_pane" ] && [ "$term_width" = "$win_width" ] && grep -q "IDE_TERM_PANE=" <<< "$env_out_3" && grep -q "IDE_AI_PANE=" <<< "$env_out_3" && grep -q "IDE_AI_CLI=claude" <<< "$env_out_3" && ! grep -q "IDE_TREE_PANE=" <<< "$env_out_3"; then
            pass "bin/ide default 3-pane layout spawns all 3 panes (Top-Left 50%x75% AI Agent, Top-Right 50%x75% Editor, Bottom 100%x25% Full-Width Shell) in a single window with initial focus on AI"
        else
            fail "bin/ide 3-pane layout" "Expected 3 panes in 1 window, initial_active=$ai_pane (got $initial_active), term_width=$win_width (got $term_width), IDE_TERM_PANE, IDE_AI_PANE, and IDE_AI_CLI=claude, got panes=$pane_cnt_3 wins=$win_cnt_3 env=$env_out_3"
        fi

        # Simulate outer client attach-session clearing session env vars
        tmux set-environment -t "=ws_3pane_test" -r NVIM_IDE_PANE

        # Test focus toggles (--toggle, --show-term, --show-editor), bounce-back, and zoom preservation
        # Initial focus is AI ($ai_pane), so first --toggle switches to Editor ($ed_pane), and second returns to AI ($ai_pane)
        "$SCRIPT_DIR/bin/ide" --toggle "ws_3pane_test"
        active_after_t1="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
        pane_cnt_after_t1="$(tmux list-panes -t "$main_win" | wc -l | tr -d ' ')"

        "$SCRIPT_DIR/bin/ide" --toggle "ws_3pane_test"
        active_after_t2="$(tmux display-message -p -t "$main_win" "#{pane_id}")"

        "$SCRIPT_DIR/bin/ide" --show-term "ws_3pane_test"
        active_after_term1="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
        "$SCRIPT_DIR/bin/ide" --show-term "ws_3pane_test"
        active_after_term2="$(tmux display-message -p -t "$main_win" "#{pane_id}")"

        # From AI ($ai_pane): first --show-editor focuses Editor ($ed_pane), second bounces back to AI ($ai_pane) without zooming
        "$SCRIPT_DIR/bin/ide" --show-editor "ws_3pane_test"
        active_after_ed1="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
        "$SCRIPT_DIR/bin/ide" --show-editor "ws_3pane_test"
        active_after_ed2="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
        zoom_no_ed="$(tmux display-message -p -t "$main_win" "#{window_zoomed_flag}")"

        # Focus Editor and zoom via tmux (Alt+z): --toggle and --show-editor preserve zoom state across panes
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
            pass "bin/ide --toggle, --show-term, and --show-editor focus and bounce back across AI, Editor, and Shell panes while preserving zoom state"
        else
            fail "bin/ide focus/zoom toggles" "Unexpected focus/zoom state: t1=$active_after_t1(exp $ed_pane) t2=$active_after_t2(exp $ai_pane) term1=$active_after_term1(exp $term_pane) term2=$active_after_term2(exp $ai_pane) ed1=$active_after_ed1 ed2=$active_after_ed2 z_no=$zoom_no_ed z_ed=$zoom_in_ed z_ai=$zoom_in_ai($active_zoom_ai) z_back=$zoom_back_ed($active_zoom_ed) unzoom=$zoom_after_unzoom"
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
           [ "$panes_after_unpark_all" = "3" ] && [ "$term_parked_flag0" = "0" ] && [ "$term_w_restored" = "$win_width" ] && [ "$term_h_restored" = "$term_h_0" ] && \
           [ "$ed_pid_0" = "$ed_pid_1" ] && [ "$term_pid_0" = "$term_pid_1" ] && [ "$ai_pid_0" = "$ai_pid_1" ]; then
            pass "bin/ide --toggle-term, --toggle-editor, --toggle-ai, and --status-click non-destructively park/unpark panes via _ide_park_<role>, track @ide_*_parked, lock main_win rename, guard the last visible pane, and restore geometry and PIDs"
        else
            fail "bin/ide pane parking/unparking" "Unexpected state: main_rename=$main_allow_rename park_term=$panes_after_park_term($park_term_win,flag=$term_parked_flag1->$term_parked_flag0) park_ed=$panes_after_park_ed($park_ed_win,flag=$ed_parked_flag1->$ed_parked_flag0) guard=$panes_after_last_guard unpark_ed=$active_after_unpark_ed all=$panes_after_unpark_all w=$term_w_restored/$win_width h=$term_h_restored/$term_h_0 pids=$ed_pid_0/$ed_pid_1,$term_pid_0/$term_pid_1,$ai_pid_0/$ai_pid_1"
        fi

        # Test directional pane swapping (--swap right|left|down|up) including horizontal wrap,
        # plus parking/unparking both top panes while vertically swapped (`--swap down`)
        tmux select-pane -t "$ai_pane"
        "$SCRIPT_DIR/bin/ide" --swap right "ws_3pane_test"
        ed_left_swap1="$(tmux display-message -p -t "$ed_pane" "#{pane_left}")"
        ai_left_swap1="$(tmux display-message -p -t "$ai_pane" "#{pane_left}")"
        swapped_flag1="$(tmux show-options -qv -t "ws_3pane_test" @ide_swapped 2>/dev/null || true)"
        # Calling --swap right again from the right-most top pane wraps horizontally back to the left
        "$SCRIPT_DIR/bin/ide" --swap right "ws_3pane_test"
        ed_left_swap2="$(tmux display-message -p -t "$ed_pane" "#{pane_left}")"
        ai_left_swap2="$(tmux display-message -p -t "$ai_pane" "#{pane_left}")"
        # Vertical swap down to Shell ([Shell | Editor] on top, [AI] full-width on bottom), then park & unpark both top panes
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
            pass "bin/ide --swap right/left/down/up directionally swaps panes, wraps horizontally across the top split, and preserves vertically-swapped layouts across multi-pane parking/unparking"
        else
            fail "bin/ide --swap" "Unexpected swap coordinates: swap1(ed=$ed_left_swap1,ai=$ai_left_swap1,flag=$swapped_flag1) swap2(ed=$ed_left_swap2,ai=$ai_left_swap2) down(ai_top=$ai_top_down,term_top=$term_top_down) restored(term_top=$term_top_restored,ed_top=$ed_top_restored,ai_top=$ai_top_restored,ai_w=$ai_w_restored/$win_width,rename=$park_allow_rename) up(ai_top=$ai_top_up,term_top=$term_top_up)"
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
            pass "bin/ide updates IDE_AI_CLI across codex/openai normalization, keeps AI pane alive on respawn, and preserves @ide_ai_cli on reattach without --ai"
        else
            fail "bin/ide IDE_AI_CLI update" "Failed to update/preserve IDE_AI_CLI=codex (opt=$opt_out_reattach)"
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
                pass "Neovim enables autoread + checktime for external AI edits and binds <leader>e / <leader>E to mini.files explorer"
            else
                fail "Neovim autoread / mini.files keymaps" "Expected AR:1 LINE:after_external_edit ME:1 MEE:1, got: $autoread_out"
            fi
        else
            pass "Neovim autoread and mini.files skipped headless runtime check (nvim not installed on runner)"
        fi

        # Verify `bin/ide --cd <subdir>` and `bin/ide --cd --reset` update @ide_workdir without respawning the AI pane
        mkdir -p "$IDE_WS_3P/subdir/sub2"
        ai_pid_before_cd="$(tmux display-message -p -t "$ai_pane" "#{pane_pid}")"
        "$SCRIPT_DIR/bin/ide" --cd "$IDE_WS_3P/subdir" "ws_3pane_test" >/dev/null 2>&1
        wdir_after_dive="$(tmux show-options -qv -t "ws_3pane_test" @ide_workdir 2>/dev/null || true)"
        "$SCRIPT_DIR/bin/ide" --cd --reset "ws_3pane_test" >/dev/null 2>&1
        wdir_after_reset="$(tmux show-options -qv -t "ws_3pane_test" @ide_workdir 2>/dev/null || true)"
        ai_pid_after_cd="$(tmux display-message -p -t "$ai_pane" "#{pane_pid}")"
        expected_dive_dir="$(cd "$IDE_WS_3P/subdir" && pwd -P)"
        expected_init_dir="$(cd "$IDE_WS_3P" && pwd -P)"
        if [ "$wdir_after_dive" = "$expected_dive_dir" ] && [ "$wdir_after_reset" = "$expected_init_dir" ] && [ "$ai_pid_before_cd" = "$ai_pid_after_cd" ]; then
            pass "bin/ide --cd <dir> and --reset synchronize @ide_workdir across Editor and Shell without killing or respawning the AI Agent pane"
        else
            fail "bin/ide --cd" "Expected dive=$expected_dive_dir reset=$expected_init_dir ai_pid=$ai_pid_before_cd==$ai_pid_after_cd (got dive=$wdir_after_dive reset=$wdir_after_reset)"
        fi

        # Verify `bin/ide --open-link` resolves session socket for file://#L<line>, filepath:line, trailing-colon compiler diagnostics (filepath:line:col:),
        # markdown [label](file:///...#L<start>-L<end>) in word, line-wrapped markdown [`label`](file:///truncated..., file URLs with parentheses,
        # Read(...) tool headers, collapsed 3-arg invocations, and workspace basename resolution (unparking Editor if hidden)
        printf "line1\nline2\nline3\n" > "$IDE_WS_3P/subdir/nested.txt"
        mkdir -p "$IDE_WS_3P/app/(auth)"
        printf "auth1\nauth2\nauth3\n" > "$IDE_WS_3P/app/(auth)/route.ts"
        sock_3p="$(tmux show-options -qv -t "ws_3pane_test" @ide_socket 2>/dev/null || true)"
        link_nvim_pid=""
        if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ]; then
            for _ in $(seq 1 40); do
                [ -S "$sock_3p" ] && break
                sleep 0.05
            done
            if [ ! -S "$sock_3p" ]; then
                nvim --headless --listen "$sock_3p" >/dev/null 2>&1 &
                link_nvim_pid=$!
                for _ in $(seq 1 30); do
                    [ -S "$sock_3p" ] && break
                    sleep 0.05
                done
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
                "$SCRIPT_DIR/bin/ide" --open-link "nested.txt:3" "$IDE_WS_3P" "ws_3pane_test"
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
                if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                    bname="$(basename "$(nvim --headless --server "$sock_3p" --remote-expr "expand('%:p')" 2>/dev/null | tr -d '\r\n\"' || true)")"
                    bline="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                    buf_after_paren_file="${bname}:${bline}"
                fi
                # Verify line-wrapped URLs in a tmux pane (e.g. broken after 'home-' onto an indented next line)
                # are stitched back together when clicking either the first line or the continuation line.
                WRAP_BROWSER_OUT="$TEMP_HOME/wrap_browser.out"
                WRAP_BROWSER_BIN="$TEMP_HOME/wrap_browser.sh"
                printf '#!/usr/bin/env bash\necho "$1" >> "%s"\n' "$WRAP_BROWSER_OUT" > "$WRAP_BROWSER_BIN"
                chmod +x "$WRAP_BROWSER_BIN"
                tmux select-pane -t "$term_pane"
                tmux send-keys -t "$term_pane" " printf '  Submitted PR (https://github.com/lock14/home-\\n  settings/pull/118)\\n'" C-m
                for _ in $(seq 1 25); do
                    tmux capture-pane -p -t "$term_pane" 2>/dev/null | grep -Fq "settings/pull/118" && break
                    sleep 0.02
                done
                IDE_BROWSER="$WRAP_BROWSER_BIN" "$SCRIPT_DIR/bin/ide" --open-link "" "https://github.com/lock14/home-" "$IDE_WS_3P" "ws_3pane_test"
                IDE_BROWSER="$WRAP_BROWSER_BIN" "$SCRIPT_DIR/bin/ide" --open-link "" "settings/pull/118" "$IDE_WS_3P" "ws_3pane_test"
                for _ in $(seq 1 25); do
                    [ "$(wc -l < "$WRAP_BROWSER_OUT" 2>/dev/null | tr -d ' ')" = "2" ] && break
                    sleep 0.02
                done
                wrap_url_line1="$(sed -n '1p' "$WRAP_BROWSER_OUT" 2>/dev/null || true)"
                wrap_url_line2="$(sed -n '2p' "$WRAP_BROWSER_OUT" 2>/dev/null || true)"
                rm -f "$WRAP_BROWSER_OUT" "$WRAP_BROWSER_BIN"
                tmux select-pane -t "$ed_pane"
                active_after_link="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
                if [ "$active_after_link" = "$ed_pane" ] && [ "$line_after_href" = "2" ] && [ "$line_after_word" = "3" ] && [ "$line_after_md" = "1" ] && [ "$line_after_wrap" = "3" ] && [ "$line_after_base" = "2" ] && [ "$line_after_collapsed" = "3" ] && [ "$line_after_tool" = "1" ] && [ "$buf_after_paren_file" = "route.ts:2" ] && [ "$wrap_url_line1" = "https://github.com/lock14/home-settings/pull/118" ] && [ "$wrap_url_line2" = "https://github.com/lock14/home-settings/pull/118" ]; then
                    pass "bin/ide --open-link handles file://#L<line>, compiler paths (filepath:line:col:), markdown [label](file:///...#L1-L3), line-wrapped URLs, file URLs with parentheses, Read(...) tool headers, collapsed empty-href args, and workspace basenames (unparking Editor if hidden)"
                else
                    fail "bin/ide --open-link focus/line" "Expected active=$ed_pane, paren=route.ts:2, wrapped URLs=https://github.com/lock14/home-settings/pull/118, and lines 2/3/1/3/2/3/1, got active=$active_after_link href=$line_after_href word=$line_after_word md=$line_after_md wrap=$line_after_wrap base=$line_after_base collapsed=$line_after_collapsed tool=$line_after_tool paren=$buf_after_paren_file wrap1=$wrap_url_line1 wrap2=$wrap_url_line2"
                fi
            else
                fail "bin/ide --open-link filepath:line:col:" "Command failed on filepath:line:col:"
            fi
        else
            fail "bin/ide --open-link file://#L<line>" "Command failed on file://#L<line>"
        fi
        if [ -n "$link_nvim_pid" ]; then
            kill "$link_nvim_pid" 2>/dev/null || true
            rm -f "$sock_3p"
        fi

        # Verify `bin/ide --copy` populates tmux buffer (`load-buffer -w` for OSC 52) AND broadcasts to X11 (`xsel -ib`) after discovering DISPLAY from tmux
        # (even when the session environment has `-DISPLAY` from headless session creation),
        # and `bin/ide --paste` prefers X11 on local desktop vs tmux buffer over SSH.
        COPY_MOCK_DIR="$(mktemp -d)"
        cat > "$COPY_MOCK_DIR/xsel" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "-ib" ]; then
    cat > "$COPY_XSEL_OUT"
    exit 0
fi
if [ "${1:-}" = "-op" ] || [ "${1:-}" = "-ob" ]; then
    printf "from-xsel-selection"
    exit 0
fi
exit 1
SH
        chmod +x "$COPY_MOCK_DIR/xsel"
        tmux set-environment -t "ws_3pane_test" -r DISPLAY 2>/dev/null || true
        tmux set-environment -g DISPLAY ":99"
        printf "solarized-clipboard-payload" | env -u DISPLAY -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT COPY_XSEL_OUT="$COPY_MOCK_DIR/xsel_out" PATH="$COPY_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/ide" --copy
        copy_tmux_got="$(tmux show-buffer 2>/dev/null || true)"
        copy_xsel_got="$(cat "$COPY_MOCK_DIR/xsel_out" 2>/dev/null || true)"
        # Local desktop (--paste without SSH_CONNECTION): prefers X11 (`from-xsel-selection`) and loads it into tmux buffer
        env -u DISPLAY -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT PATH="$COPY_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/ide" --paste "$term_pane"
        paste_local_got="$(tmux show-buffer 2>/dev/null || true)"
        # SSH session (--paste with SSH_CONNECTION): prefers tmux buffer (`from-tmux-ssh-buf`) over stale background X11
        tmux set-buffer "from-tmux-ssh-buf"
        env -u DISPLAY SSH_CONNECTION="10.0.0.1 1234 10.0.0.2 22" PATH="$COPY_MOCK_DIR:$PATH" "$SCRIPT_DIR/bin/ide" --paste "$term_pane"
        paste_ssh_got="$(tmux show-buffer 2>/dev/null || true)"
        tmux set-environment -gu DISPLAY
        rm -rf "$COPY_MOCK_DIR"
        if [ "$copy_tmux_got" = "solarized-clipboard-payload" ] && [ "$copy_xsel_got" = "solarized-clipboard-payload" ] && \
           [ "$paste_local_got" = "from-xsel-selection" ] && [ "$paste_ssh_got" = "from-tmux-ssh-buf" ]; then
            pass "bin/ide --copy discovers DISPLAY from tmux and broadcasts to OSC 52 + X11, and --paste prioritizes X11 on local desktop and tmux buffer over SSH"
        else
            fail "bin/ide --copy / --paste" "Expected copy='solarized-clipboard-payload', paste_local='from-xsel-selection', paste_ssh='from-tmux-ssh-buf', got tmux='$copy_tmux_got' xsel='$copy_xsel_got' local='$paste_local_got' ssh='$paste_ssh_got'"
        fi

        # Verify untagged pane recovery when @ide_term_pane and pane's @ide_role are cleared (tests tmux_out preserving trailing \t)
        tmux set-option -u -t "ws_3pane_test" @ide_term_pane 2>/dev/null || true
        tmux set-environment -t "ws_3pane_test" -r IDE_TERM_PANE 2>/dev/null || true
        tmux set-option -p -u -t "$term_pane" @ide_role 2>/dev/null || true
        "$SCRIPT_DIR/bin/ide" --show-term "ws_3pane_test"
        recovered_term_pane="$(tmux show-options -qv -t "ws_3pane_test" @ide_term_pane 2>/dev/null || true)"
        recovered_pane_cnt="$(tmux list-panes -t "$main_win" | wc -l | tr -d ' ')"

        # Verify self-healing when Right Full-Height Editor pane is closed while Left AI and Shell panes remain,
        # AND when Neovim exits back to an interactive shell inside an existing Editor pane (`--show-editor` revives Neovim in-place without bouncing away)
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
            pass "bin/ide recovers untagged existing panes without duplicating, self-heals Right Full-Height Editor pane if closed, and revives exited Neovim in-place on --show-editor"
        else
            fail "bin/ide Editor pane self-heal / untagged recovery" "Expected recovered_term=$term_pane (got $recovered_term_pane, panes=$recovered_pane_cnt), 3 panes with healed Right Editor at left>0,top=0 (got panes=$healed_pane_cnt left=$healed_ed_left top=$healed_ed_top), and revived Editor active=$healed_ed_pane (got active=$revived_active_pane)"
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
            pass "bin/ide resolve_nvim_bin sorts mise neovim versions numerically (0.11.0 preferred over 0.9.5)"
        else
            fail "bin/ide resolve_nvim_bin version sort" "Expected */0.11.0/bin/nvim, got '$resolved_ver'"
        fi

        "$SCRIPT_DIR/bin/ide" --quit --force "ws_3pane_test" >/dev/null 2>&1
        if ! tmux has-session -t "ws_3pane_test" 2>/dev/null; then
            pass "bin/ide --quit terminates the entire IDE workspace session cleanly"
        else
            fail "bin/ide --quit" "Session ws_3pane_test still exists after --quit"
            "$SCRIPT_DIR/bin/ide" --kill "ws_3pane_test" >/dev/null 2>&1
        fi
    else
        fail "bin/ide 3-pane creation" "Session ws_3pane_test was not created"
    fi

    # `ide --quit` stays inside its own session: closing the Editor via `<Cmd>qall!<CR>` never triggers a recursive
    # `:Q` call, and exact `-t =NAME` targets prevent prefix-matching other sessions (`foo` -> `foobar`).
    session_alive() { tmux has-session -t "=$1" 2>/dev/null; }
    all_alive() {
        local s
        for s in "$@"; do session_alive "$s" || return 1; done
    }
    pane_of() { tmux display-message -p -t "$1:" '#{pane_id}' 2>/dev/null || true; }
    # $TMUX as a pane (or run-shell job) of session $1 sees it: "<socket>,<server pid>,<session id>"
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
        # The Editor's `:Q` runs `$HOME/.local/bin/ide --quit`: HOME is swapped to a logging stub after init.lua ran
        tmux new-session -d -s "quit-editor" -x 120 -y 40 -e "NVIM_IDE_SOCKET=$QUIT_SOCK" \
            "nvim -u '$SCRIPT_DIR/dotfiles/.config/nvim/init.lua' --listen '$QUIT_SOCK' -c \"lua vim.env.HOME = '$QUIT_HOME'\""
        tmux set-option -t "=quit-editor:" @ide_socket "$QUIT_SOCK"
        for _ in $(seq 1 100); do
            if [ -S "$QUIT_SOCK" ] && nvim --headless --server "$QUIT_SOCK" --remote-expr "1" >/dev/null 2>&1; then
                break
            fi
            sleep 0.1
        done
        "$SCRIPT_DIR/bin/ide" --quit "quit-editor" >/dev/null 2>&1 || true
        for _ in $(seq 1 40); do
            session_alive "quit-editor" || break
            sleep 0.05
        done
        quit_log="$(cat "$QUIT_LOG")"
        if [ -z "$quit_log" ] && ! session_alive "quit-editor" && \
           all_alive "ide-bystander" "plain-bystander"; then
            pass "bin/ide --quit closes the Editor via <Cmd>qall!<CR> without spawning a second ide --quit, and other sessions survive"
        else
            fail "bin/ide --quit Editor close" "Expected no ide calls from the Editor (got: ${quit_log:-none}), quit-editor gone, and both bystanders alive"
        fi

        # Quitting from inside the Editor (`:Q`, `:Quit`, `<leader>q`, `<M-q>`) starts a detached `ide --quit <its session>` that closes
        # this Editor: it must outlive it and kill exactly its own session (a 2nd pane keeps the session alive like the AI
        # and Shell panes). IDE_SESSION is set on the pane the way bin/ide sets it on every pane it creates.
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
        for _ in $(seq 1 100); do
            if [ -S "$SELF_SOCK" ] && nvim --headless --server "$SELF_SOCK" --remote-expr "1" >/dev/null 2>&1; then
                break
            fi
            sleep 0.05
        done
        nvim --headless --server "$SELF_SOCK" --remote-send "<C-\\><C-n>:Q<CR>" >/dev/null 2>&1 || true
        for _ in $(seq 1 60); do
            session_alive "quit-self" || break
            sleep 0.05
        done
        sleep 0.05
        self_log="$(cat "$SELF_LOG")"
        if [ "$self_log" = "--quit quit-self" ] && ! session_alive "quit-self" && \
           all_alive "ide-bystander" "plain-bystander"; then
            pass "Quitting from inside the Editor (:Q, :Quit, <leader>q, <M-q>) runs exactly one ide --quit naming its own session, which outlives the Editor it closes and kills only that session"
        else
            fail "Editor-initiated ide --quit" "Expected exactly one '--quit quit-self' call (got: ${self_log:-none}), quit-self gone, and both bystanders alive; sessions now: $(tmux list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
        fi

        # Every Editor `ide` call names the Editor's session like the tmux key bindings do, in the argument positions
        # bin/ide parses (`--quit --force NAME`, `--cd DIR NAME`), and leaves it out without a non-empty $IDE_SESSION
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
vim.cmd("qa!")
LUA
        # A TMUX value naming no server: the stub never calls tmux, and nothing here can reach a real one
        env TMUX="$TEMP_HOME/no-such-tmux,1,0" NVIM_IDE_SOCKET="$TEMP_HOME/no-such.sock" timeout 30 \
            nvim --headless -u "$SCRIPT_DIR/dotfiles/.config/nvim/init.lua" -c "source $TEMP_HOME/editor_args.lua" -c 'qa!' >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do
            [ "$(wc -l < "$ARGS_LOG" | tr -d ' ')" -ge 8 ] && break
            sleep 0.05
        done
        args_log="$(LC_ALL=C sort "$ARGS_LOG")"
        args_expected="$(printf '%s\n' "--cd $ARGS_DIR args-sess" "--quit" "--quit" "--quit --force args-sess" "--quit args-sess" "--swap left args-sess" "--toggle args-sess" "--toggle-editor args-sess" | LC_ALL=C sort)"
        if [ "$args_log" = "$args_expected" ]; then
            pass "The Editor names its own session in every ide call (--quit [--force] NAME, --cd DIR NAME, --toggle NAME, --toggle-editor NAME, --swap DIR NAME) and omits it when \$IDE_SESSION is empty"
        else
            fail "Editor ide call arguments" "Expected: $(tr '\n' '|' <<< "$args_expected") got: $(tr '\n' '|' <<< "$args_log")"
        fi
    else
        pass "bin/ide --quit Editor close skipped headless runtime check (nvim not installed on runner)"
    fi

    # Untargeted quits look up the caller's own pane (or a run-shell job's session id) exactly, and only act on ide sessions
    tmux new-session -d -s "gone-sess" -x 120 -y 40
    tmux set-option -t "=gone-sess:" @ide_session "gone-sess"
    gone_pane="$(pane_of "gone-sess")"
    gone_env="$(tmux_env_of "gone-sess")"
    tmux kill-session -t "=gone-sess"
    for s in recent-sess auto-pane auto-job; do
        tmux new-session -d -s "$s" -x 120 -y 40
        tmux set-option -t "=$s:" @ide_session "$s"
    done
    # From a pane whose session is gone (the Editor's job above): tmux would guess the most recently used session
    env TMUX="$gone_env" TMUX_PANE="$gone_pane" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
    gone_ok=0
    all_alive plain-bystander ide-bystander recent-sess auto-pane auto-job && gone_ok=1
    # From a plain tmux session's own pane
    env TMUX="$(tmux_env_of plain-bystander)" TMUX_PANE="$(pane_of plain-bystander)" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
    # When the server named in $TMUX is gone and another one now answers on its socket
    IFS=, read -r recent_sock _ recent_id <<< "$(tmux_env_of recent-sess)"
    env TMUX="$recent_sock,1,$recent_id" TMUX_PANE="$(pane_of recent-sess)" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
    # From an ide pane, and from a run-shell job (no pane, just the session id in $TMUX): exactly that session
    env TMUX="$(tmux_env_of auto-pane)" TMUX_PANE="$(pane_of auto-pane)" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
    env -u TMUX_PANE TMUX="$(tmux_env_of auto-job)" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
    if [ "$gone_ok" = "1" ] && all_alive plain-bystander ide-bystander recent-sess && \
       ! session_alive "auto-pane" && ! session_alive "auto-job"; then
        pass "Untargeted bin/ide --quit never guesses: from a pane whose session is gone, a plain tmux session, or a replaced server it quits nothing, and from an ide pane or run-shell job it quits exactly that session"
    else
        fail "bin/ide untargeted --quit" "Expected nothing quit from a gone pane (ok=$gone_ok), plain-bystander/ide-bystander/recent-sess alive, auto-pane/auto-job quit; sessions now: $(tmux list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
    fi

    # Exact session names: quitting foo spares another IDE's ai-foobar popup, a later --kill foo / --toggle foo
    # never fall back to foobar, and launching in ./api creates api next to api-gateway instead of reusing it
    for s in foobar ai-foobar foo api-gateway; do
        tmux new-session -d -s "$s" -x 120 -y 40
    done
    "$SCRIPT_DIR/bin/ide" --kill "foo" >/dev/null 2>&1 || true
    "$SCRIPT_DIR/bin/ide" --kill "foo" >/dev/null 2>&1 || true
    "$SCRIPT_DIR/bin/ide" --toggle "foo" >/dev/null 2>&1 || true
    mkdir -p "$TEMP_HOME/api"
    env -u IDE_AI_CLI XDG_RUNTIME_DIR="$TEMP_HOME" "$SCRIPT_DIR/bin/ide" --2pane --detach "$TEMP_HOME/api" >/dev/null 2>&1 || true
    foobar_panes="$(tmux list-panes -s -t "=foobar:" 2>/dev/null | wc -l | tr -d ' ' || true)"
    gateway_panes="$(tmux list-panes -s -t "=api-gateway:" 2>/dev/null | wc -l | tr -d ' ' || true)"
    if ! session_alive "foo" && all_alive foobar ai-foobar api api-gateway && \
       [ "$foobar_panes" = "1" ] && [ "$gateway_panes" = "1" ]; then
        pass "bin/ide targets tmux sessions by exact name (=NAME): no prefix matches when killing, toggling, or launching sessions"
    else
        fail "bin/ide exact session names" "Expected foo gone and foobar (1 pane), ai-foobar, api, api-gateway (1 pane) alive; got foobar_panes=$foobar_panes gateway_panes=$gateway_panes sessions: $(tmux list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
    fi
    "$SCRIPT_DIR/bin/ide" --kill "api" >/dev/null 2>&1 || true

    # Mouse resizing & Ctrl+LeftClick link opening: in a real terminal client (a python3 pty speaking SGR mouse), dragging the
    # AI | Editor border and the Shell's top edge resizes panes under the repo's .tmux.conf, focus switches (--toggle /
    # --show-term), parking/unparking (--toggle-editor / --toggle-term), and a zoom round trip keep the dragged sizes, and
    # Ctrl+LeftClick (C-MouseDown1Pane) routes OSC 8 file hyperlinks and plain-text file:line tokens to `ide --open-link`.
    if command -v python3 >/dev/null 2>&1; then
        MOUSE_TMPDIR="$(mktemp -d)"
        IDE_WS_MOUSE="$TEMP_HOME/ws_mouse"
        MOUSE_CLICK_LOG="$TEMP_HOME/mouse_click.log"
        mkdir -p "$IDE_WS_MOUSE" "$TEMP_HOME/.local/bin"
        printf '#!/usr/bin/env bash\nif [ "${1:-}" = "--open-link" ]; then printf "argc=%%s 2=<%%s> 3=<%%s> 4=<%%s> 5=<%%s>\\n" "$#" "${2:-}" "${3:-}" "${4:-}" "${5:-}" >> %q; fi\nexec %q "$@"\n' \
            "$MOUSE_CLICK_LOG" "$SCRIPT_DIR/bin/ide" > "$TEMP_HOME/.local/bin/ide"
        chmod +x "$TEMP_HOME/.local/bin/ide"
        : > "$MOUSE_CLICK_LOG"
        mouse_out="$(
            export TMUX_TMPDIR="$MOUSE_TMPDIR"
            export HOME="$TEMP_HOME"
            tmux -f "$SCRIPT_DIR/dotfiles/.tmux.conf" new-session -d -s mouse-holder -x 120 -y 40
            env -u IDE_AI_CLI "$SCRIPT_DIR/bin/ide" --detach "$IDE_WS_MOUSE" >/dev/null 2>&1
            echo "binding=$(tmux list-keys -T root MouseDrag1Border 2>&1)"
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

def drain():  # keep reading so tmux never blocks on a full pty
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
    # SGR mouse reports use 1-based cells, and window row y sits on screen row y + 1 below the top status bar
    send(f"\x1b[<0;{x0 + 1};{y0 + 2}M")
    send(f"\x1b[<32;{(x0 + x1) // 2 + 1};{(y0 + y1) // 2 + 2}M")
    send(f"\x1b[<32;{x1 + 1};{y1 + 2}M")
    send(f"\x1b[<0;{x1 + 1};{y1 + 2}m")

before = sizes()
(al, at, aw, ah), (el, et, ew, eh), (sl, st, sw, sh) = before
drag(al + aw, at + 3, al + aw - 10, at + 3)  # AI | Editor border, 10 columns left
drag(2, st - 1, 2, st - 6)                    # Shell's top edge, 5 rows up
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

# Emit an OSC 8 hyperlink on row 0 and a plain-text token on row 1 of the AI pane, then Ctrl+LeftClick row 0 and row 1
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

attached = False
client.terminate()
print(f"drag={'ok' if drag_ok else before + dragged} kept={'ok' if kept == dragged else kept}")
PY
        )" || true
        tmux -S "$MOUSE_TMPDIR/tmux-$(id -u)/default" kill-server >/dev/null 2>&1 || true
        rm -rf "$MOUSE_TMPDIR"
        MOUSE_TMPDIR=""
        mouse_click_logged="$(cat "$MOUSE_CLICK_LOG" 2>/dev/null || true)"
        if grep -q '^binding=.*MouseDrag1Border resize-pane -M' <<< "$mouse_out" && \
           grep -q '^drag=ok kept=ok$' <<< "$mouse_out" && \
           grep -Fq 'argc=5 2=<file:///tmp/osc8_target.lua#L42> 3=<OSC8LINK>' <<< "$mouse_click_logged" && \
           grep -Fq 'argc=5 2=<> 3=<PLAINWORD.lua:7>' <<< "$mouse_click_logged"; then
            pass "tmux resizes IDE panes by mouse (preserving dragged sizes across focus switches, parking/unparking, and zoom) and routes Ctrl+LeftClick (C-MouseDown1Pane) for both OSC 8 hyperlinks and plain-text file:line tokens"
        else
            fail "tmux mouse border resize & Ctrl+LeftClick" "Expected MouseDrag1Border resize-pane -M, drag=ok kept=ok, and C-MouseDown1Pane for OSC8LINK + PLAINWORD.lua:7; got out=$mouse_out click=${mouse_click_logged:-<empty>}"
        fi
    fi

    export PATH="$OLD_TMUX_PATH"
    if [ -n "$OLD_TMUX_SHELL" ]; then
        export SHELL="$OLD_TMUX_SHELL"
    fi
    tmux kill-server >/dev/null 2>&1 || true
    rm -rf "$TMUX_TEST_TMPDIR" "$IDE_AI_STUB_DIR"
fi

# Test 7: bin/update-system CLI validation & cross-platform dry-run orchestration
echo -e "\n[7/7] Testing bin/update-system maintenance orchestrator..."
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

DEV_OUT="$("$SCRIPT_DIR/bin/update-system" --os ubuntu --with-dev --dry-run)"
if grep -Fq "mise plugins update" <<< "$DEV_OUT" && \
   grep -Fq "mise upgrade" <<< "$DEV_OUT" && \
   grep -Fq "rustup update" <<< "$DEV_OUT" && \
   grep -Fq "upgrade.sh" <<< "$DEV_OUT"; then
    pass "bin/update-system --with-dev dispatches Mise, Rustup, and Oh-My-Zsh updates"
else
    fail "bin/update-system --with-dev" "Missing expected developer toolchain commands"
fi

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

test_summary
