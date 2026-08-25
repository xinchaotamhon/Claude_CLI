#!/usr/bin/env python3
"""Verify the blocked EasyCLIProxyAPI dashboard source intake offline."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise AssertionError(message)


def run_git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        timeout=15,
    )
    if result.returncode:
        fail(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def child(root: Path, relative: str) -> Path:
    path = (root / relative).resolve()
    path.relative_to(root)
    return path


def verify(root: Path) -> None:
    metadata = json.loads(
        (root / "router_challenger" / "DASHBOARD_SOURCE.json").read_text(
            encoding="utf-8"
        )
    )
    if metadata.get("schema_version") != 1:
        fail("dashboard source schema must be 1")
    if metadata.get("status") != "source-audited-blocked-no-license-and-isolation-patch-required":
        fail("dashboard candidate must remain blocked")
    if metadata.get("license") != "none-found-in-tag-tree":
        fail("dashboard license observation changed")
    risks = metadata.get("observed_risks")
    if not isinstance(risks, dict) or risks.get("license_grant_present") is not False:
        fail("missing license blocker")
    if not all(risks.get(name) is True for name in (
        "automatic_app_and_core_download_update_paths",
        "external_agent_discovery_and_configuration_paths",
        "windows_tray_and_autostart_paths",
        "auth_file_upload_download_and_inspection",
        "quota_ui_and_provider_calls",
    )):
        fail("dashboard isolation risks must remain explicit")
    expected_policy = {
        "checkout_is_ignored_nested_repository": True,
        "runtime_was_built_or_run": False,
        "oauth_was_run": False,
        "provider_request_was_run": False,
        "source_may_be_inspected_not_copied_or_distributed": True,
        "normal_launcher_changed": False,
    }
    if metadata.get("policy") != expected_policy:
        fail("dashboard source policy changed")

    checkout = child(root, str(metadata["local_checkout"]))
    ignored = subprocess.run(
        ["git", "-C", str(root), "check-ignore", "-q", "--", checkout.name],
        check=False,
        timeout=10,
    )
    if ignored.returncode:
        fail("dashboard source checkout must be ignored by parent Git")
    if not checkout.exists():
        print("PASS: blocked dashboard metadata is valid; optional checkout absent")
        return
    if run_git(checkout, "status", "--porcelain"):
        fail("dashboard source checkout is dirty")
    if run_git(checkout, "rev-parse", "HEAD") != metadata["source_commit"]:
        fail("dashboard source commit mismatch")
    if run_git(checkout, "rev-parse", "HEAD^{tree}") != metadata["source_tree"]:
        fail("dashboard source tree mismatch")
    if run_git(checkout, "branch", "--show-current") != metadata["local_branch"]:
        fail("dashboard source must remain on local claude branch")
    if metadata["source_tag"] not in run_git(checkout, "tag", "--points-at", "HEAD").splitlines():
        fail("dashboard source tag mismatch")
    if run_git(checkout, "remote").splitlines() != [metadata["remote_name"]]:
        fail("dashboard source must have only upstream remote")
    if run_git(checkout, "remote", "get-url", metadata["remote_name"]) != metadata["source_url"]:
        fail("dashboard upstream URL mismatch")
    license_names = {"license", "license.md", "license.txt", "copying", "copying.txt"}
    tracked = {name.lower() for name in run_git(checkout, "ls-tree", "-r", "--name-only", "HEAD").splitlines()}
    if tracked.intersection(license_names):
        fail("a root license file now exists; re-audit before changing blocked status")
    for relative, expected in metadata["anchor_sha256"].items():
        path = child(checkout, relative)
        if not path.is_file() or sha256(path) != expected:
            fail(f"dashboard source anchor mismatch: {relative}")
    print("PASS: EasyCLIProxyAPI v0.2.61 source is pinned, unrun and blocked by license/isolation")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    try:
        verify(root)
        return 0
    except (AssertionError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
