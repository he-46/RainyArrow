param()
$ErrorActionPreference = 'Stop'
function Test-SameJsonValue($Left, $Right) {
    if ($null -eq $Left -or $null -eq $Right) { return $null -eq $Left -and $null -eq $Right }
    if ($Left -is [System.Management.Automation.PSCustomObject]) {
        if ($Right -isnot [System.Management.Automation.PSCustomObject]) { return $false }
        $keys = @($Left.PSObject.Properties | ForEach-Object Name)
        if ($keys.Count -ne @($Right.PSObject.Properties | ForEach-Object Name).Count) { return $false }
        foreach ($key in $keys) {
            if ($null -eq $Right.PSObject.Properties[$key] -or -not (Test-SameJsonValue $Left.$key $Right.$key)) { return $false }
        }
        return $true
    }
    if ($Left -is [array]) {
        if ($Right -isnot [array] -or $Left.Count -ne $Right.Count) { return $false }
        for ($i = 0; $i -lt $Left.Count; $i++) {
            if (-not (Test-SameJsonValue $Left[$i] $Right[$i])) { return $false }
        }
        return $true
    }
    # JSON 0 and 0.0 denote the same number after Godot canonicalizes a loaded save.
    return $Left -ceq $Right
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
$package = Join-Path $projectRoot 'builds/RainyArrow-windows-x64.zip'
if (-not (Test-Path -LiteralPath $package)) { throw 'Run tools/export-windows.ps1 first.' }
$sandbox = Join-Path $projectRoot ('.tools/release-check-' + [guid]::NewGuid().ToString('N'))
$independent = Join-Path $sandbox '独立试玩 Windows'
Expand-Archive -LiteralPath $package -DestinationPath $independent
$oldAppData = $env:APPDATA
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $sandbox 'Roaming'
    $env:LOCALAPPDATA = Join-Path $sandbox 'Local'
    New-Item -ItemType Directory -Force $env:APPDATA,$env:LOCALAPPDATA | Out-Null
    $exe = Join-Path $independent 'RainyArrow.exe'
    foreach ($view in @('menu','play','shop','talents','tutorial')) {
        $log = Join-Path $projectRoot ".tools/t09c-release-$view.log"
        $capture = Join-Path $projectRoot "artifacts/t09c-release-$view.png"
        $arguments = @('--audio-driver','Dummy','--log-file',('"{0}"' -f $log),'--','--test-mode',('--capture="{0}"' -f $capture),"--preview=$view")
        $process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $independent -WindowStyle Hidden -PassThru
        if (-not $process.WaitForExit(60000)) {
            Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
            throw "Standalone capture timed out: $view"
        }
        $content = Get-Content -LiteralPath $log
        $errors = $content | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:' -and $_ -notmatch 'Failed to read the root certificate store' }
        if ($process.ExitCode -ne 0 -or $errors -or -not ($content -match 'CAPTURE OK')) { throw "Standalone failed: $view $errors" }
        if ($view -eq 'play') {
            $sample = Join-Path $env:APPDATA 'AzVGames/ArrowsLikeRain/tests/capture-save.json'
            $playerSave = Join-Path $env:APPDATA 'AzVGames/ArrowsLikeRain/save.json'
            Copy-Item -LiteralPath $sample -Destination $playerSave
            $before = Get-Content -LiteralPath $playerSave -Raw | ConvertFrom-Json
        }
    }
    # Reopen the isolated fixture via the normal save-loading path, without --test-mode.
    $log = Join-Path $projectRoot '.tools/t09c-release-continue.log'
    $capture = Join-Path $projectRoot 'artifacts/t09c-release-continue.png'
    $process = Start-Process -FilePath $exe -WorkingDirectory $independent -WindowStyle Hidden -PassThru -ArgumentList @('--audio-driver','Dummy','--log-file',('"{0}"' -f $log),'--',('--capture="{0}"' -f $capture))
    if (-not $process.WaitForExit(60000)) {
        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        throw 'Standalone reopen timed out.'
    }
    $content = Get-Content -LiteralPath $log
    $errors = $content | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:' -and $_ -notmatch 'Failed to read the root certificate store' }
    if ($process.ExitCode -ne 0 -or $errors -or -not ($content -match 'CAPTURE OK')) { throw "Standalone reopen failed: $errors" }
    $after = Get-Content -LiteralPath $playerSave -Raw | ConvertFrom-Json
    @{before=$before; after=$after} | ConvertTo-Json -Depth 100 |
        Set-Content -LiteralPath (Join-Path $projectRoot 'artifacts/t09c-release-save-roundtrip.json') -Encoding utf8
    if ($null -eq $before.payload.run -or $null -eq $after.payload.run -or $after.version -ne 26) { throw 'Missing or invalid adventure in release save.' }
    # Opening the home page deliberately suspends a previously active adventure.
    $before.payload.run.suspended = $true
    if (-not (Test-SameJsonValue $before.payload.run $after.payload.run)) { throw 'Reopening changed the stored adventure.' }
    if (-not (Test-SameJsonValue $before.payload.world $after.payload.world)) { throw 'Reopening changed the saved field.' }
    # Inspect the actual exported resource list using the same preset as the release.
    $auditZip = Join-Path $projectRoot 'artifacts/t09c-resource-audit.zip'
    & $engine --headless --path $projectRoot --export-pack 'Windows Desktop' $auditZip --log-file (Join-Path $projectRoot '.tools/t09c-pack-audit.log')
    if ($LASTEXITCODE -ne 0) { throw 'Resource audit export failed.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($auditZip)
    try {
        $names = @($archive.Entries | ForEach-Object FullName)
        $forbidden = $names | Where-Object { $_ -match '^(tests|tools|docs|artifacts|artfacts|builds|exports|saves)/|(^|/)save\.json$|\.mid$' }
        if ($forbidden) { throw "Unexpected packaged files: $forbidden" }
        $music = @($names | Where-Object { $_ -match '^assets/audio/music/.*\.ogg\.import$' })
        if ($music.Count -ne 3) { throw "Expected only the three selected music tracks, found $($music.Count)" }
        [ordered]@{independent_directory=$independent; launches=6; save_version=$after.version; files=$names.Count; music=$music; excluded_files=0; audio='Dummy'; checks='five scene captures plus normal save-loading reopen; Chinese and space path'} |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $projectRoot 'artifacts/t09c-export.json') -Encoding utf8
    } finally { $archive.Dispose() }
    Write-Output "Standalone release checks passed: $independent"
} finally {
    $env:APPDATA = $oldAppData
    $env:LOCALAPPDATA = $oldLocalAppData
}
