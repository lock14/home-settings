#!/bin/bash

# setup automation for java development on Ubuntu version 18.X or later

usage() {
    echo "usage: $(basename $0) -j [openjdk-8 | openjdk-11] -i [intellij | intellij-ultimate | eclipse | netbeans]"
}

while getopts ":j:i:h" opt; do
  case ${opt} in
    j )
      JDK_PACKAGE=$OPTARG
      ;;
    i )
      IDE=$OPTARG
      ;;
    h )
      usage
      exit 0
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      usage
      exit 1
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# if no package provided, default to openjdk-11
if [ "$JDK_PACKAGE" = "" ]; then
    JDK_PACKAGE="openjdk-11"
fi

# if no ide provided, default to intellij
if [ "$IDE" = "" ]; then
    IDE="intellij"
fi

# validate choice of jdk package
if [ "$JDK_PACKAGE" != "openjdk-8" ] && [ "$JDK_PACKAGE" != "openjdk-11" ]; then
    echo "$JDK_PACKAGE is not a supported jdk package. Choose from: openjdk-8, or openjdk-11"
    exit 1
fi

# validate choice of ide
if [ "$IDE" != "intellij" ] && [ "$IDE" != "intellij-ultimate" ] && [ "$IDE" != "eclipse" ] && [ "$IDE" != "netbeans" ]; then
    echo "$IDE is not a supported IDE. Chose from: intellij, intellij-ultimate, eclipse, or netbeans"
fi

# get everything up to date
echo "upgrading packages"
sudo apt --yes update
sudo apt --yes full-upgrade
# auto remove uneeded things
sudo apt --yes autoremove

# install chrome
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -P ~/Downloads
sudo dpkg -i ~/Downloads/google-chrome-stable_current_amd64.deb

# install vim
echo "installing vim"
sudo apt --yes install vim

# install curl
echo "installing curl"
sudo apt --yes install curl

# install mariadb
echo "installing mariadb"
sudo apt --yes install mariadb-server mariadb-client

# install the specified jdk
echo "installing jdk"
version_num=${JDK_PACKAGE#openjdk-}
sudo apt --yes install $JDK_PACKAGE-jdk $JDK_PACKAGE-source
# this next command sets all the appropriate sym links (e.g java, javac, etc.)
sudo update-java-alternatives -s java-1.$version_num.0-openjdk-amd64

# install maven
echo "installing maven"
sudo apt --yes install maven

# install chosen IDE
if [ "$IDE" = "intellij" ]; then
    echo "intalling intellij-idea-community"
    sudo snap install intellij-idea-community --classic
elif [ "$IDE" = "intellij-ultimate" ]; then
    # install intellij ultimate
    echo "intalling intellij-idea-ultimate"
    sudo snap install intellij-idea-ultimate --classic
elif [ "$IDE" = "eclipse" ]; then
    # install eclipse 
    echo "installing eclipse"
    sudo snap install eclipse --classic
elif [ "$IDE" = "netbeans" ]; then
    echo "installing netbeans"
    sudo snap install netbeans --classic
fi

# install vs-code as well for a lightweight IDE
sudo snap install --classic code

# install postman
echo "intalling postman"
sudo snap install postman

echo "installing slack"
sudo snap install slack --classic

echo "Recommended Tools"
echo "Database Management - DbVisualizer: https://www.dbvis.com/download/10.0"

# user stuff
mkdir -p ~/bin
rsync -av ./bin ~/bin

cat bashrc_addendum >> ~/.bashrc
mv environment_variables ~/.environment_variables

echo "system restarting in 10 seconds..."
sleep 10
systemctl reboot
