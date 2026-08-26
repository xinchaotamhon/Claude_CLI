#requires -Version 7.0

[CmdletBinding()]
param([string]$Root = (Join-Path $PSScriptRoot '..'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $Root).Path
$Node = Join-Path $ProjectRoot 'provider_router\runtime\node.exe'
$Server = Join-Path $ProjectRoot 'dashboard\server.mjs'
$Runtime = Join-Path $ProjectRoot '.runtime\dashboard'
$Log = Join-Path $Runtime 'dashboard-server.log'
$Ready = Join-Path $Runtime 'ready.json'
$IdentityBytes = [System.Text.Encoding]::UTF8.GetBytes($ProjectRoot.ToLowerInvariant())
$Hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($IdentityBytes)
$MutexName = 'Local\ClaudeCliDashboard-' + ([Convert]::ToHexString($Hash).Substring(0, 24))
$Mutex = [System.Threading.Mutex]::new($false, $MutexName)
if (-not $Mutex.WaitOne(0)) { exit 0 }

try {
    [System.IO.Directory]::CreateDirectory($Runtime) | Out-Null
    $rapidFailures = 0
    while ($rapidFailures -lt 5) {
        $StartedAt = [DateTime]::UtcNow
        & $Node $Server *>> $Log
        $Elapsed = ([DateTime]::UtcNow - $StartedAt).TotalSeconds
        if ($Elapsed -ge 30) { $rapidFailures = 0 } else { $rapidFailures++ }
        try {
            if (Test-Path -LiteralPath $Ready -PathType Leaf) {
                $ReadyPid = [int](Get-Content -Raw -LiteralPath $Ready | ConvertFrom-Json).pid
                if (-not (Get-Process -Id $ReadyPid -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $Ready -Force }
            }
        } catch { }
        if ($rapidFailures -lt 5) { Start-Sleep -Milliseconds 750 }
    }
}
finally {
    try { $Mutex.ReleaseMutex() } catch { }
    $Mutex.Dispose()
}
