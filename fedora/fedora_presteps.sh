#!/bin/bash

echo "updating system"
sudo dnf -y upgrade --refresh

echo "installing snapd"
sudo dnf -y install snapd
sudo ln -s /var/lib/snapd/snap /snap

echo "system restarting in 30 seconds..."
sleep 30
systemctl reboot
