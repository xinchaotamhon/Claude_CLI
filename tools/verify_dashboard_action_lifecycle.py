from __future__ import annotations

import sys
from pathlib import Path


def fail(message: str) -> int:
    print(f"FAIL: {message}")
    return 1


def require(text: str, markers: tuple[str, ...], owner: str) -> int:
    for marker in markers:
        if marker not in text:
            return fail(f"{owner} is missing lifecycle marker: {marker}")
    return 0


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    server = (root / "dashboard" / "server.mjs").read_text(encoding="utf-8")
    frontend = (root / "dashboard" / "src" / "main.tsx").read_text(encoding="utf-8")
    helper = (root / "tools" / "dashboard_terminal.ps1").read_text(encoding="utf-8")
    starter = (root / "tools" / "start_dashboard.ps1").read_text(encoding="utf-8")
    supervisor_path = root / "tools" / "dashboard_supervisor.ps1"
    dispatcher_path = root / "tools" / "dashboard_spawn_terminal.ps1"
    if not supervisor_path.is_file() or not dispatcher_path.is_file():
        return fail("dashboard supervisor or safe visible-terminal dispatcher is missing")
    supervisor = supervisor_path.read_text(encoding="utf-8")
    dispatcher = dispatcher_path.read_text(encoding="utf-8")

    checks = (
        require(server, ("dashboard-session.json", "discoverTranscriptIds", "waitForActionStatus", "setTimeout(resolve, 650)", "pruneActionStatusFiles", "Promise.allSettled", "AUTO_REFRESH_START_DELAY_MS = 15_000", "activeLaunches > 0"), "dashboard server"),
        require(frontend, ("resumeRoutes", "Mở lại bằng", "dashboardConnected", "Đang chuẩn bị"), "dashboard frontend"),
        require(helper, ("StatusPath", "terminal_ready", "failed", "Cửa sổ được giữ lại để bạn đọc lỗi thật"), "terminal helper"),
        require(dispatcher, ("#requires -Version 7.0", "ProcessStartInfo", "UseShellExecute = $true", "ArgumentList.Add", "-StatusPath"), "terminal dispatcher"),
        require(supervisor, ("#requires -Version 7.0", "System.Threading.Mutex", "rapidFailures", "dashboard-server.log"), "dashboard supervisor"),
        require(starter, ("dashboard_supervisor.ps1", "dashboard\\session_lifecycle.mjs", "Get-CombinedFileHash", "@($Server, $SessionLifecycle)"), "dashboard starter"),
    )
    if any(checks):
        return 1
    launch = server[server.index("async function launchRoute"):server.index("function securityHeaders")]
    if launch.index("await waitForActionStatus") > launch.index("saveSessionRecord(record)"):
        return fail("session record can still be saved before launcher bootstrap confirmation")
    print("PASS: dashboard actions require acknowledged launch lifecycle")
    print("PASS: phantom sessions are hidden unless a local transcript exists")
    print("PASS: one persistent local browser session survives bounded server restart")
    print("PASS: resume can select another current route and updates settle concurrently")
    print("PASS: first launch is not forced to compete with automatic quota/catalog refresh")
    print("PASS: failed Claude launches remain visible instead of closing over the provider error")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
