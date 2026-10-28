# Clawd Buddy: a pixel companion that mirrors Claude Code sessions.
# Left click: dismiss and jump to the session's terminal. Drag: move. Right click: menu.
param(
    [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'clawd-buddy'),
    [string]$Language = $(if ($env:CLAWD_BUDDY_LANG) { $env:CLAWD_BUDDY_LANG } else { [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName }),
    # Renders every state and scene off-screen and exits non-zero on the first error.
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

if (-not $SelfTest) {
    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($true, 'Local\ClawdBuddy', [ref]$createdNew)
    if (-not $createdNew) { exit 0 }
}

. (Join-Path $PSScriptRoot 'lib\state.ps1')
. (Join-Path $PSScriptRoot 'lib\sprites.ps1')
$Strings = Get-Strings -Path (Join-Path $PSScriptRoot 'lib\strings.json') -Language $Language

Add-Type -Namespace ClawdBuddy -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
'@

$PixelSize = 6
$SpriteTop = 30   # headroom for jumps and effects above the head
$SleepAfterTicks = 5000   # ~10 minutes of idle at 120 ms per tick
$SessionsDir = Join-Path $StateDir 'sessions'
New-Item -ItemType Directory -Force -Path $SessionsDir | Out-Null

$Styles = @{
    done      = @{ Color = '#5E9E6E'; Icon = [string][char]0x2713; Sound = 'Windows Notify System Generic.wav' }
    attention = @{ Color = '#D99A2B'; Icon = '!';                  Sound = 'Windows Notify Messaging.wav' }
    error     = @{ Color = '#C9483C'; Icon = [string][char]0x2717; Sound = 'Windows Critical Stop.wav' }
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="{x:Null}" Topmost="True"
        ShowInTaskbar="False" ShowActivated="False" ResizeMode="NoResize" SizeToContent="WidthAndHeight"
        Title="Clawd Buddy">
  <StackPanel>
    <Border Name="Bubble" Visibility="Collapsed" CornerRadius="10" Padding="10,6" MaxWidth="260"
            Margin="0,0,0,2" HorizontalAlignment="Right" Background="#F7EFE5" BorderThickness="2">
      <Border.Effect><DropShadowEffect BlurRadius="8" ShadowDepth="1" Opacity="0.35"/></Border.Effect>
      <StackPanel>
        <TextBlock Name="BubbleTitle" FontFamily="Cascadia Mono, Consolas" FontWeight="Bold" FontSize="12"/>
        <TextBlock Name="BubbleDetail" FontFamily="Segoe UI" FontSize="12" TextWrapping="Wrap" Foreground="#3B2A20"/>
      </StackPanel>
    </Border>
    <Canvas Name="Sprite" Width="108" Height="96" HorizontalAlignment="Right" Background="#01000000" Cursor="Hand"/>
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
$script:current = [pscustomobject]@{ state = 'idle'; session = $null }
$script:tick = 0
$script:reactionTick = 0
$script:stateSince = 0
$script:lastDrawn = ''
$workArea = [System.Windows.SystemParameters]::WorkArea
$script:anchorRight = $workArea.Right - 16
$script:anchorBottom = $workArea.Bottom - 8

function Add-Pixels([string[]]$Rows, [int]$GridX, [int]$GridY, [int]$OffsetX, [int]$OffsetY) {
    for ($y = 0; $y -lt $Rows.Count; $y++) {
        for ($x = 0; $x -lt $Rows[$y].Length; $x++) {
            $c = [string]$Rows[$y][$x]
            if ($c -eq '.') { continue }
            $rect = New-Object Windows.Shapes.Rectangle
            $rect.Width = $PixelSize; $rect.Height = $PixelSize; $rect.Fill = $brushes[$c]
            [Windows.Controls.Canvas]::SetLeft($rect, 6 + ($GridX + $x) * $PixelSize + $OffsetX)
            [Windows.Controls.Canvas]::SetTop($rect, $SpriteTop + ($GridY + $y) * $PixelSize + $OffsetY)
            [void]$canvas.Children.Add($rect)
        }
    }
}

# Effects: array of @(overlayName, gridX, gridY); redraws only when something changed.
function Draw-Sprite([string]$FrameName, [int]$OffsetX = 0, [int]$OffsetY = 0, [object[]]$Effects = @()) {
    $key = "$FrameName|$OffsetX|$OffsetY|" + (($Effects | ForEach-Object { $_ -join ',' }) -join ';')
    if ($key -eq $script:lastDrawn) { return }
    $script:lastDrawn = $key
    # Fail loudly on typos: a missing name would otherwise draw nothing silently.
    if (-not $Frames.ContainsKey($FrameName)) { throw "Unknown frame '$FrameName'" }
    foreach ($effect in $Effects) { if (-not $Overlays.ContainsKey($effect[0])) { throw "Unknown overlay '$($effect[0])'" } }
    $canvas.Children.Clear()
    Add-Pixels $Frames[$FrameName] 0 0 $OffsetX $OffsetY
    foreach ($effect in $Effects) { Add-Pixels $Overlays[$effect[0]] $effect[1] $effect[2] $OffsetX $OffsetY }
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
            tool    = [string]$session.tool
            code    = [string]$session.code
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
        ($sessions | ForEach-Object { "$($_.project): $($Strings.states.($_.state))" }) -join "`n"
    } else { $Strings.noSessions }

    if ($state -ne $script:current.state) {
        $script:stateSince = $script:tick
        Reset-Activity $state
    }
    $script:current = [pscustomobject]@{ state = $state; session = $top }

    if (-not $Styles.ContainsKey($state)) { $bubble.Visibility = 'Collapsed'; return }

    $alertKey = "$($top.id)|$($top.ts)|$state"
    if (-not $script:alerted.ContainsKey($alertKey)) {
        $script:alerted[$alertKey] = $true
        $script:reactionTick = $script:tick
        Play-Sound $Styles[$state].Sound
    }
    $style = $Styles[$state]
    $text = Format-Bubble -Session $top -Strings $Strings
    $bubble.BorderBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($style.Color))
    $bubbleTitle.Foreground = $bubble.BorderBrush
    $title = "$($style.Icon) $($text.title)"
    $bubbleTitle.Text = if ($top.project) { "$title - $($top.project)" } else { $title }
    $bubbleDetail.Text = $text.detail
    $bubbleDetail.Visibility = if ($text.detail) { 'Visible' } else { 'Collapsed' }
    $bubble.Visibility = 'Visible'
}

# Random little scenes. Idle: every 20-45 s for 6-10 s. Working: every 6-15 s for 2-5 s.
# Gaps and lengths are in ticks (120 ms).
$ActivityPlans = @{
    idle    = @{
        Pool   = @('mate', 'music', 'yoyo', 'stretch', 'look', 'gum', 'juggle', 'gamer', 'cat', 'dance', 'meditate')
        Gap    = @(170, 380); Length = @(50, 85)
    }
    working = @{
        Pool   = @('idea', 'angry', 'scratch', 'sweat', 'fast', 'think', 'bug', 'search', 'yes', 'facepalm', 'loading', 'matebreak')
        Gap    = @(50, 125); Length = @(20, 40)
    }
}
# Loop the juggled balls follow over the head, in grid cells.
$JugglePath = @(@(2, -1), @(3, -3), @(5, -5), @(8, -5), @(11, -5), @(13, -3), @(14, -1), @(11, -2), @(8, -3), @(5, -2))
$FloatPath = @(0, -1, -2, -3, -4, -5, -4, -3, -2, -1)
$script:random = New-Object System.Random
$script:activity = $null
$script:activityStart = 0
$script:activityEnd = 0
$script:nextActivity = 0

function Reset-Activity([string]$State) {
    $script:activity = $null
    $plan = $ActivityPlans[$State]
    if ($plan) { $script:nextActivity = $script:tick + $script:random.Next($plan.Gap[0], $plan.Gap[1]) }
}

# Draws the running scene for the state and returns $true, or $false when none is due.
function Update-Activity([string]$State) {
    $t = $script:tick
    $plan = $ActivityPlans[$State]
    if (-not $script:activity) {
        if ($t -lt $script:nextActivity) { return $false }
        $script:activity = $plan.Pool[$script:random.Next(0, $plan.Pool.Count)]
        $script:activityStart = $t
        $script:activityEnd = $t + $script:random.Next($plan.Length[0], $plan.Length[1])
    }
    if ($t -ge $script:activityEnd) {
        Reset-Activity $State
        return $false
    }
    $e = $t - $script:activityStart
    $typing = if ([math]::Floor($t / 2) % 2) { 'work1' } else { 'work2' }
    switch ($script:activity) {
        'idea'    { Draw-Sprite 'work3' 0 $(if ($e -lt 3) { -3 } else { 0 }) @(, @('bulb', 6, -5)) }
        'angry'   {
            $shake = if ($e % 2) { 3 } else { -3 }
            Draw-Sprite 'workAngry' $shake 0 @(, @($(if ([math]::Floor($e / 2) % 2) { 'grr' } else { 'grr2' }), 12, -3))
        }
        'scratch' { Draw-Sprite 'workScratch' 0 $(if ([math]::Floor($e / 2) % 2) { -2 } else { 0 }) @(, @('what', 14, -5)) }
        'sweat'   { Draw-Sprite $typing 0 0 @(, @('sweat', 13, (1 + ([math]::Floor($e / 3) % 4)))) }
        'fast'    { Draw-Sprite $(if ($e % 2) { 'work1' } else { 'work2' }) 0 0 @(@('dot', (1 + ($e % 3)), -1), @('dot', (13 - ($e % 3)), -2)) }
        'think'   { Draw-Sprite 'work3' 0 0 @(, @('sparkle', 13, -3)) }
        'bug' {
            # A literal bug crawls over the laptop until it gets squashed.
            $length = $script:activityEnd - $script:activityStart
            if ($e -lt ($length * 0.7)) { Draw-Sprite $typing 0 0 @(, @('bug', (3 + [math]::Floor($e / 2) % 8), 7)) }
            else { Draw-Sprite 'workAngry' 0 0 @(, @('splat', 8, 6)) }
        }
        'search'    { Draw-Sprite 'work3' 0 0 @(, @('lens', (9 + [math]::Abs(([math]::Floor($e / 3) % 6) - 3)), -5)) }
        'yes'       { Draw-Sprite 'workYes' 0 $(if ($e -lt 4) { -4 } else { 0 }) @(, @('check', 6, -5)) }
        'facepalm'  { Draw-Sprite 'workPalm' 0 0 @(, @('sweat', 13, (1 + ([math]::Floor($e / 3) % 3)))) }
        'loading'   { Draw-Sprite $typing 0 0 @(, @("bar$([math]::Min(5, [math]::Floor($e / 4)))", 2, -4)) }
        'matebreak' { Draw-Sprite $(if ($e % 20 -lt 10) { 'mate1' } else { 'mate2' }) }
        'gum' {
            $phase = $e % 32
            if ($phase -lt 8) { Draw-Sprite 'plain' 0 0 @(, @('gum1', 7, 5)) }
            elseif ($phase -lt 16) { Draw-Sprite 'plain' 0 0 @(, @('gum2', 6, 4)) }
            elseif ($phase -lt 26) { Draw-Sprite 'plain' 0 0 @(, @('gum3', 5, 4)) }
            else { Draw-Sprite 'plain' 0 0 @(, @('pop', 5, 4)) }
        }
        'juggle' {
            $balls = @()
            foreach ($i in 0..2) {
                $point = $JugglePath[([math]::Floor($e / 2) + $i * 3) % $JugglePath.Count]
                $balls += , @(@('ballR', 'ballB', 'ballZ')[$i], $point[0], $point[1])
            }
            Draw-Sprite 'juggle' 0 0 $balls
        }
        'gamer' { Draw-Sprite $(if ([math]::Floor($e / 2) % 2) { 'gamer1' } else { 'gamer2' }) }
        'cat' {
            $effects = @(, @($(if ([math]::Floor($e / 4) % 2) { 'cat1' } else { 'cat2' }), 13, 7))
            if ($e % 20 -lt 8) { $effects += , @('heart', 11, -3) }
            Draw-Sprite 'lookR' 0 0 $effects
        }
        'dance' {
            $beat = [math]::Floor($e / 3) % 2
            Draw-Sprite $(if ($beat) { 'done' } else { 'plain' }) $(if ($beat) { 3 } else { -3 }) 0 @(, @('note', $(if ($beat) { 1 } else { 13 }), -3))
        }
        'meditate' {
            $effects = @()
            if ($e % 24 -lt 6) { $effects = @(, @('sparkle', 12, -4)) }
            Draw-Sprite 'meditate' 0 $FloatPath[[math]::Floor($e / 2) % $FloatPath.Count] $effects
        }
        'mate'    { Draw-Sprite $(if ($e % 27 -lt 15) { 'mate1' } else { 'mate2' }) }
        'music'   {
            $bob = if ([math]::Floor($e / 3) % 2) { -3 } else { 0 }
            Draw-Sprite 'music' 0 $bob @(, @('note', 13, (-2 - ([math]::Floor($e / 3) % 4))))
        }
        'yoyo'    { Draw-Sprite 'yoyo' 0 0 @(, @($(if ([math]::Floor($e / 4) % 2) { 'yoyo2' } else { 'yoyo1' }), 14, 6)) }
        'stretch' { Draw-Sprite 'stretch' 0 $(if ($e % 16 -lt 8) { -3 } else { 0 }) }
        'look'    { Draw-Sprite $(if ($e % 24 -lt 12) { 'lookL' } else { 'lookR' }) }
    }
    return $true
}

function Update-Animation {
    $t = $script:tick
    $sinceReaction = $t - $script:reactionTick
    $sinceState = $t - $script:stateSince
    switch ($script:current.state) {
        'working' {
            if (Update-Activity 'working') { return }
            $frame = if ([math]::Floor($t / 2) % 2) { 'work1' } else { 'work2' }
            # Parenthesize math inside arrays: the comma binds tighter than + and -.
            Draw-Sprite $frame 0 0 @(, @('dot', (12 + [math]::Floor($t / 4) % 3), -1))
        }
        'done' {
            $jump = @(0, -6, -12, -15, -12, -6, 0)
            $offset = if ($sinceReaction -lt $jump.Count) { $jump[$sinceReaction] } else { 0 }
            $effects = @()
            if ($sinceReaction -lt 30) {
                # Confetti falling around the head, positions derived from the tick.
                foreach ($i in 0..5) {
                    $x = (($i * 7) + 1) % 16
                    $y = -5 + (($sinceReaction + $i * 3) % 9)
                    $effects += , @('dot', $x, $y)
                }
            }
            elseif ($t % 60 -lt 6) { $effects = @(, @('sparkle', 13, -3)) }
            Draw-Sprite 'done' 0 $offset $effects
        }
        'attention' {
            $frame = if ([math]::Floor($t / 3) % 2) { 'attn1' } else { 'attn2' }
            # Assign inside the branch: "$x = if" unrolls the outer array and breaks the effect.
            $effects = @()
            if ([math]::Floor($t / 4) % 2) { $effects = @(, @('bang', 1, -5)) }
            Draw-Sprite $frame 0 0 $effects
        }
        'error' {
            $shake = @(-6, 6, -6, 6, -4, 4, -2, 2, 0)
            $offsetX = if ($sinceReaction -lt $shake.Count) { $shake[$sinceReaction] } else { 0 }
            $rise = [math]::Floor($t / 5) % 4
            Draw-Sprite 'error' $offsetX 0 @(, @('smoke', 6, (-2 - $rise)))
        }
        default {
            if ($sinceState -gt $SleepAfterTicks) {
                $rise = [math]::Floor($t / 6) % 4
                Draw-Sprite 'idleBlink' 0 0 @(, @('zzz', 12, (-2 - $rise)))
                return
            }
            if (Update-Activity 'idle') { return }
            if ($t % 50 -eq 0) { Draw-Sprite 'idleBlink' }
            elseif ($t % 150 -lt 4) { Draw-Sprite 'idlePage' }
            else { Draw-Sprite 'idle' }
        }
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
$muteItem.Header = $Strings.mute; $muteItem.IsCheckable = $true
$muteItem.Add_Click({ $script:muted = $muteItem.IsChecked })
$quitItem = New-Object Windows.Controls.MenuItem
$quitItem.Header = $Strings.quit
$quitItem.Add_Click({ $window.Close() })
[void]$menu.Items.Add($muteItem); [void]$menu.Items.Add($quitItem)
$window.ContextMenu = $menu

# One faulty frame must never kill the window: log it and keep ticking.
function Invoke-Tick {
    try {
        if ($script:tick % 3 -eq 0) { Update-State }
        Update-Animation
        Set-Anchor
    }
    catch {
        try { Add-Content -LiteralPath (Join-Path $StateDir 'avatar.log') -Value "$(Get-Date -Format o) $_ $($_.InvocationInfo.PositionMessage)" } catch { }
    }
    $script:tick++
}

if ($SelfTest) {
    try {
        foreach ($state in 'idle', 'working', 'done', 'attention', 'error') {
            $script:current = [pscustomobject]@{ state = $state; session = $null }
            $script:reactionTick = $script:tick
            $script:stateSince = $script:tick
            for ($i = 0; $i -lt 40; $i++) { Update-Animation; $script:tick++ }
        }
        # Sleep, then every scene of each plan for its whole length.
        $script:current = [pscustomobject]@{ state = 'idle'; session = $null }
        $script:stateSince = $script:tick - $SleepAfterTicks - 1
        Update-Animation
        foreach ($planState in $ActivityPlans.Keys) {
            $script:current = [pscustomobject]@{ state = $planState; session = $null }
            $script:stateSince = $script:tick
            foreach ($scene in $ActivityPlans[$planState].Pool) {
                $script:activity = $scene; $script:activityStart = $script:tick; $script:activityEnd = $script:tick + 90
                for ($i = 0; $i -lt 90; $i++) { Update-Animation; $script:tick++ }
            }
        }
        Write-Output 'selftest ok'
        exit 0
    }
    catch {
        Write-Output "selftest failed: $_ $($_.InvocationInfo.PositionMessage)"
        exit 1
    }
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(120)
$timer.Add_Tick({ Invoke-Tick })

$window.Add_Closed({ $timer.Stop(); $mutex.ReleaseMutex() })
Reset-Activity 'idle'
Invoke-Tick
$timer.Start()
[void]$window.ShowDialog()
