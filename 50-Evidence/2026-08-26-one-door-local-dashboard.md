# One-door local dashboard evidence

- Date: 2026-08-26
- Scope: original localhost dashboard, compatibility entry cleanup, exact route
  launch, account onboarding actions and provider quota adapters
- Owner outcome: operate accounts, quota and Claude terminals from one
  `DASHBOARD.bat`

## Baseline

- Parent branch was `claude`, clean and aligned with `origin/claude` before the
  change.
- Previous owner-profile cumulative baseline was 17/17 pass in
  `20260825T164233Z-42021e6c`.
- The new pre-change sandbox run `20260826T002435Z-578682a6` passed 15/17.
  `foundation.memory-routing` timed out at 30 seconds and sandbox ACL prevented
  child termination. `claude.router-menu-selftest` reached the already-known
  `Cryptography_DpApi_ProfileMayNotBeLoaded` boundary. No project source had
  changed before that run.

## Implemented control flow

```text
DASHBOARD.bat
  -> tools/start_dashboard.ps1
  -> provider_router/runtime/node.exe dashboard/server.mjs
  -> authenticated http://127.0.0.1:18320
  -> account/quota/route action
  -> tools/dashboard_terminal.bat
  -> exact reviewed PowerShell action
  -> project-local Claude/CCR or provider browser login
```

- `SIGN_ACCOUNT.bat` now only calls `DASHBOARD.bat`; it has no independent UI.
- `RUN_CLAUDE.bat` remains unchanged as a technical rollback launcher.
- Dashboard route launch validates the exact current profile ID before opening
  a new terminal. A terminal never changes an already-running terminal's
  process-local route.
- Codex and Google login actions reuse the existing project-local reviewed
  helpers. Password and 2FA remain on official provider browser pages.

## Security observations

- Server address is fixed to `127.0.0.1:18320`; no wildcard/all-interface bind
  exists.
- A random 256-bit bootstrap token becomes an HttpOnly, SameSite=Strict cookie.
  API calls require that cookie and same-origin. CSP, frame denial, no-sniff,
  no-referrer and restrictive browser permissions are set.
- Runtime ready state, terminal records and secret-free quota snapshots are
  under ignored `.runtime/dashboard`.
- Browser JSON contains account labels, route/model IDs, status and normalized
  quota only. It contains no access/refresh token, email or provider account ID.
- Built frontend has no external runtime URL or font dependency. Normal startup
  uses the copied project-local Node runtime and tracked static assets.
- EasyCLIProxyAPI remained ignored and inspect-only. No unlicensed source was
  copied, built or executed.

## Quota behavior

- Codex backend adapter queried the current project-local account usage surface
  and normalized the returned duration, used percentage and reset time. The
  observed account returned one available window. Provider credit availability
  and balance are normalized separately; the UI shows available/unavailable or
  explicitly unknown without treating credits as a percentage quota.
- Window labels are derived from provider duration: 18,000 seconds is 5 hours,
  604,800 seconds is weekly and 28–31 days is monthly. The code does not assume
  that every Free/Plus account has the same windows.
- Google schema always contains separate `gemini_models` and
  `claude_gpt_models` groups. Missing groups/windows remain unknown. No Google
  OAuth or quota request was made because no owner login exists yet.
- Custom APIs remain unknown unless a provider-specific adapter is later proved.
  Local request counts are not called provider subscription quota.
- Provider quota endpoints are labelled experimental/undocumented and may
  change. A retrieval failure affects only quota display, not route launch.

## Focused verification

- Production UI build: TypeScript check plus Vite build passed; tracked assets
  were emitted under `dashboard/static`.
- Offline dashboard verifier passed: single entry, loopback/session/CSP
  controls, no browser credential access, exact action allowlists, split Google
  quota contract and Node syntax.
- Existing setting-flow and Codex-import verifiers passed after being updated
  to require `SIGN_ACCOUNT.bat` as a pure dashboard compatibility redirect.
- Live local smoke observed:
  - schema version `1`;
  - five displayed accounts/providers/slots;
  - two current account/model routes;
  - Claude `2.1.241` and CCR `3.0.21`;
  - successful authenticated Codex quota refresh with one normalized window;
  - unauthenticated `/api/state` rejection;
  - unknown route launch rejection with HTTP `400` and no process spawn.
- The real startup helper was then run under the owner profile. Its ready PID
  was independently matched to the exact project-local Node executable and
  exact `dashboard/server.mjs` command line; loopback-only state was true and a
  per-process health instance ID matched the ready record.
- The first cumulative post-change run passed 17/18. Only the memory auditor
  timed out because `Path.rglob` traversed ignored `vendor`/`node_modules` trees
  before filtering. The auditor was corrected to prune those directories in a
  top-down walk, reducing the focused run to about 0.2 seconds and strengthening
  the no-raw/ignored-input boundary.
- All 18 enabled smoke gates passed after that repair in
  `20260826T012244Z-b98e0bf3` under the owner Windows profile.
- The exact-process/instance guard and explicit provider-credit row were then
  added. All 18 enabled smoke gates passed on that final artifact in
  `20260826T012651Z-4331fd55`.

## Rollback

Stop the dashboard process and use `RUN_CLAUDE.bat`. Removing the new
dashboard source/entry files does not require deleting or changing CCR account
homes, custom API settings, Codex App state or provider OAuth. Never delete
ignored auth state as part of UI rollback.
