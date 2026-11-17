# Bash 17-Theme + Custom-Theme Palette Engine & State Synchronizer (Bash 3.2+ compatible)
# Provides zero-fork palette parsing, hex blending, TrueColor/ANSI LS_COLORS compilation,
# Readline active-region synchronization, and cross-pane theme state tracking.

# Calibrated 16-color Solarized Dark LS_COLORS template:
# Directories Blue (34), Symlinks Cyan (36), Executables unbolded Green (32),
# Archives Orange (91), Media Violet (95), Crypto/Keys Magenta (35), Text/Code Base0 (00), Temp/Logs Base01 (90)
_HS_ANSI_LS_COLORS="rs=0:di=34:ln=36:mh=00:pi=33:so=35:do=35:bd=35:cd=35:or=31:mi=31:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;40:st=37;44:ex=32:*.tar=91:*.tgz=91:*.arc=91:*.arj=91:*.taz=91:*.lha=91:*.lz4=91:*.lzh=91:*.lzma=91:*.tlz=91:*.txz=91:*.tzo=91:*.t7z=91:*.zip=91:*.z=91:*.dz=91:*.gz=91:*.lrz=91:*.lz=91:*.lzo=91:*.xz=91:*.zst=91:*.tzst=91:*.bz2=91:*.bz=91:*.tbz=91:*.tbz2=91:*.tz=91:*.deb=91:*.rpm=91:*.jar=91:*.war=91:*.ear=91:*.sar=91:*.rar=91:*.7z=91:*.cab=91:*.dmg=91:*.iso=91:*.apk=91:*.gem=91:*.msi=91:*.xpi=91:*.jpg=95:*.jpeg=95:*.gif=95:*.bmp=95:*.pbm=95:*.pgm=95:*.ppm=95:*.tga=95:*.xbm=95:*.xpm=95:*.tif=95:*.tiff=95:*.png=95:*.svg=95:*.svgz=95:*.webp=95:*.mov=95:*.mpg=95:*.mpeg=95:*.mkv=95:*.webm=95:*.mp4=95:*.m4v=95:*.avi=95:*.flv=95:*.wmv=95:*.aac=95:*.flac=95:*.m4a=95:*.mid=95:*.midi=95:*.mka=95:*.mp3=95:*.ogg=95:*.wav=95:*.key=35:*.pem=35:*.crt=35:*.cer=35:*.gpg=35:*.pgp=35:*.asc=35:*.3des=35:*.aes=35:*.enc=35:*.txt=00:*.md=00:*.mkd=00:*.markdown=00:*.json=00:*.yaml=00:*.yml=00:*.toml=00:*.xml=00:*.html=00:*.css=00:*.properties=00:*.proto=00:*.textproto=00:*.pbtxt=00:*.textpb=00:*.prototxt=00:*.sh=00:*.bash=00:*.zsh=00:*.py=00:*.go=00:*.rs=00:*.c=00:*.cc=00:*.cpp=00:*.h=00:*.hpp=00:*.java=00:*.js=00:*.ts=00:*.sql=00:*.tf=00:*.kt=00:*.kts=00:*.swift=00:*.zig=00:*.cs=00:*.scala=00:*.sc=00:*.rb=00:*.graphql=00:*.graphqls=00:*.gql=00:*.bzl=00:*.bazel=00:*.rego=00:*.lua=00:*.mk=00:*.ex=00:*.exs=00:*.hs=00:*.lean=00:*.ml=00:*.mli=00:*.clj=00:*.cljs=00:*.cljc=00:*.edn=00:*.diff=00:*.patch=00:*.bak=90:*.old=90:*.orig=90:*.swp=90:*.swo=90:*.log=90:"

_HS_BUILTIN_THEME_ORDER=(
    solarized-dark solarized-light catppuccin-mocha catppuccin-latte
    gruvbox-dark tokyonight-night kanagawa-wave nord onedark
    new-years valentines st-patricks easter
    independence-day halloween thanksgiving christmas
)

_hs_bash_is_truecolor() {
    [ "${TERM:-}" != "linux" ] && { [ "${COLORTERM:-}" = "truecolor" ] || [ "${COLORTERM:-}" = "24bit" ]; }
}

_hs_bash_apply_ansi_ls_colors() {
    if command -v dircolors >/dev/null 2>&1 && [ -f "$HOME/.dir-colors/dircolors" ]; then
        eval "$(dircolors "$HOME/.dir-colors/dircolors")"
    else
        export LS_COLORS="$_HS_ANSI_LS_COLORS"
    fi
    export LSCOLORS="${LSCOLORS:-exgxfxdxcxfxfxegedabagacad}"
}

_hs_bash_norm_slug() {
    local s="${1:-}" out="" ch
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    local i len="${#s}"
    for ((i = 0; i < len; i++)); do
        ch="${s:i:1}"
        case "$ch" in
            A) ch=a ;; B) ch=b ;; C) ch=c ;; D) ch=d ;; E) ch=e ;; F) ch=f ;;
            G) ch=g ;; H) ch=h ;; I) ch=i ;; J) ch=j ;; K) ch=k ;; L) ch=l ;;
            M) ch=m ;; N) ch=n ;; O) ch=o ;; P) ch=p ;; Q) ch=q ;; R) ch=r ;;
            S) ch=s ;; T) ch=t ;; U) ch=u ;; V) ch=v ;; W) ch=w ;; X) ch=x ;;
            Y) ch=y ;; Z) ch=z ;; _) ch=- ;;
        esac
        out="${out}${ch}"
    done
    REPLY="$out"
}

