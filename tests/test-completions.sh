#!/usr/bin/env bash
# Test suite for Zsh completions (dotfiles/.zsh-completions, setup.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/tests/test-helper.sh"

ZSH_BIN="$(_hs_find_bin zsh)"
[ -z "$ZSH_BIN" ] && ZSH_BIN="zsh"

echo "========================================"
echo "Running Completions Setup Tests"
echo "========================================"

# Test 1: Syntax validation
echo -e "\n[1/3] Checking completion syntax..."
for zf in "$SCRIPT_DIR/dotfiles/.zsh-completions" "$SCRIPT_DIR/dotfiles/.config/shell/completions-ide.zsh" "$SCRIPT_DIR/dotfiles/.config/shell/completions-terraform.zsh" "$SCRIPT_DIR/dotfiles/.config/shell/terraform-flags.sh"; do
    if zsh -n "$zf"; then
        pass "Syntax valid (zsh): $(basename "$zf")"
    else
        fail "Syntax check failed (zsh): $(basename "$zf")" "zsh -n returned non-zero"
    fi
done
for bf in "$SCRIPT_DIR/dotfiles/.config/shell/terraform-flags.sh" "$SCRIPT_DIR/dotfiles/.config/shell/bash-completions.sh"; do
    if bash -n "$bf"; then
        pass "Syntax valid (bash): $(basename "$bf")"
    else
        fail "Syntax check failed (bash): $(basename "$bf")" "bash -n returned non-zero"
    fi
done

# Test 2: Execution in temporary environment
echo -e "\n[2/3] Testing dotfiles installation..."
TEMP_HOME=$(mktemp -d)
trap 'rm -rf "$TEMP_HOME"; _hs_cleanup_test_runtime_dir' EXIT

OLD_HOME="$HOME"
OLD_XDG_DATA_HOME="${XDG_DATA_HOME:-}"
OLD_ELAN_HOME="${ELAN_HOME:-}"
export HOME="$TEMP_HOME"
export XDG_CONFIG_HOME="$TEMP_HOME/.config"
export XDG_CACHE_HOME="$TEMP_HOME/.cache"
export XDG_DATA_HOME="$TEMP_HOME/.local/share"
unset ELAN_HOME

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
if zsh -f -c "setopt NOMATCH; HOME='$EMPTY_COMP_HOME'; compdef() { :; }; source '$SCRIPT_DIR/dotfiles/.zsh-completions'" >/dev/null 2>&1; then
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
if PATH="$MOCK_BIN:$PATH" SKIP_ZSH=true SKIP_BASH=true SKIP_COMPLETIONS=false "$SCRIPT_DIR/setup/modules/60-shell.sh" >/dev/null 2>&1; then
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
if PATH="$MOCK_BIN:$PATH" SKIP_ZSH=true SKIP_BASH=true SKIP_COMPLETIONS=false "$SCRIPT_DIR/setup/modules/60-shell.sh" >/dev/null 2>&1; then
    fail "modules/60-shell.sh zero-byte CLI completion" "Expected non-zero exit when gh completion outputs 0 bytes"
else
    tmp_comp_left=("$TEMP_HOME/.zsh/completions"/_gh.tmp.*)
    if [ ! -e "${tmp_comp_left[0]}" ] && [ -s "$TEMP_HOME/.zsh/completions/_gh" ] && grep -q "mock gh completion" "$TEMP_HOME/.zsh/completions/_gh"; then
        pass "modules/60-shell.sh rejects 0-byte CLI completion output, removes temporary files, and preserves prior _gh completion"
    else
        fail "modules/60-shell.sh zero-byte completion cleanup" "Temporary file leaked or prior _gh completion was clobbered by 0-byte output"
    fi
fi

# Verify setup.sh PATH handoff (${XDG_DATA_HOME}/mise/shims & ${ELAN_HOME}/bin), all Mise CLI completions,
# Zsh _delta override of built-in _sccs, and --skip-tools resilience against older distro binaries
SHIMS_HOME="$(mktemp -d)"
SHIMS_DIR="$SHIMS_HOME/.local/share/mise/shims"
ELAN_BIN_DIR="$SHIMS_HOME/.local/share/elan/bin"
mkdir -p "$SHIMS_DIR" "$ELAN_BIN_DIR"
cat << 'EOF' > "$ELAN_BIN_DIR/elan"
#!/bin/sh
[ "$1" = "completions" ] && [ "$2" = "zsh" ] && printf '#compdef elan\n# shim elan\n'
EOF
cat << 'EOF' > "$SHIMS_DIR/mise"
#!/bin/sh
[ "$1" = "completion" ] && [ "$2" = "zsh" ] && printf '#compdef mise\n_mise() { :; }\n'
EOF
cat << 'EOF' > "$SHIMS_DIR/delta"
#!/bin/sh
[ "$1" = "--generate-completion" ] && [ "$2" = "zsh" ] && printf '#compdef delta\n_delta() { :; }\ncompdef _delta delta\n'
EOF
cat << 'EOF' > "$SHIMS_DIR/bat"
#!/bin/sh
if [ "${1:-}" = "--completion" ] && [ "${2:-}" = "zsh" ]; then
    printf '#compdef bat\n_bat() { :; }\n'
    exit 0
fi
exit 0
EOF
cat << 'EOF' > "$SHIMS_DIR/yq"
#!/bin/sh
[ "$1" = "shell-completion" ] && [ "$2" = "zsh" ] && printf '#compdef yq\n_yq() { :; }\n'
EOF
cat << 'EOF' > "$SHIMS_DIR/glow"
#!/bin/sh
[ "$1" = "completion" ] && [ "$2" = "zsh" ] && printf '#compdef glow\n_glow() { :; }\n'
EOF
cat << 'EOF' > "$SHIMS_DIR/rustup"
#!/bin/sh
if [ "$1" = "completions" ] && [ "$2" = "zsh" ]; then
    if [ "${3:-}" = "cargo" ]; then
        printf '#compdef cargo\n_cargo() { :; }\n'
    else
        printf '#compdef rustup\n_rustup() { :; }\n'
    fi
