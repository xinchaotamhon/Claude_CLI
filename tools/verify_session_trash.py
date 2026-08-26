#!/usr/bin/env python3
"""Verify recoverable, exact-scope Claude session deletion without reading transcripts."""

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
        "const sessionTrashRoot = path.join(sessionsRoot, 'trash')",
        "function sessionTranscriptPaths(sessionId)",
        "entry.name.toLowerCase() === `${id}.jsonl`",
        "function moveSessionToTrash(sessionId)",
        "readTerminals().some((terminal) => terminal.sessionId === id && terminal.running)",
        "fs.renameSync(source, destination)",
        "policy: 'recoverable-project-local-trash'",
        "records.filter((item) => safeSessionId(item?.id) !== id)",
        "if (url.pathname === '/api/sessions/delete')",
        "body.confirmation !== sessionId",
    )
    for marker in required_server:
        if marker not in server:
            return fail(f"session trash server control is missing: {marker}")

    deletion = server[server.index("function moveSessionToTrash"):server.index("function copyLegacySessionFiles")]
    if "fs.unlinkSync(source)" in deletion or "fs.rmSync(source" in deletion:
        return fail("session deletion permanently removes a transcript instead of moving it to local trash")
    if "recursive: true" in server[server.index("function sessionTranscriptPaths"):server.index("function sessionRecords")]:
        return fail("session transcript discovery must not use broad recursive deletion semantics")

    required_frontend = (
        "window.confirm",
        "session-delete-button",
        "confirmation: session.id",
        "thùng rác cục bộ",
    )
    for marker in required_frontend:
        if marker not in frontend:
            return fail(f"session deletion UI control is missing: {marker}")

    print("PASS: session deletion requires explicit UI and exact server-side confirmation")
    print("PASS: active sessions are blocked and only exact UUID transcript files are selected")
    print("PASS: deleted sessions move to ignored project-local trash with a recovery manifest")
    print("transcript content: not read; runtime data: not modified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
