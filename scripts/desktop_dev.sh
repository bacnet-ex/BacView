#!/usr/bin/env bash
set -euo pipefail

export MIX_ENV=dev
export BACVIEW_DESKTOP=1

mix desktop.setup && mix desktop.server
