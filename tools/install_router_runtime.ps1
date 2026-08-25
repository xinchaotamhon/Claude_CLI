[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RootPath = [System.IO.Path]::GetFullPath($Root)
$RouterRoot = [System.IO.Path]::GetFullPath((Join-Path $RootPath "provider_router"))
$RuntimeRoot = [System.IO.Path]::GetFullPath((Join-Path $RouterRoot "runtime"))
$Manifest = Join-Path $RouterRoot "package.json"
$NodeTarget = Join-Path $RuntimeRoot "node.exe"
$Entry = Join-Path $RouterRoot "node_modules\@musistudio\claude-code-router\dist\main\cli.js"
$InstalledPackage = Join-Path $RouterRoot "node_modules\@musistudio\claude-code-router\package.json"

if (-not $RouterRoot.StartsWith($RootPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Router runtime resolved outside the project root."
}
if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
    throw "Pinned router package manifest is missing: $Manifest"
}

$Node = Get-Command node.exe -ErrorAction SilentlyContinue
if ($null -eq $Node) { $Node = Get-Command node -ErrorAction SilentlyContinue }
if ($null -eq $Node) { throw "Node.js 22 or newer is required once to build the project-local runtime." }

$NodeVersionText = & $Node.Source --version
if ($LASTEXITCODE -ne 0 -or $NodeVersionText -notmatch '^v(?<major>\d+)\.') {
    throw "Unable to determine the installed Node.js version."
}
if ([int]$Matches.major -lt 22) { throw "Node.js 22 or newer is required; found $NodeVersionText." }

$Npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if ($null -eq $Npm) { $Npm = Get-Command npm -ErrorAction SilentlyContinue }
if ($null -eq $Npm) { throw "npm is required once to install the pinned router package." }

New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null

Write-Host "Installing pinned Claude Code Router dependencies inside this project..." -ForegroundColor Cyan
& $Npm.Source ci --prefix $RouterRoot --omit=dev --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw "npm ci failed with exit code $LASTEXITCODE." }

Copy-Item -LiteralPath $Node.Source -Destination $NodeTarget -Force
if (-not (Test-Path -LiteralPath $Entry -PathType Leaf)) {
    throw "Router CLI entry was not installed: $Entry"
}

$LocalNodeVersion = & $NodeTarget --version
if ($LASTEXITCODE -ne 0) { throw "Copied project-local Node runtime did not pass its version check." }
$Version = [string](Get-Content -Raw -LiteralPath $InstalledPackage | ConvertFrom-Json).version
if ($Version -ne "3.0.21") { throw "Installed router package version is '$Version', expected '3.0.21'." }

$PatchTool = Join-Path $RootPath "tools\apply_router_local_patches.ps1"
if (-not (Test-Path -LiteralPath $PatchTool -PathType Leaf)) {
    throw "Required project-local router patch tool is missing: $PatchTool"
}
& $PatchTool -Root $RootPath
if (-not $?) { throw "Project-local router patch failed." }

Write-Host "PASS: project-local router runtime is ready." -ForegroundColor Green
Write-Host "Node: $LocalNodeVersion"
Write-Host "Router: $Version"
Write-Host "Runtime: $RouterRoot"
