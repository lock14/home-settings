#!/bin/bash

# setup automation for java development on Fedora version 30.X or later

# usage function
usage() {
    echo "usage: $(basename $0) -j [openjdk-8-jdk | openjdk-11-jdk] -i [intellij | intellij-ultimate | eclipse | netbeans]"
}

# need to run as root
if [ "$EUID" -ne 0 ]; then
    echo "No root permission. Please run using 'sudo'"
    exit 1
fi

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
    IDE="intellij"
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
dnf upgrade --refresh

# install gnome-tweak tool
dnf -y install gnome-tweak-tool

# install vim
echo "installing vim"
dnf -y install vim

# install curl
echo "installing curl"
dnf -y install curl

# install mariadb
echo "installing mariadb"
dnf -y install mariadb-server mariadb

# install the specified jdkdnf
if [ "$JDK_PACKAGE" = "openjdk-8-jdk" ]; then
    dnf -y install java-1.8.0-openjdk-devel
    update-alternatives --set java java-1.8.0-openjdk.x86_64
    update-alternatives --set javac java-1.8.0-openjdk.x86_64
elif [ "$JDK_PACKAGE" = "openjdk-11-jdk" ]; then
    dnf -y install java-11-openjdk-devel
    update-alternatives --set java java-11-openjdk.x86_64
    update-alternatives --set javac java-11-openjdk.x86_64
fi

# install maven
echo "installing maven"
dnf -y install maven

# install google chrome
dnf -y install fedora-workstation-repositories
dnf config-manager --set-enabled google-chrome
dnf -y install google-chrome-stable
dnf -y install chrome-gnome-shell

if [ "$IDE" = "intellij" ]; then
    echo "intalling intellij-idea-community"
    snap install intellij-idea-community --classic
elif [ "$IDE" = "intellij-ultimate" ]; then
    # install intellij ultimate
    echo "intalling intellij-idea-ultimate"
    snap install intellij-idea-ultimate --classic
elif [ "$IDE" = "eclipse" ]; then
    # install eclipse 
    echo "installing eclipse"
    snap install eclipse --classic
elif [ "$IDE" = "netbeans" ]; then
    echo "installing netbeans"
    snap install netbeans --classic
fi

# install postman
echo "intalling postman"
snap install postman

echo "installing slack"
snap install slack --classic

echo "Recommended Tools"
echo "Database Management - DbVisualizer: https://www.dbvis.com/download/10.0"

echo "system restarting in 30 seconds..."
sleep 30
systemctl reboot

