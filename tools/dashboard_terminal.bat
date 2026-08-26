@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ROOT=%~dp0.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PS_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"

if /I "%~1"=="launch" goto LAUNCH
if /I "%~1"=="codex" goto CODEX
if /I "%~1"=="codex-resume" goto CODEX_RESUME
if /I "%~1"=="google" goto GOOGLE
echo [ERROR] Unknown dashboard terminal action.
exit /b 2

:LAUNCH
title Claude CLI - %~2
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\router_project_menu.ps1" -Root "%ROOT%" -LaunchProfileId "%~2"
exit /b %ERRORLEVEL%

:CODEX
title Claude CLI - Codex account sign-in
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\router_project_menu.ps1" -Root "%ROOT%" -AddCodexPlan "%~2"
set "EXIT_CODE=%ERRORLEVEL%"
goto DONE

:CODEX_RESUME
title Claude CLI - Finish Codex account import
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\router_project_menu.ps1" -Root "%ROOT%" -AddCodexPlan "%~2" -CodexAccountName "%~3"
set "EXIT_CODE=%ERRORLEVEL%"
goto DONE

:GOOGLE
title Claude CLI - Google account sign-in
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\challenger_account_menu.ps1" -Root "%ROOT%" -AddSlot "%~2"
set "EXIT_CODE=%ERRORLEVEL%"

:DONE
echo.
if "%EXIT_CODE%"=="0" (
    echo [OK] Action finished. This window will close.
    timeout /t 2 /nobreak >nul
) else (
    echo [ERROR] Action finished with code %EXIT_CODE%.
    echo The window stays open so you can read the error.
    pause
)
exit /b %EXIT_CODE%
