@echo off
cd /d "C:\Users\Jtcra\ottawa_swim_finder\backend"
set PLAYWRIGHT_HEADLESS=true
node src\cli-sync.js >> logs\sync-scheduled.log 2>&1
