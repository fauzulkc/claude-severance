# Opens Claude Desktop for one account. Used by the "Claude - <name>" shortcuts.
param([Parameter(Mandatory)][string]$AccountId)
$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'Severance.psm1') -Force
    Start-SeveranceDesktop $AccountId
} catch {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show($_.Exception.Message, 'Claude Severance') | Out-Null
    exit 1
}
