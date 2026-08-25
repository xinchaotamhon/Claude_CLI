# Evidence — ChatGPT Free account boundary

---
observed_at: 2026-08-24
observer: codex
status: verified
---

## Request

The owner asked to apply three ChatGPT Free account records to the local
Claude/Claudy profile system.

## Sanitized observation

The owner-provided local text export was read in memory for structural
inspection only. Values were not printed or retained. The file contained:

- exactly 3 non-empty JSON records;
- account fields, password fields and 2FA fields in each record;
- nested session-token fields in each record: access token, account ID, ID token
  and refresh token;
- an `OPENAI_API_KEY` field present but empty in all 3 records.

No email, password, 2FA value, token, cookie, account ID, or source-file copy
was written to this project. No external login, token refresh, API request, or
provider test was performed.

## Interpretation

These are consumer ChatGPT web-account credentials, not OpenAI API keys. The
current Claudy integration supports Anthropic-compatible provider routes and
OpenRouter aliases; it does not support using ChatGPT web sessions as a Claude
provider.

## Result

Import was deliberately not performed. The project documents the safe supported
alternatives: OpenRouter with its own API key, an owner-controlled
Anthropic-compatible gateway, or a separately reviewed official OpenAI API
adapter.

## Reproduction boundary

The original export remains outside the project. Any future inspection must
repeat this value-suppression rule and must not send the records to a network
service or write them into project state.
