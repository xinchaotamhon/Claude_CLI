[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceMetadataPath = Join-Path $projectRoot 'router_challenger\SOURCE.json'
$sourceMetadata = Get-Content -Raw -LiteralPath $sourceMetadataPath | ConvertFrom-Json
$sourceRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot ([string]$sourceMetadata.local_checkout)))
$patchPath = [System.IO.Path]::GetFullPath((Join-Path $projectRoot ([string]$sourceMetadata.patch_file)))
$toolchainArchive = Join-Path $projectRoot '.tmp\go1.26.7.windows-amd64.zip'
$goRoot = Join-Path $projectRoot 'vendor\go'
$goExe = Join-Path $goRoot 'bin\go.exe'
$expectedArchiveHash = 'f4f534a486e4bc3387fa18f08208f2f854b7aaea8a08f2a2d829a914a05abb11'
$downloadUrl = 'https://go.dev/dl/go1.26.7.windows-amd64.zip'

function Assert-ProjectChild {
    param([Parameter(Mandatory = $true)][string]$Path)
    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith($projectRoot.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes project root: $resolved"
    }
}

Assert-ProjectChild -Path $sourceRoot
Assert-ProjectChild -Path $toolchainArchive
Assert-ProjectChild -Path $goRoot

if (-not (Test-Path -LiteralPath $goExe -PathType Leaf)) {
    if (Test-Path -LiteralPath $goRoot) {
        throw 'vendor\go exists but is incomplete; inspect and remove only that exact directory before retrying.'
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $toolchainArchive), (Join-Path $projectRoot 'vendor') | Out-Null
    Invoke-WebRequest -Uri $downloadUrl -OutFile $toolchainArchive
    $archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $toolchainArchive).Hash.ToLowerInvariant()
    if ($archiveHash -ne $expectedArchiveHash) {
        throw "Official Go archive hash mismatch: $archiveHash"
    }
    Expand-Archive -LiteralPath $toolchainArchive -DestinationPath (Join-Path $projectRoot 'vendor')
}

$goVersion = (& $goExe version).Trim()
if ($goVersion -ne 'go version go1.26.7 windows/amd64') {
    throw "Unexpected project-local Go toolchain: $goVersion"
}

if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    & git.exe clone --origin upstream --no-checkout ([string]$sourceMetadata.source_url) $sourceRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not clone the pinned challenger source.' }
    & git.exe -C $sourceRoot checkout --detach ([string]$sourceMetadata.source_commit)
    if ($LASTEXITCODE -ne 0) { throw 'Could not checkout the audited upstream commit.' }
    & git.exe -C $sourceRoot switch -c ([string]$sourceMetadata.local_branch)
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the local challenger branch.' }
    & git.exe -C $sourceRoot am $patchPath
    if ($LASTEXITCODE -ne 0) { throw 'Could not apply the tracked isolation patch.' }
}

$tree = (& git.exe -C $sourceRoot rev-parse 'HEAD^{tree}').Trim()
if ($LASTEXITCODE -ne 0 -or $tree -ne [string]$sourceMetadata.patched_tree) {
    throw "Existing challenger source is not the pinned patched tree: $tree"
}
$status = (& git.exe -C $sourceRoot status --porcelain) -join "`n"
if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace($status)) {
    throw 'Existing challenger source checkout is dirty; refusing to overwrite it.'
}

& (Join-Path $PSScriptRoot 'build_challenger.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Challenger build failed.' }
Write-Host '[OK] Project-local challenger prerequisites and pinned binaries are ready.'
