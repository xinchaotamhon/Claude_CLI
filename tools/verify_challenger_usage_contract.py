#!/usr/bin/env python3
"""Offline validator for challenger provider usage snapshots.

The contract deliberately stores observations, not credentials or provider
sessions.  A Google AI Pro snapshot has two independent usage groups:
``gemini_models`` and ``claude_gpt_models``.  Each group must report a weekly
window; a five-hour window is optional.  Other providers may add their own
groups without changing this validator.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


EXIT_OK = 0
EXIT_USAGE = 2
EXIT_IO_OR_JSON = 3
EXIT_CONTRACT = 4

ALLOWED_ROOT_KEYS = {
    "schema_version",
    "provider",
    "account_label",
    "observed_at",
    "usage_groups",
    "extensions",
}
ALLOWED_PROVIDER_KEYS = {"id", "kind", "display_name"}
ALLOWED_WINDOW_KEYS = {
    "status",
    "remaining_percent",
    "reset_at",
    "reason",
}
ALLOWED_GROUP_KEYS = {"weekly", "five_hour", "extensions"}
WINDOW_STATUSES = {"available", "unknown", "unavailable"}
SECRET_KEY_PARTS = {
    "api_key",
    "apikey",
    "authorization",
    "access_token",
    "auth_token",
    "client_key",
    "cookie",
    "credential",
    "password",
    "secret",
    "token",
}
NORMALIZED_SECRET_KEY_PARTS = {
    re.sub(r"[^a-z0-9]", "", part) for part in SECRET_KEY_PARTS
}
IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
UTC_TIMESTAMP_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$"
)


class ContractError(ValueError):
    """Raised when a decoded document violates the usage contract."""


def _fail(message: str) -> None:
    raise ContractError(message)


def _check_mapping(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        _fail(f"{path} must be an object")
    return value


def _check_no_secret_keys(value: Any, path: str = "$") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = re.sub(r"[^a-z0-9]", "", str(key).lower())
            if any(part in normalized for part in NORMALIZED_SECRET_KEY_PARTS):
                _fail(f"{path}.{key} is not allowed in a quota snapshot")
            _check_no_secret_keys(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _check_no_secret_keys(child, f"{path}[{index}]")


def _check_keys(value: dict[str, Any], allowed: set[str], path: str) -> None:
    unexpected = sorted(set(value) - allowed)
    if unexpected:
        _fail(f"{path} has unsupported field(s): {', '.join(unexpected)}")


def _required_string(value: Any, path: str, *, identifier: bool = False) -> str:
    if not isinstance(value, str) or not value.strip():
        _fail(f"{path} must be a non-empty string")
    result = value.strip()
    if identifier and not IDENTIFIER_RE.fullmatch(result):
        _fail(f"{path} must contain only letters, numbers, '.', '_' or '-'")
    return result


def _timestamp(value: Any, path: str) -> str:
    if not isinstance(value, str) or not UTC_TIMESTAMP_RE.fullmatch(value):
        _fail(f"{path} must be an RFC 3339 UTC timestamp ending in Z")
    try:
        datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        _fail(f"{path} is not a valid timestamp: {exc}")
    return value


def _validate_window(value: Any, path: str) -> None:
    window = _check_mapping(value, path)
    _check_keys(window, ALLOWED_WINDOW_KEYS, path)
    for field in ("status", "remaining_percent", "reset_at"):
        if field not in window:
            _fail(f"{path}.{field} is required")
    status = window["status"]
    if status not in WINDOW_STATUSES:
        _fail(f"{path}.status must be one of: {', '.join(sorted(WINDOW_STATUSES))}")

    remaining = window["remaining_percent"]
    reset_at = window["reset_at"]
    reason = window.get("reason")
    if reason is not None:
        _required_string(reason, f"{path}.reason")

    if status == "available":
        if isinstance(remaining, bool) or not isinstance(remaining, (int, float)):
            _fail(f"{path}.remaining_percent must be a number when status is available")
        if not 0 <= remaining <= 100:
            _fail(f"{path}.remaining_percent must be between 0 and 100")
        _timestamp(reset_at, f"{path}.reset_at")
        return

    if remaining is not None or reset_at is not None:
        _fail(
            f"{path}.remaining_percent and {path}.reset_at must be null when "
            f"status is {status}"
        )
    if reason is None:
        _fail(f"{path}.reason is required when status is {status}")


def _validate_group(value: Any, path: str) -> None:
    group = _check_mapping(value, path)
    _check_keys(group, ALLOWED_GROUP_KEYS, path)
    if "weekly" not in group:
        _fail(f"{path}.weekly is required")
    _validate_window(group["weekly"], f"{path}.weekly")
    if "five_hour" in group:
        _validate_window(group["five_hour"], f"{path}.five_hour")
    if "extensions" in group:
        _check_mapping(group["extensions"], f"{path}.extensions")


def validate_document(document: Any) -> None:
    """Validate a decoded JSON document or raise :class:`ContractError`."""

    root = _check_mapping(document, "$")
    _check_no_secret_keys(root)
    _check_keys(root, ALLOWED_ROOT_KEYS, "$")
    if root.get("schema_version") != 1:
        _fail("$.schema_version must be the integer 1")
    provider = _check_mapping(root.get("provider"), "$.provider")
    _check_keys(provider, ALLOWED_PROVIDER_KEYS, "$.provider")
    _required_string(provider.get("id"), "$.provider.id", identifier=True)
    provider_kind = _required_string(provider.get("kind"), "$.provider.kind", identifier=True)
    if "display_name" in provider:
        _required_string(provider["display_name"], "$.provider.display_name")
    _required_string(root.get("account_label"), "$.account_label")
    _timestamp(root.get("observed_at"), "$.observed_at")
    groups = _check_mapping(root.get("usage_groups"), "$.usage_groups")
    if not groups:
        _fail("$.usage_groups must contain at least one group")

    if provider_kind == "google_ai_pro":
        expected = {"gemini_models", "claude_gpt_models"}
        actual = set(groups)
        if actual != expected:
            missing = sorted(expected - actual)
            extra = sorted(actual - expected)
            details = []
            if missing:
                details.append(f"missing {', '.join(missing)}")
            if extra:
                details.append(f"unexpected {', '.join(extra)}")
            _fail("Google AI Pro must have exactly gemini_models and claude_gpt_models (" + "; ".join(details) + ")")

    for group_id, group in groups.items():
        _required_string(group_id, f"$.usage_groups[{group_id!r}]", identifier=True)
        _validate_group(group, f"$.usage_groups.{group_id}")
    if "extensions" in root:
        _check_mapping(root["extensions"], "$.extensions")


def load_and_validate(path: Path) -> None:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise OSError(f"cannot read {path}: {exc}") from exc
    try:
        document = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise json.JSONDecodeError(
            f"invalid JSON in {path}: {exc.msg}", exc.doc, exc.pos
        ) from exc
    validate_document(document)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate a secret-free challenger provider usage snapshot offline.",
        epilog=(
            "Exit codes: 0=valid, 2=command usage error, "
            "3=file/JSON input error, 4=contract violation."
        ),
    )
    parser.add_argument("path", type=Path, help="JSON snapshot to validate")
    parser.add_argument(
        "--quiet", action="store_true", help="print nothing on success"
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        load_and_validate(args.path)
    except ContractError as exc:
        print(f"CONTRACT ERROR: {exc}", file=sys.stderr)
        return EXIT_CONTRACT
    except (OSError, json.JSONDecodeError) as exc:
        print(f"INPUT ERROR: {exc}", file=sys.stderr)
        return EXIT_IO_OR_JSON
    if not args.quiet:
        print(f"VALID: {args.path}")
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
