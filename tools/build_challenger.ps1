[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$goExe = Join-Path $projectRoot 'vendor\go\bin\go.exe'
$sourceRoot = Join-Path $projectRoot 'cli-proxy-api_core'
$outputDir = Join-Path $projectRoot '.runtime\challenger\bin'
$outputExe = Join-Path $outputDir 'cli-proxy-api.exe'
$fixtureRoot = Join-Path $projectRoot 'router_challenger\fixture'
$fixtureExe = Join-Path $outputDir 'challenger-fixture.exe'
$manifestPath = Join-Path $projectRoot 'router_challenger\BUILD.json'
$sourceMetadataPath = Join-Path $projectRoot 'router_challenger\SOURCE.json'
$runtimeModelsPath = Join-Path $projectRoot 'router_challenger\google-runtime-models.json'
$sourceModelsPath = Join-Path $sourceRoot 'internal\registry\models\models.json'

if (-not (Test-Path -LiteralPath $goExe -PathType Leaf)) {
    throw 'Project-local Go is missing under vendor\go. Normal launchers never download it.'
}
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw 'The ignored cli-proxy-api_core checkout is missing.'
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'The tracked challenger build manifest is missing.'
}
if (-not (Test-Path -LiteralPath $runtimeModelsPath -PathType Leaf) -or -not (Test-Path -LiteralPath $sourceModelsPath -PathType Leaf)) {
    throw 'The Google runtime compatibility manifest or source model registry is missing.'
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$sourceMetadata = Get-Content -Raw -LiteralPath $sourceMetadataPath | ConvertFrom-Json
$runtimeModels = Get-Content -Raw -LiteralPath $runtimeModelsPath | ConvertFrom-Json
$sourceModels = Get-Content -Raw -LiteralPath $sourceModelsPath | ConvertFrom-Json
$expectedModels = @($sourceModels.antigravity | ForEach-Object { [string]$_.id } | Sort-Object -Unique)
$declaredModels = @($runtimeModels.models | ForEach-Object { [string]$_ } | Sort-Object -Unique)
if (($expectedModels -join "`n") -ne ($declaredModels -join "`n")) {
    throw 'The tracked Google runtime compatibility manifest is stale relative to the pinned source registry.'
}
if (([string]$runtimeModels.binary_sha256).ToLowerInvariant() -ne ([string]$manifest.binary.sha256).ToLowerInvariant()) {
    throw 'The Google runtime compatibility manifest does not match BUILD.json.'
}
$sourceTree = (& git.exe -C $sourceRoot rev-parse 'HEAD^{tree}').Trim()
if ($LASTEXITCODE -ne 0 -or $sourceTree -ne [string]$sourceMetadata.patched_tree) {
    throw "Challenger source tree is not the pinned patched tree: $sourceTree"
}
$sourceStatus = (& git.exe -C $sourceRoot status --porcelain) -join "`n"
if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace($sourceStatus)) {
    throw 'Challenger source checkout must be clean before build.'
}

$goVersion = (& $goExe version).Trim()
if ($goVersion -ne 'go version go1.26.7 windows/amd64') {
    throw "Unexpected project-local toolchain: $goVersion"
}

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$env:GOCACHE = Join-Path $projectRoot '.cache\go-build'
$env:GOMODCACHE = Join-Path $projectRoot 'vendor\gomodcache'
$env:GOPROXY = 'off'
$env:GOSUMDB = 'off'

Push-Location $sourceRoot
try {
    & $goExe test ./cmd/server
    if ($LASTEXITCODE -ne 0) { throw 'CLIProxyAPI cmd/server tests failed.' }
    & $goExe build -trimpath -buildvcs=false `
        -ldflags '-s -w -X main.Version=7.2.144-local.1 -X main.Commit=b811980516263623713dbcf15e3cecf8296ab2b0 -X main.BuildDate=2026-08-28' `
        -o $outputExe ./cmd/server
    if ($LASTEXITCODE -ne 0) { throw 'CLIProxyAPI build failed.' }
}
finally {
    Pop-Location
}

Push-Location $fixtureRoot
try {
    & $goExe test ./...
    if ($LASTEXITCODE -ne 0) { throw 'Fixture tests failed.' }
    & $goExe build -trimpath -buildvcs=false -o $fixtureExe .
    if ($LASTEXITCODE -ne 0) { throw 'Fixture build failed.' }
}
finally {
    Pop-Location
}

$proxyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputExe).Hash.ToLowerInvariant()
$fixtureHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $fixtureExe).Hash.ToLowerInvariant()
if ($proxyHash -ne [string]$manifest.binary.sha256) {
    throw "Challenger build is not reproducible: $proxyHash"
}
if ($fixtureHash -ne [string]$manifest.fixture_binary.sha256) {
    throw "Fixture build is not reproducible: $fixtureHash"
}
Write-Host "Built isolated challenger: $proxyHash"
Write-Host "Built offline fixture:    $fixtureHash"
