# ADR — Import Codex login snapshots into the project-local router

---
date: 2026-08-24
status: superseded
decision_owner: Human owner
extends: ADR-2026-08-24-setting-json-and-account-ui.md
supersedes_scope: SIGN_ACCOUNT Codex-import behavior
superseded_by: ADR-2026-08-24-folder-local-codex-login-homes.md
---

## Context

> Historical record only. The current design no longer reads a Windows/global
> Codex auth file; see the superseding ADR above.

CCR 3.0.21 can import a Codex login, but its scanner resolves
`CCR_INTERNAL_HOME_DIR/.codex/auth.json`. This project intentionally points that
home at `provider_router/.ccr-local/home`, so the standard Add Provider wizard
hides the import panel even when Windows has a usable Codex login. The visible
OpenAI/custom-provider screens accept API keys, not ChatGPT/Codex account login.

The owner requires one Claude CLI harness, project-local runtime state and easy
switching among separately imported Codex accounts.

## Decision

- Keep the upstream CCR package pinned and unmodified. Implement the adaptation
  in the project wrapper so an upstream update remains reviewable.
- Change `SIGN_ACCOUNT.bat` to open a project account/API menu.
- On the explicit Codex-import action only, copy the fixed current-Windows-user
  `.codex/auth.json` to guarded project-local staging. Never accept an arbitrary
  auth path, parse it in PowerShell or print its contents.
- Superseded 2026-08-26 by the deferred-import decision: browser auth may be
  saved while the verified CCR gateway serves Claude, but import/config mutation
  remains refused until active sessions close.
- Call CCR's authenticated `getLocalAgentProviderCandidates`,
  `importLocalAgentProvider`, `getConfig` and `saveConfig` RPC methods.
- Materialize unique provider IDs and OAuth plugin keys from the chosen account
  name. Reject the same detected account ID or provider name twice.
- Save a secret-free route index in ignored `.ccr-local/account-profiles.json`
  so imported accounts appear automatically in `RUN_CLAUDE.bat`.
- Remove staged auth in `finally`, restore any prior local auth file, and stop
  management after import so the next gateway compilation uses each stored
  account snapshot rather than one temporary live login.
- Keep the CCR provider UI as option 2 for API endpoint/key providers.

## Boundaries and consequences

- This does not launch Codex CLI as a harness and does not make arbitrary
  ChatGPT website sessions into API keys. It imports only a Codex login already
  represented by the current Windows user's supported auth file.
- To add another account, the owner switches the Windows Codex login, then runs
  the explicit import again with a different name.
- CCR stores imported OAuth material in its ignored project-local SQLite config.
  Git isolation is verified, but SQLite is not claimed to be encrypted at rest.
- `importLocalAgentProvider` may contact the Codex backend to refresh/probe the
  model catalog. That network action occurs only after the owner chooses import;
  deterministic gates never invoke it.
- Long-lived refresh and quota behavior remain unproved until one bounded real
  request is run for each imported account.

## Verification and rollback

- `claude.codex-account-import` statically proves staging boundaries, cleanup,
  unique identity, duplicate protection and RUN route integration without
  reading real credentials.
- `claude.router-menu-selftest` proves placeholder materialization and the
  account-route round trip with fake offline values.
- Rollback: stop CCR, restore the prior BAT/menu files, and remove only the
  explicitly selected imported provider/plugin/profile records after owner
  review. Never delete all SQLite state or external Windows login files.
