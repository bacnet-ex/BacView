#!/usr/bin/env bash
set -euo pipefail

export MIX_ENV=prod
export BACVIEW_DESKTOP=1

# First make sure that the dependencies are present, otherwise phx.gen.secret fails
mix deps.get
export SECRET_KEY_BASE=$(mix phx.gen.secret)

mix desktop.setup && mix desktop.installer
