---
last_verified: 2026-08-28
verified_by: claude-2.1.250-and-cliproxy-7.2.144-upgrade
status: active
---

# Known Failures

## ccr.source-test-external-codex-takeover — fixed/contained 2026-08-28

- Symptom: Codex App's account menu again displayed **Claude Code Router** after
  a CCR `3.0.22` source review, despite normal project launchers being isolated.
- Root cause: the upstream core unit suite was run directly while the real
  project router and Codex App were live. One upstream test reused the healthy
  router and exercised global profile synchronization without the project's
  provider-only environment. The old isolation gate covered normal launchers,
  not developer/source-test execution.
- Repair: restore `C:\Users\vhiep\.codex\config.toml` from the matching
  `config.toml.ccr-original` snapshot (verified SHA-256 before copy), then remove
  exactly six top-level CCR catalog/config/backup artifacts. A post-repair scan
  observed zero CCR artifacts and zero CCR markers in the external config.
- Prevention: `tools/run_ccr_source_tests_isolated.ps1` now refuses to run
  while Codex/ChatGPT App or project ports are live, redirects HOME, APPDATA,
  LOCALAPPDATA, TEMP, CODEX_HOME and CCR internal paths below this root, enables
  provider-only mode and compares the external Codex fingerprint before/after.
  `START_HERE.md`, `AGENTS.md` and `claude.external-app-isolation` make this
  wrapper mandatory. The wrapper's live-App refusal was observed in this run.
- CCR `3.0.22` disposition: HOLD. The source patch cherry-picked cleanly and
  typecheck passed, but the npm runtime had zero matches for all four reviewed
  minified patch anchors. The rejected worktree/runtime and review branch were
  removed; operational CCR remains `3.0.21`.

## challenger.google-dynamic-model-catalog-empty — fixed 2026-08-28

- Symptoms: completed Google accounts show quota groups but no selectable
  model; manually pressing catalog synchronization cannot populate a route.
- Impact: Google accounts cannot be safely promoted into the Claude launch
  selector, and hard-coding the current Antigravity screenshot would become
  stale as Google changes model availability.
- Reproduction: issue a bounded catalog request through the account's existing
  project-local OAuth context, then query `/v1/models` through the exact
  project-patched CLIProxyAPI binary.
- Raw evidence: the stale slots originally returned HTTP 401. After the owner
  removed/re-authenticated one slot, the same sanitized catalog adapter returned
  24 models and four separate quota windows. The first project-local runtime
  readiness attempt exposed no model immediately; a bounded registry wait then
  proved `gemini-3.7-flash-high` on `/v1/models` without sending a model turn.
  No token, email, account ID or auth payload was retained.
- Cause: two independent conditions were conflated. The old OAuth state was
  stale, while the dashboard also never converted a successful Google catalog
  into launch routes. The runtime registry is asynchronous and may briefly
  return an empty list during cold start.
- Failed approaches: direct dynamic catalog request and the reviewed current
  proxy. Screenshot model names were deliberately not used as source truth.
- Disposition: fixed. The dashboard creates Google routes only from the
  intersection of the live account catalog and the exact pinned runtime model
  manifest. The current slot produces 13 launchable routes from 24 catalog
  entries. Each slot has its own hash-verified loopback runtime and bounded
  model-registration wait; no automatic fallback is enabled.
- Regression gate: `claude.dashboard-account-management` prohibits transient
  hard-coded model names and false successful synchronization. A real provider
  entitlement still requires the owner's first normal Claude prompt; current
  proof stops at catalog, loopback identity and `/v1/models` readiness.

## challenger.google-empty-slot-acl-and-callback — fixed pending owner authorization 2026-08-27

- Symptoms: **Thêm tài khoản Google** failed before showing OAuth with
  `The property 'Count' cannot be found`; a later retry on the empty slot failed
  because `Set-Acl` requested `SeSecurityPrivilege`; an earlier OAuth attempt
  reached Google but timed out without a callback.
- Confirmed causes: PowerShell unrolled the zero-file branch to `$null`; ACL
  setup needlessly reapplied owner metadata on an already protected directory;
  and the patched listener used IPv4 `127.0.0.1` while the OAuth redirect still
  used hostname `localhost`, which can resolve to IPv6 first on Windows.
