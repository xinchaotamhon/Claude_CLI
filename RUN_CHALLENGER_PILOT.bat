@echo off
setlocal
cd /d "%~dp0"
title Claude CLI - Isolated Challenger Pilot

:menu
cls
echo ==============================================================
echo   CLAUDE CLI - ISOLATED CHALLENGER PILOT
echo   CCR remains the normal launcher: RUN_CLAUDE.bat
echo ==============================================================
echo.
echo   [1] Run offline protocol + isolation self-test
echo   [2] Show pilot status
echo   [3] Stop a verified pilot process
echo   [Q] Quit
echo.
choice /C 123Q /N /M "Select an action: "

if errorlevel 4 goto :eof
if errorlevel 3 set "PILOT_ACTION=Stop"& goto :run
if errorlevel 2 set "PILOT_ACTION=Status"& goto :run
if errorlevel 1 set "PILOT_ACTION=SelfTest"& goto :run

:run
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\challenger_pilot.ps1" -Action "%PILOT_ACTION%"
set "PILOT_EXIT=%ERRORLEVEL%"
echo.
if not "%PILOT_EXIT%"=="0" echo [ERROR] Pilot action failed with code %PILOT_EXIT%.
pause
goto :menu
