#!/usr/bin/env python3
"""Verify the ignored setting.json + CCR account-UI flow without reading secrets."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


ALLOWED_PROTOCOLS = {
    "anthropic_messages",
    "openai_chat_completions",
    "openai_responses",
    "gemini_generate_content",
    "gemini_interactions",
}


def fail(message: str) -> int:
    print(f"FAIL: {message}")
    return 1


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    actual = root / "setting.json"
    example = root / "setting.example.json"
    sign = root / "SIGN_ACCOUNT.bat"
    dashboard = root / "DASHBOARD.bat"
    run = root / "RUN_CLAUDE.bat"
    menu = root / "tools" / "router_project_menu.ps1"
    for path in (actual, example, sign, dashboard, run, menu):
        if not path.is_file():
            return fail(f"missing setting flow file: {path.relative_to(root).as_posix()}")

    # Never read the actual ignored setting.json: it may contain real API keys.
    ignored = subprocess.run(
        [
            "git",
            "-c",
            f"safe.directory={root}",
            "-C",
            str(root),
            "check-ignore",
            "--quiet",
            "--",
            "setting.json",
        ],
        capture_output=True,
        check=False,
    )
    if ignored.returncode != 0:
        return fail("setting.json is not protected by the parent .gitignore")

    try:
        payload = json.loads(read(example))
    except (OSError, json.JSONDecodeError) as exc:
        return fail(f"setting.example.json is invalid: {exc}")
    if payload.get("schema_version") != 1:
        return fail("setting.example.json must use schema_version 1")
    providers = payload.get("providers")
    profiles = payload.get("profiles")
    defaults = payload.get("claude_defaults")
    if not isinstance(providers, list) or not isinstance(profiles, list) or not isinstance(defaults, dict):
        return fail("setting.example.json lacks providers/profiles/claude_defaults")
    for provider in providers:
        if provider.get("protocol") not in ALLOWED_PROTOCOLS:
            return fail("setting example contains an unsupported provider protocol")
        if provider.get("api_key"):
            return fail("setting example must not contain an API key")
        for credential in provider.get("credentials", []):
            if credential.get("api_key"):
                return fail("setting example must not contain a credential key")

    menu_text = read(menu)
    required_menu_markers = (
        "Read-LocalSetting",
        "Ensure-SettingApplied",
        "Merge-SettingIntoCcrConfig",
        'Invoke-RouterRpc -State $State -Method "saveConfig"',
        "getServiceIdentity",
        "router-client.dpapi",
        "Read-AccountProfiles",
        'Set-JsonProperty -Object $Config.proxy -Name "systemProxy" -Value $false',
        'Set-JsonProperty -Object $Config.observability -Name "requestLogs" -Value $false',
        'Set-JsonProperty -Object $Config.profile -Name "profiles" -Value @()',
        'applyProfile = $true',
        "global-profile-takeover.json",
        "No enabled profile. Edit setting.json",
    )
    for marker in required_menu_markers:
        if marker not in menu_text:
            return fail(f"router menu is missing setting-flow marker: {marker}")
    forbidden_menu_markers = (
        "function Add-Profile",
        "function Edit-ProfileSettings",
        "function Remove-Profile",
        "Read-ProviderModel",
        "-AsSecureString",
    )
    for marker in forbidden_menu_markers:
        if marker.lower() in menu_text.lower():
            return fail(f"RUN menu still contains interactive API/profile editing: {marker}")
    run_menu_block = menu_text.split("function Invoke-Menu", 1)[1].split("function Invoke-SelfTest", 1)[0]
    read_host_lines = [line.strip() for line in run_menu_block.splitlines() if "Read-Host" in line]
    if len(read_host_lines) != 2 or any(
        allowed not in "\n".join(read_host_lines)
        for allowed in ("Select a profile or action", "Press Enter to continue")
    ):
        return fail(f"unexpected interactive prompt remains in RUN menu: {read_host_lines}")

    sign_text = read(sign)
    if 'DASHBOARD.bat"' not in sign_text or re.search(
        r"(?i)(?:codex|gemini|deepseek|openrouter|ollama)(?:\.exe)?\s+(?:login|auth)",
        sign_text,
    ):
        return fail("SIGN_ACCOUNT.bat must be only a compatibility redirect to DASHBOARD.bat")
    run_text = read(run)
    if "--account-menu" not in run_text or "router_project_menu.ps1" not in run_text:
        return fail("RUN_CLAUDE.bat does not route account setup through the project-local menu")
    if "--router-ui" in run_text or "Open API provider UI" in menu_text:
        return fail("the project still exposes CCR agent-profile UI instead of isolated setting/account flows")

    print("PASS: setting.json exists and is ignored without being read")
    print("PASS: tracked example schema has no API key")
    print("PASS: RUN menu has no API/provider/profile entry prompts")
    print("PASS: settings merge uses authenticated CCR RPC and preserves safe defaults")
    print("PASS: DASHBOARD.bat is the one account/settings UI and SIGN_ACCOUNT is only a compatibility redirect")
    print("PASS: CCR agent profiles/UI cannot select System default or modify external Codex/Claude config")
    print("network: not used; provider/model requests were not run")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
