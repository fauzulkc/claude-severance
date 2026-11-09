@echo off
rem Opens the setup window in preview: it shows every screen and changes nothing.
rem   Preview.cmd [install|update|manage|uninstall] [light|dark] [screen]
set "M=%~1" & if "%~1"=="" set "M=install"
set "TH=%~2" & if "%~2"=="" set "TH=system"
start "" powershell -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0src\Setup.ps1" -Preview -Mode %M% -Theme %TH% -Screen "%~3"
