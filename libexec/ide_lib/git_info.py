"""Zero-fork `.git` layout discovery, `.git/config` PR/MR badge resolver, and VCS status."""

from __future__ import annotations

import os
import re
import shutil
import stat
import subprocess

from ide_lib.constants import sanitize_http_url
from ide_lib.hooks import call_ide_hook

_RE_PULL_MERGE_REF = re.compile(
    r"^refs/(?:(pull)/([1-9][0-9]*)/head|(merge-requests)/([1-9][0-9]*)/head|(pull-requests)/([1-9][0-9]*)/(?:from|head))$"
)


def locate_git_dirs(workdir: str) -> tuple[str, str, str]:
    """Walk upward within the same filesystem device to locate `(worktree_root, gitdir, commondir)`."""
    if not workdir:
        return ("", "", "")
    cur = os.path.abspath(workdir)
    try:
        start_dev = os.stat(cur).st_dev
    except OSError:
        return ("", "", "")

    worktree_root = ""
    gitdir = ""
    while True:
        dot_git = os.path.join(cur, ".git")
        try:
            st = os.stat(dot_git)
        except OSError:
            st = None
        if st is not None:
            if stat.S_ISDIR(st.st_mode):
                worktree_root = cur
                gitdir = dot_git
                break
            if stat.S_ISREG(st.st_mode):
                try:
                    with open(dot_git, "r", encoding="utf-8", errors="replace") as fh:
                        first_line = fh.readline().strip()
                except OSError:
                    first_line = ""
                if first_line.lower().startswith("gitdir:"):
                    gd_raw = first_line.split(":", 1)[1].strip()
                    if gd_raw:
                        gitdir = gd_raw if os.path.isabs(gd_raw) else os.path.normpath(os.path.join(cur, gd_raw))
                        worktree_root = cur
                        break
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        try:
            if os.stat(parent).st_dev != start_dev:
                break
        except OSError:
            break
        cur = parent

    if not gitdir:
        return ("", "", "")

    commondir = gitdir
    commondir_file = os.path.join(gitdir, "commondir")
    if os.path.isfile(commondir_file):
        try:
            with open(commondir_file, "r", encoding="utf-8", errors="replace") as fh:
                common_rel = fh.readline().strip().rstrip("/")
        except OSError:
            common_rel = ""
        if common_rel and common_rel != ".":
            commondir = (
                common_rel
                if os.path.isabs(common_rel)
                else os.path.normpath(os.path.join(gitdir, common_rel))
            )
    return (worktree_root, gitdir, commondir)


