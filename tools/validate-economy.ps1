param(
    [ValidateSet('strict','flexible')][string]$Policy = 'strict',
    [ValidateRange(2,3)][int]$Revision = 3,
    [ValidateRange(1,10)][int]$Trials = 3,
    [ValidateRange(1,12)][int]$Runs = 8,
    [ValidatePattern('^[a-z0-9-]*$')][string]$Report = '',
    [switch]$Matrix
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA = Join-Path $projectRoot '.tools/t09b3-profile/Roaming'
$env:LOCALAPPDATA = Join-Path $projectRoot '.tools/t09b3-profile/Local'
New-Item -ItemType Directory -Force $env:APPDATA,$env:LOCALAPPDATA | Out-Null
$log = Join-Path $projectRoot ".tools/t09b3-r$Revision-$Policy.log"
$arguments = @('--headless','--path',('"{0}"' -f $projectRoot),'--audio-driver','Dummy','--script','res://tests/simulate_economy.gd','--log-file',('"{0}"' -f $log),'--','--test-mode',"--policy=$Policy","--economy-revision=$Revision","--runs=$Runs","--trials=$Trials")
if ($Report) { $arguments += "--report=$Report" }
if ($Matrix) { $arguments += '--matrix' }
$process = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(360000)) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue; throw 'Economy simulation timeout' }
Get-Content -LiteralPath $log -Tail 2
$errors = Get-Content -LiteralPath $log | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:' -and $_ -notmatch 'Failed to read the root certificate store' }
if ($process.ExitCode -ne 0 -or $errors) { throw 'Economy simulation failed' }
