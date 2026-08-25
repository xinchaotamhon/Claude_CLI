---
last_verified: 2026-08-25
verified_by: cli-proxy-api-phase-1-offline-pilot
status: active
---

# Current State

## Verified Facts

- Root is `D:\mydata\new-git-3\claude_CLI-V`. Project-local
  `bin/claude.exe` remains the only interactive coding harness and reports
  Claude Code `2.1.241`.
- Router is project-local CCR `3.0.21` on Node `v24.12.0`; reviewed source is
  nested branch `claude` at fork commit
  `ffc823b683861ad3f86c8dd38c0dbe61eef62f6c`, based on upstream commit
  `1347c868b493728a31c76098459584e0fcc23940`. The fork commit is pushed to
  `xinchaotamhon/claude-code-router_proxy`.
- The fork and pinned operational runtime now have the same bounded local
  patch: provider-only startup skips external Claude App/profile sync, and the
  gateway config-acceptance timeout is configurable only from 5 to 60 seconds.
  `tools/apply_router_local_patches.ps1` reapplies the exact version-locked
  runtime patch after explicit reconstruction.
- Parent Git is on branch `claude`, based on the remote `main` commit that
  contains only `LICENSE`; binaries, dependencies, ignored `setting.json`,
  `.ccr-local` and nested source repositories remain excluded.
- `RUN_CLAUDE.bat` is profile selection only. It validates and synchronizes
  changed `setting.json` providers into CCR SQLite through authenticated
  loopback RPC, preserving UI/account providers.
- `SIGN_ACCOUNT.bat` option `[1]` no longer reads the Windows/global Codex App
  login or resolves a `codex` executable from `PATH`. It runs only
  `provider_router/codex-login-runtime/codex.exe login`.
- The local login helper reports `codex-cli 0.149.0-alpha.4.1`; SHA-256 is
  `73d6d4a082a7cad601a446a45b1b3fa9b77aff9d3996052b74d9003d7947d515`.
  Tracked `provider_router/CODEX_LOGIN_SOURCE.json` records its provenance and
  policy; the 297 MB binary is Git-ignored.
- Every new Codex account receives a separate home under
  `provider_router/.ccr-local/codex-accounts`. Its generated `config.toml`
  forces `cli_auth_credentials_store = "file"` and
  `forced_login_method = "chatgpt"`; both `CODEX_HOME` and
  `CODEX_SQLITE_HOME` point to that account home only during login.
- Password/2FA are handled by the official browser page. The wrapper checks for
  local `auth.json` existence but does not parse or print it. CCR staging is
  guarded, restored and removed in `finally`.
- Owner-observed browser login reached `Successfully logged in`. CCR's import
  then exposed only its built-in fallback `gpt-5-codex`; a real Claude request
  proved that route unusable for this ChatGPT Free account with upstream HTTP
  400. This was a stale fallback/model-entitlement failure, not an OAuth-login
  failure.
- Bounded direct gateway checks proved `gpt-5.6-terra` and `gpt-5.6-luna`
  complete successfully for the imported account. `gpt-5-codex` and
  `gpt-5.6-sol` returned the same unsupported-account HTTP 400 and are hidden.
  CCR's generic connectivity check falsely accepted Sol, so the real
  Claude-compatible gateway result is authoritative for this policy.
- `SIGN_ACCOUNT.bat` action `[R]` refreshes/tests the current Codex model
  candidates without another browser login. Each retained model is written as
  a separate account route. RUN currently exposes one Terra route and one Luna
  route for `codex_free_1`.
- Account route IDs reload with slug-safe `_` and `.` punctuation. The
  multi-profile reader now enumerates each route instead of wrapping all routes
  as one `System.Object[]`. Re-running the same account label still resumes a
  valid unfinished local auth home without repeating browser/2FA.
