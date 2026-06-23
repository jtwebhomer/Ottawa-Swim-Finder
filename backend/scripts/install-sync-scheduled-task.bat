@echo off
REM Install sync every 6 hours via schtasks (no admin usually required for current user)
set BACKEND=%~dp0..
set TASK=OttawaSwimFinderSync
schtasks /Delete /TN "%TASK%" /F 2>nul
schtasks /Create /TN "%TASK%" /TR "\"%BACKEND%\scripts\run-sync-task.bat\"" /SC HOURLY /MO 6 /F
if %ERRORLEVEL% NEQ 0 (
  echo Failed. Try running this batch file as Administrator.
  exit /b 1
)
echo Installed %TASK% — runs every 6 hours.
schtasks /Run /TN "%TASK%"
echo Triggered immediate sync run.
