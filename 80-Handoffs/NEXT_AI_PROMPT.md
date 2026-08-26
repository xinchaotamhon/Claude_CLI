# Next AI Handoff

Read `START_HERE.md` and its full local read order. Do not read or print
ignored `setting.json`, account auth JSON, CCR SQLite or DPAPI plaintext unless
the Human explicitly authorizes a bounded backend diagnostic that cannot expose
the secret in output.

## Verified Baseline

- One harness: project-local `bin/claude.exe`, Claude Code `2.1.241`.
- Operational router/rollback champion: CCR `3.0.21` on project-local Node
  `v24.12.0`, provider-gateway-only on loopback. External Codex App takeover
  paths are removed and must not be reintroduced.
- `DASHBOARD.bat` is the single owner-facing entry. It starts the original
  local dashboard on authenticated `127.0.0.1:18320` using the project Node.
  Static assets are tracked; normal startup downloads/builds nothing.
- `SIGN_ACCOUNT.bat` is only a compatibility alias to the dashboard.
  `RUN_CLAUDE.bat` remains the technical rollback menu.
- Dashboard discovers Codex/custom API routes dynamically and exposes three
  pinned Google Pro OAuth slots. Browser actions call only reviewed project
  helpers; password and 2FA remain on provider pages.
- Exact route ID launch opens a separate terminal. Existing terminals retain
  their own process-local route. Same-account terminals share quota; different
  accounts do not intentionally share credentials.
- Codex Free candidates are Terra/Luna; Plus candidates are Sol/Terra/Luna.
  Current imported Free account has two proved routes: Terra and Luna. Legacy
  `gpt-5-codex` and Sol were rejected for that account.
- Backend Codex quota refresh has one live bounded proof. It returns only
  normalized windows/credits to the browser and labels the undocumented source
  experimental. Window duration determines 5-hour/weekly/monthly display.
- Google quota contract always preserves two groups: `gemini_models` and
  `claude_gpt_models`. No Google owner login or live quota shape is proved yet;
  missing values remain unknown.
- API providers have no generic subscription-quota adapter. Never relabel local
  proxy counts as provider quota.
- Automatic fallback remains disabled. Existing policy requires finite
  allowlists, session affinity and no retry after output/tool side effects.
- EasyCLIProxyAPI remains ignored inspect-only at a pinned revision because its
  tree has no license grant and unsafe global/update paths. No source was copied.
- Pre-change owner-profile baseline: 17/17 pass
  `20260825T164233Z-42021e6c`. Pre-change sandbox run
  `20260826T002435Z-578682a6` passed 15/17; only the known DPAPI profile boundary
  and a sandbox timeout/child-termination ACL failed.
- Dashboard focused evidence is
  `50-Evidence/2026-08-26-one-door-local-dashboard.md`.

## Allowed Next Work

1. Let the owner use dashboard buttons to add remaining Codex Free, Codex Plus
   and Google accounts. Do not request credentials in chat/terminal.
2. After one Google slot completes, refresh both quota groups, inspect only the
   normalized response and prove one explicit model/tool loop before route
   promotion.
3. Prove parallel terminals with same and different account routes.
4. Improve quota refresh/reauth degradation without making quota a hard launch
   dependency.
5. Add automatic fallback only as a separately approved, bounded and
   independently tested phase.
6. Rerun focused plus cumulative gates and update state/evidence before push.

## Boundaries

- No global `.codex`, global Claude config, PATH-discovered agent binary or CCR
  Connect-agent profile.
- No all-interface listener, remote dashboard, telemetry, updater, tray,
  autostart or browser token exposure.
- No hidden account rotation or claim that multiple accounts increase an
  account's allowed quota.
- No automatic merge/update of CCR, CLIProxyAPI or closed Claude binaries.
- Rollback means stop dashboard and use `RUN_CLAUDE.bat`; never delete account
  state merely to roll back the UI.
