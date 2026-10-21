param(
    [ValidateSet('Journey', 'LateGame', 'All')]
    [string]$Mode = 'All'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw 'Run tools/setup.ps1 first.' }
$env:APPDATA = Join-Path $projectRoot '.tools\t09a-profile\Roaming'
$env:LOCALAPPDATA = Join-Path $projectRoot '.tools\t09a-profile\Local'
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'artifacts') | Out-Null
$scripts = @()
if ($Mode -in @('Journey', 'All')) { $scripts += 'test_journey_window' }
# These explicitly accelerated fixtures check late-game transitions, not balance or reachability.
if ($Mode -in @('LateGame', 'All')) {
    $scripts += @('test_supply_window', 'test_mastery_window', 'test_backpack_window', 'test_contracts_window', 'test_active_skills_window', 'test_leaderboard_window')
}
foreach ($script in $scripts) {
    $log = Join-Path $projectRoot ".tools/t09a-$script.log"
    $arguments = @('--path', ('"{0}"' -f $projectRoot), '--audio-driver', 'Dummy', '--script', "res://tests/$script.gd", '--log-file', ('"{0}"' -f $log), '--', '--test-mode')
    $process = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(240000)) {
        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        throw "Validation timed out: $script"
    }
    Get-Content -LiteralPath $log -Tail 5
    if ($process.ExitCode -ne 0) { throw "Validation failed: $script" }
}
