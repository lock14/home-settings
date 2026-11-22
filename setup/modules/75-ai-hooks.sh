#!/bin/bash
# Stage 75: Idempotent AI CLI lifecycle hooks (agy, claude, and codex) for ide state reporting.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# shellcheck source=/dev/null
. "$SETUP_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$SETUP_DIR/lib/os.sh"

DRY_RUN="${DRY_RUN:-false}"
MODE="install"
if [ "${1:-}" = "--uninstall" ]; then
    MODE="uninstall"
fi

PY_BIN="/usr/bin/python3"
if [ ! -x "$PY_BIN" ]; then
    if command -v python3 >/dev/null 2>&1; then
        PY_BIN="python3"
    else
        echo "  Skipping AI CLI lifecycle hooks (python3 not found)."
        exit 0
    fi
fi

if [ "$MODE" = "uninstall" ]; then
    echo "  Removing managed AI CLI lifecycle hooks..."
else
    echo "  Configuring AI CLI lifecycle hooks (agy, claude, codex)..."
fi

"$PY_BIN" -B - "$HOME" "$MODE" "$DRY_RUN" <<'PY'
from __future__ import annotations

import json
import os
import re
import sys
import tempfile

sys.dont_write_bytecode = True

home_dir = sys.argv[1]
mode = sys.argv[2]
dry_run = sys.argv[3].lower() == "true"

AGY_HOOKS_PATH = os.path.join(home_dir, ".gemini", "config", "hooks.json")
CLAUDE_SETTINGS_PATH = os.path.join(home_dir, ".claude", "settings.json")
CODEX_CONFIG_PATH = os.path.join(home_dir, ".codex", "config.toml")

AGY_IDE_BLOCK = {
    "SessionStart": [
        {
            "type": "command",
            "command": '[ -n "${TMUX:-}" ] && command -v ide >/dev/null 2>&1 && ide state idle </dev/null >/dev/null 2>&1 || true; printf \'{}\\n\'',
        }
    ],
    "PreInvocation": [
        {
            "type": "command",
            "command": '[ -n "${TMUX:-}" ] && command -v ide >/dev/null 2>&1 && ide state running </dev/null >/dev/null 2>&1 || true; printf \'{}\\n\'',
        }
    ],
    "PreToolUse": [
        {
            "matcher": "ask_question",
            "hooks": [
                {
                    "type": "command",
                    "command": '[ -n "${TMUX:-}" ] && command -v ide >/dev/null 2>&1 && ide state approval -m "Waiting for user answer" </dev/null >/dev/null 2>&1 || true; printf \'{"decision":"allow"}\\n\'',
                }
            ],
        }
    ],
    "PostToolUse": [
        {
            "matcher": "ask_question",
            "hooks": [
                {
                    "type": "command",
                    "command": '[ -n "${TMUX:-}" ] && command -v ide >/dev/null 2>&1 && ide state running </dev/null >/dev/null 2>&1 || true; printf \'{}\\n\'',
                }
            ],
        }
    ],
    "Stop": [
        {
            "type": "command",
            "command": '(if [ -n "${TMUX:-}" ] && command -v ide >/dev/null 2>&1; then ide state done >/dev/null 2>&1 || true; else cat >/dev/null 2>&1 || true; fi); printf \'{"decision":"stop"}\\n\'',
        }
    ],
}

CLAUDE_EVENT_COMMANDS = (
    ("SessionStart", '[ -n "${TMUX:-}" ] && command -v ide >/dev/null 2>&1 && ide state idle </dev/null || true'),
    ("UserPromptSubmit", '[ -n "${TMUX:-}" ] && command -v ide >/dev/null 2>&1 && ide state running </dev/null || true'),
    ("PreToolUse", '[ -n "${TMUX:-}" ] && command -v ide >/dev/null 2>&1 && ide state running </dev/null || true'),
    ("Notification", '[ -n "${TMUX:-}" ] && command -v ide >/dev/null 2>&1 && ide state approval || true'),
    ("Stop", '[ -n "${TMUX:-}" ] && command -v ide >/dev/null 2>&1 && ide state done || true'),
)

