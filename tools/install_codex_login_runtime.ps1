#requires -Version 5.1

[CmdletBinding()]
param([string]$Root = (Join-Path $PSScriptRoot ".."))

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $Root).Path
$RouterRoot = Join-Path $RootPath "provider_router"
$TargetRoot = Join-Path $RouterRoot "codex-login-runtime"
$TargetBinary = Join-Path $TargetRoot "codex.exe"
$SourcePath = Join-Path $RouterRoot "CODEX_LOGIN_SOURCE.json"
$InstallerStateRoot = Join-Path $RouterRoot ".ccr-local\codex-installer"
$DownloadPath = Join-Path $InstallerStateRoot "install.ps1"
$OfficialInstallerUrl = "https://chatgpt.com/codex/install.ps1"

function Assert-InsideProject {
    param([Parameter(Mandatory = $true)][string]$Path)
    $FullRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([char[]]@('\', '/'))
    $FullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $FullPath.StartsWith($FullRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing a path outside the project: $Path"
    }
    return $FullPath
}

$TargetRoot = Assert-InsideProject -Path $TargetRoot
$TargetBinary = Assert-InsideProject -Path $TargetBinary
$SourcePath = Assert-InsideProject -Path $SourcePath
$InstallerStateRoot = Assert-InsideProject -Path $InstallerStateRoot
$DownloadPath = Assert-InsideProject -Path $DownloadPath
New-Item -ItemType Directory -Path $TargetRoot,$InstallerStateRoot -Force | Out-Null

$SavedInstallDir = [Environment]::GetEnvironmentVariable("CODEX_INSTALL_DIR", "Process")
$SavedHome = [Environment]::GetEnvironmentVariable("CODEX_HOME", "Process")
try {
    Invoke-WebRequest -Uri $OfficialInstallerUrl -OutFile $DownloadPath -UseBasicParsing
    $env:CODEX_INSTALL_DIR = $TargetRoot
    $env:CODEX_HOME = $InstallerStateRoot
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $DownloadPath
    if ($LASTEXITCODE -ne 0) { throw "Official Codex installer exited with code $LASTEXITCODE." }
}
finally {
    [Environment]::SetEnvironmentVariable("CODEX_INSTALL_DIR", $SavedInstallDir, "Process")
    [Environment]::SetEnvironmentVariable("CODEX_HOME", $SavedHome, "Process")
    if (Test-Path -LiteralPath $DownloadPath -PathType Leaf) { Remove-Item -LiteralPath $DownloadPath -Force }
}

if (-not (Test-Path -LiteralPath $TargetBinary -PathType Leaf)) { throw "The official installer did not create $TargetBinary" }
$VersionOutput = (& $TargetBinary --version | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or -not $VersionOutput) { throw "The installed project-local Codex binary did not report a version." }
$Version = if ($VersionOutput -match '(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)') { $Matches[1] } else { $VersionOutput }
$Hash = (Get-FileHash -LiteralPath $TargetBinary -Algorithm SHA256).Hash.ToLowerInvariant()
$Metadata = [ordered]@{
    schema_version = 1
    name = "OpenAI Codex CLI login helper"
    version = $Version
    sha256 = $Hash
    binary_path = "provider_router/codex-login-runtime/codex.exe"
    source_kind = "OpenAI standalone Windows installer"
    source_package = $OfficialInstallerUrl
    copied_at = (Get-Date).ToString("yyyy-MM-dd")
    runtime_policy = "Project-local ChatGPT login only; never execute agent work or serve as the Claude harness."
    official_docs = @(
        "https://learn.chatgpt.com/docs/auth",
        "https://learn.chatgpt.com/docs/config-file/environment-variables",
        "https://learn.chatgpt.com/docs/codex/cli"
    )
}
[System.IO.File]::WriteAllText($SourcePath, ($Metadata | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Installed project-local Codex login helper: $Version" -ForegroundColor Green
Write-Host "Binary and installer state remain inside this project." -ForegroundColor Green
