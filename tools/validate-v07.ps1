param(
    [ValidateSet('Screenshots', 'Benchmark', 'Regression')]
    [string]$Mode = 'Screenshots',
    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [string]$Tag = 'local'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw 'Run tools/setup.ps1 first.' }
# Keep all validation saves separate from the portable player's profile.
$env:APPDATA = Join-Path $projectRoot '.tools\v07-profile\Roaming'
$env:LOCALAPPDATA = Join-Path $projectRoot '.tools\v07-profile\Local'
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'artifacts') | Out-Null
$scripts = switch ($Mode) {
    'Screenshots' { @('test_visual_v07_window') }
    'Benchmark' { @('benchmark_visual_v07') }
    'Regression' { @('test_visual_v02_window', 'test_visual_v03_window', 'test_visual_v04_window', 'test_backpack_window', 'test_trait_upgrades_window') }
}
foreach ($script in $scripts) {
    $log = Join-Path $projectRoot ".tools/v07-$script-$Tag.log"
    # Quote filesystem arguments so a relocated project folder may contain spaces.
    $arguments = @('--path', ('"{0}"' -f $projectRoot), '--audio-driver', 'Dummy', '--script', "res://tests/$script.gd", '--log-file', ('"{0}"' -f $log), '--', '--test-mode', "--tag=$Tag")
    $process = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(240000)) {
        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        throw "Validation timed out: $script"
    }
    Get-Content -LiteralPath $log -Tail 5
    if ($process.ExitCode -ne 0) { throw "Validation failed: $script" }
}