- Disposition: zero auth files are now forced to an array; ACL protection is
  retry-safe and changes no owner/audit data when already correct; reviewed
  CLIProxyAPI patch 4 makes both listener and redirect exactly IPv4 loopback.
  The `7.2.141-local.4` binary was reproduced at SHA-256
  `3d3f909e0a59d810c415be65b1fbd1941a79a32eeb1e3d6a7eb1ac730b25d70e`.
  Live startup reached Google's official chooser with the corrected callback;
  completing password/2FA remains an owner action and is not yet claimed.
- Regression gates: `challenger.cli-proxy-source-pin` and
  `challenger.google-account-flow`.

## dashboard.double-console-and-active-import-block — fixed 2026-08-28

- Symptom: the first dashboard launch could leave an extra blank terminal; a
  Codex Plus attempt failed while another Claude/router session was active.
- Causes: Node originally launched CMD/batch before PowerShell; after that was
  removed, `DASHBOARD.bat` itself still waited synchronously for the hidden
  starter. Because echo was disabled, that owner console appeared as a large
  blank terminal. The importer separately rejected active CCR before allowing
  project-local browser auth.
- Disposition: `DASHBOARD.bat` now detaches the hidden starter and exits
  immediately. The supervisor/router remain hidden; a real startup failure is
  written to ignored `.runtime/dashboard/startup-error.log` and opened for the
  owner. Codex auth may be saved while CCR is active, with mutation deferred to
  the pending dashboard card.
- Regression gates: `claude.local-dashboard`,
  `claude.router-warm-start-contract` and `claude.codex-account-import`.

## dashboard.first-launch-background-refresh-contention — fixed 2026-08-28

- Symptom: after selecting a route, the dashboard appeared to wait for a long
  time before the Claude terminal became usable; early Plus attempts could also
  surface timeout/API errors that disappeared in later terminals.
- Impact: the one-click dashboard felt impractical even when account routes and
  later warm launches were healthy.
- Reproduction: start a fresh dashboard, immediately launch a route, and
  observe that the automatic quota/catalog refresh was scheduled after 750 ms
  while the same machine was cold-starting router and Claude processes.
- Raw evidence: source timing and lifecycle order only; no credential, provider
  request body or transcript was captured. Upstream latency remains separately
  unknown.
- Cause: a proved local scheduling conflict. Background account probes could
  overlap the first launch and compete for process/network resources. This does
  not prove that every reported API error had the same cause.
- Failed approach: a visible pending notice alone improved feedback but did not
  remove the competing background work.
- Disposition: fixed. Initial background refresh now waits 15 seconds and
  skips whenever `activeLaunches > 0`; the five-minute steady-state refresh is
  preserved. Provider failures still surface normally.
- Regression gate: `claude.dashboard-action-lifecycle` requires both the
  15-second delay and the active-launch guard.

## challenger.google-browser-account-reuse — fixed pending live proof 2026-08-26

- Symptom: Google OAuth reused the browser's current Google identity instead of
  clearly allowing the intended Pro account.
- Cause: OAuth requested consent but not explicit account selection and had no
  bounded login hint.
- Disposition: reviewed patch adds `prompt=consent select_account`; dashboard
  may pass a validated optional email through process-local
  `CLIPROXY_GOOGLE_LOGIN_HINT`. Password/2FA remain on Google. Offline URL tests
  and reproducible build pass; one owner-run live OAuth remains required.
- Regression gates: `challenger.cli-proxy-source-pin` and
  `challenger.google-account-flow`.

## phase2.wrapper-verifier-and-sandbox-dpapi — fixed/contained 2026-08-25

- Symptom: cumulative run `20260825T163959Z-1811586c` passed 15/17 gates.
  `claude.router-local-layout` rejected `& $GoogleMenu -Root $RootPath`, and the
  menu self-test reported `Cryptography_DpApi_ProfileMayNotBeLoaded`.
- Causes: the process allowlist had not yet named the new bounded local wrapper;
  separately, the filesystem sandbox did not load the owner DPAPI profile.
