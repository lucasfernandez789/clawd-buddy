# Pure state logic shared by hook.ps1 and avatar.ps1 (no I/O, so it is testable).
# Keep this file ASCII-only: Windows PowerShell 5.1 misreads BOM-less UTF-8.

$script:StatePriority = @{ idle = 0; working = 1; done = 2; attention = 3; error = 4 }

$script:AttentionTypes = @(
    'permission_prompt', 'elicitation_dialog', 'elicitation_url_dialog', 'agent_needs_input'
)

function Get-FirstLine {
    param([string]$Text, [int]$Max = 90)
    $line = ($Text -split "`r?`n" | ForEach-Object { ($_ -replace '[#*`>_]', '').Trim() } |
        Where-Object { $_ } | Select-Object -First 1)
    if (-not $line) { return '' }
    if ($line.Length -gt $Max) { return $line.Substring(0, $Max - 3) + '...' }
    return $line
}

# Maps one hook payload to the session's next state. Returns $null when the
# event should not change anything.
function ConvertTo-SessionState {
    param($HookEvent, $Previous, [long]$Now)

    $project = ''
    if ($HookEvent.cwd) { $project = Split-Path -Leaf ([string]$HookEvent.cwd) }
    # 'started' rides along every state so Stop can tell how long the turn took.
    $started = if ($Previous -and $Previous.started) { [long]$Previous.started } else { 0 }
    $base = @{ project = $project; transcript = [string]$HookEvent.transcript_path; ts = $Now; started = $started }

    switch ([string]$HookEvent.hook_event_name) {
        # SessionStart repeats on resume/clear/compact: never reset a live session.
        'SessionStart' {
            if ($Previous) { return $null }
            return $base + @{ state = 'idle'; detail = '' }
        }
        'UserPromptSubmit' { $base.started = $Now; return $base + @{ state = 'working'; detail = '' } }
        'Stop' {
            $took = if ($started) { $Now - $started } else { 0 }
            return $base + @{ state = 'done'; detail = Get-FirstLine $HookEvent.last_assistant_message; took = $took }
        }
        # The avatar localizes 'code' and 'tool'; 'detail' keeps the raw text.
        'StopFailure' {
            return $base + @{ state = 'error'; code = [string]$HookEvent.error; detail = [string]$HookEvent.error_details }
        }
        'PermissionRequest' {
            return $base + @{ state = 'attention'; tool = [string]$HookEvent.tool_name; detail = '' }
        }
        # Fallback only: it arrives late for permissions and repeats idle noise.
        'Notification' {
            if ($script:AttentionTypes -notcontains [string]$HookEvent.notification_type) { return $null }
            if ($Previous -and $Previous.state -eq 'attention') { return $null }
            return $base + @{ state = 'attention'; detail = [string]$HookEvent.message }
        }
    }
    return $null
}

# What a stored session should look like right now.
function Get-EffectiveState {
    param($Session, [long]$TranscriptMtime, [long]$Now, [long]$DismissedBefore)

    $state = [string]$Session.state
    $ts = [long]$Session.ts
    if ($state -in 'done', 'error', 'attention' -and $ts -le $DismissedBefore) { return 'idle' }
    # No hook fires when a permission is granted; new transcript output means work resumed.
    if ($state -eq 'attention' -and $TranscriptMtime -gt $ts + 1500) { return 'working' }
    # A closed terminal sends no SessionEnd, so a silent "working" session goes stale.
    if ($state -eq 'working' -and $Now - [math]::Max($ts, $TranscriptMtime) -gt 15 * 60 * 1000) { return 'idle' }
    return $state
}

# Loads UI strings for a language, falling back to English. Read as UTF-8 explicitly.
function Get-Strings {
    param([string]$Path, [string]$Language)
    $all = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($Language -and $all.PSObject.Properties[$Language]) { return $all.$Language }
    return $all.en
}

# Bubble text for a session in the active language.
function Format-Bubble {
    param($Session, $Strings)
    switch ([string]$Session.state) {
        'done' {
            $title = if ([long]$Session.took -gt 0) { $Strings.doneIn -f (Format-Duration ([long]$Session.took)) } else { $Strings.done }
            return @{ title = $title; detail = [string]$Session.detail }
        }
        'attention' {
            $detail = [string]$Session.detail
            if ($Session.tool) { $detail = $Strings.permission -f $Session.tool }
            elseif (-not $detail) { $detail = $Strings.permissionGeneric }
            return @{ title = $Strings.attention; detail = $detail }
        }
        'error' {
            $known = if ($Session.code) { $Strings.errors.PSObject.Properties[[string]$Session.code] } else { $null }
            $label = if ($known) { $known.Value } else { [string]$Session.code }
            $detail = (@($label, $Session.detail) | Where-Object { $_ }) -join ' - '
            return @{ title = $Strings.error; detail = $detail }
        }
    }
    return $null
}

function Format-Duration([long]$Ms) {
    $s = [long][math]::Floor($Ms / 1000)
    if ($s -lt 60) { return "${s}s" }
    if ($s -lt 3600) { return '{0}m {1}s' -f [math]::Floor($s / 60), ($s % 60) }
    return '{0}h {1}m' -f [math]::Floor($s / 3600), [math]::Floor(($s % 3600) / 60)
}

# Overlay drawn above the head while a tool runs, by tool family ('' = none).
function Get-ToolIcon([string]$Tool) {
    switch -Regex ($Tool) {
        '^(Edit|Write|MultiEdit|NotebookEdit)$' { return 'pencil' }
        '^(Bash|PowerShell)$' { return 'term' }
        '^(Read|Grep|Glob|LSP)$' { return 'lens' }
        '^(WebFetch|WebSearch)$' { return 'globe' }
    }
    return ''
}

# Prop standing next to the avatar on special dates ('' = none).
function Get-SeasonalProp([datetime]$Date) {
    $md = $Date.Month * 100 + $Date.Day
    if ($md -ge 1024 -and $md -le 1031) { return 'pumpkin' }   # Halloween week
    if ($md -ge 1201 -or $md -le 106) { return 'tree' }        # Christmas to Reyes
    if ($md -in 525, 620, 709) { return 'flag' }               # Argentine national days
    return ''
}

# Picks the session the avatar should represent: highest priority, then newest.
function Select-DisplaySession {
    param([object[]]$Sessions)
    $Sessions | Where-Object { $_ } |
        Sort-Object -Property @{ Expression = { $script:StatePriority[[string]$_.state] }; Descending = $true },
                              @{ Expression = { [long]$_.ts }; Descending = $true } |
        Select-Object -First 1
}
