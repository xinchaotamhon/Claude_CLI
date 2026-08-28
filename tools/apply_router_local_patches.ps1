[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RootPath = [System.IO.Path]::GetFullPath($Root)
$RouterRoot = [System.IO.Path]::GetFullPath((Join-Path $RootPath "provider_router"))
$Entry = [System.IO.Path]::GetFullPath((Join-Path $RouterRoot "node_modules\@musistudio\claude-code-router\dist\main\cli.js"))
$PackagePath = [System.IO.Path]::GetFullPath((Join-Path $RouterRoot "node_modules\@musistudio\claude-code-router\package.json"))

if (-not $RouterRoot.StartsWith($RootPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Router runtime resolved outside the project root."
}
if (-not (Test-Path -LiteralPath $Entry -PathType Leaf) -or -not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
    throw "Pinned router runtime is missing; run tools\RUN_CLAUDE_TECHNICAL.bat --install-router."
}
$Version = [string](Get-Content -Raw -LiteralPath $PackagePath | ConvertFrom-Json).version
if ($Version -ne "3.0.21") {
    throw "Local runtime patch is reviewed only for CCR 3.0.21; found '$Version'."
}

$Patches = @(
    [PSCustomObject]@{
        Name = "bounded gateway acceptance timeout"
        Original = 'var HM="gateway",_Z=5e3,PZ=15e3,Qqe=4e3'
        Patched = 'var HM="gateway",_Z=(()=>{let e=Number(process.env.CCR_GATEWAY_CONFIG_ACCEPTANCE_TIMEOUT_MS);return Number.isFinite(e)&&e>=5e3&&e<=6e4?Math.trunc(e):5e3})(),PZ=15e3,Qqe=4e3'
    },
    [PSCustomObject]@{
        Name = "isolate Windows core gateway from launcher console"
        Original = 'cwd:$,env:c,serialization:"advanced",stdio:["ignore","pipe","pipe","ipc"]'
        Patched = 'cwd:$,detached:process.platform==="win32",env:c,serialization:"advanced",stdio:["ignore","pipe","pipe","ipc"],windowsHide:process.platform==="win32"'
    },
    [PSCustomObject]@{
        Name = "disable external Claude App sync in provider-only mode"
        Original = 'try{t=(await Wa(t)).config}catch(n){console.error(`Failed to sync Claude App gateway config during ${e}: ${xc(n)}`)}'
        Patched = 'try{process.env.CCR_PROVIDER_GATEWAY_ONLY!=="1"&&(t=(await Wa(t)).config)}catch(n){console.error(`Failed to sync Claude App gateway config during ${e}: ${xc(n)}`)}'
    },
    [PSCustomObject]@{
        Name = "disable external agent profile apply in provider-only mode"
        Original = ',r.state==="running"){let n=await is(t,{excludeAgents:["zcode"]});vR(n)}'
        Patched = ',r.state==="running"&&process.env.CCR_PROVIDER_GATEWAY_ONLY!=="1"){let n=await is(t,{excludeAgents:["zcode"]});vR(n)}'
    },
    [PSCustomObject]@{
        Name = "disable external Claude App restore in provider-only mode"
        Original = 'try{j5()}catch(e){console.error(`Failed to restore Claude App gateway config: ${xc(e)}`)}'
        Patched = 'if(process.env.CCR_PROVIDER_GATEWAY_ONLY!=="1")try{j5()}catch(e){console.error(`Failed to restore Claude App gateway config: ${xc(e)}`)}'
    }
)

$Text = [System.IO.File]::ReadAllText($Entry)
$Changed = $false
foreach ($Patch in $Patches) {
    $PatchedCount = ([regex]::Matches($Text, [regex]::Escape([string]$Patch.Patched))).Count
    $OriginalCount = ([regex]::Matches($Text, [regex]::Escape([string]$Patch.Original))).Count
    # A patched replacement may intentionally contain the original text as a
    # suffix (for example a new guard before an existing try/catch). Treat the
    # exact patched marker as authoritative so the patcher remains idempotent.
    if ($PatchedCount -eq 1) { continue }
    if ($PatchedCount -ne 0 -or $OriginalCount -ne 1) {
        throw "Runtime patch '$($Patch.Name)' did not match exactly once; no file was changed."
    }
    $Text = $Text.Replace([string]$Patch.Original, [string]$Patch.Patched)
    $Changed = $true
}

if ($Changed) {
    $Temporary = $Entry + ".ccr-local-patch-tmp"
    try {
        [System.IO.File]::WriteAllText($Temporary, $Text, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $Temporary -Destination $Entry -Force
    }
    finally {
        if (Test-Path -LiteralPath $Temporary) { Remove-Item -LiteralPath $Temporary -Force }
    }
}

$Verified = [System.IO.File]::ReadAllText($Entry)
foreach ($Patch in $Patches) {
    if (([regex]::Matches($Verified, [regex]::Escape([string]$Patch.Patched))).Count -ne 1) {
        throw "Runtime patch verification failed for '$($Patch.Name)'."
    }
}

Write-Host "PASS: project-local CCR provider-only runtime patch is present." -ForegroundColor Green
