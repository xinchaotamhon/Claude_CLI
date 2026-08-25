@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Resolve everything from this file so Explorer double-click is deterministic.
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "CLAUDE_BIN=%ROOT%\bin\claude.exe"
set "ROUTER_ROOT=%ROOT%\provider_router"
set "ROUTER_NODE=%ROUTER_ROOT%\runtime\node.exe"
set "ROUTER_ENTRY=%ROUTER_ROOT%\node_modules\@musistudio\claude-code-router\dist\main\cli.js"
set "ROUTER_PACKAGE=%ROUTER_ROOT%\node_modules\@musistudio\claude-code-router\package.json"
set "ROUTER_HOME=%ROUTER_ROOT%\.ccr-local"
set "CLAUDE_CODE_TMPDIR=%ROOT%\.tmp"
set "DISABLE_AUTOUPDATER=1"
set "CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1"
set "CCR_INTERNAL_HOME_DIR=%ROUTER_HOME%\home"
set "CCR_INTERNAL_APP_DATA_DIR=%ROUTER_HOME%\appdata"
set "CCR_INTERNAL_USER_DATA_DIR=%ROUTER_HOME%\userdata"
set "CCR_WEB_HOST=127.0.0.1"
set "CCR_WEB_PORT=3458"
set "CCR_PROVIDER_GATEWAY_ONLY=1"
set "CCR_GATEWAY_CONFIG_ACCEPTANCE_TIMEOUT_MS=20000"
set "PATH=%ROOT%\bin;%ROUTER_ROOT%\runtime;%PATH%"

if not exist "%ROUTER_HOME%" md "%ROUTER_HOME%" >nul 2>&1
if not exist "%ROOT%\.tmp" md "%ROOT%\.tmp" >nul 2>&1

if /I "%~1"=="--new-window" (
    start "Claude CLI Multi-Provider" "%ComSpec%" /d /k call "%~f0" --child
    exit /b 0
)
if /I "%~1"=="--child" shift

set "NO_PAUSE=0"
if /I "%~1"=="--version" set "NO_PAUSE=1"
if /I "%~1"=="--router-version" set "NO_PAUSE=1"
if /I "%~1"=="--check-updates" set "NO_PAUSE=1"
if /I "%~1"=="--fetch-router-source" set "NO_PAUSE=1"
if /I "%~1"=="--install-router" set "NO_PAUSE=1"
if /I "%~1"=="--router-stop" set "NO_PAUSE=1"
if /I "%~1"=="--account-menu" set "NO_PAUSE=1"

set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PS_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not exist "%PS_EXE%" (
    echo [ERROR] PowerShell was not found.
    if "%NO_PAUSE%"=="0" pause
    exit /b 9008
)

if not exist "%CLAUDE_BIN%" (
    echo [ERROR] Claude Code local binary was not found:
    echo         "%CLAUDE_BIN%"
    if "%NO_PAUSE%"=="0" pause
    exit /b 9009
)

pushd "%ROOT%" >nul

if /I "%~1"=="--install-router" goto INSTALL_ROUTER

if not exist "%ROUTER_NODE%" (
    echo [ERROR] Project-local router runtime is missing.
    echo Run: RUN_CLAUDE.bat --install-router
    set "EXIT_CODE=9011"
    goto AFTER_RUN
)
if not exist "%ROUTER_ENTRY%" (
    echo [ERROR] Pinned Claude Code Router package is missing.
    echo Run: RUN_CLAUDE.bat --install-router
    set "EXIT_CODE=9012"
    goto AFTER_RUN
)

if /I "%~1"=="--version" goto DIRECT_CLAUDE
if /I "%~1"=="--router-version" goto ROUTER_VERSION
if /I "%~1"=="--check-updates" goto CHECK_UPDATES
if /I "%~1"=="--fetch-router-source" goto FETCH_ROUTER_SOURCE
if /I "%~1"=="--account-menu" goto ACCOUNT_MENU
if /I "%~1"=="--router-stop" goto ROUTER_STOP

if "%~1"=="" (
    "%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\router_project_menu.ps1" -Root "%ROOT%" -Launch
) else (
    "%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\router_project_menu.ps1" -Root "%ROOT%" -Launch -ClaudeArguments %*
)
set "EXIT_CODE=%ERRORLEVEL%"
goto AFTER_RUN

:DIRECT_CLAUDE
"%CLAUDE_BIN%" %*
set "EXIT_CODE=%ERRORLEVEL%"
goto AFTER_RUN

:ROUTER_VERSION
"%ROUTER_NODE%" -p "'Claude Code Router ' + require(process.argv[1]).version" "%ROUTER_PACKAGE%"
set "EXIT_CODE=%ERRORLEVEL%"
goto AFTER_RUN

:CHECK_UPDATES
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\check_updates.ps1" -Root "%ROOT%"
set "EXIT_CODE=%ERRORLEVEL%"
goto AFTER_RUN

:FETCH_ROUTER_SOURCE
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\check_updates.ps1" -Root "%ROOT%" -FetchSource
set "EXIT_CODE=%ERRORLEVEL%"
goto AFTER_RUN

:INSTALL_ROUTER
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_router_runtime.ps1" -Root "%ROOT%"
set "EXIT_CODE=%ERRORLEVEL%"
goto AFTER_RUN

:ACCOUNT_MENU
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\router_project_menu.ps1" -Root "%ROOT%" -AccountMenu
set "EXIT_CODE=%ERRORLEVEL%"
goto AFTER_RUN

:ROUTER_STOP
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\router_project_menu.ps1" -Root "%ROOT%" -StopRouter
set "EXIT_CODE=%ERRORLEVEL%"

:AFTER_RUN
popd >nul
if "%NO_PAUSE%"=="0" (
    echo.
    echo [INFO] Finished with code %EXIT_CODE%.
    pause
)
exit /b %EXIT_CODE%
