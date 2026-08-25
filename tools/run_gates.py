#!/usr/bin/env python3
"""Run cumulative project gates and append machine-readable evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import signal
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any


TIER_ORDER = {"smoke": 0, "regression": 1, "promotion": 2}
GATE_ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
MAX_CAPTURE_BYTES = 64 * 1024
MAX_LOG_BYTES = 256 * 1024
CAPTURE_TRUNCATION_MARKER = "\n...[capture truncated at 65536 bytes]"


class RegistryError(ValueError):
    pass


FINGERPRINT_IGNORED_DIRS = {
    ".git", ".hg", ".svn", "__pycache__", ".pytest_cache",
    "node_modules", ".next",
    # Generated/local-only payloads are validated by their dedicated gates;
    # hashing them here would make the cumulative fingerprint slow and would
    # make a DPAPI/profile session change look like a source-tree mutation.
    "runtime", ".runtime", ".cache", ".tmp", ".ccr-local",
    "codex-login-runtime", "vendor", "cli-proxy-api_core",
    "dashboard_easycli_source", "claude-code-router_proxy",
}
FINGERPRINT_IGNORED_DIRS_CASEFOLD = {
    name.casefold() for name in FINGERPRINT_IGNORED_DIRS
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def load_registry(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RegistryError(f"cannot read registry: {exc}") from exc

    if payload.get("schema_version") != 1:
        raise RegistryError("schema_version must be 1")
    gates = payload.get("gates")
    if not isinstance(gates, list) or not gates:
        raise RegistryError("gates must be a non-empty list")

    seen: set[str] = set()
    for index, gate in enumerate(gates):
        if not isinstance(gate, dict):
            raise RegistryError(f"gate {index} must be an object")
        gate_id = gate.get("id")
        if not isinstance(gate_id, str) or not GATE_ID_RE.fullmatch(gate_id):
            raise RegistryError(f"gate {index} has invalid id")
        if gate_id in seen:
            raise RegistryError(f"duplicate gate id: {gate_id}")
        seen.add(gate_id)

        tier = gate.get("tier")
        if tier not in TIER_ORDER:
            raise RegistryError(f"{gate_id}: invalid tier")
        command = gate.get("command")
        if not isinstance(command, list) or not command or not all(
            isinstance(part, str) and part for part in command
        ):
            raise RegistryError(f"{gate_id}: command must be a non-empty string list")
        timeout = gate.get("timeout_seconds", 60)
        if (type(timeout) not in (int, float)
                or not math.isfinite(float(timeout)) or timeout <= 0):
            raise RegistryError(
                f"{gate_id}: timeout_seconds must be a finite positive number"
            )
        if gate.get("required") is not True:
            raise RegistryError(f"{gate_id}: required must be true")
        if type(gate.get("enabled")) is not bool:
            raise RegistryError(f"{gate_id}: enabled must be boolean")
        for field in ("description", "introduced_by", "invariant"):
            value = gate.get(field)
            if not isinstance(value, str) or not value.strip():
                raise RegistryError(f"{gate_id}: {field} must be a non-empty string")

    gate_by_id = {gate["id"]: gate for gate in gates}
    for gate in gates:
        if gate["enabled"]:
            continue
        gate_id = gate["id"]
        disposition = gate.get("disposition")
        if disposition not in {"superseded", "retired"}:
            raise RegistryError(
                f"{gate_id}: disabled gate needs disposition; lifecycle disposition "
                "must be 'superseded' or 'retired'"
            )
        for field in (
            "disposition_reason", "decision_ref", "evidence_ref", "rollback_ref"
        ):
            value = gate.get(field)
            if not isinstance(value, str) or not value.strip():
                raise RegistryError(
                    f"{gate_id}: disabled gate needs non-empty {field}"
                )
        if disposition == "retired":
            if "replacement_id" in gate:
                raise RegistryError(
                    f"{gate_id}: retired gate must omit replacement_id"
                )
            continue
        replacement_id = gate.get("replacement_id")
        replacement = gate_by_id.get(replacement_id)
        if (
            not isinstance(replacement_id, str)
            or replacement_id == gate_id
            or replacement is None
            or not replacement["enabled"]
            or TIER_ORDER[replacement["tier"]] > TIER_ORDER[gate["tier"]]
        ):
            raise RegistryError(
                f"{gate_id}: invalid gate replacement: {replacement_id!r}"
            )

    if not any(gate["enabled"] for gate in gates):
        raise RegistryError("registry must contain at least one enabled gate")

    return payload


def select_gates(
    registry: dict[str, Any], tier: str, gate_ids: list[str] | None = None
) -> list[dict[str, Any]]:
    if tier not in TIER_ORDER:
        raise RegistryError(f"unknown tier: {tier}")
    gates = registry["gates"]
    if gate_ids:
        wanted = set(gate_ids)
        known = {gate["id"] for gate in gates}
        missing = sorted(wanted - known)
        if missing:
            raise RegistryError(f"unknown gate ids: {', '.join(missing)}")
        selected = [gate for gate in gates if gate["id"] in wanted]
    else:
        selected = [
            gate
            for gate in gates
            if TIER_ORDER[gate["tier"]] <= TIER_ORDER[tier]
        ]

    disabled = [gate["id"] for gate in selected if not gate.get("enabled", True)]
    if gate_ids and disabled:
        raise RegistryError(f"requested disabled gates: {', '.join(disabled)}")
    active = [gate for gate in selected if gate.get("enabled", True)]
    if not active:
        raise RegistryError(f"tier {tier} selected no enabled gates")
    return active


def ensure_within(root: Path, candidate: Path, label: str) -> Path:
    resolved_root = root.resolve()
    resolved = candidate.resolve()
    try:
        resolved.relative_to(resolved_root)
    except ValueError as exc:
        raise RegistryError(f"{label} must stay inside project root") from exc
    return resolved


def display_command(command: list[str]) -> str:
    return subprocess.list2cmdline(command)


def _git_identity(root: Path) -> bytes:
    try:
        top = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--show-toplevel"],
            capture_output=True, check=False, timeout=10,
        )
        if top.returncode != 0:
            return b"git:none"
        observed = Path(top.stdout.decode("utf-8", "replace").strip()).resolve()
        if observed != root.resolve():
            return b"git:parent-repository-not-bound"
        head = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            capture_output=True, check=False, timeout=10,
        )
        index = subprocess.run(
            ["git", "-C", str(root), "ls-files", "--stage", "-z"],
            capture_output=True, check=False, timeout=10,
        )
        if head.returncode != 0 or index.returncode != 0:
            return b"git:unborn-or-unreadable"
        return b"git:exact-root\0" + head.stdout.strip() + b"\0" + index.stdout
    except (OSError, subprocess.SubprocessError):
        return b"git:unavailable"


def _exact_root_tracked_paths(root: Path) -> list[PurePosixPath]:
    """Return exact-root Git paths, including staged paths in an unborn repo."""
    try:
        top = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--show-toplevel"],
            capture_output=True, check=False, timeout=10,
        )
        if top.returncode != 0:
            return []
        observed = Path(
            top.stdout.decode("utf-8", "replace").strip()
        ).resolve()
        if observed != root.resolve():
            return []
        tracked = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z"],
            capture_output=True, check=False, timeout=10,
        )
        if tracked.returncode != 0:
            raise RegistryError("cannot enumerate exact-root tracked files")
    except RegistryError:
        raise
    except (OSError, subprocess.SubprocessError) as exc:
        raise RegistryError(
            f"cannot inspect exact-root tracked files: {exc}"
        ) from exc

    paths: list[PurePosixPath] = []
    for raw in tracked.stdout.split(b"\0"):
        if not raw:
            continue
        relative = PurePosixPath(raw.decode("utf-8", "surrogateescape"))
        if (
            relative.is_absolute()
            or not relative.parts
            or any(part in {"", ".", ".."} for part in relative.parts)
        ):
            raise RegistryError("Git returned a non-canonical tracked path")
        paths.append(relative)
    return paths


def _reject_tracked_fingerprint_exclusions(
    root: Path, owned_logs: Path
) -> None:
    for relative in _exact_root_tracked_paths(root):
        if any(
            part.casefold() in FINGERPRINT_IGNORED_DIRS_CASEFOLD
            for part in relative.parts[:-1]
        ):
            raise RegistryError(
                "tracked file under fingerprint-excluded directory: "
                f"{relative.as_posix()}"
            )
        candidate = root.joinpath(*relative.parts).resolve()
        if candidate == owned_logs or owned_logs in candidate.parents:
            raise RegistryError(
                "tracked file under fingerprint-excluded directory: "
                f"{relative.as_posix()}"
            )
        if candidate.suffix.casefold() in {".pyc", ".pyo"}:
            raise RegistryError(
                "tracked file uses fingerprint-excluded suffix: "
                f"{relative.as_posix()}"
            )


def tree_fingerprint(project_root: Path, owned_log_dir: Path) -> str:
    root = project_root.resolve()
    owned_logs = owned_log_dir.resolve()
    _reject_tracked_fingerprint_exclusions(root, owned_logs)
    digest = hashlib.sha256()
    digest.update(b"project-tree-fingerprint-v1\0")
    digest.update(_git_identity(root))
    for current, directories, names in os.walk(root, followlinks=False):
        current_path = Path(current)
        kept: list[str] = []
        for name in sorted(directories):
            candidate = current_path / name
            if (
                name.casefold() in FINGERPRINT_IGNORED_DIRS_CASEFOLD
                or candidate == owned_logs
            ):
                continue
            if candidate.is_symlink():
                relative = candidate.relative_to(root).as_posix()
                digest.update(b"L\0" + relative.encode() + b"\0")
                digest.update(os.readlink(candidate).encode("utf-8", "surrogateescape"))
                continue
            kept.append(name)
        directories[:] = kept
        for name in sorted(names):
            path = current_path / name
            if (
                owned_logs in path.parents
                or path.suffix.casefold() in {".pyc", ".pyo"}
            ):
                continue
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                digest.update(b"L\0" + relative.encode() + b"\0")
                digest.update(os.readlink(path).encode("utf-8", "surrogateescape"))
            else:
                data = path.read_bytes()
                digest.update(b"F\0" + relative.encode() + b"\0")
                digest.update(str(len(data)).encode() + b"\0" + hashlib.sha256(data).digest())
    return digest.hexdigest()


def terminate_process_tree(process: subprocess.Popen[str]) -> tuple[bool, str]:
    errors: list[str] = []
    if os.name == "nt":
        try:
            killed = subprocess.run(
                ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                capture_output=True, text=True, encoding="utf-8",
                errors="replace", timeout=10, check=False,
            )
            if killed.returncode != 0:
                errors.append(killed.stderr.strip() or killed.stdout.strip())
        except (OSError, subprocess.SubprocessError) as exc:
            errors.append(str(exc))
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except (OSError, ProcessLookupError) as exc:
            errors.append(str(exc))
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            errors.append("process remained alive after force-kill")
    return process.poll() is not None and not errors, "; ".join(error for error in errors if error)


def _bounded_reader(stream: Any, limit: int, result: dict[str, Any], key: str) -> None:
    captured = bytearray()
    truncated = False
    try:
        while True:
            chunk = stream.read(8192)
            if not chunk:
                break
            if len(captured) < limit:
                take = min(limit - len(captured), len(chunk))
                captured.extend(chunk[:take])
                if take < len(chunk):
                    truncated = True
            else:
                truncated = True
    except (OSError, ValueError) as exc:
        result[key + "_error"] = str(exc)
    result[key] = bytes(captured)
    result[key + "_truncated"] = truncated


def _bounded_text(data: bytes, truncated: bool) -> str:
    text = data.decode("utf-8", "replace")
    return text + (CAPTURE_TRUNCATION_MARKER if truncated else "")


def _bounded_log_text(text: str) -> str:
    encoded = text.encode("utf-8", "replace")
    if len(encoded) <= MAX_LOG_BYTES:
        return text
    marker = b"\n...[log truncated at 262144 bytes]\n"
    return (encoded[: max(0, MAX_LOG_BYTES - len(marker))] + marker).decode(
        "utf-8", "replace"
    )


def _collect_process_output(
    process: subprocess.Popen[bytes], timeout: float
) -> tuple[bytes, bytes, bool, bool, str, bool, bool, bool]:
    """Drain both pipes with bounded memory and a bounded post-exit drain."""
    results: dict[str, Any] = {}
    threads = []
    for stream, key in ((process.stdout, "stdout"), (process.stderr, "stderr")):
        if stream is None:
            results[key] = b""
            results[key + "_truncated"] = False
            continue
        thread = threading.Thread(
            target=_bounded_reader, args=(stream, MAX_CAPTURE_BYTES, results, key),
            daemon=True,
        )
        thread.start()
        threads.append(thread)
    timed_out = False
    tree_terminated = False
    termination_error = ""
    drain_timed_out = False
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        tree_terminated, termination_error = terminate_process_tree(process)
    deadline = time.monotonic() + (5 if timed_out else 1)
    for thread in threads:
        remaining = max(0.0, deadline - time.monotonic())
        thread.join(timeout=remaining)
    if any(thread.is_alive() for thread in threads):
        drain_timed_out = True
        if not timed_out:
            timed_out = True
            tree_terminated, termination_error = terminate_process_tree(process)
        for thread in threads:
            thread.join(timeout=5)
    if process.poll() is None:
        process.kill()
        process.wait(timeout=5)
    for stream in (process.stdout, process.stderr):
        if stream is not None:
            stream.close()
    return (
        results.get("stdout", b""), results.get("stderr", b""), timed_out,
        tree_terminated, termination_error,
        bool(results.get("stdout_truncated")),
        bool(results.get("stderr_truncated")), drain_timed_out,
    )


def run_gate(
    gate: dict[str, Any], project_root: Path, log_dir: Path
) -> dict[str, Any]:
    cwd_value = gate.get("cwd", ".")
    if not isinstance(cwd_value, str):
        raise RegistryError(f"{gate['id']}: cwd must be a string")
    cwd = ensure_within(project_root, project_root / cwd_value, f"{gate['id']} cwd")
    if not cwd.is_dir():
        raise RegistryError(f"{gate['id']}: cwd does not exist: {cwd}")

    command = [sys.executable if part == "{python}" else part for part in gate["command"]]
    expected = gate.get("expected_exit_code", 0)
    if not isinstance(expected, int):
        raise RegistryError(f"{gate['id']}: expected_exit_code must be integer")

    started = time.monotonic()
    stdout = ""
    stderr = ""
    observed: int | None = None
    timed_out = False
    process_tree_terminated = False
    termination_error = ""
    popen_kwargs: dict[str, Any] = {}
    if os.name == "nt":
        popen_kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        popen_kwargs["start_new_session"] = True
    try:
        process = subprocess.Popen(
            command,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            shell=False,
            **popen_kwargs,
        )
        (stdout_bytes, stderr_bytes, timed_out, process_tree_terminated,
         termination_error, stdout_truncated, stderr_truncated,
         drain_timed_out) = _collect_process_output(
            process, float(gate.get("timeout_seconds", 60))
        )
        stdout = _bounded_text(stdout_bytes, stdout_truncated)
        stderr = _bounded_text(stderr_bytes, stderr_truncated)
        observed = process.returncode
    except OSError as exc:
        stderr = str(exc)
        stdout_truncated = False
        stderr_truncated = False
        drain_timed_out = False
    elapsed_ms = int((time.monotonic() - started) * 1000)
    passed = not timed_out and observed == expected

    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / f"{gate['id']}.log"
    log_text = "\n".join(
            [
                f"gate: {gate['id']}",
                f"command: {display_command(command)}",
                f"cwd: {cwd}",
                f"expected_exit_code: {expected}",
                f"observed_exit_code: {observed}",
                f"timed_out: {str(timed_out).lower()}",
                f"process_tree_terminated: {str(process_tree_terminated).lower()}",
                f"termination_error: {termination_error}",
                "",
                "[stdout]",
                stdout,
                "[stderr]",
                stderr,
            ]
        )
    log_path.write_bytes(_bounded_log_text(log_text).encode("utf-8"))

    return {
        "id": gate["id"],
        "tier": gate["tier"],
        "required": gate.get("required", True),
        "status": "pass" if passed else "fail",
        "expected_exit_code": expected,
        "observed_exit_code": observed,
        "timed_out": timed_out,
        "process_tree_terminated": process_tree_terminated,
        "termination_error": termination_error,
        "stdout_truncated": stdout_truncated,
        "stderr_truncated": stderr_truncated,
        "capture_limit_bytes": MAX_CAPTURE_BYTES,
        "log_limit_bytes": MAX_LOG_BYTES,
        "capture_drain_timed_out": drain_timed_out,
        "elapsed_ms": elapsed_ms,
        "log_path": str(log_path.relative_to(project_root)).replace("\\", "/"),
    }


def append_jsonl(path: Path, event: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps(event, ensure_ascii=True, separators=(",", ":")) + "\n"
    with path.open("a", encoding="utf-8", newline="") as handle:
        handle.write(line)
        handle.flush()
        os.fsync(handle.fileno())


def execute_registry(
    registry_path: Path,
    project_root: Path,
    evidence_dir: Path,
    tier: str,
    gate_ids: list[str] | None = None,
    fail_fast: bool = False,
) -> dict[str, Any]:
    project_root = project_root.resolve()
    evidence_dir = ensure_within(project_root, evidence_dir, "evidence directory")
    registry_path = ensure_within(project_root, registry_path, "registry")
    registry = load_registry(registry_path)
    selected = select_gates(registry, tier, gate_ids)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    log_dir = evidence_dir / "gate-logs" / run_id
    fingerprint_before = tree_fingerprint(project_root, log_dir)
    results: list[dict[str, Any]] = []

    for gate in selected:
        result = run_gate(gate, project_root, log_dir)
        results.append(result)
        print(f"[{result['status'].upper()}] {result['id']} ({result['elapsed_ms']} ms)")
        if fail_fast and result["status"] == "fail" and result["required"]:
            break

    required_failed = [
        result for result in results if result["required"] and result["status"] == "fail"
    ]

    fingerprint_after = tree_fingerprint(project_root, log_dir)
    tree_stable = fingerprint_before == fingerprint_after
    run_valid = bool(selected) and tree_stable and len(results) == len(selected)
    event = {
        "schema_version": 1,
        "type": "gate_run",
        "run_id": run_id,
        "observed_at": utc_now(),
        "registry": str(registry_path.relative_to(project_root)).replace("\\", "/"),
        "registry_sha256": hashlib.sha256(registry_path.read_bytes()).hexdigest(),
        "tier": tier,
        "status": "fail" if required_failed or not run_valid else "pass",
        "tree_fingerprint_method": "filesystem-sha256-plus-exact-root-git-head-index-v1",
        "tree_fingerprint_before": fingerprint_before,
        "tree_fingerprint_after": fingerprint_after,
        "tree_stable": tree_stable,
        "run_valid": run_valid,
        "selected_gate_count": len(selected),
        "executed_gate_count": len(results),
        "results": results,
    }
    append_jsonl(evidence_dir / "events.jsonl", event)
    return event


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", type=Path, default=Path("gates/gates.json"))
    parser.add_argument("--project-root", type=Path)
    parser.add_argument("--evidence-dir", type=Path)
    parser.add_argument("--tier", choices=tuple(TIER_ORDER), default="smoke")
    parser.add_argument("--gate", action="append", dest="gate_ids")
    parser.add_argument("--fail-fast", action="store_true")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    registry_path = args.registry.resolve()
    project_root = (
        args.project_root.resolve()
        if args.project_root
        else registry_path.parent.parent.resolve()
    )
    evidence_dir = (
        args.evidence_dir
        if args.evidence_dir and args.evidence_dir.is_absolute()
        else project_root / (args.evidence_dir or Path("50-Evidence"))
    )

    try:
        registry = load_registry(registry_path)
        if args.list:
            for gate in registry["gates"]:
                state = "enabled" if gate.get("enabled", True) else "disabled"
                print(f"{gate['id']}\t{gate['tier']}\t{state}")
            return 0
        selected = select_gates(registry, args.tier, args.gate_ids)
        if args.dry_run:
            for gate in selected:
                print(f"{gate['id']}: {display_command(gate['command'])}")
            print(f"Selected {len(selected)} gates through tier {args.tier}")
            return 0
        event = execute_registry(
            registry_path=registry_path,
            project_root=project_root,
            evidence_dir=evidence_dir,
            tier=args.tier,
            gate_ids=args.gate_ids,
            fail_fast=args.fail_fast,
        )
        print(f"Gate run {event['run_id']}: {event['status']}")
        return 0 if event["status"] == "pass" else 1
    except RegistryError as exc:
        print(f"Registry error: {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
