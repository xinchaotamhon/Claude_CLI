# Evidence — Portable session, account selection and update repair

- Date: 2026-08-26
- Scope: offline implementation checks; no real OAuth/model request performed

## Baseline and observed causes

- Parent rollback checkpoint: `ccb6da7` on branch `claude`.
- Codex homes contained three completed Free logins and no Plus home. The old
  importer rejected a verified running router before opening a browser login.
- The old launch chain was Node -> `cmd.exe` -> batch -> PowerShell -> Claude,
  explaining the extra blank console.
- Claude Code `2.1.241 --help` exposes `--session-id`, `--name` and `--resume`.
- Legacy session filenames were observed as UUID metadata only; transcript
  content was not read.

## Implemented controls

- Direct PowerShell dispatcher with allowlisted actions; old terminal batch was
  removed.
- Common ignored Claude session home, local session index and non-destructive
  one-time legacy copy.
- Two-phase Codex login/import when CCR is active.
- CLIProxyAPI patch commit
  `bcc28e6133a38b2185e04c631c9e662dbf28e9c3` adds Google account chooser and
  optional login hint. Rebuilt challenger SHA-256:
  `322468f600e7e3f85034a964c4f2852bcd87da0bbfbcf82fd572e53eb4d3d95c`.
- Explicit update cards and a reconstruction lock/runbook; no automatic update.

## Verification

- CLIProxyAPI Go tests passed for Antigravity auth and SDK auth packages.
- Reproducible challenger build passed and matched tracked binary/fixture hashes.
- Dashboard Node syntax/self-test passed.
- Dashboard TypeScript check and production build passed.
- PowerShell parser accepted router, Google account and terminal dispatchers.
- Focused verifiers passed: local dashboard, Codex account import, Google
  account flow and CLIProxyAPI source pin. These checks read no auth file,
  `setting.json` secret or session transcript and made no provider request.
- The final cumulative smoke run `20260826T171253Z-f404c4ef` passed all 18
  enabled gates under the owner Windows profile, including DPAPI. The earlier
  sandbox run's DPAPI/profile failure is environment evidence only, not a
  production regression.

## Remaining owner proof

Close active Claude terminals, add the intended Plus account and confirm which
models the provider accepts. Add one Google account with its email hint and
confirm the Google account chooser, then refresh both quota branches. Open a
new named session and resume it from the dashboard; verify only one console is
created. These live steps consume external account/network state and are not
claimed by this offline evidence.
