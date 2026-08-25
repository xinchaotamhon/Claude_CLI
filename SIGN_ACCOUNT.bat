@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Account/API setup stays inside the project wrapper. It never launches Codex as a harness.
call "%~dp0RUN_CLAUDE.bat" --account-menu
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo [ERROR] Account/API setup did not finish successfully.
    pause
)
exit /b %EXIT_CODE%
