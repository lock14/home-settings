"""CLI argument parser and command dispatcher for bin/theme."""

from __future__ import annotations

import os
from pathlib import Path
import sys

USAGE_TEXT = """Usage: theme [OPTIONS] [THEME_NAME]

Switch or preview the universal TrueColor color scheme across terminal emulators,
Neovim, Vim, Tmux, bat, delta, btop, tealdeer, fzf, eza, dircolors, and shells.
When invoked with no arguments in an interactive terminal, opens an fzf picker.

Managed Themes:
  solarized-dark     Solarized Dark (default)
  solarized-light    Solarized Light
  catppuccin-mocha   Catppuccin Mocha
  catppuccin-latte   Catppuccin Latte
  gruvbox-dark       Gruvbox Dark
  tokyonight-night   TokyoNight Night
  kanagawa-wave      Kanagawa Wave
  nord               Nord
  onedark            OneDark
  new-years          New Year's
  valentines         Valentine's Day
  st-patricks        St. Patrick's Day
  easter             Easter
  independence-day   Independence Day
  halloween          Halloween
  thanksgiving       Thanksgiving
  christmas          Christmas

Options:
  -s, --set <NAME>       Apply theme <NAME> across all managed tools
  --holiday              Apply the nearest upcoming or active US Holiday theme
  -l, --list             List all managed and user-defined themes
  --plain                Print theme slugs only (one per line) when listing
  -c, --current          Print the currently active theme name
  -p, --preview [NAME]   Render a TrueColor palette and syntax preview for [NAME]
  --env [NAME]           Output shell export commands for [NAME]
  --create <NAME>        Create a custom user theme file in the user themes directory
  --from <BASE>          Base theme to copy when used with --create (default: solarized-dark)
  -f, --force            Overwrite existing custom theme file when used with --create
  --path                 Print the user custom themes directory path
  --no-live              Write theme state and configs without signalling running servers
  -n, --dry-run [NAME]   Show files and targets that would be updated without modifying state
  -h, --help             Show this help message and exit
"""


def _parse_flag_value(
    args: list[str],
    idx: int,
    display_opt: str,
    noun: str,
    optional: bool = False,
) -> tuple[str | None, int, str | None]:
    """Extract a required or optional flag value from '--opt val' or '--opt=val'."""
    arg = args[idx]
    if "=" in arg and arg.startswith("--"):
        val = arg.split("=", 1)[1]
        if not val.strip():
            return None, idx, f"theme: option '{display_opt}' requires {noun}\n"
        return val, idx, None

    if optional:
        if idx + 1 < len(args) and not args[idx + 1].startswith("-"):
            if not args[idx + 1].strip():
                return None, idx, f"theme: option '{arg}' requires {noun}\n"
            return args[idx + 1], idx + 1, None
        return None, idx, None

    if idx + 1 >= len(args) or not args[idx + 1].strip() or args[idx + 1].startswith("-"):
        return None, idx, f"theme: option '{arg}' requires {noun}\n"
    return args[idx + 1], idx + 1, None


