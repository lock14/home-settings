#!/bin/bash

# setup automation for java development on Fedora version 30.X or later

# usage function
usage() {
    echo "usage: $(basename $0) -j [openjdk-8-jdk | openjdk-11-jdk] -i [intellij | intellij-ultimate | eclipse | netbeans]"
}

while getopts ":j:i:u:p:h" opt; do
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

# if no package provided, default to openjdk-8
if [ "$JDK_PACKAGE" = "" ]; then
    JDK_PACKAGE="openjdk-11-jdk"
fi

# if no ide provided, default to intellij
if [ "$IDE" = "" ]; then
    IDE="intellij-ultimate"
fi

# validate choice of jdk package
if [ "$JDK_PACKAGE" != "openjdk-8-jdk" ] && [ "$JDK_PACKAGE" != "openjdk-11-jdk" ]; then
    echo "$JDK_PACKAGE is not a supported jdk package. Choose from: openjdk-8-jdk, or openjdk-11-jdk"
    exit 1
fi

# validate choice of ide
if [ "$IDE" != "intellij" ] && [ "$IDE" != "intellij-ultimate" ] && [ "$IDE" != "eclipse" ] && [ "$IDE" != "netbeans" ]; then
    echo "$IDE is not a supported IDE. Chose from: intellij, intellij-ultimate, eclipse, or netbeans"
fi

# get everything up to date
echo "upgrading packages"
sudo dnf upgrade --refresh

# install gnome-tweak tool
sudo dnf -y install gnome-tweak-tool

# install vim
echo "installing vim"
sudo dnf -y install vim

# install curl
echo "installing curl"
sudo dnf -y install curl

# install mariadb
echo "installing mariadb"
sudo dnf -y install mariadb-server mariadb

# install the specified jdkdnf
if [ "$JDK_PACKAGE" = "openjdk-8-jdk" ]; then
    sudo dnf -y install java-1.8.0-openjdk-devel
    sudo update-alternatives --set java java-1.8.0-openjdk.x86_64
    sudo update-alternatives --set javac java-1.8.0-openjdk.x86_64
elif [ "$JDK_PACKAGE" = "openjdk-11-jdk" ]; then
    sudo dnf -y install java-11-openjdk-devel
    sudo update-alternatives --set java java-11-openjdk.x86_64
    sudo update-alternatives --set javac java-11-openjdk.x86_64
fi

# install maven
echo "installing maven"
sudo dnf -y install maven

# install google chrome
sudo dnf -y install fedora-workstation-repositories
sudo dnf config-manager --set-enabled google-chrome
sudo dnf -y install google-chrome-stable
sudo dnf -y install chrome-gnome-shell

sudo snap install emacs --classic

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

# install postman
echo "intalling postman"
sudo snap install postman --classic

echo "installing slack"
sudo snap install slack --classic

# locat user stuff
mkdir -p ~/bin
rsync -av ./bin ~/bin

cat bashrc_addendum >> ~/.bashrc
mv environment_variables ~/.environment_variables

echo "system restarting in 10 seconds..."
sleep 10
systemctl reboot
