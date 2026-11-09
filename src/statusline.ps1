# Claude Code status line: coloured account badge + signed-in email, model, folder, context use.
# Claude Code pipes session JSON on stdin and shows whatever this prints.
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$raw = [Console]::In.ReadToEnd()
$data = $null
try { $data = $raw | ConvertFrom-Json } catch { }

Import-Module (Join-Path $PSScriptRoot 'Severance.psm1')
$e = [char]27
$reset = "$e[0m"
$sep = " $e[2m|$reset "

$id = $null
try { $id = Find-AccountByConfigDir $env:CLAUDE_CONFIG_DIR } catch { }
if ($id) {
    $a = Get-SeveranceAccount $id
    $info = Get-ClaudeAccountInfo $id
    $rgb = ConvertFrom-HexColor $a.color
    $fg = "$e[38;2;0;0;0m"; if (Test-DarkColor $a.color) { $fg = "$e[38;2;255;255;255m" }
    $line = "$e[48;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m$fg$e[1m $(Get-AccountLabel $a) $reset"
    $who = $info.Email; if (-not $who) { $who = 'not signed in' }
    if ($info.Org) { $who = "$who ($($info.Org))" }
    $line += " $who"
    if ($a.email -and $info.Email -and ($a.email -ne $info.Email)) {
        $line += " $e[41;97;1m WRONG ACCOUNT - expected $($a.email) $reset"
    }
} else {
    $line = "$e[41;97;1m UNMAPPED ACCOUNT $reset CLAUDE_CONFIG_DIR=$env:CLAUDE_CONFIG_DIR"
}

if ($data) {
    if ($data.model.display_name) { $line += "$sep$($data.model.display_name)" }
    $dir = $data.workspace.current_dir; if (-not $dir) { $dir = $data.cwd }
    if ($dir) { $line += "$sep$(Split-Path $dir -Leaf)" }
    if ($null -ne $data.context_window.used_percentage) { $line += $sep + "ctx $([math]::Round([double]$data.context_window.used_percentage))%" }
}
[Console]::Out.Write($line)
