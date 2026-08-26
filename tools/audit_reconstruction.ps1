#requires -Version 5.1

[CmdletBinding()]
param([string]$Root = (Join-Path $PSScriptRoot '..'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $Root).Path

$Checks = @(
    @{ Name = 'Claude Code binary'; Path = 'bin\claude.exe'; Repair = 'Download official Claude Code Windows binary after owner review.' },
    @{ Name = 'CCR Node runtime'; Path = 'provider_router\runtime\node.exe'; Repair = 'tools\install_router_runtime.ps1' },
    @{ Name = 'CCR package'; Path = 'provider_router\node_modules\@musistudio\claude-code-router\package.json'; Repair = 'tools\install_router_runtime.ps1' },
    @{ Name = 'Codex login helper'; Path = 'provider_router\codex-login-runtime\codex.exe'; Repair = 'tools\install_codex_login_runtime.ps1' },
    @{ Name = 'Google challenger'; Path = '.runtime\challenger\bin\cli-proxy-api.exe'; Repair = 'tools\install_challenger_pilot.ps1' },
    @{ Name = 'Dashboard build'; Path = 'dashboard\static\index.html'; Repair = 'Restore tracked dashboard/static from Git.' }
)

Write-Host 'Claude CLI reconstruction audit' -ForegroundColor Cyan
Write-Host ("Root: {0}" -f $ProjectRoot)
Write-Host ''
$Missing = 0
foreach ($Check in $Checks) {
    $FullPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $Check.Path))
    if (-not $FullPath.StartsWith($ProjectRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe reconstruction path.' }
    if (Test-Path -LiteralPath $FullPath -PathType Leaf) {
        Write-Host ("[OK]      {0}" -f $Check.Name) -ForegroundColor Green
    }
    else {
        $Missing++
        Write-Host ("[MISSING] {0}" -f $Check.Name) -ForegroundColor Yellow
        Write-Host ("          Repair: {0}" -f $Check.Repair) -ForegroundColor DarkGray
    }
}

Write-Host ''
Write-Host 'Secrets, OAuth, CCR database and sessions are intentionally not audited or read.' -ForegroundColor DarkGray
if ($Missing) { Write-Host ("{0} optional/runtime component(s) need reconstruction." -f $Missing) -ForegroundColor Yellow; exit 2 }
Write-Host 'All expected local runtime components are present.' -ForegroundColor Green
exit 0
