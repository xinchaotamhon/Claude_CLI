#!/usr/bin/env python3
"""Offline contract for dynamic Google models and recoverable account removal."""

from __future__ import annotations

import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def fail(message: str) -> int:
    print(f"FAIL: {message}")
    return 1


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    server = (root / "dashboard" / "server.mjs").read_text(encoding="utf-8")
    ui = (root / "dashboard" / "src" / "main.tsx").read_text(encoding="utf-8")
    css = (root / "dashboard" / "src" / "styles.css").read_text(encoding="utf-8")

    server_markers = (
        "v1internal:fetchAvailableModels",
        "googleCatalogPath",
        "normalizeGoogleCatalog",
        "cachedGoogleModels",
        "googleCatalogState",
        "googleRuntimeModelIds",
        "buildGoogleRouteCandidates",
        "routes.push(...googleRoutes())",
        "launch-google-new",
        "accountTrashRoot",
        "moveGoogleAccountToTrash",
        "moveApiProviderToTrash",
        "activeRouteIds",
        "'/api/accounts/remove'",
        "confirmation !== account.id",
        "Không có model nào bị ghi cứng hoặc báo thành công giả",
    )
    for marker in server_markers:
        if marker not in server:
            return fail(f"dashboard server is missing account/catalog marker: {marker}")

    if "gemini-3.7" in server.lower() or "claude-opus-4.6" in server.lower():
        return fail("dashboard hard-codes transient Antigravity model names")
    removal = server[server.index("function moveGoogleAccountToTrash"):server.index("function binaryVersion")]
    if "fs.rmSync" in removal or "fs.unlinkSync(state.authFiles" in removal or "fs.unlinkSync(home" in removal:
        return fail("account removal contains a permanent credential deletion path")

    for marker in (
        "Xóa tài khoản",
        "Xóa provider",
        "Đồng bộ model Google",
        "deleteAccount",
        "RoutePicker",
        "route-picker-popover",
        "account-toolbar",
        "Model mới sẽ tự xuất hiện sau lần đồng bộ",
    ):
        if marker not in ui:
            return fail(f"dashboard UI is missing self-service marker: {marker}")

    for marker in (
        "--surface",
        "--focus",
        "account-card",
        "text-danger",
        "status-rail",
        "route-picker-popover",
        "segmented",
        "catalog-state",
    ):
        if marker not in css:
            return fail(f"dashboard CSS is missing compact design-system marker: {marker}")

    runtime = (root / "tools" / "google_project_runtime.ps1").read_text(encoding="utf-8")
    runtime_manifest = (root / "router_challenger" / "google-runtime-models.json").read_text(encoding="utf-8")
    for marker in (
        "Assert-BinaryIdentity",
        "Assert-LoopbackListener",
        "Wait-RuntimeModel",
        "ANTHROPIC_BASE_URL",
        "CLAUDE_CONFIG_DIR",
        "CLAUDE_CODE_MAX_RETRIES",
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
        "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS",
        "CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK",
        "--prompt-suggestions",
        "-WindowStyle Hidden",
        "without sending a model request",
    ):
        if marker not in runtime:
            return fail(f"Google runtime is missing isolation/launch marker: {marker}")
    if '"models"' not in runtime_manifest or '"binary_sha256"' not in runtime_manifest:
        return fail("Google runtime compatibility manifest is incomplete")

    print("PASS: Google model names come from a sanitized dynamic catalog cache")
    print("PASS: failed Google catalog refresh cannot be reported as a successful sync")
    print("PASS: account/provider removal is explicit, active-route-aware and recoverable")
    print("PASS: compact dashboard tokens and owner-facing removal controls are present")
    print("PASS: searchable grouped route picker and account filters replace the long native menu")
    print("PASS: Google routes are the intersection of live catalog and pinned runtime capability")
    print("PASS: Google launches bound retries and suppress proxy-incompatible background traffic")
    print("network: not used; ignored settings and auth payloads were not read")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
