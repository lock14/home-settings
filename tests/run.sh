#!/usr/bin/env bash
# Standalone parallel and targeted test suite runner for home-settings.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
cd "$REPO_DIR"

# Force 24-bit TrueColor and isolate tests from any caller tmux, Python cache, or IDE Editor RPC session
unset TMUX TMUX_PANE NVIM_IDE_SOCKET NVIM_IDE_PANE IDE_SESSION PYTHONPYCACHEPREFIX
if [ -z "${COLORTERM:-}" ]; then
    export COLORTERM="truecolor"
fi

SUITE_SPECS=(
    "system-setup:bash:tests/test-system-setup.sh"
    "dotfiles:bash:tests/test-dotfiles.sh"
    "bin:bash:tests/test-bin.sh"
    "theme:bash:tests/test-theme.sh"
    "ide-fleet:bash:tests/test-ide-fleet.sh"
    "env:bash:tests/test-env.sh"
    "zsh:zsh:tests/test-zsh.zsh"
    "completions:bash:tests/test-completions.sh"
    "vim:bash:tests/test-vim.sh"
    "fonts:bash:tests/test-fonts.sh"
)

usage() {
    cat <<'EOF'
Usage: tests/run.sh [OPTIONS] [SUITE...]

Run all or selected home-settings test suites in isolated sandboxes.

Options:
  -l, --list    List available test suite names
  -h, --help    Show this help message and exit

Examples:
  ./tests/run.sh                 # Run all 10 suites in parallel
  ./tests/run.sh system-setup    # Run a single suite with live output
  ./tests/run.sh vim theme       # Run selected suites in parallel
EOF
}

resolve_suite_spec() {
    local query="$1"
    query="${query#tests/}"
    query="${query#test-}"
    query="${query%.sh}"
    query="${query%.zsh}"
    local spec name
    for spec in "${SUITE_SPECS[@]}"; do
        name="${spec%%:*}"
        if [ "$name" = "$query" ]; then
            printf '%s\n' "$spec"
            return 0
        fi
    done
    return 1
}

SELECTED_SPECS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -l|--list)
            for spec in "${SUITE_SPECS[@]}"; do
                printf '%s\n' "${spec%%:*}"
            done
            exit 0
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if matched="$(resolve_suite_spec "$1")"; then
                SELECTED_SPECS+=("$matched")
            else
                echo "Error: Unknown test suite '$1'. Run './tests/run.sh --list' to view suites." >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [ "${#SELECTED_SPECS[@]}" -eq 0 ]; then
    SELECTED_SPECS=("${SUITE_SPECS[@]}")
fi

if [ "${#SELECTED_SPECS[@]}" -eq 1 ]; then
    spec="${SELECTED_SPECS[0]}"
    rest="${spec#*:}"
    runner="${rest%%:*}"
    script="${rest#*:}"
    exec "$runner" "$script"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

pids=()
for spec in "${SELECTED_SPECS[@]}"; do
    name="${spec%%:*}"
    rest="${spec#*:}"
    runner="${rest%%:*}"
    script="${rest#*:}"
    (
        set +e
        "$runner" "$script" > "$tmpdir/$name.out" 2>&1
        echo $? > "$tmpdir/$name.rc"
    ) &
    pids+=("$!")
done

for pid in "${pids[@]}"; do
    wait "$pid" || true
done

failed=0
for spec in "${SELECTED_SPECS[@]}"; do
    name="${spec%%:*}"
    cat "$tmpdir/$name.out"
    rc="$(cat "$tmpdir/$name.rc" 2>/dev/null || echo 1)"
    if [ "$rc" -ne 0 ]; then
        failed=1
    fi
done

if [ "$failed" -ne 0 ]; then
    exit 1
fi

echo "All tests passed successfully."