# Compact 26-field built-in palette lookup (1:1 with colors/themes/*.theme):
# LABEL|MODE|BAT_THEME|B03|B02|B04|B01|B00|B0|B1|B2|B3|YEL|ORA|RED|MAG|VIO|BLU|CYA|GRN|MGRN|MRED|MYEL|MBLU|MMAG|MB1
_hs_bash_builtin_spec() {
    REPLY=""
    case "${1:-}" in
        solarized-dark)   REPLY="Solarized Dark|dark|Solarized-Dark-TrueColor|#002B36|#073642|#002731|#586E75|#657B83|#839496|#93A1A1|#EEE8D5|#FDF6E3|#B58900|#CB4B16|#DC322F|#D33682|#6C71C4|#268BD2|#2AA198|#859900|#274C25|#422D33|#364725|#0B4764|#3E2E4C|#2C4E56" ;;
        solarized-light)  REPLY="Solarized Light|light|Solarized-Light-TrueColor|#FDF6E3|#EEE8D5|#E6DFCA|#93A1A1|#839496|#657B83|#586E75|#073642|#002B36|#B58900|#CB4B16|#DC322F|#D33682|#6C71C4|#268BD2|#2AA198|#859900|#E5ECD0|#F6D8D3|#F0E4C0|#D8E6EE|#F3D9E4|#E4DEC8" ;;
        catppuccin-mocha) REPLY="Catppuccin Mocha|dark|Catppuccin-Mocha-TrueColor|#1E1E2E|#313244|#181825|#6C7086|#7F849C|#CDD6F4|#DCE0E8|#E6E9EF|#F5E0DC|#F9E2AF|#FAB387|#F38BA8|#F5C2E7|#CBA6F7|#89B4FA|#94E2D5|#A6E3A1|#283B37|#3E2939|#3E3B3B|#29384E|#3E3247|#35374B" ;;
        catppuccin-latte) REPLY="Catppuccin Latte|light|Catppuccin-Latte-TrueColor|#EFF1F5|#CCD0DA|#E6E9EF|#686B7D|#5C5F77|#4C4F69|#383A50|#313244|#1E1E2E|#8F5902|#B34300|#D20F39|#A82B8A|#8839EF|#1E66F5|#0E7075|#2D761D|#DCEAD9|#F2D5DD|#EFE4D2|#D6E1F8|#F3DFEF|#D5D8E2" ;;
        gruvbox-dark)     REPLY="Gruvbox Dark|dark|Gruvbox-Dark-TrueColor|#282828|#3C3836|#1D2021|#928374|#A89984|#EBDBB2|#FBF1C7|#D5C4A1|#FBF1C7|#FABD2F|#FE8019|#FB4934|#D3869B|#B16286|#83A598|#8EC07C|#B8BB26|#3B3D24|#472825|#473F25|#2E3B36|#422E36|#45403D" ;;
        tokyonight-night) REPLY="TokyoNight Night|dark|TokyoNight-Night-TrueColor|#1A1B26|#292E42|#16161E|#565F89|#737AA2|#C0CAF5|#D5DCF8|#E0AF68|#E2E8FF|#E0AF68|#FF9E64|#F7768E|#BB9AF7|#9D7CD8|#7AA2F7|#7DCFFF|#9ECE6A|#273832|#3B2430|#3B342C|#23344D|#342B44|#2F354D" ;;
        kanagawa-wave)    REPLY="Kanagawa Wave|dark|Kanagawa-Wave-TrueColor|#1F1F28|#2A2A37|#16161D|#7A7970|#939288|#DCD7BA|#EAE6D1|#E6C384|#F2EFE0|#E6C384|#FFA066|#E46876|#D27E99|#957FB8|#7E9CD8|#7AA89F|#98BB6C|#2B3328|#43242B|#49443C|#252535|#3A2836|#2D4F67" ;;
        nord)             REPLY="Nord|dark|Nord-TrueColor|#2E3440|#3B4252|#242933|#8492AC|#96A4BE|#D8DEE9|#E5E9F0|#ECEFF4|#ECEFF4|#EBCB8B|#D08770|#BF616A|#B48EAD|#5E81AC|#81A1C1|#88C0D0|#A3BE8C|#394548|#443943|#494647|#384354|#423F4E|#434C5E" ;;
        onedark)          REPLY="OneDark|dark|OneDark-TrueColor|#282C34|#31353F|#21252B|#5C6370|#7F848E|#ABB2BF|#C8CCD4|#E5C07B|#FFFFFF|#E5C07B|#D19A66|#E06C75|#C678DD|#B268CA|#61AFEF|#56B6C2|#98C379|#2E3E38|#3F2D34|#3E3A34|#283B4C|#3B2F44|#3E4451" ;;
        new-years)        REPLY="New Year's|dark|New-Years-TrueColor|#07081C|#14183D|#040510|#6872AA|#848FC7|#EEF1FF|#FFFFFF|#FFFDF2|#FFFFFF|#44FF77|#FF8024|#FF1744|#5C9DFF|#B388FF|#00F0FF|#FF66C4|#FFD700|#103B2B|#3B1026|#143D29|#063647|#1A294D|#24294D" ;;
        valentines)       REPLY="Valentine's Day|dark|Valentines-TrueColor|#260715|#400D24|#18040D|#A65E7E|#C27898|#FFE8F2|#FFF5F9|#FFFDF9|#FFFFFF|#44F088|#FF8547|#FF1738|#66B2FF|#C77DFF|#FF6BB5|#2EE6C8|#FFD700|#143D31|#520A22|#19422D|#521B38|#332645|#4A1A30" ;;
        st-patricks)      REPLY="St. Patrick's Day|dark|St-Patricks-TrueColor|#042210|#0A3B1E|#021509|#529E6E|#6BB887|#E6FAEC|#F5FFF8|#FFFDF0|#FFFFFF|#FF9100|#FF5722|#FF1744|#FF66B2|#B88CFF|#FFD700|#38E5FF|#00F556|#054A20|#451220|#38390E|#3B4B0D|#382E30|#1B4D2B" ;;
        easter)           REPLY="Easter|light|Easter-TrueColor|#FDF7FF|#F0DCF8|#E4C8F0|#86659C|#6E4E85|#361E4A|#221033|#160822|#0C0312|#A87400|#E04F00|#D5001C|#008B8B|#7B1FA2|#C21878|#0070D6|#009E3D|#D4F5DF|#FAD2D8|#F5E4C3|#F5CFE8|#CEEFEB|#DEC9EC" ;;
        independence-day) REPLY="Independence Day|dark|Independence-Day-TrueColor|#061436|#10275E|#030B20|#6588CC|#85A5E6|#F4F8FF|#FFFFFF|#FFF9E6|#FAFAFF|#2EE6A6|#FF7733|#FF1738|#5CE6FF|#9E8CFF|#38B6FF|#FF6B9E|#FFD700|#0E3B2C|#3D1228|#0E403E|#113864|#163F62|#233769" ;;
        halloween)        REPLY="Halloween|dark|Halloween-TrueColor|#160824|#281040|#0E0418|#7D5BA6|#9B78C4|#EDE2FA|#F8F2FF|#FFF8EB|#FFFFFF|#FFE000|#FF3B00|#FF1744|#FF5CCD|#C77DFF|#55FF47|#2EE6D6|#FF7518|#1B3D26|#440E26|#45331D|#243F2C|#451946|#33204A" ;;
        thanksgiving)     REPLY="Thanksgiving|dark|Thanksgiving-TrueColor|#221107|#381C0C|#150A04|#9C7458|#B88E70|#F7E8D8|#FFF6EB|#FFFDF9|#FFFFFF|#FFD000|#FFA866|#FF1F2D|#FF6699|#C780FF|#FF7814|#38D9B8|#8CE645|#243D14|#4D1214|#4F3809|#4F260B|#4F2224|#472A1A" ;;
        christmas)        REPLY="Christmas|dark|Christmas-TrueColor|#062012|#0E3820|#03140B|#5C9E78|#78B894|#F0FAF4|#FFFFFF|#FFFDF7|#FAFAFF|#38E5FF|#FF7B24|#FF1738|#B8FF3D|#C788FF|#FFD700|#FF6B9E|#2EE66B|#0F4224|#3D1620|#0F3E3B|#3D4A0F|#2A471A|#234231" ;;
        *)                return 1 ;;
    esac
    return 0
}

_hs_bash_holiday_icon() {
    REPLY=""
    case "${1:-}" in
        new-years)        REPLY="🥂" ;;
        valentines)       REPLY="💘" ;;
        st-patricks)      REPLY="🍀" ;;
        easter)           REPLY="🐣" ;;
        independence-day) REPLY="🎆" ;;
        halloween)        REPLY="🎃" ;;
        thanksgiving)     REPLY="🦃" ;;
        christmas)        REPLY="🎄" ;;
        *)                return 1 ;;
    esac
    return 0
}

