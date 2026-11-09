# severance                          show every account, its command, and who it is signed in as
# severance list                     the same
# severance add <name> [--email <address>] [--alias <command>] [--folder <path>]...
#                                    add an org account (its command defaults to claude-<name>)
# severance remove <account> [--yes] remove an account; its memory and history are zipped first, without its login
# severance alias <account> <command>   rename an account's terminal command
# severance setup [--text]           add, rename or remove accounts in the setup window (or as questions here)
# severance repair                   reinstall with the current accounts, no window
# severance open <account>           open Claude Desktop for an account
# severance uninstall [--text]       go back to a single Claude
# <account> is an account's id, name or command.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Severance.psm1') -Force
$cmd = 'status'
if ($args.Count -gt 0) { $cmd = ([string]$args[0]).ToLowerInvariant() }
$text = @($args | Where-Object { $_ -in '--text', '-text', '/text' }).Count -gt 0
$ps = Get-WindowsPowerShell
$setup = Join-Path $PSScriptRoot 'Setup.ps1'

function Open-SetupWindow([string]$Mode) {
    Start-Process $ps -ArgumentList @('-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$setup`"", '-Mode', $Mode)
}

# Words after the command, and the values of --name options (an option may repeat)
$words = New-Object System.Collections.ArrayList
$opts = @{}
for ($i = 1; $i -lt $args.Count; $i++) {
    $w = [string]$args[$i]
    if ($w -match '^--?([a-z]+)$' -and $Matches[1] -notin 'text', 'yes') {
        $k = $Matches[1]
        if ($i + 1 -ge $args.Count) { throw "--$k needs a value." }
        if (-not $opts.ContainsKey($k)) { $opts[$k] = @() }
        $opts[$k] += [string]$args[$i + 1]; $i++
    } elseif ($w -notmatch '^--?(text|yes)$') { [void]$words.Add($w) }
}
$yes = @($args | Where-Object { $_ -in '--yes', '-yes', '-y' }).Count -gt 0

function Find-Account($Accounts, [string]$Key) {
    $k = $Key.ToLowerInvariant()
    $hit = @($Accounts | Where-Object { $_.id -eq $k -or ([string]$_.name).ToLowerInvariant() -eq $k -or (Get-AccountAlias $_) -eq $k })
    if ($hit.Count -eq 0) { throw "No account called $Key. Run 'severance list' to see them." }
    return $hit[0]
}

# Saves changed accounts the same way the setup window does, printing each finished step
function Save-Accounts($Accounts, [string[]]$Removed = @()) {
    $r = Invoke-SeveranceInstall -Accounts @($Accounts) -RemovedIds $Removed -DesktopShortcuts (Test-SeveranceDesktopShortcuts) `
        -AutoSwitch (Test-ShellHook) -SourceDir $PSScriptRoot -Step { param($t) Write-Host "  done  $t" -ForegroundColor DarkGreen }
    foreach ($n in @($r.Notes)) { Write-Host "  $n" -ForegroundColor DarkYellow }
    Write-Host 'Open a new terminal to use changed commands.' -ForegroundColor DarkGray
}

# Problems are said in one plain line, not a PowerShell stack trace
try {
switch ($cmd) {
    { $_ -in 'status', 'list' } {
        Get-SeveranceStatus | Format-Table -AutoSize
        Write-Host 'severance add <name> | remove <account> | alias <account> <command> | setup | open <account> | repair | uninstall' -ForegroundColor DarkGray
    }
    'add' {
        if ($words.Count -lt 1) { throw 'Usage: severance add <name> [--email <address>] [--alias <command>] [--folder <path>]...' }
        $cfg = Get-SeveranceConfig
        $accounts = @($cfg.accounts)
        $name = ($words -join ' ').Trim()
        if (@($accounts | Where-Object { ([string]$_.name).ToLowerInvariant() -eq $name.ToLowerInvariant() }).Count) { throw "There is already an account called $name." }
        $email = ''; if ($opts.email) { $email = $opts.email[0] }
        $new = New-SeveranceAccount $name $email @($opts.folder) $false @($accounts | ForEach-Object { $_.id }) $accounts.Count
        $used = @($accounts | ForEach-Object { $_.color })
        $free = @(Get-SeverancePalette | Where-Object { $used -notcontains $_ }); if ($free.Count) { $new.color = $free[0] }
        $alias = Get-DefaultAlias $new.id; if ($opts.alias) { $alias = $opts.alias[0].ToLowerInvariant() }
        $new | Add-Member -NotePropertyName alias -NotePropertyValue $alias -Force
        $why = Test-SeveranceAlias $alias $new.id $accounts
        if ($why) { throw $why }
        Write-Host "Adding $name, with the command $alias" -ForegroundColor Cyan
        Save-Accounts ($accounts + $new)
        Write-Host "Next: open 'Claude - $name' from the Start menu and sign in, and run $alias then /login." -ForegroundColor Cyan
    }
    'remove' {
        if ($words.Count -lt 1) { throw 'Usage: severance remove <account> [--yes]' }
        $accounts = @((Get-SeveranceConfig).accounts)
        $a = Find-Account $accounts $words[0]
        if ($a.main) { throw "$($a.name) is your main account and stays. To go back to one Claude, run 'severance uninstall'." }
        if (-not $yes) {
            $ans = Read-Host "Remove $($a.name)? Its memory and history are zipped to '$(Get-SeveranceBackupDir)' first, without its login. [y/N]"
            if ($ans -notmatch '^[Yy]') { Write-Host 'Kept.'; return }
        }
        Save-Accounts @($accounts | Where-Object { $_.id -ne $a.id }) @($a.id)
    }
    'alias' {
        if ($words.Count -lt 2) { throw 'Usage: severance alias <account> <command>' }
        $accounts = @((Get-SeveranceConfig).accounts)
        $a = Find-Account $accounts $words[0]
        $alias = ([string]$words[1]).ToLowerInvariant()
        if ((Get-AccountAlias $a) -eq $alias) { Write-Host "$($a.name) already uses $alias."; return }
        $why = Test-SeveranceAlias $alias $a.id $accounts
        if ($why) { throw $why }
        $old = Get-AccountAlias $a
        Set-JsonProp $a 'alias' $alias | Out-Null
        Write-Host "$($a.name): $old is now $alias" -ForegroundColor Cyan
        Save-Accounts $accounts
    }
    'setup' {
        if ($text) { & (Join-Path $PSScriptRoot 'Setup-Console.ps1') -Mode manage } else { Open-SetupWindow 'manage' }
    }
    'repair' {
        & $setup -Mode manage -Silent
        if ($LASTEXITCODE -eq 0) { Write-Host 'Repaired.' -ForegroundColor Green }
    }
    'uninstall' {
        if ($text) { & (Join-Path $PSScriptRoot 'Setup-Console.ps1') -Mode uninstall } else { Open-SetupWindow 'uninstall' }
    }
    'open' {
        if ($words.Count -lt 1) { throw 'Usage: severance open <account>' }
        Start-SeveranceDesktop (Find-Account @((Get-SeveranceConfig).accounts) $words[0]).id
    }
    'version' { "Claude Severance $(Get-SeveranceVersion)" }
    default { Write-Host 'Usage: severance [list | add <name> | remove <account> | alias <account> <command> | setup [--text] | open <account> | repair | uninstall [--text] | version]' }
}
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
