---
last_verified: 2026-08-27
verified_by: portable-session-account-update-and-kiro-route
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
- `DASHBOARD.bat` is the only owner-facing entry. Its launch action validates
  and synchronizes changed `setting.json` providers into CCR SQLite through
  authenticated loopback RPC, preserving account providers. The former
  command-line launcher is retained only as
  `tools\RUN_CLAUDE_TECHNICAL.bat` for bounded rollback/diagnostics.
- Dashboard terminal dispatch now uses a hidden, bounded dispatcher to create
  exactly one visible PowerShell terminal. The browser receives success only
  after that terminal writes a project-local lifecycle acknowledgement; model
  launches wait for the router wrapper's later `claude_starting` signal.
- A mutex-guarded project-local supervisor restarts only `dashboard/server.mjs`
  after an unexpected exit. The ignored browser bootstrap token persists in
  `.runtime/dashboard/dashboard-session.json` for at most 30 days, so an
  already-open page can reconnect after a bounded restart without reopening
  `DASHBOARD.bat`. PowerShell 7+ is an explicit host prerequisite for the safe
  argument-list dispatcher and supervisor.
- Dashboard launches now use a common ignored `.runtime/claude-home`, UUID and
  optional friendly name. The ignored session index supports **Mở lại** via
  Claude's `--resume`; legacy per-route JSONL files are copied once without
  reading transcript content, overwriting or deleting the source. Dashboard
  lists only IDs with a real JSONL transcript and allows **Mở lại bằng** any
  currently enabled route; failed starts no longer create visible phantom
  sessions.
- Codex login is two-phase when CCR is already serving Claude: official browser
  auth is saved to its project-local account home, while CCR provider/config
  mutation stays pending until active sessions close. Dashboard recovery then
  completes the import without another login while auth remains valid.
- The CLIProxyAPI nested `claude` branch now has a third reviewed patch at
  `bcc28e6133a38b2185e04c631c9e662dbf28e9c3`: Google OAuth requests an account
  chooser and accepts a bounded optional email `login_hint`. The rebuilt binary
  SHA-256 is `322468f600e7e3f85034a964c4f2852bcd87da0bbfbcf82fd572e53eb4d3d95c`.
- The dashboard exposes explicit release checks for Claude, CCR, Codex and
  CLIProxyAPI plus local reviewed/build dates. Network is used only when the
  owner presses the button; no source fetch, merge or replacement occurs.
- `DEPENDENCIES.lock.json`, `docs/RECONSTRUCT_ON_NEW_MACHINE.md` and
  `tools/audit_reconstruction.ps1` define fresh-machine reconstruction. Runtime,
  auth, DPAPI, keys and sessions remain intentionally outside Git.
- Owner-supplied Kiro Pix4K test access is configured only in ignored
  `setting.json`. Authenticated catalog discovery returned HTTP 200 and includes
  both `claude-opus-4.7` and `claude-opus-5`. A direct non-sensitive completion
  probe first received a transient HTTP 429 and one bounded retry was accepted
  with 2xx; a full Claude CLI -> CCR -> Kiro `claude-opus-5` smoke then returned
  exact text `OK` with exit 0. `/quota` is
  an HTML provider page while `/quotaBase` is not an API endpoint. Dashboard
  can open that same-host HTTPS quota page without placing the key in its URL.
- All 19 enabled smoke gates passed under the owner Windows profile in
  `20260826T190051Z-3f7f3930`, including the new acknowledged-action,
  transcript-backed-session, supervised-restart, selectable-resume-route and
  concurrent-update gate. The gate run itself made no provider/model request.
- Live lifecycle evidence observed a Codex Free account terminal acknowledge in
  about 3.0 seconds with an exact verified helper PID; the test terminal was
  then closed. Killing the exact verified dashboard Node process caused the
  supervisor to restore service with a new PID in about 1.7 seconds, and the
  pre-existing browser cookie still authorized `/api/state`. Concurrent release
  checking completed all four components in about 0.95 seconds.
- Dashboard ready state now records the exact `server.mjs` SHA-256. On the next
  `DASHBOARD.bat` click after a reviewed source update, startup stops/replaces
  only the independently verified outdated dashboard Node process; router and
  running Claude terminals are not stopped.
- A live owner-profile start matched the ready-state hash, loopback health hash
  and current server file hash, then returned five account/provider entries,
  seven routes and five resumable sessions without returning a secret.
- The pre-dashboard account action formerly exposed as `SIGN_ACCOUNT.bat [1]` no longer reads the Windows/global Codex App
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
- The retained technical account menu action `[R]` refreshes/tests the current Codex model
  candidates without another browser login. Each retained model is written as
  a separate account route. Dashboard currently exposes Terra and Luna for
  `codex_free_1`, `codex_free_2` and `codex_free_3`.
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
  path using OpenAI's standalone installer. Normal dashboard startup never
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
  account login remains project-local through the dashboard's reviewed helpers.
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
- `tools\RUN_CHALLENGER_PILOT_TECHNICAL.bat` is a separate offline-only surface and does not
  launch a real provider session. Its deterministic fixture proved loopback
  listeners, current-user-only auth ACL, no observed external connection,
  Claude non-stream/SSE/tool-result translation, verified stop/restart and
  measured startup/restart below 0.6 seconds. CCR behind `DASHBOARD.bat`
  remains the active champion.
