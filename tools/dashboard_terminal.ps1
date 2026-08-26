#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('launch-new', 'launch-resume', 'codex', 'codex-resume', 'google')]
    [string]$Action,
    [string]$Value,
    [string]$Extra,
    [string]$Label,
    [string]$Root = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $Root).Path
$RouterMenu = Join-Path $ProjectRoot 'tools\router_project_menu.ps1'
$GoogleMenu = Join-Path $ProjectRoot 'tools\challenger_account_menu.ps1'

try {
    switch ($Action) {
        'launch-new' {
            $Host.UI.RawUI.WindowTitle = "Claude CLI - $Value"
            & $RouterMenu -Root $ProjectRoot -LaunchProfileId $Value -ClaudeSessionId $Extra -ClaudeSessionName $Label
        }
        'launch-resume' {
            $Host.UI.RawUI.WindowTitle = "Claude CLI - tiếp tục $Label"
            & $RouterMenu -Root $ProjectRoot -LaunchProfileId $Value -ClaudeSessionId $Extra -ClaudeSessionName $Label -ResumeClaudeSession
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
