[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SourceRoot,
  [Parameter(Mandatory = $true)]
  [string]$DestinationRoot
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
  throw ('Runtime do FFmpeg nao encontrado: ' + $SourceRoot)
}

$sourceBin = Join-Path $SourceRoot 'bin'
$requiredFiles = @(
  (Join-Path $sourceBin 'ffmpeg.exe'),
  (Join-Path $sourceBin 'ffprobe.exe'),
  (Join-Path $SourceRoot 'LICENSE'),
  (Join-Path $SourceRoot 'README.txt')
)
foreach ($requiredFile in $requiredFiles) {
  if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
    throw ('Arquivo obrigatorio do FFmpeg ausente: ' + $requiredFile)
  }
}

if (Test-Path -LiteralPath $DestinationRoot) {
  $existingItems = @(Get-ChildItem -LiteralPath $DestinationRoot -Force)
  if ($existingItems.Count -gt 0) {
    throw ('A pasta de destino do FFmpeg deve estar vazia: ' + $DestinationRoot)
  }
}

$destinationBin = Join-Path $DestinationRoot 'bin'
New-Item -ItemType Directory -Path $destinationBin -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceBin 'ffmpeg.exe') -Destination $destinationBin
Copy-Item -LiteralPath (Join-Path $sourceBin 'ffprobe.exe') -Destination $destinationBin
Copy-Item -LiteralPath (Join-Path $SourceRoot 'LICENSE') -Destination $DestinationRoot
Copy-Item -LiteralPath (Join-Path $SourceRoot 'README.txt') -Destination $DestinationRoot

$packagedExecutables = @(
  Get-ChildItem -LiteralPath $DestinationRoot -Recurse -Filter '*.exe' -File
)
$packagedExecutableNames = @($packagedExecutables.Name | Sort-Object)
$expectedExecutableNames = @('ffmpeg.exe', 'ffprobe.exe')
if (($packagedExecutableNames -join '|') -ne
    ($expectedExecutableNames -join '|')) {
  throw 'O runtime empacotado deve conter somente ffmpeg.exe e ffprobe.exe.'
}

$packagedFiles = @(Get-ChildItem -LiteralPath $DestinationRoot -Recurse -File)
$packagedSize = ($packagedFiles | Measure-Object Length -Sum).Sum
Write-Host 'FFmpeg runtime: Essentials'
Write-Host ('FFmpeg executaveis: ' + ($packagedExecutableNames -join ', '))
Write-Host ('FFmpeg arquivos:    ' + $packagedFiles.Count)
Write-Host ('FFmpeg bytes:       ' + $packagedSize)
