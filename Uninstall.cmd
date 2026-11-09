@echo off
set "SEV=%LOCALAPPDATA%\ClaudeSeverance\bin\Setup.ps1"
if not exist "%SEV%" set "SEV=%~dp0src\Setup.ps1"
start "" powershell -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%SEV%" -Mode uninstall
