#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Launch', 'Stop', 'Status', 'Verify', 'SelfTest')]
    [string]$Action,
    [string]$Slot,
    [string]$Model,
    [string]$SessionId,
    [string]$SessionName,
    [switch]$ResumeSession,
    [string]$LaunchStatusPath,
    [string]$Root = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).Path)
$RuntimeRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot '.runtime\challenger\google-runtime'))
$AccountsRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot '.runtime\challenger\accounts\google'))
$BinaryPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot '.runtime\challenger\bin\cli-proxy-api.exe'))
$ClaudeBinary = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'bin\claude.exe'))
$ClaudeHome = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot '.runtime\claude-home'))
$BuildPath = Join-Path $ProjectRoot 'router_challenger\BUILD.json'
$ModelManifestPath = Join-Path $ProjectRoot 'router_challenger\google-runtime-models.json'
$TemplatePath = Join-Path $ProjectRoot 'router_challenger\account-config.template.yaml'
$SettingPath = Join-Path $ProjectRoot 'setting.json'
$ActionsRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot '.runtime\dashboard\actions'))

function Assert-ProjectChild {
    param([Parameter(Mandatory = $true)][string]$Path)
    $Resolved = [System.IO.Path]::GetFullPath($Path)
    $Prefix = $ProjectRoot.TrimEnd('\') + '\'
    if (-not $Resolved.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes the project root: $Resolved"
    }
    return $Resolved
}

function Get-SlotNumber {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -notmatch '^google_pro_([1-9][0-9]{0,1})$') { throw 'Invalid project-local Google slot.' }
    $Number = [int]$Matches[1]
    if ($Number -lt 1 -or $Number -gt 50) { throw 'Google slot is outside the supported range.' }
    return $Number
}

function Get-SlotState {
    param([Parameter(Mandatory = $true)][string]$Value)
    $Number = Get-SlotNumber -Value $Value
    $SlotRoot = Assert-ProjectChild -Path (Join-Path $AccountsRoot $Value)
    $AuthDir = Assert-ProjectChild -Path (Join-Path $SlotRoot 'auth')
    $AuthFiles = @(if (Test-Path -LiteralPath $AuthDir -PathType Container) {
        Get-ChildItem -LiteralPath $AuthDir -File -Filter '*.json'
    })
    if (-not (Test-Path -LiteralPath (Join-Path $SlotRoot 'completed.json') -PathType Leaf) -or $AuthFiles.Count -ne 1) {
        throw 'Google account is not completely signed in inside this project.'
    }
    $RunRoot = Assert-ProjectChild -Path (Join-Path $RuntimeRoot $Value)
    return [pscustomobject]@{
        Number = $Number
        SlotRoot = $SlotRoot
        AuthDir = $AuthDir
        RunRoot = $RunRoot
        Port = 18400 + $Number
        ConfigPath = Join-Path $RunRoot 'config.yaml'
        ClientKeyPath = Join-Path $RunRoot 'client-key.txt'
        PidPath = Join-Path $RunRoot 'proxy.pid'
        LogPrefix = Join-Path $RunRoot 'proxy'
    }
}

function Get-BuildManifest {
    if (-not (Test-Path -LiteralPath $BuildPath -PathType Leaf)) { throw 'Missing router_challenger\BUILD.json.' }
    return (Get-Content -Raw -LiteralPath $BuildPath | ConvertFrom-Json)
}

function Get-ModelManifest {
    if (-not (Test-Path -LiteralPath $ModelManifestPath -PathType Leaf)) { throw 'Missing Google runtime compatibility manifest.' }
    return (Get-Content -Raw -LiteralPath $ModelManifestPath | ConvertFrom-Json)
}

function Assert-BinaryIdentity {
    $Build = Get-BuildManifest
    $Models = Get-ModelManifest
    if (-not (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) {
        throw 'The project-local Google runtime binary is missing. Run tools\build_challenger.ps1 explicitly.'
    }
    $Expected = ([string]$Build.binary.sha256).ToLowerInvariant()
    if ($Expected -ne ([string]$Models.binary_sha256).ToLowerInvariant()) {
        throw 'Google compatibility manifest does not match the pinned runtime binary.'
    }
    $Observed = (Get-FileHash -Algorithm SHA256 -LiteralPath $BinaryPath).Hash.ToLowerInvariant()
    if ($Observed -ne $Expected) { throw 'Project-local Google runtime binary hash mismatch.' }
}

function Assert-SupportedModel {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -notmatch '^[a-z0-9][a-z0-9_.-]{0,127}$') { throw 'Invalid Google model identifier.' }
    $Supported = @((Get-ModelManifest).models | ForEach-Object { [string]$_ })
    if ($Value -notin $Supported) {
        throw 'This model is present in Google catalog but is not supported by the pinned local runtime yet.'
    }
}

