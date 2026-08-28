[CmdletBinding()]
param(
    [ValidateSet('Typecheck', 'CoreUnit')]
    [string]$Action = 'Typecheck',
    [string]$Source = 'claude-code-router_proxy'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $Source))
$projectPrefix = $projectRoot + [System.IO.Path]::DirectorySeparatorChar
if (-not $sourceRoot.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'CCR test source resolved outside the project root.'
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'package-lock.json') -PathType Leaf)) {
    throw "CCR source checkout is missing or incomplete: $sourceRoot"
}

# Source tests can contain first-party profile synchronization code. Never let
# them share a live external app or the production project router.
$externalProcesses = @(Get-Process -Name 'ChatGPT', 'Codex' -ErrorAction SilentlyContinue)
if ($externalProcesses.Count -gt 0) {
    throw 'Close Codex/ChatGPT App before running CCR source tests.'
}

function Test-LoopbackPort {
    param([Parameter(Mandatory = $true)][int]$Port)
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $pending = $client.ConnectAsync('127.0.0.1', $Port)
        return ($pending.Wait(250) -and $client.Connected)
    }
    catch { return $false }
    finally { $client.Dispose() }
}

foreach ($port in @(3456, 3458, 18320)) {
    if (Test-LoopbackPort -Port $port) {
        throw "Stop the project dashboard/router before CCR source tests; loopback port $port is active."
    }
}

$realUserProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
$globalCodexRoot = Join-Path $realUserProfile '.codex'
function Get-ExternalCodexFingerprint {
    $configPath = Join-Path $globalCodexRoot 'config.toml'
    $configHash = if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        (Get-FileHash -Algorithm SHA256 -LiteralPath $configPath).Hash
    }
    else { '<missing>' }
    $artifactNames = @(if (Test-Path -LiteralPath $globalCodexRoot -PathType Container) {
        Get-ChildItem -LiteralPath $globalCodexRoot -Force -File |
            Where-Object { $_.Name -match 'ccr|claude-code-router' } |
            Sort-Object Name |
            Select-Object -ExpandProperty Name
    })
    return ($configHash + '|' + ($artifactNames -join '|'))
}

$externalBefore = Get-ExternalCodexFingerprint
$sandboxRoot = Join-Path $projectRoot '.tmp\ccr-source-test-sandbox'
$sandboxHome = Join-Path $sandboxRoot 'home'
$sandboxAppData = Join-Path $sandboxHome 'AppData\Roaming'
$sandboxLocalAppData = Join-Path $sandboxHome 'AppData\Local'
$sandboxUserData = Join-Path $sandboxRoot 'user-data'
$sandboxTemp = Join-Path $sandboxRoot 'temp'
New-Item -ItemType Directory -Force -Path $sandboxHome, $sandboxAppData, $sandboxLocalAppData, $sandboxUserData, $sandboxTemp | Out-Null

$env:HOME = $sandboxHome
$env:USERPROFILE = $sandboxHome
$env:APPDATA = $sandboxAppData
$env:LOCALAPPDATA = $sandboxLocalAppData
$env:TEMP = $sandboxTemp
$env:TMP = $sandboxTemp
$env:TMPDIR = $sandboxTemp
$env:CODEX_HOME = Join-Path $sandboxHome '.codex'
$env:CLAUDE_CONFIG_DIR = Join-Path $sandboxHome '.claude'
$env:CCR_INTERNAL_HOME_DIR = $sandboxHome
$env:CCR_INTERNAL_APP_DATA_DIR = $sandboxAppData
$env:CCR_INTERNAL_USER_DATA_DIR = $sandboxUserData
$env:CCR_EXTENSIONS_DIR = Join-Path $sandboxRoot 'extensions'
$env:CCR_PROVIDER_GATEWAY_ONLY = '1'
$env:CCR_GATEWAY_CONFIG_ACCEPTANCE_TIMEOUT_MS = '20000'

$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if ($null -eq $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }
if ($null -eq $npm) { throw 'npm is required for an explicit CCR source test.' }

$exitCode = 1
try {
    Push-Location $sourceRoot
    try {
        if ($Action -eq 'Typecheck') {
            & $npm.Source run typecheck
        }
        else {
            & $npm.Source run test:unit -w '@claude-code-router/core'
        }
        $exitCode = $LASTEXITCODE
    }
    finally { Pop-Location }
}
finally {
    $externalAfter = Get-ExternalCodexFingerprint
    if ($externalAfter -ne $externalBefore) {
        throw 'CCR source test changed external Codex state; result is rejected and manual recovery is required.'
    }
}

if ($exitCode -ne 0) { throw "Isolated CCR source test failed with exit code $exitCode." }
Write-Host "PASS: isolated CCR $Action completed without changing external Codex state." -ForegroundColor Green