- Owner then observed that selecting the visible route failed on a generic CCR
  exit code. A bounded local diagnostic observed gateway health unavailable
  before `start --gateway`, command exit 1, then HTTP 200 health immediately
  afterward. The launcher now treats the verified service postcondition as the
  authority for idempotent startup while retaining fail-closed identity/health
  checks before DPAPI access.
- A subsequent owner run exposed the deeper gateway condition: management was
  verified, but the gateway child did not accept runtime config inside CCR's
  fixed 5000 ms IPC deadline. `Ensure-Router` now retries at most twice only
  when authenticated local status reports that exact timeout; every other
  failure remains fail-closed before DPAPI access.
- A real end-to-end menu check selected saved route `[1]` and launched the
  project-local Claude binary with `--version`, observing Claude Code `2.1.241`
  and exit 0 without a model request. The test service was stopped afterward.
- `tools/install_codex_login_runtime.ps1` is an explicit project-scoped repair
  path using OpenAI's standalone installer. Normal RUN/SIGN startup never
  downloads or updates software.
- Gateway remains `127.0.0.1:3456`, management `127.0.0.1:3458`; proxy,
  system proxy, network capture, request logs and built-in Codex agent routing
  remain disabled.
- The owner observed Codex App renamed to `Claude Code Router` with Usage
  absent. Source and fixed-marker inspection proved that a CCR Codex agent
  profile configured as `System default` plus `CLI & APP` had written the
  project gateway into external `~/.codex/config.toml`.
- The external Codex config has been restored from CCR's clean original
  snapshot. Its SHA-256 now equals the snapshot, and CCR markers, provider name,
  loopback URL and project takeover marker are absent. The running Codex App may
  cache the previous provider; owner visual verification after a full restart
  remains pending.
- After explicit owner authorization, exactly seven identified CCR files and
  the identified `.claude-code-router` directory were deleted from the external
  `.codex` directory. No wildcard was used, all eight targets are absent, and
  the active config SHA-256 remains
  `281FBC9C6183FBA5CDED167A4A4552F53E17A230CD27DBA344D43D9076C92671`.
- CCR is now provider-gateway-only. Normal project flows remove every CCR agent
  profile before save, apply takeover cleanup, and do not expose CCR agent UI or
  `System default` / `CLI & APP`. API providers use ignored `setting.json`;
  account login remains project-local through `SIGN_ACCOUNT.bat`.
- The pre-change baseline passed all 8 enabled smoke gates in
  `20260824T172947Z-7cb886ff`. The new sanitized fixture failed before the fix
  in `20260824T173222Z-32aa653f`; both focused gates passed after the reader fix
  in `20260824T173312Z-a0cee41d` and again after extending compatibility through
  Claude mode-path creation in `20260824T173807Z-f32e0a0f`. No gate read real
  `setting.json` or auth, opened browser login, called a provider or consumed
  model quota.
- The 2026-08-25 CLOVER entry-router update was reviewed by exact supplied path
  and SHA-256. Only bounded navigation/authority patterns were adopted; this
  project has no runtime or continuation dependency on CLOVER.
- All 8 enabled smoke gates passed on the integrated code and documentation in
  `20260824T173932Z-43d5c46b`.
- All 8 enabled smoke gates passed after the verified-start repair in
  `20260824T175012Z-6f2f15a6`.
- All 8 enabled smoke gates passed on the final cold-start recovery and memory
  update in `20260825T041235Z-3565decb`. The DPAPI self-test also passed under the owner's
  real Windows profile; an earlier sandbox-only failure is retained as evidence
  of the test environment boundary, not a launcher regression.
- All 9 enabled smoke gates passed after the external Codex App isolation
  repair in `20260825T043650Z-959db717`, including the new
  `claude.external-app-isolation` gate and Windows DPAPI self-test.
- All 9 enabled smoke gates passed after the Codex Free model-route repair and
  exact external-artifact cleanup in `20260825T052438Z-21e21f26`, including the
  owner-profile DPAPI self-test and multi-model account-route regression.
