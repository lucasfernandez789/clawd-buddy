# Self-check: powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\state.ps1')
. (Join-Path $root 'lib\sprites.ps1')
. (Join-Path $root 'lib\settings.ps1')

$script:failures = 0
function Assert([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { Write-Host "FAIL $Message"; $script:failures++ }
}

# Sprites: fixed 16x11 grid, only palette characters.
foreach ($name in $Frames.Keys) {
    $rows = $Frames[$name]
    $badRows = @($rows | Where-Object { $_.Length -ne 16 })
    $badChars = @(($rows -join '').ToCharArray() | Where-Object { $_ -ne '.' -and -not $Palette.ContainsKey([string]$_) })
    Assert ($rows.Count -eq 11 -and $badRows.Count -eq 0 -and $badChars.Count -eq 0) "sprite '$name' is a valid 16x11 frame"
}

foreach ($name in $Overlays.Keys) {
    $badChars = @(($Overlays[$name] -join '').ToCharArray() | Where-Object { $_ -ne '.' -and -not $Palette.ContainsKey([string]$_) })
    Assert ($badChars.Count -eq 0) "overlay '$name' uses palette colors only"
}

# Strings: every language has the same keys as English.
$stringsPath = Join-Path $root 'lib\strings.json'
$all = [IO.File]::ReadAllText($stringsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$keys = { param($o) ($o.PSObject.Properties | ForEach-Object {
    if ($_.Value -is [pscustomobject]) { $p = $_.Name; $_.Value.PSObject.Properties.Name | ForEach-Object { "$p.$_" } } else { $_.Name } }) | Sort-Object }
$enKeys = (& $keys $all.en) -join ','
foreach ($lang in $all.PSObject.Properties.Name) {
    Assert ((& $keys $all.$lang) -join ',' -eq $enKeys) "strings '$lang' match the English keys"
}
$es = Get-Strings $stringsPath 'es'
$en = Get-Strings $stringsPath 'xx'
Assert ($es.done -eq 'Listo' -and $en.done -eq 'Done') 'Spanish loads, unknown language falls back to English'
Assert ($es.states.done -eq ('termin' + [char]0x00F3)) 'accented text survives the UTF-8 read'

$b = Format-Bubble ([pscustomobject]@{ state = 'attention'; tool = 'Bash'; detail = '' }) $es
Assert ($b.title -eq 'Te necesita' -and $b.detail -eq 'Pide permiso: Bash') 'permission bubble is localized'
$b = Format-Bubble ([pscustomobject]@{ state = 'attention'; tool = ''; detail = 'Claude needs input' }) $es
Assert ($b.detail -eq 'Claude needs input') 'notification text is kept as sent'
$b = Format-Bubble ([pscustomobject]@{ state = 'error'; code = 'rate_limit'; detail = '429' }) $es
Assert ($b.detail -eq ('Se alcanz' + [char]0x00F3 + ' el l' + [char]0x00ED + 'mite de uso - 429')) 'known error code is translated'
$b = Format-Bubble ([pscustomobject]@{ state = 'error'; code = 'weird_new_code'; detail = '' }) $es
Assert ($b.detail -eq 'weird_new_code') 'unknown error code is shown raw'

# Event mapping.
$ev = { param($h) [pscustomobject]$h }
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'UserPromptSubmit'; cwd = 'C:\repos\api' }) $null 100
Assert ($s.state -eq 'working' -and $s.project -eq 'api') 'UserPromptSubmit -> working with project name'
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'Stop'; last_assistant_message = "## Summary`n**Fixed** the bug" }) $null 100
Assert ($s.state -eq 'done' -and $s.detail -eq 'Summary') 'Stop -> done with first clean line'
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'StopFailure'; error = 'rate_limit'; error_details = '429' }) $null 100
Assert ($s.state -eq 'error' -and $s.code -eq 'rate_limit' -and $s.detail -eq '429') 'StopFailure -> error with code and details'
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'PermissionRequest'; tool_name = 'Bash' }) $null 100
Assert ($s.state -eq 'attention' -and $s.tool -eq 'Bash') 'PermissionRequest -> attention with tool'
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'Notification'; notification_type = 'idle_prompt' }) $null 100
Assert ($null -eq $s) 'idle_prompt notification is ignored'
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'Notification'; notification_type = 'permission_prompt'; message = 'x' }) ([pscustomobject]@{ state = 'attention' }) 100
Assert ($null -eq $s) 'late permission notification does not duplicate attention'
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'SessionStart' }) ([pscustomobject]@{ state = 'working' }) 100
Assert ($null -eq $s) 'repeated SessionStart keeps the live state'
Assert ((Get-FirstLine ('a' * 200)).Length -eq 90) 'long detail is truncated'

