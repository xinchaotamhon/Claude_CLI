#requires -Version 5.1

[CmdletBinding()]
param([string]$Root = (Join-Path $PSScriptRoot '..'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $Root).Path
$Node = Join-Path $ProjectRoot 'provider_router\runtime\node.exe'
$Server = Join-Path $ProjectRoot 'dashboard\server.mjs'
$Static = Join-Path $ProjectRoot 'dashboard\static\index.html'
$Ready = Join-Path $ProjectRoot '.runtime\dashboard\ready.json'
$Health = 'http://127.0.0.1:18320/health'

foreach ($Required in @($Node, $Server, $Static)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) { throw "Dashboard component is missing: $Required" }
}
$ExpectedServerHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Server).Hash.ToLowerInvariant()

function Test-DashboardIdentity {
    try {
        if (-not (Test-Path -LiteralPath $Ready -PathType Leaf)) { return $false }
        $ReadyState = Get-Content -Raw -LiteralPath $Ready | ConvertFrom-Json
        $ReadyHashProperty = $ReadyState.PSObject.Properties['serverHash']
        if ($ReadyState.loopbackOnly -ne $true -or [string]$ReadyState.host -ne '127.0.0.1' -or [int]$ReadyState.port -ne 18320) { return $false }
        if ([string]::IsNullOrWhiteSpace([string]$ReadyState.instanceId) -or $null -eq $ReadyHashProperty -or [string]$ReadyHashProperty.Value -ne $ExpectedServerHash) { return $false }
        $Process = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f [int]$ReadyState.pid) -ErrorAction Stop
        if ($null -eq $Process) { return $false }
        if (-not ([string]$Process.ExecutablePath).Equals($Node, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        if (([string]$Process.CommandLine).IndexOf($Server, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
        $Response = Invoke-RestMethod -Uri $Health -Method Get -TimeoutSec 1
        return $Response.ok -eq $true -and $Response.service -eq 'claude-cli-dashboard' -and [string]$Response.instanceId -eq [string]$ReadyState.instanceId -and [string]$Response.serverHash -eq $ExpectedServerHash
    }
    catch { return $false }
}

function Stop-OutdatedOwnedDashboard {
    try {
        if (-not (Test-Path -LiteralPath $Ready -PathType Leaf)) { return }
        $ReadyState = Get-Content -Raw -LiteralPath $Ready | ConvertFrom-Json
        $ReadyHashProperty = $ReadyState.PSObject.Properties['serverHash']
        if ($null -ne $ReadyHashProperty -and [string]$ReadyHashProperty.Value -eq $ExpectedServerHash) { return }
        $Process = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f [int]$ReadyState.pid) -ErrorAction Stop
        if ($null -eq $Process) { return }
        if (-not ([string]$Process.ExecutablePath).Equals($Node, [System.StringComparison]::OrdinalIgnoreCase)) { return }
        if (([string]$Process.CommandLine).IndexOf($Server, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return }
        $Response = Invoke-RestMethod -Uri $Health -Method Get -TimeoutSec 1
        if ($Response.ok -ne $true -or $Response.service -ne 'claude-cli-dashboard' -or [string]$Response.instanceId -ne [string]$ReadyState.instanceId) { return }
        Stop-Process -Id ([int]$ReadyState.pid) -Force
        $Deadline = [DateTime]::UtcNow.AddSeconds(3)
        while ([DateTime]::UtcNow -lt $Deadline -and (Get-Process -Id ([int]$ReadyState.pid) -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 100 }
    }
    catch { }
}

if (-not (Test-DashboardIdentity)) {
    Stop-OutdatedOwnedDashboard
    if (Test-Path -LiteralPath $Ready -PathType Leaf) { Remove-Item -LiteralPath $Ready -Force }
    Start-Process -FilePath $Node -ArgumentList @($Server) -WorkingDirectory $ProjectRoot -WindowStyle Hidden | Out-Null
    $Deadline = [DateTime]::UtcNow.AddSeconds(12)
    while ([DateTime]::UtcNow -lt $Deadline) {
        if (Test-DashboardIdentity) { break }
        Start-Sleep -Milliseconds 150
    }
}

if (-not (Test-DashboardIdentity)) {
    throw 'The project-local dashboard did not become ready on 127.0.0.1:18320.'
}

$State = Get-Content -Raw -LiteralPath $Ready | ConvertFrom-Json
if ($State.loopbackOnly -ne $true -or [string]$State.host -ne '127.0.0.1' -or [int]$State.port -ne 18320) {
    throw 'Dashboard ready state failed its loopback-only contract.'
}
$Uri = [Uri]([string]$State.url)
if ($Uri.Scheme -ne 'http' -or $Uri.Host -ne '127.0.0.1' -or $Uri.Port -ne 18320) { throw 'Dashboard URL is unsafe.' }
Start-Process ([string]$State.url) | Out-Null
