#!/bin/bash
# Pre-steps for Fedora workstations (snapd and package manager setup)
# Delegates to fedora/os-packages.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/os-packages.sh" "$@"
