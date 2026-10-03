param([string]$Godot = 'godot')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    New-Item -ItemType Directory -Force builds/windows/licenses, builds/web | Out-Null
    Set-Content -LiteralPath builds/.gdignore -Value ''
    & $Godot --headless --path . --export-release 'Windows Desktop' builds/windows/FoxhaPlayground.exe
    if ($LASTEXITCODE -ne 0) { throw 'Windows export failed' }
    & $Godot --headless --path . --export-release Web builds/web/index.html
    if ($LASTEXITCODE -ne 0) { throw 'Web export failed' }
    & $Godot --headless --path . --script res://scripts/write_licenses.gd
    if ($LASTEXITCODE -ne 0) { throw 'License export failed' }
    Copy-Item -Path addons/webrtc_native/LICENSE.* -Destination builds/windows/licenses
    Compress-Archive -Path builds/windows/* -DestinationPath builds/FoxhaPlayground-Windows.zip -Force
    $webFiles = Get-ChildItem -LiteralPath builds/web -File | Where-Object { $_.Extension -ne '.import' }
    Compress-Archive -LiteralPath $webFiles.FullName -DestinationPath builds/FoxhaPlayground-Web.zip -Force
} finally { Pop-Location }
