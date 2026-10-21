param(
    [ValidateSet('Candidates', 'Campaign', 'Matrix', 'Window', 'Regression')]
    [string]$Mode = 'Campaign',
    [ValidatePattern('^test_[a-z0-9_]+$')]
    [string]$StartAt = 'test_journey_window'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA = Join-Path $projectRoot '.tools\t09b-profile\Roaming'
$env:LOCALAPPDATA = Join-Path $projectRoot '.tools\t09b-profile\Local'
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA,(Join-Path $projectRoot 'artifacts') | Out-Null
$jobs = switch ($Mode) {
    'Candidates' { @('baseline', 'draws16', 'gentle') }
    'Campaign' { @('current') }
    'Matrix' { @('matrix') }
    'Window' { @('test_balance_window') }
    'Regression' { @('test_journey_window', 'test_contracts_window', 'test_supply_window', 'test_mastery_window', 'test_boss_window', 'test_boss_combat_window', 'test_cosmetics_window', 'test_talent_expansion_window') }
}
foreach ($job in $jobs) {
	if ($Mode -eq 'Regression' -and $jobs.IndexOf($job) -lt $jobs.IndexOf($StartAt)) { continue }
    $script = if ($job.StartsWith('test_')) { $job } else { 'simulate_progression' }
    $log = Join-Path $projectRoot ".tools/t09b-$job.log"
    $arguments = @('--path', ('"{0}"' -f $projectRoot), '--audio-driver', 'Dummy', '--script', "res://tests/$script.gd", '--log-file', ('"{0}"' -f $log))
    if ($script -eq 'simulate_progression') { $arguments += '--headless' }
    $arguments += @('--', '--test-mode')
    if ($script -eq 'simulate_progression') { $arguments += $(if ($job -eq 'matrix') { '--matrix' } else { "--variant=$job" }) }
    $process = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(240000)) {
        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        throw "Balance validation timed out: $job"
    }
    Get-Content -LiteralPath $log -Tail 3
    $errors = Get-Content -LiteralPath $log | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:' -and $_ -notmatch 'Failed to read the root certificate store' }
    if ($process.ExitCode -ne 0 -or $errors) { throw "Balance validation failed: $job" }
}