- Disposition: the verifier now permits only that exact wrapper command, while
  the dedicated Google flow verifier proves its pinned path/hash/loopback
  boundary. No wildcard process allowance was added. The complete 17-gate run
  passed under the owner Windows profile in `20260825T164115Z-8fc5f438`.
- Regression gates: `claude.router-local-layout`,
  `claude.router-menu-selftest` and `challenger.google-account-flow`.

## challenger.phase2-build-hash-rollover — fixed 2026-08-25

- Symptom: the first reproducible rebuild after adding the loopback callback
  patch rejected the output because `BUILD.json` still held the previous Phase
  1 binary hash.
- Cause: expected fail-closed identity rollover after a reviewed source change.
- Disposition: the newly built binary was inspected, its exact source
  commit/tree/version recorded, then the new hash was promoted and a second
  reproducible build passed. No unverified binary was used for OAuth.
- Regression gate: `challenger.cli-proxy-source-pin` plus the explicit build
  script's binary-hash check.

## phase2.account-slot-count-misread — fixed before promotion 2026-08-25

- Symptom: the first delegated manifest draft modeled six slots because it
  interpreted “two Codex Free accounts” as the total rather than two accounts
  in addition to the already imported `codex_free_1`.
- Cause: ambiguous conversational shorthand was not reconciled with verified
  current state.
- Disposition: corrected to seven exact slots before gate promotion: three
  Free, one Plus and three Google Pro. The validator and 12 tests now reject any
  other count/order.
- Regression gate: `challenger.account-onboarding-contract`.

## challenger.concurrent-baseline-invalid — contained 2026-08-25

- Symptom: smoke run `20260825T141021Z-0bdd6512` reported 9/10 with the source
  pin gate failing and `tree_stable: false`.
- Cause: the explicitly delegated Terra worker began the approved nested source
  patch while the parent baseline gate run was still in progress.
- Impact: that run is invalid evidence, not a regression in the previously
  accepted 10/10 baseline `20260825T133921Z-29f3a3bd`.
- Disposition: contained. The exact patch was reviewed, formatted, tested and
  committed before later gates. Do not run a cumulative gate concurrently with
  any worker that can write inside an indexed/verified nested checkout.

## challenger.fixture-composite-literal — fixed 2026-08-25

- Symptom: the first Go compile of the new deterministic fixture reported a
  missing comma/brace around the non-stream tool-call response.
- Cause: one `assistantMessage` composite literal was not closed before the
  enclosing `chatChoice` finish reason.
- Disposition: fixed with one closing brace, then formatted by project-local
  `gofmt`. All fixture tests, reproducible build and full offline protocol
  self-test passed afterward.
- Regression gate: `challenger.offline-pilot` plus fixture `go test ./...` in
  `tools/build_challenger.ps1`.

## foundation.fingerprint-scanned-local-toolchains — fixed 2026-08-25

- Symptom: the first final cumulative run after staging Go/module cache and two
  ignored source checkouts spent minutes before producing a gate result.
- Cause: the tree fingerprint excluded the old Node/runtime payloads but still
  hashed ignored Go toolchain/module caches and both new nested source trees.
- Impact: evidence generation was impractically slow; focused gates themselves
  were not failing.
- Disposition: fixed. Exact local-only directories are excluded from the global
  fingerprint and are instead validated by dedicated source/binary gates. The
  runner still rejects any tracked file under a fingerprint-excluded directory.

## challenger.windows-powershell-missing-filehash — fixed 2026-08-25

- Symptom: cumulative run `20260825T151833Z-dbff50bf` passed 13/14 gates; only
  `challenger.offline-pilot` failed immediately because Windows PowerShell did
  not resolve `Get-FileHash` in the gate subprocess.
- Cause: the new gate used legacy `powershell.exe`, while the tested pilot and
  existing project PowerShell gates use pinned PowerShell 7.
- Impact: no protocol/isolation behavior ran in that failed gate. The same
  self-test had already passed directly under PowerShell 7.
- Disposition: fixed by using exact project-approved PowerShell 7 executable in
  the registry; no production or provider code changed.

