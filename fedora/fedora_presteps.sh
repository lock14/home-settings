#!/bin/bash

# need to run as root
if [ "$EUID" -ne 0 ]; then
    echo "No root permission. Please run using 'sudo'"
    exit 1
fi

echo "updating system"
dnf -y upgrade --refresh

echo "installing snapd"
dnf -y install snapd
ln -s /var/lib/snapd/snap /snap
echo "PATH=$PATH:/var/lib/snapd/snap/bin" >> /etc/bashrc

echo "system restarting in 30 seconds..."
sleep 30
systemctl reboot
