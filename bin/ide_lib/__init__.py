"""Modular runtime library for the Hybrid Terminal IDE (`bin/ide`).

Layered package architecture (strictly acyclic bottom-to-top):
- `constants`: Shared delimiters, CLI usage specification, path/CWD helpers, and Unicode cell metrics.
- `hooks`: Untracked user hook execution (`links.sh`) and external workspace root discovery.
- `git_info`: Zero-fork `.git` layout inspection, `.git/config` parser, PR/MR badge resolver, and Git summary.
- `tmux`: Tmux IPC primitives, exact-target session/pane lookup, SSH/display sync, clipboard, and process checks.
- `theme`: Active palette loader, TrueColor foreground SGR escapes, and `fzf` option synthesis.
- `nvim_rpc`: Mise-aware Neovim binary lookup, headless RPC helpers, CWD self-healing, and Editor/AI launchers.
- `fleet`: Deterministic AI lifecycle state machine, notifications, urgency fleet classifier, and PR opener.
- `layout`: Workspace geometry, `_ide_park_<role>` parking, directional swap, focus toggles, dive, refresh, and quit.
- `links`: Bounded workspace file search, `file://`/`#anchor`/OSC 8 link router, and AI prompt context dispatch.
- `sessions`: Tabular fleet views, live ANSI session preview, `fzf` session switcher, directory picker, and attention jump.
- `cli`: Command-line flag parser and lazy subcommand dispatcher.
"""

from __future__ import annotations

from ide_lib.constants import TMUX_SEP, USAGE_TEXT, _TMUX_SEP, usage

__all__ = [
    "TMUX_SEP",
    "USAGE_TEXT",
    "_TMUX_SEP",
    "usage",
]