def build_forge_pr_url(raw_url: str, pr_num: str, forge_hint: str = "") -> str:
    """Construct a pull or merge request URL across GitHub, GitLab, Bitbucket, and Gitea/Forgejo/Codeberg."""
    if not raw_url or not pr_num.isdigit() or int(pr_num) <= 0:
        return ""
    scheme = "https"
    rest = raw_url.strip()
    has_scheme = False
    is_http = False
    if rest.startswith("http://"):
        scheme = "http"
        rest = rest[len("http://"):]
        has_scheme = True
        is_http = True
    elif rest.startswith("https://"):
        scheme = "https"
        rest = rest[len("https://"):]
        has_scheme = True
        is_http = True
    elif rest.startswith(("ssh://", "git://", "git+ssh://")):
        rest = rest.split("://", 1)[1]
        has_scheme = True
    elif rest.startswith("file://"):
        rest = "localhost/" + rest[len("file://"):]
        has_scheme = True
    elif rest.startswith("/"):
        rest = "localhost" + rest
        has_scheme = True

    host = ""
    repo_path = ""
    if has_scheme:
        if "/" not in rest:
            return ""
        host, repo_path = rest.split("/", 1)
        if "@" in host:
            host = host.rsplit("@", 1)[1]
        if not is_http and ":" in host and not host.endswith("]"):
            host = host.rsplit(":", 1)[0]
    elif ":" in rest and ("/" not in rest or "/" not in rest.split(":", 1)[0]):
        host, repo_path = rest.split(":", 1)
        if "@" in host:
            host = host.rsplit("@", 1)[1]
    elif "/" in rest:
        host, repo_path = rest.split("/", 1)
        if "@" in host:
            host = host.rsplit("@", 1)[1]
    else:
        return ""

    repo_path = repo_path.strip("/")
    if repo_path.endswith(".git"):
        repo_path = repo_path[:-4].rstrip("/")
    if not host or not repo_path:
        return ""

    host_l = host.lower()
    forge = forge_hint.strip().lower()
    if not forge:
        if "github" in host_l:
            forge = "github"
        elif "gitlab" in host_l:
            forge = "gitlab"
        elif host_l == "bitbucket.org":
            forge = "bitbucket-cloud"
        elif "bitbucket" in host_l or "stash" in host_l:
            forge = "bitbucket-server"
        elif any(k in host_l for k in ("codeberg", "gitea", "forgejo")):
            forge = "gitea"
        else:
            forge = "github"

    if forge == "gitlab":
        return f"{scheme}://{host}/{repo_path}/-/merge_requests/{pr_num}"
    if forge in ("bitbucket-cloud", "bitbucket_cloud"):
        return f"https://bitbucket.org/{repo_path}/pull-requests/{pr_num}"
    if forge in ("bitbucket-server", "bitbucket_server", "bitbucket-dc", "stash"):
        bb_path = repo_path[4:] if repo_path.startswith("scm/") else repo_path
        if "/scm/" in bb_path:
            bb_path = bb_path.split("/scm/", 1)[1]
        if "/" in bb_path:
            rem_part, repo = bb_path.rsplit("/", 1)
            proj = rem_part.rsplit("/", 1)[-1]
        else:
            proj = bb_path
            repo = bb_path
        if proj.startswith("~"):
            return f"{scheme}://{host}/users/{proj[1:]}/repos/{repo}/pull-requests/{pr_num}"
        return f"{scheme}://{host}/projects/{proj.upper()}/repos/{repo}/pull-requests/{pr_num}"
    if forge in ("gitea", "forgejo", "codeberg"):
        return f"{scheme}://{host}/{repo_path}/pulls/{pr_num}"
    return f"{scheme}://{host}/{repo_path}/pull/{pr_num}"


def _unescape_git_cfg_str(raw: str) -> str:
    out: list[str] = []
    i = 0
    n = len(raw)
    while i < n:
        ch = raw[i]
        if ch == "\\" and i + 1 < n:
            nxt = raw[i + 1]
            out.append({"n": "\n", "t": "\t", "b": "\b"}.get(nxt, nxt))
            i += 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def _parse_git_section_header(s: str) -> tuple[str, str] | None:
    if not s.startswith("["):
        return None
    in_quote = False
    close_idx = -1
    i = 1
    n = len(s)
    while i < n:
        ch = s[i]
        if in_quote:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == '"':
                in_quote = False
        else:
            if ch == '"':
                in_quote = True
            elif ch == "]":
                close_idx = i
                break
        i += 1
    if close_idx < 0:
        return None
    rem = s[close_idx + 1:].strip()
    if rem and rem[0] not in ("#", ";"):
        return None
    hdr = s[1:close_idx].strip()
    if '"' in hdr:
        q_start = hdr.index('"')
        q_end = hdr.rfind('"')
        if q_end <= q_start:
            return None
        sec_type = hdr[:q_start].strip().lower()
        sec_name = _unescape_git_cfg_str(hdr[q_start + 1:q_end])
        return (sec_type, sec_name)
    if "." in hdr:
        sec_type, sec_name = hdr.split(".", 1)
        return (sec_type.strip().lower(), sec_name.strip())
    return (hdr.lower(), "")


