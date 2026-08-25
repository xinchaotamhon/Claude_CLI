#!/usr/bin/env python3
"""Validate the secret-free project-local account onboarding contract.

This module defines wizard slots only.  It never reads project settings,
account homes, global Codex/App state, authentication files, quotas, or a
provider.  It also does not implement account switching or fallback.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


EXIT_OK = 0
EXIT_USAGE = 2
EXIT_IO_OR_JSON = 3
EXIT_CONTRACT = 4

ROOT_KEYS = {
    "schema_version",
    "manifest_type",
    "automatic_fallback_default",
    "slots",
    "extensions",
}
SLOT_COMMON_KEYS = {"id", "provider", "expected_plan", "label", "login_order"}
SLOT_KEYS_BY_PROVIDER = {
    "openai_codex": SLOT_COMMON_KEYS | {"allowed_models"},
    "google_ai": SLOT_COMMON_KEYS | {"usage_groups"},
}
EXPECTED_SLOT_IDS = {
    "codex_free_1",
    "codex_free_2",
    "codex_free_3",
    "codex_plus_1",
    "google_pro_1",
    "google_pro_2",
    "google_pro_3",
}
EXPECTED_SLOT_ORDER = {
    "codex_free_1": 1,
    "codex_free_2": 2,
    "codex_free_3": 3,
    "codex_plus_1": 4,
    "google_pro_1": 5,
    "google_pro_2": 6,
    "google_pro_3": 7,
}
PLAN_BY_SLOT = {
    "codex_free_1": "codex_free",
    "codex_free_2": "codex_free",
    "codex_free_3": "codex_free",
    "codex_plus_1": "codex_plus",
    "google_pro_1": "google_ai_pro",
    "google_pro_2": "google_ai_pro",
    "google_pro_3": "google_ai_pro",
}
PROVIDER_BY_PLAN = {
    "codex_free": "openai_codex",
    "codex_plus": "openai_codex",
    "google_ai_pro": "google_ai",
}
MODELS_BY_PLAN = {
    "codex_free": ("terra", "luna"),
    "codex_plus": ("sol", "terra", "luna"),
}
GOOGLE_USAGE_GROUPS = ("gemini_models", "claude_gpt_models")
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
    "session",
    "token",
}
NORMALIZED_SECRET_KEY_PARTS = {
    re.sub(r"[^a-z0-9]", "", value) for value in SECRET_KEY_PARTS
}
IDENTIFIER_RE = re.compile(r"^[a-z][a-z0-9_]*$")


class ContractError(ValueError):
    """Raised when a decoded onboarding manifest violates the contract."""


def _fail(message: str) -> None:
    raise ContractError(message)


def _mapping(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        _fail(f"{path} must be an object")
    return value


def _keys(value: dict[str, Any], allowed: set[str], path: str) -> None:
    unexpected = sorted(set(value) - allowed)
    if unexpected:
        _fail(f"{path} has unsupported field(s): {', '.join(unexpected)}")


def _string(value: Any, path: str, *, identifier: bool = False) -> str:
    if not isinstance(value, str) or not value.strip():
        _fail(f"{path} must be a non-empty string")
    result = value.strip()
    if identifier and not IDENTIFIER_RE.fullmatch(result):
        _fail(f"{path} must use lower-case letters, numbers and '_' only")
    return result


def _string_list(value: Any, path: str) -> tuple[str, ...]:
    if not isinstance(value, list) or not value:
        _fail(f"{path} must be a non-empty array")
    result = tuple(_string(item, f"{path}[{index}]", identifier=True) for index, item in enumerate(value))
    if len(result) != len(set(result)):
        _fail(f"{path} must not contain duplicates")
    return result


def _check_no_secret_keys(value: Any, path: str = "$") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = re.sub(r"[^a-z0-9]", "", str(key).lower())
            if any(part in normalized for part in NORMALIZED_SECRET_KEY_PARTS):
                _fail(f"{path}.{key} is not allowed in a secret-free onboarding manifest")
            _check_no_secret_keys(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _check_no_secret_keys(child, f"{path}[{index}]")


def _validate_slot(value: Any, index: int, seen_ids: set[str], seen_labels: set[str]) -> str:
    path = f"$.slots[{index}]"
    slot = _mapping(value, path)
    provider = _string(slot.get("provider"), f"{path}.provider", identifier=True)
    if provider not in SLOT_KEYS_BY_PROVIDER:
        _fail(f"{path}.provider is not a supported onboarding provider")
    _keys(slot, SLOT_KEYS_BY_PROVIDER[provider], path)

    slot_id = _string(slot.get("id"), f"{path}.id", identifier=True)
    if slot_id in seen_ids:
        _fail(f"duplicate slot id: {slot_id}")
    seen_ids.add(slot_id)
    if slot_id not in EXPECTED_SLOT_IDS:
        _fail(f"{path}.id is not one of the seven required onboarding slots")

    label = _string(slot.get("label"), f"{path}.label")
    label_key = label.casefold()
    if label_key in seen_labels:
        _fail(f"duplicate slot label: {label}")
    seen_labels.add(label_key)

    expected_plan = _string(slot.get("expected_plan"), f"{path}.expected_plan", identifier=True)
    if expected_plan not in PROVIDER_BY_PLAN:
        _fail(f"{path}.expected_plan is not a supported onboarding plan")
    if expected_plan != PLAN_BY_SLOT[slot_id]:
        _fail(f"{path}.expected_plan does not match required slot {slot_id}")
    if provider != PROVIDER_BY_PLAN[expected_plan]:
        _fail(f"{path}.provider does not match {expected_plan}")

    login_order = slot.get("login_order")
    if isinstance(login_order, bool) or not isinstance(login_order, int):
        _fail(f"{path}.login_order must be an integer")
    if login_order != EXPECTED_SLOT_ORDER[slot_id]:
        _fail(f"{path}.login_order does not match required slot {slot_id}")

    if provider == "openai_codex":
        models = _string_list(slot.get("allowed_models"), f"{path}.allowed_models")
        if models != MODELS_BY_PLAN[expected_plan]:
            _fail(f"{path}.allowed_models does not match the expected {expected_plan} model set/order")
    else:
        groups = _string_list(slot.get("usage_groups"), f"{path}.usage_groups")
        if groups != GOOGLE_USAGE_GROUPS:
            _fail(f"{path}.usage_groups must be gemini_models then claude_gpt_models")
    return slot_id


def validate_document(document: Any) -> None:
    """Validate a decoded account-batch manifest or raise :class:`ContractError`."""

    root = _mapping(document, "$")
    _check_no_secret_keys(root)
    _keys(root, ROOT_KEYS, "$")
    if root.get("schema_version") != 1:
        _fail("$.schema_version must be the integer 1")
    if root.get("manifest_type") != "project_local_account_onboarding":
        _fail("$.manifest_type must be 'project_local_account_onboarding'")
    if root.get("automatic_fallback_default") is not False:
        _fail("$.automatic_fallback_default must be false during onboarding")
    slots = root.get("slots")
    if not isinstance(slots, list) or len(slots) != len(EXPECTED_SLOT_IDS):
        _fail("$.slots must contain exactly seven onboarding slots")
    seen_ids: set[str] = set()
    seen_labels: set[str] = set()
    for index, slot in enumerate(slots):
        _validate_slot(slot, index, seen_ids, seen_labels)
    if seen_ids != EXPECTED_SLOT_IDS:
        _fail("$.slots must contain the exact seven required onboarding slot IDs")
    if "extensions" in root:
        _mapping(root["extensions"], "$.extensions")


def load_and_validate(path: Path) -> None:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise OSError(f"cannot read {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise json.JSONDecodeError(f"invalid JSON in {path}: {exc.msg}", exc.doc, exc.pos) from exc
    validate_document(document)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate a secret-free project-local account onboarding manifest.",
        epilog="Exit codes: 0=valid, 2=usage, 3=input, 4=contract.",
    )
    parser.add_argument("path", type=Path, help="JSON manifest to validate")
    parser.add_argument("--quiet", action="store_true", help="print nothing on success")
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
