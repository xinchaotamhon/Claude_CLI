[CmdletBinding()]
param(
    [ValidateSet('SelfTest', 'Status', 'Stop')]
    [string]$Action = 'SelfTest'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtimeRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot '.runtime\challenger'))
$binaryPath = [System.IO.Path]::GetFullPath((Join-Path $runtimeRoot 'bin\cli-proxy-api.exe'))
$fixtureBinaryPath = [System.IO.Path]::GetFullPath((Join-Path $runtimeRoot 'bin\challenger-fixture.exe'))
$manifestPath = Join-Path $projectRoot 'router_challenger\BUILD.json'
$templatePath = Join-Path $projectRoot 'router_challenger\pilot-config.template.yaml'
$pidPath = Join-Path $runtimeRoot 'pilot.pid'
$proxyPort = 18317
$fixturePort = 18442

function Assert-ProjectChild {
    param([Parameter(Mandatory = $true)][string]$Path)
    $resolved = [System.IO.Path]::GetFullPath($Path)
    $prefix = $projectRoot.TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes the project root: $resolved"
    }
    return $resolved
}

function Get-Manifest {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'Missing router_challenger\BUILD.json.'
    }
    return (Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json)
}

function Assert-BinaryIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedHash,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing. Run tools\build_challenger.ps1 explicitly."
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($actual -ne $ExpectedHash.ToLowerInvariant()) {
        throw "$Label hash mismatch. Expected $ExpectedHash, observed $actual."
    }
}

function Assert-ProcessIdentity {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][string]$ExpectedPath
    )
    $process = Get-Process -Id $ProcessId -ErrorAction Stop
    $actualPath = [System.IO.Path]::GetFullPath($process.Path)
    if (-not $actualPath.Equals($ExpectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "PID $ProcessId is not the verified pilot binary."
    }
    return $process
}

function Stop-VerifiedProcess {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][string]$ExpectedPath
    )
    try {
        $process = Assert-ProcessIdentity -ProcessId $ProcessId -ExpectedPath $ExpectedPath
    }
    catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
        return
    }
    Stop-Process -Id $process.Id -Force
    $process.WaitForExit(5000) | Out-Null
}

function Get-RandomLocalValue {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_'))
}

function Protect-DirectoryForCurrentUser {
    param([Parameter(Mandatory = $true)][string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $sid = $identity.User
    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
        [void]$acl.RemoveAccessRuleSpecific($rule)
    }
    $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $propagation = [System.Security.AccessControl.PropagationFlags]::None
    $access = [System.Security.AccessControl.AccessControlType]::Allow
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sid,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $inheritance,
        $propagation,
        $access
    )
    $acl.SetOwner($sid)
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl

    $verified = Get-Acl -LiteralPath $Path
    foreach ($entry in @($verified.Access)) {
        $entrySid = $entry.IdentityReference.Translate(
            [System.Security.Principal.SecurityIdentifier]
        )
        if ($entry.IsInherited -or $entry.AccessControlType -ne 'Allow' -or $entrySid.Value -ne $sid.Value) {
            throw "Auth ACL contains an unexpected access rule: $($entry.IdentityReference)."
        }
    }
    if (@($verified.Access).Count -lt 1) {
        throw 'Auth ACL has no current-user access rule.'
    }
}

function Write-PilotConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$AuthDir,
        [Parameter(Mandatory = $true)][string]$ClientKey,
        [Parameter(Mandatory = $true)][string]$ManagementKey,
        [Parameter(Mandatory = $true)][string]$UpstreamKey
    )
    $content = Get-Content -Raw -LiteralPath $templatePath
    $yamlAuth = $AuthDir.Replace('\', '/')
    $content = $content.Replace('__PROXY_PORT__', [string]$proxyPort)
    $content = $content.Replace('__FIXTURE_PORT__', [string]$fixturePort)
    $content = $content.Replace('__AUTH_DIR__', $yamlAuth)
    $content = $content.Replace('__CLIENT_KEY__', $ClientKey)
    $content = $content.Replace('__MANAGEMENT_KEY__', $ManagementKey)
    $content = $content.Replace('__UPSTREAM_KEY__', $UpstreamKey)
    if ($content -match '__[A-Z0-9_]+__') {
        throw 'Pilot config still contains an unresolved placeholder.'
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Destination, $content, $utf8)
}

