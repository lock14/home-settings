#!/bin/bash
# Setup automation for Ubuntu workstations
# Delegates to the common modular system setup engine

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../system/system-setup.sh" --os ubuntu "$@"