- All 9 enabled smoke gates passed again under the owner Windows profile in
  `20260825T125429Z-b9904aa4` before the first parent-repository commit. A
  preceding sandbox run failed only the DPAPI round trip with
  `Cryptography_DpApi_ProfileMayNotBeLoaded`; the same self-test passed outside
  the sandbox and no project source changed between the two observations.
- Four owner-supplied architecture/security reports were read and hash-recorded.
  Their useful common direction is a CLIProxyAPI-family candidate, but several
  report claims were unsupported, stale or demonstrably fabricated. No report
  is adopted as authority. CLIProxyAPI core is the proposed bounded challenger;
  EasyCLIProxyAPI is a later UI candidate, while ZeroLimit and Quotio Desktop
  remain comparison candidates only.
- CLIProxyAPI Phase 0 source intake is complete. The ignored independent
  checkout is on local branch `claude` at tag `v7.2.141`, commit
  `dc3c3b1ec3ed04bb0917e76451eaf98c6842674d` and tree
  `320d4056873d7e8fd036c568db493acc0e565dc7`. Tracked
  `router_challenger/SOURCE.json` and an offline verifier preserve the exact
  review point; the source has not been built or run.
- The candidate registers Anthropic `POST /v1/messages`, stores Codex
  `plan_type`, uses different embedded Free/Plus model catalogs, and filters
  candidate credentials by the requested model. Its current catalog includes
  Terra/Luna for Free and Sol/Terra/Luna for Plus/Pro/Team.
- Multi-account strategies are round-robin, weighted round-robin and
  fill-first. Optional session affinity keeps a Claude session/model/provider
  on one account and fails over when that auth becomes unavailable. Management
  can disable individual auths, but a fixed-account user flow is not yet proved.
- CLIProxyAPI is not safe to run unchanged for this project. Defaults bind all
  interfaces and place JSON auth under `~/.cli-proxy-api`; `--local-model`
  stops model-catalog updates but not the unconditional Antigravity version
  request to Google Cloud Run. A source patch and absolute local paths are
  required before an offline pilot.
- Core quota surfaces are proxy-observed request/cooldown state, not proved
  provider-reported 5-hour or weekly subscription limits. The core alone does
  not meet the owner's quota-dashboard requirement.
- The first post-intake run passed 9/10 gates and failed only because the memory
  auditor scanned an example key string inside the ignored candidate README.
  After adding the exact candidate checkout to the same exclusion set as the
  existing CCR source checkout, all 10 enabled smoke gates passed in
  `20260825T133632Z-91288459`.
- CLIProxyAPI Phase 1 offline pilot is built but not promoted. The nested
  `claude` branch has one bounded update-isolation patch at commit
  `d3177d8ecd1c99d566fbe6e6ca1ba19a2be7ddc4`, directly above audited upstream
  `v7.2.141`. Under `--local-model`, both remote catalogs and the Antigravity
  manifest updater are suppressed; `go test ./cmd/server` passed.
- Official Go `1.26.7` is staged only under ignored `vendor/go`; dependencies,
  build cache and binaries remain under this project. The reproducible
  challenger binary SHA-256 is
  `830e9ff8f4526ec5d7ca9f620dc26881dd854023edea1b33452fcc3de17ad17e`.
- `RUN_CHALLENGER_PILOT.bat` is a separate offline-only surface and does not
  launch a real provider session. Its deterministic fixture proved loopback
  listeners, current-user-only auth ACL, no observed external connection,
  Claude non-stream/SSE/tool-result translation, verified stop/restart and
  measured startup/restart below 0.6 seconds. CCR and `RUN_CLAUDE.bat` remain
  the active champion.
- The secret-free usage contract now requires Google AI Pro to expose separate
  `gemini_models` and `claude_gpt_models` weekly branches. Five-hour windows are
  optional; unknown/unavailable values require null measurements plus a reason.
  Ten validator tests passed. No live quota adapter exists yet.
