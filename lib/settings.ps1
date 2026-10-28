# Merges Clawd Buddy hooks into Claude Code settings.json without touching other entries.

$script:BuddyTag = 'clawd-buddy'
$script:BuddyEvents = [ordered]@{
    SessionStart      = $null
    SessionEnd        = $null
    UserPromptSubmit  = $null
    Stop              = $null
    StopFailure       = $null
    PermissionRequest = $null
    Notification      = 'permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input'
}

function Read-Settings([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{} }
    $text = [IO.File]::ReadAllText($Path)
    if (-not $text.Trim()) { return [pscustomobject]@{} }
    return $text | ConvertFrom-Json
}

function Test-BuddyHandler($Handler) {
    return (@($Handler.args) -contains $script:BuddyTag)
}

function Remove-BuddyHooks($Settings) {
    if (-not $Settings.hooks) { return }
    foreach ($eventName in @($Settings.hooks.PSObject.Properties.Name)) {
        $groups = @()
        foreach ($group in @($Settings.hooks.$eventName)) {
            $kept = @(@($group.hooks) | Where-Object { -not (Test-BuddyHandler $_) })
            if ($kept.Count -eq @($group.hooks).Count) { $groups += $group; continue }
            if ($kept.Count) { $group.hooks = $kept; $groups += $group }
        }
        if ($groups.Count) { $Settings.hooks.$eventName = $groups }
        else { $Settings.hooks.PSObject.Properties.Remove($eventName) }
    }
}

function Add-BuddyHooks($Settings, [string]$HookScript) {
    if (-not $Settings.hooks) {
        $Settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    foreach ($eventName in $script:BuddyEvents.Keys) {
        # Exec form (command + args) skips the wrapper shell; async keeps Claude Code unblocked.
        $handler = [pscustomobject][ordered]@{
            type    = 'command'
            command = 'powershell.exe'
            args    = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $HookScript, '-Tag', $script:BuddyTag)
            async   = $true
            timeout = 10
        }
        $group = [pscustomobject][ordered]@{}
        if ($script:BuddyEvents[$eventName]) { $group | Add-Member -NotePropertyName matcher -NotePropertyValue $script:BuddyEvents[$eventName] }
        $group | Add-Member -NotePropertyName hooks -NotePropertyValue @($handler)

        $existing = @()
        if ($Settings.hooks.PSObject.Properties[$eventName]) { $existing = @($Settings.hooks.$eventName) }
        $Settings.hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue (@($existing) + $group) -Force
    }
}

# Windows PowerShell 5.1 emits odd indentation and escapes quotes/<>&; re-indent and unescape.
function Format-Json([string]$Json) {
    $Json = [regex]::Replace($Json, '(?<!\\)((?:\\\\)*)\\u00(27|3c|3e|26)', {
        param($m) $m.Groups[1].Value + [char][Convert]::ToInt32($m.Groups[2].Value, 16)
    })
    $out = New-Object System.Text.StringBuilder
    $indent = 0; $inString = $false; $escaped = $false
    foreach ($ch in $Json.ToCharArray()) {
        if ($inString) {
            [void]$out.Append($ch)
            if ($escaped) { $escaped = $false } elseif ($ch -eq '\') { $escaped = $true } elseif ($ch -eq '"') { $inString = $false }
            continue
        }
        switch -CaseSensitive ($ch) {
            '"' { $inString = $true; [void]$out.Append($ch) }
            { $_ -eq '{' -or $_ -eq '[' } { $indent++; [void]$out.Append($ch).Append("`n").Append('  ' * $indent) }
            { $_ -eq '}' -or $_ -eq ']' } { $indent--; [void]$out.Append("`n").Append('  ' * $indent).Append($ch) }
            ',' { [void]$out.Append(",`n").Append('  ' * $indent) }
            ':' { [void]$out.Append(': ') }
            { [char]::IsWhiteSpace($_) } { }
            default { [void]$out.Append($ch) }
        }
    }
    # Collapse empty containers produced by the re-indent.
    return [regex]::Replace($out.ToString(), '([\[{])\s+([\]}])', '$1$2')
}

function Write-Settings($Settings, [string]$Path) {
    $json = Format-Json (ConvertTo-Json -InputObject $Settings -Depth 64 -Compress)
    [IO.File]::WriteAllText($Path, $json + "`n", (New-Object System.Text.UTF8Encoding $false))
}
