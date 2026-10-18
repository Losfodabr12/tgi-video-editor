[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SourceRoot,
  [Parameter(Mandatory = $true)]
  [string]$DestinationRoot,
  [string[]]$Models = @('base')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
  throw ('Pasta do whisper.cpp nao encontrada: ' + $SourceRoot)
}

$sourceBin = Join-Path $SourceRoot 'bin'
$sourceModels = Join-Path $SourceRoot 'models'
$sourceLicense = Join-Path $SourceRoot 'LICENSE'
$sourceReadme = Join-Path $SourceRoot 'README.md'

$whisperExecutable = $null
foreach ($candidateName in @('whisper-cli.exe', 'main.exe')) {
  $candidate = Join-Path $sourceBin $candidateName
  if (Test-Path -LiteralPath $candidate -PathType Leaf) {
    $whisperExecutable = Get-Item -LiteralPath $candidate
    break
  }
}
if (-not $whisperExecutable) {
  throw 'whisper-cli.exe ou main.exe nao foi encontrado em tools\whisper\bin.'
}
if (-not (Test-Path -LiteralPath $sourceLicense -PathType Leaf)) {
  throw 'LICENSE do whisper.cpp ausente. Execute tool\install_whisper_cpp.ps1.'
}

$modelFiles = @(
  foreach ($modelName in $Models) {
    if ($modelName -notmatch '^[a-z0-9._-]+$') {
      throw ('Nome de modelo Whisper invalido: ' + $modelName)
    }
    $modelPath = Join-Path $sourceModels ('ggml-' + $modelName + '.bin')
    if (-not (Test-Path -LiteralPath $modelPath -PathType Leaf)) {
      throw ('Modelo Whisper obrigatorio ausente: ' + $modelPath)
    }
    Get-Item -LiteralPath $modelPath
  }
)
if ($modelFiles.Count -eq 0) {
  throw 'Informe ao menos um modelo Whisper para o runtime.'
}

$runtimeDlls = @(
  Get-ChildItem -LiteralPath $sourceBin -File |
    Where-Object {
      $_.Name -eq 'whisper.dll' -or $_.Name -like 'ggml*.dll'
    }
)

if (Test-Path -LiteralPath $DestinationRoot) {
  $existingItems = @(Get-ChildItem -LiteralPath $DestinationRoot -Force)
  if ($existingItems.Count -gt 0) {
    throw ('A pasta de destino do Whisper deve estar vazia: ' + $DestinationRoot)
  }
}

$destinationBin = Join-Path $DestinationRoot 'bin'
$destinationModels = Join-Path $DestinationRoot 'models'
New-Item -ItemType Directory -Path $destinationBin -Force | Out-Null
New-Item -ItemType Directory -Path $destinationModels -Force | Out-Null

Copy-Item -LiteralPath $whisperExecutable.FullName -Destination $destinationBin
foreach ($dll in $runtimeDlls) {
  Copy-Item -LiteralPath $dll.FullName -Destination $destinationBin
}
foreach ($model in $modelFiles) {
  Copy-Item -LiteralPath $model.FullName -Destination $destinationModels
}
Copy-Item -LiteralPath $sourceLicense -Destination $DestinationRoot
if (Test-Path -LiteralPath $sourceReadme -PathType Leaf) {
  Copy-Item -LiteralPath $sourceReadme -Destination $DestinationRoot
}

$packagedExecutables = @(
  Get-ChildItem -LiteralPath $destinationBin -Filter '*.exe' -File
)
if ($packagedExecutables.Count -ne 1 -or
    $packagedExecutables[0].Name -ne $whisperExecutable.Name) {
  throw 'O runtime empacotado deve conter somente o executavel CLI do Whisper.'
}

$packagedFiles = @(Get-ChildItem -LiteralPath $DestinationRoot -Recurse -File)
$packagedSize = ($packagedFiles | Measure-Object Length -Sum).Sum
Write-Host ('Whisper runtime: ' + $packagedExecutables[0].Name)
Write-Host ('Whisper modelos: ' + $modelFiles.Count)
Write-Host ('Whisper arquivos: ' + $packagedFiles.Count)
Write-Host ('Whisper bytes:   ' + $packagedSize)
