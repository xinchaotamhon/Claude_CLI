# ADR — Portable sessions, direct terminals and deferred account import

- Date: 2026-08-26
- Status: accepted
- Owner: Human project owner

## Context

The first dashboard launch could show two consoles because Node started a CMD
batch dispatcher which then started PowerShell. Codex Plus login was also
rejected whenever the verified CCR gateway was serving an existing Claude
session. Google OAuth could silently reuse the browser's current account.
Legacy Claude sessions were fragmented across route-specific mode homes.

## Decision

1. Dashboard starts one detached PowerShell dispatcher directly; CMD is removed
   from the launch chain.
2. Every dashboard Claude launch receives a UUID and optional friendly name.
   Claude uses ignored `.runtime/claude-home`; the dashboard keeps only a local
   ignored index under `.runtime/claude-sessions`.
3. Existing mode session JSONL files are copied once into the common home
   without reading content, overwriting an existing destination or deleting the
   source. Resume uses Claude's official `--resume <uuid>` option.
4. Codex browser login may complete while CCR serves an active session, but
   CCR provider/config mutation is deferred. The account remains pending and is
   completed after active sessions close, without another login when auth is
   still valid.
5. Google OAuth always requests `select_account`; an optional validated email
   is passed as `login_hint`. Password and 2FA remain provider-owned.
6. Update checks are explicit, read-only public release metadata. No normal
   startup downloads, fetches source, merges or replaces binaries.
7. Reconstruction authority is tracked in `DEPENDENCIES.lock.json`, source and
   build records, patches and `docs/RECONSTRUCT_ON_NEW_MACHINE.md`. Secrets,
   account state and sessions remain intentionally untracked.

## Consequences

- Parallel terminals keep independent route environment and can resume the
  same local transcript. Multiple terminals on one provider account still
  share that provider quota.
- A pending account is visible and recoverable rather than forcing the owner to
  stop ongoing work before browser/2FA.
- A new machine can reproduce code/runtime structure, but must reauthenticate
  accounts and cannot recover uncommitted private sessions from Git.
- Provider plan/model entitlement and quota schema remain provider-controlled;
  a label such as “Plus” is an expectation, not proof of Sol entitlement.

## Rollback

Restore the prior route-specific `CLAUDE_CONFIG_DIR`, reinstate the old batch
dispatcher and restore fail-before-login account behavior. Do not delete the
common or legacy session directories during rollback; choose one session home
only after preserving both.
