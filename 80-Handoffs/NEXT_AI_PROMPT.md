# Next AI Handoff

Read `START_HERE.md` and its full local read order. Do not read or print
ignored `setting.json`, account auth JSON, CCR SQLite or DPAPI plaintext unless
the Human explicitly authorizes a bounded backend diagnostic that cannot expose
the secret in output.

## Verified Baseline

- One harness: project-local `bin/claude.exe`, Claude Code `2.1.250`.
- Operational router/rollback champion: CCR `3.0.21` on project-local Node
  `v24.12.0`, provider-gateway-only on loopback. External Codex App takeover
  paths are removed and must not be reintroduced.
- `DASHBOARD.bat` is the single owner-facing entry. It detaches one hidden
  bootstrapper, returns immediately and starts the original local dashboard on
  authenticated `127.0.0.1:18320` using the project Node. Successful startup
  leaves no blank console; failures open ignored
  `.runtime/dashboard/startup-error.log`. Static assets are tracked; normal
  startup downloads/builds nothing.
- Root contains only `DASHBOARD.bat`. Technical rollback is
  `tools/RUN_CLAUDE_TECHNICAL.bat`; do not recreate duplicate root BAT files.
- Dashboard discovers Codex/custom API routes dynamically and exposes up to 50
  bounded Google Pro OAuth slots. Browser actions call only reviewed project
  helpers; password and 2FA remain on provider pages.
- Google routes do not use CCR. Each slot launches one hash-verified
  CLIProxyAPI `7.2.144-local.1` process on deterministic loopback ports
  `18401` through `18450`. A route exists only in the intersection of the
  slot's sanitized live catalog and the tracked pinned-runtime manifest.
- Exact route ID launch opens one separately acknowledged visible terminal.
  Dashboard success requires `terminal_ready` and, for a model launch,
  `claude_starting`. Existing terminals retain their own process-local route.
  Same-account terminals share quota; different accounts do not intentionally
  share credentials.
- A mutex-guarded supervisor restarts the localhost Node server while an ignored
  persistent HttpOnly browser session lets an open page reconnect. Session rows
  are shown only for real transcript JSONL IDs and **Mở lại bằng** can select any
  current route against the common ignored Claude home.
- Session **Xóa** requires confirmation, rejects active terminals and moves the
  exact UUID transcript to ignored project-local trash with a recovery manifest.
- **Xóa mục đã đóng** changes only the ignored terminal-history registry after
  recomputing liveness; it must not stop processes or remove sessions.
- Dashboard process orchestration explicitly requires PowerShell 7+. Do not
  reintroduce Windows PowerShell 5.1 fallback around `ArgumentList` or
  `Convert.ToHexString`; reconstruction documents this host prerequisite.
- Codex Free candidates are Terra/Luna; Plus candidates are Sol/Terra/Luna.
  Current imported Free account has two proved routes: Terra and Luna. Legacy
  `gpt-5-codex` and Sol were rejected for that account.
- Backend Codex quota refresh has one live bounded proof. It returns only
  normalized windows/credits to the browser and labels the undocumented source
  experimental. Window duration determines 5-hour/weekly/monthly display.
- Google onboarding/runtime uses reviewed CLIProxyAPI `7.2.144-local.1` at
  patched nested commit `b811980516263623713dbcf15e3cecf8296ab2b0` and binary
  SHA-256
  `bc2631f4e46a2fcc0a9ceafa6d55d3887d3442666b556712edac85c04d1f24e2`;
  redirect, listener and runtime endpoints use `127.0.0.1`. The authenticated
  `google_pro_1` slot exposed 24 sanitized catalog models, 13 launchable runtime
  intersections and four quota windows across the separately preserved
  `gemini_models` and `claude_gpt_models` groups. A bounded registry proof
  exposed `gemini-3.7-flash-high` on port `18401` without a model request.
- API providers have no generic subscription-quota adapter. Never relabel local
  proxy counts as provider quota.
- Automatic fallback remains disabled. Existing policy requires finite
  allowlists, session affinity and no retry after output/tool side effects.
- EasyCLIProxyAPI remains ignored inspect-only at a pinned revision because its
  tree has no license grant and unsafe global/update paths. No source was copied.
- Current cumulative owner-profile baseline: 22/22 pass
  `20260828T084103Z-4ba632f2`. Focused dashboard/account gates also pass in
  `20260828T082346Z-556b8c64`. Kiro `claude-opus-5` has a bounded full
  Claude CLI -> CCR -> provider smoke with exact output `OK`; this proves one
  request, not provider identity, privacy or future availability.
- Current focused evidence is
  `50-Evidence/2026-08-28-google-runtime-routes-dashboard-startup-ui.md`.

## Allowed Next Work

1. Let the owner use dashboard buttons to add remaining Codex Free, Codex Plus
   and Google accounts. Do not request credentials in chat/terminal.
2. Let the owner choose one of the 13 proved Google routes and send the first
   normal model/tool-loop prompt. Record only sanitized outcome metadata; route
   promotion already depends on catalog/runtime intersection and must not be
   expanded from screenshot labels.
3. Prove owner-visible cross-route resume, then parallel terminals with same
   and different account routes.
4. Improve quota refresh/reauth degradation without making quota a hard launch
   dependency.
5. Add automatic fallback only as a separately approved, bounded and
   independently tested phase.
6. Rerun focused plus cumulative gates and update state/evidence before push.

## Boundaries

- No global `.codex`, global Claude config, PATH-discovered agent binary or CCR
  Connect-agent profile.
- Never run CCR source tests directly. Close Codex/ChatGPT App and the local
  dashboard/router, then use `tools/run_ccr_source_tests_isolated.ps1`.
- No all-interface listener, remote dashboard, telemetry, updater, tray,
  autostart or browser token exposure.
- No hidden account rotation or claim that multiple accounts increase an
  account's allowed quota.
- No automatic merge/update of CCR, CLIProxyAPI or closed Claude binaries.
- Rollback means stop dashboard and use `tools/RUN_CLAUDE_TECHNICAL.bat`; never
  delete account state merely to roll back the UI.
