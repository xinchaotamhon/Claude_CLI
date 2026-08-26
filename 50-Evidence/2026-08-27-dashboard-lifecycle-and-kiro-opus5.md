# Dashboard lifecycle and Kiro Opus 5 repair — 2026-08-27

## Owner-observed failures

- A stale localhost page remained visible after its Node server had exited, so
  account buttons appeared to do nothing while opening `setting.json` still
  worked through an earlier page state.
- Terminal creation returned HTTP success immediately after spawning a detached
  process; early CCR/helper failure was therefore reported as success.
- A new session record was written before Claude started, producing four index
  rows without corresponding transcript JSONL files.
- Session resume always reused its historical route, update checks ran four
  network requests sequentially, and the ignored Kiro profile exposed only
  `claude-opus-4.7` despite a broader authenticated model catalog.

## Controls implemented

- `tools/dashboard_spawn_terminal.ps1` is a hidden bounded dispatcher that uses
  `ProcessStartInfo`, `UseShellExecute` and argument-list separation to create
  one visible project-local PowerShell 7 terminal without command interpolation.
  The former incompatible Windows PowerShell 5.1 fallback was removed and
  PowerShell 7+ is now an explicit reconstruction prerequisite.
- `tools/dashboard_terminal.ps1` writes only sanitized lifecycle JSON under
  ignored `.runtime/dashboard/actions`. Account setup waits for
  `terminal_ready`; model launch waits for `claude_starting`, emitted by
  `tools/router_project_menu.ps1` immediately before `bin/claude.exe`.
- `dashboard/server.mjs` saves a session only after launch acknowledgement and
  lists only session IDs that have an actual JSONL transcript under the common
  ignored `.runtime/claude-home`.
- The dashboard offers **Mở lại bằng** for any current allowlisted route. The
  same common Claude home and `--resume <UUID>` preserve cross-model access;
  credentials and transcript content never enter the browser payload.
- `tools/dashboard_supervisor.ps1` uses a project-derived mutex and bounded
  rapid-failure limit. The server's bootstrap token persists only in ignored
  `.runtime/dashboard/dashboard-session.json`; the cookie remains HttpOnly and
  SameSite=Strict, and the token rotates after 30 days.
- Lifecycle acknowledgement is followed by a 650 ms process-stability check;
  an immediate helper/Claude exit is returned as an error instead of a success
  toast. Successful action files are removed after 30 seconds and stale
  diagnostic files after 24 hours.
- Release checks use `Promise.allSettled`; one repository failure is displayed
  as `error` while successful components remain independently current/available.
- Ignored `setting.json` now has a separate `kiro-pix4k-opus-5` route. No key or
  credential was copied into tracked code, evidence, terminal arguments or logs.

## Reproducible and live results

- TypeScript no-emit check: exit 0.
- Vite production build: exit 0; tracked static dashboard rebuilt.
- Node syntax and dashboard self-test: exit 0.
- A live Codex Free dashboard action returned `terminal_ready`, and the exact
  visible helper PID/command line was independently verified in about 3.0 s.
  That exact test process was then stopped; no wildcard/process-name kill ran.
- After stopping the exact verified dashboard Node PID, the supervisor created
  a different healthy PID in about 1.7 s. The original in-memory browser cookie
  immediately authorized `/api/state` against the restarted server.
- Live state contained five transcript-backed sessions rather than the prior
  nine index rows; both Kiro models appeared as routes.
- Concurrent GitHub release checking returned results for Claude Code, CCR,
  Codex helper and CLIProxyAPI in about 0.95 s. It performed no download, merge
  or replacement.
- A bounded full-harness request used `bin/claude.exe` through project-local CCR
  with route `Kiro Pix4K Test/claude-opus-5`; observed output was exactly `OK`
  and exit code was 0.
- All 19 enabled gates passed under the owner Windows profile in gate run
  `20260826T190051Z-3f7f3930`.

## Known boundary and rollback

- Transcript filtering proves a file exists, not semantic session quality.
  Owner-visible proof of opening prior context through a different route remains
  in `40-State/NEXT_ACTIONS.md`.
- Kiro is an owner-selected third-party relay. Its catalog and one successful
  request do not guarantee availability, model identity, privacy or future
  quota; transient 429 remains possible.
- Roll back this repair by reverting its parent commit, then rebuild
  `dashboard/static`. Runtime/auth/session files under `.runtime` and
  `provider_router/.ccr-local` are ignored and must not be committed or deleted
  as part of source rollback.
