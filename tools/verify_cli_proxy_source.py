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
    if metadata.get("status") != "phase-6-v7.2.144-upgrade-built":
        fail("source status must identify the reviewed v7.2.144 Phase 6 build")
    if metadata.get("source_url") != EXPECTED_URL:
        fail("unexpected source URL")
    if not HEX40.fullmatch(str(metadata.get("source_commit", ""))):
        fail("invalid source commit")
    if not HEX40.fullmatch(str(metadata.get("source_tree", ""))):
        fail("invalid source tree")
    if not HEX40.fullmatch(str(metadata.get("patched_commit", ""))):
        fail("invalid patched commit")
    if not HEX40.fullmatch(str(metadata.get("patched_tree", ""))):
        fail("invalid patched tree")
    patches = metadata.get("patches")
    if not isinstance(patches, list) or len(patches) != 4:
        fail("exactly four reviewed challenger patches are required")
    if metadata.get("local_branch") != "claude":
        fail("candidate branch must be claude")
    if metadata.get("remote_name") != "upstream":
        fail("candidate remote must be named upstream")
    if metadata.get("license") != "MIT":
        fail("unexpected license")
    if metadata.get("required_go_version") != "1.26.0":
        fail("unexpected Go version pin")
    if metadata.get("build_go_version") != "1.26.7":
        fail("unexpected build Go version pin")

    policy = metadata.get("policy")
    if not isinstance(policy, dict):
        fail("missing source policy")
    expected_policy = {
        "checkout_is_ignored_nested_repository": True,
        "runtime_is_active": True,
        "offline_binary_was_built": True,
        "oauth_was_run": False,
        "provider_request_was_run": False,
        "normal_launcher_changed": False,
        "local_model_suppresses_remote_catalog_and_antigravity_updates": True,
        "offline_fixture_only": False,
        "oauth_callback_loopback_only": True,
        "google_account_chooser_and_login_hint": True,
        "google_redirect_matches_ipv4_listener": True,
    }
    if policy != expected_policy:
        fail("reviewed source policy changed unexpectedly")

    anchors = metadata.get("anchor_sha256")
    if not isinstance(anchors, dict) or not anchors:
        fail("missing source anchor hashes")
    for name, digest in anchors.items():
        if not isinstance(name, str) or not name or not HEX64.fullmatch(str(digest)):
            fail("invalid source anchor hash")

    checkout = ensure_child(root, str(metadata.get("local_checkout", "")))
    for index, patch in enumerate(patches):
        if not isinstance(patch, dict):
            fail(f"patch {index} is not an object")
        if not HEX40.fullmatch(str(patch.get("commit", ""))):
            fail(f"patch {index} has an invalid commit")
        if not HEX64.fullmatch(str(patch.get("sha256", ""))):
            fail(f"patch {index} has an invalid hash")
        patch_path = ensure_child(root, str(patch.get("file", "")))
        if not patch_path.is_file() or sha256(patch_path) != patch["sha256"]:
            fail(f"tracked challenger patch {index} is missing or mismatched")
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
    if run_git(checkout, "rev-parse", "HEAD^{tree}") != metadata["patched_tree"]:
        fail("candidate tree differs from the pinned patched tree")
    if run_git(checkout, "rev-parse", "HEAD") != metadata["patched_commit"]:
        fail("candidate HEAD differs from the pinned patched commit")
    patches = metadata["patches"]
    assert isinstance(patches, list)
    if run_git(checkout, "rev-list", "--count", f"{metadata['source_commit']}..HEAD") != str(len(patches)):
        fail("candidate does not contain exactly the reviewed patch series")
    observed_commits = run_git(checkout, "rev-list", "--reverse", f"{metadata['source_commit']}..HEAD").splitlines()
    expected_commits = [str(patch["commit"]) for patch in patches]
    if observed_commits != expected_commits:
        fail("candidate patch commit order differs from SOURCE.json")
    if run_git(checkout, "rev-list", "--merges", f"{metadata['source_commit']}..HEAD"):
        fail("candidate patch series must not contain merge commits")
    if run_git(checkout, "branch", "--show-current") != metadata["local_branch"]:
        fail("candidate is not on the local claude branch")
    if metadata["source_tag"] not in run_git(
        checkout, "tag", "--points-at", str(metadata["source_commit"])
    ).splitlines():
        fail("pinned tag does not point at candidate HEAD")
    remotes = run_git(checkout, "remote").splitlines()
    if remotes != [metadata["remote_name"]]:
        fail("candidate must have only the pinned upstream remote")
    if run_git(checkout, "remote", "get-url", metadata["remote_name"]) != EXPECTED_URL:
        fail("candidate upstream URL differs from metadata")

    antigravity_auth = (checkout / "sdk" / "auth" / "antigravity.go").read_text(encoding="utf-8")
    if 'fmt.Sprintf("http://127.0.0.1:%d/oauth-callback", port)' not in antigravity_auth:
        fail("Antigravity redirect URI must use the same IPv4 loopback address as its callback listener")

    anchors = metadata["anchor_sha256"]
    assert isinstance(anchors, dict)
    for relative, expected in anchors.items():
        path = ensure_child(checkout, str(relative))
        if not path.is_file() or sha256(path) != expected:
            fail(f"source anchor mismatch: {relative}")
    print(
        "PASS: CLIProxyAPI source is clean and pinned to audited upstream "
        f"{metadata['source_tag']} plus patched tree {metadata['patched_tree']}"
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
