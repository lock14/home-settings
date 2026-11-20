"""Process-tree inspection (`/proc` and `ps`) and Editor pane Neovim socket discovery."""

from __future__ import annotations

import os
import re
import stat
import subprocess

from ide_lib.constants import is_live_socket, which_executable

_BARE_SHELL_CMD_RE = re.compile(
    r"^-?(?:(?:ba|z|da|k|mk|a|tc|c|fi)?sh|nu|elvish|xonsh|pwsh)$",
    re.IGNORECASE,
)


def pids_with_children(pids: set[int], *, force_ps: bool = False) -> set[int]:
    """Return the subset of `pids` that currently own at least one live child process."""
    if not pids:
        return set()
    found: set[int] = set()
    my_pid = os.getpid()
    if not force_ps and os.path.isfile(f"/proc/{my_pid}/task/{my_pid}/children"):
        for pid in pids:
            task_dir = f"/proc/{pid}/task"
            try:
                tids = os.listdir(task_dir)
            except OSError:
                continue
            for tid in tids:
                try:
                    with open(f"{task_dir}/{tid}/children", "r", encoding="utf-8") as fh:
                        if fh.read().strip():
                            found.add(pid)
                            break
                except OSError:
                    continue
        return found

    if not force_ps and os.path.isfile("/proc/stat"):
        try:
            for entry in os.listdir("/proc"):
                if not entry.isdigit():
                    continue
                try:
                    with open(f"/proc/{entry}/stat", "r", encoding="utf-8", errors="replace") as fh:
                        stat_txt = fh.read()
                except OSError:
                    continue
                rparen = stat_txt.rfind(")")
                if rparen < 0:
                    continue
                fields = stat_txt[rparen + 2:].split(None, 2)
                if len(fields) >= 2 and fields[1].isdigit():
                    ppid = int(fields[1])
                    if ppid in pids:
                        found.add(ppid)
                        if len(found) == len(pids):
                            break
            return found
        except OSError:
            pass

    ps_bin = which_executable("ps") or ("/bin/ps" if os.path.isfile("/bin/ps") else "ps")
    try:
        res = subprocess.run(
            [ps_bin, "-eo", "ppid="],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=2.0,
            check=False,
        )
        if res.returncode == 0 and res.stdout:
            for tok in res.stdout.split():
                if tok.isdigit():
                    ppid = int(tok)
                    if ppid in pids:
                        found.add(ppid)
    except (OSError, subprocess.SubprocessError):
        pass
    return found


def is_bare_shell_cmd(cmd: str) -> bool:
    """Return True if `cmd` names an interactive shell rather than a direct foreground binary."""
    s = os.path.basename(cmd.strip())
    return not s or bool(_BARE_SHELL_CMD_RE.match(s))


def pane_has_child_procs(pane_pid: str, pane_cmd: str = "") -> bool:
    """Return True if an AI pane is running a foreground CLI (either via `exec` or child process)."""
    p = pane_pid.strip()
    if not p.isdigit():
        return False
    pid = int(p)
    if pid <= 0:
        return False
    if pane_cmd.strip() and not is_bare_shell_cmd(pane_cmd):
        return True
    return pid in pids_with_children({pid})


def _read_proc_state_and_ppid(pid: int) -> tuple[str, str, int]:
    try:
        with open(f"/proc/{pid}/stat", "r", encoding="utf-8", errors="replace") as fh:
            stat_txt = fh.read()
    except OSError:
        return ("", "", 0)
    lparen = stat_txt.find("(")
    rparen = stat_txt.rfind(")")
    if lparen < 0 or rparen < lparen:
        return ("", "", 0)
    comm = stat_txt[lparen + 1:rparen]
    fields = stat_txt[rparen + 2:].split(None, 2)
    if not fields:
        return (comm, "", 0)
    st_ch = fields[0]
    ppid = int(fields[1]) if len(fields) >= 2 and fields[1].isdigit() else 0
    return (comm, st_ch, ppid)


