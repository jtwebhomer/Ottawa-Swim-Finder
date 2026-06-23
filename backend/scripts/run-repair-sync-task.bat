@echo off
cd /d "C:\Users\Jtcra\ottawa_swim_finder\backend"
set PLAYWRIGHT_HEADLESS=true
node src\cli-repair-sync.js >> logs\sync-repair.log 2>&1
