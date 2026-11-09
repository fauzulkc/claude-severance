# Kept for older Start menu entries and Settings > Apps entries from v1.0: forwards to the setup window.
#   -Yes / -Quiet   uninstall without a window     -RemoveData   also remove the extra accounts (zipped first)
param([switch]$Yes, [switch]$Quiet, [switch]$RemoveData)
if ($Yes -or $Quiet) { & (Join-Path $PSScriptRoot 'Setup.ps1') -Mode uninstall -Silent -RemoveData:$RemoveData }
else { & (Join-Path $PSScriptRoot 'Setup.ps1') -Mode uninstall }
exit $LASTEXITCODE
