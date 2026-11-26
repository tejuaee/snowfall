@echo off
rem Snowfall for Windows: falling snow over your desktop.
rem
rem   snow            start the snow (installs Electron on first run)
rem   snow stop       stop it
rem
rem Once it is running, everything else is in the snowflake icon in the taskbar tray.
setlocal
cd /d "%~dp0desktop"

where npm >nul 2>nul
if errorlevel 1 (
  echo Snowfall needs Node.js ^(with npm^): https://nodejs.org
  exit /b 1
)

if /i "%~1"=="stop" (
  if exist node_modules\electron\dist\electron.exe node_modules\electron\dist\electron.exe . --stop
  exit /b 0
)

if not exist node_modules\electron (
  echo Installing Electron ^(first run only^)...
  call npm install --no-fund --no-audit || exit /b 1
)

echo Let it snow. Use the snowflake in the taskbar tray for intensity, settings or quit.
rem Electron is a windowed program, so "start" detaches it: closing this console
rem does not stop the snow.
start "" node_modules\electron\dist\electron.exe .