def _pane_tree_snapshot(
    pane_pid: str,
    max_pids: int = 64,
    *,
    force_ps: bool = False,
) -> tuple[list[int], dict[int, int], dict[int, str], dict[int, str]]:
    p = pane_pid.strip()
    if not p.isdigit():
        return ([], {}, {}, {})
    root = int(p)
    if root <= 0:
        return ([], {}, {}, {})
    parent_by_pid: dict[int, int] = {}
    state_by_pid: dict[int, str] = {}
    comm_by_pid: dict[int, str] = {}
    my_pid = os.getpid()
    if not force_ps and os.path.isfile(f"/proc/{my_pid}/task/{my_pid}/children"):
        order = [root]
        seen = {root}
        cm0, st0, _ = _read_proc_state_and_ppid(root)
        if cm0:
            comm_by_pid[root] = cm0
        if st0:
            state_by_pid[root] = st0
        idx = 0
        while idx < len(order) and len(order) < max_pids:
            cur = order[idx]
            idx += 1
            task_dir = f"/proc/{cur}/task"
            try:
                tids = sorted(os.listdir(task_dir))
            except OSError:
                continue
            for tid in tids:
                try:
                    with open(f"{task_dir}/{tid}/children", "r", encoding="utf-8") as fh:
                        raw_children = fh.read().split()
                except OSError:
                    continue
                for tok in raw_children:
                    if tok.isdigit():
                        cpid = int(tok)
                        if cpid > 0 and cpid not in seen:
                            seen.add(cpid)
                            parent_by_pid[cpid] = cur
                            cmc, stc, _ = _read_proc_state_and_ppid(cpid)
                            if cmc:
                                comm_by_pid[cpid] = cmc
                            if stc:
                                state_by_pid[cpid] = stc
                            order.append(cpid)
                            if len(order) >= max_pids:
                                break
                if len(order) >= max_pids:
                    break
        return (order, parent_by_pid, state_by_pid, comm_by_pid)

    children_by_ppid: dict[int, list[int]] = {}
    if not force_ps and os.path.isfile("/proc/stat"):
        try:
            for entry in os.listdir("/proc"):
                if not entry.isdigit():
                    continue
                cpid = int(entry)
                cm_ch, st_ch, ppid = _read_proc_state_and_ppid(cpid)
                if cm_ch:
                    comm_by_pid[cpid] = cm_ch
                if st_ch:
                    state_by_pid[cpid] = st_ch
                if ppid > 0:
                    children_by_ppid.setdefault(ppid, []).append(cpid)
        except OSError:
            children_by_ppid.clear()
            state_by_pid.clear()
            comm_by_pid.clear()

    if not children_by_ppid:
        ps_bin = which_executable("ps") or ("/bin/ps" if os.path.isfile("/bin/ps") else "ps")
        try:
            res = subprocess.run(
                [ps_bin, "-eo", "pid=,ppid=,stat=,comm="],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=2.0,
                check=False,
            )
            if res.returncode != 0 or not res.stdout:
                res = subprocess.run(
                    [ps_bin, "-eo", "pid=,ppid="],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                    timeout=2.0,
                    check=False,
                )
            if res.returncode == 0 and res.stdout:
                for line in res.stdout.splitlines():
                    parts = line.split(None, 3)
                    if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
                        cpid = int(parts[0])
                        ppid = int(parts[1])
                        children_by_ppid.setdefault(ppid, []).append(cpid)
                        if len(parts) >= 3:
                            state_by_pid[cpid] = parts[2]
                        if len(parts) >= 4:
                            comm_by_pid[cpid] = os.path.basename(parts[3].strip())
        except (OSError, subprocess.SubprocessError):
            pass

    order = [root]
    seen = {root}
    idx = 0
    while idx < len(order) and len(order) < max_pids:
        cur = order[idx]
        idx += 1
        for cpid in sorted(children_by_ppid.get(cur, ())):
            if cpid > 0 and cpid not in seen:
                seen.add(cpid)
                parent_by_pid[cpid] = cur
                order.append(cpid)
                if len(order) >= max_pids:
                    break
    return (order, parent_by_pid, state_by_pid, comm_by_pid)


def pane_tree_pids(pane_pid: str, max_pids: int = 64) -> list[int]:
    """Return `[root_pid, ...]` in breadth-first descendant order for `pane_pid`."""
    return _pane_tree_snapshot(pane_pid, max_pids=max_pids)[0]


def _read_proc_nvim_env(pid: int) -> tuple[str, str, str]:
    try:
        with open(f"/proc/{pid}/environ", "rb") as fh:
            raw = fh.read(262144)
    except OSError:
        return ("", "", "")
    listen_addr = ""
    xdg_rt = ""
    tmpdir = ""
    for entry in raw.split(b"\x00"):
        if entry.startswith(b"NVIM_LISTEN_ADDRESS="):
            listen_addr = entry[20:].decode("utf-8", errors="surrogateescape").strip()
        elif entry.startswith(b"XDG_RUNTIME_DIR="):
            xdg_rt = entry[16:].decode("utf-8", errors="surrogateescape").strip()
        elif entry.startswith(b"TMPDIR="):
            tmpdir = entry[7:].decode("utf-8", errors="surrogateescape").strip()
    return (listen_addr, xdg_rt, tmpdir)


