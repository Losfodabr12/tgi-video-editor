$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourceRoot = Join-Path $projectRoot 'source'
$identity = Get-Content -LiteralPath (Join-Path $sourceRoot 'lib\app\app_identity.dart') -Raw
$nameMatch = [regex]::Match($identity, "(?s)'EDITOR_NAME',\s*defaultValue:\s*'([^']+)'")
if (-not $nameMatch.Success) { throw 'Nome padrao ausente em app_identity.dart.' }
$productName = $nameMatch.Groups[1].Value
$background = [regex]::Match($identity, 'iconBackgroundArgb\s*=\s*0x([A-Fa-f0-9]{8})').Groups[1].Value
$accent = [regex]::Match($identity, 'iconAccentArgb\s*=\s*0x([A-Fa-f0-9]{8})').Groups[1].Value
if (-not $background -or -not $accent) { throw 'Cores ausentes em app_identity.dart.' }
$assets = Join-Path $sourceRoot 'assets\branding'
$resourceRoot = Join-Path $sourceRoot 'windows\runner'
$utf8 = New-Object Text.UTF8Encoding($false)
$escapedName = $productName.Replace('\','\\').Replace('"','\"')
$header = "// Generated from lib/app/app_identity.dart.`n#pragma once`n#define EDITOR_PRODUCT_NAME `"$escapedName`"`n#define EDITOR_WINDOW_TITLE L`"$escapedName`"`n"
[IO.File]::WriteAllText((Join-Path $resourceRoot 'app_branding.h'), $header, $utf8)
$bgRgb = '#' + $background.Substring(2)
$accentRgb = '#' + $accent.Substring(2)
$svg = "<svg xmlns=`"http://www.w3.org/2000/svg`" viewBox=`"0 0 256 256`"><rect width=`"256`" height=`"256`" rx=`"48`" fill=`"$bgRgb`"/><rect x=`"32`" y=`"48`" width=`"192`" height=`"160`" rx=`"20`" fill=`"none`" stroke=`"$accentRgb`" stroke-width=`"12`"/><path d=`"M104 88L166 128L104 168Z`" fill=`"white`"/><path d=`"M64 48V76M192 48V76M64 180V208M192 180V208`" stroke=`"$accentRgb`" stroke-width=`"12`"/></svg>`n"
[IO.File]::WriteAllText((Join-Path $assets 'editor_icon.svg'), $svg, $utf8)
Add-Type -AssemblyName System.Drawing
$bitmap = New-Object Drawing.Bitmap(256,256)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$brush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb([Convert]::ToInt32($background,16)))
$pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb([Convert]::ToInt32($accent,16)),12)
$path = New-Object Drawing.Drawing2D.GraphicsPath
$frame = New-Object Drawing.Drawing2D.GraphicsPath
$memory = New-Object IO.MemoryStream
try {
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([Drawing.Color]::Transparent)
    foreach ($arc in @(@(0,0,96,96,180,90),@(160,0,96,96,270,90),@(160,160,96,96,0,90),@(0,160,96,96,90,90))) { $path.AddArc($arc[0],$arc[1],$arc[2],$arc[3],$arc[4],$arc[5]) }
    $path.CloseFigure()
    $graphics.FillPath($brush,$path)
    foreach ($arc in @(@(32,48,40,40,180,90),@(184,48,40,40,270,90),@(184,168,40,40,0,90),@(32,168,40,40,90,90))) { $frame.AddArc($arc[0],$arc[1],$arc[2],$arc[3],$arc[4],$arc[5]) }
    $frame.CloseFigure()
    $graphics.DrawPath($pen,$frame)
    foreach ($line in @(@(64,48,64,76),@(192,48,192,76),@(64,180,64,208),@(192,180,192,208))) { $graphics.DrawLine($pen,$line[0],$line[1],$line[2],$line[3]) }
    $points = [Drawing.Point[]]@((New-Object Drawing.Point(104,88)),(New-Object Drawing.Point(166,128)),(New-Object Drawing.Point(104,168)))
    $graphics.FillPolygon([Drawing.Brushes]::White,$points)
    $bitmap.Save($memory,[Drawing.Imaging.ImageFormat]::Png)
    $bytes=$memory.ToArray()
    [IO.File]::WriteAllBytes((Join-Path $assets 'editor_icon.png'),$bytes)
    $iconPath=Join-Path $resourceRoot 'resources\app_icon.ico'
    $writer=New-Object IO.BinaryWriter([IO.File]::Create($iconPath))
    try {
        $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]1)
        $writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([byte]0)
        $writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$bytes.Length);$writer.Write([uint32]22);$writer.Write($bytes)
    } finally { $writer.Dispose() }
} finally {
    $memory.Dispose();$frame.Dispose();$path.Dispose();$pen.Dispose();$brush.Dispose();$graphics.Dispose();$bitmap.Dispose()
}
Write-Output ('Identidade gerada: ' + $productName)
