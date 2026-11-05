#!/usr/bin/env bash
# Test suite for Zsh completions (dotfiles/.zsh-completions, setup.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/tests/test-helper.sh"

echo "========================================"
echo "Running Completions Setup Tests"
echo "========================================"

# Test 1: Syntax validation
echo -e "\n[1/3] Checking completion syntax..."
if zsh -n "$SCRIPT_DIR/dotfiles/.zsh-completions"; then
    pass "Syntax valid: dotfiles/.zsh-completions"
else
    fail "Syntax check failed: dotfiles/.zsh-completions" "zsh -n returned non-zero"
fi

# Test 2: Execution in temporary environment
echo -e "\n[2/3] Testing dotfiles installation..."
TEMP_HOME=$(mktemp -d)
trap 'rm -rf "$TEMP_HOME"' EXIT

OLD_HOME="$HOME"
export HOME="$TEMP_HOME"
export XDG_CONFIG_HOME="$TEMP_HOME/.config"
export XDG_CACHE_HOME="$TEMP_HOME/.cache"

# Run setup (dotfiles only)
if output=$("$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-fonts --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-terminal 2>&1); then
    :
else
    fail "setup.sh dotfiles-only" "Execution failed: $output"
fi

if [ -L "$TEMP_HOME/.zsh-completions" ]; then
    pass "Symlink created: ~/.zsh-completions"
else
    fail "Symlink missing" "Expected ~/.zsh-completions symlink"
fi

if [ -d "$TEMP_HOME/.zsh/completions" ]; then
    pass "Directory created: ~/.zsh/completions"
else
    fail "Directory missing" "Expected ~/.zsh/completions"
fi

# Verify sourcing .zsh-completions with an empty ~/.zsh/completions directory under Zsh NOMATCH
EMPTY_COMP_HOME=$(mktemp -d)
mkdir -p "$EMPTY_COMP_HOME/.zsh/completions"
if zsh -c "setopt NOMATCH; HOME='$EMPTY_COMP_HOME'; compdef() { :; }; source '$SCRIPT_DIR/dotfiles/.zsh-completions'" >/dev/null 2>&1; then
    pass ".zsh-completions handles empty ~/.zsh/completions cleanly under Zsh NOMATCH"
else
    fail ".zsh-completions empty directory" "Failed under Zsh NOMATCH with empty ~/.zsh/completions"
fi
rm -rf "$EMPTY_COMP_HOME"

# Test 3: CLI completion generator with mock CLI
echo -e "\n[3/3] Testing CLI generator with mock CLI..."
MOCK_BIN="$TEMP_HOME/mock_bin"
mkdir -p "$MOCK_BIN"
cat << 'EOF' > "$MOCK_BIN/gh"
#!/bin/sh
if [ "$1" = "completion" ]; then
    echo "# mock gh completion"
    exit 0
fi
EOF
cat << 'EOF' > "$MOCK_BIN/elan"
#!/bin/sh
if [ "$1" = "completions" ] && [ "$2" = "zsh" ]; then
    echo "# mock elan completion"
    exit 0
fi
EOF
chmod +x "$MOCK_BIN/gh" "$MOCK_BIN/elan"

if output=$(PATH="$MOCK_BIN:$PATH" "$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-fonts --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-terminal 2>&1); then
    :
else
    fail "setup.sh completions generation" "Execution failed: $output"
fi

if [ -f "$TEMP_HOME/.zsh/completions/_gh" ] && grep -q "mock gh completion" "$TEMP_HOME/.zsh/completions/_gh" && \
   [ -f "$TEMP_HOME/.zsh/completions/_elan" ] && grep -q "mock elan completion" "$TEMP_HOME/.zsh/completions/_elan"; then
    pass "Generated completions: ~/.zsh/completions/_gh and ~/.zsh/completions/_elan"
else
    fail "CLI completion generation" "Failed to generate ~/.zsh/completions/_gh or _elan"
fi

# Idempotency check
if output=$(PATH="$MOCK_BIN:$PATH" "$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-fonts --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-terminal 2>&1); then
    pass "setup.sh completions are idempotent"
else
    fail "setup.sh idempotency" "Second run failed: $output"
fi

# Atomic completion failure check: failing or empty-output CLI completion must exit non-zero, clean up .tmp file, and preserve existing _gh
cat << 'EOF' > "$MOCK_BIN/gh"
#!/bin/sh
exit 1
EOF
chmod +x "$MOCK_BIN/gh"
if PATH="$MOCK_BIN:$PATH" SKIP_ZSH=true SKIP_BASH=true SKIP_COMPLETIONS=false "$SCRIPT_DIR/modules/60-shell.sh" >/dev/null 2>&1; then
    fail "modules/60-shell.sh failing CLI completion" "Expected non-zero exit when gh completion fails"
else
    tmp_comp_left=("$TEMP_HOME/.zsh/completions"/_gh.tmp.*)
    if [ ! -e "${tmp_comp_left[0]}" ] && [ -s "$TEMP_HOME/.zsh/completions/_gh" ] && grep -q "mock gh completion" "$TEMP_HOME/.zsh/completions/_gh"; then
        pass "modules/60-shell.sh propagates CLI completion failure, removes temporary files, and preserves prior _gh completion"
    else
        fail "modules/60-shell.sh atomic completion cleanup" "Temporary file leaked or prior _gh completion was clobbered"
    fi
fi

cat << 'EOF' > "$MOCK_BIN/gh"
#!/bin/sh
exit 0
EOF
chmod +x "$MOCK_BIN/gh"
if PATH="$MOCK_BIN:$PATH" SKIP_ZSH=true SKIP_BASH=true SKIP_COMPLETIONS=false "$SCRIPT_DIR/modules/60-shell.sh" >/dev/null 2>&1; then
    fail "modules/60-shell.sh zero-byte CLI completion" "Expected non-zero exit when gh completion outputs 0 bytes"
else
    tmp_comp_left=("$TEMP_HOME/.zsh/completions"/_gh.tmp.*)
    if [ ! -e "${tmp_comp_left[0]}" ] && [ -s "$TEMP_HOME/.zsh/completions/_gh" ] && grep -q "mock gh completion" "$TEMP_HOME/.zsh/completions/_gh"; then
        pass "modules/60-shell.sh rejects 0-byte CLI completion output, removes temporary files, and preserves prior _gh completion"
    else
        fail "modules/60-shell.sh zero-byte completion cleanup" "Temporary file leaked or prior _gh completion was clobbered by 0-byte output"
    fi
fi

if grep -Fq "'--plain:" "$SCRIPT_DIR/dotfiles/.zsh-completions" && \
   grep -Fq "'--holiday:" "$SCRIPT_DIR/dotfiles/.zsh-completions"; then
    pass "dotfiles/.zsh-completions registers --plain and --holiday in _theme"
else
    fail "_theme_complete options" "Missing --plain or --holiday in dotfiles/.zsh-completions"
fi

# Test 4: _ide completion registration and dynamic candidate dispatch
MOCK_IDE_HOME="$(mktemp -d)"
mkdir -p "$MOCK_IDE_HOME/.local/bin"
cat << 'EOF' > "$MOCK_IDE_HOME/.local/bin/ide"
#!/bin/sh
if [ "$1" = "--list" ] && [ "$2" = "--plain" ]; then
    printf "alpha-ws\nbeta-ws\n"
    exit 0
fi
exit 0
EOF
chmod +x "$MOCK_IDE_HOME/.local/bin/ide"

cat << 'EOF' > "$MOCK_IDE_HOME/test-ide-comp.zsh"
#!/usr/bin/env zsh
set -euo pipefail
typeset -gA COMP_MAP=()
typeset -ga OFFERED=()
compdef() {
    local fn="$1"
    shift
    local cmd
    for cmd in "$@"; do
        COMP_MAP[$cmd]="$fn"
    done
}
_describe() {
    if [[ "${1:-}" == "-t" ]]; then
        shift 2
    fi
    local arr_name="$2"
    local item
    for item in "${(@P)arr_name}"; do
        OFFERED+=("${item%%:*}")
    done
}
_files() {
    OFFERED+=("_FILES_${*:-any}")
}

source "$1"

for c in ide ide2 ide3 qide idek; do
    [[ "${COMP_MAP[$c]:-}" == "_ide" ]] || { print -u2 "missing compdef for $c"; exit 1; }
done

run_case() {
    OFFERED=()
    words=("$@")
    CURRENT=${#words}
    _ide
    print -r -- "${(j:,:)OFFERED}"
}

out_opts="$(run_case ide --)"
[[ ",$out_opts," == *",--sessions,"* && ",$out_opts," == *",--send,"* && ",$out_opts," == *",--list,"* && ",$out_opts," == *",--next-attention,"* && ",$out_opts," == *",--agent-state,"* && ",$out_opts," != *",--on-bell,"* ]] || { print -u2 "bad opts: $out_opts"; exit 1; }

out_ai="$(run_case ide --ai "")"
[[ "$out_ai" == "agy,claude,codex" ]] || { print -u2 "bad --ai: $out_ai"; exit 1; }

out_swap="$(run_case ide --swap "")"
[[ "$out_swap" == "left,down,up,right" ]] || { print -u2 "bad --swap: $out_swap"; exit 1; }

out_list="$(run_case ide --list "")"
[[ "$out_list" == "--plain" ]] || { print -u2 "bad --list: $out_list"; exit 1; }

out_sess="$(run_case ide -s "")"
[[ "$out_sess" == "alpha-ws,beta-ws" ]] || { print -u2 "bad -s: $out_sess"; exit 1; }

out_next_attn="$(run_case ide --next-attention "")"
[[ "$out_next_attn" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --next-attention: $out_next_attn"; exit 1; }

out_agent_state="$(run_case ide --agent-state "")"
[[ "$out_agent_state" == "running,approval,done,idle" ]] || { print -u2 "bad --agent-state: $out_agent_state"; exit 1; }

out_agent_state_sess="$(run_case ide --agent-state running "")"
[[ "$out_agent_state_sess" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --agent-state sess: $out_agent_state_sess"; exit 1; }

out_quit="$(run_case ide --quit "")"
[[ "$out_quit" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --quit: $out_quit"; exit 1; }

out_qide="$(run_case qide "")"
[[ "$out_qide" == "alpha-ws,beta-ws" ]] || { print -u2 "bad qide: $out_qide"; exit 1; }

out_open="$(run_case ide --open "")"
[[ "$out_open" == "_FILES_any" ]] || { print -u2 "bad --open: $out_open"; exit 1; }

out_preview="$(run_case ide --preview "")"
[[ "$out_preview" == "_FILES_any" ]] || { print -u2 "bad --preview: $out_preview"; exit 1; }

out_open_sess="$(run_case ide --open src/app.py "")"
[[ "$out_open_sess" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --open file sess: $out_open_sess"; exit 1; }

out_open_line_sess="$(run_case ide --open src/app.py 42 "")"
[[ "$out_open_line_sess" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --open file line sess: $out_open_line_sess"; exit 1; }

out_open_plus_sess="$(run_case ide --open src/app.py +42 "")"
[[ "$out_open_plus_sess" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --open file +line sess: $out_open_plus_sess"; exit 1; }

out_preview_line_sess="$(run_case ide --preview src/app.py 42 "")"
[[ "$out_preview_line_sess" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --preview file line sess: $out_preview_line_sess"; exit 1; }

out_preview_plus_sess="$(run_case ide --preview src/app.py +42 "")"
[[ "$out_preview_plus_sess" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --preview file +line sess: $out_preview_plus_sess"; exit 1; }

out_cd="$(run_case ide --cd "")"
[[ "$out_cd" == "_FILES_-/" ]] || { print -u2 "bad --cd: $out_cd"; exit 1; }

out_send_sub="$(run_case ide --send "")"
[[ "$out_send_sub" == "--stdin,--ref,--text,--no-focus" ]] || { print -u2 "bad --send subflags: $out_send_sub"; exit 1; }

out_send_stdin="$(run_case ide --send --stdin "")"
[[ "$out_send_stdin" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --send --stdin: $out_send_stdin"; exit 1; }

out_send_ref="$(run_case ide --send --ref "")"
[[ "$out_send_ref" == "_FILES_any" ]] || { print -u2 "bad --send --ref: $out_send_ref"; exit 1; }

out_send_ref_sess="$(run_case ide --send --ref src/app.py "")"
[[ "$out_send_ref_sess" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --send --ref sess: $out_send_ref_sess"; exit 1; }

out_send_text_val="$(run_case ide --send --text "")"
[[ "$out_send_text_val" == "" ]] || { print -u2 "bad --send --text arg: $out_send_text_val"; exit 1; }

out_send_text_sess="$(run_case ide --send --text "hello" "")"
[[ "$out_send_text_sess" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --send --text sess: $out_send_text_sess"; exit 1; }

out_root="$(run_case ide "")"
[[ ",$out_root," == *",cd,"* && ",$out_root," == *",quit,"* && ",$out_root," == *",alpha-ws,"* && ",$out_root," == *",_FILES_-/,"* ]] || { print -u2 "bad root: $out_root"; exit 1; }
EOF

if ide_comp_err="$(HOME="$MOCK_IDE_HOME" zsh "$MOCK_IDE_HOME/test-ide-comp.zsh" "$SCRIPT_DIR/dotfiles/.zsh-completions" 2>&1)"; then
    pass "_ide Zsh completion registers ide/ide2/ide3/qide/idek and completes flags, --ai, --swap, --list --plain, --open/--preview [line] [session], --send subflags, file/dir paths, and live IDE sessions"
else
    fail "_ide Zsh completion" "Unexpected _ide completion behavior: $ide_comp_err"
fi
rm -rf "$MOCK_IDE_HOME"

export HOME="$OLD_HOME"

test_summary
