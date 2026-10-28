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
    $base = @{ project = $project; transcript = [string]$HookEvent.transcript_path; ts = $Now }

    switch ([string]$HookEvent.hook_event_name) {
        # SessionStart repeats on resume/clear/compact: never reset a live session.
        'SessionStart' {
            if ($Previous) { return $null }
            return $base + @{ state = 'idle'; detail = '' }
        }
        'UserPromptSubmit' { return $base + @{ state = 'working'; detail = '' } }
        'Stop' { return $base + @{ state = 'done'; detail = Get-FirstLine $HookEvent.last_assistant_message } }
        'StopFailure' {
            $detail = (@($HookEvent.error, $HookEvent.error_details) | Where-Object { $_ }) -join ': '
            return $base + @{ state = 'error'; detail = $detail }
        }
        'PermissionRequest' {
            $detail = 'Needs your permission'
            if ($HookEvent.tool_name) { $detail = "Needs permission: $($HookEvent.tool_name)" }
            return $base + @{ state = 'attention'; detail = $detail }
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

# Picks the session the avatar should represent: highest priority, then newest.
function Select-DisplaySession {
    param([object[]]$Sessions)
    $Sessions | Where-Object { $_ } |
        Sort-Object -Property @{ Expression = { $script:StatePriority[[string]$_.state] }; Descending = $true },
                              @{ Expression = { [long]$_.ts }; Descending = $true } |
        Select-Object -First 1
}
