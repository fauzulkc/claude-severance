# Runs Claude Code on one account.
#   claude-account.ps1 <id> [claude args...]   explicit account (what claude-<id> calls)
#   claude-account.ps1 auto [claude args...]   account picked from the current folder; asks when the folder isn't mapped
# No param() block on purpose: every flag after the account id goes to claude untouched.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Severance.psm1') -Force

if ($args.Count -lt 1) {
    Write-Host 'Usage: claude-<account> [claude args...]'
    Get-SeveranceStatus | Format-Table -AutoSize
    exit 1
}
$id = [string]$args[0]
$rest = @()
if ($args.Count -gt 1) { $rest = @($args[1..($args.Count - 1)]) }

if ($id -eq 'auto') {
    $id = Resolve-AccountForPath (Get-Location).Path
    if (-not $id) {
        # Unmapped folder: ask instead of guessing, so org work never lands on the wrong account
        if ([Console]::IsInputRedirected) { throw "This folder isn't mapped to an account. Use claude-<account>, or add the folder with 'severance setup'." }
        $all = @((Get-SeveranceConfig).accounts)
        Write-Host "This folder isn't mapped to an account. Which account?"
        for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $all[$i].name) }
        $pick = Read-Host 'Number'
        $n = 0
        if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 1 -or $n -gt $all.Count) { throw 'Cancelled.' }
        $id = [string]$all[$n - 1].id
        Write-Host "Tip: run 'severance setup' and add this folder to that account to skip this question." -ForegroundColor DarkGray
    }
}

Show-AccountBanner $id
Invoke-SeveranceClaude -Id $id -ClaudeArgs $rest
exit $LASTEXITCODE