function Wait-HttpReady {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [hashtable]$Headers = @{},
        [int]$TimeoutMilliseconds = 10000
    )
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastError = $null
    while ($watch.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -Headers $Headers -TimeoutSec 2
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                return [int]$watch.ElapsedMilliseconds
            }
        }
        catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 100
    }
    throw "Timed out waiting for $Uri. Last error: $lastError"
}

function Assert-LoopbackListener {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][int]$Port
    )
    $matching = @()
    foreach ($line in (& netstat.exe -ano -p tcp)) {
        if ($line -match '^\s*TCP\s+(\S+):(\d+)\s+(\S+):(\d+)\s+LISTENING\s+(\d+)\s*$') {
            if ([int]$Matches[2] -eq $Port -and [int]$Matches[5] -eq $ProcessId) {
                $matching += $Matches[1]
            }
        }
    }
    if ($matching.Count -ne 1 -or $matching[0] -ne '127.0.0.1') {
        throw "PID $ProcessId must listen exactly on 127.0.0.1:$Port; observed: $($matching -join ', ')."
    }
}

function Assert-NoExternalConnections {
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    foreach ($line in (& netstat.exe -ano -p tcp)) {
        if ($line -match '^\s*TCP\s+\S+\s+(\S+):(\d+)\s+ESTABLISHED\s+(\d+)\s*$') {
            if ([int]$Matches[3] -eq $ProcessId) {
                $remote = $Matches[1].Trim('[', ']')
                if ($remote -notin @('127.0.0.1', '::1')) {
                    throw "Pilot made a non-loopback connection to $remote."
                }
            }
        }
    }
}

function Start-HiddenProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$LogPrefix
    )
    return Start-Process -FilePath $FilePath -ArgumentList $ArgumentList `
        -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput ($LogPrefix + '.stdout.log') `
        -RedirectStandardError ($LogPrefix + '.stderr.log')
}

function Invoke-ClaudeMessage {
    param(
        [Parameter(Mandatory = $true)][string]$ClientKey,
        [Parameter(Mandatory = $true)][object]$Body,
        [switch]$Raw
    )
    $headers = @{
        'x-api-key' = $ClientKey
        'anthropic-version' = '2023-06-01'
        'content-type' = 'application/json'
    }
    $json = $Body | ConvertTo-Json -Depth 30 -Compress
    if ($Raw) {
        return Invoke-WebRequest -UseBasicParsing -Method Post `
            -Uri "http://127.0.0.1:$proxyPort/v1/messages" `
            -Headers $headers -Body $json -TimeoutSec 15
    }
    return Invoke-RestMethod -Method Post `
        -Uri "http://127.0.0.1:$proxyPort/v1/messages" `
        -Headers $headers -Body $json -TimeoutSec 15
}

