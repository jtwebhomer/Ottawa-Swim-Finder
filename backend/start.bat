@echo off
REM Start Ottawa Swim Finder API on Windows
cd /d "%~dp0"
if not exist .env (
  echo Copy .env.example to .env and set API_KEY first.
  copy .env.example .env
  exit /b 1
)
node src/index.js
