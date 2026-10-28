# Claude Code hook: records the session state the avatar renders.
# It must never break Claude Code, so it prints nothing and always exits 0.
param(
    [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'clawd-buddy'),
    [string]$Tag = ''
)

$ErrorActionPreference = 'Stop'

# Walks up from this process to the first ancestor that owns a window (the terminal).
function Get-HostWindow {
    $processId = $PID
    for ($i = 0; $i -lt 8; $i++) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
        if (-not $proc) { return 0 }
        $live = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($live -and $live.MainWindowHandle -ne [IntPtr]::Zero -and $processId -ne $PID) {
            return [long]$live.MainWindowHandle
        }
        $processId = $proc.ParentProcessId
    }
    return 0
}

function Start-Avatar {
    $existing = $null
    if ([System.Threading.Mutex]::TryOpenExisting('Local\ClawdBuddy', [ref]$existing)) { return }
    $avatar = Join-Path $PSScriptRoot 'avatar.ps1'
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Sta', '-File', "`"$avatar`"", '-StateDir', "`"$StateDir`""
    )
}

try {
    . (Join-Path $PSScriptRoot 'lib\state.ps1')
    [Console]::InputEncoding = New-Object System.Text.UTF8Encoding $false
    $hookEvent = [Console]::In.ReadToEnd() | ConvertFrom-Json

    $id = ([string]$hookEvent.session_id) -replace '[^\w-]', ''
    if (-not $id) { exit 0 }
    $sessions = Join-Path $StateDir 'sessions'
    New-Item -ItemType Directory -Force -Path $sessions | Out-Null
    $file = Join-Path $sessions "$id.json"

    if ($hookEvent.hook_event_name -eq 'SessionEnd') {
        Remove-Item -LiteralPath $file -ErrorAction SilentlyContinue
        exit 0
    }

    $previous = $null
    if (Test-Path -LiteralPath $file) { $previous = [IO.File]::ReadAllText($file) | ConvertFrom-Json }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $next = ConvertTo-SessionState -HookEvent $hookEvent -Previous $previous -Now $now
    if ($next) {
        $next.hwnd = 0
        if ($previous -and $previous.hwnd) { $next.hwnd = [long]$previous.hwnd }
        if ($next.state -in 'done', 'attention', 'error' -and -not $next.hwnd) { $next.hwnd = Get-HostWindow }
        $tmp = "$file.$PID.tmp"
        [IO.File]::WriteAllText($tmp, ($next | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding $false))
        Move-Item -LiteralPath $tmp -Destination $file -Force
    }

    if ($hookEvent.hook_event_name -eq 'SessionStart') { Start-Avatar }
}
catch {
    # A cosmetic hook must not surface errors in Claude Code; keep a trail for debugging.
    try { Add-Content -LiteralPath (Join-Path $StateDir 'hook.log') -Value "$(Get-Date -Format o) $_" } catch { }
}
exit 0
