#!/usr/bin/env python3
"""Verify that normal project flows cannot take over external agent apps.

This gate reads tracked launcher/documentation only. It never reads the user's
global Codex/Claude config, ignored router database, auth, DPAPI or settings.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def fail(message: str) -> int:
    print(f"FAIL: {message}")
    return 1


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    menu_path = root / "tools" / "router_project_menu.ps1"
    launcher_path = root / "tools" / "RUN_CLAUDE_TECHNICAL.bat"
    start_path = root / "START_HERE.md"
    runbook_path = root / "docs" / "ROUTER_LOCAL.md"
    for path in (menu_path, launcher_path, start_path, runbook_path):
        if not path.is_file():
            return fail(f"missing isolation artifact: {path.relative_to(root).as_posix()}")

    menu = read(menu_path)
    launcher = read(launcher_path)
    guidance = f"{read(start_path)}\n{read(runbook_path)}"

    required = (
        '$GlobalProfileTakeoverPath = Join-Path',
        '"global-profile-takeover.json"',
        'Set-JsonProperty -Object $Config.profile -Name "profiles" -Value @()',
        '$Options = [PSCustomObject]@{ applyProfile = $true }',
        '-not (Test-Path -LiteralPath $GlobalProfileTakeoverPath -PathType Leaf)',
    )
    for marker in required:
        if marker not in menu:
            return fail(f"router isolation control is missing: {marker}")

    forbidden = {
        "launcher --router-ui": "--router-ui" in launcher,
        "menu OpenRouterUi": "Open-RouterUi" in menu,
        "menu UI launch": bool(re.search(r'Invoke-Ccr\s+-Arguments\s+@\("ui"', menu)),
        "account option [2]": "Open API provider UI" in menu,
        "profile save without cleanup": "applyProfile = $false" in menu,
    }
    active_forbidden = [name for name, present in forbidden.items() if present]
    if active_forbidden:
        return fail(f"external-app takeover surface remains: {active_forbidden}")

    for phrase in ("System default", "CLI & APP", "setting.json"):
        if phrase not in guidance:
            return fail(f"isolation guidance is missing: {phrase}")

    print("PASS: normal launchers do not expose CCR agent UI")
    print("PASS: every synchronized config removes agent profiles and applies cleanup")
    print("PASS: a local takeover marker invalidates the fast path and forces restoration")
    print("PASS: documentation warns that System default / CLI & APP are external scopes")
    print("external config/auth: not read; network: not used")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
