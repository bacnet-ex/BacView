#!/usr/bin/env bash
set -euo pipefail

export MIX_ENV=prod
export BACVIEW_DESKTOP=1

mix setup && mix desktop.setup && mix desktop.installer
