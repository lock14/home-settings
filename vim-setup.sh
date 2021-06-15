#!/bin/bash

#pathogen
mkdir -p ~/.vim/autoload ~/.vim/bundle
curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim

# vim solarized
cd ~/.vim/bundle
git clone git://github.com/altercation/vim-colors-solarized.git
cd -

# mv .vimrc to home
cp .vimrc ~
