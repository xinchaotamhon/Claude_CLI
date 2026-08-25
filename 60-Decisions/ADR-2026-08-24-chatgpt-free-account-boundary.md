# ADR-2026-08-24 — ChatGPT Free account boundary

---
status: accepted
date: 2026-08-24
deciders: Human owner + Codex implementation review
---

## Context

The owner asked to apply three ChatGPT Free accounts to the local Claude Code
profile menu. A local export was inspected without printing its values. It
contained three JSON records with web-account fields (`email`, `password`,
`2fa`, and nested session tokens including `access_token`, `id_token`, and
`refresh_token`). The `OPENAI_API_KEY` field was empty in all three records.

Claudy profiles in this project route Claude Code to an Anthropic-compatible
provider and store only a provider credential entered through the hidden prompt.
They are not a web-browser login manager or a ChatGPT-session emulator.

## Decision

Do not import, test, refresh, rotate, or route the three ChatGPT web-account
credentials through Claude/Claudy. Do not copy the export, its values, or a
derived personal-data manifest into this project. The source export remains
untouched and no network request was made with those credentials.

The supported OpenAI-model paths remain:

1. An OpenRouter profile, with its API key entered interactively and stored as
   Windows-DPAPI ciphertext.
2. An owner-controlled Anthropic-compatible gateway, configured as a custom
   provider.
3. A future explicitly reviewed adapter for an official OpenAI API key; an
   OpenAI API key alone is not a Claude-compatible endpoint.

The normal menu must explain this boundary rather than displaying a broken
"ChatGPT Free" profile. `claude-switcher` is not required for this decision.

## Evidence and verification

- Sanitized inspection: exactly three records; all had web-login/session-token
  fields; all had an empty `OPENAI_API_KEY` field.
- No credential value, email, token, cookie, or account identifier was written
  to project files, DPAPI state, Git, logs, or handoff material.
- The local Claudy profile menu remains the only supported credential entry
  path for this project.
- See [sanitized evidence](../50-Evidence/2026-08-24-chatgpt-account-boundary.md).

## Consequences

The three ChatGPT Free accounts cannot be selected as Claude provider profiles.
This avoids relying on undocumented web-session behavior and avoids turning
consumer subscription credentials into an unofficial API bridge. OpenAI models
can still be used through an authorized API-compatible route when the owner
provides the appropriate provider credential.

## Rollback

No source, runtime, or credential state was changed by this decision. Rollback
is therefore limited to reverting this documentation decision if the owner
later chooses a separately reviewed, authorized integration design.
