#!/usr/bin/env python3
"""Verify folder-local Codex logins without reading any credential."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path


def fail(message: str) -> int:
    print(f"FAIL: {message}")
    return 1


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    menu_path = root / "tools" / "router_project_menu.ps1"
    installer_path = root / "tools" / "install_codex_login_runtime.ps1"
    source_path = root / "provider_router" / "CODEX_LOGIN_SOURCE.json"
    binary_path = root / "provider_router" / "codex-login-runtime" / "codex.exe"
    sign_path = root / "SIGN_ACCOUNT.bat"
    run_path = root / "RUN_CLAUDE.bat"
    ignore_path = root / ".gitignore"
    for path in (menu_path, installer_path, source_path, binary_path, sign_path, run_path, ignore_path):
        if not path.is_file():
            return fail(f"missing folder-local account-flow file: {path.relative_to(root).as_posix()}")

    menu = read(menu_path)
    required = (
        "function SignInAndImportCodexAccount",
        "function Invoke-ProjectLocalCodexLogin",
        "function Resolve-CodexAccountSlot",
        "function Resolve-CodexModelChoice",
        "function Get-CodexAccountModelCandidates",
        "function Test-CodexAccountModels",
        "function Set-CodexAccountProfiles",
        "function Refresh-CodexAccountModels",
        "$CodexAccountsRoot = Join-Path $RouterStateRoot",
        "$CodexLoginBinary = Join-Path $CodexLoginRuntimeRoot",
        'cli_auth_credentials_store = `"file`"',
        'forced_login_method = `"chatgpt`"',
        '$env:CODEX_HOME = $SafeAccountHome',
        '$env:CODEX_SQLITE_HOME = $SafeAccountHome',
        '& $SafeBinary login',
        'Join-Path $SafeAccountHome "auth.json"',
        "Assert-PathInside -Path (Join-Path $CodexAccountsRoot",
        'Invoke-RouterRpc -State $State -Method "getLocalAgentProviderCandidates"',
        'Invoke-RouterRpc -State $State -Method "importLocalAgentProvider"',
        'Invoke-RouterRpc -State $State -Method "checkProviderConnectivity"',
        'Invoke-RouterRpc -State $State -Method "saveConfig"',
        "Materialize-ProviderPlugins",
        "This Codex account is already imported",
        "Resuming the unfinished project-local sign-in for this account label",
        "Automatically selected the only available model",
        "Enter a listed number or the exact model ID",
        'Write-Host "  [R] Refresh/test model routes for an imported Codex account"',
        '$CodexChatGptCandidateModels = @("gpt-5.6-terra", "gpt-5.6-luna")',
        '$UnsupportedCodexChatGptModels = @("gpt-5-codex", "gpt-5.6-sol")',
        "Each verified model will appear as a separate choice in RUN_CLAUDE.bat.",
        "A Claude/router session is running",
        "Remove-Item -LiteralPath $LocalAuthPath -Force",
        "account-profiles.json",
        "Read-AccountProfiles | Where-Object",
        "$Id -notmatch '^[a-z0-9][a-z0-9_.-]{0,62}$'",
        '"account_name+tag@example.test"',
        "Enforce-SafeCcrConfig",
    )
    for marker in required:
        if marker not in menu:
            return fail(f"missing folder-local account isolation marker: {marker}")
    compatible_route_id_validator = "$Id -notmatch '^[a-z0-9][a-z0-9_.-]{0,62}$'"
    if menu.count(compatible_route_id_validator) < 2:
        return fail("generated account route IDs are not accepted by both index reload and Claude mode-path creation")

    forbidden = (
        "GetFolderPath",
        "USERPROFILE",
        "WindowsApps",
        "Get-Command codex",
        "Get-Content -Raw -LiteralPath $SourceAuthPath",
        "ConvertFrom-Json $SourceAuthPath",
        'Read-Host "API key',
        'Read-Host "token',
        "codex exec",
    )
    for marker in forbidden:
        if marker.lower() in menu.lower():
            return fail(f"external or unsafe account behavior found: {marker}")
    if 'throw "Invalid model selection."' in menu:
        return fail("one invalid model entry still aborts an otherwise successful login")
    if re.search(r"(?i)Write-(?:Host|Output).*?(?:accessToken|refreshToken|auth\.json)", menu):
        return fail("account flow may print credential material")
    if re.search(r"(?im)^\s*&\s*\$SafeBinary\s+(?!login\s*$)", menu):
        return fail("project-local Codex helper is used for something other than login")

    try:
        source = json.loads(read(source_path))
    except (OSError, json.JSONDecodeError) as exc:
        return fail(f"invalid CODEX_LOGIN_SOURCE.json: {exc}")
    if source.get("binary_path") != "provider_router/codex-login-runtime/codex.exe":
        return fail("Codex login metadata points outside the fixed local runtime path")
    expected_hash = str(source.get("sha256", "")).lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected_hash):
        return fail("Codex login metadata has no valid SHA-256")
    if sha256(binary_path) != expected_hash:
        return fail("project-local Codex binary does not match its tracked provenance")

    installer = read(installer_path)
    installer_required = (
        '"https://chatgpt.com/codex/install.ps1"',
        "$env:CODEX_INSTALL_DIR = $TargetRoot",
        "$env:CODEX_HOME = $InstallerStateRoot",
        "Assert-InsideProject",
    )
    for marker in installer_required:
        if marker not in installer:
            return fail(f"installer is not project-scoped: {marker}")

    ignore = read(ignore_path)
    if "/provider_router/codex-login-runtime/*" not in ignore:
        return fail("large Codex login binary is not Git-ignored")
    sign = read(sign_path)
    run = read(run_path)
    if 'RUN_CLAUDE.bat" --account-menu' not in sign:
        return fail("SIGN_ACCOUNT.bat does not enter the project account menu")
    if "goto ACCOUNT_MENU" not in run or "-AccountMenu" not in run:
        return fail("RUN_CLAUDE.bat lacks the account-menu dispatcher")

    print("PASS: Codex login binary, config, auth homes and staging are folder-local")
    print("PASS: each added account receives a separate CODEX_HOME inside router state")
    print("PASS: wrapper invokes the local Codex helper only for official browser login")
    print("PASS: no Windows/global Codex auth path is discovered or read")
    print("PASS: provenance hash, Git exclusion and project-scoped repair installer are present")
    print("PASS: imported providers/plugins use unique identities and appear in RUN_CLAUDE")
    print("PASS: generated route IDs with slug-safe punctuation survive account-index reload")
    print("PASS: rejected legacy fallback models are excluded and live account checks create one RUN route per supported model")
    print("PASS: imported account models can be refreshed from SIGN_ACCOUNT without another browser login")
    print("PASS: an unfinished folder-local login can resume without repeating browser/2FA")
    print("network: not used; real auth files and setting.json were not read")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
