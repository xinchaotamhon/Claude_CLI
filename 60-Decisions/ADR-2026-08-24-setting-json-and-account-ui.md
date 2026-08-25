# ADR — Root setting.json and separate CCR account UI

---
date: 2026-08-24
status: accepted
decision_owner: Human owner
extends: ADR-2026-08-24-adopt-claude-code-router.md
---

## Context

The owner wants one obvious file for manually entering provider API keys,
endpoints and models. `RUN_CLAUDE.bat` must not ask for new provider/profile
data. Account handling may use CCR's own interface through a separate BAT.

CCR 3.0.21 persists live configuration in SQLite. Its legacy `config.json` is
read only once for migration, so merely placing a JSON file beside the launcher
would not provide reliable ongoing configuration.

## Decision

- Use ignored root `setting.json` as the owner-edited local source for API
  providers, credential pools, model lists, launch profiles and Claude defaults.
- Track only secret-free `setting.example.json`.
- On first use or changed SHA-256, validate the complete file before mutation,
  then merge providers carrying the `local-setting--` ID prefix through CCR's
  authenticated loopback `getConfig`/`saveConfig` RPC into SQLite.
- Preserve providers/accounts created or imported through CCR UI. Reject a name
  collision instead of silently replacing them.
- Generate/reuse one CCR client key internally and store it as Windows DPAPI
  ciphertext; never prompt for it in the RUN menu.
- Make the RUN menu selection-only: numbered profiles, reload, status, stop,
  update and quit. Remove Add/Edit/Delete API/profile prompts.
- Add `SIGN_ACCOUNT.bat` for explicit account/API setup. Its initial UI-only
  behavior and later Windows-auth snapshot behavior are superseded for Codex by
  `ADR-2026-08-24-folder-local-codex-login-homes.md`.
- Enforce loopback gateway/management, proxy off, system proxy off, network
  capture off, request logs off and the Codex built-in routing rule off whenever
  `setting.json` is synchronized.

## Account boundary

Pinned CCR can detect/import usable local login state for supported integrations
such as Claude Code, Codex, ZCode and Kimi CLI. Availability depends on what CCR
actually detects; the UI does not create a universal OAuth flow for arbitrary
ChatGPT, Google or provider website accounts. Browser-based usage connectors are
not equivalent to model API authorization, and some are desktop-only.

Current Codex account login state originates from an official browser flow but
is written to a separate home inside this folder. The wrapper does not inspect
global Codex App/CLI state. Browser and provider endpoints remain external
network services; runtime/config/auth filesystem paths remain project-local.

## Consequences

- `setting.json` is easy to edit but contains plaintext provider secrets by
  owner choice. Git ignores it, while CCR also stores synchronized credentials
  in ignored SQLite.
- UI edits to a `local-setting--*` provider are overwritten on the next changed
  `setting.json`; UI-imported/non-managed providers are preserved.
- A malformed file causes no SQLite save. A valid file with a wrong real
  endpoint/key can still fail or consume quota when the owner launches/tests it.

## Verification and rollback

- `claude.setting-json-flow` verifies the ignored/tracked boundary, example
  schema, prompt-free menu and CCR-only account BAT without reading real secrets.
- `claude.router-menu-selftest` validates parser/merge/DPAPI and safe runtime
  defaults using isolated fake data and no RPC/provider request.
- Rollback: stop CCR, restore the previous menu/ADR design, remove the applied
  hash/client-key files under ignored `.ccr-local`, and explicitly decide how to
  treat `local-setting--*` SQLite providers. Never delete non-managed account
  providers as part of that rollback.
