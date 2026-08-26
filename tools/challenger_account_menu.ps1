#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot ".."),
    [switch]$SelfTest,
    [string]$AddSlot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = [System.IO.Path]::GetFullPath($Root)
$RuntimeRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot ".runtime\challenger"))
$AccountsRoot = [System.IO.Path]::GetFullPath((Join-Path $RuntimeRoot "accounts\google"))
$BinaryPath = [System.IO.Path]::GetFullPath((Join-Path $RuntimeRoot "bin\cli-proxy-api.exe"))
$BuildPath = Join-Path $ProjectRoot "router_challenger\BUILD.json"
$SourcePath = Join-Path $ProjectRoot "router_challenger\SOURCE.json"
$BatchPath = Join-Path $ProjectRoot "router_challenger\account-batch.example.json"
$TemplatePath = Join-Path $ProjectRoot "router_challenger\account-config.template.yaml"

function Get-GoogleSlotNumber {
    param([Parameter(Mandatory = $true)][string]$Slot)
    if ($Slot -notmatch '^google_pro_([1-9][0-9]{0,2})$') { return 0 }
    $Number = [int]$Matches[1]
    if ($Number -lt 1 -or $Number -gt 50) { return 0 }
    return $Number
}

function Get-GoogleCallbackPort {
    param([Parameter(Mandatory = $true)][string]$Slot)
    $Number = Get-GoogleSlotNumber -Slot $Slot
    if ($Number -eq 0) { throw "Unknown Google Pro slot: $Slot" }
    return (51120 + $Number)
}

function Get-GoogleSlots {
    $Slots = @()
    if (Test-Path -LiteralPath $AccountsRoot -PathType Container) {
        $Slots = @(Get-ChildItem -LiteralPath $AccountsRoot -Directory -ErrorAction Stop |
            Where-Object { (Get-GoogleSlotNumber -Slot $_.Name) -gt 0 } |
            Sort-Object { Get-GoogleSlotNumber -Slot $_.Name } |
            ForEach-Object { $_.Name })
    }
    return @($Slots)
}

function Get-NextGoogleSlot {
    $Occupied = @{}
    foreach ($Slot in @(Get-GoogleSlots)) { $Occupied[$Slot] = $true }
    for ($Index = 1; $Index -le 50; $Index++) {
        $Candidate = "google_pro_$Index"
        if (-not $Occupied.ContainsKey($Candidate)) { return $Candidate }
    }
    throw "All 50 project-local Google slots are occupied."
}

function Assert-ProjectChild {
    param([Parameter(Mandatory = $true)][string]$Path)
    $Resolved = [System.IO.Path]::GetFullPath($Path)
    $Prefix = $ProjectRoot.TrimEnd('\') + '\'
    if (-not $Resolved.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes project root: $Resolved"
    }
    return $Resolved
}

function Get-RandomLocalValue {
    $Bytes = New-Object byte[] 32
    $Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $Rng.GetBytes($Bytes) } finally { $Rng.Dispose() }
    return ([Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_'))
}

function Protect-DirectoryForCurrentUser {
    param([Parameter(Mandatory = $true)][string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $Sid = $Identity.User
    $Acl = Get-Acl -LiteralPath $Path
    $Acl.SetAccessRuleProtection($true, $false)
    foreach ($Rule in @($Acl.Access)) { [void]$Acl.RemoveAccessRuleSpecific($Rule) }
    $Inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $Propagation = [System.Security.AccessControl.PropagationFlags]::None
    $Access = [System.Security.AccessControl.AccessControlType]::Allow
    $Rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Sid,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $Inheritance,
        $Propagation,
        $Access
    )
    $Acl.SetOwner($Sid)
    $Acl.AddAccessRule($Rule)
    Set-Acl -LiteralPath $Path -AclObject $Acl
    $Verified = Get-Acl -LiteralPath $Path
    foreach ($Entry in @($Verified.Access)) {
        $EntrySid = $Entry.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier])
        if ($Entry.IsInherited -or $Entry.AccessControlType -ne 'Allow' -or $EntrySid.Value -ne $Sid.Value) {
            throw "Account ACL contains an unexpected access rule."
        }
    }
    if (@($Verified.Access).Count -lt 1) { throw "Account ACL has no current-user rule." }
}

function Assert-AccountRuntime {
    foreach ($Path in @($BuildPath, $SourcePath, $BatchPath, $TemplatePath)) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required account component is missing: $Path" }
    }
    if (-not (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) {
        throw "Project-local challenger binary is missing. Run tools\install_challenger_pilot.ps1 explicitly."
    }
    $Build = Get-Content -Raw -LiteralPath $BuildPath | ConvertFrom-Json
    $ObservedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $BinaryPath).Hash.ToLowerInvariant()
    if ($ObservedHash -ne ([string]$Build.binary.sha256).ToLowerInvariant()) { throw "Project-local challenger binary hash mismatch." }
    $Source = Get-Content -Raw -LiteralPath $SourcePath | ConvertFrom-Json
    if ($Source.policy.oauth_callback_loopback_only -ne $true) { throw "OAuth callback loopback policy is not pinned." }
    $PatchFiles = @($Source.patches | ForEach-Object { [string]$_.file })
    if ($PatchFiles -notcontains "router_challenger/patches/0001-fix-bind-antigravity-oauth-callback-to-loopback.patch") {
        throw "Reviewed Antigravity callback patch is not pinned."
    }
}

