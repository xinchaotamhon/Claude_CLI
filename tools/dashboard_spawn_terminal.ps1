#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('launch-new', 'launch-resume', 'codex', 'codex-resume', 'google')]
    [string]$Action,
    [string]$Value,
    [string]$Extra,
    [string]$Label,
    [Parameter(Mandatory = $true)][string]$StatusPath,
    [string]$Root = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $Root).Path
$Helper = Join-Path $ProjectRoot 'tools\dashboard_terminal.ps1'
$PowerShell = Join-Path ${env:ProgramFiles} 'PowerShell\7\pwsh.exe'
if (-not $PowerShell -or -not (Test-Path -LiteralPath $Helper -PathType Leaf)) { throw 'Project terminal helper is unavailable.' }

$Start = [System.Diagnostics.ProcessStartInfo]::new()
$Start.FileName = $PowerShell
$Start.WorkingDirectory = $ProjectRoot
$Start.UseShellExecute = $true
$Start.CreateNoWindow = $false
foreach ($Argument in @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Helper, '-Action', $Action, '-Root', $ProjectRoot, '-StatusPath', $StatusPath)) {
    [void]$Start.ArgumentList.Add([string]$Argument)
}
if ($PSBoundParameters.ContainsKey('Value')) { [void]$Start.ArgumentList.Add('-Value'); [void]$Start.ArgumentList.Add($Value) }
if ($PSBoundParameters.ContainsKey('Extra')) { [void]$Start.ArgumentList.Add('-Extra'); [void]$Start.ArgumentList.Add($Extra) }
if ($PSBoundParameters.ContainsKey('Label')) { [void]$Start.ArgumentList.Add('-Label'); [void]$Start.ArgumentList.Add($Label) }
$Process = [System.Diagnostics.Process]::Start($Start)
if ($null -eq $Process -or $Process.Id -le 0) { throw 'Visible terminal did not start.' }
[PSCustomObject]@{ schemaVersion = 1; pid = $Process.Id } | ConvertTo-Json -Compress
