#!/bin/bash

# setup automation for java development on Ubunutu version 18.X or later

# need to run as root
if [ "$EUID" -ne 0 ]; then
    echo "No root permission. Please run using 'sudo'"
    exit 1
fi

while getopts ":j:" opt; do
  case ${opt} in
    j )
      JDK_PACKAGE=$OPTARG
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      exit 1
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# if no package provided, default to openjdk-11
if [ "$JDK_PACKAGE" = "" ]; then
    JDK_PACKAGE="openjdk-11-jdk"
fi

# validate choice of jdk package
if [ "$JDK_PACKAGE" != "oracle-8-jdk" ] && [ "$JDK_PACKAGE" != "openjdk-8-jdk" ] && [ "$JDK_PACKAGE" != "openjdk-11-jdk" ]; then
    echo "$JDK_PACKAGE is not a supported jdk package. Choose from: oracle-8-jdk, openjdk-8-jdk, or openjdk-11-jdk"
    exit 1
fi

# get everything up to date
echo "upgrading packages"
apt update
apt full-upgrade
# auto remove uneeded things
apt autoremove

# install git
echo "installing git"
apt install git

# install vim
echo "installing vim"
apt install vim

# install curl
echo "installing curl"
apt install curl

# install mariadb
echo "installing mariadb"
apt install mariadb-server mariadb-client

# install the specified jdk
echo "installing jdk"
if [ "$JDK_PACKAGE" = "oracle-8-jdk" ]; then
    # add oracle-jdk ppa
    add-apt-repository ppa:webupd8team/java
    apt update 
    # install oracle jdk 8
    apt install oracle-java8-installer
    ln -s /usr/lib/jvm/java-8-oracle /usr/lib/jvm/default-jdk
else # its an openjdk package
    version_num=${JDK_PACKAGE#openjdk-}
    version_num=${version_num%jdk-}
    apt install $JDK_PACKAGE
    # this next command sets all the appropriate sym links (e.g java, javac, etc.)
    update-java-alternatives -s java-1.$version_num.0-openjdk-amd64
    ln -s /usr/lib/jvm/java-1.$version_num.0-openjdk-amd64 /usr/lib/jvm/default-jdk
fi

# install maven
echo "installing maven"
apt install maven

# install intellij
echo "intalling intellij-idea-ultimate"
snap install intellij-idea-ultimate --classic

# install postman
echo "intalling postman"
snap install postman

echo "Recommended Tools"
echo "Database Management - DbVisualizer: https://www.dbvis.com/download/10.0"

