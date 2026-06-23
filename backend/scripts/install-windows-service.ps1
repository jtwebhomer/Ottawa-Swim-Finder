# Installs Ottawa Swim Finder API as a Windows Scheduled Task (runs at logon, restarts on failure).

param(
    [switch]$AtBoot
)

$ErrorActionPreference = 'Stop'
$BackendDir = Split-Path $PSScriptRoot -Parent
$NodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $NodeExe) { throw 'Node.js not found on PATH' }
if (-not (Test-Path (Join-Path $BackendDir 'src\index.js'))) {
    throw "Backend not found at $BackendDir"
}

$TaskName = 'OttawaSwimFinderAPI'
$LogDir = Join-Path $BackendDir 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Action = New-ScheduledTaskAction `
    -Execute $NodeExe `
    -Argument 'src\index.js' `
    -WorkingDirectory $BackendDir

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Days 3650)

if ($AtBoot) {
    $Principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $Trigger = New-ScheduledTaskTrigger -AtStartup
} else {
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Principal $Principal `
    -Description 'Ottawa Swim Finder schedule API (Node.js + Playwright)' `
    -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName
Write-Host "Installed and started scheduled task: $TaskName"
Write-Host "Backend directory: $BackendDir"
