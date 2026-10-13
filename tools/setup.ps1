$ErrorActionPreference = 'Stop'
$version = '4.7.2'
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $projectRoot '.tools'
New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
$archive = Join-Path $toolRoot 'godot.zip'
$url = 'https://downloads.godotengine.org/?version={0}&flavor=stable&slug=win64.exe.zip&platform=windows.64' -f $version
Invoke-WebRequest -Uri $url -OutFile $archive
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $toolRoot 'godot') -Force
Set-Content -LiteralPath (Join-Path $toolRoot '.gdignore') -Value ''
Set-Content -LiteralPath (Join-Path $toolRoot 'godot-version.txt') -Value ($version + '-stable')
Write-Host 'Godot is ready. Run Play.cmd or Open-Editor.cmd.'
