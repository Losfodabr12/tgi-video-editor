param([string]$ToolsRoot, [switch]$SkipWhisper)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $ToolsRoot) { $ToolsRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'source\tools' }
$toolsPath = [IO.Path]::GetFullPath($ToolsRoot)
New-Item -ItemType Directory -Path $toolsPath -Force | Out-Null
$downloadRoot = Join-Path $toolsPath '.downloads'
New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

function Get-VerifiedFile {
    param([string]$Uri, [string]$Path, [string]$Sha256)
    if (Test-Path -LiteralPath $Path) {
        if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Sha256) { return }
    }
    $partialPath = $Path + '.partial'
    Invoke-WebRequest -Uri $Uri -OutFile $partialPath -UseBasicParsing
    $actual = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash
    if ($actual -ne $Sha256) { throw ('SHA-256 incorreto: ' + $Path) }
    Move-Item -LiteralPath $partialPath -Destination $Path -Force
}

function Expand-VerifiedRuntime {
    param([string]$Archive, [string]$ExeName, [string]$Destination)
    $scratchPath = Join-Path $downloadRoot ([guid]::NewGuid().ToString('N'))
    try {
        Expand-Archive -LiteralPath $Archive -DestinationPath $scratchPath
        $executable = Get-ChildItem -LiteralPath $scratchPath -File -Recurse |
            Where-Object { $_.Name -eq $ExeName } | Select-Object -First 1
        if ($null -eq $executable) { throw ('Executavel ausente: ' + $ExeName) }
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        Get-ChildItem -LiteralPath $executable.Directory.FullName -File |
            Copy-Item -Destination $Destination -Force
        $licenseRoot = Split-Path $Destination -Parent
        Get-ChildItem -LiteralPath $scratchPath -Recurse -File |
            Where-Object { $_.Name -match '^(LICENSE|COPYING)' } |
            ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $licenseRoot -Force }
    } finally {
        $resolvedScratch = [IO.Path]::GetFullPath($scratchPath)
        $resolvedDownloads = [IO.Path]::GetFullPath($downloadRoot).TrimEnd('\') + '\'
        if (-not $resolvedScratch.StartsWith($resolvedDownloads, [StringComparison]::OrdinalIgnoreCase)) { throw 'Diretorio temporario fora do destino.' }
        if (Test-Path -LiteralPath $resolvedScratch) { Remove-Item -LiteralPath $resolvedScratch -Recurse -Force }
    }
}

$ffmpegBin = Join-Path $toolsPath 'ffmpeg\bin'
if (-not ((Test-Path -LiteralPath (Join-Path $ffmpegBin 'ffmpeg.exe')) -and (Test-Path -LiteralPath (Join-Path $ffmpegBin 'ffprobe.exe')))) {
    $archive = Join-Path $downloadRoot 'ffmpeg-8.1.2.zip'
    Get-VerifiedFile -Uri 'https://github.com/GyanD/codexffmpeg/releases/download/8.1.2/ffmpeg-8.1.2-essentials_build.zip' -Path $archive -Sha256 'db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec'
    Expand-VerifiedRuntime -Archive $archive -ExeName 'ffmpeg.exe' -Destination $ffmpegBin
}
$ffmpegVersion = & (Join-Path $ffmpegBin 'ffmpeg.exe') -version
if ($LASTEXITCODE -ne 0) { throw 'FFmpeg nao inicializou.' }
Write-Output $ffmpegVersion[0]
$ffprobeVersion = & (Join-Path $ffmpegBin 'ffprobe.exe') -version
if ($LASTEXITCODE -ne 0) { throw 'ffprobe nao inicializou.' }
Write-Output $ffprobeVersion[0]

if (-not $SkipWhisper) {
    $whisperBin = Join-Path $toolsPath 'whisper\bin'
    $pinnedCliHash = '331dba46d6427105d2b802cdbc7eae916ea1c5abf9b0d3b5cfe460d8db8e4366'
    $installedCli = Join-Path $whisperBin 'whisper-cli.exe'
    if (-not (Test-Path -LiteralPath $installedCli) -or (Get-FileHash -LiteralPath $installedCli -Algorithm SHA256).Hash -ne $pinnedCliHash) {
        $archive = Join-Path $downloadRoot 'whisper-b5454-x64.zip'
        Get-VerifiedFile -Uri 'https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-bin-x64.zip' -Path $archive -Sha256 '6ba69e3482d7826214f90a6a9c84ca07782aec1e1d0c6a7c30c994fd5d816ccb'
        Expand-VerifiedRuntime -Archive $archive -ExeName 'whisper-cli.exe' -Destination $whisperBin
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/ggml-org/whisper.cpp/b5454/LICENSE' -OutFile (Join-Path $toolsPath 'whisper\LICENSE') -UseBasicParsing
    }
    if ((Get-FileHash -LiteralPath $installedCli -Algorithm SHA256).Hash -ne $pinnedCliHash) { throw 'Whisper CLI diverge do runtime fixado.' }
    & $installedCli --version
    if ($LASTEXITCODE -ne 0) { throw 'Whisper nao inicializou.' }
    $vulkanManifest = Join-Path $toolsPath 'whisper\vulkan\manifest.json'
    $vulkanReady = $false
    if (Test-Path -LiteralPath $vulkanManifest) {
        $vulkanReady = $true
        $entries = Get-Content -LiteralPath $vulkanManifest -Raw | ConvertFrom-Json
        foreach ($entry in $entries.PSObject.Properties) {
            $binary = Join-Path $toolsPath ('whisper\vulkan\bin\' + $entry.Name)
            if (-not (Test-Path -LiteralPath $binary) -or (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value) { $vulkanReady = $false; break }
        }
    }
    if (-not $vulkanReady) {
        & python (Join-Path $PSScriptRoot 'build_whisper_vulkan.py') --tools-root $toolsPath
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar Vulkan fixado.' }
    }
    $models = Join-Path $toolsPath 'whisper\models'
    New-Item -ItemType Directory -Path $models -Force | Out-Null
    Get-VerifiedFile -Uri 'https://huggingface.co/ggml-org/whisper-vad/resolve/9ffd54a1e1ee413ddf265af9913beaf518d1639b/ggml-silero-v5.1.2.bin' -Path (Join-Path $models 'ggml-silero-v5.1.2.bin') -Sha256 '29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf'
    Get-VerifiedFile -Uri 'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin' -Path (Join-Path $models 'ggml-base.bin') -Sha256 '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe'
}
Write-Output ('Ferramentas preparadas: ' + $toolsPath)
