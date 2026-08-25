# ADR — Keep the API profile menu local to the project

---
date: 2026-08-24
status: superseded
decision_owner: Human owner
superseded_by: ADR-2026-08-24-adopt-claudy-local.md
---

## Context

The project needs a Windows double-click entry point that lets the owner
choose among several Claude-compatible API credentials and endpoints. The
folder must remain independently movable and must not silently alter the
user's normal Claude installation or shell configuration.

Eight external projects were reviewed. They vary between global installers,
user-level Claude settings, 1Password integrations, small unreleased binaries,
and ambiguous package names. Their feature sets are useful, but none was
verified to satisfy the complete local-boundary contract.

## Historical decision

This ADR records the first direct PowerShell-menu design. It is retained for
provenance, but the operational decision is now recorded in
`ADR-2026-08-24-adopt-claudy-local.md`.

## Decision at the time

Use the project-local `tools/claude_profile_menu.ps1` behind
`RUN_CLAUDE.bat` as the current implementation. Do not install an external
switcher into this folder or globally as part of this decision.

Profiles contain non-secret metadata in `.claude-local\profiles\profiles.json`.
Credential values are entered interactively and stored in per-profile DPAPI
records under `.claude-local\profiles\secrets\`. Each launch receives the
selected credential and endpoint through its child process environment and
gets a profile-specific Claude configuration and temporary directory.

## Rationale

- It directly satisfies the requested double-click workflow.
- The launcher has one accepted executable target: `bin\claude.exe`.
- The secret value is not placed in the profile JSON, repository, or handoff
  documents.
- The implementation is small enough to audit, test, and roll back within the
  folder.
- It uses the documented Claude Code environment controls rather than editing
  the normal user-level settings file.

## Consequences

- DPAPI records are tied to the current Windows user context and are not a
  portable backup format. A moved copy must re-enter its credentials.
- A real provider request and interactive login remain owner-approved runtime
  actions; the smoke gates intentionally do not call an API.
- The menu is narrower than Claudy and does not provide provider discovery,
  session migration, or cross-tool bridges.
- If a third-party tool is later adopted, it must be pinned and audited as a
  replaceable component rather than silently mixed into the launcher.

## Rollback

Remove or restore only the menu/documentation changes and return
`RUN_CLAUDE.bat` to the previously recorded launcher version. The proprietary
`bin\claude.exe` is not modified by this decision.
