@echo off

set MIX_ENV=dev
set BACVIEW_DESKTOP=1

mix desktop.setup && mix desktop.server
