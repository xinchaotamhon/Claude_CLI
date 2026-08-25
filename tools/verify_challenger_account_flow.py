#!/usr/bin/env python3
"""Verify the Google Pro project-local OAuth wrapper without reading auth state."""

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
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    script_path = root / "tools" / "challenger_account_menu.ps1"
    template_path = root / "router_challenger" / "account-config.template.yaml"
    source_path = root / "router_challenger" / "SOURCE.json"
    build_path = root / "router_challenger" / "BUILD.json"
    batch_path = root / "router_challenger" / "account-batch.example.json"
    menu_path = root / "tools" / "router_project_menu.ps1"
    for path in (script_path, template_path, source_path, build_path, batch_path, menu_path):
        if not path.is_file():
            return fail(f"missing Google account-flow file: {path.relative_to(root).as_posix()}")

    script = read(script_path)
    required = (
        '$AccountsRoot = [System.IO.Path]::GetFullPath((Join-Path $RuntimeRoot "accounts\\google"))',
        '$GoogleSlots = @("google_pro_1", "google_pro_2", "google_pro_3")',
        "google_pro_1 = 51121",
        "google_pro_2 = 51122",
        "google_pro_3 = 51123",
        "function Protect-DirectoryForCurrentUser",
        "function Assert-AccountRuntime",
        "function Assert-CallbackPortFree",
        "function Add-GoogleAccount",
        "-antigravity-login -oauth-callback-port $Port -local-model",
        'provider = "google_ai"',
        'expected_plan = "google_ai_pro"',
        '@("gemini_models", "claude_gpt_models")',
        "Get-FileHash -Algorithm SHA256 -LiteralPath $BinaryPath",
        "oauth_callback_loopback_only",
        "AuthFiles.Count -ne 1",
        "Get-NetTCPConnection -State Listen -LocalPort $Port",
    )
    for marker in required:
        if marker not in script:
            return fail(f"missing Google account isolation marker: {marker}")

    forbidden = (
        "USERPROFILE",
        "GetFolderPath",
        "Get-Command codex",
        "WindowsApps",
        "Start-Process codex",
        "setting.json",
        "provider_router/.ccr-local",
        "ConvertFrom-Json $Auth",
        "Get-Content -Raw -LiteralPath $Auth",
        "Remove-Item -LiteralPath $State.root",
    )
    for marker in forbidden:
        if marker.casefold() in script.casefold():
            return fail(f"unsafe/global Google account behavior found: {marker}")
    if re.search(r"(?i)Write-(?:Host|Output).*?(?:access_token|refresh_token|auth-file-content|token-value)", script):
        return fail("Google account wrapper may print credential material")

    template = read(template_path)
    for marker in (
        'host: "127.0.0.1"',
        'allow-remote: false',
        'disable-control-panel: true',
        'disable-auto-update-panel: true',
        'auth-dir: "__AUTH_DIR__"',
        "usage-statistics-enabled: false",
        'proxy-url: ""',
        "request-retry: 0",
    ):
        if marker not in template:
            return fail(f"unsafe Google OAuth template: missing {marker}")

    try:
        source = json.loads(read(source_path))
        build = json.loads(read(build_path))
        batch = json.loads(read(batch_path))
    except json.JSONDecodeError as exc:
        return fail(f"invalid tracked account metadata: {exc}")
    if source.get("policy", {}).get("oauth_callback_loopback_only") is not True:
        return fail("source policy does not require a loopback OAuth callback")
    patches = source.get("patches")
    if not isinstance(patches, list) or len(patches) != 2:
        return fail("reviewed two-patch challenger series is missing")
    for patch in patches:
        path = root / str(patch.get("file", ""))
        if not path.is_file() or sha256(path) != patch.get("sha256"):
            return fail("reviewed challenger patch hash mismatch")
    if build.get("source", {}).get("patched_commit") != source.get("patched_commit"):
        return fail("build/source patched commits disagree")
    if batch.get("automatic_fallback_default") is not False:
        return fail("account onboarding must keep automatic fallback disabled")
    if [slot.get("id") for slot in batch.get("slots", []) if slot.get("expected_plan") == "codex_free"] != ["codex_free_1", "codex_free_2", "codex_free_3"]:
        return fail("account onboarding does not preserve the existing Free slot plus two additional Free slots")
    google = [slot for slot in batch.get("slots", []) if slot.get("provider") == "google_ai"]
    if [slot.get("id") for slot in google] != ["google_pro_1", "google_pro_2", "google_pro_3"]:
        return fail("account onboarding does not define the exact three Google Pro slots")

    menu = read(menu_path)
    if "function Invoke-GoogleAccountMenu" not in menu or "challenger_account_menu.ps1" not in menu:
        return fail("SIGN_ACCOUNT project menu does not expose the Google Pro helper")

    print("PASS: three Google Pro OAuth slots use ignored project-local account directories")
    print("PASS: callback ports and patched listener are loopback-only")
    print("PASS: binary/source/patch identity and current-user-only ACL controls are present")
    print("PASS: no global Codex App/account path or credential parser is used")
    print("network: not used; auth directories were not read")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
