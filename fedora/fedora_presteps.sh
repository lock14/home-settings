#!/bin/bash

set -euo pipefail

# Ensure sudo credentials are valid
sudo -v

echo "updating system"
sudo dnf -y upgrade --refresh

echo "installing snapd"
sudo dnf -y install snapd
sudo ln -sf /var/lib/snapd/snap /snap

echo "Pre-steps complete! A system restart is recommended to ensure snapd is active."
