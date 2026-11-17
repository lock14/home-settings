"""Untracked user hook runner (`links.sh`) and external workspace discovery."""

from __future__ import annotations

import os
import subprocess

from ide_lib.constants import sanitize_name_token


def ide_rules_path() -> str:
    """Return the configured untracked `links.sh` hook file path."""
    xdg_cfg = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.environ.get("IDE_LINK_RULES") or os.path.join(xdg_cfg, "ide", "links.sh")


def ide_rules_with_fn(fn_name: str) -> str:
    """Return the rules file path if readable and mentioning `fn_name`, else empty."""
    rules = ide_rules_path()
    try:
        with open(rules, "r", encoding="utf-8") as fh:
            if fn_name in fh.read():
                return rules
    except OSError:
        pass
    return ""


def call_ide_hook(fn_name: str, *args: str, timeout: float = 1.0) -> str:
    """Invoke shell function `fn_name` in `links.sh` with a bounded timeout."""
    rules = ide_rules_with_fn(fn_name)
    if not rules:
        return ""
    try:
        res = subprocess.run(
            [
                "bash",
                "-c",
                f'. "$1" && declare -F {fn_name} >/dev/null && {fn_name} "${{@:2}}"',
                "ide",
                rules,
                *args,
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return (res.stdout or "").strip() if res.returncode == 0 else ""


def scandir_child_dirs(parent: str, cache: dict[str, set[str]]) -> set[str]:
    """List immediate subdirectory names of `parent` once via `os.scandir`, caching results."""
    if parent in cache:
        return cache[parent]
    live: set[str] = set()
    try:
        with os.scandir(parent) as it:
            for entry in it:
                try:
                    if entry.is_dir():
                        live.add(entry.name)
                except OSError:
                    pass
    except OSError:
        pass
    cache[parent] = live
    return live


def collect_configured_workspace_roots(
    parent_cache: dict[str, set[str]] | None = None,
    include_hook: bool = True,
) -> tuple[list[str], set[str], dict[str, set[str]]]:
    """Collect live external workspace directories from `ide_workspace_dirs` and `$IDE_WORKSPACE_DIRS`."""
    cache = parent_cache if parent_cache is not None else {}
    raw_candidates: list[str] = []
    if include_hook:
        hook_out = call_ide_hook("ide_workspace_dirs", timeout=1.0)
        if hook_out:
            raw_candidates.extend(hook_out.splitlines())
    env_ws = os.environ.get("IDE_WORKSPACE_DIRS", "")
    if env_ws:
        raw_candidates.extend(env_ws.split(":"))

    roots: list[str] = []
    seen_roots: set[str] = set()
    managed_parents: set[str] = set()
    for raw in raw_candidates:
        s = raw.strip()
        if not s:
            continue
        norm = os.path.abspath(os.path.expanduser(s))
        if norm in seen_roots:
            continue
        parent = os.path.dirname(norm)
        if parent and parent != "/":
            managed_parents.add(parent)
            if os.path.basename(norm) not in scandir_child_dirs(parent, cache):
                continue
        elif not os.path.isdir(norm):
            continue
        seen_roots.add(norm)
        roots.append(norm)
    return roots, managed_parents, cache


def resolve_workspace_target(raw_target: str) -> str:
    """Resolve workspace shorthand or mount root via `ide_resolve_workspace` or configured roots."""
    if not raw_target or raw_target in (".", "..") or raw_target.startswith(("./", "../")):
        return ""
    hook_resolved = call_ide_hook("ide_resolve_workspace", raw_target, timeout=1.0)
    if hook_resolved:
        first_ln = next((ln.strip() for ln in hook_resolved.splitlines() if ln.strip()), "")
        if first_ln:
            exp = os.path.expanduser(first_ln)
            if os.path.isdir(exp):
                return os.path.abspath(exp)

    if raw_target.startswith(("/", "~")):
        return ""
    clean_rel = raw_target.rstrip("/")
    if not clean_rel:
        return ""
    head, sep, tail = clean_rel.partition("/")
    if not head or head in (".", "..") or ".." in tail.split("/"):
        return ""
    roots, _, _ = collect_configured_workspace_roots()
    for ws_root in roots:
        if os.path.basename(ws_root) == head:
            if not sep or not tail:
                mount_resolved = call_ide_hook("ide_resolve_workspace", ws_root, timeout=1.0)
                if mount_resolved:
                    m_ln = next((ln.strip() for ln in mount_resolved.splitlines() if ln.strip()), "")
                    if m_ln:
                        m_exp = os.path.expanduser(m_ln)
                        if os.path.isdir(m_exp):
                            return os.path.abspath(m_exp)
                return ws_root
            joined = os.path.join(ws_root, tail)
            return os.path.abspath(joined) if os.path.isdir(joined) else ""
    return ""


def resolve_custom_session_name(target_dir: str) -> str:
    """Return custom session name from `ide_session_name` hook if defined."""
    return call_ide_hook("ide_session_name", target_dir)


def sanitize_session_name(raw: str) -> str:
    """Derive a clean tmux session name from `ide_session_name` or directory basename."""
    custom = resolve_custom_session_name(raw)
    if custom:
        return sanitize_name_token(custom)
    base = os.path.basename(raw.rstrip("/")) if raw.rstrip("/") else os.path.basename(raw)
    return sanitize_name_token(base)
