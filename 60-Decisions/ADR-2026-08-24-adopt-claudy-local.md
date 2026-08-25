# ADR — Adopt the local Claudy fork as the provider adapter

---
date: 2026-08-24
status: accepted
decision_owner: Human owner
supersedes: ADR-2026-08-24-api-profile-menu.md
---

## Context

The project needs one Windows double-click entry point for a proprietary local
Claude Code binary and multiple provider profiles. It also needs a reviewable
way to use provider routes such as DeepSeek, Z.AI, OpenRouter and custom
Anthropic-compatible endpoints, while keeping runtime data inside this folder.

The owner forked Claudy into `claudy_provider-clitool` and wants the fork to be
reviewed independently, kept on a `claude` branch, and checked for upstream
changes without automatically merging them.

Source inspection showed that unmodified Claudy writes global MCP/skill state,
uses the normal Claudy home, and discovers Claude through PATH. Those defaults
are not sufficient for this independent folder.

## Decision

Use the local Claudy fork as the operational provider adapter behind
`RUN_CLAUDE.bat`. Keep the following boundaries:

- `CLAUDY_HOME` points to `claudy_provider-clitool/.claudy-local`.
- `CLAUDY_PROJECT_ONLY=1` activates source guards that skip global MCP/skill
  registration while retaining mode-local behavior.
- PATH puts this folder's `bin/claude.exe` before unrelated installations.
- The parent PowerShell menu stores profile metadata without secrets and stores
  credentials as Windows DPAPI ciphertext under the ignored local state tree.
- Claude and Claudy are checked for version/hash/release metadata at launch;
  nothing is automatically replaced or merged.
- The fork is kept on local branch `claude`; pushing remains an owner action.

The source fork also accepts `provider_overrides` for custom providers so the
old Opus/Sonnet/Haiku tier settings can be applied through the same routing
pipeline as built-in providers.

## Why not claude-switcher now

No extra `claude-switcher` binary is required for the current scope. The local
Claudy menu already handles provider/profile selection, OpenRouter aliases and
the fork's agent/handoff concepts. Adding another switcher would create a
second state store and another update boundary before the current integration
has been proven.

## Consequences

- The runtime build is a local release artifact and remains ignored; source and
  build provenance are reviewable, but the binary is not pushed to GitHub.
- DPAPI credentials are tied to the current Windows user. A moved copy must
  re-enter keys through the hidden prompt.
- OpenAI/ChatGPT and Google/Gemini are available through an OpenRouter alias or
  compatible gateway; Claudy's `codex`/`agy` handoff is a separate new-session
  bridge, not direct provider authentication.
- Same-profile concurrent terminals share that profile's Claude session store;
  different profiles have separate mode directories.
- Upstream Claudy changes require source review and smoke gates before merge.

## Rollback

Restore the last reviewed launcher/menu and stop using the local Claudy runtime;
the proprietary Claude binary is not modified. If the source fork needs to be
reverted, use normal local Git review on branch `claude`; do not use destructive
reset commands without the owner's explicit approval.