## foundation.candidate-source-readme-triggered-secret-scan — fixed 2026-08-25

- Symptom: the first post-intake cumulative run failed
  `foundation.memory-routing` with a possible embedded secret in
  `cli-proxy-api_core/examples/realtime-openai-go/README.md`.
- Impact: Phase 0 could not be promoted despite the other nine gates passing.
- Reproduction: keep the ignored CLIProxyAPI source checkout present and run
  the smoke tier before adding its exact directory name to the memory auditor's
  source-checkout exclusions.
- Raw evidence: run `20260825T133535Z-7097f80b` retained only the relative README
  path and gate result. The example value was not copied into tracked evidence.
- Cause: the auditor excluded the older ignored CCR source checkout but did not
  yet know the equivalent new CLIProxyAPI checkout, so it scanned third-party
  example documentation as project memory.
- Failed approach: none; the first cumulative run exposed the missing boundary.
- Disposition: fixed. Only the exact independent checkout directory was added
  to `AUDIT_IGNORED_DIRS`; tracked project Markdown remains scanned.
- Regression gates: `foundation.memory-routing` and
  `challenger.cli-proxy-source-pin`; all 10 gates passed in
  `20260825T133632Z-91288459`.

## foundation.tracked-runtime-marker-invalidated-gate — fixed 2026-08-25

- Symptom: the first post-stage cumulative gate run stopped before executing
  gates with `tracked file under fingerprint-excluded directory` for
  `provider_router/runtime/.gitkeep`.
- Impact: the initial Git baseline could not be promoted even though the marker
  contained no runtime data.
- Reproduction: stage the previously untracked marker, then run
  `tools/run_gates.py` on the resulting Git index.
- Cause: `.gitignore` exempted a `.gitkeep` file inside a directory deliberately
  excluded from the evidence fingerprint. Before the initial stage there was no
  tracked index, so the contradiction was latent.
- Disposition: fixed. The empty marker and its ignore exception were removed;
  the runtime directory is created by explicit reconstruction and remains
  entirely untracked.
- Regression gate: the gate runner's existing tracked-file check prevents any
  future tracked artifact under the excluded runtime directory.

## bootstrap.source-template-path-missing — accepted 2026-08-23

- Symptom: the Human-supplied CLOVER template path ending in
  `START/_HERE.md` was not present.
- Impact: that exact file could not be read.
- Reproduction: `Test-Path` returned false for the supplied path.
- Cause: unknown; the available CLOVER root router used the sibling filename
  `START_HERE.md`.
- Disposition: accepted for this bootstrap. The existing CLOVER root router was
  read and its local project-memory conventions were applied; no external file
  is required at runtime.
- Regression gate: not applicable to this project; future work should preserve
  the local `START_HERE.md` route and report a missing supplied source path
  rather than silently inventing a replacement.

## router.version-probe-requires-model — fixed 2026-08-24

- Symptom: invoking the CCR CLI only to obtain its version returned
  `No available models` before any provider had been configured.
- Impact: `RUN_CLAUDE.bat --router-version` could fail during first-time setup
  even though the pinned package was installed correctly.
- Reproduction: execute the installed CCR CLI with `--version` while its local
  configuration has no models.
- Cause: the CLI initializes routing configuration before completing that
  version path.
- Failed approach: treating the router executable like a standalone binary
  whose `--version` path is configuration-free.
- Disposition: fixed. The launcher reads the installed package's exact version
  from its local `package.json` using project-local Node; it does not open the
  router or a provider connection.
- Regression gate: `claude.router-local-layout` checks the installed manifest
  against the pinned version.

## router.open-port-was-not-identity — fixed 2026-08-24

- Symptom: the first implementation accepted any listener on local port 3456
  as an already-running router.
- Impact: a different local process could have received the DPAPI-decrypted CCR
  client key and Claude request content.
- Reproduction: inspection of the old `Ensure-Router` showed an immediate
  return when `Test-LocalPort -Port 3456` succeeded.
- Cause: readiness and process identity were incorrectly treated as the same
  condition.
