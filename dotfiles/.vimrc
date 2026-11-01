" Indentation & Formatting (compatible with minimal -eval vim.tiny builds)
set nocompatible
set tabstop=4
set shiftwidth=4
set expandtab
set background=dark
set t_RB=
map <Home> ^
imap <Home> <Esc>^i

if 1
filetype plugin indent on

" TrueColor (24-bit) Terminal Support & Focus Events (Vim 8/9+)
if !has('nvim') && !has('gui_running') && &term =~# '^\(tmux\|screen\|xterm\|rxvt\|alacritty\|wezterm\|foot\)'
    silent! let &t_fe = "\<Esc>[?1004h"
    silent! let &t_fd = "\<Esc>[?1004l"
endif
if has('termguicolors') && &term !=# 'linux'
    let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
    let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
    if $COLORTERM ==# 'truecolor' || $COLORTERM ==# '24bit' || $TERM =~# '^\(xterm-ghostty\|wezterm\|alacritty\|xterm-kitty\|foot\)'
        set termguicolors
    endif
endif

" Zero-Dependency Inline Solarized Dark Fallback and Dynamic 17-Theme + Custom Palette Engine
let s:vimrc_repo_root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')

let s:builtin_theme_order = [
    \ 'solarized-dark', 'solarized-light', 'catppuccin-mocha', 'catppuccin-latte',
    \ 'gruvbox-dark', 'tokyonight-night', 'kanagawa-wave', 'nord', 'onedark',
    \ 'new-years', 'valentines', 'st-patricks', 'easter',
    \ 'independence-day', 'halloween', 'thanksgiving', 'christmas'
    \ ]

" Compact 26-field built-in palette table (1:1 with colors/themes/*.theme for 2-file standalone servers):
" LABEL|MODE|BAT_THEME|B03|B02|B04|B01|B00|B0|B1|B2|B3|YEL|ORA|RED|MAG|VIO|BLU|CYA|GRN|MGRN|MRED|MYEL|MBLU|MMAG|MB1
let s:builtin_themes = {
    \ 'solarized-dark':   'Solarized Dark|dark|Solarized-Dark-TrueColor|#002B36|#073642|#002731|#586E75|#657B83|#839496|#93A1A1|#EEE8D5|#FDF6E3|#B58900|#CB4B16|#DC322F|#D33682|#6C71C4|#268BD2|#2AA198|#859900|#274C25|#422D33|#364725|#0B4764|#3E2E4C|#2C4E56',
    \ 'solarized-light':  'Solarized Light|light|Solarized-Light-TrueColor|#FDF6E3|#EEE8D5|#E6DFCA|#93A1A1|#839496|#657B83|#586E75|#073642|#002B36|#B58900|#CB4B16|#DC322F|#D33682|#6C71C4|#268BD2|#2AA198|#859900|#E5ECD0|#F6D8D3|#F0E4C0|#D8E6EE|#F3D9E4|#E4DEC8',
    \ 'catppuccin-mocha': 'Catppuccin Mocha|dark|Catppuccin-Mocha-TrueColor|#1E1E2E|#313244|#181825|#6C7086|#7F849C|#CDD6F4|#DCE0E8|#E6E9EF|#F5E0DC|#F9E2AF|#FAB387|#F38BA8|#F5C2E7|#CBA6F7|#89B4FA|#94E2D5|#A6E3A1|#283B37|#3E2939|#3E3B3B|#29384E|#3E3247|#35374B',
    \ 'catppuccin-latte': 'Catppuccin Latte|light|Catppuccin-Latte-TrueColor|#EFF1F5|#CCD0DA|#E6E9EF|#686B7D|#5C5F77|#4C4F69|#383A50|#313244|#1E1E2E|#8F5902|#B34300|#D20F39|#A82B8A|#8839EF|#1E66F5|#0E7075|#2D761D|#DCEAD9|#F2D5DD|#EFE4D2|#D6E1F8|#F3DFEF|#D5D8E2',
    \ 'gruvbox-dark':     'Gruvbox Dark|dark|Gruvbox-Dark-TrueColor|#282828|#3C3836|#1D2021|#928374|#A89984|#EBDBB2|#FBF1C7|#D5C4A1|#FBF1C7|#FABD2F|#FE8019|#FB4934|#D3869B|#B16286|#83A598|#8EC07C|#B8BB26|#3B3D24|#472825|#473F25|#2E3B36|#422E36|#45403D',
    \ 'tokyonight-night': 'TokyoNight Night|dark|TokyoNight-Night-TrueColor|#1A1B26|#292E42|#16161E|#565F89|#737AA2|#C0CAF5|#D5DCF8|#E0AF68|#E2E8FF|#E0AF68|#FF9E64|#F7768E|#BB9AF7|#9D7CD8|#7AA2F7|#7DCFFF|#9ECE6A|#273832|#3B2430|#3B342C|#23344D|#342B44|#2F354D',
    \ 'kanagawa-wave':    'Kanagawa Wave|dark|Kanagawa-Wave-TrueColor|#1F1F28|#2A2A37|#16161D|#7A7970|#939288|#DCD7BA|#EAE6D1|#E6C384|#F2EFE0|#E6C384|#FFA066|#E46876|#D27E99|#957FB8|#7E9CD8|#7AA89F|#98BB6C|#2B3328|#43242B|#49443C|#252535|#3A2836|#2D4F67',
    \ 'nord':             'Nord|dark|Nord-TrueColor|#2E3440|#3B4252|#242933|#8492AC|#96A4BE|#D8DEE9|#E5E9F0|#ECEFF4|#ECEFF4|#EBCB8B|#D08770|#BF616A|#B48EAD|#5E81AC|#81A1C1|#88C0D0|#A3BE8C|#394548|#443943|#494647|#384354|#423F4E|#434C5E',
    \ 'onedark':          'OneDark|dark|OneDark-TrueColor|#282C34|#31353F|#21252B|#5C6370|#7F848E|#ABB2BF|#C8CCD4|#E5C07B|#FFFFFF|#E5C07B|#D19A66|#E06C75|#C678DD|#B268CA|#61AFEF|#56B6C2|#98C379|#2E3E38|#3F2D34|#3E3A34|#283B4C|#3B2F44|#3E4451',
    \ 'new-years':        "New Year's|dark|New-Years-TrueColor|#07081C|#14183D|#040510|#6872AA|#848FC7|#EEF1FF|#FFFFFF|#FFFDF2|#FFFFFF|#44FF77|#FF8024|#FF1744|#5C9DFF|#B388FF|#00F0FF|#FF66C4|#FFD700|#103B2B|#3B1026|#143D29|#063647|#1A294D|#24294D",
    \ 'valentines':       "Valentine's Day|dark|Valentines-TrueColor|#260715|#400D24|#18040D|#A65E7E|#C27898|#FFE8F2|#FFF5F9|#FFFDF9|#FFFFFF|#44F088|#FF8547|#FF1738|#66B2FF|#C77DFF|#FF6BB5|#2EE6C8|#FFD700|#143D31|#520A22|#19422D|#521B38|#332645|#4A1A30",
    \ 'st-patricks':      "St. Patrick's Day|dark|St-Patricks-TrueColor|#042210|#0A3B1E|#021509|#529E6E|#6BB887|#E6FAEC|#F5FFF8|#FFFDF0|#FFFFFF|#FF9100|#FF5722|#FF1744|#FF66B2|#B88CFF|#FFD700|#38E5FF|#00F556|#054A20|#451220|#38390E|#3B4B0D|#382E30|#1B4D2B",
    \ 'easter':           'Easter|light|Easter-TrueColor|#FDF7FF|#F0DCF8|#E4C8F0|#86659C|#6E4E85|#361E4A|#221033|#160822|#0C0312|#A87400|#E04F00|#D5001C|#008B8B|#7B1FA2|#C21878|#0070D6|#009E3D|#D4F5DF|#FAD2D8|#F5E4C3|#F5CFE8|#CEEFEB|#DEC9EC',
    \ 'independence-day': 'Independence Day|dark|Independence-Day-TrueColor|#061436|#10275E|#030B20|#6588CC|#85A5E6|#F4F8FF|#FFFFFF|#FFF9E6|#FAFAFF|#2EE6A6|#FF7733|#FF1738|#5CE6FF|#9E8CFF|#38B6FF|#FF6B9E|#FFD700|#0E3B2C|#3D1228|#0E403E|#113864|#163F62|#233769',
    \ 'halloween':        'Halloween|dark|Halloween-TrueColor|#160824|#281040|#0E0418|#7D5BA6|#9B78C4|#EDE2FA|#F8F2FF|#FFF8EB|#FFFFFF|#FFE000|#FF3B00|#FF1744|#FF5CCD|#C77DFF|#55FF47|#2EE6D6|#FF7518|#1B3D26|#440E26|#45331D|#243F2C|#451946|#33204A',
    \ 'thanksgiving':     'Thanksgiving|dark|Thanksgiving-TrueColor|#221107|#381C0C|#150A04|#9C7458|#B88E70|#F7E8D8|#FFF6EB|#FFFDF9|#FFFFFF|#FFD000|#FFA866|#FF1F2D|#FF6699|#C780FF|#FF7814|#38D9B8|#8CE645|#243D14|#4D1214|#4F3809|#4F260B|#4F2224|#472A1A',
    \ 'christmas':        'Christmas|dark|Christmas-TrueColor|#062012|#0E3820|#03140B|#5C9E78|#78B894|#F0FAF4|#FFFFFF|#FFFDF7|#FAFAFF|#38E5FF|#FF7B24|#FF1738|#B8FF3D|#C788FF|#FFD700|#FF6B9E|#2EE66B|#0F4224|#3D1620|#0F3E3B|#3D4A0F|#2A471A|#234231'
    \ }

