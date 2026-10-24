param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
if (-not $env:GITHUB_RUN_ID -or -not $env:GITHUB_SHA) { throw 'Este registro requer um run real do GitHub Actions.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
$report = Get-Content -LiteralPath (Join-Path $projectRoot 'RELATORIO_ALTERACOES.md') -Raw
if ($report -notmatch '(?s)<!-- CI_RESULT_START -->.*?<!-- CI_RESULT_END -->') { throw 'Marcador de evidencia CI ausente.' }
$runUrl = $env:GITHUB_SERVER_URL + '/' + $env:GITHUB_REPOSITORY + '/actions/runs/' + $env:GITHUB_RUN_ID
$evidence = @"
<!-- CI_RESULT_START -->
## Resultado remoto desta compilacao

Commit executado: ``$env:GITHUB_SHA``. [Run do GitHub Actions]($runUrl).
Runner Windows, Flutter 3.44.4. Etapas anteriores deste mesmo job terminaram
com exit 0: pub get, analyze --no-pub, test --no-pub, testes de integracao com
FFmpeg, build windows --release --no-pub e verificacao dos limites do catalogo
MCP e dos schemas. O empacotamento e upload ocorrem depois deste registro;
a conclusao completa do workflow deve ser consultada
no link do run. Este texto foi gerado depois dos comandos, nao antecipadamente.
<!-- CI_RESULT_END -->
"@
$updated = [regex]::Replace($report, '(?s)<!-- CI_RESULT_START -->.*?<!-- CI_RESULT_END -->', [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $evidence })
$parent = Split-Path ([IO.Path]::GetFullPath($OutputPath)) -Parent
New-Item -ItemType Directory -Path $parent -Force | Out-Null
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $updated, [Text.UTF8Encoding]::new($false))
