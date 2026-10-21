param(
    [ValidateSet('Audit', 'Tests', 'Window', 'EconomyWindow', 'Campaign', 'Matrix')][string]$Mode = 'Audit',
    [ValidateSet('legacy', 'resilient')][string]$Variant = 'resilient',
    [ValidateSet('damage', 'quantity', 'penetration')][string]$Route = 'quantity',
    [ValidateRange(1, 20)][int]$Trials = 6,
    [ValidateRange(0, 0.1)][double]$AimError = 0,
    [switch]$CurrentEconomy
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA = Join-Path $projectRoot '.tools/t09b2-profile/Roaming'
$env:LOCALAPPDATA = Join-Path $projectRoot '.tools/t09b2-profile/Local'
New-Item -ItemType Directory -Force $env:APPDATA,$env:LOCALAPPDATA,(Join-Path $projectRoot 'artifacts') | Out-Null
$script = switch ($Mode) {
    'Audit' { 'simulate_boss_pacing' }
    'Tests' { 'test_runner' }
    'Window' { 'test_balance_window' }
    'EconomyWindow' { 'test_economy_window' }
    'Campaign' { 'simulate_progression' }
    'Matrix' { 'simulate_progression' }
}
$label = if ($Mode -eq 'Audit') { "$Variant-$Route-aim$AimError" } else { $Mode.ToLower() }
$log = Join-Path $projectRoot ".tools/t09b2-$label.log"
$arguments = @('--path', ('"{0}"' -f $projectRoot), '--audio-driver', 'Dummy', '--script', "res://tests/$script.gd", '--log-file', ('"{0}"' -f $log))
if ($Mode -notin @('Window','EconomyWindow')) { $arguments += '--headless' }
$arguments += @('--', '--test-mode')
if ($Mode -eq 'Audit') { $arguments += @("--variant=$Variant", "--route=$Route", "--trials=$Trials", "--aim-error=$($AimError.ToString([System.Globalization.CultureInfo]::InvariantCulture))") }
if ($CurrentEconomy) { $arguments += '--economy-current' }
if ($Mode -eq 'Window') { $arguments += '--resilient' }
if ($Mode -eq 'Campaign') { $arguments += @('--variant=current', '--report=t09b2-campaign') }
if ($Mode -eq 'Matrix') { $arguments += @('--matrix', '--report=t09b2-matrix') }
$process = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(240000)) {
    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
    throw "Boss pacing validation timed out: $label"
}
Get-Content -LiteralPath $log -Tail 5
$errors = Get-Content -LiteralPath $log | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:' -and $_ -notmatch 'Failed to read the root certificate store' }
if ($process.ExitCode -ne 0 -or $errors) { throw "Boss pacing validation failed: $label" }
