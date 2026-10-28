# Clawd Buddy: a pixel companion that mirrors Claude Code sessions.
# Left click: dismiss and jump to the session's terminal. Drag: move. Right click: menu.
param([string]$StateDir = (Join-Path $env:LOCALAPPDATA 'clawd-buddy'))

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\ClawdBuddy', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

. (Join-Path $PSScriptRoot 'lib\state.ps1')
. (Join-Path $PSScriptRoot 'lib\sprites.ps1')

Add-Type -Namespace ClawdBuddy -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
'@

$PixelSize = 6
$SpriteTop = 12   # headroom for the "done" jump
$SessionsDir = Join-Path $StateDir 'sessions'
New-Item -ItemType Directory -Force -Path $SessionsDir | Out-Null

$Styles = @{
    done      = @{ Color = '#5E9E6E'; Title = "$([char]0x2713) Done";      Sound = 'Windows Notify System Generic.wav' }
    attention = @{ Color = '#D99A2B'; Title = '! Needs you';               Sound = 'Windows Notify Messaging.wav' }
    error     = @{ Color = '#C9483C'; Title = "$([char]0x2717) Error";     Sound = 'Windows Critical Stop.wav' }
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="{x:Null}" Topmost="True"
        ShowInTaskbar="False" ShowActivated="False" ResizeMode="NoResize" SizeToContent="WidthAndHeight"
        Title="Clawd Buddy">
  <StackPanel>
    <Border Name="Bubble" Visibility="Collapsed" CornerRadius="10" Padding="10,6" MaxWidth="260"
            Margin="0,0,0,4" HorizontalAlignment="Right" Background="#F7EFE5" BorderThickness="2">
      <Border.Effect><DropShadowEffect BlurRadius="8" ShadowDepth="1" Opacity="0.35"/></Border.Effect>
      <StackPanel>
        <TextBlock Name="BubbleTitle" FontFamily="Cascadia Mono, Consolas" FontWeight="Bold" FontSize="12"/>
        <TextBlock Name="BubbleDetail" FontFamily="Segoe UI" FontSize="12" TextWrapping="Wrap" Foreground="#3B2A20"/>
      </StackPanel>
    </Border>
    <Canvas Name="Sprite" Width="96" Height="78" HorizontalAlignment="Right" Background="#01000000" Cursor="Hand"/>
  </StackPanel>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$bubble = $window.FindName('Bubble')
$bubbleTitle = $window.FindName('BubbleTitle')
$bubbleDetail = $window.FindName('BubbleDetail')
$canvas = $window.FindName('Sprite')

$brushes = @{}
foreach ($key in $Palette.Keys) {
    $brush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Palette[$key]))
    $brush.Freeze()
    $brushes[$key] = $brush
}

$script:muted = $false
$script:dismissedBefore = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()  # old alerts stay quiet on startup
$script:alerted = @{}
$script:current = $null
$script:tick = 0
$script:reactionTick = 0
$script:lastDrawn = ''
$workArea = [System.Windows.SystemParameters]::WorkArea
$script:anchorRight = $workArea.Right - 16
$script:anchorBottom = $workArea.Bottom - 8

function Draw-Sprite([string]$FrameName, [int]$OffsetY) {
    $key = "$FrameName|$OffsetY"
    if ($key -eq $script:lastDrawn) { return }
    $script:lastDrawn = $key
    $canvas.Children.Clear()
    $rows = $Frames[$FrameName]
    for ($y = 0; $y -lt $rows.Count; $y++) {
        for ($x = 0; $x -lt $rows[$y].Length; $x++) {
            $c = [string]$rows[$y][$x]
            if ($c -eq '.') { continue }
            $rect = New-Object Windows.Shapes.Rectangle
            $rect.Width = $PixelSize; $rect.Height = $PixelSize; $rect.Fill = $brushes[$c]
            [Windows.Controls.Canvas]::SetLeft($rect, $x * $PixelSize)
            [Windows.Controls.Canvas]::SetTop($rect, $SpriteTop + $y * $PixelSize + $OffsetY)
            [void]$canvas.Children.Add($rect)
        }
    }
}

function Play-Sound([string]$Name) {
    if ($script:muted) { return }
    $path = Join-Path $env:WINDIR "Media\$Name"
    if (Test-Path -LiteralPath $path) {
        try { (New-Object System.Media.SoundPlayer $path).Play() } catch { }
    }
}

function Get-UnixMs([datetime]$Utc) { ([DateTimeOffset]$Utc).ToUnixTimeMilliseconds() }

