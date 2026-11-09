<#
  Claude Severance text setup: the same install, update, account changes and uninstall as the setup window,
  as questions in a console. Used when the window can't open, or with Install.cmd /text.
#>
param([string]$Mode = 'auto')
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Severance.psm1') -Force

function Read-Default([string]$Prompt, [string]$Default) {
    $v = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
    return $v.Trim()
}
function Read-YesNo([string]$Prompt, [bool]$Default) {
    $hint = 'y/N'; if ($Default) { $hint = 'Y/n' }
    while ($true) {
        $v = Read-Host "$Prompt ($hint)"
        if (-not $v) { return $Default }
        if ($v -match '^[Yy]') { return $true }
        if ($v -match '^[Nn]') { return $false }
    }
}
function Read-Paths {
    $paths = [string](Read-Host '  Project folders, separated by ; (optional)')
    return @($paths -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })
}
function Show-List($List) {
    Write-Host ''
    for ($i = 0; $i -lt $List.Count; $i++) {
        $a = $List[$i]
        $tag = ''; if ($a.main) { $tag = '   (main - your normal Claude)' }
        $em = ''; if ($a.email) { $em = "  <$($a.email)>" }
        Write-Host ("  {0}) {1}{2}{3}" -f ($i + 1), $a.name, $em, $tag)
    }
    Write-Host ''
}
$Ok = { param($t) Write-Host "  done  $t" -ForegroundColor DarkGreen }

$failed = $false
try {
    $info = Get-SeveranceSetupInfo $Mode
    Write-Host ''
    Write-Host " Claude Severance $($info.Version) " -BackgroundColor DarkCyan -ForegroundColor White
    Write-Host ''

    if ($info.Mode -eq 'uninstall') {
        $extras = @($info.Accounts | Where-Object { -not $_.main })
        $main = (@($info.Accounts | Where-Object { $_.main }))[0].name
        Write-Host "Back to one Claude. $main stays your normal Claude, untouched."
        $rd = $false
        if ($extras.Count) {
            $rd = Read-YesNo "Also remove $(($extras | ForEach-Object { $_.name }) -join ', ') from this PC? (zipped first, without logins)" $false
        }
        if (-not (Read-YesNo 'Uninstall Claude Severance now?' $false)) { return }
        $r = Invoke-SeveranceUninstall -RemoveData $rd -Step $Ok
        Write-Host ''
        Write-Host " Claude Severance is removed. $($r.MainName) is your single Claude again. " -BackgroundColor DarkGreen -ForegroundColor White
        if ($r.Backup) { Write-Host "  Backup, without logins: $($r.Backup)" }
        if ($r.KeptData) { Write-Host '  Extra accounts are kept, signed in, in case you install again.' }
        if ($r.Left) { Write-Host "  Some files were in use and go at your next Windows sign-in: $($r.Left)" -ForegroundColor DarkYellow }
        return
    }

    $accounts = New-Object System.Collections.ArrayList
    foreach ($a in @($info.Accounts)) { [void]$accounts.Add($a) }
    $removed = New-Object System.Collections.ArrayList

    if ($info.Source -eq 'new') {
        Write-Host 'Main account: your normal Claude app, kept as it is.' -ForegroundColor Cyan
        $m = $accounts[0]
        $m.name = Read-Default '  Name' $m.name
        $m.label = New-AccountLabel $m.name
        $m.email = Read-Default '  Email it signs in with' $m.email
        $m.paths = @(Read-Paths)
        $more = $true
        while ($more) {
            Write-Host "Account $($accounts.Count + 1):" -ForegroundColor Cyan
            $name = Read-Default '  Name' "Org $($accounts.Count)"
            $email = [string](Read-Host '  Email it signs in with (optional)')
            [void]$accounts.Add((New-SeveranceAccount $name $email @(Read-Paths) $false @($accounts | ForEach-Object { $_.id }) $accounts.Count))
            $more = Read-YesNo 'Add another account?' $false
        }
    } else {
        while ($true) {
            Write-Host 'Your accounts:' -ForegroundColor Cyan
            Show-List $accounts
            $c = Read-Host 'Enter = keep these, A = add an account, R = remove an account'
            if (-not $c) { break }
            if ($c -match '^[Aa]') {
                $name = Read-Default '  Name' "Org $($accounts.Count)"
                $email = [string](Read-Host '  Email it signs in with (optional)')
                [void]$accounts.Add((New-SeveranceAccount $name $email @(Read-Paths) $false @($accounts | ForEach-Object { $_.id }) $accounts.Count))
            } elseif ($c -match '^[Rr]') {
                $n = 0
                if (-not [int]::TryParse((Read-Host 'Number of the account to remove'), [ref]$n) -or $n -lt 1 -or $n -gt $accounts.Count) { continue }
                $acc = $accounts[$n - 1]
                if ($acc.main) { Write-Host "The main account stays. To go back to one Claude, uninstall instead." -ForegroundColor Yellow; continue }
                if (Read-YesNo "Remove $($acc.name)? It is backed up first, without its login" $false) { [void]$removed.Add($acc.id); $accounts.Remove($acc) }
            }
        }
    }

    $desktopShortcuts = Read-YesNo 'Put shortcuts on the desktop?' ([bool]$info.DesktopShortcuts)
    $auto = $false
    if (-not $info.ScriptsBlocked) {
        $auto = Read-YesNo "Let plain 'claude' pick the account by folder?" ([bool]$info.AutoSwitch -or $info.Source -eq 'new')
    }
    $allow = $false
    if ($auto -and $info.NeedsScripts) { $allow = Read-YesNo 'That needs your own PowerShell scripts to run (RemoteSigned, for you only). Allow?' $true }
    $installDesktop = $false
    if (-not $info.DesktopFound) {
        if (-not $info.Winget) { Start-Process 'https://claude.ai/download'; throw 'Install Claude Desktop from the page that just opened, then run setup again.' }
        $installDesktop = Read-YesNo 'Claude Desktop is not installed. Install it with winget?' $true
        if (-not $installDesktop) { throw 'Claude Desktop is needed. Install it, then run setup again.' }
    }
    $installCode = $false
    if (-not $info.CodeFound) { $installCode = Read-YesNo 'Install Claude Code (the claude command) too?' $true }

    Write-Host ''
    $r = Invoke-SeveranceInstall -Accounts @($accounts) -RemovedIds @($removed) -DesktopShortcuts $desktopShortcuts -AutoSwitch $auto -AllowScripts $allow `
        -InstallDesktopApp $installDesktop -InstallCode $installCode -SourceDir $PSScriptRoot -Step $Ok
    Write-Host ''
    Write-Host ' Claude Severance is ready. ' -BackgroundColor DarkGreen -ForegroundColor White
    foreach ($n in @($r.Notes)) { Write-Host "  $n" -ForegroundColor DarkYellow }
    Write-Host ''
    Write-Host 'Sign in once per extra account. Open it from its Start menu or desktop shortcut.'
    Write-Host 'The sign-in link opens your main Claude: copy the code it shows, press Cancel there, then paste it into the new window.'
    Write-Host 'Claude Code, in a new terminal:'
    foreach ($a in @($r.Accounts | Where-Object { -not $_.main })) { Write-Host "  $(Get-AccountAlias $a)   then /login" }
} catch {
    $failed = $true
    Write-Host ''
    Write-Host " Setup stopped: $($_.Exception.Message) " -BackgroundColor DarkRed -ForegroundColor White
}
Write-Host ''
[void](Read-Host 'Press Enter to close')
if ($failed) { exit 1 }
