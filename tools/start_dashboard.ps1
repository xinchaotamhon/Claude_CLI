#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot '..'),
    [switch]$Detached,
    [switch]$SkipBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$StartupLog = $null
try {
    $StartupLog = [System.IO.Path]::GetFullPath((Join-Path $Root '.runtime\dashboard\startup-error.log'))
}
catch { }

trap {
    $Message = [string]$_.Exception.Message
    try {
        if (-not [string]::IsNullOrWhiteSpace($StartupLog)) {
            $StartupDirectory = Split-Path -Parent $StartupLog
            [System.IO.Directory]::CreateDirectory($StartupDirectory) | Out-Null
            $Line = '[{0}] Dashboard startup failed: {1}{2}' -f [DateTime]::UtcNow.ToString('o'), $Message, [Environment]::NewLine
            [System.IO.File]::AppendAllText($StartupLog, $Line, (New-Object System.Text.UTF8Encoding($false)))
        }
    }
    catch { }
    if ($Detached) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($StartupLog) -and (Test-Path -LiteralPath $StartupLog -PathType Leaf)) {
                Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $StartupLog) -WindowStyle Normal | Out-Null
            }
        }
        catch { }
    }
    else {
        [Console]::Error.WriteLine('[ERROR] Dashboard startup failed: ' + $Message)
    }
    exit 1
}
$ProjectRoot = (Resolve-Path -LiteralPath $Root).Path
$PowerShell7 = Join-Path ${env:ProgramFiles} 'PowerShell\7\pwsh.exe'
$Node = Join-Path $ProjectRoot 'provider_router\runtime\node.exe'
$Server = Join-Path $ProjectRoot 'dashboard\server.mjs'
$SessionLifecycle = Join-Path $ProjectRoot 'dashboard\session_lifecycle.mjs'
$Supervisor = Join-Path $ProjectRoot 'tools\dashboard_supervisor.ps1'
$RouterWarmup = Join-Path $ProjectRoot 'tools\router_project_menu.ps1'
$Static = Join-Path $ProjectRoot 'dashboard\static\index.html'
$Ready = Join-Path $ProjectRoot '.runtime\dashboard\ready.json'
$VerifiedIdentity = Join-Path $ProjectRoot '.runtime\dashboard\verified-identity.json'
$WarmupState = Join-Path $ProjectRoot '.runtime\dashboard\warmup-started.json'
$Health = 'http://127.0.0.1:18320/health'

foreach ($Required in @($PowerShell7, $Node, $Server, $SessionLifecycle, $Static, $Supervisor, $RouterWarmup)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) { throw "Dashboard component is missing: $Required" }
}

function Get-CombinedFileHash {
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    $Parts = @()
    $TotalLength = 0
    foreach ($Path in $Paths) {
        [byte[]]$Part = [System.IO.File]::ReadAllBytes($Path)
        $Parts += ,$Part
        $TotalLength += $Part.Length
    }
    [byte[]]$Combined = New-Object byte[] $TotalLength
    $Offset = 0
    foreach ($Part in $Parts) {
        [System.Array]::Copy($Part, 0, $Combined, $Offset, $Part.Length)
        $Offset += $Part.Length
    }
    $Hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($Hasher.ComputeHash($Combined))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $Hasher.Dispose()
    }
}

$ExpectedServerHash = Get-CombinedFileHash -Paths @($Server, $SessionLifecycle)

