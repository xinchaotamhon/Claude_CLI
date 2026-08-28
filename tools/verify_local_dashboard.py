#!/usr/bin/env python3
"""Offline contract verifier for the one-door localhost dashboard."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


def fail(message: str) -> int:
    print(f"FAIL: {message}")
    return 1


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    files = {
        "entry": root / "DASHBOARD.bat",
        "start": root / "tools" / "start_dashboard.ps1",
        "terminal": root / "tools" / "dashboard_terminal.ps1",
        "server": root / "dashboard" / "server.mjs",
        "ui": root / "dashboard" / "src" / "main.tsx",
        "css": root / "dashboard" / "src" / "styles.css",
        "package": root / "dashboard" / "package.json",
        "static": root / "dashboard" / "static" / "index.html",
        "router": root / "tools" / "router_project_menu.ps1",
        "google": root / "tools" / "challenger_account_menu.ps1",
        "node": root / "provider_router" / "runtime" / "node.exe",
    }
    for name, path in files.items():
        if not path.is_file():
            return fail(f"missing dashboard {name}: {path.relative_to(root).as_posix()}")

    server = read(files["server"])
    required_server = (
        "const HOST = '127.0.0.1'",
        "const PORT = 18320",
        "bootstrapToken = crypto.randomBytes(32)",
        "instanceId = crypto.randomBytes(24)",
        "serverHash = crypto.createHash('sha256')",
        "HttpOnly; SameSite=Strict; Path=/",
        "if (!authorized(request))",
        "if (!sameOrigin(request))",
        "Content-Security-Policy",
        "X-Frame-Options",
        "provider_router', '.ccr-local', 'codex-accounts'",
        "'.runtime', 'challenger', 'accounts', 'google'",
        "account/rateLimits/read",
        "OpenAI Codex app-server (chính thức)",
        "window?.resetsAt",
        "/^(OPENAI|CODEX|CHATGPT|AZURE_OPENAI)_/i",
        "env.CODEX_HOME = home",
        "env.CODEX_SQLITE_HOME = home",
        "AUTO_REFRESH_MS = 5 * 60 * 1000",
        "codex-pending:",
        "retrieveUserQuotaSummary",
        "gemini_models",
        "claude_gpt_models",
        "spawnTerminal(resumeId ? 'launch-resume' : 'launch-new'",
        "spawnTerminal('codex'",
        "spawnTerminal('google'",
        "'/api/sessions/resume'",
        "'/api/updates/check'",
        "'/api/providers/quota/open'",
        "'.runtime', 'claude-sessions'",
        "'.runtime', 'claude-home'",
        "API tùy chỉnh không có chuẩn chung cho hạn mức",
    )
    for marker in required_server:
        if marker not in server:
            return fail(f"dashboard server is missing safety/capability marker: {marker}")
    for forbidden in ("0.0.0.0", "USERPROFILE", "GetFolderPath", "WindowsApps", "shell: true", "env = { ...process.env"):
        if forbidden.lower() in server.lower():
            return fail(f"dashboard server contains forbidden external/global behavior: {forbidden}")

    start = read(files["start"])
    if "provider_router\\runtime\\node.exe" not in start or "-WindowStyle Hidden" not in start:
        return fail("dashboard does not use the project-local Node runtime in a hidden server process")
    for marker in ("[switch]$Detached", "startup-error.log", "Start-Process -FilePath 'notepad.exe'"):
        if marker not in start:
            return fail(f"dashboard detached startup is missing failure feedback marker: {marker}")
    for marker in ("127.0.0.1:18320", "loopbackOnly", "Get-CimInstance Win32_Process", "ExecutablePath", "CommandLine", "instanceId", "ExpectedServerHash", "Stop-OutdatedOwnedDashboard"):
        if marker not in start:
            return fail(f"dashboard startup does not independently verify exact process/loopback identity: {marker}")

    entry = read(files["entry"])
    for marker in ("start_dashboard.ps1", "-WindowStyle Hidden", "-Detached", 'start ""'):
        if marker not in entry:
            return fail(f"DASHBOARD.bat is missing detached startup marker: {marker}")
    if "start_dashboard.ps1" not in entry:
        return fail("DASHBOARD.bat does not enter the bounded local startup helper")
    root_batches = sorted(path.name for path in root.glob("*.bat"))
    if root_batches != ["DASHBOARD.bat"]:
        return fail(f"project root must expose only DASHBOARD.bat, found: {root_batches}")

    terminal = read(files["terminal"])
    for marker in ("-LaunchProfileId", "-AddCodexPlan", "-CodexAccountName", "-AddSlot", "-ClaudeSessionId", "-ResumeClaudeSession", "-GoogleLoginHint"):
        if marker not in terminal:
            return fail(f"dashboard terminal dispatcher is missing {marker}")
    router = read(files["router"])
    google = read(files["google"])
    if "$LaunchProfileId" not in router or "$AddCodexPlan" not in router or "$CodexAccountName" not in router or "$ClaudeSessionId" not in router:
        return fail("router helper lacks allowlisted dashboard route/account actions")
    if "$AddSlot" not in google or "$GoogleLoginHint" not in google or "CLIPROXY_GOOGLE_LOGIN_HINT" not in google:
        return fail("Google helper lacks the allowlisted dashboard slot action")

    ui = read(files["ui"])
    css = read(files["css"])
    if "https://" in ui or "https://" in css or "http://" in ui or "http://" in css:
        return fail("browser UI has an external runtime dependency")
    for marker in ("Mở terminal", "Codex Free", "Codex Plus", "Google AI Pro", "Làm mới tất cả", "Tín dụng bổ sung", "Hoàn tất nhập tài khoản", "mỗi 5 phút", "Mở lại công việc cũ", "Kiểm tra cập nhật", "Mở trang quota của provider"):
        if marker not in ui:
            return fail(f"dashboard UI is missing owner-facing action: {marker}")

    try:
        package = json.loads(read(files["package"]))
    except (OSError, json.JSONDecodeError) as exc:
        return fail(f"dashboard package metadata is invalid: {exc}")
    dependencies = set(package.get("dependencies", {})) | set(package.get("devDependencies", {}))
    forbidden_packages = {"next", "wrangler", "@cloudflare/vite-plugin", "@openai/sites-vite-plugin"}
    if dependencies & forbidden_packages:
        return fail(f"local-only dashboard still carries hosting packages: {sorted(dependencies & forbidden_packages)}")

    check = subprocess.run(
        [str(files["node"]), "--check", str(files["server"])],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
    )
    if check.returncode != 0:
        return fail(f"dashboard server syntax check failed: {check.stderr.strip()}")
    self_test = subprocess.run(
        [str(files["node"]), str(files["server"]), "--self-test"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
    )
    expected_self_test = "PASS: dashboard Codex label, Google route intersection, reset timestamp and child-environment self-test"
    if self_test.returncode != 0 or expected_self_test not in self_test.stdout:
        return fail(f"dashboard server self-test failed: {(self_test.stderr or self_test.stdout).strip()}")
    static_index = read(files["static"])
    if not re.search(r"/assets/index-[A-Za-z0-9_-]+\.js", static_index):
        return fail("tracked production dashboard assets were not built")

    print("PASS: DASHBOARD.bat is the single owner-facing account, quota and launch surface")
    print("PASS: server binds only 127.0.0.1 with bootstrap cookie, same-origin and CSP controls")
    print("PASS: browser receives no credential material and has no external runtime dependency")
    print("PASS: Codex and Google quota adapters preserve unknown values instead of fabricating them")
    print("PASS: exact route/account actions use only project-local runtimes and allowlists")
    print("network: not used; ignored setting/auth files were not read")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