fi
EOF
cat << 'EOF' > "$SHIMS_DIR/cargo"
#!/bin/sh
exit 0
EOF
cat << 'EOF' > "$SHIMS_DIR/tree-sitter"
#!/bin/sh
[ "$1" = "complete" ] && [ "$2" = "--shell" ] && [ "$3" = "zsh" ] && printf '#compdef tree-sitter\n_tree-sitter() { :; }\n'
EOF
chmod +x "$ELAN_BIN_DIR/elan" "$SHIMS_DIR"/*

if shims_out=$(env -u ELAN_HOME HOME="$SHIMS_HOME" XDG_CONFIG_HOME="$SHIMS_HOME/.config" XDG_CACHE_HOME="$SHIMS_HOME/.cache" XDG_DATA_HOME="$SHIMS_HOME/.local/share" PATH="/usr/bin:/bin" "$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-fonts --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-terminal 2>&1); then
    missing_comp=""
    for expected_comp in _elan _mise _delta _bat _yq _glow _rustup _cargo _tree-sitter; do
        if [ ! -s "$SHIMS_HOME/.zsh/completions/$expected_comp" ]; then
            missing_comp="$expected_comp"
            break
        fi
    done
    delta_binding="$(HOME="$SHIMS_HOME" zsh -f -c 'autoload -Uz compinit && compinit -u -d "$HOME/.zcompdump"; source "'"$SCRIPT_DIR"'/dotfiles/.zsh-completions"; print -r -- "${_comps[delta]:-none}|${_comps[tree-sitter]:-none}"' 2>/dev/null || true)"
    if [ -z "$missing_comp" ] && [ "$delta_binding" = "_delta|_tree-sitter" ]; then
        pass "setup.sh hands off mise/shims and elan/bin on PATH to 60-shell.sh, generates _elan/_mise/_delta/_bat/_yq/_glow/_rustup/_cargo/_tree-sitter, and overrides Zsh _sccs with _delta"
    else
        fail "Mise CLI completions & _delta override" "missing='$missing_comp' delta_binding='$delta_binding'"
    fi
else
    fail "setup.sh shims PATH handoff" "Execution failed: $shims_out"
fi

# Now simulate older distro bat (no --completion), Python yq (no shell-completion), SCCS delta (non-# output), untrusted/missing gh & elan shims (exit 1), and rustc shim without rustup under --skip-tools
rm -f "$SHIMS_DIR/rustup"
rustc_marker="$SHIMS_HOME/rustc_auto_install_leaked"
printf '#!/bin/sh\n[ "${MISE_NOT_FOUND_AUTO_INSTALL:-}" = "false" ] || : > "%s"\nexit 1\n' "$rustc_marker" > "$SHIMS_DIR/rustc"
printf '#!/bin/sh\n[ "${1:-}" = "cache" ] && exit 0\necho "error: unexpected argument --completion" >&2\nexit 2\n' > "$SHIMS_DIR/bat"
printf '#!/bin/sh\necho "yq: error: unrecognized arguments: shell-completion" >&2\nexit 2\n' > "$SHIMS_DIR/yq"
printf '#!/bin/sh\necho "Usage: sccs delta"\nexit 0\n' > "$SHIMS_DIR/delta"
printf '#!/bin/sh\necho "mise ERROR Config files are not trusted" >&2\nexit 1\n' > "$SHIMS_DIR/gh"
printf '#!/bin/sh\necho "mise ERROR No version is set for shim: elan" >&2\nexit 1\n' > "$ELAN_BIN_DIR/elan"
chmod +x "$SHIMS_DIR/rustc" "$SHIMS_DIR/bat" "$SHIMS_DIR/yq" "$SHIMS_DIR/delta" "$SHIMS_DIR/gh" "$ELAN_BIN_DIR/elan"
if skip_tools_out=$(env -u ELAN_HOME HOME="$SHIMS_HOME" XDG_CONFIG_HOME="$SHIMS_HOME/.config" XDG_CACHE_HOME="$SHIMS_HOME/.cache" XDG_DATA_HOME="$SHIMS_HOME/.local/share" PATH="/usr/bin:/bin" "$SCRIPT_DIR/setup.sh" --dotfiles-only --skip-fonts --skip-tools --skip-vim --skip-nvim --skip-zsh --skip-terminal 2>&1); then
    leftover_tmp=("$SHIMS_HOME/.zsh/completions"/*.tmp.*)
    if [ ! -e "${leftover_tmp[0]}" ] && [ ! -e "$rustc_marker" ] && grep -Fq "_bat()" "$SHIMS_HOME/.zsh/completions/_bat" && grep -Fq "_yq()" "$SHIMS_HOME/.zsh/completions/_yq" && grep -Fq "_delta()" "$SHIMS_HOME/.zsh/completions/_delta" && grep -Fq "shim elan" "$SHIMS_HOME/.zsh/completions/_elan" && grep -Fq "_cargo()" "$SHIMS_HOME/.zsh/completions/_cargo"; then
        pass "modules/60-shell.sh under --skip-tools tolerates older distro bat/yq, non-completion stdout, and failing gh/elan/rustc shims (with MISE_NOT_FOUND_AUTO_INSTALL=false) without aborting or clobbering prior completions"
    else
        fail "modules/60-shell.sh --skip-tools preservation" "Temporary file leaked, rustc lacked MISE_NOT_FOUND_AUTO_INSTALL=false, or prior _bat/_yq/_delta/_elan/_cargo completion was clobbered"
    fi
else
    fail "modules/60-shell.sh --skip-tools distro fallback" "Expected exit 0 under --skip-tools with older distro binaries and failing shims, got: $skip_tools_out"
fi
rm -rf "$SHIMS_HOME"

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
zmodload zsh/complete 2>/dev/null || true
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
    local item unesc
    for item in "${(@P)arr_name}"; do
        unesc="${item//\\:/__HS_COLON__}"
        unesc="${unesc%%:*}"
        OFFERED+=("${unesc//__HS_COLON__/:}")
    done
}
_files() {
    OFFERED+=("_FILES_${*:-any}")
}

source "$1"

for c in ide ide2 ide3 qide idek quit; do
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
[[ ",$out_opts," == *",--new,"* && ",$out_opts," == *",-n,"* && ",$out_opts," == *",--sessions,"* && ",$out_opts," == *",--send,"* && ",$out_opts," == *",--list,"* && ",$out_opts," == *",--next-attention,"* && ",$out_opts," == *",--agent-state,"* && ",$out_opts," == *",--message,"* && ",$out_opts," == *",--ack-ai,"* && ",$out_opts," == *",--open-pr,"* && ",$out_opts," == *",--switch,"* && ",$out_opts," != *",--on-bell,"* ]] || { print -u2 "bad opts: $out_opts"; exit 1; }

out_new_pos="$(run_case ide -n "")"
[[ "$out_new_pos" == "" ]] || { print -u2 "bad -n pos: $out_new_pos"; exit 1; }

out_new_long_pos="$(run_case ide --new "")"
[[ "$out_new_long_pos" == "" ]] || { print -u2 "bad --new pos: $out_new_long_pos"; exit 1; }

out_new_flags="$(run_case ide -n --)"
[[ ",$out_new_flags," == *",--2pane,"* && ",$out_new_flags," == *",--ai,"* ]] || { print -u2 "bad -n flags: $out_new_flags"; exit 1; }

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
[[ "$out_agent_state" == "running,approval,quota,done,idle" ]] || { print -u2 "bad --agent-state: $out_agent_state"; exit 1; }

out_agent_state_eq="$(run_case ide --agent-state=)"
[[ "$out_agent_state_eq" == "running,approval,quota,done,idle" ]] || { print -u2 "bad --agent-state=: $out_agent_state_eq"; exit 1; }

out_agent_state_sess="$(run_case ide --agent-state quota "")"
[[ "$out_agent_state_sess" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --agent-state sess: $out_agent_state_sess"; exit 1; }

out_agent_msg_val="$(run_case ide --agent-state done --message "")"
[[ "$out_agent_msg_val" == "" ]] || { print -u2 "bad --agent-state --message val: $out_agent_msg_val"; exit 1; }

out_agent_msg_sess="$(run_case ide --agent-state done --message "all green" "")"
[[ "$out_agent_msg_sess" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --agent-state --message sess: $out_agent_msg_sess"; exit 1; }

out_ack_ai="$(run_case ide --ack-ai "")"
[[ "$out_ack_ai" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --ack-ai: $out_ack_ai"; exit 1; }

out_ack_ai_multi="$(run_case ide --ack-ai alpha-ws "")"
[[ "$out_ack_ai_multi" == "beta-ws" ]] || { print -u2 "bad --ack-ai multi: $out_ack_ai_multi"; exit 1; }

out_open_pr="$(run_case ide --open-pr "")"
[[ "$out_open_pr" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --open-pr: $out_open_pr"; exit 1; }

out_quit="$(run_case ide --quit "")"
[[ "$out_quit" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --quit: $out_quit"; exit 1; }

out_quit_multi="$(run_case ide --quit alpha-ws "")"
[[ "$out_quit_multi" == "beta-ws" ]] || { print -u2 "bad --quit multi: $out_quit_multi"; exit 1; }

out_sub_quit_multi="$(run_case ide quit alpha-ws "")"
[[ "$out_sub_quit_multi" == "beta-ws" ]] || { print -u2 "bad ide quit multi: $out_sub_quit_multi"; exit 1; }

out_sub_kill_multi="$(run_case ide kill alpha-ws "")"
[[ "$out_sub_kill_multi" == "beta-ws" ]] || { print -u2 "bad ide kill multi: $out_sub_kill_multi"; exit 1; }

out_qide="$(run_case qide "")"
[[ "$out_qide" == "alpha-ws,beta-ws" ]] || { print -u2 "bad qide: $out_qide"; exit 1; }

out_quit_alias="$(run_case quit "")"
[[ "$out_quit_alias" == "alpha-ws,beta-ws" ]] || { print -u2 "bad quit alias: $out_quit_alias"; exit 1; }

out_quit_alias_multi="$(run_case quit alpha-ws "")"
[[ "$out_quit_alias_multi" == "beta-ws" ]] || { print -u2 "bad quit alias multi: $out_quit_alias_multi"; exit 1; }

out_idek_multi="$(run_case idek alpha-ws "")"
[[ "$out_idek_multi" == "beta-ws" ]] || { print -u2 "bad idek multi: $out_idek_multi"; exit 1; }

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
[[ "$out_send_sub" == "--stdin,--ref,--text,--no-focus,--switch" ]] || { print -u2 "bad --send subflags: $out_send_sub"; exit 1; }

out_send_switch_sess="$(run_case ide --send --switch --ref src/app.py "")"
[[ "$out_send_switch_sess" == "alpha-ws,beta-ws" ]] || { print -u2 "bad --send --switch --ref sess: $out_send_switch_sess"; exit 1; }

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
[[ ",$out_root," == *",cd,"* && ",$out_root," == *",quit,"* && ",$out_root," == *",kill,"* && ",$out_root," == *",alpha-ws,"* && ",$out_root," == *",_FILES_-/,"* ]] || { print -u2 "bad root: $out_root"; exit 1; }

mkdir -p "$HOME/.config/ide" "$HOME/ext1/gamma-ext" "$HOME/ext1/alpha-ws" "$HOME/ext1/colon:ws" "$HOME/ext1/space ws" "$HOME/ext2/delta-ext"
touch "$HOME/ext2/not-a-dir.txt"
WS_HOOK_LOG="$HOME/ws_hook.log"
cat <<HOOK > "$HOME/.config/ide/links.sh"
ide_workspace_dirs() {
    printf '1\n' >> "$WS_HOOK_LOG"
    printf '%s\n' "$HOME/ext1/gamma-ext" "$HOME/ext1/alpha-ws" "$HOME/ext1/colon:ws" "$HOME/ext1/space ws" "$HOME/ext1/dead-ext"
}
HOOK
export IDE_WORKSPACE_DIRS="$HOME/ext2/delta-ext:$HOME/ext2/missing-ext:$HOME/ext2/not-a-dir.txt"

rm -f "$WS_HOOK_LOG"
out_ws_flag="$(run_case ide --)"
out_ws_qide="$(run_case qide "")"
out_ws_quit="$(run_case quit "")"
out_ws_idek="$(run_case idek "")"
out_ws_sess="$(run_case ide -s "")"
out_ws_sess2="$(run_case ide -s alpha-ws "")"
out_ws_pr="$(run_case ide --open-pr "")"
out_ws_new="$(run_case ide -n "")"
out_ws_keys="$(run_case ide --keys "")"
out_ws_mon="$(run_case ide --monitor "")"
out_ws_lplain="$(run_case ide --list --plain "")"
out_ws_cd3="$(run_case ide cd subdir "")"
out_ws_after_pos="$(run_case ide alpha-ws "")"
out_ws_slash="$(run_case ide sub/path)"
out_ws_dot="$(run_case ide ./sub)"
[[ ! -s "$WS_HOOK_LOG" ]] || { print -u2 "ide_workspace_dirs invoked eagerly outside launch-target position"; exit 1; }
for non_launch in "$out_ws_qide" "$out_ws_quit" "$out_ws_idek" "$out_ws_sess" "$out_ws_sess2" "$out_ws_pr" "$out_ws_new" "$out_ws_keys" "$out_ws_mon" "$out_ws_lplain" "$out_ws_cd3" "$out_ws_after_pos" "$out_ws_slash" "$out_ws_dot"; do
    [[ ",$non_launch," != *",gamma-ext,"* && ",$non_launch," != *",delta-ext,"* ]] || { print -u2 "workspace leaked into non-launch completion: $non_launch"; exit 1; }
done
[[ "$out_ws_keys" == "" && "$out_ws_mon" == "" && "$out_ws_lplain" == "" && "$out_ws_after_pos" == "" && "$out_ws_cd3" == "alpha-ws,beta-ws" ]] || { print -u2 "bad non-launch completion outputs: keys=$out_ws_keys mon=$out_ws_mon lplain=$out_ws_lplain after=$out_ws_after_pos cd3=$out_ws_cd3"; exit 1; }

out_ws_ide="$(run_case ide "")"
[[ -s "$WS_HOOK_LOG" ]] || { print -u2 "ide_workspace_dirs not invoked at ide launch position"; exit 1; }
[[ ",$out_ws_ide," == *",gamma-ext,"* && ",$out_ws_ide," == *",delta-ext,"* && ",$out_ws_ide," == *",colon:ws,"* && ",$out_ws_ide," == *",space ws,"* && ",$out_ws_ide," != *",dead-ext,"* && ",$out_ws_ide," != *",missing-ext,"* && ",$out_ws_ide," != *",not-a-dir.txt,"* ]] || { print -u2 "bad ide ws launch completion: $out_ws_ide"; exit 1; }
alpha_cnt=0
for tok in ${(s:,:)out_ws_ide}; do
    [[ "$tok" == "alpha-ws" ]] && (( alpha_cnt++ )) || true
done
(( alpha_cnt == 1 )) || { print -u2 "alpha-ws not deduplicated ($alpha_cnt): $out_ws_ide"; exit 1; }

out_ws_ide2="$(run_case ide2 "")"
[[ ",$out_ws_ide2," == *",gamma-ext,"* && ",$out_ws_ide2," == *",delta-ext,"* && ",$out_ws_ide2," != *",quit,"* ]] || { print -u2 "bad ide2 ws launch completion: $out_ws_ide2"; exit 1; }

out_ws_ide3="$(run_case ide3 "")"
[[ ",$out_ws_ide3," == *",gamma-ext,"* && ",$out_ws_ide3," == *",delta-ext,"* ]] || { print -u2 "bad ide3 ws launch completion: $out_ws_ide3"; exit 1; }

out_ws_2p="$(run_case ide --2pane "")"
[[ ",$out_ws_2p," == *",gamma-ext,"* && ",$out_ws_2p," == *",delta-ext,"* ]] || { print -u2 "bad ide --2pane ws launch completion: $out_ws_2p"; exit 1; }
EOF

if ide_comp_err="$(HOME="$MOCK_IDE_HOME" XDG_CONFIG_HOME="$MOCK_IDE_HOME/.config" zsh -f "$MOCK_IDE_HOME/test-ide-comp.zsh" "$SCRIPT_DIR/dotfiles/.zsh-completions" 2>&1)" && [ -z "$ide_comp_err" ]; then
    pass "_ide Zsh completion registers ide/ide2/ide3/qide/idek/quit and completes -n/--new, flags, --ai, --swap, --list --plain, --open/--preview [line] [session], --send subflags, file/dir paths, live IDE sessions, and lazy ide_workspace_dirs / IDE_WORKSPACE_DIRS basenames strictly at launch positions"
else
    fail "_ide Zsh completion" "Unexpected _ide completion behavior: $ide_comp_err"
fi
rm -rf "$MOCK_IDE_HOME"

# Test 5: _terraform Zsh completion registration for `terraform` and `tf`
MOCK_TF_HOME="$(mktemp -d)"
mkdir -p "$MOCK_TF_HOME/bin"
cat << 'EOF' > "$MOCK_TF_HOME/bin/terraform"
#!/bin/sh
case "${COMP_LINE:-}" in
    "terraform ")
        printf "init\nplan\napply\nstate\nworkspace\n-chdir=\n"
        ;;
    "terraform pl")
        printf "plan\n"
        ;;
    "terraform state ")
        printf "list\nmv\nrm\nshow\n"
        ;;
    "terraform init -")
        printf "%s\n" "-upgrade" "-reconfigure" "-backend="
        ;;
    "terraform init -backend=")
        printf "true\nfalse\n"
        ;;
    "terraform init -backend=f")
        printf "false\n"
        ;;
esac
EOF
chmod +x "$MOCK_TF_HOME/bin/terraform"
mkdir -p "$MOCK_TF_HOME/broken_bin"
cat << 'EOF' > "$MOCK_TF_HOME/broken_bin/terraform"
#!/bin/sh
[ "${MISE_NOT_FOUND_AUTO_INSTALL:-}" = "false" ] || exit 99
exit 1
EOF
chmod +x "$MOCK_TF_HOME/broken_bin/terraform"

cat << 'EOF' > "$MOCK_TF_HOME/test-tf-comp.zsh"
#!/usr/bin/env zsh
set -euo pipefail
zmodload zsh/complete 2>/dev/null || true
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
    local item unesc
    for item in "${(@P)arr_name}"; do
        unesc="${item//\\:/__HS_COLON__}"
        unesc="${unesc%%:*}"
        OFFERED+=("${unesc//__HS_COLON__/:}")
    done
}
_files() {
    OFFERED+=("_FILES_${*:-any}")
}

source "$1"

for c in terraform tf; do
    [[ "${COMP_MAP[$c]:-}" == "_terraform" ]] || { print -u2 "missing compdef for $c"; exit 1; }
done

run_tf() {
    OFFERED=()
    words=("$@")
    CURRENT=${#words}
    _terraform
    print -r -- "${(j:,:)OFFERED}"
}

out_root="$(run_tf terraform "")"
[[ ",$out_root," == *",init,"* && ",$out_root," == *",plan,"* && ",$out_root," == *",-chdir=,"* ]] || { print -u2 "bad terraform root: $out_root"; exit 1; }

out_tf_pl="$(run_tf tf pl)"
[[ "$out_tf_pl" == "plan" ]] || { print -u2 "bad tf pl: $out_tf_pl"; exit 1; }

out_tf_state="$(run_tf tf state "")"
[[ "$out_tf_state" == "list,mv,rm,show" ]] || { print -u2 "bad tf state: $out_tf_state"; exit 1; }

out_init_flags="$(run_tf terraform init -)"
[[ ",$out_init_flags," == *",-upgrade,"* && ",$out_init_flags," == *",-backend=,"* ]] || { print -u2 "bad init flags: $out_init_flags"; exit 1; }

out_backend_eq="$(run_tf tf init -backend=)"
[[ "$out_backend_eq" == "true,false" ]] || { print -u2 "bad init -backend=: $out_backend_eq"; exit 1; }

out_backend_f="$(run_tf tf init -backend=f)"
[[ "$out_backend_f" == "false" ]] || { print -u2 "bad init -backend=f: $out_backend_f"; exit 1; }

out_chdir="$(run_tf tf -chdir=infra)"
[[ "$out_chdir" == "_FILES_-/" ]] || { print -u2 "bad -chdir=: $out_chdir"; exit 1; }

out_plugindir_sp="$(run_tf tf init -plugin-dir "")"
[[ "$out_plugindir_sp" == "_FILES_-/" ]] || { print -u2 "bad -plugin-dir space: $out_plugindir_sp"; exit 1; }

out_varfile="$(run_tf terraform plan -var-file=prod.tfvars)"
[[ "$out_varfile" == "_FILES_any" ]] || { print -u2 "bad -var-file=: $out_varfile"; exit 1; }

out_varfile_sp="$(run_tf terraform plan -var-file "")"
[[ "$out_varfile_sp" == "_FILES_any" ]] || { print -u2 "bad -var-file space: $out_varfile_sp"; exit 1; }

out_pos_file="$(run_tf terraform apply "")"
[[ "$out_pos_file" == "_FILES_any" ]] || { print -u2 "bad apply file fallback: $out_pos_file"; exit 1; }

# Subcommands where Terraform's built-in posener/complete returns empty output
out_plan_flags="$(run_tf tf plan -)"
[[ ",$out_plan_flags," == *",-out=,"* && ",$out_plan_flags," == *",-destroy,"* && ",$out_plan_flags," == *",-detailed-exitcode,"* && ",$out_plan_flags," == *",-var-file=,"* ]] || { print -u2 "bad plan flags: $out_plan_flags"; exit 1; }

out_plan_o="$(run_tf tf plan -o)"
[[ "$out_plan_o" == "-out=" ]] || { print -u2 "bad tf plan -o: $out_plan_o"; exit 1; }

out_chdir_plan_o="$(run_tf tf -chdir=envs/prod plan -o)"
[[ "$out_chdir_plan_o" == "-out=" ]] || { print -u2 "bad tf -chdir=... plan -o: $out_chdir_plan_o"; exit 1; }

out_apply_auto="$(run_tf tf apply -auto)"
[[ "$out_apply_auto" == "-auto-approve" ]] || { print -u2 "bad tf apply -auto: $out_apply_auto"; exit 1; }

out_destroy_auto="$(run_tf tf destroy -auto)"
[[ "$out_destroy_auto" == "-auto-approve" ]] || { print -u2 "bad tf destroy -auto: $out_destroy_auto"; exit 1; }

out_fmt_flags="$(run_tf tf fmt -)"
[[ ",$out_fmt_flags," == *",-check,"* && ",$out_fmt_flags," == *",-diff,"* && ",$out_fmt_flags," == *",-recursive,"* && ",$out_fmt_flags," == *",-write=,"* ]] || { print -u2 "bad fmt flags: $out_fmt_flags"; exit 1; }

out_validate_flags="$(run_tf tf validate -)"
[[ ",$out_validate_flags," == *",-json,"* && ",$out_validate_flags," == *",-no-color,"* && ",$out_validate_flags," == *",-no-tests,"* ]] || { print -u2 "bad validate flags: $out_validate_flags"; exit 1; }

out_state_mv_d="$(run_tf tf state mv -d)"
[[ "$out_state_mv_d" == "-dry-run" ]] || { print -u2 "bad tf state mv -d: $out_state_mv_d"; exit 1; }

out_ws_sel_o="$(run_tf tf workspace select -o)"
[[ "$out_ws_sel_o" == "-or-create=" ]] || { print -u2 "bad tf workspace select -o: $out_ws_sel_o"; exit 1; }

out_plan_lock_f="$(run_tf tf plan -lock=f)"
[[ "$out_plan_lock_f" == "false" ]] || { print -u2 "bad tf plan -lock=f: $out_plan_lock_f"; exit 1; }

out_mirror_lockfile_f="$(run_tf tf providers mirror -lock-file=f)"
[[ "$out_mirror_lockfile_f" == "false" ]] || { print -u2 "bad tf providers mirror -lock-file=f: $out_mirror_lockfile_f"; exit 1; }

out_schema_var="$(run_tf tf providers schema -var-)"
[[ "$out_schema_var" == "-var-file=" ]] || { print -u2 "bad tf providers schema -var-: $out_schema_var"; exit 1; }

out_prov_dir_flag="$(run_tf tf providers envs/prod -t)"
[[ "$out_prov_dir_flag" == "-test-directory=" ]] || { print -u2 "bad tf providers dir -t: $out_prov_dir_flag"; exit 1; }

mkdir -p "$HOME/envs/prod"
out_chdir_varfile="$(run_tf tf -chdir="$HOME/envs/prod" plan -var-file=prod.tfvars)"
[[ "$out_chdir_varfile" == "_FILES_-W ${HOME:a}/envs/prod" ]] || { print -u2 "bad tf -chdir=... -var-file=: $out_chdir_varfile"; exit 1; }

out_global_c="$(run_tf tf -c)"
[[ "$out_global_c" == "-chdir=" ]] || { print -u2 "bad tf -c: $out_global_c"; exit 1; }

out_ddash="$(run_tf tf plan -- -o)"
[[ "$out_ddash" == "_FILES_any" ]] || { print -u2 "bad tf plan -- -o: $out_ddash"; exit 1; }

# Verify GLOB_SUBST safety when cur contains pattern metacharacters
setopt localoptions GLOB_SUBST
out_glob_subst="$(run_tf tf plan '-[')"
[[ -z "$out_glob_subst" ]] || { print -u2 "bad GLOB_SUBST tf plan -[: $out_glob_subst"; exit 1; }
unsetopt GLOB_SUBST

# Verify static fallback when terraform shim fails (exit 1) or binary is absent from PATH
PATH="$HOME/broken_bin:/usr/bin:/bin"
out_broken_shim="$(run_tf tf pl)"
[[ "$out_broken_shim" == "plan" ]] || { print -u2 "bad static fallback with broken shim: $out_broken_shim"; exit 1; }
out_broken_plan_o="$(run_tf tf plan -o)"
[[ "$out_broken_plan_o" == "-out=" ]] || { print -u2 "bad broken-shim tf plan -o: $out_broken_plan_o"; exit 1; }

PATH="/usr/bin:/bin"
out_no_bin="$(run_tf tf pl)"
[[ "$out_no_bin" == "plan" ]] || { print -u2 "bad static fallback without binary: $out_no_bin"; exit 1; }
out_no_bin_apply="$(run_tf tf apply -auto)"
[[ "$out_no_bin_apply" == "-auto-approve" ]] || { print -u2 "bad binary-absent tf apply -auto: $out_no_bin_apply"; exit 1; }
out_no_bin_state="$(run_tf tf state "")"
[[ ",$out_no_bin_state," == *",list,"* && ",$out_no_bin_state," == *",mv,"* ]] || { print -u2 "bad binary-absent tf state: $out_no_bin_state"; exit 1; }
out_no_bin_stacks="$(run_tf tf stacks "")"
[[ ",$out_no_bin_stacks," == *",init,"* && ",$out_no_bin_stacks," == *",providers-lock,"* ]] || { print -u2 "bad binary-absent tf stacks: $out_no_bin_stacks"; exit 1; }
EOF

tf_zsh_pty="ok"
if command -v python3 >/dev/null 2>&1; then
    tf_zsh_pty="$(MOCK_TF_HOME="$MOCK_TF_HOME" ZSH_BIN="$ZSH_BIN" ZSH_COMP_FILE="$SCRIPT_DIR/dotfiles/.zsh-completions" python3 - <<'PY'
import fcntl, os, pty, re, select, struct, subprocess, termios, time

home = os.environ["MOCK_TF_HOME"]
zcomp = os.environ["ZSH_COMP_FILE"]
os.makedirs(os.path.join(home, "my dir"), exist_ok=True)
os.makedirs(os.path.join(home, "dir=1/sub"), exist_ok=True)
open(os.path.join(home, "dir=1/main.tf"), "w").close()
os.makedirs(os.path.join(home, "envs/prod/vars_sub"), exist_ok=True)
open(os.path.join(home, "envs/prod/prod vars.tfvars"), "w").close()
os.makedirs(os.path.join(home, ".local/bin"), exist_ok=True)
ide_mock = os.path.join(home, ".local/bin/ide")
with open(ide_mock, "w", encoding="utf-8") as fh:
    fh.write('#!/bin/sh\nif [ "${1:-}" = "--list" ] && [ "${2:-}" = "--plain" ]; then\n    printf "alpha-ws\\nbeta-ws\\n"\nfi\n')
os.chmod(ide_mock, 0o755)

# Simulate Oh-My-Zsh plugins/terraform autoloaded completion + matcher-list prior to sourcing .zsh-completions
omz_tf_dir = os.path.join(home, "omz_tf")
os.makedirs(omz_tf_dir, exist_ok=True)
with open(os.path.join(omz_tf_dir, "_terraform"), "w", encoding="utf-8") as fh:
    fh.write("#compdef terraform\n_terraform() { compadd -- STALE_OMZ; }\n")

zshrc = os.path.join(home, ".zshrc")
with open(zshrc, "w", encoding="utf-8") as fh:
    fh.write(
        f"unsetopt PROMPT_SP\n"
        f"PROMPT='READY> '\n"
        f"bindkey -e\n"
        f"fpath=({omz_tf_dir!r} $fpath)\n"
        f"autoload -Uz compinit && compinit -u -d '{home}/.zcompdump'\n"
        f"zstyle ':completion:*' matcher-list 'm:{{a-zA-Z}}={{A-Za-z}}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'\n"
        f"alias tf=terraform\n"
        f"alias tfp='terraform plan'\n"
        f"source {zcomp!r}\n"
    )

env = {
    "HOME": home,
    "ZDOTDIR": home,
    "PATH": f"{home}/.local/bin:{home}/bin:/usr/bin:/bin",
    "TERM": "xterm-256color",
}
checks = [
    ("tf init -backend=f\t", "tf init -backend=false {m}"),
    ("tf -chdir=my\t", "tf -chdir=my\\ dir/{m}"),
    ("tf -chdir=dir=1/\t", "tf -chdir=dir=1/sub/{m}"),
    ("tf plan -out=dir=1/ma\t", "tf plan -out=dir=1/main.tf {m}"),
    ("tf plan -o\t", "tf plan -out={m}"),
    ("tf apply -auto\t", "tf apply -auto-approve {m}"),
    ("tf apply -AUTO\t", "tf apply -auto-approve {m}"),
    ("tf apply -approve\t", "tf apply -auto-approve {m}"),
    ("tf destroy -auto\t", "tf destroy -auto-approve {m}"),
    ("tf fmt -r\t", "tf fmt -recursive {m}"),
    ("tf validate -no-t\t", "tf validate -no-tests {m}"),
    ("tf plan -lock=f\t", "tf plan -lock=false {m}"),
    ("tf providers mirror -lock-file=f\t", "tf providers mirror -lock-file=false {m}"),
    ("tf -chdir=envs/prod plan -var-file=prod\t", "tf -chdir=envs/prod plan -var-file=prod\\ vars.tfvars {m}"),
    ("tf -chdir=envs/prod plan -var-file=vars\t", "tf -chdir=envs/prod plan -var-file=vars_sub/{m}"),
    ("tfp -o\t", "tfp -out={m}"),
    ("ide --ai=cl\t", "ide --ai=claude {m}"),
    ("ide --agent-state=qu\t", "ide --agent-state=quota {m}"),
    ("ide --swap=ri\t", "ide --swap=right {m}"),
    ("ide --open=dir=1/ma\t", "ide --open=dir=1/main.tf {m}"),
    ("ide --open-pr=al\t", "ide --open-pr=alpha-ws {m}"),
]

rx_buf = ""

def read_until(fd, marker, timeout=5.0):
    global rx_buf
    end = time.monotonic() + timeout
    while marker not in rx_buf and time.monotonic() < end:
        r, _, _ = select.select([fd], [], [], 0.03)
        if r:
            try:
                chunk = os.read(fd, 8192).decode("utf-8", "replace")
            except OSError:
                break
            if not chunk:
                break
            rx_buf += chunk
    pos = rx_buf.find(marker)
    if pos != -1:
        end_pos = pos + len(marker)
        taken = rx_buf[:end_pos]
        rx_buf = rx_buf[end_pos:]
        return taken, True
    taken = rx_buf
    rx_buf = ""
    return taken, False

def render_line(raw, marker):
    s = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", raw)
    s = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", s)
    s = re.sub(r"\x1b[=>]", "", s)
    out = []
    for ch in s:
        if ch == "\x08":
            if out:
                out.pop()
        elif ch != "\x07":
            out.append(ch)
        joined = "".join(out)
        if marker in joined:
            return joined
    return "".join(out)

def _attach_ctty():
    os.setsid()
    try:
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)
    except OSError:
        try:
            fcntl.ioctl(0, termios.TIOCSCTTY, 1)
        except OSError:
            pass

mfd, sfd = pty.openpty()
fcntl.ioctl(sfd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 200, 0, 0))
proc = subprocess.Popen(
    [os.environ.get("ZSH_BIN") or "zsh", "-d", "-i"],
    stdin=sfd,
    stdout=sfd,
    stderr=sfd,
    cwd=home,
    env=env,
    preexec_fn=_attach_ctty,
    close_fds=True,
)
os.close(sfd)
bad = []
try:
    init_out, ok_init = read_until(mfd, "READY> ", timeout=15.0)
    if not ok_init:
        bad.append(f"initial prompt timeout: {init_out!r}")
    else:
        for idx, (typed, expected_tmpl) in enumerate(checks):
            marker = f"<<<END{idx}>>>"
            expected = expected_tmpl.format(m=marker)
            os.write(mfd, typed.encode() + marker.encode() + b"\x15\n")
            out, ok_step = read_until(mfd, "READY> ", timeout=5.0)
            rendered = render_line(out, marker)
            if not ok_step:
                bad.append(f"timeout on {typed!r}: {rendered!r}")
                break
            if expected not in rendered:
                bad.append(f"{expected!r} not in {rendered!r}")
    try:
        os.write(mfd, b"\x15exit\n")
    except OSError:
        pass
finally:
    os.close(mfd)
    try:
        proc.wait(timeout=2)
    except Exception:
        proc.kill()
        proc.wait()

print("ok" if not bad else "; ".join(bad))
PY
)"
fi

if tf_comp_err="$(HOME="$MOCK_TF_HOME" PATH="$MOCK_TF_HOME/bin:/usr/bin:/bin" "$ZSH_BIN" -f "$MOCK_TF_HOME/test-tf-comp.zsh" "$SCRIPT_DIR/dotfiles/.zsh-completions" 2>&1)" && [ -z "$tf_comp_err" ] && [ "$tf_zsh_pty" = "ok" ]; then
    pass "_terraform Zsh completion registers terraform and tf and completes subcommands, plan/apply/destroy/fmt/validate flags, -backend=false/-lock=false values, space-escaped -chdir=/-var-file= paths, and broken-shim/binary-absent fallback"
else
    fail "_terraform Zsh completion" "Unexpected _terraform completion behavior: err='${tf_comp_err:-}' pty='$tf_zsh_pty'"
fi
rm -rf "$MOCK_TF_HOME"

# Test 6: Lazy subprocess execution in _ide and _theme (Zsh & Bash) + mise-before-zoxide startup order
LAZY_COMP_HOME="$(mktemp -d)"
mkdir -p "$LAZY_COMP_HOME/.local/bin"
IDE_LAZY_LOG="$LAZY_COMP_HOME/ide_calls.log"
THEME_LAZY_LOG="$LAZY_COMP_HOME/theme_calls.log"
cat << EOF > "$LAZY_COMP_HOME/.local/bin/ide"
#!/bin/sh
echo "\$*" >> "$IDE_LAZY_LOG"
printf "lazy-ws\n"
EOF
cat << EOF > "$LAZY_COMP_HOME/.local/bin/theme"
#!/bin/sh
echo "\$*" >> "$THEME_LAZY_LOG"
printf "solarized-dark\nnord\n"
EOF
chmod +x "$LAZY_COMP_HOME/.local/bin/ide" "$LAZY_COMP_HOME/.local/bin/theme"

cat << 'EOF' > "$LAZY_COMP_HOME/check-lazy.zsh"
#!/usr/bin/env zsh
set -euo pipefail
typeset -gA COMP_MAP=()
typeset -ga OFFERED=()
compdef() { local fn="$1"; shift; local c; for c in "$@"; do COMP_MAP[$c]="$fn"; done; }
_describe() { [[ "${1:-}" == "-t" ]] && shift 2; local arr="$2" it; for it in "${(@P)arr}"; do OFFERED+=("${it%%:*}"); done; }
_files() { OFFERED+=("_FILES_"); }
source "$1"
run_comp() { local fn="$1"; shift; OFFERED=(); words=("$@"); CURRENT=${#words}; "$fn"; }
run_comp _ide ide --
run_comp _ide ide --ai ""
run_comp _ide ide --swap ""
run_comp _ide ide --list ""
run_comp _ide ide --agent-state ""
run_comp _ide ide --open ""
run_comp _ide ide --cd ""
run_comp _ide ide --send ""
run_comp _theme theme --
run_comp _theme theme -
[[ ! -s "$2" ]] || { print -u2 "ide invoked eagerly on flag/static completion"; exit 1; }
[[ ! -s "$3" ]] || { print -u2 "theme invoked eagerly on flag completion"; exit 1; }
run_comp _ide ide -s ""
run_comp _theme theme --set ""
run_comp _theme theme --set=
[[ -s "$2" ]] || { print -u2 "ide not invoked on session completion"; exit 1; }
[[ -s "$3" ]] || { print -u2 "theme not invoked on theme completion"; exit 1; }
EOF

rm -f "$IDE_LAZY_LOG" "$THEME_LAZY_LOG"
lazy_zsh_err="$(HOME="$LAZY_COMP_HOME" PATH="$LAZY_COMP_HOME/.local/bin:/usr/bin:/bin" "$ZSH_BIN" -f "$LAZY_COMP_HOME/check-lazy.zsh" "$SCRIPT_DIR/dotfiles/.zsh-completions" "$IDE_LAZY_LOG" "$THEME_LAZY_LOG" 2>&1 || true)"

rm -f "$THEME_LAZY_LOG"
lazy_bash_ok="$({ HOME="$LAZY_COMP_HOME" PATH="$LAZY_COMP_HOME/.local/bin:/usr/bin:/bin" THEME_LOG="$THEME_LAZY_LOG" "$BASH" --noprofile --norc -i -c '
    source "'"$SCRIPT_DIR"'/dotfiles/.bashrc-addendum"
    rm -f "$THEME_LOG"
    COMP_WORDS=(theme --)
    COMP_CWORD=1
    _theme_bash_complete
    [ ! -s "$THEME_LOG" ] || { echo "eager:${COMPREPLY[*]}"; exit 1; }
    COMP_WORDS=(theme "")
    COMP_CWORD=1
    _theme_bash_complete
    [ -s "$THEME_LOG" ] && [[ " ${COMPREPLY[*]} " == *" nord "* ]] || { echo "pos:${COMPREPLY[*]}"; exit 1; }
    COMP_WORDS=(theme --set =)
    COMP_CWORD=2
    _theme_bash_complete
    [[ " ${COMPREPLY[*]} " == *" nord "* ]] && [[ " ${COMPREPLY[*]} " != *" --list "* ]] || { echo "eq:${COMPREPLY[*]}"; exit 1; }
    COMP_WORDS=(theme --set = -)
    COMP_CWORD=3
    _theme_bash_complete
    [[ " ${COMPREPLY[*]} " != *" --list "* ]] && [[ " ${COMPREPLY[*]} " != *" -c "* ]] || { echo "eq_dash:${COMPREPLY[*]}"; exit 1; }
    COMP_WORDS=(theme --set=no)
    COMP_CWORD=1
    _theme_bash_complete
    [[ " ${COMPREPLY[*]} " == *" nord "* || " ${COMPREPLY[*]} " == *" --set=nord "* ]] && echo "ok"
' 2>/dev/null || true; } | tail -n 1)"

order_ok="$(python3 - "$SCRIPT_DIR/dotfiles/.zshrc-addendum" "$SCRIPT_DIR/dotfiles/.bashrc-addendum" <<'PY' 2>&1 || true
import sys
for path in sys.argv[1:]:
    txt = open(path, encoding="utf-8").read()
    m_pos = txt.find("mise activate")
    z_pos = txt.find("zoxide init")
    assert 0 <= m_pos < z_pos, f"{path}: mise activate ({m_pos}) must precede zoxide init ({z_pos})"
print("ok")
PY
)"
rm -rf "$LAZY_COMP_HOME"

if [ -z "$lazy_zsh_err" ] && [ "$lazy_bash_ok" = "ok" ] && [ "$order_ok" = "ok" ]; then
    pass "_ide and _theme lazy-load session/theme lists on Tab completion, and mise activate precedes zoxide init in both shells"
else
    fail "Lazy completions & mise/zoxide init order" "zsh_err='$lazy_zsh_err' bash='$lazy_bash_ok' order='$order_ok'"
fi

export HOME="$OLD_HOME"
if [ -n "$OLD_XDG_DATA_HOME" ]; then export XDG_DATA_HOME="$OLD_XDG_DATA_HOME"; else unset XDG_DATA_HOME; fi
if [ -n "$OLD_ELAN_HOME" ]; then export ELAN_HOME="$OLD_ELAN_HOME"; else unset ELAN_HOME; fi

test_summary
