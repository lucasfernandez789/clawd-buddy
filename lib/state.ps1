# State logic shared by hook.ps1 and avatar.ps1. Pure (so it is testable), except Remove-SessionFiles.
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

# How the avatar celebrates a finished turn: 'question' (the answer ends asking something),
# 'trouble' (it says it could not finish), 'big' (10+ minutes), 'quick' (under 15 s) or ''.
# Patterns are narrow and accent-free on purpose: "fixed the error" must not read as trouble.
function Get-DoneMood {
    param([string]$Message, [long]$Took)
    $lines = @($Message -split "`r?`n" | ForEach-Object { ($_ -replace '[#*`>_]', '').Trim() } | Where-Object { $_ })
    if ($lines.Count -and $lines[-1].EndsWith('?')) { return 'question' }
    # Only the opening line counts: a caveat further down a successful answer is not trouble.
    if ($lines.Count -and $lines[0] -match "\b(couldn.t|could not|unable to|still fail|no pude|no se pudo|no logr|siguen? fallando)") { return 'trouble' }
    if ($Took -ge 10 * 60 * 1000) { return 'big' }
    if ($Took -gt 0 -and $Took -lt 15000) { return 'quick' }
    return ''
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
            $message = [string]$HookEvent.last_assistant_message
            return $base + @{ state = 'done'; detail = Get-FirstLine $message; took = $took; mood = Get-DoneMood $message $took }
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

# A closed terminal sends no SessionEnd: a session silent for a day is forgotten.
# shortcut: a prompt left pending for over 24 h is dropped too; exempt 'attention' if that bites.
function Test-SessionAbandoned {
    param($Session, [long]$TranscriptMtime, [long]$Now)
    return $Now - [math]::Max([long]$Session.ts, $TranscriptMtime) -gt 24 * 60 * 60 * 1000
}

# $Side is the session path without extension: the state file and its side files hang off it.
function Remove-SessionFiles([string]$Side) {
    Remove-Item -LiteralPath "$Side.json", "$Side.tool", "$Side.compact" -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "$Side.agents" -Recurse -Force -ErrorAction SilentlyContinue
}

# Saved bottom-right corner, or $null when it is missing or off the current screens (monitor unplugged).
function Get-SavedAnchor {
    param($Prefs, [double]$Left, [double]$Top, [double]$Width, [double]$Height)
    if (-not $Prefs -or $null -eq $Prefs.right -or $null -eq $Prefs.bottom) { return $null }
    $right = [double]$Prefs.right; $bottom = [double]$Prefs.bottom
    if ($right -lt $Left + 60 -or $right -gt $Left + $Width -or $bottom -lt $Top + 60 -or $bottom -gt $Top + $Height) { return $null }
    return @{ right = $right; bottom = $bottom }
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

# Argentine dates, keyed by month*100+day: prop drawn at the feet and the strings.json 'days' key.
$script:SpecialDays = @{
    324  = @('scarf', 'memory')        # Dia de la Memoria
    402  = @('flag', 'malvinas')       # Veteranos y Caidos en Malvinas
    525  = @('flag', 'may25')          # Revolucion de Mayo
    620  = @('flag', 'flagDay')        # Dia de la Bandera
    709  = @('flag', 'independence')   # Dia de la Independencia
    720  = @('heart', 'friendship')    # Dia del Amigo
    817  = @('flag', 'sanMartin')      # Paso a la inmortalidad de San Martin
    911  = @('apple', 'teachers')      # Dia del Maestro
    921  = @('flower', 'spring')       # Dia de la Primavera y del Estudiante
    1031 = @('pumpkin', 'halloween')
    1110 = @('mate', 'tradition')      # Dia de la Tradicion
    1120 = @('flag', 'sovereignty')    # Dia de la Soberania Nacional
    1130 = @('mate', 'mateDay')        # Dia Nacional del Mate
    1218 = @('trophy', 'worldCup')     # Final del Mundial 2022
    1225 = @('tree', 'christmas')
}

# What stands next to the avatar today: @{ prop; day } (day = '' for a plain season), or $null.
function Get-SeasonalProp([datetime]$Date) {
    $md = $Date.Month * 100 + $Date.Day
    $special = $script:SpecialDays[$md]
    if ($special) { return @{ prop = $special[0]; day = $special[1] } }
    if ($Date.DayOfYear -eq 256) { return @{ prop = 'code'; day = 'programmers' } }   # Dia del Programador
    if ($Date.Day -eq 29) { return @{ prop = 'gnocchi'; day = 'gnocchi' } }           # noquis del 29
    if ($md -ge 1024 -and $md -le 1030) { return @{ prop = 'pumpkin'; day = '' } }    # Halloween week
    if ($md -ge 1208 -or $md -le 106) { return @{ prop = 'tree'; day = '' } }         # arbolito: Dec 8 to Reyes
    return $null
}

# Picks the session the avatar should represent: highest priority, then newest.
function Select-DisplaySession {
    param([object[]]$Sessions)
    $Sessions | Where-Object { $_ } |
        Sort-Object -Property @{ Expression = { $script:StatePriority[[string]$_.state] }; Descending = $true },
                              @{ Expression = { [long]$_.ts }; Descending = $true } |
        Select-Object -First 1
}