- The secret-free usage contract now requires Google AI Pro to expose separate
  `gemini_models` and `claude_gpt_models` weekly branches. Five-hour windows are
  optional; unknown/unavailable values require null measurements plus a reason.
  Ten validator tests passed. This statement was later superseded by the
  original dashboard's live Codex adapter; Google remains pending login/proof.
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
- Owner authorized Phase 2 account onboarding but clarified that switching the
  Codex App account because its five-hour quota is exhausted is outside this
  project. No global Codex App account-switching surface was added.
- The account contract now has exactly seven secret-free slots: the existing
  `codex_free_1`, two additional Free accounts, one Plus account and three
  Google AI Pro accounts. Codex Free candidates are Terra/Luna; Plus candidates
  are Sol/Terra/Luna. Each Google account preserves separate `gemini_models`
  and `claude_gpt_models` usage groups. Automatic fallback remains off by
  default.
- The underlying account helper distinguishes Codex Free and Plus before browser
  login. The declared plan selects a bounded candidate set and is stored only
  as non-secret local metadata; actual entitlement still requires the existing
  minimal route check. Existing accounts without this metadata remain Free for
  backward compatibility.
- The challenger nested branch now has two bounded commits above audited
  upstream: updater isolation at `d3177d8ecd1c99d566fbe6e6ca1ba19a2be7ddc4`
  and IPv4-loopback-only Antigravity OAuth callback binding at
  `3a3df12d068ac3a3bff2712db168ed1a7d31190a`. Patched tree is
  `37209cb0f5ba9a60e45a12742a8208fa7f49928d`; both patches are tracked and
  hash-verified by the reconstruction path.
- Rebuilt challenger version `7.2.141-local.2` has SHA-256
  `40f05398a6abac44698c2ecfa1d748869f37b2950ee2b98a1a58c97b4d4105ea`.
  `go test ./sdk/auth ./cmd/server` passed. No real OAuth/provider request was
  made during build or focused verification.
- The Google account menu allocates ignored project-local slots dynamically
  from 1 through 50. Callback port is deterministically `51120 + slot`, remains
  loopback-only and is protected by current-user-only ACL checks. It verifies
  source policy and binary hash before invoking the official provider browser
  flow, does not parse auth JSON, and refuses to overwrite an occupied or
  incomplete slot.
- RUN now renders routes first and starts a credential-free router warmup in a
  hidden project-local PowerShell process. The already-running verified fast
  path measured 987 ms. Selection remains fail-closed: exact process,
  loopback and health verification still precede any DPAPI client-key read.
- Focused offline verification passed: 12 account-contract tests, 7 warm-start
  tests, Codex import-flow verification, Google account-flow verification and
  exact two-patch challenger-source verification. JSON metadata also parsed.
- The first 17-gate cumulative run `20260825T163959Z-1811586c` correctly
  rejected an unlisted project-local wrapper invocation and encountered the
  known sandbox-only DPAPI profile limitation. The verifier was narrowed to the
  exact Google wrapper command; no process wildcard was added. Re-running all
  17 gates under the owner Windows profile passed in
  `20260825T164115Z-8fc5f438`; after updating state/evidence, all 17 passed
  again in final cumulative run `20260825T164233Z-42021e6c`.
- `DASHBOARD.bat` is now the single owner-facing entry point. It starts the
  original project-local dashboard with `provider_router/runtime/node.exe`,
  binds only `127.0.0.1:18320`, bootstraps an HttpOnly/SameSite cookie and
  rejects unauthenticated or cross-origin API calls. Built browser assets are
  tracked; normal double-click startup performs no package install or build.
- The root now contains only `DASHBOARD.bat`. The former SIGN alias was removed;
  technical/rollback launchers were moved under `tools/` so normal account,
  quota, route/model and terminal UX has one visible entry.
- Dashboard account discovery is dynamic for imported Codex, pending Codex,
  Google and custom API state. Google slots are allocated on demand from 1 to
  50 with deterministic loopback callback ports. Codex Free/Plus and each
  Google slot launch the existing reviewed browser-login helpers in a separate
  visible terminal; password and 2FA stay on the provider page. Failed account
  actions keep the terminal open so the error remains visible.
- Selecting a dashboard route launches a new terminal by exact allowlisted
  profile ID. Each terminal receives its route through process-local
  environment. Multiple terminals may use the same or different routes; two
  terminals on one account share that provider account's quota.
- The local server returns no token, email or provider account ID to the
  browser. Codex quota now uses the official local app-server JSONL method
  `account/rateLimits/read` in each exact account `CODEX_HOME`; dashboard code
  no longer parses `auth.json`. A live bounded read for `codex_free_1` returned
  plan `free`, one 43,200-minute monthly window at 1% used, no secondary window,
  no individual limit and zero reset credits. The dashboard therefore shows
  monthly 99% for this account and does not fabricate a weekly value. It
  refreshes ready account snapshots every five minutes and never redeems reset
  credits automatically.
