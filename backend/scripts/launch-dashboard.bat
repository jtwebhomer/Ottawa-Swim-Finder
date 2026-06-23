@echo off
REM Launch Ottawa Swim Finder Sync Dashboard in app window
set PORT=3000
if exist "%~dp0..\.env" (
  for /f "tokens=2 delims==" %%a in ('findstr /B "PORT=" "%~dp0..\.env"') do set PORT=%%a
)
set URL=http://127.0.0.1:%PORT%/dashboard

where msedge >nul 2>&1 && (
  start "" msedge --app=%URL% --window-size=1280,900
  exit /b 0
)
where chrome >nul 2>&1 && (
  start "" chrome --app=%URL% --window-size=1280,900
  exit /b 0
)
start "" %URL%
