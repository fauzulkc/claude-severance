# Builds dist\ClaudeSeverance-<version>.zip (what people download) and its .sha256. Prints the zip's path.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$version = ([regex]::Match((Get-Content (Join-Path $root 'src\Severance.psm1') -Raw), "\`$script:Version = '([^']+)'")).Groups[1].Value
if (-not $version) { throw 'Version not found in src\Severance.psm1' }
$dist = Join-Path $root 'dist'
$name = "ClaudeSeverance-$version"
$stage = Join-Path $dist $name
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach ($f in 'Install.cmd', 'Uninstall.cmd', 'Preview.cmd', 'README.md', 'LICENSE', 'CHANGELOG.md') { Copy-Item (Join-Path $root $f) $stage }
Copy-Item (Join-Path $root 'src') $stage -Recurse
$zip = Join-Path $dist "$name.zip"
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path "$zip.sha256" -Value "$hash  $name.zip" -Encoding ASCII
Remove-Item $stage -Recurse -Force
$zip