def main(argv: list[str] | None = None) -> int:
    """Execute the theme CLI command from argv (expects [repo_dir, ...cli_args])."""
    raw_argv = sys.argv[1:] if argv is None else argv
    repo_dir = Path(raw_argv[0]).resolve()
    args = raw_argv[1:]

    action: str | None = None
    target_name: str | None = None
    base_name = "solarized-dark"
    force = False
    dry_run = False
    no_live = False
    plain = False
    resolve_holiday = False

    i = 0
    end_of_opts = False
    while i < len(args):
        arg = args[i]
        if not end_of_opts and arg == "--":
            end_of_opts = True
        elif not end_of_opts and arg in ("-h", "--help"):
            print(USAGE_TEXT, end="")
            return 0
        elif not end_of_opts and arg == "--sync-assets":
            action = "sync-assets"
        elif not end_of_opts and arg in ("-l", "--list"):
            action = "list"
        elif not end_of_opts and arg == "--plain":
            plain = True
            if action is None:
                action = "list"
        elif not end_of_opts and arg in ("-c", "--current"):
            action = "current"
        elif not end_of_opts and arg == "--path":
            action = "path"
        elif not end_of_opts and arg in ("-n", "--dry-run"):
            dry_run = True
        elif not end_of_opts and arg == "--no-live":
            no_live = True
        elif not end_of_opts and arg in ("-f", "--force"):
            force = True
        elif not end_of_opts and arg == "--holiday":
            action = "set"
            resolve_holiday = True
        elif not end_of_opts and (arg in ("-s", "--set") or arg.startswith("--set=")):
            val, i, err = _parse_flag_value(args, i, "--set", "a theme name")
            if err:
                sys.stderr.write(err)
                return 1
            action = "set"
            resolve_holiday = False
            target_name = val
        elif not end_of_opts and (arg in ("-p", "--preview") or arg.startswith("--preview=")):
            val, i, err = _parse_flag_value(args, i, "--preview", "a theme name", optional=True)
            if err:
                sys.stderr.write(err)
                return 1
            action = "preview"
            if val is not None:
                target_name = val
        elif not end_of_opts and (arg == "--env" or arg.startswith("--env=")):
            val, i, err = _parse_flag_value(args, i, "--env", "a theme name", optional=True)
            if err:
                sys.stderr.write(err)
                return 1
            action = "env"
            if val is not None:
                target_name = val
        elif not end_of_opts and (arg == "--create" or arg.startswith("--create=")):
            val, i, err = _parse_flag_value(args, i, "--create", "a new theme name")
            if err:
                sys.stderr.write(err)
                return 1
            action = "create"
            target_name = val
        elif not end_of_opts and (arg == "--from" or arg.startswith("--from=")):
            val, i, err = _parse_flag_value(args, i, "--from", "a base theme name")
            if err:
                sys.stderr.write(err)
                return 1
            assert val is not None
            base_name = val
        elif not end_of_opts and arg.startswith("-"):
            sys.stderr.write(f"theme: unknown option '{arg}' (try 'theme --help')\n")
            return 1
        else:
            if not arg.strip():
                sys.stderr.write("theme: theme name must not be empty\n")
                return 1
            if target_name is not None or resolve_holiday:
                sys.stderr.write(f"theme: unexpected extra argument '{arg}'\n")
                return 1
            target_name = arg
            if action is None:
                action = "set"
        i += 1

    if action == "path":
        from theme_lib.palette import get_user_themes_dirs

        print(str(get_user_themes_dirs()[0]))
        return 0

    if action == "sync-assets":
        from theme_lib.reload import sync_managed_repo_assets

        sync_managed_repo_assets(repo_dir)
        return 0

    from theme_lib.palette import (
        create_user_theme,
        discover_themes,
        get_current_theme_slug,
        resolve_nearest_holiday_slug,
    )

    if resolve_holiday:
        target_name = resolve_nearest_holiday_slug()

    try:
        themes = discover_themes(repo_dir)
    except ValueError as err:
        sys.stderr.write(f"theme: {err}\n")
        return 1

    current_slug = get_current_theme_slug(themes)

    if action == "current":
        print(current_slug)
        return 0
    if action == "list":
        if plain:
            from theme_lib.palette import MANAGED_ORDER

            ordered = [s for s in MANAGED_ORDER if s in themes]
            ordered.extend(s for s in sorted(themes) if s not in ordered)
            for slug in ordered:
                print(slug)
            return 0
        from theme_lib.preview import list_themes

        return list_themes(themes, current_slug, plain=False)
    if action == "create":
        assert target_name is not None
        return create_user_theme(target_name, base_name, themes, force=force)

    if action in ("preview", "env"):
        raw_target = current_slug if target_name is None else target_name
        slug = raw_target.strip().lower().replace("_", "-")
        if slug not in themes:
            sys.stderr.write(
                f"theme: unknown theme '{raw_target}' (run 'theme --list' to see available themes)\n"
            )
            return 1
        if action == "preview":
            from theme_lib.preview import render_preview

            return render_preview(themes[slug])
        from theme_lib.generators import generate_theme_env_sh

        print(generate_theme_env_sh(themes[slug], repo_dir), end="")
        return 0

    if action == "set" or (dry_run and target_name is not None):
        raw_target = current_slug if target_name is None else target_name
        slug = raw_target.strip().lower().replace("_", "-")
        if slug not in themes:
            sys.stderr.write(
                f"theme: unknown theme '{raw_target}' (run 'theme --list' to see available themes)\n"
            )
            return 1
        from theme_lib.reload import apply_theme

        return apply_theme(themes[slug], repo_dir, dry_run=dry_run, no_live=no_live)

    if dry_run and target_name is None:
        from theme_lib.reload import apply_theme

        return apply_theme(themes[current_slug], repo_dir, dry_run=True, no_live=no_live)

    from theme_lib.preview import list_themes, run_fzf_picker

    if (sys.stdin.isatty() and sys.stdout.isatty()) or os.environ.get("THEME_FORCE_FZF") == "1":
        return run_fzf_picker(themes, current_slug, repo_dir, dry_run=dry_run, no_live=no_live)
    return list_themes(themes, current_slug)
