#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot ".."),
    [switch]$Launch,
    [switch]$SelfTest,
    [switch]$AccountMenu,
    [switch]$StopRouter,
    [switch]$SyncSettings,
    [switch]$WarmRouter,
    [ValidateSet("codex_free", "codex_plus")]
    [string]$AddCodexPlan,
    [string]$CodexAccountName,
    [string]$LaunchProfileId,
    [string]$ClaudeSessionId,
    [string]$ClaudeSessionName,
    [switch]$ResumeClaudeSession,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ClaudeArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ProjectRoot {
    param([Parameter(Mandatory = $true)][string]$Candidate)
    if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) {
        throw "Project root does not exist: $Candidate"
    }
    return (Resolve-Path -LiteralPath $Candidate).Path
}

$RootPath = Resolve-ProjectRoot -Candidate $Root
$SettingPath = Join-Path $RootPath "setting.json"
$SettingExamplePath = Join-Path $RootPath "setting.example.json"
$RouterRoot = Join-Path $RootPath "provider_router"
$RouterStateRoot = Join-Path $RouterRoot ".ccr-local"
$ModesRoot = Join-Path $RouterStateRoot "modes"
$NodePath = Join-Path $RouterRoot "runtime\node.exe"
$RouterCliPath = Join-Path $RouterRoot "node_modules\@musistudio\claude-code-router\dist\main\cli.js"
$ClaudeBinary = Join-Path $RootPath "bin\claude.exe"
$GatewayUrl = "http://127.0.0.1:3456"
$ManagementUrl = "http://127.0.0.1:3458"
$CcrHomePath = Join-Path $RouterStateRoot "home"
$CcrAppDataPath = Join-Path $RouterStateRoot "appdata"
$CcrUserDataPath = Join-Path $RouterStateRoot "userdata"
$ServiceStatePath = Join-Path (Join-Path $CcrAppDataPath "claude-code-router") "service.json"
$ConfigDatabasePath = Join-Path (Join-Path $CcrAppDataPath "claude-code-router") "config.sqlite"
$GlobalProfileTakeoverPath = Join-Path (Join-Path $CcrAppDataPath "claude-code-router") "global-profile-takeover.json"
$AppliedSettingHashPath = Join-Path $RouterStateRoot "setting.applied.sha256"
$RouterClientSecretPath = Join-Path $RouterStateRoot "router-client.dpapi"
$AccountProfilesPath = Join-Path $RouterStateRoot "account-profiles.json"
$CodexAccountsRoot = Join-Path $RouterStateRoot "codex-accounts"
$CodexLoginRuntimeRoot = Join-Path $RouterRoot "codex-login-runtime"
$CodexLoginBinary = Join-Path $CodexLoginRuntimeRoot "codex.exe"
$CodexLoginSourcePath = Join-Path $RouterRoot "CODEX_LOGIN_SOURCE.json"
$ClaudeHomePath = Join-Path $RootPath ".runtime\claude-home"
$ManagedProviderPrefix = "local-setting--"
$LocalAgentProviderApiKey = "ccr-local-agent-login"
$CodexAccountBaseUrl = "https://chatgpt.com/backend-api/codex"
$ProviderNamePlaceholder = "__CCR_PROVIDER_NAME__"
$ProviderNameSlugPlaceholder = "__CCR_PROVIDER_NAME_SLUG__"
$ProviderInternalNamePlaceholder = "__CCR_PROVIDER_INTERNAL_NAME__"
# The owner declares the expected plan before browser login. This avoids
# parsing credentials in the wrapper while keeping Free accounts away from Sol,
# which CCR's generic probe can falsely accept. Provider checks still decide
# which declared-plan candidates become routes.
$CodexChatGptModelsByPlan = @{
    codex_free = @("gpt-5.6-terra", "gpt-5.6-luna")
    codex_plus = @("gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna")
}
$UnsupportedCodexChatGptModels = @("gpt-5-codex")
$script:MenuExitCode = 0
$script:WarmupProcess = $null

# This wrapper authorizes CCR only as a project-local provider gateway. The
# upstream CLI otherwise synchronizes Claude App/profile configuration outside
# this folder. The bounded cold-start timeout is raised because Windows module
# loading on this machine exceeds CCR's upstream five-second IPC deadline.
$env:CCR_PROVIDER_GATEWAY_ONLY = "1"
$env:CCR_GATEWAY_CONFIG_ACCEPTANCE_TIMEOUT_MS = "20000"

function Assert-PathInside {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BasePath,
        [switch]$AllowBase
    )
    $FullBase = [System.IO.Path]::GetFullPath($BasePath).TrimEnd([char[]]@('\', '/'))
    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $Prefix = $FullBase + [System.IO.Path]::DirectorySeparatorChar
    $Comparison = [System.StringComparison]::OrdinalIgnoreCase
    if (($AllowBase -and [string]::Equals($FullPath, $FullBase, $Comparison)) -or $FullPath.StartsWith($Prefix, $Comparison)) {
        return $FullPath
    }
    throw "Unsafe path outside the project-local router state: $Path"
}

function Ensure-StateDirectories {
    foreach ($Path in @($RouterStateRoot, $ModesRoot, $CcrHomePath, $CcrAppDataPath, $CcrUserDataPath, $CodexAccountsRoot)) {
        $SafePath = Assert-PathInside -Path $Path -BasePath $RouterRoot
        if (-not (Test-Path -LiteralPath $SafePath)) {
            New-Item -ItemType Directory -Path $SafePath -Force | Out-Null
        }
    }
    if (-not (Test-Path -LiteralPath $ClaudeHomePath)) {
        New-Item -ItemType Directory -Path $ClaudeHomePath -Force | Out-Null
    }
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )
    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
    else { $Object.$Name = $Value }
}

function Get-ObjectPropertyValue {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $Member = Get-Member -InputObject $Object -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $Member) { return $null }
    return $Object.$Name
}

function Get-StringProperty {
    param($Object, [string]$Name, [string]$Default = "")
    $Value = Get-ObjectPropertyValue -Object $Object -Name $Name
    if ($null -eq $Value) { return $Default }
    return ([string]$Value).Trim()
}

function Get-BoolProperty {
    param($Object, [string]$Name, [bool]$Default = $true)
    $Value = Get-ObjectPropertyValue -Object $Object -Name $Name
    if ($null -eq $Value) { return $Default }
    if ($Value -isnot [bool]) { throw "'$Name' must be true or false." }
    return [bool]$Value
}

function Protect-SecureValue {
    param([Parameter(Mandatory = $true)][System.Security.SecureString]$Value)
    # No explicit key means ConvertFrom-SecureString uses Windows DPAPI.
    return ($Value | ConvertFrom-SecureString)
}

function Reveal-ProtectedValue {
    param([Parameter(Mandatory = $true)][string]$CipherText)
    $SecureValue = ConvertTo-SecureString -String $CipherText
    $Handle = [IntPtr]::Zero
    try {
        $Handle = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Handle)
    }
    finally {
        if ($Handle -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Handle) }
    }
}

function Write-ProtectedSecret {
    param([Parameter(Mandatory = $true)][string]$PlainText)
    $SafePath = Assert-PathInside -Path $RouterClientSecretPath -BasePath $RouterStateRoot
    $Secure = ConvertTo-SecureString -String $PlainText -AsPlainText -Force
    $CipherText = Protect-SecureValue -Value $Secure
    [System.IO.File]::WriteAllText($SafePath, $CipherText, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-ProtectedSecret {
    $SafePath = Assert-PathInside -Path $RouterClientSecretPath -BasePath $RouterStateRoot
    if (-not (Test-Path -LiteralPath $SafePath -PathType Leaf)) {
        throw "The project-local CCR client key has not been synchronized from setting.json yet."
    }
    $CipherText = (Get-Content -Raw -LiteralPath $SafePath).Trim()
    if ([string]::IsNullOrWhiteSpace($CipherText)) { throw "The DPAPI client-key record is empty." }
    return Reveal-ProtectedValue -CipherText $CipherText
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $Algorithm = [System.Security.Cryptography.SHA256]::Create()
    try { $Bytes = $Algorithm.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)) }
    finally { $Algorithm.Dispose() }
    return (($Bytes | ForEach-Object { $_.ToString("x2") }) -join "")
}

function ConvertTo-ProviderSlug {
    param([Parameter(Mandatory = $true)][string]$Value)
    $Slug = $Value.Trim().ToLowerInvariant() -replace '[^a-z0-9_.-]+', '-'
    $Slug = $Slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($Slug)) { return "provider" }
    return $Slug
}

function Replace-ProviderPluginPlaceholders {
    param(
        $Value,
        [Parameter(Mandatory = $true)][hashtable]$Replacements
    )
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        $Result = [string]$Value
        foreach ($Key in $Replacements.Keys) { $Result = $Result.Replace([string]$Key, [string]$Replacements[$Key]) }
        return $Result
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $Result = [ordered]@{}
        foreach ($Key in $Value.Keys) { $Result[[string]$Key] = Replace-ProviderPluginPlaceholders -Value $Value[$Key] -Replacements $Replacements }
        return [PSCustomObject]$Result
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $Result = [ordered]@{}
        foreach ($Property in $Value.PSObject.Properties) { $Result[$Property.Name] = Replace-ProviderPluginPlaceholders -Value $Property.Value -Replacements $Replacements }
        return [PSCustomObject]$Result
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $Items = @()
        foreach ($Item in $Value) { $Items += ,(Replace-ProviderPluginPlaceholders -Value $Item -Replacements $Replacements) }
        return ,$Items
    }
    return $Value
}

function Materialize-ProviderPlugins {
    param(
        [object[]]$Templates,
        [Parameter(Mandatory = $true)][string]$ProviderName,
        [Parameter(Mandatory = $true)][string]$Protocol,
        [Parameter(Mandatory = $true)][string]$ProviderId
    )
    $Replacements = @{
        $ProviderNamePlaceholder = $ProviderName
        $ProviderNameSlugPlaceholder = ConvertTo-ProviderSlug -Value $ProviderName
        $ProviderInternalNamePlaceholder = "${ProviderId}::$Protocol"
    }
    $Plugins = @()
    foreach ($Template in @($Templates)) { $Plugins += ,(Replace-ProviderPluginPlaceholders -Value $Template -Replacements $Replacements) }
    return ,$Plugins
}

function Merge-ProviderPlugins {
    param([object[]]$Current, [object[]]$Additions)
    $AddedKeys = @{}
    foreach ($Plugin in @($Additions)) {
        $Key = Get-StringProperty -Object $Plugin -Name "key"
        if ($Key) { $AddedKeys[$Key] = $true }
    }
    $Merged = @()
    foreach ($Plugin in @($Current)) {
        $Key = Get-StringProperty -Object $Plugin -Name "key"
        if (-not $Key -or -not $AddedKeys.ContainsKey($Key)) { $Merged += ,$Plugin }
    }
    return ,@($Merged + @($Additions))
}

function Read-AccountProfiles {
    param([string]$Path = $AccountProfilesPath)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    try { $Payload = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json }
    catch { throw "The project-local account profile index is invalid." }
    if ($null -eq $Payload -or [int]$Payload.schema_version -ne 1) { throw "The project-local account profile index has an unsupported schema." }
    $Profiles = @()
    foreach ($Profile in @($Payload.profiles)) {
        $Id = Get-StringProperty -Object $Profile -Name "id"
        $Name = Get-StringProperty -Object $Profile -Name "name"
        $Provider = Get-StringProperty -Object $Profile -Name "provider"
        $Model = Get-StringProperty -Object $Profile -Name "model"
        if ($Id -notmatch '^[a-z0-9][a-z0-9_.-]{0,62}$' -or -not $Name -or -not $Provider -or -not $Model) { throw "The project-local account profile index contains an invalid route." }
        $Profiles += [PSCustomObject][ordered]@{
            id = $Id; name = $Name; enabled = $true; provider = $Provider; model = $Model
            background_model = Get-StringProperty -Object $Profile -Name "background_model" -Default $Model
            think_model = Get-StringProperty -Object $Profile -Name "think_model" -Default $Model
            long_context_model = Get-StringProperty -Object $Profile -Name "long_context_model" -Default $Model
        }
    }
    return $Profiles
}

