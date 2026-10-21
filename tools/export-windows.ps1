param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
$template = Join-Path $projectRoot '.tools/godot/editor_data/export_templates/4.7.2.stable/windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $template)) { throw 'Install templates first: python tools/setup-windows-templates.py' }
$output = Join-Path $projectRoot 'builds/windows'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$oldAppData = $env:APPDATA
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $projectRoot '.tools/export-profile/Roaming'
    $env:LOCALAPPDATA = Join-Path $projectRoot '.tools/export-profile/Local'
    New-Item -ItemType Directory -Force $env:APPDATA,$env:LOCALAPPDATA | Out-Null
    $log = Join-Path $projectRoot '.tools/export-windows.log'
    & $engine --headless --path $projectRoot --export-release 'Windows Desktop' (Join-Path $output 'RainyArrow.exe') --log-file $log
    if ($LASTEXITCODE -ne 0) { throw 'Windows export failed.' }
    $errors = Get-Content -LiteralPath $log | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:' -and $_ -notmatch 'Failed to read the root certificate store' }
    if ($errors) { throw "Export reported errors: $errors" }
    & $engine --headless --path $projectRoot --script res://tools/export_notices.gd --log-file (Join-Path $projectRoot '.tools/export-notices.log')
    if ($LASTEXITCODE -ne 0) { throw 'License notice export failed.' }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/audio/music/battle_v4/GeneralUser-GS-LICENSE.txt') -Destination $output
    @'
《箭如雨下》Windows x64 试玩版

双击 RainyArrow.exe 启动。请将 RainyArrow.pck 与程序放在同一目录。
左键在弓附近拖动并松开发射；Esc 取消拉弓／暂停；Q 主动技能；M 静音。
全屏、音量、减少特效等选项在“设置”中调整。

本版本含 T09-B3 成长调整与 T09-C 桌面验证；平衡仍在迭代。
存档位于 %APPDATA%\AzVGames\ArrowsLikeRain\save.json。
开发入口 Play.cmd 使用独立的 .tools/profile 存档，不会自动合并到此处。
压缩包不含任何玩家存档。关闭窗口会保存当前冒险。

引擎和第三方许可见 Godot-Third-Party-Notices.txt。
《林间交锋》使用的 GeneralUser GS 音色许可见 GeneralUser-GS-LICENSE.txt。
'@ | Set-Content -LiteralPath (Join-Path $output '开始游戏.txt') -Encoding utf8
    # Explicit allowlist prevents logs, stale test exports and player profiles entering the ZIP.
    $files = @('RainyArrow.exe','RainyArrow.pck','Godot-Third-Party-Notices.txt','GeneralUser-GS-LICENSE.txt','开始游戏.txt')
    $manifest = foreach ($file in $files) {
        $path = Join-Path $output $file
        $item = Get-Item -LiteralPath $path
        [ordered]@{name=$file; bytes=$item.Length; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
    }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding utf8
    $packageFiles = @($files + 'manifest.json' | ForEach-Object { Join-Path $output $_ })
    Compress-Archive -LiteralPath $packageFiles -DestinationPath (Join-Path $projectRoot 'builds/RainyArrow-windows-x64.zip') -Force
    Write-Output "Built: $output"
} finally {
    $env:APPDATA = $oldAppData
    $env:LOCALAPPDATA = $oldLocalAppData
}
