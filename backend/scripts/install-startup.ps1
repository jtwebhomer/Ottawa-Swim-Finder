# Adds API server to Windows Startup folder (no admin required).
$ErrorActionPreference = 'Stop'
$Startup = [Environment]::GetFolderPath('Startup')
$BackendDir = Split-Path $PSScriptRoot -Parent
$Launcher = Join-Path $BackendDir 'scripts\start-server-hidden.bat'
$LinkPath = Join-Path $Startup 'OttawaSwimFinderAPI.bat'

Copy-Item -Path $Launcher -Destination $LinkPath -Force
Write-Host "Startup launcher installed: $LinkPath"
Write-Host "Server will start automatically when you log in to Windows."
