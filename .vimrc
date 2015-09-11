set smartindent
set tabstop=4
set shiftwidth=4
set expandtab

highlight DiffAdd term=reverse cterm=bold ctermbg=green ctermfg=white 
highlight DiffChange term=reverse cterm=bold ctermbg=cyan ctermfg=black 
highlight DiffText term=reverse cterm=bold ctermbg=gray ctermfg=black 
highlight DiffDelete term=reverse cterm=bold ctermbg=red ctermfg=black

map <Home> ^
imap <Home> <Esc>^i
inoremap ( ()<Esc>:call BC_AddChar(")")<CR>i
inoremap { {}<Esc>:call BC_AddChar("}")<CR>i
inoremap [ []<Esc>:call BC_AddChar("]")<CR>i
inoremap " ""<Esc>:call BC_AddChar("\"")<CR>i
inoremap <C-j> <Esc>:call search(BC_GetChar(), "W")<CR>a
inoremap ) <c-r>=ClosePair(')')<CR>
inoremap ] <c-r>=ClosePair(']')<CR>
inoremap } <c-r>=ClosePair('}')<CR>
inoremap " <c-r>=QuoteDelim('"')<CR>
inoremap ' <c-r>=QuoteDelim("'")<CR>
inoremap <CR> <c-r>=EnterCheck()<CR>

function! EnterCheck()
    let charone = getline(".")[col(".")-2]
    let chartwo = getline(".")[col(".")-1]
    if charone == '{' && chartwo == '}'
        return "\n\<BS>\<BS>\<BS>\<BS>\<Esc>kA\n"
    else
        return "\n"
    endif
endfunction
    
function! BC_AddChar(schar)
    if exists("b:robstack")
        let b:robstack = b:robstack . a:schar
    else
        let b:robstack = a:schar
    endif
endfunction

function! BC_GetChar()
    let l:char = b:robstack[strlen(b:robstack)-1]
    let b:robstack = strpart(b:robstack, 0, strlen(b:robstack)-1)
    return l:char
endfunction

function ClosePair(char)
    if getline('.')[col('.') - 1] == a:char
        return "\<Right>"
    else
        return a:char
    endif
endf

function CloseBracket()
    if match(getline(line('.') + 1), '\s*}') < 0
        return "\<CR>}"
    else
        return "\<Esc>j0f}a"
    endif
endf

function QuoteDelim(char)
    let line = getline('.')
    let col = col('.')
    if line[col - 2] == "\\"
        "Inserting a quoted quotation mark into the string
        return a:char
    elseif line[col - 1] == a:char
        "Escaping out of the string
        return "\<Right>"
    else
        "Starting a string
        return a:char.a:char."\<Esc>i"
    endif
endf
