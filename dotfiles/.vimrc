" Indentation & Formatting
filetype plugin indent on
set tabstop=4
set shiftwidth=4
set expandtab

" TrueColor (24-bit) Terminal Support (Vim 8/9+)
set t_RB=
if has('termguicolors') && ($COLORTERM ==# 'truecolor' || $COLORTERM ==# '24bit')
    let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
    let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
    set termguicolors
endif

" Zero-Dependency Inline Solarized Dark Fallback Palette
" Applied automatically on remote servers / environments lacking solarized.vim
function! s:ApplySolarizedDark() abort
    if get(g:, 'colors_name', '') !=# 'solarized'
        " Canvas & UI Chrome (Base0 #839496 on Base03 #002B36, Base02 #073642, Base01 #586E75, Base1 #93A1A1)
        highlight Normal cterm=NONE ctermfg=12 ctermbg=8 gui=NONE guifg=#839496 guibg=#002B36
        highlight Identifier cterm=NONE ctermfg=12 ctermbg=NONE gui=NONE guifg=#839496 guibg=NONE
        highlight Delimiter cterm=NONE ctermfg=12 ctermbg=NONE gui=NONE guifg=#839496 guibg=NONE
        highlight Comment cterm=NONE ctermfg=10 ctermbg=NONE gui=NONE guifg=#586E75 guibg=NONE
        highlight LineNr cterm=NONE ctermfg=10 ctermbg=8 gui=NONE guifg=#586E75 guibg=#002B36
        highlight VertSplit cterm=NONE ctermfg=10 ctermbg=8 gui=NONE guifg=#586E75 guibg=#002B36
        highlight StatusLine cterm=NONE ctermfg=14 ctermbg=0 gui=NONE guifg=#93A1A1 guibg=#073642
        highlight StatusLineNC cterm=NONE ctermfg=10 ctermbg=0 gui=NONE guifg=#586E75 guibg=#073642
        highlight StatusLineTerm cterm=NONE ctermfg=14 ctermbg=0 gui=NONE guifg=#93A1A1 guibg=#073642
        highlight StatusLineTermNC cterm=NONE ctermfg=10 ctermbg=0 gui=NONE guifg=#586E75 guibg=#073642
        highlight NonText cterm=NONE ctermfg=10 ctermbg=NONE gui=NONE guifg=#586E75 guibg=NONE
        highlight SpecialKey cterm=NONE ctermfg=10 ctermbg=NONE gui=NONE guifg=#586E75 guibg=NONE
        highlight Conceal cterm=NONE ctermfg=10 ctermbg=NONE gui=NONE guifg=#586E75 guibg=NONE
        highlight Folded cterm=NONE ctermfg=10 ctermbg=0 gui=NONE guifg=#586E75 guibg=#073642
        highlight FoldColumn cterm=NONE ctermfg=10 ctermbg=8 gui=NONE guifg=#586E75 guibg=#002B36
        highlight SignColumn cterm=NONE ctermfg=10 ctermbg=8 gui=NONE guifg=#586E75 guibg=#002B36
        highlight CursorLine cterm=NONE ctermfg=NONE ctermbg=0 gui=NONE guifg=NONE guibg=#073642
        highlight CursorColumn cterm=NONE ctermfg=NONE ctermbg=0 gui=NONE guifg=NONE guibg=#073642
        highlight ColorColumn cterm=NONE ctermfg=NONE ctermbg=0 gui=NONE guifg=NONE guibg=#073642
        highlight CursorLineNr cterm=bold ctermfg=14 ctermbg=0 gui=bold guifg=#93A1A1 guibg=#073642
        highlight Visual cterm=reverse ctermfg=NONE ctermbg=0 gui=NONE guifg=NONE guibg=#073642
        highlight VisualNOS cterm=NONE ctermfg=NONE ctermbg=0 gui=NONE guifg=NONE guibg=#073642
        highlight Pmenu cterm=NONE ctermfg=12 ctermbg=0 gui=NONE guifg=#839496 guibg=#073642
        highlight PmenuSel cterm=bold ctermfg=14 ctermbg=10 gui=bold guifg=#93A1A1 guibg=#586E75
        highlight PmenuSbar cterm=NONE ctermfg=NONE ctermbg=0 gui=NONE guifg=NONE guibg=#073642
        highlight PmenuThumb cterm=NONE ctermfg=NONE ctermbg=10 gui=NONE guifg=NONE guibg=#586E75
        highlight PmenuShadow cterm=NONE ctermfg=10 ctermbg=0 gui=NONE guifg=#586E75 guibg=#073642
        highlight WildMenu cterm=bold ctermfg=14 ctermbg=0 gui=bold guifg=#93A1A1 guibg=#073642
        highlight TabLine cterm=NONE ctermfg=10 ctermbg=0 gui=NONE guifg=#586E75 guibg=#073642
        highlight TabLineFill cterm=NONE ctermfg=10 ctermbg=0 gui=NONE guifg=#586E75 guibg=#073642
        highlight TabLineSel cterm=bold ctermfg=14 ctermbg=8 gui=bold guifg=#93A1A1 guibg=#002B36
        highlight MatchParen cterm=bold ctermfg=14 ctermbg=0 gui=bold guifg=#93A1A1 guibg=#073642
        highlight Search cterm=NONE ctermfg=0 ctermbg=3 gui=NONE guifg=#93A1A1 guibg=#364725
        highlight IncSearch cterm=bold ctermfg=0 ctermbg=9 gui=bold guifg=#002B36 guibg=#CB4B16
        highlight Directory cterm=NONE ctermfg=4 ctermbg=NONE gui=NONE guifg=#268BD2 guibg=NONE
        highlight Title cterm=NONE ctermfg=9 ctermbg=NONE gui=NONE guifg=#CB4B16 guibg=NONE
        highlight MoreMsg cterm=NONE ctermfg=2 ctermbg=NONE gui=NONE guifg=#859900 guibg=NONE
        highlight ModeMsg cterm=bold ctermfg=14 ctermbg=NONE gui=bold guifg=#93A1A1 guibg=NONE
        highlight Question cterm=NONE ctermfg=6 ctermbg=NONE gui=NONE guifg=#2AA198 guibg=NONE
        highlight Underlined cterm=underline ctermfg=13 ctermbg=NONE gui=underline guifg=#6C71C4 guibg=NONE
        highlight Ignore cterm=NONE ctermfg=8 ctermbg=NONE gui=NONE guifg=#002B36 guibg=NONE
        highlight SpellBad cterm=underline ctermfg=1 ctermbg=NONE gui=undercurl guisp=#DC322F
        highlight SpellCap cterm=underline ctermfg=4 ctermbg=NONE gui=undercurl guisp=#268BD2
        highlight SpellRare cterm=underline ctermfg=13 ctermbg=NONE gui=undercurl guisp=#6C71C4
        highlight SpellLocal cterm=underline ctermfg=6 ctermbg=NONE gui=undercurl guisp=#2AA198

        " Control Flow & Execution Jumps (Solarized Yellow #B58900)
        highlight Conditional cterm=NONE ctermfg=3 ctermbg=NONE gui=NONE guifg=#B58900 guibg=NONE
        highlight Repeat cterm=NONE ctermfg=3 ctermbg=NONE gui=NONE guifg=#B58900 guibg=NONE
        highlight Label cterm=NONE ctermfg=3 ctermbg=NONE gui=NONE guifg=#B58900 guibg=NONE
        highlight Exception cterm=NONE ctermfg=3 ctermbg=NONE gui=NONE guifg=#B58900 guibg=NONE

        " Structural Scaffolding, Keywords & Primitive Types (Solarized Green #859900)
        highlight Statement cterm=NONE ctermfg=2 ctermbg=NONE gui=NONE guifg=#859900 guibg=NONE
        highlight Keyword cterm=NONE ctermfg=2 ctermbg=NONE gui=NONE guifg=#859900 guibg=NONE
        highlight Operator cterm=NONE ctermfg=2 ctermbg=NONE gui=NONE guifg=#859900 guibg=NONE
        highlight Type cterm=NONE ctermfg=2 ctermbg=NONE gui=NONE guifg=#859900 guibg=NONE
        highlight StorageClass cterm=NONE ctermfg=2 ctermbg=NONE gui=NONE guifg=#859900 guibg=NONE
        highlight Structure cterm=NONE ctermfg=2 ctermbg=NONE gui=NONE guifg=#859900 guibg=NONE
        highlight Typedef cterm=NONE ctermfg=2 ctermbg=NONE gui=NONE guifg=#859900 guibg=NONE

        " Routine & Function Declarations (Solarized Blue #268BD2)
        highlight Function cterm=NONE ctermfg=4 ctermbg=NONE gui=NONE guifg=#268BD2 guibg=NONE

        " Aspects & Module Imports (Solarized Violet #6C71C4)
        highlight Include cterm=NONE ctermfg=13 ctermbg=NONE gui=NONE guifg=#6C71C4 guibg=NONE

        " Preprocessor Directives & Macros (Solarized Orange #CB4B16)
        highlight PreProc cterm=NONE ctermfg=9 ctermbg=NONE gui=NONE guifg=#CB4B16 guibg=NONE
        highlight Define cterm=NONE ctermfg=9 ctermbg=NONE gui=NONE guifg=#CB4B16 guibg=NONE
        highlight Macro cterm=NONE ctermfg=9 ctermbg=NONE gui=NONE guifg=#CB4B16 guibg=NONE
        highlight PreCondit cterm=NONE ctermfg=9 ctermbg=NONE gui=NONE guifg=#CB4B16 guibg=NONE
        highlight Special cterm=NONE ctermfg=9 ctermbg=NONE gui=NONE guifg=#CB4B16 guibg=NONE

        " Strings & Character Literals (Solarized Cyan #2AA198)
        highlight String cterm=NONE ctermfg=6 ctermbg=NONE gui=NONE guifg=#2AA198 guibg=NONE
        highlight Character cterm=NONE ctermfg=6 ctermbg=NONE gui=NONE guifg=#2AA198 guibg=NONE
        highlight SpecialChar cterm=NONE ctermfg=6 ctermbg=NONE gui=NONE guifg=#2AA198 guibg=NONE

        " Constants, Numbers & Booleans (Solarized Magenta #D33682)
        highlight Constant cterm=NONE ctermfg=5 ctermbg=NONE gui=NONE guifg=#D33682 guibg=NONE
        highlight Number cterm=NONE ctermfg=5 ctermbg=NONE gui=NONE guifg=#D33682 guibg=NONE
        highlight Boolean cterm=NONE ctermfg=5 ctermbg=NONE gui=NONE guifg=#D33682 guibg=NONE
        highlight Float cterm=NONE ctermfg=5 ctermbg=NONE gui=NONE guifg=#D33682 guibg=NONE

        " Diagnostics, Errors & Warnings (Solarized Red #DC322F / Orange #CB4B16)
        highlight Error cterm=bold ctermfg=1 ctermbg=NONE gui=bold guifg=#DC322F guibg=#002B36
        highlight ErrorMsg cterm=bold ctermfg=1 ctermbg=NONE gui=bold guifg=#DC322F guibg=#002B36
        highlight WarningMsg cterm=bold ctermfg=9 ctermbg=NONE gui=bold guifg=#CB4B16 guibg=NONE
        highlight Todo cterm=bold ctermfg=5 ctermbg=0 gui=bold guifg=#D33682 guibg=#073642
        highlight Added cterm=NONE ctermfg=2 ctermbg=NONE gui=NONE guifg=#859900 guibg=NONE
        highlight Changed cterm=NONE ctermfg=3 ctermbg=NONE gui=NONE guifg=#B58900 guibg=NONE
        highlight Removed cterm=NONE ctermfg=1 ctermbg=NONE gui=NONE guifg=#DC322F guibg=NONE
    endif

    " Diff Highlight Formatting
    highlight DiffAdd term=reverse cterm=bold ctermbg=green ctermfg=white gui=NONE guifg=#859900 guibg=#274C25
    highlight DiffChange term=reverse cterm=bold ctermbg=cyan ctermfg=black gui=NONE guifg=#B58900 guibg=#364725
    highlight DiffText term=reverse cterm=bold ctermbg=gray ctermfg=black gui=bold guifg=#268BD2 guibg=#0B4764
    highlight DiffDelete term=reverse cterm=bold ctermbg=red ctermfg=black gui=NONE guifg=#DC322F guibg=#422D33
endfunction

augroup SolarizedDarkFallback
    autocmd!
    autocmd ColorScheme,Syntax * call s:ApplySolarizedDark()
    if exists('##OptionSet')
        autocmd OptionSet background call s:ApplySolarizedDark()
    endif
augroup END

" Syntax & Visual Theme
syntax enable
set background=dark
silent! colorscheme solarized
call s:ApplySolarizedDark()

" Navigation
map <Home> ^
imap <Home> <Esc>^i
