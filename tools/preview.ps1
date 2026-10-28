# Renders every scene to a PNG sprite sheet: powershell -Sta -File tools\preview.ps1 -Out preview.png
param([string]$Out = (Join-Path (Split-Path -Parent $PSScriptRoot) 'preview.png'))

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\sprites.ps1')

# Scene: label, frame, overlays (name, gridX, gridY).
$scenes = @(
    @('reading', 'idle', @()), @('page turn', 'idlePage', @()), @('sleeping', 'idleBlink', @(, @('zzz', 12, -5))),
    @('mate', 'mate1', @()), @('sip', 'mate2', @()), @('music', 'music', @(, @('note', 13, -3))),
    @('yo-yo', 'yoyo', @(, @('yoyo2', 14, 6))), @('stretch', 'stretch', @()), @('look', 'lookL', @()),
    @('typing', 'work1', @(, @('dot', 13, -1))), @('idea', 'work3', @(, @('bulb', 6, -5))), @('grr', 'workAngry', @(, @('grr', 12, -3))),
    @('hmm?', 'workScratch', @(, @('what', 14, -5))), @('sweat', 'work2', @(, @('sweat', 13, 2))), @('done', 'done', @(@('dot', 1, -3), @('dot', 8, -4), @('dot', 15, -2))),
    @('needs you', 'attn1', @(, @('bang', 1, -5))), @('error', 'error', @(, @('smoke', 6, -4))),
    @('gum', 'plain', @(, @('gum3', 5, 4))), @('juggle', 'juggle', @(@('ballR', 3, -3), @('ballB', 8, -5), @('ballZ', 13, -3))),
    @('gamer', 'gamer2', @()), @('cat visit', 'lookR', @(@('cat1', 13, 7), @('heart', 11, -3))), @('meditate', 'meditate', @(, @('sparkle', 12, -4))),
    @('bug!', 'work1', @(, @('bug', 6, 7))), @('search', 'work3', @(, @('lens', 10, -5))), @('yes!', 'workYes', @(, @('check', 6, -5))),
    @('facepalm', 'workPalm', @(, @('sweat', 13, 2))), @('loading', 'work2', @(, @('bar3', 2, -4)))
)

$px = 5; $cellW = 110; $cellH = 110; $cols = 7
$rows = [math]::Ceiling($scenes.Count / $cols)
$visual = New-Object Windows.Media.DrawingVisual
$dc = $visual.RenderOpen()
$dc.DrawRectangle((New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x2A, 0x22, 0x33))), $null,
    (New-Object Windows.Rect 0, 0, ($cols * $cellW), ($rows * $cellH)))
$brushes = @{}
foreach ($k in $Palette.Keys) { $brushes[$k] = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Palette[$k])) }

function Draw-Rows($Rows, $OriginX, $OriginY) {
    for ($y = 0; $y -lt $Rows.Count; $y++) {
        for ($x = 0; $x -lt $Rows[$y].Length; $x++) {
            $c = [string]$Rows[$y][$x]
            if ($c -eq '.') { continue }
            $dc.DrawRectangle($brushes[$c], $null, (New-Object Windows.Rect ($OriginX + $x * $px), ($OriginY + $y * $px), $px, $px))
        }
    }
}

for ($i = 0; $i -lt $scenes.Count; $i++) {
    $label, $frame, $effects = $scenes[$i]
    $ox = ($i % $cols) * $cellW + 10
    $oy = [math]::Floor($i / $cols) * $cellH + 28
    Draw-Rows $Frames[$frame] $ox $oy
    foreach ($e in $effects) { Draw-Rows $Overlays[$e[0]] ($ox + $e[1] * $px) ($oy + $e[2] * $px) }
    $text = New-Object Windows.Media.FormattedText ($label, [Globalization.CultureInfo]::InvariantCulture,
        [Windows.FlowDirection]::LeftToRight, (New-Object Windows.Media.Typeface 'Consolas'), 11, [Windows.Media.Brushes]::WhiteSmoke)
    $dc.DrawText($text, (New-Object Windows.Point $ox, ($oy + 60)))
}
$dc.Close()

$bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap ($cols * $cellW), ($rows * $cellH), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
$bitmap.Render($visual)
$encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
$stream = [IO.File]::Create($Out)
try { $encoder.Save($stream) } finally { $stream.Dispose() }
Write-Host "Saved $Out"
