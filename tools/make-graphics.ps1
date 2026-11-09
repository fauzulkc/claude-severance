<#
  Builds Claude Severance's logo files, app icon and release graphics with WPF (no other dependencies).
    powershell -NoProfile -STA -ExecutionPolicy Bypass -File tools\make-graphics.ps1
  Writes assets\logo\*.svg, assets\logo\png\*.png, assets\banner-*.png, assets\social-preview.png and src\assets\severance.ico.

  The mark: one disc cut down the middle. The left half (at work) is solid; the right half (outside) is only an
  outline; the halves sit a step apart. Geometry on a 64-unit tile; the setup window draws the same shapes.
#>
param([string]$Root = (Split-Path $PSScriptRoot))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing
$INV = [Globalization.CultureInfo]::InvariantCulture
$Logo = Join-Path $Root 'assets\logo'
New-Item -ItemType Directory -Force -Path (Join-Path $Logo 'png'), (Join-Path $Root 'src\assets') | Out-Null

$Light = @{ Canvas = '#F3F4F1'; Floor = '#ECEFEA'; Ink = '#13201C'; Muted = '#55625D'; Subtle = '#6F7B76'; Hairline = '#D7DCD6'; Tile = '#2F5D4F'; TileInk = '#F3F4F1'; Light = '#3A9A94'; Label = '#2A7A75'; DigitOp = 0.10 }
$Dark = @{ Canvas = '#06141A'; Floor = '#08191F'; Ink = '#CFEDEA'; Muted = '#82A9A6'; Subtle = '#638B88'; Hairline = '#17323A'; Tile = '#CFEDEA'; TileInk = '#06141A'; Light = '#7FD8CF'; Label = '#7FD8CF'; DigitOp = 0.16 }

$MarkSolid = 'M 29,12 A 18,18 0 0 0 29,48 Z'
$MarkLine = 'M 35,17.5 A 16.5,16.5 0 0 1 35,50.5 Z'

function Brush([string]$Hex, [double]$Alpha = 1) {
    $c = [Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $b = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb([byte][math]::Round(255 * $Alpha), $c.R, $c.G, $c.B))
    $b.Freeze()
    return $b.psobject.BaseObject
}
$FontBase = New-Object Uri ('file:///' + ((Join-Path $Root 'src\fonts') -replace '\\', '/') + '/')
$Sans = (New-Object Windows.Media.FontFamily $FontBase, './#IBM Plex Sans').psobject.BaseObject
$Mono = (New-Object Windows.Media.FontFamily $FontBase, './#IBM Plex Mono').psobject.BaseObject

# ---------------------------------------------------------------- SVG files
function Get-MarkSvg([string]$Tile, [string]$Ink, [int]$Size = 64, [string]$Extra = '', [int]$Width = 64) {
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="{0}" height="{1}" viewBox="0 0 {2} 64"><title>Claude Severance</title>' +
        '<rect width="64" height="64" rx="14" fill="{3}"/><path d="{5}" fill="{4}"/>' +
        '<path d="{6}" fill="none" stroke="{4}" stroke-width="3" stroke-linejoin="round"/>{7}</svg>') -f
    ($Size * $Width / 64), $Size, $Width, $Tile, $Ink, $MarkSolid, $MarkLine, $Extra
}

