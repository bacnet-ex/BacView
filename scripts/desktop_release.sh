#!/usr/bin/env bash
set -euo pipefail

# Check if running locally on Arch Linux by inspecting /etc/os-release
if grep -qi "arch" /etc/os-release 2>/dev/null; then
    # Set NO_STRIP so that AppImage builder does not fail
    export NO_STRIP=true
    echo "Arch Linux detected: Automatically setting NO_STRIP=true"
fi

export MIX_ENV=prod
export BACVIEW_DESKTOP=1

# First make sure that the dependencies are present, otherwise phx.gen.secret fails
mix deps.get
export SECRET_KEY_BASE=$(mix phx.gen.secret)

mix desktop.setup && mix desktop.installer
