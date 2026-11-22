"""Validate standalone Python packages and shell-embedded Python heredocs for Python 3.9+ compatibility."""

from __future__ import annotations

import ast
import glob
import os
import re
import sys

if not getattr(sys, "pycache_prefix", None):
    sys.dont_write_bytecode = True

_BUILTIN_TYPE_NAMES = frozenset({
    "int", "str", "float", "bool", "bytes", "list", "dict", "set",
    "frozenset", "tuple", "type", "object", "complex", "bytearray",
    "memoryview", "range", "slice",
})
_GENERIC_TYPE_NAMES = frozenset({
    "list", "dict", "set", "frozenset", "tuple", "type",
})


def _has_future_annotations(tree: ast.Module) -> bool:
    for stmt in tree.body:
        if (
            isinstance(stmt, ast.Expr)
            and isinstance(stmt.value, ast.Constant)
            and isinstance(stmt.value.value, str)
        ):
            continue
        if isinstance(stmt, ast.ImportFrom) and stmt.module == "__future__":
            if any(alias.name == "annotations" for alias in stmt.names):
                return True
            continue
        break
    return False


def _find_bitor_line(node: ast.AST) -> int | None:
    for sub in ast.walk(node):
        if isinstance(sub, ast.BinOp) and isinstance(sub.op, ast.BitOr):
            return getattr(sub, "lineno", 1)
    return None


def _is_type_union_operand(expr: ast.AST) -> bool:
    if isinstance(expr, ast.Constant) and expr.value is None:
        return True
    if isinstance(expr, ast.Name) and expr.id in _BUILTIN_TYPE_NAMES:
        return True
    if (
        isinstance(expr, ast.Subscript)
        and isinstance(expr.value, ast.Name)
        and expr.value.id in _GENERIC_TYPE_NAMES
    ):
        return True
    return False


