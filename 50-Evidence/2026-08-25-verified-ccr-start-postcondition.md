# Verified CCR start postcondition — 2026-08-25

## Accepted outcome

Selecting an already-imported account route must open the project-local Claude
harness when the exact project-local CCR gateway is healthy. A stale/nonzero
`start` exit must not override a stronger verified postcondition, and no client
key may be decrypted when process identity or health is unverified.

## Owner observation

After the account route became visible, choosing `[1]` failed with the generic
wrapper message `CCR command failed (exit code 1)`. No auth, token, SQLite,
request log or ignored settings content was supplied or read for diagnosis.

## Bounded runtime observation

The diagnostic used only the pinned project-local Node/CCR command, exact local
runtime paths, loopback listener metadata and unauthenticated gateway `/health`.
Raw CCR output was withheld to avoid exposing management URLs or tokens.

- Before `start --gateway`: management listened on `127.0.0.1:3458`; gateway
  health on `127.0.0.1:3456` was unavailable.
- Command observation: exit code 1.
- Immediately afterward: gateway `/health` returned HTTP 200.

This proves that, for this observed transition, process exit and requested
postcondition disagreed. It does not prove the internal reason CCR emitted exit
1; that remains unknown.

## Root cause and repair

`Ensure-Router` called `Invoke-Ccr start --gateway`, which threw immediately on
nonzero exit. Therefore the existing stronger verification—local service state,
PID, exact Node/CLI command line, service token and gateway health—never ran.

`Invoke-CcrStartAndVerify` now captures the start error only as diagnostic
context and always evaluates the independent verifier. It returns only when the
required service is verified. If verification never passes, it fails closed
with both the verification error and sanitized start-command context. The
gateway verifier still runs before `Read-ProtectedSecret`.

## Deterministic evidence

- Pre-repair focused marker gate: `20260824T174637Z-f7d21190`, expected failure.
- Post-repair focused gates: `20260824T174749Z-ade30ddf`,
  `claude.router-local-layout` and `claude.router-menu-selftest` both passed.
- Integrated cumulative run: `20260824T175012Z-6f2f15a6`, all 8 enabled smoke
  gates passed.
- Offline self-test fixture `simulated CCR start exit after service activation`
  proves that verified readiness wins over a stale start error.
- A second fixture proves that start error plus failed verification remains a
  failure and retains both diagnostic contexts.
- Tests do not invoke a provider/model, read real auth/settings/SQLite, or print
  raw CCR output.

## Rollback

Revert `Invoke-CcrStartAndVerify`, restore direct `Invoke-Ccr start` handling,
and revert its fixture/verifier/memory updates together. This would intentionally
restore the owner-observed false-negative startup failure.
