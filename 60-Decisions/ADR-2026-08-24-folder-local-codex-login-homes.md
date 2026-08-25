# ADR — Folder-local Codex login homes

---
date: 2026-08-24
status: accepted
decision_owner: Human owner
extends: ADR-2026-08-24-setting-json-and-account-ui.md
supersedes: ADR-2026-08-24-project-local-codex-account-snapshots.md
---

## Context

The earlier adapter copied the current Windows user's global
`.codex/auth.json` into CCR staging. It preserved local operational state but
violated the owner's stricter requirement that this project must not depend on
any executable, config or credential path outside its root.

OpenAI Codex supports browser ChatGPT login and stores auth/config under
`CODEX_HOME`; file-backed auth can be forced with
`cli_auth_credentials_store = "file"`. This permits isolated login homes.

## Decision

- Vendor one official Codex CLI binary at the fixed ignored path
  `provider_router/codex-login-runtime/codex.exe`.
- Track `provider_router/CODEX_LOGIN_SOURCE.json` with version, source, policy
  and SHA-256. Refuse login if the local binary does not match.
- Authorize that binary only for exact `login`; never `exec`, agent work,
  routing or the Claude harness.
- Before each login, choose a unique provider ID and create
  `provider_router/.ccr-local/codex-accounts/<id>`.
- Write only local `config.toml`, forcing file credential storage and ChatGPT
  login. Temporarily set both `CODEX_HOME` and `CODEX_SQLITE_HOME` to that home,
  run official browser login, then restore process environment.
- Do not discover `USERPROFILE`, Codex App state, global `~/.codex`, a PATH
  command or WindowsApps at runtime. Do not request/read password or 2FA.
- Check local auth-file existence without parsing/printing it; copy it only to
  guarded local CCR staging, use native authenticated import RPC, then remove
  staging and restore any prior file in `finally`.
- Preserve a separate login home and unique CCR provider/plugin/profile for
  each account so RUN can select them explicitly.
- Provide `tools/install_codex_login_runtime.ps1` only as an explicit repair or
  clone reconstruction path. Normal startup never downloads or updates.

## Boundary and consequences

- “Independent” covers filesystem paths, runtime selection, config, account
  state and staging. OpenAI browser login and model inference still require
  external network services; the project does not claim offline identity.
- The ignored login binary is large and is reconstructed explicitly after a
  Git clone. Its tracked metadata makes replacement reviewable by version/hash,
  not source diff.
- OAuth/auth and CCR SQLite remain sensitive ignored state and are not claimed
  encrypted at rest. Password/2FA remain in the official browser flow.
- Real entitlement, refresh, model availability and quota switching require a
  bounded owner-run test; deterministic gates make no provider request.

## Verification and rollback

- `claude.codex-account-import` checks local paths, per-account home settings,
  exact login-only invocation, provenance hash, Git ignore and lack of global
  path discovery without reading auth.
- `claude.router-menu-selftest` writes a fake account config under isolated
  test state and confirms required settings without opening browser/network.
- Rollback: stop CCR, restore the superseded wrapper, or remove only the named
  account's reviewed local provider/plugin/profile/home. Never delete all
  `.ccr-local` state and never modify global Codex/App login.