_hs_bash_blend_hex() {
    local fg="$1" bg="$2" pct="$3"
    local fr=$((16#${fg:1:2})) fg_g=$((16#${fg:3:2})) fb=$((16#${fg:5:2}))
    local br=$((16#${bg:1:2})) bg_g=$((16#${bg:3:2})) bb=$((16#${bg:5:2}))
    local r=$(( (fr * pct + br * (100 - pct) + 50) / 100 ))
    local g=$(( (fg_g * pct + bg_g * (100 - pct) + 50) / 100 ))
    local b=$(( (fb * pct + bb * (100 - pct) + 50) / 100 ))
    printf -v REPLY '#%02X%02X%02X' "$r" "$g" "$b"
}

_hs_bash_safe_hex() {
    local val="${1:-}" fb="$2"
    if [[ "$val" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
        printf -v REPLY '#%02X%02X%02X' "$((16#${val:1:2}))" "$((16#${val:3:2}))" "$((16#${val:5:2}))"
    else
        REPLY="$fb"
    fi
}

_hs_bash_rgb_semi() {
    local h="$1"
    printf -v REPLY '%d;%d;%d' "$((16#${h:1:2}))" "$((16#${h:3:2}))" "$((16#${h:5:2}))"
}

_hs_bash_user_theme_dirs() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
    _HS_USER_DIRS=()
    if [ -n "${HOME_SETTINGS_USER_THEMES_DIR:-}" ]; then
        _HS_USER_DIRS+=("$HOME_SETTINGS_USER_THEMES_DIR")
    fi
    _HS_USER_DIRS+=("$cfg/themes" "$cfg/home-settings/themes")
}

# Safely parse a .theme or .conf file into _HS_RAW_* variables without executing shell code
_hs_bash_reset_raw() {
    _HS_RAW_ID="" _HS_RAW_LABEL="" _HS_RAW_MODE="" _HS_RAW_BAT=""
    _HS_RAW_B03="" _HS_RAW_B02="" _HS_RAW_B04="" _HS_RAW_B01="" _HS_RAW_B00="" _HS_RAW_B0="" _HS_RAW_B1="" _HS_RAW_B2="" _HS_RAW_B3=""
    _HS_RAW_YEL="" _HS_RAW_ORA="" _HS_RAW_RED="" _HS_RAW_MAG="" _HS_RAW_VIO="" _HS_RAW_BLU="" _HS_RAW_CYA="" _HS_RAW_GRN=""
    _HS_RAW_MGRN="" _HS_RAW_MRED="" _HS_RAW_MYEL="" _HS_RAW_MBLU="" _HS_RAW_MMAG="" _HS_RAW_MB1=""
}

_hs_bash_parse_file() {
    local path="$1"
    _hs_bash_reset_raw
    [ -r "$path" ] || return 1
    local line="" k="" v="" q="" rest=""
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] || [[ "$line" == \#* ]] && continue
        if [[ "$line" == "export "* || "$line" == $'export\t'* ]]; then
            line="${line#export}"
            line="${line#"${line%%[![:space:]]*}"}"
        fi
        [[ "$line" == *=* ]] || continue
        k="${line%%=*}"
        k="${k%"${k##*[![:space:]]}"}"
        v="${line#*=}"
        v="${v#"${v%%[![:space:]]*}"}"
        if [ "${#v}" -ge 2 ] && { [[ "$v" == \"* ]] || [[ "$v" == \'* ]]; }; then
            q="${v:0:1}"
            rest="${v:1}"
            if [[ "$rest" == *"$q"* ]]; then
                local after="${rest#*"$q"}"
                after="${after#"${after%%[![:space:]]*}"}"
                if [ -z "$after" ] || [[ "$after" == \#* ]]; then
                    v="${rest%%"$q"*}"
                fi
            fi
        else
            v="${v%"${v##*[![:space:]]}"}"
            if [[ "$v" =~ ^(.*[^[:space:]])[[:space:]]+#.*$ ]]; then
                v="${BASH_REMATCH[1]}"
            elif [[ "$v" == \#* ]] && [[ ! "$v" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
                v=""
            fi
        fi
        case "$k" in
            THEME_ID)       _HS_RAW_ID="$v" ;;
            THEME_LABEL)    _HS_RAW_LABEL="$v" ;;
            THEME_MODE)     _HS_RAW_MODE="$v" ;;
            BAT_THEME_NAME) _HS_RAW_BAT="$v" ;;
            BASE03)         _HS_RAW_B03="$v" ;;
            BASE02)         _HS_RAW_B02="$v" ;;
            BASE04)         _HS_RAW_B04="$v" ;;
            BASE01)         _HS_RAW_B01="$v" ;;
            BASE00)         _HS_RAW_B00="$v" ;;
            BASE0)          _HS_RAW_B0="$v" ;;
            BASE1)          _HS_RAW_B1="$v" ;;
            BASE2)          _HS_RAW_B2="$v" ;;
            BASE3)          _HS_RAW_B3="$v" ;;
            YELLOW)         _HS_RAW_YEL="$v" ;;
            ORANGE)         _HS_RAW_ORA="$v" ;;
            RED)            _HS_RAW_RED="$v" ;;
            MAGENTA)        _HS_RAW_MAG="$v" ;;
            VIOLET)         _HS_RAW_VIO="$v" ;;
            BLUE)           _HS_RAW_BLU="$v" ;;
            CYAN)           _HS_RAW_CYA="$v" ;;
            GREEN)          _HS_RAW_GRN="$v" ;;
            MIX_GREEN)      _HS_RAW_MGRN="$v" ;;
            MIX_RED)        _HS_RAW_MRED="$v" ;;
            MIX_YELLOW)     _HS_RAW_MYEL="$v" ;;
            MIX_BLUE)       _HS_RAW_MBLU="$v" ;;
            MIX_MAGENTA)    _HS_RAW_MMAG="$v" ;;
            MIX_BASE1)      _HS_RAW_MB1="$v" ;;
        esac
    done < "$path"
    return 0
}

_hs_bash_unpack_spec_to_raw() {
    local slug="$1" spec="$2"
    _hs_bash_reset_raw
    _HS_RAW_ID="$slug"
    IFS='|' read -r \
        _HS_RAW_LABEL _HS_RAW_MODE _HS_RAW_BAT \
        _HS_RAW_B03 _HS_RAW_B02 _HS_RAW_B04 _HS_RAW_B01 _HS_RAW_B00 _HS_RAW_B0 _HS_RAW_B1 _HS_RAW_B2 _HS_RAW_B3 \
        _HS_RAW_YEL _HS_RAW_ORA _HS_RAW_RED _HS_RAW_MAG _HS_RAW_VIO _HS_RAW_BLU _HS_RAW_CYA _HS_RAW_GRN \
        _HS_RAW_MGRN _HS_RAW_MRED _HS_RAW_MYEL _HS_RAW_MBLU _HS_RAW_MMAG _HS_RAW_MB1 <<< "$spec"
}

