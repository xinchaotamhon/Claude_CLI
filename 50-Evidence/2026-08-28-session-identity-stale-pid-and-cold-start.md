# Session identity, stale PID and cold-start containment — 2026-08-28

## Scope and owner observations

This change addresses four bounded observations without reading credentials or
transcript content:

1. a dashboard resume reported failure before a Google Claude terminal started;
2. resuming with another model relabelled the old session as that model;
3. Codex could fail on the first cold request and work later; and
4. after extracting session logic, the dashboard server announced readiness
   while the starter still timed out.

The owner requires one project-local Claude harness, retained `xhigh`, no
automatic fallback and the ability to run the same account/model in multiple
terminals.

## Baseline and pre-fix evidence

- Parent branch was `claude`, synchronized with `origin/claude` at
  `af7123d` before this work.
- Baseline smoke run `20260828T135427Z-2cdddb1e` passed 21/22 in the restricted
  tool profile. The only failure was the expected unavailable Windows DPAPI
  user profile; no source invariant failed.
- A new lifecycle regression initially failed because the session lifecycle
  module did not exist.
- A new Codex readiness regression initially failed because no stable-health
  verifier existed.
- A bounded owner-profile Google resume reproduced the exact sanitized failure:
  `Recorded PID ... is not the verified project-local Google runtime.`
- Sanitized ignored metadata showed several session UUIDs whose index route had
  been overwritten by a later resume route. No transcript line was inspected.

## Proved root causes

### Session identity mutation

`dashboard/server.mjs` updated `routeId`, `routeName` and `model` in place when
resuming. Those fields had been serving both as origin identity and most-recent
launch metadata. There was also no in-flight reservation for an exact UUID.

### Google resume failure

The ignored `proxy.pid` outlived its project runtime. Windows reused that PID
for a different executable. The verifier correctly rejected the executable but
incorrectly turned ordinary PID reuse into a terminal launch failure instead of
discarding the stale marker.

### False dashboard startup failure

The server fingerprint included `server.mjs` plus the extracted
`session_lifecycle.mjs`, while `start_dashboard.ps1` fingerprinted only the
first file. Both healthy identities could therefore never match.

### Codex cold start

A local readiness weakness is proved: one instantaneous gateway `/health`
success was accepted immediately. The exact provider-side cause of the owner's
first-request API error remains unproved, so the change is classified as
containment rather than a complete upstream fix.

## Implemented invariants

- `originRouteId`, `originRouteName` and `originModel` are immutable session
  identity. `lastRouteId`, `lastRouteName` and `lastModel` describe only the most
  recent resume route.
- Legacy relabelled rows recover their origin from the earliest retained local
  terminal metadata. This reads metadata only, never transcript content.
- One exact session UUID is reserved while starting and rejected while already
  running. Distinct newly created UUIDs may use the same account/model in any
  number of terminals and share only provider quota.
- Malformed, exited or reused Google PID markers are removed without stopping a
  mismatched process. Only the exact hash-pinned owned binary may be restarted.
- Codex/CCR requires three consecutive verified local health checks and uses at
  most three process-local Claude retries with nonessential traffic suppressed.
  Account, model, effort and fallback policy do not change.
- Starter and server hash the same ordered dashboard source pair.

## Verification

- Session lifecycle functional test: pass, including legacy repair, cross-route
  resume, same-route distinct UUIDs and exact-UUID conflict.
- Router startup unit suite: 11/11 pass.
- Google runtime lifecycle self-test: pass; a marker deliberately pointed at
  the current PowerShell process was discarded and that unrelated process
  remained alive.
- Dashboard static verifiers, Node syntax checks, PowerShell parser and static
  TypeScript/Vite build: pass.
- Live dashboard restart: pass. Ready-state and `/health` returned equal
  composite source hashes; sanitized API state returned seven transcript-backed
  sessions, five with a distinct last route, and no credential material.
- Real bounded owner-profile Google resume: pass. The old conversation was
  offered under a different selected route, `xhigh` remained visible, and no
  new prompt/model request was sent during the proof.
- Final owner-profile smoke run `20260828T142604Z-ee30a4cf`: 24/24 pass,
  including DPAPI, external Codex App isolation, session lifecycle and stale PID
  recovery. The gate run made no provider/model request.

## Usage/token disposition

No aggressive token optimizer was installed. The four reviewed candidates
remain uninstalled because prompt/output clipping or context/log interception
could hide warnings, stack traces or project memory. Safe controls currently in
use are common resumable sessions, native Claude auto-compaction, suppression of
nonessential background traffic and finite process-local retries. These can
reduce repeated setup and background requests, but they do not reduce the
reasoning tokens intrinsically required by `xhigh`. Subagents retain separate
provider usage and are not a billing bypass.

## Remaining owner proof and rollback

- Send one ordinary first prompt after a true Codex cold start. If it still
  fails, retain the visible error and timestamp before further changes.
- Open two new terminals with the same account/model to confirm independent
  session UUIDs. Do not resume the same UUID in both terminals.
- Rollback is the parent commit before this change. No auth/session file needs
  deletion; dashboard and Claude terminals can be closed normally.
