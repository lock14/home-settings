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

echo "Pre-steps complete! A system restart is recommended to ensure snapd is active."
