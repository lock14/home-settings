#!/bin/bash

set -o errexit   # abort on nonzero exitstatus.
set -o nounset   # abort on unbound variable.
set -o pipefail  # don't hide errors within pipes

# Detect package manager (apt for Ubuntu/Debian, dnf for Fedora)
if command -v apt &>/dev/null; then
    PKG_INSTALL="sudo apt --yes install"
elif command -v dnf &>/dev/null; then
    PKG_INSTALL="sudo dnf -y install"
else
    echo "Unsupported package manager. Only apt and dnf are supported." >&2
    exit 1
fi

# install necessary packages
$PKG_INSTALL zsh
$PKG_INSTALL zsh-syntax-highlighting
$PKG_INSTALL fzf
$PKG_INSTALL command-not-found

# intstall oh-my-zsh and desired plugins
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/unixorn/fzf-zsh-plugin.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-zsh-plugin

# set theme to powerlevel10k and add desired plugins to plugins list
sed -i 's|ZSH_THEME="robbyrussell"|ZSH_THEME="powerlevel10k/powerlevel10k"|g' ~/.zshrc
sed -i 's|plugins=(git)|plugins=(git command-not-found zsh-autosuggestions zsh-syntax-highlighting fzf-zsh-plugin)|g' ~/.zshrc

# switch shell to zsh
chsh -s "$(which zsh)"

