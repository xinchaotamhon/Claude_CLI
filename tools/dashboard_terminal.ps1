#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('launch-new', 'launch-resume', 'launch-google-new', 'launch-google-resume', 'codex', 'codex-resume', 'google')]
    [string]$Action,
    [string]$Value,
    [string]$Extra,
    [string]$Label,
    [string]$Meta,
    [string]$StatusPath,
    [string]$Root = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $Root).Path
$RouterMenu = Join-Path $ProjectRoot 'tools\router_project_menu.ps1'
$GoogleMenu = Join-Path $ProjectRoot 'tools\challenger_account_menu.ps1'
$GoogleRuntime = Join-Path $ProjectRoot 'tools\google_project_runtime.ps1'
$ActionsRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot '.runtime\dashboard\actions'))

function Write-ActionStatus {
    param([Parameter(Mandatory = $true)][string]$Status, [int]$ExitCode = 0)
    if ([string]::IsNullOrWhiteSpace($StatusPath)) { return }
    $Target = [System.IO.Path]::GetFullPath($StatusPath)
    $Prefix = $ActionsRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $Target.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase) -or [System.IO.Path]::GetExtension($Target) -ne '.json') { throw 'Invalid dashboard action status path.' }
    [System.IO.Directory]::CreateDirectory($ActionsRoot) | Out-Null
    $Temporary = "$Target.$PID.tmp"
    $Payload = [ordered]@{ schemaVersion = 1; status = $Status; pid = $PID; exitCode = $ExitCode; observedAt = [DateTime]::UtcNow.ToString('o') }
    [System.IO.File]::WriteAllText($Temporary, ($Payload | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $Temporary -Destination $Target -Force
}

try {
    Write-ActionStatus -Status 'terminal_ready'
    switch ($Action) {
        'launch-new' {
            $Host.UI.RawUI.WindowTitle = "Claude CLI - $Value"
            & $RouterMenu -Root $ProjectRoot -LaunchProfileId $Value -ClaudeSessionId $Extra -ClaudeSessionName $Label -LaunchStatusPath $StatusPath
        }
        'launch-resume' {
            $Host.UI.RawUI.WindowTitle = "Claude CLI - tiếp tục $Label"
            & $RouterMenu -Root $ProjectRoot -LaunchProfileId $Value -ClaudeSessionId $Extra -ClaudeSessionName $Label -ResumeClaudeSession -LaunchStatusPath $StatusPath
        }
        'launch-google-new' {
            $Host.UI.RawUI.WindowTitle = "Claude CLI - Google $Value [$Extra]"
            & $GoogleRuntime -Root $ProjectRoot -Action Launch -Slot $Value -Model $Extra -SessionId $Label -SessionName $Meta -LaunchStatusPath $StatusPath
        }
        'launch-google-resume' {
            $Host.UI.RawUI.WindowTitle = "Claude CLI - tiếp tục Google $Value [$Extra]"
            & $GoogleRuntime -Root $ProjectRoot -Action Launch -Slot $Value -Model $Extra -SessionId $Label -SessionName $Meta -ResumeSession -LaunchStatusPath $StatusPath
        }
        'codex' {
            $Host.UI.RawUI.WindowTitle = 'Claude CLI - đăng nhập Codex'
            & $RouterMenu -Root $ProjectRoot -AddCodexPlan $Value
        }
        'codex-resume' {
            $Host.UI.RawUI.WindowTitle = 'Claude CLI - hoàn tất Codex'
            & $RouterMenu -Root $ProjectRoot -AddCodexPlan $Value -CodexAccountName $Extra
        }
        'google' {
            $Host.UI.RawUI.WindowTitle = 'Claude CLI - đăng nhập Google'
            & $GoogleMenu -Root $ProjectRoot -AddSlot $Value -GoogleLoginHint $Extra
        }
    }
    $ExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
}
catch {
    try { Write-ActionStatus -Status 'failed' -ExitCode 1 } catch { }
    Write-Error $_
    $ExitCode = 1
}

if ($Action -like 'launch-*') { exit $ExitCode }
Write-Host ''
if ($ExitCode -eq 0) {
    Write-Host '[OK] Hoàn tất. Cửa sổ này sẽ tự đóng.' -ForegroundColor Green
    Start-Sleep -Seconds 2
}
else {
    Write-Host "[ERROR] Thao tác kết thúc với mã $ExitCode." -ForegroundColor Red
    [void](Read-Host 'Nhấn Enter để đóng sau khi đã đọc lỗi')
}
exit $ExitCode