- Failed approach: TCP-port availability alone.
- Disposition: fixed fail-closed. Launch now verifies project-local service
  state, exact loopback URL, PID, project-local Node executable, local CCR
  command line and gateway `/health` before secret access.
- Regression gates: `claude.router-local-layout` rejects the port-only bypass
  and missing identity markers; `claude.router-menu-selftest` checks the
  hardening markers and loopback-only endpoints.

## router.legacy-config-json-is-not-live — fixed 2026-08-24

- Symptom: a root JSON file could appear to configure CCR while having no
  effect after CCR had created its SQLite database.
- Impact: the owner could edit API URL/key/model values and still launch an old
  route, creating both confusion and possible unintended quota/endpoint use.
- Reproduction: CCR 3.0.21 documentation and source show that legacy
  `config.json` is a one-time migration input; live config is `config.sqlite`.
- Cause: treating a legacy migration file as a continuously watched source.
- Failed approach: copying a JSON template into a CCR config directory.
- Disposition: fixed. The ignored root `setting.json` uses a project-owned
  schema; when its SHA-256 changes, the launcher validates it and merges only
  `local-setting--*` providers through authenticated loopback `getConfig` /
  `saveConfig` RPC. CCR UI/account providers are preserved.
- Regression gates: `claude.setting-json-flow` verifies ignore/schema/prompt
  boundaries and RPC markers; `claude.router-menu-selftest` verifies the
  deterministic parser/merge without reading the owner's real file.

## router.isolated-home-hid-codex-import — fixed 2026-08-24

- Symptom: Add Provider showed only API presets; no local Codex import panel
  appeared despite a successful Windows Codex login.
- Impact: the owner was led toward an OpenAI API-key form that cannot accept a
  ChatGPT/Codex account login.
- Reproduction: run CCR with this project's `CCR_INTERNAL_HOME_DIR`, open Add
  Provider, and observe an empty local-agent candidate list.
- Cause: CCR scans `CCR_INTERNAL_HOME_DIR/.codex/auth.json`; the project-local
  home intentionally does not contain the external Windows login. UI source
  hides the entire import panel when no non-missing candidate exists.
- Failed approach: directing the owner to search the normal provider wizard for
  an import control without first verifying the isolated home path.
- Disposition: fixed in the project wrapper. `SIGN_ACCOUNT.bat` now performs an
  explicit browser login into a separate project-local Codex home, then performs
  guarded import and creates a local RUN route; API presets remain in the UI for
  real API keys/endpoints.
- Regression gates: `claude.codex-account-import` and
  `claude.router-menu-selftest`.

## router.external-codex-auth-broke-independence — fixed 2026-08-24

- Symptom: option `[1]` depended on the current Windows user's global
  `.codex/auth.json`, despite all later staging/state being local.
- Impact: moving/cloning the project did not preserve its login mechanism, and
  changing global Codex App/CLI login affected which account could be imported.
- Reproduction: prior `Import-CurrentCodexAccount` resolved the Windows user
  profile before copying auth to CCR staging.
- Cause: “local snapshot destination” was mistaken for full source/runtime
  independence.
- Failed approach: treat global auth as a read-only exception and ask the owner
  to switch the Windows Codex login between imports.
- Disposition: fixed. A pinned official login helper now runs only `login` with
  unique project-local `CODEX_HOME`/`CODEX_SQLITE_HOME`; global user/app auth and
  PATH are not discovered. Browser/network remain inherently external.
- Regression gates: `claude.codex-account-import` rejects global path discovery,
  verifies helper SHA-256 and per-account local homes;
  `claude.router-menu-selftest` checks fake file-backed ChatGPT config.

## router.invalid-model-input-aborted-valid-login — fixed 2026-08-24

- Symptom: browser login succeeded and CCR returned one model, but entering an
  unrelated alias at the model selector aborted the entire import.
- Impact: the account route was not saved after password/2FA had already
  completed, and repeating the old flow could create another account-home
  directory.
- Reproduction: with one returned model, enter a non-numeric string different
  from the listed model ID.
- Cause: the selector prompted unnecessarily for one choice and threw on the
  first invalid value; account-slot allocation also skipped every existing
  unfinished local home.
