param(
    [ValidateSet('Window', 'Soak')][string]$Mode = 'Window',
    [ValidateRange(20, 1800)][int]$Seconds = 120,
    [ValidateSet('Dummy', 'WASAPI')][string]$AudioDriver = 'Dummy'
)
$ErrorActionPreference = 'Stop'
if ($Mode -eq 'Soak' -and $AudioDriver -ne 'Dummy') { throw 'Soak measurements use Dummy audio; use Window mode for device checks.' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
$oldAppData = $env:APPDATA
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $projectRoot '.tools/t09c-profile/Roaming'
    $env:LOCALAPPDATA = Join-Path $projectRoot '.tools/t09c-profile/Local'
    New-Item -ItemType Directory -Force $env:APPDATA,$env:LOCALAPPDATA,(Join-Path $projectRoot 'artifacts') | Out-Null
    $script = if ($Mode -eq 'Window') { 'test_desktop_window' } else { 'soak_desktop' }
    $log = Join-Path $projectRoot ".tools/t09c-$script-$AudioDriver.log"
    $arguments = @('--path', ('"{0}"' -f $projectRoot), '--audio-driver', $AudioDriver, '--script', "res://tests/$script.gd", '--log-file', ('"{0}"' -f $log), '--', '--test-mode', "--seconds=$Seconds")
    $process = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(($Seconds * 2 + 120) * 1000)) {
        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        throw "Desktop validation timed out: $Mode"
    }
    Get-Content -LiteralPath $log -Tail 8
    $errors = Get-Content -LiteralPath $log | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:' -and $_ -notmatch 'Failed to read the root certificate store' }
    if ($process.ExitCode -ne 0 -or $errors) { throw "Desktop validation failed: $Mode" }
} finally {
    $env:APPDATA = $oldAppData
    $env:LOCALAPPDATA = $oldLocalAppData
}