def _parse_git_cfg_value(v_raw: str) -> str:
    s = v_raw.lstrip()
    in_quote = False
    out: list[str] = []
    last_keep = 0
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if in_quote:
            if ch == "\\" and i + 1 < n:
                nxt = s[i + 1]
                out.append({"n": "\n", "t": "\t", "b": "\b"}.get(nxt, nxt))
                last_keep = len(out)
                i += 2
                continue
            if ch == '"':
                in_quote = False
                last_keep = len(out)
                i += 1
                continue
            out.append(ch)
            last_keep = len(out)
        else:
            if ch in ("#", ";"):
                break
            if ch == '"':
                in_quote = True
                i += 1
                continue
            if ch == "\\" and i + 1 < n:
                nxt = s[i + 1]
                out.append({"n": "\n", "t": "\t", "b": "\b"}.get(nxt, nxt))
                last_keep = len(out)
                i += 2
                continue
            out.append(ch)
            if not ch.isspace():
                last_keep = len(out)
        i += 1
    return "".join(out[:last_keep])


def _git_glob_match(pat: str, text: str, icase: bool = False) -> bool:
    parts: list[str] = ["^"]
    i = 0
    n = len(pat)
    while i < n:
        if i == 0 and pat.startswith("**/"):
            parts.append("(?:.*/)?")
            i += 3
        elif pat.startswith("/**/", i):
            parts.append("(?:/|/.+/)")
            i += 4
        elif pat.startswith("**", i):
            parts.append(".*")
            i += 2
        elif pat[i] == "*":
            parts.append("[^/]*")
            i += 1
        elif pat[i] == "?":
            parts.append("[^/]")
            i += 1
        else:
            parts.append(re.escape(pat[i]))
            i += 1
    parts.append("$")
    return bool(re.match("".join(parts), text, re.IGNORECASE if icase else 0))


