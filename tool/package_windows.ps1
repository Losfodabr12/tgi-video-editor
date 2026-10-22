param([string]$OutputRoot, [string]$ToolsRoot, [string]$ReportPath)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputRoot) { $OutputRoot = Join-Path $projectRoot 'dist' }
if (-not $ToolsRoot) { $ToolsRoot = Join-Path $projectRoot 'source\tools' }
if (-not $ReportPath) { $ReportPath = Join-Path $projectRoot 'RELATORIO_ALTERACOES.md' }
$outputPath = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'source\pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') { throw 'Versao de pacote invalida.' }
$version = $Matches[1]
$buildNumber = $Matches[2]
if ($env:GITHUB_REF_TYPE -eq 'tag' -and $env:GITHUB_REF_NAME -ne ('v' + $version)) {
    throw 'A tag deve corresponder a versao do pubspec.'
}
$releaseRoot = Join-Path $projectRoot 'source\build\windows\x64\runner\Release'
foreach ($required in @('VideoEditor.exe','flutter_windows.dll','data\app.so')) {
    if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot $required))) { throw ('Build incompleto: ' + $required) }
}
$exeInfo = (Get-Item -LiteralPath (Join-Path $releaseRoot 'VideoEditor.exe')).VersionInfo
$exeVersion = $exeInfo.ProductVersion
if ($exeVersion -ne ($version + '+' + $buildNumber)) { throw ('Build desatualizado: ' + $exeVersion) }
if ($exeInfo.FileVersion -ne $exeVersion) { throw 'FileVersion e ProductVersion divergem.' }
$scratchPath = Join-Path $outputPath ('.package-' + [guid]::NewGuid().ToString('N'))
$packageName = 'FrameStudio-' + $version + '-windows-x64'
$packagePath = Join-Path $scratchPath $packageName
try {
    New-Item -ItemType Directory -Path $packagePath -Force | Out-Null
    Get-ChildItem -LiteralPath $releaseRoot -Force | Copy-Item -Destination $packagePath -Recurse -Force
    foreach ($runtimeName in @('ffmpeg','whisper')) {
        $runtimeSource = Join-Path $ToolsRoot $runtimeName
        $runtimeTarget = Join-Path $packagePath $runtimeName
        New-Item -ItemType Directory -Path $runtimeTarget -Force | Out-Null
        # The runtime directories contain binaries, model, documentation and licenses.
        # Download caches and preview caches are never part of the release.
        foreach ($entry in Get-ChildItem -LiteralPath $runtimeSource -Force) {
            if ($entry.Name -notin @('.downloads','cache','cuda') -and $entry.Name -notlike '*.zip') {
                Copy-Item -LiteralPath $entry.FullName -Destination $runtimeTarget -Recurse -Force
            }
        }
    }
    foreach ($required in @('ffmpeg\bin\ffmpeg.exe','ffmpeg\bin\ffprobe.exe','ffmpeg\LICENSE',
        'whisper\bin\whisper-cli.exe','whisper\models\ggml-base.bin','whisper\LICENSE',
        'whisper\vulkan\licenses\Vulkan-Headers-MIT.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $packagePath $required))) { throw ('Runtime incompleto: ' + $required) }
    }
    $whisperCliHash = (Get-FileHash -LiteralPath (Join-Path $packagePath 'whisper\bin\whisper-cli.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($whisperCliHash -ne '331dba46d6427105d2b802cdbc7eae916ea1c5abf9b0d3b5cfe460d8db8e4366') { throw 'Whisper do ZIP difere do runtime testado.' }
    $manifestSource = Join-Path $ToolsRoot 'whisper\vulkan\manifest.json'
    $manifest = Get-Content -LiteralPath $manifestSource -Raw | ConvertFrom-Json
    foreach ($entry in $manifest.PSObject.Properties) {
        $binary = Join-Path $packagePath ('whisper\vulkan\bin\' + $entry.Name)
        if ((Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value) { throw ('Vulkan do ZIP diverge: ' + $entry.Name) }
    }
    # App-local Microsoft CRT avoids requiring an online installer on a fresh PC.
    foreach ($dll in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')) {
        Copy-Item -LiteralPath (Join-Path $env:WINDIR ('System32\' + $dll)) -Destination $packagePath -Force
    }
    Copy-Item -LiteralPath $ReportPath -Destination (Join-Path $packagePath 'RELATORIO_ALTERACOES.md')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'CHANGELOG.md') -Destination $packagePath
    New-Item -ItemType Directory -Path (Join-Path $packagePath 'docs') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\MCP.md') -Destination (Join-Path $packagePath 'docs\MCP.md')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\THIRD_PARTY.md') -Destination $packagePath
    @'
FRAME STUDIO - Windows x64
Extraia a pasta inteira e abra VideoEditor.exe. Mantenha DLLs, data, ffmpeg e
whisper junto ao executavel. Os runtimes e o modelo Base ja estao incluidos.
Dados e caches sao gravados em %LOCALAPPDATA%\TGI_VIDEO_EDITOR.
Detalhes de validacao: RELATORIO_ALTERACOES.md. Licencas: THIRD_PARTY.md,
ffmpeg\LICENSE, whisper\LICENSE e data\flutter_assets\NOTICES.Z.
'@ | Set-Content -LiteralPath (Join-Path $packagePath 'LEIA-ME.txt') -Encoding UTF8
    $ffmpegVersion = & (Join-Path $packagePath 'ffmpeg\bin\ffmpeg.exe') -version
    if ($LASTEXITCODE -ne 0) { throw 'FFmpeg empacotado falhou.' }
    $commit = git -C $projectRoot rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Commit nao encontrado.' }
    $changes = @(git -C $projectRoot status --porcelain)
    if ($LASTEXITCODE -ne 0) { throw 'Estado do checkout nao encontrado.' }
    @{
        version = $version; build = $buildNumber; productVersion = $exeVersion
        fileVersion = $exeInfo.FileVersion; commit = $commit
        workingTreeDirty = ($changes.Count -gt 0)
        ffmpeg = $ffmpegVersion[0]; ffmpegLicense = 'GPL-3.0-or-later'
        files = @(Get-ChildItem -LiteralPath $packagePath -Recurse -File | ForEach-Object {
            @{ path = $_.FullName.Substring($packagePath.Length + 1).Replace('\','/');
               sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
        })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $packagePath 'BUILD_INFO.json') -Encoding UTF8
    $archivePath = Join-Path $outputPath ($packageName + '.zip')
    Compress-Archive -LiteralPath $packagePath -DestinationPath $archivePath -Force
    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    ($hash + '  ' + (Split-Path $archivePath -Leaf)) | Set-Content -LiteralPath (Join-Path $outputPath 'SHA256SUMS.txt') -Encoding ascii
    Copy-Item -LiteralPath $ReportPath -Destination (Join-Path $outputPath 'RELATORIO_ALTERACOES.md') -Force
    Write-Output ('Pacote: ' + $archivePath)
    Write-Output ('SHA256: ' + $hash)
} finally {
    $resolvedScratch = [IO.Path]::GetFullPath($scratchPath)
    $resolvedOutput = $outputPath.TrimEnd('\') + '\'
    if (-not $resolvedScratch.StartsWith($resolvedOutput, [StringComparison]::OrdinalIgnoreCase)) { throw 'Temporario fora do destino.' }
    if (Test-Path -LiteralPath $resolvedScratch) { Remove-Item -LiteralPath $resolvedScratch -Recurse -Force }
}