- Failed approach: require the owner to know that `[1]` means numeric input and
  restart browser login after a typo.
- Disposition: fixed. Sole model auto-selects; multiple-model input accepts a
  number or exact ID and retries; exact account label resumes unfinished local
  auth using a non-secret label hash and file-existence check.
- Regression gates: `claude.router-menu-selftest` covers choice resolution and
  fake pending-home resume; `claude.codex-account-import` rejects the old throw
  behavior and requires the retry/resume controls.

## router.generated-account-route-id-rejected — fixed 2026-08-25

- Symptom: account browser login/import completed, but the next RUN failed with
  `The project-local account profile index contains an invalid route.`
- Impact: the saved account could not appear in the Claude route menu even
  though its local authentication and provider import had succeeded.
- Reproduction: generate an account provider slug from the sanitized label
  `account_name+tag@example.test`, save its route, then reload the account
  profile index.
- Cause: `ConvertTo-ProviderSlug` deliberately preserved slug-safe `_` and `.`
  characters, while `Read-AccountProfiles` accepted only letters, digits and
  hyphens in the route ID created from that slug. `Get-ModePath` repeated the
  narrower rule when a displayed route was selected.
- Failed approach: the prior self-test used only `codex-account-1`, so generator
  and reader appeared compatible while common account-label punctuation was
  untested.
- Disposition: fixed without reading or rewriting real authentication data.
  Account route IDs now accept the same slug-safe punctuation as their local
  generator in both index reload and isolated Claude mode-path creation; an
  offline sanitized round-trip fixture prevents regression.
- Regression gates: `claude.router-menu-selftest` executes the round trip;
  `claude.codex-account-import` requires both the compatible validator and the
  sanitized fixture.

## router.start-exit-overrode-verified-gateway — fixed 2026-08-25

- Symptom: selecting an account route produced `CCR command failed (exit code
  1)` and returned to the BAT file instead of opening Claude.
- Impact: a correctly imported account still could not reach the Claude harness.
- Reproduction: with management listening only on `127.0.0.1:3458`, invoke the
  pinned local CCR `start --gateway`. The observed command exit was 1; gateway
  health was unavailable before the command and HTTP 200 immediately after it.
- Cause: `Ensure-Router` treated the CLI exit as the final truth and never
  reached its stronger process-identity and gateway-health verification. Why
  this CCR build reported exit 1 after achieving the requested state remains
  unknown and is not required for the wrapper-level repair.
- Failed approach: require a zero process exit before checking the independently
  observable gateway postcondition.
- Disposition: fixed. `Invoke-CcrStartAndVerify` records a start failure as
  diagnostic context, then verifies exact project-local process identity,
  service token and loopback health. A verified service continues; an
  unverified service fails closed before DPAPI secret access and reports both
  contexts without exposing CCR output or credentials.
- Regression gates: `claude.router-local-layout` requires the verified-start
  control; `claude.router-menu-selftest` simulates both stale-exit/success and
  start-error/verification-error fail-closed paths.

## router.cold-gateway-ipc-timeout — fixed 2026-08-25

- Symptom: selecting `[1]` failed with gateway health unavailable even though
  the exact project-local management process was verified.
- Impact: a valid imported Codex account and visible route could not launch the
  Claude harness.
- Reproduction: authenticated local `getGatewayStatus` returned `state=error`
  with `Core gateway did not accept runtime config within 5000ms.`; source fixes
  that deadline at five seconds in the core runtime supervisor.
- Raw evidence: retained only as sanitized state/timing in
  `50-Evidence/2026-08-25-ccr-cold-start-recovery.md`; management tokens, auth,
  settings, SQLite, DPAPI plaintext and raw command output were not retained.
- Cause: proved at the control boundary—the gateway child missed CCR's fixed IPC
  acceptance deadline. A slow first Windows module load/cache or endpoint
  scanner is consistent with the probe behavior but remains an inference.
- Failed approach: increasing the minified runtime timeout temporarily did not
  produce a trustworthy result in the stale service lifecycle and was fully
  rolled back; replacing CCR with 9router would expand runtime/auth/state scope
  before fixing the bounded lifecycle condition.