function Get-SlotState {
    param([Parameter(Mandatory = $true)][string]$Slot)
    $SlotRoot = Assert-ProjectChild -Path (Join-Path $AccountsRoot $Slot)
    $AuthDir = Assert-ProjectChild -Path (Join-Path $SlotRoot "auth")
    $Marker = Assert-ProjectChild -Path (Join-Path $SlotRoot "completed.json")
    $AuthFiles = if (Test-Path -LiteralPath $AuthDir -PathType Container) { @(Get-ChildItem -LiteralPath $AuthDir -Filter "*.json" -File -ErrorAction Stop) } else { @() }
    return [PSCustomObject]@{
        slot = $Slot
        root = $SlotRoot
        authDir = $AuthDir
        marker = $Marker
        complete = ((Test-Path -LiteralPath $Marker -PathType Leaf) -and $AuthFiles.Count -eq 1)
        authFileCount = $AuthFiles.Count
    }
}

function Write-AccountConfig {
    param([Parameter(Mandatory = $true)]$State)
    Protect-DirectoryForCurrentUser -Path ([string]$State.root)
    Protect-DirectoryForCurrentUser -Path ([string]$State.authDir)
    $ConfigPath = Assert-ProjectChild -Path (Join-Path ([string]$State.root) "config.yaml")
    $Template = Get-Content -Raw -LiteralPath $TemplatePath
    $SafeAuth = ([string]$State.authDir).Replace('\', '/')
    $Text = $Template.Replace("__AUTH_DIR__", $SafeAuth).Replace("__CLIENT_KEY__", (Get-RandomLocalValue)).Replace("__MANAGEMENT_KEY__", (Get-RandomLocalValue))
    [System.IO.File]::WriteAllText($ConfigPath, $Text, (New-Object System.Text.UTF8Encoding($false)))
    return $ConfigPath
}

function Assert-CallbackPortFree {
    param([Parameter(Mandatory = $true)][int]$Port)
    $Listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
    if ($null -ne $Listener) { throw "OAuth callback port $Port is already in use." }
}

function Add-GoogleAccount {
    param([Parameter(Mandatory = $true)][string]$Slot)
    if ((Get-GoogleSlotNumber -Slot $Slot) -eq 0) { throw "Unknown Google Pro slot: $Slot" }
    Assert-AccountRuntime
    $State = Get-SlotState -Slot $Slot
    if ($State.complete) {
        Write-Host "Slot '$Slot' is already signed in. No credential was changed." -ForegroundColor Yellow
        return
    }
    if ($State.authFileCount -gt 0) { throw "Slot '$Slot' has incomplete credential state; inspect/remove only that slot before retrying." }
    $Port = Get-GoogleCallbackPort -Slot $Slot
    Assert-CallbackPortFree -Port $Port
    $ConfigPath = Write-AccountConfig -State $State
    Write-Host ""
    Write-Host "Opening official Google OAuth for $Slot..." -ForegroundColor Cyan
    Write-Host "Choose the intended Google AI Pro account in the browser and complete 2FA there." -ForegroundColor DarkGray
    Write-Host "The callback listens only on 127.0.0.1:$Port; credentials stay in this slot." -ForegroundColor DarkGray
    Push-Location ([string]$State.root)
    try {
        & $BinaryPath -config $ConfigPath -antigravity-login -oauth-callback-port $Port -local-model
        $CommandExit = $LASTEXITCODE
    }
    finally { Pop-Location }
    if ($CommandExit -ne 0) { throw "Google OAuth helper exited with code $CommandExit." }
    $AuthFiles = @(Get-ChildItem -LiteralPath ([string]$State.authDir) -Filter "*.json" -File -ErrorAction Stop)
    if ($AuthFiles.Count -ne 1) { throw "Google OAuth did not leave exactly one project-local credential file for '$Slot'." }
    $MarkerPayload = [ordered]@{
        schema_version = 1
        slot = $Slot
        provider = "google_ai"
        expected_plan = "google_ai_pro"
        usage_groups = @("gemini_models", "claude_gpt_models")
        authenticated_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    [System.IO.File]::WriteAllText(([string]$State.marker), ($MarkerPayload | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
    Protect-DirectoryForCurrentUser -Path ([string]$State.root)
    if ($null -ne (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)) { throw "OAuth callback listener did not close cleanly." }
    Write-Host "Google AI Pro slot '$Slot' is ready in project-local state." -ForegroundColor Green
}

function Show-GoogleAccounts {
    Write-Host ""
    Write-Host "Google AI Pro project-local slots:" -ForegroundColor Cyan
    $Slots = @(Get-GoogleSlots)
    if ($Slots.Count -eq 0) { Write-Host "  (no Google account slot has been created yet)" -ForegroundColor DarkGray }
    foreach ($Slot in $Slots) {
        $State = Get-SlotState -Slot $Slot
        $Status = if ($State.complete) { "signed in" } elseif ($State.authFileCount -gt 0) { "incomplete" } else { "not signed in" }
        Write-Host ("  - {0}: {1}" -f $Slot, $Status)
    }
}

function Select-GoogleSlot {
    Show-GoogleAccounts
    Write-Host ""
    $GoogleSlots = @((Get-GoogleSlots) + (Get-NextGoogleSlot)) | Select-Object -Unique
    for ($Index = 0; $Index -lt $GoogleSlots.Count; $Index++) { Write-Host ("  [{0}] {1}" -f ($Index + 1), $GoogleSlots[$Index]) }
    $Choice = (Read-Host "Google Pro slot number").Trim()
    if ($Choice -notmatch '^\d+$') { throw "Invalid Google Pro slot selection." }
    $Selected = [int]$Choice
    if ($Selected -lt 1 -or $Selected -gt $GoogleSlots.Count) { throw "Invalid Google Pro slot selection." }
    return $GoogleSlots[$Selected - 1]
}

function Invoke-SelfTest {
    Assert-AccountRuntime
    $Template = Get-Content -Raw -LiteralPath $TemplatePath
    foreach ($Required in @('host: "127.0.0.1"', 'auth-dir: "__AUTH_DIR__"', 'allow-remote: false', 'disable-control-panel: true', 'usage-statistics-enabled: false')) {
        if ($Template.IndexOf($Required, [System.StringComparison]::Ordinal) -lt 0) { throw "Account template safety marker is missing: $Required" }
    }
    if ((Get-GoogleCallbackPort -Slot "google_pro_1") -ne 51121 -or (Get-GoogleCallbackPort -Slot "google_pro_50") -ne 51170) { throw "Google Pro slot/callback contract is invalid." }
    Write-Output "PASS: Google Pro OAuth account helper is project-local, hash-pinned and loopback-callback-only"
    Write-Output "PASS: self-test opened no browser and read no credential file"
}

if ($SelfTest) { Invoke-SelfTest; exit 0 }
if ($AddSlot) { Add-GoogleAccount -Slot $AddSlot; exit 0 }
while ($true) {
    try { Clear-Host } catch { }
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  GOOGLE AI PRO - PROJECT-LOCAL SIGN-IN" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  [A] Add/sign in one Google AI Pro slot"
    Write-Host "  [L] List project-local Google AI Pro slots"
    Write-Host "  [Q] Back"
    Write-Host ""
    $Choice = (Read-Host "Select an action").Trim().ToLowerInvariant()
    try {
        switch ($Choice) {
            "a" { Add-GoogleAccount -Slot (Select-GoogleSlot) }
            "l" { Show-GoogleAccounts }
            "q" { return }
            default { Write-Host "Invalid selection." -ForegroundColor Yellow }
        }
    }
    catch { Write-Host ("[ERROR] " + $_.Exception.Message) -ForegroundColor Red }
    Read-Host "Press Enter to continue" | Out-Null
}
