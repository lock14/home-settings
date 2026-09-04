" Plugin management (Pathogen)
if filereadable(expand('~/.vim/autoload/pathogen.vim'))
    execute pathogen#infect()
endif

" Suppress Python 3.12+ syntax/deprecation warnings from interrupting Vim
let $PYTHONWARNINGS = "ignore"


" UltiSnips snippet triggers & SuperTab integration
let g:UltiSnipsExpandTrigger = "<tab>"
let g:UltiSnipsJumpForwardTrigger = "<c-j>"
let g:UltiSnipsJumpBackwardTrigger = "<c-k>"
let g:SuperTabDefaultCompletionType = "<c-n>"

" Auto-Pairs configuration
let g:AutoPairsShortcutJump = '<c-l>'

" Indentation & Formatting
filetype plugin indent on
set tabstop=4
set shiftwidth=4
set expandtab

" Syntax & Visual Theme
syntax enable
set background=dark
silent! colorscheme solarized

" Diff Highlight Formatting
highlight DiffAdd term=reverse cterm=bold ctermbg=green ctermfg=white
highlight DiffChange term=reverse cterm=bold ctermbg=cyan ctermfg=black
highlight DiffText term=reverse cterm=bold ctermbg=gray ctermfg=black
highlight DiffDelete term=reverse cterm=bold ctermbg=red ctermfg=black

" Navigation
map <Home> ^
imap <Home> <Esc>^i