function Write-AccountProfiles {
    param([object[]]$Profiles, [string]$Path = $AccountProfilesPath)
    $SafePath = Assert-PathInside -Path $Path -BasePath $RouterStateRoot
    $Payload = [ordered]@{ schema_version = 1; profiles = @($Profiles) }
    [System.IO.File]::WriteAllText($SafePath, ($Payload | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
}

function Read-LocalSetting {
    param([string]$Path = $SettingPath)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "setting.json is missing. Start from setting.example.json: $Path"
    }
    $Raw = Get-Content -Raw -LiteralPath $Path
    try { $Data = $Raw | ConvertFrom-Json }
    catch { throw "setting.json is not valid JSON: $($_.Exception.Message)" }
    if ($null -eq $Data -or $null -eq $Data.PSObject.Properties["schema_version"] -or [int]$Data.schema_version -ne 1) {
        throw "setting.json must use schema_version 1."
    }

    $AllowedProtocols = @("anthropic_messages", "openai_chat_completions", "openai_responses", "gemini_generate_content", "gemini_interactions")
    $Providers = @()
    $ProviderIds = @{}
    $ProviderNames = @{}
    $RawProviders = if ($null -eq $Data.PSObject.Properties["providers"] -or $null -eq $Data.providers) { @() } else { @($Data.providers) }
    foreach ($Provider in $RawProviders) {
        $Id = Get-StringProperty -Object $Provider -Name "id"
        $Name = Get-StringProperty -Object $Provider -Name "name"
        $Enabled = Get-BoolProperty -Object $Provider -Name "enabled" -Default $true
        $BaseUrl = Get-StringProperty -Object $Provider -Name "base_url"
        $Protocol = Get-StringProperty -Object $Provider -Name "protocol"
        $ApiKey = Get-StringProperty -Object $Provider -Name "api_key"
        if ($Id -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Provider id '$Id' is invalid." }
        if ($ProviderIds.ContainsKey($Id)) { throw "Duplicate provider id: $Id" }
        if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 100 -or $Name -match '[\r\n/,]') { throw "Provider '$Id' has an invalid name." }
        if ($ProviderNames.ContainsKey($Name.ToLowerInvariant())) { throw "Duplicate provider name: $Name" }
        $Uri = $null
        if (-not [System.Uri]::TryCreate($BaseUrl, [System.UriKind]::Absolute, [ref]$Uri) -or $Uri.Scheme -notin @("http", "https") -or -not [string]::IsNullOrWhiteSpace($Uri.UserInfo)) {
            throw "Provider '$Name' must have an absolute HTTP(S) base_url without embedded credentials."
        }
        if ($Protocol -notin $AllowedProtocols) { throw "Provider '$Name' has unsupported protocol '$Protocol'." }
        $Models = @()
        if ($null -ne $Provider.PSObject.Properties["models"] -and $null -ne $Provider.models) {
            $Models = @($Provider.models | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
        }
        if ($Enabled -and $Models.Count -eq 0) { throw "Enabled provider '$Name' needs at least one model." }

        $Credentials = @()
        if ($null -ne $Provider.PSObject.Properties["credentials"] -and $null -ne $Provider.credentials) {
            $CredentialIndex = 0
            foreach ($Credential in @($Provider.credentials)) {
                $CredentialIndex++
                $CredentialKey = Get-StringProperty -Object $Credential -Name "api_key"
                $CredentialEnabled = Get-BoolProperty -Object $Credential -Name "enabled" -Default $true
                if ($CredentialEnabled -and [string]::IsNullOrWhiteSpace($CredentialKey)) { throw "Enabled credential $CredentialIndex for '$Name' has no api_key." }
                $CredentialObject = [ordered]@{
                    id = "$($ManagedProviderPrefix)$Id-key-$CredentialIndex"
                    name = Get-StringProperty -Object $Credential -Name "name" -Default "Key $CredentialIndex"
                    api_key = $CredentialKey
                    enabled = $CredentialEnabled
                    priority = $CredentialIndex
                    weight = 1
                }
                if ($null -ne $Credential.PSObject.Properties["priority"]) { $CredentialObject.priority = [int]$Credential.priority }
                if ($null -ne $Credential.PSObject.Properties["weight"]) { $CredentialObject.weight = [double]$Credential.weight }
                $Credentials += [PSCustomObject]$CredentialObject
            }
        }
        $EnabledCredentialCount = @($Credentials | Where-Object { $_.enabled -and -not [string]::IsNullOrWhiteSpace([string]$_.api_key) }).Count
        if ($Enabled -and [string]::IsNullOrWhiteSpace($ApiKey) -and $EnabledCredentialCount -eq 0) {
            throw "Enabled provider '$Name' needs api_key or an enabled credentials entry."
        }

        $ExtraHeaders = if ($null -ne $Provider.PSObject.Properties["extra_headers"]) { $Provider.extra_headers } else { $null }
        $ExtraBody = if ($null -ne $Provider.PSObject.Properties["extra_body"]) { $Provider.extra_body } else { $null }
        $Providers += [PSCustomObject][ordered]@{
            id = $Id
            name = $Name
            enabled = $Enabled
            base_url = $BaseUrl
            protocol = $Protocol
            api_key = $ApiKey
            credentials = @($Credentials)
            models = @($Models)
            extra_headers = $ExtraHeaders
            extra_body = $ExtraBody
        }
        $ProviderIds[$Id] = $true
        $ProviderNames[$Name.ToLowerInvariant()] = $true
    }

    $Defaults = [PSCustomObject][ordered]@{
        effort_level = "xhigh"
        theme = "dark"
        permission_mode = "acceptEdits"
        allow = @("Bash(*)", "PowerShell(*)", "WebSearch", "WebFetch(domain:github.com)")
        telemetry = "0"
    }
    if ($null -ne $Data.PSObject.Properties["claude_defaults"] -and $null -ne $Data.claude_defaults) {
        $InputDefaults = $Data.claude_defaults
        foreach ($Name in @("effort_level", "theme", "permission_mode", "telemetry")) {
            $Value = Get-StringProperty -Object $InputDefaults -Name $Name
            if (-not [string]::IsNullOrWhiteSpace($Value)) { Set-JsonProperty -Object $Defaults -Name $Name -Value $Value }
        }
        if ($null -ne $InputDefaults.PSObject.Properties["allow"] -and $null -ne $InputDefaults.allow) {
            $Defaults.allow = @($InputDefaults.allow | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
        }
    }
    if ($Defaults.effort_level -notin @("low", "medium", "high", "xhigh")) { throw "claude_defaults.effort_level is invalid." }

    $Profiles = @()
    $ProfileIds = @{}
    $RawProfiles = if ($null -eq $Data.PSObject.Properties["profiles"] -or $null -eq $Data.profiles) { @() } else { @($Data.profiles) }
    foreach ($Profile in $RawProfiles) {
        $Id = Get-StringProperty -Object $Profile -Name "id"
        $Name = Get-StringProperty -Object $Profile -Name "name"
        $ProviderName = Get-StringProperty -Object $Profile -Name "provider"
        $Model = Get-StringProperty -Object $Profile -Name "model"
        $Enabled = Get-BoolProperty -Object $Profile -Name "enabled" -Default $true
        if ($Id -notmatch '^[a-z0-9][a-z0-9-]{0,62}$' -or $ProfileIds.ContainsKey($Id)) { throw "Profile id '$Id' is invalid or duplicated." }
        if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($ProviderName) -or [string]::IsNullOrWhiteSpace($Model)) { throw "Profile '$Id' needs name, provider and model." }
        if ($ProviderName -match '[\r\n/,]' -or $Model -match '[\r\n,]') { throw "Profile '$Id' has an invalid provider or model." }
        $Profiles += [PSCustomObject][ordered]@{
            id = $Id
            name = $Name
            enabled = $Enabled
            provider = $ProviderName
            model = $Model
            background_model = Get-StringProperty -Object $Profile -Name "background_model" -Default $Model
            think_model = Get-StringProperty -Object $Profile -Name "think_model" -Default $Model
            long_context_model = Get-StringProperty -Object $Profile -Name "long_context_model" -Default $Model
        }
        $ProfileIds[$Id] = $true
    }
    return [PSCustomObject][ordered]@{
        hash = Get-TextSha256 -Text $Raw
        providers = @($Providers)
        profiles = @($Profiles)
        defaults = $Defaults
    }
}

function Get-ModelRoute {
    param([Parameter(Mandatory = $true)]$Profile, [Parameter(Mandatory = $true)][string]$Tier)
    $Model = switch ($Tier) {
        "background" { [string]$Profile.background_model }
        "think" { [string]$Profile.think_model }
        "long_context" { [string]$Profile.long_context_model }
        default { [string]$Profile.model }
    }
    if ([string]::IsNullOrWhiteSpace($Model)) { $Model = [string]$Profile.model }
    return ("{0}/{1}" -f ([string]$Profile.provider, $Model))
}

function Get-ModePath {
    param([Parameter(Mandatory = $true)][string]$Id)
    if ($Id -notmatch '^[a-z0-9][a-z0-9_.-]{0,62}$') { throw "Invalid profile identifier." }
    return (Assert-PathInside -Path (Join-Path $ModesRoot $Id) -BasePath $ModesRoot)
}

function Write-ModeSettings {
    param([Parameter(Mandatory = $true)]$Profile, [Parameter(Mandatory = $true)]$Defaults)
    $ModePath = Get-ModePath -Id ([string]$Profile.id)
    if (-not (Test-Path -LiteralPath $ModePath)) { New-Item -ItemType Directory -Path $ModePath -Force | Out-Null }
    $ClaudeSettings = [ordered]@{
        env = [ordered]@{ CLAUDE_CODE_ENABLE_TELEMETRY = [string]$Defaults.telemetry }
        permissions = [ordered]@{ allow = @($Defaults.allow); defaultMode = [string]$Defaults.permission_mode }
        effortLevel = [string]$Defaults.effort_level
        theme = [string]$Defaults.theme
    }
    $SettingsFile = Assert-PathInside -Path (Join-Path $ModePath "settings.json") -BasePath $ModesRoot
    [System.IO.File]::WriteAllText($SettingsFile, ($ClaudeSettings | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
    return $ModePath
}

function Write-CommonClaudeSettings {
    param([Parameter(Mandatory = $true)]$Defaults)
    $SafeHome = Assert-PathInside -Path $ClaudeHomePath -BasePath $RootPath
    if (-not (Test-Path -LiteralPath $SafeHome)) { New-Item -ItemType Directory -Path $SafeHome -Force | Out-Null }
    $ClaudeSettings = [ordered]@{
        env = [ordered]@{ CLAUDE_CODE_ENABLE_TELEMETRY = [string]$Defaults.telemetry }
        permissions = [ordered]@{ allow = @($Defaults.allow); defaultMode = [string]$Defaults.permission_mode }
        effortLevel = [string]$Defaults.effort_level
        theme = [string]$Defaults.theme
    }
    $SettingsFile = Assert-PathInside -Path (Join-Path $SafeHome "settings.json") -BasePath $SafeHome
    [System.IO.File]::WriteAllText($SettingsFile, ($ClaudeSettings | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
    return $SafeHome
}

function Assert-RouterRuntime {
    if (-not (Test-Path -LiteralPath $NodePath -PathType Leaf)) { throw "Project-local Node runtime is missing: $NodePath" }
    if (-not (Test-Path -LiteralPath $RouterCliPath -PathType Leaf)) { throw "Project-local CCR runtime is missing: $RouterCliPath" }
}

function Invoke-Ccr {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    Assert-RouterRuntime
    $Saved = @{}
    foreach ($Name in @("CCR_INTERNAL_HOME_DIR", "CCR_INTERNAL_APP_DATA_DIR", "CCR_INTERNAL_USER_DATA_DIR")) { $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process") }
    try {
        $env:CCR_INTERNAL_HOME_DIR = $CcrHomePath
        $env:CCR_INTERNAL_APP_DATA_DIR = $CcrAppDataPath
        $env:CCR_INTERNAL_USER_DATA_DIR = $CcrUserDataPath
        $Output = & $NodePath $RouterCliPath @Arguments 2>&1
        $Code = $LASTEXITCODE
        if ($Code -ne 0) {
            $CommandName = if ($Arguments.Count -gt 0) { [string]$Arguments[0] } else { "unknown" }
            throw "CCR command '$CommandName' failed (exit code $Code)."
        }
        return @($Output)
    }
    finally { foreach ($Name in $Saved.Keys) { [Environment]::SetEnvironmentVariable($Name, $Saved[$Name], "Process") } }
}

function Invoke-CcrStartAndVerify {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][scriptblock]$Verifier,
        [Parameter(Mandatory = $true)][string]$FailureMessage,
        [int]$Attempts = 20,
        [int]$DelayMilliseconds = 250,
        [scriptblock]$Starter
    )
    if ($null -eq $Starter) {
        $Starter = { param([string[]]$StartArguments) [void](Invoke-Ccr -Arguments $StartArguments) }
    }
    $StartError = $null
    try { [void](& $Starter $Arguments) }
    catch { $StartError = $_.Exception.Message }

    $LastError = "CCR service verification has not completed."
    for ($Attempt = 0; $Attempt -lt $Attempts; $Attempt++) {
        try { return (& $Verifier) }
        catch {
            $LastError = $_.Exception.Message
            if ($Attempt + 1 -lt $Attempts -and $DelayMilliseconds -gt 0) { Start-Sleep -Milliseconds $DelayMilliseconds }
        }
    }
    $StartContext = if ($StartError) { " Start command report: $StartError" } else { "" }
    throw "$FailureMessage $LastError$StartContext"
}

function Get-RpcToken {
    param([Parameter(Mandatory = $true)][System.Uri]$Uri)
    $Match = [regex]::Match($Uri.Query, '(?:^|[?&])ccr_web_token=([^&]+)')
    if (-not $Match.Success) { throw "CCR service URL does not contain its management token." }
    return [System.Uri]::UnescapeDataString($Match.Groups[1].Value)
}

function Invoke-RouterRpc {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Method,
        [object[]]$Arguments = @()
    )
    $Uri = [System.Uri]([string]$State.url)
    $Token = Get-RpcToken -Uri $Uri
    $Endpoint = $Uri.GetLeftPart([System.UriPartial]::Authority) + "/api/ccr/rpc"
    $Body = @{ method = $Method; args = @($Arguments) } | ConvertTo-Json -Depth 100 -Compress
    try {
        $Response = Invoke-RestMethod -Method Post -Uri $Endpoint -Headers @{ "x-ccr-web-auth" = $Token } -ContentType "application/json" -Body $Body -TimeoutSec 15
    }
    catch { throw "CCR management RPC '$Method' failed without exposing response credentials." }
    if ($null -eq $Response -or $Response.ok -ne $true) { throw "CCR management RPC '$Method' returned an unsuccessful result." }
    return $Response.value
}

function Assert-VerifiedManagementService {
    Assert-RouterRuntime
    if (-not (Test-Path -LiteralPath $ServiceStatePath -PathType Leaf)) { throw "CCR service state is missing." }
    try { $State = Get-Content -Raw -LiteralPath $ServiceStatePath | ConvertFrom-Json }
    catch { throw "CCR service state is unreadable or invalid JSON." }
    if ($null -eq $State.pid -or $null -eq $State.url -or $null -eq $State.serviceToken) { throw "CCR service state lacks PID, URL or service token." }
    try { $ServiceUri = [System.Uri]([string]$State.url) }
    catch { throw "CCR service state has an invalid URL." }
    if ($ServiceUri.Scheme -ne "http" -or $ServiceUri.Host -ne "127.0.0.1" -or $ServiceUri.Port -ne 3458) { throw "CCR management is not on the required loopback endpoint." }
    $ProcessId = 0
    if (-not [int]::TryParse([string]$State.pid, [ref]$ProcessId) -or $ProcessId -le 0) { throw "CCR service state has an invalid PID." }
    try { $RouterProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop }
    catch { throw "Cannot verify the CCR process recorded in local service state." }
    if ($null -eq $RouterProcess) { throw "The CCR process recorded in service state is not running." }
    $ExpectedNode = [System.IO.Path]::GetFullPath($NodePath)
    $ExpectedCli = [System.IO.Path]::GetFullPath($RouterCliPath)
    try { $ActualNode = [System.IO.Path]::GetFullPath([string]$RouterProcess.ExecutablePath) }
    catch { throw "Cannot verify the CCR executable path." }
    $CommandLine = [string]$RouterProcess.CommandLine
    if (-not [string]::Equals($ActualNode, $ExpectedNode, [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::IsNullOrWhiteSpace($CommandLine) -or
        $CommandLine.IndexOf($ExpectedNode, [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        $CommandLine.IndexOf($ExpectedCli, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "CCR process identity does not match the project-local runtime."
    }
    $Identity = Invoke-RouterRpc -State $State -Method "getServiceIdentity" -Arguments @([string]$State.serviceToken)
    if ($Identity.serviceTokenMatches -ne $true -or [int]$Identity.pid -ne $ProcessId) { throw "CCR service-token identity check failed." }
    return $State
}

function Ensure-ManagementService {
    return (Invoke-CcrStartAndVerify `
        -Arguments @("start", "--host", "127.0.0.1", "--port", "3458", "--no-open", "--no-gateway") `
        -Verifier { Assert-VerifiedManagementService } `
        -FailureMessage "CCR management verification failed:")
}

function Assert-VerifiedRouterService {
    $State = Assert-VerifiedManagementService
    try { $Health = Invoke-WebRequest -Uri "$GatewayUrl/health" -UseBasicParsing -TimeoutSec 3 }
    catch { throw "The verified CCR process did not answer the local gateway health check." }
    if ([int]$Health.StatusCode -ne 200) { throw "The verified CCR gateway health check did not return HTTP 200." }
    return $State
}

function Test-GatewayConfigAcceptanceTimeout {
    param([Parameter(Mandatory = $true)]$Status)
    if ($null -eq $Status) { return $false }
    $StateProperty = $Status.PSObject.Properties["state"]
    $ErrorProperty = $Status.PSObject.Properties["lastError"]
    if ($null -eq $StateProperty -or [string]$StateProperty.Value -ne "error" -or $null -eq $ErrorProperty) { return $false }
    return ([string]$ErrorProperty.Value -match '^Core gateway did not accept runtime config within [0-9]+ms\.$')
}

function Ensure-Router {
    # Fast path after background warmup (or when another project-local Claude
    # session already owns the verified gateway). This performs the full
    # process/loopback/health identity check and reads no DPAPI value.
    try { [void](Assert-VerifiedRouterService); return } catch { }

    if ($null -ne $script:WarmupProcess) {
        try {
            for ($WarmWait = 0; $WarmWait -lt 8 -and -not $script:WarmupProcess.HasExited; $WarmWait++) {
                Start-Sleep -Milliseconds 125
                try { [void](Assert-VerifiedRouterService); return } catch { }
            }
        }
        catch { }
    }

    $InitialFailure = $null
    try {
        [void](Invoke-CcrStartAndVerify `
            -Arguments @("start", "--host", "127.0.0.1", "--port", "3458", "--no-open", "--gateway") `
            -Verifier { Assert-VerifiedRouterService } `
            -FailureMessage "CCR gateway verification failed before any DPAPI client key was read.")
        return
    }
    catch { $InitialFailure = $_.Exception.Message }

    # On some Windows systems the first cold load of the gateway bundle exceeds
    # CCR's internal five-second IPC deadline. That failed attempt warms the
    # local files, so retry only this exact, verified error through management
    # RPC. Other gateway failures remain fail-closed and are never disguised.
    try {
        $State = Ensure-ManagementService
        $Status = Invoke-RouterRpc -State $State -Method "getGatewayStatus"
    }
    catch { throw "$InitialFailure Recovery status could not be verified." }
    if (-not (Test-GatewayConfigAcceptanceTimeout -Status $Status)) { throw $InitialFailure }

    $RetryFailure = "The cold-start retry did not produce a verified gateway."
    for ($Retry = 1; $Retry -le 2; $Retry++) {
        try { [void](Invoke-RouterRpc -State $State -Method "startGateway") }
        catch { $RetryFailure = "CCR management rejected cold-start retry $Retry." }
        try {
            [void](Invoke-CcrStartAndVerify `
                -Arguments @("cold-start-verification") `
                -Starter { param([string[]]$IgnoredArguments) } `
                -Verifier { Assert-VerifiedRouterService } `
                -FailureMessage "CCR cold-start retry $Retry was not verified:" `
                -Attempts 40 `
                -DelayMilliseconds 250)
            return
        }
        catch { $RetryFailure = $_.Exception.Message }
        try { $Status = Invoke-RouterRpc -State $State -Method "getGatewayStatus" }
        catch { break }
        if (-not (Test-GatewayConfigAcceptanceTimeout -Status $Status)) { break }
    }
    throw "$InitialFailure $RetryFailure"
}

function Start-RouterWarmup {
    # The menu must stay responsive: the child performs the same verified
    # startup path as route selection, but it never reaches setting/auth/profile
    # code. A failed child is deliberately non-fatal; route selection calls
    # Ensure-Router again and remains the fail-closed authority.
    if ($null -ne $script:WarmupProcess) {
        try {
            if (-not $script:WarmupProcess.HasExited) { return }
            if ([int]$script:WarmupProcess.ExitCode -eq 0) { return }
        }
        catch { }
        $script:WarmupProcess = $null
    }

    $PowerShellPath = if ($PSVersionTable.PSEdition -eq "Core") {
        Join-Path $PSHOME "pwsh.exe"
    }
    else {
        Join-Path $PSHOME "powershell.exe"
    }
    if (-not (Test-Path -LiteralPath $PowerShellPath -PathType Leaf)) {
        Write-Host "  Router warmup unavailable; route selection will verify startup synchronously." -ForegroundColor DarkGray
        return
    }

    $QuotedScriptPath = '"' + $PSCommandPath.Replace('"', '\"') + '"'
    $QuotedRootPath = '"' + $RootPath.Replace('"', '\"') + '"'
    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $StartInfo.FileName = $PowerShellPath
    $StartInfo.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File {0} -Root {1} -WarmRouter' -f $QuotedScriptPath, $QuotedRootPath
    $StartInfo.WorkingDirectory = $RootPath
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    try {
        $script:WarmupProcess = [System.Diagnostics.Process]::Start($StartInfo)
        if ($null -eq $script:WarmupProcess) { throw "PowerShell warmup process did not start." }
    }
    catch {
        $script:WarmupProcess = $null
        Write-Host "  Router warmup could not start; route selection will verify startup synchronously." -ForegroundColor DarkGray
    }
}

function ConvertTo-CcrProvider {
    param([Parameter(Mandatory = $true)]$Provider)
    $Result = [PSCustomObject][ordered]@{
        id = $ManagedProviderPrefix + [string]$Provider.id
        name = [string]$Provider.name
        enabled = [bool]$Provider.enabled
        api_base_url = [string]$Provider.base_url
        api_key = [string]$Provider.api_key
        credentials = @($Provider.credentials)
        models = @($Provider.models)
        type = [string]$Provider.protocol
        protocolDetectionMode = "manual"
    }
    if ($null -ne $Provider.extra_headers) { Set-JsonProperty -Object $Result -Name "extraHeaders" -Value $Provider.extra_headers }
    if ($null -ne $Provider.extra_body) { Set-JsonProperty -Object $Result -Name "extraBody" -Value $Provider.extra_body }
    return $Result
}

function Enforce-SafeCcrConfig {
    param([Parameter(Mandatory = $true)]$Config)
    Set-JsonProperty -Object $Config -Name "HOST" -Value "127.0.0.1"
    Set-JsonProperty -Object $Config -Name "PORT" -Value 3456
    Set-JsonProperty -Object $Config -Name "routerEndpoint" -Value $GatewayUrl
    Set-JsonProperty -Object $Config.gateway -Name "enabled" -Value $true
    Set-JsonProperty -Object $Config.gateway -Name "host" -Value "127.0.0.1"
    Set-JsonProperty -Object $Config.gateway -Name "port" -Value 3456
    Set-JsonProperty -Object $Config.proxy -Name "enabled" -Value $false
    Set-JsonProperty -Object $Config.proxy -Name "systemProxy" -Value $false
    Set-JsonProperty -Object $Config.proxy -Name "captureNetwork" -Value $false
    Set-JsonProperty -Object $Config.observability -Name "requestLogs" -Value $false
    # This project uses CCR only as the HTTP provider gateway behind Claude.
    # CCR agent profiles can write to ~/.codex, ~/.claude and desktop-app
    # configuration when their scope is "global" (System default). Remove all
    # of them so saveConfig(applyProfile=true) restores any previous takeover.
    if ($null -ne $Config.PSObject.Properties["profile"] -and $null -ne $Config.profile) {
        Set-JsonProperty -Object $Config.profile -Name "profiles" -Value @()
    }
    if ($null -ne $Config.Router -and $null -ne $Config.Router.builtInRules) {
        if ($null -ne $Config.Router.builtInRules.PSObject.Properties["claude-code"]) { Set-JsonProperty -Object $Config.Router.builtInRules."claude-code" -Name "enabled" -Value $true }
        if ($null -ne $Config.Router.builtInRules.PSObject.Properties["codex"]) { Set-JsonProperty -Object $Config.Router.builtInRules.codex -Name "enabled" -Value $false }
    }
    return $Config
}

function Merge-SettingIntoCcrConfig {
    param([Parameter(Mandatory = $true)]$CurrentConfig, [Parameter(Mandatory = $true)]$Setting)
    $Preserved = @($CurrentConfig.Providers | Where-Object { -not ([string]$_.id).StartsWith($ManagedProviderPrefix, [System.StringComparison]::OrdinalIgnoreCase) })
    $PreservedNames = @{}
    foreach ($Provider in $Preserved) { $PreservedNames[([string]$Provider.name).ToLowerInvariant()] = $true }
    $Managed = @()
    foreach ($Provider in @($Setting.providers)) {
        if ($PreservedNames.ContainsKey(([string]$Provider.name).ToLowerInvariant())) { throw "setting.json provider '$($Provider.name)' conflicts with a provider/account managed in CCR UI." }
        $Managed += ConvertTo-CcrProvider -Provider $Provider
    }
    Set-JsonProperty -Object $CurrentConfig -Name "Providers" -Value @($Preserved + $Managed)
    return (Enforce-SafeCcrConfig -Config $CurrentConfig)
}

function New-LocalClientKey {
    $Bytes = New-Object byte[] 32
    $Generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $Generator.GetBytes($Bytes) }
    finally { $Generator.Dispose() }
    return "ccr-local-" + [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Ensure-SettingApplied {
    param([switch]$Force)
    $Setting = Read-LocalSetting
    $HashMatches = $false
    if (Test-Path -LiteralPath $AppliedSettingHashPath -PathType Leaf) {
        $HashMatches = ((Get-Content -Raw -LiteralPath $AppliedSettingHashPath).Trim() -eq [string]$Setting.hash)
    }
    if (-not $Force -and $HashMatches -and
        (Test-Path -LiteralPath $ConfigDatabasePath -PathType Leaf) -and
        (Test-Path -LiteralPath $RouterClientSecretPath -PathType Leaf) -and
        -not (Test-Path -LiteralPath $GlobalProfileTakeoverPath -PathType Leaf)) {
        return $Setting
    }

    $State = Ensure-ManagementService
    $CurrentConfig = Invoke-RouterRpc -State $State -Method "getConfig"
    $NextConfig = Merge-SettingIntoCcrConfig -CurrentConfig $CurrentConfig -Setting $Setting
    $Options = [PSCustomObject]@{ applyProfile = $true }
    $SavedConfig = Invoke-RouterRpc -State $State -Method "saveConfig" -Arguments @($NextConfig, $Options)
    $ClientKeys = @($SavedConfig.APIKEYS)
    if ($ClientKeys.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$ClientKeys[0].key)) {
        $GeneratedKey = New-LocalClientKey
        $KeyRecord = [PSCustomObject][ordered]@{
            id = [Guid]::NewGuid().ToString("D")
            name = "Claude CLI local launcher"
            key = $GeneratedKey
            createdAt = (Get-Date).ToUniversalTime().ToString("o")
        }
        $RpcKeyArguments = New-Object object[] 1
        $RpcKeyArguments[0] = @($KeyRecord)
        $SavedConfig = Invoke-RouterRpc -State $State -Method "saveApiKeys" -Arguments $RpcKeyArguments
        $ClientKeys = @($SavedConfig.APIKEYS)
    }
    if ($ClientKeys.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$ClientKeys[0].key)) { throw "CCR did not provide a client key for the local Claude launcher." }
    Write-ProtectedSecret -PlainText ([string]$ClientKeys[0].key)
    [System.IO.File]::WriteAllText($AppliedSettingHashPath, ([string]$Setting.hash + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Applied setting.json to the project-local CCR database." -ForegroundColor Green
    return $Setting
}

function Start-Profile {
    param(
        [Parameter(Mandatory = $true)]$Profile,
        [Parameter(Mandatory = $true)]$Defaults,
        [string]$SessionId,
        [string]$SessionName,
        [switch]$ResumeSession
    )
    if (-not (Test-Path -LiteralPath $ClaudeBinary -PathType Leaf)) { throw "Only project-local bin\claude.exe is allowed, but it is missing." }
    if ($SessionId) {
        $ParsedSessionId = [Guid]::Empty
        if (-not [Guid]::TryParseExact($SessionId, "D", [ref]$ParsedSessionId)) { throw "Invalid Claude session identifier." }
        $SessionId = $ParsedSessionId.ToString("D")
    }
    if ($SessionName -and ($SessionName.Length -gt 80 -or $SessionName -match '[\r\n]')) { throw "Invalid Claude session name." }
    if ($ResumeSession -and -not $SessionId) { throw "A session identifier is required to resume Claude." }
    Ensure-Router
    $ClientKey = Read-ProtectedSecret
    $ModePath = if ($SessionId) { Write-CommonClaudeSettings -Defaults $Defaults } else { Write-ModeSettings -Profile $Profile -Defaults $Defaults }
    $EffectiveClaudeArguments = @($ClaudeArguments)
    if ($ResumeSession) {
        $EffectiveClaudeArguments += @("--resume", $SessionId)
    }
    elseif ($SessionId) {
        $EffectiveClaudeArguments += @("--session-id", $SessionId)
        if ($SessionName) { $EffectiveClaudeArguments += @("--name", $SessionName) }
    }
    $Saved = @{}
    $Names = @("ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL", "CLAUDE_CONFIG_DIR", "CCR_INTERNAL_HOME_DIR", "CCR_INTERNAL_APP_DATA_DIR", "CCR_INTERNAL_USER_DATA_DIR", "DISABLE_AUTOUPDATER")
    foreach ($Name in $Names) { $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process") }
    try {
        $env:ANTHROPIC_BASE_URL = $GatewayUrl
        $env:ANTHROPIC_AUTH_TOKEN = $ClientKey
        Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
        $env:ANTHROPIC_MODEL = Get-ModelRoute -Profile $Profile -Tier "default"
        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = Get-ModelRoute -Profile $Profile -Tier "background"
        $env:ANTHROPIC_DEFAULT_SONNET_MODEL = Get-ModelRoute -Profile $Profile -Tier "think"
        $env:ANTHROPIC_DEFAULT_OPUS_MODEL = Get-ModelRoute -Profile $Profile -Tier "long_context"
        $env:CLAUDE_CONFIG_DIR = $ModePath
        $env:CCR_INTERNAL_HOME_DIR = $CcrHomePath
        $env:CCR_INTERNAL_APP_DATA_DIR = $CcrAppDataPath
        $env:CCR_INTERNAL_USER_DATA_DIR = $CcrUserDataPath
        $env:DISABLE_AUTOUPDATER = "1"
        Write-Host ("Launching Claude: {0} -> {1}" -f $Profile.name, $env:ANTHROPIC_MODEL) -ForegroundColor Green
        & $ClaudeBinary @EffectiveClaudeArguments
        $script:MenuExitCode = $LASTEXITCODE
    }
    finally {
        $env:ANTHROPIC_AUTH_TOKEN = ""
        foreach ($Name in $Saved.Keys) { [Environment]::SetEnvironmentVariable($Name, $Saved[$Name], "Process") }
    }
}

function Show-RouterStatus {
    $State = Ensure-ManagementService
    $GatewayState = "stopped"
    try { [void](Assert-VerifiedRouterService); $GatewayState = "running and verified" } catch { }
    Write-Host "Management : $ManagementUrl (verified PID $($State.pid))"
    Write-Host "Gateway    : $GatewayUrl ($GatewayState)"
}

function Get-UniqueCodexAccountName {
    param([object[]]$Providers, [ValidateSet("codex_free", "codex_plus")][string]$ExpectedPlan = "codex_free")
    $Names = @{}
    foreach ($Provider in @($Providers)) { $Names[([string]$Provider.name).ToLowerInvariant()] = $true }
    $BaseName = if ($ExpectedPlan -eq "codex_plus") { "codex_plus" } else { "codex_free" }
    $Index = 1
    while ($Names.ContainsKey(("${BaseName}_$Index").ToLowerInvariant())) { $Index++ }
    return "${BaseName}_$Index"
}

function Get-UniqueProviderId {
    param([Parameter(Mandatory = $true)][string]$Name, [object[]]$Providers)
    $Ids = @{}
    foreach ($Provider in @($Providers)) { $Ids[([string]$Provider.id).ToLowerInvariant()] = $true }
    $Base = ConvertTo-ProviderSlug -Value $Name
    $Candidate = $Base
    $Index = 2
    while ($Ids.ContainsKey($Candidate.ToLowerInvariant())) { $Candidate = "$Base-$Index"; $Index++ }
    return $Candidate
}

function Resolve-CodexAccountSlot {
    param([Parameter(Mandatory = $true)][string]$Name, [object[]]$Providers)
    $ReservedProviders = @($Providers)
    $LabelHash = Get-TextSha256 -Text $Name
    while ($true) {
        $ProviderId = Get-UniqueProviderId -Name $Name -Providers $ReservedProviders
        $AccountHome = Assert-PathInside -Path (Join-Path $CodexAccountsRoot $ProviderId) -BasePath $CodexAccountsRoot
        $AuthPath = Assert-PathInside -Path (Join-Path $AccountHome "auth.json") -BasePath $AccountHome
        $LabelHashPath = Assert-PathInside -Path (Join-Path $AccountHome "account-label.sha256") -BasePath $AccountHome
        if (-not (Test-Path -LiteralPath $AccountHome -PathType Container)) {
            return [PSCustomObject]@{ providerId = $ProviderId; accountHome = $AccountHome; authPath = $AuthPath; labelHashPath = $LabelHashPath; labelHash = $LabelHash; resume = $false }
        }

        $MarkerMatches = $false
        if (Test-Path -LiteralPath $LabelHashPath -PathType Leaf) {
            $ObservedLabelHash = (Get-Content -Raw -LiteralPath $LabelHashPath).Trim()
            $MarkerMatches = $ObservedLabelHash.Equals($LabelHash, [System.StringComparison]::OrdinalIgnoreCase)
        }
        else {
            # Homes created before the label marker existed are safe to adopt
            # only under their exact first-choice slug. No auth content is read.
            $MarkerMatches = $true
        }
        if ($MarkerMatches) {
            return [PSCustomObject]@{ providerId = $ProviderId; accountHome = $AccountHome; authPath = $AuthPath; labelHashPath = $LabelHashPath; labelHash = $LabelHash; resume = (Test-Path -LiteralPath $AuthPath -PathType Leaf) }
        }
        $ReservedProviders += [PSCustomObject]@{ id = $ProviderId }
    }
}

function Write-CodexAccountLabelMarker {
    param([Parameter(Mandatory = $true)]$Slot)
    $SafeAccountHome = Assert-PathInside -Path ([string]$Slot.accountHome) -BasePath $CodexAccountsRoot
    if (-not (Test-Path -LiteralPath $SafeAccountHome -PathType Container)) { New-Item -ItemType Directory -Path $SafeAccountHome -Force | Out-Null }
    $SafeMarkerPath = Assert-PathInside -Path ([string]$Slot.labelHashPath) -BasePath $SafeAccountHome
    [System.IO.File]::WriteAllText($SafeMarkerPath, ([string]$Slot.labelHash + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
}

function Assert-LocalCodexLoginRuntime {
    $SafeRuntimeRoot = Assert-PathInside -Path $CodexLoginRuntimeRoot -BasePath $RouterRoot
    $SafeBinary = Assert-PathInside -Path $CodexLoginBinary -BasePath $SafeRuntimeRoot
    $SafeSource = Assert-PathInside -Path $CodexLoginSourcePath -BasePath $RouterRoot
    if (-not (Test-Path -LiteralPath $SafeBinary -PathType Leaf)) {
        throw "The project-local Codex login helper is missing. Run tools\install_codex_login_runtime.ps1, then retry."
    }
    if (-not (Test-Path -LiteralPath $SafeSource -PathType Leaf)) { throw "CODEX_LOGIN_SOURCE.json is missing." }
    $Source = Get-Content -Raw -LiteralPath $SafeSource | ConvertFrom-Json
    $ExpectedHash = Get-StringProperty -Object $Source -Name "sha256"
    if ($ExpectedHash -notmatch '^[0-9a-fA-F]{64}$') { throw "CODEX_LOGIN_SOURCE.json has no valid SHA-256." }
    $ObservedHash = (Get-FileHash -LiteralPath $SafeBinary -Algorithm SHA256).Hash
    if (-not $ObservedHash.Equals($ExpectedHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "The project-local Codex login helper does not match CODEX_LOGIN_SOURCE.json. Repair it before signing in."
    }
    return $SafeBinary
}

function Write-LocalCodexAccountConfig {
    param([Parameter(Mandatory = $true)][string]$AccountHome)
    $SafeAccountHome = Assert-PathInside -Path $AccountHome -BasePath $CodexAccountsRoot
    if (-not (Test-Path -LiteralPath $SafeAccountHome -PathType Container)) { New-Item -ItemType Directory -Path $SafeAccountHome -Force | Out-Null }
    $ConfigPath = Assert-PathInside -Path (Join-Path $SafeAccountHome "config.toml") -BasePath $SafeAccountHome
    $ConfigText = "cli_auth_credentials_store = `"file`"`r`nforced_login_method = `"chatgpt`"`r`n"
    [System.IO.File]::WriteAllText($ConfigPath, $ConfigText, (New-Object System.Text.UTF8Encoding($false)))
    return $SafeAccountHome
}

function Invoke-ProjectLocalCodexLogin {
    param([Parameter(Mandatory = $true)][string]$AccountHome)
    $SafeBinary = Assert-LocalCodexLoginRuntime
    $SafeAccountHome = Write-LocalCodexAccountConfig -AccountHome $AccountHome
    $AuthPath = Assert-PathInside -Path (Join-Path $SafeAccountHome "auth.json") -BasePath $SafeAccountHome
    $SavedCodexHome = [Environment]::GetEnvironmentVariable("CODEX_HOME", "Process")
    $SavedCodexSqliteHome = [Environment]::GetEnvironmentVariable("CODEX_SQLITE_HOME", "Process")
    try {
        $env:CODEX_HOME = $SafeAccountHome
        $env:CODEX_SQLITE_HOME = $SafeAccountHome
        Write-Host ""
        Write-Host "Opening the official OpenAI sign-in page for this project-local account..." -ForegroundColor Cyan
        Write-Host "Complete the password/2FA steps in your browser. The result stays inside this project." -ForegroundColor DarkGray
        & $SafeBinary login
        if ($LASTEXITCODE -ne 0) { throw "Project-local Codex login exited with code $LASTEXITCODE." }
    }
    finally {
        [Environment]::SetEnvironmentVariable("CODEX_HOME", $SavedCodexHome, "Process")
        [Environment]::SetEnvironmentVariable("CODEX_SQLITE_HOME", $SavedCodexSqliteHome, "Process")
    }
    if (-not (Test-Path -LiteralPath $AuthPath -PathType Leaf)) { throw "Sign-in finished without a project-local auth.json. Please retry." }
    return $AuthPath
}

function Resolve-CodexModelChoice {
    param(
        [Parameter(Mandatory = $true)][object[]]$Choices,
        [AllowEmptyString()][string]$Choice
    )
    $NormalizedChoices = @($Choices | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    $Value = ([string]$Choice).Trim()
    if (-not $Value) { return [string]$NormalizedChoices[0] }
    if ($Value -match '^\d+$') {
        $Index = [int]$Value
        if ($Index -ge 1 -and $Index -le $NormalizedChoices.Count) { return [string]$NormalizedChoices[$Index - 1] }
        return $null
    }
    foreach ($Model in $NormalizedChoices) {
        if ($Model.Equals($Value, [System.StringComparison]::OrdinalIgnoreCase)) { return [string]$Model }
    }
    return $null
}

function Select-CodexAccountModel {
    param([Parameter(Mandatory = $true)][object[]]$Models)
    $Choices = @($Models | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if ($Choices.Count -eq 0) { throw "CCR did not return any Codex model for this account." }
    Write-Host ""
    Write-Host "Models available for this imported account:" -ForegroundColor Cyan
    for ($Index = 0; $Index -lt $Choices.Count; $Index++) { Write-Host ("  [{0}] {1}" -f ($Index + 1), $Choices[$Index]) }
    if ($Choices.Count -eq 1) {
        Write-Host ("Automatically selected the only available model: {0}" -f $Choices[0]) -ForegroundColor Green
        return [string]$Choices[0]
    }
    while ($true) {
        $Choice = Read-Host "Choose a number or exact model ID [1]"
        $Selected = Resolve-CodexModelChoice -Choices $Choices -Choice $Choice
        if ($null -ne $Selected) { return [string]$Selected }
        Write-Host "That model is not available. Enter a listed number or the exact model ID." -ForegroundColor Yellow
    }
}

function Get-CodexAccountModelCandidates {
    param(
        [object[]]$ImportedModels = @(),
        [ValidateSet("codex_free", "codex_plus")][string]$ExpectedPlan = "codex_free"
    )
    $Unsupported = @{}
    foreach ($Model in $UnsupportedCodexChatGptModels) { $Unsupported[[string]$Model] = $true }
    if ($ExpectedPlan -eq "codex_free") { $Unsupported["gpt-5.6-sol"] = $true }
    $Seen = @{}
    $Candidates = @()
    foreach ($RawModel in @($CodexChatGptModelsByPlan[$ExpectedPlan]) + @($ImportedModels)) {
        $Model = ([string]$RawModel).Trim()
        if (-not $Model -or $Unsupported.ContainsKey($Model) -or $Seen.ContainsKey($Model)) { continue }
        $Seen[$Model] = $true
        $Candidates += $Model
    }
    return @($Candidates)
}

function Get-CodexAccountProviderPlugins {
    param(
        [object[]]$Plugins,
        [Parameter(Mandatory = $true)][string]$ProviderName,
        [Parameter(Mandatory = $true)][string]$ProviderId
    )
    $KeyPrefix = "ccr-local-agent-$(ConvertTo-ProviderSlug -Value $ProviderId)-"
    return @($Plugins | Where-Object {
        $Plugin = $_
        $PluginName = Get-StringProperty -Object $Plugin -Name "providerName"
        $PluginKey = Get-StringProperty -Object $Plugin -Name "key"
        $HasCodexOauth = $PluginKey.IndexOf("codex-oauth", [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        $HasCodexOauth -and (
            $PluginName.Equals($ProviderName, [System.StringComparison]::OrdinalIgnoreCase) -or
            $PluginName.StartsWith("${ProviderName}::", [System.StringComparison]::OrdinalIgnoreCase) -or
            $PluginKey.StartsWith($KeyPrefix, [System.StringComparison]::OrdinalIgnoreCase)
        )
    })
}

function Test-CodexAccountModels {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Provider,
        [Parameter(Mandatory = $true)][object[]]$ProviderPlugins,
        [Parameter(Mandatory = $true)][object[]]$Models
    )
    $Candidates = @($Models | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if ($Candidates.Count -eq 0) { throw "No current Codex ChatGPT model candidate is configured." }
    if ($ProviderPlugins.Count -eq 0) { throw "The imported Codex account has no matching OAuth provider plugin." }
    $BaseUrl = Get-StringProperty -Object $Provider -Name "api_base_url" -Default $CodexAccountBaseUrl
    $ApiKey = Get-StringProperty -Object $Provider -Name "api_key" -Default $LocalAgentProviderApiKey
    $Protocol = Get-StringProperty -Object $Provider -Name "type" -Default "openai_responses"
    $Request = [PSCustomObject]@{
        apiKey = $ApiKey
        candidates = @([PSCustomObject]@{ baseUrl = $BaseUrl; protocols = @($Protocol); source = "custom" })
        forceRefresh = $true
        models = $Candidates
        providerPlugins = @($ProviderPlugins)
        protocols = @($Protocol)
    }
    $RpcArguments = New-Object object[] 1
    $RpcArguments[0] = $Request
    Write-Host "Testing current Codex models for this ChatGPT account..." -ForegroundColor Cyan
    Write-Host "This sends one minimal connectivity request per candidate model." -ForegroundColor DarkGray
    $Report = Invoke-RouterRpc -State $State -Method "checkProviderConnectivity" -Arguments $RpcArguments
    $Supported = @($Report.passed | ForEach-Object { Get-StringProperty -Object $_ -Name "model" } | Where-Object { $_ } | Select-Object -Unique)
    foreach ($Model in $Candidates) {
        $Color = if ($Supported -contains $Model) { "Green" } else { "DarkGray" }
        $Status = if ($Supported -contains $Model) { "available" } else { "not available for this account" }
        Write-Host ("  - {0}: {1}" -f $Model, $Status) -ForegroundColor $Color
    }
    return @($Supported)
}

function Set-CodexAccountProfiles {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderName,
        [Parameter(Mandatory = $true)][string]$ProviderId,
        [Parameter(Mandatory = $true)][object[]]$Models,
        [string]$Path = $AccountProfilesPath
    )
    $Profiles = @(Read-AccountProfiles -Path $Path | Where-Object { $_.provider -ne $ProviderName })
    foreach ($RawModel in @($Models | Select-Object -Unique)) {
        $Model = ([string]$RawModel).Trim()
        if (-not $Model) { continue }
        $ModelSlug = ConvertTo-ProviderSlug -Value $Model
        $ProfileId = "account-$ProviderId-$ModelSlug"
        if ($ProfileId.Length -gt 63) { $ProfileId = $ProfileId.Substring(0, 63).TrimEnd('-') }
        $Profiles += [PSCustomObject][ordered]@{
            id = $ProfileId
            name = "Codex: $ProviderName [$Model]"
            enabled = $true
            provider = $ProviderName
            model = $Model
            background_model = $Model
            think_model = $Model
            long_context_model = $Model
        }
    }
    if (@($Profiles | Where-Object { $_.provider -eq $ProviderName }).Count -eq 0) { throw "No Codex account profile was generated." }
    Write-AccountProfiles -Profiles $Profiles -Path $Path
}

function Add-CodexAccountProfile {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderName,
        [Parameter(Mandatory = $true)][string]$ProviderId,
        [Parameter(Mandatory = $true)][string]$Model,
        [string]$Path = $AccountProfilesPath
    )
    Set-CodexAccountProfiles -ProviderName $ProviderName -ProviderId $ProviderId -Models @($Model) -Path $Path
}

function SignInAndImportCodexAccount {
    param(
        [ValidateSet("codex_free", "codex_plus")][string]$ExpectedPlan = "codex_free",
        [string]$RequestedName
    )
    $RouterWasRunning = $false
    try { [void](Assert-VerifiedRouterService); $RouterWasRunning = $true } catch { }

    $LocalCodexDir = Assert-PathInside -Path (Join-Path $CcrHomePath ".codex") -BasePath $RouterStateRoot
    $LocalAuthPath = Assert-PathInside -Path (Join-Path $LocalCodexDir "auth.json") -BasePath $RouterStateRoot
    $BackupAuthPath = Assert-PathInside -Path (Join-Path $LocalCodexDir "auth.json.before-account-import") -BasePath $RouterStateRoot
    if (-not (Test-Path -LiteralPath $LocalCodexDir -PathType Container)) { New-Item -ItemType Directory -Path $LocalCodexDir -Force | Out-Null }
    if (Test-Path -LiteralPath $BackupAuthPath) { throw "A previous account-import backup still exists; no credential file was changed." }

    $HadLocalAuth = $false
    $StagedLocalAuth = $false
    try {
        $State = Ensure-ManagementService
        $CurrentConfig = Invoke-RouterRpc -State $State -Method "getConfig"
        $DefaultName = Get-UniqueCodexAccountName -Providers @($CurrentConfig.Providers) -ExpectedPlan $ExpectedPlan
        $ProviderName = if ($RequestedName) { $RequestedName.Trim() } else { (Read-Host "Account name [$DefaultName]").Trim() }
        if (-not $ProviderName) { $ProviderName = $DefaultName }
        if ($ProviderName.Length -gt 100 -or $ProviderName -match '[\r\n/,]') { throw "The account name is invalid." }
        $ExistingProvider = @($CurrentConfig.Providers | Where-Object { ([string]$_.name).Equals($ProviderName, [System.StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
        if ($null -ne $ExistingProvider -and $RequestedName) {
            $ExistingProviderId = Get-StringProperty -Object $ExistingProvider -Name "id"
            $ExistingPlan = Get-StringProperty -Object $ExistingProvider -Name "local_expected_plan"
            $ExistingModels = @($ExistingProvider.models | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
            $AllowedRecoveryModels = @($CodexChatGptModelsByPlan[$ExpectedPlan])
            $UnexpectedRecoveryModels = @($ExistingModels | Where-Object { $AllowedRecoveryModels -notcontains $_ })
            $RecoveryModelsMatch = $ExistingModels.Count -gt 0 -and $UnexpectedRecoveryModels.Count -eq 0
            $ExistingPlugins = @(Get-CodexAccountProviderPlugins -Plugins @($CurrentConfig.providerPlugins) -ProviderName $ProviderName -ProviderId $ExistingProviderId)
            $ExistingHome = if ($ExistingProviderId -match '^[a-z0-9][a-z0-9_.-]{0,62}$') { Assert-PathInside -Path (Join-Path $CodexAccountsRoot $ExistingProviderId) -BasePath $CodexAccountsRoot } else { "" }
            $ExistingMarker = if ($ExistingHome) { Join-Path $ExistingHome "account-label.sha256" } else { "" }
            $ExistingAuth = if ($ExistingHome) { Join-Path $ExistingHome "auth.json" } else { "" }
            $ExistingPending = if ($ExistingHome) { Join-Path $ExistingHome "pending-account.json" } else { "" }
            $ExistingPendingPlan = ""
            if ($ExistingPending -and (Test-Path -LiteralPath $ExistingPending -PathType Leaf)) {
                try {
                    $PendingRecord = Get-Content -Raw -LiteralPath $ExistingPending | ConvertFrom-Json
                    $ExistingPendingPlan = Get-StringProperty -Object $PendingRecord -Name "expectedPlan"
                }
                catch { $ExistingPendingPlan = "" }
            }
            $RecoveryPlanMatches = $ExistingPlan -eq $ExpectedPlan -or $ExistingPendingPlan -eq $ExpectedPlan
            $MarkerMatches = $false
            if ($ExistingMarker -and (Test-Path -LiteralPath $ExistingMarker -PathType Leaf)) {
                $MarkerMatches = (Get-Content -Raw -LiteralPath $ExistingMarker).Trim().Equals((Get-TextSha256 -Text $ProviderName), [System.StringComparison]::OrdinalIgnoreCase)
            }
            if ($RecoveryPlanMatches -and $RecoveryModelsMatch -and $ExistingPlugins.Count -gt 0 -and $MarkerMatches -and (Test-Path -LiteralPath $ExistingAuth -PathType Leaf)) {
                Set-CodexAccountProfiles -ProviderName $ProviderName -ProviderId $ExistingProviderId -Models $ExistingModels
                $PendingMetadataPath = Join-Path $ExistingHome "pending-account.json"
                if (Test-Path -LiteralPath $PendingMetadataPath -PathType Leaf) { Remove-Item -LiteralPath $PendingMetadataPath -Force }
                Write-Host ("Recovered the already-persisted account '{0}' and created its dashboard routes." -f $ProviderName) -ForegroundColor Green
                return
            }
        }
        if ($null -ne $ExistingProvider) {
            $RecoveryProblems = New-Object System.Collections.Generic.List[string]
            if (-not $RecoveryPlanMatches) { $RecoveryProblems.Add("plan marker") }
            if (-not $RecoveryModelsMatch) { $RecoveryProblems.Add("models") }
            if ($ExistingPlugins.Count -eq 0) { $RecoveryProblems.Add("OAuth plugin") }
            if (-not $MarkerMatches) { $RecoveryProblems.Add("account label marker") }
            if (-not (Test-Path -LiteralPath $ExistingAuth -PathType Leaf)) { $RecoveryProblems.Add("project-local login") }
            if ($RequestedName -and $RecoveryProblems.Count -gt 0) {
                throw ("The account provider exists but recovery could not verify: " + ($RecoveryProblems -join ", ") + ".")
            }
            throw "A provider/account with that name already exists."
        }
        $AccountSlot = Resolve-CodexAccountSlot -Name $ProviderName -Providers @($CurrentConfig.Providers)
        $ProviderId = [string]$AccountSlot.providerId
        $AccountHome = [string]$AccountSlot.accountHome
        Write-CodexAccountLabelMarker -Slot $AccountSlot
        $PendingMetadataPath = Assert-PathInside -Path (Join-Path $AccountHome "pending-account.json") -BasePath $CodexAccountsRoot
        $PendingMetadata = [ordered]@{ schema_version = 1; label = $ProviderName; expectedPlan = $ExpectedPlan; status = "pending" }
        [System.IO.File]::WriteAllText($PendingMetadataPath, ($PendingMetadata | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
        if ([bool]$AccountSlot.resume) {
            Write-Host ""
            Write-Host "Resuming the unfinished project-local sign-in for this account label." -ForegroundColor Cyan
            Write-Host "No browser login or 2FA is needed again unless CCR reports that the local session expired." -ForegroundColor DarkGray
            $SourceAuthPath = [string]$AccountSlot.authPath
        }
        else {
            $SourceAuthPath = Invoke-ProjectLocalCodexLogin -AccountHome $AccountHome
        }

        if ($RouterWasRunning) {
            Write-Host ""
            Write-Host ("Saved the browser login for '{0}' inside this project." -f $ProviderName) -ForegroundColor Green
            Write-Host "A Claude/router session is currently running, so CCR was not changed." -ForegroundColor Yellow
            Write-Host "Close the active Claude terminals, then use 'Hoan tat nhap tai khoan' in DASHBOARD.bat. No new browser login is required while this session remains valid." -ForegroundColor Cyan
            return
        }

        $HadLocalAuth = Test-Path -LiteralPath $LocalAuthPath -PathType Leaf
        if ($HadLocalAuth) { Move-Item -LiteralPath $LocalAuthPath -Destination $BackupAuthPath }
        Copy-Item -LiteralPath $SourceAuthPath -Destination $LocalAuthPath
        $StagedLocalAuth = $true
        $Candidates = @(Invoke-RouterRpc -State $State -Method "getLocalAgentProviderCandidates")
        $Candidate = @($Candidates | Where-Object { $_.id -eq "codex-api" -and $_.importable -eq $true }) | Select-Object -First 1
        if ($null -eq $Candidate) { throw "CCR could not use this project-local Codex login. Sign in again and retry." }

        $ImportRequest = [PSCustomObject]@{ id = "codex-api"; providerNames = @($CurrentConfig.Providers | ForEach-Object { [string]$_.name }) }
        $RpcArguments = New-Object object[] 1
        $RpcArguments[0] = $ImportRequest
        $Imported = Invoke-RouterRpc -State $State -Method "importLocalAgentProvider" -Arguments $RpcArguments
        $ImportedPlugins = @($Imported.providerPlugins)
        $ImportedAccountId = ""
        foreach ($Plugin in $ImportedPlugins) {
            $CodexOauth = Get-ObjectPropertyValue -Object $Plugin -Name "codexOauth"
            if ($null -ne $CodexOauth) { $ImportedAccountId = Get-StringProperty -Object $CodexOauth -Name "accountId"; if ($ImportedAccountId) { break } }
        }
        $CurrentProviderPlugins = if ($null -ne $CurrentConfig.PSObject.Properties["providerPlugins"] -and $null -ne $CurrentConfig.providerPlugins) { @($CurrentConfig.providerPlugins) } else { @() }
        if ($ImportedAccountId) {
            foreach ($Plugin in $CurrentProviderPlugins) {
                $CodexOauth = Get-ObjectPropertyValue -Object $Plugin -Name "codexOauth"
                if ($null -ne $CodexOauth -and (Get-StringProperty -Object $CodexOauth -Name "accountId") -eq $ImportedAccountId) {
                    throw "This Codex account is already imported into the project."
                }
            }
        }

        $Protocol = Get-StringProperty -Object $Imported.provider -Name "protocol" -Default "openai_responses"
        $Models = @(Get-CodexAccountModelCandidates -ImportedModels @($Imported.provider.models) -ExpectedPlan $ExpectedPlan)
        $Provider = [PSCustomObject][ordered]@{
            id = $ProviderId
            name = $ProviderName
            api_base_url = Get-StringProperty -Object $Imported.provider -Name "baseUrl" -Default $CodexAccountBaseUrl
            api_key = Get-StringProperty -Object $Imported.provider -Name "apiKey" -Default $LocalAgentProviderApiKey
            models = $Models
            type = $Protocol
            protocolDetectionMode = "manual"
            local_expected_plan = $ExpectedPlan
        }
        foreach ($OptionalName in @("account", "capabilities", "icon", "modelDescriptions", "modelDisplayNames", "modelMetadata")) {
            if ($null -ne $Imported.provider.PSObject.Properties[$OptionalName] -and $null -ne $Imported.provider.$OptionalName) {
                Set-JsonProperty -Object $Provider -Name $OptionalName -Value $Imported.provider.$OptionalName
            }
        }
        $MaterializedPlugins = Materialize-ProviderPlugins -Templates $ImportedPlugins -ProviderName $ProviderName -Protocol $Protocol -ProviderId $ProviderId
        $SupportedModels = @(Test-CodexAccountModels -State $State -Provider $Provider -ProviderPlugins $MaterializedPlugins -Models $Models)
        if ($SupportedModels.Count -eq 0) { throw "No current Codex model is available for this ChatGPT account. The imported CCR fallback model was not saved." }
        Set-JsonProperty -Object $Provider -Name "models" -Value $SupportedModels
        Set-JsonProperty -Object $CurrentConfig -Name "Providers" -Value @(@($CurrentConfig.Providers) + $Provider)
        Set-JsonProperty -Object $CurrentConfig -Name "providerPlugins" -Value (Merge-ProviderPlugins -Current $CurrentProviderPlugins -Additions $MaterializedPlugins)
        if (-not (Get-StringProperty -Object $CurrentConfig -Name "preferredProvider")) { Set-JsonProperty -Object $CurrentConfig -Name "preferredProvider" -Value $ProviderName }
        $CurrentConfig = Enforce-SafeCcrConfig -Config $CurrentConfig
        $Options = [PSCustomObject]@{ applyProfile = $true }
        try { [void](Invoke-RouterRpc -State $State -Method "saveConfig" -Arguments @($CurrentConfig, $Options)) }
        catch {
            # saveConfig persists before it starts/updates the gateway. A slow
            # Windows cold start can therefore fail the RPC after the exact
            # provider and OAuth plugins are already durable. Accept only that
            # independently re-read, exact postcondition; every other failure
            # remains fail-closed and is retried from the dashboard.
            $PersistedConfig = Invoke-RouterRpc -State $State -Method "getConfig"
            $PersistedProvider = @($PersistedConfig.Providers | Where-Object { ([string]$_.name).Equals($ProviderName, [System.StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
            $PersistedModels = if ($null -ne $PersistedProvider) { @($PersistedProvider.models | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique) } else { @() }
            $PersistedPlugins = if ($null -ne $PersistedProvider) { @(Get-CodexAccountProviderPlugins -Plugins @($PersistedConfig.providerPlugins) -ProviderName $ProviderName -ProviderId $ProviderId) } else { @() }
            $MissingModel = @($SupportedModels | Where-Object { $PersistedModels -notcontains $_ })
            $UnexpectedModel = @($PersistedModels | Where-Object { $SupportedModels -notcontains $_ })
            if ($null -eq $PersistedProvider -or (Get-StringProperty -Object $PersistedProvider -Name "id") -ne $ProviderId -or $MissingModel.Count -gt 0 -or $UnexpectedModel.Count -gt 0 -or $PersistedPlugins.Count -eq 0 -or @($PersistedConfig.profile.profiles).Count -ne 0) { throw }
            Write-Host "CCR persisted the exact account config before its gateway update reported an error; continuing from the verified stored postcondition." -ForegroundColor Yellow
        }
        Set-CodexAccountProfiles -ProviderName $ProviderName -ProviderId $ProviderId -Models $SupportedModels
        if (Test-Path -LiteralPath $PendingMetadataPath -PathType Leaf) { Remove-Item -LiteralPath $PendingMetadataPath -Force }
        Write-Host ""
        Write-Host ("Imported '{0}' into this project. Its login and route are project-local." -f $ProviderName) -ForegroundColor Green
        Write-Host "Each verified model will appear as a separate choice in DASHBOARD.bat." -ForegroundColor Green
    }
    finally {
        if ($StagedLocalAuth -and (Test-Path -LiteralPath $LocalAuthPath -PathType Leaf)) { Remove-Item -LiteralPath $LocalAuthPath -Force }
        if ($HadLocalAuth -and (Test-Path -LiteralPath $BackupAuthPath -PathType Leaf)) { Move-Item -LiteralPath $BackupAuthPath -Destination $LocalAuthPath }
        if (-not $RouterWasRunning) { try { [void](Invoke-Ccr -Arguments @("stop")) } catch { } }
    }
}

function Select-ImportedCodexAccount {
    param([Parameter(Mandatory = $true)][object[]]$Accounts)
    if ($Accounts.Count -eq 0) { throw "No Codex account has been imported into this project." }
    if ($Accounts.Count -eq 1) { return $Accounts[0] }
    Write-Host ""
    Write-Host "Choose an imported Codex account:" -ForegroundColor Cyan
    for ($Index = 0; $Index -lt $Accounts.Count; $Index++) { Write-Host ("  [{0}] {1}" -f ($Index + 1), $Accounts[$Index].name) }
    while ($true) {
        $Choice = (Read-Host "Account number").Trim()
        if ($Choice -match '^\d+$') {
            $Number = [int]$Choice
            if ($Number -ge 1 -and $Number -le $Accounts.Count) { return $Accounts[$Number - 1] }
        }
        Write-Host "Invalid account number." -ForegroundColor Yellow
    }
}

function Refresh-CodexAccountModels {
    try {
        [void](Assert-VerifiedRouterService)
        throw "A Claude/router session is running. Close it or stop the router before refreshing account models."
    }
    catch {
        if ($_.Exception.Message -like "A Claude/router session is running.*") { throw }
    }
    try {
        $State = Ensure-ManagementService
        $Config = Invoke-RouterRpc -State $State -Method "getConfig"
        $Accounts = @($Config.Providers | Where-Object {
            (Get-StringProperty -Object $_ -Name "api_key") -eq $LocalAgentProviderApiKey -and
            (Get-StringProperty -Object $_ -Name "api_base_url") -eq $CodexAccountBaseUrl
        })
        $Provider = Select-ImportedCodexAccount -Accounts $Accounts
        $ProviderName = Get-StringProperty -Object $Provider -Name "name"
        $ProviderId = Get-StringProperty -Object $Provider -Name "id"
        if (-not $ProviderName -or -not $ProviderId) { throw "The imported Codex provider has no stable name or ID." }
        $Plugins = @(Get-CodexAccountProviderPlugins -Plugins @($Config.providerPlugins) -ProviderName $ProviderName -ProviderId $ProviderId)
        $ExpectedPlan = Get-StringProperty -Object $Provider -Name "local_expected_plan" -Default "codex_free"
        if ($ExpectedPlan -notin @("codex_free", "codex_plus")) { $ExpectedPlan = "codex_free" }
        $Candidates = @(Get-CodexAccountModelCandidates -ImportedModels @($Provider.models) -ExpectedPlan $ExpectedPlan)
        $SupportedModels = @(Test-CodexAccountModels -State $State -Provider $Provider -ProviderPlugins $Plugins -Models $Candidates)
        if ($SupportedModels.Count -eq 0) { throw "No current Codex model is available for this ChatGPT account; the saved routes were left unchanged." }
        Set-JsonProperty -Object $Provider -Name "models" -Value $SupportedModels
        $Config = Enforce-SafeCcrConfig -Config $Config
        $Options = [PSCustomObject]@{ applyProfile = $true }
        [void](Invoke-RouterRpc -State $State -Method "saveConfig" -Arguments @($Config, $Options))
        Set-CodexAccountProfiles -ProviderName $ProviderName -ProviderId $ProviderId -Models $SupportedModels
        Write-Host ""
        Write-Host "Codex model routes were refreshed for this account." -ForegroundColor Green
    }
    finally {
        try { [void](Invoke-Ccr -Arguments @("stop")) } catch { }
    }
}

function Show-ImportedCodexAccounts {
    $State = Ensure-ManagementService
    $Config = Invoke-RouterRpc -State $State -Method "getConfig"
    $Accounts = @($Config.Providers | Where-Object {
        (Get-StringProperty -Object $_ -Name "api_key") -eq $LocalAgentProviderApiKey -and
        (Get-StringProperty -Object $_ -Name "api_base_url") -eq $CodexAccountBaseUrl
    })
    Write-Host ""
    if ($Accounts.Count -eq 0) { Write-Host "No Codex account has been imported into this project." -ForegroundColor Yellow; return }
    Write-Host "Imported Codex accounts:" -ForegroundColor Cyan
    foreach ($Account in $Accounts) {
        $Plan = Get-StringProperty -Object $Account -Name "local_expected_plan" -Default "codex_free"
        Write-Host ("  - {0} [{1}]" -f $Account.name, $Plan)
    }
}

function Invoke-GoogleAccountMenu {
    $GoogleMenu = Join-Path $RootPath "tools\challenger_account_menu.ps1"
    if (-not (Test-Path -LiteralPath $GoogleMenu -PathType Leaf)) { throw "Google Pro project-local account menu is missing." }
    & $GoogleMenu -Root $RootPath
    if (-not $?) { throw "Google Pro account menu did not finish successfully." }
}

function Invoke-AccountMenu {
    while ($true) {
        try { Clear-Host } catch { }
        Write-Host "==============================================================" -ForegroundColor Cyan
        Write-Host "  CLAUDE CLI - PROJECT-LOCAL ACCOUNT SETUP" -ForegroundColor Cyan
        Write-Host "==============================================================" -ForegroundColor Cyan
        Write-Host "  [1] Sign in + add a Codex Free account (Terra/Luna)"
        Write-Host "  [2] Sign in + add a Codex Plus account (Sol/Terra/Luna)"
        Write-Host "  [G] Google AI Pro accounts (Antigravity OAuth, project-local)"
        Write-Host "  [R] Refresh/test model routes for an imported Codex account"
        Write-Host "  [L] List imported Codex accounts"
        Write-Host "  [Q] Quit"
        Write-Host ""
        Write-Host "  Run [1]/[2] once per Codex account. Every login gets its own" -ForegroundColor DarkGray
        Write-Host "  private folder under provider_router\.ccr-local\codex-accounts." -ForegroundColor DarkGray
        $Choice = (Read-Host "Select an action").Trim().ToLowerInvariant()
        switch ($Choice) {
            "1" { SignInAndImportCodexAccount -ExpectedPlan "codex_free" }
            "2" { SignInAndImportCodexAccount -ExpectedPlan "codex_plus" }
            "g" { Invoke-GoogleAccountMenu }
            "r" { Refresh-CodexAccountModels }
            "l" { Show-ImportedCodexAccounts }
            "q" { return }
            default { Write-Host "Invalid selection." -ForegroundColor Yellow }
        }
        Read-Host "Press Enter to continue" | Out-Null
    }
}

function Stop-RouterService {
    if (-not (Test-Path -LiteralPath $NodePath -PathType Leaf) -or -not (Test-Path -LiteralPath $RouterCliPath -PathType Leaf)) { Write-Host "CCR runtime is not installed." -ForegroundColor Yellow; return }
    [void](Invoke-Ccr -Arguments @("stop"))
    Write-Host "Requested stop for the project-local CCR service." -ForegroundColor Green
}

function Show-UpdateCheck {
    $Checker = Join-Path $RootPath "tools\check_updates.ps1"
    if (-not (Test-Path -LiteralPath $Checker -PathType Leaf)) { throw "Project update checker is missing." }
    & $Checker -Root $RootPath
    if (-not $?) { throw "Update checker failed." }
}

function Invoke-Menu {
    $Setting = Ensure-SettingApplied
    while ($true) {
        try { Clear-Host } catch { }
        Write-Host "==============================================================" -ForegroundColor Cyan
        Write-Host "  CLAUDE CLI - ROUTES FROM setting.json" -ForegroundColor Cyan
        Write-Host "  Project-local accounts and quota: DASHBOARD.bat" -ForegroundColor DarkGray
        Write-Host "==============================================================" -ForegroundColor Cyan
        $Profiles = @($Setting.profiles | Where-Object { $_.enabled }) + @(Read-AccountProfiles | Where-Object { $_.enabled })
        if ($Profiles.Count -eq 0) { Write-Host "  No enabled profile. Edit setting.json, then choose [S]." -ForegroundColor Yellow }
        for ($Index = 0; $Index -lt $Profiles.Count; $Index++) {
            Write-Host ("  [{0}] {1}" -f ($Index + 1), $Profiles[$Index].name)
            Write-Host ("      {0}" -f (Get-ModelRoute -Profile $Profiles[$Index] -Tier "default")) -ForegroundColor DarkGray
        }
        if ($Profiles.Count -gt 0) { Start-RouterWarmup }
        Write-Host ""
        Write-Host "  [S] Reload setting.json   [R] Router status"
        Write-Host "  [X] Stop router           [U] Check updates   [Q] Quit"
        $Choice = (Read-Host "Select a profile or action").Trim()
        if ($Choice -match '^\d+$') {
            $Number = [int]$Choice
            if ($Number -ge 1 -and $Number -le $Profiles.Count) { Start-Profile -Profile $Profiles[$Number - 1] -Defaults $Setting.defaults; return }
            Write-Host "Invalid selection." -ForegroundColor Yellow; Start-Sleep -Seconds 1; continue
        }
        switch ($Choice.ToLowerInvariant()) {
            "s" { $Setting = Ensure-SettingApplied -Force }
            "r" { Show-RouterStatus }
            "x" { Stop-RouterService }
            "u" { Show-UpdateCheck }
            "q" { return }
            default { Write-Host "Invalid selection." -ForegroundColor Yellow }
        }
        Read-Host "Press Enter to continue" | Out-Null
    }
}

function Invoke-SelfTest {
    $TestRoot = Assert-PathInside -Path (Join-Path $RouterStateRoot "__setting-flow-selftest__") -BasePath $RouterStateRoot
    $TestCodexHome = Assert-PathInside -Path (Join-Path $CodexAccountsRoot "__login-config-selftest__") -BasePath $CodexAccountsRoot
    if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
    if (Test-Path -LiteralPath $TestCodexHome) { Remove-Item -LiteralPath $TestCodexHome -Recurse -Force }
    try {
        New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
        $SamplePath = Join-Path $TestRoot "setting.json"
        $Sample = [ordered]@{
            schema_version = 1
            providers = @([ordered]@{ id = "sample"; name = "Sample API"; enabled = $true; base_url = "https://api.example.invalid/v1"; protocol = "openai_chat_completions"; api_key = "offline-unit-test-key"; credentials = @(); models = @("sample-model") })
            profiles = @([ordered]@{ id = "sample"; name = "Sample"; enabled = $true; provider = "Sample API"; model = "sample-model"; background_model = "sample-small"; think_model = "sample-think"; long_context_model = "sample-long" })
            claude_defaults = [ordered]@{ effort_level = "xhigh"; theme = "dark"; permission_mode = "acceptEdits"; allow = @("Bash(*)"); telemetry = "0" }
        }
        [System.IO.File]::WriteAllText($SamplePath, ($Sample | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
        $Parsed = Read-LocalSetting -Path $SamplePath
        if ($Parsed.providers.Count -ne 1 -or $Parsed.profiles.Count -ne 1 -or (Get-ModelRoute -Profile $Parsed.profiles[0] -Tier "think") -ne "Sample API/sample-think") { throw "setting.json parser did not preserve provider/profile routes." }
        $FakeConfig = [PSCustomObject]@{
            Providers = @([PSCustomObject]@{ id = "account-provider"; name = "Imported Account"; models = @("account-model") })
            HOST = "external"; PORT = 9999; routerEndpoint = "http://external"
            gateway = [PSCustomObject]@{ enabled = $false; host = "external"; port = 9999 }
            proxy = [PSCustomObject]@{ enabled = $true; systemProxy = $true; captureNetwork = $true }
            observability = [PSCustomObject]@{ requestLogs = $true }
            Router = [PSCustomObject]@{ builtInRules = [PSCustomObject]@{ "claude-code" = [PSCustomObject]@{ enabled = $false }; codex = [PSCustomObject]@{ enabled = $true } } }
            profile = [PSCustomObject]@{ profiles = @([PSCustomObject]@{ agent = "codex"; enabled = $true; scope = "global"; surface = "auto"; providerName = "Claude Code Router" }) }
        }
        $Merged = Merge-SettingIntoCcrConfig -CurrentConfig $FakeConfig -Setting $Parsed
        if ($Merged.Providers.Count -ne 2 -or $Merged.Providers[0].name -ne "Imported Account" -or $Merged.Providers[1].id -ne ($ManagedProviderPrefix + "sample")) { throw "Managed-provider merge did not preserve UI/account providers." }
        if ($Merged.gateway.host -ne "127.0.0.1" -or $Merged.proxy.enabled -or $Merged.proxy.systemProxy -or $Merged.observability.requestLogs -or $Merged.Router.builtInRules.codex.enabled) { throw "Safe loopback/proxy/log defaults were not enforced." }
        if (@($Merged.profile.profiles).Count -ne 0) { throw "A CCR agent profile capable of modifying external app configuration survived isolation enforcement." }
        $FakePlugins = @([PSCustomObject]@{
            key = "ccr-local-agent-${ProviderNameSlugPlaceholder}-codex-oauth"
            providerName = $ProviderNamePlaceholder
            codexOauth = [PSCustomObject]@{ accessToken = "offline-fake-access"; refreshToken = "offline-fake-refresh"; required = $true }
        })
        $Materialized = @(Materialize-ProviderPlugins -Templates $FakePlugins -ProviderName "Codex Account 1" -Protocol "openai_responses" -ProviderId "codex-account-1")
        if ($Materialized.Count -ne 1 -or $Materialized[0].key -ne "ccr-local-agent-codex-account-1-codex-oauth" -or $Materialized[0].providerName -ne "Codex Account 1") { throw "Codex account plugin placeholders were not isolated by account name." }
        $FakeAccountProfilesPath = Join-Path $TestRoot "account-profiles.json"
        Add-CodexAccountProfile -ProviderName "Codex Account 1" -ProviderId "codex-account-1" -Model "gpt-offline-test" -Path $FakeAccountProfilesPath
        $FakeAccountProfiles = @(Read-AccountProfiles -Path $FakeAccountProfilesPath)
        if ($FakeAccountProfiles.Count -ne 1 -or (Get-ModelRoute -Profile $FakeAccountProfiles[0] -Tier "default") -ne "Codex Account 1/gpt-offline-test") { throw "Imported account route index did not round-trip." }
        $SpecialAccountProfilesPath = Join-Path $TestRoot "account-profiles-special-label.json"
        $SpecialProviderName = "account_name+tag@example.test"
        $SpecialProviderId = ConvertTo-ProviderSlug -Value $SpecialProviderName
        Add-CodexAccountProfile -ProviderName $SpecialProviderName -ProviderId $SpecialProviderId -Model "gpt-offline-test" -Path $SpecialAccountProfilesPath
        $SpecialAccountProfiles = @(Read-AccountProfiles -Path $SpecialAccountProfilesPath)
        if ($SpecialAccountProfiles.Count -ne 1 -or (Get-ModelRoute -Profile $SpecialAccountProfiles[0] -Tier "default") -ne "$SpecialProviderName/gpt-offline-test") { throw "A sanitized account label with slug-safe punctuation did not round-trip." }
        $SpecialModePath = Get-ModePath -Id ([string]$SpecialAccountProfiles[0].id)
        if ([System.IO.Path]::GetFileName($SpecialModePath) -ne [string]$SpecialAccountProfiles[0].id) { throw "A generated account route ID did not resolve to its isolated Claude mode path." }
        $FakeStartState = [PSCustomObject]@{ checks = 0 }
        $VerifiedAfterStartExit = Invoke-CcrStartAndVerify `
            -Arguments @("start", "--gateway") `
            -Starter { param([string[]]$IgnoredArguments) throw "simulated CCR start exit after service activation" } `
            -Verifier {
                $FakeStartState.checks++
                if ($FakeStartState.checks -lt 2) { throw "simulated service readiness delay" }
                return "verified-service"
            } `
            -FailureMessage "simulated verified-start failure:" `
            -Attempts 2 `
            -DelayMilliseconds 0
        if ($VerifiedAfterStartExit -ne "verified-service") { throw "A verified CCR service was rejected only because its start command reported failure." }
        $RejectedUnverifiedStart = $false
        try {
            [void](Invoke-CcrStartAndVerify `
                -Arguments @("start", "--gateway") `
                -Starter { param([string[]]$IgnoredArguments) throw "simulated start failure" } `
                -Verifier { throw "simulated verification failure" } `
                -FailureMessage "simulated fail-closed:" `
                -Attempts 1 `
                -DelayMilliseconds 0)
        }
        catch {
            $RejectedUnverifiedStart = $_.Exception.Message -match 'simulated verification failure' -and $_.Exception.Message -match 'simulated start failure'
        }
        if (-not $RejectedUnverifiedStart) { throw "An unverified CCR start did not fail closed with both diagnostic contexts." }
        if (-not (Test-GatewayConfigAcceptanceTimeout -Status ([PSCustomObject]@{ state = "error"; lastError = "Core gateway did not accept runtime config within 5000ms." }))) { throw "The bounded Windows cold-start recovery trigger was not recognized." }
        if (Test-GatewayConfigAcceptanceTimeout -Status ([PSCustomObject]@{ state = "error"; lastError = "Unrelated gateway failure." })) { throw "An unrelated gateway failure was accepted by the cold-start recovery trigger." }
        if (Test-GatewayConfigAcceptanceTimeout -Status ([PSCustomObject]@{ state = "stopped" })) { throw "A gateway status without a last error was accepted by the cold-start recovery trigger." }
        if ((Resolve-CodexModelChoice -Choices @("model-a", "model-b") -Choice "2") -ne "model-b") { throw "Numeric Codex model selection did not resolve." }
        if ((Resolve-CodexModelChoice -Choices @("model-a", "model-b") -Choice "MODEL-A") -ne "model-a") { throw "Exact Codex model ID selection was not case-insensitive." }
        if ($null -ne (Resolve-CodexModelChoice -Choices @("model-a", "model-b") -Choice "terra")) { throw "An unavailable Codex model alias was accepted." }
        $CurrentCodexCandidates = @(Get-CodexAccountModelCandidates -ImportedModels @("gpt-5-codex", "gpt-custom-current") -ExpectedPlan "codex_free")
        if ($CurrentCodexCandidates.Count -ne 3 -or $CurrentCodexCandidates -contains "gpt-5-codex" -or $CurrentCodexCandidates -contains "gpt-5.6-sol" -or $CurrentCodexCandidates -notcontains "gpt-5.6-terra" -or $CurrentCodexCandidates -notcontains "gpt-5.6-luna" -or $CurrentCodexCandidates -notcontains "gpt-custom-current") { throw "Current Codex candidates did not replace rejected Free-account models safely." }
        $PlusCodexCandidates = @(Get-CodexAccountModelCandidates -ImportedModels @("gpt-5-codex") -ExpectedPlan "codex_plus")
        if ($PlusCodexCandidates.Count -ne 3 -or $PlusCodexCandidates -notcontains "gpt-5.6-sol" -or $PlusCodexCandidates -notcontains "gpt-5.6-terra" -or $PlusCodexCandidates -notcontains "gpt-5.6-luna") { throw "Codex Plus candidates did not expose the declared Sol/Terra/Luna entitlement set." }
        $MultiAccountProfilesPath = Join-Path $TestRoot "account-profiles-multi-model.json"
        Set-CodexAccountProfiles -ProviderName "Codex Multi" -ProviderId "codex-multi" -Models @("gpt-5.6-terra", "gpt-5.6-luna") -Path $MultiAccountProfilesPath
        $MultiAccountProfiles = @(Read-AccountProfiles -Path $MultiAccountProfilesPath)
        if ($MultiAccountProfiles.Count -ne 2 -or (Get-ModelRoute -Profile $MultiAccountProfiles[0] -Tier "default") -eq (Get-ModelRoute -Profile $MultiAccountProfiles[1] -Tier "default")) { throw "Verified Codex models did not become separate RUN routes." }
        if ((Select-CodexAccountModel -Models @("only-model")) -ne "only-model") { throw "A sole Codex model was not selected automatically." }
        [void](Write-LocalCodexAccountConfig -AccountHome $TestCodexHome)
        $TestCodexConfig = Get-Content -Raw -LiteralPath (Join-Path $TestCodexHome "config.toml")
        if ($TestCodexConfig -notmatch 'cli_auth_credentials_store\s*=\s*"file"' -or $TestCodexConfig -notmatch 'forced_login_method\s*=\s*"chatgpt"') { throw "Project-local Codex account config does not force file-backed ChatGPT login." }
        $FakePendingSlot = Resolve-CodexAccountSlot -Name "__login-config-selftest__" -Providers @()
        Write-CodexAccountLabelMarker -Slot $FakePendingSlot
        [System.IO.File]::WriteAllText(([string]$FakePendingSlot.authPath), "{}", (New-Object System.Text.UTF8Encoding($false)))
        $ResolvedPendingSlot = Resolve-CodexAccountSlot -Name "__login-config-selftest__" -Providers @()
        if (-not [bool]$ResolvedPendingSlot.resume -or [string]$ResolvedPendingSlot.providerId -ne "__login-config-selftest__") { throw "An unfinished project-local Codex login was not resumed by exact label." }
        $PlainText = "setting-flow-dpapi-selftest"
        $CipherText = Protect-SecureValue -Value (ConvertTo-SecureString -String $PlainText -AsPlainText -Force)
        if ((Reveal-ProtectedValue -CipherText $CipherText) -ne $PlainText) { throw "DPAPI round-trip failed." }
        $Text = Get-Content -Raw -LiteralPath $PSCommandPath
        foreach ($Forbidden in @(
            ("function Add" + "-Profile"),
            ("function Edit" + "-ProfileSettings"),
            ("function Remove" + "-Profile"),
            ("CCR client key " + "(hidden")
        )) {
            if ($Text.IndexOf($Forbidden, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { throw "Interactive API/profile input remains in RUN menu: $Forbidden" }
        }
        foreach ($Required in @("setting.json", "saveConfig", "getServiceIdentity", "Assert-VerifiedRouterService", '"$GatewayUrl/health"', "importLocalAgentProvider", "account-profiles.json", "CODEX_HOME", "CODEX_SQLITE_HOME", "codex-login-runtime", "global-profile-takeover.json", 'applyProfile = $true')) {
            if ($Text.IndexOf($Required, [System.StringComparison]::Ordinal) -lt 0) { throw "Required setting flow marker is missing: $Required" }
        }
        foreach ($ExternalMarker in @(
            ("GetFolder" + "Path"),
            ("USER" + "PROFILE"),
            ("Windows" + "Apps"),
            ("Get-Command " + "codex")
        )) {
            if ($Text.IndexOf($ExternalMarker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { throw "External Codex path discovery remains: $ExternalMarker" }
        }
        if (-not (Test-Path -LiteralPath $SettingPath -PathType Leaf) -or -not (Test-Path -LiteralPath $SettingExamplePath -PathType Leaf)) { throw "Root setting.json or setting.example.json is missing." }
        Write-Output "PASS: setting.json provider/profile schema and tier routing"
        Write-Output "PASS: managed providers merge without deleting CCR UI/account providers"
        Write-Output "PASS: loopback-only, proxy-off, request-log-off and Claude-only defaults"
        Write-Output "PASS: CCR agent profiles are removed so System default / CLI & APP cannot modify external apps"
        Write-Output "PASS: Windows DPAPI client-key round-trip without interactive API entry"
        Write-Output "PASS: multiple Codex account plugin names and local account routes are isolated"
        Write-Output "PASS: generated account route IDs accept slug-safe underscore and dot characters"
        Write-Output "PASS: verified CCR postcondition wins over a stale start exit while unverified starts fail closed"
        Write-Output "PASS: bounded Windows cold-start recovery matches only the exact CCR IPC timeout"
        Write-Output "PASS: sole Codex model auto-selection and exact multi-model resolution"
        Write-Output "PASS: unfinished project-local Codex login resumes by exact account label"
        Write-Output "PASS: Codex account homes force file-backed ChatGPT login inside router state"
        Write-Output "PASS: self-test used no provider request or management RPC"
    }
    finally {
        if (Test-Path -LiteralPath $TestRoot -PathType Container) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
        if (Test-Path -LiteralPath $TestCodexHome -PathType Container) { Remove-Item -LiteralPath $TestCodexHome -Recurse -Force }
    }
}

try {
    Ensure-StateDirectories
    if ($WarmRouter) { [void](Ensure-Router); exit 0 }
    if ($SelfTest) { Invoke-SelfTest; exit 0 }
    if ($StopRouter) { Stop-RouterService; exit 0 }
    if ($AddCodexPlan) { SignInAndImportCodexAccount -ExpectedPlan $AddCodexPlan -RequestedName $CodexAccountName; exit 0 }
    if ($LaunchProfileId) {
        if ($LaunchProfileId -notmatch '^[a-z0-9][a-z0-9_.-]{0,62}$') { throw "Invalid dashboard profile identifier." }
        $DashboardSetting = Ensure-SettingApplied
        $DashboardProfiles = @($DashboardSetting.profiles | Where-Object { $_.enabled }) + @(Read-AccountProfiles | Where-Object { $_.enabled })
        $DashboardProfile = @($DashboardProfiles | Where-Object { [string]$_.id -eq $LaunchProfileId }) | Select-Object -First 1
        if ($null -eq $DashboardProfile) { throw "The selected dashboard profile no longer exists or is disabled." }
        Start-Profile -Profile $DashboardProfile -Defaults $DashboardSetting.defaults -SessionId $ClaudeSessionId -SessionName $ClaudeSessionName -ResumeSession:$ResumeClaudeSession
        exit $script:MenuExitCode
    }
    if ($AccountMenu) { Invoke-AccountMenu; exit 0 }
    if ($SyncSettings) { [void](Ensure-SettingApplied -Force); exit 0 }
    if ($Launch) { Invoke-Menu; exit $script:MenuExitCode }
    Write-Output "Use -Launch, -LaunchProfileId, -AddCodexPlan, -SelfTest, -AccountMenu, -StopRouter, -SyncSettings, or -WarmRouter."
    exit 0
}
catch {
    $FailureLine = if ($null -ne $_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber -gt 0) { " (source line $($_.InvocationInfo.ScriptLineNumber))" } else { "" }
    Write-Error ("Router project menu failed${FailureLine}: " + $_.Exception.Message)
    exit 1
}
