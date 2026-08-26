# Google OAuth And Session Trash Repair — 2026-08-27

## Scope and invariant

- Scope: project-local Google Pro onboarding, pinned CLIProxyAPI challenger,
  dashboard session deletion and their deterministic gates.
- Invariant: credentials and transcripts stay inside ignored project runtime;
  Google callbacks bind only IPv4 loopback; no session content is read or
  permanently deleted by the dashboard action.
- Non-goal: reuse or inspect credentials from the separately installed
  Antigravity application. Its executable path was observed only to confirm the
  owner has it installed.

## Reproduction and causes

1. Direct `google_pro_1` onboarding failed at `Get-SlotState` before OAuth:
   PowerShell reported that `.Count` did not exist. The zero-file conditional
   had emitted `$null` instead of an array.
2. After forcing the empty collection to an array, the helper reached Google's
   OAuth page but timed out without a callback. Source inspection proved the
   callback listener was `127.0.0.1` while `redirect_uri` still used
   `localhost`; these are not guaranteed to resolve to the same address family.
3. Retrying the already-created empty slot failed at `Set-Acl` with missing
   `SeSecurityPrivilege`. ACL metadata showed the directory was already owned
   by and granted only to the current user; rewriting owner metadata was both
   unnecessary and non-idempotent.

No auth JSON content, access token, refresh token, password, 2FA value or
session transcript was read during diagnosis.

## Controlled repair

- `tools/challenger_account_menu.ps1` now preserves an empty auth-file
  collection as an array and self-tests that unused slot state.
- Current-user-only ACL setup returns when the exact protected ACL is already
  present, verifies ownership before mutation, and does not rewrite owner/audit
  metadata. Its self-test applies the operation twice to one exact temporary
  project child and removes only that temporary directory.
- Nested CLIProxyAPI branch `claude` adds reviewed commit
  `e835220044fb7f9bbe3f21ef3705864d4ded6cd1`, tree
  `f823d155849f2be31d7de3c19adb90e65146e6f8`. Tracked patch:
  `router_challenger/patches/0004-fix-align-antigravity-oauth-callback-host.patch`,
  SHA-256 `51ef6e57763943871da68253f55ae76a357fe375bd5e5b0854218fe85cb95e50`.
- Reproducible binary `7.2.141-local.4`: SHA-256
  `3d3f909e0a59d810c415be65b1fbd1941a79a32eeb1e3d6a7eb1ac730b25d70e`,
  size 65,938,432 bytes. `tools/build_challenger.ps1` rebuilt the same hash;
  fixture hash remained
  `f3205d4fa5102b2f8e1d4748dccc028929e84078b9911420116c35122aef48e2`.
- The live helper then displayed the corrected
  `redirect_uri=http://127.0.0.1:51121/oauth-callback` and waited for the
  official Google callback. Final provider authorization remains an explicit
  owner/browser step unless a later evidence update records completion.

## Recoverable session deletion

- Dashboard adds **Xóa** beside each resumable session and requires an explicit
  browser confirmation plus exact server-side session-ID confirmation.
- A session whose recorded terminal PID is still running is rejected.
- Discovery selects only an exact UUID-named `.jsonl` under the isolated common
  Claude home. The transcript is moved, not unlinked, to
  `.runtime/claude-sessions/trash/<uuid>-<nonce>/claude-home/...`.
- A secret-free recovery manifest records relative file names and session index
  metadata. Index removal occurs only after all selected files move; partial
  failure attempts rollback and removes only the exact new trash batch.
- Focused verification reads source markers only; it does not read or alter any
  real transcript.

## Closed terminal-history cleanup

- **Xóa mục đã đóng** requires a separate confirmation explaining that session
  and transcript data remain untouched.
- The server recomputes each recorded PID at action time, writes back every
  running record, and removes only non-running rows from the ignored terminal
  registry. It has no process-stop, session-index or Claude-home operation.
- The focused gate does not invoke the cleanup endpoint and therefore does not
  change the owner's current terminal list.

## Gates and observed results

- `go test ./sdk/auth`: pass, including exact IPv4 redirect test.
- `tools/build_challenger.ps1`: pass with the binary and fixture hashes above.
- `challenger.cli-proxy-source-pin`: pass at the four-patch tree.
- `challenger.google-account-flow`: pass, including retry-safe empty slot/ACL
  self-test; no browser or credential file was read by the gate.
- `claude.session-trash`: pass; runtime data not modified.
- Full owner-profile smoke run `20260826T202334Z-d7f6d1a7`: **21/21 pass**,
  including `claude.terminal-history-cleanup`.
- `tools/start_dashboard.ps1` replaced only the outdated owned dashboard
  process; the new ready-state SHA-256 matched the tracked `server.mjs`, the
  process remained running on `127.0.0.1:18320`, and a bounded follow-up
  `/health` check returned the same hash. The first immediate two-second probe
  timed out during startup settling and is not treated as the final health
  observation.

## Rollback

1. Parent rollback: revert the parent commit containing dashboard/helper,
   metadata and patch 4; rebuild static dashboard assets.
2. Challenger rollback: reset only the ignored nested checkout to
   `bcc28e6133a38b2185e04c631c9e662dbf28e9c3`, restore the prior tracked
   `SOURCE.json`/`BUILD.json`, then run the pinned build procedure.
3. Session deletion rollback for an individual action: use its local trash
   manifest to move the exact relative transcript back under
   `.runtime/claude-home`, then restore its index record. Never replace or
   delete the whole Claude home.