- Disposition: fixed in the wrapper. Only the exact authenticated timeout state
  permits at most two `startGateway` retries; all unrelated errors and failed
  identity/health checks remain fail-closed before DPAPI access.
- Regression gates: `claude.router-menu-selftest` verifies exact trigger versus
  unrelated error; all 8 gates passed in `20260825T041235Z-3565decb`. A real
  route selection launched project-local Claude `--version` with exit 0 and no
  provider request.

## router.system-default-took-over-codex-app — fixed 2026-08-25

- Symptom: external Codex App displayed `Claude Code Router` and its normal
  Usage surface disappeared.
- Impact: the supposedly isolated Claude CLI project changed the user's Codex
  App/provider behavior outside the project folder.
- Reproduction: select Codex agent, `System default` and `CLI & APP` in CCR's
  Connect agent form. Source maps these to global/auto scope and writes the
  gateway provider into `~/.codex/config.toml`.
- Raw evidence: only fixed CCR markers, loopback URL presence and SHA-256 were
  observed. Before repair the global config had CCR markers/provider/URL and
  the local takeover marker existed; after repair its hash matched the clean
  CCR original snapshot and all those markers were absent. See
  `50-Evidence/2026-08-25-external-codex-app-isolation-repair.md`.
- Cause: the project exposed CCR's generic agent UI despite its narrower
  provider-gateway-only architecture. The selected global/App profile was
  working as designed by CCR but violated this project's isolation invariant.
- Failed approach: relying only on `CCR_INTERNAL_*` paths. Those isolate CCR's
  own database, but a global agent profile deliberately resolves and writes a
  user-level Codex/Claude config. Merely disabling built-in Codex routing did
  not disable agent-profile application.
- Disposition: fixed. All CCR agent profiles are removed before save, profile
  cleanup is applied, a takeover marker forces synchronization, agent UI entry
  points are removed, and API/account setup uses only `setting.json` plus the
  project-local login wrapper. The external config was restored from a verified
  clean snapshot on disk; the running App must be fully restarted to discard its
  cached provider state.
- Regression gate: `claude.external-app-isolation` plus existing router/setting
  gates. Owner restart is still required to visually verify label/Usage.

## router.codex-free-fallback-model-was-not-usable — fixed 2026-08-25

- Symptom: Claude opened on `codex_free_1/gpt-5-codex`, but the first prompt
  returned `API Error: 400 All target providers failed.`
- Impact: browser login, route display and gateway startup all appeared
  successful while no real inference could complete.
- Reproduction: send a minimal streaming Anthropic message through the local
  gateway to the imported route. Sanitized attempt metadata reported stage
  `upstream_response`, status 400 and that `gpt-5-codex` is unsupported when
  Codex is used with a ChatGPT account.
- Cause: CCR 3.0.21 catches failure of its live Codex model-catalog probe and
  silently falls back to its source default `gpt-5-codex`. Model discovery was
  therefore treated as entitlement proof even though the upstream rejected it.
- Failed approaches: trusting the imported model list; trusting CCR's generic
  connectivity check, which also marked Sol available although the real Claude
  `/v1/messages` path rejected Sol for this Free account.
- Disposition: fixed for the project's ChatGPT Free accounts. The legacy model
  and Sol are excluded; Terra and Luna were both proved with HTTP 200 completed
  streams and receive separate RUN routes. `SIGN_ACCOUNT.bat` action `[R]`
  refreshes model routes without another browser login.
- Regression gate: `claude.codex-account-import`, including current candidate
  filtering and a deterministic two-model account-index round trip. Real
  entitlement remains a bounded owner-authorized gateway check because an
  offline test cannot prove provider account access.
- Evidence: `50-Evidence/2026-08-25-codex-free-model-route-repair.md`.

For every new retained failure, include a stable ID, impact, reproduction, raw
evidence, cause or `unknown`, failed approaches, disposition, and a regression
gate or an explicit reason that deterministic gating is not feasible. Do not
remove a retained entry after fixing it; mark it fixed and link the preventing
gate.
