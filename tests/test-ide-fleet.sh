#!/usr/bin/env bash
# Test suite for bin/ide multi-session fleet switcher, AI lifecycle state machine, and context dispatch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/tests/test-helper.sh"

echo "========================================"
echo "Running IDE Fleet & Lifecycle Tests"
echo "========================================"

# Phase 0: Modular bin/ide_lib architecture, acyclic DAG, reusable domain unit tests, symlink resolution, and <50ms cold CLI latency
MODULAR_TEST_OUT="$(TMUX="" TMUX_PANE="" NVIM_IDE_SOCKET="" IDE_SESSION="" python3 -B - "$SCRIPT_DIR" 2>&1 <<'PY'
from __future__ import annotations

import ast
import glob
import os
import subprocess
import sys
import tempfile
import time

repo_dir = sys.argv[1]
ide_entry = os.path.join(repo_dir, "bin", "ide")
ide_lib_dir = os.path.join(repo_dir, "libexec", "ide_lib")

# 1. Verify thin bootstrapper and expected cohesive domain modules
with open(ide_entry, encoding="utf-8") as fh:
    ide_lines = fh.read().splitlines()
assert len(ide_lines) <= 300, f"bin/ide should stay a thin bootstrapper (<=300 lines), got {len(ide_lines)}"

expected_modules = {
    "__init__.py",
    "constants.py",
    "hooks.py",
    "git_info.py",
    "proc.py",
    "tmux.py",
    "dock.py",
    "theme.py",
    "nvim_rpc.py",
    "fleet.py",
    "launcher.py",
    "layout.py",
    "links.py",
    "preview.py",
    "switcher.py",
    "sessions.py",
    "cli.py",
}
found_files = sorted(glob.glob(os.path.join(ide_lib_dir, "*.py")))
found_names = {os.path.basename(p) for p in found_files}
assert expected_modules.issubset(found_names), f"missing expected ide_lib modules: {expected_modules - found_names}"

# 2. Verify Python 3.9 AST compatibility and strict acyclic import DAG across bin/ide_lib/*.py
dag: dict[str, set[str]] = {}
for path in found_files:
    mod_name = os.path.splitext(os.path.basename(path))[0]
    dag[mod_name] = set()
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    tree = ast.parse(src, filename=path, feature_version=(3, 9))
    has_future = any(
        isinstance(n, ast.ImportFrom)
        and n.module == "__future__"
        and any(a.name == "annotations" for a in n.names)
        for n in tree.body
    )
    assert has_future, f"{path} missing 'from __future__ import annotations'"
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module and node.module.startswith("ide_lib"):
            parts = node.module.split(".")
            if len(parts) >= 2:
                dag[mod_name].add(parts[1])

visiting: set[str] = set()
visited: set[str] = set()


def _check_dag(node_name: str, trail: list[str]) -> None:
    assert node_name not in visiting, f"circular import in ide_lib: {trail + [node_name]}"
    if node_name in visited:
        return
    visiting.add(node_name)
    for dep in sorted(dag.get(node_name, ())):
        _check_dag(dep, trail + [node_name])
    visiting.remove(node_name)
    visited.add(node_name)


for mname in sorted(dag):
    _check_dag(mname, [])

# 3. Direct in-process unit checks of reusable ide_lib domain functions (zero tmux subprocesses)
sys.path.insert(0, os.path.join(repo_dir, "libexec"))
from ide_lib import TMUX_SEP, USAGE_TEXT
from ide_lib.constants import is_live_socket, sanitize_agent_msg, sanitize_http_url, visible_width
from ide_lib.fleet import format_attn_summary
from ide_lib.git_info import build_forge_pr_url
from ide_lib.links import parse_file_target, strip_token_wrappers
from ide_lib.sessions import (
    _ansi_visible_width,
    _carry_sgr_prefix,
    _fzf_supports_resize_bind,
    _resolve_fzf_wrap_config,
    _resolve_preview_interval,
    _select_preview_tail,
    _wrapped_preview_rows,
)
from ide_lib.theme import hex_to_fg
from ide_lib.tmux import (
    is_switcher_session_name,
    pane_tree_pids,
    read_switcher_result,
    write_switcher_result,
)

assert TMUX_SEP == "\t__IDE_SEP__\t"
assert is_switcher_session_name("ai-sw-100-200") is True
assert is_switcher_session_name("ai-alpha-ws") is False
assert is_switcher_session_name("agy-alpha-ws") is False
assert is_switcher_session_name("alpha-ws") is False
assert read_switcher_result("") is None
_sw_tmp_f = os.path.join(tempfile.gettempdir(), f"ide-sw-unit-{os.getpid()}.json")
try:
    assert read_switcher_result(_sw_tmp_f) is None
    write_switcher_result(_sw_tmp_f, "switch", "alpha-ws", "ctrl-e")
    assert read_switcher_result(_sw_tmp_f) == ("switch", "alpha-ws", "ctrl-e")
finally:
    try:
        os.unlink(_sw_tmp_f)
    except OSError:
        pass
assert _fzf_supports_resize_bind("", "0.74.5 (c0a193e0)") is True
assert _fzf_supports_resize_bind("", "0.46.0 (debian)") is True
assert _fzf_supports_resize_bind("", "0.44.1 (ubuntu)") is False
assert _fzf_supports_resize_bind("/tmp/mock-fzf.py") is False
from ide_lib.cli import _calibrate_ide_path
from ide_lib.constants import _MISE_TOOL_BIN_CACHE, resolve_mise_tool_bin
from ide_lib.sessions import _FZF_RESIZE_CAP_CACHE

_cap_dir = tempfile.mkdtemp(prefix=f"ide-fzf-cap-{os.getpid()}-")
_saved_xdg_c = os.environ.get("XDG_CACHE_HOME")
_saved_path = os.environ.get("PATH")
_saved_strict = os.environ.get("IDE_STRICT_PATH")
try:
    os.environ["XDG_CACHE_HOME"] = _cap_dir
    _fake_fzf = os.path.join(_cap_dir, "fzf")
    with open(_fake_fzf, "w", encoding="utf-8") as _ff:
        _ff.write("#!/bin/sh\nprintf '0.52.1 (test)\\n'\n")
    os.chmod(_fake_fzf, 0o755)
    _FZF_RESIZE_CAP_CACHE.pop(_fake_fzf, None)
    assert _fzf_supports_resize_bind(_fake_fzf) is True
    assert os.path.isfile(os.path.join(_cap_dir, "home-settings", "fzf-cap.cache"))
    _FZF_RESIZE_CAP_CACHE.pop(_fake_fzf, None)
    assert _fzf_supports_resize_bind(_fake_fzf) is True
    with open(_fake_fzf, "w", encoding="utf-8") as _ff:
        _ff.write("#!/bin/sh\nprintf '0.42.0 (older-binary)\\n'\n")
    os.chmod(_fake_fzf, 0o755)
    _FZF_RESIZE_CAP_CACHE.pop(_fake_fzf, None)
    assert _fzf_supports_resize_bind(_fake_fzf) is False

    # Verify mise shim bypass (resolve_mise_tool_bin) & zero shim cache-poisoning in fzf-cap.cache
    _fake_mise_root = os.path.join(_cap_dir, "mise")
    os.makedirs(os.path.join(_fake_mise_root, "shims"), exist_ok=True)
    _fake_mise_exe = os.path.join(_cap_dir, "mise-bin", "mise")
    os.makedirs(os.path.dirname(_fake_mise_exe), exist_ok=True)
    _ver_f = os.path.join(_cap_dir, "shim-ver.txt")
    with open(_ver_f, "w", encoding="utf-8") as _vf:
        _vf.write("0.44.1 (shim-old)\n")
    with open(_fake_mise_exe, "w", encoding="utf-8") as _mf:
        _mf.write(f"#!/bin/sh\ncat {_ver_f!r}\n")
    os.chmod(_fake_mise_exe, 0o755)
    _shim_fzf = os.path.join(_fake_mise_root, "shims", "fzf")
    os.symlink(_fake_mise_exe, _shim_fzf)
    _FZF_RESIZE_CAP_CACHE.pop(_shim_fzf, None)
    assert _fzf_supports_resize_bind(_shim_fzf) is False
    with open(_ver_f, "w", encoding="utf-8") as _vf:
        _vf.write("0.74.5 (shim-upgraded)\n")
    _FZF_RESIZE_CAP_CACHE.pop(_shim_fzf, None)
    assert _fzf_supports_resize_bind(_shim_fzf) is True

    _inst_fzf_dir = os.path.join(_fake_mise_root, "installs", "fzf", "0.74.5")
    os.makedirs(_inst_fzf_dir, exist_ok=True)
    _direct_fzf = os.path.join(_inst_fzf_dir, "fzf")
    with open(_direct_fzf, "w", encoding="utf-8") as _df:
        _df.write("#!/bin/sh\nprintf '0.74.5 (direct)\\n'\n")
    os.chmod(_direct_fzf, 0o755)
    os.environ["IDE_STRICT_PATH"] = "0"
    os.environ["PATH"] = f"{os.path.join(_fake_mise_root, 'shims')}:/usr/bin:/bin"
    _MISE_TOOL_BIN_CACHE.clear()
    assert resolve_mise_tool_bin("fzf") == _direct_fzf

    # Verify MISE_DATA_DIR override when separate from shims directory + load_active_palette stat cache
    _alt_mise_data = os.path.join(_cap_dir, "alt-mise-data")
    _alt_zox_dir = os.path.join(_alt_mise_data, "installs", "zoxide", "0.9.6")
    os.makedirs(_alt_zox_dir, exist_ok=True)
    _alt_zox = os.path.join(_alt_zox_dir, "zoxide")
    with open(_alt_zox, "w", encoding="utf-8") as _zf:
        _zf.write("#!/bin/sh\nexit 0\n")
    os.chmod(_alt_zox, 0o755)
    _shim_zox = os.path.join(_fake_mise_root, "shims", "zoxide")
    os.symlink(_fake_mise_exe, _shim_zox)
    _saved_mise_dd = os.environ.get("MISE_DATA_DIR")
    try:
        os.environ["MISE_DATA_DIR"] = _alt_mise_data
        _MISE_TOOL_BIN_CACHE.clear()
        assert resolve_mise_tool_bin("zoxide") == _alt_zox
    finally:
        if _saved_mise_dd is None:
            os.environ.pop("MISE_DATA_DIR", None)
        else:
            os.environ["MISE_DATA_DIR"] = _saved_mise_dd

    from ide_lib.dock import _switcher_lock_path, select_dockable_ai_pane
    from ide_lib.preview import PipeHangupWatcher
    from ide_lib.proc import _pane_tree_snapshot, _ps_batch_nvim_cmdlines, pids_with_children
    from ide_lib.theme import load_active_palette
    import errno as _errno
    import select

    # Verify missing env_override returns None (never non-existent raw_ovr) and hidden .mise.* dirs are ignored
    os.makedirs(os.path.join(_fake_mise_root, "installs", "fzf", ".mise.backend.toml"), exist_ok=True)
    _saved_fzf_ovr = os.environ.get("IDE_FZF_BIN")
    try:
        os.environ["IDE_FZF_BIN"] = os.path.join(_cap_dir, "missing-fzf-bin")
        assert resolve_mise_tool_bin("fzf", env_override="IDE_FZF_BIN") is None
        os.environ["IDE_FZF_BIN"] = "definitely-not-installed-fzf-xyz"
        assert resolve_mise_tool_bin("fzf", env_override="IDE_FZF_BIN") is None
    finally:
        if _saved_fzf_ovr is None:
            os.environ.pop("IDE_FZF_BIN", None)
        else:
            os.environ["IDE_FZF_BIN"] = _saved_fzf_ovr
    _MISE_TOOL_BIN_CACHE.clear()
    assert resolve_mise_tool_bin("fzf") == _direct_fzf

    # Verify server-scoped switcher lock path unifies concurrent switchers on the same tmux socket
    _sock_demo = os.path.join(_cap_dir, "tmux-1000", "default")
    os.makedirs(os.path.dirname(_sock_demo), exist_ok=True)
    open(_sock_demo, "w", encoding="utf-8").close()
    _saved_tmux_env = os.environ.get("TMUX")
    try:
        os.environ["TMUX"] = f"{_sock_demo},12345,$0"
        assert _switcher_lock_path() == _switcher_lock_path(_sock_demo)
    finally:
        if _saved_tmux_env is None:
            os.environ.pop("TMUX", None)
        else:
            os.environ["TMUX"] = _saved_tmux_env

    # Verify PipeHangupWatcher kqueue semantics (open, immediate EOF, EPIPE error, EINVAL fallback to poll, mid-stream EOF)
    class _FakeKev:
        def __init__(self, ident, filter=0, flags=0, data=0):
            self.ident = ident
            self.filter = filter
            self.flags = flags
            self.data = data

    class _FakeKq:
        def __init__(self, init_evs, poll_evs):
            self._init = init_evs
            self._poll = poll_evs
            self.closed_kq = False

        def control(self, chlist, _max_ev, _timeout):
            return self._init if chlist is not None else self._poll

        def close(self):
            self.closed_kq = True

    class _FakeSelectMod:
        KQ_FILTER_WRITE = -2
        KQ_EV_ADD = 0x0001
        KQ_EV_CLEAR = 0x0020
        KQ_EV_EOF = 0x8000
        KQ_EV_ERROR = 0x4000
        POLLERR = select.POLLERR if hasattr(select, "POLLERR") else 8
        POLLHUP = select.POLLHUP if hasattr(select, "POLLHUP") else 16
        POLLNVAL = getattr(select, "POLLNVAL", 32)
        kevent = _FakeKev
        poll = getattr(select, "poll", None)

        def __init__(self, kq_obj):
            self.kq_obj = kq_obj

        def kqueue(self):
            return self.kq_obj

    _r_pipe, _w_pipe = os.pipe()
    try:
        # 1) Normal open kqueue registration + mid-stream KQ_EV_EOF
        _kq_live = _FakeKq([_FakeKev(_w_pipe, flags=0)], [])
        _w1 = PipeHangupWatcher(_w_pipe, select_mod=_FakeSelectMod(_kq_live))
        assert _w1.closed is False and _w1.is_closed() is False
        _kq_live._poll = [_FakeKev(_w_pipe, flags=_FakeSelectMod.KQ_EV_EOF)]
        assert _w1.wait_closed(0.05) is True and _w1.closed is True
        _w1.close()
        assert _kq_live.closed_kq is True

        # 2) Registration KQ_EV_ERROR with EPIPE -> marks closed immediately
        _kq_epipe = _FakeKq([_FakeKev(_w_pipe, flags=_FakeSelectMod.KQ_EV_ERROR, data=_errno.EPIPE)], [])
        _w2 = PipeHangupWatcher(_w_pipe, select_mod=_FakeSelectMod(_kq_epipe))
        assert _w2.closed is True and _kq_epipe.closed_kq is True
        _w2.close()

        # 3) Registration KQ_EV_ERROR with EINVAL/ENODEV -> falls back to poll instead of falsely marking closed!
        _kq_einval = _FakeKq([_FakeKev(_w_pipe, flags=_FakeSelectMod.KQ_EV_ERROR, data=_errno.EINVAL)], [])
        _w3 = PipeHangupWatcher(_w_pipe, select_mod=_FakeSelectMod(_kq_einval))
        assert _kq_einval.closed_kq is True and _w3.closed is False and _w3.is_closed() is False
        os.close(_r_pipe)
        _r_pipe = -1
        if hasattr(select, "poll"):
            assert _w3.is_closed() is True
        _w3.close()
    finally:
        for _pfd in (_r_pipe, _w_pipe):
            if _pfd >= 0:
                try:
                    os.close(_pfd)
                except OSError:
                    pass

    _p_map = {
        "%1": ("alpha", "@1", "1", "0", "ai", "", ""),
        "%2": ("alpha", "@1", "0", "0", "editor", "", ""),
        "%3": ("alpha", "@1", "0", "0", "", "", ""),
        "%4": ("ai-sw-99", "@9", "1", "0", "ai", "ai-sw-99", ""),
        "%5": ("ide-bare", "@2", "1", "0", "", "", ""),
    }
    _s_panes = {
        "alpha": [("%1", "ai", ""), ("%2", "editor", ""), ("%3", "", "")],
        "ide-bare": [("%5", "", "")],
    }
    assert select_dockable_ai_pane("alpha", "%1", _p_map, _s_panes) == ("%1", False)
    assert select_dockable_ai_pane("alpha", "%4", _p_map, _s_panes) == ("", False)
    assert select_dockable_ai_pane("alpha", "%999", _p_map, _s_panes) == ("%1", True)
    # Corrupted @ide_ai_pane pointing to same-session Editor (%2) must NOT dock Editor; heals to %1!
    assert select_dockable_ai_pane("alpha", "%2", _p_map, _s_panes) == ("%1", True)
    # When AI pane (%1) was killed, must NOT hijack ad-hoc split (%3) or editor (%2)
    _p_dead_ai = {k: v for k, v in _p_map.items() if k != "%1"}
    _s_dead_ai = {"alpha": [("%2", "editor", ""), ("%3", "", "")], "ide-bare": [("%5", "", "")]}
    assert select_dockable_ai_pane("alpha", "%1", _p_dead_ai, _s_dead_ai) == ("", False)
    assert select_dockable_ai_pane("ide-bare", "", _p_dead_ai, _s_dead_ai) == ("%5", True)

    _saved_xdg_cfg = os.environ.get("XDG_CONFIG_HOME")
    try:
        os.environ["XDG_CONFIG_HOME"] = _cap_dir
        _h1, _ = load_active_palette()
        _h1["BLUE"] = "#000000"
        _h2, _ = load_active_palette()
        assert _h2["BLUE"] == "#268BD2", "load_active_palette cache leaked caller mutation"
        _theme_dir = os.path.join(_cap_dir, "home-settings")
        os.makedirs(_theme_dir, exist_ok=True)
        with open(os.path.join(_theme_dir, "active-theme.theme"), "w", encoding="utf-8") as _tf:
            _tf.write('BLUE="#88C0D0"\n')
        _h3, _ = load_active_palette()
        assert _h3["BLUE"] == "#88C0D0", f"load_active_palette did not invalidate on file update: {_h3['BLUE']}"
    finally:
        if _saved_xdg_cfg is None:
            os.environ.pop("XDG_CONFIG_HOME", None)
        else:
            os.environ["XDG_CONFIG_HOME"] = _saved_xdg_cfg

    os.environ["IDE_STRICT_PATH"] = "1"
    os.environ["PATH"] = "/custom/strict/bin:/usr/bin"
    _calibrate_ide_path()
    assert os.environ["PATH"] == "/custom/strict/bin:/usr/bin"
    os.environ["IDE_STRICT_PATH"] = "0"
    os.environ["PATH"] = ""
    _calibrate_ide_path()
    assert "::" not in os.environ["PATH"], f"empty PATH calibration emitted '::': {os.environ['PATH']!r}"
finally:
    if _saved_xdg_c is None:
        os.environ.pop("XDG_CACHE_HOME", None)
    else:
        os.environ["XDG_CACHE_HOME"] = _saved_xdg_c
    if _saved_path is not None:
        os.environ["PATH"] = _saved_path
    if _saved_strict is None:
        os.environ.pop("IDE_STRICT_PATH", None)
    else:
        os.environ["IDE_STRICT_PATH"] = _saved_strict
    import shutil as _shutil_cap
    _shutil_cap.rmtree(_cap_dir, ignore_errors=True)
assert visible_width("\x1b[38;2;38;139;210malpha\x1b[0m") == 5
assert _ansi_visible_width("\x1b]8;;https://github.com/acme/repo/pull/42\x1b\\main@42\x1b]8;;\x1b\\") == 7
assert _ansi_visible_width("\t\talpha") == 21
assert _ansi_visible_width("⚠️") == 2
assert _ansi_visible_width("\U0001f6e0\ufe0f") == 2
assert _wrapped_preview_rows("x" * 49, 49) == 1
assert _wrapped_preview_rows("x" * 50, 49) == 2
assert _wrapped_preview_rows("x" * 98, 49) == 3
assert _wrapped_preview_rows("x" * 120, 0) == 1
assert _wrapped_preview_rows("\t\t\t\t" + ("x" * 32), 60) == 2
assert _wrapped_preview_rows("中" * 56, 57) == 3
assert _wrapped_preview_rows(("X" * 49) + "\tAFTER_TAB", 52, wrap_sign_w=6, tabstop=8) == 2
_saved_fzf_opts = os.environ.get("FZF_DEFAULT_OPTS")
try:
    os.environ["FZF_DEFAULT_OPTS"] = "--wrap-sign='>> ' --preview-wrap-sign='>>>=> ' --tabstop=4"
    assert _resolve_fzf_wrap_config() == (6, 4)
    assert _wrapped_preview_rows("A" * 52, 20) == 1 + ((52 - 20 + 13) // 14)
finally:
    if _saved_fzf_opts is None:
        os.environ.pop("FZF_DEFAULT_OPTS", None)
    else:
        os.environ["FZF_DEFAULT_OPTS"] = _saved_fzf_opts
assert _carry_sgr_prefix(["\x1b[38;2;42;161;152mL1\x1b[39m"]) == ""
assert _carry_sgr_prefix(["\x1b[1;38;2;42;161;152;48;2;7;54;66mFULL_ROW"]) == "\x1b[1;38;2;42;161;152;48;2;7;54;66m"
_sgr_tail = _select_preview_tail(
    ["\x1b[38;2;42;161;152m" + ("C" * 40), "C" * 40, ("C" * 20) + "\x1b[39m"],
    ["H"] * 4,
    6,
    40,
)
assert _sgr_tail[0].startswith("\x1b[38;2;42;161;152mC") and len(_sgr_tail) == 2, f"missing SGR carry-over: {_sgr_tail!r}"
assert len(_select_preview_tail([f"L{i}" for i in range(50)] + ["\x1b[0m   "], ["H"] * 6, 0, 0)) == 35
_fitted_tail = _select_preview_tail([f"L{i:02d}" for i in range(1, 41)], ["H"] * 6, 16, 49)
assert _fitted_tail[0] == "L31" and _fitted_tail[-1] == "L40" and len(_fitted_tail) == 10, f"bad fitted tail: {_fitted_tail}"
_huge_tail = _select_preview_tail(["early", "Z" * 400], ["H"] * 6, 12, 40)
assert _huge_tail == ["Z" * 400], f"oversized bottom line should still be preserved: {_huge_tail}"
assert _resolve_preview_interval(None) == 0.2
assert _resolve_preview_interval(0.001) == 0.02
assert _resolve_preview_interval(99.0) == 5.0
assert sanitize_agent_msg("\x1b[31mQuota\tlimit\x1b[0m\nhit") == "Quota limit hit"
assert sanitize_http_url("https://example.com/pr/42") == "https://example.com/pr/42"
assert sanitize_http_url("-aCalculator") == ""
assert sanitize_http_url("javascript:alert(1)") == ""
assert build_forge_pr_url("git@github.com:acme/widgets.git", "17") == "https://github.com/acme/widgets/pull/17"
assert build_forge_pr_url("https://gitlab.com/acme/group/sub.git", "9") == "https://gitlab.com/acme/group/sub/-/merge_requests/9"
assert parse_file_target("src/app.py:42:7") == ("src/app.py", "42")
assert parse_file_target("file:///tmp/demo.py#L19") == ("/tmp/demo.py", "19")
assert strip_token_wrappers("(`src/app.py:42`),") == "src/app.py:42"
assert format_attn_summary(
    [
        {"sess": "beta", "state": "DONE", "attn_ts": 5.0, "needs_attn": True},
        {"sess": "alpha", "state": "ATTN", "attn_ts": 10.0, "needs_attn": True},
        {"sess": "gamma", "state": "WORKING", "attn_ts": 0.0, "needs_attn": False},
    ]
) == "alpha +1"
assert hex_to_fg("#268BD2") == "\033[38;2;38;139;210m"

import socket as _socket

_short_tmp_base = "/tmp" if os.path.isdir("/tmp") else None
_sock_tmp = tempfile.mkdtemp(prefix="ide-live-sock.", dir=_short_tmp_base)
try:
    _live_p = os.path.join(_sock_tmp, "live.sock")
    _dead_p = os.path.join(_sock_tmp, "dead.sock")
    _reg_p = os.path.join(_sock_tmp, "regular.txt")
    with open(_reg_p, "w", encoding="utf-8") as _rf:
        _rf.write("not a socket\n")
    _ls = _socket.socket(_socket.AF_UNIX, _socket.SOCK_STREAM)
    _ls.bind(_live_p)
    _ls.listen(1)
    _ds = _socket.socket(_socket.AF_UNIX, _socket.SOCK_STREAM)
    _ds.bind(_dead_p)
    _ds.close()
    try:
        assert is_live_socket(_live_p) is True
        assert is_live_socket(_dead_p) is False
        assert is_live_socket(_reg_p) is False
        assert is_live_socket(os.path.join(_sock_tmp, "missing.sock")) is False
        assert is_live_socket(os.path.join(_sock_tmp, "x" * 130 + ".sock")) is False
        os.chmod(_live_p, 0)
        try:
            if os.geteuid() != 0:
                assert is_live_socket(_live_p) is False
        finally:
            os.chmod(_live_p, 0o600)
    finally:
        _ls.close()
    _child_sleep = subprocess.Popen(["sleep", "5"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _child_py_listen = subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(5)", "--headless", "--listen", "/tmp/fake-nvim-ps.sock"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        _tree = pane_tree_pids(str(os.getpid()))
        assert _tree and _tree[0] == os.getpid() and _child_sleep.pid in _tree, f"unexpected pane_tree_pids: {_tree}"
        # Exercise non-/proc BSD/macOS `ps` fallbacks (`force_ps=True`)
        assert os.getpid() in pids_with_children({os.getpid()}, force_ps=True)
        _ps_order, _ps_parents, _, _ = _pane_tree_snapshot(str(os.getpid()), force_ps=True)
        assert _child_sleep.pid in _ps_order and _ps_parents.get(_child_sleep.pid) == os.getpid()
        _ps_cmd_map = _ps_batch_nvim_cmdlines([_child_py_listen.pid])
        assert _ps_cmd_map.get(_child_py_listen.pid) == (True, ["/tmp/fake-nvim-ps.sock"]), f"bad _ps_batch_nvim_cmdlines: {_ps_cmd_map}"
    finally:
        for _cp in (_child_sleep, _child_py_listen):
            _cp.terminate()
            _cp.wait(timeout=2)
finally:
    import shutil as _sock_shutil

    _sock_shutil.rmtree(_sock_tmp, ignore_errors=True)

# 4. Isolated temp-dir symlink resolution + <50ms cold CLI latency budget (--keys, --help, --list --plain)
tmp_root = tempfile.mkdtemp(prefix="ide-mod-lat.", dir=_short_tmp_base)
try:
    sym_dir = os.path.join(tmp_root, "isolated_bin")
    run_dir = os.path.join(tmp_root, "run")
    cache_dir = os.path.join(tmp_root, "cache")
    os.makedirs(sym_dir, mode=0o700)
    os.makedirs(run_dir, mode=0o700)
    os.makedirs(cache_dir, mode=0o700)
    sym_ide = os.path.join(sym_dir, "ide")
    os.symlink(ide_entry, sym_ide)

    env = {
        **os.environ,
        "TMUX": "",
        "TMUX_PANE": "",
        "NVIM_IDE_SOCKET": "",
        "IDE_SESSION": "",
        "TMUX_TMPDIR": run_dir,
        "XDG_RUNTIME_DIR": run_dir,
        "XDG_CACHE_HOME": cache_dir,
        "PYTHONPYCACHEPREFIX": "",
        "IDE_KEYS_NO_WAIT": "1",
    }

    # Verify Option A MsgPack-RPC codec, zero-subprocess AF_UNIX Neovim RPC fast-path, and XDG bytecode cache
    from ide_lib.constants import which_executable
    from ide_lib.nvim_rpc import (
        _IncompleteMsgPack,
        _NVIM_FALLBACK_CACHE,
        _mp_decode,
        _mp_encode_str,
        nvim_remote_expr,
        nvim_remote_send,
    )

    for _s_sample in ("", "ok", "x" * 40, "y" * 300):
        _enc_b = _mp_encode_str(_s_sample)
        _dec_v, _dec_pos = _mp_decode(memoryview(_enc_b), 0)
        assert _dec_v == _s_sample and _dec_pos == len(_enc_b)
    _trunc_caught = False
    try:
        _mp_decode(memoryview(_mp_encode_str("truncated")[:-2]), 0)
    except _IncompleteMsgPack:
        _trunc_caught = True
    assert _trunc_caught is True

    _real_nvim = which_executable("nvim")
    if _real_nvim:
        _rpc_sock = os.path.join(run_dir, "rpc-unit.sock")
        _spy_log = os.path.join(run_dir, "spy-nvim.log")
        _spy_bin_dir = os.path.join(tmp_root, "spy_bin")
        os.makedirs(_spy_bin_dir, mode=0o700)
        _spy_nvim = os.path.join(_spy_bin_dir, "nvim")
        with open(_spy_nvim, "w", encoding="utf-8") as _sf:
            _sf.write(f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> {_spy_log!r}\nexit 0\n")
        os.chmod(_spy_nvim, 0o755)
        _nv_srv = subprocess.Popen(
            [_real_nvim, "--headless", "-u", "NONE", "-i", "NONE", "--listen", _rpc_sock],
            env={**env, "NVIM_LOG_FILE": "/dev/null"},
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            for _ in range(80):
                if is_live_socket(_rpc_sock):
                    break
                time.sleep(0.025)
            assert is_live_socket(_rpc_sock), "rpc-unit.sock did not become live"
            _saved_p = os.environ.get("PATH", "")
            try:
                os.environ["PATH"] = f"{_spy_bin_dir}:{_saved_p}"
                _MISE_TOOL_BIN_CACHE.clear()
                _NVIM_FALLBACK_CACHE.clear()
                assert nvim_remote_expr(_rpc_sock, "19 + 23") == "42"
                assert not os.path.exists(_spy_log), "nvim_remote_expr spawned nvim subprocess instead of AF_UNIX MsgPack-RPC"
                assert nvim_remote_send(_rpc_sock, "<C-\\><C-n><Cmd>qall!<CR>") is True
                assert not os.path.exists(_spy_log), "nvim_remote_send spawned nvim subprocess instead of AF_UNIX MsgPack-RPC"
            finally:
                os.environ["PATH"] = _saved_p
                _MISE_TOOL_BIN_CACHE.clear()
                _NVIM_FALLBACK_CACHE.clear()
            _nv_srv.wait(timeout=3.0)
        finally:
            if _nv_srv.poll() is None:
                _nv_srv.terminate()
                _nv_srv.wait(timeout=2.0)

    # Trigger Python CLI path (--unknown-opt) and verify PYTHONPYCACHEPREFIX populates XDG cache, never bin/ide_lib/__pycache__
    subprocess.run([ide_entry, "--help"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    _py_res = subprocess.run([ide_entry, "--definitely-unknown-flag"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert _py_res.returncode != 0
    assert os.path.isdir(os.path.join(cache_dir, "home-settings", "pycache")), "expected XDG pycache dir to be populated"
    assert not os.path.exists(os.path.join(ide_lib_dir, "__pycache__")), "bin/ide_lib/__pycache__ must never be created"

    checks = (
        (["keys"], "IDE Workspace & Editor Keybindings"),
        (["--help"], USAGE_TEXT + "\n"),
        (["list", "--plain"], ""),
        (["list", "--json"], "[]\n"),
    )
    for target_bin in (ide_entry, sym_ide):
        for flag_args, exp_out in checks:
            subprocess.run([target_bin, *flag_args], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
            samples = []
            last_out = ""
            for _ in range(3):
                t0 = time.monotonic()
                res = subprocess.run([target_bin, *flag_args], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
                samples.append((time.monotonic() - t0) * 1000.0)
                assert res.returncode == 0
                last_out = res.stdout
            if flag_args in (["--help"], ["list", "--json"]):
                assert last_out == exp_out, f"bin/ide {flag_args} fast-path diverged: {last_out!r} != {exp_out!r}"
            elif exp_out:
                assert exp_out in last_out, f"unexpected stdout for {target_bin} {flag_args}: {last_out!r}"
            else:
                assert last_out.strip() == "", f"expected empty list --plain stdout, got {last_out!r}"
            best_ms = min(samples)
            assert best_ms < 50.0, (
                f"cold CLI latency budget (<50ms) exceeded for {target_bin} {flag_args}: {best_ms:.1f}ms (samples={samples})"
            )
finally:
    import shutil as _shutil

    _shutil.rmtree(tmp_root, ignore_errors=True)

# Verify un-`-B` in-process IDE_PY_SRC execution sets sys.dont_write_bytecode = True (never polluting bin/ide_lib/__pycache__)
subprocess.run(
    [
        sys.executable,
        "-c",
        (
            "import os, re, sys; "
            "p = sys.argv[1]; txt = open(p, encoding='utf-8').read(); "
            "m = re.search(r\"IDE_PY_SRC <<\\s*'PY'[^\\n]*\\n(.*?)\\nPY\\n\", txt, re.S); "
            "ns = {'__name__': 'ide_mod'}; exec(compile(m.group(1), p, 'exec'), ns); "
            "assert sys.dont_write_bytecode is True"
        ),
        ide_entry,
    ],
    env={k: v for k, v in os.environ.items() if k != "PYTHONPYCACHEPREFIX"},
    check=True,
)
assert not os.path.exists(os.path.join(ide_lib_dir, "__pycache__")), "bin/ide_lib/__pycache__ must not be created"

print("MODULAR_ARCH_OK")
PY
)" || true
if grep -Fq "MODULAR_ARCH_OK" <<< "$MODULAR_TEST_OUT"; then
    pass "bin/ide + bin/ide_lib modular architecture: thin bootstrapper, Python 3.9 AST compliance, acyclic DAG, domain unit tests, isolated symlink resolution, and <50ms cold CLI latency"
else
    fail "bin/ide + bin/ide_lib modular architecture suite" "Suite failed: $MODULAR_TEST_OUT"
fi

# End-to-end hermetic multi-session workspace switcher, parked-window exclusion, live ANSI preview, and context dispatch tests
if command -v tmux >/dev/null 2>&1; then
    FLEET_SANDBOX_ROOT="$(make_sandbox_dir)"
    FLEET_TMUX_TMP="$(make_tmux_sandbox_dir)"
    FLEET_TEST_OUT="$(python3 -B - "$SCRIPT_DIR" "$FLEET_SANDBOX_ROOT" "$FLEET_TMUX_TMP" 2>&1 <<'PY'
import fcntl
import hashlib
import json
import os
import pty
import re
import select
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

repo_dir = sys.argv[1]
root = sys.argv[2]
tmux_tmp = sys.argv[3]
ide_src = os.path.join(repo_dir, "bin", "ide")
tmux_conf_src = os.path.join(repo_dir, "dotfiles", ".tmux.conf")
orig_home = os.path.expanduser("~")
orig_xdg_data = os.environ.get("XDG_DATA_HOME") or os.path.join(orig_home, ".local", "share")
orig_xdg_cache = os.environ.get("XDG_CACHE_HOME") or os.path.join(orig_home, ".cache")
orig_xdg_state = os.environ.get("XDG_STATE_HOME") or os.path.join(orig_home, ".local", "state")

client_proc = None
client_mfd = None
client2_proc = None
client2_mfd = None
base_env = {}

def run_cmd(args, env=None, input_text=None, check=True, cwd=None):
    e = dict(base_env if env is None else env)
    r = subprocess.run(
        args,
        input=input_text,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=e,
        cwd=cwd,
        check=False,
    )
    if check and r.returncode != 0:
        diag = ""
        if args[:2] == ["tmux", "switch-client"]:
            cl_diag = subprocess.run(["tmux", "list-clients", "-F", "#{client_name} sess=#{session_name} flags=#{client_flags}"], env={**base_env, "TMUX": ""}, capture_output=True, text=True).stdout
            s_diag = subprocess.run(["tmux", "list-sessions", "-F", "#{session_name} att=#{session_attached}"], env={**base_env, "TMUX": ""}, capture_output=True, text=True).stdout
            diag = f" | clients={cl_diag!r} sessions={s_diag!r}"
        raise RuntimeError(f"Command {args} failed rc={r.returncode} stderr={r.stderr!r} stdout={r.stdout!r}{diag}")
    return r

def tmux(*args, check=False):
    return run_cmd(["tmux", *args], env={**base_env, "TMUX": "", "TMUX_PANE": ""}, check=check)

def tmux_out(*args):
    r = tmux(*args, check=False)
    return r.stdout.rstrip("\n") if r.returncode == 0 else ""

def wait_until(pred, timeout=3.0, step=0.03):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        val = pred()
        if val:
            return val
        time.sleep(step)
    return pred()

def nvim_expr_eq(sock, expr, expected):
    if not os.path.exists(sock):
        return False
    try:
        r = subprocess.run(
            ["nvim", "--headless", "--server", sock, "--remote-expr", expr],
            env=base_env,
            text=True,
            capture_output=True,
            timeout=2,
            check=False,
        )
        return r.returncode == 0 and r.stdout.strip() == expected
    except Exception:
        return False

try:
    thome = os.path.join(root, "home")
    xdg_cfg = os.path.join(thome, ".config")
    xdg_cache = os.path.join(thome, ".cache")
    xdg_run = os.path.join(tmux_tmp, "run")
    bin_dir = os.path.join(thome, ".local", "bin")
    for d in (thome, tmux_tmp, xdg_cfg, xdg_cache, xdg_run, bin_dir):
        os.makedirs(d, mode=0o700, exist_ok=True)

    ide_bin = os.path.join(bin_dir, "ide")
    os.symlink(ide_src, ide_bin)
    os.symlink(tmux_conf_src, os.path.join(thome, ".tmux.conf"))

    clean_path = f"{bin_dir}:{os.environ.get('PATH', '/usr/bin:/bin')}"
    _raw_lang = os.environ.get("LANG", "")
    _utf8_lang = (
        _raw_lang
        if ("UTF-8" in _raw_lang.upper() or "UTF8" in _raw_lang.upper())
        else ("en_US.UTF-8" if sys.platform == "darwin" else "C.UTF-8")
    )
    base_env = {
        "HOME": thome,
        "PATH": clean_path,
        "TMUX_TMPDIR": tmux_tmp,
        "XDG_CONFIG_HOME": xdg_cfg,
        "XDG_CACHE_HOME": xdg_cache,
        "XDG_RUNTIME_DIR": xdg_run,
        "_ZO_DATA_DIR": os.path.join(thome, "zoxide"),
        "TERM": "xterm-256color",
        "LANG": _utf8_lang,
    }

    # 1. Server-down safety for list, list --plain, list --json, switch, and send error paths
    r_plain0 = run_cmd([ide_bin, "list", "--plain"], env={**base_env, "TMUX": ""}, check=False)
    assert r_plain0.returncode == 0 and r_plain0.stdout.strip() == "", f"plain0={r_plain0}"
    r_json0 = run_cmd([ide_bin, "list", "--json"], env={**base_env, "TMUX": ""}, check=False)
    assert r_json0.returncode == 0 and json.loads(r_json0.stdout) == [], f"json0={r_json0}"
    r_list0 = run_cmd([ide_bin, "list"], env={**base_env, "TMUX": ""}, check=False)
    assert r_list0.returncode == 0 and "No active IDE sessions." in r_list0.stdout, f"list0={r_list0.stdout}"
    r_sess0 = run_cmd([ide_bin, "switch"], env={**base_env, "TMUX": ""}, check=False)
    assert r_sess0.returncode == 0 and "No active IDE sessions." in r_sess0.stdout, f"sess0={r_sess0.stdout}"
    r_ref0 = run_cmd([ide_bin, "refresh"], env={**base_env, "TMUX": ""}, check=False)
    assert r_ref0.returncode == 0 and "No active IDE sessions." in r_ref0.stdout, f"ref0={r_ref0.stdout}"
    r_ref_missing0 = run_cmd([ide_bin, "refresh", "missing-sess"], env={**base_env, "TMUX": ""}, check=False)
    assert r_ref_missing0.returncode != 0, "expected non-zero when refresh targets missing session with server down"
    r_send_missing_mode = run_cmd([ide_bin, "send"], env={**base_env, "TMUX": ""}, check=False)
    assert r_send_missing_mode.returncode != 0, "expected non-zero when send has no payload"
    r_send_missing_sess = run_cmd([ide_bin, "send", "--text", "hi", "missing-sess"], env={**base_env, "TMUX": ""}, check=False)
    assert r_send_missing_sess.returncode != 0, "expected non-zero when send targets missing session"

    # Boot isolated server with non-IDE session + ai-*/agy-* popup sessions (all must be excluded)
    tmux("-f", os.path.join(thome, ".tmux.conf"), "new-session", "-d", "-s", "plain-non-ide", "-x", "160", "-y", "48", "exec sleep 300", check=True)
    tmux("new-session", "-d", "-s", "ai-alpha-ws", "-x", "120", "-y", "40", "exec sleep 300", check=True)
    tmux("new-session", "-d", "-s", "agy-beta-ws", "-x", "120", "-y", "40", "exec sleep 300", check=True)
    tmux("set-option", "-q", "-t", "=ai-alpha-ws:", "@ide_session", "ai-alpha-ws", check=True)
    tmux("set-option", "-q", "-t", "=agy-beta-ws:", "@ide_session", "agy-beta-ws", check=True)

    # 1b. Zero-session behavior for `ide -s` / `ide --sessions`:
    # - Non-interactive callers preserve "No active IDE sessions."
    # - Interactive TTY without `fzf` preserves "No active IDE sessions."
    # - Interactive TTY (or IDE_IN_POPUP=1) with `fzf` opens `New IDE >` directly (Esc cancels cleanly without looping; Enter launches)
    r_sess_non_tty = run_cmd([ide_bin, "-s"], env={**base_env, "TMUX": ""}, check=False)
    assert r_sess_non_tty.returncode == 0 and "No active IDE sessions." in r_sess_non_tty.stdout, f"sess_non_tty={r_sess_non_tty}"

    def _run_pty_cmd(argv, env_dict, timeout_s=5.0):
        m_fd, s_fd = pty.openpty()
        winsz = struct.pack("HHHH", 40, 140, 0, 0)
        for _fd in (s_fd, m_fd):
            try:
                fcntl.ioctl(_fd, termios.TIOCSWINSZ, winsz)
            except OSError:
                pass

        def _attach_ctty():
            os.setsid()
            for _tty_fd in (0, 1):
                try:
                    fcntl.ioctl(_tty_fd, termios.TIOCSCTTY, 0)
                    break
                except OSError:
                    pass

        p = subprocess.Popen(
            argv,
            stdin=s_fd,
            stdout=s_fd,
            stderr=s_fd,
            env=env_dict,
            preexec_fn=_attach_ctty,
            close_fds=True,
        )
        os.close(s_fd)
        buf = bytearray()
        try:
            deadline = time.monotonic() + timeout_s
            while time.monotonic() < deadline:
                r_ready, _, _ = select.select([m_fd], [], [], 0.05)
                if r_ready:
                    try:
                        chunk = os.read(m_fd, 8192)
                        if chunk:
                            buf.extend(chunk)
                            if b"\x1b[6n" in chunk:
                                os.write(m_fd, b"\x1b[1;1R")
                            if b"\x1b[5n" in chunk:
                                os.write(m_fd, b"\x1b[0n")
                    except OSError:
                        break
                if p.poll() is not None:
                    while True:
                        r_rem, _, _ = select.select([m_fd], [], [], 0.02)
                        if not r_rem:
                            break
                        try:
                            chunk = os.read(m_fd, 8192)
                            if not chunk:
                                break
                            buf.extend(chunk)
                        except OSError:
                            break
                    break
            rc_out = p.wait(timeout=2.0)
        finally:
            if p.poll() is None:
                try:
                    p.kill()
                    p.wait(timeout=2.0)
                except Exception:
                    pass
            try:
                os.close(m_fd)
            except OSError:
                pass
        return rc_out, buf.decode("utf-8", errors="replace")

    no_fzf_dir = os.path.join(root, "no_fzf_bin")
    os.makedirs(no_fzf_dir, exist_ok=True)
    for tool_nm in ("bash", "python3", "tmux", "sh"):
        src_t = shutil.which(tool_nm)
        if src_t:
            os.symlink(src_t, os.path.join(no_fzf_dir, tool_nm))
    rc_no_fzf, out_no_fzf = _run_pty_cmd([ide_bin, "-s"], {**base_env, "IDE_STRICT_PATH": "1", "PATH": no_fzf_dir, "TMUX": "", "TMUX_PANE": ""})
    assert rc_no_fzf == 0 and "No active IDE sessions." in out_no_fzf, f"TTY without fzf should print No active IDE sessions: rc={rc_no_fzf} out={out_no_fzf!r}"

    zero_esc_log = os.path.join(root, "zero_esc_fzf.log")
    zero_esc_fzf = os.path.join(root, "zero_esc_fzf.py")
    with open(zero_esc_fzf, "w", encoding="utf-8") as zef:
        zef.write(
            "#!/usr/bin/env python3\n"
            "import sys\n"
            f"with open({zero_esc_log!r}, 'a', encoding='utf-8') as f:\n"
            "    f.write(' '.join(sys.argv[1:]) + '\\n')\n"
            "sys.exit(130)\n"
        )
    os.chmod(zero_esc_fzf, 0o755)
    rc_zero_esc, _ = _run_pty_cmd([ide_bin, "-s"], {**base_env, "IDE_FZF_BIN": zero_esc_fzf, "TMUX": "", "TMUX_PANE": ""})
    esc_invocations = open(zero_esc_log, encoding="utf-8").read().splitlines()
    assert rc_zero_esc == 0 and len(esc_invocations) == 1, f"expected 1 New IDE fzf call and exit 0 on Esc when 0 sessions exist, got rc={rc_zero_esc} calls={esc_invocations}"
    assert "--prompt=New IDE > " in esc_invocations[0] and "Esc: cancel" in esc_invocations[0] and "back to sessions" not in esc_invocations[0], (
        f"unexpected 0-session fzf args: {esc_invocations[0]}"
    )

    zero_ws_dir = os.path.join(thome, "zero-boot-ws")
    os.makedirs(zero_ws_dir, exist_ok=True)
    stub_agy = os.path.join(bin_dir, "agy")
    with open(stub_agy, "w", encoding="utf-8") as saf:
        saf.write("#!/bin/sh\nexec sleep 300\n")
    os.chmod(stub_agy, 0o755)
    zero_pick_fzf = os.path.join(root, "zero_pick_fzf.py")
    with open(zero_pick_fzf, "w", encoding="utf-8") as zpf:
        zpf.write(
            "#!/usr/bin/env python3\n"
            "import sys\n"
            "lines = [l.rstrip('\\n') for l in sys.stdin if l.strip()]\n"
            "picked = next(l for l in lines if 'zero-boot-ws' in l)\n"
            "print(picked)\n"
        )
    os.chmod(zero_pick_fzf, 0o755)
    # Attach temporary client to plain-non-ide and run `ide -s` inside popup mode with 0 IDE sessions -> spawns & switches to zero-boot-ws!
    z_mfd, z_sfd = pty.openpty()
    fcntl.ioctl(z_mfd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 140, 0, 0))
    z_proc = subprocess.Popen(
        ["tmux", "attach-session", "-t", "=plain-non-ide"],
        stdin=z_sfd,
        stdout=z_sfd,
        stderr=z_sfd,
        env={**base_env, "TMUX": "", "TMUX_PANE": ""},
        start_new_session=True,
        close_fds=True,
    )
    os.close(z_sfd)
    assert wait_until(lambda: bool(tmux_out("list-clients", "-F", "#{client_name}").strip()))
    z_client = tmux_out("list-clients", "-F", "#{client_name}").splitlines()[0].strip()
    z_tmux_env = tmux_out("display-message", "-p", "-t", "=plain-non-ide:", "#{socket_path},#{pid},#{session_id}")
    r_zero_pop = run_cmd(
        [ide_bin, "-s"],
        env={**base_env, "IDE_CLIENT": z_client, "IDE_FZF_BIN": zero_pick_fzf, "TMUX": z_tmux_env, "TMUX_PANE": ""},
        check=True,
    )
    assert r_zero_pop.returncode == 0
    assert tmux("has-session", "-t", "=zero-boot-ws", check=False).returncode == 0, "0-session ide -s did not spawn chosen workspace"
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", z_client, "#{session_name}") == "zero-boot-ws"), "0-session ide -s did not switch client to zero-boot-ws"
    tmux("switch-client", "-c", z_client, "-t", "=plain-non-ide", check=True)
    run_cmd([ide_bin, "quit", "--force", "zero-boot-ws"], env={**base_env, "TMUX": ""}, check=True)
    tmux("detach-client", "-t", z_client, check=False)
    try:
        z_proc.wait(timeout=2.0)
    except Exception:
        z_proc.kill()
        z_proc.wait(timeout=2.0)
    os.close(z_mfd)
    os.unlink(stub_agy)
    shutil.rmtree(zero_ws_dir, ignore_errors=True)

    def make_ws(name, ai_cmd="exec sleep 300", ed_cmd="exec sleep 300", ai_cli="agy", git_branch="", git_dirty=False, in_home=False):
        ws_parent = os.path.join(thome, "projects") if in_home else os.path.join(root, "ws")
        ws_dir = os.path.join(ws_parent, name)
        os.makedirs(os.path.join(ws_dir, "sub"), exist_ok=True)
        with open(os.path.join(ws_dir, "README.md"), "w", encoding="utf-8") as f:
            f.write(f"# {name}\nline2\nline3\n")
        with open(os.path.join(ws_dir, "sub", "mod.py"), "w", encoding="utf-8") as f:
            f.write("\n".join(f"line_{i}" for i in range(1, 25)) + "\n")
        if git_branch:
            run_cmd(["git", "-C", ws_dir, "init", "-q", "-b", git_branch], check=True)
            run_cmd(["git", "-C", ws_dir, "config", "user.email", "test@example.com"], check=True)
            run_cmd(["git", "-C", ws_dir, "config", "user.name", "Test User"], check=True)
            run_cmd(["git", "-C", ws_dir, "add", "."], check=True)
            run_cmd(["git", "-C", ws_dir, "commit", "-q", "-m", "init"], check=True)
            if git_dirty:
                with open(os.path.join(ws_dir, "README.md"), "a", encoding="utf-8") as f:
                    f.write("dirty\n")

        sock_path = os.path.join(xdg_run, f"nvim-ide-{name}.sock")
        env_flags = [
            "-e", f"IDE_SESSION={name}",
            "-e", f"IDE_AI_CLI={ai_cli}",
            "-e", f"NVIM_IDE_SOCKET={sock_path}",
            "-e", f"IDE_INITIAL_ROOT={ws_dir}",
        ]
        ai_shell = "/bin/sh" if ai_cmd == "exec /bin/sh" else f"/bin/sh -c {shlex.quote(ai_cmd + '; :')}"
        ed_shell = "exec sleep 300" if ed_cmd == "exec sleep 300" else f"/bin/sh -c {shlex.quote(ed_cmd + '; :')}"
        init = tmux_out(
            "new-session", "-d", "-P", "-F", "#{pane_id}\t#{window_id}",
            "-s", name, "-n", "ide", "-c", ws_dir, "-x", "160", "-y", "48",
            *env_flags, ai_shell,
        )
        p_ai, m_win = init.split("\t")
        p_ed = tmux_out("split-window", "-h", "-P", "-F", "#{pane_id}", "-t", p_ai, "-l", "50%", "-c", ws_dir, *env_flags, ed_shell)
        p_tm = tmux_out("split-window", "-f", "-v", "-P", "-F", "#{pane_id}", "-t", m_win, "-l", "25%", "-c", ws_dir, *env_flags, "exec /bin/sh")
        tmux(
            "set-option", "-w", "-t", m_win, "automatic-rename", "off", ";",
            "set-option", "-w", "-t", m_win, "allow-rename", "off", ";",
            "set-option", "-p", "-t", p_ai, "@ide_role", "ai", ";",
            "set-option", "-p", "-t", p_ed, "@ide_role", "editor", ";",
            "set-option", "-p", "-t", p_tm, "@ide_role", "term", ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_session", name, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_ai_cli", ai_cli, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_socket", sock_path, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_initial_root", ws_dir, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_workdir", ws_dir, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_main_win", m_win, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_ai_pane", p_ai, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_editor_pane", p_ed, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_term_pane", p_tm, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_layout_mode", "3pane", ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_ai_parked", "0", ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_ed_parked", "0", ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_term_parked", "0", ";",
            "set-environment", "-t", f"={name}", "IDE_SESSION", name, ";",
            "select-pane", "-t", p_ai,
            check=True,
        )
        return {"dir": ws_dir, "win": m_win, "ai": p_ai, "ed": p_ed, "tm": p_tm}

    def sess_env(sess, pane=""):
        meta = tmux_out("display-message", "-p", "-t", f"={sess}:", "#{socket_path},#{pid},#{session_id}\t#{pane_id}")
        t_env, p_id = meta.split("\t")
        return {**base_env, "TMUX": t_env, "TMUX_PANE": pane or p_id, "IDE_SESSION": sess}

    # 2. Create 3 IDE workspaces with distinct agents, Git states, and home-shortened vs non-home paths
    ws_alpha = make_ws(
        "alpha-ws",
        ai_cmd="printf '\\033[36mALPHA_AI_VIEWPORT_LINE\\033[0m\\n'; sleep 300",
        ed_cmd="printf 'ALPHA_EDITOR_VIEWPORT_LINE\\n'; sleep 300",
        ai_cli="claude",
        git_branch="feat/switcher",
        git_dirty=True,
        in_home=True,
    )
    ws_beta = make_ws(
        "beta-ws",
        ai_cmd="printf 'BETA_AI_READY\\n'; sleep 300",
        ed_cmd="printf 'BETA_EDITOR_VISIBLE_LINE\\n'; sleep 300",
        ai_cli="codex",
        git_branch="main",
        git_dirty=False,
        in_home=True,
    )
    ws_gamma = make_ws(
        "gamma-ws",
        ai_cmd="printf 'GAMMA_SHELL_VIEW\\n'; sleep 300",
        ai_cli="agy",
        git_branch="",
        in_home=False,
    )

    assert wait_until(
        lambda: "ALPHA_AI_VIEWPORT_LINE" in tmux_out("capture-pane", "-p", "-t", ws_alpha["ai"])
        and "BETA_EDITOR_VISIBLE_LINE" in tmux_out("capture-pane", "-p", "-t", ws_beta["ed"])
        and "GAMMA_SHELL_VIEW" in tmux_out("capture-pane", "-p", "-t", ws_gamma["ai"]),
        timeout=4.0,
    ), "timed out waiting for workspace pane viewports"

    # Wait past gamma-ws's integer timestamp so send-keys bumps beta-ws #{window_activity} deterministically
    gamma_ts = max(
        (int(x) for x in tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{session_activity} #{window_activity}").split() if x.isdigit()),
        default=int(time.time()),
    )
    while int(time.time()) <= gamma_ts:
        time.sleep(0.05)
    tmux("send-keys", "-t", ws_beta["tm"], "echo activity_bump", "C-m", check=True)
    assert wait_until(
        lambda: "activity_bump" in tmux_out("capture-pane", "-p", "-t", ws_beta["tm"])
        and int(tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{window_activity}") or "0") > gamma_ts
    )

    plain_lines = run_cmd([ide_bin, "list", "--plain"], env=sess_env("alpha-ws"), check=True).stdout.splitlines()
    assert plain_lines == ["alpha-ws", "beta-ws", "gamma-ws"], f"unexpected list --plain order: {plain_lines}"
    assert "plain-non-ide" not in plain_lines and "ai-alpha-ws" not in plain_lines and "agy-beta-ws" not in plain_lines

    json_fleet = json.loads(run_cmd([ide_bin, "list", "--json"], env=sess_env("alpha-ws"), check=True).stdout)
    assert [it["session"] for it in json_fleet] == ["alpha-ws", "beta-ws", "gamma-ws"], f"unexpected list --json order: {json_fleet}"
    assert json_fleet[0]["agent"] == "claude" and json_fleet[0]["is_current"] is True and json_fleet[0]["git_branch"] == "feat/switcher" and json_fleet[0]["git_dirty"] is True, f"bad json row0: {json_fleet[0]}"
    assert json_fleet[1]["agent"] == "codex" and json_fleet[1]["is_current"] is False and json_fleet[1]["git_branch"] == "main" and json_fleet[1]["git_dirty"] is False, f"bad json row1: {json_fleet[1]}"
    assert set(json_fleet[0].keys()) >= {"session", "agent", "state", "state_label", "state_ts", "needs_attention", "attention_ts", "message", "workdir", "git_branch", "git_dirty", "git_detail", "git_pr_url", "worktree_root", "worktree_peers", "active_role", "attached", "is_current", "quit_error"}, f"missing json keys: {json_fleet[0].keys()}"

    list_out = run_cmd([ide_bin, "list"], env=sess_env("alpha-ws"), check=True).stdout
    list_lines = [ln for ln in list_out.splitlines() if ln.strip()]
    assert "SESSION" in list_lines[0] and "AGENT" in list_lines[0] and "STATE" in list_lines[0] and "BRANCH" in list_lines[0] and "WORKSPACE" in list_lines[0], f"bad header: {list_lines[0]}"
    assert list_lines[1].startswith("* alpha-ws") and "claude" in list_lines[1] and " - " in list_lines[1] and "feat/switcher*" in list_lines[1] and "~/projects/alpha-ws" in list_lines[1], f"bad row1: {list_lines[1]}"
    assert "beta-ws" in list_lines[2] and "codex" in list_lines[2] and " - " in list_lines[2] and "main" in list_lines[2] and "main*" not in list_lines[2] and "~/projects/beta-ws" in list_lines[2], f"bad row2: {list_lines[2]}"
    assert "gamma-ws" in list_lines[3] and "agy" in list_lines[3] and " - " in list_lines[3], f"bad row3: {list_lines[3]}"

    # 3. Live ANSI _internal session-preview & _ide_park_* exclusion
    prev_alpha = run_cmd([ide_bin, "_internal", "session-preview", "alpha-ws"], env={**sess_env("alpha-ws"), "NO_COLOR": ""}, check=True).stdout
    assert "alpha-ws" in prev_alpha and "claude" in prev_alpha and "State:" in prev_alpha and "feat/switcher (" in prev_alpha, f"bad alpha preview header: {prev_alpha}"
    assert "\x1b[36mALPHA_AI_VIEWPORT_LINE" in prev_alpha, f"expected live ANSI sequence from AI pane in preview: {prev_alpha!r}"

    # Park beta-ws AI pane into _ide_park_ai -> preview must skip _ide_park_ai and render visible Editor pane instead!
    run_cmd([ide_bin, "_internal", "park", "ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_parked") == "1"
    prev_beta_parked = run_cmd([ide_bin, "_internal", "session-preview", "beta-ws"], env=sess_env("alpha-ws"), check=True).stdout
    assert "BETA_EDITOR_VISIBLE_LINE" in prev_beta_parked and "BETA_AI_READY" not in prev_beta_parked, f"parked _ide_park_ai leaked into preview: {prev_beta_parked}"

    # Non-VCS preview uses calm BASE01 (#586E75 -> 88;110;117), never Green (#859900 -> 133;153;0)
    prev_gamma = run_cmd([ide_bin, "_internal", "session-preview", "gamma-ws"], env={**sess_env("alpha-ws"), "NO_COLOR": ""}, check=True).stdout
    git_line_gamma = next((ln for ln in prev_gamma.splitlines() if "VCS      :" in ln), "")
    assert "not a repository" in git_line_gamma and "38;2;88;110;117mnot a repository" in git_line_gamma, f"non-repo line wrong color: {git_line_gamma!r}"
    prev_missing = run_cmd([ide_bin, "_internal", "session-preview", "no-such-ws"], env=sess_env("alpha-ws"), check=True).stdout
    assert "Session is no longer active." in prev_missing

    # 4. Attach real PTY client to alpha-ws & verify status_click() column accuracy on calm 3-state status bar
    def set_ctty(sfd):
        os.setsid()
        fcntl.ioctl(sfd, termios.TIOCSCTTY, 0)

    client_mfd, client_sfd = pty.openpty()
    fcntl.ioctl(client_sfd, termios.TIOCSWINSZ, struct.pack("HHHH", 48, 160, 0, 0))
    client_proc = subprocess.Popen(
        ["tmux", "attach-session", "-t", "=alpha-ws"],
        stdin=client_sfd,
        stdout=client_sfd,
        stderr=client_sfd,
        env={**base_env, "TMUX": "", "TMUX_PANE": ""},
        close_fds=True,
        preexec_fn=lambda sfd=client_sfd: set_ctty(sfd),
    )
    os.close(client_sfd)

    def drain_pty():
        while True:
            r, _, _ = select.select([client_mfd], [], [], 0)
            if not r:
                break
            try:
                if not os.read(client_mfd, 8192):
                    break
            except OSError:
                break

    client_name = wait_until(lambda: (drain_pty() or tmux_out("list-clients", "-t", "=alpha-ws", "-F", "#{client_name}").strip()))
    assert client_name, "failed to attach PTY tmux client to alpha-ws"

    run_cmd([ide_bin, "_internal", "focus", "editor", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    sleft_raw = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:status-left}")
    wcur_raw = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:window-status-current-format}")
    strip_tags = lambda s: re.sub(r"#\[[^\]]*\]", "", s)
    sleft_plain = strip_tags(sleft_raw)
    wcur_plain = strip_tags(wcur_raw)
    ed_col = len(sleft_plain) + wcur_plain.index("Editor") + 2
    sh_col = len(sleft_plain) + wcur_plain.index("Shell") + 2

    run_cmd([ide_bin, "_internal", "status-click", str(sh_col), "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term"
    run_cmd([ide_bin, "_internal", "status-click", str(ed_col), "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["tm"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor"

    # 5. Interactive Workspace Switcher (ide -s / switch) with mock IDE_FZF_BIN (in-process + live display-popup)
    mock_fzf = os.path.join(root, "mock-fzf.py")
    with open(mock_fzf, "w", encoding="utf-8") as f:
        f.write(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            "lines = [l.rstrip('\\n') for l in sys.stdin if l.strip()]\n"
            "assert all('\\t' in l for l in lines), f'missing tab delimiter: {lines}'\n"
            "rc = int(os.environ.get('MOCK_FZF_EXIT', '0'))\n"
            "if rc != 0:\n"
            "    sys.exit(rc)\n"
            "target = os.environ.get('MOCK_FZF_TARGET', '')\n"
            "key = os.environ.get('MOCK_FZF_KEY', '')\n"
            "picked = next((l for l in lines if l.split('\\t', 1)[0] == target), lines[0])\n"
            "print(key)\n"
            "print(picked)\n"
        )
    os.chmod(mock_fzf, 0o755)

    # alt-s abort (exit 130) returns 0 cleanly without switching
    r_abort = run_cmd(
        [ide_bin, "switch", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_EXIT": "130", "IDE_CLIENT": client_name},
        check=False,
    )
    assert r_abort.returncode == 0
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws"

    # Enter (empty --expect key) switches session preserving target's focused pane
    run_cmd([ide_bin, "_internal", "focus", "editor", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    run_cmd(
        [ide_bin, "-s", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "", "MOCK_FZF_TARGET": "gamma-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    drain_pty()
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "gamma-ws"
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{@ide_role}") == "editor"
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    drain_pty()

    # ctrl-e does NOT bounce when editor is already active
    run_cmd(
        [ide_bin, "-s", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "ctrl-e", "MOCK_FZF_TARGET": "alpha-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor"

    # ctrl-t unparks parked Shell and does NOT bounce when Shell is already active
    run_cmd([ide_bin, "_internal", "park", "term", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_term_parked") == "1"
    run_cmd(
        [ide_bin, "switch", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "ctrl-t", "MOCK_FZF_TARGET": "alpha-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_term_parked") == "0"
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term"
    run_cmd(
        [ide_bin, "switch", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["tm"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "ctrl-t", "MOCK_FZF_TARGET": "alpha-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term"

    # Live display-popup path: switches attached PTY client to beta-ws and unparks its parked AI pane via ctrl-a!
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_parked") == "1"
    tmux("set-environment", "-g", "IDE_FZF_BIN", mock_fzf, check=True)
    tmux("set-environment", "-g", "MOCK_FZF_KEY", "ctrl-a", check=True)
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "beta-ws", check=True)
    run_cmd(
        [ide_bin, "switch", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["tm"]), "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "ctrl-a", "MOCK_FZF_TARGET": "beta-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    drain_pty()
    assert wait_until(lambda: (drain_pty() or tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "beta-ws")), "live display-popup switch did not switch client to beta-ws"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_parked") == "0"
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "ai"

    # 6. Context Dispatch (ide send: --ref, L1==L2, empty no-op, after icd, external path, --text --no-focus, --stdin, live copy-mode-vi 'a', and untouched default tmux buffer)
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("set-buffer", "SACRED_DEFAULT_BUFFER", check=True)
    recv_root = os.path.join(root, "ai_recv_root.txt")
    tmux(
        "respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"],
        f"/bin/sh -c 'stty -echo -icanon min 1 time 0; exec cat > {recv_root}'",
        check=True,
    )
    time.sleep(0.1)
    run_cmd([ide_bin, "_internal", "focus", "editor", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)

    # Empty payloads (--stdin empty, --text "", --ref "   ") return 0 WITHOUT switching focus away from Editor!
    run_cmd([ide_bin, "send", "--stdin", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), input_text="", check=True)
    run_cmd([ide_bin, "send", "--text", "", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    run_cmd([ide_bin, "send", "--ref", "   ", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor", "empty send payload spuriously switched focus away from Editor"

    mod_file = os.path.join(ws_alpha["dir"], "sub", "mod.py")
    run_cmd([ide_bin, "send", "--ref", f"{mod_file}:10-20", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "ai"

    # L1 == L2 normalizes to #L15
    run_cmd([ide_bin, "send", "--ref", f"{mod_file}:15-15", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)

    # --no-focus keeps Editor focused
    run_cmd([ide_bin, "_internal", "focus", "editor", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    run_cmd([ide_bin, "send", "--text", "[NOFOCUS]", "--no-focus", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor"

    # --stdin (all ide send calls must leave default tmux buffer untouched)
    run_cmd([ide_bin, "send", "--stdin", "--no-focus", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), input_text="[STDIN_OK]", check=True)
    assert tmux_out("show-buffer") == "SACRED_DEFAULT_BUFFER", f"default tmux buffer clobbered by ide send: {tmux_out('show-buffer')!r}"
    assert "_ide_send_" not in tmux_out("list-buffers"), "temporary _ide_send_ buffer leaked"

    # Live Tmux copy-mode-vi 'a' binding from Shell pane
    tmux("send-keys", "-t", ws_alpha["tm"], "echo COPY_MODE_PAYLOAD", "C-m", check=True)
    assert wait_until(lambda: "\nCOPY_MODE_PAYLOAD" in "\n" + tmux_out("capture-pane", "-p", "-t", ws_alpha["tm"])), "missing COPY_MODE_PAYLOAD in Shell pane"
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["tm"], check=True)
    tmux("copy-mode", "-t", ws_alpha["tm"], check=True)
    drain_pty()
    tmux("send-keys", "-t", ws_alpha["tm"], "-X", "search-backward", "COPY_MODE_PAYLOAD", check=True)
    tmux("send-keys", "-t", ws_alpha["tm"], "-X", "begin-selection", check=True)
    tmux("send-keys", "-t", ws_alpha["tm"], "-X", "next-space-end", check=True)
    os.write(client_mfd, b"a")

    def root_recv_complete():
        drain_pty()
        if not os.path.isfile(recv_root):
            return False
        data = open(recv_root, encoding="utf-8", errors="replace").read()
        return "COPY_MODE_PAYLOAD" in data
    assert wait_until(root_recv_complete, timeout=3.0), f"copy-mode-vi 'a' payload never reached AI pane: {open(recv_root).read() if os.path.isfile(recv_root) else 'missing'}"
    got_root = open(recv_root, encoding="utf-8", errors="replace").read()
    clean_root = got_root.replace("\x1b[200~", "").replace("\x1b[201~", "")
    assert "@sub/mod.py#L10-L20 @sub/mod.py#L15 [NOFOCUS][STDIN_OK]COPY_MODE_PAYLOAD" == clean_root, f"unexpected AI root stream: {clean_root!r}"
    assert "_ide_send_" not in tmux_out("list-buffers"), "temporary _ide_send_ buffer leaked after copy-mode-vi"

    # Relative path resolution after icd into subdirectory (<ws>/sub) + outside-workspace fallback
    recv_sub = os.path.join(root, "ai_recv_sub.txt")
    sub_dir = os.path.join(ws_alpha["dir"], "sub")
    tmux("set-option", "-q", "-t", "=alpha-ws:", "@ide_workdir", sub_dir, check=True)
    tmux(
        "respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", sub_dir,
        f"/bin/sh -c 'stty -echo -icanon min 1 time 0; exec cat > {recv_sub}'",
        check=True,
    )
    time.sleep(0.1)
    readme_file = os.path.join(ws_alpha["dir"], "README.md")
    ext_file = os.path.join(root, "outside-ws.txt")
    with open(ext_file, "w", encoding="utf-8") as f:
        f.write("ext\n")
    ext_real = os.path.realpath(ext_file)
    run_cmd([ide_bin, "send", "--ref", f"{mod_file}:7", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    run_cmd([ide_bin, "send", "--ref", f"{readme_file}:1-3", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    run_cmd([ide_bin, "send", "--ref", f"{ext_file}:4", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert wait_until(lambda: os.path.isfile(recv_sub) and ext_real in open(recv_sub, encoding="utf-8").read()), "subdir --ref payloads did not arrive"
    clean_sub = open(recv_sub, encoding="utf-8").read().replace("\x1b[200~", "").replace("\x1b[201~", "")
    assert clean_sub == f"@mod.py#L7 @../README.md#L1-L3 @{ext_real}#L4 ", f"unexpected AI subdir stream: {clean_sub!r}"

    # 7. Multi-client Alt+s isolation, non-IDE Alt+s, relative invocation, popup ctrl-x self-quit + reload highlight, --ref/--send edge cases, and dirty-buffer --quit guard
    popup_env_log = os.path.join(root, "popup_env.txt")
    with open(mock_fzf, "w", encoding="utf-8") as f:
        f.write(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            f"with open({popup_env_log!r}, 'w', encoding='utf-8') as out:\n"
            "    out.write(os.environ.get('IDE_CLIENT', '') + '\\t' + os.environ.get('FZF_DEFAULT_OPTS', '') + '\\t' + ' '.join(sys.argv[1:]))\n"
            "lines = [l.rstrip('\\n') for l in sys.stdin if l.strip()]\n"
            "target = os.environ.get('MOCK_FZF_TARGET', '')\n"
            "key = os.environ.get('MOCK_FZF_KEY', '')\n"
            "picked = next((l for l in lines if l.split('\\t', 1)[0] == target), lines[0])\n"
            "print(key)\n"
            "print(picked)\n"
        )
    os.chmod(mock_fzf, 0o755)

    # (7a) Attach second PTY client (client2) to alpha-ws while client1 stays on alpha-ws; press real Alt+s (\x1bs) on client2
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    drain_pty()
    client2_mfd, client2_sfd = pty.openpty()
    fcntl.ioctl(client2_sfd, termios.TIOCSWINSZ, struct.pack("HHHH", 48, 160, 0, 0))
    client2_proc = subprocess.Popen(
        ["tmux", "attach-session", "-t", "=alpha-ws"],
        stdin=client2_sfd,
        stdout=client2_sfd,
        stderr=client2_sfd,
        env={**base_env, "TMUX": "", "TMUX_PANE": ""},
        close_fds=True,
        preexec_fn=lambda sfd=client2_sfd: set_ctty(sfd),
    )
    os.close(client2_sfd)

    def drain_pty_both():
        drain_pty()
        while True:
            r, _, _ = select.select([client2_mfd], [], [], 0)
            if not r:
                break
            try:
                if not os.read(client2_mfd, 8192):
                    break
            except OSError:
                break

    def find_client2():
        drain_pty_both()
        cls = [c.strip() for c in tmux_out("list-clients", "-t", "=alpha-ws", "-F", "#{client_name}").splitlines() if c.strip() and c.strip() != client_name]
        return cls[0] if cls else ""

    client2_name = wait_until(find_client2)
    assert client2_name, "failed to attach second PTY client to alpha-ws"

    tmux("set-environment", "-g", "IDE_FZF_BIN", mock_fzf, check=True)
    tmux("set-environment", "-g", "MOCK_FZF_KEY", "", check=True)
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "beta-ws", check=True)
    try:
        os.unlink(popup_env_log)
    except FileNotFoundError:
        pass
    os.write(client2_mfd, b"\x1bs")
    assert wait_until(lambda: (drain_pty_both() or tmux_out("display-message", "-p", "-t", client2_name, "#{session_name}") == "beta-ws")), "Alt+s on client2 did not switch client2 to beta-ws"
    time.sleep(0.2)
    drain_pty_both()
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws", "Alt+s on client2 wrongly switched client1!"
    recorded_env = open(popup_env_log, encoding="utf-8").read()
    rec_client, rec_default_fzf, _ = recorded_env.split("\t", 2)
    assert rec_client == client2_name and "#{" not in recorded_env, f"unexpanded format or wrong IDE_CLIENT in popup: {recorded_env!r}"
    assert "spinner:#859900" in rec_default_fzf and "prompt:#B58900" in rec_default_fzf, f"unexpected default FZF_DEFAULT_OPTS palette: {rec_default_fzf!r}"

    # Real Alt+s from non-IDE session (plain-non-ide) switches client2 cleanly into gamma-ws
    tmux("switch-client", "-c", client2_name, "-t", "=plain-non-ide", check=True)
    time.sleep(0.1)
    drain_pty_both()
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "gamma-ws", check=True)
    os.write(client2_mfd, b"\x1bs")
    assert wait_until(lambda: (drain_pty_both() or tmux_out("display-message", "-p", "-t", client2_name, "#{session_name}") == "gamma-ws")), "Alt+s on non-IDE session did not switch client2 to gamma-ws"
    time.sleep(0.2)
    drain_pty_both()
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws"

    # (7b) Relative invocation (./.local/bin/ide -s) + build_fzf_env single-quoted theme-env.sh overriding stale FZF_DEFAULT_OPTS
    hs_cfg_dir = os.path.join(thome, ".config", "home-settings")
    os.makedirs(hs_cfg_dir, exist_ok=True)
    theme_env_file = os.path.join(hs_cfg_dir, "theme-env.sh")
    with open(theme_env_file, "w", encoding="utf-8") as tf:
        tf.write("export FZF_DEFAULT_OPTS='--color=bg+:#313244,bg:#1E1E2E,spinner:#A6E3A1 --prompt='\\''WS> '\\'' --border=rounded'\n")
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "beta-ws", check=True)
    run_cmd(
        ["./.local/bin/ide", "-s", "gamma-ws"],
        env={
            **sess_env("gamma-ws", ws_gamma["ed"]),
            "FZF_DEFAULT_OPTS": "--color=bg+:#000000",
            "IDE_FZF_BIN": mock_fzf,
            "MOCK_FZF_KEY": "",
            "MOCK_FZF_TARGET": "beta-ws",
            "IDE_CLIENT": client2_name,
        },
        cwd=thome,
        check=True,
    )
    assert wait_until(lambda: (drain_pty_both() or tmux_out("display-message", "-p", "-t", client2_name, "#{session_name}") == "beta-ws")), "relative ./ide -s popup failed"
    _, rel_fzf_opts, rel_fzf_args = open(popup_env_log, encoding="utf-8").read().split("\t", 2)
    os.unlink(theme_env_file)
    assert "--color=bg+:#313244" in rel_fzf_opts and "--prompt='WS> '" in rel_fzf_opts and "#000000" not in rel_fzf_opts, f"build_fzf_env failed to load single-quoted/escaped theme-env.sh over stale FZF_DEFAULT_OPTS: {rel_fzf_opts!r}"
    assert os.path.abspath(ide_bin) in rel_fzf_args or os.path.realpath(ide_bin) in rel_fzf_args, f"relative path leaked into fzf args: {rel_fzf_args}"
    assert "--multi" in rel_fzf_args and "quit {+1}" in rel_fzf_args, f"expected --multi and quit {{+1}} in fzf args: {rel_fzf_args}"
    assert (
        "--border=rounded" in rel_fzf_args
        and "--border-label-pos=bottom" in rel_fzf_args
        and "--border-label= Enter: switch · Alt+l: AI · C-y: ack · Alt+s: close " in rel_fzf_args
        and "--color=label:#586E75" in rel_fzf_args
        and "border:#586E75,separator:#586E75" in rel_fzf_args
        and "spinner:#2AA198" in rel_fzf_args
        and "--bind=f12:refresh-preview" in rel_fzf_args
        and "--bind=f5:" in rel_fzf_args
        and "--bind=f1:execute(" in rel_fzf_args
        and "--bind=alt-?:execute(" in rel_fzf_args
        and "--header=" not in rel_fzf_args
    ), f"expected width-fitted 2-pane bottom border-label and F1/F5 binds in fzf args: {rel_fzf_args}"

    # Verify session_last_attached promotes recently visited gamma-ws above beta-ws
    beta_max_ts = max(
        (int(x) for x in tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{session_activity} #{session_last_attached} #{window_activity}").split() if x.isdigit()),
        default=int(time.time()),
    )
    while int(time.time()) <= beta_max_ts:
        time.sleep(0.05)
    tmux("switch-client", "-c", client2_name, "-t", "=gamma-ws", check=True)
    drain_pty_both()
    recency_after_switch = run_cmd([ide_bin, "list", "--plain"], env=sess_env("alpha-ws"), check=True).stdout.splitlines()
    assert recency_after_switch == ["alpha-ws", "gamma-ws", "beta-ws"], f"session_last_attached did not promote gamma-ws: {recency_after_switch}"

    # (7c) Quitting the active session from inside the popup (IDE_IN_POPUP=1, ctrl-x) switches attached client to the most recently active surviving IDE session, and _internal sessions-lines re-highlights the new session
    ws_killme = make_ws("killme-ws", ai_cmd="sleep 300")
    tmux("switch-client", "-c", client2_name, "-t", "=killme-ws", check=True)
    drain_pty_both()
    run_cmd([ide_bin, "quit", "killme-ws"], env={**sess_env("killme-ws", ws_killme["ed"]), "IDE_IN_POPUP": "1", "IDE_CLIENT": client2_name}, check=True)
    drain_pty_both()
    surviving_sess = tmux_out("display-message", "-p", "-t", client2_name, "#{session_name}")
    assert surviving_sess in ("alpha-ws", "beta-ws", "gamma-ws"), f"popup self-quit switched to unexpected session: {surviving_sess!r}"
    reloaded_rows = run_cmd([ide_bin, "_internal", "sessions-lines", "killme-ws"], env={**base_env, "IDE_IN_POPUP": "1", "IDE_CLIENT": client2_name}, check=True).stdout.splitlines()
    assert reloaded_rows and reloaded_rows[0].split("\t", 1)[0] == surviving_sess and "▸" in reloaded_rows[0], f"reload after ctrl-x did not highlight new client session {surviving_sess}: {reloaded_rows}"

    # (7d) Relative --ref from outside workspace CWD, '#' in filename, =--ref= syntax, and '--' leading-dash text
    tmux("set-option", "-q", "-t", "=alpha-ws:", "@ide_workdir", ws_alpha["dir"], check=True)
    hash_file = os.path.join(ws_alpha["dir"], "sub", "issue#12")
    with open(hash_file, "w", encoding="utf-8") as f:
        f.write("tracked\n")
    recv_edge = os.path.join(root, "ai_recv_edge.txt")
    tmux(
        "respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"],
        f"/bin/sh -c 'stty -echo -icanon min 1 time 0; exec cat > {recv_edge}'",
        check=True,
    )
    time.sleep(0.1)
    run_cmd([ide_bin, "send", "--no-focus", "--ref=sub/mod.py:4-4", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), cwd=root, check=True)
    run_cmd([ide_bin, "send", "--ref", "sub/issue#12", "--no-focus", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), cwd=root, check=True)
    run_cmd([ide_bin, "send", "--no-focus", "--text", "- leading-dash ", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), cwd=root, check=True)
    run_cmd([ide_bin, "send", "--no-focus", "--", "--literal-end", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), cwd=root, check=True)
    assert wait_until(lambda: os.path.isfile(recv_edge) and "--literal-end" in open(recv_edge, encoding="utf-8").read()), "edge send payloads did not arrive"
    clean_edge = open(recv_edge, encoding="utf-8").read().replace("\x1b[200~", "").replace("\x1b[201~", "")
    assert clean_edge == "@sub/mod.py#L4 @sub/issue#12 - leading-dash --literal-end", f"unexpected edge send stream: {clean_edge!r}"

    # (7e) ide quit refuses to close workspace when Neovim server has unsaved changes (while closing clean sibling sessions); quit --force closes it
    if shutil.which("nvim"):
        ws_dirty = make_ws("dirty-ws", ai_cmd="sleep 300")
        ws_clean_sib = make_ws("clean-sib-ws", ai_cmd="sleep 300")
        dirty_sock = tmux_out("show-options", "-qv", "-t", "=dirty-ws:", "@ide_socket")
        dirty_file = os.path.join(ws_dirty["dir"], "unsaved.txt")
        tmux(
            "respawn-pane", "-k", "-t", ws_dirty["ed"], "-c", ws_dirty["dir"],
            f"nvim --headless -u NONE -i NONE --listen {shlex.quote(dirty_sock)} -c {shlex.quote('edit ' + dirty_file)} -c \"call setline(1, 'dirty')\"",
            check=True,
        )
        assert wait_until(lambda: nvim_expr_eq(dirty_sock, "&modified", "1")), "dirty-ws nvim buffer did not become modified"
        r_dirty_quit = run_cmd([ide_bin, "quit", "dirty-ws", "clean-sib-ws"], env={**base_env, "TMUX": ""}, check=False)
        assert r_dirty_quit.returncode != 0, f"expected ide quit to refuse dirty buffer, got {r_dirty_quit}"
        assert tmux("has-session", "-t", "=dirty-ws", check=False).returncode == 0, "dirty-ws was killed despite unsaved buffer!"
        assert tmux("has-session", "-t", "=clean-sib-ws", check=False).returncode != 0, "clean-sib-ws should have been closed alongside dirty-ws check!"
        run_cmd([ide_bin, "quit", "--force", "dirty-ws"], env={**base_env, "TMUX": ""}, check=True)
        assert tmux("has-session", "-t", "=dirty-ws", check=False).returncode != 0, "dirty-ws survived quit --force"

    # 8. Deterministic Hook-Only AI Lifecycle State, Zero Heuristic Invention, FIFO --next-attention, Parked AI Preservation, Stale-Hook SHELL Guard, and Top-Bar Width Invariance
    import glob as _glob
    _ide_py_files = sorted(_glob.glob(os.path.join(repo_dir, "libexec", "ide_lib", "*.py")))
    _combined_ide_src = "\n".join(
        open(p, encoding="utf-8").read() for p in [os.path.realpath(ide_bin), *_ide_py_files]
    )
    for banned_heuristic in ("inspect_fleet_procs", "inspect_ai_viewport", "alert-bell", "--on-bell"):
        assert banned_heuristic not in _combined_ide_src, f"heuristic remnant {banned_heuristic!r} found in bin/ide or bin/ide_lib"

    # Detach client2 so client_name is the sole attached viewer on alpha-ws Editor pane
    tmux("detach-client", "-t", client2_name, check=False)
    drain_pty_both()
    tmux("respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"], "/bin/sh -c 'sleep 300; :'", check=True)
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    tmux("select-pane", "-t", ws_gamma["ed"], check=True)
    drain_pty()

    # (8a) Prompt-like text + terminal bell (\a) in gamma-ws AI pane MUST NOT invent WORKING or ATTN without hooks!
    tmux(
        "respawn-pane", "-k", "-t", ws_gamma["ai"], "-c", ws_gamma["dir"],
        "/bin/sh -c 'printf \"Allow tool execution? [Y/n] \\a\\n\"; sleep 300; :'",
        check=True,
    )
    assert wait_until(lambda: "Allow tool execution" in tmux_out("capture-pane", "-p", "-t", ws_gamma["ai"]))
    run_cmd([ide_bin, "_internal", "refresh-attn"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") in ("", "0")
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""
    assert tmux_out("show-options", "-gqv", "@ide_fleet_count") == "3"
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "0"
    sright_idle = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:status-right}")
    assert "range=user|fleet]#[fg=#839496,bg=#073642,nobold] 3 · 0 active (Alt+s)" in sright_idle, f"bad idle fleet pill: {sright_idle!r}"

    # (8b) Unfocused @ide_tab_ai character width invariance across all 4 states:
    # neutral -> running (Cyan) -> unacknowledged done (Green) -> approval (Orange), both visible and parked!
    wcur_neutral = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wcur_running = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "1"
    sright_active = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:status-right}")
    assert "range=user|fleet]#[fg=#839496,bg=#073642,nobold] 3 · #[fg=#2AA198,bg=#073642,nobold]1 active#[fg=#839496,bg=#073642,nobold] (Alt+s)" in sright_active, f"bad active fleet pill: {sright_active!r}"

    run_cmd([ide_bin, "state", "done", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "done"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1"
    wcur_done = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")

    run_cmd([ide_bin, "state", "quota", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "quota"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "0"
    wcur_quota = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")

    run_cmd([ide_bin, "state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wcur_approval = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    assert strip_tags(wcur_neutral) == strip_tags(wcur_running) == strip_tags(wcur_done) == strip_tags(wcur_quota) == strip_tags(wcur_approval), (
        f"@ide_tab_ai shifted character width! neutral={strip_tags(wcur_neutral)!r} running={strip_tags(wcur_running)!r} done={strip_tags(wcur_done)!r} quota={strip_tags(wcur_quota)!r} approval={strip_tags(wcur_approval)!r}"
    )
    assert "fg=#839496,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_neutral, f"expected Base0 neutral tint: {wcur_neutral!r}"
    assert "fg=#2AA198,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_running, f"expected Cyan running tint: {wcur_running!r}"
    assert "fg=#859900,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_done, f"expected Green unacknowledged done tint: {wcur_done!r}"
    assert "fg=#B58900,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_quota, f"expected Yellow quota tint: {wcur_quota!r}"
    assert "fg=#CB4B16,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_approval, f"expected Orange approval tint: {wcur_approval!r}"

    # Verify parked [Alt+a] @ide_tab_ai across all 5 states as well (zero character width shift)
    run_cmd([ide_bin, "_internal", "park", "ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)
    wpark_approval = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "state", "idle", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wpark_neutral = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wpark_running = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "state", "quota", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wpark_quota = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "state", "done", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wpark_done = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    assert strip_tags(wpark_neutral) == strip_tags(wpark_running) == strip_tags(wpark_quota) == strip_tags(wpark_done) == strip_tags(wpark_approval), (
        f"parked @ide_tab_ai shifted character width! neutral={strip_tags(wpark_neutral)!r} running={strip_tags(wpark_running)!r} quota={strip_tags(wpark_quota)!r} done={strip_tags(wpark_done)!r} approval={strip_tags(wpark_approval)!r}"
    )
    assert "fg=#586E75,bg=#073642,nobold]󰚩 codex [Alt+A]" in wpark_neutral, f"expected Base01 parked neutral: {wpark_neutral!r}"
    assert "fg=#2AA198,bg=#073642,nobold]󰚩 codex [Alt+A]" in wpark_running, f"expected Cyan parked running: {wpark_running!r}"
    assert "fg=#B58900,bg=#073642,nobold]󰚩 codex [Alt+A]" in wpark_quota, f"expected Yellow parked quota: {wpark_quota!r}"
    assert "fg=#859900,bg=#073642,nobold]󰚩 codex [Alt+A]" in wpark_done, f"expected Green parked done: {wpark_done!r}"
    assert "fg=#CB4B16,bg=#073642,nobold]󰚩 codex [Alt+A]" in wpark_approval, f"expected Orange parked approval: {wpark_approval!r}"
    run_cmd([ide_bin, "_internal", "park", "ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)

    # Verify status_click still clicks Editor & Shell accurately when @ide_tab_ai is tinted!
    run_cmd([ide_bin, "_internal", "status-click", str(sh_col), "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term"
    run_cmd([ide_bin, "_internal", "status-click", str(ed_col), "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["tm"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor"

    # (8c) Foreground done vs Background done + Mixed FIFO queue (beta-ws approval, gamma-ws background done)
    # Foreground done: when alpha-ws is attached and its AI pane IS focused, done sets @ide_ai_attn=0 (not queued)
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    drain_pty()
    run_cmd([ide_bin, "state", "done", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "done"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "0", "foreground done while viewing AI pane must not set @ide_ai_attn=1!"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn_ts") == ""
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws", "foreground done must not enter @ide_attn_summary!"
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    drain_pty()
    wcur_alpha_fg_done = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:window-status-current-format}")
    assert "fg=#839496,bg=#073642,nobold]󰚩 claude (Alt+a)" in wcur_alpha_fg_done, f"acknowledged foreground done must stay neutral Base0: {wcur_alpha_fg_done!r}"
    list_fg_done = run_cmd([ide_bin, "list"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True).stdout
    assert any("alpha-ws" in ln and "DONE" in ln for ln in list_fg_done.splitlines()), f"expected DONE for alpha-ws: {list_fg_done}"
    run_cmd([ide_bin, "state", "idle", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    list_idle = run_cmd([ide_bin, "list"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True).stdout
    assert any("alpha-ws" in ln and "IDLE" in ln for ln in list_idle.splitlines()), f"expected IDLE for alpha-ws: {list_idle}"

    # Background done: gamma-ws finishes turn while detached -> @ide_ai_attn=1, @ide_attn_summary == "beta-ws +1", FIFO order
    time.sleep(0.03)
    run_cmd([ide_bin, "state", "done", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_state") == "done"
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws +1"
    sright_attn = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:status-right}")
    assert "range=user|attn]#[fg=#CB4B16,bg=#073642,nobold]󰂚 beta-ws +1 " in sright_attn, f"missing urgent attn pill: {sright_attn!r}"

    fifo_plain = run_cmd([ide_bin, "list", "--plain"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True).stdout.splitlines()
    assert fifo_plain == ["beta-ws", "gamma-ws", "alpha-ws"], f"mixed ATTN + background DONE FIFO sort failed: {fifo_plain}"

    list_mixed_plain = run_cmd([ide_bin, "list"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True).stdout.splitlines()
    assert any(ln.lstrip().startswith("! ") and "beta-ws" in ln and "ATTN" in ln for ln in list_mixed_plain), f"missing ! ATTN row: {list_mixed_plain}"
    assert any(ln.lstrip().startswith("! ") and "gamma-ws" in ln and "DONE" in ln for ln in list_mixed_plain), f"missing ! DONE row: {list_mixed_plain}"

    color_env = {k: v for k, v in sess_env("alpha-ws", ws_alpha["ed"]).items() if k != "NO_COLOR"}
    slines_ansi = run_cmd([ide_bin, "_internal", "sessions-lines", "alpha-ws"], env=color_env, check=True).stdout.splitlines()
    beta_ansi = next(ln for ln in slines_ansi if ln.startswith("beta-ws\t"))
    gamma_ansi = next(ln for ln in slines_ansi if ln.startswith("gamma-ws\t"))
    assert "\x1b[38;2;203;75;22m󰂚\x1b[0m" in beta_ansi and "\x1b[38;2;203;75;22mbeta-ws" in beta_ansi, f"expected Orange bell & session on ATTN row: {beta_ansi!r}"
    assert "\x1b[38;2;133;153;0m󰂚\x1b[0m" in gamma_ansi and "\x1b[38;2;133;153;0mgamma-ws" in gamma_ansi and "\x1b[38;2;133;153;0mDONE" in gamma_ansi, f"expected Green bell, session & DONE on unacknowledged DONE row: {gamma_ansi!r}"
    l_mfd, l_sfd = pty.openpty()
    try:
        l_proc = subprocess.Popen([ide_bin, "list"], stdin=subprocess.DEVNULL, stdout=l_sfd, stderr=l_sfd, env=color_env)
        os.close(l_sfd)
        l_chunks = []
        while True:
            try:
                chunk = os.read(l_mfd, 16384)
                if not chunk:
                    break
                l_chunks.append(chunk)
            except OSError:
                break
        assert l_proc.wait(timeout=5.0) == 0
    finally:
        try:
            os.close(l_mfd)
        except OSError:
            pass
    list_mixed_ansi = b"".join(l_chunks).decode("utf-8", "replace").splitlines()
    beta_list_ansi = next(ln for ln in list_mixed_ansi if "beta-ws" in ln)
    gamma_list_ansi = next(ln for ln in list_mixed_ansi if "gamma-ws" in ln)
    assert "\x1b[38;2;203;75;22m󰂚\x1b[0m" in beta_list_ansi and "\x1b[38;2;203;75;22mbeta-ws" in beta_list_ansi, f"expected Orange bell & session in TTY list: {beta_list_ansi!r}"
    assert "\x1b[38;2;133;153;0m󰂚\x1b[0m" in gamma_list_ansi and "\x1b[38;2;133;153;0mgamma-ws" in gamma_list_ansi, f"expected Green bell & session in TTY list: {gamma_list_ansi!r}"

    # (8d) ide next jumps to oldest needs_attn session (beta-ws approval), focuses AI pane, auto-acknowledges, and updates @ide_attn_summary -> "gamma-ws"
    run_cmd([ide_bin, "next", "alpha-ws"], env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_CLIENT": client_name}, check=True)
    drain_pty()
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "beta-ws"
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "ai"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") in ("", "0")
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "gamma-ws"

    # Real Alt+Shift+S (\x1bS) on attached PTY jumps to next needs_attn session (gamma-ws background done), transitions done -> idle, and clears @ide_attn_summary!
    os.write(client_mfd, b"\x1bS")
    assert wait_until(lambda: (drain_pty() or tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "gamma-ws")), "Alt+Shift+S did not jump to background-done gamma-ws"
    assert wait_until(lambda: (drain_pty() or tmux_out("show-options", "-gqv", "@ide_attn_summary") == "")), "Alt+Shift+S focus hook did not clear @ide_attn_summary"
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{@ide_role}") == "ai"
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_state") == "idle"
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") in ("", "0")

    # Attached session with Editor focused receiving state done ALSO queues attention & jumps to AI pane!
    tmux("select-pane", "-t", ws_gamma["ed"], check=True)
    drain_pty()
    run_cmd([ide_bin, "state", "done", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "gamma-ws"
    run_cmd([ide_bin, "next", "gamma-ws"], env={**sess_env("gamma-ws", ws_gamma["ed"]), "IDE_CLIENT": client_name}, check=True)
    drain_pty()
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{@ide_role}") == "ai"
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") in ("", "0")
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""

    # Calling next when queue is empty is a safe exit-0 no-op
    run_cmd([ide_bin, "next", "gamma-ws"], env={**sess_env("gamma-ws", ws_gamma["ai"]), "IDE_CLIENT": client_name}, check=True)
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "gamma-ws"

    # Calling next outside tmux with TTY stdin but redirected stdout (IDE_NO_ATTACH=0) exits 0 without 'open terminal failed'
    run_cmd([ide_bin, "state", "done", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1"
    na_mfd, na_sfd = pty.openpty()
    try:
        na_env = {**base_env, "TMUX": "", "TMUX_PANE": "", "IDE_CLIENT": "", "IDE_NO_ATTACH": "0"}
        na_res = subprocess.run([ide_bin, "next"], stdin=na_sfd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=na_env, text=True, check=False)
        assert na_res.returncode == 0, f"outside-tmux next with redirected stdout failed: {na_res.stderr!r}"
    finally:
        os.close(na_sfd)
        os.close(na_mfd)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") in ("", "0")

    # (8e) Parked AI pane (_ide_park_ai) preserves live WORKING state
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    run_cmd([ide_bin, "_internal", "park", "ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_parked") == "1"
    list_parked_run = run_cmd([ide_bin, "list"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True).stdout
    assert any("beta-ws" in ln and "WORKING" in ln for ln in list_parked_run.splitlines()), f"parked running AI lost WORKING state: {list_parked_run}"
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "1"
    run_cmd([ide_bin, "_internal", "park", "ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)

    # (8f) Stale-hook guard: if AI CLI exits back to bare shell (0 child processes), report SHELL and clear stale @ide_ai_state/@ide_ai_attn!
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws"
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec /bin/sh", check=True)
    assert wait_until(
        lambda: any("beta-ws" in ln and "SHELL" in ln for ln in run_cmd([ide_bin, "list"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True).stdout.splitlines()),
        timeout=3.0,
    ), "bare-shell AI pane did not transition to SHELL"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == ""
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") in ("", "0")
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "0"

    # (8g) Exec-launched childless foreground AI process (0 child PIDs, non-shell pane_current_command) retains hook state!
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec sleep 300", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sleep")
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1", "exec-launched childless AI lost approval state!"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws", "exec-launched childless AI wiped from @ide_attn_summary!"

    # (8h) Real SGR mouse clicks on top status bar: Help (Alt+?) popup, #[range=user|attn], and #[range=user|fleet]
    import unicodedata as _ud
    _ansi_strip_re = re.compile(r"\x1b(?:\[[0-9;?]*[A-Za-z~]|\][^\x07\x1b]*(?:\x07|\x1b\\)|[()][A-Z0-9])")

    def _cell_w(text):
        total = 0
        for ch in text:
            cp = ord(ch)
            if 0xE000 <= cp <= 0xF8FF or 0xF0000 <= cp <= 0x10FFFF:
                total += 1
            elif cp >= 0x10000 or _ud.east_asian_width(ch) in ("W", "F"):
                total += 2
            elif not _ud.combining(ch):
                total += 1
        return total

    def _read_pty_chunk(sec=0.5):
        end_t = time.monotonic() + sec
        buf = []
        while time.monotonic() < end_t:
            rdy, _, _ = select.select([client_mfd], [], [], max(0.01, end_t - time.monotonic()))
            if rdy:
                try:
                    buf.append(os.read(client_mfd, 65536))
                except OSError:
                    break
        return b"".join(buf)

    def _pump_pty(sec=0.05):
        _read_pty_chunk(sec)
        return False

    def _wait_pty_text(needle, timeout=3.0):
        end_t = time.monotonic() + timeout
        acc = bytearray()
        while time.monotonic() < end_t:
            rdy, _, _ = select.select([client_mfd], [], [], min(0.05, max(0.005, end_t - time.monotonic())))
            if rdy:
                try:
                    acc.extend(os.read(client_mfd, 65536))
                except OSError:
                    break
                txt = _ansi_strip_re.sub("", acc.decode("utf-8", "replace"))
                if needle in txt:
                    return txt
        return _ansi_strip_re.sub("", acc.decode("utf-8", "replace"))

    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("set-environment", "-t", "=alpha-ws", "SSH_CONNECTION", "10.0.0.1 12345 10.0.0.2 22", check=True)
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _read_pty_chunk(0.35)

    c_width = int(tmux_out("display-message", "-p", "-t", client_name, "#{client_width}"))
    sr_raw = subprocess.run(
        ["tmux", "-u", "display-message", "-t", "=alpha-ws:", "-p", "#{T:status-right}"],
        env=base_env, text=True, capture_output=True, check=True,
    ).stdout.rstrip("\n")
    sr_vis = re.sub(r"#\[[^\]]*\]", "", sr_raw)

    def _sr_col(label):
        pos = sr_vis.index(label)
        return c_width - _cell_w(sr_vis[pos:]) + 1

    # Click 0: Non-interactive SSH host segment ("󰣀") and empty middle status bar space MUST NOT open Help OR hijack pane focus!
    ssh_x = _sr_col("󰣀")
    os.write(client_mfd, f"\x1b[<0;{ssh_x};1M\x1b[<0;{ssh_x};1m".encode())
    ssh_out = _ansi_strip_re.sub("", _read_pty_chunk(0.35).decode("utf-8", "replace"))
    assert "IDE Workspace & Editor Keybindings" not in ssh_out, f"SSH segment click unexpectedly opened Help popup: {ssh_out[-250:]!r}"
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws"
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor", "SSH segment click hijacked active pane role!"

    # Empty middle bar space click (both unzoomed and zoomed) must be a strict pure-C no-op!
    sl_vis = re.sub(r"#\[[^\]]*\]", "", subprocess.run(["tmux", "-u", "display-message", "-t", "=alpha-ws:", "-p", "#{T:status-left}"], env=base_env, text=True, capture_output=True, check=True).stdout.rstrip("\n"))
    wc_vis = re.sub(r"#\[[^\]]*\]", "", subprocess.run(["tmux", "-u", "display-message", "-t", "=alpha-ws:", "-p", "#{T:window-status-current-format}"], env=base_env, text=True, capture_output=True, check=True).stdout.rstrip("\n"))
    empty_mid_x = _cell_w(sl_vis) + _cell_w(wc_vis) + 6
    _read_pty_chunk(0.35)
    os.write(client_mfd, f"\x1b[<0;{empty_mid_x};1M\x1b[<0;{empty_mid_x};1m".encode())
    _read_pty_chunk(0.35)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor", "Empty middle status bar click switched focus to Shell!"
    tmux("resize-pane", "-Z", "-t", ws_alpha["ed"], check=True)
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _read_pty_chunk(0.2)
    os.write(client_mfd, f"\x1b[<0;{empty_mid_x + 18};1M\x1b[<0;{empty_mid_x + 18};1m".encode())
    _read_pty_chunk(0.35)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{window_zoomed_flag}") == "1", "Empty middle status bar click unzoomed active pane!"

    # Native #[range=user|tab_zoom] (including rapid <80ms DoubleClick1Status), #[range=user|tab_term], #[range=user|tab_ai], and #[range=user|tab_editor] clicks:
    wc_zoom_vis = re.sub(r"#\[[^\]]*\]", "", subprocess.run(["tmux", "-u", "display-message", "-t", "=alpha-ws:", "-p", "#{T:window-status-current-format}"], env=base_env, text=True, capture_output=True, check=True).stdout.rstrip("\n"))
    zoom_tab_x = _cell_w(sl_vis) + _cell_w(wc_zoom_vis[:wc_zoom_vis.index("ZOOM")]) + 1
    os.write(client_mfd, f"\x1b[<0;{zoom_tab_x};1M\x1b[<0;{zoom_tab_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.03) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{window_zoomed_flag}") == "0")), "tab_zoom SGR click did not unzoom"
    tmux("resize-pane", "-Z", "-t", ws_alpha["ed"], check=True)
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    assert "ZOOM" in _wait_pty_text("ZOOM", timeout=2.0), "status bar did not redraw ZOOM badge after re-zoom"
    os.write(client_mfd, f"\x1b[<0;{zoom_tab_x};1M\x1b[<0;{zoom_tab_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.03) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{window_zoomed_flag}") == "0")), "rapid DoubleClick1Status on tab_zoom was dropped!"
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _read_pty_chunk(0.35)

    term_tab_x = _cell_w(sl_vis) + _cell_w(wc_vis[:wc_vis.index("Shell")]) + 1
    os.write(client_mfd, f"\x1b[<0;{term_tab_x};1M\x1b[<0;{term_tab_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.05) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term")), "tab_term SGR click did not focus Shell"
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _read_pty_chunk(0.35)

    wc_term_vis = re.sub(r"#\[[^\]]*\]", "", subprocess.run(["tmux", "-u", "display-message", "-t", "=alpha-ws:", "-p", "#{T:window-status-current-format}"], env=base_env, text=True, capture_output=True, check=True).stdout.rstrip("\n"))
    ai_tab_x = _cell_w(sl_vis) + 3
    os.write(client_mfd, f"\x1b[<0;{ai_tab_x};1M\x1b[<0;{ai_tab_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.05) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "ai")), "tab_ai SGR click did not focus AI"
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _read_pty_chunk(0.35)

    wc_ai_vis = re.sub(r"#\[[^\]]*\]", "", subprocess.run(["tmux", "-u", "display-message", "-t", "=alpha-ws:", "-p", "#{T:window-status-current-format}"], env=base_env, text=True, capture_output=True, check=True).stdout.rstrip("\n"))
    ed_tab_x = _cell_w(sl_vis) + _cell_w(wc_ai_vis[:wc_ai_vis.index("Editor")]) + 1
    os.write(client_mfd, f"\x1b[<0;{ed_tab_x};1M\x1b[<0;{ed_tab_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.05) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor")), "tab_editor SGR click did not focus Editor"
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _read_pty_chunk(0.35)
    _ = wc_term_vis

    # Click 1: Help (Alt+?) (#[range=user|help]) while SSH, attn, and fleet segments are rendered to its left
    help_x = _sr_col("Help")
    os.write(client_mfd, f"\x1b[<0;{help_x};1M\x1b[<0;{help_x};1m".encode())
    help_out = _wait_pty_text("IDE Workspace & Editor Keybindings", timeout=4.0)
    assert "IDE Workspace & Editor Keybindings" in help_out, f"Help SGR click failed: {help_out[-250:]!r}"
    os.write(client_mfd, b"q")
    _read_pty_chunk(0.4)
    tmux("set-environment", "-u", "-t", "=alpha-ws", "SSH_CONNECTION", check=True)

    # Click 2: Urgent #[range=user|attn] pill ("beta-ws") jumps client to beta-ws and auto-acks
    attn_x = _sr_col("beta-ws")
    os.write(client_mfd, f"\x1b[<0;{attn_x};1M\x1b[<0;{attn_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.08) or tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "beta-ws")), "attn pill SGR click did not jump to beta-ws"
    assert wait_until(lambda: (_pump_pty(0.05) or tmux_out("show-options", "-gqv", "@ide_attn_summary") == "")), "attn pill SGR click did not clear @ide_attn_summary"

    # Click 3: #[range=user|fleet] pill ("(Alt+s)") opens --sessions popup and switches back to alpha-ws
    tmux("set-environment", "-g", "MOCK_FZF_KEY", "", check=True)
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "alpha-ws", check=True)
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _wait_pty_text("(Alt+s)", timeout=2.0)
    _read_pty_chunk(0.15)
    sr_raw2 = subprocess.run(
        ["tmux", "-u", "display-message", "-t", "=beta-ws:", "-p", "#{T:status-right}"],
        env=base_env, text=True, capture_output=True, check=True,
    ).stdout.rstrip("\n")
    sr_vis2 = re.sub(r"#\[[^\]]*\]", "", sr_raw2)
    fleet_x = c_width - _cell_w(sr_vis2[sr_vis2.index("(Alt+s)"):]) + 1
    os.write(client_mfd, f"\x1b[<0;{fleet_x};1M\x1b[<0;{fleet_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.1) or tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws"), timeout=4.0), "fleet pill SGR click did not switch to alpha-ws"
    _read_pty_chunk(0.2)

    # (8i) Zero-fork pure-C if-shell -F guard on pane-focus-in & client-session-changed:
    # Switching between Editor and Shell (or into idle/empty AI panes or non-IDE sessions) must NEVER
    # invoke ~/.local/bin/ide --ack-ai, whereas focusing AI when @ide_ai_attn == 1 (approval or
    # background done) immediately invokes --ack-ai --hook and clears @ide_ai_attn and @ide_attn_summary.
    for s_clean in ("alpha-ws", "beta-ws", "gamma-ws"):
        run_cmd([ide_bin, "state", "idle", s_clean], env=sess_env(s_clean), check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.25)

    real_ide_path = os.path.realpath(ide_bin)
    ack_hook_log = os.path.join(root, "ack_hook.log")
    open(ack_hook_log, "w", encoding="utf-8").close()
    os.unlink(ide_bin)
    with open(ide_bin, "w", encoding="utf-8") as wf:
        wf.write(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            f"log_p = {ack_hook_log!r}\n"
            f"real_p = {real_ide_path!r}\n"
            "if sys.argv[1:3] == ['_internal', 'ack-hook']:\n"
            "    with open(log_p, 'a', encoding='utf-8') as lf:\n"
            "        lf.write(' '.join(sys.argv[1:]) + '\\n')\n"
            "os.execv(real_p, [real_p, *sys.argv[1:]])\n"
        )
    os.chmod(ide_bin, 0o755)

    # Routine focus switches while @ide_ai_state is idle or empty:
    tmux("select-pane", "-t", ws_alpha["tm"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    os.write(client_mfd, b"\x1bt")
    assert wait_until(lambda: (_pump_pty(0.05) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term")), "Alt+t did not focus Shell"
    os.write(client_mfd, b"\x1bk")
    assert wait_until(lambda: (_pump_pty(0.05) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor")), "Alt+k from Shell did not focus Editor"
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("set-option", "-q", "-u", "-t", "=alpha-ws:", "@ide_ai_state", check=True)
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("switch-client", "-c", client_name, "-t", "=plain-non-ide", check=True)
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)

    # Even while @ide_ai_attn == 1 (background done), switching between Editor and Shell must NOT invoke _internal ack-hook!
    run_cmd([ide_bin, "state", "done", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "alpha-ws"
    tmux("select-pane", "-t", ws_alpha["tm"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.3)
    logged_false = open(ack_hook_log, encoding="utf-8").read()
    assert logged_false == "", f"if-shell -F guard leaked _internal ack-hook calls during non-AI/idle switches: {logged_false!r}"

    # Focusing AI pane while @ide_ai_attn == 1 (background done) immediately triggers _internal ack-hook and clears!
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    assert wait_until(lambda: (_pump_pty(0.05) or "_internal ack-hook alpha-ws" in open(ack_hook_log, encoding="utf-8").read())), "pane-focus-in on background-done AI did not invoke _internal ack-hook"
    assert wait_until(lambda: (_pump_pty(0.05) or (tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") in ("", "0") and tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""))), "pane-focus-in did not clear @ide_ai_attn/@ide_attn_summary on done"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "idle"

    # Focusing AI pane while @ide_ai_attn == 1 (approval) immediately triggers _internal ack-hook, clears @ide_ai_attn/@ide_attn_summary, AND preserves @ide_ai_state == "approval"!
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.15)
    open(ack_hook_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "state", "approval", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "alpha-ws"
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    assert wait_until(lambda: (_pump_pty(0.05) or "_internal ack-hook alpha-ws" in open(ack_hook_log, encoding="utf-8").read())), "pane-focus-in on approval AI did not invoke _internal ack-hook"
    assert wait_until(lambda: (_pump_pty(0.05) or (tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") in ("", "0") and tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""))), "pane-focus-in did not clear @ide_ai_attn/@ide_attn_summary on approval"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "approval", "focusing AI wiped unanswered approval state to idle!"
    # Switching back to Editor to inspect code keeps approval state (Orange AI tab & ATTN in list) without re-triggering @ide_attn_summary!
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.15)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "approval"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""
    wcur_ack_app = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:window-status-current-format}")
    assert "fg=#CB4B16,bg=#073642,nobold]󰚩 claude (Alt+a)" in wcur_ack_app, f"expected Orange approval tab tint while inspecting Editor: {wcur_ack_app!r}"

    # Firing state approval while ALREADY focused in AI pane sets @ide_ai_state=approval with @ide_ai_attn=0 (no false urgent alert!)
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    _read_pty_chunk(0.15)
    run_cmd([ide_bin, "state", "running", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    run_cmd([ide_bin, "state", "approval", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "approval"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "0", "foreground approval while focused in AI falsely raised @ide_ai_attn=1!"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "", "foreground approval while focused in AI falsely lit @ide_attn_summary!"
    run_cmd([ide_bin, "state", "idle", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)

    # Routine focus switches into live running or quota AI panes:
    # (a) Foreground non-shell AI binary (ws_beta["ai"] running 'sleep'): 0 _internal ack-hook forks!
    tmux("switch-client", "-c", client_name, "-t", "=beta-ws", check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    _read_pty_chunk(0.15)
    run_cmd([ide_bin, "state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    open(ack_hook_log, "w", encoding="utf-8").close()
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "state", "quota", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    _read_pty_chunk(0.25)
    assert open(ack_hook_log, encoding="utf-8").read() == "", f"routine running/quota focus spawned hook storm: {open(ack_hook_log, encoding='utf-8').read()!r}"
    run_cmd([ide_bin, "state", "idle", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    # (b) Shell-wrapped AI process (ws_alpha["ai"]: /bin/sh with live child sleep): preserves running/quota without wiping state!
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.15)
    run_cmd([ide_bin, "state", "running", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    _read_pty_chunk(0.2)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "running", "shell-wrapped live running AI lost state on focus!"
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    run_cmd([ide_bin, "state", "idle", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)

    # Switching client to a session whose AI pane is active with @ide_ai_attn == 1 triggers client-session-changed _internal ack-hook and preserves approval!
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    _read_pty_chunk(0.15)
    open(ack_hook_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws"
    tmux("switch-client", "-c", client_name, "-t", "=beta-ws", check=True)
    assert wait_until(lambda: (_pump_pty(0.05) or "_internal ack-hook beta-ws" in open(ack_hook_log, encoding="utf-8").read())), "client-session-changed did not invoke _internal ack-hook beta-ws"
    assert wait_until(lambda: (_pump_pty(0.05) or (tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") in ("", "0") and tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""))), "client-session-changed did not clear @ide_ai_attn/@ide_attn_summary"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "approval"

    # Crashed 'running' AI CLI (exited to bare /bin/sh without Stop hook):
    # 1) Focusing AI from Editor triggers pane-focus-in crashed-shell guard (_internal ack-hook) and clears @ide_ai_state & @ide_fleet_active!
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    _read_pty_chunk(0.15)
    open(ack_hook_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "1"
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec /bin/sh", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sh")
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    assert wait_until(lambda: (_pump_pty(0.05) or "_internal ack-hook beta-ws" in open(ack_hook_log, encoding="utf-8").read())), "pane-focus-in on crashed running AI did not invoke _internal ack-hook"
    assert wait_until(lambda: (_pump_pty(0.05) or (tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "" and tmux_out("show-options", "-gqv", "@ide_fleet_active") == "0"))), "pane-focus-in did not clear stale running state after AI exit"

    # 2) If AI crashes while running AND user is already in AI pane, bouncing out via Alt+a (_internal toggle) clears stale running & @ide_fleet_active!
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec sleep 300", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sleep")
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    run_cmd([ide_bin, "state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "1"
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec /bin/sh", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sh")
    run_cmd([ide_bin, "_internal", "toggle", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "editor"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "", "bouncing out of crashed running AI via _internal toggle left stale @ide_ai_state!"
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "0", "bouncing out of crashed running AI via _internal toggle left stale @ide_fleet_active!"

    # (8j) ide refresh heals stale Editor CWDs + reloads Neovim theme over RPC, refreshes top bar, and NEVER injects keys or wipes unsent text in idle Shell panes!
    r_ref_bad = run_cmd([ide_bin, "refresh", "no-such-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=False)
    assert r_ref_bad.returncode != 0, "expected non-zero when refresh targets nonexistent session"
    tmux("respawn-pane", "-k", "-t", ws_alpha["tm"], "-c", ws_alpha["dir"], "env PS1='PROMPT> ' bash --norc --noprofile -i", check=True)
    assert wait_until(lambda: "PROMPT>" in tmux_out("capture-pane", "-p", "-t", ws_alpha["tm"]))
    tmux("send-keys", "-t", ws_alpha["tm"], "-l", "git commit -m 'unsent draft", check=True)
    assert wait_until(lambda: "git commit -m 'unsent draft" in tmux_out("capture-pane", "-p", "-t", ws_alpha["tm"]))
    alpha_sock = tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_socket")
    if shutil.which("nvim"):
        stale_ed_sub = os.path.join(ws_alpha["dir"], "stale_ed")
        os.makedirs(stale_ed_sub, exist_ok=True)
        tmux(
            "respawn-pane", "-k", "-t", ws_alpha["ed"], "-c", stale_ed_sub,
            f"exec nvim --headless -u NONE -i NONE --listen {shlex.quote(alpha_sock)} -c \"lua _G.apply_home_settings_theme = function() vim.g.hs_theme_reloaded = (vim.g.hs_theme_reloaded or 0) + 1 end\"",
            check=True,
        )
        assert wait_until(lambda: nvim_expr_eq(alpha_sock, "exists('*v:lua.apply_home_settings_theme')", "1")), "alpha-ws nvim callback did not initialize for refresh test"
        shutil.rmtree(stale_ed_sub)
    r_ref_all = run_cmd([ide_bin, "refresh"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert "Refreshed 3 IDE session(s)" in r_ref_all.stdout and "shell" not in r_ref_all.stdout, f"unexpected refresh output: {r_ref_all.stdout!r}"
    time.sleep(0.15)
    tm_cap_after = tmux_out("capture-pane", "-p", "-t", ws_alpha["tm"])
    assert "git commit -m 'unsent draft" in tm_cap_after and "_hs_recover_stale_cwd" not in tm_cap_after, (
        f"ide --refresh corrupted or wiped unsent text in idle Shell pane: {tm_cap_after!r}"
    )
    if shutil.which("nvim"):
        ed_cwd_after = subprocess.run(
            ["nvim", "--server", alpha_sock, "--remote-expr", "luaeval('(vim.uv or vim.loop).cwd() or \"\"')"],
            env=base_env, text=True, capture_output=True, timeout=3, check=True,
        ).stdout.strip()
        ed_wrapped = subprocess.run(
            ["nvim", "--server", alpha_sock, "--remote-expr", "luaeval('tostring(vim.fs and vim.fs._hs_abspath_wrapped == true)')"],
            env=base_env, text=True, capture_output=True, timeout=3, check=True,
        ).stdout.strip()
        ed_theme_cnt = subprocess.run(
            ["nvim", "--server", alpha_sock, "--remote-expr", "luaeval('tostring(vim.g.hs_theme_reloaded or 0)')"],
            env=base_env, text=True, capture_output=True, timeout=3, check=True,
        ).stdout.strip()
        assert os.path.realpath(ed_cwd_after) in (os.path.realpath(ws_alpha["dir"]), os.path.realpath(sub_dir)), f"ide --refresh did not heal nvim CWD: {ed_cwd_after!r}"
        assert ed_wrapped == "true", f"ide --refresh did not install vim.fs.abspath wrapper: {ed_wrapped!r}"
        assert ed_theme_cnt == "1", f"ide --refresh did not invoke v:lua.apply_home_settings_theme(): {ed_theme_cnt!r}"

    # 9. Five-Tier Urgency Hierarchy, Elapsed State Age, OS Focus & Notifications, Multi-Ack, PR Badges, Worktree Collision Guard, Cross-Session --send --switch, and Alt+n Launcher
    # Restore direct ide symlink (removing the step 8i ack wrapper)
    try:
        os.unlink(ide_bin)
    except FileNotFoundError:
        pass
    os.symlink(real_ide_path, ide_bin)

    ws_delta = make_ws("delta-ws", ai_cmd="sleep 300", ai_cli="claude", git_branch="feat/cache", in_home=True)
    ws_shell = make_ws("shell-ws", ai_cmd="exec /bin/sh", ai_cli="agy", git_branch="", in_home=False)
    for s_restore, ws_obj in (("alpha-ws", ws_alpha), ("beta-ws", ws_beta), ("gamma-ws", ws_gamma)):
        tmux("respawn-pane", "-k", "-t", ws_obj["ai"], "-c", ws_obj["dir"], "exec sleep 300", check=True)
        tmux("set-option", "-q", "-t", f"={s_restore}:", "@ide_workdir", ws_obj["dir"], check=True)
    assert wait_until(
        lambda: tmux_out("display-message", "-p", "-t", ws_alpha["ai"], "#{pane_current_command}") == "sleep"
        and tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sleep"
        and tmux_out("display-message", "-p", "-t", ws_gamma["ai"], "#{pane_current_command}") == "sleep"
        and tmux_out("display-message", "-p", "-t", ws_shell["ai"], "#{pane_current_command}") == "sh"
    )
    tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
    tmux("select-pane", "-t", ws_gamma["ed"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    tmux("select-pane", "-t", ws_delta["ed"], check=True)
    _read_pty_chunk(0.15)

    # (9a) Five-tier urgency sort: older DONE (beta-ws) MUST NOT beat newer ATTN (alpha-ws); WORKING > IDLE > SHELL; elapsed ages & repeated running preservation
    run_cmd([ide_bin, "state", "done", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    time.sleep(0.03)
    run_cmd([ide_bin, "state", "approval", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    run_cmd([ide_bin, "state", "running", "delta-ws"], env=sess_env("delta-ws", ws_delta["ai"]), check=True)
    run_cmd([ide_bin, "state", "idle", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)

    now_epoch = int(time.time())
    tmux("set-option", "-q", "-t", "=alpha-ws:", "@ide_ai_state_ts", str(now_epoch - 1560), check=True)  # 26m
    tmux("set-option", "-q", "-t", "=beta-ws:", "@ide_ai_state_ts", str(now_epoch - 180), check=True)    # 3m
    tmux("set-option", "-q", "-t", "=delta-ws:", "@ide_ai_state_ts", str(now_epoch - 480), check=True)   # 8m
    tmux("set-option", "-q", "-t", "=gamma-ws:", "@ide_ai_state_ts", str(now_epoch - 120), check=True)   # 2m

    # Repeated state running on delta-ws MUST preserve existing @ide_ai_state_ts (8m), not reset to 0s!
    run_cmd([ide_bin, "state", "running", "delta-ws"], env=sess_env("delta-ws", ws_delta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=delta-ws:", "@ide_ai_state_ts") == str(now_epoch - 480), "repeated running hook reset @ide_ai_state_ts!"

    tier_order = run_cmd([ide_bin, "list", "--plain"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert tier_order == ["alpha-ws", "beta-ws", "delta-ws", "gamma-ws", "shell-ws"], f"5-tier sort order broken: {tier_order}"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "alpha-ws +1", f"attn_summary failed to prioritize ATTN over older DONE: {tmux_out('show-options', '-gqv', '@ide_attn_summary')!r}"

    tier_table = run_cmd([ide_bin, "list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert any("alpha-ws" in ln and "ATTN 26m" in ln for ln in tier_table), f"missing ATTN 26m in list: {tier_table}"
    assert any("beta-ws" in ln and "DONE 3m" in ln for ln in tier_table), f"missing DONE 3m in list: {tier_table}"
    assert any("delta-ws" in ln and "WORKING 8m" in ln for ln in tier_table), f"missing WORKING 8m in list: {tier_table}"
    assert any("gamma-ws" in ln and "IDLE 2m" in ln for ln in tier_table), f"missing IDLE 2m in list: {tier_table}"
    assert any("shell-ws" in ln and "SHELL" in ln and "SHELL " not in ln.split("SHELL", 1)[1][:2] for ln in tier_table), f"unexpected SHELL row: {tier_table}"
    # Verify dynamic column alignment: WORKSPACE column starts at identical character index across every row!
    ws_col_idx = tier_table[0].index("WORKSPACE")
    for row_ln in tier_table[1:]:
        assert row_ln[ws_col_idx:ws_col_idx + 1] in ("~", "/"), f"misaligned WORKSPACE column at {ws_col_idx} in row: {row_ln!r}"

    prev_alpha_age = run_cmd([ide_bin, "_internal", "session-preview", "alpha-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    assert "ATTN 26m" in prev_alpha_age, f"missing ATTN 26m in _internal session-preview: {prev_alpha_age}"

    # next jumps to newer ATTN (alpha-ws) BEFORE older DONE (beta-ws)!
    run_cmd([ide_bin, "next", "gamma-ws"], env={**sess_env("gamma-ws", ws_gamma["ed"]), "IDE_CLIENT": client_name}, check=True)
    _read_pty_chunk(0.15)
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws", "next failed to prioritize ATTN blocker ahead of older DONE!"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws"

    # (9b) Multi-session ack: remotely acking approval mutes @ide_ai_attn while keeping ATTN state; remotely acking done transitions to IDLE
    tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.15)
    run_cmd([ide_bin, "state", "approval", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "alpha-ws +1"
    run_cmd([ide_bin, "ack", "alpha-ws", "beta-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "", "multi-target ack did not clear @ide_attn_summary"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "idle", "remote ack on done did not transition to idle"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "0", "remote ack on approval did not clear @ide_ai_attn"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "approval", "remote ack wiped unanswered approval state!"
    muted_list = run_cmd([ide_bin, "list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert any("alpha-ws" in ln and "ATTN" in ln and not ln.lstrip().startswith("!") for ln in muted_list), f"muted approval should remain ATTN without '!' marker: {muted_list}"

    # (9c) OS window unfocus (DECSET 1004 \x1b[O / \x1b[I), trailing JSON & piped stdin hardening, idle_prompt ignore, ide_notify & IDE_NOTIFY banners
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    assert wait_until(lambda: (drain_pty() or "focused" in tmux_out("list-clients", "-t", "=alpha-ws", "-F", "#{client_flags}")))
    run_cmd([ide_bin, "state", "running", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)

    # Set up custom ide_notify hook + mock notify-send (with broken DBUS_SESSION_BUS_ADDRESS so busctl falls back cleanly to notify-send!)
    notify_hook_log = os.path.join(root, "ide_notify_hook.log")
    os_notify_log = os.path.join(root, "os_notify.log")
    rules_file = os.path.join(xdg_cfg, "ide", "links.sh")
    os.makedirs(os.path.dirname(rules_file), exist_ok=True)
    with open(rules_file, "w", encoding="utf-8") as rf:
        rf.write(
            f'ide_notify() {{ printf "%s|%s|%s|%s|%s|%s\\n" "$1" "$2" "$3" "$4" "$5" "$6" >> {shlex.quote(notify_hook_log)}; }}\n'
        )
    mock_nsend = os.path.join(bin_dir, "notify-send")
    with open(mock_nsend, "w", encoding="utf-8") as nf:
        nf.write(
            "#!/usr/bin/env python3\n"
            "import sys\n"
            f"with open({os_notify_log!r}, 'a', encoding='utf-8') as f:\n"
            "    f.write('|'.join(sys.argv[1:]) + '\\n')\n"
        )
    os.chmod(mock_nsend, 0o755)
    notif_base_env = {
        **sess_env("alpha-ws", ws_alpha["ai"]),
        "DBUS_SESSION_BUS_ADDRESS": f"unix:path={os.path.join(root, 'no-such-bus')}",
        "DISPLAY": ":99",
    }

    # Send DECSET 1004 FocusOut (\x1b[O) while cursor stays in alpha-ws AI pane!
    os.write(client_mfd, b"\x1b[O")
    assert wait_until(lambda: (drain_pty() or "focused" not in tmux_out("list-clients", "-t", "=alpha-ws", "-F", "#{client_flags}"))), "tmux did not clear focused client flag on \\x1b[O"

    # Codex-style trailing JSON argument while OS window is unfocused -> sets @ide_ai_attn=1, updates [!] title, fires ide_notify + notify-send with HTML-escaped body!
    codex_json = '{"type":"agent-turn-complete","last-assistant-message":"Checks <green> & fast"}'
    run_cmd([ide_bin, "state", "done", codex_json], env={**notif_base_env, "IDE_NOTIFY": "1"}, check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "done"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "1", "unfocused OS window missed done completion while cursor stayed in AI pane!"
    title_unfocused = tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{E:set-titles-string}")
    assert title_unfocused.startswith("[!] alpha-ws"), f"expected [!] title prefix on unfocused done: {title_unfocused!r}"
    assert wait_until(lambda: os.path.isfile(notify_hook_log) and "done|alpha-ws|claude|" in open(notify_hook_log, encoding="utf-8").read()), "ide_notify hook did not fire on unfocused done"
    assert wait_until(lambda: os.path.isfile(os_notify_log) and "Checks &lt;green&gt; &amp; fast" in open(os_notify_log, encoding="utf-8").read()), "notify-send fallback did not receive HTML-escaped body"
    assert "string:x-canonical-private-synchronous:ide-alpha-ws" in open(os_notify_log, encoding="utf-8").read()

    # Claude-style idle_prompt on non-TTY stdin MUST be ignored and MUST NOT overwrite DONE with ATTN,
    # including >256 KiB multi-chunk slow-writer payloads and >1 MiB payloads without EPIPE!
    def _pipe_chunked_hook(chunks, delay_s=0.0):
        p = subprocess.Popen(
            [ide_bin, "state", "approval", "alpha-ws"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={**notif_base_env, "IDE_NOTIFY": "1"},
        )
        assert p.stdin is not None
        for idx_c, ch_bytes in enumerate(chunks):
            if idx_c > 0 and delay_s > 0:
                time.sleep(delay_s)
            p.stdin.write(ch_bytes)
            p.stdin.flush()
        p.stdin.close()
        rc_p = p.wait(timeout=5.0)
        assert rc_p == 0, f"chunked state failed rc={rc_p}: {p.stderr.read() if p.stderr else b''!r}"

    chunk_a = ('{"pad":"' + ("x" * 110000)).encode("utf-8")
    chunk_b = (("y" * 290000) + '","notification_type":"idle_prompt","message":"Slow writer 400KB"}').encode("utf-8")
    _pipe_chunked_hook([chunk_a, chunk_b], delay_s=0.015)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "done", "400KB slow-writer idle_prompt overwrote DONE with approval!"

    oversized_idle = ('{"notification_type":"idle_prompt","pad":"' + ("z" * 1300000) + '"}').encode("utf-8")
    _pipe_chunked_hook([oversized_idle[:600000], oversized_idle[600000:]], delay_s=0.005)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "done", "1.3MB oversized idle_prompt overwrote DONE with approval!"

    # Send DECSET 1004 FocusIn (\x1b[I) -> tmux pane-focus-in auto-acknowledges alpha-ws!
    os.write(client_mfd, b"\x1b[I")
    assert wait_until(lambda: (drain_pty() or (tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "0" and tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "idle"))), "FocusIn \\x1b[I did not auto-acknowledge AI pane!"

    # When OS window IS focused and AI pane IS visible alongside focused Editor:
    # IDE_NOTIFY=1 suppresses OS desktop banner, IDE_NOTIFY=always sends it, zoomed Editor under IDE_NOTIFY=1 sends it, duplicate approval does not re-fire, and SSH suppresses OS banner!
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    drain_pty()
    open(os_notify_log, "w", encoding="utf-8").close()
    open(notify_hook_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "state", "done", "--message", "Visible pane done", "alpha-ws"], env={**notif_base_env, "IDE_NOTIFY": "1"}, check=True)
    assert wait_until(lambda: os.path.isfile(notify_hook_log) and "Visible pane done" in open(notify_hook_log, encoding="utf-8").read()), "ide_notify hook should still fire on attention edge"
    time.sleep(0.1)
    assert open(os_notify_log, encoding="utf-8").read() == "", f"IDE_NOTIFY=1 spammed OS banner when AI pane was already visible in focused window: {open(os_notify_log, encoding='utf-8').read()!r}"

    # Duplicate done edge must NOT re-trigger ide_notify!
    open(notify_hook_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "state", "done", "--message", "Duplicate", "alpha-ws"], env={**notif_base_env, "IDE_NOTIFY": "always"}, check=True)
    time.sleep(0.15)
    assert open(notify_hook_log, encoding="utf-8").read() == "", "duplicate state transition re-fired notification!"

    # Transition done -> approval with IDE_NOTIFY=always fires even while AI pane is visible!
    run_cmd([ide_bin, "state", "approval", "--message", "Always banner", "alpha-ws"], env={**notif_base_env, "IDE_NOTIFY": "always"}, check=True)
    assert wait_until(lambda: "Always banner" in open(os_notify_log, encoding="utf-8").read()), "IDE_NOTIFY=always did not fire on visible attention edge"

    # Zooming Editor hides AI pane -> IDE_NOTIFY=1 fires!
    run_cmd([ide_bin, "state", "running", "alpha-ws"], env=notif_base_env, check=True)
    open(os_notify_log, "w", encoding="utf-8").close()
    tmux("resize-pane", "-Z", "-t", ws_alpha["ed"], check=True)
    run_cmd([ide_bin, "state", "approval", "--message", "Zoomed editor blocker", "alpha-ws"], env={**notif_base_env, "IDE_NOTIFY": "1"}, check=True)
    assert wait_until(lambda: "Zoomed editor blocker" in open(os_notify_log, encoding="utf-8").read()), "IDE_NOTIFY=1 missed blocker while Editor was zoomed full-screen!"
    tmux("resize-pane", "-Z", "-t", ws_alpha["ed"], check=True)

    # SSH session NEVER fires local OS notification banner even under IDE_NOTIFY=always!
    run_cmd([ide_bin, "state", "running", "alpha-ws"], env=notif_base_env, check=True)
    open(os_notify_log, "w", encoding="utf-8").close()
    run_cmd(
        [ide_bin, "state", "approval", "--message", "SSH blocker", "alpha-ws"],
        env={**notif_base_env, "IDE_NOTIFY": "always", "SSH_CONNECTION": "10.0.0.1 1234 10.0.0.2 22"},
        check=True,
    )
    time.sleep(0.15)
    assert open(os_notify_log, encoding="utf-8").read() == "", "SSH session leaked local desktop notification!"

    # Session-level `-IDE_NOTIFY` removal or empty `IDE_NOTIFY=""` override MUST NOT fall through to global `IDE_NOTIFY=always`!
    tmux("set-environment", "-g", "IDE_NOTIFY", "always", check=True)
    tmux("set-environment", "-t", "=alpha-ws", "-r", "IDE_NOTIFY", check=True)
    env_no_notify_var = {k: v for k, v in notif_base_env.items() if k != "IDE_NOTIFY"}
    run_cmd([ide_bin, "state", "running", "alpha-ws"], env=env_no_notify_var, check=True)
    open(os_notify_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "state", "approval", "--message", "Session muted -r", "alpha-ws"], env=env_no_notify_var, check=True)
    time.sleep(0.15)
    assert open(os_notify_log, encoding="utf-8").read() == "", "session -r IDE_NOTIFY fell through to global IDE_NOTIFY=always!"
    tmux("set-environment", "-t", "=alpha-ws", "IDE_NOTIFY", "", check=True)
    run_cmd([ide_bin, "state", "running", "alpha-ws"], env=env_no_notify_var, check=True)
    run_cmd([ide_bin, "state", "approval", "--message", "Session muted empty", "alpha-ws"], env=env_no_notify_var, check=True)
    time.sleep(0.15)
    assert open(os_notify_log, encoding="utf-8").read() == "", "session empty IDE_NOTIFY= fell through to global IDE_NOTIFY=always!"
    tmux("set-environment", "-gu", "IDE_NOTIFY", check=True)
    tmux("set-environment", "-t", "=alpha-ws", "-u", "IDE_NOTIFY", check=True)

    run_cmd([ide_bin, "state", "idle", "alpha-ws"], env=notif_base_env, check=True)
    run_cmd([ide_bin, "state", "idle", "delta-ws"], env=sess_env("delta-ws", ws_delta["ai"]), check=True)

    # (9d) Zero-fork PR/MR badges (<branch>@<N>), ide pr (local browser & SSH OSC 52), ide_vcs_summary timeout, and WORKING worktree collision guard
    run_cmd(["git", "-C", ws_alpha["dir"], "remote", "add", "origin", "git@github.com:acme/alpha-ws.git"], check=True)
    run_cmd(["git", "-C", ws_alpha["dir"], "config", "branch.feat/switcher.pr", "42"], check=True)

    pr_cache_dir = os.path.join(xdg_cache, "git-pr-prompt")
    os.makedirs(pr_cache_dir, exist_ok=True)
    delta_common = os.path.realpath(os.path.join(ws_delta["dir"], ".git"))
    delta_key = re.sub(r"[^A-Za-z0-9._-]", "_", delta_common)
    with open(os.path.join(pr_cache_dir, f"{delta_key}.state"), "w", encoding="utf-8") as cf:
        cf.write(f"feat/cache|108|https://gitlab.example.com/team/delta/-/merge_requests/108|{now_epoch}\n")

    beta_common = os.path.realpath(os.path.join(ws_beta["dir"], ".git"))
    beta_key = re.sub(r"[^A-Za-z0-9._-]", "_", beta_common)
    run_cmd(["git", "-C", ws_beta["dir"], "checkout", "-q", "-b", "feat/no-pr"], check=True)
    with open(os.path.join(pr_cache_dir, f"{beta_key}.state"), "w", encoding="utf-8") as cf:
        cf.write(f"feat/no-pr|NONE||{now_epoch}\n")

    pr_list = run_cmd([ide_bin, "list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    assert "feat/switcher@42*" in pr_list, f"Tier 0 branch.pr @42 badge missing from list: {pr_list}"
    assert "feat/cache@108" in pr_list, f"Tier 0.5 cached @108 badge missing from list: {pr_list}"
    assert "feat/no-pr@" not in pr_list and "feat/no-pr" in pr_list, f"NONE cache entry leaked @ badge: {pr_list}"

    browser_log = os.path.join(root, "browser_pr.log")
    mock_browser = os.path.join(root, "mock-browser.sh")
    with open(mock_browser, "w", encoding="utf-8") as bf:
        bf.write(f'#!/bin/sh\nprintf "%s\\n" "$1" >> {shlex.quote(browser_log)}\n')
    os.chmod(mock_browser, 0o755)
    run_cmd([ide_bin, "pr", "alpha-ws"], env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_BROWSER": mock_browser}, check=True)
    assert wait_until(lambda: os.path.isfile(browser_log) and "https://github.com/acme/alpha-ws/pull/42" in open(browser_log, encoding="utf-8").read()), "ide pr failed to open Tier 0 GitHub PR URL"

    # Over SSH (without IDE_BROWSER), pr copies URL into tmux buffer (OSC 52) without launching local browser
    run_cmd(
        [ide_bin, "pr", "delta-ws"],
        env={**sess_env("delta-ws", ws_delta["ed"]), "SSH_CONNECTION": "10.0.0.1 1 10.0.0.2 22"},
        check=True,
    )
    assert tmux_out("show-buffer") == "https://gitlab.example.com/team/delta/-/merge_requests/108", f"SSH pr did not load URL into tmux buffer: {tmux_out('show-buffer')!r}"
    assert run_cmd([ide_bin, "pr", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=False).returncode != 0, "pr should exit non-zero when session has no PR URL"

    # Hanging ide_vcs_summary hook in links.sh must time out in ~0.4s without blocking ide list,
    # AND ide _internal session-preview on gamma-ws must stay O(1) without invoking slow peer hooks!
    vcs_inv_log = os.path.join(root, "vcs_invocations.log")
    with open(rules_file, "a", encoding="utf-8") as rf:
        rf.write(
            f'ide_vcs_summary() {{ printf "%s\\n" "$1" >> {shlex.quote(vcs_inv_log)}; if [ "$1" = {shlex.quote(ws_gamma["dir"])} ]; then echo "rev/999|1|rev/999 (pending)|https://cr.example.com/999"; else sleep 2; fi; }}\n'
        )
    vcs_prev_gamma = run_cmd([ide_bin, "_internal", "session-preview", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    prev_vcs_calls = [ln.strip() for ln in open(vcs_inv_log, encoding="utf-8").read().splitlines() if ln.strip()] if os.path.isfile(vcs_inv_log) else []
    assert "rev/999 (pending)" in vcs_prev_gamma and prev_vcs_calls == [ws_gamma["dir"]], (
        f"_internal session-preview failed O(1) ide_vcs_summary scoping (calls={prev_vcs_calls!r}): {vcs_prev_gamma}"
    )
    open(vcs_inv_log, "w", encoding="utf-8").close()
    t0 = time.monotonic()
    vcs_hook_list = run_cmd([ide_bin, "list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    elapsed_vcs = time.monotonic() - t0
    list_vcs_calls = [ln.strip() for ln in open(vcs_inv_log, encoding="utf-8").read().splitlines() if ln.strip()] if os.path.isfile(vcs_inv_log) else []
    assert "rev/999*" in vcs_hook_list and len(list_vcs_calls) == 5 and elapsed_vcs < 5.0, (
        f"ide_vcs_summary hook failed or hung ({elapsed_vcs:.2f}s, calls={list_vcs_calls!r}): {vcs_hook_list}"
    )

    # Multi-session ide_vcs_summary executes concurrently via ThreadPoolExecutor (barrier proves >=2 simultaneous hooks)
    vcs_conc_dir = os.path.join(root, "vcs_conc_markers")
    os.makedirs(vcs_conc_dir, exist_ok=True)
    with open(rules_file, "w", encoding="utf-8") as rf:
        rf.write(
            f'ide_vcs_summary() {{\n'
            f'  : > {shlex.quote(vcs_conc_dir)}/"$$"\n'
            f'  i=0\n'
            f'  while [ "$i" -lt 25 ]; do\n'
            f'    set -- {shlex.quote(vcs_conc_dir)}/*\n'
            f'    if [ "$#" -ge 2 ]; then printf "par-ok|0|par-ok\\n"; return 0; fi\n'
            f'    sleep 0.01\n'
            f'    i=$((i + 1))\n'
            f'  done\n'
            f'  printf "serial-fail|0|serial-fail\\n"\n'
            f'}}\n'
        )
    par_lines_out = run_cmd([ide_bin, "_internal", "sessions-lines", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    assert "par-ok" in par_lines_out and "serial-fail" not in par_lines_out, (
        f"expected concurrent ide_vcs_summary execution across fleet, got: {par_lines_out!r}"
    )
    shutil.rmtree(vcs_conc_dir, ignore_errors=True)

    with open(rules_file, "w", encoding="utf-8") as rf:
        rf.write(
            f'ide_notify() {{ printf "%s|%s|%s|%s|%s|%s\\n" "$1" "$2" "$3" "$4" "$5" "$6" >> {shlex.quote(notify_hook_log)}; }}\n'
        )

    # Git config edge cases: bracketed/escaped branch subsections, includeIf gitdir/onbranch + insteadOf, and non-http(s) prurl rejection!
    inc_cfg = os.path.join(root, "git-corp.inc")
    with open(inc_cfg, "w", encoding="utf-8") as icf:
        icf.write('[url "https://gitlab.corp.example/"]\n\tinsteadOf = corp:[git]:\n[remote "origin"]\n\tforge = gitlab\n')
    global_git_cfg = os.path.join(root, "global.gitconfig")
    with open(global_git_cfg, "w", encoding="utf-8") as ggf:
        ggf.write(f'[includeIf "gitdir:{ws_gamma["dir"].rstrip("/")}/"]\n\tpath = "{inc_cfg}"\n')
    run_cmd(["git", "-C", ws_gamma["dir"], "init", "-q", "-b", 'feat/wip]"1'], check=True)
    run_cmd(["git", "-C", ws_gamma["dir"], "remote", "add", "origin", "corp:[git]:platform/gamma.git"], check=True)
    run_cmd(["git", "-C", ws_gamma["dir"], "config", 'branch.feat/wip]"1.pr', "77"], check=True)
    run_cmd(["git", "-C", ws_gamma["dir"], "config", 'branch.feat/wip]"1.prurl', "-aCalculator"], check=True)
    open(browser_log, "w", encoding="utf-8").close()
    gamma_env_git = {**sess_env("gamma-ws", ws_gamma["ed"]), "GIT_CONFIG_GLOBAL": global_git_cfg, "IDE_BROWSER": mock_browser}
    gamma_pr_list = run_cmd([ide_bin, "list"], env=gamma_env_git, check=True).stdout
    assert 'feat/wip]"1@77' in gamma_pr_list, f'bracketed/escaped [branch "feat/wip]\\"1"] subsection failed to parse @77 badge: {gamma_pr_list}'
    run_cmd([ide_bin, "pr", "gamma-ws"], env=gamma_env_git, check=True)
    assert wait_until(
        lambda: os.path.isfile(browser_log)
        and open(browser_log, encoding="utf-8").read().strip() == "https://gitlab.corp.example/platform/gamma/-/merge_requests/77"
    ), f"unsafe prurl was not rejected or includeIf/insteadOf failed: {open(browser_log, encoding='utf-8').read()!r}"
    # If remote is absent and prurl is file:///etc/passwd, pr must reject it with non-zero exit and zero browser launches
    run_cmd(["git", "-C", ws_gamma["dir"], "remote", "remove", "origin"], check=True)
    run_cmd(["git", "-C", ws_gamma["dir"], "config", 'branch.feat/wip]"1.prurl', "file:///etc/passwd"], check=True)
    open(browser_log, "w", encoding="utf-8").close()
    assert run_cmd([ide_bin, "pr", "gamma-ws"], env=gamma_env_git, check=False).returncode != 0, "file:// prurl was not rejected by pr!"
    assert open(browser_log, encoding="utf-8").read() == "", "file:// prurl launched browser!"
    shutil.rmtree(os.path.join(ws_gamma["dir"], ".git"))

    # Shared worktree collision guard: subdirectory shares worktree root, separate `git worktree add` does NOT!
    wt2_dir = os.path.join(root, "alpha-wt2")
    run_cmd(["git", "-C", ws_alpha["dir"], "worktree", "add", "-q", "-b", "feat/wt2", wt2_dir], check=True)
    ws_alpha_sub = make_ws("alpha-sub-ws", ai_cmd="sleep 300")
    tmux("set-option", "-q", "-t", "=alpha-sub-ws:", "@ide_workdir", os.path.join(ws_alpha["dir"], "sub"), check=True)
    ws_alpha_wt2 = make_ws("alpha-wt2-ws", ai_cmd="sleep 300")
    tmux("set-option", "-q", "-t", "=alpha-wt2-ws:", "@ide_workdir", wt2_dir, check=True)

    # Idle dirty shared worktree -> NO collision warning!
    idle_wt_prev = _ansi_strip_re.sub("", run_cmd([ide_bin, "_internal", "session-preview", "alpha-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout)
    idle_wt_list = run_cmd([ide_bin, "list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert "Warning  : Shared worktree" not in idle_wt_prev, f"false-positive worktree warning while idle: {idle_wt_prev}"
    assert not any("alpha-ws" in ln and ln.rstrip().endswith(" !") for ln in idle_wt_list), f"false-positive ! suffix while idle: {idle_wt_list}"

    # When alpha-ws enters WORKING -> both alpha-ws and alpha-sub-ws warn, while separate git worktree alpha-wt2-ws stays clean!
    run_cmd([ide_bin, "state", "running", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    work_wt_prev_raw = run_cmd([ide_bin, "_internal", "session-preview", "alpha-sub-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    work_wt_prev = _ansi_strip_re.sub("", work_wt_prev_raw)
    wt2_prev = _ansi_strip_re.sub("", run_cmd([ide_bin, "_internal", "session-preview", "alpha-wt2-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout)
    work_wt_list = run_cmd([ide_bin, "list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert "Warning  : Shared worktree with alpha-ws" in work_wt_prev, f"missing shared-worktree warning in preview: {work_wt_prev}"
    assert "\x1b[38;2;181;137;0mShared worktree with alpha-ws" in work_wt_prev_raw, f"expected Solarized Yellow on shared-worktree warning: {work_wt_prev_raw!r}"
    assert "Warning  : Shared worktree" not in wt2_prev, f"separate git worktree falsely warned: {wt2_prev}"
    assert any("alpha-ws" in ln and ln.rstrip().endswith(" !") for ln in work_wt_list), f"missing ! suffix on alpha-ws: {work_wt_list}"
    assert any("alpha-sub-ws" in ln and ln.rstrip().endswith(" !") for ln in work_wt_list), f"missing ! suffix on alpha-sub-ws: {work_wt_list}"
    assert not any("alpha-wt2-ws" in ln and ln.rstrip().endswith(" !") for ln in work_wt_list), f"false ! suffix on separate git worktree: {work_wt_list}"
    run_cmd([ide_bin, "quit", "--force", "alpha-sub-ws", "alpha-wt2-ws", "delta-ws", "shell-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)

    # (9e) Cross-session ide send --switch stages payload without Enter, focuses target AI pane, and switches active client!
    recv_beta_sw = os.path.join(root, "ai_recv_beta_sw.txt")
    tmux(
        "respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"],
        f"/bin/sh -c 'stty -echo -icanon min 1 time 0; exec cat > {recv_beta_sw}'",
        check=True,
    )
    time.sleep(0.1)
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    _read_pty_chunk(0.1)
    beta_mod = os.path.join(ws_beta["dir"], "sub", "mod.py")
    run_cmd(
        [ide_bin, "send", "--ref", f"{beta_mod}:5-7", "--switch", "beta-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_CLIENT": client_name},
        check=True,
    )
    _read_pty_chunk(0.15)
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "beta-ws", "send --switch did not switch active client to beta-ws"
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "ai", "send --switch did not focus beta-ws AI pane"
    assert wait_until(lambda: os.path.isfile(recv_beta_sw) and "@sub/mod.py#L5-L7 " in open(recv_beta_sw, encoding="utf-8").read()), "send --switch payload did not arrive in beta-ws AI pane"
    sw_stream = open(recv_beta_sw, encoding="utf-8").read().replace("\x1b[200~", "").replace("\x1b[201~", "")
    assert sw_stream == "@sub/mod.py#L5-L7 " and "\n" not in sw_stream, f"send --switch unexpectedly submitted newline: {sw_stream!r}"

    # (9f) In-picker Alt+n workspace spawner (zoxide query -l + Esc loop back + launch & switch + $HOME subdir fallback)
    spawn_dir = os.path.join(thome, "projects", "spawned-ws")
    os.makedirs(spawn_dir, exist_ok=True)
    mock_zoxide = os.path.join(root, "mock-zoxide.sh")
    with open(mock_zoxide, "w", encoding="utf-8") as zf:
        zf.write(f'#!/bin/sh\nif [ "$1" = "query" ] && [ "$2" = "-l" ]; then printf "%s\\n" {shlex.quote(spawn_dir)}; fi\n')
    os.chmod(mock_zoxide, 0o755)

    altn_state = os.path.join(root, "altn_state.txt")
    altn_fzf = os.path.join(root, "altn-fzf.py")
    with open(altn_fzf, "w", encoding="utf-8") as af:
        af.write(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            f"st_path = {altn_state!r}\n"
            "step = int(open(st_path).read().strip()) if os.path.isfile(st_path) else 0\n"
            "open(st_path, 'w').write(str(step + 1))\n"
            "lines = [l.rstrip('\\n') for l in sys.stdin if l.strip()]\n"
            "args = ' '.join(sys.argv[1:])\n"
            "if step == 0:\n"
            "    assert 'ctrl-y:execute-silent' in args and 'ctrl-o:execute-silent' in args and 'alt-n' in args and 'alt-o' in args and 'alt-r' in args and '--bind=f1:execute(' in args and '--bind=f5:' in args, f'missing triage/launcher/CUA binds: {args}'\n"
            "    assert '--border=rounded' in args and '--border-label-pos=bottom' in args and '--border-label= Enter: switch · C-a/e/t: pane · C-y: ack · C-o: PR · M-n: new · M-o: open · M-r: agent · C-x: quit · C-r/F5: reload · F1: help · Alt+s: close ' in args and '--header=' not in args, f'missing bottom border-label on step 0: {args}'\n"
            "    print('alt-o')\n"
            "    print(lines[0])\n"
            "elif step == 1:\n"
            "    assert '--prompt=New IDE > ' in args and '--border=rounded' in args and '--border-label-pos=bottom' in args and '--border-label= Enter: launch · Alt+n: new · Esc: back to sessions ' in args and '--color=label:#586E75' in args and 'border:#586E75' in args and '--header=' not in args, f'expected New IDE prompt and bottom border-label on step 1: {args}'\n"
            "    sys.exit(130)\n"
            "elif step == 2:\n"
            "    assert '--prompt=IDE > ' in args and '--border-label-pos=bottom' in args and '--border-label= Enter: switch · C-a/e/t: pane · C-y: ack · C-o: PR · M-n: new · M-o: open · M-r: agent · C-x: quit · C-r/F5: reload · F1: help · Alt+s: close ' in args, f'Esc from Alt+o did not return to session list: {args}'\n"
            "    print('alt-o')\n"
            "elif step == 3:\n"
            "    assert '--border=rounded' in args and '--border-label-pos=bottom' in args and '--border-label= Enter: launch · Alt+n: new · Esc: back to sessions ' in args, f'expected bottom border-label on step 3: {args}'\n"
            "    picked = next(l for l in lines if 'spawned-ws' in l)\n"
            "    print(picked)\n"
        )
    os.chmod(altn_fzf, 0o755)

    run_cmd(
        [ide_bin, "switch", "beta-ws"],
        env={
            **sess_env("beta-ws", ws_beta["ed"]),
            "IDE_NO_POPUP": "1",
            "IDE_FZF_BIN": altn_fzf,
            "IDE_ZOXIDE_BIN": mock_zoxide,
            "IDE_CLIENT": client_name,
            "COLUMNS": "160",
        },
        check=True,
    )
    _read_pty_chunk(0.2)
    assert open(altn_state, encoding="utf-8").read().strip() == "4", f"expected 4 fzf invocations across Alt+n -> Esc -> Alt+n -> Enter, got {open(altn_state).read()!r}"
    assert tmux("has-session", "-t", "=spawned-ws", check=False).returncode == 0, "Alt+n did not spawn spawned-ws session"
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "spawned-ws", "Alt+n did not switch client into spawned-ws"

    # Also verify $HOME immediate subdirectory fallback when zoxide is unavailable/empty
    empty_zoxide = os.path.join(root, "empty-zoxide.sh")
    with open(empty_zoxide, "w", encoding="utf-8") as ez:
        ez.write("#!/bin/sh\nexit 1\n")
    os.chmod(empty_zoxide, 0o755)
    home_fb_dir = os.path.join(thome, "fallback-ws")
    os.makedirs(home_fb_dir, exist_ok=True)
    fb_state = os.path.join(root, "fb_state.txt")
    fb_fzf = os.path.join(root, "fb-fzf.py")
    with open(fb_fzf, "w", encoding="utf-8") as ff:
        ff.write(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            f"st_path = {fb_state!r}\n"
            "step = int(open(st_path).read().strip()) if os.path.isfile(st_path) else 0\n"
            "open(st_path, 'w').write(str(step + 1))\n"
            "lines = [l.rstrip('\\n') for l in sys.stdin if l.strip()]\n"
            "if step == 0:\n"
            "    print('alt-o')\n"
            "else:\n"
            "    picked = next(l for l in lines if 'fallback-ws' in l)\n"
            "    print(picked)\n"
        )
    os.chmod(fb_fzf, 0o755)
    run_cmd(
        [ide_bin, "switch", "spawned-ws"],
        env={
            **sess_env("spawned-ws"),
            "IDE_NO_POPUP": "1",
            "IDE_FZF_BIN": fb_fzf,
            "IDE_ZOXIDE_BIN": empty_zoxide,
            "IDE_CLIENT": client_name,
        },
        check=True,
    )
    _read_pty_chunk(0.2)
    assert tmux("has-session", "-t", "=fallback-ws", check=False).returncode == 0
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "fallback-ws"

    # (9g) QUOTA fleet state: passive @ide_ai_attn=0, elapsed age preservation, Tier 2 ordering (WORKING > QUOTA > IDLE > SHELL), focus preservation, and SHELL guard
    tmux("respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"], "exec sleep 300", check=True)
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec sleep 300", check=True)
    tmux("respawn-pane", "-k", "-t", ws_gamma["ai"], "-c", ws_gamma["dir"], "exec sleep 300", check=True)
    assert wait_until(
        lambda: tmux_out("display-message", "-p", "-t", ws_alpha["ai"], "#{pane_current_command}") == "sleep"
        and tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sleep"
        and tmux_out("display-message", "-p", "-t", ws_gamma["ai"], "#{pane_current_command}") == "sleep"
    )
    tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
    _read_pty_chunk(0.15)
    run_cmd([ide_bin, "quit", "--force", "spawned-ws", "fallback-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    open(notify_hook_log, "w", encoding="utf-8").close()
    open(os_notify_log, "w", encoding="utf-8").close()

    run_cmd([ide_bin, "state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    run_cmd([ide_bin, "state", "idle", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)
    run_cmd([ide_bin, "state", "quota", "alpha-ws"], env={**notif_base_env, "IDE_NOTIFY": "always"}, check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "quota"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "0", "quota state must stay passive (@ide_ai_attn=0)"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "", "quota state must not enter @ide_attn_summary"
    time.sleep(0.1)
    assert open(notify_hook_log, encoding="utf-8").read() == "" and open(os_notify_log, encoding="utf-8").read() == "", "quota state must not fire attention notifications"

    tmux("set-option", "-q", "-t", "=alpha-ws:", "@ide_ai_state_ts", str(now_epoch - 720), check=True)
    run_cmd([ide_bin, "state", "quota", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state_ts") == str(now_epoch - 720), "repeated quota hook reset @ide_ai_state_ts!"

    quota_order = run_cmd([ide_bin, "list", "--plain"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert quota_order == ["beta-ws", "alpha-ws", "gamma-ws"], f"expected WORKING (beta-ws) > QUOTA (alpha-ws) > IDLE (gamma-ws), got {quota_order}"
    quota_list = run_cmd([ide_bin, "list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    assert "QUOTA 12m" in quota_list, f"expected QUOTA 12m in list: {quota_list}"
    quota_prev = run_cmd([ide_bin, "_internal", "session-preview", "alpha-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    assert "QUOTA 12m" in quota_prev, f"expected QUOTA 12m in _internal session-preview: {quota_prev}"

    # Focusing AI pane (_internal ack-hook) must preserve active quota state while child process is alive,
    # and classify_ide_fleet() must clear stale quota to SHELL once the AI process exits to a bare shell.
    run_cmd([ide_bin, "_internal", "ack-hook", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "quota", "_internal ack-hook wiped live quota state!"
    tmux("respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"], "exec /bin/sh", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_alpha["ai"], "#{pane_current_command}") == "sh")
    shell_after_quota = run_cmd([ide_bin, "list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert any("alpha-ws" in ln and "SHELL" in ln for ln in shell_after_quota), f"exited quota pane did not transition to SHELL: {shell_after_quota}"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "", "classify_ide_fleet did not clear stale @ide_ai_state=quota on bare shell"

    # 10. Adversarial regression coverage for F-02..F-13:
    # (10a) F-02: classify_ide_fleet() #{window_active} & OS focus guard (background window must NOT auto-clear done attention)
    tmux("respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"], "exec sleep 300", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_alpha["ai"], "#{pane_current_command}") == "sleep")
    tmux("switch-client", "-c", client_name, "-t", "=beta-ws", check=True)
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    assert wait_until(lambda: (drain_pty() or "focused" in tmux_out("list-clients", "-t", "=beta-ws", "-F", "#{client_flags}")))
    bg_win_id = tmux_out("new-window", "-P", "-F", "#{window_id}", "-t", "=beta-ws", "-n", "scratch", "exec sleep 300")
    drain_pty()
    run_cmd([ide_bin, "state", "done", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1", "done while viewing 2nd tmux window failed to set @ide_ai_attn=1!"
    run_cmd([ide_bin, "list", "--plain"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1", "classify_ide_fleet falsely cleared done attention while AI window was inactive!"
    tmux("kill-window", "-t", bg_win_id, check=True)
    drain_pty()
    run_cmd([ide_bin, "list", "--plain"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "0", "classify_ide_fleet did not clear done once active focused AI window returned!"

    # (10b) F-06: @ide_ai_msg persistence, ANSI/8-bit CSI/control stripping, 160-char cap, repeat preservation, Message preview, and state-transition clearing
    long_dirty_msg = "[\x1b[32mOK\x1b[0m] \x9b31mRate limit\x9b0m\t\nhit: " + ("x" * 180)
    run_cmd([ide_bin, "state", "quota", "--message", long_dirty_msg, "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    stored_msg = tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_msg")
    assert stored_msg.startswith("[OK] Rate limit hit: ") and "\x1b" not in stored_msg and "\x9b" not in stored_msg and "\t" not in stored_msg and len(stored_msg) == 160 and stored_msg.endswith("…"), f"bad @ide_ai_msg sanitization/cap: {stored_msg!r}"
    # Repeat quota hook without --message preserves existing @ide_ai_msg
    run_cmd([ide_bin, "state", "quota", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_msg") == stored_msg, "repeat quota hook wiped @ide_ai_msg!"
    prev_msg_out = _ansi_strip_re.sub("", run_cmd([ide_bin, "_internal", "session-preview", "alpha-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout)
    assert "Message  : [OK] Rate limit hit:" in prev_msg_out, f"missing Message row in _internal session-preview: {prev_msg_out}"
    # Transitioning to running clears @ide_ai_msg
    run_cmd([ide_bin, "state", "running", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_msg") == "", "running state did not clear @ide_ai_msg!"
    # Approval preserves @ide_ai_msg across focus/ack; done clears @ide_ai_msg when acknowledged to idle
    tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
    drain_pty()
    run_cmd([ide_bin, "state", "approval", "--message", "Approve rm -rf build?", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    run_cmd([ide_bin, "ack", "alpha-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_msg") == "Approve rm -rf build?", "acknowledging approval wiped @ide_ai_msg!"
    run_cmd([ide_bin, "state", "done", "--message", "All tests green", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_msg") == "All tests green"
    run_cmd([ide_bin, "ack", "alpha-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_msg") == "", "acking done -> idle did not clear @ide_ai_msg!"

    # (10c) F-05: Ctrl+x (quit {+1}, including multi-select) in Alt+s popup (IDE_IN_POPUP=1) on dirty Neovim buffer NEVER hijacks outer client and surfaces [unsaved] + Warning
    if shutil.which("nvim"):
        ws_pop_dirty = make_ws("pop-dirty-ws", ai_cmd="sleep 300")
        ws_pop_clean = make_ws("pop-clean-ws", ai_cmd="sleep 300")
        _ = ws_pop_clean
        pop_sock = tmux_out("show-options", "-qv", "-t", "=pop-dirty-ws:", "@ide_socket")
        pop_file = os.path.join(ws_pop_dirty["dir"], "unsaved_pop.txt")
        tmux(
            "respawn-pane", "-k", "-t", ws_pop_dirty["ed"], "-c", ws_pop_dirty["dir"],
            f"nvim --headless -u NONE -i NONE --listen {shlex.quote(pop_sock)} -c {shlex.quote('edit ' + pop_file)} -c \"call setline(1, 'unsaved')\"",
            check=True,
        )
        assert wait_until(lambda: nvim_expr_eq(pop_sock, "&modified", "1")), "pop-dirty-ws nvim buffer did not become modified"
        tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
        drain_pty()
        r_pop_q = run_cmd(
            [ide_bin, "quit", "pop-dirty-ws", "pop-clean-ws"],
            env={**sess_env("gamma-ws", ws_gamma["ed"]), "IDE_IN_POPUP": "1", "IDE_CLIENT": client_name},
            check=False,
        )
        assert r_pop_q.returncode != 0, "expected non-zero from popup quit when one selected session has dirty buffers"
        assert tmux("has-session", "-t", "=pop-clean-ws", check=False).returncode != 0, "clean session in multi-quit should still close"
        assert tmux("has-session", "-t", "=pop-dirty-ws", check=False).returncode == 0, "dirty session must survive multi-quit"
        assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "gamma-ws", "IDE_IN_POPUP=1 quit hijacked outer client behind popup!"
        assert "Unsaved changes" in tmux_out("show-options", "-qv", "-t", "=pop-dirty-ws:", "@ide_quit_err")
        pop_lines = _ansi_strip_re.sub("", run_cmd([ide_bin, "_internal", "sessions-lines", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout)
        assert "[unsaved]" in pop_lines, f"missing [unsaved] badge in _internal sessions-lines: {pop_lines}"
        pop_prev = _ansi_strip_re.sub("", run_cmd([ide_bin, "_internal", "session-preview", "pop-dirty-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout)
        assert "Warning  : Unsaved changes in 1 buffer(s)" in pop_prev, f"missing Warning in _internal session-preview: {pop_prev}"
        # Saving buffer in Neovim auto-clears @ide_quit_err on next preview!
        subprocess.run(["nvim", "--headless", "--server", pop_sock, "--remote-send", "<C-\\><C-n>:write!<CR>"], env=base_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5, check=True)
        assert wait_until(lambda: nvim_expr_eq(pop_sock, "&modified", "0")), "pop-dirty-ws nvim buffer did not become clean after :write!"
        pop_prev_clean = _ansi_strip_re.sub("", run_cmd([ide_bin, "_internal", "session-preview", "pop-dirty-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout)
        assert "Unsaved changes" not in pop_prev_clean and tmux_out("show-options", "-qv", "-t", "=pop-dirty-ws:", "@ide_quit_err") == ""
        run_cmd([ide_bin, "quit", "pop-dirty-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)

    # (10d) F-07: send_to_ai() refuses bare shell AI pane and strips nested \x1b[200~ / \x1b[201~ / \x9b201~ bracketed-paste escapes
    tmux("respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"], "exec /bin/sh", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_alpha["ai"], "#{pane_current_command}") == "sh")
    r_bare_send = run_cmd([ide_bin, "send", "--text", "echo PWNED_BARE_SHELL", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=False)
    assert r_bare_send.returncode != 0 and "idle shell prompt" in r_bare_send.stderr, f"expected bare-shell refusal on send, got {r_bare_send}"
    assert "PWNED_BARE_SHELL" not in tmux_out("capture-pane", "-p", "-t", ws_alpha["ai"]), "send_to_ai pasted into bare shell!"

    recv_bp = os.path.join(root, "ai_recv_bp.txt")
    tmux(
        "respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"],
        f"/bin/sh -c 'stty -echo -icanon min 1 time 0; exec cat > {recv_bp}'",
        check=True,
    )
    time.sleep(0.1)
    run_cmd([ide_bin, "send", "--no-focus", "--text", "safe\x1b[20\x1b[201~1~mid\x1b[200~end\x9b201~!", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert wait_until(lambda: os.path.isfile(recv_bp) and "safe" in open(recv_bp, encoding="utf-8").read())
    bp_raw = open(recv_bp, encoding="utf-8").read()
    # Outer paste-buffer -p wraps at most once; inner payload must contain zero embedded 200~/201~ breakouts!
    bp_inner = bp_raw
    if bp_inner.startswith("\x1b[200~"):
        bp_inner = bp_inner[len("\x1b[200~"):]
    if bp_inner.endswith("\x1b[201~"):
        bp_inner = bp_inner[: -len("\x1b[201~")]
    assert bp_inner == "safemidend!", f"nested bracketed-paste escapes were not stripped: {bp_raw!r}"

    # (10e) F-08: open_browser_url() blocks leading '-' option flags and non-http(s) schemes from ide_resolve_link
    open(browser_log, "w", encoding="utf-8").close()
    with open(rules_file, "w", encoding="utf-8") as rf:
        rf.write(
            'ide_resolve_link() {\n'
            '  case "$1" in\n'
            '    badflag) echo "-aCalculator" ;;\n'
            '    badjs) echo "javascript:alert(1)" ;;\n'
            '    goodurl) echo "https://example.com/safe-target" ;;\n'
            '  esac\n'
            '}\n'
        )
    link_env_f08 = {**sess_env("gamma-ws", ws_gamma["ed"]), "IDE_BROWSER": mock_browser}
    assert run_cmd([ide_bin, "_internal", "open-link", "", "badflag", ws_gamma["dir"], "gamma-ws"], env=link_env_f08, check=False).returncode != 0
    assert run_cmd([ide_bin, "_internal", "open-link", "", "badjs", ws_gamma["dir"], "gamma-ws"], env=link_env_f08, check=False).returncode != 0
    assert open(browser_log, encoding="utf-8").read() == "", f"unsafe ide_resolve_link output launched browser: {open(browser_log, encoding='utf-8').read()!r}"
    run_cmd([ide_bin, "_internal", "open-link", "", "goodurl", ws_gamma["dir"], "gamma-ws"], env=link_env_f08, check=True)
    assert wait_until(lambda: open(browser_log, encoding="utf-8").read().strip() == "https://example.com/safe-target")

    # (10f) F-09: resolve_ai_cmd() quotes executable paths containing spaces and falls back when IDE_AI_CLI is uninstalled
    open(os.path.join(thome, ".zshrc"), "a", encoding="utf-8").close()
    spaced_dir = os.path.join(root, "dir with spaces")
    os.makedirs(spaced_dir, exist_ok=True)
    spaced_cli = os.path.join(spaced_dir, "custom agent")
    spaced_marker = os.path.join(root, "spaced_agent_ran.txt")
    with open(spaced_cli, "w", encoding="utf-8") as sf:
        sf.write(f"#!/bin/sh\necho ok > {shlex.quote(spaced_marker)}\nexec sleep 300\n")
    os.chmod(spaced_cli, 0o755)
    f09_ws_dir = os.path.join(root, "f09-spaced-ws")
    os.makedirs(f09_ws_dir, exist_ok=True)
    run_cmd([ide_bin, "--detach", "--agent", spaced_cli, f09_ws_dir], env=base_env, check=True)
    assert wait_until(lambda: os.path.isfile(spaced_marker), timeout=3.0), "spaced AI CLI path failed to launch via send-keys!"
    run_cmd([ide_bin, "quit", "--force", "f09-spaced-ws"], env=base_env, check=True)

    f09_fb_dir = os.path.join(root, "f09-fb-ws")
    os.makedirs(f09_fb_dir, exist_ok=True)
    mock_claude_dir = os.path.join(root, "mock_claude_bin")
    os.makedirs(mock_claude_dir, exist_ok=True)
    for sys_tool in ("tmux", "bash", "sh", "zsh", "python3", "env", "sleep", "mktemp", "rm", "ps"):
        real_t = shutil.which(sys_tool)
        if real_t and not os.path.exists(os.path.join(mock_claude_dir, sys_tool)):
            os.symlink(real_t, os.path.join(mock_claude_dir, sys_tool))
    fb_claude_marker = os.path.join(root, "fb_claude_ran.txt")
    with open(os.path.join(mock_claude_dir, "claude"), "w", encoding="utf-8") as cf:
        cf.write(f"#!/bin/sh\necho fallback_ok > {shlex.quote(fb_claude_marker)}\nexec sleep 300\n")
    os.chmod(os.path.join(mock_claude_dir, "claude"), 0o755)
    run_cmd(
        [ide_bin, "--detach", f09_fb_dir],
        env={**base_env, "IDE_STRICT_PATH": "1", "IDE_AI_CLI": "nonexistent-custom-ai-xyz", "PATH": mock_claude_dir},
        check=True,
    )
    assert tmux_out("show-options", "-qv", "-t", "=f09-fb-ws:", "@ide_ai_cli") == "claude", "missing IDE_AI_CLI did not update @ide_ai_cli to fallback 'claude'"
    assert wait_until(lambda: os.path.isfile(fb_claude_marker), timeout=3.0), "missing IDE_AI_CLI did not fall back cleanly to claude!"
    run_cmd([ide_bin, "quit", "--force", "f09-fb-ws"], env=base_env, check=True)

    f09_cwd_dir = os.path.join(root, "f09-cwd-ws")
    os.makedirs(f09_cwd_dir, exist_ok=True)
    cwd_agent_marker = os.path.join(root, "cwd_agent_ran.txt")
    with open(os.path.join(f09_cwd_dir, "local-agent-bin"), "w", encoding="utf-8") as lcf:
        lcf.write(f"#!/bin/sh\necho cwd_ok > {shlex.quote(cwd_agent_marker)}\nexec sleep 300\n")
    os.chmod(os.path.join(f09_cwd_dir, "local-agent-bin"), 0o755)
    subprocess.run(
        [ide_bin, "--detach", "--agent", "local-agent-bin", f09_cwd_dir],
        cwd=f09_cwd_dir,
        env={**base_env, "IDE_STRICT_PATH": "1", "PATH": mock_claude_dir},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    assert wait_until(lambda: os.path.isfile(cwd_agent_marker), timeout=3.0), "CWD-local --agent executable without '/' fell back to claude instead of launching!"
    run_cmd([ide_bin, "quit", "--force", "f09-cwd-ws"], env=base_env, check=True)

    # (10g) F-04 CLI status_click() bounds, ad-hoc split role, & F-11 ad-hoc split Alt+a bounce-back + unpark_role_pane geometry
    tmux("select-pane", "-t", ws_gamma["ed"], check=True)
    adhoc_pane = tmux_out("split-window", "-h", "-P", "-F", "#{pane_id}", "-t", ws_gamma["ed"], "-c", ws_gamma["dir"], "exec sleep 300")
    assert tmux_out("show-options", "-pqv", "-t", adhoc_pane, "@ide_role") == "", "ad-hoc split should keep empty @ide_role"
    # Out-of-bounds status_click (x=135) must be a strict no-op (both unzoomed and zoomed)!
    run_cmd([ide_bin, "_internal", "status-click", "135", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{pane_id}") == adhoc_pane, "out-of-bounds status_click hijacked focus!"
    tmux("resize-pane", "-Z", "-t", adhoc_pane, check=True)
    run_cmd([ide_bin, "_internal", "status-click", "135", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{window_zoomed_flag}") == "1", "out-of-bounds status_click unzoomed pane!"
    tmux("resize-pane", "-Z", "-t", adhoc_pane, check=True)
    # Alt+a (_internal toggle) from ad-hoc split focuses AI, and second Alt+a bounces right back to adhoc_pane!
    run_cmd([ide_bin, "_internal", "toggle", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{pane_id}") == ws_gamma["ai"]
    run_cmd([ide_bin, "_internal", "toggle", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{pane_id}") == adhoc_pane, "Alt+a failed to bounce back to ad-hoc split!"
    # Park AI and Editor while Shell (bar_role) AND adhoc_pane stay visible -> unparking Editor joins horizontally beside adhoc_pane (not 3 vertical rows)!
    run_cmd([ide_bin, "_internal", "park", "editor", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    run_cmd([ide_bin, "_internal", "park", "ai", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    run_cmd([ide_bin, "_internal", "park", "editor", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    ed_top_w_bar = tmux_out("display-message", "-p", "-t", ws_gamma["ed"], "#{pane_top}")
    adhoc_top_w_bar = tmux_out("display-message", "-p", "-t", adhoc_pane, "#{pane_top}")
    assert ed_top_w_bar == adhoc_top_w_bar, f"unpark_role_pane stacked Editor vertically instead of beside adhoc_pane: ed_top={ed_top_w_bar} adhoc_top={adhoc_top_w_bar}"
    # Park all 3 canonical panes while adhoc_pane stays visible, then unpark Editor alongside adhoc_pane!
    run_cmd([ide_bin, "_internal", "park", "term", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    run_cmd([ide_bin, "_internal", "park", "editor", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    assert tmux_out("list-panes", "-t", "=gamma-ws:", "-F", "#{pane_id}").splitlines() == [adhoc_pane]
    run_cmd([ide_bin, "_internal", "park", "editor", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    vis_after_unpark = tmux_out("list-panes", "-t", "=gamma-ws:", "-F", "#{pane_id}").splitlines()
    assert adhoc_pane in vis_after_unpark and ws_gamma["ed"] in vis_after_unpark, f"unpark_role_pane failed when only ad-hoc split was visible: {vis_after_unpark}"
    tmux("kill-pane", "-t", adhoc_pane, check=True)

    # (10h) F-13: literal tab character in workspace directory path + odd/even/comment trailing backslashes & quoted leading-space continuations in .git/config
    tab_ws_dir = os.path.join(root, "dir\twith\ttab")
    os.makedirs(tab_ws_dir, exist_ok=True)
    run_cmd(["git", "-C", tab_ws_dir, "init", "-q", "-b", "feat/tab-bs"], check=True)
    with open(os.path.join(tab_ws_dir, ".git", "config"), "a", encoding="utf-8") as gcf:
        gcf.write(
            '# Windows path comment ending in backslash C:\\\n'
            '[url "https://github.com/wrong/"]\n'
            '\tinsteadOf = corp\\\\\\\\\n'
            '[url "https://gitlab.com/acme/"]\n'
            '\tinsteadOf = "corp\\"bs\\\\\\\n  sp:"\n'
            '# Another backslash comment \\\n'
            '[remote "orig\\"in\\\\1"]\n'
            '\turl = "corp\\"bs\\\\  sp:tabrepo.git" # trailing comment \\\n'
            '[branch "feat/tab-bs"]\n'
            '\tpr = \\\n'
            '\t\t91 # inline comment ending in \\\n'
            '\tremote = "orig\\"in\\\\1"\n'
        )
    tmux("set-option", "-q", "-t", "=beta-ws:", "@ide_workdir", tab_ws_dir, check=True)
    tab_list = run_cmd([ide_bin, "list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    assert "feat/tab-bs@91" in tab_list and "beta-ws" in tab_list, f"literal tab path or odd/even backslash config broke list: {tab_list!r}"
    open(browser_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "pr", "beta-ws"], env={**sess_env("beta-ws", ws_beta["ed"]), "IDE_BROWSER": mock_browser}, check=True)
    assert wait_until(lambda: open(browser_log, encoding="utf-8").read().strip() == "https://gitlab.com/acme/tabrepo/-/merge_requests/91"), (
        f"even trailing backslash in .git/config corrupted remote URL: {open(browser_log, encoding='utf-8').read()!r}"
    )

    # (10i) tmux <= 3.4 utf8_stravis C0-octal escaping regression guard:
    # Older tmux releases (e.g. Ubuntu 22.04/24.04 tmux 3.2a/3.4) escape non-tab/newline C0 control
    # characters (< 0x20 except \t and \n) in display-message / list-* format strings as octal \037.
    # Ensure bin/ide uses printable/tab-based _TMUX_SEP and survives C0-octal-escaped tmux format output
    # even when @ide_workdir contains literal tab characters.
    ide_full_src = open(real_ide_path, encoding="utf-8").read()
    constants_src = open(os.path.join(repo_dir, "libexec", "ide_lib", "constants.py"), encoding="utf-8").read()
    assert '_TMUX_SEP = "\\t__IDE_SEP__\\t"' in constants_src, "missing printable/tab _TMUX_SEP delimiter in bin/ide_lib/constants.py"
    real_tmux_bin = shutil.which("tmux")
    assert real_tmux_bin, "tmux binary not found on PATH"
    tmux34_dir = os.path.join(root, "tmux34_compat_bin")
    os.makedirs(tmux34_dir, exist_ok=True)
    tmux34_hits = os.path.join(root, "tmux34_hits.log")
    tmux34_wrap = os.path.join(tmux34_dir, "tmux")
    with open(tmux34_wrap, "w", encoding="utf-8") as twf:
        twf.write(
            "#!/usr/bin/env python3\n"
            "import subprocess, sys\n"
            f"REAL_TMUX = {real_tmux_bin!r}\n"
            f"HIT_LOG = {tmux34_hits!r}\n"
            "FMT_CMDS = {'display-message', 'display', 'list-sessions', 'ls', 'list-panes', 'lsp', 'list-clients', 'lsc', 'list-windows', 'lsw'}\n"
            "r = subprocess.run([REAL_TMUX, *sys.argv[1:]], stdout=subprocess.PIPE, stderr=subprocess.PIPE)\n"
            "out = r.stdout\n"
            "if any(a in FMT_CMDS for a in sys.argv[1:]):\n"
            "    with open(HIT_LOG, 'a', encoding='utf-8') as hf:\n"
            "        hf.write('1\\n')\n"
            "    escaped = bytearray()\n"
            "    for b in out:\n"
            "        if b < 0x20 and b not in (0x09, 0x0a):\n"
            "            escaped.extend(f'\\\\{b:03o}'.encode('ascii'))\n"
            "        else:\n"
            "            escaped.append(b)\n"
            "    out = bytes(escaped)\n"
            "sys.stdout.buffer.write(out)\n"
            "sys.stderr.buffer.write(r.stderr)\n"
            "sys.exit(r.returncode)\n"
        )
    os.chmod(tmux34_wrap, 0o755)
    t34_path = f"{tmux34_dir}:{base_env['PATH']}"
    env_t34_ed = {**sess_env("beta-ws", ws_beta["ed"]), "PATH": t34_path}
    t34_plain = run_cmd([ide_bin, "list", "--plain"], env=env_t34_ed, check=True).stdout.splitlines()
    assert t34_plain and t34_plain[0] == "beta-ws" and {"alpha-ws", "beta-ws", "gamma-ws"}.issubset(set(t34_plain)), (
        f"tmux 3.4 C0-octal escaping broke current_ide_session / list --plain: {t34_plain!r}"
    )
    t34_list = run_cmd([ide_bin, "list"], env=env_t34_ed, check=True).stdout
    assert "feat/tab-bs@91" in t34_list and "beta-ws" in t34_list, f"tmux 3.4 C0-octal escaping broke list with tab path: {t34_list!r}"
    panes_before_t34 = tmux_out("list-panes", "-t", "=beta-ws:", "-F", "#{pane_id}").splitlines()
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "_internal", "toggle", "beta-ws"], env=env_t34_ed, check=True)
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "ai", "tmux 3.4 C0-octal escaping broke _internal toggle -> ai"
    run_cmd([ide_bin, "_internal", "toggle", "beta-ws"], env={**sess_env("beta-ws", ws_beta["ai"]), "PATH": t34_path}, check=True)
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "editor", "tmux 3.4 C0-octal escaping broke _internal toggle -> editor"
    panes_after_t34 = tmux_out("list-panes", "-t", "=beta-ws:", "-F", "#{pane_id}").splitlines()
    assert panes_after_t34 == panes_before_t34, f"tmux 3.4 C0-octal escaping spawned extra panes during _internal toggle: {panes_before_t34} -> {panes_after_t34}"
    assert os.path.isfile(tmux34_hits) and len(open(tmux34_hits, encoding="utf-8").read().splitlines()) >= 4, "tmux34_wrap shim did not intercept tmux format commands!"

    # Also verify dotfiles/.tmux.conf preserves status-bar click fallback when #{mouse_status_range} is empty (tmux < 3.4, e.g. 3.2a/3.3a)
    tmux_conf_txt = open(tmux_conf_src, encoding="utf-8").read()
    for status_ev in ("MouseDown1Status", "DoubleClick1Status", "TripleClick1Status"):
        assert re.search(rf"bind -n {status_ev}\b.*mouse_status_range\}},.*_internal status-click", tmux_conf_txt), (
            f"missing tmux < 3.4 empty mouse_status_range _internal status-click fallback on {status_ev}"
        )

    # (10j) External workspace hooks (ide_workspace_dirs + IDE_WORKSPACE_DIRS + ide_resolve_workspace),
    # zoxide query -l --all frecency collapsing & fallback, zero negative-lookup stat() on dead managed children,
    # ide -n / --new (popup + --2pane + error guards), and _call_ide_hook 1.0s timeout resilience
    ext_parent = os.path.join(root, "ext_mounts")
    env_parent = os.path.join(root, "env_mounts")
    ws_frec = os.path.join(ext_parent, "ws-frecency")
    ws_unvis = os.path.join(ext_parent, "ws-unvisited")
    ws_deleted = os.path.join(ext_parent, "ws-deleted")
    ws_env_only = os.path.join(env_parent, "ws-env-only")
    home_top = os.path.join(thome, "projects", "local-top")
    home_low = os.path.join(thome, "projects", "local-low")
    home_unvis = os.path.join(thome, "unvisited-home-dir")
    home_hidden = os.path.join(thome, ".hidden-home-dir")
    for p_mk in (
        os.path.join(ws_frec, "src_tree", "deep", "pkg"),
        os.path.join(ws_unvis, "src_tree"),
        ws_env_only,
        home_top,
        home_low,
        home_unvis,
        home_hidden,
    ):
        os.makedirs(p_mk, exist_ok=True)

    ext_rules_path = os.path.join(root, "ext_launcher_rules.sh")
    with open(ext_rules_path, "w", encoding="utf-8") as erf:
        erf.write(
            f"ide_workspace_dirs() {{\n"
            f"    printf '%s\\n' {shlex.quote(ws_frec)} {shlex.quote(ws_unvis)} {shlex.quote(ws_deleted)}\n"
            f"}}\n"
            f"ide_resolve_workspace() {{\n"
            f"    case \"${{1%/}}\" in\n"
            f"        {shlex.quote(ws_frec)}|ws-frecency) printf '%s\\n' {shlex.quote(os.path.join(ws_frec, 'src_tree'))}; return 0 ;;\n"
            f"        {shlex.quote(ws_unvis)}|ws-unvisited) printf '%s\\n' {shlex.quote(os.path.join(ws_unvis, 'src_tree'))}; return 0 ;;\n"
            f"    esac\n"
            f"    return 1\n"
            f"}}\n"
            f"ide_session_name() {{\n"
            f"    case \"$1\" in\n"
            f"        {shlex.quote(ext_parent)}/*)\n"
            f"            rem=\"${{1#{shlex.quote(ext_parent)}/}}\"\n"
            f"            printf '%s\\n' \"${{rem%%/*}}\"\n"
            f"            return 0 ;;\n"
            f"    esac\n"
            f"    return 1\n"
            f"}}\n"
        )

    zox_all_bin = os.path.join(root, "zox-all.sh")
    with open(zox_all_bin, "w", encoding="utf-8") as zab:
        zab.write(
            "#!/bin/sh\n"
            'if [ "$1" = "query" ] && [ "$2" = "-l" ] && [ "${3:-}" = "--all" ]; then\n'
            f"    printf '%s\\n' {shlex.quote(home_top)} {shlex.quote(os.path.join(ws_deleted, 'src_tree'))} "
            f"{shlex.quote(os.path.join(ws_frec, 'src_tree', 'deep', 'pkg'))} {shlex.quote(home_low)}\n"
            "    exit 0\n"
            "fi\n"
            "exit 1\n"
        )
    os.chmod(zox_all_bin, 0o755)

    # Load bin/ide Python module in-process to spy on negative stat/isdir calls for ws_deleted while verifying ordering
    m_py = re.search(r"IDE_PY_SRC <<\s*'PY'[^\n]*\n(.*?)\nPY\n", ide_full_src, re.S)
    assert m_py, "failed to extract IDE_PY_SRC from bin/ide"
    ide_ns = {"__name__": "ide_launcher_test"}
    exec(compile(m_py.group(1), real_ide_path, "exec"), ide_ns)
    orig_isdir = os.path.isdir
    dead_stat_hits = []

    def _spy_isdir(path_arg):
        if str(path_arg).startswith(ws_deleted):
            dead_stat_hits.append(str(path_arg))
        return orig_isdir(path_arg)

    saved_env_snap = dict(os.environ)
    try:
        os.environ.update({
            **base_env,
            "IDE_LINK_RULES": ext_rules_path,
            "IDE_WORKSPACE_DIRS": f"{ws_env_only}:{os.path.join(env_parent, 'missing-env-ws')}",
            "IDE_ZOXIDE_BIN": zox_all_bin,
        })
        os.path.isdir = _spy_isdir
        collected = ide_ns["_collect_launcher_dirs"]()
    finally:
        os.path.isdir = orig_isdir
        os.environ.clear()
        os.environ.update(saved_env_snap)

    assert dead_stat_hits == [], f"_collect_launcher_dirs performed negative stat/isdir on deleted managed child: {dead_stat_hits}"
    assert collected[:3] == [home_top, ws_frec, home_low], (
        f"expected deep subpath under ws_frec to collapse at true zoxide frecency rank 2 between local-top and local-low, got {collected[:5]}"
    )
    assert ws_unvis in collected and ws_env_only in collected and home_unvis in collected, f"missing unvisited roots/home dir: {collected}"
    assert not any(ws_deleted in c for c in collected) and home_hidden not in collected, f"dead or hidden dir leaked: {collected}"
    assert collected.index(home_low) < collected.index(ws_unvis) < collected.index(home_unvis), f"unexpected tail ordering: {collected}"

    # Verify fallback to `zoxide query -l` when `zoxide query -l --all` exits non-zero
    zox_noall_bin = os.path.join(root, "zox-noall.sh")
    with open(zox_noall_bin, "w", encoding="utf-8") as znb:
        znb.write(
            "#!/bin/sh\n"
            'if [ "$1" = "query" ] && [ "$2" = "-l" ] && [ "${3:-}" = "--all" ]; then exit 2; fi\n'
            f'if [ "$1" = "query" ] && [ "$2" = "-l" ]; then printf "%s\\n" {shlex.quote(home_low)}; exit 0; fi\n'
            "exit 1\n"
        )
    os.chmod(zox_noall_bin, 0o755)
    try:
        os.environ.update({**base_env, "IDE_LINK_RULES": ext_rules_path, "IDE_ZOXIDE_BIN": zox_noall_bin})
        os.environ.pop("IDE_WORKSPACE_DIRS", None)
        collected_fb = ide_ns["_collect_launcher_dirs"]()
    finally:
        os.environ.clear()
        os.environ.update(saved_env_snap)
    assert collected_fb and collected_fb[0] == home_low, f"zoxide --all fallback failed: {collected_fb}"

    # Verify `ide dir` / `ide new` error paths (missing fzf / non-interactive terminal)
    r_dir_nofzf = run_cmd([ide_bin, "dir"], env={**base_env, "IDE_STRICT_PATH": "1", "PATH": no_fzf_dir, "TMUX": "", "TMUX_PANE": ""}, check=False)
    assert r_dir_nofzf.returncode != 0 and "fzf" in r_dir_nofzf.stderr, f"expected missing-fzf error on ide dir: {r_dir_nofzf}"
    r_dir_nontty = run_cmd([ide_bin, "dir"], env={**base_env, "TMUX": "", "TMUX_PANE": ""}, check=False)
    assert r_dir_nontty.returncode != 0 and "interactive terminal" in r_dir_nontty.stderr, f"expected non-TTY error on ide dir: {r_dir_nontty}"
    r_new_nontty = run_cmd([ide_bin, "new"], env={**base_env, "TMUX": "", "TMUX_PANE": ""}, check=False)
    assert r_new_nontty.returncode != 0 and "interactive terminal" in r_new_nontty.stderr, f"expected non-TTY error on ide new without NAME: {r_new_nontty}"

    # Verify `ide -o --2pane <query>` inside tmux launches via real display-popup, forwards --query, resolves ws_unvis -> ws_unvis/src_tree via ide_resolve_workspace,
    # names session `ws-unvisited` via ide_session_name, and switches client_name!
    stub_agy2 = os.path.join(bin_dir, "agy")
    with open(stub_agy2, "w", encoding="utf-8") as sa2:
        sa2.write("#!/bin/sh\nexec sleep 300\n")
    os.chmod(stub_agy2, 0o755)
    new_pop_fzf = os.path.join(root, "new-pop-fzf.py")
    new_pop_args_log = os.path.join(root, "new_pop_args.log")
    with open(new_pop_fzf, "w", encoding="utf-8") as npf:
        npf.write(
            "#!/usr/bin/env python3\n"
            "import sys\n"
            f"with open({new_pop_args_log!r}, 'w', encoding='utf-8') as f:\n"
            "    f.write(' '.join(sys.argv[1:]))\n"
            "lines = [l.rstrip('\\n') for l in sys.stdin if l.strip()]\n"
            "picked = next(l for l in lines if 'ws-unvisited' in l)\n"
            "print(picked)\n"
        )
    os.chmod(new_pop_fzf, 0o755)
    stub_claude2 = os.path.join(bin_dir, "claude")
    with open(stub_claude2, "w", encoding="utf-8") as sc2:
        sc2.write("#!/bin/sh\nexec sleep 300\n")
    os.chmod(stub_claude2, 0o755)
    ws_space_glob = os.path.join(env_parent, "ws [space] dir")
    os.makedirs(ws_space_glob, exist_ok=True)
    tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
    _read_pty_chunk(0.1)
    run_cmd(
        [ide_bin, "-o", "--2pane", "ws-un"],
        env={
            **sess_env("gamma-ws", ws_gamma["ed"]),
            "IDE_AI_CLI": "claude",
            "IDE_CLIENT": client_name,
            "IDE_FZF_BIN": new_pop_fzf,
            "IDE_ZOXIDE_BIN": zox_all_bin,
            "IDE_LINK_RULES": ext_rules_path,
            "IDE_WORKSPACE_DIRS": ws_space_glob,
        },
        check=True,
    )
    _read_pty_chunk(0.2)
    assert os.path.isfile(new_pop_args_log), "ide -o inside tmux did not open display-popup running IDE_FZF_BIN"
    pop_fzf_args = open(new_pop_args_log, encoding="utf-8").read()
    assert "--prompt=New IDE > " in pop_fzf_args and "Esc: cancel" in pop_fzf_args and "--query=ws-un" in pop_fzf_args, f"bad ide -o popup fzf args: {pop_fzf_args}"
    assert tmux("has-session", "-t", "=ws-unvisited", check=False).returncode == 0, "ide -n did not create ws-unvisited session"
    assert tmux_out("show-options", "-qv", "-t", "=ws-unvisited:", "@ide_workdir") == os.path.realpath(os.path.join(ws_unvis, "src_tree")), (
        "ide -n did not apply ide_resolve_workspace to chosen workspace root"
    )
    assert tmux_out("show-options", "-qv", "-t", "=ws-unvisited:", "@ide_layout_mode") == "2pane", "ide -n --2pane did not propagate 2pane layout across popup"
    assert tmux_out("show-options", "-qv", "-t", "=ws-unvisited:", "@ide_ai_cli") == "claude", "ide -n did not propagate caller IDE_AI_CLI across popup"
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "ws-unvisited", "ide -n did not switch client to ws-unvisited"
    tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
    run_cmd([ide_bin, "quit", "--force", "ws-unvisited"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)

    # Verify _pick_workspace_directory preserves spaces and glob metacharacters (`[`, `]`)
    space_pick_fzf = os.path.join(root, "space-pick-fzf.py")
    with open(space_pick_fzf, "w", encoding="utf-8") as spf:
        spf.write(
            "#!/usr/bin/env python3\n"
            "import sys\n"
            "lines = [l.rstrip('\\n') for l in sys.stdin if l.strip()]\n"
            "picked = next(l for l in lines if 'ws [space] dir' in l)\n"
            "print(picked)\n"
        )
    os.chmod(space_pick_fzf, 0o755)
    try:
        os.environ.update({**base_env, "IDE_WORKSPACE_DIRS": ws_space_glob, "IDE_ZOXIDE_BIN": empty_zoxide, "IDE_LINK_RULES": os.path.join(root, "no_rules.sh")})
        picked_sp = ide_ns["_pick_workspace_directory"](space_pick_fzf, dict(os.environ), back_to_sessions=False)
    finally:
        os.environ.clear()
        os.environ.update(saved_env_snap)
    assert picked_sp == os.path.abspath(ws_space_glob), f"_pick_workspace_directory corrupted space/bracket path: {picked_sp!r}"

    # Verify _call_ide_hook 1.0s timeout resilience when a user hook hangs
    slow_rules = os.path.join(root, "slow_rules.sh")
    with open(slow_rules, "w", encoding="utf-8") as srf:
        srf.write("ide_workspace_dirs() { sleep 5; }\n")
    t0_hook = time.monotonic()
    r_slow = run_cmd(
        [ide_bin, "-o", "--detach"],
        env={**base_env, "TMUX": "", "TMUX_PANE": "", "IDE_FZF_BIN": zero_esc_fzf, "IDE_ZOXIDE_BIN": empty_zoxide, "IDE_LINK_RULES": slow_rules},
        check=True,
    )
    dt_hook = time.monotonic() - t0_hook
    assert r_slow.returncode == 0 and dt_hook < 3.0, f"hanging ide_workspace_dirs hook was not bounded by 1.0s timeout: dt={dt_hook:.2f}s"

    # End-to-end @ide_socket self-healing & strict Editor-pane isolation (nvim_rpc.py + ide.lua)
    if shutil.which("nvim"):
        import socket as _hsock

        from ide_lib.tmux import discover_pane_nvim_sockets, pane_tree_pids

        ws_heal = make_ws("heal-ws", ai_cmd="exec /bin/sh", ed_cmd="exec /bin/sh")
        heal_sock = os.path.join(xdg_run, "nvim-ide-heal-ws.sock")
        heal_dot_dir = os.path.join(ws_heal["dir"], "dotfiles")
        heal_sub_dir = os.path.join(ws_heal["dir"], "subdir")
        os.makedirs(heal_dot_dir, exist_ok=True)
        os.makedirs(heal_sub_dir, exist_ok=True)
        heal_tmux_conf = os.path.join(heal_dot_dir, ".tmux.conf")
        with open(heal_tmux_conf, "w", encoding="utf-8") as htf:
            htf.write("".join(f"# line {ln}\n" for ln in range(1, 45)))

        # 1. Headless nvim in Editor pane + interactive nvim in Shell & AI panes must NEVER bind @ide_socket
        headless_ed = subprocess.Popen(
            ["nvim", "--clean", "--headless"],
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env={**base_env, "NVIM_IDE_SOCKET": heal_sock},
        )
        tmux("send-keys", "-t", ws_heal["ed"], f" nvim --clean --headless </dev/zero >/dev/null 2>&1 &", "C-m", check=True)
        tmux("send-keys", "-t", ws_heal["tm"], " nvim --clean", "C-m", check=True)
        tmux("send-keys", "-t", ws_heal["ai"], " nvim --clean", "C-m", check=True)
        tm_pid = tmux_out("display-message", "-p", "-t", ws_heal["tm"], "#{pane_pid}")
        ai_pid_h = tmux_out("display-message", "-p", "-t", ws_heal["ai"], "#{pane_pid}")
        ed_pid_h = tmux_out("display-message", "-p", "-t", ws_heal["ed"], "#{pane_pid}")
        assert wait_until(lambda: bool(discover_pane_nvim_sockets(tm_pid, sock_hint=heal_sock)), timeout=4.0), "Shell nvim socket did not appear"
        assert wait_until(lambda: bool(discover_pane_nvim_sockets(ai_pid_h, sock_hint=heal_sock)), timeout=4.0), "AI nvim socket did not appear"
        assert wait_until(lambda: bool(discover_pane_nvim_sockets(ed_pid_h, sock_hint=heal_sock)), timeout=4.0), "Editor headless nvim socket did not appear"
        r_no_steal = run_cmd([ide_bin, "_internal", "heal-socket", "heal-ws"], env={**base_env, "TMUX": ""}, check=False)
        assert r_no_steal.returncode != 0 and not os.path.exists(heal_sock), (
            f"_internal heal-socket must refuse headless Editor nvim and Shell/AI nvim: rc={r_no_steal.returncode}"
        )
        headless_ed.terminate()
        headless_ed.wait(timeout=2)
        tmux("respawn-pane", "-k", "-t", ws_heal["ed"], "-c", ws_heal["dir"], "exec /bin/sh", check=True)

        # 2. Interactive `nvim --clean` in Editor pane WITHOUT --listen + dead stale @ide_socket on disk:
        #    `ide _internal open-link` heals @ide_socket via serverstart() and opens dotfiles/.tmux.conf:37 in Editor (never Shell/AI)
        dead_s = _hsock.socket(_hsock.AF_UNIX, _hsock.SOCK_STREAM)
        dead_s.bind(heal_sock)
        dead_s.close()
        ed_pid_clean = tmux_out("display-message", "-p", "-t", ws_heal["ed"], "#{pane_pid}")
        tmux("send-keys", "-t", ws_heal["ed"], " env -u NVIM_IDE_PANE nvim --clean", "C-m", check=True)
        ed_ephem_socks = wait_until(
            lambda: (
                s
                if (s := discover_pane_nvim_sockets(ed_pid_clean, sock_hint=heal_sock))
                and nvim_expr_eq(s[0], "string(len(nvim_list_uis()))", "1")
                else []
            ),
            timeout=5.0,
        )
        assert ed_ephem_socks, "Editor interactive nvim --clean ephemeral socket did not appear"
        ed_ephem = ed_ephem_socks[0]

        run_cmd(
            [ide_bin, "_internal", "open-link", "", "dotfiles/.tmux.conf:37", ws_heal["dir"], "heal-ws"],
            env={**base_env, "TMUX": ""},
            check=True,
        )
        assert wait_until(
            lambda: nvim_expr_eq(
                heal_sock,
                "fnamemodify(bufname('%'), ':p') . ':' . line('.') . '|' . $IDE_SESSION",
                f"{os.path.realpath(heal_tmux_conf)}:37|heal-ws",
            ),
            timeout=3.0,
        ), "ide _internal open-link failed to self-heal missing/stale @ide_socket and open dotfiles/.tmux.conf:37"
        tm_ephem = discover_pane_nvim_sockets(tm_pid, sock_hint=heal_sock)[0]
        assert nvim_expr_eq(tm_ephem, "bufname('%')", ""), "Shell pane nvim must remain untouched by ide _internal open-link"

        # 3. Unsaved-buffer guard in `ide quit`, workspace dive `ide cd`, and `ide refresh` all self-heal missing @ide_socket
        os.unlink(heal_sock)
        subprocess.run(
            ["nvim", "--headless", "--server", ed_ephem, "--remote-expr", "setline(1, 'unsaved-mod')"],
            env=base_env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
            check=True,
        )
        r_quit_guard = run_cmd([ide_bin, "quit", "heal-ws"], env={**base_env, "TMUX": ""}, check=False)
        assert r_quit_guard.returncode != 0 and os.path.exists(heal_sock), (
            f"ide quit failed to heal missing @ide_socket and guard unsaved buffer: rc={r_quit_guard.returncode}"
        )
        assert "Unsaved changes" in tmux_out("show-options", "-qv", "-t", "=heal-ws:", "@ide_quit_err")
        # Unlinking @ide_socket while Editor is still running must NOT cause _internal sessions-lines to wipe @ide_quit_err
        os.unlink(heal_sock)
        run_cmd([ide_bin, "_internal", "sessions-lines", "heal-ws"], env={**base_env, "TMUX": ""}, check=True)
        assert "Unsaved changes" in tmux_out("show-options", "-qv", "-t", "=heal-ws:", "@ide_quit_err"), (
            "classify_ide_fleet wiped @ide_quit_err while Editor nvim was still running with unsaved changes"
        )
        r_prev_unsaved = run_cmd([ide_bin, "_internal", "session-preview", "heal-ws"], env={**base_env, "TMUX": ""}, check=True)
        assert os.path.exists(heal_sock) and "Unsaved changes" in r_prev_unsaved.stdout, (
            "render_session_preview failed to heal @ide_socket and preserve unsaved warning"
        )
        subprocess.run(
            ["nvim", "--headless", "--server", ed_ephem, "--remote-expr", "execute('edit!')"],
            env=base_env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
            check=True,
        )
        os.unlink(heal_sock)
        run_cmd([ide_bin, "_internal", "session-preview", "heal-ws"], env={**base_env, "TMUX": ""}, check=True)
        assert tmux_out("show-options", "-qv", "-t", "=heal-ws:", "@ide_quit_err") == "", (
            "render_session_preview failed to heal @ide_socket and clear @ide_quit_err once buffer was clean"
        )

        os.unlink(heal_sock)
        run_cmd([ide_bin, "cd", heal_sub_dir, "heal-ws"], env={**base_env, "TMUX": ""}, check=True)
        assert nvim_expr_eq(heal_sock, "getcwd()", os.path.realpath(heal_sub_dir)), (
            "ide cd failed to heal missing @ide_socket and cd Editor"
        )

        os.unlink(heal_sock)
        r_ref_heal = run_cmd([ide_bin, "refresh", "heal-ws"], env={**base_env, "TMUX": ""}, check=True)
        assert os.path.exists(heal_sock) and "(1 editor(s))" in r_ref_heal.stdout, (
            f"ide refresh failed to heal missing @ide_socket: {r_ref_heal.stdout!r}"
        )

        # 4. Neovim `solarized/ide.lua` (`SolarizedIdeSocket`) startup self-binding in Editor vs Shell/split/nested guards
        init_lua_path = os.path.join(repo_dir, "dotfiles", ".config", "nvim", "init.lua")
        lock_json_path = os.path.join(repo_dir, "dotfiles", ".config", "nvim", "lazy-lock.json")
        with open(lock_json_path, "r", encoding="utf-8") as _lf:
            _lock_plugins = list(json.load(_lf).keys())

        def _has_valid_plugin_dir(pdir):
            git_p = os.path.join(pdir, ".git")
            if os.path.isdir(git_p):
                return os.path.isfile(os.path.join(git_p, "HEAD"))
            return os.path.isfile(git_p)

        orig_lazy_root = os.path.join(orig_xdg_data, "nvim", "lazy")
        has_bootstrapped_lazy = (
            bool(_lock_plugins)
            and os.path.isfile(os.path.join(orig_lazy_root, "lazy.nvim", "lua", "lazy", "init.lua"))
            and all(_has_valid_plugin_dir(os.path.join(orig_lazy_root, pname)) for pname in _lock_plugins)
        )
        # Isolate XDG_DATA_HOME per suite so interactive Neovim never mutates caller's ~/.local/share/nvim/mason
        # or triggers live Mason registry/package downloads (`clangd`, `gopls`, etc.) on CI runners.
        nvim_xdg_data = os.path.join(root, "nvim_data")
        iso_nvim_dir = os.path.join(nvim_xdg_data, "nvim")
        os.makedirs(iso_nvim_dir, mode=0o700, exist_ok=True)
        if has_bootstrapped_lazy:
            for _sub in ("lazy", "site"):
                _src_sub = os.path.join(orig_xdg_data, "nvim", _sub)
                if os.path.exists(_src_sub):
                    os.symlink(_src_sub, os.path.join(iso_nvim_dir, _sub))
        else:
            os.makedirs(os.path.join(iso_nvim_dir, "lazy", "lazy.nvim"), exist_ok=True)

        os.makedirs(os.path.join(iso_nvim_dir, "mason", "bin"), exist_ok=True)
        _reg_dir = os.path.join(iso_nvim_dir, "mason", "registries", "github", "mason-org", "mason-registry")
        os.makedirs(_reg_dir, exist_ok=True)
        _now_ts = int(time.time())
        _mason_pairs = (
            ("clangd", "clangd"),
            ("rust-analyzer", "rust_analyzer"),
            ("gopls", "gopls"),
            ("lua-language-server", "lua_ls"),
            ("terraform-ls", "terraformls"),
            ("jdtls", "jdtls"),
        )
        with open(os.path.join(_reg_dir, "registry.json"), "w", encoding="utf-8") as _rjf:
            json.dump(
                [
                    {
                        "name": _pkg,
                        "description": _pkg,
                        "homepage": "https://example.invalid",
                        "licenses": ["MIT"],
                        "languages": [],
                        "categories": ["LSP"],
                        "source": {"id": f"pkg:generic/{_pkg}@1.0.0"},
                        "neovim": {"lspconfig": _lsp},
                    }
                    for _pkg, _lsp in _mason_pairs
                ],
                _rjf,
            )
        with open(os.path.join(_reg_dir, "info.json"), "w", encoding="utf-8") as _ijf:
            json.dump({"checksums": {}, "download_timestamp": _now_ts, "version": "hermetic"}, _ijf)
        for _pkg, _ in _mason_pairs:
            os.makedirs(os.path.join(iso_nvim_dir, "mason", "packages", _pkg), exist_ok=True)
        _reg_hash = hashlib.sha256(b"mason-org/mason-registry").hexdigest()

        _mise_data_dir = os.environ.get("MISE_DATA_DIR") or os.path.join(orig_xdg_data, "mise")
        _mise_cache_dir = os.environ.get("MISE_CACHE_DIR") or os.path.join(orig_xdg_cache, "mise")
        _mise_state_dir = os.environ.get("MISE_STATE_DIR") or os.path.join(orig_xdg_state, "mise")

        def _prep_nvim_instance_dirs(tag):
            st_dir = os.path.join(root, f"nvim_state_{tag}")
            ca_dir = os.path.join(root, f"nvim_cache_{tag}")
            os.makedirs(st_dir, mode=0o700, exist_ok=True)
            os.makedirs(os.path.join(ca_dir, "nvim"), mode=0o700, exist_ok=True)
            with open(os.path.join(ca_dir, "nvim", "mason-registry-update"), "w", encoding="utf-8") as _rfh:
                _rfh.write(f"{_reg_hash}\n{_now_ts}")
            return st_dir, ca_dir

        def _nvim_hermetic_overrides(st_dir, ca_dir):
            return {
                "XDG_DATA_HOME": nvim_xdg_data,
                "XDG_STATE_HOME": st_dir,
                "XDG_CACHE_HOME": ca_dir,
                "MISE_DATA_DIR": _mise_data_dir,
                "MISE_CACHE_DIR": _mise_cache_dir,
                "MISE_STATE_DIR": _mise_state_dir,
                "NVIM_LOG_FILE": "/dev/null",
                "NVIM_TS_SKIP_AUTO_INSTALL": "1",
                "GIT_TERMINAL_PROMPT": "0",
                "HTTPS_PROXY": "http://127.0.0.1:1",
                "https_proxy": "http://127.0.0.1:1",
                "HTTP_PROXY": "http://127.0.0.1:1",
                "http_proxy": "http://127.0.0.1:1",
            }

        def _nvim_init_env_dict(tag, base_dict=None, extra=None):
            st_dir, ca_dir = _prep_nvim_instance_dirs(tag)
            out_env = dict(base_env if base_dict is None else base_dict)
            out_env.update(_nvim_hermetic_overrides(st_dir, ca_dir))
            if extra:
                out_env.update(extra)
            return out_env

        def _write_nvim_launcher(tag, extra_args=(), extra_env=None, unset_vars=()):
            st_dir, ca_dir = _prep_nvim_instance_dirs(tag)
            # Place launcher inside short `tmux_tmp` so `tmux send-keys` never hits `/bin/sh` 255-byte MAX_CANON
            script_p = os.path.join(tmux_tmp, f"nvim_launch_{tag}.sh")
            lines = ["#!/bin/sh"]
            for uvar in unset_vars:
                lines.append(f"unset {uvar}")
            kv = _nvim_hermetic_overrides(st_dir, ca_dir)
            if extra_env:
                kv.update(extra_env)
            for k, v in kv.items():
                lines.append(f"export {k}={shlex.quote(v)}")
            arg_str = " ".join(shlex.quote(a) for a in extra_args)
            lines.append(f"exec nvim -i NONE -u {shlex.quote(init_lua_path)} {arg_str} \"$@\"")
            with open(script_p, "w", encoding="utf-8") as sf:
                sf.write("\n".join(lines) + "\n")
            os.chmod(script_p, 0o755)
            return script_p

        def _safe_unlink(sock_p: str) -> None:
            try:
                os.unlink(sock_p)
            except FileNotFoundError:
                pass

        def _bind_dead_unix_sock(sock_p: str) -> None:
            for _ in range(20):
                _safe_unlink(sock_p)
                s = _hsock.socket(_hsock.AF_UNIX, _hsock.SOCK_STREAM)
                try:
                    s.bind(sock_p)
                    return
                except OSError:
                    time.sleep(0.02)
                finally:
                    s.close()
            _safe_unlink(sock_p)
            s = _hsock.socket(_hsock.AF_UNIX, _hsock.SOCK_STREAM)
            try:
                s.bind(sock_p)
            finally:
                s.close()

        tmux("respawn-pane", "-k", "-t", ws_heal["ed"], "-c", ws_heal["dir"], "exec /bin/sh", check=True)
        tmux("respawn-pane", "-k", "-t", ws_heal["tm"], "-c", ws_heal["dir"], "exec /bin/sh", check=True)
        tmux("respawn-pane", "-k", "-t", ws_heal["ai"], "-c", ws_heal["dir"], "exec /bin/sh", check=True)
        _safe_unlink(heal_sock)

        adhoc_pane = tmux_out("split-window", "-h", "-P", "-F", "#{pane_id}", "-t", ws_heal["tm"], "-c", ws_heal["dir"], "exec /bin/sh")
        tm_launcher = _write_nvim_launcher("tm", extra_env={"NVIM_IDE_SOCKET": heal_sock})
        adhoc_launcher = _write_nvim_launcher("adhoc", extra_env={"NVIM_IDE_SOCKET": heal_sock})
        tmux("send-keys", "-t", ws_heal["tm"], f" {shlex.quote(tm_launcher)}", "C-m", check=True)
        tmux("send-keys", "-t", adhoc_pane, f" {shlex.quote(adhoc_launcher)}", "C-m", check=True)
        tm_pid2 = tmux_out("display-message", "-p", "-t", ws_heal["tm"], "#{pane_pid}")
        adhoc_pid = tmux_out("display-message", "-p", "-t", adhoc_pane, "#{pane_pid}")
        tm_socks2 = wait_until(lambda: discover_pane_nvim_sockets(tm_pid2, sock_hint=heal_sock), timeout=8.0)
        adhoc_socks2 = wait_until(lambda: discover_pane_nvim_sockets(adhoc_pid, sock_hint=heal_sock), timeout=8.0)
        assert tm_socks2, "Shell init.lua nvim did not boot"
        assert adhoc_socks2, "Adhoc init.lua nvim did not boot"
        assert wait_until(
            lambda: nvim_expr_eq(tm_socks2[0], "luaeval(\"require('solarized.ide')._socket_probe_state\")", "skipped_non_editor"),
            timeout=8.0,
        ), "Shell init.lua nvim did not finish SolarizedIdeSocket non-editor guard"
        assert wait_until(
            lambda: nvim_expr_eq(adhoc_socks2[0], "luaeval(\"require('solarized.ide')._socket_probe_state\")", "skipped_non_editor"),
            timeout=8.0,
        ), "Adhoc init.lua nvim did not finish SolarizedIdeSocket non-editor guard"
        assert not os.path.exists(heal_sock), "Shell or ad-hoc split nvim with init.lua must NEVER claim @ide_socket"

        # Plant dead stale socket, then boot interactive `nvim -u init.lua` WITHOUT --listen inside Editor pane
        dead_s2 = _hsock.socket(_hsock.AF_UNIX, _hsock.SOCK_STREAM)
        dead_s2.bind(heal_sock)
        dead_s2.close()
        ed_launcher = _write_nvim_launcher("ed", unset_vars=("NVIM_IDE_PANE",))
        tmux("send-keys", "-t", ws_heal["ed"], f" {shlex.quote(ed_launcher)}", "C-m", check=True)
        assert wait_until(
            lambda: nvim_expr_eq(
                heal_sock,
                "$IDE_SESSION . '|' . luaeval(\"require('solarized.ide')._socket_probe_state\")",
                "heal-ws|bound",
            ),
            timeout=8.0,
        ), "Editor nvim -u init.lua failed to self-bind @ide_socket over stale socket on VimEnter"
        ed_srv_pid = subprocess.check_output(
            ["nvim", "--headless", "--server", heal_sock, "--remote-expr", "string(getpid())"],
            env=base_env,
            stdin=subprocess.DEVNULL,
            text=True,
            timeout=3,
        ).strip()

        # Launching and exiting a second nvim with TMUX_PANE=ed_pane (e.g. Ctrl+Z or :!git commit) must NOT steal or unlink live @ide_socket
        sub_state_file = os.path.join(root, "sub_probe_state.txt")
        sub_lua = (
            f"lua local ide = require('solarized.ide'); local n = 0; "
            f"local function poll() n = n + 1; local st = ide._socket_probe_state; "
            f"if (st ~= 'idle' and st ~= 'running') or n > 200 then "
            f"local f = io.open({sub_state_file!r}, 'w'); if f then f:write(tostring(st)); f:close() end; "
            f"vim.cmd('qall!') else vim.defer_fn(poll, 25) end end; vim.defer_fn(poll, 20)"
        )
        rc_sub, out_sub = _run_pty_cmd(
            ["nvim", "-i", "NONE", "-u", init_lua_path, "-c", sub_lua],
            _nvim_init_env_dict(
                "sub",
                base_dict=sess_env("heal-ws", ws_heal["ed"]),
                extra={"NVIM_IDE_SOCKET": heal_sock},
            ),
            timeout_s=10.0,
        )
        assert rc_sub == 0, f"Secondary nvim inside Editor pane exited non-zero: rc={rc_sub} out={out_sub[-400:]!r}"
        sub_probe_st = open(sub_state_file, encoding="utf-8").read().strip() if os.path.isfile(sub_state_file) else ""
        assert sub_probe_st == "live_peer", f"Expected secondary nvim SolarizedIdeSocket state 'live_peer', got {sub_probe_st!r}"
        assert nvim_expr_eq(heal_sock, "string(getpid())", ed_srv_pid), (
            "Secondary nvim inside Editor pane stole or unlinked live @ide_socket"
        )

        # 5. Nested `:!nvim` (e.g. `:!git commit`, where $NVIM is unset) inside `nvim --clean` must NEVER claim @ide_socket
        tmux("respawn-pane", "-k", "-t", ws_heal["ed"], "-c", ws_heal["dir"], "exec /bin/sh", check=True)
        _safe_unlink(heal_sock)
        ed_pid_bang = tmux_out("display-message", "-p", "-t", ws_heal["ed"], "#{pane_pid}")
        tmux(
            "send-keys",
            "-t",
            ws_heal["ed"],
            " env -u NVIM_IDE_PANE nvim --clean -c 'let g:is_outer_ed = 77'",
            "C-m",
            check=True,
        )
        outer_bang_socks = wait_until(
            lambda: (
                s
                if (s := discover_pane_nvim_sockets(ed_pid_bang, sock_hint=heal_sock))
                and nvim_expr_eq(s[0], "string(get(g:, 'is_outer_ed', 0))", "77")
                else []
            ),
            timeout=5.0,
        )
        assert outer_bang_socks, "Outer nvim --clean socket did not appear"
        bang_marker = os.path.join(ws_heal["dir"], ".bang_inner_ready")
        bang_release = os.path.join(ws_heal["dir"], ".bang_inner_release")
        bang_done = os.path.join(ws_heal["dir"], ".bang_inner_done")
        bang_lua = (
            f'lua vim.api.nvim_create_autocmd("VimLeavePre", {{ once = true, callback = function() '
            f'io.open({bang_done!r}, "w"):close() end }}); '
            f'local ide = require("solarized.ide"); local uv = vim.uv or vim.loop; local n = 0; '
            f'local function wait_rel(m) if (uv and uv.fs_stat({bang_release!r})) or m > 160 then vim.cmd("qall!") '
            f'else vim.defer_fn(function() wait_rel(m + 1) end, 25) end end; '
            f'local function wait_probe() n = n + 1; local st = ide._socket_probe_state; '
            f'if (st ~= "idle" and st ~= "running") or n > 200 then '
            f'local f = io.open({bang_marker!r}, "w"); if f then f:write(tostring(st)); f:close() end; '
            f'wait_rel(0) else vim.defer_fn(wait_probe, 25) end end; vim.defer_fn(wait_probe, 20)'
        )
        outer_pid_cnt = len(pane_tree_pids(ed_pid_bang))
        bang_launcher = _write_nvim_launcher("bang", extra_args=("-c", bang_lua))
        tmux("send-keys", "-t", ws_heal["ed"], f":!{shlex.quote(bang_launcher)}", "C-m", check=True)
        assert wait_until(lambda: os.path.exists(bang_marker), timeout=8.0), "Nested :!nvim child did not start"
        try:
            bang_probe_st = open(bang_marker, encoding="utf-8").read().strip()
            assert bang_probe_st in ("skipped_headless", "skipped_ancestry:nested_nvim"), (
                f"Unexpected nested :!nvim SolarizedIdeSocket state: {bang_probe_st!r}"
            )
            assert not os.path.exists(heal_sock), "Nested :!nvim inside Editor pane must NEVER claim @ide_socket"
            assert discover_pane_nvim_sockets(ed_pid_bang, sock_hint=heal_sock) == outer_bang_socks, (
                "discover_pane_nvim_sockets must exclude nested :!nvim children under an outer Editor nvim"
            )
        finally:
            open(bang_release, "w", encoding="utf-8").close()
        assert wait_until(
            lambda: os.path.exists(bang_done) and len(pane_tree_pids(ed_pid_bang)) <= outer_pid_cnt,
            timeout=6.0,
        ), "Nested :!nvim child did not exit cleanly"
        tmux("send-keys", "-t", ws_heal["ed"], "C-m", check=True)

        # Also test PTY-attached nested nvim (`:terminal` with `unset NVIM`) so UI attaches (#nvim_list_uis() > 0) and check_pane_ancestry() runs
        term_marker = os.path.join(ws_heal["dir"], ".term_inner_ready")
        term_release = os.path.join(ws_heal["dir"], ".term_inner_release")
        term_done = os.path.join(ws_heal["dir"], ".term_inner_done")
        term_lua = (
            f'lua vim.api.nvim_create_autocmd("VimLeavePre", {{ once = true, callback = function() '
            f'io.open({term_done!r}, "w"):close() end }}); '
            f'local ide = require("solarized.ide"); local uv = vim.uv or vim.loop; local n = 0; '
            f'local function wait_rel(m) if (uv and uv.fs_stat({term_release!r})) or m > 160 then vim.cmd("qall!") '
            f'else vim.defer_fn(function() wait_rel(m + 1) end, 25) end end; '
            f'local function wait_probe() n = n + 1; local st = ide._socket_probe_state; '
            f'if (st ~= "idle" and st ~= "running") or n > 200 then '
            f'local f = io.open({term_marker!r}, "w"); if f then f:write(tostring(st)); f:close() end; '
            f'wait_rel(0) else vim.defer_fn(wait_probe, 25) end end; vim.defer_fn(wait_probe, 20)'
        )
        term_launcher = _write_nvim_launcher("term_nested", extra_args=("-c", term_lua), unset_vars=("NVIM", "NVIM_LISTEN_ADDRESS"))
        tmux("send-keys", "-t", ws_heal["ed"], f":terminal {shlex.quote(term_launcher)}", "C-m", check=True)
        assert wait_until(lambda: os.path.exists(term_marker), timeout=8.0), "Nested :terminal (unset NVIM) nvim child did not start"
        try:
            term_probe_st = open(term_marker, encoding="utf-8").read().strip()
            assert term_probe_st == "skipped_ancestry:nested_nvim", (
                f"Expected nested PTY nvim SolarizedIdeSocket state 'skipped_ancestry:nested_nvim', got {term_probe_st!r}"
            )
            assert not os.path.exists(heal_sock), "Nested PTY nvim inside Editor pane must NEVER claim @ide_socket"
            assert discover_pane_nvim_sockets(ed_pid_bang, sock_hint=heal_sock) == outer_bang_socks, (
                "discover_pane_nvim_sockets must exclude nested :terminal nvim children under an outer Editor nvim"
            )
        finally:
            open(term_release, "w", encoding="utf-8").close()
        assert wait_until(lambda: os.path.exists(term_done), timeout=6.0), "Nested :terminal nvim child did not exit cleanly"
        subprocess.run(
            ["nvim", "--headless", "--server", outer_bang_socks[0], "--remote-expr", "execute('bd!')"],
            env=base_env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
            check=False,
        )
        assert wait_until(
            lambda: run_cmd([ide_bin, "_internal", "heal-socket", "heal-ws"], env={**base_env, "TMUX": ""}, check=False).returncode == 0,
            timeout=3.0,
        )
        assert nvim_expr_eq(heal_sock, "string(g:is_outer_ed)", "77"), "Outer Editor nvim was not healed after :!nvim"

        # 6. Special characters (spaces + single quotes) in @ide_socket path + Ctrl+Z foreground priority + relaunch wait
        weird_sock_dir = os.path.join(xdg_run, "sp 'dir")
        weird_sock = os.path.join(weird_sock_dir, "nvim-ide-heal-ws.sock")
        tmux("set-option", "-t", "=heal-ws:", "@ide_socket", weird_sock, check=True)
        run_cmd([ide_bin, "_internal", "heal-socket", "heal-ws"], env={**base_env, "TMUX": ""}, check=True)
        assert nvim_expr_eq(weird_sock, "string(g:is_outer_ed)", "77"), (
            f"bind_nvim_server_socket failed on socket path with spaces and quotes: {weird_sock!r}"
        )
        tmux("set-option", "-t", "=heal-ws:", "@ide_socket", heal_sock, check=True)

        if shutil.which("bash"):
            tmux("respawn-pane", "-k", "-t", ws_heal["ed"], "-c", ws_heal["dir"], "exec bash --norc --noprofile -i", check=True)
            _safe_unlink(heal_sock)
            ed_pid_cz = tmux_out("display-message", "-p", "-t", ws_heal["ed"], "#{pane_pid}")
            tmux("send-keys", "-t", ws_heal["ed"], " nvim --clean -c 'let g:cz_ord = 1'", "C-m", check=True)
            assert wait_until(
                lambda: (
                    len(s := discover_pane_nvim_sockets(ed_pid_cz, sock_hint=heal_sock)) == 1
                    and nvim_expr_eq(s[0], "string(get(g:, 'cz_ord', 0))", "1")
                ),
                timeout=4.0,
            )
            tmux("send-keys", "-t", ws_heal["ed"], "C-z", check=True)
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_heal["ed"], "#{pane_current_command}") == "bash",
                timeout=3.0,
            )
            tmux("send-keys", "-t", ws_heal["ed"], " nvim --clean -c 'let g:cz_ord = 2'", "C-m", check=True)
            assert wait_until(
                lambda: (
                    len(s := discover_pane_nvim_sockets(ed_pid_cz, sock_hint=heal_sock)) == 2
                    and nvim_expr_eq(s[0], "string(get(g:, 'cz_ord', 0))", "2")
                ),
                timeout=4.0,
            )
            t0_cz = time.monotonic()
            run_cmd([ide_bin, "_internal", "heal-socket", "heal-ws"], env={**base_env, "TMUX": ""}, check=True)
            dt_cz = time.monotonic() - t0_cz
            assert dt_cz < 1.5 and nvim_expr_eq(heal_sock, "string(g:cz_ord)", "2"), (
                f"_internal heal-socket failed to prioritize foreground nvim over Ctrl+Z background nvim (dt={dt_cz:.2f}s)"
            )

        # Bare-shell relaunch (`open --preview`) and closed-split heal (`_internal open-link` + dead stale socket) must wait for socket & open target line
        tmux("respawn-pane", "-k", "-t", ws_heal["ed"], "-c", ws_heal["dir"], "exec /bin/sh", check=True)
        tmux("set-option", "-t", "=heal-ws:", "@ide_quit_err", "Stale quit warning", check=True)
        _bind_dead_unix_sock(heal_sock)
        run_cmd([ide_bin, "_internal", "sessions-lines", "heal-ws"], env={**base_env, "TMUX": ""}, check=True)
        assert tmux_out("show-options", "-qv", "-t", "=heal-ws:", "@ide_quit_err") == "", (
            "classify_ide_fleet failed to clear @ide_quit_err when Editor exited leaving a dead stale socket"
        )
        run_cmd([ide_bin, "open", "--preview", f"{heal_tmux_conf}:37", "heal-ws"], env={**base_env, "TMUX": ""}, check=True)
        assert wait_until(
            lambda: nvim_expr_eq(heal_sock, "fnamemodify(bufname('%'), ':p') . ':' . line('.')", f"{os.path.realpath(heal_tmux_conf)}:37"),
            timeout=4.0,
        ), "ide open --preview failed to wait for relaunched Editor socket and open target file:line"

        cur_ed_p = tmux_out("show-options", "-qv", "-t", "=heal-ws:", "@ide_editor_pane")
        tmux("kill-pane", "-t", cur_ed_p, check=True)
        _bind_dead_unix_sock(heal_sock)
        run_cmd([ide_bin, "_internal", "open-link", "", "dotfiles/.tmux.conf:41", ws_heal["dir"], "heal-ws"], env={**base_env, "TMUX": ""}, check=True)
        assert wait_until(
            lambda: nvim_expr_eq(heal_sock, "fnamemodify(bufname('%'), ':p') . ':' . line('.')", f"{os.path.realpath(heal_tmux_conf)}:41"),
            timeout=4.0,
        ), "ide _internal open-link after Editor pane close failed to wait for healed Editor socket and open target file:line"

        for _rem_s in (*tm_socks2, *adhoc_socks2):
            if os.path.exists(_rem_s):
                subprocess.run(
                    ["nvim", "--headless", "--server", _rem_s, "--remote-send", "<C-\\><C-n><Cmd>qall!<CR>"],
                    env=base_env,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=2,
                    check=False,
                )
        run_cmd([ide_bin, "quit", "--force", "heal-ws"], env={**base_env, "TMUX": ""}, check=True)

    # 11. Dynamic streaming `_internal session-preview --follow` (deduplicated CSI 2J frames, viewport bottom fitting,
    #     fast-tick peer/state/viewport updates without slow VCS forks, pipe-close POLLHUP self-termination,
    #     session-exit termination, CLI error guards, and live real-`fzf` `Alt+s` popup rendering)
    for bad_prev_args in (
        ["_internal"],
        ["_internal", "session-preview"],
        ["_internal", "session-preview", "--follow"],
        ["_internal", "session-preview", "--follow", "--"],
        ["--follow"],
        ["list", "--follow"],
        ["list", "--plain", "--json"],
    ):
        r_bad_prev = run_cmd([ide_bin, *bad_prev_args], env={**base_env, "TMUX": ""}, check=False)
        assert r_bad_prev.returncode != 0, f"expected non-zero exit for {bad_prev_args}, got {r_bad_prev}"

    for valid_order_args in (
        ["_internal", "session-preview", "--follow", "--", "no-such-dyn-ws"],
        ["_internal", "session-preview", "--", "no-such-dyn-ws"],
    ):
        r_order_prev = run_cmd(
            [ide_bin, *valid_order_args],
            env={**base_env, "TMUX": "", "IDE_PREVIEW_INTERVAL": "0.05"},
            check=True,
        )
        assert "Session is no longer active." in r_order_prev.stdout

    for term_target in ("", "no-such-dyn-ws", "plain-non-ide"):
        t0_term = time.monotonic()
        r_term_prev = run_cmd(
            [ide_bin, "_internal", "session-preview", "--follow", "--", term_target],
            env={**base_env, "TMUX": "", "IDE_PREVIEW_INTERVAL": "0.05"},
            check=True,
        )
        dt_term = time.monotonic() - t0_term
        assert dt_term < 1.5, f"_internal session-preview --follow on {term_target!r} hung ({dt_term:.2f}s)"
        if term_target == "plain-non-ide":
            assert "plain-non-ide" in r_term_prev.stdout
        else:
            assert "Session is no longer active." in r_term_prev.stdout

    ws_dyn = make_ws(
        "dyn-ws",
        ai_cmd="exec /bin/sh",
        ed_cmd="exec sleep 300",
        ai_cli="claude",
        git_branch="feat/dyn-preview",
        git_dirty=False,
        in_home=True,
    )
    ws_dyn_peer = make_ws("dyn-peer-ws", ai_cmd="exec sleep 300", ai_cli="codex")
    tmux("set-option", "-q", "-t", "=dyn-peer-ws:", "@ide_workdir", ws_dyn["dir"], check=True)
    tmux(
        "respawn-pane",
        "-k",
        "-t",
        ws_dyn["ai"],
        "-c",
        ws_dyn["dir"],
        "/bin/sh -c 'i=1; while [ $i -le 45 ]; do printf \"SCROLL_ROW_%02d\\n\" \"$i\"; i=$((i+1)); done; printf \"DYN_BOTTOM_STAGE_1\\n\"; sleep 300'",
        check=True,
    )
    assert wait_until(
        lambda: "DYN_BOTTOM_STAGE_1" in tmux_out("capture-pane", "-p", "-t", ws_dyn["ai"]),
        timeout=3.0,
    ), "dyn-ws initial 46-line viewport did not render"

    # Verify FZF_PREVIEW_LINES + FZF_PREVIEW_COLUMNS pins header AND preserves bottommost live output line
    r_fitted_prev = run_cmd(
        [ide_bin, "_internal", "session-preview", "dyn-ws"],
        env={
            **sess_env("dyn-ws", ws_dyn["ed"]),
            "NO_COLOR": "",
            "FZF_PREVIEW_COLUMNS": "48",
            "FZF_PREVIEW_LINES": "16",
        },
        check=True,
    )
    fitted_clean_lines = [_ansi_strip_re.sub("", ln) for ln in r_fitted_prev.stdout.splitlines()]
    assert any("dyn-ws" in ln for ln in fitted_clean_lines), f"missing header in fitted preview: {fitted_clean_lines}"
    assert any("DYN_BOTTOM_STAGE_1" in ln for ln in fitted_clean_lines), (
        f"fitted preview clipped live bottom line! lines={fitted_clean_lines}"
    )
    assert "SCROLL_ROW_01" not in "\n".join(fitted_clean_lines), (
        f"fitted preview did not trim top scrollback to FZF_PREVIEW_LINES=16: {fitted_clean_lines}"
    )
    assert len(fitted_clean_lines) <= 16, f"fitted preview exceeded FZF_PREVIEW_LINES=16: len={len(fitted_clean_lines)}"

    # Verify streaming _internal session-preview --follow over OS pipe:
    # 1) Immediate initial frame without \x1b[2J
    # 2) Zero duplicate emissions across idle ticks
    # 3) Fast-tick updates for viewport text, state + @ide_ai_msg, and shared-worktree WORKING peer warning
    #    while throttling VCS hook calls
    # 4) Sub-250ms clean exit (rc=0, empty stderr) when pipe reader closes
    dyn_vcs_log = os.path.join(root, "dyn_vcs_hits.log")
    dyn_rules = os.path.join(root, "dyn_vcs_rules.sh")
    with open(dyn_rules, "w", encoding="utf-8") as drf:
        drf.write(
            f'ide_vcs_summary() {{ printf "1\\n" >> {shlex.quote(dyn_vcs_log)}; echo "feat/dyn-preview|0|feat/dyn-preview (clean)|"; }}\n'
        )

    p_rfd, p_wfd = os.pipe()
    os.set_blocking(p_rfd, False)
    follow_env = {
        **sess_env("dyn-ws", ws_dyn["ed"]),
        "NO_COLOR": "",
        "IDE_PREVIEW_INTERVAL": "0.06",
        "IDE_LINK_RULES": dyn_rules,
        "FZF_PREVIEW_COLUMNS": "64",
        "FZF_PREVIEW_LINES": "22",
    }
    follow_proc = subprocess.Popen(
        [ide_bin, "_internal", "session-preview", "--follow", "--", "dyn-ws"],
        stdin=subprocess.DEVNULL,
        stdout=p_wfd,
        stderr=subprocess.PIPE,
        env=follow_env,
        close_fds=True,
    )
    os.close(p_wfd)

    def _drain_follow_pipe(wait_s=0.0):
        if wait_s > 0:
            select.select([p_rfd], [], [], wait_s)
        chunks = []
        while True:
            rdy, _, _ = select.select([p_rfd], [], [], 0)
            if not rdy:
                break
            try:
                data = os.read(p_rfd, 65536)
                if not data:
                    break
                chunks.append(data)
            except BlockingIOError:
                break
            except OSError:
                break
        return b"".join(chunks).decode("utf-8", "replace")

    try:
        acc_f1 = ""
        deadline_f1 = time.monotonic() + 3.0
        while time.monotonic() < deadline_f1 and "DYN_BOTTOM_STAGE_1" not in acc_f1:
            acc_f1 += _drain_follow_pipe(0.05)
        assert "DYN_BOTTOM_STAGE_1" in acc_f1 and "\x1b[2J" not in acc_f1, (
            f"expected immediate initial frame without CSI 2J, got {acc_f1!r}"
        )

        # Idle deduplication: 3 full intervals (~0.20s) with unchanged session must emit 0 bytes
        time.sleep(0.20)
        idle_spill = _drain_follow_pipe(0.0)
        assert idle_spill == "", f"unchanged session emitted duplicate preview bytes: {idle_spill!r}"
        vcs_hits_after_idle = len(open(dyn_vcs_log, encoding="utf-8").read().splitlines()) if os.path.isfile(dyn_vcs_log) else 0
        assert vcs_hits_after_idle == 1, f"expected 1 initial VCS call across fast idle ticks, got {vcs_hits_after_idle}"

        # Stream new viewport output + approval state + peer WORKING collision -> must emit \x1b[2J + live updates
        tmux(
            "respawn-pane",
            "-k",
            "-t",
            ws_dyn["ai"],
            "-c",
            ws_dyn["dir"],
            "/bin/sh -c 'printf \"DYN_BOTTOM_STAGE_1\\nDYN_LIVE_STREAM_2\\n\"; sleep 300'",
            check=True,
        )
        assert wait_until(lambda: "DYN_LIVE_STREAM_2" in tmux_out("capture-pane", "-p", "-t", ws_dyn["ai"]))
        run_cmd(
            [ide_bin, "state", "approval", "--message", "Approve live diff?", "dyn-ws"],
            env=sess_env("dyn-ws", ws_dyn["ai"]),
            check=True,
        )
        run_cmd([ide_bin, "state", "running", "dyn-peer-ws"], env=sess_env("dyn-peer-ws", ws_dyn_peer["ai"]), check=True)

        acc_f2 = ""
        deadline_f2 = time.monotonic() + 2.5
        while time.monotonic() < deadline_f2:
            acc_f2 += _drain_follow_pipe(0.05)
            plain_f2 = _ansi_strip_re.sub("", acc_f2)
            if (
                "\x1b[2J" in acc_f2
                and "DYN_LIVE_STREAM_2" in plain_f2
                and "Approve live diff?" in plain_f2
                and "Shared worktree with dyn-peer-ws" in plain_f2
            ):
                break
        plain_f2 = _ansi_strip_re.sub("", acc_f2)
        assert "\x1b[2J" in acc_f2 and "DYN_LIVE_STREAM_2" in plain_f2, f"missing streamed viewport update: {acc_f2!r}"
        assert "ATTN" in plain_f2 and "Approve live diff?" in plain_f2, f"missing streamed state/message update: {plain_f2!r}"
        assert "Shared worktree with dyn-peer-ws" in plain_f2, f"missing fast-tick peer worktree warning: {plain_f2!r}"

        # Closing reader pipe must wake select.poll(POLLERR|POLLHUP) immediately and exit 0 with empty stderr
        t0_close = time.monotonic()
        os.close(p_rfd)
        p_rfd = -1
        rc_follow = follow_proc.wait(timeout=1.5)
        dt_close = time.monotonic() - t0_close
        follow_stderr = follow_proc.stderr.read().decode("utf-8", "replace") if follow_proc.stderr else ""
        assert rc_follow == 0 and follow_stderr == "" and dt_close < 0.5, (
            f"_internal session-preview --follow did not exit cleanly on pipe close: rc={rc_follow} dt={dt_close:.3f}s stderr={follow_stderr!r}"
        )
    finally:
        if p_rfd >= 0:
            try:
                os.close(p_rfd)
            except OSError:
                pass
        if follow_proc.poll() is None:
            follow_proc.kill()
            follow_proc.wait(timeout=2.0)

    # Killing a session mid-stream emits CSI 2J + "Session is no longer active." and terminates cleanly
    ws_ephem_prev = make_ws("ephem-prev-ws", ai_cmd="printf 'EPHEM_ALIVE\\n'; sleep 300")
    assert wait_until(lambda: "EPHEM_ALIVE" in tmux_out("capture-pane", "-p", "-t", ws_ephem_prev["ai"]))
    ephem_proc = subprocess.Popen(
        [ide_bin, "_internal", "session-preview", "--follow", "ephem-prev-ws"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={**sess_env("dyn-ws", ws_dyn["ed"]), "IDE_PREVIEW_INTERVAL": "0.05"},
        text=True,
    )
    try:
        time.sleep(0.18)
        run_cmd([ide_bin, "quit", "--force", "ephem-prev-ws"], env={**base_env, "TMUX": ""}, check=True)
        ephem_out, ephem_err = ephem_proc.communicate(timeout=2.0)
        assert ephem_proc.returncode == 0 and ephem_err == "", (
            f"killed-session --follow failed: rc={ephem_proc.returncode} err={ephem_err!r}"
        )
        assert "EPHEM_ALIVE" in ephem_out and "\x1b[2JSession is no longer active." in ephem_out, (
            f"expected live frame then CSI 2J inactive notice on session kill, got {ephem_out!r}"
        )
    finally:
        if ephem_proc.poll() is None:
            ephem_proc.kill()
            ephem_proc.wait(timeout=2.0)

    # Verify multi-row full-width SGR carry-over when _select_preview_tail slices Row 0 of `tmux capture-pane -e`
    ws_sgr_slice = make_ws("sgr-slice-ws", ai_cmd="exec sleep 300")
    tmux("resize-window", "-t", ws_sgr_slice["win"], "-x", "80", "-y", "24", check=True)
    sgr_pane_w = int(tmux_out("display-message", "-p", "-t", ws_sgr_slice["ai"], "#{pane_width}") or "40")
    tmux(
        "respawn-pane",
        "-k",
        "-t",
        ws_sgr_slice["ai"],
        "-c",
        ws_sgr_slice["dir"],
        f"/bin/sh -c 'printf \"\\033[38;2;42;161;152m\"; i=1; n={sgr_pane_w * 3 - 5}; while [ $i -le $n ]; do printf \"C\"; i=$((i+1)); done; printf \"\\033[0m\\n\"; sleep 300'",
        check=True,
    )
    assert wait_until(lambda: ("C" * 15) in tmux_out("capture-pane", "-p", "-t", ws_sgr_slice["ai"]))
    r_sgr_sliced = run_cmd(
        [ide_bin, "_internal", "session-preview", "sgr-slice-ws"],
        env={
            **sess_env("sgr-slice-ws", ws_sgr_slice["ed"]),
            "NO_COLOR": "",
            "FZF_PREVIEW_COLUMNS": "60",
            "FZF_PREVIEW_LINES": "7",
        },
        check=True,
    )
    assert "\x1b[38;2;42;161;152mC" in r_sgr_sliced.stdout, (
        f"sliced multi-row Cyan line lost active SGR foreground: {r_sgr_sliced.stdout!r}"
    )
    run_cmd([ide_bin, "quit", "--force", "sgr-slice-ws"], env={**base_env, "TMUX": ""}, check=True)

    # Verify subreaper-reparented (`PR_SET_CHILD_SUBREAPER`, `ppid != 1`) orphan self-termination on Linux
    if sys.platform.startswith("linux"):
        subreaper_rc = subprocess.run(
            [
                sys.executable,
                "-c",
                (
                    "import ctypes, os, select, subprocess, sys, time\n"
                    "libc = ctypes.CDLL('libc.so.6')\n"
                    "libc.prctl(36, 1, 0, 0, 0)\n"
                    "r_fd, w_fd = os.pipe()\n"
                    "ack_r, ack_w = os.pipe()\n"
                    "mid = os.fork()\n"
                    "if mid == 0:\n"
                    "    os.close(r_fd)\n"
                    "    os.close(ack_w)\n"
                    "    subprocess.Popen([sys.argv[1], '_internal', 'session-preview', '--follow', 'dyn-ws'], stdin=subprocess.DEVNULL, stdout=w_fd, stderr=subprocess.DEVNULL)\n"
                    "    os.read(ack_r, 1)\n"
                    "    os._exit(0)\n"
                    "os.close(ack_r)\n"
                    "rdy, _, _ = select.select([r_fd], [], [], 3.0)\n"
                    "assert rdy and os.read(r_fd, 4096), 'preview child did not emit initial frame'\n"
                    "os.write(ack_w, b'1')\n"
                    "os.close(ack_w)\n"
                    "os.waitpid(mid, 0)\n"
                    "deadline = time.monotonic() + 1.5\n"
                    "reaped = False\n"
                    "while time.monotonic() < deadline:\n"
                    "    try:\n"
                    "        wpid, _ = os.waitpid(-1, os.WNOHANG)\n"
                    "        if wpid > 0:\n"
                    "            reaped = True\n"
                    "            break\n"
                    "    except ChildProcessError:\n"
                    "        reaped = True\n"
                    "        break\n"
                    "    time.sleep(0.03)\n"
                    "os.close(r_fd)\n"
                    "os.close(w_fd)\n"
                    "assert reaped, 'preview child hung under PR_SET_CHILD_SUBREAPER after parent exit!'\n"
                ),
                ide_bin,
            ],
            env={**sess_env("dyn-ws", ws_dyn["ed"]), "IDE_PREVIEW_INTERVAL": "0.05"},
            capture_output=True,
            text=True,
            check=False,
        )
        assert subreaper_rc.returncode == 0, f"subreaper orphan termination failed: {subreaper_rc.stderr!r}"

    # Real `fzf` end-to-end `ide -s` (`Alt+s`) dynamic preview verification inside tmux
    real_fzf_bin = shutil.which("fzf")
    if real_fzf_bin:
        tmux("set-environment", "-gu", "IDE_FZF_BIN", check=False)
        run_cmd([ide_bin, "state", "running", "dyn-ws"], env=sess_env("dyn-ws", ws_dyn["ai"]), check=True)
        # Also exercise custom `--preview-wrap-sign` via FZF_DEFAULT_OPTS_FILE alongside odd-width CJK + tabs + window resize
        custom_fzf_opts_file = os.path.join(root, "custom_fzf.opts")
        with open(custom_fzf_opts_file, "w", encoding="utf-8") as cfof:
            cfof.write("--preview-wrap-sign='>>>=> '\n")
        switcher_env_flags = [
            "-e", f"HOME={thome}",
            "-e", f"PATH={clean_path}",
            "-e", f"XDG_CONFIG_HOME={xdg_cfg}",
            "-e", f"XDG_CACHE_HOME={xdg_cache}",
            "-e", f"XDG_RUNTIME_DIR={xdg_run}",
            "-e", "IDE_NO_POPUP=1",
            "-e", f"IDE_FZF_BIN={real_fzf_bin}",
            "-e", "IDE_PREVIEW_INTERVAL=0.06",
            "-e", f"FZF_DEFAULT_OPTS_FILE={custom_fzf_opts_file}",
        ]
        sw_pane = tmux_out(
            "new-window",
            "-d",
            "-P",
            "-F",
            "#{pane_id}",
            "-t",
            "=plain-non-ide",
            "-n",
            "fzf-live",
            *switcher_env_flags,
            f"{shlex.quote(ide_bin)} switch dyn-ws",
        )
        try:
            assert wait_until(
                lambda: "DYN_LIVE_STREAM_2" in tmux_out("capture-pane", "-p", "-t", sw_pane),
                timeout=4.0,
            ), f"real fzf ide switch did not render initial preview: {tmux_out('capture-pane', '-p', '-t', sw_pane)!r}"

            # Mutate AI viewport AND lifecycle state WITHOUT touching fzf (no Ctrl+r, no cursor movement)
            tmux(
                "respawn-pane",
                "-k",
                "-t",
                ws_dyn["ai"],
                "-c",
                ws_dyn["dir"],
                "python3",
                "-c",
                "import time; print('REAL_FZF_DYNAMIC_UPDATE_OK', flush=True); time.sleep(300)",
                check=True,
            )
            run_cmd(
                [ide_bin, "state", "done", "--message", "Ship dynamic preview", "dyn-ws"],
                env=sess_env("dyn-ws", ws_dyn["ai"]),
                check=True,
            )
            assert wait_until(
                lambda: (
                    "REAL_FZF_DYNAMIC_UPDATE_OK" in (cap := tmux_out("capture-pane", "-p", "-t", sw_pane))
                    and "Ship dynamic preview" in cap
                    and "DYN_LIVE_STREAM_2" not in cap
                ),
                timeout=4.0,
            ), f"real fzf preview remained static instead of updating dynamically: {tmux_out('capture-pane', '-p', '-t', sw_pane)!r}"

            # Resize window to odd width 114x27 (`FZF_PREVIEW_COLUMNS=57`) and stream tab-indented + wide CJK lines;
            # confirm custom `--preview-wrap-sign='>>>=> '` + tabs + CJK never clip the bottom sentinel line!
            tmux("resize-window", "-t", sw_pane, "-x", "114", "-y", "27", check=True)
            tmux(
                "respawn-pane",
                "-k",
                "-t",
                ws_dyn["ai"],
                "-c",
                ws_dyn["dir"],
                "/bin/sh -c 'i=1; while [ $i -le 6 ]; do printf \"\\t\\t\\t\\tTAB_WRAP_%02d_xxxxxxxxxxxxxxxxxxxxxxxxxx\\n\" \"$i\"; i=$((i+1)); done; "
                "j=1; while [ $j -le 4 ]; do printf \"中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中\\n\"; j=$((j+1)); done; "
                "printf \"ODD_CJK_TAB_BOTTOM_OK\\n\"; sleep 300'",
                check=True,
            )
            assert wait_until(
                lambda: "ODD_CJK_TAB_BOTTOM_OK" in tmux_out("capture-pane", "-p", "-t", sw_pane),
                timeout=4.0,
            ), f"tabs + odd-width CJK + custom wrap-sign clipped live bottom line in real fzf: {tmux_out('capture-pane', '-p', '-t', sw_pane)!r}"

            # Move selection down to row 2 (`dyn-peer-ws`, both WORKING at startup so row 2 is dyn-peer-ws)
            # and confirm fzf switches streaming preview cleanly and streams new output for dyn-peer-ws too
            tmux("send-keys", "-t", sw_pane, "Down", check=True)
            assert wait_until(
                lambda: " dyn-peer-ws" in tmux_out("capture-pane", "-p", "-t", sw_pane),
                timeout=3.0,
            ), f"Down in real fzf did not switch preview to dyn-peer-ws: {tmux_out('capture-pane', '-p', '-t', sw_pane)!r}"
            tmux(
                "respawn-pane",
                "-k",
                "-t",
                ws_dyn_peer["ai"],
                "-c",
                ws_dyn["dir"],
                "/bin/sh -c 'printf \"PEER_ROW2_DYNAMIC_STREAM\\n\"; sleep 300'",
                check=True,
            )
            assert wait_until(
                lambda: "PEER_ROW2_DYNAMIC_STREAM" in tmux_out("capture-pane", "-p", "-t", sw_pane),
                timeout=3.0,
            ), f"row 2 preview in real fzf did not stream live updates: {tmux_out('capture-pane', '-p', '-t', sw_pane)!r}"

            # Close switcher via Alt+s (`M-s`) and confirm window closes cleanly
            tmux("send-keys", "-t", sw_pane, "M-s", check=False)
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", sw_pane, "#{pane_id}") == "",
                timeout=3.0,
            ), "Alt+s did not close real fzf ide switch window cleanly"
        finally:
            tmux("resize-window", "-u", "-t", "=plain-non-ide:", check=False)
            tmux("kill-window", "-t", sw_pane, check=False)

    run_cmd([ide_bin, "quit", "--force", "dyn-ws", "dyn-peer-ws"], env={**base_env, "TMUX": ""}, check=True)

    # 12. 2-Pane Interactive Switcher (`ai-sw-*` popup: live embedded AI terminal pane + `fzf` list)
    if real_fzf_bin:
        import threading

        tmux("set-environment", "-gu", "IDE_FZF_BIN", check=False)
        tmux("set-environment", "-gu", "MOCK_FZF_KEY", check=False)
        tmux("set-environment", "-gu", "MOCK_FZF_TARGET", check=False)

        ai_repl_py = os.path.join(root, "mock_ai_repl.py")
        with open(ai_repl_py, "w", encoding="utf-8") as repl_fh:
            repl_fh.write(
                "#!/usr/bin/env python3\n"
                "import sys\n"
                "tag = sys.argv[1]\n"
                "log_p = sys.argv[2]\n"
                "print(f'LIVE_AGENT_READY:{tag}', flush=True)\n"
                "for raw in sys.stdin:\n"
                "    s = raw.strip()\n"
                "    with open(log_p, 'a', encoding='utf-8') as lf:\n"
                "        lf.write(s + '\\n')\n"
                "    print(f'AGENT_ACK:{tag}:{s}', flush=True)\n"
            )
        os.chmod(ai_repl_py, 0o755)

        alpha_log = os.path.join(root, "int_alpha_in.log")
        beta_log = os.path.join(root, "int_beta_in.log")
        ws_int_alpha = make_ws(
            "int-alpha",
            ai_cmd=f"python3 -B {shlex.quote(ai_repl_py)} alpha {shlex.quote(alpha_log)}",
            ed_cmd="printf 'INT_ALPHA_ED\\n'; sleep 300",
            ai_cli="claude",
            git_branch="feat/live-ai",
        )
        ws_int_beta = make_ws(
            "int-beta",
            ai_cmd=f"python3 -B {shlex.quote(ai_repl_py)} beta {shlex.quote(beta_log)}",
            ed_cmd="printf 'INT_BETA_ED\\n'; sleep 300",
            ai_cli="codex",
            git_branch="main",
        )
        assert wait_until(
            lambda: "LIVE_AGENT_READY:alpha" in tmux_out("capture-pane", "-p", "-t", ws_int_alpha["ai"])
            and "LIVE_AGENT_READY:beta" in tmux_out("capture-pane", "-p", "-t", ws_int_beta["ai"]),
            timeout=4.0,
        ), "mock live AI REPLs did not become ready"

        # Give int-alpha a custom non-default AI pane width (94 cols) and unacknowledged DONE state,
        # and park int-beta's AI pane into `_ide_park_ai` so we test both custom width & parked AI preservation!
        tmux("resize-pane", "-t", ws_int_alpha["ai"], "-x", "94", check=True)
        orig_alpha_w = int(tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{pane_width}") or "0")
        assert orig_alpha_w >= 90, f"expected custom int-alpha AI width >= 90, got {orig_alpha_w}"
        run_cmd(
            [ide_bin, "state", "done", "--message", "Ready for interactive follow-up", "int-alpha"],
            env=sess_env("int-alpha", ws_int_alpha["ed"]),
            check=True,
        )
        assert tmux_out("show-options", "-qv", "-t", "=int-alpha:", "@ide_ai_attn") == "1"

        run_cmd([ide_bin, "_internal", "park", "ai", "int-beta"], env=sess_env("int-beta", ws_int_beta["ed"]), check=True)
        assert tmux_out("show-options", "-qv", "-t", "=int-beta:", "@ide_ai_parked") == "1"
        run_cmd([ide_bin, "state", "running", "int-beta"], env=sess_env("int-beta", ws_int_beta["ai"]), check=True)

        tmux("switch-client", "-c", client_name, "-t", "=int-alpha", check=True)
        tmux("select-pane", "-t", ws_int_alpha["ed"], check=True)
        drain_pty()
        # Send focus-in `\x1b[I` so client_name has `focused` flag in tmux
        os.write(client_mfd, b"\x1b[I")
        time.sleep(0.05)
        drain_pty()

        pump_stop = threading.Event()

        def _pty_pump_fn():
            while not pump_stop.is_set():
                try:
                    r_fds, _, _ = select.select([client_mfd], [], [], 0.02)
                    if r_fds:
                        os.read(client_mfd, 16384)
                except OSError:
                    break

        pump_thr = threading.Thread(target=_pty_pump_fn, daemon=True)
        pump_thr.start()

        def _active_sw_sess():
            for ln in tmux_out("list-sessions", "-F", "#{session_name}").splitlines():
                s = ln.strip()
                if s.startswith("ai-sw-"):
                    return s
            return ""

        def _sw_ready():
            s = _active_sw_sess()
            if not s:
                return ""
            att = tmux_out("display-message", "-p", "-t", f"={s}:", "#{session_attached}").strip()
            fp = tmux_out("show-options", "-qv", "-t", f"={s}:", "@ide_sw_fzf_pane").strip()
            if att not in ("", "0") and fp and "IDE >" in tmux_out("capture-pane", "-p", "-t", fp):
                return s
            return ""

        sw_proc = None
        int_alpha_nvim_sock = ""
        try:
            # 12a. Open live 2-pane Alt+s popup on client_name
            sw_env = {
                **sess_env("int-alpha", ws_int_alpha["ed"]),
                "IDE_CLIENT": client_name,
                "IDE_FZF_BIN": real_fzf_bin,
                "IDE_PREVIEW_INTERVAL": "0.06",
            }
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess = wait_until(
                lambda: (
                    s
                    if (s := _sw_ready())
                    and tmux_out("show-options", "-qv", "-t", f"={s}:", "@ide_sw_selected_sess").strip() == "int-alpha"
                    and (sp0 := tmux_out("show-options", "-qv", "-t", f"={s}:", "@ide_sw_slot_pane").strip())
                    and "LIVE_AGENT_READY:alpha" in tmux_out("capture-pane", "-p", "-t", sp0)
                    else ""
                ),
                timeout=4.0,
            )
            assert sw_sess, f"2-pane switcher ai-sw-* did not open and render int-alpha preview: sessions={tmux_out('list-sessions')}"

            fzf_p = tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_fzf_pane").strip()
            slot_p = tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_slot_pane").strip()
            assert fzf_p and slot_p, f"missing switcher pane options: fzf={fzf_p!r} slot={slot_p!r}"
            sw_panes = tmux_out("list-panes", "-t", f"={sw_sess}:", "-F", "#{pane_id}").splitlines()
            assert sw_panes == [fzf_p, slot_p], (
                f"expected lazy preview [fzf_p, slot_p] in {sw_sess} before Alt+l, got {sw_panes}"
            )
            # Home AI pane stays completely untouched in int-alpha during lazy browsing (zero swap-pane / zero SIGWINCH)
            home_ai_sess, home_ai_w_s = (
                tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{session_name}\t#{pane_width}").split("\t") + ["", ""]
            )[:2]
            assert home_ai_sess == "int-alpha" and int(home_ai_w_s or "0") == orig_alpha_w, (
                f"lazy switcher unexpectedly mutated home int-alpha AI pane: sess={home_ai_sess!r} w={home_ai_w_s!r} expected={orig_alpha_w}"
            )

            # Left fzf preview renders compact metadata card (`header_only`) without duplicating LIVE_AGENT_READY viewport body
            assert wait_until(
                lambda: (
                    "Ready for interactive follow-up" in (fcap := tmux_out("capture-pane", "-p", "-t", fzf_p))
                    and "LIVE_AGENT_READY:alpha" not in fcap
                ),
                timeout=3.0,
            ), f"left fzf pane did not render header-only metadata card: {tmux_out('capture-pane', '-p', '-t', fzf_p)!r}"

            # `ide list --plain` excludes `ai-sw-*` and keeps `int-alpha` classified as DONE (never SHELL)!
            list_while_open = run_cmd([ide_bin, "list"], env={**base_env, "TMUX": ""}, check=True).stdout
            assert sw_sess not in list_while_open, f"ephemeral {sw_sess} leaked into ide list: {list_while_open}"
            alpha_row_open = next((ln for ln in list_while_open.splitlines() if "int-alpha" in ln), "")
            assert "DONE" in alpha_row_open and "SHELL" not in alpha_row_open, (
                f"int-alpha misclassified in ide list while switcher open: {alpha_row_open!r}"
            )

            # 12b. Press Alt+l (`\x1bl`) on real PTY to lazily dock & focus right live AI pane, interact directly, and verify auto-ack!
            os.write(client_mfd, b"\x1bl")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{pane_id}") == ws_int_alpha["ai"]
                and tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{session_name}") == sw_sess
                and tmux_out("show-options", "-qv", "-t", "=int-alpha:", "@ide_ai_state") == "idle"
                and tmux_out("show-options", "-qv", "-t", "=int-alpha:", "@ide_ai_attn") == "0",
                timeout=3.0,
            ), "Alt+l inside 2-pane switcher did not lazily dock & focus AI pane and auto-acknowledge DONE -> IDLE"

            # While docked, placeholder `slot_p` holds int-alpha's exact custom width (`orig_alpha_w`) in int-alpha's main window
            ph_sess, ph_w_s = (
                tmux_out("display-message", "-p", "-t", slot_p, "#{session_name}\t#{pane_width}").split("\t") + ["", ""]
            )[:2]
            assert ph_sess == "int-alpha" and int(ph_w_s or "0") == orig_alpha_w, (
                f"placeholder did not preserve int-alpha geometry while docked: sess={ph_sess!r} w={ph_w_s!r} expected={orig_alpha_w}"
            )
            list_while_docked = run_cmd([ide_bin, "list"], env={**base_env, "TMUX": ""}, check=True).stdout
            assert sw_sess not in list_while_docked, f"ephemeral {sw_sess} leaked into ide list: {list_while_docked}"
            alpha_row_docked = next((ln for ln in list_while_docked.splitlines() if "int-alpha" in ln), "")
            assert "IDLE" in alpha_row_docked and "SHELL" not in alpha_row_docked, (
                f"docked int-alpha misclassified in ide list: {alpha_row_docked!r}"
            )

            os.write(client_mfd, b"HELLO_EMBEDDED_AI_1\r")
            assert wait_until(
                lambda: "AGENT_ACK:alpha:HELLO_EMBEDDED_AI_1" in tmux_out("capture-pane", "-p", "-t", ws_int_alpha["ai"])
                and os.path.isfile(alpha_log)
                and "HELLO_EMBEDDED_AI_1" in open(alpha_log, encoding="utf-8").read(),
                timeout=3.0,
            ), f"live keystrokes did not reach embedded AI process: {tmux_out('capture-pane', '-p', '-t', ws_int_alpha['ai'])!r}"

            # `ide send --stdin <sw_sess>` (copy-mode-vi `a`) pastes into embedded AI pane WITHOUT undocking it!
            run_cmd(
                [ide_bin, "send", "--stdin", sw_sess],
                env=sess_env("int-alpha", ws_int_alpha["ai"]),
                input_text="SENT_IN_SWITCHER\n",
                check=True,
            )
            assert tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{session_name}") == sw_sess, (
                "send inside switcher unexpectedly undocked AI pane"
            )
            assert wait_until(
                lambda: "AGENT_ACK:alpha:SENT_IN_SWITCHER" in tmux_out("capture-pane", "-p", "-t", ws_int_alpha["ai"]),
                timeout=3.0,
            ), "ide send inside switcher did not deliver payload to embedded AI pane"

            # Press Alt+h (`\x1bh`) to return to left `fzf` session list -> undocks AI pane back to int-alpha and reloads IDLE!
            os.write(client_mfd, b"\x1bh")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{pane_id}") == fzf_p
                and tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{session_name}") == "int-alpha"
                and "IDLE" in tmux_out("capture-pane", "-p", "-t", fzf_p)
                and "AGENT_ACK:alpha:SENT_IN_SWITCHER" in tmux_out("capture-pane", "-p", "-t", slot_p),
                timeout=3.0,
            ), f"Alt+h did not undock AI pane, return to fzf list, and reload IDLE state: {tmux_out('capture-pane', '-p', '-t', fzf_p)!r}"
            restored_alpha_w = int(tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{pane_width}") or "0")
            assert restored_alpha_w == orig_alpha_w, f"int-alpha custom width lost on Alt+h undock: {restored_alpha_w} != {orig_alpha_w}"

            # 12c. Scroll in `fzf` to `int-beta` (whose AI pane was parked in `_ide_park_ai`), interact with it, and scroll back!
            # Type filter `int-beta` -> previews `LIVE_AGENT_READY:beta` on `slot_p` while `ws_int_beta["ai"]` stays parked in `int-beta`!
            os.write(client_mfd, b"int-beta")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_selected_sess").strip() == "int-beta"
                and "LIVE_AGENT_READY:beta" in tmux_out("capture-pane", "-p", "-t", slot_p)
                and tmux_out("display-message", "-p", "-t", ws_int_beta["ai"], "#{session_name}") == "int-beta",
                timeout=3.0,
            ), "filtering to int-beta did not render parked int-beta AI preview without docking"

            # Bounce into int-beta's AI pane via Alt+a (`\x1ba`) -> lazily docks parked AI pane, type live prompt, and bounce back via Alt+a!
            os.write(client_mfd, b"\x1ba")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{pane_id}") == ws_int_beta["ai"]
                and tmux_out("display-message", "-p", "-t", ws_int_beta["ai"], "#{session_name}") == sw_sess,
                timeout=3.0,
            ), "Alt+a did not lazily dock and focus right AI pane for parked int-beta"
            os.write(client_mfd, b"BETA_LIVE_TURN\r")
            assert wait_until(
                lambda: "AGENT_ACK:beta:BETA_LIVE_TURN" in tmux_out("capture-pane", "-p", "-t", ws_int_beta["ai"]),
                timeout=3.0,
            ), "live interaction with parked int-beta AI pane inside switcher failed"

            os.write(client_mfd, b"\x1ba")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{pane_id}") == fzf_p
                and tmux_out("display-message", "-p", "-t", ws_int_beta["ai"], "#{session_name}") == "int-beta"
                and tmux_out("display-message", "-p", "-t", ws_int_beta["ai"], "#{window_name}").startswith("_ide_park_"),
                timeout=3.0,
            ), "Alt+a did not bounce back and undock int-beta AI pane into _ide_park_ai"
            assert tmux_out("show-options", "-qv", "-t", "=int-beta:", "@ide_ai_parked") == "1"

            # Clear filter (`Ctrl+u`) to return to `int-alpha` preview
            os.write(client_mfd, b"\x15int-alpha")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess}:", "@ide_sw_selected_sess").strip() == "int-alpha"
                and "LIVE_AGENT_READY:alpha" in tmux_out("capture-pane", "-p", "-t", slot_p),
                timeout=3.0,
            ), "scrolling back to int-alpha did not refresh slot_p preview"

            # 12d. Focus INSIDE the embedded right AI pane and press Alt+s (`\x1bs`) to close the popup cleanly!
            os.write(client_mfd, b"\x1bl")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", f"={sw_sess}:", "#{pane_id}") == ws_int_alpha["ai"],
                timeout=3.0,
            )
            os.write(client_mfd, b"\x1bs")
            sw_rc = sw_proc.wait(timeout=5.0)
            sw_proc = None
            assert sw_rc == 0, f"closing switcher from embedded AI pane via Alt+s returned {sw_rc}"
            assert _active_sw_sess() == "", "ai-sw-* session was not cleaned up on Alt+s close"
            assert tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{session_name}") == "int-alpha"
            assert int(tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{pane_width}") or "0") == orig_alpha_w
            assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "int-alpha"

            # Zoom int-alpha's Editor pane, open switcher, verify lazy browsing NEVER unzooms Editor,
            # then dock via Alt+l and close via duplicate `ide --sessions` toggle (`find_switcher_for_client`);
            # confirm zoomed state (`window_zoomed_flag == 1` on Editor) is restored on undock!
            tmux("select-pane", "-t", ws_int_alpha["ed"], check=True)
            tmux("resize-pane", "-Z", "-t", ws_int_alpha["ed"], check=True)
            assert tmux_out("display-message", "-p", "-t", ws_int_alpha["ed"], "#{window_zoomed_flag}") == "1"
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess_z = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_z, "switcher did not open for zoom test"
            os.write(client_mfd, b"int-alpha")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_z}:", "@ide_sw_selected_sess").strip() == "int-alpha",
                timeout=3.0,
            )
            assert tmux_out("display-message", "-p", "-t", ws_int_alpha["ed"], "#{window_zoomed_flag}") == "1", (
                "lazy browsing inside switcher unexpectedly unzoomed home Editor window"
            )
            os.write(client_mfd, b"\x1bl")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{session_name}") == sw_sess_z,
                timeout=3.0,
            ), "Alt+l inside switcher did not dock zoomed int-alpha AI pane"
            # Invoking `ide switch` again for the same client toggles the active switcher closed cleanly!
            run_cmd([ide_bin, "switch", "int-alpha"], env=sw_env, check=True)
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None
            assert _active_sw_sess() == ""
            assert tmux_out("display-message", "-p", "-t", ws_int_alpha["ed"], "#{window_zoomed_flag}") == "1", (
                "undocking int-alpha did not restore prior Editor window zoom"
            )
            tmux("resize-pane", "-Z", "-t", ws_int_alpha["ed"], check=True)

            # 12e. Alt+e jump-out AND Ctrl+Click (`_internal open-link`) file:line jump-out from undocked preview pane
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess_e = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_e
            os.write(client_mfd, b"int-beta")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_e}:", "@ide_sw_selected_sess").strip() == "int-beta",
                timeout=3.0,
            )
            # Press Alt+e (`\x1be`) while inside undocked switcher -> closes popup, switches outer client to int-beta, focuses Editor!
            os.write(client_mfd, b"\x1be")
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "int-beta"
                and tmux_out("display-message", "-p", "-t", "=int-beta:", "#{@ide_role}") == "editor",
                timeout=3.0,
            ), "Alt+e inside switcher did not switch outer client to int-beta Editor"

            # Ctrl+Click (`_internal open-link`) on a file:line inside the switcher's undocked preview pane opens file:line in target Editor & switches!
            if shutil.which("nvim"):
                click_target_py = os.path.join(ws_int_alpha["dir"], "clicked_mod.py")
                with open(click_target_py, "w", encoding="utf-8") as cfh:
                    cfh.write("line1 = 1\nline2 = 2\nline3 = 3\nline4 = 4\nline5 = 5\n")
                int_alpha_nvim_sock = os.path.join(xdg_run, "nvim-ide-int-alpha.sock")
                tmux(
                    "respawn-pane",
                    "-k",
                    "-t",
                    ws_int_alpha["ed"],
                    "-c",
                    ws_int_alpha["dir"],
                    f"nvim --clean --listen {shlex.quote(int_alpha_nvim_sock)}",
                    check=True,
                )
                assert wait_until(lambda: nvim_expr_eq(int_alpha_nvim_sock, "1+1", "2"), timeout=4.0), (
                    "int-alpha nvim server did not start"
                )
                sw_env_beta = {
                    **sess_env("int-beta", ws_int_beta["ed"]),
                    "IDE_CLIENT": client_name,
                    "IDE_FZF_BIN": real_fzf_bin,
                    "IDE_PREVIEW_INTERVAL": "0.06",
                }
                sw_proc = subprocess.Popen(
                    [ide_bin, "switch", "int-beta"],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    env=sw_env_beta,
                )
                sw_sess_lk = wait_until(_sw_ready, timeout=4.0)
                assert sw_sess_lk
                os.write(client_mfd, b"int-alpha")
                assert wait_until(
                    lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_lk}:", "@ide_sw_selected_sess").strip() == "int-alpha",
                    timeout=3.0,
                )
                run_cmd(
                    [ide_bin, "_internal", "open-link", "", "clicked_mod.py:4", ws_int_beta["dir"], sw_sess_lk],
                    env=sess_env("int-beta", ws_int_beta["ed"]),
                    check=True,
                )
                assert sw_proc.wait(timeout=5.0) == 0
                sw_proc = None
                assert wait_until(
                    lambda: tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "int-alpha"
                    and tmux_out("display-message", "-p", "-t", "=int-alpha:", "#{@ide_role}") == "editor"
                    and nvim_expr_eq(int_alpha_nvim_sock, "fnamemodify(bufname('%'), ':t') . ':' . line('.')", "clicked_mod.py:4"),
                    timeout=3.0,
                ), "Ctrl+Click _internal open-link inside switcher did not jump to clicked_mod.py:4 in int-alpha Editor"

            # 12f. Docked AI pane exit recovery (`Subcase B`) & `Ctrl+x` workspace termination inside switcher
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess_x = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_x
            os.write(client_mfd, b"int-beta")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_x}:", "@ide_sw_selected_sess").strip() == "int-beta",
                timeout=3.0,
            )
            os.write(client_mfd, b"\x1bl")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_int_beta["ai"], "#{session_name}") == sw_sess_x
                and tmux_out("display-message", "-p", "-t", f"={sw_sess_x}:", "#{pane_id}") == ws_int_beta["ai"],
                timeout=3.0,
            )
            # Kill docked int-beta AI pane while embedded -> switcher survives (`Subcase B` respawns slot_pane) and heals cleanly!
            tmux("kill-pane", "-t", ws_int_beta["ai"], check=True)
            assert wait_until(
                lambda: len(tmux_out("list-panes", "-t", f"={sw_sess_x}:", "-F", "#{pane_id}").splitlines()) == 2,
                timeout=3.0,
            ), "Subcase B did not respawn right placeholder slot_pane after docked AI pane exited"
            os.write(client_mfd, b"\x15int-alpha")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_x}:", "@ide_sw_selected_sess").strip() == "int-alpha"
                and (sp_x := tmux_out("show-options", "-qv", "-t", f"={sw_sess_x}:", "@ide_sw_slot_pane").strip())
                and "LIVE_AGENT_READY:alpha" in tmux_out("capture-pane", "-p", "-t", sp_x),
                timeout=3.0,
            ), "switcher did not recover preview after docked int-beta AI pane exited"
            # Quit clean `int-beta` via Ctrl+x (`\x18`) inside switcher -> int-beta terminates while switcher stays open!
            os.write(client_mfd, b"\x15int-beta")
            time.sleep(0.15)
            os.write(client_mfd, b"\x18")
            assert wait_until(
                lambda: tmux("has-session", "-t", "=int-beta", check=False).returncode != 0,
                timeout=3.0,
            ), "Ctrl+x inside 2-pane switcher did not terminate clean int-beta session"
            os.write(client_mfd, b"\x1bs")
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None

            # 12g. Adversarial switcher regressions:
            # - Alt+h / Alt+l non-wrapping boundaries + Alt+z -> Alt+a unzoom
            # - Alt+n (`New IDE >`) focus/zoom shielding against Alt+a / Alt+l / Alt+h + Esc round-trip
            # - Wrapped URL Ctrl+Click (`--open-link`) inside switcher preview pane
            # - `v`-style `ide --focus-editor` from docked `$TMUX_PANE` (no session arg) closing switcher & jumping to Editor
            # - `Alt+Shift+S` (`--next-attention`) inside switcher switching OUTER client (never nesting inside popup)
            tmux(
                "send-keys",
                "-t",
                ws_int_alpha["ai"],
                "WRAP_URL_TEST https://example.com/switcher-wrapped-path/seg-one-\nseg-two-leaf\n",
            )
            assert wait_until(
                lambda: "seg-two-leaf" in tmux_out("capture-pane", "-p", "-t", ws_int_alpha["ai"]),
                timeout=3.0,
            )
            open(browser_log, "w", encoding="utf-8").close()
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess_adv = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_adv
            fzf_adv = tmux_out("show-options", "-qv", "-t", f"={sw_sess_adv}:", "@ide_sw_fzf_pane").strip()
            os.write(client_mfd, b"int-alpha")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_adv}:", "@ide_sw_selected_sess").strip() == "int-alpha",
                timeout=3.0,
            )

            # Wrapped URL tail click inside switcher (even while undocked!) stitches across lines and opens browser
            run_cmd(
                [ide_bin, "_internal", "open-link", "", "seg-two-leaf", ws_int_alpha["dir"], sw_sess_adv],
                env={**sess_env("int-alpha", ws_int_alpha["ai"]), "IDE_BROWSER": mock_browser},
                check=True,
            )
            assert wait_until(
                lambda: os.path.isfile(browser_log)
                and "https://example.com/switcher-wrapped-path/seg-one-seg-two-leaf"
                in open(browser_log, encoding="utf-8").read(),
                timeout=3.0,
            ), f"wrapped URL inside switcher failed to open: {open(browser_log, encoding='utf-8').read()!r}"

            # Alt+h at left edge stays on fzf_adv; Alt+l lazily docks & moves right; second Alt+l stays on AI pane; Alt+z -> Alt+a unzooms & undocks back to list
            os.write(client_mfd, b"\x1bh")
            time.sleep(0.15)
            assert tmux_out("display-message", "-p", "-t", f"={sw_sess_adv}:", "#{pane_id}") == fzf_adv, (
                "Alt+h on left fzf list unexpectedly wrapped into right AI pane"
            )
            os.write(client_mfd, b"\x1bl")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", f"={sw_sess_adv}:", "#{pane_id}") == ws_int_alpha["ai"],
                timeout=3.0,
            )
            os.write(client_mfd, b"\x1bl")
            time.sleep(0.15)
            assert tmux_out("display-message", "-p", "-t", f"={sw_sess_adv}:", "#{pane_id}") == ws_int_alpha["ai"], (
                "second Alt+l on right AI pane unexpectedly wrapped back to fzf list"
            )
            os.write(client_mfd, b"\x1bz")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", f"={sw_sess_adv}:", "#{window_zoomed_flag}") == "1",
                timeout=3.0,
            )
            os.write(client_mfd, b"\x1ba")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", f"={sw_sess_adv}:", "#{pane_id}") == fzf_adv
                and tmux_out("display-message", "-p", "-t", f"={sw_sess_adv}:", "#{window_zoomed_flag}") == "0"
                and tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{session_name}") == "int-alpha",
                timeout=3.0,
            ), "Alt+a from zoomed embedded AI pane did not unzoom and undock back to 2-pane session list"

            # Alt+n (`New IDE >`) zooms fzf_adv, ignores Alt+a / Alt+l / Alt+h, and Esc returns to 2-pane sessions mode
            os.write(client_mfd, b"\x1bn")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_adv}:", "@ide_sw_mode") == "new"
                and tmux_out("display-message", "-p", "-t", f"={sw_sess_adv}:", "#{window_zoomed_flag}") == "1"
                and "New IDE >" in tmux_out("capture-pane", "-p", "-t", fzf_adv),
                timeout=3.0,
            )
            for nav_seq in (b"\x1ba", b"\x1bl", b"\x1bh"):
                os.write(client_mfd, nav_seq)
                time.sleep(0.1)
                assert tmux_out("display-message", "-p", "-t", f"={sw_sess_adv}:", "#{pane_id}") == fzf_adv, (
                    f"{nav_seq!r} escaped New IDE > directory picker onto hidden placeholder pane"
                )
                assert tmux_out("display-message", "-p", "-t", f"={sw_sess_adv}:", "#{window_zoomed_flag}") == "1", (
                    f"{nav_seq!r} unzoomed New IDE > directory picker"
                )
            os.write(client_mfd, b"\x1b")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_adv}:", "@ide_sw_mode") == "sessions"
                and tmux_out("display-message", "-p", "-t", f"={sw_sess_adv}:", "#{window_zoomed_flag}") == "0"
                and "IDE >" in (cap_s := tmux_out("capture-pane", "-p", "-t", fzf_adv))
                and "New IDE >" not in cap_s,
                timeout=3.0,
            ), "Esc from Alt+n did not restore 2-pane switcher session list"
            os.write(client_mfd, b"int-alpha")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_adv}:", "@ide_sw_selected_sess").strip() == "int-alpha",
                timeout=3.0,
            )
            os.write(client_mfd, b"\x1bl")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{session_name}") == sw_sess_adv,
                timeout=3.0,
            )

            # `ide _internal focus editor` (no session arg, called from docked `$TMUX_PANE` as `v` does) closes switcher & focuses Editor!
            tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
            run_cmd([ide_bin, "_internal", "focus", "editor"], env=sess_env("int-alpha", ws_int_alpha["ai"]), check=True)
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None
            assert wait_until(
                lambda: _active_sw_sess() == ""
                and tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "int-alpha"
                and tmux_out("display-message", "-p", "-t", "=int-alpha:", "#{@ide_role}") == "editor",
                timeout=3.0,
            ), "ide _internal focus editor from docked TMUX_PANE did not close switcher and switch outer client to Editor"

            # Alt+Shift+S (`\x1bS`) inside switcher jumps OUTER client to oldest ATTN session without nesting inside popup!
            run_cmd(
                [ide_bin, "state", "approval", "--message", "Urgent approval", "gamma-ws"],
                env=sess_env("gamma-ws", ws_gamma["ai"]),
                check=True,
            )
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess_attn = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_attn
            os.write(client_mfd, b"\x1bS")
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None
            assert wait_until(
                lambda: _active_sw_sess() == ""
                and tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "gamma-ws"
                and tmux_out("display-message", "-p", "-t", ws_gamma["ai"], "#{session_name}") == "gamma-ws",
                timeout=3.0,
            ), "Alt+Shift+S inside switcher failed to close popup and switch outer client to gamma-ws"
            run_cmd([ide_bin, "state", "idle", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)

            # 12h. Outside-`tmux` (`TMUX=""`) standalone PTY `ide -s` attach (zero leaked `ide-sw-res-*` files + DONE auto-ack)
            import glob as _glob

            if int_alpha_nvim_sock and os.path.exists(int_alpha_nvim_sock):
                subprocess.run(
                    ["nvim", "--headless", "--server", int_alpha_nvim_sock, "--remote-send", "<C-\\><C-n><Cmd>qall!<CR>"],
                    env=base_env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=2,
                    check=False,
                )
                int_alpha_nvim_sock = ""
            tmux("select-pane", "-t", ws_int_alpha["ai"], check=True)
            tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
            run_cmd(
                [ide_bin, "state", "done", "--message", "Standalone attach done", "int-alpha"],
                env=sess_env("int-alpha", ws_int_alpha["ed"]),
                check=True,
            )
            assert tmux_out("show-options", "-qv", "-t", "=int-alpha:", "@ide_ai_attn") == "1"

            ext_mfd, ext_sfd = pty.openpty()
            fcntl.ioctl(ext_sfd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 140, 0, 0))

            def _ext_ctty():
                os.setsid()
                fcntl.ioctl(0, termios.TIOCSCTTY, 0)

            ext_pump_stop = threading.Event()
            ext_proc = None
            try:
                ext_proc = subprocess.Popen(
                    [ide_bin, "-s"],
                    stdin=ext_sfd,
                    stdout=ext_sfd,
                    stderr=ext_sfd,
                    env={**base_env, "TMUX": "", "TMUX_PANE": "", "IDE_FZF_BIN": real_fzf_bin, "IDE_PREVIEW_INTERVAL": "0.06"},
                    close_fds=True,
                    preexec_fn=_ext_ctty,
                )
                os.close(ext_sfd)
                ext_sfd = -1

                def _ext_pump():
                    while not ext_pump_stop.is_set():
                        try:
                            rfds, _, _ = select.select([ext_mfd], [], [], 0.02)
                            if rfds:
                                os.read(ext_mfd, 16384)
                        except OSError:
                            break

                threading.Thread(target=_ext_pump, daemon=True).start()
                sw_ext = wait_until(_sw_ready, timeout=4.0)
                assert sw_ext, "outside-tmux ide -s did not spawn 2-pane ai-sw-* session"
                os.write(ext_mfd, b"int-alpha")
                assert wait_until(
                    lambda: tmux_out("show-options", "-qv", "-t", f"={sw_ext}:", "@ide_sw_selected_sess").strip() == "int-alpha"
                    and tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{session_name}") == "int-alpha",
                    timeout=3.0,
                )
                os.write(ext_mfd, b"\r")
                assert wait_until(
                    lambda: _active_sw_sess() == ""
                    and tmux_out("list-clients", "-t", "=int-alpha", "-F", "#{client_name}") != "",
                    timeout=4.0,
                ), "outside-tmux ide -s Enter did not attach client to int-alpha"
                leaked_res = _glob.glob(os.path.join(xdg_run, "ide-sw-res-*"))
                assert leaked_res == [], f"outside-tmux ide -s leaked switcher result file(s): {leaked_res}"
                assert tmux_out("show-options", "-qv", "-t", "=int-alpha:", "@ide_ai_attn") == "0"
                assert tmux_out("show-options", "-qv", "-t", "=int-alpha:", "@ide_ai_state") == "idle"
            finally:
                ext_pump_stop.set()
                if ext_sfd >= 0:
                    try:
                        os.close(ext_sfd)
                    except OSError:
                        pass
                try:
                    os.close(ext_mfd)
                except OSError:
                    pass
                if ext_proc is not None and ext_proc.poll() is None:
                    ext_proc.terminate()
                    ext_proc.wait(timeout=2.0)

            # 12i. Seeded initial preview card + live `--follow` transition on stationary Row 0 + instant Alt+s close
            # + spaced/quoted `ide_self` focus hook + cross-session stale `@ide_ai_pane` guard + `fzf < 0.46` last-session `Ctrl+x`
            spaced_dir = os.path.join(root, "dir with 'quote' and space", "bin")
            os.makedirs(spaced_dir, exist_ok=True)
            spaced_ide_bin = os.path.join(spaced_dir, "ide")
            shutil.copy2(ide_src, spaced_ide_bin)
            os.chmod(spaced_ide_bin, 0o755)
            shutil.copytree(os.path.join(repo_dir, "libexec", "ide_lib"), os.path.join(os.path.dirname(spaced_dir), "libexec", "ide_lib"), dirs_exist_ok=True)

            # Corrupt int-alpha's @ide_ai_pane to point to gamma-ws's Editor pane: switcher must NOT steal gamma-ws's pane!
            gamma_ed_pane = ws_gamma["ed"]
            tmux("set-option", "-q", "-t", "=int-alpha:", "@ide_ai_pane", gamma_ed_pane, check=True)
            tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
            sw_proc = subprocess.Popen(
                [spaced_ide_bin, "switch", "gamma-ws"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess_seed = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_seed
            fzf_seed = tmux_out("show-options", "-qv", "-t", f"={sw_sess_seed}:", "@ide_sw_fzf_pane").strip()
            top_selected = wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_seed}:", "@ide_sw_selected_sess").strip(),
                timeout=3.0,
            )
            assert top_selected, "seeded switcher failed to set initial @ide_sw_selected_sess"
            assert wait_until(
                lambda: "Workspace:" in (c := tmux_out("capture-pane", "-p", "-t", fzf_seed)) and "VCS      :" in c,
                timeout=3.0,
            ), f"seeded switcher preview card did not render Workspace/VCS lines: {tmux_out('capture-pane', '-p', '-t', fzf_seed)!r}"
            run_cmd(
                [ide_bin, "state", "approval", "--message", "Seeded live update", top_selected],
                env=sw_env,
                check=True,
            )
            assert wait_until(
                lambda: "Seeded live update" in tmux_out("capture-pane", "-p", "-t", fzf_seed),
                timeout=3.0,
            ), f"seeded preview did not transition into live --follow updates: {tmux_out('capture-pane', '-p', '-t', fzf_seed)!r}"
            # Verify `pane-focus-in` hook fires cleanly even when `ide_self` contains spaces and single quotes
            os.write(client_mfd, b"\x1bl")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_seed}:", "@ide_sw_visited_ai").strip() == "1",
                timeout=3.0,
            ), "spaced/quoted ide_self failed to execute pane-focus-in hook"
            os.write(client_mfd, b"\x1bh")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", f"={sw_sess_seed}:", "#{pane_id}").strip() == fzf_seed,
                timeout=3.0,
            )
            # Filter to `int-alpha` -> must heal `@ide_ai_pane` to `ws_int_alpha['ai']` without stealing `gamma_ed_pane`!
            os.write(client_mfd, b"int-alpha")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", "=int-alpha:", "@ide_ai_pane").strip() == ws_int_alpha["ai"],
                timeout=3.0,
            ), "stale cross-session @ide_ai_pane was not healed to int-alpha's own AI pane"
            assert tmux_out("display-message", "-p", "-t", gamma_ed_pane, "#{session_name}").strip() == "gamma-ws", (
                "switcher stole foreign gamma-ws Editor pane via stale @ide_ai_pane"
            )
            assert tmux_out("display-message", "-p", "-t", gamma_ed_pane, "#{@ide_owner_sess}").strip() == "", (
                "switcher corrupted foreign gamma-ws Editor pane @ide_owner_sess"
            )
            run_cmd([ide_bin, "state", "idle", top_selected], env=sw_env, check=True)
            os.write(client_mfd, b"\x1bs")
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None
            assert wait_until(lambda: _active_sw_sess() == "", timeout=3.0)
            assert _glob.glob(os.path.join(xdg_run, "ide-sw-res-*")) == [], "seeded switcher leaked ide-sw-res-* artifacts"

            # 12j. Zoomed home AI pane (`window_zoomed_flag == 1` on `ai_pane`) + `Alt+z` inside switcher restores home AI zoom on close,
            # directory `Ctrl+Click` (`_internal open-link`) inside switcher dives & switches outer client,
            # and parked-AI exit inside switcher resets `@ide_ai_parked=0` while preserving home Editor zoom!
            tmux("switch-client", "-c", client_name, "-t", "=int-alpha", check=True)
            tmux("select-pane", "-t", ws_int_alpha["ai"], check=True)
            tmux("resize-pane", "-Z", "-t", ws_int_alpha["ai"], check=True)
            assert tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{window_zoomed_flag}") == "1"
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess_aiz = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_aiz
            os.write(client_mfd, b"int-alpha")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_aiz}:", "@ide_sw_selected_sess").strip() == "int-alpha",
                timeout=3.0,
            )
            os.write(client_mfd, b"\x1bl")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", f"={sw_sess_aiz}:", "#{pane_id}") == ws_int_alpha["ai"]
                and tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{session_name}") == sw_sess_aiz,
                timeout=3.0,
            )
            os.write(client_mfd, b"\x1bz")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", f"={sw_sess_aiz}:", "#{window_zoomed_flag}") == "1",
                timeout=3.0,
            )
            os.write(client_mfd, b"\x1bs")
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None
            assert wait_until(
                lambda: _active_sw_sess() == ""
                and tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{session_name}") == "int-alpha"
                and tmux_out("display-message", "-p", "-t", ws_int_alpha["ai"], "#{window_zoomed_flag}") == "1",
                timeout=3.0,
            ), "closing switcher after zooming already-zoomed home AI pane failed to restore home AI zoom"
            tmux("resize-pane", "-Z", "-t", ws_int_alpha["ai"], check=True)

            # Directory Ctrl+Click (`_internal open-link` on `sub`) inside undocked switcher dives @ide_workdir, closes switcher, and switches outer client
            tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "gamma-ws"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess_dir = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_dir
            os.write(client_mfd, b"int-alpha")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_dir}:", "@ide_sw_selected_sess").strip() == "int-alpha",
                timeout=3.0,
            )
            run_cmd(
                [ide_bin, "_internal", "open-link", "", "sub", ws_gamma["dir"], sw_sess_dir],
                env={**sess_env("gamma-ws", ws_gamma["ed"]), "IDE_CD_SKIP_SHELL": "1"},
                check=True,
            )
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None
            assert wait_until(
                lambda: _active_sw_sess() == ""
                and tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "int-alpha"
                and tmux_out("show-options", "-qv", "-t", "=int-alpha:", "@ide_workdir")
                == os.path.realpath(os.path.join(ws_int_alpha["dir"], "sub")),
                timeout=3.0,
            ), "Ctrl+Click directory inside switcher failed to dive @ide_workdir and switch outer client"
            run_cmd(
                [ide_bin, "cd", "--reset", "int-alpha"],
                env={**sess_env("int-alpha", ws_int_alpha["ed"]), "IDE_CD_SKIP_SHELL": "1"},
                check=True,
            )

            # Unparked AI + zoomed Editor (`subb-ws`) AND parked AI + zoomed Editor (`gamma-ws`):
            # killing docked AI pane resets `@ide_ai_parked=0` / `@ide_ai_attn=0` and restores/preserves home Editor zoom!
            ws_subb = make_ws("subb-ws", ai_cmd="exec sleep 300", ed_cmd="exec sleep 300", ai_cli="claude")
            tmux("select-pane", "-t", ws_subb["ed"], check=True)
            tmux("resize-pane", "-Z", "-t", ws_subb["ed"], check=True)
            assert tmux_out("display-message", "-p", "-t", ws_subb["ed"], "#{window_zoomed_flag}") == "1"
            if tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_term_parked") == "1":
                run_cmd([ide_bin, "_internal", "park", "term", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
            if tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_parked") != "1":
                run_cmd([ide_bin, "_internal", "park", "ai", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
            assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_parked") == "1"
            run_cmd([ide_bin, "state", "approval", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)
            tmux("select-pane", "-t", ws_gamma["ed"], check=True)
            if tmux_out("display-message", "-p", "-t", ws_gamma["ed"], "#{window_zoomed_flag}") != "1":
                tmux("resize-pane", "-Z", "-t", ws_gamma["ed"], check=True)
            assert tmux_out("display-message", "-p", "-t", ws_gamma["ed"], "#{window_zoomed_flag}") == "1"
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess_pk = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_pk
            os.write(client_mfd, b"subb-ws")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_pk}:", "@ide_sw_selected_sess").strip() == "subb-ws",
                timeout=3.0,
            )
            os.write(client_mfd, b"\x1bl")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_subb["ai"], "#{session_name}") == sw_sess_pk
                and tmux_out("display-message", "-p", "-t", f"={sw_sess_pk}:", "#{pane_id}") == ws_subb["ai"],
                timeout=3.0,
            )
            # swap-pane unzoomed subb-ws's main window; killing subb-ws AI while docked must restore subb-ws Editor zoom on undock!
            assert tmux_out("display-message", "-p", "-t", ws_subb["ed"], "#{window_zoomed_flag}") == "0"
            tmux("kill-pane", "-t", ws_subb["ai"], check=True)
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_subb["ed"], "#{window_zoomed_flag}") == "1",
                timeout=3.0,
            ), "killing docked unparked AI pane failed to restore home Editor zoom on subb-ws"
            os.write(client_mfd, b"\x15gamma-ws")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_pk}:", "@ide_sw_selected_sess").strip() == "gamma-ws",
                timeout=3.0,
            )
            os.write(client_mfd, b"\x1bl")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_gamma["ai"], "#{session_name}") == sw_sess_pk
                and tmux_out("display-message", "-p", "-t", f"={sw_sess_pk}:", "#{pane_id}") == ws_gamma["ai"],
                timeout=3.0,
            )
            tmux("kill-pane", "-t", ws_gamma["ai"], check=True)
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_parked") == "0"
                and tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") == "0",
                timeout=3.0,
            ), "killing docked parked AI pane failed to reset @ide_ai_parked=0 and @ide_ai_attn=0"
            assert tmux_out("display-message", "-p", "-t", ws_gamma["ed"], "#{window_zoomed_flag}") == "1", (
                "killing docked parked AI pane lost home Editor zoom on gamma-ws"
            )
            os.write(client_mfd, b"\x1bs")
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None
            run_cmd([ide_bin, "quit", "--force", "subb-ws"], env={**base_env, "TMUX": ""}, check=False)

            # 12k. Subcase C live-AI preservation when placeholder `slot_pane` is killed externally while home session lives,
            # concurrent 2-client `Alt+l` contention (server-scoped flock preventing double-docking / pane theft),
            # scroll & cursor preservation across both lazy browse and live docking, immediate 3-line mouse wheel scrolling,
            # non-POSIX `$SHELL` resilience in single-pane `fzf`, and `--2pane --agent` forwarding across `ide -s` `Alt+n`!
            ws_subc = make_ws(
                "subc-ws",
                ai_cmd=f"python3 -B {shlex.quote(ai_repl_py)} subc {shlex.quote(os.path.join(root, 'subc.log'))}",
                ed_cmd="exec sleep 300",
                ai_cli="claude",
            )
            assert wait_until(
                lambda: "LIVE_AGENT_READY:subc" in tmux_out("capture-pane", "-p", "-t", ws_subc["ai"]),
                timeout=3.0,
            )
            tmux("switch-client", "-c", client_name, "-t", "=subc-ws", check=True)
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "subc-ws"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess_subc = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_subc
            os.write(client_mfd, b"subc-ws")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_subc}:", "@ide_sw_selected_sess").strip() == "subc-ws",
                timeout=3.0,
            )
            os.write(client_mfd, b"\x1bl")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_subc["ai"], "#{session_name}") == sw_sess_subc
                and tmux_out("display-message", "-p", "-t", f"={sw_sess_subc}:", "#{pane_id}") == ws_subc["ai"],
                timeout=3.0,
            )
            subc_slot = tmux_out("show-options", "-qv", "-t", f"={sw_sess_subc}:", "@ide_sw_slot_pane").strip()
            assert subc_slot and tmux_out("display-message", "-p", "-t", subc_slot, "#{session_name}") == "subc-ws"
            # Kill placeholder `subc_slot` inside live `subc-ws` while `ws_subc["ai"]` is docked in `sw_sess_subc`!
            tmux("kill-pane", "-t", subc_slot, check=True)
            os.write(client_mfd, b"\x1bs")
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None
            assert wait_until(
                lambda: _active_sw_sess() == ""
                and tmux_out("display-message", "-p", "-t", ws_subc["ai"], "#{session_name}") == "subc-ws"
                and tmux_out("show-options", "-qv", "-t", "=subc-ws:", "@ide_docked_in") == "",
                timeout=3.0,
            ), "Subcase C failed to rejoin live AI pane back into subc-ws after placeholder slot_pane was killed"
            tmux("send-keys", "-t", ws_subc["ai"], "STILL_ALIVE_AFTER_SUBC", "C-m", check=True)
            assert wait_until(
                lambda: "AGENT_ACK:subc:STILL_ALIVE_AFTER_SUBC" in tmux_out("capture-pane", "-p", "-t", ws_subc["ai"]),
                timeout=3.0,
            ), "Subcase C killed the user's live AI agent process instead of preserving it!"

            # Concurrent 2-client `Alt+l` contention on the same urgent workspace (`subc-ws`)
            run_cmd(
                [ide_bin, "state", "approval", "--message", "Contested blocker", "subc-ws"],
                env=sess_env("subc-ws", ws_subc["ai"]),
                check=True,
            )
            c2_mfd, c2_sfd = pty.openpty()
            fcntl.ioctl(c2_sfd, termios.TIOCSWINSZ, struct.pack("HHHH", 48, 160, 0, 0))
            c2_proc = subprocess.Popen(
                ["tmux", "attach-session", "-t", "=int-alpha"],
                stdin=c2_sfd,
                stdout=c2_sfd,
                stderr=c2_sfd,
                env={**base_env, "TMUX": "", "TMUX_PANE": ""},
                close_fds=True,
                preexec_fn=lambda sfd=c2_sfd: set_ctty(sfd),
            )
            os.close(c2_sfd)
            c2_pump_stop = threading.Event()

            def _c2_pump_fn():
                while not c2_pump_stop.is_set():
                    try:
                        rfds2, _, _ = select.select([c2_mfd], [], [], 0.02)
                        if rfds2:
                            os.read(c2_mfd, 16384)
                    except OSError:
                        break

            c2_pump_thr = threading.Thread(target=_c2_pump_fn, daemon=True)
            c2_pump_thr.start()
            sw_proc2 = None
            try:
                c2_name = wait_until(
                    lambda: next(
                        (
                            cl.strip()
                            for cl in tmux_out("list-clients", "-t", "=int-alpha", "-F", "#{client_name}").splitlines()
                            if cl.strip() and cl.strip() != client_name
                        ),
                        "",
                    ),
                    timeout=3.0,
                )
                assert c2_name, "failed to attach second PTY client for contention test"
                sw_env2 = {**sw_env, "IDE_CLIENT": c2_name}
                sw_proc = subprocess.Popen(
                    [ide_bin, "switch", "subc-ws"],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    env=sw_env,
                )
                sw_proc2 = subprocess.Popen(
                    [ide_bin, "switch", "int-alpha"],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    env=sw_env2,
                )
                both_sw = wait_until(
                    lambda: (
                        sws
                        if len(
                            sws := [
                                s.strip()
                                for s in tmux_out("list-sessions", "-F", "#{session_name}").splitlines()
                                if s.strip().startswith("ai-sw-")
                            ]
                        )
                        == 2
                        and all(
                            tmux_out("display-message", "-p", "-t", f"={s}:", "#{session_attached}").strip() not in ("", "0")
                            and tmux_out("show-options", "-qv", "-t", f"={s}:", "@ide_sw_selected_sess").strip() == "subc-ws"
                            for s in sws
                        )
                        else []
                    ),
                    timeout=4.0,
                )
                assert len(both_sw) == 2, f"expected 2 concurrent ai-sw-* sessions on subc-ws, got {both_sw}"
                # Both clients press Alt+l simultaneously -> flock ensures subc-ws AI pane docks in AT MOST ONE switcher!
                os.write(client_mfd, b"\x1bl")
                os.write(c2_mfd, b"\x1bl")
                ai_holder = wait_until(
                    lambda: (
                        h
                        if (h := tmux_out("display-message", "-p", "-t", ws_subc["ai"], "#{session_name}").strip()) in both_sw
                        else ""
                    ),
                    timeout=3.0,
                )
                assert ai_holder in both_sw, f"expected subc-ws AI pane in one of {both_sw}, got {ai_holder!r}"
                time.sleep(0.15)
                ai_holder = tmux_out("display-message", "-p", "-t", ws_subc["ai"], "#{session_name}").strip()
                assert ai_holder in both_sw, f"subc-ws AI pane did not stay docked in one switcher: {ai_holder!r}"
                other_sw = both_sw[1] if both_sw[0] == ai_holder else both_sw[0]
                other_panes = tmux_out("list-panes", "-t", f"={other_sw}:", "-F", "#{pane_id}\t#{@ide_sw_placeholder}").splitlines()
                assert len(other_panes) == 2 and any(ln.endswith("\t1") for ln in other_panes), (
                    f"second concurrent switcher {other_sw} lost its placeholder or stole docked pane: {other_panes}"
                )
                other_cl = tmux_out("show-options", "-qv", "-t", f"={other_sw}:", "@ide_sw_client").strip()
                if other_cl == c2_name:
                    os.write(c2_mfd, b"\x1bs")
                    assert sw_proc2.wait(timeout=5.0) == 0
                    sw_proc2 = None
                    # Closing the non-holding switcher must NOT disturb the holding switcher's docked AI pane!
                    assert tmux_out("display-message", "-p", "-t", ws_subc["ai"], "#{session_name}").strip() == ai_holder
                    os.write(client_mfd, b"\x1bs")
                    assert sw_proc.wait(timeout=5.0) == 0
                    sw_proc = None
                else:
                    os.write(client_mfd, b"\x1bs")
                    assert sw_proc.wait(timeout=5.0) == 0
                    sw_proc = None
                    # Closing the non-holding switcher must NOT disturb the holding switcher's docked AI pane!
                    assert tmux_out("display-message", "-p", "-t", ws_subc["ai"], "#{session_name}").strip() == ai_holder
                    os.write(c2_mfd, b"\x1bs")
                    assert sw_proc2.wait(timeout=5.0) == 0
                    sw_proc2 = None
                assert wait_until(
                    lambda: _active_sw_sess() == ""
                    and tmux_out("display-message", "-p", "-t", ws_subc["ai"], "#{session_name}").strip() == "subc-ws"
                    and "@ide_sw_placeholder" not in tmux_out("list-panes", "-s", "-t", "=subc-ws:", "-F", "#{?#{==:#{@ide_sw_placeholder},1},@ide_sw_placeholder,}"),
                    timeout=3.0,
                ), "closing concurrent switchers failed to cleanly restore subc-ws AI pane"
            finally:
                if sw_proc2 is not None and sw_proc2.poll() is None:
                    sw_proc2.kill()
                c2_pump_stop.set()
                c2_pump_thr.join(timeout=2.0)
                tmux("detach-client", "-t", c2_name, check=False) if "c2_name" in locals() and c2_name else None
                try:
                    c2_proc.terminate()
                    c2_proc.wait(timeout=2.0)
                except Exception:
                    c2_proc.kill()
                try:
                    os.close(c2_mfd)
                except OSError:
                    pass
            tmux("switch-client", "-c", client_name, "-t", "=int-alpha", check=True)
            run_cmd([ide_bin, "quit", "--force", "subc-ws"], env={**base_env, "TMUX": ""}, check=False)

            # 12l. Scroll & cursor preservation across session switching (zero SIGWINCH + copy-mode scroll_position + zoomed Editor view)
            # AND immediate 3-line non-focus-stealing mouse wheel scrolling!
            winch_cnt_file = os.path.join(root, "scroll_winch.cnt")
            scroll_ai_py = os.path.join(root, "scroll_ai.py")
            with open(scroll_ai_py, "w", encoding="utf-8") as saf:
                saf.write(
                    "import signal, time\n"
                    f"cnt_p = {winch_cnt_file!r}\n"
                    "n = 0\n"
                    "open(cnt_p, 'w').write('0')\n"
                    "def _on_w(sig, frm):\n"
                    "    global n\n"
                    "    n += 1\n"
                    "    open(cnt_p, 'w').write(str(n))\n"
                    "signal.signal(signal.SIGWINCH, _on_w)\n"
                    "for i in range(1, 121):\n"
                    "    print(f'SCROLL_LINE_{i:03d}', flush=True)\n"
                    "while True:\n"
                    "    time.sleep(1)\n"
                )
            scroll_nvim_sock = os.path.join(xdg_run, "nvim-ide-scroll-ws.sock")
            scroll_txt = os.path.join(root, "scroll_doc.txt")
            with open(scroll_txt, "w", encoding="utf-8") as stf:
                stf.write("".join(f"doc line {i}\n" for i in range(1, 301)))
            ed_scroll_cmd = (
                f"nvim --clean --listen {shlex.quote(scroll_nvim_sock)} {shlex.quote(scroll_txt)}"
                if shutil.which("nvim")
                else "exec sleep 300"
            )
            ws_scroll = make_ws(
                "scroll-ws",
                ai_cmd=f"python3 -B {shlex.quote(scroll_ai_py)}",
                ed_cmd=ed_scroll_cmd,
                ai_cli="claude",
            )
            if shutil.which("nvim"):
                tmux("set-option", "-q", "-t", "=scroll-ws:", "@ide_socket", scroll_nvim_sock, check=True)
            assert wait_until(
                lambda: "SCROLL_LINE_120" in tmux_out("capture-pane", "-p", "-t", ws_scroll["ai"]),
                timeout=3.0,
            )
            # Visit `scroll-ws` on the live 160x48 client first (modeling switching away and back between active sessions),
            # enter copy-mode at scroll_position=40, zoom Editor at topline=150/lnum=160, and record baseline SIGWINCH count!
            tmux("switch-client", "-c", client_name, "-t", "=scroll-ws", check=True)
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", "=scroll-ws:", "#{window_height}").strip() == "47",
                timeout=3.0,
            )
            tmux("copy-mode", "-t", ws_scroll["ai"], check=True)
            tmux("send-keys", "-X", "-t", ws_scroll["ai"], "-N", "40", "scroll-up", check=True)
            assert tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{scroll_position}").strip() == "40"
            orig_topline = ""
            if shutil.which("nvim"):
                assert wait_until(lambda: nvim_expr_eq(scroll_nvim_sock, "line('$')", "300"), timeout=4.0), (
                    "scroll_doc.txt did not finish loading 300 lines in scroll-ws nvim"
                )
                tmux("select-pane", "-t", ws_scroll["ed"], check=True)
                tmux("resize-pane", "-Z", "-t", ws_scroll["ed"], check=True)
                time.sleep(0.08)
                subprocess.run(
                    [
                        "nvim",
                        "--headless",
                        "--server",
                        scroll_nvim_sock,
                        "--remote-expr",
                        "execute(\"call winrestview({'topline': 150, 'lnum': 160, 'col': 0})\")",
                    ],
                    env=base_env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=3,
                    check=True,
                )
                orig_topline = "150:160"
                assert wait_until(
                    lambda: nvim_expr_eq(
                        scroll_nvim_sock,
                        "get(winsaveview(), 'topline', 0) . ':' . line('.')",
                        orig_topline,
                    ),
                    timeout=2.0,
                ), "failed to position zoomed scroll-ws Editor at topline=150, lnum=160"

            # A) Switch away to `int-alpha`, open `Alt+s`, browse to `scroll-ws`, and press Enter to switch back
            # -> ZERO new SIGWINCH signals, scroll_position==40, and zoomed Editor view intact!
            tmux("switch-client", "-c", client_name, "-t", "=int-alpha", check=True)
            ai_pty_path = tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{pane_tty}").strip()
            expected_ai_wh = tuple(
                int(x)
                for x in tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{pane_height}\t#{pane_width}").split("\t")
            )
            if ai_pty_path and os.path.exists(ai_pty_path):
                def _ai_pty_settled():
                    with open(ai_pty_path, "rb", buffering=0) as pfh:
                        r_h, r_w, _, _ = struct.unpack("HHHH", fcntl.ioctl(pfh.fileno(), termios.TIOCGWINSZ, bytes(8)))
                    return (r_h, r_w) == expected_ai_wh

                assert wait_until(_ai_pty_settled, timeout=1.0), "scroll-ws AI PTY geometry did not settle before baseline"
            time.sleep(0.05)
            baseline_winch = open(winch_cnt_file, encoding="utf-8").read().strip()
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess_scr = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_scr
            os.write(client_mfd, b"scroll-ws")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_scr}:", "@ide_sw_selected_sess").strip() == "scroll-ws",
                timeout=3.0,
            )
            os.write(client_mfd, b"\r")
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "scroll-ws",
                timeout=3.0,
            )
            after_switch_winch = open(winch_cnt_file, encoding="utf-8").read().strip()
            assert after_switch_winch == baseline_winch, (
                f"lazy switcher browse/switch fired SIGWINCH on scroll-ws AI pane: {baseline_winch!r} -> {after_switch_winch!r}"
            )
            assert tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{pane_in_mode}\t#{scroll_position}").strip() == "1\t40", (
                "lazy switcher browse/switch lost copy-mode scroll_position=40"
            )
            if orig_topline:
                assert tmux_out("display-message", "-p", "-t", ws_scroll["ed"], "#{window_zoomed_flag}").strip() == "1"
                assert nvim_expr_eq(scroll_nvim_sock, "winsaveview().topline . ':' . line('.')", orig_topline), (
                    "lazy switcher browse/switch shifted zoomed Editor topline/cursor"
                )

            # B) Dock `scroll-ws` via `Alt+l` (`swap-pane -d` across geometry difference!) and undock via `Alt+h` + `Alt+s`
            # -> BOTH `scroll_position == 40` AND zoomed Editor `topline:lnum` are saved & restored!
            tmux("switch-client", "-c", client_name, "-t", "=int-alpha", check=True)
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess_scr2 = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_scr2
            os.write(client_mfd, b"scroll-ws")
            assert wait_until(
                lambda: tmux_out("show-options", "-qv", "-t", f"={sw_sess_scr2}:", "@ide_sw_selected_sess").strip() == "scroll-ws",
                timeout=3.0,
            )
            os.write(client_mfd, b"\x1bl")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{session_name}") == sw_sess_scr2
                and tmux_out("display-message", "-p", "-t", f"={sw_sess_scr2}:", "#{pane_id}") == ws_scroll["ai"]
                and tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{scroll_position}").strip() == "40",
                timeout=3.0,
            ), "docking scroll-ws via Alt+l failed to focus AI pane and preserve copy-mode scroll_position=40"
            os.write(client_mfd, b"\x1bh")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{session_name}") == "scroll-ws",
                timeout=3.0,
            ), (
                "Alt+h from docked copy-mode AI pane did not undock back to scroll-ws: "
                + repr(tmux_out("display-message", "-p", "-t", f"={sw_sess_scr2}:", "#{pane_id}\t#{@ide_sw_docked_pane}"))
            )
            os.write(client_mfd, b"\x1bs")
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None
            assert tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{pane_in_mode}\t#{scroll_position}").strip() == "1\t40", (
                "undocking scroll-ws lost copy-mode scroll_position=40"
            )
            if orig_topline:
                assert tmux_out("display-message", "-p", "-t", ws_scroll["ed"], "#{window_zoomed_flag}").strip() == "1"
                assert wait_until(
                    lambda: nvim_expr_eq(
                        scroll_nvim_sock,
                        "get(winsaveview(), 'topline', 0) . ':' . line('.')",
                        orig_topline,
                    ),
                    timeout=2.0,
                ), "undocking scroll-ws failed to restore zoomed Editor topline/cursor"
            tmux("send-keys", "-X", "-t", ws_scroll["ai"], "cancel", check=False)
            if orig_topline:
                tmux("resize-pane", "-Z", "-t", ws_scroll["ed"], check=False)

            # C) Hover mouse wheel scrolling (`WheelUpPane` / `WheelDownPane` from `dotfiles/.tmux.conf`):
            # immediate 3-line step on tick 1 (`scroll_position == 3`), auto-cancel at 0, and ZERO focus theft!
            tmux("source-file", os.path.join(repo_dir, "dotfiles", ".tmux.conf"), check=True)
            tmux("switch-client", "-c", client_name, "-t", "=scroll-ws", check=True)
            tmux("select-pane", "-t", ws_scroll["ed"], check=True)
            ai_left_s, ai_top_s = (
                tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{pane_left}\t#{pane_top}").split("\t") + ["0", "0"]
            )[:2]
            wheel_col = int(ai_left_s or "0") + 3
            wheel_row = int(ai_top_s or "0") + 3  # +1 status bar +1 1-based SGR row +1 inside pane
            os.write(client_mfd, f"\x1b[<64;{wheel_col};{wheel_row}M".encode("ascii"))
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{pane_in_mode}\t#{scroll_position}").strip() == "1\t3",
                timeout=3.0,
            ), (
                "first WheelUpPane tick did not immediately scroll 3 lines: "
                + repr(tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{pane_in_mode}\t#{scroll_position}"))
            )
            os.write(client_mfd, f"\x1b[<64;{wheel_col};{wheel_row}M".encode("ascii"))
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{pane_in_mode}\t#{scroll_position}").strip() == "1\t6",
                timeout=3.0,
            ), "second hover WheelUpPane tick over unfocused AI pane did not advance scroll_position to 6"
            assert tmux_out("display-message", "-p", "-t", "=scroll-ws:", "#{pane_id}").strip() == ws_scroll["ed"], (
                "hover WheelUpPane over unfocused AI pane stole active keyboard focus from Editor!"
            )
            os.write(client_mfd, f"\x1b[<65;{wheel_col};{wheel_row}M".encode("ascii"))
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{pane_in_mode}\t#{scroll_position}").strip() == "1\t3",
                timeout=3.0,
            ), "first hover WheelDownPane tick did not step scroll_position from 6 to 3"
            os.write(client_mfd, f"\x1b[<65;{wheel_col};{wheel_row}M".encode("ascii"))
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", ws_scroll["ai"], "#{pane_in_mode}\t#{scroll_position}").strip() == "0",
                timeout=3.0,
            ), "WheelDownPane back to bottom did not auto-cancel copy-mode"
            assert tmux_out("display-message", "-p", "-t", "=scroll-ws:", "#{pane_id}").strip() == ws_scroll["ed"], (
                "hover WheelDownPane over unfocused AI pane stole active keyboard focus from Editor!"
            )

            if shutil.which("nvim") and os.path.exists(scroll_nvim_sock):
                subprocess.run(
                    ["nvim", "--headless", "--server", scroll_nvim_sock, "--remote-send", "<C-\\><C-n><Cmd>qall!<CR>"],
                    env=base_env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=2,
                    check=False,
                )
            tmux("switch-client", "-c", client_name, "-t", "=int-alpha", check=True)
            run_cmd([ide_bin, "quit", "--force", "scroll-ws"], env={**base_env, "TMUX": ""}, check=False)

            # 12m. mono-tui v0.2.5 ergonomics: width-fitted footer packing, 90-col responsive split/stack breakpoint,
            # Focused Surface [PREVIEW]/[LIVE] border states, and 4-tier color + Nerd Font degradation!
            sys.path.insert(0, os.path.join(repo_dir, "libexec"))
            from ide_lib.constants import use_nerd_fonts, visible_width
            from ide_lib.preview import format_fleet_sessions_lines, format_session_preview_header
            from ide_lib.switcher import (
                SIDE_BY_SIDE_MIN_COLS,
                build_sessions_fzf_args,
                format_sessions_footer_label,
                query_outer_switcher_snapshot,
                run_interactive_switcher_session,
            )
            from ide_lib.theme import build_fzf_env, detect_color_tier, load_active_palette

            assert SIDE_BY_SIDE_MIN_COLS == 90
            lbl_narrow = format_sessions_footer_label(pane_w=58, in_two_pane=True)
            assert visible_width(lbl_narrow) <= 54, f"narrow footer overflowed budget: {lbl_narrow!r}"
            assert "Enter: switch" in lbl_narrow and "Alt+l: AI" in lbl_narrow and "Alt+s: close" in lbl_narrow
            for tok in lbl_narrow.strip().split(" · "):
                assert ":" in tok, f"clipped token in narrow footer: {lbl_narrow!r}"

            hm_saved_env = os.environ.copy()
            try:
                os.environ.clear()
                os.environ.update(base_env)
                hm_test, _ = load_active_palette()
                args_80 = build_sessions_fzf_args(
                    fzf_bin="fzf",
                    ide_self=ide_bin,
                    cur_sess="int-alpha",
                    hex_map=hm_test,
                    supports_modern_binds=True,
                    sw_sess="",
                    pane_h=24,
                    pane_w=80,
                )
                args_120 = build_sessions_fzf_args(
                    fzf_bin="fzf",
                    ide_self=ide_bin,
                    cur_sess="int-alpha",
                    hex_map=hm_test,
                    supports_modern_binds=True,
                    sw_sess="",
                    pane_h=36,
                    pane_w=120,
                )
                assert "--preview-window=down:50%:wrap:noinfo" in args_80, f"80-col fzf did not stack preview vertically: {args_80}"
                assert "--preview-window=right:56%:wrap:noinfo" in args_120, f"120-col fzf did not split preview right: {args_120}"
                assert any("spinner:#2AA198" in a for a in args_120), f"expected CYAN spinner for WORKING state, got {args_120}"
                os.environ["NO_MOTION"] = "1"
                args_nomotion = build_sessions_fzf_args(
                    fzf_bin="fzf",
                    ide_self=ide_bin,
                    cur_sess="int-alpha",
                    hex_map=hm_test,
                    supports_modern_binds=True,
                )
                assert any("spinner:#002B36" in a for a in args_nomotion), (
                    f"NO_MOTION=1 did not mask spinner to BASE03: {args_nomotion}"
                )
            finally:
                os.environ.clear()
                os.environ.update(hm_saved_env)

            # Verify state-driven IDE_PREVIEW_WHILE_WORKING=1:
            # - exits immediately on non-WORKING sessions (zero idle spinner/polling)
            # - stays streaming while WORKING, and auto-exits when transitioning out of WORKING!
            t0_idle_prev = time.monotonic()
            r_idle_prev = run_cmd(
                [ide_bin, "_internal", "session-preview", "--follow", "int-alpha"],
                env={**sw_env, "IDE_PREVIEW_WHILE_WORKING": "1"},
                check=True,
            )
            assert (time.monotonic() - t0_idle_prev) < 1.0 and "Workspace:" in r_idle_prev.stdout, (
                f"IDE_PREVIEW_WHILE_WORKING=1 hung on IDLE session: {r_idle_prev.stdout!r}"
            )
            run_cmd([ide_bin, "state", "running", "int-alpha"], env=sw_env, check=True)
            wk_prev_proc = subprocess.Popen(
                [ide_bin, "_internal", "session-preview", "--follow", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env={**sw_env, "IDE_PREVIEW_WHILE_WORKING": "1", "IDE_PREVIEW_INTERVAL": "0.06"},
            )
            try:
                time.sleep(0.22)
                assert wk_prev_proc.poll() is None, "IDE_PREVIEW_WHILE_WORKING=1 exited prematurely while session was WORKING"
                run_cmd([ide_bin, "state", "idle", "int-alpha"], env=sw_env, check=True)
                wk_out, wk_err = wk_prev_proc.communicate(timeout=2.0)
                assert wk_prev_proc.returncode == 0 and wk_err == "" and "IDLE" in wk_out, (
                    f"IDE_PREVIEW_WHILE_WORKING=1 did not emit final state and auto-exit when leaving WORKING: rc={wk_prev_proc.returncode} out={wk_out!r}"
                )
            finally:
                if wk_prev_proc.poll() is None:
                    wk_prev_proc.kill()

            # Verify live `ai-sw-*` window exposes `[PREVIEW]` vs `[LIVE]` with calm `BASE01` borders, and `< 90` cols returns `None`!
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env={**sw_env, "IDE_NERD_FONTS": "0"},
            )
            sw_sess_mt = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_mt
            mt_bfmt = tmux_out("show-options", "-wv", "-t", f"={sw_sess_mt}:sessions", "pane-border-format")
            mt_act_b = tmux_out("show-options", "-wv", "-t", f"={sw_sess_mt}:sessions", "pane-active-border-style")
            assert "[PREVIEW]" in mt_bfmt and "[LIVE]" in mt_bfmt, f"missing [PREVIEW]/[LIVE] in pane-border-format: {mt_bfmt!r}"
            assert hm_test["BASE01"].lower() in mt_act_b.lower(), f"expected calm BASE01 active border in switcher, got {mt_act_b!r}"
            assert not any(0xE000 <= ord(ch) <= 0xF8FF or ord(ch) >= 0xF0000 for ch in mt_bfmt), (
                f"IDE_NERD_FONTS=0 leaked PUA glyphs into switcher border: {mt_bfmt!r}"
            )
            # Pressing F1 inside 2-pane `ai-sw-*` zooms the left pane across the full modal to render the spacious cheatsheet, then unzooms on `q`!
            mt_fzf_p = tmux_out("show-options", "-qv", "-t", f"={sw_sess_mt}:", "@ide_sw_fzf_pane").strip()
            os.write(client_mfd, b"\x1bOP")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", f"={sw_sess_mt}:", "#{window_zoomed_flag}").strip() == "1"
                and "Ack attention or open PR" in tmux_out("capture-pane", "-p", "-t", mt_fzf_p),
                timeout=3.0,
            ), f"F1 inside ai-sw-* did not zoom fzf pane and render spacious cheatsheet: {tmux_out('capture-pane', '-p', '-t', mt_fzf_p)!r}"
            os.write(client_mfd, b"q")
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-t", f"={sw_sess_mt}:", "#{window_zoomed_flag}").strip() == "0"
                and "IDE >" in tmux_out("capture-pane", "-p", "-t", mt_fzf_p),
                timeout=3.0,
            ), "closing F1 cheatsheet inside ai-sw-* did not restore unzoomed 2-pane switcher"
            os.write(client_mfd, b"\x1bs")
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None

            # Shrink PTY to 80x24 temporarily and confirm `display-keys-ide` clamps without `height too large` AND `run_interactive_switcher_session` returns `None` (`< 90` cols -> stacked fallback)
            fcntl.ioctl(client_mfd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
            assert wait_until(
                lambda: tmux_out("display-message", "-p", "-c", client_name, "#{client_width}").strip() == "80",
                timeout=3.0,
            )
            keys_80_proc = subprocess.Popen(
                ["tmux", "display-keys-ide"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            time.sleep(0.15)
            os.write(client_mfd, b"q")
            _, keys_80_err = keys_80_proc.communicate(timeout=3.0)
            assert keys_80_proc.returncode == 0 and keys_80_err == "", (
                f"display-keys-ide failed on 80x24 client: rc={keys_80_proc.returncode} err={keys_80_err!r}"
            )
            saved_env = os.environ.copy()
            try:
                os.environ.update({**sw_env, "IDE_IN_POPUP": "1"})
                snap_80 = query_outer_switcher_snapshot("int-alpha")
                assert snap_80.client_w == 80
                rc_80 = run_interactive_switcher_session(
                    origin_sess="int-alpha",
                    cur_sess="int-alpha",
                    ide_self=ide_bin,
                    fzf_bin=real_fzf_bin,
                    forward_ai_cli=False,
                    snap=snap_80,
                    client_name=client_name,
                )
                assert rc_80 is None, f"expected None (< 90 cols fallback) on 80x24 client, got {rc_80!r}"
            finally:
                os.environ.clear()
                os.environ.update(saved_env)
                fcntl.ioctl(client_mfd, termios.TIOCSWINSZ, struct.pack("HHHH", 48, 160, 0, 0))
                wait_until(
                    lambda: tmux_out("display-message", "-p", "-c", client_name, "#{client_width}").strip() == "160",
                    timeout=3.0,
                )

            # Verify 4-tier color degradation + ASCII glyph fallback on synthetic fleet row & preview header
            sample_fleet = [
                {
                    "sess": "int-alpha",
                    "ai_cli": "claude",
                    "state": "ATTN",
                    "state_age_s": 120,
                    "needs_attn": True,
                    "is_current": True,
                    "git_branch": "main",
                    "git_dirty": True,
                    "git_detail": "2 modified",
                    "pr_label": "main@42",
                    "short_path": "~/ws/alpha",
                    "workdir": ws_int_alpha["dir"],
                    "worktree_peers": ["int-beta"],
                    "active_role": "ai",
                    "ai_msg": "Approve command",
                    "msg": "Approve command",
                    "quit_err": "",
                }
            ]
            for env_patch, exp_tier, check_fn in [
                (
                    {"NO_COLOR": "1", "COLORTERM": "truecolor", "TERM": "xterm-256color", "IDE_NERD_FONTS": "1"},
                    "nocolor",
                    lambda line_s, hdr_s, nf_v: ("\x1b[" not in line_s and "\x1b[" not in hdr_s and nf_v is True),
                ),
                (
                    {"NO_COLOR": "", "COLORTERM": "", "TERM": "dumb", "IDE_NERD_FONTS": ""},
                    "mono",
                    lambda line_s, hdr_s, nf_v: (
                        "\x1b[38;" not in line_s
                        and ("\x1b[1m" in line_s or "\x1b[2m" in line_s)
                        and nf_v is False
                        and not any(0xE000 <= ord(ch) <= 0xF8FF or ord(ch) >= 0xF0000 for ch in line_s + hdr_s)
                    ),
                ),
                (
                    {"NO_COLOR": "", "COLORTERM": "", "TERM": "screen-256color", "IDE_NERD_FONTS": "0"},
                    "256color",
                    lambda line_s, hdr_s, nf_v: (
                        "\x1b[38;5;" in line_s
                        and "\x1b[38;2;" not in line_s
                        and nf_v is False
                        and not any(0xE000 <= ord(ch) <= 0xF8FF or ord(ch) >= 0xF0000 for ch in line_s + hdr_s)
                    ),
                ),
                (
                    {"NO_COLOR": "", "COLORTERM": "256color", "TERM": "xterm-256color", "IDE_NERD_FONTS": "1"},
                    "256color",
                    lambda line_s, hdr_s, nf_v: ("\x1b[38;5;" in line_s and "\x1b[38;2;" not in line_s and nf_v is True),
                ),
                (
                    {"NO_COLOR": "", "COLORTERM": "", "TERM": "xterm", "IDE_NERD_FONTS": "1"},
                    "16color",
                    lambda line_s, hdr_s, nf_v: ("\x1b[" in line_s and "\x1b[38;" not in line_s and nf_v is True),
                ),
            ]:
                saved_e = os.environ.copy()
                try:
                    os.environ.clear()
                    os.environ.update({**base_env, **env_patch})
                    if env_patch["NO_COLOR"] == "":
                        os.environ.pop("NO_COLOR", None)
                    got_tier = detect_color_tier()
                    assert got_tier == exp_tier, f"expected tier {exp_tier!r} for {env_patch}, got {got_tier!r}"
                    _, tier_esc = load_active_palette()
                    fzf_opts_t = build_fzf_env(hm_test).get("FZF_DEFAULT_OPTS", "")
                    if exp_tier == "nocolor":
                        assert fzf_opts_t.startswith("--no-color "), f"expected --no-color FZF_DEFAULT_OPTS, got {fzf_opts_t!r}"
                    elif exp_tier == "mono":
                        assert fzf_opts_t.startswith("--color=bw "), f"expected --color=bw FZF_DEFAULT_OPTS, got {fzf_opts_t!r}"
                    row_s = "\n".join(format_fleet_sessions_lines(sample_fleet, tier_esc))
                    hdr_s = "\n".join(
                        format_session_preview_header(sample_fleet[0], tier_esc, "main", True, "2 modified", "", ["int-beta"])
                    )
                    assert check_fn(row_s, hdr_s, use_nerd_fonts()), (
                        f"tier {exp_tier} degradation failed: row={row_s!r} hdr={hdr_s!r}"
                    )
                finally:
                    os.environ.clear()
                    os.environ.update(saved_e)

            # Verify `ide --2pane --agent codex -s` forwards `--2pane` and `--agent codex` when launching a workspace via `Alt+n`!
            twopane_ws_dir = os.path.join(thome, "twopane-altn-ws")
            os.makedirs(twopane_ws_dir, exist_ok=True)
            stub_codex = os.path.join(bin_dir, "codex")
            with open(stub_codex, "w", encoding="utf-8") as scf:
                scf.write("#!/bin/sh\nexec sleep 300\n")
            os.chmod(stub_codex, 0o755)
            sw_proc = subprocess.Popen(
                [ide_bin, "--2pane", "--agent", "codex", "-s", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=sw_env,
            )
            sw_sess_2p = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_2p
            fzf_2p = tmux_out("show-options", "-qv", "-t", f"={sw_sess_2p}:", "@ide_sw_fzf_pane").strip()
            os.write(client_mfd, b"\x1bn")
            assert wait_until(
                lambda: "New IDE >" in tmux_out("capture-pane", "-p", "-t", fzf_2p),
                timeout=3.0,
            )
            os.write(client_mfd, b"twopane-altn-ws")
            time.sleep(0.15)
            os.write(client_mfd, b"\r")
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None
            assert wait_until(
                lambda: tmux("has-session", "-t", "=twopane-altn-ws", check=False).returncode == 0
                and tmux_out("show-options", "-qv", "-t", "=twopane-altn-ws:", "@ide_layout_mode") == "2pane"
                and tmux_out("show-options", "-qv", "-t", "=twopane-altn-ws:", "@ide_ai_cli") == "codex",
                timeout=3.0,
            ), (
                f"ide --2pane --agent codex -s Alt+n dropped layout/agent flags: "
                f"layout={tmux_out('show-options', '-qv', '-t', '=twopane-altn-ws:', '@ide_layout_mode')!r} "
                f"cli={tmux_out('show-options', '-qv', '-t', '=twopane-altn-ws:', '@ide_ai_cli')!r}"
            )
            tmux("switch-client", "-c", client_name, "-t", "=int-alpha", check=True)
            run_cmd([ide_bin, "quit", "--force", "twopane-altn-ws"], env={**base_env, "TMUX": ""}, check=False)
            os.unlink(stub_codex)
            shutil.rmtree(twopane_ws_dir, ignore_errors=True)

            # Verify non-POSIX `$SHELL` (e.g. `fish`/`tcsh` simulated by `/bin/false`) never breaks `fzf` `--preview` in single-pane `sessions.py`!
            false_sh = shutil.which("false") or "/bin/false"
            nosh_pane = tmux_out(
                "new-window",
                "-d",
                "-P",
                "-F",
                "#{pane_id}",
                "-t",
                "=plain-non-ide",
                "-n",
                "fzf-nosh",
                "-e", f"HOME={thome}",
                "-e", f"PATH={clean_path}",
                "-e", f"XDG_CONFIG_HOME={xdg_cfg}",
                "-e", f"XDG_CACHE_HOME={xdg_cache}",
                "-e", f"XDG_RUNTIME_DIR={xdg_run}",
                "-e", "IDE_NO_POPUP=1",
                "-e", f"IDE_FZF_BIN={real_fzf_bin}",
                "-e", f"SHELL={false_sh}",
                f"{shlex.quote(ide_bin)} switch int-alpha",
            )
            try:
                assert wait_until(
                    lambda: "Workspace:" in tmux_out("capture-pane", "-p", "-t", nosh_pane),
                    timeout=4.0,
                ), f"non-POSIX SHELL={false_sh} broke fzf --preview in sessions.py: {tmux_out('capture-pane', '-p', '-t', nosh_pane)!r}"
                tmux("send-keys", "-t", nosh_pane, "M-s", check=False)
            finally:
                tmux("kill-window", "-t", nosh_pane, check=False)

            # Last-IDE-session `Ctrl+x` under `fzf 0.44.1` (`not supports_modern_binds`) closes `ai-sw-*` cleanly and switches outer client to `plain-non-ide`!
            old_fzf_dir = os.path.join(root, "old_fzf_044")
            os.makedirs(old_fzf_dir, exist_ok=True)
            old_fzf_bin = os.path.join(old_fzf_dir, "fzf")
            with open(old_fzf_bin, "w", encoding="utf-8") as ofh:
                ofh.write(
                    f'#!/bin/sh\nif [ "$1" = "--version" ]; then printf "0.44.1 (ubuntu)\\n"; exit 0; fi\n'
                    f'exec {shlex.quote(real_fzf_bin)} "$@"\n'
                )
            os.chmod(old_fzf_bin, 0o755)
            tmux("switch-client", "-c", client_name, "-t", "=int-alpha", check=True)
            run_cmd([ide_bin, "quit", "--force", "alpha-ws", "beta-ws", "gamma-ws"], env={**base_env, "TMUX": ""}, check=False)
            sw_proc = subprocess.Popen(
                [ide_bin, "switch", "int-alpha"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env={**sw_env, "IDE_FZF_BIN": old_fzf_bin},
            )
            sw_sess_last = wait_until(_sw_ready, timeout=4.0)
            assert sw_sess_last
            os.write(client_mfd, b"\x18")
            assert sw_proc.wait(timeout=5.0) == 0
            sw_proc = None
            assert wait_until(
                lambda: _active_sw_sess() == ""
                and tmux("has-session", "-t", "=int-alpha", check=False).returncode != 0
                and tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "plain-non-ide",
                timeout=3.0,
            ), "Ctrl+x on last IDE session did not close switcher and preserve outer client on plain-non-ide"
            assert client_proc.poll() is None, "Ctrl+x on last IDE session detached outer client while plain-non-ide existed!"
        finally:
            if sw_proc is not None and sw_proc.poll() is None:
                try:
                    os.write(client_mfd, b"\x1bs")
                    sw_proc.wait(timeout=2.0)
                except Exception:
                    sw_proc.kill()
            pump_stop.set()
            pump_thr.join(timeout=2.0)
            if int_alpha_nvim_sock and os.path.exists(int_alpha_nvim_sock):
                subprocess.run(
                    ["nvim", "--headless", "--server", int_alpha_nvim_sock, "--remote-send", "<C-\\><C-n><Cmd>qall!<CR>"],
                    env=base_env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=2,
                    check=False,
                )
            run_cmd([ide_bin, "quit", "--force", "int-alpha", "int-beta", "subb-ws", "subc-ws", "twopane-altn-ws"], env={**base_env, "TMUX": ""}, check=False)

    # (21) Responsive TUI surfaces (80x24 / 100 / 160 status bar, ide list TTY truncation, ide new narrow footer, agy Stop payloads & switcher label state)
    import signal
    from ide_lib.fleet import _parse_hook_metadata, format_switcher_pane_label
    from ide_lib.sessions import _format_new_picker_footer
    from ide_lib.constants import visible_width as _vw_chk

    nt_cancel, msg_cancel = _parse_hook_metadata('{"terminationReason":"USER_CANCELED","fullyIdle":true}', [])
    assert nt_cancel == "user_canceled" and msg_cancel == "", f"unexpected agy cancel parse: {(nt_cancel, msg_cancel)}"
    nt_err, msg_err = _parse_hook_metadata('{"terminationReason":"ERROR","error":"Rate limit reached"}', [])
    assert msg_err == "Rate limit reached", f"unexpected agy error parse: {(nt_err, msg_err)}"
    assert format_switcher_pane_label("ws-a", "agy", "WORKING") == "ws-a · agy · WORKING"
    assert format_switcher_pane_label("ws-a", "agy", "-") == "ws-a · agy"
    assert _format_new_picker_footer(120, True) == " Enter: launch · Alt+n: new · Esc: back to sessions "
    assert _format_new_picker_footer(48, True) == " Enter: launch · Alt+n: new · Esc: back "
    assert _vw_chk(_format_new_picker_footer(28, False)) <= 24

    resp_ws = os.path.join(root, "deeply-nested-workspace-parent", "another-long-segment", "resp-svc")
    os.makedirs(resp_ws, exist_ok=True)
    run_cmd([ide_bin, "--detach", resp_ws], env={**base_env, "TMUX": ""}, check=True)
    try:
        # agy USER_CANCELED on `ide state done` downgrades to IDLE instead of queuing DONE attention
        run_cmd([ide_bin, "state", "running", "resp-svc"], env={**base_env, "TMUX": ""}, check=True)
        p_canc = subprocess.run(
            [ide_bin, "state", "done", "resp-svc"],
            input='{"terminationReason":"USER_CANCELED"}\n',
            text=True,
            env={**base_env, "TMUX": ""},
            capture_output=True,
            check=True,
        )
        assert p_canc.returncode == 0
        assert tmux_out("show-options", "-qv", "-t", "=resp-svc:", "@ide_ai_state") == "idle"
        assert tmux_out("show-options", "-qv", "-t", "=resp-svc:", "@ide_ai_attn") == "0"

        piped_list = run_cmd([ide_bin, "list"], env={**base_env, "TMUX": ""}, check=True).stdout
        narrow_list = run_cmd([ide_bin, "list"], env={**base_env, "TMUX": "", "IDE_LIST_COLUMNS": "76"}, check=True).stdout
        assert "deeply-nested-workspace-parent/another-long-segment/resp-svc" in piped_list, f"piped ide list should not truncate: {piped_list!r}"
        for n_ln in narrow_list.splitlines():
            assert _vw_chk(n_ln) <= 76, f"IDE_LIST_COLUMNS=76 overflowed ({_vw_chk(n_ln)} cols): {n_ln!r}"
        assert any("/resp-svc" in n_ln and "…" in n_ln for n_ln in narrow_list.splitlines()), f"expected preserved /resp-svc basename tail: {narrow_list!r}"

        # Verify 80x24 vs 100x30 client_width status bar tiers on attached PTY client
        r_mfd, r_sfd = pty.openpty()
        fcntl.ioctl(r_sfd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        r_proc = subprocess.Popen(
            ["tmux", "attach-session", "-t", "=resp-svc"],
            stdin=r_sfd,
            stdout=r_sfd,
            stderr=r_sfd,
            env={**base_env, "TMUX": "", "TMUX_PANE": ""},
            close_fds=True,
            preexec_fn=lambda sfd=r_sfd: set_ctty(sfd),
        )
        os.close(r_sfd)
        def _drain_r_pty():
            while select.select([r_mfd], [], [], 0)[0]:
                try:
                    if not os.read(r_mfd, 4096):
                        break
                except OSError:
                    break
        try:
            cl80 = ""
            for _ in range(40):
                _drain_r_pty()
                cl80 = tmux_out("list-clients", "-t", "=resp-svc", "-F", "#{client_name} #{client_width}").strip()
                if cl80.endswith(" 80"):
                    break
                time.sleep(0.05)
            assert cl80.endswith(" 80"), f"expected 80-col client on resp-svc, got {cl80!r}"
            cl80_name = cl80.split()[0]
            wcur_80 = strip_tags(tmux_out("display-message", "-p", "-c", cl80_name, "-t", "=resp-svc:ide", "#{E:window-status-current-format}"))
            sleft_80 = strip_tags(tmux_out("display-message", "-p", "-c", cl80_name, "-t", "=resp-svc:ide", "#{E:status-left}"))
            sright_80 = strip_tags(tmux_out("display-message", "-p", "-c", cl80_name, "-t", "=resp-svc:ide", "#{E:status-right}"))
            assert "(Alt+a)" not in wcur_80 and "(Alt+e)" not in wcur_80 and "(Alt+s)" not in sright_80 and "Help" not in sright_80, (
                f"80-col status bar failed to condense hints: wcur={wcur_80!r} sright={sright_80!r}"
            )
            assert _vw_chk(sleft_80) + _vw_chk(wcur_80) + _vw_chk(sright_80) <= 80, (
                f"80-col status bar overflowed 80 cols: {_vw_chk(sleft_80) + _vw_chk(wcur_80) + _vw_chk(sright_80)}"
            )
            fcntl.ioctl(r_mfd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
            os.kill(r_proc.pid, signal.SIGWINCH)
            for _ in range(40):
                _drain_r_pty()
                if tmux_out("display-message", "-p", "-c", cl80_name, "#{client_width}").strip() == "100":
                    break
                time.sleep(0.05)
            wcur_100 = strip_tags(tmux_out("display-message", "-p", "-c", cl80_name, "-t", "=resp-svc:ide", "#{E:window-status-current-format}"))
            sright_100 = strip_tags(tmux_out("display-message", "-p", "-c", cl80_name, "-t", "=resp-svc:ide", "#{E:status-right}"))
            assert "(Alt+a)" in wcur_100 and "(Alt+e)" in wcur_100 and "(Alt+s)" not in sright_100 and "Help" not in sright_100, (
                f"100-col status bar expected full role tabs + compact right shelf: wcur={wcur_100!r} sright={sright_100!r}"
            )

            # Verify self-session @ide_attn_summary is suppressed in status-right of the active session
            # AND client-focus-in (\x1b[I) auto-acknowledges background done when returning OS focus to AI pane!
            os.write(r_mfd, b"\x1b[O")
            for _ in range(30):
                _drain_r_pty()
                if "focused" not in tmux_out("display-message", "-p", "-c", cl80_name, "#{client_flags}"):
                    break
                time.sleep(0.03)
            tmux("select-pane", "-t", "=resp-svc:ide.1", check=True)
            run_cmd([ide_bin, "state", "done", "resp-svc"], env={**base_env, "TMUX": ""}, check=True)
            assert tmux_out("show-options", "-qv", "-t", "=resp-svc:", "@ide_ai_attn") == "1"
            assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "resp-svc"
            sright_self_attn = strip_tags(tmux_out("display-message", "-p", "-c", cl80_name, "-t", "=resp-svc:ide", "#{E:status-right}"))
            assert "resp-svc" not in sright_self_attn, f"active session status-right should not show self alert: {sright_self_attn!r}"
            os.write(r_mfd, b"\x1b[I")
            for _ in range(40):
                _drain_r_pty()
                if tmux_out("show-options", "-gqv", "@ide_attn_summary") == "":
                    break
                time.sleep(0.05)
            assert tmux_out("show-options", "-qv", "-t", "=resp-svc:", "@ide_ai_attn") in ("", "0") and tmux_out("show-options", "-gqv", "@ide_attn_summary") == "", (
                "client-focus-in (\\x1b[I) did not auto-acknowledge background done on active AI pane!"
            )
        finally:
            try:
                os.close(r_mfd)
            except OSError:
                pass
            r_proc.terminate()
            try:
                r_proc.wait(timeout=2.0)
            except Exception:
                r_proc.kill()
    finally:
        run_cmd([ide_bin, "quit", "--force", "resp-svc"], env={**base_env, "TMUX": ""}, check=False)

    # (22) Workspace creation (`ide new <name>`, `ide_create_workspace`, `$IDE_WORKSPACE_PARENT`, interactive New Workspace PTY card,
    #      `ide _internal dir-preview`, `ide agent [<cli>|restart]`, `Alt+Shift+A` AI parking, and `COPY` bar `a send to AI`)
    stub_agy_22 = os.path.join(bin_dir, "agy")
    stub_claude_22 = os.path.join(bin_dir, "claude")
    stub_codex_22 = os.path.join(bin_dir, "codex")
    for _sb in (stub_agy_22, stub_claude_22, stub_codex_22):
        with open(_sb, "w", encoding="utf-8") as _sbf:
            _sbf.write("#!/bin/sh\nexec sleep 300\n")
        os.chmod(_sb, 0o755)

    # 22a. Default `mkdir` under $HOME and under $IDE_WORKSPACE_PARENT + `..` traversal rejection
    r_trav = run_cmd([ide_bin, "new", "-d", "../escape-attempt"], env={**base_env, "TMUX": ""}, check=False)
    assert r_trav.returncode != 0 and (".." in r_trav.stderr or "outside" in r_trav.stderr), f"expected .. traversal rejection: {r_trav}"

    def_created_ws = os.path.join(thome, "mkdir-home-ws")
    assert not os.path.exists(def_created_ws)
    run_cmd([ide_bin, "new", "-d", "mkdir-home-ws"], env={**base_env, "TMUX": "", "IDE_LINK_RULES": os.path.join(root, "no_rules.sh")}, check=True)
    assert os.path.isdir(def_created_ws) and tmux("has-session", "-t", "=mkdir-home-ws", check=False).returncode == 0

    custom_parent = os.path.join(root, "custom-ws-parent")
    os.makedirs(custom_parent, exist_ok=True)
    parent_created_ws = os.path.join(custom_parent, "parent-child-ws")
    run_cmd(
        [ide_bin, "-n", "-d", "--2pane", "--agent", "claude", "parent-child-ws"],
        env={**base_env, "TMUX": "", "IDE_WORKSPACE_PARENT": custom_parent, "IDE_LINK_RULES": os.path.join(root, "no_rules.sh")},
        check=True,
    )
    assert os.path.isdir(parent_created_ws) and tmux("has-session", "-t", "=parent-child-ws", check=False).returncode == 0
    assert tmux_out("show-options", "-qv", "-t", "=parent-child-ws:", "@ide_layout_mode") == "2pane"
    assert tmux_out("show-options", "-qv", "-t", "=parent-child-ws:", "@ide_ai_cli") == "claude"

    # Comment-only `ide_create_workspace` in links.sh falls back to `mkdir` rather than failing
    comment_rules = os.path.join(root, "comment_create_rules.sh")
    with open(comment_rules, "w", encoding="utf-8") as crf:
        crf.write("# Optional hook: ide_create_workspace NAME\n")
    comment_ws = os.path.join(custom_parent, "comment-fb-ws")
    run_cmd(
        [ide_bin, "new", "-d", "comment-fb-ws"],
        env={**base_env, "TMUX": "", "IDE_WORKSPACE_PARENT": custom_parent, "IDE_LINK_RULES": comment_rules},
        check=True,
    )
    assert os.path.isdir(comment_ws) and tmux("has-session", "-t", "=comment-fb-ws", check=False).returncode == 0

    # 22b. Real `ide_create_workspace NAME` hook (multi-line stdout progress + failure handling)
    hook_root = os.path.join(root, "hook-provisioned")
    os.makedirs(hook_root, exist_ok=True)
    hook_rules = os.path.join(root, "create_hook_rules.sh")
    hook_arg_log = os.path.join(root, "create_hook_arg.log")
    with open(hook_rules, "w", encoding="utf-8") as hrf:
        hrf.write(
            "ide_create_workspace() {\n"
            f"  printf '%s\\n' \"$1\" >> {shlex.quote(hook_arg_log)}\n"
            "  if [ \"$1\" = \"fail-ws\" ]; then\n"
            "    echo 'Simulated VCS provisioning error' >&2\n"
            "    return 1\n"
            "  fi\n"
            "  echo 'Provisioning workspace checkout...'\n"
            f"  d={shlex.quote(hook_root)}/\"$1\"\n"
            "  mkdir -p \"$d/src\"\n"
            "  printf '%s\\n' \"$d\"\n"
            "}\n"
        )
    r_hook_fail = run_cmd([ide_bin, "new", "-d", "fail-ws"], env={**base_env, "TMUX": "", "IDE_LINK_RULES": hook_rules}, check=False)
    assert r_hook_fail.returncode != 0 and "Simulated VCS provisioning error" in r_hook_fail.stderr, f"expected hook error: {r_hook_fail}"
    assert not os.path.exists(os.path.join(thome, "fail-ws")) and tmux("has-session", "-t", "=fail-ws", check=False).returncode != 0

    run_cmd([ide_bin, "new", "-d", "hooked-ws"], env={**base_env, "TMUX": "", "IDE_LINK_RULES": hook_rules}, check=True)
    assert os.path.isdir(os.path.join(hook_root, "hooked-ws", "src"))
    assert tmux("has-session", "-t", "=hooked-ws", check=False).returncode == 0
    assert tmux_out("show-options", "-qv", "-t", "=hooked-ws:", "@ide_workdir") == os.path.realpath(os.path.join(hook_root, "hooked-ws"))
    assert open(hook_arg_log, encoding="utf-8").read().splitlines() == ["fail-ws", "hooked-ws"]

    # 22c. Interactive PTY test of `ide new` (`New IDE Workspace` card: Tab cycles agent agy->claude, Alt+2 toggles 2pane, Backspace edits name)
    pty_new_m, pty_new_s = pty.openpty()
    fcntl.ioctl(pty_new_s, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    p_new_pty = subprocess.Popen(
        [ide_bin, "new", "-d"],
        stdin=pty_new_s,
        stdout=pty_new_s,
        stderr=pty_new_s,
        env={**base_env, "TMUX": "", "TMUX_PANE": "", "IDE_WORKSPACE_PARENT": custom_parent, "IDE_LINK_RULES": os.path.join(root, "no_rules.sh")},
        close_fds=True,
        preexec_fn=lambda sfd=pty_new_s: set_ctty(sfd),
    )
    os.close(pty_new_s)
    pty_new_buf = bytearray()
    try:
        dl_new = time.monotonic() + 3.0
        while time.monotonic() < dl_new and b"New IDE >" not in pty_new_buf:
            if select.select([pty_new_m], [], [], 0.05)[0]:
                pty_new_buf.extend(os.read(pty_new_m, 4096))
        assert b"New IDE >" in pty_new_buf, f"expected New IDE > card in PTY: {pty_new_buf!r}"
        # Type "pty-x\x7fws" -> "pty-ws", Tab (agy -> claude), Alt+2 (3pane -> 2pane), Enter
        os.write(pty_new_m, b"pty-x\x7fws\t\x1b2\r")
        dl_fin = time.monotonic() + 5.0
        while time.monotonic() < dl_fin and p_new_pty.poll() is None:
            if select.select([pty_new_m], [], [], 0.05)[0]:
                try:
                    pty_new_buf.extend(os.read(pty_new_m, 4096))
                except OSError:
                    break
        assert p_new_pty.wait(timeout=3.0) == 0, f"interactive ide new PTY failed: {pty_new_buf!r}"
    finally:
        try:
            os.close(pty_new_m)
        except OSError:
            pass
    assert os.path.isdir(os.path.join(custom_parent, "pty-ws"))
    assert tmux("has-session", "-t", "=pty-ws", check=False).returncode == 0
    assert tmux_out("show-options", "-qv", "-t", "=pty-ws:", "@ide_ai_cli") == "claude"
    assert tmux_out("show-options", "-qv", "-t", "=pty-ws:", "@ide_layout_mode") == "2pane"

    # 22d. `ide _internal dir-preview` active badge, contents, 80x24 width clamping, IDE_NERD_FONTS=0, and NO_COLOR
    open(os.path.join(parent_created_ws, "README.md"), "w", encoding="utf-8").write("# Demo\n")
    dp_out = run_cmd(
        [ide_bin, "_internal", "dir-preview", "--", parent_created_ws],
        env={**base_env, "TMUX": "", "FZF_PREVIEW_COLUMNS": "44", "FZF_PREVIEW_LINES": "14", "IDE_NERD_FONTS": "0", "NO_COLOR": "1"},
        check=True,
    ).stdout
    assert "parent-child-ws" in dp_out and "active: claude" in dp_out and "README.md" in dp_out and "\x1b[" not in dp_out, f"bad dir-preview: {dp_out!r}"
    for dp_ln in dp_out.splitlines():
        assert _vw_chk(dp_ln) <= 44, f"dir-preview overflowed 44 cols: {dp_ln!r}"

    # 22e. `ide agent [<cli>|restart] <sess>`, `Alt+Shift+A` AI parking, and `COPY` mode `a send to AI` top-bar hint
    run_cmd([ide_bin, "state", "quota", "mkdir-home-ws"], env={**base_env, "TMUX": ""}, check=True)
    assert tmux_out("show-options", "-qv", "-t", "=mkdir-home-ws:", "@ide_ai_state") == "quota"
    run_cmd([ide_bin, "agent", "codex", "mkdir-home-ws"], env={**base_env, "TMUX": ""}, check=True)
    assert tmux_out("show-options", "-qv", "-t", "=mkdir-home-ws:", "@ide_ai_cli") == "codex"
    assert tmux_out("show-options", "-qv", "-t", "=mkdir-home-ws:", "@ide_ai_state") == ""
    run_cmd([ide_bin, "agent", "restart", "mkdir-home-ws"], env={**base_env, "TMUX": ""}, check=True)
    assert tmux_out("show-options", "-qv", "-t", "=mkdir-home-ws:", "@ide_ai_cli") == "codex"

    # Park & unpark AI pane via `ide _internal park ai` (`Alt+Shift+A`) + verify COPY mode `status-right` hint
    run_cmd([ide_bin, "_internal", "park", "ai", "mkdir-home-ws"], env={**base_env, "TMUX": ""}, check=True)
    assert tmux_out("show-options", "-qv", "-t", "=mkdir-home-ws:", "@ide_ai_parked") == "1"
    run_cmd([ide_bin, "_internal", "park", "ai", "mkdir-home-ws"], env={**base_env, "TMUX": ""}, check=True)
    assert tmux_out("show-options", "-qv", "-t", "=mkdir-home-ws:", "@ide_ai_parked") == "0"
    ed_p_mk = tmux_out("show-options", "-qv", "-t", "=mkdir-home-ws:", "@ide_editor_pane").strip()
    tmux("copy-mode", "-t", ed_p_mk, check=True)
    sright_copy = strip_tags(tmux_out("display-message", "-p", "-t", ed_p_mk, "#{E:status-right}"))
    assert "a send to AI" in sright_copy, f"COPY mode status-right missing 'a send to AI': {sright_copy!r}"
    tmux("send-keys", "-t", ed_p_mk, "-X", "cancel", check=True)

    run_cmd(
        [ide_bin, "quit", "--force", "mkdir-home-ws", "parent-child-ws", "comment-fb-ws", "hooked-ws", "pty-ws"],
        env={**base_env, "TMUX": ""},
        check=False,
    )

    print("ALL_FLEET_OK")
finally:
    for mfd in (client2_mfd, client_mfd):
        if mfd is not None:
            try:
                os.close(mfd)
            except OSError:
                pass
    for cproc in (client2_proc, client_proc):
        if cproc is not None:
            try:
                cproc.terminate()
                cproc.wait(timeout=2.0)
            except Exception:
                try:
                    cproc.kill()
                except Exception:
                    pass
    try:
        if xdg_run and os.path.isdir(xdg_run) and shutil.which("nvim"):
            for fn in os.listdir(xdg_run):
                if fn.endswith(".sock"):
                    sp = os.path.join(xdg_run, fn)
                    subprocess.run(
                        ["nvim", "--headless", "--server", sp, "--remote-send", "<C-\\><C-n><Cmd>qall!<CR>"],
                        env=base_env,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=2,
                        check=False,
                    )
    except Exception:
        pass
    try:
        _sock_cleanup = os.path.join(tmux_tmp, f"tmux-{os.getuid()}", "default")
        subprocess.run(
            ["tmux", "-S", _sock_cleanup, "kill-server"],
            env={**(base_env or os.environ), "TMUX": "", "TMUX_PANE": ""},
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except Exception:
        pass
    shutil.rmtree(tmux_tmp, ignore_errors=True)
    shutil.rmtree(root, ignore_errors=True)
PY
    )" || true
    if grep -Fq "ALL_FLEET_OK" <<< "$FLEET_TEST_OUT"; then
        pass "bin/ide multi-session workspace switcher (list [--plain|--json], lazy-docking -s/switch popup & fzf ctrl-a/e/t/ctrl-x/alt-s/F1/F5, _internal session-preview, scroll & cursor preservation, 90-col & 4-tier mono-tui degradation), deterministic hook-only AI lifecycle (state, FIFO next, Alt+Shift+S, stale-hook SHELL guard, parked AI preservation, zero-shift top-bar tinting), and context dispatch (send)"
    else
        fail "bin/ide multi-session workspace switcher & lifecycle suite" "Suite failed: $FLEET_TEST_OUT"
    fi
fi

test_summary
