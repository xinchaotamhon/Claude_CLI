# ADR-2026-08-24 — Official Codex ChatGPT login and local bridge

---
status: accepted
date: 2026-08-24
deciders: Human owner + Codex implementation review
---

## Context

The owner observed that signing in to Codex in the ChatGPT app also makes the
Codex CLI authenticated. The official OpenAI authentication documentation
confirms that Codex CLI supports `codex login` with a browser flow, that the
owner completes the sign-in/2FA step, and that the desktop app and CLI reuse the
same cached login details.

The local Claude launcher previously exposed only provider profiles. Selecting
the seeded `Legacy xapi.qhieu.dev` profile therefore asked for
`ANTHROPIC_AUTH_TOKEN`; that prompt is correct for the old Anthropic-compatible
gateway and unrelated to a ChatGPT/Codex login.

## Decision

Add an explicit ChatGPT/Codex route to the local menu and launcher:

- `[C]` opens a submenu for browser login, device-code login, status, account
  switch (logout + browser login), logout, and opening Codex CLI.
- Direct launcher flags expose the same actions for one-click use.
- The owner completes browser login and 2FA; the project never receives or
  prints the credential value.
- Each Claude profile mode receives an ignored `.claude.json` pointing to the
  local Claudy runtime's MCP server. Claude can therefore delegate a selected
  task to the locally installed Codex CLI's `ask_agent` bridge.
- The bridge inherits Codex's normal `CODEX_HOME`/OS credential-store choice so
  the app/CLI shared login continues to work. It does not copy the auth cache
  into `.claudy-local`.
- The obsolete `legacy-qhieu` provider profile is retired and is no longer
  seeded. Its exact project-local metadata, DPAPI record, and mode folder are
  removed on the next menu launch; other profiles and global state are left
  untouched.

## Non-goals

- Do not convert ChatGPT web tokens into `ANTHROPIC_AUTH_TOKEN`.
- Do not make Claude Code silently route every prompt through ChatGPT/Codex.
- Do not import email/password/2FA/session exports or create three unofficial
  web-session profiles.
- Do not mutate global Claude MCP/skill configuration. The bridge is written
  only to the active project's ignored mode configuration.
- Do not call Codex or an external provider in smoke tests.

## Consequences

The user can switch the active ChatGPT account through one menu action: choose
`[C]` then `[4]`, which logs out and starts the official browser login again;
the desired account is selected in the browser. Only one active Codex login is
used by the shared cache at a time, so this is a re-login switch rather than
three stored instant-switch slots. Claude remains the main session provider;
delegated Codex work is a separate agent call with its own account/plan limits.

The explicit login action is the one deliberate exception to this folder's
project-only boundary: it uses the Codex app/CLI cache outside the folder in
order to preserve the official app/CLI sharing behavior. The exception is
owner-triggered, visible in the menu, and documented.

## Verification and rollback

- Menu self-test verifies DPAPI protection and generation of the project-local
  MCP bridge without a network request.
- Local MCP initialize/tools-list smoke confirmed an `ask_agent` tool and a
  discovered `codex` agent; no delegated prompt was sent.
- Rollback: remove the `[C]`/`--codex-*` launcher route and stop generating the
  per-mode `.claude.json` bridge. The user's Codex login can be cleared with
  `codex logout`; no project credential migration is required.

## Official reference

- [Codex authentication](https://developers.openai.com/codex/auth/)
