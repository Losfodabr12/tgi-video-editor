param([string]$ToolsRoot, [switch]$SkipWhisper)
& (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'tool\setup_tools.ps1') -ToolsRoot $ToolsRoot -SkipWhisper:$SkipWhisper
if (-not $?) { exit 1 }
