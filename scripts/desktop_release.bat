@echo off

set MIX_ENV=prod
set BACVIEW_DESKTOP=1

mix setup && mix desktop.setup && mix desktop.installer