let s:builtin_field_keys = [
    \ 'THEME_LABEL', 'THEME_MODE', 'BAT_THEME_NAME',
    \ 'BASE03', 'BASE02', 'BASE04', 'BASE01', 'BASE00', 'BASE0', 'BASE1', 'BASE2', 'BASE3',
    \ 'YELLOW', 'ORANGE', 'RED', 'MAGENTA', 'VIOLET', 'BLUE', 'CYAN', 'GREEN',
    \ 'MIX_GREEN', 'MIX_RED', 'MIX_YELLOW', 'MIX_BLUE', 'MIX_MAGENTA', 'MIX_BASE1'
    \ ]

function! s:Trim(str) abort
    return substitute(a:str, '^\s\+\|\s\+$', '', 'g')
endfunction

function! s:UnpackBuiltinTheme(slug) abort
    if !has_key(s:builtin_themes, a:slug)
        return {}
    endif
    let l:parts = split(s:builtin_themes[a:slug], '|', 1)
    let l:p = {'THEME_ID': a:slug}
    for l:idx in range(min([len(s:builtin_field_keys), len(l:parts)]))
        let l:p[s:builtin_field_keys[l:idx]] = l:parts[l:idx]
    endfor
    return l:p
endfunction

function! s:ParseThemeFile(path) abort
    let l:p = {}
    if !filereadable(a:path)
        return l:p
    endif
    for l:raw_line in readfile(a:path)
        let l:line = s:Trim(substitute(l:raw_line, "\r$", '', ''))
        if empty(l:line) || l:line[0] ==# '#'
            continue
        endif
        let l:line = substitute(l:line, '^export\s\+', '', '')
        let l:m = matchlist(l:line, '^\([A-Za-z_][A-Za-z0-9_]*\)\s*=\s*\(.*\)$')
        if empty(l:m)
            continue
        endif
        let l:k = l:m[1]
        let l:v = s:Trim(l:m[2])
        if len(l:v) >= 2 && (l:v[0] ==# '"' || l:v[0] ==# "'")
            let l:q = l:v[0]
            let l:end_idx = stridx(l:v, l:q, 1)
            if l:end_idx > 0
                let l:rest = s:Trim(strpart(l:v, l:end_idx + 1))
                if empty(l:rest) || l:rest[0] ==# '#'
                    let l:v = strpart(l:v, 1, l:end_idx - 1)
                endif
            endif
        else
            let l:v = s:Trim(substitute(l:v, '\s\+#.*$', '', ''))
        endif
        let l:p[l:k] = l:v
    endfor
    return l:p
endfunction

function! s:SafeHex(p, key, fallback) abort
    let l:val = s:Trim(get(a:p, a:key, ''))
    if l:val =~? '^#[0-9a-f]\{6\}$'
        return toupper(l:val)
    endif
    return a:fallback
endfunction

function! s:BlendHex(fg, bg, pct) abort
    let l:fr = str2nr(strpart(a:fg, 1, 2), 16)
    let l:fg_g = str2nr(strpart(a:fg, 3, 2), 16)
    let l:fb = str2nr(strpart(a:fg, 5, 2), 16)
    let l:br = str2nr(strpart(a:bg, 1, 2), 16)
    let l:bg_g = str2nr(strpart(a:bg, 3, 2), 16)
    let l:bb = str2nr(strpart(a:bg, 5, 2), 16)
    let l:r = (l:fr * a:pct + l:br * (100 - a:pct) + 50) / 100
    let l:g = (l:fg_g * a:pct + l:bg_g * (100 - a:pct) + 50) / 100
    let l:b = (l:fb * a:pct + l:bb * (100 - a:pct) + 50) / 100
    return printf('#%02X%02X%02X', l:r, l:g, l:b)
endfunction

function! s:UserThemeDirs(cfg_home) abort
    let l:dirs = []
    if !empty($HOME_SETTINGS_USER_THEMES_DIR)
        call add(l:dirs, $HOME_SETTINGS_USER_THEMES_DIR)
    endif
    call add(l:dirs, a:cfg_home . '/themes')
    call add(l:dirs, a:cfg_home . '/home-settings/themes')
    return l:dirs
endfunction

function! s:FindUserThemeFile(slug, cfg_home) abort
    if empty(a:slug)
        return ''
    endif
    let l:user_dirs = s:UserThemeDirs(a:cfg_home)
    for l:udir in l:user_dirs
        for l:ext in ['.theme', '.conf']
            let l:cand = l:udir . '/' . a:slug . l:ext
            if filereadable(l:cand)
                let l:kv = s:ParseThemeFile(l:cand)
                let l:cid = substitute(tolower(s:Trim(get(l:kv, 'THEME_ID', a:slug))), '_', '-', 'g')
                if l:cid ==# a:slug
                    return l:cand
                endif
            endif
        endfor
    endfor
    for l:udir in l:user_dirs
        if isdirectory(l:udir)
            for l:cand in sort(glob(l:udir . '/*.theme', 0, 1) + glob(l:udir . '/*.conf', 0, 1))
                let l:kv = s:ParseThemeFile(l:cand)
                let l:cid = substitute(tolower(s:Trim(get(l:kv, 'THEME_ID', fnamemodify(l:cand, ':t:r')))), '_', '-', 'g')
                if l:cid ==# a:slug
                    return l:cand
                endif
            endfor
        endif
    endfor
    return ''
endfunction

function! s:ResolveThemeBySlug(slug, cfg_home) abort
    let l:norm = substitute(tolower(s:Trim(a:slug)), '_', '-', 'g')
    if empty(l:norm)
        return {}
    endif
    let l:ufile = s:FindUserThemeFile(l:norm, a:cfg_home)
    if !empty(l:ufile)
        let l:p = s:ParseThemeFile(l:ufile)
        if !has_key(l:p, 'THEME_ID')
            let l:p['THEME_ID'] = l:norm
        endif
        return l:p
    endif
    let l:repo_cand = s:vimrc_repo_root . '/colors/themes/' . l:norm . '.theme'
    if filereadable(l:repo_cand)
        let l:p = s:ParseThemeFile(l:repo_cand)
        if !has_key(l:p, 'THEME_ID')
            let l:p['THEME_ID'] = l:norm
        endif
        return l:p
    endif
    return s:UnpackBuiltinTheme(l:norm)
endfunction

function! s:ReadActiveTheme() abort
    let l:cfg_home = empty($XDG_CONFIG_HOME) ? expand('$HOME/.config') : $XDG_CONFIG_HOME
    if !exists('s:user_env_theme') || $HOME_SETTINGS_THEME !=# get(s:, 'internal_env_theme', '')
        let s:user_env_theme = $HOME_SETTINGS_THEME
    endif
    let l:req_slug = substitute(tolower(s:Trim(s:user_env_theme)), '_', '-', 'g')
    let l:p = {}
    if !empty($HOME_SETTINGS_THEME_FILE)
        if filereadable($HOME_SETTINGS_THEME_FILE)
            let l:p = s:ParseThemeFile($HOME_SETTINGS_THEME_FILE)
        elseif !empty(l:req_slug)
            let l:p = s:ResolveThemeBySlug(l:req_slug, l:cfg_home)
        endif
    else
        let l:active_file = l:cfg_home . '/home-settings/active-theme.theme'
        let l:state_file = l:cfg_home . '/home-settings/theme'
        let l:saved_slug = ''
        if filereadable(l:state_file)
            let l:lines = readfile(l:state_file, '', 1)
            if !empty(l:lines)
                let l:saved_slug = substitute(tolower(s:Trim(substitute(l:lines[0], "\r$", '', ''))), '_', '-', 'g')
            endif
        endif
        if filereadable(l:active_file)
            let l:p = s:ParseThemeFile(l:active_file)
            let l:active_id = substitute(tolower(s:Trim(get(l:p, 'THEME_ID', ''))), '_', '-', 'g')
            if !empty(l:saved_slug) && l:saved_slug !=# l:active_id
                let l:override_p = s:ResolveThemeBySlug(l:saved_slug, l:cfg_home)
                if !empty(l:override_p)
                    let l:p = l:override_p
                    let l:active_id = l:saved_slug
                endif
            endif
            let l:ufile = s:FindUserThemeFile(l:active_id, l:cfg_home)
            if !empty(l:ufile)
                let l:p = s:ParseThemeFile(l:ufile)
                let l:p['THEME_ID'] = l:active_id
            endif
        elseif !empty(l:saved_slug)
            let l:p = s:ResolveThemeBySlug(l:saved_slug, l:cfg_home)
        elseif !empty(l:req_slug)
            let l:p = s:ResolveThemeBySlug(l:req_slug, l:cfg_home)
        endif
    endif
    if !empty(l:p) && !has_key(l:p, 'THEME_ID') && !empty(l:req_slug)
        let l:p['THEME_ID'] = l:req_slug
    endif
    return l:p
endfunction

function! s:FileSig(path) abort
    if empty(a:path) || !filereadable(a:path)
        return 'missing'
    endif
    let l:sz = getfsize(a:path)
    if l:sz < 0 || l:sz > 65536
        return getftime(a:path) . ':' . l:sz
    endif
    let l:raw = join(readfile(a:path, 'b'), "\n")
    return exists('*sha256') ? sha256(l:raw) : (getftime(a:path) . ':' . l:sz . ':' . l:raw)
endfunction

function! s:ActiveThemeSignature() abort
    let l:cfg_home = empty($XDG_CONFIG_HOME) ? expand('$HOME/.config') : $XDG_CONFIG_HOME
    let l:env_t = ($HOME_SETTINGS_THEME !=# get(s:, 'internal_env_theme', '')) ? $HOME_SETTINGS_THEME : get(s:, 'user_env_theme', '')
    if !empty($HOME_SETTINGS_THEME_FILE)
        return 'F:' . $HOME_SETTINGS_THEME_FILE . ':' . s:FileSig($HOME_SETTINGS_THEME_FILE) . '|E:' . l:env_t
    endif
    let l:af = l:cfg_home . '/home-settings/active-theme.theme'
    let l:sf = l:cfg_home . '/home-settings/theme'
    let l:slug = get(g:, 'home_settings_theme', '')
    if filereadable(l:sf)
        let l:slines = readfile(l:sf, '', 1)
        if !empty(l:slines)
            let l:cand_slug = substitute(tolower(s:Trim(substitute(l:slines[0], "\r$", '', ''))), '_', '-', 'g')
            if !empty(l:cand_slug)
                let l:slug = l:cand_slug
            endif
        endif
    endif
    let l:uf = !empty(l:slug) ? s:FindUserThemeFile(l:slug, l:cfg_home) : ''
    return 'A:' . s:FileSig(l:af) . '|S:' . s:FileSig(l:sf) . '|U:' . s:FileSig(l:uf) . '|E:' . l:env_t
endfunction

function! s:BuildCompletePalette(raw) abort
    let l:mode = tolower(s:Trim(get(a:raw, 'THEME_MODE', 'dark'))) ==# 'light' ? 'light' : 'dark'
    let l:base = s:UnpackBuiltinTheme(l:mode ==# 'light' ? 'solarized-light' : 'solarized-dark')
    let l:id = substitute(tolower(s:Trim(get(a:raw, 'THEME_ID', 'solarized-dark'))), '_', '-', 'g')
    if l:id !~# '^[a-z0-9][a-z0-9-]*$'
        let l:id = 'solarized-dark'
    endif
    let l:c = {'THEME_ID': l:id, 'THEME_MODE': l:mode}
    let l:label_Parts = split(l:id, '[-_]\+')
    let l:def_label = join(map(copy(l:label_Parts), 'toupper(v:val[0]) . strpart(v:val, 1)'), ' ')
    let l:def_bat = join(map(copy(l:label_Parts), 'toupper(v:val[0]) . strpart(v:val, 1)'), '-') . '-TrueColor'
    let l:raw_label = substitute(s:Trim(get(a:raw, 'THEME_LABEL', '')), '["\\$`\r\n]', '', 'g')
    let l:raw_bat = s:Trim(get(a:raw, 'BAT_THEME_NAME', ''))
    let l:c['THEME_LABEL'] = !empty(l:raw_label) ? l:raw_label : get(s:UnpackBuiltinTheme(l:id), 'THEME_LABEL', l:def_label)
    let l:c['BAT_THEME_NAME'] = (l:raw_bat =~# '^[A-Za-z0-9._-]\+$') ? l:raw_bat : get(s:UnpackBuiltinTheme(l:id), 'BAT_THEME_NAME', l:def_bat)
    for l:k in ['BASE03', 'BASE02', 'BASE01', 'BASE00', 'BASE0', 'BASE1', 'BASE2', 'BASE3', 'YELLOW', 'ORANGE', 'RED', 'MAGENTA', 'VIOLET', 'BLUE', 'CYAN', 'GREEN']
        let l:c[l:k] = s:SafeHex(a:raw, l:k, l:base[l:k])
    endfor
    let l:c['BASE04']      = s:SafeHex(a:raw, 'BASE04',      (l:c['BASE03'] ==# l:base['BASE03'] && l:c['BASE02'] ==# l:base['BASE02'])   ? l:base['BASE04']      : s:BlendHex(l:c['BASE02'],  l:c['BASE03'], 50))
    let l:c['MIX_GREEN']   = s:SafeHex(a:raw, 'MIX_GREEN',   (l:c['BASE03'] ==# l:base['BASE03'] && l:c['GREEN'] ==# l:base['GREEN'])     ? l:base['MIX_GREEN']   : s:BlendHex(l:c['GREEN'],   l:c['BASE03'], 18))
    let l:c['MIX_RED']     = s:SafeHex(a:raw, 'MIX_RED',     (l:c['BASE03'] ==# l:base['BASE03'] && l:c['RED'] ==# l:base['RED'])         ? l:base['MIX_RED']     : s:BlendHex(l:c['RED'],     l:c['BASE03'], 18))
    let l:c['MIX_YELLOW']  = s:SafeHex(a:raw, 'MIX_YELLOW',  (l:c['BASE03'] ==# l:base['BASE03'] && l:c['YELLOW'] ==# l:base['YELLOW'])   ? l:base['MIX_YELLOW']  : s:BlendHex(l:c['YELLOW'],  l:c['BASE03'], 20))
    let l:c['MIX_BLUE']    = s:SafeHex(a:raw, 'MIX_BLUE',    (l:c['BASE03'] ==# l:base['BASE03'] && l:c['BLUE'] ==# l:base['BLUE'])       ? l:base['MIX_BLUE']    : s:BlendHex(l:c['BLUE'],    l:c['BASE03'], 22))
    let l:c['MIX_MAGENTA'] = s:SafeHex(a:raw, 'MIX_MAGENTA', (l:c['BASE03'] ==# l:base['BASE03'] && l:c['MAGENTA'] ==# l:base['MAGENTA']) ? l:base['MIX_MAGENTA'] : s:BlendHex(l:c['MAGENTA'], l:c['BASE03'], 20))
    let l:c['MIX_BASE1']   = s:SafeHex(a:raw, 'MIX_BASE1',   (l:c['BASE03'] ==# l:base['BASE03'] && l:c['BASE1'] ==# l:base['BASE1'])     ? l:base['MIX_BASE1']   : s:BlendHex(l:c['BASE1'],   l:c['BASE03'], 16))
    return l:c
endfunction

function! s:Hi(groups, cterm, ctermfg, ctermbg, gui, guifg, guibg) abort
    let l:spec = ' cterm=' . a:cterm . ' ctermfg=' . a:ctermfg . ' ctermbg=' . a:ctermbg . ' gui=' . a:gui . ' guifg=' . a:guifg . ' guibg=' . a:guibg
    for l:grp in a:groups
        execute 'highlight ' . l:grp . l:spec
    endfor
endfunction

function! s:ApplySolarizedDark() abort
    let l:c = s:BuildCompletePalette(s:ReadActiveTheme())
    let g:home_settings_theme = l:c['THEME_ID']
    let g:home_settings_theme_mode = l:c['THEME_MODE']
    let s:internal_env_theme = l:c['THEME_ID']
    let $HOME_SETTINGS_THEME = l:c['THEME_ID']
    let $HOME_SETTINGS_THEME_MODE = l:c['THEME_MODE']
    if !empty(l:c['BAT_THEME_NAME'])
        let $BAT_THEME = l:c['BAT_THEME_NAME']
    endif
    if &background !=# l:c['THEME_MODE']
        execute 'noautocmd set background=' . l:c['THEME_MODE']
    endif

    let l:b03  = l:c['BASE03']
    let l:b02  = l:c['BASE02']
    let l:b04  = l:c['BASE04']
    let l:b01  = l:c['BASE01']
    let l:b00  = l:c['BASE00']
    let l:b0   = l:c['BASE0']
    let l:b1   = l:c['BASE1']
    let l:b2   = l:c['BASE2']
    let l:b3   = l:c['BASE3']
    let l:yel  = l:c['YELLOW']
    let l:ora  = l:c['ORANGE']
    let l:red  = l:c['RED']
    let l:mag  = l:c['MAGENTA']
    let l:vio  = l:c['VIOLET']
    let l:blu  = l:c['BLUE']
    let l:cya  = l:c['CYAN']
    let l:grn  = l:c['GREEN']
    let l:mgrn = l:c['MIX_GREEN']
    let l:mred = l:c['MIX_RED']
    let l:myel = l:c['MIX_YELLOW']
    let l:mblu = l:c['MIX_BLUE']
    let l:mmag = l:c['MIX_MAGENTA']
    let l:mb1  = l:c['MIX_BASE1']

    " 16-slot ANSI terminal palette for :terminal buffers (1:1 with Ghostty & Neovim)
    let g:terminal_ansi_colors = [
        \ l:b02, l:red, l:grn, l:yel, l:blu, l:mag, l:cya, l:b2,
        \ l:b01, l:ora, l:b01, l:b00, l:b0,  l:vio, l:b1,  l:b3
        \ ]
    if has('nvim')
        for l:ti in range(16)
            let g:['terminal_color_' . l:ti] = g:terminal_ansi_colors[l:ti]
        endfor
    elseif exists('*term_list') && exists('*term_setansicolors') && (&termguicolors || has('gui_running'))
        for l:tbuf in term_list()
            silent! call term_setansicolors(l:tbuf, g:terminal_ansi_colors)
        endfor
    endif

    " Canvas, Gutter, Splits, Floats & UI Chrome (ctermbg=NONE on canvas/gutter/splits)
    call s:Hi(['Normal', 'NormalNC'], 'NONE', '12', 'NONE', 'NONE', l:b0, l:b03)
    call s:Hi(['EndOfBuffer'], 'NONE', '10', 'NONE', 'NONE', l:b03, 'NONE')
    call s:Hi(['LineNr', 'LineNrAbove', 'LineNrBelow', 'VertSplit', 'WinSeparator', 'FoldColumn', 'SignColumn'], 'NONE', '10', 'NONE', 'NONE', l:b01, l:b03)
    call s:Hi(['StatusLine', 'StatusLineTerm'], 'NONE', '14', '0', 'NONE', l:b1, l:b02)
    call s:Hi(['StatusLineNC', 'StatusLineTermNC', 'Folded', 'PmenuShadow', 'PmenuBorder', 'TabLine', 'TabLineFill'], 'NONE', '10', '0', 'NONE', l:b01, l:b02)
    call s:Hi(['NonText', 'SpecialKey', 'Conceal', 'Whitespace'], 'NONE', '10', 'NONE', 'NONE', l:b01, 'NONE')
    call s:Hi(['CursorLine', 'CursorColumn', 'ColorColumn', 'PmenuSbar'], 'NONE', 'NONE', '0', 'NONE', 'NONE', l:b02)
    call s:Hi(['CursorLineNr', 'WildMenu', 'MatchParen', 'QuickFixLine', 'FloatTitle', 'PopupTitle'], 'bold', '14', '0', 'bold', l:b1, l:b02)
    call s:Hi(['NormalFloat', 'Popup', 'PopupNotification', 'MessageWindow'], 'NONE', '12', '0', 'NONE', l:b0, l:b04)
    call s:Hi(['FloatBorder', 'PopupBorder'], 'NONE', '10', '0', 'NONE', l:b01, l:b04)
    call s:Hi(['Visual'], 'reverse', 'NONE', '0', 'NONE', l:b1, l:mb1)
    call s:Hi(['VisualNOS'], 'NONE', 'NONE', '0', 'NONE', l:b1, l:mb1)
    call s:Hi(['Pmenu'], 'NONE', '12', '0', 'NONE', l:b0, l:b02)
    call s:Hi(['PmenuSel'], 'bold', '14', '10', 'bold', l:b1, l:b01)
    call s:Hi(['PmenuThumb'], 'NONE', 'NONE', '10', 'NONE', 'NONE', l:b01)
    call s:Hi(['TabLineSel'], 'bold', '14', 'NONE', 'bold', l:b1, l:b03)
    call s:Hi(['Search'], 'NONE', '0', '3', 'bold', l:b1, l:myel)
    call s:Hi(['IncSearch', 'CurSearch'], 'bold', '0', '5', 'bold', l:mag, l:mmag)
    call s:Hi(['MoreMsg'], 'NONE', '2', 'NONE', 'NONE', l:grn, 'NONE')
    call s:Hi(['ModeMsg'], 'bold', '14', 'NONE', 'bold', l:b1, 'NONE')
    call s:Hi(['Question'], 'NONE', '6', 'NONE', 'NONE', l:cya, 'NONE')
    call s:Hi(['Underlined'], 'underline', '13', 'NONE', 'underline', l:vio, 'NONE')
    call s:Hi(['Ignore'], 'NONE', '8', 'NONE', 'NONE', l:b03, 'NONE')
    execute 'highlight SpellBad cterm=underline ctermfg=1 ctermbg=NONE gui=undercurl guisp=' . l:red
    execute 'highlight SpellCap cterm=underline ctermfg=4 ctermbg=NONE gui=undercurl guisp=' . l:blu
    execute 'highlight SpellRare cterm=underline ctermfg=13 ctermbg=NONE gui=undercurl guisp=' . l:vio
    execute 'highlight SpellLocal cterm=underline ctermfg=6 ctermbg=NONE gui=undercurl guisp=' . l:cya

    " Core Semantic Syntax Architecture (7 Pillars + Converged Diagnostic Ladder)
    call s:Hi(['Identifier', 'Delimiter', 'Operator', 'TagDelimiter'], 'NONE', '12', 'NONE', 'NONE', l:b0, 'NONE')
    call s:Hi(['Comment'], 'NONE', '10', 'NONE', 'NONE', l:b01, 'NONE')
    call s:Hi(['Conditional', 'Repeat', 'Label', 'Exception'], 'NONE', '3', 'NONE', 'NONE', l:yel, 'NONE')
    call s:Hi(['Statement', 'Keyword', 'Type', 'StorageClass', 'Structure', 'Typedef'], 'NONE', '2', 'NONE', 'NONE', l:grn, 'NONE')
    call s:Hi(['Function', 'Directory', 'Tag'], 'NONE', '4', 'NONE', 'NONE', l:blu, 'NONE')
    call s:Hi(['Include', 'Special'], 'NONE', '13', 'NONE', 'NONE', l:vio, 'NONE')
    call s:Hi(['PreProc', 'Define', 'Macro', 'PreCondit', 'Title'], 'NONE', '9', 'NONE', 'NONE', l:ora, 'NONE')
    call s:Hi(['String', 'Character', 'SpecialChar'], 'NONE', '6', 'NONE', 'NONE', l:cya, 'NONE')
    call s:Hi(['Constant', 'Number', 'Boolean', 'Float'], 'NONE', '5', 'NONE', 'NONE', l:mag, 'NONE')
    call s:Hi(['Error', 'ErrorMsg'], 'bold', '1', 'NONE', 'bold', l:red, l:b03)
    call s:Hi(['WarningMsg'], 'bold', '3', 'NONE', 'bold', l:yel, 'NONE')
    call s:Hi(['Todo'], 'bold', '5', '0', 'bold', l:mag, l:b02)
    call s:Hi(['Added', 'diffAdded'], 'NONE', '2', 'NONE', 'NONE', l:grn, 'NONE')
    call s:Hi(['Changed', 'diffChanged'], 'NONE', '3', 'NONE', 'NONE', l:yel, 'NONE')
    call s:Hi(['Removed', 'diffRemoved'], 'NONE', '1', 'NONE', 'NONE', l:red, 'NONE')
    execute 'highlight DiffAdd term=reverse cterm=bold ctermbg=green ctermfg=white gui=NONE guifg=' . l:grn . ' guibg=' . l:mgrn
    execute 'highlight DiffChange term=reverse cterm=bold ctermbg=cyan ctermfg=black gui=NONE guifg=' . l:yel . ' guibg=' . l:myel
    execute 'highlight DiffText term=reverse cterm=bold ctermbg=gray ctermfg=black gui=bold guifg=' . l:blu . ' guibg=' . l:mblu
    execute 'highlight DiffDelete term=reverse cterm=bold ctermbg=red ctermfg=black gui=NONE guifg=' . l:red . ' guibg=' . l:mred

    " Filetype Syntax Overrides (Markdown H1..H6 without bold/Yellow, and zero-Yellow declarative configs)
    call s:Hi(['markdownH1'], 'NONE', '9', 'NONE', 'NONE', l:ora, 'NONE')
    call s:Hi(['markdownH2', 'markdownLinkText', 'markdownId'], 'NONE', '4', 'NONE', 'NONE', l:blu, 'NONE')
    call s:Hi(['markdownH3'], 'NONE', '13', 'NONE', 'NONE', l:vio, 'NONE')
    call s:Hi(['markdownH4'], 'NONE', '14', 'NONE', 'NONE', l:b1, 'NONE')
    call s:Hi(['markdownH5', 'markdownH6', 'markdownBlockquote', 'markdownCodeBlock'], 'NONE', '12', 'NONE', 'NONE', l:b0, 'NONE')
    call s:Hi(['markdownHeadingDelimiter', 'markdownH1Delimiter', 'markdownH2Delimiter', 'markdownH3Delimiter', 'markdownH4Delimiter', 'markdownH5Delimiter', 'markdownH6Delimiter', 'markdownRule', 'markdownHeadingRule', 'markdownCodeDelimiter', 'markdownUrlDelimiter', 'markdownLinkDelimiter', 'markdownIdDelimiter'], 'NONE', '10', 'NONE', 'NONE', l:b01, 'NONE')
    call s:Hi(['markdownListMarker', 'markdownOrderedListMarker'], 'NONE', '2', 'NONE', 'NONE', l:grn, 'NONE')
    call s:Hi(['markdownCode', 'markdownUrl', 'markdownAutomaticLink', 'markdownIdDeclaration'], 'NONE', '6', 'NONE', 'NONE', l:cya, 'NONE')
    call s:Hi(['markdownBold'], 'bold', '14', 'NONE', 'bold', l:b1, 'NONE')
    call s:Hi(['markdownItalic'], 'italic', '12', 'NONE', 'italic', l:b0, 'NONE')

    call s:Hi(['jsonKeyword', 'jsonTest', 'yamlMappingKey', 'yamlBlockMappingKey', 'yamlFlowMappingKey', 'yamlBlockMappingMerge', 'yamlFlowMappingMerge', 'tomlKey', 'tomlKeyDq', 'tomlKeySq', 'xmlAttrib', 'htmlArg', 'cssProp', 'jpropertiesIdentifier', 'protoStructure', 'protoRepeat', 'protoDefault', 'protoExtend', 'protoRPC', 'protoType', 'protoTypedef', 'pbtxtField'], 'NONE', '2', 'NONE', 'NONE', l:grn, 'NONE')
    call s:Hi(['tomlTable', 'tomlTableArray', 'xmlTagName', 'xmlNamespace', 'htmlTagName', 'htmlSpecialTagName', 'cssTagName', 'cssClassName', 'cssIdentifier', 'pbtxtMessage', 'diffLine', 'diffSubname'], 'NONE', '4', 'NONE', 'NONE', l:blu, 'NONE')
    call s:Hi(['xmlCdataStart', 'xmlCdataEnd', 'xmlCdataCdata', 'cssPseudoClass', 'cssPseudoClassId', 'cssPagePseudo'], 'NONE', '13', 'NONE', 'NONE', l:vio, 'NONE')
    call s:Hi(['yamlDocumentStart', 'yamlDocumentEnd', 'xmlProcessing', 'xmlDocTypeDecl', 'xmlDocTypeKeyword', 'htmlDoctype', 'cssAtRule', 'cssAtKeyword', 'protoSyntax'], 'NONE', '9', 'NONE', 'NONE', l:ora, 'NONE')
    call s:Hi(['jsonNull', 'jsonBoolean', 'jsonNumber', 'yamlNull', 'yamlBool', 'yamlInteger', 'yamlFloat', 'yamlTimestamp', 'tomlDate', 'tomlBoolean', 'tomlInteger', 'tomlFloat', 'xmlEntity', 'xmlEntityPunct', 'htmlSpecialChar', 'cssColor', 'cssValueNumber', 'cssValueInteger', 'cssValueLength', 'cssValueAngle', 'cssValueTime', 'cssValueFrequency', 'cssUnitDecorators', 'hsJPropertiesConst', 'protoBool', 'protoInt', 'protoFloat', 'pbtxtEnum', 'pbtxtBool', 'pbtxtInt', 'pbtxtHex', 'pbtxtFloat'], 'NONE', '5', 'NONE', 'NONE', l:mag, 'NONE')
    call s:Hi(['jsonString', 'jsonEscape', 'yamlString', 'yamlFlowString', 'tomlString', 'tomlEscape', 'xmlString', 'htmlString', 'cssStringQ', 'cssStringQQ', 'cssURL', 'jpropertiesString', 'jpropertiesExtendString', 'jpropertiesSpecial', 'jpropertiesSpecialChar', 'protoString', 'pbtxtString', 'diffFile', 'diffOldFile', 'diffNewFile'], 'NONE', '6', 'NONE', 'NONE', l:cya, 'NONE')
    call s:Hi(['jsonBraces', 'jsonNoise', 'yamlKeyValueDelimiter', 'yamlBlockMappingDelimiter', 'yamlFlowMappingDelimiter', 'yamlFlowIndicator', 'yamlBlockCollectionItemStart', 'yamlBlockScalarHeader', 'yamlNodeTag', 'xmlTag', 'xmlEndTag', 'xmlEqual', 'xmlCdata', 'htmlTag', 'htmlEndTag', 'htmlHead', 'htmlTitle', 'htmlH1', 'htmlH2', 'htmlH3', 'htmlH4', 'htmlH5', 'htmlH6', 'htmlBold', 'htmlItalic', 'htmlUnderline', 'htmlBoldItalic', 'htmlBoldUnderline', 'htmlBoldUnderlineItalic', 'htmlUnderlineItalic', 'htmlLink', 'cssBraces', 'cssClassNameDot', 'cssAttributeSelector', 'cssCustomProp', 'cssCustomProperty', 'cssVar', 'cssAttr', 'cssFunctionName', 'cssFunctionComma', 'cssSelectorOp', 'cssSelectorOp2', 'cssAttrComma', 'cssNoise', 'cssUnitizers', 'jpropertiesAssignment', 'jpropertiesDelimiter', 'hsJPropertiesInterp'], 'NONE', '12', 'NONE', 'NONE', l:b0, 'NONE')
    call s:Hi(['yamlAnchor', 'yamlAlias', 'xmlComment', 'xmlCommentPart', 'xmlProcessingDelim', 'htmlComment', 'htmlCommentPart', 'jpropertiesComment', 'protoComment', 'protoTodo', 'pbtxtComment', 'pbtxtTodo', 'diffIndexLine'], 'NONE', '10', 'NONE', 'NONE', l:b01, 'NONE')
    call s:Hi(['cssImportant'], 'NONE', '1', 'NONE', 'NONE', l:red, 'NONE')

    let s:applied_theme_sig = s:ActiveThemeSignature()
endfunction

function! s:SyncActiveTheme() abort
    if s:ActiveThemeSignature() !=# get(s:, 'applied_theme_sig', '')
        call s:ApplySolarizedDark()
    endif
endfunction

function! s:HolidayScheduleForYear(year) abort
    let l:a = a:year % 19
    let l:b = a:year / 100
    let l:c = a:year % 100
    let l:d = l:b / 4
    let l:e = l:b % 4
    let l:f = (l:b + 8) / 25
    let l:g = (l:b - l:f + 1) / 3
    let l:h = (19 * l:a + l:b - l:d - l:g + 15) % 30
    let l:i = l:c / 4
    let l:k = l:c % 4
    let l:lv = ((32 + 2 * l:e + 2 * l:i - l:h - l:k) % 7 + 7) % 7
    let l:m = (l:a + 11 * l:h + 22 * l:lv) / 451
    let l:em = (l:h + l:lv - 7 * l:m + 114) / 31
    let l:ed = ((l:h + l:lv - 7 * l:m + 114) % 31) + 1
    let l:nov1_dow = (a:year + a:year / 4 - a:year / 100 + a:year / 400 + 3) % 7
    let l:td = 1 + ((4 - l:nov1_dow + 7) % 7) + 21
    return [
        \ [a:year * 10000 + 101,              'new-years'],
        \ [a:year * 10000 + 214,              'valentines'],
        \ [a:year * 10000 + 317,              'st-patricks'],
        \ [a:year * 10000 + l:em * 100 + l:ed, 'easter'],
        \ [a:year * 10000 + 704,              'independence-day'],
        \ [a:year * 10000 + 1031,             'halloween'],
        \ [a:year * 10000 + 1100 + l:td,      'thanksgiving'],
        \ [a:year * 10000 + 1225,             'christmas']
        \ ]
endfunction

function! s:ResolveNearestHolidaySlug() abort
    let l:ds = s:Trim($THEME_HOLIDAY_DATE)
    if !empty(l:ds)
        if l:ds !~# '^\d\{4\}-\d\{2\}-\d\{2\}$'
            return ''
        endif
        let l:yr_chk = str2nr(strpart(l:ds, 0, 4))
        let l:mo_chk = str2nr(strpart(l:ds, 5, 2))
        let l:dy_chk = str2nr(strpart(l:ds, 8, 2))
        if l:mo_chk < 1 || l:mo_chk > 12 || l:dy_chk < 1
            return ''
        endif
        let l:leap = (l:yr_chk % 4 == 0 && l:yr_chk % 100 != 0) || (l:yr_chk % 400 == 0)
        let l:mdays = [31, l:leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        if l:dy_chk > l:mdays[l:mo_chk - 1]
            return ''
        endif
    else
        let l:ds = exists('*strftime') ? strftime('%Y-%m-%d') : s:Trim(system('date +%Y-%m-%d'))
    endif
    let l:yr = str2nr(strpart(l:ds, 0, 4))
    let l:mo = str2nr(strpart(l:ds, 5, 2))
    let l:dy = str2nr(strpart(l:ds, 8, 2))
    let l:today_int = l:yr * 10000 + l:mo * 100 + l:dy
    for l:item in s:HolidayScheduleForYear(l:yr) + s:HolidayScheduleForYear(l:yr + 1)
        if l:item[0] >= l:today_int
            return l:item[1]
        endif
    endfor
    return 'new-years'
endfunction

function! s:WriteFileAtomic(path, lines) abort
    let l:tmp = a:path . '.tmp.' . getpid()
    try
        if writefile(a:lines, l:tmp) == 0
            if rename(l:tmp, a:path) == 0
                return 1
            endif
        endif
    catch
    endtry
    silent! call delete(l:tmp)
    return 0
endfunction

function! s:ThemeCommand(raw_arg) abort
    let l:arg = s:Trim(a:raw_arg)
    if empty(l:arg)
        echomsg 'Active theme: ' . get(g:, 'home_settings_theme', 'solarized-dark')
        return
    endif
    let l:cfg_home = empty($XDG_CONFIG_HOME) ? expand('$HOME/.config') : $XDG_CONFIG_HOME
    let l:theme_bin = expand('$HOME/.local/bin/theme')
    if !executable(l:theme_bin)
        let l:repo_bin = s:vimrc_repo_root . '/bin/theme'
        let l:theme_bin = executable(l:repo_bin) ? l:repo_bin : exepath('theme')
    endif
    if !empty(l:theme_bin) && executable(l:theme_bin)
        let l:sub = (l:arg ==# '--holiday' || l:arg ==# 'holiday') ? '--holiday' : ('--set=' . shellescape(l:arg))
        let l:prev_skip = $THEME_SKIP_NVIM_SOCKET
        if exists('v:servername') && !empty(v:servername)
            let $THEME_SKIP_NVIM_SOCKET = v:servername
        endif
        let l:out = system(shellescape(l:theme_bin) . ' ' . l:sub)
        let l:rc = v:shell_error
        let $THEME_SKIP_NVIM_SOCKET = l:prev_skip
        if l:rc != 0
            let l:msg = s:Trim(l:out)
            echohl ErrorMsg
            echomsg 'Theme switch failed: ' . (!empty(l:msg) ? l:msg : l:arg)
            echohl None
            return
        endif
        let $HOME_SETTINGS_THEME_FILE = ''
        let s:user_env_theme = ''
        call s:ApplySolarizedDark()
        return
    endif

    " Standalone 2-file fallback when bin/theme is not installed
    if l:arg ==# '--holiday' || l:arg ==# 'holiday'
        let l:slug = s:ResolveNearestHolidaySlug()
        if empty(l:slug)
            echohl ErrorMsg
            echomsg 'Theme switch failed: invalid THEME_HOLIDAY_DATE: ' . $THEME_HOLIDAY_DATE
            echohl None
            return
        endif
    else
        let l:slug = substitute(tolower(l:arg), '_', '-', 'g')
    endif
    let l:raw = s:ResolveThemeBySlug(l:slug, l:cfg_home)
    if empty(l:raw)
        echohl ErrorMsg
        echomsg 'Theme switch failed: unknown theme: ' . l:arg
        echohl None
        return
    endif
    let l:c = s:BuildCompletePalette(l:raw)
    let l:state_dir = l:cfg_home . '/home-settings'
    try
        call mkdir(l:state_dir, 'p')
    catch
    endtry
    let l:active_lines = [
        \ '# Active home-settings palette (' . l:c['THEME_ID'] . ')',
        \ 'THEME_ID="' . l:c['THEME_ID'] . '"',
        \ 'THEME_LABEL="' . l:c['THEME_LABEL'] . '"',
        \ 'THEME_MODE="' . l:c['THEME_MODE'] . '"',
        \ 'BAT_THEME_NAME="' . l:c['BAT_THEME_NAME'] . '"'
        \ ]
    for l:k in ['BASE03', 'BASE02', 'BASE04', 'BASE01', 'BASE00', 'BASE0', 'BASE1', 'BASE2', 'BASE3', 'YELLOW', 'ORANGE', 'RED', 'MAGENTA', 'VIOLET', 'BLUE', 'CYAN', 'GREEN', 'MIX_GREEN', 'MIX_RED', 'MIX_YELLOW', 'MIX_BLUE', 'MIX_MAGENTA', 'MIX_BASE1']
        call add(l:active_lines, l:k . '="' . l:c[l:k] . '"')
    endfor
    if !isdirectory(l:state_dir) || !s:WriteFileAtomic(l:state_dir . '/active-theme.theme', l:active_lines) || !s:WriteFileAtomic(l:state_dir . '/theme', [l:c['THEME_ID']])
        echohl ErrorMsg
        echomsg 'Theme switch failed: cannot write theme state in ' . l:state_dir
        echohl None
        return
    endif
    silent! call delete(l:state_dir . '/theme-env.sh')
    let $HOME_SETTINGS_THEME_FILE = ''
    let s:user_env_theme = ''
    call s:ApplySolarizedDark()
endfunction

function! s:CompleteTheme(arg_lead, cmd_line, cursor_pos) abort
    let l:cfg_home = empty($XDG_CONFIG_HOME) ? expand('$HOME/.config') : $XDG_CONFIG_HOME
    let l:seen = {}
    let l:items = []
    for l:slug in s:builtin_theme_order
        let l:seen[l:slug] = 1
        call add(l:items, l:slug)
    endfor
    let l:custom = []
    for l:udir in s:UserThemeDirs(l:cfg_home)
        if isdirectory(l:udir)
            for l:f in glob(l:udir . '/*.theme', 0, 1) + glob(l:udir . '/*.conf', 0, 1)
                let l:stem = fnamemodify(l:f, ':t:r')
                if l:stem !=# 'active-theme'
                    let l:kv = s:ParseThemeFile(l:f)
                    let l:cslug = substitute(tolower(s:Trim(get(l:kv, 'THEME_ID', l:stem))), '_', '-', 'g')
                    if l:cslug =~# '^[a-z0-9][a-z0-9-]*$' && l:cslug !=# 'active-theme' && !has_key(l:seen, l:cslug)
                        let l:seen[l:cslug] = 1
                        call add(l:custom, l:cslug)
                    endif
                endif
            endfor
        endif
    endfor
    call extend(l:items, sort(l:custom))
    call add(l:items, '--holiday')
    return filter(l:items, 'stridx(v:val, a:arg_lead) == 0')
endfunction

command! -nargs=? -complete=customlist,s:CompleteTheme Theme call s:ThemeCommand(<q-args>)

augroup SolarizedFiletypes
    autocmd!
    autocmd BufNewFile,BufRead *.proto setfiletype proto
    autocmd BufNewFile,BufRead *.textproto,*.pbtxt,*.textpb,*.prototxt,*.pb.txt,*.proto.text setfiletype pbtxt
    autocmd BufNewFile,BufRead *.bzl,BUILD.bazel,BUILD,WORKSPACE,WORKSPACE.bazel,*.bazel,*.star setfiletype bzl
    autocmd BufNewFile,BufRead *.rego setfiletype rego
    autocmd BufNewFile,BufRead *.graphql,*.graphqls,*.gql setfiletype graphql
    autocmd BufNewFile,BufRead *.zig setfiletype zig
    autocmd BufNewFile,BufRead *.kt,*.kts setfiletype kotlin
    autocmd BufNewFile,BufRead *.scala,*.sc setfiletype scala
    autocmd BufNewFile,BufRead *.ex,*.exs setfiletype elixir
    autocmd BufNewFile,BufRead *.clj,*.cljs,*.cljc,*.edn setfiletype clojure
    autocmd BufNewFile,BufRead *.lean setfiletype lean
    autocmd BufNewFile,BufRead *.mk setfiletype make
    autocmd BufNewFile,BufRead Dockerfile,Containerfile,*.Dockerfile,*.Containerfile,Dockerfile.*,Containerfile.* setfiletype dockerfile
augroup END

" Syntax & Visual Theme
syntax enable

function! s:ApplyJPropertiesSyntax() abort
    silent! syntax clear jpropertiesString hsJPropertiesInterp hsJPropertiesConst
    silent! syntax region jpropertiesString start="" skip="\\$" end="$" keepend contained contains=jpropertiesSpecialChar,jpropertiesError,jpropertiesSpecial,hsJPropertiesInterp,hsJPropertiesConst
    silent! syntax match hsJPropertiesInterp /\${[^}\n]\+}/ excludenl contained containedin=jpropertiesString,jpropertiesExtendString
    silent! syntax match hsJPropertiesConst /\C\%(^\s*[^=:[:space:]]\+\s*[=:]\s*\)\@1024<=\%(true\|false\|[-+]\=\d\+\%(\.\d\+\)\=\)\ze\s*$/ excludenl contained containedin=jpropertiesString
endfunction

function! s:OnSyntaxPost(amatch) abort
    call s:ApplySolarizedDark()
    if a:amatch ==# 'jproperties'
        call s:ApplyJPropertiesSyntax()
    endif
endfunction

function! s:RegisterSyntaxPost() abort
    augroup SolarizedSyntaxPost
        autocmd!
        autocmd Syntax * call s:OnSyntaxPost(expand('<amatch>'))
    augroup END
endfunction

augroup SolarizedDarkFallback
    autocmd!
    autocmd ColorScheme * call s:ApplySolarizedDark()
    if exists('##SourcePost')
        autocmd SourcePost */syntax/synload.vim call s:RegisterSyntaxPost()
        autocmd SourcePost */syntax/syncolor.vim call s:ApplySolarizedDark()
        autocmd SourcePost */syntax/jproperties.vim call s:ApplyJPropertiesSyntax()
    endif
    if exists('##OptionSet')
        autocmd OptionSet background,termguicolors call s:ApplySolarizedDark()
    endif
    if exists('##VimResume')
        autocmd FocusGained,BufEnter,VimResume,CursorHold,CursorHoldI * call s:SyncActiveTheme()
    else
        autocmd FocusGained,BufEnter,CursorHold,CursorHoldI * call s:SyncActiveTheme()
    endif
augroup END
call s:RegisterSyntaxPost()

let s:initial_theme = s:ReadActiveTheme()
if tolower(s:Trim(get(s:initial_theme, 'THEME_MODE', 'dark'))) ==# 'light'
    set background=light
else
    set background=dark
endif
unlet s:initial_theme
silent! colorscheme solarized
call s:ApplySolarizedDark()

" Navigation & Hybrid Tmux Split Integration
let mapleader = " "

" Built-in Netrw Project Tree Sidebar Configuration
let g:netrw_banner = 0
let g:netrw_liststyle = 3
let g:netrw_browse_split = 4
let g:netrw_altv = 1
let g:netrw_winsize = 20
nnoremap <silent> <leader>e :Lexplore<CR>

set mouse=a
if has('mouse_sgr')
    set ttymouse=sgr
endif

if !has('nvim')
    silent! execute "set <M-h>=\<Esc>h"
    silent! execute "set <M-j>=\<Esc>j"
    silent! execute "set <M-k>=\<Esc>k"
    silent! execute "set <M-l>=\<Esc>l"
    silent! execute "set <M-c>=\<Esc>c"
    silent! execute "set <M-v>=\<Esc>v"
endif

if has('clipboard')
    xnoremap <silent> <LeftRelease> <LeftRelease>"+ygv"*ygv
    xnoremap <silent> <C-c> "+y
    xnoremap <silent> <M-c> "+y
    nnoremap <silent> <M-v> "+p
    inoremap <silent> <M-v> <C-r><C-o>+
    xnoremap <silent> <M-v> "+p
    nnoremap <silent> <MiddleMouse> <LeftMouse>"*p
    inoremap <silent> <MiddleMouse> <LeftMouse><C-r><C-o>*
    xnoremap <silent> <MiddleMouse> "*p
    cnoremap <MiddleMouse> <C-r>*
else
    xnoremap <silent> <M-c> y
    nnoremap <silent> <M-v> p
    inoremap <silent> <M-v> <C-r><C-o>"
    xnoremap <silent> <M-v> p
endif
nnoremap <silent> <X1Mouse> <C-o>
nnoremap <silent> <X2Mouse> <C-i>
vnoremap <silent> <X1Mouse> <C-o>
vnoremap <silent> <X2Mouse> <C-i>
inoremap <silent> <X1Mouse> <C-\><C-o><C-o>
inoremap <silent> <X2Mouse> <C-\><C-o><C-i>

function! s:TmuxNavigate(dir, tmux_dir) abort
    let l:cur_win = winnr()
    execute 'wincmd ' . a:dir
    if winnr() == l:cur_win && !empty($TMUX)
        let l:pane_opt = !empty($TMUX_PANE) ? '-t ' . $TMUX_PANE . ' ' : ''
        let l:target_cmd = 'select-pane ' . l:pane_opt . '-' . a:tmux_dir
        call system('tmux if-shell ' . l:pane_opt . '-F "#{==:#{window_zoomed_flag},0}" "' . l:target_cmd . '"')
    endif
endfunction

nnoremap <silent> <C-h> <C-w>h
nnoremap <silent> <C-j> <C-w>j
nnoremap <silent> <C-k> <C-w>k
nnoremap <silent> <C-l> <C-w>l
nnoremap <silent> <M-h> :call <SID>TmuxNavigate('h', 'L')<CR>
nnoremap <silent> <M-j> :call <SID>TmuxNavigate('j', 'D')<CR>
nnoremap <silent> <M-k> :call <SID>TmuxNavigate('k', 'U')<CR>
nnoremap <silent> <M-l> :call <SID>TmuxNavigate('l', 'R')<CR>
vnoremap <silent> <M-h> :<C-u>call <SID>TmuxNavigate('h', 'L')<CR>
vnoremap <silent> <M-j> :<C-u>call <SID>TmuxNavigate('j', 'D')<CR>
vnoremap <silent> <M-k> :<C-u>call <SID>TmuxNavigate('k', 'U')<CR>
vnoremap <silent> <M-l> :<C-u>call <SID>TmuxNavigate('l', 'R')<CR>
inoremap <silent> <M-h> <Esc>:call <SID>TmuxNavigate('h', 'L')<CR>
inoremap <silent> <M-j> <Esc>:call <SID>TmuxNavigate('j', 'D')<CR>
inoremap <silent> <M-k> <Esc>:call <SID>TmuxNavigate('k', 'U')<CR>
inoremap <silent> <M-l> <Esc>:call <SID>TmuxNavigate('l', 'R')<CR>
endif
