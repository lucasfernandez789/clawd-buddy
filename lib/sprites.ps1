# Loads the pixel art from sprites.json: drawings are data, kept out of the script.
# Exposes $Palette (letter -> color), $Overlays and $Frames (name -> rows of letters).

$spriteData = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'sprites.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json

$script:Palette = @{}
$script:Overlays = @{}
$script:Frames = @{}
foreach ($entry in $spriteData.palette.PSObject.Properties) { $script:Palette[$entry.Name] = [string]$entry.Value }
# @() keeps one-row drawings as arrays; ConvertFrom-Json returns a bare string for them.
foreach ($entry in $spriteData.overlays.PSObject.Properties) { $script:Overlays[$entry.Name] = [string[]]@($entry.Value) }
foreach ($entry in $spriteData.frames.PSObject.Properties) { $script:Frames[$entry.Name] = [string[]]@($entry.Value) }
