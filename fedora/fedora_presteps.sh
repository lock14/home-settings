#!/bin/bash

if [ "$PASS" = "" ]; then
    printf "[password]: "
    read -s PASS
    echo ""
fi

echo "updating system"
echo $PASS | sudo -S dnf -y upgrade --refresh

echo "installing snapd"
echo $PASS | sudo -S dnf -y install snapd
echo $PASS | sudo -S ln -s /var/lib/snapd/snap /snap

echo "system restarting in 30 seconds..."
sleep 30
systemctl reboot
