#!/usr/bin/env python3
"""Deterministically verify the project-local Claude Code Router boundary.

This check is deliberately offline. It reads only tracked provenance plus the
installed package manifest and invokes local Node with ``--version``. It never
opens ignored runtime/config contents, resolves credentials, starts a gateway,
or contacts a provider.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path


PINNED_ROUTER_VERSION = "3.0.21"
KEY_SHAPED = re.compile(
    r"(?i)(?:sk-(?:ant|or|proj)-[a-z0-9_-]{20,}|"
    r"AIza[0-9A-Za-z_-]{20,}|"
    r"xox[baprs]-[0-9A-Za-z-]{20,}|"
    r"gh[pousr]_[0-9A-Za-z_]{20,})"
)
FORBIDDEN_CLI_INVOCATION = re.compile(
    r"(?im)(?:start-process\s+[^\r\n]*(?:codex|claudy|gemini|deepseek|"
    r"openrouter|ollama|anthropic)[^\r\n]*|"
    r"(?:^|[&|])[ \t]*(?:codex|claudy|gemini|deepseek|openrouter|ollama|"
    r"anthropic)(?:\.exe)?(?:[ \t]|$))"
)


def fail(message: str) -> int:
    print(f"FAIL: {message}")
    return 1


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def run_local_version(executable: Path, *arguments: str) -> tuple[int, str]:
    # Do not inherit provider credentials, proxy settings, or user config
    # selectors while probing local versions.  The executable is absolute and
    # does not need the project's PATH to answer --version.
    safe_env = {
        name: value
        for name in ("SystemRoot", "SystemDrive", "ComSpec", "TEMP", "TMP")
        if (value := os.environ.get(name))
    }
    try:
        result = subprocess.run(
            [str(executable), *arguments],
            cwd=executable.parent,
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
            shell=False,
            env=safe_env,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return 1, f"ERROR: {exc}"
    output = " ".join((result.stdout + " " + result.stderr).split())
    return result.returncode, output


def assert_markers(text: str, markers: tuple[str, ...], label: str) -> str | None:
    for marker in markers:
        if marker not in text:
            return f"{label} is missing required marker: {marker}"
    return None


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    package_path = root / "provider_router" / "package.json"
    source_path = root / "provider_router" / "SOURCE.json"
    claude_binary = root / "bin" / "claude.exe"
    node_binary = root / "provider_router" / "runtime" / "node.exe"
    router_package = (
        root
        / "provider_router"
        / "node_modules"
        / "@musistudio"
        / "claude-code-router"
        / "package.json"
    )
    launcher_path = root / "tools" / "RUN_CLAUDE_TECHNICAL.bat"
    menu_path = root / "tools" / "router_project_menu.ps1"
    installer_path = root / "tools" / "install_router_runtime.ps1"
    lock_path = root / "provider_router" / "package-lock.json"
    gitignore_path = root / ".gitignore"
    source_repo = root / "claude-code-router_proxy"

    for path in (
        claude_binary,
        package_path,
        lock_path,
        source_path,
        launcher_path,
        menu_path,
        installer_path,
        gitignore_path,
    ):
        if not path.is_file():
            return fail(f"missing required router item: {path.relative_to(root).as_posix()}")
    if not node_binary.is_file():
        return fail("missing ignored project-local Node runtime: provider_router/runtime/node.exe")
    router_entry = router_package.parent / "dist" / "main" / "cli.js"
    if not router_entry.is_file() or not router_package.is_file():
        return fail(
            "missing ignored installed router CLI entry: "
            "provider_router/node_modules/@musistudio/claude-code-router/dist/main/cli.js"
        )
    if not (source_repo / ".git").exists() or not (source_repo / "package.json").is_file():
        return fail("missing reviewable router source fork: claude-code-router_proxy")
    if claude_binary.stat().st_size < 1_000_000:
        return fail("bin/claude.exe is unexpectedly small")

    try:
        package = json.loads(read_text(package_path))
        source = json.loads(read_text(source_path))
    except (OSError, json.JSONDecodeError) as exc:
        return fail(f"router provenance metadata is invalid: {exc}")
    if package.get("dependencies", {}).get("@musistudio/claude-code-router") != PINNED_ROUTER_VERSION:
        return fail("provider_router/package.json does not pin Claude Code Router 3.0.21")
    if source.get("version") != PINNED_ROUTER_VERSION:
        return fail("provider_router/SOURCE.json does not pin Claude Code Router 3.0.21")
    if source.get("package") != "@musistudio/claude-code-router":
        return fail("provider_router/SOURCE.json names an unexpected router package")
    if source.get("local_source") != "claude-code-router_proxy" or source.get("local_branch") != "claude":
        return fail("provider_router/SOURCE.json does not own the local source fork/branch")
    try:
        source_package = json.loads(read_text(source_repo / "package.json"))
    except (OSError, json.JSONDecodeError) as exc:
        return fail(f"router source package metadata is invalid: {exc}")
    if source_package.get("version") != PINNED_ROUTER_VERSION:
        return fail("router source fork version differs from the pinned runtime")
    source_git = subprocess.run(
        [
            "git",
            "-c",
            f"safe.directory={source_repo}",
            "-C",
            str(source_repo),
            "rev-parse",
            "--abbrev-ref",
            "HEAD",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if source_git.returncode != 0 or source_git.stdout.strip() != "claude":
        return fail("router source fork must be on local branch 'claude'")
    source_head = subprocess.run(
        ["git", "-c", f"safe.directory={source_repo}", "-C", str(source_repo), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=False,
    )
    if source_head.returncode != 0 or source_head.stdout.strip() != source.get("source_commit"):
        return fail("router source fork HEAD differs from the reviewed source commit")

    parent_branch = subprocess.run(
        [
            "git",
            "-c",
            f"safe.directory={root}",
            "-C",
            str(root),
            "branch",
            "--show-current",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if parent_branch.returncode != 0 or parent_branch.stdout.strip() != "claude":
        return fail("parent project must be initialized on branch 'claude'")
    ignored_paths = (
        "bin/claude.exe",
        "provider_router/runtime/node.exe",
        "provider_router/node_modules/",
        "provider_router/.ccr-local/",
        "provider_router/codex-login-runtime/codex.exe",
        "claude-code-router_proxy/",
        ".tmp/",
    )
    missing = []
    for ignored_path in ignored_paths:
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
                ignored_path,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if ignored.returncode != 0:
            missing.append(ignored_path)
    if missing:
        return fail(f"parent .gitignore does not protect local runtime/state paths: {missing}")

    launcher = read_text(launcher_path)
    launcher_error = assert_markers(
        launcher,
        (
            "router_project_menu.ps1",
            "ROUTER_ROOT=%ROOT%\\provider_router",
            "ROUTER_NODE=%ROUTER_ROOT%\\runtime\\node.exe",
            "ROUTER_ENTRY=%ROUTER_ROOT%\\node_modules\\@musistudio\\claude-code-router\\dist\\main\\cli.js",
            "ROUTER_HOME=%ROUTER_ROOT%\\.ccr-local",
            "CCR_INTERNAL_HOME_DIR=%ROUTER_HOME%\\home",
            "CCR_INTERNAL_APP_DATA_DIR=%ROUTER_HOME%\\appdata",
            "CCR_INTERNAL_USER_DATA_DIR=%ROUTER_HOME%\\userdata",
            "CCR_WEB_HOST=127.0.0.1",
            "CLAUDE_CODE_TMPDIR=%ROOT%\\.tmp",
            "DISABLE_AUTOUPDATER=1",
        ),
        "RUN_CLAUDE.bat",
    )
    if launcher_error:
        return fail(launcher_error)
    if "claudy_project_menu.ps1" in launcher or "claudy_provider-clitool" in launcher:
        return fail("RUN_CLAUDE.bat still references the retired Claudy layout")
    if "--router-ui" in launcher:
        return fail("RUN_CLAUDE.bat still exposes the CCR agent UI that can modify external app configuration")
    if re.search(r"(?im)^\s*(?:set\s+)?(?:CLAUDY_|CODEX_|ANTHROPIC_API_KEY)", launcher):
        return fail("RUN_CLAUDE.bat contains a retired Claudy/Codex/provider environment variable")

    try:
        lock = json.loads(read_text(lock_path))
    except (OSError, json.JSONDecodeError) as exc:
        return fail(f"provider_router/package-lock.json is invalid: {exc}")
    lock_dependency = lock.get("packages", {}).get("", {}).get("dependencies", {}).get(
        "@musistudio/claude-code-router"
    )
    if lock_dependency != PINNED_ROUTER_VERSION:
        return fail("provider_router/package-lock.json differs from the pinned router version")
    installer = read_text(installer_path)
    if "ci --prefix $RouterRoot --omit=dev --no-audit --no-fund" not in installer:
        return fail("router installer does not reconstruct dependencies with the committed lockfile")
    if re.search(r"(?im)^\s*&\s*\$Npm\.Source\s+install\b", installer):
        return fail("router installer still uses mutable npm install instead of npm ci")

    menu = read_text(menu_path)
    menu_error = assert_markers(
        menu,
        (
            "DPAPI",
            "local gateway",
            "bin\\claude.exe",
            "Invoke-Ccr",
            "Assert-VerifiedRouterService",
            "Invoke-CcrStartAndVerify",
            "simulated CCR start exit after service activation",
            "ServiceStatePath",
            "Win32_Process",
            '"$GatewayUrl/health"',
            "before any DPAPI client key was read",
            "global-profile-takeover.json",
            'applyProfile = $true',
        ),
        "router_project_menu.ps1",
    )
    if menu_error:
        return fail(menu_error)
    if FORBIDDEN_CLI_INVOCATION.search(menu):
        return fail("router menu invokes a Codex, Claudy, or provider CLI")
    if "0.0.0.0" in launcher or "0.0.0.0" in menu:
        return fail("router launcher/menu exposes a service beyond the required loopback addresses")
    if re.search(r'(?im)^\s*\[void\]\(Invoke-Ccr\s+-Arguments\s+@\("ui"', menu):
        return fail("router menu still launches the CCR agent UI")
    if not re.search(
        r'(?s)function Enforce-SafeCcrConfig\s*\{.*?Set-JsonProperty\s+-Object\s+\$Config\.profile\s+-Name\s+"profiles"\s+-Value\s+@\(\)',
        menu,
    ):
        return fail("safe CCR config does not remove agent profiles before save")
    if re.search(
        r"(?i)(?:installProxyCertificate|certificate\s+install|"
        r"set(?:ting)?\s+(?:a\s+)?system\s+proxy|mitm)",
        launcher + "\n" + menu,
    ):
        return fail("router launcher/menu attempts a system proxy, certificate install, or MITM action")
    ensure_match = re.search(
        r"(?s)function Ensure-Router\s*\{(?P<body>.*?)\n\}", menu
    )
    if not ensure_match:
        return fail("router menu is missing Ensure-Router")
    ensure_body = ensure_match.group("body")
    if re.search(r"if\s*\(Test-LocalPort[^\n]+\)\s*\{\s*return", ensure_body):
        return fail("Ensure-Router still trusts a listening port without process verification")
    start_profile = re.search(
        r"(?s)function Start-Profile\s*\{(?P<body>.*?)\n\}", menu
    )
    if not start_profile:
        return fail("router menu is missing Start-Profile")
    profile_body = start_profile.group("body")
    if profile_body.find("Ensure-Router") > profile_body.find("Read-ProtectedSecret"):
        return fail("Start-Profile reads a DPAPI client key before verifying the router")
    # Local Node may run the reviewed router, Start-Process may open only the
    # loopback management UI, and the account menu may hand off to the separately
    # verified project-local Google wrapper. Provider CLIs remain forbidden above.
    for line in menu.splitlines():
        stripped = line.strip()
        if re.search(r"(?i)(?:^&\s+|\bStart-Process\b)", stripped):
            if stripped in ("& $SafeBinary login", "& $GoogleMenu -Root $RootPath"):
                continue
            if not re.search(
                r"(?i)(?:claude\.exe|bin[\\/]claude\.exe|\$ClaudeBinary|"
                r"\$NodePath|\$ManagementUrl|\$Checker)",
                stripped,
            ):
                return fail(f"router menu has an unapproved process invocation: {stripped}")
    if not re.search(r"(?i)(?:claude\.exe|bin[\\/]claude\.exe)", menu):
        return fail("router menu does not identify the project-local bin/claude.exe")

    tracked_operational = [launcher_path, menu_path, package_path, source_path]
    for path in tracked_operational:
        if KEY_SHAPED.search(read_text(path)):
            return fail(f"key-shaped literal found in tracked file: {path.relative_to(root).as_posix()}")

    node_code, node_version = run_local_version(node_binary, "--version")
    if node_code != 0 or not node_version:
        return fail(f"project-local Node --version failed: {node_version or node_code}")
    try:
        installed_version = json.loads(read_text(router_package)).get("version")
    except (OSError, json.JSONDecodeError) as exc:
        return fail(f"installed router package metadata is invalid: {exc}")
    if installed_version != PINNED_ROUTER_VERSION:
        return fail(
            f"installed router package is {installed_version!r}, expected {PINNED_ROUTER_VERSION}"
        )

    print("PASS: project-local Claude Code Router integration is complete")
    print(f"root: {root}")
    print(f"claude: {claude_binary.stat().st_size} bytes")
    print(f"node: {node_version}")
    print(f"router package: {installed_version}")
    print("secrets/config: ignored runtime and configuration contents were not read")
    print("network: not used; only local Node --version was run")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
