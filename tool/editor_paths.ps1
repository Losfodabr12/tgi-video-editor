function Invoke-EditorShortPath {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot,
          [Parameter(Mandatory=$true)][scriptblock]$Action)
    $resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $mappedDrive = $null
    $locationPushed = $false
    try {
        foreach ($letter in @('V','W','X','Y','Z','U','T')) {
            $candidate = $letter + ':'
            if (-not (Test-Path -LiteralPath ($candidate + '\'))) {
                & subst.exe $candidate $resolvedRoot
                if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar caminho curto.' }
                $mappedDrive = $candidate
                break
            }
        }
        if ($null -eq $mappedDrive) { throw 'Nenhuma unidade temporaria disponivel.' }
        Push-Location -LiteralPath ($mappedDrive + '\source')
        $locationPushed = $true
        & $Action
    } finally {
        if ($locationPushed) { Pop-Location }
        if ($null -ne $mappedDrive) { & subst.exe $mappedDrive /D }
    }
}

function Invoke-EditorFlutter {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -ne $flutter) { $flutterPath = $flutter.Source }
    elseif ($env:FLUTTER_ROOT -and (Test-Path -LiteralPath (Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'))) {
        $flutterPath = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
    }
    else { throw 'Flutter nao encontrado no PATH ou em FLUTTER_ROOT.' }
    if ($Arguments[0] -in @('test','build','run')) {
        $manifestPath = Join-Path $PSScriptRoot '..\source\tools\whisper\vulkan\manifest.json'
        if (Test-Path -LiteralPath $manifestPath) {
            $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($manifestPath))
            $Arguments += ('--dart-define=TGI_VULKAN_MANIFEST=' + $encoded)
        }
    }
    # PowerShell 5 treats native stderr as ErrorRecord. Exit code is authoritative.
    $ErrorActionPreference = 'Continue'
    & $flutterPath @Arguments
    $result = $LASTEXITCODE
    if ($result -ne 0) { throw ('flutter ' + ($Arguments -join ' ') + ' falhou: ' + $result) }
}
