#!/bin/bash

# setup automation for java development on Ubuntu version 18.X or later

usage() {
    echo "usage: $(basename $0) -j [oracle-8-jdk | openjdk-8-jdk | openjdk-11-jdk] -i [intellij | intellij-ultimate | eclipse | netbeans]"
}

# need to run as root
if [ "$EUID" -ne 0 ]; then
    echo "No root permission. Please run using 'sudo'"
    exit 1
fi

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
    JDK_PACKAGE="openjdk-11-jdk"
fi

# if no ide provided, default to intellij
if [ "$IDE" = "" ]; then
    IDE="intellij"
fi

# validate choice of jdk package
if [ "$JDK_PACKAGE" != "oracle-8-jdk" ] && [ "$JDK_PACKAGE" != "openjdk-8-jdk" ] && [ "$JDK_PACKAGE" != "openjdk-11-jdk" ]; then
    echo "$JDK_PACKAGE is not a supported jdk package. Choose from: oracle-8-jdk, openjdk-8-jdk, or openjdk-11-jdk"
    exit 1
fi

# validate choice of ide
if [ "$IDE" != "intellij" ] && [ "$IDE" != "intellij-ultimate" ] && [ "$IDE" != "eclipse" ] && [ "$IDE" != "netbeans" ]; then
    echo "$IDE is not a supported IDE. Chose from: intellij, intellij-ultimate, eclipse, or netbeans"
fi

# get everything up to date
echo "upgrading packages"
apt --yes update
apt --yes full-upgrade
# auto remove uneeded things
apt --yes autoremove

# install chrome
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -P ~/Downloads
dpkg -i ~/Downloads/google-chrome-stable_current_amd64.deb

# install vim
echo "installing vim"
apt --yes install vim

# install curl
echo "installing curl"
apt --yes install curl

# install mariadb
echo "installing mariadb"
apt --yes install mariadb-server mariadb-client

# install the specified jdk
echo "installing jdk"
if [ "$JDK_PACKAGE" = "oracle-8-jdk" ]; then
    # add oracle-jdk ppa
    add-apt-repository --yes ppa:webupd8team/java
    apt --yes update 
    # install oracle jdk 8
    apt --yes install oracle-java8-installer
    ln -s /usr/lib/jvm/java-8-oracle /usr/lib/jvm/default-jdk
else # its an openjdk package
    version_num=${JDK_PACKAGE#openjdk-}
    version_num=${version_num%jdk-}
    apt --yes install $JDK_PACKAGE $JDK_PACKAGE-source
    # this next command sets all the appropriate sym links (e.g java, javac, etc.)
    update-java-alternatives -s java-1.$version_num.0-openjdk-amd64
    ln -s /usr/lib/jvm/java-1.$version_num.0-openjdk-amd64 /usr/lib/jvm/default-jdk
fi

# install maven
echo "installing maven"
apt --yes install maven

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

echo "rebooting..."	
systemctl reboot
