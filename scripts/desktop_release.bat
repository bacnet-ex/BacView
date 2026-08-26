@echo off

set MIX_ENV=prod
set BACVIEW_DESKTOP=1

REM Make sure first that the dependencies are present, otherwise phx.gen.secret fails
mix deps.get
FOR /F "tokens=*" %g IN ('mix phx.gen.secret') DO SET SECRET_KEY_BASE=%g

mix desktop.setup && mix desktop.installer
