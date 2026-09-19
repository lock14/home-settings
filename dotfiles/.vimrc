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
