# Evidence — folder-local Codex login homes

Date: 2026-08-24
Scope: `D:\mydata\new-git-3\claude_CLI-V`

## Baseline and root cause

- Baseline before this correction: all 8 enabled smoke gates passed in
  `20260824T103306Z-3cd61d88`.
- Inspection confirmed the prior importer resolved the Windows user profile and
  copied global `.codex/auth.json`. That was functional staging, but it did not
  meet strict folder independence.
- No real auth file, `setting.json`, SQLite credential or DPAPI plaintext was
  read into this evidence.

## Implemented control flow

1. `SIGN_ACCOUNT.bat` enters the project account menu.
2. Option `[1]` obtains a unique account label/ID from project-local CCR config.
3. The wrapper creates `.ccr-local/codex-accounts/<id>/config.toml`, forces
   file-backed ChatGPT login and sets local `CODEX_HOME`/`CODEX_SQLITE_HOME`.
4. Only the pinned local binary is invoked, and only with `login`; browser owns
   password/2FA.
5. The resulting local auth path is checked but not parsed/printed. Guarded CCR
   staging is cleaned/restored, and unique provider/plugin/RUN route is saved.

## Binary provenance

- Path: `provider_router/codex-login-runtime/codex.exe` (Git ignored).
- Observed version: `codex-cli 0.149.0-alpha.4.1`.
- SHA-256:
  `73d6d4a082a7cad601a446a45b1b3fa9b77aff9d3996052b74d9003d7947d515`.
- Source at adoption: OpenAI Codex desktop bundled CLI package recorded in
  `provider_router/CODEX_LOGIN_SOURCE.json`.
- Explicit reconstruction uses OpenAI's documented standalone installer with
  install and state destinations constrained under the project.

## Offline verification

- Focused account verifier: PASS for local binary/hash, separate account homes,
  forced file auth, exact login-only invocation, no global path discovery,
  staging cleanup and RUN route integration.
- Router menu self-test: PASS for fake local login config, multi-account plugin
  identity, route round-trip, DPAPI and safe loopback defaults.
- Cumulative smoke: 8/8 PASS in `20260824T111228Z-0396a8b8` after code changes.
- Browser login, import RPC against a real account and model request were
  deliberately not run; no quota was consumed by verification.

## Rollback

The staging transaction tracks whether it actually copied local auth before
cleanup, preventing a failed browser login from deleting an existing CCR file.
Operational rollback removes only reviewed named account records/home after CCR
is stopped. Global Codex/App state is neither input nor rollback target.
