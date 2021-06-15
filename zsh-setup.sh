#!/bin/bash

# needs testing, likely buggy
sudo apt --yes install zsh
sudo apt --yes install zsh-syntax-highlighting
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
sed -i s/ZSH_THEME=\"robbyrussell\"/ZSH_THEME=\"powerlevel10k/powerlevel10k\"/g ~/.zshrc
sed -i s/plugins=(git)/plugins=(git zsh-syntax-highlighting)/g ~/.zshrc
chsh -s $(which zsh)

