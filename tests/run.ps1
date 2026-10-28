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

# Event mapping.
$ev = { param($h) [pscustomobject]$h }
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'UserPromptSubmit'; cwd = 'C:\repos\api' }) $null 100
Assert ($s.state -eq 'working' -and $s.project -eq 'api') 'UserPromptSubmit -> working with project name'
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'Stop'; last_assistant_message = "## Summary`n**Fixed** the bug" }) $null 100
Assert ($s.state -eq 'done' -and $s.detail -eq 'Summary') 'Stop -> done with first clean line'
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'StopFailure'; error = 'rate_limit'; error_details = '429' }) $null 100
Assert ($s.state -eq 'error' -and $s.detail -eq 'rate_limit: 429') 'StopFailure -> error with details'
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'PermissionRequest'; tool_name = 'Bash' }) $null 100
Assert ($s.state -eq 'attention' -and $s.detail -eq 'Needs permission: Bash') 'PermissionRequest -> attention'
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'Notification'; notification_type = 'idle_prompt' }) $null 100
Assert ($null -eq $s) 'idle_prompt notification is ignored'
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'Notification'; notification_type = 'permission_prompt'; message = 'x' }) ([pscustomobject]@{ state = 'attention' }) 100
Assert ($null -eq $s) 'late permission notification does not duplicate attention'
$s = ConvertTo-SessionState (& $ev @{ hook_event_name = 'SessionStart' }) ([pscustomobject]@{ state = 'working' }) 100
Assert ($null -eq $s) 'repeated SessionStart keeps the live state'
Assert ((Get-FirstLine ('a' * 200)).Length -eq 90) 'long detail is truncated'

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
    Assert (@($cfg.hooks.PSObject.Properties).Count -eq 7) 'all seven events registered'
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
    '{"session_id":"abc-1","hook_event_name":"SessionEnd"}' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hook -StateDir $stateDir
    Assert (-not (Test-Path $file)) 'SessionEnd removes the session'
    'not json' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hook -StateDir $stateDir
    Assert ($LASTEXITCODE -eq 0) 'bad input still exits 0'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failures) { Write-Host "$script:failures failure(s)"; exit 1 }
Write-Host 'all passed'
