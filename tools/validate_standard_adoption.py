#!/usr/bin/env python3
"""Validate a Project Standard 1.2.2 adoption without Vault access."""

from __future__ import annotations

import argparse
import json
import re
from datetime import date
from pathlib import Path
from typing import Any

SHA_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
DRIVE_RE = re.compile(r"^[A-Za-z]:[\\/]")


class AdoptionError(ValueError):
    pass


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AdoptionError(f"cannot read adoption JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise AdoptionError("adoption JSON root must be an object")
    return value


def frontmatter(path: Path) -> dict[str, str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "---":
        raise AdoptionError("adoption Markdown lacks frontmatter")
    result: dict[str, str] = {}
    for line in lines[1:]:
        if line == "---":
            break
        if ":" not in line:
            raise AdoptionError("invalid adoption Markdown frontmatter")
        key, value = line.split(":", 1)
        value = value.strip()
        if value.startswith('"') and value.endswith('"'):
            value = json.loads(value)
        result[key.strip()] = value
    return result


def validate(root: Path) -> dict[str, Any]:
    root = root.resolve()
    receipt = read_json(root / "00-Governance" / "STANDARD_ADOPTION.json")
    if set(receipt) != {
        "schema_version", "type", "standard", "vault", "adopted_at",
        "routine_continuation_requires_vault", "bootstrap"
    }:
        raise AdoptionError("adoption receipt keys are not exact")
    if receipt["schema_version"] != 1 or receipt["type"] != "project_standard_adoption":
        raise AdoptionError("adoption identity is invalid")
    standard, vault = receipt["standard"], receipt["vault"]
    if not isinstance(standard, dict) or set(standard) != {
        "version", "subpath", "entry_sha256", "manifest_sha256",
        "files_digest_sha256"
    }:
        raise AdoptionError("standard identity is invalid")
    if standard["version"] != "1.2.2":
        raise AdoptionError("standard version must be 1.2.2")
    if standard["subpath"] != "20-First-Party/project-standard":
        raise AdoptionError("standard subpath is invalid")
    for key in ("entry_sha256", "manifest_sha256", "files_digest_sha256"):
        if not isinstance(standard[key], str) or not SHA_RE.fullmatch(standard[key]):
            raise AdoptionError(f"{key} is invalid")
    if not isinstance(vault, dict) or set(vault) != {"version", "commit", "remote"}:
        raise AdoptionError("Vault identity is invalid")
    if not isinstance(vault["version"], str) or not vault["version"].strip():
        raise AdoptionError("Vault version is empty")
    if not isinstance(vault["commit"], str) or not COMMIT_RE.fullmatch(vault["commit"]):
        raise AdoptionError("Vault commit is invalid")
    if (not isinstance(vault["remote"], str) or not vault["remote"].strip()
            or DRIVE_RE.match(vault["remote"])
            or vault["remote"].startswith(("/", "\\"))):
        raise AdoptionError("Vault remote is invalid or machine-local")
    try:
        date.fromisoformat(receipt["adopted_at"])
    except (TypeError, ValueError) as exc:
        raise AdoptionError("adopted_at must be an ISO date") from exc
    if receipt["routine_continuation_requires_vault"] is not False:
        raise AdoptionError("routine continuation must not require Vault")
    if receipt["bootstrap"] != {
        "tool": "standard_package.py bootstrap",
        "copy_policy": "blank-destination-no-overwrite",
        "source_validation": "passed-before-copy",
    }:
        raise AdoptionError("bootstrap receipt is invalid")
    required = {
        "START_HERE.md", "AGENTS.md", "gates/gates.json",
        "tools/run_gates.py", "tools/audit_project_memory.py",
        "tools/validate_standard_adoption.py",
        "00-Governance/STANDARD_ADOPTION.md",
    }
    missing = sorted(item for item in required if not (root / item).is_file())
    if missing:
        raise AdoptionError(f"required local files missing: {', '.join(missing)}")
    expected = {
        "standard_version": standard["version"],
        "vault_version": vault["version"],
        "vault_commit": vault["commit"],
        "vault_remote": vault["remote"],
        "source_path_at_adoption": standard["subpath"],
        "standard_entry_sha256": standard["entry_sha256"],
        "standard_manifest_sha256": standard["manifest_sha256"],
        "adopted_at": receipt["adopted_at"],
        "status": "adopted",
        "routine_continuation_requires_vault": "false",
    }
    if frontmatter(root / "00-Governance" / "STANDARD_ADOPTION.md") != expected:
        raise AdoptionError("Markdown and JSON adoption receipts disagree")
    return {
        "status": "PASS",
        "standard_version": "1.2.2",
        "manifest_sha256": standard["manifest_sha256"],
        "routine_continuation_requires_vault": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project_root", nargs="?", type=Path, default=Path("."))
    args = parser.parse_args()
    try:
        print(json.dumps(validate(args.project_root), sort_keys=True))
        return 0
    except (AdoptionError, OSError) as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, sort_keys=True))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
