@echo off
cd /d "C:\Users\Jtcra\ottawa_swim_finder\backend"
set PLAYWRIGHT_HEADLESS=true
node src\cli-weekly-sync.js >> logs\sync-weekly.log 2>&1
