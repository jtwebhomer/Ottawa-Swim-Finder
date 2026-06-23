# Creates a desktop shortcut for the Ottawa Swim Finder Sync Dashboard.
$ErrorActionPreference = 'Stop'
$BackendDir = Split-Path $PSScriptRoot -Parent
$Launcher = Join-Path $BackendDir 'scripts\launch-dashboard.bat'
$Desktop = [Environment]::GetFolderPath('Desktop')
$ShortcutPath = Join-Path $Desktop 'Ottawa Swim Sync Dashboard.lnk'

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = $Launcher
$Shortcut.WorkingDirectory = $BackendDir
$Shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,109"
$Shortcut.Description = 'Ottawa Swim Finder — facility sync status dashboard'
$Shortcut.Save()

Write-Host "Desktop shortcut created:"
Write-Host $ShortcutPath
Write-Host ""
Write-Host "Requires the API server running on port 3000."
Write-Host "Open: http://127.0.0.1:3000/dashboard"
