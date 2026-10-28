# Removes only Clawd Buddy hooks from Claude Code settings and stops the avatar.
param([string]$SettingsPath = (Join-Path $HOME '.claude\settings.json'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\settings.ps1')

if (Test-Path -LiteralPath $SettingsPath) {
    $settings = Read-Settings $SettingsPath
    Remove-BuddyHooks $settings
    Write-Settings $settings $SettingsPath
    Write-Host "Hooks removed from $SettingsPath."
}

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*clawd-buddy*avatar.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Host 'Avatar stopped.'
