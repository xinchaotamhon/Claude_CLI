#!/usr/bin/env python3
"""Offline validator and deterministic evaluator for safe fallback policy.

This module never contacts a provider and never performs a retry.  It validates
a secret-free policy and exposes ``eligible_route_ids`` for a dashboard or a
challenger to use as a decision oracle.  The caller must provide a session
identity and perform the actual request; this file deliberately has no client
or credential handling.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable


EXIT_OK = 0
EXIT_USAGE = 2
EXIT_IO_OR_JSON = 3
EXIT_CONTRACT = 4

WINDOW_STATUSES = {"available", "unknown", "unavailable"}
REACTIVE_SIGNALS = {"quota_exhausted", "rate_limited"}
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
    re.sub(r"[^a-z0-9]", "", value) for value in SECRET_KEY_PARTS
}
IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
UTC_TIMESTAMP_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$"
)

ROOT_KEYS = {
    "schema_version",
    "policy_id",
    "provider",
    "account_label",
    "observed_at",
    "manual_only",
    "allowlist",
    "usage_groups",
    "routes",
    "fallback",
    "extensions",
}
PROVIDER_KEYS = {"id", "kind", "display_name"}
ALLOWLIST_KEYS = {"account_ids", "model_ids"}
WINDOW_KEYS = {"status", "remaining_percent", "reset_at", "reason"}
GROUP_KEYS = {"weekly", "five_hour", "extensions"}
ROUTE_KEYS = {"id", "account_id", "model_id", "usage_group", "enabled", "priority"}
FALLBACK_KEYS = {
    "enabled",
    "session_affinity",
    "max_attempts",
    "before_upstream_output_only",
    "after_output",
    "after_tool_side_effect",
    "unknown_five_hour_mode",
    "reactive_signals",
    "respect_provider_limits",
    "no_quota_bypass",
    "chain",
}
CHAIN_ENTRY_KEYS = {"route_id", "fallback_route_ids"}


class ContractError(ValueError):
    """Raised when a policy violates the fallback contract."""


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
        _fail(f"{path} must contain only letters, numbers, '.', '_' or '-'")
    return result


def _bool(value: Any, path: str) -> bool:
    if not isinstance(value, bool):
        _fail(f"{path} must be boolean")
    return value


def _timestamp(value: Any, path: str) -> None:
    if not isinstance(value, str) or not UTC_TIMESTAMP_RE.fullmatch(value):
        _fail(f"{path} must be an RFC 3339 UTC timestamp ending in Z")
    try:
        datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        _fail(f"{path} is not a valid timestamp: {exc}")


def _string_list(value: Any, path: str, *, allow_empty: bool = False) -> list[str]:
    if not isinstance(value, list) or (not allow_empty and not value):
        _fail(f"{path} must be a non-empty array")
    result = [_string(item, f"{path}[{index}]", identifier=True) for index, item in enumerate(value)]
    if len(set(result)) != len(result):
        _fail(f"{path} must not contain duplicates")
    return result


def _check_no_secret_keys(value: Any, path: str = "$") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = re.sub(r"[^a-z0-9]", "", str(key).lower())
            if any(part in normalized for part in NORMALIZED_SECRET_KEY_PARTS):
                _fail(f"{path}.{key} is not allowed in a fallback policy")
            _check_no_secret_keys(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _check_no_secret_keys(child, f"{path}[{index}]")


def _window(value: Any, path: str) -> None:
    window = _mapping(value, path)
    _keys(window, WINDOW_KEYS, path)
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
        _string(reason, f"{path}.reason")
    if status == "available":
        if isinstance(remaining, bool) or not isinstance(remaining, (int, float)):
            _fail(f"{path}.remaining_percent must be numeric when available")
        if not 0 <= remaining <= 100:
            _fail(f"{path}.remaining_percent must be between 0 and 100")
        _timestamp(reset_at, f"{path}.reset_at")
        return
    if remaining is not None or reset_at is not None:
        _fail(f"{path}.remaining_percent and reset_at must be null when {status}")
    if reason is None:
        _fail(f"{path}.reason is required when status is {status}")


def _usage_groups(value: Any, provider_kind: str) -> dict[str, Any]:
    groups = _mapping(value, "$.usage_groups")
    if not groups:
        _fail("$.usage_groups must contain at least one group")
    if provider_kind == "google_ai_pro" and set(groups) != {"gemini_models", "claude_gpt_models"}:
        _fail("Google AI Pro must contain exactly gemini_models and claude_gpt_models")
    for group_id, group in groups.items():
        _string(group_id, f"$.usage_groups[{group_id!r}]", identifier=True)
        item = _mapping(group, f"$.usage_groups.{group_id}")
        _keys(item, GROUP_KEYS, f"$.usage_groups.{group_id}")
        if "weekly" not in item:
            _fail(f"$.usage_groups.{group_id}.weekly is required")
        _window(item["weekly"], f"$.usage_groups.{group_id}.weekly")
        if "five_hour" in item:
            _window(item["five_hour"], f"$.usage_groups.{group_id}.five_hour")
        if "extensions" in item:
            _mapping(item["extensions"], f"$.usage_groups.{group_id}.extensions")
    return groups


def _routes_and_allowlist(root: dict[str, Any], groups: dict[str, Any]) -> dict[str, dict[str, Any]]:
    allowlist = _mapping(root.get("allowlist"), "$.allowlist")
    _keys(allowlist, ALLOWLIST_KEYS, "$.allowlist")
    accounts = set(_string_list(allowlist.get("account_ids"), "$.allowlist.account_ids"))
    models = set(_string_list(allowlist.get("model_ids"), "$.allowlist.model_ids"))
    routes = root.get("routes")
    if not isinstance(routes, list) or not routes:
        _fail("$.routes must be a non-empty array")
    by_id: dict[str, dict[str, Any]] = {}
    for index, route_value in enumerate(routes):
        path = f"$.routes[{index}]"
        route = _mapping(route_value, path)
        _keys(route, ROUTE_KEYS, path)
        route_id = _string(route.get("id"), f"{path}.id", identifier=True)
        if route_id in by_id:
            _fail(f"duplicate route id: {route_id}")
        account_id = _string(route.get("account_id"), f"{path}.account_id", identifier=True)
        model_id = _string(route.get("model_id"), f"{path}.model_id", identifier=True)
        usage_group = _string(route.get("usage_group"), f"{path}.usage_group", identifier=True)
        if account_id not in accounts:
            _fail(f"{path}.account_id is outside the account allowlist")
        if model_id not in models:
            _fail(f"{path}.model_id is outside the model allowlist")
        if usage_group not in groups:
            _fail(f"{path}.usage_group does not name a usage group")
        _bool(route.get("enabled"), f"{path}.enabled")
        priority = route.get("priority")
        if isinstance(priority, bool) or not isinstance(priority, int) or priority < 1:
            _fail(f"{path}.priority must be a positive integer")
        by_id[route_id] = route
    return by_id


def _fallback(root: dict[str, Any], routes: dict[str, dict[str, Any]]) -> None:
    fallback = _mapping(root.get("fallback"), "$.fallback")
    _keys(fallback, FALLBACK_KEYS, "$.fallback")
    for field in (
        "enabled",
        "session_affinity",
        "before_upstream_output_only",
        "respect_provider_limits",
        "no_quota_bypass",
    ):
        if _bool(fallback.get(field), f"$.fallback.{field}") is False:
            _fail(f"$.fallback.{field} must be true for this safety contract")
    max_attempts = fallback.get("max_attempts")
    if isinstance(max_attempts, bool) or not isinstance(max_attempts, int) or not 1 <= max_attempts <= 5:
        _fail("$.fallback.max_attempts must be a finite integer from 1 through 5")
    if fallback.get("after_output") != "stop":
        _fail("$.fallback.after_output must be 'stop'")
    if fallback.get("after_tool_side_effect") != "stop":
        _fail("$.fallback.after_tool_side_effect must be 'stop'")
    if fallback.get("unknown_five_hour_mode") != "reactive_only":
        _fail("$.fallback.unknown_five_hour_mode must be 'reactive_only'")
    signals = set(_string_list(fallback.get("reactive_signals"), "$.fallback.reactive_signals"))
    if not signals or not signals <= REACTIVE_SIGNALS:
        _fail("$.fallback.reactive_signals may contain only quota_exhausted/rate_limited")
    chain = fallback.get("chain")
    if not isinstance(chain, list):
        _fail("$.fallback.chain must be an array")
    chain_ids: set[str] = set()
    for index, entry_value in enumerate(chain):
        path = f"$.fallback.chain[{index}]"
        entry = _mapping(entry_value, path)
        _keys(entry, CHAIN_ENTRY_KEYS, path)
        route_id = _string(entry.get("route_id"), f"{path}.route_id", identifier=True)
        if route_id in chain_ids:
            _fail(f"fallback chain repeats route: {route_id}")
        chain_ids.add(route_id)
        if route_id not in routes:
            _fail(f"{path}.route_id does not name a route")
        target_ids = _string_list(entry.get("fallback_route_ids"), f"{path}.fallback_route_ids", allow_empty=True)
        if route_id in target_ids:
            _fail(f"{path}.fallback_route_ids cannot include its source route")
        if len(target_ids) != len(set(target_ids)):
            _fail(f"{path}.fallback_route_ids must not contain duplicates")
        for target_id in target_ids:
            if target_id not in routes:
                _fail(f"{path}.fallback_route_ids contains an unknown route: {target_id}")
    if chain_ids != set(routes):
        _fail("fallback chain must declare every route exactly once")
    graph = {
        entry["route_id"]: entry["fallback_route_ids"] for entry in chain
    }

    def path_length(route_id: str, active: tuple[str, ...] = ()) -> int:
        if route_id in active:
            _fail("fallback chain must not contain cycles")
        targets = graph[route_id]
        if not targets:
            return 1
        return 1 + max(path_length(target, active + (route_id,)) for target in targets)

    longest = max(path_length(route_id) for route_id in graph)
    if longest > max_attempts:
        _fail("a fallback chain path exceeds max_attempts")


def validate_document(document: Any) -> None:
    """Validate a decoded fallback policy or raise :class:`ContractError`."""

    root = _mapping(document, "$")
    _check_no_secret_keys(root)
    _keys(root, ROOT_KEYS, "$")
    if root.get("schema_version") != 1:
        _fail("$.schema_version must be the integer 1")
    _string(root.get("policy_id"), "$.policy_id", identifier=True)
    provider = _mapping(root.get("provider"), "$.provider")
    _keys(provider, PROVIDER_KEYS, "$.provider")
    _string(provider.get("id"), "$.provider.id", identifier=True)
    provider_kind = _string(provider.get("kind"), "$.provider.kind", identifier=True)
    if "display_name" in provider:
        _string(provider["display_name"], "$.provider.display_name")
    _string(root.get("account_label"), "$.account_label")
    _timestamp(root.get("observed_at"), "$.observed_at")
    _bool(root.get("manual_only"), "$.manual_only")
    groups = _usage_groups(root.get("usage_groups"), provider_kind)
    routes = _routes_and_allowlist(root, groups)
    _fallback(root, routes)
    if "extensions" in root:
        _mapping(root["extensions"], "$.extensions")


def _window_allows_initial(window_group: dict[str, Any]) -> bool:
    weekly = window_group["weekly"]
    if weekly["status"] != "available" or weekly["remaining_percent"] <= 0:
        return False
    five_hour = window_group.get("five_hour")
    if five_hour is not None and five_hour["status"] == "available":
        return five_hour["remaining_percent"] > 0
    return True


def eligible_route_ids(
    document: dict[str, Any],
    *,
    phase: str = "initial",
    current_route_id: str | None = None,
    signal: str | None = None,
    upstream_output_started: bool = False,
    tool_side_effect: bool = False,
) -> tuple[str, ...]:
    """Return allowed candidates without performing a request.

    ``initial`` selects routes whose weekly window is available and whose
    available five-hour window is not exhausted. Missing/unknown five-hour
    data does not block the initial attempt. ``reactive`` is only permitted
    after a configured quota/rate-limit signal and then may use only the
    declared fallbacks for ``current_route_id``. Any output or tool side effect
    returns no candidates, enforcing the no-retry-after-side-effect invariant.
    """

    validate_document(document)
    if phase not in {"initial", "reactive"}:
        raise ContractError("phase must be 'initial' or 'reactive'")
    fallback = document["fallback"]
    if document["manual_only"] or not fallback["enabled"]:
        return ()
    if upstream_output_started or tool_side_effect:
        return ()
    if phase == "reactive":
        if current_route_id is None:
            raise ContractError("reactive phase requires current_route_id")
        if signal not in fallback["reactive_signals"]:
            return ()
        chain_entry = next(
            (
                item
                for item in fallback["chain"]
                if item["route_id"] == current_route_id
            ),
            None,
        )
        if chain_entry is None:
            raise ContractError(f"unknown current_route_id: {current_route_id}")
        route_ids: Iterable[str] = chain_entry["fallback_route_ids"]
    else:
        route_ids = (route["id"] for route in document["routes"])
    groups = document["usage_groups"]
    by_id = {route["id"]: route for route in document["routes"]}
    candidates = []
    for route_id in route_ids:
        route = by_id[route_id]
        group = groups[route["usage_group"]]
        if route["enabled"] and _window_allows_initial(group):
            candidates.append(route)
    candidates.sort(key=lambda route: (route["priority"], route["id"]))
    return tuple(route["id"] for route in candidates)


def load_and_validate(path: Path) -> None:
    try:
        raw = path.read_text(encoding="utf-8")
        document = json.loads(raw)
    except OSError as exc:
        raise OSError(f"cannot read {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise json.JSONDecodeError(
            f"invalid JSON in {path}: {exc.msg}", exc.doc, exc.pos
        ) from exc
    validate_document(document)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate a secret-free challenger fallback policy offline.",
        epilog="Exit codes: 0=valid, 2=usage, 3=input, 4=contract.",
    )
    parser.add_argument("path", type=Path, help="JSON policy to validate")
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
