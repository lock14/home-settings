#!/bin/bash
set -euo pipefail

# user stuff
mkdir -p "$HOME/bin"
rsync -av ./common-bin/ "$HOME/bin"

