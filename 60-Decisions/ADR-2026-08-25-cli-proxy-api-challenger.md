# ADR — CLIProxyAPI remains a bounded challenger

- Date: 2026-08-25
- Status: accepted for Phase 1 offline pilot; not promoted
- Owner intent: one project-local Claude CLI harness with provider/model routing,
  multiple subscription accounts and clearly labelled quota information

## Decision

Retain CCR as the active rollback champion. Keep CLIProxyAPI `v7.2.141` as an
ignored nested source repository on local branch `claude`, with exact tracked
provenance and a bounded update-isolation patch. Phase 1 may build and run only
the deterministic loopback fixture through `RUN_CHALLENGER_PILOT.bat`. Do not
authenticate, call a real provider or wire it into `RUN_CLAUDE.bat` until a
later owner-approved phase proves live-account controls.

## Why

CLIProxyAPI has the strongest source-level fit found so far: Anthropic
`/v1/messages`, Codex/Claude/Google OAuth, API-key providers, plan-aware model
catalogs, per-model account filtering, cooldown handling and session affinity.
It also has unacceptable defaults for this project: all-interface binding,
user-home auth storage, plaintext JSON credentials and an unconditional
Antigravity update request. Its core usage counters are not provider-reported
5-hour/weekly quota.

## Consequences

- Phase 1 stages Go and all runtime/cache paths inside this project and does not
  consume provider quota.
- `--local-model` is locally patched to suppress the Antigravity updater as well
  as remote model catalogs; build/source identities are pinned and reproducible.
- Explicit account selection is a required gate. Round-robin/failover remains
  disabled for the first real account test.
- Sol availability is derived from the authenticated account's `plan_type` and
  model registry; it is not hard-coded into every account menu.
- A live quota UI is deferred. Its contract now requires separate Google Pro
  `gemini_models` and `claude_gpt_models` weekly branches; five-hour data is
  optional. Every value must say provider-reported, proxy-observed, estimated
  or unknown.

## Rollback

Stop and remove only the ignored challenger runtime. Continue using the current
CCR launcher and project-local account state. The source checkout can be deleted
without affecting normal operation because tracked metadata is sufficient to
recreate the exact review point.
