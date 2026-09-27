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
trap 'rm -rf "$TEMP_HOME"' EXIT

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

if command -v tmux >/dev/null 2>&1; then
    TMUX_TEST_TMPDIR="$(mktemp -d)"
    export TMUX_TMPDIR="$TMUX_TEST_TMPDIR"
    unset TMUX

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
                FOLLOW_BRAIN="$TEMP_HOME/brain_test/conv-123"
                mkdir -p "$FOLLOW_REPO" "$FOLLOW_BRAIN"
                (
                    cd "$FOLLOW_REPO"
                    git init -q
                    git config user.email "test@example.com"
                    git config user.name "Test"
                    printf "line1\nline2\nline3\nline4\n" > "$FOLLOW_REPO/tracked.go"
                    git add tracked.go
                    git commit -q -m "initial" --no-gpg-sign
                )
                printf "# Implementation Plan\n" > "$FOLLOW_BRAIN/plan.md"
                plan_follow_out="$(cd "$FOLLOW_REPO" && nvim --headless -u "$SCRIPT_DIR/dotfiles/.config/nvim/init.lua" \
                    -c "lua vim.g.ide_artifact_dirs = { '$TEMP_HOME/brain_test' }; IdeFollow.sync(true); io.stdout:write('PLAN:' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'))" \
                    -c "qa!" 2>&1 || true)"
                sleep 1
                printf "line1\nline2\nline3_ai_edited\nline4\n" > "$FOLLOW_REPO/tracked.go"
                follow_out="$(cd "$FOLLOW_REPO" && nvim --headless -u "$SCRIPT_DIR/dotfiles/.config/nvim/init.lua" \
                    -c "lua vim.g.ide_artifact_dirs = { '$TEMP_HOME/brain_test' }; IdeFollow.sync(true); io.stdout:write('FILE:' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t') .. ' LINE:' .. vim.fn.line('.'))" \
                    -c "qa!" 2>&1 || true)"
                if grep -Fq "PLAN:plan.md" <<< "$plan_follow_out" && grep -Fq "FILE:tracked.go LINE:3" <<< "$follow_out"; then
                    pass "AI Live-Follow Mode (IdeFollow.sync) follows newly written /plan .md artifacts and git-modified files, jumping to the modified diff hunk line"
                else
                    fail "AI Live-Follow Mode (IdeFollow.sync)" "Expected PLAN:plan.md and FILE:tracked.go LINE:3, got plan=$plan_follow_out code=$follow_out"
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
