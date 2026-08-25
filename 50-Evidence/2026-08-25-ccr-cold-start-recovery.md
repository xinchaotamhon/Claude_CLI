# CCR cold-start recovery — 2026-08-25

## Accepted outcome

Selecting an imported route must start the project-local CCR gateway, verify
its identity and loopback health before DPAPI access, and then launch only the
project-local Claude binary. Recovery may retry only a narrowly identified
transient startup condition; unrelated gateway failures must remain fail-closed.

## Owner observation

Selecting `[1]` failed before Claude opened. The sanitized error stated that the
verified CCR process did not answer the local gateway health check. Account
login and route discovery had already succeeded.

## Runtime diagnosis

No real `setting.json`, auth file, SQLite credential, DPAPI plaintext, request
body or provider response was printed or copied.

- Management remained available on loopback, while gateway health was absent.
- Authenticated local management status reported `state=error` and the exact
  non-secret error `Core gateway did not accept runtime config within 5000ms.`
- Source inspection located the fixed five-second acceptance deadline in
  `claude-code-router_proxy/packages/core/src/gateway/core-runtime/supervisor.ts`.
- A provider-free synthetic bootstrap probe initially exceeded 15 seconds.
  After the gateway module was loaded directly from the same project-local
  runtime, the exact bootstrap accepted the same synthetic config. This is
  consistent with a slow first module load/cache or endpoint-scanner delay on
  Windows, but the external cause of that delay is inferred rather than proved.
- A later real project-local start completed in 8.297 seconds, returned exit 0,
  answered gateway health and reported `state=running` with no last error.

The proved root condition is therefore the fixed five-second IPC acceptance
deadline being exceeded. The specific Windows source of the slow first load is
unknown.

## Repair

`Ensure-Router` retains its normal verified start path. If and only if local
management reports the exact config-acceptance timeout, it performs at most two
authenticated `startGateway` retries and re-runs full process identity plus
gateway health verification. It does not decrypt the route client key during
recovery. Any other status, failed identity check or unverified retry stops the
launch.

No installed/minified CCR runtime file remains patched. All diagnostic probes,
raw temporary output and the exact temporary runtime backup were removed after
the original runtime hash was restored and verified.

## Verification

- Project self-test outside the Codex sandbox: PASS, including Windows DPAPI
  round-trip and the exact-only cold-start trigger fixture.
- Final cumulative smoke gates: all 8 passed in
  `20260825T041235Z-3565decb`.
- End-to-end launcher check: selected real menu route `[1]` while passing
  `--version`; observed `2.1.241 (Claude Code)` and exit 0. This exercised the
  saved route, CCR start/health verification, DPAPI client-key read and local
  Claude launch without sending a model request or consuming quota.
- The project-local CCR service started for this test was stopped afterward.

An earlier sandboxed gate run, `20260825T040648Z-51c987ee`, failed only because
the automated sandbox did not load the Windows profile required by DPAPI. The
same self-test and full gate run passed outside that sandbox under the owner's
Windows profile.

## 9router bounded comparison

A read-only source assessment found that 9router exposes an
Anthropic-compatible `/v1/messages` path and supports multiple Codex OAuth
connections with automatic fallback. It was not adopted because it adds a
Next.js server, SQLite/dashboard state and a separate project-local packaging
task; the inspected checkout also needs its Codex OAuth import path verified.
The chat route did not show direct per-request selection of one fixed account.
CCR is therefore retained; 9router remains an unverified sidecar candidate.

## Rollback

Revert `Test-GatewayConfigAcceptanceTimeout`, restore the former single-attempt
`Ensure-Router`, and revert the associated fixture/state/evidence updates. That
would intentionally restore failure on the observed fixed-deadline cold start.