def resolve_git_pr_badge(
    branch: str,
    upstream: str,
    gitdir: str,
    commondir: str,
    worktree_root: str = "",
) -> tuple[str, str]:
    """Resolve `(pr_number, pr_url)` from `.git/config` (Tier 0) or `git-pr-prompt/*.state` (Tier 0.5)."""
    if not branch or branch in ("-", "HEAD", "(detached)") or branch.startswith("@") or not gitdir:
        return ("", "")

    remote_urls: dict[str, str] = {}
    remote_forges: dict[str, str] = {}
    instead_of: dict[str, str] = {}
    seen_cfgs: set[str] = set()
    first_remote_name = ""
    branch_remote = ""
    branch_pr = ""
    branch_pr_url = ""
    merge_forge_hint = ""

    gitdir_cands: list[str] = []
    for raw_gd in (
        gitdir,
        os.path.realpath(gitdir),
        os.path.join(worktree_root, ".git") if worktree_root else "",
        os.path.join(os.path.realpath(worktree_root), ".git") if worktree_root else "",
    ):
        if raw_gd:
            norm_gd = raw_gd.rstrip("/") + "/"
            if norm_gd not in gitdir_cands:
                gitdir_cands.append(norm_gd)

    def _eval_include_if(cond: str, cfg_dir: str) -> bool:
        if cond.startswith("onbranch:"):
            b_pat = cond[len("onbranch:"):]
            if not b_pat:
                return False
            if b_pat.endswith("/"):
                b_pat += "**"
            return _git_glob_match(b_pat, branch, icase=False)
        icase = False
        if cond.startswith("gitdir/i:"):
            g_pat = cond[len("gitdir/i:"):]
            icase = True
        elif cond.startswith("gitdir:"):
            g_pat = cond[len("gitdir:"):]
        else:
            return False
        if not g_pat:
            return False
        if g_pat.startswith("~/"):
            g_pat = os.path.expanduser("~").rstrip("/") + "/" + g_pat[2:]
        elif g_pat.startswith("./"):
            g_pat = cfg_dir.rstrip("/") + "/" + g_pat[2:]
        elif not g_pat.startswith("/"):
            g_pat = "**/" + g_pat
        if g_pat.endswith("/"):
            g_pat += "**"
        return any(_git_glob_match(g_pat, cand, icase=icase) for cand in gitdir_cands)

    def parse_cfg(cfg_path: str, is_repo_cfg: bool, depth: int = 0) -> None:
        nonlocal first_remote_name, branch_remote, branch_pr, branch_pr_url, merge_forge_hint
        if depth > 4 or not cfg_path or cfg_path in seen_cfgs or not os.path.isfile(cfg_path):
            return
        seen_cfgs.add(cfg_path)
        try:
            with open(cfg_path, "r", encoding="utf-8", errors="replace") as fh:
                raw_lines = fh.readlines()
        except OSError:
            return

        def _has_line_continuation(line_s: str) -> bool:
            if not line_s.endswith("\\"):
                return False
            in_q = False
            esc = False
            for ch in line_s:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    in_q = not in_q
                elif not in_q and ch in ("#", ";"):
                    return False
            return esc

        logical_lines: list[str] = []
        idx = 0
        while idx < len(raw_lines):
            cur_l = raw_lines[idx].rstrip("\r\n")
            lead_s = cur_l.lstrip()
            if not lead_s or lead_s[0] in ("#", ";"):
                idx += 1
                continue
            while _has_line_continuation(cur_l) and idx + 1 < len(raw_lines):
                idx += 1
                cur_l = cur_l[:-1] + raw_lines[idx].rstrip("\r\n")
            logical_lines.append(cur_l)
            idx += 1

        cfg_dir = os.path.dirname(os.path.abspath(cfg_path))
        sec_type = ""
        sec_name = ""
        seen_url_in_sec = False
        for raw_l in logical_lines:
            s = raw_l.lstrip()
            if not s or s[0] in ("#", ";"):
                continue
            if s.startswith("["):
                seen_url_in_sec = False
                parsed_hdr = _parse_git_section_header(s)
                if parsed_hdr is None:
                    sec_type = ""
                    sec_name = ""
                    continue
                sec_type, sec_name = parsed_hdr
                if sec_type == "includeif":
                    sec_type = "include" if _eval_include_if(sec_name, cfg_dir) else ""
                    sec_name = ""
                elif sec_type not in ("remote", "branch", "url", "include"):
                    sec_type = ""
                    sec_name = ""
                continue
            if not sec_type or "=" not in s:
                continue
            k_raw, v_raw = s.split("=", 1)
            key = k_raw.strip().lower()
            val = _parse_git_cfg_value(v_raw)
            if not val:
                continue

            if sec_type == "remote":
                if key == "url" and not seen_url_in_sec:
                    remote_urls[sec_name] = val
                    seen_url_in_sec = True
                    if is_repo_cfg and not first_remote_name:
                        first_remote_name = sec_name
                elif key == "forge":
                    remote_forges[sec_name] = val.lower()
            elif sec_type == "branch" and sec_name == branch:
                if key == "remote":
                    branch_remote = val
                elif key == "pr" and val.isdigit() and int(val) > 0:
                    branch_pr = val
                elif key == "prurl":
                    safe_u = sanitize_http_url(val)
                    if safe_u:
                        branch_pr_url = safe_u
                elif key == "merge":
                    m_ref = _RE_PULL_MERGE_REF.match(val)
                    if m_ref:
                        if m_ref.group(1):
                            if not branch_pr:
                                branch_pr = m_ref.group(2)
                            merge_forge_hint = "github"
                        elif m_ref.group(3):
                            if not branch_pr:
                                branch_pr = m_ref.group(4)
                            merge_forge_hint = "gitlab"
                        elif m_ref.group(5):
                            if not branch_pr:
                                branch_pr = m_ref.group(6)
                            merge_forge_hint = "bitbucket-server"
            elif sec_type == "url" and key == "insteadof":
                instead_of[val] = sec_name
            elif sec_type == "include" and key == "path":
                inc = os.path.expanduser(val) if val.startswith("~/") else val
                if not os.path.isabs(inc):
                    inc = os.path.join(cfg_dir, inc)
                parse_cfg(inc, is_repo_cfg, depth + 1)

    global_cfg = os.environ.get("GIT_CONFIG_GLOBAL", "").strip()
    if global_cfg:
        parse_cfg(global_cfg, False)
    else:
        xdg_cfg = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
        parse_cfg(os.path.join(xdg_cfg, "git", "config"), False)
        parse_cfg(os.path.expanduser("~/.gitconfig"), False)

    eff_common = commondir or gitdir
    if eff_common and os.path.realpath(eff_common) != os.path.realpath(gitdir):
        parse_cfg(os.path.join(eff_common, "config"), True)
    parse_cfg(os.path.join(gitdir, "config"), True)
    parse_cfg(os.path.join(gitdir, "config.worktree"), True)

    if branch_remote and branch_remote != "." and branch_remote in remote_urls:
        remote_name = branch_remote
    elif "/" in upstream and upstream.split("/", 1)[0] in remote_urls:
        remote_name = upstream.split("/", 1)[0]
    elif branch_remote and branch_remote != ".":
        remote_name = branch_remote
    elif "/" in upstream:
        remote_name = upstream.split("/", 1)[0]
    else:
        remote_name = "origin"

    first_remote_url = remote_urls.get(first_remote_name, "") if first_remote_name else ""
    remote_url = remote_urls.get(remote_name) or remote_urls.get("origin") or first_remote_url
    if remote_url and instead_of:
        best_pfx = ""
        for pfx in instead_of:
            if remote_url.startswith(pfx) and len(pfx) > len(best_pfx):
                best_pfx = pfx
        if best_pfx:
            remote_url = instead_of[best_pfx] + remote_url[len(best_pfx):]

    first_remote_forge = remote_forges.get(first_remote_name, "") if first_remote_name else ""
    forge_hint = (
        remote_forges.get(remote_name)
        or remote_forges.get("origin")
        or first_remote_forge
        or merge_forge_hint
    )

    if branch_pr and branch_pr.isdigit() and int(branch_pr) > 0:
        pr_url = sanitize_http_url(
            branch_pr_url or (build_forge_pr_url(remote_url, branch_pr, forge_hint) if remote_url else "")
        )
        return (branch_pr, pr_url)

    if branch in ("main", "master", "trunk", "develop") or not eff_common:
        return ("", "")

    cache_dir = (
        os.environ.get("GIT_PR_CACHE_DIR")
        or os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "git-pr-prompt")
    )
    cand_common_paths: list[str] = []
    for cp in (os.path.realpath(eff_common), os.path.abspath(eff_common)):
        if cp and cp not in cand_common_paths:
            cand_common_paths.append(cp)

    best_ts = -1
    best_num = ""
    best_url = ""
    for cp in cand_common_paths:
        repo_key = re.sub(r"[^A-Za-z0-9._-]", "_", cp)
        state_file = os.path.join(cache_dir, f"{repo_key}.state")
        if not os.path.isfile(state_file):
            continue
        try:
            with open(state_file, "r", encoding="utf-8", errors="replace") as fh:
                for raw_l in fh:
                    parts = raw_l.rstrip("\r\n").split("|")
                    if len(parts) < 2 or parts[0] != branch:
                        continue
                    c_num = parts[1].strip()
                    c_url = sanitize_http_url(parts[2]) if len(parts) > 2 else ""
                    c_ts_s = parts[3].strip() if len(parts) > 3 else ""
                    c_ts = int(c_ts_s) if c_ts_s.isdigit() else 0
                    if c_ts >= best_ts:
                        best_ts = c_ts
                        if c_num != "NONE" and c_num.isdigit() and int(c_num) > 0:
                            best_num = c_num
                            best_url = c_url
                        else:
                            best_num = ""
                            best_url = ""
                    break
        except OSError:
            continue

    if best_num:
        resolved_url = sanitize_http_url(
            best_url or (build_forge_pr_url(remote_url, best_num, forge_hint) if remote_url else "")
        )
        return (best_num, resolved_url)
    return ("", "")