function Get-RandomLocalValue {
    $Bytes = New-Object byte[] 32
    $Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $Rng.GetBytes($Bytes) } finally { $Rng.Dispose() }
    return ([Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_'))
}

function Protect-DirectoryForCurrentUser {
    param([Parameter(Mandatory = $true)][string]$Path)
    [System.IO.Directory]::CreateDirectory($Path) | Out-Null
    $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $Sid = $Identity.User
    $Acl = Get-Acl -LiteralPath $Path
    $Acl.SetAccessRuleProtection($true, $false)
    foreach ($Rule in @($Acl.Access)) { [void]$Acl.RemoveAccessRuleSpecific($Rule) }
    $Inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $Rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Sid,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $Inheritance,
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $Acl.SetOwner($Sid)
    $Acl.AddAccessRule($Rule)
    Set-Acl -LiteralPath $Path -AclObject $Acl
}

function Get-OrCreateClientKey {
    param([Parameter(Mandatory = $true)]$State)
    if (-not (Test-Path -LiteralPath $State.RunRoot -PathType Container)) {
        Protect-DirectoryForCurrentUser -Path $State.RunRoot
    }
    if (Test-Path -LiteralPath $State.ClientKeyPath -PathType Leaf) {
        $Existing = (Get-Content -Raw -LiteralPath $State.ClientKeyPath).Trim()
        if ($Existing -match '^[A-Za-z0-9_-]{40,80}$') { return $Existing }
        throw 'Project-local Google client key file is invalid.'
    }
    $ClientKey = Get-RandomLocalValue
    [System.IO.File]::WriteAllText($State.ClientKeyPath, $ClientKey, (New-Object System.Text.UTF8Encoding($false)))
    return $ClientKey
}

function Write-RuntimeConfig {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$ClientKey
    )
    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) { throw 'Missing account config template.' }
    $Content = Get-Content -Raw -LiteralPath $TemplatePath
    $Content = $Content.Replace('__PROXY_PORT__', [string]$State.Port)
    $Content = $Content.Replace('__AUTH_DIR__', ([string]$State.AuthDir).Replace('\', '/'))
    $Content = $Content.Replace('__CLIENT_KEY__', $ClientKey)
    $Content = $Content.Replace('__MANAGEMENT_KEY__', (Get-RandomLocalValue))
    if ($Content -match '__[A-Z0-9_]+__') { throw 'Google runtime config contains an unresolved placeholder.' }
    [System.IO.File]::WriteAllText($State.ConfigPath, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Assert-ProcessIdentity {
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    $Process = Get-Process -Id $ProcessId -ErrorAction Stop
    $Observed = [System.IO.Path]::GetFullPath($Process.Path)
    if (-not $Observed.Equals($BinaryPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Recorded PID $ProcessId is not the verified project-local Google runtime."
    }
    return $Process
}

function Assert-LoopbackListener {
    param([Parameter(Mandatory = $true)][int]$ProcessId, [Parameter(Mandatory = $true)][int]$Port)
    $MatchesForPid = @()
    foreach ($Line in (& netstat.exe -ano -p tcp)) {
        if ($Line -match '^\s*TCP\s+(\S+):(\d+)\s+(\S+):(\d+)\s+LISTENING\s+(\d+)\s*$') {
            if ([int]$Matches[2] -eq $Port -and [int]$Matches[5] -eq $ProcessId) { $MatchesForPid += $Matches[1] }
        }
    }
    if ($MatchesForPid.Count -ne 1 -or $MatchesForPid[0] -ne '127.0.0.1') {
        throw "Google runtime must listen exactly on 127.0.0.1:$Port."
    }
}

function Read-ModelsFromRuntime {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$ClientKey,
        [int]$TimeoutSeconds = 2
    )
    $Response = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:$($State.Port)/v1/models" `
        -Headers @{ Authorization = "Bearer $ClientKey" } -TimeoutSec $TimeoutSeconds
    return @($Response.data | ForEach-Object { [string]$_.id })
}

function Wait-RuntimeModel {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$ClientKey,
        [Parameter(Mandatory = $true)][string]$ExpectedModel,
        [int]$TimeoutMilliseconds = 10000
    )
    $Watch = [System.Diagnostics.Stopwatch]::StartNew()
    $Available = @()
    while ($Watch.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
        $Available = @(Read-ModelsFromRuntime -State $State -ClientKey $ClientKey)
        if ($ExpectedModel -in $Available) { return $Available }
        Start-Sleep -Milliseconds 150
    }
    return $Available
}

function Get-VerifiedRunningProxy {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$ClientKey)
    if (-not (Test-Path -LiteralPath $State.PidPath -PathType Leaf)) { return $null }
    $Recorded = (Get-Content -Raw -LiteralPath $State.PidPath).Trim()
    $ProcessId = 0
    if (-not [int]::TryParse($Recorded, [ref]$ProcessId)) { throw 'Google runtime PID file is invalid.' }
    try {
        $Process = Assert-ProcessIdentity -ProcessId $ProcessId
        Assert-LoopbackListener -ProcessId $ProcessId -Port $State.Port
        [void](Read-ModelsFromRuntime -State $State -ClientKey $ClientKey)
        return $Process
    }
    catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
        Remove-Item -Force -LiteralPath $State.PidPath -ErrorAction SilentlyContinue
        return $null
    }
}