def _parse_nvim_argv_flags(args: list[str]) -> tuple[bool, list[str]]:
    if not args:
        return (False, [])
    is_headless = "--headless" in args
    listen_paths: list[str] = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--":
            break
        if arg == "--listen" and i + 1 < len(args):
            val = args[i + 1].strip()
            if val.startswith("/"):
                listen_paths.append(val)
            i += 2
            continue
        if arg.startswith("--listen="):
            val = arg[9:].strip()
            if val.startswith("/"):
                listen_paths.append(val)
        i += 1
    return (is_headless, listen_paths)


def _read_proc_nvim_cmdline(pid: int) -> tuple[bool, list[str]] | None:
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            raw = fh.read(65536)
    except OSError:
        return None
    if not raw:
        return (False, [])
    args = [tok.decode("utf-8", errors="surrogateescape") for tok in raw.split(b"\x00") if tok]
    return _parse_nvim_argv_flags(args)


def _ps_batch_nvim_cmdlines(pids: list[int]) -> dict[int, tuple[bool, list[str]]]:
    if not pids:
        return {}
    import shlex

    ps_bin = which_executable("ps") or ("/bin/ps" if os.path.isfile("/bin/ps") else "ps")
    pid_csv = ",".join(str(p) for p in pids)
    try:
        res = subprocess.run(
            [ps_bin, "-ww", "-o", "pid=,args=", "-p", pid_csv],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=2.0,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return {}
    if res.returncode != 0 or not res.stdout:
        return {}
    out: dict[int, tuple[bool, list[str]]] = {}
    for line in res.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0].isdigit():
            pid = int(parts[0])
            try:
                argv = shlex.split(parts[1], posix=True)
            except ValueError:
                argv = parts[1].split()
            out[pid] = _parse_nvim_argv_flags(argv)
    return out


def _is_stopped_or_zombie_state(st: str) -> bool:
    return bool(st) and st[0] in ("T", "t", "Z", "X")


def _is_nvim_comm_name(comm: str) -> bool:
    base = os.path.basename(comm)
    return base == "nvim" or base.startswith("nvim.") or base.startswith("nvim-")