function Start-Proxy {
    param(
        [Parameter(Mandatory = $true)][string]$SessionRoot,
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$ClientKey,
        [Parameter(Mandatory = $true)][string]$LogPrefix
    )
    $process = Start-HiddenProcess -FilePath $binaryPath `
        -ArgumentList @('-config', $ConfigPath, '-local-model') `
        -WorkingDirectory $SessionRoot -LogPrefix $LogPrefix
    [System.IO.File]::WriteAllText($pidPath, [string]$process.Id)
    try {
        $elapsed = Wait-HttpReady -Uri "http://127.0.0.1:$proxyPort/v1/models" `
            -Headers @{ Authorization = "Bearer $ClientKey" }
        [void](Assert-ProcessIdentity -ProcessId $process.Id -ExpectedPath $binaryPath)
        Assert-LoopbackListener -ProcessId $process.Id -Port $proxyPort
        Assert-NoExternalConnections -ProcessId $process.Id
        return [pscustomobject]@{ Process = $process; StartupMilliseconds = $elapsed }
    }
    catch {
        Stop-VerifiedProcess -ProcessId $process.Id -ExpectedPath $binaryPath
        throw
    }
}

function Invoke-ProtocolTests {
    param([Parameter(Mandatory = $true)][string]$ClientKey)
    $baseBody = [ordered]@{
        model = 'fixture/fixture-model'
        max_tokens = 128
        messages = @(@{ role = 'user'; content = 'offline non-stream check' })
    }
    $plain = Invoke-ClaudeMessage -ClientKey $ClientKey -Body $baseBody
    $plainText = (@($plain.content) | Where-Object { $_.type -eq 'text' } | Select-Object -First 1).text
    if ($plainText -ne 'Fixture response.') {
        throw "Unexpected non-stream response: $plainText"
    }

    $streamBody = [ordered]@{}
    foreach ($key in $baseBody.Keys) { $streamBody[$key] = $baseBody[$key] }
    $streamBody.stream = $true
    $stream = Invoke-ClaudeMessage -ClientKey $ClientKey -Body $streamBody -Raw
    if (
        $stream.Content -notmatch 'message_start' -or
        $stream.Content -notmatch 'Fixture ' -or
        $stream.Content -notmatch 'response\.' -or
        $stream.Content -notmatch 'message_stop'
    ) {
        throw 'Anthropic SSE translation did not produce the expected lifecycle/content.'
    }

    $toolBody = [ordered]@{
        model = 'fixture/fixture-model'
        max_tokens = 128
        messages = @(@{ role = 'user'; content = 'call the local lookup tool' })
        tools = @(@{
            name = 'local_lookup'
            description = 'Offline fixture tool'
            input_schema = @{
                type = 'object'
                properties = @{ value = @{ type = 'string' } }
                required = @('value')
            }
        })
    }
    $toolResponse = Invoke-ClaudeMessage -ClientKey $ClientKey -Body $toolBody
    $toolUse = @($toolResponse.content) | Where-Object { $_.type -eq 'tool_use' } | Select-Object -First 1
    if ($null -eq $toolUse -or $toolUse.name -ne 'local_lookup') {
        throw 'Claude tool-use translation did not expose local_lookup.'
    }
    $secondBody = [ordered]@{
        model = 'fixture/fixture-model'
        max_tokens = 128
        messages = @(
            @{ role = 'user'; content = 'call the local lookup tool' },
            @{ role = 'assistant'; content = @($toolResponse.content) },
            @{ role = 'user'; content = @(@{
                type = 'tool_result'
                tool_use_id = $toolUse.id
                content = 'fixture tool result'
            }) }
        )
        tools = $toolBody.tools
    }
    $toolFinal = Invoke-ClaudeMessage -ClientKey $ClientKey -Body $secondBody
    $finalText = (@($toolFinal.content) | Where-Object { $_.type -eq 'text' } | Select-Object -First 1).text
    if ($finalText -ne 'Fixture tool result received.') {
        throw "Unexpected post-tool response: $finalText"
    }
}

function Show-Status {
    $manifest = Get-Manifest
    Assert-BinaryIdentity -Path $binaryPath -ExpectedHash $manifest.binary.sha256 -Label 'Challenger binary'
    Assert-BinaryIdentity -Path $fixtureBinaryPath -ExpectedHash $manifest.fixture_binary.sha256 -Label 'Fixture binary'
    if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) {
        Write-Host '[OK] Pinned pilot binaries are present. No pilot PID is recorded.'
        return
    }
    $recorded = (Get-Content -Raw -LiteralPath $pidPath).Trim()
    $pidValue = 0
    if (-not [int]::TryParse($recorded, [ref]$pidValue)) {
        throw 'Pilot PID file is invalid.'
    }
    try {
        [void](Assert-ProcessIdentity -ProcessId $pidValue -ExpectedPath $binaryPath)
        Assert-LoopbackListener -ProcessId $pidValue -Port $proxyPort
        Write-Host "[OK] Verified pilot PID $pidValue is listening only on 127.0.0.1:$proxyPort."
    }
    catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
        Remove-Item -Force -LiteralPath $pidPath
        Write-Host '[OK] Removed a stale pilot PID record. No pilot is running.'
    }
}

function Stop-Pilot {
    if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) {
        Write-Host '[OK] No pilot PID is recorded.'
        return
    }
    $recorded = (Get-Content -Raw -LiteralPath $pidPath).Trim()
    $pidValue = 0
    if (-not [int]::TryParse($recorded, [ref]$pidValue)) {
        throw 'Pilot PID file is invalid; refusing to stop an unverified process.'
    }
    Stop-VerifiedProcess -ProcessId $pidValue -ExpectedPath $binaryPath
    Remove-Item -Force -LiteralPath $pidPath -ErrorAction SilentlyContinue
    Write-Host '[OK] Verified pilot process stopped.'
}

function Invoke-SelfTest {
    $manifest = Get-Manifest
    Assert-BinaryIdentity -Path $binaryPath -ExpectedHash $manifest.binary.sha256 -Label 'Challenger binary'
    Assert-BinaryIdentity -Path $fixtureBinaryPath -ExpectedHash $manifest.fixture_binary.sha256 -Label 'Fixture binary'
    Assert-ProjectChild -Path $runtimeRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null

    $sessionRoot = Assert-ProjectChild -Path (Join-Path $runtimeRoot ('selftest-' + [Guid]::NewGuid().ToString('N')))
    $authDir = Assert-ProjectChild -Path (Join-Path $sessionRoot 'auth')
    New-Item -ItemType Directory -Force -Path $sessionRoot | Out-Null
    Protect-DirectoryForCurrentUser -Path $authDir

    $clientKey = Get-RandomLocalValue
    $managementKey = Get-RandomLocalValue
    $upstreamKey = Get-RandomLocalValue
    $configPath = Join-Path $sessionRoot 'config.yaml'
    Write-PilotConfig -Destination $configPath -AuthDir $authDir `
        -ClientKey $clientKey -ManagementKey $managementKey -UpstreamKey $upstreamKey

    $fixture = $null
    $proxy = $null
    $firstStartup = $null
    $restartStartup = $null
    try {
        $fixture = Start-HiddenProcess -FilePath $fixtureBinaryPath `
            -ArgumentList @('--host', '127.0.0.1', '--port', [string]$fixturePort) `
            -WorkingDirectory $sessionRoot -LogPrefix (Join-Path $sessionRoot 'fixture')
        [void](Wait-HttpReady -Uri "http://127.0.0.1:$fixturePort/health")
        [void](Assert-ProcessIdentity -ProcessId $fixture.Id -ExpectedPath $fixtureBinaryPath)
        Assert-LoopbackListener -ProcessId $fixture.Id -Port $fixturePort

        $started = Start-Proxy -SessionRoot $sessionRoot -ConfigPath $configPath `
            -ClientKey $clientKey -LogPrefix (Join-Path $sessionRoot 'proxy-first')
        $proxy = $started.Process
        $firstStartup = $started.StartupMilliseconds
        Invoke-ProtocolTests -ClientKey $clientKey
        Assert-NoExternalConnections -ProcessId $proxy.Id

        Stop-VerifiedProcess -ProcessId $proxy.Id -ExpectedPath $binaryPath
        $proxy = $null
        Remove-Item -Force -LiteralPath $pidPath -ErrorAction SilentlyContinue

        $restarted = Start-Proxy -SessionRoot $sessionRoot -ConfigPath $configPath `
            -ClientKey $clientKey -LogPrefix (Join-Path $sessionRoot 'proxy-restart')
        $proxy = $restarted.Process
        $restartStartup = $restarted.StartupMilliseconds
        Assert-NoExternalConnections -ProcessId $proxy.Id

        Write-Host '[PASS] Binary identity and project-local runtime paths'
        Write-Host '[PASS] Current-user-only auth ACL'
        Write-Host '[PASS] Loopback-only proxy and fixture listeners'
        Write-Host '[PASS] No non-loopback connection observed'
        Write-Host '[PASS] Anthropic non-stream, SSE stream and tool round-trip'
        Write-Host "[PASS] Startup ${firstStartup}ms; restart ${restartStartup}ms"
    }
    finally {
        if ($null -ne $proxy) {
            Stop-VerifiedProcess -ProcessId $proxy.Id -ExpectedPath $binaryPath
        }
        if ($null -ne $fixture) {
            Stop-VerifiedProcess -ProcessId $fixture.Id -ExpectedPath $fixtureBinaryPath
        }
        Remove-Item -Force -LiteralPath $pidPath -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $sessionRoot) {
            $verifiedSession = Assert-ProjectChild -Path $sessionRoot
            Remove-Item -LiteralPath $verifiedSession -Recurse -Force
        }
    }
}

try {
    switch ($Action) {
        'SelfTest' { Invoke-SelfTest }
        'Status' { Show-Status }
        'Stop' { Stop-Pilot }
    }
    exit 0
}
catch {
    Write-Error ("Challenger pilot failed: " + $_.Exception.Message)
    exit 1
}
