@echo off
if not exist "%~dp0src\Setup.ps1" (
  echo.
  echo  Extract the Claude Severance zip first, then run Install.cmd from the extracted folder.
  echo.
  pause
  exit /b 1
)
if /i "%~1"=="/text" (
  powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Setup.ps1" -Console
  exit /b
)
start "" powershell -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0src\Setup.ps1"
