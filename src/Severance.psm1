# Severance.psm1 - Claude Severance
# Separate Claude accounts side by side on Windows: Claude Desktop + Claude Code, each with its own login and context.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.

$script:Version = '1.1.0'
# Account colours: muted mid-century tones (blue, mustard, green, rust, plum, rose, teal, orange)
$script:Palette = @('#3E6FA3', '#C08A2E', '#3E7A5A', '#B4442E', '#6C5B9E', '#B5577A', '#2F8A86', '#C46A2B')
$script:HookStart = '# >>> claude-severance >>>'
$script:HookEnd = '# <<< claude-severance <<<'
$script:Utf8 = New-Object System.Text.UTF8Encoding $false

# ---------------- locations ----------------
function Get-SeveranceVersion { return $script:Version }
function Get-SeverancePalette { return $script:Palette }
function Get-SeveranceRoot { return (Join-Path $env:LOCALAPPDATA 'ClaudeSeverance') }
function Get-SeveranceBin { return (Join-Path (Get-SeveranceRoot) 'bin') }
function Get-SeveranceConfigPath { return (Join-Path (Get-SeveranceRoot) 'accounts.json') }
function Get-SeveranceStartMenu { return (Join-Path ([Environment]::GetFolderPath('Programs')) 'Claude Severance') }
function Get-SeveranceBackupDir { return (Join-Path $env:USERPROFILE 'Claude Severance backups') }
function Get-WindowsPowerShell { return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') }

function Expand-PathVars([string]$p) {
    if (-not $p) { return $p }
    return [Environment]::ExpandEnvironmentVariables($p).TrimEnd('\')
}

function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

# ---------------- JSON helpers ----------------
function Read-JsonFile([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    $text = [IO.File]::ReadAllText($Path)
    if (-not $text.Trim()) { return $null }
    return ($text | ConvertFrom-Json)
}

function Write-JsonFile([string]$Path, $Object) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
    [IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 64), $script:Utf8)
}

function Get-JsonProp($Object, [string]$Name) {
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

# Sets (or with $null removes) a property; returns $true when something changed
function Set-JsonProp($Object, [string]$Name, $Value) {
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $Value) {
        if ($p) { $Object.PSObject.Properties.Remove($Name); return $true }
        return $false
    }
    if ($p) {
        if ((ConvertTo-Json $p.Value -Depth 64 -Compress) -eq (ConvertTo-Json $Value -Depth 64 -Compress)) { return $false }
        $p.Value = $Value
        return $true
    }
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    return $true
}

# ---------------- accounts ----------------
function Test-SeveranceConfig($Config) {
    $accts = @($Config.accounts)
    if ($accts.Count -eq 0) { throw 'accounts.json has no accounts.' }
    $ids = @($accts | ForEach-Object { [string]$_.id })
    foreach ($id in $ids) {
        if ($id -notmatch '^[a-z0-9][a-z0-9-]*$' -or $id -eq 'auto') {
            throw "Account id '$id' is invalid: use lowercase letters, digits and dashes, and not 'auto'."
        }
    }
    if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { throw 'Account ids must be unique.' }
    if (@($accts | Where-Object { $_.main }).Count -ne 1) { throw 'Exactly one account must be the main account.' }
}

function Get-SeveranceConfig {
    $path = Get-SeveranceConfigPath
    if (-not (Test-Path $path)) { throw "Claude Severance isn't set up yet. Run Install.cmd." }
    $cfg = Read-JsonFile $path
    Test-SeveranceConfig $cfg
    return $cfg
}

function Save-SeveranceConfig($Config) {
    Test-SeveranceConfig $Config
    Write-JsonFile (Get-SeveranceConfigPath) $Config
}

function Get-SeveranceAccount([string]$Id) {
    $cfg = Get-SeveranceConfig
    $a = @($cfg.accounts | Where-Object { $_.id -eq $Id })
    if ($a.Count -eq 0) { throw "Unknown account '$Id'. Known: $((@($cfg.accounts) | ForEach-Object { $_.id }) -join ', ')" }
    return $a[0]
}

function Get-MainAccount { return (@((Get-SeveranceConfig).accounts | Where-Object { $_.main }))[0] }
function Test-MainAccount([string]$Id) { return [bool](Get-SeveranceAccount $Id).main }

function Get-AccountLabel($Account) {
    if ($Account.label) { return [string]$Account.label }
    return ([string]$Account.id).ToUpper()
}

# ---------------- command aliases ----------------
# Each account has its own terminal command. It defaults to claude-<id> (what v1.0 made) and can be renamed.
# Names cmd.exe or PowerShell treat specially, and Claude's own commands, are never allowed.
$script:ReservedAliases = @('claude', 'severance', 'claude-account', 'cmd', 'powershell', 'pwsh', 'wsl', 'bash', 'git',
    'assoc', 'call', 'cd', 'chdir', 'cls', 'color', 'copy', 'date', 'del', 'dir', 'echo', 'endlocal', 'erase', 'exit', 'for',
    'ftype', 'goto', 'if', 'md', 'mkdir', 'mklink', 'move', 'path', 'pause', 'popd', 'prompt', 'pushd', 'rd', 'rem', 'ren',
    'rename', 'rmdir', 'set', 'setlocal', 'shift', 'start', 'time', 'title', 'type', 'ver', 'verify', 'vol',
    'con', 'prn', 'aux', 'nul', 'com1', 'com2', 'com3', 'com4', 'lpt1', 'lpt2', 'lpt3')

function Get-DefaultAlias([string]$Id) { return "claude-$Id" }

function Get-AccountAlias($Account) {
    $a = [string](Get-JsonProp $Account 'alias')
    if ($a) { return $a.ToLowerInvariant() }
    return (Get-DefaultAlias ([string]$Account.id))
}

# Returns $null when Alias can be used for the account Id, or a sentence saying why not.
# Others: the other accounts (anything with name, id and alias). Checks, in order: the shape of the name, names Windows
# and Claude reserve, the other accounts, then every command PowerShell can find on this PC except our own shims.
function Test-SeveranceAlias([string]$Alias, [string]$Id, $Others = @()) {
    $a = ([string]$Alias).Trim().ToLowerInvariant()
    if (-not $a) { return 'Give it a command name.' }
    if ($a -notmatch '^[a-z0-9][a-z0-9._-]{0,39}$') { return "$Alias can't be a command: use letters, digits, dots, dashes or underscores, starting with a letter or digit." }
    if ($a.EndsWith('.') -or $a -match '\.(cmd|bat|exe|ps1|com)$') { return "$Alias can't be a command: leave off the dot and extension." }
    if ($script:ReservedAliases -contains $a) { return "$a is taken by Windows or Claude itself. Pick another name." }
    foreach ($o in @($Others)) {
        if ([string]$o.id -eq $Id) { continue }
        if ((Get-AccountAlias $o) -eq $a) { return "$a is already the command for $($o.name)." }
    }
    $bin = (Get-SeveranceBin).TrimEnd('\')
    foreach ($c in @(Get-Command $a -All -ErrorAction SilentlyContinue)) {
        if ($c.CommandType -eq 'Application' -and $c.Source -and ((Split-Path $c.Source).TrimEnd('\') -ieq $bin)) { continue }
        $where = [string]$c.Source; if (-not $where) { $where = "a PowerShell $(([string]$c.CommandType).ToLowerInvariant())" }
        return "$a is already a command on this PC ($where). Pick another name."
    }
    return $null
}

# Our shims are the .cmd files in bin that call claude-account.ps1
function Get-SeveranceShims {
    $bin = Get-SeveranceBin
    if (-not (Test-Path $bin)) { return @() }
    return @(Get-ChildItem $bin -Filter '*.cmd' -File | Where-Object { (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'claude-account\.ps1' })
}

function Get-AccountShortcutName($Account) {
    return ("Claude - " + ([string]$Account.name -replace '[\\/:*?"<>|]', ''))
}

# Value for CLAUDE_CONFIG_DIR, or $null for the main account (stock ~/.claude, variable unset)
function Get-ClaudeCodeEnv([string]$Id) {
    if (Test-MainAccount $Id) { return $null }
    return (Join-Path (Get-SeveranceRoot) "code\$Id")
}

# Folder holding this account's Claude Code config (settings.json, CLAUDE.md, credentials)
function Get-ClaudeCodeDir([string]$Id) {
    $e = Get-ClaudeCodeEnv $Id
    if ($e) { return $e }
    return (Join-Path $env:USERPROFILE '.claude')
}

# Claude Code's account/state file for this account
function Get-ClaudeStateFile([string]$Id) {
    $e = Get-ClaudeCodeEnv $Id
    if ($e) { return (Join-Path $e '.claude.json') }
    return (Join-Path $env:USERPROFILE '.claude.json')
}

# Claude Desktop data folder for an account ($null = the normal app data)
function Get-ClaudeDesktopDir([string]$Id) {
    if (Test-MainAccount $Id) { return $null }
    return (Join-Path (Get-SeveranceRoot) "desktop\$Id")
}

# Which account a CLAUDE_CONFIG_DIR value belongs to (empty = main account)
function Find-AccountByConfigDir([string]$ConfigDir) {
    $cfg = Get-SeveranceConfig
    if (-not $ConfigDir) { return (Get-MainAccount).id }
    $want = (Expand-PathVars $ConfigDir).ToLowerInvariant()
    foreach ($a in @($cfg.accounts)) {
        if ((Get-ClaudeCodeDir $a.id).TrimEnd('\').ToLowerInvariant() -eq $want) { return $a.id }
    }
    return $null
}

# Email/org Claude Code is signed in with for this account (best effort)
# Reads only the oauthAccount object (email and org, no tokens) from a Claude Code state file. ConvertFrom-Json can't
# be used: a long-used .claude.json often holds keys that differ only by case (project paths), and it rejects the
# whole file. .NET's JavaScriptSerializer keeps keys case-sensitive.
function Read-OAuthAccount([string]$File) {
    if (-not (Test-Path -LiteralPath $File)) { return $null }
    $text = [IO.File]::ReadAllText($File)
    if ($PSVersionTable.PSVersion.Major -ge 6) { $o = $text | ConvertFrom-Json -AsHashtable }
    else {
        Add-Type -AssemblyName System.Web.Extensions
        $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $js.MaxJsonLength = [int]::MaxValue
        $o = $js.DeserializeObject($text)
    }
    if ($o -and $o.ContainsKey('oauthAccount')) { return $o['oauthAccount'] }
    return $null
}

function Get-ClaudeAccountInfo([string]$Id) {
    $info = [pscustomobject]@{ Email = $null; Org = $null }
    try {
        $acct = Read-OAuthAccount (Get-ClaudeStateFile $Id)
        if ($acct) {
            $info.Email = [string]$acct['emailAddress']
            $info.Org = [string]$acct['organizationName']
        }
    } catch { }
    return $info
}

# Profile for a folder from 'paths' (longest match). $null means: ask the user.
function Resolve-AccountForPath([string]$Dir) {
    $cfg = Get-SeveranceConfig
    $dirN = (Expand-PathVars $Dir).ToLowerInvariant() + '\'
    $best = $null; $bestLen = -1
    foreach ($a in @($cfg.accounts)) {
        foreach ($raw in @($a.paths)) {
            if (-not $raw) { continue }
            $root = (Expand-PathVars ([string]$raw)).ToLowerInvariant() + '\'
            if ($dirN.StartsWith($root) -and $root.Length -gt $bestLen) { $best = $a.id; $bestLen = $root.Length }
        }
    }
    if ($best) { return $best }
    if (-not $cfg.defaultCodeProfile -or $cfg.defaultCodeProfile -eq 'ask') { return $null }
    return [string]$cfg.defaultCodeProfile
}

# ---------------- colours ----------------
function ConvertFrom-HexColor([string]$Hex) {
    $h = ([string]$Hex).TrimStart('#')
    if ($h -notmatch '^[0-9A-Fa-f]{6}$') { $h = '888888' }
    return @([Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16))
}

function Test-DarkColor([string]$Hex) {
    $rgb = ConvertFrom-HexColor $Hex
    return ((0.299 * $rgb[0] + 0.587 * $rgb[1] + 0.114 * $rgb[2]) -lt 150)
}

function Get-NearestConsoleColor([string]$Hex) {
    $rgb = ConvertFrom-HexColor $Hex
    $palette = [ordered]@{
        DarkBlue = @(0, 55, 218); DarkGreen = @(19, 161, 14); DarkCyan = @(58, 150, 221); DarkRed = @(197, 15, 31)
        DarkMagenta = @(136, 23, 152); DarkYellow = @(193, 156, 0); Gray = @(204, 204, 204); DarkGray = @(118, 118, 118)
        Blue = @(59, 120, 255); Green = @(22, 198, 12); Cyan = @(97, 214, 214); Red = @(231, 72, 86)
        Magenta = @(180, 0, 158); Yellow = @(249, 241, 165); White = @(242, 242, 242)
    }
    $best = 'Gray'; $bestD = [double]::MaxValue
    foreach ($k in $palette.Keys) {
        $c = $palette[$k]
        $d = [math]::Pow($rgb[0] - $c[0], 2) + [math]::Pow($rgb[1] - $c[1], 2) + [math]::Pow($rgb[2] - $c[2], 2)
        if ($d -lt $bestD) { $bestD = $d; $best = $k }
    }
    return [System.ConsoleColor]$best
}

# ---------------- Claude installs ----------------
function Get-ClaudeAppxPackage {
    return Get-AppxPackage -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*Claude*' -and $_.Publisher -like '*Anthropic*' } |
        Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
}

# Claude.exe for the Microsoft Store install or the classic installer; re-resolved every launch so updates don't break shortcuts
function Resolve-ClaudeExe {
    $pkg = Get-ClaudeAppxPackage
    if ($pkg) {
        $direct = Join-Path $pkg.InstallLocation 'app\Claude.exe'
        if (Test-Path $direct) { return $direct }
        $found = Get-ChildItem $pkg.InstallLocation -Filter 'Claude.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    $squirrel = Join-Path $env:LOCALAPPDATA 'AnthropicClaude'
    if (Test-Path $squirrel) {
        $app = Get-ChildItem $squirrel -Directory -Filter 'app-*' |
            Sort-Object { [version]($_.Name -replace '^app-', '' -replace '[^0-9.].*$', '') } -Descending | Select-Object -First 1
        if ($app) {
            $exe = Get-ChildItem $app.FullName -Filter 'claude.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($exe) { return $exe.FullName }
        }
    }
    throw 'Claude Desktop is not installed.'
}

# The real Claude Code CLI (never one of this tool's own commands)
function Find-ClaudeCli {
    $bin = Get-SeveranceBin
    $cmd = Get-Command claude -CommandType Application -All -ErrorAction SilentlyContinue |
        Where-Object { (Split-Path $_.Source) -ne $bin } |
        Sort-Object { if ($_.Source -like '*.exe') { 0 } else { 1 } } | Select-Object -First 1
    if ($cmd) { return [pscustomobject]@{ Source = $cmd.Source } }
    $native = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
    if (Test-Path $native) { return [pscustomobject]@{ Source = $native } }
    return $null
}

# ---------------- Claude Desktop ----------------
function Get-ClaudeDesktopProcesses {
    return @(Get-CimInstance Win32_Process -Filter "Name = 'Claude.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -like '*\WindowsApps\*' -or $_.ExecutablePath -like '*\AnthropicClaude\*') })
}

# Closes Claude Desktop windows of one extra account ($Id) or of all extra accounts ($Id empty)
function Stop-SeveranceDesktop([string]$Id) {
    $base = [regex]::Escape((Join-Path (Get-SeveranceRoot) 'desktop'))
    $pattern = $base
    if ($Id) { $pattern = $base + '\\' + [regex]::Escape($Id) + '(?=["\s\\]|$)' }
    $procs = @(Get-ClaudeDesktopProcesses | Where-Object { $_.CommandLine -match $pattern })
    foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($procs.Count -gt 0) { Start-Sleep -Seconds 2 }
}

function Start-SeveranceDesktop([string]$Id) {
    $a = Get-SeveranceAccount $Id
    if ($a.main) {
        # Start exactly like the Start menu does: normal data, app identity, Cowork VM
        $pkg = Get-ClaudeAppxPackage
        if ($pkg) {
            $appId = @((Get-AppxPackageManifest -Package $pkg.PackageFullName).Package.Applications.Application)[0].Id
            Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$($pkg.PackageFamilyName)!$appId"
        } else {
            Start-Process (Resolve-ClaudeExe)
        }
        return
    }
    $exe = Resolve-ClaudeExe
    $dataDir = Get-ClaudeDesktopDir $Id
    $codeDir = Get-ClaudeCodeEnv $Id
    New-Item -ItemType Directory -Force -Path $dataDir, $codeDir | Out-Null
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = Split-Path $exe
    # The Code tab of this window keeps its sessions and settings in this account
    $psi.EnvironmentVariables['CLAUDE_CONFIG_DIR'] = $codeDir
    $psi.EnvironmentVariables.Remove('ANTHROPIC_API_KEY')
    $psi.Arguments = "--user-data-dir=`"$dataDir`""
    [System.Diagnostics.Process]::Start($psi) | Out-Null
}

# ---------------- Claude Code ----------------
function Show-AccountBanner([string]$Id) {
    $a = Get-SeveranceAccount $Id
    $info = Get-ClaudeAccountInfo $Id
    $label = Get-AccountLabel $a
    $fg = 'Black'; if (Test-DarkColor $a.color) { $fg = 'White' }
    Write-Host " $label " -BackgroundColor (Get-NearestConsoleColor $a.color) -ForegroundColor $fg -NoNewline
    $who = $info.Email; if (-not $who) { $who = 'not signed in yet - type /login' }
    if ($info.Org) { $who = "$who  ($($info.Org))" }
    Write-Host "  $($a.name)  |  $who"
    if ($a.email -and $info.Email -and ($a.email -ne $info.Email)) {
        Write-Host " WRONG ACCOUNT: this is meant to be $($a.email). Type /logout then /login. " -BackgroundColor DarkRed -ForegroundColor White
    }
    try { $Host.UI.RawUI.WindowTitle = "Claude [$label] $($a.name)" } catch { }
}

function Invoke-SeveranceClaude([string]$Id, [string[]]$ClaudeArgs) {
    $null = Get-SeveranceAccount $Id
    $codeEnv = Get-ClaudeCodeEnv $Id
    if ($codeEnv) { New-Item -ItemType Directory -Force -Path $codeEnv | Out-Null }
    $cli = Find-ClaudeCli
    if (-not $cli) { throw 'Claude Code is not installed. Run "severance setup" to install it.' }
    $prevDir = $env:CLAUDE_CONFIG_DIR
    $prevKey = $env:ANTHROPIC_API_KEY
    try {
        if ($codeEnv) { $env:CLAUDE_CONFIG_DIR = $codeEnv } else { Remove-Item Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
        # A key in the environment would bill the API instead of this account's subscription
        Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
        & $cli.Source @ClaudeArgs
    } finally {
        if ($null -ne $prevDir) { $env:CLAUDE_CONFIG_DIR = $prevDir } else { Remove-Item Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
        if ($null -ne $prevKey) { $env:ANTHROPIC_API_KEY = $prevKey }
    }
}

function Get-SeveranceStatus {
    foreach ($a in @((Get-SeveranceConfig).accounts)) {
        $info = Get-ClaudeAccountInfo $a.id
        $check = ''
        if ($a.email -and $info.Email) { if ($a.email -eq $info.Email) { $check = 'ok' } else { $check = 'WRONG ACCOUNT' } }
        $type = 'extra'; if ($a.main) { $type = 'main' }
        [pscustomobject]@{
            Account   = $a.name
            Type      = $type
            Command   = (Get-AccountAlias $a)
            SignedIn  = $info.Email
            Org       = $info.Org
            Check     = $check
        }
    }
}

# ---------------- install helpers ----------------
# Edits the user PATH in the registry without expanding %VARS% or changing the value type
function Set-UserPathEntry([string]$Dir, [bool]$Add) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $current = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $want = $Dir.TrimEnd('\')
        $parts = @($current.Split(';') | Where-Object { $_ -and ([Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ne $want) })
        if ($Add) { $parts += $want }
        $key.SetValue('Path', ($parts -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally { $key.Close() }
}

# Tells Windows the environment changed so new terminals see the new PATH
function Send-EnvironmentChange([bool]$Installed) {
    $value = $null; if ($Installed) { $value = Get-SeveranceRoot }
    [Environment]::SetEnvironmentVariable('CLAUDE_SEVERANCE_HOME', $value, 'User')
}

function Get-PowerShellProfilePaths {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    return @((Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'), (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'))
}

function Remove-ShellHook([string]$Start = $script:HookStart, [string]$End = $script:HookEnd) {
    foreach ($file in Get-PowerShellProfilePaths) {
        if (-not (Test-Path $file)) { continue }
        $text = [IO.File]::ReadAllText($file)
        $pattern = '(?s)\r?\n?' + [regex]::Escape($Start) + '.*?' + [regex]::Escape($End) + '\r?\n?'
        $new = [regex]::Replace($text, $pattern, "`r`n")
        if ($new -ne $text) { Set-Content -Path $file -Value $new.TrimEnd() -Encoding UTF8 }
    }
}

function Add-ShellHook {
    $target = (Join-Path (Get-SeveranceBin) 'claude-account.ps1') -replace "'", "''"
    $hook = $script:HookStart + "`r`n" +
        "if (Test-Path '$target') { function claude { & '$target' auto @args } }" + "`r`n" + $script:HookEnd
    Remove-ShellHook
    foreach ($file in Get-PowerShellProfilePaths) {
        New-Item -ItemType Directory -Force -Path (Split-Path $file) | Out-Null
        Add-Content -Path $file -Value "`r`n$hook" -Encoding UTF8
    }
}

# Execution policy that applies to profile scripts (ignores this process's own Bypass)
function Get-ProfileExecutionPolicy {
    $list = Get-ExecutionPolicy -List
    foreach ($scope in 'MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine') {
        $v = [string](($list | Where-Object { [string]$_.Scope -eq $scope }).ExecutionPolicy)
        if ($v -and $v -ne 'Undefined') { return [pscustomobject]@{ Policy = $v; Scope = $scope } }
    }
    return [pscustomobject]@{ Policy = 'Restricted'; Scope = 'Default' }
}

function New-SeveranceShortcut([string]$Path, [string]$Arguments, [string]$Icon, [string]$Description, [int]$WindowStyle = 7) {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($Path)
    $lnk.TargetPath = Get-WindowsPowerShell
    $lnk.Arguments = $Arguments
    $lnk.WorkingDirectory = Get-SeveranceBin
    $lnk.WindowStyle = $WindowStyle
    if ($Icon -and (Test-Path $Icon)) { $lnk.IconLocation = "$Icon,0" }
    $lnk.Description = $Description
    $lnk.Save()
}

# Removes desktop shortcuts created by this tool (or by the older ClaudeProfiles tool)
function Remove-SeveranceShortcuts([string]$Marker = 'ClaudeSeverance') {
    $shell = New-Object -ComObject WScript.Shell
    $desk = [Environment]::GetFolderPath('Desktop')
    foreach ($f in @(Get-ChildItem $desk -Filter *.lnk -ErrorAction SilentlyContinue)) {
        try { if ($shell.CreateShortcut($f.FullName).Arguments -like "*$Marker*") { Remove-Item $f.FullName -Force } } catch { }
    }
}

# ---------------- account logos ----------------
# A chosen logo is copied to logos\<id>.png (256 px, fitted on a transparent square), so the original can move or go.
$script:LogoTypes = @('.png', '.jpg', '.jpeg', '.bmp', '.gif', '.ico')
function Get-SeveranceLogoTypes { return $script:LogoTypes }
function Get-SeveranceLogoDir { return (Join-Path (Get-SeveranceRoot) 'logos') }
function Get-SeveranceLogoPath($Account) {
    $name = [string](Get-JsonProp $Account 'logo')
    if (-not $name) { return $null }
    $p = Join-Path (Get-SeveranceLogoDir) ([IO.Path]::GetFileName($name))
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}

# Loads an image without keeping the file open
function Read-SeveranceImage([string]$File) {
    Add-Type -AssemblyName System.Drawing
    $bytes = [IO.File]::ReadAllBytes($File)
    if ([IO.Path]::GetExtension($File) -ieq '.ico') {
        # System.Drawing can't read PNG-compressed icon frames; WPF can. Take the largest frame, re-encoded as PNG.
        Add-Type -AssemblyName PresentationCore, WindowsBase
        $in = New-Object System.IO.MemoryStream (, $bytes)
        $dec = [System.Windows.Media.Imaging.BitmapDecoder]::Create($in, 'PreservePixelFormat', 'OnLoad')
        $frame = @($dec.Frames | Sort-Object { $_.PixelWidth } -Descending)[0]
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($frame))
        $out = New-Object System.IO.MemoryStream
        $enc.Save($out); $in.Dispose()
        $bytes = $out.ToArray(); $out.Dispose()
    }
    $ms = New-Object System.IO.MemoryStream (, $bytes)
    try {
        $img = [System.Drawing.Image]::FromStream($ms)
        try { return (New-Object System.Drawing.Bitmap $img) } finally { $img.Dispose() }
    } finally { $ms.Dispose() }
}

function Add-ContainedImage($Graphics, $Image, [int]$Size) {
    $scale = [math]::Min($Size / $Image.Width, $Size / $Image.Height)
    $w = $Image.Width * $scale; $h = $Image.Height * $scale
    $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $Graphics.DrawImage($Image, [single](($Size - $w) / 2), [single](($Size - $h) / 2), [single]$w, [single]$h)
}

# Copies a logo in for an account and returns the file name to store in accounts.json
function Import-SeveranceLogo([string]$Source, [string]$Id) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "the file $Source isn't there any more" }
    $ext = [IO.Path]::GetExtension($Source).ToLowerInvariant()
    if ($script:LogoTypes -notcontains $ext) { throw "use a $($script:LogoTypes -join ', ') file" }
    if ((Get-Item -LiteralPath $Source).Length -gt 20MB) { throw 'the file is over 20 MB' }
    $img = Read-SeveranceImage $Source
    $size = 256
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.Clear([System.Drawing.Color]::Transparent); Add-ContainedImage $g $img $size }
    finally { $g.Dispose(); $img.Dispose() }
    $dir = Get-SeveranceLogoDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $name = "$Id.png"
    try { $bmp.Save((Join-Path $dir $name), [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
    return $name
}

# 256px icon saved as a PNG-compressed .ico: the account's logo if it has one, else a coloured shell with its letter
function New-SeveranceIcon([string]$Path, [string]$Hex, [string]$Label, [string]$Logo = '') {
    Add-Type -AssemblyName System.Drawing
    $size = 256
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::Transparent)
    $drawn = $false
    if ($Logo -and (Test-Path -LiteralPath $Logo)) {
        try { $img = Read-SeveranceImage $Logo; Add-ContainedImage $g $img $size; $img.Dispose(); $drawn = $true } catch { $g.Clear([System.Drawing.Color]::Transparent) }
    }
    if ($drawn) { Save-SeveranceIco $g $bmp $Path; return }
    $rgb = ConvertFrom-HexColor $Hex
    $fill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, $rgb[0], $rgb[1], $rgb[2]))
    $r = 56
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gp.AddArc(0, 0, $r, $r, 180, 90); $gp.AddArc($size - $r - 1, 0, $r, $r, 270, 90)
    $gp.AddArc($size - $r - 1, $size - $r - 1, $r, $r, 0, 90); $gp.AddArc(0, $size - $r - 1, $r, $r, 90, 90)
    $gp.CloseFigure(); $g.FillPath($fill, $gp)
    $textColor = [System.Drawing.Color]::Black; if (Test-DarkColor $Hex) { $textColor = [System.Drawing.Color]::White }
    $fontSize = 150; if ($Label.Length -eq 2) { $fontSize = 112 } elseif ($Label.Length -ge 3) { $fontSize = 82 }
    $font = New-Object System.Drawing.Font 'Segoe UI', $fontSize, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString($Label, $font, (New-Object System.Drawing.SolidBrush $textColor), (New-Object System.Drawing.RectangleF 0, 6, $size, $size), $fmt)
    Save-SeveranceIco $g $bmp $Path
}

function Save-SeveranceIco($Graphics, $Bitmap, [string]$Path) {
    $Graphics.Dispose()
    $bmp = $Bitmap
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    $png = $ms.ToArray()
    $fs = [System.IO.File]::Create($Path)
    $w = New-Object System.IO.BinaryWriter $fs
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]1)
    $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$png.Length); $w.Write([uint32]22)
    $w.Write($png); $w.Close()
}

# ---------------- Claude Code settings ----------------
function Get-StatusLineCommand {
    $p = (Join-Path (Get-SeveranceBin) 'statusline.ps1') -replace '\\', '/'
    return "powershell -NoProfile -ExecutionPolicy Bypass -File `"$p`""
}

function Test-OurStatusLine($StatusLine) {
    $c = [string](Get-JsonProp $StatusLine 'command')
    return ($c -like '*statusline.ps1*' -and ($c -like '*ClaudeSeverance*' -or $c -like '*ClaudeProfiles*'))
}

# Adds the account badge to a settings.json; keeps every other setting and never replaces your own status line
function Set-SeveranceStatusLine([string]$SettingsPath) {
    $obj = Read-JsonFile $SettingsPath
    if ($null -eq $obj) { $obj = New-Object psobject }
    $existing = Get-JsonProp $obj 'statusLine'
    if ($existing -and -not (Test-OurStatusLine $existing)) {
        Write-Warning "Kept your own status line in $SettingsPath (no account badge there)."
        return
    }
    $bak = "$SettingsPath.bak-severance"
    if ((Test-Path $SettingsPath) -and -not (Test-Path $bak)) { Copy-Item $SettingsPath $bak }
    $sl = [pscustomobject]@{ type = 'command'; command = (Get-StatusLineCommand); padding = 0 }
    if (Set-JsonProp $obj 'statusLine' $sl) { Write-JsonFile $SettingsPath $obj }
}

function Remove-SeveranceStatusLine([string]$SettingsPath) {
    $obj = $null
    try { $obj = Read-JsonFile $SettingsPath } catch { return }
    if ($null -eq $obj) { return }
    $existing = Get-JsonProp $obj 'statusLine'
    if ($existing -and (Test-OurStatusLine $existing)) {
        $null = Set-JsonProp $obj 'statusLine' $null
        Write-JsonFile $SettingsPath $obj
    }
}

# All accounts share one Claude Code program, so they must agree on the update channel.
# Copies the main account's autoUpdatesChannel and minimumVersion to every extra account.
function Sync-SeveranceUpdateSettings {
    $main = Get-MainAccount
    $m = $null
    try { $m = Read-JsonFile (Join-Path (Get-ClaudeCodeDir $main.id) 'settings.json') } catch { return }
    $channel = $null; $minv = $null
    if ($m) { $channel = Get-JsonProp $m 'autoUpdatesChannel'; $minv = Get-JsonProp $m 'minimumVersion' }
    foreach ($a in @((Get-SeveranceConfig).accounts | Where-Object { -not $_.main })) {
        $path = Join-Path (Get-ClaudeCodeDir $a.id) 'settings.json'
        try {
            $o = Read-JsonFile $path
            if ($null -eq $o) { $o = New-Object psobject }
            $c1 = Set-JsonProp $o 'autoUpdatesChannel' $channel
            $c2 = Set-JsonProp $o 'minimumVersion' $minv
            if ($c1 -or $c2) { Write-JsonFile $path $o }
        } catch { Write-Warning "Couldn't sync update settings into $path : $($_.Exception.Message)" }
    }
}

# ---------------- account data ----------------
# Zips extra accounts' Claude Code data (never the login token) and Desktop MCP config. Returns the zip path or $null.
function Backup-SeveranceAccounts([string[]]$Ids) {
    $root = Get-SeveranceRoot
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $stage = Join-Path $env:TEMP "claude-severance-$stamp"
    foreach ($id in $Ids) {
        $code = Join-Path $root "code\$id"
        if (Test-Path $code) {
            $null = & robocopy.exe $code (Join-Path $stage "$id\claude-code") /E /XF .credentials.json /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
            if ($LASTEXITCODE -ge 8) { throw "Backup of '$id' failed (robocopy exit code $LASTEXITCODE)." }
        }
        $mcp = Join-Path $root "desktop\$id\claude_desktop_config.json"
        if (Test-Path $mcp) {
            $d = Join-Path $stage "$id\claude-desktop"
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            Copy-Item $mcp $d
        }
    }
    if (-not (Test-Path $stage) -or -not (Get-ChildItem $stage -Recurse -File -Force)) {
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        return $null
    }
    $dest = Get-SeveranceBackupDir
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = Join-Path $dest "backup $stamp.zip"
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    return $zip
}

function Remove-SeveranceAccountData([string]$Id) {
    Stop-SeveranceDesktop $Id
    $root = Get-SeveranceRoot
    foreach ($p in @((Join-Path $root "code\$Id"), (Join-Path $root "desktop\$Id"), (Join-Path $root "logos\$Id.png"))) {
        if (Test-Path $p) {
            try { Remove-Item $p -Recurse -Force }
            catch { Write-Warning "Couldn't fully delete $p (a Claude window or terminal may still use it). Delete it later." }
        }
    }
}

# ---------------- Apps & Features entry ----------------
function Register-SeveranceUninstall([string]$Icon) {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClaudeSeverance'
    if (-not (Test-Path $k)) { New-Item -Path $k | Out-Null }
    $ps = Get-WindowsPowerShell
    $bin = Get-SeveranceBin
    Set-ItemProperty $k 'DisplayName' 'Claude Severance'
    Set-ItemProperty $k 'DisplayVersion' $script:Version
    Set-ItemProperty $k 'Publisher' 'Claude Severance'
    Set-ItemProperty $k 'InstallLocation' (Get-SeveranceRoot)
    Set-ItemProperty $k 'DisplayIcon' $Icon
    Set-ItemProperty $k 'UninstallString' "`"$ps`" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$bin\Setup.ps1`" -Mode uninstall"
    Set-ItemProperty $k 'QuietUninstallString' "`"$ps`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$bin\Setup.ps1`" -Mode uninstall -Silent"
    Set-ItemProperty $k 'ModifyPath' "`"$ps`" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$bin\Setup.ps1`" -Mode manage"
    Set-ItemProperty $k 'URLInfoAbout' 'https://claude.ai/download'
    New-ItemProperty $k 'NoRepair' -Value 1 -PropertyType DWord -Force | Out-Null
    try {
        $kb = [int](((Get-ChildItem $bin -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1KB)
        New-ItemProperty $k 'EstimatedSize' -Value $kb -PropertyType DWord -Force | Out-Null
    } catch { }
}

function Unregister-SeveranceUninstall {
    Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClaudeSeverance' -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-SeveranceInstalledVersion {
    try { return [string](Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClaudeSeverance' -ErrorAction Stop).DisplayVersion }
    catch { return $null }
}

# ---------------- account helpers shared by the setup window and the text setup ----------------
function New-AccountId([string]$Name, [string[]]$Existing) {
    $base = ([string]$Name).ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $base = $base.Trim('-')
    if (-not $base -or $base -eq 'auto') { $base = 'account' }
    $id = $base; $n = 2
    while ($Existing -contains $id) { $id = "$base$n"; $n++ }
    return $id
}

# The letter on an account's shell: the first letter or digit of its name
function New-AccountLabel([string]$Name) {
    $m = [regex]::Match([string]$Name, '[A-Za-z0-9]')
    if (-not $m.Success) { return '?' }
    return $m.Value.ToUpperInvariant()
}

function New-SeveranceAccount([string]$Name, [string]$Email, [string[]]$Paths, [bool]$Main, [string[]]$ExistingIds, [int]$Index) {
    return [pscustomobject]@{
        id    = (New-AccountId $Name $ExistingIds)
        name  = $Name
        label = (New-AccountLabel $Name)
        color = $script:Palette[$Index % $script:Palette.Count]
        email = ([string]$Email).Trim()
        main  = $Main
        paths = @($Paths | Where-Object { $_ })
    }
}

function Test-ShellHook {
    foreach ($file in Get-PowerShellProfilePaths) {
        if ((Test-Path $file) -and ([IO.File]::ReadAllText($file)).Contains($script:HookStart)) { return $true }
    }
    return $false
}

function Test-SeveranceDesktopShortcuts {
    $shell = New-Object -ComObject WScript.Shell
    foreach ($f in @(Get-ChildItem ([Environment]::GetFolderPath('Desktop')) -Filter *.lnk -ErrorAction SilentlyContinue)) {
        try { if ($shell.CreateShortcut($f.FullName).Arguments -like '*ClaudeSeverance*') { return $true } } catch { }
    }
    return $false
}

# ---------------- the earlier ClaudeProfiles toolkit ----------------
function Read-LegacyProfiles {
    $cfgPath = Join-Path $env:USERPROFILE 'ClaudeProfiles\bin\profiles.json'
    if (-not (Test-Path $cfgPath)) { return $null }
    try { $legacy = Get-Content $cfgPath -Raw | ConvertFrom-Json } catch { return $null }
    $profiles = @($legacy.profiles)
    $hasMain = @($profiles | Where-Object { $_.desktopData -eq 'default' }).Count -gt 0
    $list = @(); $i = 0
    foreach ($p in $profiles) {
        $isMain = ($p.desktopData -eq 'default') -or (-not $hasMain -and $i -eq 0)
        $name = ([string]$p.name) -replace '^Claude\s*-\s*', ''
        $color = [string]$p.color; if (-not $color) { $color = $script:Palette[$i % $script:Palette.Count] }
        $label = [string]$p.label; if (-not $label) { $label = New-AccountLabel $name }
        $list += [pscustomobject]@{
            id = [string]$p.id; name = $name; label = $label; color = $color; email = [string]$p.email
            main = [bool]$isMain; paths = @($p.paths | Where-Object { $_ }); legacyDesktop = [string]$p.desktopData
        }
        $i++
    }
    return [pscustomobject]@{ Root = (Expand-PathVars ([string]$legacy.profilesRoot)); Accounts = $list }
}

function Move-LegacyProfiles($Legacy) {
    $root = Get-SeveranceRoot
    $pat = [regex]::Escape((Join-Path $Legacy.Root 'desktop'))
    Get-ClaudeDesktopProcesses | Where-Object { $_.CommandLine -match $pat } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 800
    foreach ($a in @($Legacy.Accounts)) {
        if ($a.main) { continue }
        $pairs = @(
            @((Join-Path $Legacy.Root "desktop\$($a.legacyDesktop)"), (Join-Path $root "desktop\$($a.id)")),
            @((Join-Path $Legacy.Root "code\$($a.id)"), (Join-Path $root "code\$($a.id)"))
        )
        foreach ($pair in $pairs) {
            if ((Test-Path $pair[0]) -and -not (Test-Path $pair[1])) {
                New-Item -ItemType Directory -Force -Path (Split-Path $pair[1]) | Out-Null
                Move-Item $pair[0] $pair[1]
            }
        }
    }
    Remove-SeveranceShortcuts 'ClaudeProfiles'
    Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'Claude Profiles') -Recurse -Force -ErrorAction SilentlyContinue
    Set-UserPathEntry (Join-Path $Legacy.Root 'bin') $false
    [Environment]::SetEnvironmentVariable('CLAUDE_PROFILES_ROOT', $null, 'User')
    Remove-ShellHook '# >>> claude-profiles >>>' '# <<< claude-profiles <<<'
    Remove-Item (Join-Path $Legacy.Root 'bin') -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($d in @((Join-Path $Legacy.Root 'desktop'), (Join-Path $Legacy.Root 'code'), $Legacy.Root)) {
        if ((Test-Path $d) -and -not (Get-ChildItem $d -Force)) { Remove-Item $d -Force -ErrorAction SilentlyContinue }
    }
}

# ---------------- what setup finds before it starts ----------------
function Get-SeveranceSetupInfo([string]$Mode = 'auto') {
    $installed = Get-SeveranceInstalledVersion
    if ($Mode -eq 'auto' -or -not $Mode) {
        if (-not $installed) { $Mode = 'install' }
        else {
            $older = $false
            try { $older = ([version]$installed -lt [version]$script:Version) } catch { $older = $true }
            if ($older) { $Mode = 'update' } else { $Mode = 'manage' }
        }
    }
    $desktopFound = $true
    try { $null = Resolve-ClaudeExe } catch { $desktopFound = $false }
    $winget = [bool](Get-Command winget.exe -ErrorAction SilentlyContinue)
    $codeFound = [bool](Find-ClaudeCli)

    $accounts = @(); $source = 'new'
    if (Test-Path (Get-SeveranceConfigPath)) {
        try { $accounts = @((Get-SeveranceConfig).accounts); $source = 'kept' } catch { $accounts = @() }
    }
    if ($accounts.Count -eq 0) {
        $legacy = Read-LegacyProfiles
        if ($legacy) { $accounts = @($legacy.Accounts); $source = 'legacy' }
    }
    if ($accounts.Count -eq 0) {
        $email = ''
        try {
            $acct = Read-OAuthAccount (Join-Path $env:USERPROFILE '.claude.json')
            if ($acct -and $acct['emailAddress']) { $email = [string]$acct['emailAddress'] }
        } catch { }
        $accounts = @(New-SeveranceAccount 'Personal' $email @() $true @() 0)
    }
    if ($installed) { $source = 'installed' }

    $ep = Get-ProfileExecutionPolicy
    $blocked = $ep.Policy -in 'Restricted', 'AllSigned'
    $orgBlocked = $blocked -and ($ep.Scope -in 'MachinePolicy', 'UserPolicy')
    $autoSwitch = -not $orgBlocked
    if ($installed) { $autoSwitch = $autoSwitch -and (Test-ShellHook) }
    $shortcuts = $true
    if ($installed) { $shortcuts = Test-SeveranceDesktopShortcuts }

    return [pscustomobject]@{
        Version          = $script:Version
        Installed        = $installed
        Mode             = $Mode
        Dir              = (Get-SeveranceRoot)
        DesktopFound     = $desktopFound
        Winget           = $winget
        CodeFound        = $codeFound
        Accounts         = $accounts
        Source           = $source
        NeedsScripts     = ($blocked -and -not $orgBlocked)
        ScriptsBlocked   = $orgBlocked
        AutoSwitch       = $autoSwitch
        DesktopShortcuts = $shortcuts
        Running          = (@(Get-ClaudeDesktopProcesses | Where-Object { $_.CommandLine -match [regex]::Escape((Join-Path (Get-SeveranceRoot) 'desktop')) }).Count -gt 0)
    }
}

# ---------------- install, update and account changes ----------------
# $Step is called with one short line per finished step, for the setup window's checklist.
function Invoke-SeveranceInstall {
    param(
        [Parameter(Mandatory)] $Accounts,
        [string[]] $RemovedIds = @(),
        [bool] $DesktopShortcuts = $true,
        [bool] $AutoSwitch = $true,
        [bool] $AllowScripts = $false,
        [bool] $InstallDesktopApp = $false,
        [bool] $InstallCode = $false,
        [string] $SourceDir = $PSScriptRoot,
        [scriptblock] $Step = { param($t) }
    )
    $notes = New-Object System.Collections.Generic.List[string]
    $root = Get-SeveranceRoot
    $bin = Get-SeveranceBin

    if ($env:OS -ne 'Windows_NT') { throw 'Claude Severance runs on Windows only.' }

    if ($InstallDesktopApp) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if (-not $winget) { throw 'Claude Desktop is not installed, and winget is not available to install it. Get it from claude.ai/download, then run setup again.' }
        $p = Start-Process $winget.Source -ArgumentList 'install', '--id', 'Anthropic.Claude', '-e', '--silent', '--accept-source-agreements', '--accept-package-agreements' -Wait -PassThru -WindowStyle Hidden
        try { $null = Resolve-ClaudeExe } catch { throw "Claude Desktop didn't install (winget exit code $($p.ExitCode)). Get it from claude.ai/download, then run setup again." }
        & $Step 'Installed Claude Desktop'
    } else {
        try { $null = Resolve-ClaudeExe } catch { throw 'Claude Desktop is not installed. Get it from claude.ai/download, then run setup again.' }
    }

    if ($InstallCode) {
        $p = Start-Process (Get-WindowsPowerShell) -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', 'irm https://claude.ai/install.ps1 | iex' -Wait -PassThru -WindowStyle Hidden
        Update-SessionPath
        if (Find-ClaudeCli) { & $Step 'Installed Claude Code' }
        else { $notes.Add("Claude Code didn't install. Desktop accounts work; install Claude Code later and open Manage accounts.") }
    }

    if (-not (Test-Path (Get-SeveranceConfigPath))) {
        $legacy = Read-LegacyProfiles
        if ($legacy) { Move-LegacyProfiles $legacy; & $Step 'Brought over your earlier ClaudeProfiles setup' }
    }

    $oldCfg = $null
    try { if (Test-Path (Get-SeveranceConfigPath)) { $oldCfg = Get-SeveranceConfig } } catch { }
    $clean = @()
    foreach ($a in @($Accounts)) {
        # logo: a new file to copy in (logoSource), the one already stored (logo), or none
        $id = [string]$a.id
        $logo = [string](Get-JsonProp $a 'logo')
        $logoSource = [string](Get-JsonProp $a 'logoSource')
        if ($logoSource) {
            try { $logo = Import-SeveranceLogo $logoSource $id }
            catch { $notes.Add("Couldn't use the logo for $($a.name) ($($_.Exception.Message)), so it shows its letter."); $logo = '' }
        }
        if ($logo -and -not (Get-SeveranceLogoPath ([pscustomobject]@{ logo = $logo }))) { $logo = '' }
        if (-not $logo) { Remove-Item (Join-Path (Get-SeveranceLogoDir) "$id.png") -Force -ErrorAction SilentlyContinue }
        $clean += [pscustomobject]@{
            id = $id; name = [string]$a.name; label = [string]$a.label; color = [string]$a.color; logo = $logo
            alias = (Get-AccountAlias $a)
            email = [string]$a.email; main = [bool]$a.main; paths = @(@($a.paths) | Where-Object { $_ } | ForEach-Object { [string]$_ })
        }
    }
    # Every command name is checked before anything on the PC changes
    foreach ($c in $clean) {
        $why = Test-SeveranceAlias $c.alias $c.id $clean
        if ($why) { throw "The command for $($c.name) can't be $($c.alias): $why" }
    }
    $cfg = [pscustomobject]@{ version = 1; defaultCodeProfile = 'ask'; accounts = $clean }
    if ($oldCfg -and $oldCfg.defaultCodeProfile) { $cfg.defaultCodeProfile = [string]$oldCfg.defaultCodeProfile }
    Test-SeveranceConfig $cfg

    $RemovedIds = @($RemovedIds | Where-Object { $_ -and ($clean.id -notcontains $_) })
    if ($RemovedIds.Count -gt 0) {
        $zip = Backup-SeveranceAccounts $RemovedIds
        foreach ($id in $RemovedIds) { Remove-SeveranceAccountData $id }
        $names = @($RemovedIds | ForEach-Object {
            $rid = $_; $o = @($oldCfg.accounts | Where-Object { $_.id -eq $rid }); if ($o.Count) { $o[0].name } else { $rid } })
        & $Step "Backed up and removed $($names -join ', ')"
        if ($zip) { $notes.Add("Backup of removed accounts: $zip") }
    }
    Save-SeveranceConfig $cfg

    # ---- files ----
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    $src = [IO.Path]::GetFullPath($SourceDir).TrimEnd('\')
    if ($src -ne $bin.TrimEnd('\')) {
        foreach ($f in 'Severance.psm1', 'Setup.ps1', 'SetupWindow.ps1', 'Setup-Console.ps1', 'Uninstall.ps1', 'Launch-Desktop.ps1', 'claude-account.ps1', 'statusline.ps1', 'severance.ps1') {
            $from = Join-Path $src $f
            if (Test-Path $from) { Copy-Item $from (Join-Path $bin $f) -Force }
        }
        foreach ($dirName in 'fonts', 'assets') {
            $dir = Join-Path $src $dirName
            if (-not (Test-Path $dir)) { continue }
            New-Item -ItemType Directory -Force -Path (Join-Path $bin $dirName) | Out-Null
            foreach ($ff in @(Get-ChildItem $dir -File)) {
                $to = Join-Path $bin "$dirName\$($ff.Name)"
                # a font or icon in use by an open window can't be replaced; the copy already there is the same file
                try { Copy-Item $ff.FullName $to -Force } catch { if (-not (Test-Path $to)) { throw } }
            }
        }
    }
    Get-ChildItem $bin -File -Recurse | Unblock-File -ErrorAction SilentlyContinue
    & $Step 'Copied Claude Severance to your PC'

    # ---- clean what an earlier run made ----
    Remove-SeveranceShortcuts
    $startMenu = Get-SeveranceStartMenu
    Remove-Item $startMenu -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
    Get-SeveranceShims | Remove-Item -Force
    Get-ChildItem $bin -Filter 'icon-*.ico' | Where-Object { $_.Name -ne 'icon-severance.ico' } | Remove-Item -Force -ErrorAction SilentlyContinue

    # ---- accounts ----
    $desktop = [Environment]::GetFolderPath('Desktop')
    $mainCode = Get-ClaudeCodeDir (Get-MainAccount).id
    $shared = 'CLAUDE.md', 'settings.json', 'commands', 'agents', 'skills', 'hooks', 'output-styles'
    foreach ($a in @($cfg.accounts)) {
        $codeDir = Get-ClaudeCodeDir $a.id
        $isNew = -not (Test-Path $codeDir)
        New-Item -ItemType Directory -Force -Path $codeDir | Out-Null
        $deskDir = Get-ClaudeDesktopDir $a.id
        if ($deskDir) { New-Item -ItemType Directory -Force -Path $deskDir | Out-Null }
        if ($isNew -and -not $a.main -and (Test-Path $mainCode)) {
            foreach ($item in $shared) {
                $from = Join-Path $mainCode $item
                if (Test-Path $from) { Copy-Item $from (Join-Path $codeDir $item) -Recurse -Force }
            }
        }
        try { Set-SeveranceStatusLine (Join-Path $codeDir 'settings.json') }
        catch { $notes.Add("No account badge for $($a.name): its settings.json couldn't be read.") }

        $icon = Join-Path $bin "icon-$($a.id).ico"
        try { New-SeveranceIcon $icon $a.color (Get-AccountLabel $a) (Get-SeveranceLogoPath $a) } catch { $icon = $null }
        $sc = Get-AccountShortcutName $a
        $lnkArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$bin\Launch-Desktop.ps1`" -AccountId $($a.id)"
        if ($DesktopShortcuts) { New-SeveranceShortcut (Join-Path $desktop "$sc.lnk") $lnkArgs $icon "Claude Desktop - $($a.name)" 7 }
        New-SeveranceShortcut (Join-Path $startMenu "$sc.lnk") $lnkArgs $icon "Claude Desktop - $($a.name)" 7
        $shim = "@echo off`r`npowershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"%~dp0claude-account.ps1`" $($a.id) %*`r`n"
        [IO.File]::WriteAllText((Join-Path $bin "$(Get-AccountAlias $a).cmd"), $shim, [Text.Encoding]::ASCII)
        & $Step "Set up $($a.name)"
    }

    # ---- Start menu, commands, Settings > Apps ----
    $appIcon = Join-Path $bin 'assets\severance.ico'
    if (-not (Test-Path $appIcon)) {
        $appIcon = Join-Path $bin 'icon-severance.ico'
        if (-not (Test-Path $appIcon)) { try { New-SeveranceIcon $appIcon '#221F19' 'CS' } catch { $appIcon = $null } }
    }
    $ps = Get-WindowsPowerShell
    New-SeveranceShortcut (Join-Path $startMenu 'Claude Severance - Manage accounts.lnk') "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$bin\Setup.ps1`" -Mode manage" $appIcon 'Add, rename or remove Claude accounts' 7
    New-SeveranceShortcut (Join-Path $startMenu 'Uninstall Claude Severance.lnk') "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$bin\Setup.ps1`" -Mode uninstall" $appIcon 'Go back to a single Claude' 7
    if ($DesktopShortcuts) { & $Step 'Added Start menu entries and desktop shortcuts' } else { & $Step 'Added Start menu entries' }

    $sev = "@powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"%~dp0severance.ps1`" %* & exit /b`r`n"
    [IO.File]::WriteAllText((Join-Path $bin 'severance.cmd'), $sev, [Text.Encoding]::ASCII)
    Set-UserPathEntry $bin $true
    Send-EnvironmentChange $true
    & $Step "Added each account's command, and severance"

    Sync-SeveranceUpdateSettings
    & $Step 'Matched Claude Code update settings across accounts'

    $autoOn = $false
    if ($AutoSwitch) {
        $ep = Get-ProfileExecutionPolicy
        if ($ep.Policy -in 'Restricted', 'AllSigned') {
            if ($AllowScripts -and $ep.Scope -notin 'MachinePolicy', 'UserPolicy') {
                # This process runs with Bypass, so Windows reports the user setting as "overridden": expected
                try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop } catch { }
            }
            $ep = Get-ProfileExecutionPolicy
        }
        if ($ep.Policy -notin 'Restricted', 'AllSigned') { Add-ShellHook; $autoOn = $true; & $Step 'Turned on auto-switch for claude' }
        else { Remove-ShellHook; $notes.Add("Auto-switch is off: PowerShell scripts are blocked on this PC. Use claude-<account>.") }
    } else { Remove-ShellHook }

    if ($appIcon) { Register-SeveranceUninstall $appIcon } else { Register-SeveranceUninstall '' }
    & $Step 'Added Claude Severance to Settings > Apps'

    return [pscustomobject]@{ Accounts = $cfg.accounts; AutoSwitch = $autoOn; Notes = @($notes) }
}

# ---------------- uninstall ----------------
# Removes everything Claude Severance added. Extra accounts' data stays unless $RemoveData,
# so installing again brings them back signed in. With $RemoveData it is zipped first, without logins.
function Invoke-SeveranceUninstall {
    param([bool] $RemoveData = $false, [scriptblock] $Step = { param($t) })
    $root = Get-SeveranceRoot
    $cfg = $null
    try { if (Test-Path (Get-SeveranceConfigPath)) { $cfg = Get-SeveranceConfig } } catch { }
    $extras = @()
    if ($cfg) { $extras = @($cfg.accounts | Where-Object { -not $_.main }) }

    Stop-SeveranceDesktop ''
    & $Step "Closed the extra accounts' windows"

    $zip = $null
    if ($RemoveData -and $extras.Count -gt 0) {
        $zip = Backup-SeveranceAccounts @($extras | ForEach-Object { [string]$_.id })
        & $Step 'Zipped the extra accounts, without their logins'
    }

    $mainSettings = Join-Path $env:USERPROFILE '.claude\settings.json'
    Remove-SeveranceStatusLine $mainSettings
    Remove-Item "$mainSettings.bak-severance" -Force -ErrorAction SilentlyContinue
    & $Step 'Removed the account badge from your main Claude Code'

    Remove-SeveranceShortcuts
    Remove-Item (Get-SeveranceStartMenu) -Recurse -Force -ErrorAction SilentlyContinue
    & $Step 'Removed shortcuts and Start menu entries'

    Remove-ShellHook
    Set-UserPathEntry (Get-SeveranceBin) $false
    Send-EnvironmentChange $false
    & $Step 'Removed the commands and auto-switch'

    Unregister-SeveranceUninstall
    & $Step 'Removed Claude Severance from Settings > Apps'

    $target = Get-SeveranceBin
    if ($RemoveData) { $target = $root }
    $left = $null
    try { if (Test-Path $target) { Remove-Item $target -Recurse -Force } }
    catch {
        $left = $target
        $runOnce = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
        if (-not (Test-Path $runOnce)) { New-Item -Path $runOnce | Out-Null }
        Set-ItemProperty $runOnce 'ClaudeSeveranceCleanup' "cmd.exe /c rmdir /s /q `"$target`""
    }
    if ($RemoveData) { & $Step 'Removed the extra accounts from this PC' } else { & $Step "Removed Claude Severance's files" }

    $mainName = 'Your main account'
    if ($cfg) { $mainName = [string](@($cfg.accounts | Where-Object { $_.main }))[0].name }
    return [pscustomobject]@{
        Backup   = $zip
        Left     = $left
        KeptData = ((-not $RemoveData) -and $extras.Count -gt 0)
        MainName = $mainName
        Extras   = @($extras | ForEach-Object { $_.name })
    }
}

Export-ModuleMember -Function *
