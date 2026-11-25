"""Modular runtime library for the Hybrid Terminal IDE (`bin/ide`).

Layered package architecture (strictly acyclic bottom-to-top):
- `constants`: Shared delimiters, CLI usage specification, path/CWD helpers, and Unicode cell metrics.
- `keymap`: Canonical TUI shortcut registry, width-fitted `fzf`/card footers, and top-bar hitbox specs.
- `hooks`: Untracked user hook execution (`links.sh`) and external workspace root discovery.
- `git_info`: Zero-fork `.git` layout inspection, `.git/config` parser, PR/MR badge resolver, and Git summary.
- `proc`: Process-tree inspection (`/proc` and `ps`) and Editor pane Neovim socket discovery.
- `tmux`: Tmux IPC primitives, exact-target session/pane lookup, SSH/display sync, browser opener, and clipboard.
- `dock`: Two-pane `ai-sw-*` switcher docking state machine, `flock` serialization, and client handoff.
- `theme`: Active palette loader, TrueColor foreground SGR escapes, and `fzf` option synthesis.
- `nvim_rpc`: Mise-aware Neovim binary lookup, headless RPC helpers, CWD self-healing, and Editor/AI launchers.
- `fleet`: Deterministic AI lifecycle state machine, notifications, urgency fleet classifier, and PR opener.
- `launcher`: Interactive `mono-tui` New Workspace card, AI Agent switcher dialog, and directory preview.
- `layout`: Workspace geometry, `_ide_park_<role>` parking, directional swap, focus toggles, dive, refresh, and quit.
- `links`: Bounded workspace file search, `file://`/`#anchor`/OSC 8 link router, and AI prompt context dispatch.
- `preview`: Tab/CJK/emoji-aware `fzf` preview line-wrap model, SGR carry-over, and `--follow` streamer.
- `switcher`: Single-round-trip `Alt+w` topology snapshot, FIFO Git feeder, and 2-pane `ai-sw-*` popup runner.
- `sessions`: Tabular and JSON fleet views, FIFO attention jump, workspace directory picker, and `switch` entrypoint.
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
