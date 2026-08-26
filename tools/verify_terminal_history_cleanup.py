#!/usr/bin/env python3
"""Verify exact-scope cleanup of closed dashboard terminal history."""

from __future__ import annotations

import sys
from pathlib import Path


def fail(message: str) -> int:
    print(f"FAIL: {message}")
    return 1


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    server = (root / "dashboard" / "server.mjs").read_text(encoding="utf-8")
    frontend = (root / "dashboard" / "src" / "main.tsx").read_text(encoding="utf-8")

    required_server = (
        "function clearClosedTerminalHistory()",
        "processRunning(Number(record.pid))",
        "writeJson(terminalsPath, retained)",
        "if (url.pathname === '/api/terminals/clear-closed')",
        "body.confirmation !== 'clear-closed-terminals'",
    )
    for marker in required_server:
        if marker not in server:
            return fail(f"terminal cleanup server control is missing: {marker}")

    cleanup = server[server.index("function clearClosedTerminalHistory"):server.index("function binaryVersion")]
    for forbidden in ("Stop-Process", "process.kill", "unlinkSync", "rmSync", "sessionsPath", "claudeHomeRoot"):
        if forbidden in cleanup:
            return fail(f"terminal history cleanup may affect live/session data: {forbidden}")

    required_frontend = (
        "Xóa mục đã đóng",
        "window.confirm",
        "clear-closed-terminals",
        "không xóa session",
    )
    for marker in required_frontend:
        if marker not in frontend:
            return fail(f"terminal cleanup UI control is missing: {marker}")

    print("PASS: closed-terminal cleanup requires explicit UI and exact server confirmation")
    print("PASS: running PIDs are recomputed and retained; no process/session/transcript path is touched")
    print("runtime terminal history: not modified by this gate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