- Dashboard architecture is separated from CCR: a future local control plane
  owns login, account/model selection, quota provenance and finite fallback;
  CCR remains rollback only. EasyCLIProxyAPI `v0.2.61` was pinned as an ignored
  source reference but is blocked: no license grant exists in the tagged tree,
  and source includes update downloads, global Codex/Claude discovery and
  configuration, tray/autostart and auth-file inspection paths. It was not
  built or run and no code may be copied into this project without permission.
- The fallback contract was corrected after review so each account owns its
  quota observation. Its example uses two distinct Google Pro accounts; known
  five-hour depletion blocks eligibility even with weekly quota, while unknown
  five-hour data permits only signal-driven reactive fallback. Output/tool side
  effects stop retries. Thirteen account-aware fallback tests passed.
- All 14 enabled smoke gates passed under the owner Windows profile in
  `20260825T151944Z-d9df7999`: existing CCR/DPAPI/account/App isolation, pinned
  challenger source, split usage contract, account-aware fallback, offline
  protocol pilot and blocked dashboard-source boundary. The pilot left no PID
  or session directory and made no provider/OAuth request.

## Blockers

- Phase 2 live-account work is not approved or proved. The challenger must not
  open OAuth, read existing CCR accounts, call a real provider or replace the
  normal launcher until explicit account selection, credential ACL/lifecycle
  and provider-specific quota provenance have focused gates.
- Owner visual verification after reopening Codex App remains.

## Unknowns

- Browser login, route display and real Terra/Luna inference are proved for one
  imported account. Token refresh, quota exhaustion and explicit switching
  among two or more imported accounts remain unproved until owner-run checks.
- 9router appears capable of Anthropic-compatible routing and automatic Codex
  account fallback, but its project-local packaging, inspected OAuth import
  path and direct fixed-account selection remain unverified. It is not active.
- API keys in ignored `setting.json` are plaintext by owner choice. Git protects
  against normal commit, but Windows-user access and backups remain an owner
  responsibility.
- CLIProxyAPI real OAuth refresh, mixed Free/Plus routing, explicit account
  selection, provider-reported quota and full Claude tool-loop fidelity remain
  unproved. EasyCLIProxyAPI global-agent/update isolation remains unreviewed.
- The source supports per-plan model catalogs, but actual Sol/Terra/Luna
  entitlements remain provider-controlled and require a bounded owner-run test.
- Filesystem/runtime independence does not remove provider dependencies:
  browser login and inference still use OpenAI/Google/other network services.

## Evidence

- [Folder-local Codex login evidence](../50-Evidence/2026-08-24-folder-local-codex-login.md)
- [Model selection retry evidence](../50-Evidence/2026-08-24-account-model-selection-retry.md)
- [Account route-ID compatibility evidence](../50-Evidence/2026-08-25-account-route-id-compatibility.md)
- [Verified CCR start postcondition evidence](../50-Evidence/2026-08-25-verified-ccr-start-postcondition.md)
- [CCR cold-start recovery evidence](../50-Evidence/2026-08-25-ccr-cold-start-recovery.md)
- [External Codex App isolation repair](../50-Evidence/2026-08-25-external-codex-app-isolation-repair.md)
- [Codex Free model-route repair](../50-Evidence/2026-08-25-codex-free-model-route-repair.md)
- [Prior snapshot-import evidence (superseded)](../50-Evidence/2026-08-24-project-local-codex-account-import.md)
- [CCR integration evidence](../50-Evidence/2026-08-24-claude-code-router-integration.md)
- [Machine-readable gate events](../50-Evidence/events.jsonl)
- [Current decision](../60-Decisions/ADR-2026-08-24-folder-local-codex-login-homes.md)
- [Router candidate research](../50-Evidence/2026-08-25-router-candidate-research.md)
- [CLIProxyAPI Phase 0 source audit](../50-Evidence/2026-08-25-cli-proxy-api-phase-0-source-audit.md)
- [CLIProxyAPI challenger decision](../60-Decisions/ADR-2026-08-25-cli-proxy-api-challenger.md)