# Turn duration: 'started' survives a permission prompt and Stop reports the elapsed time.
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'UserPromptSubmit' }) $null 1000
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'PermissionRequest'; tool_name = 'Bash' }) ([pscustomobject]$s) 5000
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'Stop'; last_assistant_message = 'ok' }) ([pscustomobject]$s) 193000
Assert ($s.took -eq 192000) 'Stop measures the turn from UserPromptSubmit, across a permission prompt'
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'Stop' }) $null 100
Assert ($s.took -eq 0) 'Stop without a known start has no duration'
Assert ((Format-Duration 42000) -eq '42s' -and (Format-Duration 192000) -eq '3m 12s' -and (Format-Duration 3900000) -eq '1h 5m') 'durations read as s, m s, h m'
$b = Format-Bubble ([pscustomobject]@{ state = 'done'; took = 192000; detail = 'x' }) $es
Assert ($b.title -eq 'Listo en 3m 12s') 'done bubble shows the duration'
$b = Format-Bubble ([pscustomobject]@{ state = 'done'; took = 0; detail = 'x' }) $es
Assert ($b.title -eq 'Listo') 'done bubble without duration keeps the plain title'

Assert ((Get-ToolIcon 'Edit') -eq 'pencil' -and (Get-ToolIcon 'Bash') -eq 'term' -and (Get-ToolIcon 'Grep') -eq 'lens' -and (Get-ToolIcon 'WebSearch') -eq 'globe') 'tool families map to icons'
Assert ((Get-ToolIcon 'Agent') -eq '' -and (Get-ToolIcon '') -eq '') 'other tools have no icon'
foreach ($icon in 'pencil', 'term', 'lens', 'globe', 'mini', 'pumpkin', 'tree', 'flag', 'press1', 'press2', 'press3') {
    Assert ($Overlays.ContainsKey($icon)) "overlay '$icon' exists"
}
Assert ((Get-SeasonalProp ([datetime]'2026-10-31')) -eq 'pumpkin' -and (Get-SeasonalProp ([datetime]'2026-10-23')) -eq '') 'pumpkin only in Halloween week'
Assert ((Get-SeasonalProp ([datetime]'2026-12-24')) -eq 'tree' -and (Get-SeasonalProp ([datetime]'2027-01-06')) -eq 'tree' -and (Get-SeasonalProp ([datetime]'2027-01-07')) -eq '') 'tree from December to Reyes'
Assert ((Get-SeasonalProp ([datetime]'2026-07-09')) -eq 'flag' -and (Get-SeasonalProp ([datetime]'2026-03-15')) -eq '') 'flag on national days, nothing on a plain day'

# Effective state.
$sess = { param($st, $ts) [pscustomobject]@{ state = $st; ts = $ts } }
Assert ((Get-EffectiveState (& $sess 'done' 100) 0 200 150) -eq 'idle') 'dismissed alert becomes idle'
Assert ((Get-EffectiveState (& $sess 'done' 200) 0 300 150) -eq 'done') 'new alert after dismiss stays'
Assert ((Get-EffectiveState (& $sess 'attention' 1000) 5000 6000 0) -eq 'working') 'transcript activity resolves attention'
Assert ((Get-EffectiveState (& $sess 'working' 0) 0 (16 * 60 * 1000) 0) -eq 'idle') 'silent working session goes stale'
Assert ((Get-EffectiveState (& $sess 'working' 0) 0 (60 * 1000) 0) -eq 'working') 'recent working session stays working'

$pick = Select-DisplaySession @(
    [pscustomobject]@{ state = 'working'; ts = 9 }, [pscustomobject]@{ state = 'attention'; ts = 1 },
    [pscustomobject]@{ state = 'done'; ts = 5 })
Assert ($pick.state -eq 'attention') 'attention outranks done and working'

