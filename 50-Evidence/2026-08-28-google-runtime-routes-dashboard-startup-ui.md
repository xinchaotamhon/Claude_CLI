# Evidence — Google runtime routes, hidden dashboard start and control-room UX

- Date: 2026-08-28
- Scope: Google model launch, dashboard startup lifecycle, route-selection UX,
  release-card truthfulness and durable handoff
- Secret boundary: no password, 2FA, token, auth JSON, account email, ignored
  `setting.json`, provider request body or Claude transcript was printed or
  copied into tracked evidence

## Accepted architecture and invariants

- Claude Code remains the only interactive coding harness.
- Codex and custom APIs continue through the pinned project-local CCR runtime.
- Google routes bypass CCR. Each authenticated Google slot receives one
  hash-verified CLIProxyAPI `7.2.144-local.1` process bound only to its
  deterministic loopback port (`18401` through `18450`).
- Every launched terminal receives its route, model, local endpoint and common
  project-local Claude home through process-scoped environment only. It does
  not write an external Codex/Claude profile or resolve an agent binary from
  `PATH`.
- Automatic fallback and hidden account rotation remain disabled. Catalog or
  quota refresh failure does not silently choose another account.
- Account deletion stops only the exact verified slot proxy and moves the
  account/cache to recoverable project-local trash before removing the card.

## Google catalog root cause and repair

- OAuth and quota collection were already working, but dashboard route creation
  read only CCR routes. Therefore a Google card could truthfully show catalog
  models while the route palette exposed none.
- The server now intersects each slot's sanitized live catalog with a tracked
  runtime-compatibility manifest. That manifest is generated from and checked
  against the exact nested CLIProxyAPI Antigravity model registry used to build
  the hash-pinned binary; screenshot labels are not promoted as capabilities.
- The card continues to display all 24 discovered catalog entries. The route
  palette exposes only the 13 entries proved present in the pinned runtime
  registry. Future catalog models remain visible but non-routable until a
  reviewed CLIProxyAPI update, reproducible rebuild and gate run promote them.
- `tools/google_project_runtime.ps1` validates the project root, slot, exact
  binary SHA-256, account root and process identity; creates a current-user-only
  runtime config/client key; starts a hidden per-slot proxy; and waits a bounded
  interval for its asynchronous `/v1/models` registry.
- A bounded owner-profile verification exposed
  `gemini-3.7-flash-high` on `127.0.0.1:18401` and then stopped the test proxy.
  This read only the local model registry and sent no provider model request.
- The actual sanitized dashboard route summary contained 31 routes total and
  13 Google routes. The 13 Google route IDs included Claude, Gemini and GPT-OSS
  entries from the pinned runtime manifest. First real model inference remains
  an owner action and is not claimed by this evidence.

## Startup terminal root cause and repair

- The blank terminal shown after double-clicking `DASHBOARD.bat` was not a
  Claude terminal and not the router. The BAT itself synchronously waited for a
  PowerShell bootstrap process while command echo was disabled.
- The BAT now starts one hidden detached bootstrapper and exits immediately.
  Successful dashboard start leaves no blank owner console. A genuine startup
  failure is retained at ignored `.runtime/dashboard/startup-error.log` and is
  opened in Notepad, so hiding the bootstrap does not hide diagnosis.
- User-triggered model launches still create exactly one visible Claude
  terminal and retain the existing PID/lifecycle acknowledgement contract.

## Control-room UX and update truthfulness

- The route selector is now a provider/account-grouped command palette with
  search, `Ctrl/Cmd+K`, arrow navigation, Enter, Escape, click-outside close,
  visible focus and focus return. Searching `Google AI Pro 1` produced one
  account group with 13 selectable model rows instead of one group per model.
- Long account catalogs and secondary diagnostics use progressive disclosure;
  account/provider filters and compact status cards reduce the initial page
  density. The layout remains responsive and uses no CDN or runtime UI library.
- Fluent UI and Carbon were pattern references only (tokens, hierarchy,
  keyboard/focus behavior and progressive disclosure). No source, component,
  asset or dependency from those repositories was copied into this project.
- Update cards now compare versions instead of treating every unequal version
  as newer. On 2026-08-28 the live view correctly reported two candidates:
  CCR `3.0.22` and Codex helper `0.150.1`; local Claude `2.1.250` and local
  CLIProxyAPI `7.2.144` were not falsely labeled behind older published tags.

## Verification completed before the cumulative gate

- Dashboard server syntax/self-test: pass, including Google catalog/runtime
  intersection and semantic version ordering.
- Production UI build: pass; tracked hashed CSS/JavaScript regenerated.
- `tools/google_project_runtime.ps1 -Action SelfTest`: pass.
- Owner-profile Google runtime verification: pass on port `18401`; no model
  inference request.
- Focused gates `claude.local-dashboard` and
  `claude.dashboard-account-management`: pass in run
  `20260828T082346Z-556b8c64`.
- The first cumulative run exposed one stale source-policy verifier that still
  required the pre-runtime `pilot` metadata. After updating that verifier to
  the active Google-runtime contract, all 22 enabled smoke gates passed in
  owner-profile run `20260828T084103Z-4ba632f2`.
- Live browser QA: dashboard connected; router running; 8 ready accounts;
  31 routes; Google card reported 24 catalog and 13 routable models; grouped
  Google search returned 13 options; update rail reported two candidates.

## Known unknowns and rollback

- A first real Google model/tool loop has not been sent by this implementation
  pass. Provider availability, entitlement and future catalog stability remain
  unknown until the owner launches one normal prompt.
- Roll back Google launch by reverting the server route intersection,
  dispatcher branch, runtime helper and manifest while retaining OAuth/catalog
  and quota state. No account deletion is needed for code rollback.
- Roll back the dashboard UX/static build from Git. Roll back hidden startup by
  restoring the preceding BAT/starter pair; the error log remains ignored.
- Runtime/auth/session directories are ignored and were not added to Git.

## CLOVER contribution disposition

- CLOVER was read only as a governance/resource router. No project code or
  private runtime data was copied into it.
- Three sanitized reusable candidates were recorded locally in
  `80-Handoffs/CLOVER_CONTRIBUTION_PROPOSAL.md`: capability intersection before
  promotion, hidden-success/visible-failure Windows launch, and recoverable
  account/session lifecycle. They remain proposals requiring owner review.
