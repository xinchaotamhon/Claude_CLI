# ADR — CLIProxyAPI remains a bounded challenger

- Date: 2026-08-25
- Status: accepted for Phase 0 source audit only
- Owner intent: one project-local Claude CLI harness with provider/model routing,
  multiple subscription accounts and clearly labelled quota information

## Decision

Retain CCR as the active rollback champion. Keep CLIProxyAPI `v7.2.141` as an
ignored nested source repository on local branch `claude`, with exact tracked
provenance and an offline verifier. Do not build, authenticate, start or wire it
into `RUN_CLAUDE.bat` until Phase 1 is separately approved and its isolation
patch/gates pass.

## Why

CLIProxyAPI has the strongest source-level fit found so far: Anthropic
`/v1/messages`, Codex/Claude/Google OAuth, API-key providers, plan-aware model
catalogs, per-model account filtering, cooldown handling and session affinity.
It also has unacceptable defaults for this project: all-interface binding,
user-home auth storage, plaintext JSON credentials and an unconditional
Antigravity update request. Its core usage counters are not provider-reported
5-hour/weekly quota.

## Consequences

- Phase 0 adds no runtime dependency and does not consume provider quota.
- Phase 1 requires a project-local Go toolchain and a reviewable update-isolation
  patch before an offline build.
- Explicit account selection is a required gate. Round-robin/failover remains
  disabled for the first real account test.
- Sol availability is derived from the authenticated account's `plan_type` and
  model registry; it is not hard-coded into every account menu.
- A quota UI is deferred. EasyCLIProxyAPI may be evaluated after the core
  passes; every quota value must say provider-reported, proxy-observed,
  estimated or unknown.

## Rollback

Stop and remove only the ignored challenger runtime. Continue using the current
CCR launcher and project-local account state. The source checkout can be deleted
without affecting normal operation because tracked metadata is sufficient to
recreate the exact review point.