# Settings merge: keeps foreign hooks, idempotent, uninstall restores.
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("clawd-buddy-test-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $settingsPath = Join-Path $tmp 'settings.json'
    $original = '{"model":"opus","hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"codegraph.cmd prompt-hook"}]}]},"note":"it''s <ok> & fine"}'
    [IO.File]::WriteAllText($settingsPath, $original)

    foreach ($i in 1, 2) {
        $cfg = Read-Settings $settingsPath; Remove-BuddyHooks $cfg; Add-BuddyHooks $cfg 'C:\x\hook.ps1'; Write-Settings $cfg $settingsPath
    }
    $cfg = Read-Settings $settingsPath
    Assert (@($cfg.hooks.UserPromptSubmit).Count -eq 2) 'install twice adds one group next to the foreign hook'
    Assert (@($cfg.hooks.PSObject.Properties).Count -eq 12) 'all twelve events registered'
    Assert ($cfg.hooks.UserPromptSubmit[0].hooks[0].command -eq 'codegraph.cmd prompt-hook') 'foreign hook preserved first'
    Assert ($cfg.hooks.Stop[0].hooks[0].async -eq $true) 'buddy hooks are async'
    $text = [IO.File]::ReadAllText($settingsPath)
    Assert ($text.Contains("it's <ok> & fine")) 'writer keeps quotes and <>& unescaped'

    Remove-BuddyHooks $cfg; Write-Settings $cfg $settingsPath
    $cfg = Read-Settings $settingsPath
    Assert (@($cfg.hooks.PSObject.Properties.Name) -join ',' -eq 'UserPromptSubmit') 'uninstall leaves only foreign hooks'
    Assert ($cfg.model -eq 'opus' -and $cfg.note -eq "it's <ok> & fine") 'other settings untouched'

    # Hook end to end, through a real process and stdin.
    $stateDir = Join-Path $tmp 'state'
    $hook = Join-Path $root 'hook.ps1'
    $payload = '{"session_id":"abc-1","hook_event_name":"UserPromptSubmit","cwd":"C:\\repos\\api","transcript_path":"","prompt":"hola \u00f1and\u00fa"}'
    $output = $payload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hook -StateDir $stateDir
    $file = Join-Path $stateDir 'sessions\abc-1.json'
    Assert ($LASTEXITCODE -eq 0 -and -not $output) 'hook exits 0 and prints nothing'
    Assert ((Test-Path $file) -and ((Get-Content $file -Raw | ConvertFrom-Json).state -eq 'working')) 'hook writes the session state'
    $side = Join-Path $stateDir 'sessions\abc-1'
    $runHook = { param($json) $json | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hook -StateDir $stateDir }
    & $runHook '{"session_id":"abc-1","hook_event_name":"PreToolUse","tool_name":"Edit"}'
    Assert ((Get-Content "$side.tool" -Raw) -eq 'Edit') 'PreToolUse records the running tool'
    Assert ((Get-Content $file -Raw | ConvertFrom-Json).state -eq 'working') 'PreToolUse leaves the session state alone'
    & $runHook '{"session_id":"abc-1","hook_event_name":"SubagentStart","agent_id":"ag-1"}'
    & $runHook '{"session_id":"abc-1","hook_event_name":"SubagentStart","agent_id":"ag-2"}'
    & $runHook '{"session_id":"abc-1","hook_event_name":"SubagentStop","agent_id":"ag-1"}'
    Assert ((@(Get-ChildItem "$side.agents" -File).Name -join ',') -eq 'ag-2') 'subagent markers follow start and stop'
    & $runHook '{"session_id":"abc-1","hook_event_name":"PreCompact"}'
    Assert (Test-Path "$side.compact") 'PreCompact marks the session as compacting'
    & $runHook '{"session_id":"abc-1","hook_event_name":"PostCompact"}'
    Assert (-not (Test-Path "$side.compact")) 'PostCompact clears the mark'
    & $runHook '{"session_id":"abc-1","hook_event_name":"PreCompact"}'
    & $runHook '{"session_id":"abc-1","hook_event_name":"SessionEnd"}'
    Assert (-not (Test-Path $file)) 'SessionEnd removes the session'
    Assert (-not (Test-Path "$side.tool") -and -not (Test-Path "$side.agents") -and -not (Test-Path "$side.compact")) 'SessionEnd removes the side files'
    'not json' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hook -StateDir $stateDir
    Assert ($LASTEXITCODE -eq 0) 'bad input still exits 0'

    # Avatar renders every state and scene without throwing.
    $result = powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File (Join-Path $root 'avatar.ps1') -StateDir $stateDir -SelfTest
    Assert ($LASTEXITCODE -eq 0) "avatar renders every state and scene ($result)"
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failures) { Write-Host "$script:failures failure(s)"; exit 1 }
Write-Host 'all passed'