# The wordmark's words as outlines, so the SVG needs no font
function Get-TextPath([string]$Text, $Family, $Weight, [double]$Size, [double]$X, [double]$Baseline, [string]$Fill) {
    $tf = New-Object Windows.Media.Typeface $Family, ([Windows.FontStyles]::Normal), $Weight, ([Windows.FontStretches]::Normal)
    $ft = New-Object Windows.Media.FormattedText $Text, $INV, ([Windows.FlowDirection]::LeftToRight), $tf, $Size, (Brush '#000000'), 1.0
    $geo = $ft.BuildGeometry((New-Object Windows.Point $X, ($Baseline - $ft.Baseline)))
    $d = $geo.GetFlattenedPathGeometry(0.05, 'Relative').ToString($INV) -replace '^F[01]\s*', ''
    return @{ Svg = "<path d=`"$d`" fill=`"$Fill`"/>"; Width = $ft.WidthIncludingTrailingWhitespace }
}

$svgs = [ordered]@{
    'mark.svg'            = Get-MarkSvg $Light.Tile $Light.TileInk
    'mark-dark.svg'       = Get-MarkSvg $Dark.Tile $Dark.TileInk
    'mark-mono-black.svg' = Get-MarkSvg '#000000' '#FFFFFF'
    'mark-mono-white.svg' = Get-MarkSvg '#FFFFFF' '#000000'
}
foreach ($t in @(@('wordmark.svg', $Light), @('wordmark-dark.svg', $Dark))) {
    $p = $t[1]
    $words = Get-TextPath 'Claude Severance' $Sans ([Windows.FontWeights]::Medium) 34 82 44 $p.Ink
    $w = [int][math]::Ceiling(82 + $words.Width + 4)
    $svgs[$t[0]] = Get-MarkSvg $p.Tile $p.TileInk 64 $words.Svg $w
}
foreach ($k in $svgs.Keys) { [IO.File]::WriteAllText((Join-Path $Logo $k), $svgs[$k], (New-Object Text.UTF8Encoding $false)) }

# ---------------------------------------------------------------- WPF drawing
function New-MarkVisual([double]$Size, [string]$Tile, [string]$Ink) {
    $g = New-Object Windows.Controls.Grid
    $g.Width = $Size; $g.Height = $Size
    $r = New-Object Windows.Controls.Border
    $r.CornerRadius = New-Object Windows.CornerRadius ($Size * 14 / 64)
    $r.Background = Brush $Tile
    [void]$g.Children.Add($r)
    $cv = New-Object Windows.Controls.Canvas
    $cv.Width = 64; $cv.Height = 64
    $a = New-Object Windows.Shapes.Path
    $a.Data = [Windows.Media.Geometry]::Parse($MarkSolid); $a.Fill = Brush $Ink
    $b = New-Object Windows.Shapes.Path
    $b.Data = [Windows.Media.Geometry]::Parse($MarkLine); $b.Stroke = Brush $Ink; $b.StrokeThickness = 3; $b.StrokeLineJoin = 'Round'
    [void]$cv.Children.Add($a); [void]$cv.Children.Add($b)
    $vb = New-Object Windows.Controls.Viewbox
    $vb.Child = $cv
    [void]$g.Children.Add($vb)
    return $g
}

function Save-Visual($Visual, [int]$W, [int]$H, [string]$Path) {
    $Visual.Measure((New-Object Windows.Size $W, $H))
    $Visual.Arrange((New-Object Windows.Rect 0, 0, $W, $H))
    $Visual.UpdateLayout()
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap $W, $H, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($Visual)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create($Path)
    try { $enc.Save($fs) } finally { $fs.Close() }
}

# Downscales with GDI+ high-quality bicubic, which keeps small sizes crisp
function Save-Scaled([string]$From, [int]$Size, [string]$To) {
    $src = [System.Drawing.Image]::FromFile($From)
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'; $g.SmoothingMode = 'AntiAlias'
    $g.DrawImage($src, 0, 0, $Size, $Size)
    $g.Dispose(); $src.Dispose()
    $bmp.Save($To, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256, 512
foreach ($m in @(@('mark', $Light), @('mark-dark', $Dark))) {
    $big = Join-Path $Logo "png\$($m[0])-1024.png"
    Save-Visual (New-MarkVisual 1024 $m[1].Tile $m[1].TileInk) 1024 1024 $big
    foreach ($s in $sizes) { Save-Scaled $big $s (Join-Path $Logo "png\$($m[0])-$s.png") }
}

foreach ($t in @(@('wordmark.png', $Light), @('wordmark-dark.png', $Dark))) {
    $p = $t[1]
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    [void]$sp.Children.Add((New-MarkVisual 256 $p.Tile $p.TileInk))
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = 'Claude Severance'; $tb.FontFamily = $Sans; $tb.FontWeight = 'Medium'; $tb.FontSize = 136
    $tb.Foreground = Brush $p.Ink; $tb.VerticalAlignment = 'Center'; $tb.Margin = New-Object Windows.Thickness 72, 0, 16, 18
    [void]$sp.Children.Add($tb)
    $sp.Measure((New-Object Windows.Size ([double]::PositiveInfinity), 256))
    Save-Visual $sp ([int][math]::Ceiling($sp.DesiredSize.Width)) 256 (Join-Path $Logo "png\$($t[0])")
}

# ---------------------------------------------------------------- banners
# The severed floor: the work half shaded, one seam with its light, the mark on the seam, the words on the left
function New-Banner([int]$W, [int]$H, $P) {
    $root = New-Object Windows.Controls.Grid
    $root.Width = $W; $root.Height = $H
    $root.Background = Brush $P.Canvas
    $seamX = [math]::Round($W * 0.7)
    $floor = New-Object Windows.Shapes.Rectangle
    $floor.Width = $seamX; $floor.HorizontalAlignment = 'Left'; $floor.Fill = Brush $P.Floor
    [void]$root.Children.Add($floor)

    $cv = New-Object Windows.Controls.Canvas
    [void]$root.Children.Add($cv)
    $seam = New-Object Windows.Shapes.Rectangle
    $seam.Width = 1.5; $seam.Height = $H; $seam.Fill = Brush $P.Hairline
    [Windows.Controls.Canvas]::SetLeft($seam, $seamX)
    [void]$cv.Children.Add($seam)
    $lg = New-Object Windows.Media.LinearGradientBrush
    $lg.StartPoint = New-Object Windows.Point 0, 0; $lg.EndPoint = New-Object Windows.Point 0, 1
    $lc = [Windows.Media.ColorConverter]::ConvertFromString($P.Light)
    $clear = [Windows.Media.Color]::FromArgb(0, $lc.R, $lc.G, $lc.B)
    $lg.GradientStops.Add((New-Object Windows.Media.GradientStop $clear, 0))
    $lg.GradientStops.Add((New-Object Windows.Media.GradientStop $lc, 0.72))
    $lg.GradientStops.Add((New-Object Windows.Media.GradientStop $clear, 1))
    $light = New-Object Windows.Shapes.Rectangle
    $light.Width = 1.5; $light.Height = $H * 0.42; $light.Fill = $lg
    [Windows.Controls.Canvas]::SetLeft($light, $seamX); [Windows.Controls.Canvas]::SetTop($light, $H * 0.04)
    [void]$cv.Children.Add($light)

    # a faint band of digits along the foot of the work floor
    $rnd = New-Object Random 1962
    for ($row = 0; $row -lt 3; $row++) {
        $d = New-Object Windows.Controls.TextBlock
        $d.Text = (@(1..40 | ForEach-Object { $rnd.Next(0, 10) }) -join '    ')
        $d.FontFamily = $Mono; $d.FontSize = [math]::Round($H * 0.024); $d.Foreground = Brush $P.Label; $d.Opacity = $P.DigitOp * (1 - $row * 0.25)
        [Windows.Controls.Canvas]::SetLeft($d, $W * 0.05 - $row * 14); [Windows.Controls.Canvas]::SetTop($d, $H * (0.855 + $row * 0.05))
        $d.Width = $seamX - $W * 0.05 + $row * 14; $d.TextTrimming = 'None'; $d.ClipToBounds = $true
        [void]$cv.Children.Add($d)
    }

    $ms = [math]::Round($H * 0.34)
    $mark = New-MarkVisual $ms $P.Tile $P.TileInk
    [Windows.Controls.Canvas]::SetLeft($mark, $seamX - $ms / 2); [Windows.Controls.Canvas]::SetTop($mark, ($H - $ms) / 2)
    [void]$cv.Children.Add($mark)

    $copy = New-Object Windows.Controls.StackPanel
    $copy.Margin = New-Object Windows.Thickness ($W * 0.075), 0, 0, 0
    $copy.VerticalAlignment = 'Center'; $copy.HorizontalAlignment = 'Left'; $copy.Width = $seamX - $W * 0.075 - $ms / 2 - $W * 0.04
    $e = New-Object Windows.Controls.TextBlock
    $e.Text = 'CLAUDE SEVERANCE  ' + [char]0x00B7 + '  FOR WINDOWS'; $e.FontFamily = $Mono; $e.FontSize = [math]::Round($H * 0.03); $e.Foreground = Brush $P.Label
    [void]$copy.Children.Add($e)
    # the headline fits the space left of the mark: "Personal stays yours." is about 11 ems wide in Plex Sans
    $fs = [math]::Round([math]::Min($H * 0.115, $copy.Width / 11.2))
    foreach ($line in @(@('Work stays at work.', $P.Ink, 'Medium'), @('Personal stays yours.', $P.Muted, 'Normal'))) {
        $t = New-Object Windows.Controls.TextBlock
        $t.Text = $line[0]; $t.FontFamily = $Sans; $t.FontWeight = $line[2]; $t.FontSize = $fs
        $t.Foreground = Brush $line[1]; $t.LineStackingStrategy = 'BlockLineHeight'; $t.LineHeight = [math]::Round($fs * 1.13)
        if ($line[0] -like 'Work*') { $t.Margin = New-Object Windows.Thickness 0, ($H * 0.035), 0, 0 }
        [void]$copy.Children.Add($t)
    }
    $para = New-Object Windows.Controls.TextBlock
    $para.Text = 'Run your personal and org Claude accounts side by side on one PC, each with its own login, chats and Claude Code memory.'
    $para.FontFamily = $Sans; $para.FontSize = [math]::Round($H * 0.034); $para.Foreground = Brush $P.Muted; $para.TextWrapping = 'Wrap'
    $para.LineHeight = [math]::Round($H * 0.052); $para.Margin = New-Object Windows.Thickness 0, ($H * 0.045), 0, 0
    [void]$copy.Children.Add($para)
    $m = New-Object Windows.Controls.TextBlock
    $dot = '   ' + [char]0x00B7 + '   '
    $m.Text = "Free and open source${dot}No administrator${dot}Windows 10 and 11"
    $m.FontFamily = $Sans; $m.FontSize = [math]::Round($H * 0.026); $m.Foreground = Brush $P.Subtle; $m.Margin = New-Object Windows.Thickness 0, ($H * 0.05), 0, 0
    [void]$copy.Children.Add($m)
    [void]$root.Children.Add($copy)
    return $root
}
foreach ($b in @(@('banner-light.png', 1600, 560, $Light), @('banner-dark.png', 1600, 560, $Dark), @('social-preview.png', 1280, 640, $Dark))) {
    Save-Visual (New-Banner $b[1] $b[2] $b[3]) $b[1] $b[2] (Join-Path $Root "assets\$($b[0])")
}

# ---------------------------------------------------------------- Windows icon: PNG frames for every size Explorer asks for
$icoSizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$frames = @($icoSizes | ForEach-Object { , [IO.File]::ReadAllBytes((Join-Path $Logo "png\mark-$_.png")) })
$fs = [IO.File]::Create((Join-Path $Root 'src\assets\severance.ico'))
$w = New-Object IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$icoSizes.Count)
$offset = 6 + 16 * $icoSizes.Count
for ($i = 0; $i -lt $icoSizes.Count; $i++) {
    $s = $icoSizes[$i]; if ($s -ge 256) { $s = 0 }
    $w.Write([byte]$s); $w.Write([byte]$s); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$frames[$i].Length); $w.Write([uint32]$offset)
    $offset += $frames[$i].Length
}
foreach ($f in $frames) { $w.Write($f) }
$w.Close()
'graphics done'
