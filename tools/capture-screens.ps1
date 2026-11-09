# Renders every setup screen, light and dark, to docs\screenshots (2x PNGs). Uses preview mode: changes nothing.
param([string]$Out = (Join-Path (Split-Path $PSScriptRoot) 'docs\screenshots'))
$setup = Join-Path (Split-Path $PSScriptRoot) 'src\Setup.ps1'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$log = Join-Path $Out 'capture.log'
Set-Content -Path $log -Value ("started {0:s}" -f (Get-Date))
$shots = @(
    @('install', 'welcome', 1700), @('install', 'accounts', 1700), @('install', 'working', 3000), @('install', 'ready', 1700),
    @('install', 'failed', 9500), @('update', 'welcome', 1700), @('manage', 'accounts', 1700),
    @('uninstall', 'confirm', 1700), @('uninstall', 'removing', 2600), @('uninstall', 'removed', 1700)
)
foreach ($theme in 'light', 'dark') {
    foreach ($s in $shots) {
        $file = Join-Path $Out ('{0}-{1}-{2}.png' -f $s[0], $s[1], $theme)
        Remove-Item $file, "$file.error.txt" -ErrorAction SilentlyContinue
        $p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$setup`"", '-Preview',
            '-Mode', $s[0], '-Screen', $s[1], '-Theme', $theme, '-Capture', "`"$file`"", '-CaptureDelay', $s[2]) -PassThru -WindowStyle Hidden
        # A screen that hasn't saved within a minute is stuck: stop it and record it as failed, rather than wait forever
        $exit = 'timeout'
        if ($p.WaitForExit(60000)) { $exit = $p.ExitCode } else { try { $p.Kill() } catch { } }
        Add-Content -Path $log -Value ('{0}  exit={1}  saved={2}' -f (Split-Path $file -Leaf), $exit, (Test-Path $file))
    }
}
Add-Content -Path $log -Value ("DONE {0:s}" -f (Get-Date))
