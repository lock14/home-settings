#!/bin/zsh
# Solarized Dark TrueColor ZLE & zsh-syntax-highlighting Palette
# Sourced by dotfiles/.zshrc-addendum before active zsh-theme.zsh overrides.

# Solarized Dark TrueColor (Ethan Schoonover palette) for CLI Syntax Highlighting & ZLE
typeset -gA ZSH_HIGHLIGHT_STYLES
typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)

# Commands & Builtins (Solarized Green #859900 - unbolded, zero-jitter)
ZSH_HIGHLIGHT_STYLES[command]='fg=#859900'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#859900'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#859900'
ZSH_HIGHLIGHT_STYLES[function]='fg=#859900'
ZSH_HIGHLIGHT_STYLES[hashed-command]='fg=#859900'

# Control Flow & Reserved Words (Solarized Yellow #B58900 - exclusive control flow)
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#B58900'

# Precommands & Autodirectory (Solarized Blue #268BD2)
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#268BD2'
ZSH_HIGHLIGHT_STYLES[autodirectory]='fg=#268BD2'

# Options, Flags & Parameters (Solarized Base0 #839496 - restrained)
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#839496'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#839496'

# Strings & Quoted Arguments (Solarized Cyan #2AA198)
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#2AA198'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#2AA198'
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#2AA198'
ZSH_HIGHLIGHT_STYLES[back-quoted-argument]='fg=#839496'

# Variables, Expansions & Assignments (Solarized Base0 #839496)
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=#839496'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#839496'
ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=#268BD2'
ZSH_HIGHLIGHT_STYLES[assign]='fg=#839496'

# Substitutions & Delimiters (Pillar IV: Navigational Neutrality)
ZSH_HIGHLIGHT_STYLES[command-substitution]='fg=#839496'
ZSH_HIGHLIGHT_STYLES[command-substitution-quoted]='fg=#839496'
ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]='fg=#839496'
ZSH_HIGHLIGHT_STYLES[process-substitution]='fg=#839496'
ZSH_HIGHLIGHT_STYLES[process-substitution-delimiter]='fg=#839496'
ZSH_HIGHLIGHT_STYLES[back-quoted-argument-delimiter]='fg=#839496'

# Numbers, Constants & Arithmetic (Solarized Magenta #D33682)
ZSH_HIGHLIGHT_STYLES[numeric-fd]='fg=#D33682'
ZSH_HIGHLIGHT_STYLES[arithmetic-expansion]='fg=#D33682'

# Standalone numbers & assignment numeric values outside quotes (Solarized Magenta #D33682)
if zmodload zsh/pcre >/dev/null 2>&1; then
    setopt rematchpcre
    ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets regexp)
    typeset -gA ZSH_HIGHLIGHT_REGEXP
    ZSH_HIGHLIGHT_REGEXP+=("(?<=[=\\s]|^)[0-9]+(\\.[0-9]+)?(?=[\\s;|<>&]|$)(?=(?:[^\"]*\"[^\"]*\")*[^\"]*$)(?=(?:[^'\'']*'\''[^'\'']*'\'')*[^'\'']*$)" 'fg=#D33682')
fi

# Operators & Punctuation (Solarized Base0 #839496)
ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#839496'
ZSH_HIGHLIGHT_STYLES[redirection]='fg=#839496'

# Paths & Directories (Solarized Blue #268BD2 matching dircolors/eza / Base0 #839496)
ZSH_HIGHLIGHT_STYLES[path]='fg=#268BD2'
ZSH_HIGHLIGHT_STYLES[path_prefix]='fg=#839496'

# Unknown Tokens & Errors (Solarized Red #DC322F)
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#DC322F'

# Comments (Solarized Base01 #586E75)
ZSH_HIGHLIGHT_STYLES[comment]='fg=#586E75'

# Default Arguments (Solarized Base0 #839496)
ZSH_HIGHLIGHT_STYLES[default]='fg=#839496'

# Bracket Matching (Solarized Base0 #839496 / Error Red #DC322F)
ZSH_HIGHLIGHT_STYLES[bracket-level-1]='fg=#839496'
ZSH_HIGHLIGHT_STYLES[bracket-level-2]='fg=#839496'
ZSH_HIGHLIGHT_STYLES[bracket-level-3]='fg=#839496'
ZSH_HIGHLIGHT_STYLES[bracket-error]='fg=#DC322F'

# ZLE Selection, Search & Autosuggestion (Base02 #073642, Base01 #586E75)
zle_highlight=(region:bg=#073642 special:fg=#D33682 isearch:underline,fg=#268BD2)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#586E75'

# Source active Zsh theme overrides (managed by bin/theme)
if [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/home-settings/zsh-theme.zsh" ]; then
    source "${XDG_CONFIG_HOME:-$HOME/.config}/home-settings/zsh-theme.zsh"
fi
