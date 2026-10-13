param(
    [ValidateSet('Run', 'Editor', 'Test', 'Capture')]
    [string]$Mode = 'Run',
    [ValidateSet('play', 'menu', 'shop', 'choice', 'encounter-log', 'trait-choice', 'trait-linkage', 'trait-flight', 'trait-shop', 'trait-log', 'conversion-unity', 'conversion-crit', 'conversion-next', 'conversion-shop', 'conversion-log', 'conversion-flight', 'result', 'hub', 'settings', 'tutorial', 'talents', 'talents-built', 'field-many', 'field-giant', 'cosmetics', 'pause')]
    [string]$View = 'play'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $projectRoot '.tools'
$engineFolder = Join-Path $toolRoot 'godot'
$engine = Get-ChildItem -LiteralPath $engineFolder -Filter '*_console.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $engine) {
    throw 'Godot is missing. Run tools/setup.ps1 or open project.godot with Godot 4.7.2.'
}
# Keep the portable editor profile and game saves inside this workspace.
$env:APPDATA = Join-Path $toolRoot 'profile\Roaming'
$env:LOCALAPPDATA = Join-Path $toolRoot 'profile\Local'
New-Item -ItemType Directory -Path $env:APPDATA,$env:LOCALAPPDATA -Force | Out-Null
$logPath = Join-Path $toolRoot ('{0}.log' -f $Mode.ToLowerInvariant())
$engineArgs = @('--path', $projectRoot, '--log-file', $logPath)
if ($Mode -in @('Run', 'Capture') -and -not (Test-Path -LiteralPath (Join-Path $projectRoot '.godot\global_script_class_cache.cfg'))) {
    & $engine.FullName --headless --path $projectRoot --editor --import --quit --log-file (Join-Path $toolRoot 'import.log')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
switch ($Mode) {
    'Editor' { $engineArgs += '--editor' }
    'Test' {
        & $engine.FullName --headless --path $projectRoot --editor --import --quit --log-file (Join-Path $toolRoot 'import.log')
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $engineArgs += @('--headless', '--script', 'res://tests/test_runner.gd', '--', '--test-mode')
    }
    'Capture' {
        $artifactRoot = Join-Path $projectRoot 'artifacts'
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $artifactRoot '.gdignore') -Value ''
        $capturePath = Join-Path $artifactRoot ($View + '.png')
        $engineArgs += @('--', '--test-mode', ('--capture=' + $capturePath), ('--preview=' + $View))
    }
}
& $engine.FullName @engineArgs
exit $LASTEXITCODE

