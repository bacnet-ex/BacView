@echo off

set MIX_ENV=dev
set BACVIEW_DESKTOP=1

mix setup && mix desktop.setup && mix desktop.server