def _validate_py39_source(src: str, path: str, start_line: int, errors: list[str]) -> None:
    try:
        tree = ast.parse(
            src,
            filename=f"{path}:{start_line}",
            feature_version=(3, 9),
        )
    except SyntaxError as exc:
        err_line = start_line + (exc.lineno or 1) - 1
        errors.append(f"{path}:{err_line}: Python 3.9 SyntaxError: {exc.msg}")
        return

    has_future_ann = _has_future_annotations(tree)
    ann_roots = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if node.returns is not None:
                ann_roots.append(node.returns)
            all_args = (
                list(getattr(node.args, "posonlyargs", []))
                + list(node.args.args)
                + list(node.args.kwonlyargs)
            )
            if node.args.vararg:
                all_args.append(node.args.vararg)
            if node.args.kwarg:
                all_args.append(node.args.kwarg)
            for a in all_args:
                if a.annotation is not None:
                    ann_roots.append(a.annotation)
        elif isinstance(node, ast.AnnAssign) and node.annotation is not None:
            ann_roots.append(node.annotation)

    if not has_future_ann:
        for ann in ann_roots:
            bline = _find_bitor_line(ann)
            if bline is not None:
                err_line = start_line + bline - 1
                errors.append(
                    f"{path}:{err_line}: un-postponed PEP 604 union annotation (X | Y) without 'from __future__ import annotations' breaks Python 3.9"
                )

    postponed_ids = {id(sub) for ann in ann_roots for sub in ast.walk(ann)}
    isinstance_union_ids: set[int] = set()
    for node in ast.walk(tree):
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id in ("isinstance", "issubclass")
            and len(node.args) >= 2
        ):
            bline = _find_bitor_line(node.args[1])
            if bline is not None:
                isinstance_union_ids.update(id(sub) for sub in ast.walk(node.args[1]))
                err_line = start_line + bline - 1
                errors.append(
                    f"{path}:{err_line}: PEP 604 union in {node.func.id}() breaks Python 3.9 at runtime"
                )
        elif (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "zip"
            and any(kw.arg == "strict" for kw in node.keywords)
        ):
            err_line = start_line + getattr(node, "lineno", 1) - 1
            errors.append(
                f"{path}:{err_line}: zip(..., strict=...) requires Python 3.10+ and breaks Python 3.9"
            )
    for node in ast.walk(tree):
        if (
            isinstance(node, ast.BinOp)
            and isinstance(node.op, ast.BitOr)
            and id(node) not in postponed_ids
            and id(node) not in isinstance_union_ids
            and (_is_type_union_operand(node.left) or _is_type_union_operand(node.right))
        ):
            err_line = start_line + getattr(node, "lineno", 1) - 1
            errors.append(
                f"{path}:{err_line}: runtime PEP 604 type union (X | Y) breaks Python 3.9"
            )


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    root_dir = args[0] if args else "."

    standalone_py_files: list[str] = []
    for pkg_base in (
        os.path.join(root_dir, "libexec"),
        os.path.join(root_dir, "tests", "lint"),
        os.path.join(root_dir, "bin"),
    ):
        if not os.path.isdir(pkg_base):
            continue
        is_bin_root = os.path.basename(pkg_base) == "bin"
        for walk_root, dirs, fnames in os.walk(pkg_base):
            dirs[:] = sorted(d for d in dirs if d != "__pycache__" and not d.startswith("."))
            for fn in sorted(fnames):
                full_p = os.path.join(walk_root, fn)
                if not os.path.isfile(full_p):
                    continue
                if fn.endswith(".py"):
                    if full_p not in standalone_py_files:
                        standalone_py_files.append(full_p)
                elif is_bin_root and walk_root == pkg_base:
                    with open(full_p, encoding="utf-8", errors="replace") as fh:
                        first = fh.readline()
                    if first.startswith("#!") and "python" in first:
                        if full_p not in standalone_py_files:
                            standalone_py_files.append(full_p)

    shell_patterns = [
        os.path.join(root_dir, "bin", "*"),
        os.path.join(root_dir, "setup", "lib", "*.sh"),
        os.path.join(root_dir, "setup", "modules", "*.sh"),
        os.path.join(root_dir, "lib", "*.sh"),
        os.path.join(root_dir, "modules", "*.sh"),
        os.path.join(root_dir, "dotfiles", ".config", "shell", "*.sh"),
        os.path.join(root_dir, "dotfiles", ".config", "shell", "*.zsh"),
        os.path.join(root_dir, "dotfiles", ".config", "shell", "*", "*.sh"),
        os.path.join(root_dir, "dotfiles", ".config", "shell", "*", "*.zsh"),
        os.path.join(root_dir, "tests", "*.sh"),
        os.path.join(root_dir, "tests", "*.zsh"),
        os.path.join(root_dir, "setup.sh"),
    ]
    standalone_set = set(standalone_py_files)
    shell_files: list[str] = []
    for pat in shell_patterns:
        for path in sorted(glob.glob(pat)):
            if os.path.isfile(path) and path not in standalone_set and path not in shell_files:
                shell_files.append(path)

    heredoc_re = re.compile(
        r"(?:\bpython3\b[^\n]*|_PY(?:_SRC)?\s+)<<(-?)\s*'([A-Za-z0-9_]+)'(?:\s*(?:(?:[0-9]*[><]|[|&;#)]).*)?)?$"
    )
    parsed_blocks = 0
    errors: list[str] = []

    for py_path in standalone_py_files:
        with open(py_path, encoding="utf-8") as fh:
            py_src = fh.read()
        parsed_blocks += 1
        _validate_py39_source(py_src, py_path, 1, errors)

    for path in shell_files:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
        idx = 0
        while idx < len(lines):
            line = lines[idx]
            if not line.lstrip().startswith("#"):
                m = heredoc_re.search(line)
                if m:
                    strip_tabs = m.group(1) == "-"
                    tag = m.group(2)
                    start_line = idx + 2
                    block = []
                    idx += 1
                    while idx < len(lines):
                        candidate = lines[idx].lstrip("\t") if strip_tabs else lines[idx]
                        if candidate == tag:
                            break
                        block.append(lines[idx])
                        idx += 1
                    src = "\n".join(block) + "\n"
                    parsed_blocks += 1
                    _validate_py39_source(src, path, start_line, errors)
            idx += 1

    if parsed_blocks == 0:
        errors.append("No Python modules or embedded Python blocks found across scripts")

    if errors:
        for err in errors:
            print(err, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
