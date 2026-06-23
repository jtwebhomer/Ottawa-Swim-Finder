@echo off
cd /d "C:\Users\Jtcra\ottawa_swim_finder\backend"
start "" /B node src\index.js >> logs\server.log 2>&1
