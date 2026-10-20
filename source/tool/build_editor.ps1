param([switch]$Run)
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path $PSScriptRoot -Parent
$projectRoot = Split-Path $sourceRoot -Parent
$outputRoot = Join-Path $projectRoot 'aplicativo'
. (Join-Path $projectRoot 'tool\editor_paths.ps1')
Invoke-EditorShortPath -ProjectRoot $projectRoot -Action {
    Invoke-EditorFlutter -Arguments @('clean')
    Invoke-EditorFlutter -Arguments @('pub','get')
    if ($Run) { Invoke-EditorFlutter -Arguments @('run','-d','windows') }
    else {
        Invoke-EditorFlutter -Arguments @('build','windows','--release','--no-pub')
        New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
        Get-ChildItem -LiteralPath 'build\windows\x64\runner\Release' -Force |
            Copy-Item -Destination $outputRoot -Recurse -Force
        foreach ($runtimeName in @('ffmpeg','whisper')) {
            $runtimeRoot = Join-Path $outputRoot $runtimeName
            New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
            Get-ChildItem -LiteralPath ('tools\' + $runtimeName) -Force |
                Copy-Item -Destination $runtimeRoot -Recurse -Force
        }
        Write-Output ('Editor gerado: ' + (Join-Path $outputRoot 'VideoEditor.exe'))
    }
}
