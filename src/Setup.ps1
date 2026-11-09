<#
  Claude Severance setup. Opens the setup window for the right moment:
    first run -> install    older version installed -> update    same version -> manage accounts    -Mode uninstall -> uninstall
  Switches:
    -Mode auto|install|update|manage|uninstall
    -Silent [-RemoveData]   no window: repair the install with its current accounts, or uninstall (exit code 1 on failure)
    -Console                the text setup, for when a window can't open
    -Preview [-Screen <name>] [-Theme light|dark]   look at the window; changes nothing
#>
param(
    [ValidateSet('auto', 'install', 'update', 'manage', 'uninstall')][string]$Mode = 'auto',
    [switch]$Uninstall,
    [switch]$Silent,
    [switch]$RemoveData,
    [switch]$Console,
    [switch]$Preview,
    [ValidateSet('system', 'light', 'dark')][string]$Theme = 'system',
    [string]$Screen = '',
    [string]$Capture = '',
    [int]$CaptureDelay = 1600,
    [switch]$FromTemp
)
$ErrorActionPreference = 'Stop'
if ($Uninstall) { $Mode = 'uninstall' }
$here = $PSScriptRoot
Import-Module (Join-Path $here 'Severance.psm1') -Force
$log = Join-Path $env:TEMP 'claude-severance-setup.log'
function Write-Log([string]$Message) { try { Add-Content -Path $log -Value ("{0:s}  {1}" -f (Get-Date), $Message) } catch { } }

# ---- no window ----
if ($Silent) {
    try {
        if ($Mode -eq 'uninstall') { $null = Invoke-SeveranceUninstall -RemoveData ([bool]$RemoveData) }
        else {
            $i = Get-SeveranceSetupInfo $Mode
            $null = Invoke-SeveranceInstall -Accounts $i.Accounts -DesktopShortcuts ([bool]$i.DesktopShortcuts) -AutoSwitch ([bool]$i.AutoSwitch) -SourceDir $here
        }
        exit 0
    } catch {
        Write-Log "silent $Mode : $($_.Exception.Message)"
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
}

if ($Console) {
    & (Join-Path $here 'Setup-Console.ps1') -Mode $Mode
    exit $LASTEXITCODE
}

# ---- uninstall runs from a temporary copy, so the installed files can all be removed ----
$bin = Get-SeveranceBin
if ($Mode -eq 'uninstall' -and -not $Preview -and -not $FromTemp -and ([IO.Path]::GetFullPath($here).TrimEnd('\') -ieq $bin.TrimEnd('\'))) {
    $tmp = Join-Path $env:TEMP ('ClaudeSeverance-uninstall-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    foreach ($f in 'Severance.psm1', 'Setup.ps1', 'SetupWindow.ps1', 'Setup-Console.ps1') {
        if (Test-Path (Join-Path $here $f)) { Copy-Item (Join-Path $here $f) $tmp }
    }
    foreach ($d in 'fonts', 'assets') { if (Test-Path (Join-Path $here $d)) { Copy-Item (Join-Path $here $d) $tmp -Recurse } }
    Start-Process (Get-WindowsPowerShell) -ArgumentList @('-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$tmp\Setup.ps1`"", '-Mode', 'uninstall', '-FromTemp')
    exit 0
}

# ---- the window ----
try {
    & (Join-Path $here 'SetupWindow.ps1') -Mode $Mode -Preview:$Preview -Theme $Theme -Screen $Screen -Capture $Capture -CaptureDelay $CaptureDelay
} catch {
    Write-Log "window: $($_.Exception.Message)`r`n$($_.ScriptStackTrace)"
    if ($Capture) { Set-Content -Path "$Capture.error.txt" -Value "$($_.Exception.ToString())`r`n$($_.ScriptStackTrace)"; exit 2 }
    Add-Type -AssemblyName PresentationFramework
    $answer = [System.Windows.MessageBox]::Show(
        "The setup window couldn't open:`n$($_.Exception.Message)`n`nOpen the text setup instead?`n`nDetails: $log",
        'Claude Severance Setup', 'YesNo', 'Warning')
    if ([string]$answer -eq 'Yes') {
        Start-Process (Get-WindowsPowerShell) -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$here\Setup-Console.ps1`"", '-Mode', $Mode)
    }
    exit 1
}