function Start-VerifiedProxy {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$ClientKey)
    $Existing = Get-VerifiedRunningProxy -State $State -ClientKey $ClientKey
    if ($null -ne $Existing) { return $Existing }
    Write-RuntimeConfig -State $State -ClientKey $ClientKey
    $Process = Start-Process -FilePath $BinaryPath -ArgumentList @('-config', $State.ConfigPath, '-local-model') `
        -WorkingDirectory $State.RunRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput ($State.LogPrefix + '.stdout.log') `
        -RedirectStandardError ($State.LogPrefix + '.stderr.log')
    [System.IO.File]::WriteAllText($State.PidPath, [string]$Process.Id, (New-Object System.Text.UTF8Encoding($false)))
    $Watch = [System.Diagnostics.Stopwatch]::StartNew()
    $LastError = ''
    try {
        while ($Watch.ElapsedMilliseconds -lt 12000) {
            if ($Process.HasExited) { throw "Google runtime exited with code $($Process.ExitCode)." }
            try {
                [void](Read-ModelsFromRuntime -State $State -ClientKey $ClientKey)
                [void](Assert-ProcessIdentity -ProcessId $Process.Id)
                Assert-LoopbackListener -ProcessId $Process.Id -Port $State.Port
                return $Process
            }
            catch { $LastError = $_.Exception.Message }
            Start-Sleep -Milliseconds 100
        }
        throw "Google runtime readiness timed out. $LastError"
    }
    catch {
        try {
            [void](Assert-ProcessIdentity -ProcessId $Process.Id)
            Stop-Process -Id $Process.Id -Force
        } catch { }
        Remove-Item -Force -LiteralPath $State.PidPath -ErrorAction SilentlyContinue
        throw
    }
}

function Stop-VerifiedProxy {
    param([Parameter(Mandatory = $true)]$State)
    if (-not (Test-Path -LiteralPath $State.PidPath -PathType Leaf)) { return }
    $Recorded = (Get-Content -Raw -LiteralPath $State.PidPath).Trim()
    $ProcessId = 0
    if (-not [int]::TryParse($Recorded, [ref]$ProcessId)) { throw 'Google runtime PID file is invalid; refusing to stop an unverified process.' }
    try {
        $Process = Assert-ProcessIdentity -ProcessId $ProcessId
        Stop-Process -Id $Process.Id -Force
        $Process.WaitForExit(5000) | Out-Null
    }
    catch [Microsoft.PowerShell.Commands.ProcessCommandException] { }
    Remove-Item -Force -LiteralPath $State.PidPath -ErrorAction SilentlyContinue
}