IDE_HOOK_CMD_RE = re.compile(r"(?:^|[\s;&|(])(?:~/.local/bin/|/[^\s\"']+/)?ide\s+(?:--agent-state|state)\b")
CODEX_IDE_NOTIFY_RE = re.compile(
    r'^\s*notify\s*=\s*\[\s*"[^"]*ide"\s*,\s*"(?:--agent-state|state)"\s*,\s*"done"\s*\]\s*(?:#.*)?$'
)
CODEX_ANY_NOTIFY_RE = re.compile(r"^\s*notify\s*=")
CODEX_CANONICAL_LINE = 'notify = ["ide", "state", "done"]'


def atomic_write_text(path: str, content: str) -> None:
    parent = os.path.dirname(path)
    if dry_run:
        print(f"  [DryRun] write {path}")
        return
    os.makedirs(parent, mode=0o700, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".hs-hooks-", dir=parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def remove_file_and_prune_empty(path: str, stop_dir: str) -> None:
    if dry_run:
        if os.path.exists(path):
            print(f"  [DryRun] rm -f {path}")
        return
    try:
        os.unlink(path)
    except FileNotFoundError:
        return
    cur = os.path.dirname(path)
    stop_real = os.path.realpath(stop_dir)
    while cur and os.path.realpath(cur) != stop_real:
        try:
            os.rmdir(cur)
        except OSError:
            break
        cur = os.path.dirname(cur)


def load_json_dict(path: str) -> dict[str, object] | None:
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read().strip()
        if not raw:
            return {}
        data = json.loads(raw)
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def reconcile_agy() -> None:
    data = load_json_dict(AGY_HOOKS_PATH)
    if data is None:
        print(f"  Skipping {AGY_HOOKS_PATH} (existing file is not a JSON object).")
        return
    if mode == "uninstall":
        if "ide-state" not in data:
            return
        updated = {k: v for k, v in data.items() if k != "ide-state"}
        if not updated:
            remove_file_and_prune_empty(AGY_HOOKS_PATH, home_dir)
        else:
            atomic_write_text(AGY_HOOKS_PATH, json.dumps(updated, indent=2) + "\n")
        return

    if data.get("ide-state") == AGY_IDE_BLOCK and os.path.isfile(AGY_HOOKS_PATH):
        return
    updated = dict(data)
    updated["ide-state"] = AGY_IDE_BLOCK
    atomic_write_text(AGY_HOOKS_PATH, json.dumps(updated, indent=2) + "\n")


def _strip_claude_ide_entries(groups: object) -> list[dict[str, object]]:
    if not isinstance(groups, list):
        return []
    kept_groups: list[dict[str, object]] = []
    for grp in groups:
        if not isinstance(grp, dict):
            continue
        hooks_list = grp.get("hooks")
        if not isinstance(hooks_list, list):
            kept_groups.append(grp)
            continue
        rem_hooks = [
            h
            for h in hooks_list
            if not (
                isinstance(h, dict)
                and isinstance(h.get("command"), str)
                and IDE_HOOK_CMD_RE.search(str(h["command"]))
            )
        ]
        if rem_hooks:
            new_grp = dict(grp)
            new_grp["hooks"] = rem_hooks
            kept_groups.append(new_grp)
    return kept_groups


def reconcile_claude() -> None:
    data = load_json_dict(CLAUDE_SETTINGS_PATH)
    if data is None:
        print(f"  Skipping {CLAUDE_SETTINGS_PATH} (existing file is not a JSON object).")
        return
    if mode == "uninstall":
        if not os.path.isfile(CLAUDE_SETTINGS_PATH):
            return
        raw_hooks = data.get("hooks")
        if not isinstance(raw_hooks, dict):
            return
        changed = False
        new_hooks: dict[str, object] = {}
        for ev_name, ev_groups in raw_hooks.items():
            cleaned = _strip_claude_ide_entries(ev_groups)
            if cleaned != ev_groups:
                changed = True
            if cleaned:
                new_hooks[ev_name] = cleaned
        if not changed:
            return
        updated = dict(data)
        if new_hooks:
            updated["hooks"] = new_hooks
        else:
            updated.pop("hooks", None)
        if not updated:
            remove_file_and_prune_empty(CLAUDE_SETTINGS_PATH, home_dir)
        else:
            atomic_write_text(CLAUDE_SETTINGS_PATH, json.dumps(updated, indent=2) + "\n")
        return

    updated = dict(data)
    raw_hooks = updated.get("hooks")
    hooks_map: dict[str, object] = dict(raw_hooks) if isinstance(raw_hooks, dict) else {}
    for ev_name, cmd_str in CLAUDE_EVENT_COMMANDS:
        cleaned_groups = _strip_claude_ide_entries(hooks_map.get(ev_name))
        cleaned_groups.append({"hooks": [{"type": "command", "command": cmd_str}]})
        hooks_map[ev_name] = cleaned_groups
    updated["hooks"] = hooks_map
    rendered = json.dumps(updated, indent=2) + "\n"
    if os.path.isfile(CLAUDE_SETTINGS_PATH):
        try:
            with open(CLAUDE_SETTINGS_PATH, "r", encoding="utf-8") as fh:
                if fh.read() == rendered:
                    return
        except OSError:
            pass
    atomic_write_text(CLAUDE_SETTINGS_PATH, rendered)


def reconcile_codex() -> None:
    existing = ""
    if os.path.isfile(CODEX_CONFIG_PATH):
        try:
            with open(CODEX_CONFIG_PATH, "r", encoding="utf-8") as fh:
                existing = fh.read()
        except OSError:
            return

    lines = existing.splitlines()
    if mode == "uninstall":
        if not os.path.isfile(CODEX_CONFIG_PATH):
            return
        kept: list[str] = []
        removed = False
        in_top = True
        for ln in lines:
            stripped = ln.strip()
            if stripped.startswith("["):
                in_top = False
            if in_top and CODEX_IDE_NOTIFY_RE.match(ln):
                removed = True
                continue
            kept.append(ln)
        if not removed:
            return
        while kept and not kept[0].strip():
            kept.pop(0)
        body = ("\n".join(kept).rstrip() + "\n") if any(k.strip() for k in kept) else ""
        if not body:
            remove_file_and_prune_empty(CODEX_CONFIG_PATH, home_dir)
        else:
            atomic_write_text(CODEX_CONFIG_PATH, body)
        return

    new_lines: list[str] = []
    in_top = True
    saw_custom_notify = False
    replaced_ide_notify = False
    first_table_idx: int | None = None
    for idx, ln in enumerate(lines):
        stripped = ln.strip()
        if stripped.startswith("[") and in_top:
            in_top = False
            first_table_idx = len(new_lines)
        if in_top and CODEX_IDE_NOTIFY_RE.match(ln):
            if not replaced_ide_notify:
                new_lines.append(CODEX_CANONICAL_LINE)
                replaced_ide_notify = True
            continue
        if in_top and CODEX_ANY_NOTIFY_RE.match(ln):
            saw_custom_notify = True
        new_lines.append(ln)

    if not saw_custom_notify and not replaced_ide_notify:
        if first_table_idx is None:
            if new_lines and new_lines[-1].strip():
                new_lines.append(CODEX_CANONICAL_LINE)
            elif new_lines:
                new_lines.insert(len(new_lines) - 1, CODEX_CANONICAL_LINE)
            else:
                new_lines.append(CODEX_CANONICAL_LINE)
        else:
            insert_block = [CODEX_CANONICAL_LINE, ""] if (first_table_idx == 0 or new_lines[first_table_idx - 1].strip()) else [CODEX_CANONICAL_LINE, ""]
            new_lines[first_table_idx:first_table_idx] = insert_block

    rendered = "\n".join(new_lines).rstrip() + "\n"
    if os.path.isfile(CODEX_CONFIG_PATH) and existing == rendered:
        return
    atomic_write_text(CODEX_CONFIG_PATH, rendered)


reconcile_agy()
reconcile_claude()
reconcile_codex()
PY