def discover_pane_nvim_sockets(pane_pid: str, sock_hint: str = "", *, force_ps: bool = False) -> list[str]:
    """Discover live ephemeral Neovim sockets belonging to processes inside `pane_pid`'s tree."""
    raw_pids, parent_by_pid, state_by_pid, comm_by_pid = _pane_tree_snapshot(pane_pid, force_ps=force_ps)
    if not raw_pids:
        return []

    cand_entries: list[tuple[int, int, int]] = []
    for bfs_idx, cpid in enumerate(raw_pids):
        if _is_stopped_or_zombie_state(state_by_pid.get(cpid, "")):
            continue
        stopped_anc = False
        nested_under_nvim = False
        imm_parent = parent_by_pid.get(cpid)
        anc = imm_parent
        seen_anc: set[int] = set()
        while anc is not None and anc not in seen_anc:
            seen_anc.add(anc)
            if _is_stopped_or_zombie_state(state_by_pid.get(anc, "")):
                stopped_anc = True
            if anc != imm_parent and _is_nvim_comm_name(comm_by_pid.get(anc, "")):
                nested_under_nvim = True
                break
            anc = parent_by_pid.get(anc)
        if nested_under_nvim:
            continue
        cand_entries.append((1 if stopped_anc else 0, bfs_idx, cpid))

    if not cand_entries:
        return []

    cmdline_by_pid: dict[int, tuple[bool, list[str]]] = {}
    need_ps_pids: list[int] = []
    for _, _, cpid in cand_entries:
        proc_cmd = None if force_ps else _read_proc_nvim_cmdline(cpid)
        if proc_cmd is not None:
            cmdline_by_pid[cpid] = proc_cmd
        else:
            need_ps_pids.append(cpid)
    if need_ps_pids:
        ps_cmds = _ps_batch_nvim_cmdlines(need_ps_pids)
        for cpid in need_ps_pids:
            cmdline_by_pid[cpid] = ps_cmds.get(cpid, (False, []))

    ranked = [
        (1 if cmdline_by_pid.get(cpid, (False, []))[0] else 0, stopped_flag, bfs_idx, cpid)
        for stopped_flag, bfs_idx, cpid in cand_entries
    ]
    ranked.sort()
    pids = [item[3] for item in ranked]

    import getpass
    from pathlib import Path

    try:
        uid: int | None = os.getuid()
    except AttributeError:
        uid = None
    try:
        nvim_user = os.environ.get("USER", "").strip() or getpass.getuser()
    except Exception:
        nvim_user = ""

    excl_abs = os.path.abspath(sock_hint) if sock_hint else ""
    excl_real = os.path.realpath(sock_hint) if sock_hint else ""
    excl_inode: tuple[int, int] | None = None
    if sock_hint:
        try:
            hst = os.stat(sock_hint)
            excl_inode = (hst.st_dev, hst.st_ino)
        except OSError:
            excl_inode = None
    sock_dir = os.path.dirname(excl_abs) if excl_abs else ""
    sock_real_dir = os.path.dirname(excl_real) if excl_real else ""
    env_xdg_rt = os.environ.get("XDG_RUNTIME_DIR", "").strip()
    env_tmp = os.environ.get("TMPDIR", "").strip()
    darwin_tmp = ""
    if hasattr(os, "confstr"):
        try:
            darwin_tmp = (os.confstr("CS_DARWIN_USER_TEMP_DIR") or "").strip()
        except (ValueError, OSError):
            darwin_tmp = ""
    run_uid_dir = f"/run/user/{uid}" if uid is not None else ""

    found: list[str] = []
    seen_paths: set[str] = set()
    seen_inodes: set[tuple[int, int]] = set()

    def _accept(cand_raw: str) -> None:
        if not cand_raw or ":" in os.path.basename(cand_raw):
            return
        cand_abs = os.path.abspath(cand_raw)
        cand_real = os.path.realpath(cand_raw)
        if cand_abs in (excl_abs, excl_real) or cand_real in (excl_abs, excl_real):
            return
        if cand_real in seen_paths or cand_abs in seen_paths:
            return
        try:
            st = os.stat(cand_raw)
        except OSError:
            return
        if not stat.S_ISSOCK(st.st_mode):
            return
        if uid is not None and st.st_uid != uid:
            return
        ino_key = (st.st_dev, st.st_ino)
        if excl_inode is not None and ino_key == excl_inode:
            return
        if ino_key in seen_inodes:
            return
        if not is_live_socket(cand_raw):
            return
        seen_paths.add(cand_real)
        seen_paths.add(cand_abs)
        seen_inodes.add(ino_key)
        found.append(cand_raw)

    for cpid in pids:
        _, cmd_lpaths = cmdline_by_pid.get(cpid, (False, []))
        for lp in cmd_lpaths:
            _accept(lp)
        proc_listen, proc_xdg_rt, proc_tmp = _read_proc_nvim_env(cpid)
        if proc_listen and proc_listen.startswith("/"):
            _accept(proc_listen)

        seen_rt: set[str] = set()
        for rt_d in (proc_xdg_rt, sock_dir, sock_real_dir, env_xdg_rt, run_uid_dir):
            if not rt_d:
                continue
            rt_real = os.path.realpath(rt_d)
            if rt_real in seen_rt or not os.path.isdir(rt_d):
                continue
            seen_rt.add(rt_real)
            try:
                for p in sorted(Path(rt_d).glob(f"nvim.{cpid}.*")):
                    _accept(str(p))
            except OSError:
                pass

        seen_tmp: set[str] = set()
        for tmp_d in (proc_tmp, sock_dir, sock_real_dir, env_tmp, darwin_tmp, "/tmp"):
            if not tmp_d:
                continue
            tmp_real = os.path.realpath(tmp_d)
            if tmp_real in seen_tmp or not os.path.isdir(tmp_d):
                continue
            seen_tmp.add(tmp_real)
            try:
                for p in sorted(Path(tmp_d).glob(f"nvim.{cpid}.*")):
                    _accept(str(p))
            except OSError:
                pass
            if nvim_user:
                user_nvim_dir = Path(tmp_d) / f"nvim.{nvim_user}"
                if user_nvim_dir.is_dir():
                    for pat in (f"nvim.{cpid}.*", f"*/nvim.{cpid}.*"):
                        try:
                            for p in sorted(user_nvim_dir.glob(pat)):
                                _accept(str(p))
                        except OSError:
                            pass

    if not found and os.path.isfile("/proc/net/unix"):
        by_pid: dict[int, list[str]] = {}
        pid_set = set(pids)
        try:
            with open("/proc/net/unix", "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if "nvim." not in line:
                        continue
                    parts = line.split()
                    if not parts:
                        continue
                    spath = parts[-1]
                    if not spath.startswith("/"):
                        continue
                    bname = os.path.basename(spath)
                    if bname.startswith("nvim."):
                        bparts = bname.split(".")
                        if len(bparts) >= 3 and bparts[1].isdigit():
                            mpid = int(bparts[1])
                            if mpid in pid_set:
                                by_pid.setdefault(mpid, []).append(spath)
        except OSError:
            pass
        for cpid in pids:
            for spath in sorted(by_pid.get(cpid, ())):
                _accept(spath)

    return found
