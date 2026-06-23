# Installs Windows Scheduled Tasks:
#   OttawaSwimFinderWeeklySync  — full scrape every 7 days
#   OttawaSwimFinderRepairSync    — retry incomplete facilities every 30 minutes

$ErrorActionPreference = 'Stop'
$BackendDir = Split-Path $PSScriptRoot -Parent
$NodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $NodeExe) { throw 'Node.js not found on PATH' }

$LogDir = Join-Path $BackendDir 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$WeeklyWrapper = Join-Path $BackendDir 'scripts\run-weekly-sync-task.bat'
@"
@echo off
cd /d "$BackendDir"
set PLAYWRIGHT_HEADLESS=true
node src\cli-weekly-sync.js >> logs\sync-weekly.log 2>&1
"@ | Set-Content -Path $WeeklyWrapper -Encoding ASCII

$RepairWrapper = Join-Path $BackendDir 'scripts\run-repair-sync-task.bat'
@"
@echo off
cd /d "$BackendDir"
set PLAYWRIGHT_HEADLESS=true
node src\cli-repair-sync.js >> logs\sync-repair.log 2>&1
"@ | Set-Content -Path $RepairWrapper -Encoding ASCII

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 2 `
    -RestartInterval (New-TimeSpan -Minutes 10) `
    -ExecutionTimeLimit (New-TimeSpan -Hours 6)

$Principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Limited

# Weekly full sync
$WeeklyTask = 'OttawaSwimFinderWeeklySync'
$WeeklyStart = (Get-Date).AddMinutes(5)
$WeeklyTrigger = New-ScheduledTaskTrigger `
    -Once `
    -At $WeeklyStart `
    -RepetitionInterval (New-TimeSpan -Days 7) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

Register-ScheduledTask `
    -TaskName $WeeklyTask `
    -Action (New-ScheduledTaskAction -Execute $WeeklyWrapper -WorkingDirectory $BackendDir) `
    -Trigger $WeeklyTrigger `
    -Settings $Settings `
    -Principal $Principal `
    -Description 'Ottawa Swim Finder weekly full Playwright scrape (all facilities)' `
    -Force | Out-Null

# 30-minute repair loop
$RepairTask = 'OttawaSwimFinderRepairSync'
$RepairStart = (Get-Date).AddMinutes(2)
$RepairTrigger = New-ScheduledTaskTrigger `
    -Once `
    -At $RepairStart `
    -RepetitionInterval (New-TimeSpan -Minutes 30) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

Register-ScheduledTask `
    -TaskName $RepairTask `
    -Action (New-ScheduledTaskAction -Execute $RepairWrapper -WorkingDirectory $BackendDir) `
    -Trigger $RepairTrigger `
    -Settings (New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 45)) `
    -Principal $Principal `
    -Description 'Ottawa Swim Finder repair sync (blocked/incomplete facilities only)' `
    -Force | Out-Null

# Remove legacy 6-hour task if present
Unregister-ScheduledTask -TaskName 'OttawaSwimFinderSync' -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "Installed: $WeeklyTask (every 7 days, first at $WeeklyStart)"
Write-Host "Installed: $RepairTask (every 30 minutes, first at $RepairStart)"
Write-Host "Logs: $LogDir\sync-weekly.log, sync-repair.log"
