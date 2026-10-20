param([switch]$Integration, [switch]$Build)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'editor_paths.ps1')
$projectRoot = Split-Path $PSScriptRoot -Parent
Invoke-EditorShortPath -ProjectRoot $projectRoot -Action {
    # Regenerate absolute native-hook paths under the same short drive as build.
    Invoke-EditorFlutter -Arguments @('clean')
    Invoke-EditorFlutter -Arguments @('pub','get')
    Invoke-EditorFlutter -Arguments @('analyze','--no-pub')
    Invoke-EditorFlutter -Arguments @('test','--no-pub')
    if ($Integration) {
        Invoke-EditorFlutter -Arguments @('test','--no-pub','--dart-define=TGI_RUN_FFMPEG_INTEGRATION_TESTS=true')
    }
    if ($Build) { Invoke-EditorFlutter -Arguments @('build','windows','--release','--no-pub') }
}
