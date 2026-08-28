@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PS_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"

if not exist "%PS_EXE%" (
    echo [ERROR] PowerShell is missing: "%PS_EXE%"
    pause
    exit /b 1
)

rem Detach the project-local starter so the Explorer/Windows Terminal console
rem can close immediately. The starter owns readiness checks and opens the
rem project-local startup log in Notepad only when detached startup fails.
start "" "%PS_EXE%" -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%ROOT%\tools\start_dashboard.ps1" -Root "%ROOT%" -Detached
set "START_CODE=%ERRORLEVEL%"
if not "%START_CODE%"=="0" (
    echo [ERROR] Dashboard starter could not be detached. Code %START_CODE%.
    pause
)
exit /b %START_CODE%
