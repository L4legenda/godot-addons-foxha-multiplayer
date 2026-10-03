param([string]$ProjectPath = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
$version = '1.2.2-stable'
$expected = '98E9446921740D995BD9CA1BE48798DC3C2CEED51E044A25CE18B3CFF11F56E5'
$root = (Resolve-Path -LiteralPath $ProjectPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $root 'project.godot'))) { throw 'Not a Godot project.' }
$destination = Join-Path $root 'addons/webrtc_native'
if (Test-Path -LiteralPath $destination) { Write-Output "WebRTC already installed: $destination"; exit 0 }
$archive = Join-Path ([System.IO.Path]::GetTempPath()) ('foxha-webrtc-' + [Guid]::NewGuid().ToString('N') + '.zip')
try {
    Invoke-WebRequest -Uri "https://github.com/godotengine/webrtc-native/releases/download/$version/godot-extension-webrtc_native.zip" -OutFile $archive
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected) { throw 'WebRTC archive checksum mismatch.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach ($entry in $zip.Entries) {
            $target = [System.IO.Path]::GetFullPath((Join-Path $root $entry.FullName))
            if (-not $target.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'Unexpected archive path.'
            }
        }
    } finally { $zip.Dispose() }
    Expand-Archive -LiteralPath $archive -DestinationPath $root
    Write-Output "Installed official webrtc-native $version. Restart/import the Godot project before exporting."
} finally {
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive }
}