function Test-DashboardIdentity {
    try {
        if (-not (Test-Path -LiteralPath $Ready -PathType Leaf)) { return $false }
        $ReadyState = Get-Content -Raw -LiteralPath $Ready | ConvertFrom-Json
        $ReadyHashProperty = $ReadyState.PSObject.Properties['serverHash']
        if ($ReadyState.loopbackOnly -ne $true -or [string]$ReadyState.host -ne '127.0.0.1' -or [int]$ReadyState.port -ne 18320) { return $false }
        if ([string]::IsNullOrWhiteSpace([string]$ReadyState.instanceId) -or $null -eq $ReadyHashProperty -or [string]$ReadyHashProperty.Value -ne $ExpectedServerHash) { return $false }
        $Verified = $null
        if (Test-Path -LiteralPath $VerifiedIdentity -PathType Leaf) {
            try { $Verified = Get-Content -Raw -LiteralPath $VerifiedIdentity | ConvertFrom-Json } catch { $Verified = $null }
        }
        $FastIdentity = $null -ne $Verified -and [int]$Verified.pid -eq [int]$ReadyState.pid -and [string]$Verified.instanceId -eq [string]$ReadyState.instanceId -and [string]$Verified.serverHash -eq $ExpectedServerHash
        if ($FastIdentity) {
            $Process = Get-Process -Id ([int]$ReadyState.pid) -ErrorAction Stop
            if (-not ([string]$Process.Path).Equals($Node, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
        else {
            $Process = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f [int]$ReadyState.pid) -ErrorAction Stop
            if ($null -eq $Process) { return $false }
            if (-not ([string]$Process.ExecutablePath).Equals($Node, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
            if (([string]$Process.CommandLine).IndexOf($Server, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
            $VerifiedPayload = [ordered]@{ schemaVersion = 1; pid = [int]$ReadyState.pid; instanceId = [string]$ReadyState.instanceId; serverHash = $ExpectedServerHash; verifiedAt = [DateTime]::UtcNow.ToString('o') }
            [System.IO.File]::WriteAllText($VerifiedIdentity, ($VerifiedPayload | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
        }
        $Response = Invoke-RestMethod -Uri $Health -Method Get -TimeoutSec 1
        return $Response.ok -eq $true -and $Response.service -eq 'claude-cli-dashboard' -and [string]$Response.instanceId -eq [string]$ReadyState.instanceId -and [string]$Response.serverHash -eq $ExpectedServerHash
    }
    catch { return $false }
}

function Stop-OutdatedOwnedDashboard {
    try {
        if (-not (Test-Path -LiteralPath $Ready -PathType Leaf)) { return }
        $ReadyState = Get-Content -Raw -LiteralPath $Ready | ConvertFrom-Json
        if ($ReadyState.loopbackOnly -ne $true -or [string]$ReadyState.host -ne '127.0.0.1' -or [int]$ReadyState.port -ne 18320) { return }
        $Process = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f [int]$ReadyState.pid) -ErrorAction Stop
        if ($null -eq $Process) { return }
        if (-not ([string]$Process.ExecutablePath).Equals($Node, [System.StringComparison]::OrdinalIgnoreCase)) { return }
        if (([string]$Process.CommandLine).IndexOf($Server, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return }
        Stop-Process -Id ([int]$ReadyState.pid) -Force
        $Deadline = [DateTime]::UtcNow.AddSeconds(3)
        while ([DateTime]::UtcNow -lt $Deadline -and (Get-Process -Id ([int]$ReadyState.pid) -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 100 }
    }
    catch { }
}

$DashboardReady = Test-DashboardIdentity
if ((Test-Path -LiteralPath $Ready -PathType Leaf) -and -not $DashboardReady) {
    $RecoveryDeadline = [DateTime]::UtcNow.AddSeconds(3)
    while ([DateTime]::UtcNow -lt $RecoveryDeadline -and -not $DashboardReady) {
        Start-Sleep -Milliseconds 150
        $DashboardReady = Test-DashboardIdentity
    }
}

if (-not $DashboardReady) {
    Stop-OutdatedOwnedDashboard
    if (Test-Path -LiteralPath $Ready -PathType Leaf) { Remove-Item -LiteralPath $Ready -Force }
    Start-Process -FilePath $PowerShell7 -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Supervisor, '-Root', $ProjectRoot) -WorkingDirectory $ProjectRoot -WindowStyle Hidden | Out-Null
    $Deadline = [DateTime]::UtcNow.AddSeconds(12)
    while ([DateTime]::UtcNow -lt $Deadline) {
        $DashboardReady = Test-DashboardIdentity
        if ($DashboardReady) { break }
        Start-Sleep -Milliseconds 150
    }
}

if (-not $DashboardReady) {
    throw 'The project-local dashboard did not become ready on 127.0.0.1:18320.'
}

# Warm the same independently verified loopback gateway used by route launch.
# This child reads no setting, account or DPAPI credential; launch remains the
# fail-closed authority if background warmup cannot finish.
$ShouldWarm = $true
if (Test-Path -LiteralPath $WarmupState -PathType Leaf) {
    try {
        $PreviousWarmup = Get-Content -Raw -LiteralPath $WarmupState | ConvertFrom-Json
        $PreviousAt = [DateTime]::Parse([string]$PreviousWarmup.requestedAt).ToUniversalTime()
        if ([DateTime]::UtcNow.Subtract($PreviousAt).TotalMinutes -lt 2) { $ShouldWarm = $false }
    }
    catch { $ShouldWarm = $true }
}
if ($ShouldWarm) {
    $WarmupPayload = [ordered]@{ schemaVersion = 1; requestedAt = [DateTime]::UtcNow.ToString('o') }
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $WarmupState)) | Out-Null
    [System.IO.File]::WriteAllText($WarmupState, ($WarmupPayload | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
    Start-Process -FilePath $PowerShell7 -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $RouterWarmup, '-Root', $ProjectRoot, '-WarmRouter') -WorkingDirectory $ProjectRoot -WindowStyle Hidden | Out-Null
}

$State = Get-Content -Raw -LiteralPath $Ready | ConvertFrom-Json
if ($State.loopbackOnly -ne $true -or [string]$State.host -ne '127.0.0.1' -or [int]$State.port -ne 18320) {
    throw 'Dashboard ready state failed its loopback-only contract.'
}
$Uri = [Uri]([string]$State.url)
if ($Uri.Scheme -ne 'http' -or $Uri.Host -ne '127.0.0.1' -or $Uri.Port -ne 18320) { throw 'Dashboard URL is unsafe.' }
if (-not $SkipBrowser) {
    Start-Process ([string]$State.url) | Out-Null
}
