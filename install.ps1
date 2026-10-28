# Registers Clawd Buddy hooks in Claude Code and starts the avatar.
param(
    [string]$SettingsPath = (Join-Path $HOME '.claude\settings.json'),
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\settings.ps1')

$settings = Read-Settings $SettingsPath
if (Test-Path -LiteralPath $SettingsPath) {
    $backup = "$SettingsPath.clawd-buddy-$(Get-Date -Format yyyyMMdd-HHmmss).bak"
    Copy-Item -LiteralPath $SettingsPath -Destination $backup
    Write-Host "Backup: $backup"
}

Remove-BuddyHooks $settings
Add-BuddyHooks $settings (Join-Path $PSScriptRoot 'hook.ps1')
Write-Settings $settings $SettingsPath
Write-Host "Hooks installed in $SettingsPath (new Claude Code sessions pick them up)."

if (-not $NoLaunch) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Sta', '-File', "`"$(Join-Path $PSScriptRoot 'avatar.ps1')`""
    )
    Write-Host 'Avatar started.'
}
