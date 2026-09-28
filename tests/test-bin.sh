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
# Tear down the isolated tmux server (by its explicit socket, never via $TMUX) even when a check aborts
# or the run is interrupted, so no test server or Editor outlives the suite
cleanup_test_bin() {
    if [ -n "$TMUX_TEST_TMPDIR" ]; then
        tmux -S "$TMUX_TEST_TMPDIR/tmux-$(id -u)/default" kill-server >/dev/null 2>&1 || true
        rm -rf "$TMUX_TEST_TMPDIR"
    fi
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
if "$SCRIPT_DIR/bin/ide" --help | grep -q -- '--3pane' && "$SCRIPT_DIR/bin/ide" --help | grep -q -- '--kill'; then
    pass "bin/ide --help displays usage for 2-pane, --3pane, --kill, and --list"
else
    fail "bin/ide --help" "Expected --3pane and --kill in bin/ide --help output"
fi

if "$SCRIPT_DIR/bin/ide" --unknown-flag >/dev/null 2>&1; then
    fail "bin/ide invalid flag" "Expected non-zero exit status on unknown flag"
else
    pass "bin/ide rejects unknown CLI flags"
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
    unset TMUX TMUX_PANE

    IDE_WS_2P="$TEMP_HOME/ws_2pane_test"
    IDE_WS_3P="$TEMP_HOME/ws_3pane_test"
    mkdir -p "$IDE_WS_2P" "$IDE_WS_3P"

    env -u IDE_AI_CLI "$SCRIPT_DIR/bin/ide" --2pane --detach "$IDE_WS_2P"
    if tmux has-session -t "ide-ws_2pane_test" 2>/dev/null; then
        pane_cnt="$(tmux list-panes -t "ide-ws_2pane_test" | wc -l | tr -d ' ')"
        win_cnt="$(tmux list-windows -t "ide-ws_2pane_test" | wc -l | tr -d ' ')"
        env_out="$(tmux show-environment -t "ide-ws_2pane_test" 2>/dev/null || true)"
        if [ "$pane_cnt" = "2" ] && [ "$win_cnt" = "1" ] && grep -q "NVIM_IDE_SOCKET=" <<< "$env_out" && grep -q "NVIM_IDE_PANE=" <<< "$env_out" && grep -q "IDE_AI_PANE=" <<< "$env_out" && grep -q "IDE_AI_CLI=agy" <<< "$env_out"; then
            pass "bin/ide --2pane layout spawns 2 side-by-side panes (50% AI | 50% Editor) in a single window and exports NVIM_IDE_SOCKET, NVIM_IDE_PANE, IDE_AI_PANE, and IDE_AI_CLI=agy"
        else
            fail "bin/ide 2-pane layout" "Expected 2 panes in 1 window and NVIM_IDE_* / IDE_AI_PANE / IDE_AI_CLI=agy env vars, got panes=$pane_cnt wins=$win_cnt env=$env_out"
        fi
        "$SCRIPT_DIR/bin/ide" --kill "ide-ws_2pane_test" >/dev/null 2>&1
    else
        fail "bin/ide 2-pane creation" "Session ide-ws_2pane_test was not created"
    fi

    "$SCRIPT_DIR/bin/ide" --ai claude --detach "$IDE_WS_3P"
    if tmux has-session -t "ide-ws_3pane_test" 2>/dev/null; then
        pane_cnt_3="$(tmux list-panes -t "ide-ws_3pane_test" | wc -l | tr -d ' ')"
        win_cnt_3="$(tmux list-windows -t "ide-ws_3pane_test" | wc -l | tr -d ' ')"
        env_out_3="$(tmux show-environment -t "ide-ws_3pane_test" 2>/dev/null || true)"
        ed_pane="$(tmux show-options -qv -t "ide-ws_3pane_test" @ide_editor_pane)"
        ai_pane="$(tmux show-options -qv -t "ide-ws_3pane_test" @ide_ai_pane)"
        term_pane="$(tmux show-options -qv -t "ide-ws_3pane_test" @ide_term_pane)"
        main_win="$(tmux show-options -qv -t "ide-ws_3pane_test" @ide_main_win)"
        initial_active="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
        win_width="$(tmux display-message -p -t "$main_win" "#{window_width}")"
        term_width="$(tmux display-message -p -t "$term_pane" "#{pane_width}")"
        if [ "$pane_cnt_3" = "3" ] && [ "$win_cnt_3" = "1" ] && [ "$initial_active" = "$ai_pane" ] && [ "$term_width" = "$win_width" ] && grep -q "IDE_TERM_PANE=" <<< "$env_out_3" && grep -q "IDE_AI_PANE=" <<< "$env_out_3" && grep -q "IDE_AI_CLI=claude" <<< "$env_out_3" && ! grep -q "IDE_TREE_PANE=" <<< "$env_out_3"; then
            pass "bin/ide default 3-pane layout spawns all 3 panes (Top-Left 50%x75% AI Agent, Top-Right 50%x75% Editor, Bottom 100%x25% Full-Width Shell) in a single window with initial focus on AI"
        else
            fail "bin/ide 3-pane layout" "Expected 3 panes in 1 window, initial_active=$ai_pane (got $initial_active), term_width=$win_width (got $term_width), IDE_TERM_PANE, IDE_AI_PANE, and IDE_AI_CLI=claude, got panes=$pane_cnt_3 wins=$win_cnt_3 env=$env_out_3"
        fi

        # Simulate outer client attach-session clearing session env vars
        tmux set-environment -t "ide-ws_3pane_test" -r NVIM_IDE_PANE

        # Test focus toggles (--toggle, --show-term, --show-editor) and zoom preservation
        # Initial focus is AI ($ai_pane), so first --toggle switches to Editor ($ed_pane), and second returns to AI ($ai_pane)
        "$SCRIPT_DIR/bin/ide" --toggle "ide-ws_3pane_test"
        active_after_t1="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
        pane_cnt_after_t1="$(tmux list-panes -t "$main_win" | wc -l | tr -d ' ')"

        "$SCRIPT_DIR/bin/ide" --toggle "ide-ws_3pane_test"
        active_after_t2="$(tmux display-message -p -t "$main_win" "#{pane_id}")"

        "$SCRIPT_DIR/bin/ide" --show-term "ide-ws_3pane_test"
        active_after_term1="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
        "$SCRIPT_DIR/bin/ide" --show-term "ide-ws_3pane_test"
        active_after_term2="$(tmux display-message -p -t "$main_win" "#{pane_id}")"

        # Now in Editor ($ed_pane): calling --show-editor when already in Editor toggles zoom ON
        "$SCRIPT_DIR/bin/ide" --show-editor "ide-ws_3pane_test"
        zoom_in_ed="$(tmux display-message -p -t "$main_win" "#{window_zoomed_flag}")"
        # Calling --toggle while zoomed focuses AI and preserves zoom
        "$SCRIPT_DIR/bin/ide" --toggle "ide-ws_3pane_test"
        active_zoom_ai="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
        zoom_in_ai="$(tmux display-message -p -t "$main_win" "#{window_zoomed_flag}")"
        # Calling --show-editor from zoomed AI returns to Editor and preserves zoom
        "$SCRIPT_DIR/bin/ide" --show-editor "ide-ws_3pane_test"
        active_zoom_ed="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
        zoom_back_ed="$(tmux display-message -p -t "$main_win" "#{window_zoomed_flag}")"
        # Calling --show-editor again while in zoomed Editor unzooms
        "$SCRIPT_DIR/bin/ide" --show-editor "ide-ws_3pane_test"
        zoom_after_unzoom="$(tmux display-message -p -t "$main_win" "#{window_zoomed_flag}")"

        if [ "$pane_cnt_after_t1" = "3" ] && \
           [ "$active_after_t1" = "$ed_pane" ] && \
           [ "$active_after_t2" = "$ai_pane" ] && \
           [ "$active_after_term1" = "$term_pane" ] && \
           [ "$active_after_term2" = "$ed_pane" ] && \
           [ "$zoom_in_ed" = "1" ] && \
           [ "$active_zoom_ai" = "$ai_pane" ] && [ "$zoom_in_ai" = "1" ] && \
           [ "$active_zoom_ed" = "$ed_pane" ] && [ "$zoom_back_ed" = "1" ] && \
           [ "$zoom_after_unzoom" = "0" ]; then
            pass "bin/ide --toggle, --show-term, and --show-editor switch focus across AI, Editor, and Shell panes while preserving zoom state"
        else
            fail "bin/ide focus/zoom toggles" "Unexpected focus/zoom state: t1=$active_after_t1(exp $ed_pane) t2=$active_after_t2(exp $ai_pane) term1=$active_after_term1(exp $term_pane) term2=$active_after_term2(exp $ed_pane) z_ed=$zoom_in_ed z_ai=$zoom_in_ai($active_zoom_ai) z_back=$zoom_back_ed($active_zoom_ed) unzoom=$zoom_after_unzoom"
        fi

        "$SCRIPT_DIR/bin/ide" --ai codex --detach "$IDE_WS_3P"
        env_out_codex="$(tmux show-environment -t "ide-ws_3pane_test" 2>/dev/null || true)"
        "$SCRIPT_DIR/bin/ide" --ai openai --detach "$IDE_WS_3P"
        env_out_openai="$(tmux show-environment -t "ide-ws_3pane_test" 2>/dev/null || true)"
        IDE_AI_CLI="agy" "$SCRIPT_DIR/bin/ide" --detach "$IDE_WS_3P"
        env_out_reattach="$(tmux show-environment -t "ide-ws_3pane_test" 2>/dev/null || true)"
        opt_out_reattach="$(tmux show-options -qv -t "ide-ws_3pane_test" @ide_ai_cli 2>/dev/null || true)"
        if grep -q "IDE_AI_CLI=codex" <<< "$env_out_codex" && \
           grep -q "IDE_AI_CLI=codex" <<< "$env_out_openai" && \
           grep -q "IDE_AI_CLI=codex" <<< "$env_out_reattach" && \
           [ "$opt_out_reattach" = "codex" ] && \
           tmux display-message -p -t "$ai_pane" "#{pane_id}" >/dev/null 2>&1; then
            pass "bin/ide updates IDE_AI_CLI across codex/openai normalization, keeps AI pane alive on respawn, and preserves @ide_ai_cli on reattach without --ai"
        else
            fail "bin/ide IDE_AI_CLI update" "Failed to update/preserve IDE_AI_CLI=codex (opt=$opt_out_reattach)"
        fi

        # Verify in-process SolarizedIdeTree (`IdeTree.toggle_split()`), `IdeClose` (`:q`), and `IdeFollow.sync(true)` AI live-follow
        if command -v nvim >/dev/null 2>&1; then
            mkdir -p "$IDE_WS_3P/subdir"
            echo "hello" > "$IDE_WS_3P/subdir/nested.txt"
            tree_test_out="$(cd "$IDE_WS_3P" && nvim --headless -u "$SCRIPT_DIR/dotfiles/.config/nvim/init.lua" \
                -c "edit $IDE_WS_3P/subdir/nested.txt | lua IdeTree.toggle_split(); vim.cmd('2'); vim.cmd('normal l'); local exp = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'); local wfw = vim.wo.winfixwidth and '1' or '0'; vim.cmd('normal h'); local col = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'); vim.cmd('wincmd p'); vim.cmd('IdeClose'); io.stdout:write('EXP:' .. (exp:find('nested.txt') and '1' or '0') .. ' COL:' .. (col:find('nested.txt') and '1' or '0') .. ' WFW:' .. wfw .. ' WINS:' .. vim.fn.winnr('$') .. ' FT:' .. vim.bo.filetype)" \
                -c "qa!" 2>&1 || true)"
            if grep -Fq "EXP:1 COL:0 WFW:1 WINS:2 FT:" <<< "$tree_test_out" && ! grep -Fq "FT:ide_tree" <<< "$tree_test_out"; then
                pass "In-process SolarizedIdeTree sets winfixwidth, expands/collapses directories via l/h, and IdeClose (:q) keeps the code split alive beside the sidebar"
            else
                fail "In-process SolarizedIdeTree / IdeClose" "Expected EXP:1 COL:0 WFW:1 WINS:2 and non-ide_tree ft, got: $tree_test_out"
            fi

            if command -v git >/dev/null 2>&1; then
                FOLLOW_REPO="$TEMP_HOME/follow_repo_test"
                # agy's data directory is auto-detected as the ~/.gemini/* entry holding cli/history.jsonl
                FOLLOW_HOME="$TEMP_HOME/follow_home"
                FOLLOW_AGY="$FOLLOW_HOME/.gemini/agy_test"
                FOLLOW_CLAUDE="$TEMP_HOME/claude_test"
                mkdir -p "$FOLLOW_REPO/pkg" "$FOLLOW_AGY/cli" "$FOLLOW_AGY/brain/conv-own/.system_generated/subagents" \
                    "$FOLLOW_AGY/brain/conv-sub" "$FOLLOW_AGY/brain/conv-foreign" "$FOLLOW_HOME/.gemini/unrelated" "$FOLLOW_CLAUDE/plans"
                (
                    cd "$FOLLOW_REPO"
                    git init -q
                    git config user.email "test@example.com"
                    git config user.name "Test"
                    printf "line1\nline2\nline3\nline4\n" > "$FOLLOW_REPO/tracked.go"
                    git add tracked.go
                    git commit -q -m "initial" --no-gpg-sign
                )
                FOLLOW_REPO_REAL="$(cd "$FOLLOW_REPO" && pwd -P)"
                CLAUDE_PROJECT="$FOLLOW_CLAUDE/projects/$(printf '%s' "$FOLLOW_REPO_REAL" | LC_ALL=C sed 's/[^[:alnum:]]/-/g')"
                mkdir -p "$CLAUDE_PROJECT"

                # Two concurrent `ide` sessions: conv-own was launched in this session's root, conv-foreign in another
                printf '{"display":"plan it","timestamp":1000,"workspace":"%s","conversationId":"conv-own"}\n' "$FOLLOW_REPO" > "$FOLLOW_AGY/cli/history.jsonl"
                printf '{"display":"other","timestamp":2000,"workspace":"%s","conversationId":"conv-foreign"}\n' "$TEMP_HOME/other_repo" >> "$FOLLOW_AGY/cli/history.jsonl"
                printf '{"conversationId":"conv-sub"}\n' > "$FOLLOW_AGY/brain/conv-own/.system_generated/subagents/conv-sub.json"
                printf "# Implementation Plan\n" > "$FOLLOW_AGY/brain/conv-own/plan.md"
                printf "# Other Session Plan\n" > "$FOLLOW_AGY/brain/conv-foreign/foreign_plan.md"
                touch -t 202001010000.10 "$FOLLOW_AGY/brain/conv-own/plan.md"
                touch -t 202001010000.30 "$FOLLOW_AGY/brain/conv-foreign/foreign_plan.md"

                # HOME is swapped only after init.lua ran, so lazy.nvim still loads from the real data dir
                follow_nvim() {
                    local cwd="$1"
                    local lua_cmd="$2"
                    local root="${3:-$FOLLOW_REPO}"
                    (cd "$cwd" && env -u NVIM_IDE_SOCKET IDE_INITIAL_ROOT="$root" nvim --headless -u "$SCRIPT_DIR/dotfiles/.config/nvim/init.lua" \
                        -c "lua vim.env.HOME = '$FOLLOW_HOME'; vim.g.ide_claude_dir = '$FOLLOW_CLAUDE'; $lua_cmd" \
                        -c "qa!" 2>&1 || true)
                }
                follow_plan_lua="IdeFollow.sync(true); io.stdout:write('PLAN:' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'))"
                follow_report="io.stdout:write('FILE:' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t') .. ' LINE:' .. vim.fn.line('.'))"

                own_follow_out="$(follow_nvim "$FOLLOW_REPO" "$follow_plan_lua")"

                printf "# Subagent Report\n" > "$FOLLOW_AGY/brain/conv-sub/sub_report.md"
                touch -t 202001010000.40 "$FOLLOW_AGY/brain/conv-sub/sub_report.md"
                sub_follow_out="$(follow_nvim "$FOLLOW_REPO" "$follow_plan_lua")"

                # Claude Code shares ~/.claude/plans across projects; only plans named in this root's transcripts belong here
                printf "# Claude Plan\n" > "$FOLLOW_CLAUDE/plans/own-claude-plan.md"
                printf "# Other Claude Plan\n" > "$FOLLOW_CLAUDE/plans/foreign-claude-plan.md"
                printf '{"type":"assistant","cwd":"%s","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s"}}]}}\n' \
                    "$FOLLOW_REPO_REAL" "$FOLLOW_CLAUDE/plans/own-claude-plan.md" > "$CLAUDE_PROJECT/session-1.jsonl"
                touch -t 202001010000.50 "$FOLLOW_CLAUDE/plans/own-claude-plan.md"
                touch -t 202001010000.55 "$CLAUDE_PROJECT/session-1.jsonl"
                touch -t 202001010001.00 "$FOLLOW_CLAUDE/plans/foreign-claude-plan.md"
                claude_follow_out="$(follow_nvim "$FOLLOW_REPO" "$follow_plan_lua")"

                if grep -Fq "PLAN:plan.md" <<< "$own_follow_out" && \
                   grep -Fq "PLAN:sub_report.md" <<< "$sub_follow_out" && \
                   grep -Fq "PLAN:own-claude-plan.md" <<< "$claude_follow_out"; then
                    pass "AI Live-Follow Mode (IdeFollow.sync) follows only this session's /plan artifacts (own agy conversation in the auto-detected ~/.gemini data dir, its subagents, and Claude plans named in this root's transcripts) while ignoring newer artifacts of concurrent ide sessions"
                else
                    fail "IdeFollow session-scoped artifacts" "Expected PLAN:plan.md, PLAN:sub_report.md, PLAN:own-claude-plan.md; got own=$own_follow_out sub=$sub_follow_out claude=$claude_follow_out"
                fi

                # Shell-driven edit (no edit-log record) caught by the background `git status` from an `icd` subdirectory
                # root (porcelain paths are toplevel-relative), landing on its last diff hunk once git answers
                printf "line1\nline2\nline3_ai_edited\nline4\n" > "$FOLLOW_REPO/tracked.go"
                follow_out="$(follow_nvim "$FOLLOW_REPO/pkg" "IdeFollow.enabled = true; vim.wait(8000, function() IdeFollow.sync(false); return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t') == 'tracked.go' and vim.fn.line('.') == 3 end, 50); $follow_report")"

                # Your own :w is not AI activity: even once the background scan reports the file dirty, the cursor stays put
                self_save_out="$(follow_nvim "$FOLLOW_REPO" "IdeFollow.enabled = true; vim.cmd('edit $FOLLOW_REPO/tracked.go'); vim.api.nvim_buf_set_lines(0, 0, 1, false, { 'line1_user_edit' }); vim.cmd('silent write'); vim.api.nvim_win_set_cursor(0, { 1, 0 }); local moved = IdeFollow.sync(false); vim.wait(8000, function() return IdeFollow.vcs.scans >= 1 end, 20); moved = IdeFollow.sync(false) or moved; io.stdout:write('SELFSAVE:' .. tostring(moved) .. ' LINE:' .. vim.fn.line('.') .. ' SCANS:' .. IdeFollow.vcs.scans)")"

                if grep -Fq "FILE:tracked.go LINE:3" <<< "$follow_out" && grep -Eq "SELFSAVE:false LINE:1 SCANS:[1-9]" <<< "$self_save_out"; then
                    pass "AI Live-Follow Mode follows shell-driven edits found by the background git status from an icd subdirectory root to their diff hunk, and never re-jumps after your own :w saves"
                else
                    fail "IdeFollow git fallback / self-save" "Expected FILE:tracked.go LINE:3 and SELFSAVE:false LINE:1 after a scan, got code=$follow_out save=$self_save_out"
                fi

                # Edit-log records land on the exact edited line while git takes 3 s to answer: the tick never waits on a subprocess
                REAL_GIT="$(command -v git)"
                SLOW_GIT_DIR="$TEMP_HOME/slow_git_bin"
                mkdir -p "$SLOW_GIT_DIR" "$FOLLOW_AGY/brain/conv-own/.system_generated/logs"
                printf '#!/usr/bin/env bash\nset -euo pipefail\nsleep 3\nexec "%s" "$@"\n' "$REAL_GIT" > "$SLOW_GIT_DIR/git"
                chmod +x "$SLOW_GIT_DIR/git"
                printf 'l1\nl2\nl3\nl4\nl5\n}\n\tagyEdited := true\nl8\n' > "$FOLLOW_REPO/pkg/fast.go"
                printf '{"step_index":7,"type":"PLANNER_RESPONSE","tool_calls":[{"name":"replace_file_content","args":{"TargetFile":"%s","StartLine":6,"EndLine":6,"ReplacementContent":"}\\n\\tagyEdited := true"}}]}\n' \
                    "$FOLLOW_REPO/pkg/fast.go" > "$FOLLOW_AGY/brain/conv-own/.system_generated/logs/transcript_full.jsonl"
                fast_out="$(PATH="$SLOW_GIT_DIR:$PATH" follow_nvim "$FOLLOW_REPO" "local uv = vim.uv or vim.loop; local t0 = uv.hrtime(); IdeFollow.sync(true); local ms = (uv.hrtime() - t0) / 1e6; $follow_report; io.stdout:write(' FAST:' .. (ms < 500 and 1 or 0))")"

                # Claude Code `Edit` records carry no line numbers: the whole replacement block is located, not an earlier decoy of its first line
                printf 'package pkg\n// see func claudeEdited() {\n// decoy\nfunc claudeEdited() {\n\treturn\n}\n' > "$FOLLOW_REPO/pkg/claude.go"
                printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s","old_string":"func old() {","new_string":"func claudeEdited() {\\n\\treturn\\n}"}}]}}\n' \
                    "$FOLLOW_REPO_REAL/pkg/claude.go" > "$CLAUDE_PROJECT/session-2.jsonl"
                claude_edit_out="$(follow_nvim "$FOLLOW_REPO" "IdeFollow.sync(true); $follow_report")"

                if grep -Fq "FILE:fast.go LINE:7 FAST:1" <<< "$fast_out" && grep -Fq "FILE:claude.go LINE:4" <<< "$claude_edit_out"; then
                    pass "AI Live-Follow Mode lands agy and Claude Code edit-log records on the exact edited line without waiting on a slow git"
                else
                    fail "IdeFollow edit logs" "Expected FILE:fast.go LINE:7 FAST:1 and FILE:claude.go LINE:4, got agy=$fast_out claude=$claude_edit_out"
                fi

                # Mercurial-style workspace without git (`.hg` marker): this session's edit in a sibling directory of its root is
                # followed, while newer edits by another session's conversation, to AI scratch files, and outside the workspace are not
                HG_WS="$TEMP_HOME/hg_ws_test"
                HG_ROOT="$HG_WS/src/experimental/app"
                HG_LOG="$FOLLOW_AGY/brain/conv-hg/.system_generated/logs/transcript_full.jsonl"
                mkdir -p "$HG_WS/.hg" "$HG_ROOT" "$HG_WS/src/configs" "$TEMP_HOME/outside" \
                    "$FOLLOW_AGY/brain/conv-hg/.system_generated/logs" "$FOLLOW_AGY/brain/conv-hg/scratch" \
                    "$FOLLOW_AGY/brain/conv-foreign/.system_generated/logs" "$FOLLOW_AGY/brain/conv-hg2/.system_generated/logs"
                printf '{"display":"hg","timestamp":3000,"workspace":"%s","conversationId":"conv-hg"}\n' "$HG_ROOT" >> "$FOLLOW_AGY/cli/history.jsonl"
                printf 'a1\na2\na3\n}\nhg_edit_marker = 1\na6\n' > "$HG_WS/src/configs/app.cfg"
                printf 'foreign\n' > "$HG_WS/src/configs/foreign.cfg"
                printf 'print(1)\n' > "$FOLLOW_AGY/brain/conv-hg/scratch/probe.lua"
                printf 'notes\n' > "$TEMP_HOME/outside/notes.txt"
                {
                    printf '{"type":"PLANNER_RESPONSE","tool_calls":[{"name":"replace_file_content","args":{"TargetFile":"%s","StartLine":4,"EndLine":4,"ReplacementContent":"}\\nhg_edit_marker = 1"}}]}\n' "$HG_WS/src/configs/app.cfg"
                    printf '{"type":"PLANNER_RESPONSE","tool_calls":[{"name":"write_to_file","args":{"TargetFile":"%s","CodeContent":"print(1)"}}]}\n' "$FOLLOW_AGY/brain/conv-hg/scratch/probe.lua"
                    printf '{"type":"PLANNER_RESPONSE","tool_calls":[{"name":"write_to_file","args":{"TargetFile":"%s","CodeContent":"notes"}}]}\n' "$TEMP_HOME/outside/notes.txt"
                } > "$HG_LOG"
                printf '{"type":"PLANNER_RESPONSE","tool_calls":[{"name":"write_to_file","args":{"TargetFile":"%s","CodeContent":"foreign"}}]}\n' \
                    "$HG_WS/src/configs/foreign.cfg" > "$FOLLOW_AGY/brain/conv-foreign/.system_generated/logs/transcript_full.jsonl"
                touch -t 202101010000.10 "$HG_WS/src/configs/app.cfg"
                touch -t 202101010000.20 "$HG_WS/src/configs/foreign.cfg"
                touch -t 202101010000.30 "$FOLLOW_AGY/brain/conv-hg/scratch/probe.lua"
                touch -t 202101010000.40 "$TEMP_HOME/outside/notes.txt"
                hg_out="$(follow_nvim "$HG_ROOT" "IdeFollow.sync(true); $follow_report" "$HG_ROOT")"

                # A conversation with only the compact `transcript.jsonl` (every argument value JSON-encoded)
                printf '{"display":"hg2","timestamp":4000,"workspace":"%s","conversationId":"conv-hg2"}\n' "$HG_ROOT" >> "$FOLLOW_AGY/cli/history.jsonl"
                printf 'c1\ncompact_marker = 2\nc3\n' > "$HG_WS/src/configs/compact.cfg"
                printf '{"type":"PLANNER_RESPONSE","tool_calls":[{"name":"replace_file_content","args":{"TargetFile":"\\"%s\\"","StartLine":"2","EndLine":"2","ReplacementContent":"\\"compact_marker = 2\\""}}],"truncated_fields":["tool_calls"]}\n' \
                    "$HG_WS/src/configs/compact.cfg" > "$FOLLOW_AGY/brain/conv-hg2/.system_generated/logs/transcript.jsonl"
                touch -t 202101010000.50 "$HG_WS/src/configs/compact.cfg"
                hg2_out="$(follow_nvim "$HG_ROOT" "IdeFollow.sync(true); $follow_report" "$HG_ROOT")"

                # A running Editor follows only what is logged after it started: existing records are skipped, new ones followed
                LATE_CFG="$HG_WS/src/configs/late.cfg"
                late_out="$(follow_nvim "$HG_ROOT" "IdeFollow.start_timer(); vim.wait(200); local primed = vim.tbl_count(IdeFollow.edits); IdeFollow.enabled = true; vim.fn.writefile({ vim.json.encode({ type = 'PLANNER_RESPONSE', tool_calls = { { name = 'replace_file_content', args = { TargetFile = '$LATE_CFG', StartLine = 3, EndLine = 3, ReplacementContent = 'late_marker = 3' } } } }) }, '$HG_LOG', 'a'); vim.fn.writefile({ 'l1', 'l2', 'late_marker = 3', 'l4' }, '$LATE_CFG'); IdeFollow.sync(false); $follow_report; io.stdout:write(' PRIMED:' .. primed .. ' EDITS:' .. vim.tbl_count(IdeFollow.edits))" "$HG_ROOT")"

                if grep -Fq "FILE:app.cfg LINE:5" <<< "$hg_out" && \
                   grep -Fq "FILE:compact.cfg LINE:2" <<< "$hg2_out" && \
                   grep -Fq "FILE:late.cfg LINE:3 PRIMED:0 EDITS:1" <<< "$late_out"; then
                    pass "AI Live-Follow Mode follows this session's edit logs in a Mercurial-style workspace without git (full and compact transcripts), ignores other sessions, AI scratch files, and paths outside the workspace, and skips edits logged before the Editor started"
                else
                    fail "IdeFollow Mercurial edit logs" "Expected FILE:app.cfg LINE:5, FILE:compact.cfg LINE:2, FILE:late.cfg LINE:3 PRIMED:0 EDITS:1; got hg=$hg_out compact=$hg2_out late=$late_out"
                fi

                # A session launched in $HOME itself: its workspace contains ~/.gemini, yet the AI's own state (a newer
                # scratch file in its data dir) is still never followed, only the project edit
                HOME_LOG="$FOLLOW_AGY/brain/conv-home/.system_generated/logs/transcript_full.jsonl"
                mkdir -p "$FOLLOW_HOME/notes" "$FOLLOW_AGY/brain/conv-home/.system_generated/logs" "$FOLLOW_AGY/brain/conv-home/scratch"
                printf '{"display":"home","timestamp":5000,"workspace":"%s","conversationId":"conv-home"}\n' "$FOLLOW_HOME" >> "$FOLLOW_AGY/cli/history.jsonl"
                printf 'h1\nhome_marker = 1\nh3\n' > "$FOLLOW_HOME/notes/todo.cfg"
                printf 'print(2)\n' > "$FOLLOW_AGY/brain/conv-home/scratch/probe2.lua"
                {
                    printf '{"type":"PLANNER_RESPONSE","tool_calls":[{"name":"replace_file_content","args":{"TargetFile":"%s","StartLine":2,"EndLine":2,"ReplacementContent":"home_marker = 1"}}]}\n' "$FOLLOW_HOME/notes/todo.cfg"
                    printf '{"type":"PLANNER_RESPONSE","tool_calls":[{"name":"write_to_file","args":{"TargetFile":"%s","CodeContent":"print(2)"}}]}\n' "$FOLLOW_AGY/brain/conv-home/scratch/probe2.lua"
                } > "$HOME_LOG"
                touch -t 202101010001.00 "$FOLLOW_HOME/notes/todo.cfg"
                touch -t 202101010001.10 "$FOLLOW_AGY/brain/conv-home/scratch/probe2.lua"
                home_out="$(follow_nvim "$FOLLOW_HOME" "IdeFollow.sync(true); $follow_report" "$FOLLOW_HOME")"

                if grep -Fq "FILE:todo.cfg LINE:2" <<< "$home_out"; then
                    pass "AI Live-Follow Mode never follows the AI tools' own state (~/.gemini, agy's data dir), even when the session's workspace contains it"
                else
                    fail "IdeFollow AI-state exclusion" "Expected FILE:todo.cfg LINE:2, got: $home_out"
                fi
            fi
        else
            pass "In-process SolarizedIdeTree and IdeFollow skipped headless runtime check (nvim not installed on runner)"
        fi

        # Verify `bin/ide --cd <subdir>` and `bin/ide --cd --reset` update @ide_workdir without respawning the AI pane
        mkdir -p "$IDE_WS_3P/subdir/sub2"
        ai_pid_before_cd="$(tmux display-message -p -t "$ai_pane" "#{pane_pid}")"
        "$SCRIPT_DIR/bin/ide" --cd "$IDE_WS_3P/subdir" "ide-ws_3pane_test" >/dev/null 2>&1
        wdir_after_dive="$(tmux show-options -qv -t "ide-ws_3pane_test" @ide_workdir 2>/dev/null || true)"
        "$SCRIPT_DIR/bin/ide" --cd --reset "ide-ws_3pane_test" >/dev/null 2>&1
        wdir_after_reset="$(tmux show-options -qv -t "ide-ws_3pane_test" @ide_workdir 2>/dev/null || true)"
        ai_pid_after_cd="$(tmux display-message -p -t "$ai_pane" "#{pane_pid}")"
        expected_dive_dir="$(cd "$IDE_WS_3P/subdir" && pwd -P)"
        expected_init_dir="$(cd "$IDE_WS_3P" && pwd -P)"
        if [ "$wdir_after_dive" = "$expected_dive_dir" ] && [ "$wdir_after_reset" = "$expected_init_dir" ] && [ "$ai_pid_before_cd" = "$ai_pid_after_cd" ]; then
            pass "bin/ide --cd <dir> and --reset synchronize @ide_workdir across Editor, IdeTree, and Shell without killing or respawning the AI Agent pane"
        else
            fail "bin/ide --cd" "Expected dive=$expected_dive_dir reset=$expected_init_dir ai_pid=$ai_pid_before_cd==$ai_pid_after_cd (got dive=$wdir_after_dive reset=$wdir_after_reset)"
        fi

        # Verify `bin/ide --open-link` resolves session socket for file://#L<line>, filepath:line, and trailing-colon compiler diagnostics (filepath:line:col:)
        printf "line1\nline2\nline3\n" > "$IDE_WS_3P/subdir/nested.txt"
        sock_3p="$(tmux show-options -qv -t "ide-ws_3pane_test" @ide_socket 2>/dev/null || true)"
        link_nvim_pid=""
        if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ ! -S "$sock_3p" ]; then
            nvim --headless --listen "$sock_3p" >/dev/null 2>&1 &
            link_nvim_pid=$!
            for _ in $(seq 1 30); do
                [ -S "$sock_3p" ] && break
                sleep 0.05
            done
        fi
        "$SCRIPT_DIR/bin/ide" --toggle "ide-ws_3pane_test"
        if "$SCRIPT_DIR/bin/ide" --open-link "file://$IDE_WS_3P/subdir/nested.txt#L2" "" "$IDE_WS_3P" "ide-ws_3pane_test"; then
            line_after_href="2"
            if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                line_after_href="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
            fi
            if "$SCRIPT_DIR/bin/ide" --open-link "" "(subdir/nested.txt:3:1):" "$IDE_WS_3P" "ide-ws_3pane_test"; then
                line_after_word="3"
                if command -v nvim >/dev/null 2>&1 && [ -n "$sock_3p" ] && [ -S "$sock_3p" ]; then
                    line_after_word="$(nvim --headless --server "$sock_3p" --remote-expr "line('.')" 2>/dev/null | tr -cd '0-9' || true)"
                fi
                active_after_link="$(tmux display-message -p -t "$main_win" "#{pane_id}")"
                if [ "$active_after_link" = "$ed_pane" ] && [ "$line_after_href" = "2" ] && [ "$line_after_word" = "3" ]; then
                    pass "bin/ide --open-link handles file://#L<line> and trailing-colon compiler paths (filepath:line:col:), focuses Editor pane, and jumps to target line numbers"
                else
                    fail "bin/ide --open-link focus/line" "Expected active=$ed_pane and lines 2/3, got active=$active_after_link href_line=$line_after_href word_line=$line_after_word"
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

        # Verify self-healing when Right Full-Height Editor pane is closed while Left AI and Shell panes remain
        tmux kill-pane -t "$ed_pane" 2>/dev/null || true
        "$SCRIPT_DIR/bin/ide" --focus-editor "ide-ws_3pane_test"
        healed_ed_pane="$(tmux show-options -qv -t "ide-ws_3pane_test" @ide_editor_pane 2>/dev/null || true)"
        healed_ed_left="$(tmux display-message -p -t "$healed_ed_pane" "#{pane_left}" 2>/dev/null || echo 0)"
        healed_ed_top="$(tmux display-message -p -t "$healed_ed_pane" "#{pane_top}" 2>/dev/null || echo 1)"
        healed_pane_cnt="$(tmux list-panes -t "$main_win" | wc -l | tr -d ' ')"
        if [ "$healed_pane_cnt" = "3" ] && [ "${healed_ed_left:-0}" -gt 0 ] && [ "${healed_ed_top:-1}" = "0" ]; then
            pass "bin/ide self-heals Right Full-Height Editor pane (left>0, top=0) and restores 3-pane geometry if closed"
        else
            fail "bin/ide Editor pane self-heal" "Expected 3 panes and healed Right Editor at left>0,top=0, got panes=$healed_pane_cnt left=$healed_ed_left top=$healed_ed_top"
        fi

        "$SCRIPT_DIR/bin/ide" --quit --force "ide-ws_3pane_test" >/dev/null 2>&1
        if ! tmux has-session -t "ide-ws_3pane_test" 2>/dev/null; then
            pass "bin/ide --quit terminates the entire IDE workspace session cleanly"
        else
            fail "bin/ide --quit" "Session ide-ws_3pane_test still exists after --quit"
            "$SCRIPT_DIR/bin/ide" --kill "ide-ws_3pane_test" >/dev/null 2>&1
        fi
    else
        fail "bin/ide 3-pane creation" "Session ide-ws_3pane_test was not created"
    fi

    # `ide --quit` stays inside its own session. It used to type `:qa!` into the Editor, whose `:qa` -> `:Q`
    # abbreviation spawned a second, untargeted `ide --quit`; by the time that ran its session was gone, tmux
    # answered "the current session" with the most recently used one, and one quit cascaded through every
    # session on the server. Bare `-t NAME` targets also prefix-matched other sessions (`ide-foo` -> `ide-foobar`).
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

    if command -v nvim >/dev/null 2>&1; then
        QUIT_HOME="$TEMP_HOME/quit_stub_home"
        QUIT_LOG="$TEMP_HOME/quit_stub.log"
        QUIT_SOCK="$TEMP_HOME/quit_editor.sock"
        mkdir -p "$QUIT_HOME/.local/bin"
        printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\n' "$QUIT_LOG" > "$QUIT_HOME/.local/bin/ide"
        chmod +x "$QUIT_HOME/.local/bin/ide"
        : > "$QUIT_LOG"
        # The Editor's `:Q` runs `$HOME/.local/bin/ide --quit`: HOME is swapped to a logging stub after init.lua ran
        tmux new-session -d -s "ide-quit-editor" -x 120 -y 40 -e "NVIM_IDE_SOCKET=$QUIT_SOCK" \
            "nvim -u '$SCRIPT_DIR/dotfiles/.config/nvim/init.lua' --listen '$QUIT_SOCK' -c \"lua vim.env.HOME = '$QUIT_HOME'\""
        tmux set-option -t "ide-quit-editor" @ide_socket "$QUIT_SOCK"
        quit_abbrev=""
        for _ in $(seq 1 100); do
            if [ -S "$QUIT_SOCK" ]; then
                quit_abbrev="$(nvim --headless --server "$QUIT_SOCK" --remote-expr "execute('cabbrev qa!')" 2>/dev/null || true)"
                grep -Fq "'Q!'" <<< "$quit_abbrev" && break
            fi
            sleep 0.1
        done
        "$SCRIPT_DIR/bin/ide" --quit "ide-quit-editor" >/dev/null 2>&1 || true
        sleep 1
        quit_log="$(cat "$QUIT_LOG")"
        if grep -Fq "'Q!'" <<< "$quit_abbrev" && [ -z "$quit_log" ] && ! session_alive "ide-quit-editor" && \
           all_alive "ide-bystander" "plain-bystander"; then
            pass "bin/ide --quit closes the Editor past its :qa! -> :Q! abbreviation, so the Editor never spawns a second, untargeted ide --quit and other sessions survive"
        else
            fail "bin/ide --quit Editor close" "Expected the Editor's :qa! -> :Q! abbreviation (got: ${quit_abbrev:-none}), no ide calls from the Editor (got: ${quit_log:-none}), ide-quit-editor gone, and both bystanders alive"
        fi

        # Quitting from inside the Editor (`:Q`, `:qa`, `<leader>q`) starts a detached `ide --quit <its session>` that closes
        # this Editor: it must outlive it and kill exactly its own session (a 2nd pane keeps the session alive like the AI
        # and Shell panes). IDE_SESSION is set on the pane the way bin/ide sets it on every pane it creates.
        SELF_HOME="$TEMP_HOME/quit_self_home"
        SELF_LOG="$TEMP_HOME/quit_self.log"
        SELF_SOCK="$TEMP_HOME/quit_self.sock"
        mkdir -p "$SELF_HOME/.local/bin"
        printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\nexec %q "$@"\n' "$SELF_LOG" "$SCRIPT_DIR/bin/ide" > "$SELF_HOME/.local/bin/ide"
        chmod +x "$SELF_HOME/.local/bin/ide"
        : > "$SELF_LOG"
        tmux new-session -d -s "ide-quit-self" -x 120 -y 40 -e "NVIM_IDE_SOCKET=$SELF_SOCK" -e "IDE_SESSION=ide-quit-self" \
            "nvim -u '$SCRIPT_DIR/dotfiles/.config/nvim/init.lua' --listen '$SELF_SOCK' -c \"lua vim.env.HOME = '$SELF_HOME'\""
        tmux split-window -d -t "ide-quit-self:" "sleep 600"
        tmux set-option -t "ide-quit-self" @ide_socket "$SELF_SOCK"
        self_abbrev=""
        for _ in $(seq 1 100); do
            if [ -S "$SELF_SOCK" ]; then
                self_abbrev="$(nvim --headless --server "$SELF_SOCK" --remote-expr "execute('cabbrev qa!')" 2>/dev/null || true)"
                grep -Fq "'Q!'" <<< "$self_abbrev" && break
            fi
            sleep 0.1
        done
        nvim --headless --server "$SELF_SOCK" --remote-send "<C-\\><C-n>:Q<CR>" >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do
            session_alive "ide-quit-self" || break
            sleep 0.1
        done
        sleep 0.5
        self_log="$(cat "$SELF_LOG")"
        if grep -Fq "'Q!'" <<< "$self_abbrev" && [ "$self_log" = "--quit ide-quit-self" ] && ! session_alive "ide-quit-self" && \
           all_alive "ide-bystander" "plain-bystander"; then
            pass "Quitting from inside the Editor (:Q, :qa, <leader>q) runs exactly one ide --quit naming its own session, which outlives the Editor it closes and kills only that session"
        else
            fail "Editor-initiated ide --quit" "Expected exactly one '--quit ide-quit-self' call (got: ${self_log:-none}), ide-quit-self gone, and both bystanders alive; sessions now: $(tmux list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
        fi

        # Every Editor `ide` call names the Editor's session like the tmux key bindings do, in the argument positions
        # bin/ide parses (`--quit --force NAME`, `--cd DIR NAME`), and leaves it out without an ide-* $IDE_SESSION
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
as("ide-args", function() vim.cmd("Q") end)
as("ide-args", function() vim.cmd("Q!") end)
as("ide-args", function() IdeTree.dive([[$ARGS_DIR]]) end)
as("ide-args", function() vim.fn.maparg("<leader>a", "n", false, true).callback() end)
as(nil, function() vim.cmd("Q") end)
as("args", function() vim.cmd("Q") end)
vim.cmd("qa!")
LUA
        # A TMUX value naming no server: the stub never calls tmux, and nothing here can reach a real one
        env TMUX="$TEMP_HOME/no-such-tmux,1,0" NVIM_IDE_SOCKET="$TEMP_HOME/no-such.sock" timeout 30 \
            nvim --headless -u "$SCRIPT_DIR/dotfiles/.config/nvim/init.lua" -c "source $TEMP_HOME/editor_args.lua" -c 'qa!' >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do
            [ "$(wc -l < "$ARGS_LOG" | tr -d ' ')" -ge 6 ] && break
            sleep 0.1
        done
        args_log="$(LC_ALL=C sort "$ARGS_LOG")"
        args_expected="$(printf '%s\n' "--cd $ARGS_DIR ide-args" "--quit" "--quit" "--quit --force ide-args" "--quit ide-args" "--toggle ide-args" | LC_ALL=C sort)"
        if [ "$args_log" = "$args_expected" ]; then
            pass "The Editor names its own session in every ide call (--quit [--force] NAME, --cd DIR NAME, --toggle NAME) and omits it without an ide-* \$IDE_SESSION"
        else
            fail "Editor ide call arguments" "Expected: $(tr '\n' '|' <<< "$args_expected") got: $(tr '\n' '|' <<< "$args_log")"
        fi
    else
        pass "bin/ide --quit Editor close skipped headless runtime check (nvim not installed on runner)"
    fi

    # Untargeted quits look up the caller's own pane (or a run-shell job's session id) exactly, and only act on ide-* sessions
    tmux new-session -d -s "ide-gone" -x 120 -y 40
    gone_pane="$(pane_of "ide-gone")"
    gone_env="$(tmux_env_of "ide-gone")"
    tmux kill-session -t "=ide-gone"
    for s in ide-recent ide-auto-pane ide-auto-job; do
        tmux new-session -d -s "$s" -x 120 -y 40
    done
    # From a pane whose session is gone (the Editor's job above): tmux would guess the most recently used session
    env TMUX="$gone_env" TMUX_PANE="$gone_pane" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
    gone_ok=0
    all_alive plain-bystander ide-bystander ide-recent ide-auto-pane ide-auto-job && gone_ok=1
    # From a plain tmux session's own pane
    env TMUX="$(tmux_env_of plain-bystander)" TMUX_PANE="$(pane_of plain-bystander)" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
    # When the server named in $TMUX is gone and another one now answers on its socket
    IFS=, read -r recent_sock _ recent_id <<< "$(tmux_env_of ide-recent)"
    env TMUX="$recent_sock,1,$recent_id" TMUX_PANE="$(pane_of ide-recent)" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
    # From an ide pane, and from a run-shell job (no pane, just the session id in $TMUX): exactly that session
    env TMUX="$(tmux_env_of ide-auto-pane)" TMUX_PANE="$(pane_of ide-auto-pane)" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
    env -u TMUX_PANE TMUX="$(tmux_env_of ide-auto-job)" "$SCRIPT_DIR/bin/ide" --quit --force >/dev/null 2>&1 || true
    if [ "$gone_ok" = "1" ] && all_alive plain-bystander ide-bystander ide-recent && \
       ! session_alive "ide-auto-pane" && ! session_alive "ide-auto-job"; then
        pass "Untargeted bin/ide --quit never guesses: from a pane whose session is gone, a plain tmux session, or a replaced server it quits nothing, and from an ide pane or run-shell job it quits exactly that session"
    else
        fail "bin/ide untargeted --quit" "Expected nothing quit from a gone pane (ok=$gone_ok), plain-bystander/ide-bystander/ide-recent alive, ide-auto-pane/ide-auto-job quit; sessions now: $(tmux list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
    fi

    # Exact session names: quitting ide-foo spares another IDE's ai-ide-foobar popup, a later --kill foo / --toggle foo
    # never fall back to ide-foobar, and launching in ./api creates ide-api next to ide-api-gateway instead of reusing it
    for s in ide-foobar ai-ide-foobar ide-foo ide-api-gateway; do
        tmux new-session -d -s "$s" -x 120 -y 40
    done
    "$SCRIPT_DIR/bin/ide" --kill "ide-foo" >/dev/null 2>&1 || true
    "$SCRIPT_DIR/bin/ide" --kill "foo" >/dev/null 2>&1 || true
    "$SCRIPT_DIR/bin/ide" --toggle "foo" >/dev/null 2>&1 || true
    mkdir -p "$TEMP_HOME/api"
    env -u IDE_AI_CLI XDG_RUNTIME_DIR="$TEMP_HOME" "$SCRIPT_DIR/bin/ide" --2pane --detach "$TEMP_HOME/api" >/dev/null 2>&1 || true
    foobar_panes="$(tmux list-panes -s -t "ide-foobar:" 2>/dev/null | wc -l | tr -d ' ' || true)"
    gateway_panes="$(tmux list-panes -s -t "ide-api-gateway:" 2>/dev/null | wc -l | tr -d ' ' || true)"
    if ! session_alive "ide-foo" && all_alive ide-foobar ai-ide-foobar ide-api ide-api-gateway && \
       [ "$foobar_panes" = "1" ] && [ "$gateway_panes" = "1" ]; then
        pass "bin/ide targets tmux sessions by exact name (=NAME): no prefix matches when killing, toggling, or launching sessions"
    else
        fail "bin/ide exact session names" "Expected ide-foo gone and ide-foobar (1 pane), ai-ide-foobar, ide-api, ide-api-gateway (1 pane) alive; got foobar_panes=$foobar_panes gateway_panes=$gateway_panes sessions: $(tmux list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
    fi
    "$SCRIPT_DIR/bin/ide" --kill "ide-api" >/dev/null 2>&1 || true

    tmux kill-server >/dev/null 2>&1 || true
    rm -rf "$TMUX_TEST_TMPDIR"
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
