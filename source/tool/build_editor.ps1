param([switch]$Run)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path $PSScriptRoot -Parent
$projectRoot = Split-Path $sourceRoot -Parent
$outputRoot = Join-Path $projectRoot 'aplicativo'
$mappedDrive = $null
$locationPushed = $false
try {
    # Os alvos nativos de media_kit excedem MAX_PATH em pastas longas.
    # Uma unidade temporaria evita alterar a configuracao global do Windows.
    foreach ($letter in @('V', 'W', 'X', 'Y', 'Z', 'U', 'T')) {
        $candidate = $letter + ':'
        if (-not (Test-Path -LiteralPath ($candidate + '\'))) {
            & subst.exe $candidate $projectRoot
            if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar caminho curto.' }
            $mappedDrive = $candidate
            break
        }
    }
    if ($null -eq $mappedDrive) { throw 'Nenhuma unidade temporaria disponivel.' }
    Push-Location -LiteralPath ($mappedDrive + '\source')
    $locationPushed = $true
    # Regenera os caches que guardam caminhos absolutos de compilacoes anteriores.
    & flutter clean
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao limpar os caches de compilacao.' }
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao obter dependencias.' }
    if ($Run) {
        & flutter run -d windows
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao executar o editor.' }
    } else {
        & flutter build windows --release --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o editor.' }
        New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
        Get-ChildItem -LiteralPath 'build\windows\x64\runner\Release' -Force |
            Copy-Item -Destination $outputRoot -Recurse -Force
        foreach ($runtimeName in @('ffmpeg', 'whisper')) {
            $runtimeRoot = Join-Path $outputRoot $runtimeName
            New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
            Get-ChildItem -LiteralPath ('tools\' + $runtimeName) -Force |
                Copy-Item -Destination $runtimeRoot -Recurse -Force
        }
        Write-Host ('Editor gerado: ' + (Join-Path $outputRoot 'VideoEditor.exe'))
    }
} finally {
    if ($locationPushed) { Pop-Location }
    if ($null -ne $mappedDrive) { & subst.exe $mappedDrive /D }
}