_hs_bash_find_user_theme_file() {
    REPLY=""
    local slug="$1"
    [[ "$slug" == [a-z0-9]* && "$slug" != */* && "$slug" != *..* ]] || return 1
    _hs_bash_user_theme_dirs
    local udir cand stem cid d_idx has_dir=0
    for ((d_idx = 0; d_idx < ${#_HS_USER_DIRS[@]}; d_idx++)); do
        udir="${_HS_USER_DIRS[$d_idx]}"
        [ -d "$udir" ] || continue
        has_dir=1
        for cand in "$udir/$slug.theme" "$udir/$slug.conf"; do
            if [ -r "$cand" ]; then
                _hs_bash_parse_file "$cand" || continue
                _hs_bash_norm_slug "${_HS_RAW_ID:-$slug}"
                if [ "$REPLY" = "$slug" ]; then
                    REPLY="$cand"
                    return 0
                fi
            fi
        done
    done
    (( has_dir == 0 )) && return 1
    local -a cands=()
    local had_fg=0 had_ng=0
    shopt -q failglob && had_fg=1
    shopt -q nullglob && had_ng=1
    shopt -u failglob
    shopt -s nullglob
    for ((d_idx = 0; d_idx < ${#_HS_USER_DIRS[@]}; d_idx++)); do
        udir="${_HS_USER_DIRS[$d_idx]}"
        [ -d "$udir" ] && cands+=("$udir"/*.theme "$udir"/*.conf)
    done
    (( had_ng == 0 )) && shopt -u nullglob
    (( had_fg == 1 )) && shopt -s failglob
    for cand in ${cands[@]+"${cands[@]}"}; do
        [ -r "$cand" ] || continue
        stem="${cand##*/}"
        stem="${stem%.*}"
        [ "$stem" = "active-theme" ] && continue
        _hs_bash_parse_file "$cand" || continue
        _hs_bash_norm_slug "${_HS_RAW_ID:-$stem}"
        cid="$REPLY"
        if [ "$cid" = "$slug" ]; then
            REPLY="$cand"
            return 0
        fi
    done
    REPLY=""
    return 1
}

_hs_bash_resolve_slug_to_raw() {
    _hs_bash_norm_slug "${1:-}"
    local slug="$REPLY"
    [[ "$slug" == [a-z0-9]* && "$slug" != */* && "$slug" != *..* ]] || return 1
    _HS_RESOLVED_UFILE=""
    if _hs_bash_find_user_theme_file "$slug"; then
        _HS_RESOLVED_UFILE="$REPLY"
        _hs_bash_parse_file "$_HS_RESOLVED_UFILE" || return 1
        [ -z "$_HS_RAW_ID" ] && _HS_RAW_ID="$slug"
        return 0
    fi
    if [ -n "${_HS_BASHRC_REPO_ROOT:-}" ] && [ -r "$_HS_BASHRC_REPO_ROOT/colors/themes/$slug.theme" ]; then
        _hs_bash_parse_file "$_HS_BASHRC_REPO_ROOT/colors/themes/$slug.theme" || return 1
        [ -z "$_HS_RAW_ID" ] && _HS_RAW_ID="$slug"
        return 0
    fi
    if _hs_bash_builtin_spec "$slug"; then
        _hs_bash_unpack_spec_to_raw "$slug" "$REPLY"
        return 0
    fi
    return 1
}

# Finalize _HS_RAW_* into validated _HS_C_* palette (filling defaults + blended tints)
_hs_bash_finalize_palette() {
    local fallback_slug="${1:-solarized-dark}"
    _hs_bash_norm_slug "${_HS_RAW_ID:-$fallback_slug}"
    _HS_C_ID="${REPLY:-solarized-dark}"
    [[ "$_HS_C_ID" =~ ^[a-z0-9][a-z0-9-]*$ ]] || _HS_C_ID="solarized-dark"
    _hs_bash_norm_slug "${_HS_RAW_MODE:-dark}"
    if [ "$REPLY" = "light" ]; then
        _HS_C_MODE="light"
    else
        _HS_C_MODE="dark"
    fi

    local base_spec=""
    if [ "$_HS_C_MODE" = "light" ]; then
        _hs_bash_builtin_spec "solarized-light"
    else
        _hs_bash_builtin_spec "solarized-dark"
    fi
    base_spec="$REPLY"
    local _bl _bm _bb db03 db02 db04 db01 db00 db0 db1 db2 db3 dyel dora dred dmag dvio dblu dcya dgrn dmgrn dmred dmyel dmblu dmmag dmb1
    IFS='|' read -r _bl _bm _bb db03 db02 db04 db01 db00 db0 db1 db2 db3 dyel dora dred dmag dvio dblu dcya dgrn dmgrn dmred dmyel dmblu dmmag dmb1 <<< "$base_spec"

    if [ -n "$_HS_RAW_LABEL" ]; then
        _HS_C_LABEL="$_HS_RAW_LABEL"
    elif _hs_bash_builtin_spec "$_HS_C_ID"; then
        _HS_C_LABEL="${REPLY%%|*}"
    else
        _HS_C_LABEL="$_HS_C_ID"
    fi
    _HS_C_LABEL="${_HS_C_LABEL//$'\r'/}"
    _HS_C_LABEL="${_HS_C_LABEL//$'\n'/ }"
    _HS_C_LABEL="${_HS_C_LABEL//\"/}"
    _HS_C_LABEL="${_HS_C_LABEL//\\/}"
    _HS_C_LABEL="${_HS_C_LABEL//\$/}"
    _HS_C_LABEL="${_HS_C_LABEL//\`/}"
    [ -z "$_HS_C_LABEL" ] && _HS_C_LABEL="$_HS_C_ID"

    if [ -n "$_HS_RAW_BAT" ] && [[ "$_HS_RAW_BAT" =~ ^[A-Za-z0-9._-]+$ ]]; then
        _HS_C_BAT="$_HS_RAW_BAT"
    elif _hs_bash_builtin_spec "$_HS_C_ID"; then
        local rem="${REPLY#*|}"
        rem="${rem#*|}"
        _HS_C_BAT="${rem%%|*}"
    else
        local part="" cap="" pascal="" rest_id="$_HS_C_ID"
        while [ -n "$rest_id" ]; do
            if [[ "$rest_id" == *-* ]]; then
                part="${rest_id%%-*}"
                rest_id="${rest_id#*-}"
            else
                part="$rest_id"
                rest_id=""
            fi
            if [ -n "$part" ]; then
                cap="${part:0:1}"
                case "$cap" in
                    a) cap=A ;; b) cap=B ;; c) cap=C ;; d) cap=D ;; e) cap=E ;; f) cap=F ;;
                    g) cap=G ;; h) cap=H ;; i) cap=I ;; j) cap=J ;; k) cap=K ;; l) cap=L ;;
                    m) cap=M ;; n) cap=N ;; o) cap=O ;; p) cap=P ;; q) cap=Q ;; r) cap=R ;;
                    s) cap=S ;; t) cap=T ;; u) cap=U ;; v) cap=V ;; w) cap=W ;; x) cap=X ;;
                    y) cap=Y ;; z) cap=Z ;;
                esac
                pascal="${pascal:+$pascal-}${cap}${part:1}"
            fi
        done
        _HS_C_BAT="${pascal:-Solarized-Dark}-TrueColor"
    fi

    _hs_bash_safe_hex "$_HS_RAW_B03" "$db03"; _HS_C_B03="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_B02" "$db02"; _HS_C_B02="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_B01" "$db01"; _HS_C_B01="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_B00" "$db00"; _HS_C_B00="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_B0"  "$db0";  _HS_C_B0="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_B1"  "$db1";  _HS_C_B1="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_B2"  "$db2";  _HS_C_B2="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_B3"  "$db3";  _HS_C_B3="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_YEL" "$dyel"; _HS_C_YEL="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_ORA" "$dora"; _HS_C_ORA="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_RED" "$dred"; _HS_C_RED="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_MAG" "$dmag"; _HS_C_MAG="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_VIO" "$dvio"; _HS_C_VIO="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_BLU" "$dblu"; _HS_C_BLU="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_CYA" "$dcya"; _HS_C_CYA="$REPLY"
    _hs_bash_safe_hex "$_HS_RAW_GRN" "$dgrn"; _HS_C_GRN="$REPLY"

    local fb
    if [ "$_HS_C_B03" = "$db03" ] && [ "$_HS_C_B02" = "$db02" ]; then fb="$db04";  else _hs_bash_blend_hex "$_HS_C_B02" "$_HS_C_B03" 50; fb="$REPLY"; fi; _hs_bash_safe_hex "$_HS_RAW_B04"  "$fb"; _HS_C_B04="$REPLY"
    if [ "$_HS_C_B03" = "$db03" ] && [ "$_HS_C_GRN" = "$dgrn" ]; then fb="$dmgrn"; else _hs_bash_blend_hex "$_HS_C_GRN" "$_HS_C_B03" 18; fb="$REPLY"; fi; _hs_bash_safe_hex "$_HS_RAW_MGRN" "$fb"; _HS_C_MGRN="$REPLY"
    if [ "$_HS_C_B03" = "$db03" ] && [ "$_HS_C_RED" = "$dred" ]; then fb="$dmred"; else _hs_bash_blend_hex "$_HS_C_RED" "$_HS_C_B03" 18; fb="$REPLY"; fi; _hs_bash_safe_hex "$_HS_RAW_MRED" "$fb"; _HS_C_MRED="$REPLY"
    if [ "$_HS_C_B03" = "$db03" ] && [ "$_HS_C_YEL" = "$dyel" ]; then fb="$dmyel"; else _hs_bash_blend_hex "$_HS_C_YEL" "$_HS_C_B03" 20; fb="$REPLY"; fi; _hs_bash_safe_hex "$_HS_RAW_MYEL" "$fb"; _HS_C_MYEL="$REPLY"
    if [ "$_HS_C_B03" = "$db03" ] && [ "$_HS_C_BLU" = "$dblu" ]; then fb="$dmblu"; else _hs_bash_blend_hex "$_HS_C_BLU" "$_HS_C_B03" 22; fb="$REPLY"; fi; _hs_bash_safe_hex "$_HS_RAW_MBLU" "$fb"; _HS_C_MBLU="$REPLY"
    if [ "$_HS_C_B03" = "$db03" ] && [ "$_HS_C_MAG" = "$dmag" ]; then fb="$dmmag"; else _hs_bash_blend_hex "$_HS_C_MAG" "$_HS_C_B03" 20; fb="$REPLY"; fi; _hs_bash_safe_hex "$_HS_RAW_MMAG" "$fb"; _HS_C_MMAG="$REPLY"
    if [ "$_HS_C_B03" = "$db03" ] && [ "$_HS_C_B1"  = "$db1"  ]; then fb="$dmb1";  else _hs_bash_blend_hex "$_HS_C_B1"  "$_HS_C_B03" 16; fb="$REPLY"; fi; _hs_bash_safe_hex "$_HS_RAW_MB1"  "$fb"; _HS_C_MB1="$REPLY"
}

_hs_bash_build_truecolor_ls_colors() {
    local b03="$1" b02="$2" b01="$3" b0="$4" b2="$5" yel="$6" ora="$7" red="$8" mag="$9" vio="${10}" blu="${11}" cya="${12}" grn="${13}"
    local ls_out=":$_HS_ANSI_LS_COLORS"
    ls_out="${ls_out//:su=37;41:/:su=38;2;${b2};48;2;${red}:}"
    ls_out="${ls_out//:sg=30;43:/:sg=38;2;${b03};48;2;${yel}:}"
    ls_out="${ls_out//:ca=30;41:/:ca=38;2;${b03};48;2;${red}:}"
    ls_out="${ls_out//:tw=30;42:/:tw=38;2;${b03};48;2;${grn}:}"
    ls_out="${ls_out//:ow=34;40:/:ow=38;2;${blu};48;2;${b02}:}"
    ls_out="${ls_out//:st=37;44:/:st=38;2;${b2};48;2;${blu}:}"
    ls_out="${ls_out//:di=34:/:di=38;2;${blu}:}"
    ls_out="${ls_out//:ln=36:/:ln=38;2;${cya}:}"
    ls_out="${ls_out//:pi=33:/:pi=38;2;${yel}:}"
    ls_out="${ls_out//:so=35:/:so=38;2;${mag}:}"
    ls_out="${ls_out//:do=35:/:do=38;2;${mag}:}"
    ls_out="${ls_out//:bd=35:/:bd=38;2;${mag}:}"
    ls_out="${ls_out//:cd=35:/:cd=38;2;${mag}:}"
    ls_out="${ls_out//:or=31:/:or=38;2;${red}:}"
    ls_out="${ls_out//:mi=31:/:mi=38;2;${red}:}"
    ls_out="${ls_out//:ex=32:/:ex=38;2;${grn}:}"
    ls_out="${ls_out//:mh=00:/:mh=__MH00__:}"
    ls_out="${ls_out//=91:/=38;2;${ora}:}"
    ls_out="${ls_out//=95:/=38;2;${vio}:}"
    ls_out="${ls_out//=35:/=38;2;${mag}:}"
    ls_out="${ls_out//=90:/=38;2;${b01}:}"
    ls_out="${ls_out//=00:/=38;2;${b0}:}"
    ls_out="${ls_out//:mh=__MH00__:/:mh=00:}"
    REPLY="${ls_out#:}fi=38;2;${b0}:"
}

_HS_RL_VARS=""
_HS_LAST_RL_REGION_SPEC=""
if [[ "$-" == *i* ]] && [[ -o emacs || -o vi ]]; then
    _HS_RL_VARS="$(builtin bind -v)"
fi

_hs_bash_refresh_readline_region() {
    [[ "$-" == *i* ]] && [[ -o emacs || -o vi ]] || return 0
    [[ "${_HS_RL_VARS:-}" == *"enable-active-region"* ]] || return 0
    local want_spec r_b1="147;161;161" r_b02="7;54;66" v
    if [ -n "${NO_COLOR:-}" ]; then
        want_spec="off"
    elif _hs_bash_is_truecolor; then
        if [ -n "${_HS_PROMPT_FG_BASE1:-}" ]; then
            v="${_HS_PROMPT_FG_BASE1#*38;2;}"
            r_b1="${v%%m*}"
        fi
        if [ -n "${_HS_PROMPT_BG_BASE02:-}" ]; then
            v="${_HS_PROMPT_BG_BASE02#*48;2;}"
            r_b02="${v%%m*}"
        fi
        want_spec="tc:${r_b1}:${r_b02}"
    else
        want_spec="ansi7"
    fi
    [ "${_HS_LAST_RL_REGION_SPEC:-}" = "$want_spec" ] && return 0
    _HS_LAST_RL_REGION_SPEC="$want_spec"
    if [ "$want_spec" = "off" ]; then
        builtin bind 'set enable-active-region off'
    elif [ "$want_spec" = "ansi7" ]; then
        builtin bind 'set enable-active-region on'
        if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 2) )) || [[ "${_HS_RL_VARS:-}" == *"active-region-start-color"* ]]; then
            builtin bind 'set active-region-start-color \e[7m'
            builtin bind 'set active-region-end-color \e[27m'
        fi
    else
        builtin bind 'set enable-active-region on'
        if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 2) )) || [[ "${_HS_RL_VARS:-}" == *"active-region-start-color"* ]]; then
            builtin bind "set active-region-start-color \e[38;2;${r_b1};48;2;${r_b02}m"
            builtin bind 'set active-region-end-color \e[0m'
        fi
    fi
}

# Apply finalized _HS_C_* palette directly to current Bash environment (zero forks)
_hs_bash_apply_finalized_palette() {
    local b03 b02 b01 b00 b0 b1 b2 yel ora red mag vio blu cya grn
    _hs_bash_rgb_semi "$_HS_C_B03"; b03="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_B02"; b02="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_B01"; b01="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_B00"; b00="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_B0";  b0="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_B1";  b1="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_B2";  b2="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_YEL"; yel="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_ORA"; ora="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_RED"; red="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_MAG"; mag="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_VIO"; vio="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_BLU"; blu="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_CYA"; cya="$REPLY"
    _hs_bash_rgb_semi "$_HS_C_GRN"; grn="$REPLY"

    _HS_INTERNAL_ENV_THEME="$_HS_C_ID"
    export HOME_SETTINGS_THEME="$_HS_C_ID"
    export HOME_SETTINGS_THEME_MODE="$_HS_C_MODE"
    export BAT_THEME="$_HS_C_BAT"
    export FZF_DEFAULT_OPTS="--color=bg+:${_HS_C_B02},bg:${_HS_C_B03},spinner:${_HS_C_GRN},hl:${_HS_C_B01} --color=fg:${_HS_C_B0},header:${_HS_C_B01},info:${_HS_C_YEL},pointer:${_HS_C_GRN} --color=marker:${_HS_C_GRN},fg+:${_HS_C_B1},prompt:${_HS_C_YEL},hl+:${_HS_C_BLU} --layout=reverse --border=rounded --info=inline"
    export EZA_COLORS="di=38;2;${blu}:ex=38;2;${grn}:fi=38;2;${b0}:pi=38;2;${yel}:so=38;2;${mag}:bd=38;2;${mag}:cd=38;2;${mag}:ln=38;2;${cya}:or=38;2;${red}:xx=38;2;${b01}:da=38;2;${b0}:hd=4;38;2;${b1}:lp=38;2;${b0}:cc=38;2;${ora}:bO=38;2;${red}:in=38;2;${b01}:bl=38;2;${b01}:oc=38;2;${b0}:ur=38;2;${b0}:uw=38;2;${b0}:ux=38;2;${b0}:ue=38;2;${b0}:gr=38;2;${b0}:gw=38;2;${b0}:gx=38;2;${b0}:tr=38;2;${b0}:tw=38;2;${b0}:tx=38;2;${b0}:su=38;2;${b0}:sf=38;2;${b0}:xa=38;2;${b0}:sn=38;2;${b0}:nb=38;2;${b01}:nk=38;2;${b0}:nm=38;2;${yel}:ng=38;2;${ora}:nt=38;2;${red}:sb=38;2;${b0}:ub=38;2;${b01}:uk=38;2;${b0}:um=38;2;${yel}:ug=38;2;${ora}:ut=38;2;${red}:df=38;2;${b0}:ds=38;2;${b0}:uu=38;2;${b0}:uR=38;2;${red}:un=38;2;${b0}:gu=38;2;${b0}:gR=38;2;${red}:gn=38;2;${b0}:lc=38;2;${b0}:lm=38;2;${yel}:ga=38;2;${grn}:gm=38;2;${yel}:gd=38;2;${red}:gv=38;2;${b0}:gt=38;2;${b0}:gi=38;2;${b01}:gc=38;2;${red}:Gm=38;2;${grn}:Go=38;2;${blu}:Gc=38;2;${grn}:Gd=38;2;${yel}:sp=38;2;${ora}:mp=38;2;${blu}:im=38;2;${vio}:vi=38;2;${vio}:mu=38;2;${vio}:lo=38;2;${vio}:cr=38;2;${mag}:do=38;2;${b0}:co=38;2;${ora}:tm=38;2;${b01}:cm=38;2;${b01}:bu=38;2;${grn}:sc=38;2;${b0}:Sn=38;2;${b01}:Su=38;2;${b0}:Sr=38;2;${b0}:St=38;2;${b0}:Sl=38;2;${b0}:ff=38;2;${b0}"
    export EXA_COLORS="$EZA_COLORS"
    export JQ_COLORS="38;2;${mag}:38;2;${mag}:38;2;${mag}:38;2;${mag}:38;2;${cya}:38;2;${b0}:38;2;${b0}:38;2;${grn}"
    export LESS="${LESS:--R}"
    export GROFF_NO_SGR=1
    local esc=$'\033'
    export LESS_TERMCAP_mb="${esc}[38;2;${red}m"
    export LESS_TERMCAP_md="${esc}[1;38;2;${blu}m"
    export LESS_TERMCAP_me="${esc}[0m"
    export LESS_TERMCAP_so="${esc}[38;2;${b1};48;2;${b02}m"
    export LESS_TERMCAP_se="${esc}[0m"
    export LESS_TERMCAP_us="${esc}[4;38;2;${cya}m"
    export LESS_TERMCAP_ue="${esc}[0m"
    export _HS_ESC_ORANGE="${esc}[38;2;${ora}m"
    export _HS_ESC_BLUE="${esc}[38;2;${blu}m"
    export _HS_ESC_CYAN="${esc}[38;2;${cya}m"
    export _HS_ESC_BASE0="${esc}[38;2;${b0}m"
    export _HS_ESC_BASE01="${esc}[38;2;${b01}m"
    export LSCOLORS="exgxfxdxcxfxfxegedabagacad"

    _hs_bash_build_truecolor_ls_colors "$b03" "$b02" "$b01" "$b0" "$b2" "$yel" "$ora" "$red" "$mag" "$vio" "$blu" "$cya" "$grn"
    _HS_LAST_TC_LS_COLORS="$REPLY"
    if _hs_bash_is_truecolor; then
        export LS_COLORS="$_HS_LAST_TC_LS_COLORS"
    else
        _hs_bash_apply_ansi_ls_colors
    fi

    if _hs_bash_holiday_icon "$_HS_C_ID"; then
        export _HS_PROMPT_OS_ICON="$REPLY"
    else
        unset _HS_PROMPT_OS_ICON
    fi

    export _HS_PROMPT_BG_BASE02="\\[\\e[48;2;${b02}m\\]"
    export _HS_PROMPT_CAP_BASE02="\\[\\e[0m\\e[38;2;${b02}m\\]"
    export _HS_PROMPT_CAP_RED="\\[\\e[0m\\e[38;2;${red}m\\]"
    export _HS_PROMPT_FG_BASE02="\\[\\e[38;2;${b02}m\\]"
    export _HS_PROMPT_FG_BASE01="\\[\\e[38;2;${b01}m\\]"
    export _HS_PROMPT_FG_BASE00="\\[\\e[38;2;${b00}m\\]"
    export _HS_PROMPT_FG_BASE0="\\[\\e[38;2;${b0}m\\]"
    export _HS_PROMPT_FG_BASE1="\\[\\e[38;2;${b1}m\\]"
    export _HS_PROMPT_FG_YELLOW="\\[\\e[38;2;${yel}m\\]"
    export _HS_PROMPT_FG_ORANGE="\\[\\e[38;2;${ora}m\\]"
    export _HS_PROMPT_FG_RED="\\[\\e[38;2;${red}m\\]"
    export _HS_PROMPT_FG_VIOLET="\\[\\e[38;2;${vio}m\\]"
    export _HS_PROMPT_FG_BLUE="\\[\\e[38;2;${blu}m\\]"
    export _HS_PROMPT_FG_CYAN="\\[\\e[38;2;${cya}m\\]"
    export _HS_PROMPT_FG_GREEN="\\[\\e[38;2;${grn}m\\]"
    export _HS_LOADED_THEME="$_HS_C_ID"
    _hs_bash_refresh_readline_region
}

# Synchronize active theme state (startup & cross-pane prompt check; zero subprocess forks)
_hs_bash_sync_theme_state() {
    local is_startup="${1:-0}"
    local hs_dir="${XDG_CONFIG_HOME:-$HOME/.config}/home-settings"

    # Track explicit caller overrides (including VAR=val prefix assignments on `source`)
    local cur_tfile_state="${HOME_SETTINGS_THEME_FILE-__UNSET__}"
    if [ "$is_startup" = "1" ]; then
        _HS_USER_ENV_THEME="$_HS_CALLER_THEME_PRE"
        _HS_USER_ENV_TFILE="$_HS_CALLER_TFILE_PRE"
        _HS_POST_SOURCE_SYNC=1
        _HS_LAST_SEEN_TFILE="$cur_tfile_state"
    elif [ "${_HS_POST_SOURCE_SYNC:-0}" = "1" ]; then
        _HS_POST_SOURCE_SYNC=0
        _HS_LAST_SEEN_TFILE="$cur_tfile_state"
        if [ -n "${HOME_SETTINGS_THEME_FILE:-}" ]; then
            _HS_USER_ENV_TFILE="$HOME_SETTINGS_THEME_FILE"
        fi
        if [ -n "${HOME_SETTINGS_THEME:-}" ] && [ "${HOME_SETTINGS_THEME}" != "${_HS_INTERNAL_ENV_THEME:-}" ]; then
            _HS_USER_ENV_THEME="$HOME_SETTINGS_THEME"
        elif [ -z "${HOME_SETTINGS_THEME:-}" ] && [ -n "${_HS_USER_ENV_THEME:-}" ] && [ -n "${_HS_INTERNAL_ENV_THEME:-}" ]; then
            export HOME_SETTINGS_THEME="$_HS_INTERNAL_ENV_THEME"
        fi
    else
        if [ "$cur_tfile_state" != "${_HS_LAST_SEEN_TFILE:-__UNSET__}" ]; then
            _HS_LAST_SEEN_TFILE="$cur_tfile_state"
            _HS_USER_ENV_TFILE="${HOME_SETTINGS_THEME_FILE:-}"
        fi
        if [ "${HOME_SETTINGS_THEME:-}" != "${_HS_INTERNAL_ENV_THEME:-}" ]; then
            _HS_USER_ENV_THEME="${HOME_SETTINGS_THEME:-}"
        fi
    fi

    # 1. Explicit $HOME_SETTINGS_THEME_FILE override
    local eff_tfile="${HOME_SETTINGS_THEME_FILE:-${_HS_USER_ENV_TFILE:-}}"
    if [ -n "$eff_tfile" ]; then
        if [ -r "$eff_tfile" ]; then
            local tf_raw=""
            IFS= read -r -d '' tf_raw < "$eff_tfile" || true
            if [ "$tf_raw" != "${_HS_LOADED_TFILE_RAW:-}" ] || [ "${_HS_LOADED_TFILE_PATH:-}" != "$eff_tfile" ]; then
                _HS_LOADED_TFILE_RAW="$tf_raw"
                _HS_LOADED_TFILE_PATH="$eff_tfile"
                _hs_bash_parse_file "$eff_tfile" || return 0
                local stem="${eff_tfile##*/}"
                _hs_bash_finalize_palette "${stem%.*}"
                _hs_bash_apply_finalized_palette
            elif [ -z "${HOME_SETTINGS_THEME:-}" ] && [ -n "${_HS_LOADED_THEME:-}" ]; then
                export HOME_SETTINGS_THEME="$_HS_LOADED_THEME"
            fi
        elif [ -n "${_HS_USER_ENV_THEME:-}" ]; then
            _hs_bash_norm_slug "$_HS_USER_ENV_THEME"
            local req="$REPLY"
            if [ "${_HS_LOADED_THEME:-}" != "$req" ] && _hs_bash_resolve_slug_to_raw "$req"; then
                _hs_bash_finalize_palette "$req"
                _hs_bash_apply_finalized_palette
            fi
        elif [ -n "${_HS_LOADED_THEME:-}" ]; then
            _hs_bash_builtin_spec "solarized-dark" && _hs_bash_unpack_spec_to_raw "solarized-dark" "$REPLY"
            _hs_bash_finalize_palette "solarized-dark"
            _hs_bash_apply_finalized_palette
            unset HOME_SETTINGS_THEME HOME_SETTINGS_THEME_MODE _HS_INTERNAL_ENV_THEME _HS_LOADED_THEME _HS_LAST_TC_LS_COLORS _HS_PROMPT_OS_ICON
            _hs_bash_apply_ansi_ls_colors
        fi
        if ! _hs_bash_is_truecolor; then
            if [[ "${LS_COLORS:-}" == *"38;2;"* ]]; then
                _hs_bash_apply_ansi_ls_colors
            fi
        elif [ -n "${_HS_LOADED_THEME:-}" ] && [ -n "${_HS_LAST_TC_LS_COLORS:-}" ] && [[ "${LS_COLORS:-}" != *"38;2;"* ]]; then
            export LS_COLORS="$_HS_LAST_TC_LS_COLORS"
        fi
        _hs_bash_refresh_readline_region
        return 0
    fi

    # 2. Persistent state directory ($XDG_CONFIG_HOME/home-settings)
    local active_theme=""
    if [ -r "$hs_dir/theme" ]; then
        IFS= read -r active_theme < "$hs_dir/theme" || true
        active_theme="${active_theme//$'\r'/}"
        _hs_bash_norm_slug "$active_theme"
        active_theme="$REPLY"
    fi

    if [ -n "$active_theme" ]; then
        # Check if a custom user .theme/.conf file was edited at or after theme-env.sh (including same-second edits)
        local ufile=""
        if _hs_bash_find_user_theme_file "$active_theme"; then
            ufile="$REPLY"
        fi
        if [ -n "$ufile" ] && { [ ! -r "$hs_dir/theme-env.sh" ] || ! [ "$hs_dir/theme-env.sh" -nt "$ufile" ]; }; then
            local uf_raw=""
            IFS= read -r -d '' uf_raw < "$ufile" || true
            if [ "${_HS_LOADED_THEME:-}" != "$active_theme" ] || [ "$uf_raw" != "${_HS_LOADED_UFILE_RAW:-}" ]; then
                _HS_LOADED_UFILE_RAW="$uf_raw"
                _HS_LOADED_ENV_RAW=""
                _hs_bash_parse_file "$ufile" || return 0
                _hs_bash_finalize_palette "$active_theme"
                _hs_bash_apply_finalized_palette
            fi
        elif [ -r "$hs_dir/theme-env.sh" ]; then
            local env_raw=""
            IFS= read -r -d '' env_raw < "$hs_dir/theme-env.sh" || true
            # Guard against partial writes: verify complete footer matching active_theme before sourcing
            if [[ "$env_raw" == *"_HS_LOADED_THEME='${active_theme}'"* || "$env_raw" == *"_HS_LOADED_THEME=\"${active_theme}\""* ]]; then
                if [ "${_HS_LOADED_THEME:-}" != "$active_theme" ] || [ "$env_raw" != "${_HS_LOADED_ENV_RAW:-}" ]; then
                    _HS_LOADED_ENV_RAW="$env_raw"
                    _HS_LOADED_UFILE_RAW=""
                    # shellcheck source=/dev/null
                    . "$hs_dir/theme-env.sh"
                    [[ "${LS_COLORS:-}" == *"38;2;"* ]] && _HS_LAST_TC_LS_COLORS="$LS_COLORS"
                    _HS_INTERNAL_ENV_THEME="${HOME_SETTINGS_THEME:-$active_theme}"
                fi
            elif { [ -z "$env_raw" ] || [[ "$env_raw" == *"_HS_LOADED_THEME="* ]]; } && [ "${_HS_LOADED_THEME:-}" != "$active_theme" ]; then
                # theme-env.sh is empty or complete for an older theme (not a partial write): load active-theme.theme or slug
                local loaded_from_af=0
                if [ -r "$hs_dir/active-theme.theme" ] && _hs_bash_parse_file "$hs_dir/active-theme.theme"; then
                    _hs_bash_norm_slug "${_HS_RAW_ID:-}"
                    if [ "$REPLY" = "$active_theme" ]; then
                        _hs_bash_finalize_palette "$active_theme"
                        _hs_bash_apply_finalized_palette
                        loaded_from_af=1
                    fi
                fi
                if [ "$loaded_from_af" -eq 0 ] && _hs_bash_resolve_slug_to_raw "$active_theme"; then
                    _hs_bash_finalize_palette "$active_theme"
                    _hs_bash_apply_finalized_palette
                fi
            fi
        elif [ -r "$hs_dir/active-theme.theme" ]; then
            local af_raw=""
            IFS= read -r -d '' af_raw < "$hs_dir/active-theme.theme" || true
            if [ "${_HS_LOADED_THEME:-}" != "$active_theme" ] || [ "$af_raw" != "${_HS_LOADED_ENV_RAW:-}" ]; then
                _HS_LOADED_ENV_RAW="$af_raw"
                _hs_bash_parse_file "$hs_dir/active-theme.theme" || return 0
                _hs_bash_finalize_palette "$active_theme"
                _hs_bash_apply_finalized_palette
            fi
        elif [ "${_HS_LOADED_THEME:-}" != "$active_theme" ] && _hs_bash_resolve_slug_to_raw "$active_theme"; then
            _hs_bash_finalize_palette "$active_theme"
            _hs_bash_apply_finalized_palette
        fi
    elif [ -r "$hs_dir/theme-env.sh" ]; then
        local env_raw=""
        IFS= read -r -d '' env_raw < "$hs_dir/theme-env.sh" || true
        if [[ "$env_raw" == *"_HS_LOADED_THEME="* ]] && [ "$env_raw" != "${_HS_LOADED_ENV_RAW:-}" ]; then
            _HS_LOADED_ENV_RAW="$env_raw"
            # shellcheck source=/dev/null
            . "$hs_dir/theme-env.sh"
            [[ "${LS_COLORS:-}" == *"38;2;"* ]] && _HS_LAST_TC_LS_COLORS="$LS_COLORS"
            _HS_INTERNAL_ENV_THEME="${HOME_SETTINGS_THEME:-}"
        fi
    elif [ -r "$hs_dir/active-theme.theme" ]; then
        local af_raw=""
        IFS= read -r -d '' af_raw < "$hs_dir/active-theme.theme" || true
        if [ "$af_raw" != "${_HS_LOADED_ENV_RAW:-}" ]; then
            _HS_LOADED_ENV_RAW="$af_raw"
            _hs_bash_parse_file "$hs_dir/active-theme.theme" || return 0
            _hs_bash_finalize_palette "solarized-dark"
            _hs_bash_apply_finalized_palette
        fi
    elif [ -n "${_HS_USER_ENV_THEME:-}" ]; then
        _hs_bash_norm_slug "$_HS_USER_ENV_THEME"
        local env_slug="$REPLY"
        if [ -n "$env_slug" ] && [ "${_HS_LOADED_THEME:-}" != "$env_slug" ] && _hs_bash_resolve_slug_to_raw "$env_slug"; then
            _hs_bash_finalize_palette "$env_slug"
            _hs_bash_apply_finalized_palette
        elif [ -n "$env_slug" ] && [ "${_HS_LOADED_THEME:-}" = "$env_slug" ] && [ -z "${HOME_SETTINGS_THEME:-}" ]; then
            export HOME_SETTINGS_THEME="$_HS_LOADED_THEME"
        fi
    elif [ -n "${_HS_LOADED_THEME:-}" ]; then
        _HS_LOADED_ENV_RAW=""
        _HS_LOADED_UFILE_RAW=""
        _hs_bash_builtin_spec "solarized-dark" && _hs_bash_unpack_spec_to_raw "solarized-dark" "$REPLY"
        _hs_bash_finalize_palette "solarized-dark"
        _hs_bash_apply_finalized_palette
        unset HOME_SETTINGS_THEME HOME_SETTINGS_THEME_MODE _HS_INTERNAL_ENV_THEME _HS_LOADED_THEME _HS_LAST_TC_LS_COLORS _HS_PROMPT_OS_ICON
        _hs_bash_apply_ansi_ls_colors
    fi

    if ! _hs_bash_is_truecolor; then
        if [[ "${LS_COLORS:-}" == *"38;2;"* ]]; then
            _hs_bash_apply_ansi_ls_colors
        fi
    elif [ -n "${_HS_LOADED_THEME:-}" ] && [ -n "${_HS_LAST_TC_LS_COLORS:-}" ] && [[ "${LS_COLORS:-}" != *"38;2;"* ]]; then
        export LS_COLORS="$_HS_LAST_TC_LS_COLORS"
    fi
    _hs_bash_refresh_readline_region
}
