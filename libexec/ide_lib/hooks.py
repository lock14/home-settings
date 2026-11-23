"""Untracked user hook runner (`links.sh`) and external workspace discovery."""

from __future__ import annotations

import os
import re
import subprocess
import sys

from ide_lib.constants import sanitize_name_token

_CREATE_FN_DEF_RE = re.compile(
    r"(?m)^[ \t]*(?:function[ \t]+ide_create_workspace(?:[ \t]*\(\s*\))?[ \t{(]|ide_create_workspace[ \t]*\(\s*\))"
)


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


def default_workspace_parent() -> str:
    """Return configured `$IDE_WORKSPACE_PARENT` base directory or `$HOME`."""
    raw = (os.environ.get("IDE_WORKSPACE_PARENT") or "").strip()
    if raw:
        return os.path.abspath(os.path.expanduser(raw))
    return os.path.abspath(os.path.expanduser("~"))


def has_create_workspace_hook() -> bool:
    """Return True when `links.sh` declares an `ide_create_workspace` shell function."""
    rules = ide_rules_path()
    try:
        with open(rules, "r", encoding="utf-8") as fh:
            return bool(_CREATE_FN_DEF_RE.search(fh.read()))
    except OSError:
        return False


def _resolve_create_timeout(timeout: float | None) -> float:
    raw_env = (os.environ.get("IDE_CREATE_TIMEOUT") or "").strip()
    if raw_env:
        try:
            parsed = float(raw_env)
            if parsed > 0:
                return parsed
        except ValueError:
            pass
    if timeout is not None and timeout > 0:
        return timeout
    return 120.0


def create_workspace_directory(
    raw_name: str,
    timeout: float | None = None,
    interactive_tty: bool | None = None,
) -> tuple[str, str]:
    """Create a workspace directory via `ide_create_workspace` hook or `mkdir` under `$IDE_WORKSPACE_PARENT`."""
    clean = raw_name.strip()
    if not clean or clean in (".", "..", "/", "~"):
        return ("", "Invalid workspace name.")
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in clean):
        return ("", "Workspace name cannot contain control characters.")
    if ".." in [seg for seg in clean.replace("\\", "/").split("/") if seg]:
        return ("", "Workspace name cannot contain '..' traversal segments.")

    parent_dir = default_workspace_parent()
    rules = ide_rules_with_fn("ide_create_workspace")
    if rules:
        eff_timeout = _resolve_create_timeout(timeout)
        is_tty = (
            (sys.stdin.isatty() and sys.stderr.isatty())
            if interactive_tty is None
            else bool(interactive_tty)
        )
        hook_env = os.environ.copy()
        hook_env["IDE_WORKSPACE_PARENT"] = parent_dir
        try:
            res = subprocess.run(
                [
                    "bash",
                    "-c",
                    (
                        '. "$1" || exit 1; '
                        'if ! declare -F ide_create_workspace >/dev/null 2>&1; then exit 126; fi; '
                        'ide_create_workspace "$2"'
                    ),
                    "ide",
                    rules,
                    clean,
                ],
                stdin=None if is_tty else subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=None if is_tty else subprocess.PIPE,
                text=True,
                env=hook_env,
                timeout=eff_timeout,
                check=False,
            )
        except KeyboardInterrupt:
            return ("", "Workspace creation canceled.")
        except subprocess.TimeoutExpired:
            return ("", f"ide_create_workspace timed out after {eff_timeout:g}s.")
        except OSError as exc:
            return ("", f"Failed to execute ide_create_workspace: {exc.strerror or exc}")

        if res.returncode != 126:
            if res.returncode != 0:
                err_lines = [ln.strip() for ln in (res.stderr or "").splitlines() if ln.strip()]
                detail = err_lines[-1] if err_lines else f"ide_create_workspace exited with status {res.returncode}."
                return ("", detail)
            out_lines = [ln.strip() for ln in (res.stdout or "").splitlines() if ln.strip()]
            for cand_ln in reversed(out_lines):
                exp_ln = os.path.abspath(os.path.expanduser(cand_ln))
                if os.path.isdir(exp_ln):
                    return (exp_ln, "")
            resolved_ws = resolve_workspace_target(clean)
            if resolved_ws and os.path.isdir(resolved_ws):
                return (os.path.abspath(resolved_ws), "")
            if not out_lines:
                cand_def = os.path.abspath(os.path.join(parent_dir, clean))
                if os.path.isdir(cand_def):
                    return (cand_def, "")
                return ("", "ide_create_workspace exited 0 without printing or creating a workspace directory.")
            return ("", f"ide_create_workspace returned non-existent directory '{out_lines[-1]}'.")

    if clean.startswith(("/", "~/", "./")):
        exp_path = os.path.expanduser(clean)
        target_dir = os.path.abspath(exp_path)
    else:
        segs = [seg for seg in clean.replace("\\", "/").split("/") if seg]
        if not segs or "." in segs or ".." in segs:
            return ("", "Workspace name cannot contain '.' or '..' path segments.")
        target_dir = os.path.abspath(os.path.join(parent_dir, *segs))
        try:
            if target_dir == parent_dir or os.path.commonpath([parent_dir, target_dir]) != parent_dir:
                return ("", f"Workspace '{clean}' resolves outside '{parent_dir}'.")
        except ValueError:
            return ("", f"Workspace '{clean}' resolves outside '{parent_dir}'.")

    try:
        os.makedirs(target_dir, exist_ok=True)
    except OSError as exc:
        return ("", f"Failed to create directory '{target_dir}': {exc.strerror or exc}")
    return (target_dir, "")