- Google quota state always keeps separate `gemini_models` and
  `claude_gpt_models` groups. The adapter reads a completed project-local slot,
  queries the Antigravity quota surface and leaves missing/unrecognized groups
  `unknown`; no Google account was logged in or queried during this change.
- Custom API providers show `unknown` unless a provider-specific quota adapter
  exists. Local proxy request counts are not presented as subscription quota.
  Automatic fallback remains off and was not promoted into dashboard actions.
- The implementation is original code. The unlicensed EasyCLIProxyAPI checkout
  remains inspect-only and ignored; none of its source was copied, built or
  executed. The generated Sites hosting file and Cloudflare packages were
  removed because this dashboard is intentionally localhost-only.
- Focused live smoke proved schema 1, five displayed account/provider entries,
  two current Codex routes, Claude `2.1.241`, CCR `3.0.21`, authenticated state,
  successful Codex quota refresh and rejection of an unknown route with HTTP
  400. An unauthenticated state request was also rejected.
- The actual `tools/start_dashboard.ps1` double-click flow also passed under the
  owner Windows profile. Ready PID `1588` was observed running the exact
  project-local Node executable with the exact `dashboard/server.mjs` command,
  loopback-only state was true and the independent health instance ID matched.
  The PID is volatile evidence only; future starts must reverify identity.
- The pre-change sandbox baseline `20260826T002435Z-578682a6` passed 15/17
  gates. `foundation.memory-routing` exceeded its 30-second timeout and could
  not terminate the child under sandbox ACL; `claude.router-menu-selftest`
  hit the known sandbox-only unloaded DPAPI profile. The previous owner-profile
  baseline remained 17/17 in `20260825T164233Z-42021e6c`.
- After pruning ignored directory trees before filesystem traversal, the memory
  audit dropped from timeout to about 0.2 seconds. All 18 enabled smoke gates
  then passed in `20260826T012244Z-b98e0bf3` under the owner Windows profile.
- After exact PID/instance verification and the provider-credit UI were added,
  all 18 enabled smoke gates passed again on the final artifact in
  `20260826T012651Z-4331fd55`.
- After the quota/account/terminal/root cleanup, all 18 enabled gates passed
  under the owner Windows profile in `20260826T071307Z-d22080f6`. That
  intermediate live state showed `codex_free_2` incomplete. The exact recovery
  path subsequently completed its already-persisted provider without another
  browser login and created Terra/Luna routes. Official app-server reads then
  reported monthly remaining 99% for `codex_free_1` and 100% for
  `codex_free_2`; neither account returned a weekly bucket. The second account
  returned reset timestamp `2026-09-25T07:52:22Z` after external credential
  environment variables were removed from the app-server child.
- All 18 enabled gates passed again after the persisted-account recovery fix
  under the owner Windows profile in `20260826T075259Z-7bc77059`. This run
  includes DPAPI, external Codex App isolation, Codex import recovery, dynamic
  Google onboarding, fallback contracts and the local dashboard gate.

## Blockers

- The Phase 2 wrappers and offline gates are ready, but real Google OAuth has
  not been completed. The owner must choose **Thêm tài khoản Google** from
  `DASHBOARD.bat` and complete the official
  browser password/2FA flow. This project must never request those secrets.
- Google accounts are not yet promoted as Claude routes. After interactive
  login, refresh both quota groups and run one bounded account/model route proof
  before wiring a Google route into the normal launch selector.
- Owner reported that Codex App operates normally again. Its separate account
  rotation/quota workflow remains deliberately outside this project.

## Unknowns

- Browser login, route display and official current-quota retrieval are proved
  for both imported Free accounts. Real Terra/Luna inference remains proved for
  `codex_free_1`; an owner-run inference from `codex_free_2`, expired-token
  refresh, quota exhaustion and automatic fallback remain unproved.
- 9router appears capable of Anthropic-compatible routing and automatic Codex
  account fallback, but its project-local packaging, inspected OAuth import
  path and direct fixed-account selection remain unverified. It is not active.
- API keys in ignored `setting.json` are plaintext by owner choice. Git protects
  against normal commit, but Windows-user access and backups remain an owner
  responsibility.
- CLIProxyAPI real OAuth refresh, mixed Free/Plus routing, Google quota response
  shape and full Claude tool-loop fidelity remain unproved. Codex quota uses an
  official app-server method whose upstream account policy and returned buckets
  can still change; the dashboard must degrade to `unknown`/reauthentication
  instead of failing launch.
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
- [Phase 2 account onboarding and warm start](../50-Evidence/2026-08-25-phase-2-account-onboarding-and-warm-start.md)
- [CLIProxyAPI Phase 0 source audit](../50-Evidence/2026-08-25-cli-proxy-api-phase-0-source-audit.md)
- [CLIProxyAPI challenger decision](../60-Decisions/ADR-2026-08-25-cli-proxy-api-challenger.md)
- [Portable session/account/update repair](../50-Evidence/2026-08-26-portable-session-account-update-repair.md)
- [Portable session decision](../60-Decisions/ADR-2026-08-26-portable-sessions-and-deferred-account-import.md)