def call_vcs_summary_hook(workdir: str) -> tuple[str, bool, str, str] | None:
    """Invoke optional `ide_vcs_summary WORKDIR` hook with a 0.4s timeout."""
    raw_out = call_ide_hook("ide_vcs_summary", workdir, timeout=0.4)
    if not raw_out:
        return None
    first_line = next((ln.strip() for ln in raw_out.splitlines() if ln.strip()), "")
    if not first_line or "|" not in first_line:
        return None
    parts = first_line.split("|", 3)
    branch = parts[0].strip() or "-"
    dirty = (parts[1].strip().lower() in ("1", "true", "yes", "dirty", "*")) if len(parts) > 1 else False
    detail = (parts[2].strip() if len(parts) > 2 else "") or (
        f"{branch} (modified)" if dirty else f"{branch} (clean)"
    )
    url = sanitize_http_url(parts[3]) if len(parts) > 3 else ""
    return (branch, dirty, detail, url)


def git_summary(workdir: str) -> tuple[str, bool, str, str, str]:
    """Return `(branch_badge, is_dirty, detail, pr_url, worktree_root)` using custom VCS hook or single-fork Git status."""
    if not workdir or not os.path.isdir(workdir):
        return ("-", False, "not a repository", "", "")
    custom_vcs = call_vcs_summary_hook(workdir)
    worktree_root, gitdir, commondir = locate_git_dirs(workdir)
    if custom_vcs is not None:
        return (custom_vcs[0], custom_vcs[1], custom_vcs[2], custom_vcs[3], worktree_root)
    env_git_dir = os.environ.get("GIT_DIR", "").strip()
    eff_gitdir = gitdir or (os.path.abspath(env_git_dir) if env_git_dir else "")
    eff_commondir = commondir or eff_gitdir
    if not shutil.which("git") or not eff_gitdir:
        return ("-", False, "not a repository", "", "")
    try:
        res = subprocess.run(
            ["git", "-C", workdir, "--no-optional-locks", "status", "--porcelain=v2", "--branch"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=0.4,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return ("-", False, "unavailable", "", "")
    if res.returncode != 0 or not res.stdout:
        return ("-", False, "not a repository", "", "")
    branch = ""
    oid = ""
    upstream = ""
    staged = 0
    modified = 0
    untracked = 0
    for line in res.stdout.splitlines():
        if line.startswith("# branch.head "):
            branch = line[len("# branch.head "):].strip()
        elif line.startswith("# branch.oid "):
            oid = line[len("# branch.oid "):].strip()
        elif line.startswith("# branch.upstream "):
            upstream = line[len("# branch.upstream "):].strip()
        elif line.startswith("? "):
            untracked += 1
        elif line.startswith(("1 ", "2 ", "u ")):
            parts = line.split(" ", 2)
            xy = parts[1] if len(parts) > 1 else ".."
            if len(xy) >= 2:
                if xy[0] != ".":
                    staged += 1
                if xy[1] != ".":
                    modified += 1
    if branch in ("", "(detached)"):
        branch = f"@{oid[:7]}" if oid and oid != "(initial)" else "HEAD"
    pr_num, pr_url = resolve_git_pr_badge(branch, upstream, eff_gitdir, eff_commondir, worktree_root)
    branch_badge = f"{branch}@{pr_num}" if pr_num else branch
    dirty = (staged + modified + untracked) > 0
    if not dirty:
        detail = f"{branch_badge} (clean)"
    else:
        counts = []
        if staged:
            counts.append(f"+{staged} staged")
        if modified:
            counts.append(f"~{modified} modified")
        if untracked:
            counts.append(f"?{untracked} untracked")
        detail = f"{branch_badge} ({', '.join(counts)})"
    return (branch_badge, dirty, detail, pr_url, worktree_root)
