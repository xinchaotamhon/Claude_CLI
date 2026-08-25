#!/usr/bin/env python3
"""Verify the pinned CLIProxyAPI source intake without network or credentials."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_URL = "https://github.com/router-for-me/CLIProxyAPI.git"


def fail(message: str) -> None:
    raise AssertionError(message)


def run_git(repo: Path, *args: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=15,
    )
    if completed.returncode != 0:
        fail(
            f"git {' '.join(args)} failed ({completed.returncode}): "
            f"{completed.stderr.strip()}"
        )
    return completed.stdout.strip()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ensure_child(root: Path, relative: str) -> Path:
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise AssertionError("local checkout escapes project root") from exc
    return candidate


def verify_metadata(root: Path) -> tuple[dict[str, object], Path]:
    metadata_path = root / "router_challenger" / "SOURCE.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if metadata.get("schema_version") != 1:
        fail("SOURCE schema_version must be 1")
    if metadata.get("component") != "CLIProxyAPI":
        fail("unexpected source component")
    if metadata.get("status") != "phase-0-source-audited-not-adopted":
        fail("source status must remain non-adopted during Phase 0")
    if metadata.get("source_url") != EXPECTED_URL:
        fail("unexpected source URL")
    if not HEX40.fullmatch(str(metadata.get("source_commit", ""))):
        fail("invalid source commit")
    if not HEX40.fullmatch(str(metadata.get("source_tree", ""))):
        fail("invalid source tree")
    if metadata.get("local_branch") != "claude":
        fail("candidate branch must be claude")
    if metadata.get("remote_name") != "upstream":
        fail("candidate remote must be named upstream")
    if metadata.get("license") != "MIT":
        fail("unexpected license")
    if metadata.get("required_go_version") != "1.26.0":
        fail("unexpected Go version pin")

    policy = metadata.get("policy")
    if not isinstance(policy, dict):
        fail("missing source policy")
    expected_policy = {
        "checkout_is_ignored_nested_repository": True,
        "runtime_is_active": False,
        "oauth_was_run": False,
        "provider_request_was_run": False,
        "normal_launcher_changed": False,
    }
    if policy != expected_policy:
        fail("Phase 0 source policy changed unexpectedly")

    anchors = metadata.get("anchor_sha256")
    if not isinstance(anchors, dict) or not anchors:
        fail("missing source anchor hashes")
    for name, digest in anchors.items():
        if not isinstance(name, str) or not name or not HEX64.fullmatch(str(digest)):
            fail("invalid source anchor hash")

    checkout = ensure_child(root, str(metadata.get("local_checkout", "")))
    ignored = subprocess.run(
        ["git", "-C", str(root), "check-ignore", "-q", "--", checkout.name],
        check=False,
        timeout=10,
    )
    if ignored.returncode != 0:
        fail("candidate checkout must remain ignored by parent Git")
    return metadata, checkout


def verify_checkout(metadata: dict[str, object], checkout: Path) -> None:
    if not checkout.exists():
        print("PASS: pinned metadata valid; optional ignored checkout is absent")
        return
    if not checkout.is_dir():
        fail("candidate checkout path is not a directory")
    if Path(run_git(checkout, "rev-parse", "--show-toplevel")).resolve() != checkout:
        fail("candidate is not an independent nested repository")
    if run_git(checkout, "status", "--porcelain"):
        fail("candidate source checkout is dirty")
    if run_git(checkout, "rev-parse", "HEAD") != metadata["source_commit"]:
        fail("candidate HEAD differs from pinned commit")
    if run_git(checkout, "rev-parse", "HEAD^{tree}") != metadata["source_tree"]:
        fail("candidate tree differs from pinned tree")
    if run_git(checkout, "branch", "--show-current") != metadata["local_branch"]:
        fail("candidate is not on the local claude branch")
    if metadata["source_tag"] not in run_git(
        checkout, "tag", "--points-at", "HEAD"
    ).splitlines():
        fail("pinned tag does not point at candidate HEAD")
    remotes = run_git(checkout, "remote").splitlines()
    if remotes != [metadata["remote_name"]]:
        fail("candidate must have only the upstream remote during Phase 0")
    if run_git(checkout, "remote", "get-url", metadata["remote_name"]) != EXPECTED_URL:
        fail("candidate upstream URL differs from metadata")

    anchors = metadata["anchor_sha256"]
    assert isinstance(anchors, dict)
    for relative, expected in anchors.items():
        path = ensure_child(checkout, str(relative))
        if not path.is_file() or sha256(path) != expected:
            fail(f"source anchor mismatch: {relative}")
    print(
        "PASS: CLIProxyAPI source is clean, independently pinned and unexecuted "
        f"at {metadata['source_tag']} ({metadata['source_commit']})"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path("."))
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        metadata, checkout = verify_metadata(root)
        verify_checkout(metadata, checkout)
        return 0
    except (AssertionError, OSError, json.JSONDecodeError, subprocess.SubprocessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
