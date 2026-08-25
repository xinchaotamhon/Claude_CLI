[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$FetchSource
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RootPath = [System.IO.Path]::GetFullPath($Root)
$ClaudeBin = Join-Path $RootPath "bin\claude.exe"
$RouterRoot = Join-Path $RootPath "provider_router"
$SourceRecord = Join-Path $RouterRoot "SOURCE.json"
$NodeBin = Join-Path $RouterRoot "runtime\node.exe"
$RouterEntry = Join-Path $RouterRoot "node_modules\@musistudio\claude-code-router\dist\main\cli.js"
$InstalledRouterPackage = Join-Path $RouterRoot "node_modules\@musistudio\claude-code-router\package.json"

function Invoke-Version([string]$Executable, [string[]]$Arguments) {
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { return "missing" }
    $Text = & $Executable @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { return "error:$LASTEXITCODE" }
    return (($Text | Out-String).Trim())
}

function Get-Release([string]$Repository) {
    try {
        return Invoke-RestMethod -Headers @{ "User-Agent" = "claude-cli-local-update-check" } `
            -Uri "https://api.github.com/repos/$Repository/releases/latest" -TimeoutSec 15
    }
    catch {
        Write-Host ("  Metadata unavailable: " + $_.Exception.Message) -ForegroundColor Yellow
        return $null
    }
}

if (-not (Test-Path -LiteralPath $SourceRecord -PathType Leaf)) {
    throw "Missing router source record: $SourceRecord"
}
$Source = Get-Content -Raw -LiteralPath $SourceRecord | ConvertFrom-Json

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "          CLAUDE CLI LOCAL - UPDATE REVIEW" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "No binary, dependency, source branch, or credential is replaced." -ForegroundColor DarkGray
Write-Host ""

Write-Host "Claude Code binary" -ForegroundColor White
Write-Host ("  Local version : {0}" -f (Invoke-Version $ClaudeBin @("--version")))
if (Test-Path -LiteralPath $ClaudeBin -PathType Leaf) {
    Write-Host ("  Local SHA-256 : {0}" -f (Get-FileHash -Algorithm SHA256 -LiteralPath $ClaudeBin).Hash)
}
$ClaudeRelease = Get-Release "anthropics/claude-code"
if ($null -ne $ClaudeRelease) {
    Write-Host ("  Latest release: {0}" -f $ClaudeRelease.tag_name)
    Write-Host ("  Release page  : {0}" -f $ClaudeRelease.html_url)
}

Write-Host ""
Write-Host "Claude Code Router" -ForegroundColor White
Write-Host ("  Pinned package: {0}@{1}" -f $Source.package, $Source.version)
Write-Host ("  Source commit : {0}" -f $Source.source_commit)
$InstalledVersion = if (Test-Path -LiteralPath $InstalledRouterPackage -PathType Leaf) {
    [string](Get-Content -Raw -LiteralPath $InstalledRouterPackage | ConvertFrom-Json).version
} else { "missing" }
Write-Host ("  Local runtime : {0}" -f $InstalledVersion)
if (Test-Path -LiteralPath $NodeBin -PathType Leaf) {
    Write-Host ("  Node SHA-256  : {0}" -f (Get-FileHash -Algorithm SHA256 -LiteralPath $NodeBin).Hash)
}
$RouterRelease = Get-Release "musistudio/claude-code-router"
if ($null -ne $RouterRelease) {
    Write-Host ("  Latest release: {0}" -f $RouterRelease.tag_name)
    Write-Host ("  Release page  : {0}" -f $RouterRelease.html_url)
}

if (-not $FetchSource) {
    Write-Host ""
    Write-Host "Use RUN_CLAUDE.bat --fetch-router-source to clone/fetch source in ignored .tmp and show the review diff." -ForegroundColor DarkGray
    exit 0
}

$ReviewRoot = [System.IO.Path]::GetFullPath((Join-Path $RootPath ([string]$Source.local_source)))
if (-not $ReviewRoot.StartsWith($RootPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Source review path resolved outside the project root."
}

Write-Host ""
Write-Host "Source-only review (no merge)" -ForegroundColor White
if (-not (Test-Path -LiteralPath (Join-Path $ReviewRoot ".git"))) { throw "Local router source fork is missing: $ReviewRoot" }

& git -c "safe.directory=$ReviewRoot" -C $ReviewRoot fetch --quiet --no-tags upstream main
if ($LASTEXITCODE -ne 0) { throw "Unable to fetch router source for review." }

$Pinned = [string]$Source.source_commit
& git -c "safe.directory=$ReviewRoot" -C $ReviewRoot cat-file -e "$Pinned^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    & git -c "safe.directory=$ReviewRoot" -C $ReviewRoot fetch --quiet upstream $Pinned
    if ($LASTEXITCODE -ne 0) { throw "Pinned source commit is unavailable from the repository." }
}

Write-Host "Commits after the pinned source:" -ForegroundColor Cyan
& git -c "safe.directory=$ReviewRoot" -C $ReviewRoot log --oneline "$Pinned..upstream/main"
Write-Host ""
Write-Host "Diff summary from pinned source to current upstream main:" -ForegroundColor Cyan
& git -c "safe.directory=$ReviewRoot" -C $ReviewRoot diff --stat "$Pinned..upstream/main"
Write-Host ""
Write-Host "Review only complete. Nothing was merged, installed, or replaced." -ForegroundColor Green
