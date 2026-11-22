"""Unified multi-theme palette, config generation, sync, and live-reload package."""

from __future__ import annotations

__all__ = [
    "ALL_COLOR_KEYS",
    "ANSI_ROLE_ORDER",
    "CORE_COLOR_KEYS",
    "SOLARIZED_DARK_DEFAULTS",
    "SOLARIZED_LIGHT_DEFAULTS",
    "USAGE_TEXT",
    "ansi_palette_hex_list",
    "apply_theme",
    "blend_hex",
    "broadcast_live_reloads",
    "build_fzf_color_opts",
    "build_usage_text",
    "compile_truecolor_ls_colors",
    "compute_easter_date",
    "compute_nth_weekday_date",
    "compute_thanksgiving_date",
    "contrast_ratio",
    "create_user_theme",
    "discover_builtin_themes",
    "discover_nvim_sockets",
    "discover_themes",
    "emit_live_osc_sequences",
    "format_swatch_strip",
    "generate_active_theme_file_text",
    "generate_btop_config_text",
    "generate_btop_theme_text",
    "generate_ghostty_config_text",
    "generate_ghostty_theme_text",
    "generate_git_config_text",
    "generate_p10k_theme_text",
    "generate_tealdeer_config_text",
    "generate_theme_env_sh",
    "generate_tmtheme_text",
    "generate_tmux_theme_text",
    "generate_zsh_theme_text",
    "get_current_theme_slug",
    "get_holiday_meta",
    "get_holiday_schedule_for_year",
    "get_user_themes_dirs",
    "get_xdg_config_home",
    "hex_to_rgb",
    "hue_difference",
    "list_themes",
    "main",
    "ordered_theme_slugs",
    "parse_theme_file",
    "parse_theme_kv",
    "relative_luminance",
    "render_preview",
    "resolve_holiday_rule_date",
    "resolve_nearest_holiday_slug",
    "resolve_single_theme",
    "rgb_distance",
    "rgb_semicolon",
    "run_fzf_picker",
    "slug_to_label",
    "sync_managed_repo_assets",
    "sync_symlink",
    "theme_sort_key",
]

_MODULE_EXPORTS: dict[str, str] = {
    "USAGE_TEXT": "cli",
    "build_usage_text": "cli",
    "main": "cli",
    "build_fzf_color_opts": "generators",
    "compile_truecolor_ls_colors": "generators",
    "generate_active_theme_file_text": "generators",
    "generate_btop_config_text": "generators",
    "generate_btop_theme_text": "generators",
    "generate_ghostty_config_text": "generators",
    "generate_ghostty_theme_text": "generators",
    "generate_git_config_text": "generators",
    "generate_p10k_theme_text": "generators",
    "generate_tealdeer_config_text": "generators",
    "generate_theme_env_sh": "generators",
    "generate_tmtheme_text": "generators",
    "generate_tmux_theme_text": "generators",
    "generate_zsh_theme_text": "generators",
    "format_swatch_strip": "preview",
    "list_themes": "preview",
    "render_preview": "preview",
    "run_fzf_picker": "preview",
    "apply_theme": "reload",
    "broadcast_live_reloads": "reload",
    "discover_nvim_sockets": "reload",
    "emit_live_osc_sequences": "reload",
    "sync_symlink": "reload",
    "sync_managed_repo_assets": "sync",
}


def __getattr__(name: str) -> object:
    """Lazily load submodules on demand to keep CLI startup minimal."""
    if name not in __all__:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
    submod_name = _MODULE_EXPORTS.get(name, "palette")
    import importlib

    submod = importlib.import_module(f"theme_lib.{submod_name}")
    val = getattr(submod, name)
    globals()[name] = val
    return val
