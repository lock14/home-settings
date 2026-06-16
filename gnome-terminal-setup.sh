#!/bin/bash

cd ~ || exit 1
git clone https://github.com/aruhier/gnome-terminal-colors-solarized.git
cd - || exit 1
cd ~/gnome-terminal-colors-solarized || exit 1
./install.sh
cd - || exit 1
