#!/bin/bash

# needs testing, likely buggy

# install necessary packages
sudo apt --yes install zsh
sudo apt --yes install zsh-syntax-highlighting
sudo apt --yes install fzf
sudo apt --yes install command-not-found                                                                                                                                     ✔  26s  

# intstall oh-my-zsh and desired plugins
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/unixorn/fzf-zsh-plugin.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-zsh-plugin

# set theme to powerlevel10k and add desired plugins to plugins list
sed -i s/ZSH_THEME=\"robbyrussell\"/ZSH_THEME=\"powerlevel10k/powerlevel10k\"/g ~/.zshrc
sed -i s/plugins=(git)/plugins=(git command-not-found zsh-autosuggestions zsh-syntax-highlighting fzf-zsh-plugin)/g ~/.zshrc

# switch shell to zsh
chsh -s $(which zsh)

