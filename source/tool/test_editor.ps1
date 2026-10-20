param([switch]$Integration, [switch]$Build)
& (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'tool\test_editor.ps1') -Integration:$Integration -Build:$Build
if (-not $?) { exit 1 }