function Read-Sessions {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    foreach ($file in Get-ChildItem -LiteralPath $SessionsDir -Filter '*.json' -ErrorAction SilentlyContinue) {
        try { $session = [IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json } catch { continue }
        $mtime = 0
        if ($session.transcript -and (Test-Path -LiteralPath $session.transcript)) {
            $mtime = Get-UnixMs (Get-Item -LiteralPath $session.transcript).LastWriteTimeUtc
        }
        [pscustomobject]@{
            id      = $file.BaseName
            state   = Get-EffectiveState -Session $session -TranscriptMtime $mtime -Now $now -DismissedBefore $script:dismissedBefore
            ts      = [long]$session.ts
            project = [string]$session.project
            detail  = [string]$session.detail
            hwnd    = [long]$session.hwnd
        }
    }
}

function Update-State {
    $sessions = @(Read-Sessions)
    $top = Select-DisplaySession -Sessions $sessions
    $state = 'idle'
    if ($top) { $state = $top.state }

    $canvas.ToolTip = if ($sessions.Count) {
        ($sessions | ForEach-Object { "$($_.project): $($_.state)" }) -join "`n"
    } else { 'Clawd Buddy - no sessions' }

    $previousState = if ($script:current) { $script:current.state } else { 'idle' }
    $script:current = [pscustomobject]@{ state = $state; session = $top }

    if ($Styles.ContainsKey($state)) {
        $alertKey = "$($top.id)|$($top.ts)|$state"
        if (-not $script:alerted.ContainsKey($alertKey)) {
            $script:alerted[$alertKey] = $true
            $script:reactionTick = $script:tick
            Play-Sound $Styles[$state].Sound
        }
        $style = $Styles[$state]
        $color = [Windows.Media.ColorConverter]::ConvertFromString($style.Color)
        $bubble.BorderBrush = New-Object Windows.Media.SolidColorBrush $color
        $bubbleTitle.Foreground = $bubble.BorderBrush
        $bubbleTitle.Text = if ($top.project) { "$($style.Title) - $($top.project)" } else { $style.Title }
        $bubbleDetail.Text = $top.detail
        $bubbleDetail.Visibility = if ($top.detail) { 'Visible' } else { 'Collapsed' }
        $bubble.Visibility = 'Visible'
    }
    elseif ($previousState -ne $state) {
        $bubble.Visibility = 'Collapsed'
    }
}

function Update-Animation {
    $t = $script:tick
    $sinceReaction = $t - $script:reactionTick
    switch ($script:current.state) {
        'working'   { Draw-Sprite $(if ([math]::Floor($t / 3) % 2) { 'work1' } else { 'work2' }) 0 }
        'done'      {
            $jump = @(0, -4, -8, -10, -8, -4, 0)
            $offset = if ($sinceReaction -lt $jump.Count) { $jump[$sinceReaction] } else { 0 }
            Draw-Sprite 'done' $offset
        }
        'attention' { Draw-Sprite $(if ([math]::Floor($t / 3) % 2) { 'attn1' } else { 'attn2' }) 0 }
        'error'     { Draw-Sprite 'error' 0 }
        default     { Draw-Sprite 'idle' 0 }
    }
}

function Focus-Session {
    $session = $script:current.session
    if (-not $session -or -not $session.hwnd) { return }
    $handle = [IntPtr]$session.hwnd
    if (-not [ClawdBuddy.Native]::IsWindow($handle)) { return }
    if ([ClawdBuddy.Native]::IsIconic($handle)) { [void][ClawdBuddy.Native]::ShowWindow($handle, 9) }
    [void][ClawdBuddy.Native]::SetForegroundWindow($handle)
}

# Keep the bottom-right corner fixed while the bubble grows or shrinks.
# Applied every tick: SizeChanged alone does not reposition a SizeToContent window reliably.
$script:dragging = $false
function Set-Anchor {
    if ($script:dragging -or -not $window.ActualWidth) { return }
    $left = $script:anchorRight - $window.ActualWidth
    $top = $script:anchorBottom - $window.ActualHeight
    if ([math]::Abs($window.Left - $left) -gt 0.5) { $window.Left = $left }
    if ([math]::Abs($window.Top - $top) -gt 0.5) { $window.Top = $top }
}

$window.Add_MouseLeftButtonDown({
    $left = $window.Left; $top = $window.Top
    $script:dragging = $true
    try { $window.DragMove() } catch { }
    $script:dragging = $false
    if ([math]::Abs($window.Left - $left) -lt 2 -and [math]::Abs($window.Top - $top) -lt 2) {
        Focus-Session
        $script:dismissedBefore = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $bubble.Visibility = 'Collapsed'
    }
    else {
        $script:anchorRight = $window.Left + $window.ActualWidth
        $script:anchorBottom = $window.Top + $window.ActualHeight
    }
})

$menu = New-Object Windows.Controls.ContextMenu
$muteItem = New-Object Windows.Controls.MenuItem
$muteItem.Header = 'Mute sounds'; $muteItem.IsCheckable = $true
$muteItem.Add_Click({ $script:muted = $muteItem.IsChecked })
$quitItem = New-Object Windows.Controls.MenuItem
$quitItem.Header = 'Quit'
$quitItem.Add_Click({ $window.Close() })
[void]$menu.Items.Add($muteItem); [void]$menu.Items.Add($quitItem)
$window.ContextMenu = $menu

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(120)
$timer.Add_Tick({
    try {
        if ($script:tick % 3 -eq 0) { Update-State }
        Update-Animation
        Set-Anchor
    }
    catch {
        try { Add-Content -LiteralPath (Join-Path $StateDir 'avatar.log') -Value "$(Get-Date -Format o) $_ $($_.InvocationInfo.PositionMessage)" } catch { }
    }
    $script:tick++
})

$window.Add_Closed({ $timer.Stop(); $mutex.ReleaseMutex() })
Update-State
Update-Animation
$timer.Start()
[void]$window.ShowDialog()