function Write-ClaudeSettings {
    [System.IO.Directory]::CreateDirectory($ClaudeHome) | Out-Null
    $Setting = if (Test-Path -LiteralPath $SettingPath -PathType Leaf) { Get-Content -Raw -LiteralPath $SettingPath | ConvertFrom-Json } else { $null }
    $Defaults = if ($null -ne $Setting -and $null -ne $Setting.PSObject.Properties['claude_defaults']) { $Setting.claude_defaults } else { $null }
    $Telemetry = if ($null -ne $Defaults -and $null -ne $Defaults.PSObject.Properties['telemetry']) { [string]$Defaults.telemetry } else { '0' }
    $Allow = if ($null -ne $Defaults -and $null -ne $Defaults.PSObject.Properties['allow']) { @($Defaults.allow) } else { @() }
    $PermissionMode = if ($null -ne $Defaults -and $null -ne $Defaults.PSObject.Properties['permission_mode'] -and $Defaults.permission_mode) { [string]$Defaults.permission_mode } else { 'default' }
    $EffortLevel = if ($null -ne $Defaults -and $null -ne $Defaults.PSObject.Properties['effort_level'] -and $Defaults.effort_level) { [string]$Defaults.effort_level } else { 'high' }
    $Theme = if ($null -ne $Defaults -and $null -ne $Defaults.PSObject.Properties['theme'] -and $Defaults.theme) { [string]$Defaults.theme } else { 'dark' }
    $Payload = [ordered]@{
        env = [ordered]@{ CLAUDE_CODE_ENABLE_TELEMETRY = $Telemetry }
        permissions = [ordered]@{
            allow = $Allow
            defaultMode = $PermissionMode
        }
        effortLevel = $EffortLevel
        theme = $Theme
    }
    [System.IO.File]::WriteAllText((Join-Path $ClaudeHome 'settings.json'), ($Payload | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
}

function Write-LaunchStatus {
    if ([string]::IsNullOrWhiteSpace($LaunchStatusPath)) { return }
    $Target = [System.IO.Path]::GetFullPath($LaunchStatusPath)
    $Prefix = $ActionsRoot.TrimEnd('\') + '\'
    if (-not $Target.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase) -or [System.IO.Path]::GetExtension($Target) -ne '.json') {
        throw 'Invalid dashboard launch status path.'
    }
    [System.IO.Directory]::CreateDirectory($ActionsRoot) | Out-Null
    $Temporary = "$Target.$PID.tmp"
    $Payload = [ordered]@{ schemaVersion = 1; status = 'claude_starting'; pid = $PID; observedAt = [DateTime]::UtcNow.ToString('o') }
    [System.IO.File]::WriteAllText($Temporary, ($Payload | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $Temporary -Destination $Target -Force
}

function Start-Claude {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$ClientKey)
    if (-not (Test-Path -LiteralPath $ClaudeBinary -PathType Leaf)) { throw 'Only project-local bin\claude.exe is allowed, but it is missing.' }
    Assert-SupportedModel -Value $Model
    $Available = Wait-RuntimeModel -State $State -ClientKey $ClientKey -ExpectedModel $Model
    if ($Model -notin $Available) { throw 'The selected Google model is not exposed by the verified local runtime.' }
    $ParsedSession = [Guid]::Empty
    if (-not [Guid]::TryParseExact($SessionId, 'D', [ref]$ParsedSession)) { throw 'Invalid Claude session identifier.' }
    if ($SessionName -and ($SessionName.Length -gt 80 -or $SessionName -match '[\r\n]')) { throw 'Invalid Claude session name.' }
    Write-ClaudeSettings
    $Arguments = @('--model', $Model, '--prompt-suggestions', 'false')
    if ($ResumeSession) { $Arguments += @('--resume', $ParsedSession.ToString('D')) }
    else {
        $Arguments += @('--session-id', $ParsedSession.ToString('D'))
        if ($SessionName) { $Arguments += @('--name', $SessionName) }
    }
    $Saved = @{}
    $Names = @(
        'ANTHROPIC_BASE_URL',
        'ANTHROPIC_AUTH_TOKEN',
        'ANTHROPIC_API_KEY',
        'ANTHROPIC_MODEL',
        'ANTHROPIC_DEFAULT_HAIKU_MODEL',
        'ANTHROPIC_DEFAULT_SONNET_MODEL',
        'ANTHROPIC_DEFAULT_OPUS_MODEL',
        'CLAUDE_CONFIG_DIR',
        'DISABLE_AUTOUPDATER',
        'CLAUDE_CODE_MAX_RETRIES',
        'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC',
        'CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS',
        'CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK'
    )
    foreach ($Name in $Names) { $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process') }
    try {
        $env:ANTHROPIC_BASE_URL = "http://127.0.0.1:$($State.Port)"
        $env:ANTHROPIC_AUTH_TOKEN = $ClientKey
        Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
        $env:ANTHROPIC_MODEL = $Model
        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $Model
        $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $Model
        $env:ANTHROPIC_DEFAULT_OPUS_MODEL = $Model
        $env:CLAUDE_CONFIG_DIR = $ClaudeHome
        $env:DISABLE_AUTOUPDATER = '1'
        # Google/third-party routes can return a transient 429 for a large Claude
        # harness request even when a tiny provider probe succeeds. Keep the
        # terminal responsive and remove Anthropic-only background traffic.
        $env:CLAUDE_CODE_MAX_RETRIES = '2'
        $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
        $env:CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS = '1'
        $env:CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK = '1'
        Write-Host ("Launching Claude: Google {0} [{1}] -> local port {2}" -f $State.Number, $Model, $State.Port) -ForegroundColor Green
        Write-LaunchStatus
        & $ClaudeBinary @Arguments
        $ExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        return $ExitCode
    }
    finally {
        $env:ANTHROPIC_AUTH_TOKEN = ''
        foreach ($Name in $Saved.Keys) { [Environment]::SetEnvironmentVariable($Name, $Saved[$Name], 'Process') }
    }
}

function Invoke-SelfTest {
    Assert-ProjectChild -Path $RuntimeRoot | Out-Null
    Assert-ProjectChild -Path $AccountsRoot | Out-Null
    Assert-ProjectChild -Path $ClaudeHome | Out-Null
    Assert-BinaryIdentity
    $Manifest = Get-ModelManifest
    $Unique = @($Manifest.models | Sort-Object -Unique)
    if ($Unique.Count -ne @($Manifest.models).Count -or $Unique.Count -lt 1) { throw 'Google runtime model manifest is empty or contains duplicates.' }
    if ((Get-Content -Raw -LiteralPath $TemplatePath) -notmatch '__PROXY_PORT__') { throw 'Account config template is missing its port placeholder.' }
    Write-Host '[PASS] Project-local paths, pinned binary identity and Google runtime model manifest.'
}

try {
    if ($Action -eq 'SelfTest') { Invoke-SelfTest; exit 0 }
    $State = Get-SlotState -Value $Slot
    if ($Action -eq 'Stop' -and -not (Test-Path -LiteralPath $State.PidPath -PathType Leaf)) { exit 0 }
    Assert-BinaryIdentity
    if ($Action -eq 'Stop') { Stop-VerifiedProxy -State $State; exit 0 }
    $ClientKey = Get-OrCreateClientKey -State $State
    if ($Action -eq 'Status') {
        $Process = Get-VerifiedRunningProxy -State $State -ClientKey $ClientKey
        if ($null -eq $Process) { Write-Host '[OK] Google runtime is stopped.' }
        else { Write-Host "[OK] Google runtime PID $($Process.Id) is verified on 127.0.0.1:$($State.Port)." }
        exit 0
    }
    if ($Action -eq 'Verify') {
        $SelectedModel = if ($Model) { $Model } else { [string]@((Get-ModelManifest).models)[0] }
        Assert-SupportedModel -Value $SelectedModel
        try {
            [void](Start-VerifiedProxy -State $State -ClientKey $ClientKey)
            $Available = Wait-RuntimeModel -State $State -ClientKey $ClientKey -ExpectedModel $SelectedModel
            if ($SelectedModel -notin $Available) {
                throw ("Verified runtime did not expose the selected Google model. Available IDs: " + (($Available | Sort-Object -Unique) -join ', '))
            }
            Write-Host "[PASS] Verified Google runtime exposes $SelectedModel on 127.0.0.1:$($State.Port) without sending a model request."
        }
        finally { Stop-VerifiedProxy -State $State }
        exit 0
    }
    Assert-SupportedModel -Value $Model
    $Process = Start-VerifiedProxy -State $State -ClientKey $ClientKey
    [void]$Process
    exit (Start-Claude -State $State -ClientKey $ClientKey)
}
catch {
    Write-Error ("Project-local Google runtime failed: " + $_.Exception.Message)
    exit 1
}
