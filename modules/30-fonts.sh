#!/bin/bash
# Stage 30: MesloLGS Nerd Font (ryanoasis/nerd-fonts v3) downloading and caching.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# Source helper libraries
# shellcheck source=/dev/null
. "$REPO_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/os.sh"

OS="${OS:-$(detect_os)}"
DRY_RUN="${DRY_RUN:-false}"

if [ "$OS" = "macos" ]; then
    FONT_DIR="$HOME/Library/Fonts"
else
    FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
fi

echo "  Installing MesloLGS Nerd Font fonts into $FONT_DIR..."

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] Downloading MesloLGS Nerd Font (Regular, Bold, Italic, Bold Italic) to $FONT_DIR"
else
    mkdir -p "$FONT_DIR"
    CACHE_DIR="${HOME_SETTINGS_FONT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/home-settings/fonts}"
    mkdir -p "$CACHE_DIR"

    # Remove any conflicting hyphenated or stray numbered font files
    rm -f "$FONT_DIR"/MesloLGS-NF-*.ttf "$CACHE_DIR"/MesloLGS-NF-*.ttf
    rm -f "$FONT_DIR"/[0-9]MesloLGS*.ttf "$CACHE_DIR"/[0-9]MesloLGS*.ttf

    # Ensure fontconfig alias is provisioned on Linux and clean any dangling symlinks
    if [ "$OS" != "macos" ]; then
        xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
        if [ -L "$xdg_config/fontconfig" ] && [ ! -e "$xdg_config/fontconfig" ]; then
            rm -f "$xdg_config/fontconfig"
        fi
        fontconfig_dir="$xdg_config/fontconfig/conf.d"
        mkdir -p "$fontconfig_dir"
        fc_alias_src="$REPO_DIR/dotfiles/.config/fontconfig/conf.d/10-meslo-nerd-font.conf"
        fc_alias_dest="$fontconfig_dir/10-meslo-nerd-font.conf"
        if [ -f "$fc_alias_src" ] && [ ! -e "$fc_alias_dest" ]; then
            cp -f "$fc_alias_src" "$fc_alias_dest"
        elif [ -f "$fc_alias_src" ] && ! [ "$fc_alias_src" -ef "$fc_alias_dest" ]; then
            cp -f "$fc_alias_src" "$fc_alias_dest"
        fi
    fi

    BASE_FONT_URL="https://github.com/ryanoasis/nerd-fonts/raw/v3.3.0/patched-fonts/Meslo/S"
    FONTS=(
        "Regular/MesloLGSNerdFont-Regular.ttf:MesloLGSNerdFont-Regular.ttf"
        "Bold/MesloLGSNerdFont-Bold.ttf:MesloLGSNerdFont-Bold.ttf"
        "Italic/MesloLGSNerdFont-Italic.ttf:MesloLGSNerdFont-Italic.ttf"
        "Bold-Italic/MesloLGSNerdFont-BoldItalic.ttf:MesloLGSNerdFont-BoldItalic.ttf"
    )
    pids=()
    for entry in "${FONTS[@]}"; do
        IFS=":" read -r remote_path local_file <<< "$entry"
        target="$FONT_DIR/$local_file"
        cached="$CACHE_DIR/$local_file"

        # Validate cache & target size (>2.0MB for complete Nerd Font v3)
        if [ -f "$cached" ]; then
            csize=$(wc -c < "$cached" | tr -d ' ')
            if [ "$csize" -lt 2000000 ]; then
                rm -f "$cached"
            fi
        fi
        if [ -f "$target" ]; then
            tsize=$(wc -c < "$target" | tr -d ' ')
            if [ "$tsize" -lt 2000000 ]; then
                rm -f "$target"
            fi
        fi

        if [ ! -s "$target" ]; then
            if [ -s "$cached" ]; then
                target_tmp="$target.tmp.$$.${BASHPID:-$RANDOM}"
                cp -f "$cached" "$target_tmp" && mv -f "$target_tmp" "$target"
            else
                (
                    tmp_file="$cached.tmp.$$.${BASHPID:-$RANDOM}"
                    target_tmp="$target.tmp.$$.${BASHPID:-$RANDOM}"
                    trap 'rm -f "$tmp_file" "$target_tmp"' EXIT
                    if curl -fsSL "$BASE_FONT_URL/$remote_path" -o "$tmp_file"; then
                        mv -f "$tmp_file" "$cached"
                        cp -f "$cached" "$target_tmp" && mv -f "$target_tmp" "$target"
                    else
                        rm -f "$tmp_file"
                        exit 1
                    fi
                ) &
                pids+=($!)
            fi
        elif [ ! -s "$cached" ]; then
            cp -f "$target" "$cached"
        fi
    done
    if [ ${#pids[@]} -gt 0 ]; then
        download_failed=0
        for pid in "${pids[@]}"; do
            if ! wait "$pid"; then
                download_failed=1
            fi
        done
        if [ "$download_failed" -ne 0 ]; then
            exit 1
        fi
    fi

    # Clean up legacy unpatched romkatv fonts once v3 is safely in place
    rm -f "$FONT_DIR/MesloLGS NF"*.ttf "$CACHE_DIR/MesloLGS NF"*.ttf

    if [ "$OS" = "macos" ] && command -v atsutil &>/dev/null; then
        # Ensure the macOS font server is awake (never kill fontd while terminal apps are running)
        atsutil server -ping >/dev/null 2>&1 || true
    fi
    if command -v fc-cache &>/dev/null; then
        fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
        if [ "$OS" != "macos" ] && [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig" ]; then
            fc-cache -f "${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig" >/dev/null 2>&1 || true
        fi
    fi

fi
