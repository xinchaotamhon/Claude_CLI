@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Compatibility shortcut only. DASHBOARD.bat is the single user-facing entry point.
call "%~dp0DASHBOARD.bat"
exit /b %ERRORLEVEL%
