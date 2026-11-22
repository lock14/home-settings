#!/usr/bin/env bash
# Standalone static analysis, ShellCheck, Python 3.9+ AST, and documentation linter runner.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
cd "$REPO_DIR"

unset TMUX TMUX_PANE NVIM_IDE_SOCKET NVIM_IDE_PANE IDE_SESSION PYTHONPYCACHEPREFIX
if [ -z "${COLORTERM:-}" ]; then
    export COLORTERM="truecolor"
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    cat <<'EOF'
Usage: tests/lint.sh

Run Zsh syntax validation, Bash syntax validation, ShellCheck static analysis,
Python 3.9+ AST compatibility checks, and documentation hygiene checks.
EOF
    exit 0
fi

if [ "$#" -gt 0 ]; then
    echo "Error: Unknown argument: $1" >&2
    exit 1
fi

echo "Checking zsh syntax..."
for zf in \
    dotfiles/.aliases \
    dotfiles/.zsh-functions \
    dotfiles/.zshrc-addendum \
    dotfiles/.zsh-completions \
    dotfiles/.p10k.zsh \
    tests/test-zsh.zsh \
    dotfiles/.config/shell/*.zsh \
    dotfiles/.config/shell/*/*.zsh; do
    [ -f "$zf" ] || continue
    zsh -n "$zf"
done

echo "Checking bash script syntax with 'bash -n'..."
bash_files=(
    dotfiles/.aliases
    dotfiles/.bashrc-addendum
    dotfiles/.environment-variables
    setup.sh
)
for sf in \
    setup/lib/*.sh \
    setup/modules/*.sh \
    tests/*.sh \
    dotfiles/.config/shell/*.sh \
    dotfiles/.config/shell/*/*.sh; do
    [ -f "$sf" ] && bash_files+=("$sf")
done
for bf in bin/*; do
    [ -f "$bf" ] || continue
    first=""
    IFS= read -r first < "$bf" || first=""
    case "$first" in
        '#!'*python*) continue ;;
    esac
    bash_files+=("$bf")
done

bash -n "${bash_files[@]}"

if command -v shellcheck >/dev/null 2>&1; then
    echo "Running shellcheck on bash/sh scripts..."
    jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    case "$jobs" in
        ''|*[!0-9]*|0) jobs=4 ;;
    esac
    [ "$jobs" -gt 8 ] && jobs=8
    printf '%s\0' "${bash_files[@]}" | xargs -0 -n 1 -P "$jobs" shellcheck --severity=warning -e SC2148,SC2154
else
    echo "shellcheck not found in PATH (skipped shellcheck static analysis)."
fi

echo "Checking Python module and embedded AST syntax..."
python3 -B "$TESTS_DIR/lint/lint_python.py" "$REPO_DIR"

echo "Checking documentation hygiene and links..."
python3 -B "$TESTS_DIR/lint/lint_docs.py" "$REPO_DIR"

echo "Checking derived theme assets and standalone fallback sync..."
"$REPO_DIR/bin/theme" --check-assets

echo "All lint checks passed."
