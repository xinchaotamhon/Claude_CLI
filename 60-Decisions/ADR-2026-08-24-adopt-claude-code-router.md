# ADR — Use Claude Code Router behind one Claude CLI

---
date: 2026-08-24
status: accepted
decision_owner: Human owner
supersedes:
  - ADR-2026-08-24-adopt-claudy-local.md
  - ADR-2026-08-24-codex-chatgpt-login-bridge.md
---

## Context

The owner clarified that Claude Code CLI must remain the only harness and user
surface. The selected model may be served by Google, OpenAI, DeepSeek,
OpenRouter or another API, but no Codex/Gemini/provider CLI may be used as an
agent or backend process. Claudy selects one compatible endpoint per process;
it does not provide the required native multi-protocol gateway.

## Decision

Adopt the MIT-licensed `musistudio/claude-code-router` package at pinned version
3.0.21/source commit `1347c868b493728a31c76098459584e0fcc23940` as a
project-local loopback gateway.

- Keep Claude at `bin/claude.exe` as the only interactive CLI.
- Bind CCR management/gateway to loopback ports 3458/3456.
- Route all CCR state into `provider_router/.ccr-local` using its supported
  internal path variables.
- Keep a project-local Node runtime and installed package; normal operation has
  no global Node/npm dependency.
- Store upstream provider keys in ignored CCR state and launcher client keys as
  ignored Windows DPAPI ciphertext.
- Pin package/source provenance and review upstream source without auto-merge.
- Keep `claude-code-router_proxy` as the separate reviewable source fork on
  branch `claude`; keep the built npm runtime under `provider_router`.
- Before decrypting a launcher client key, require service-state, PID,
  project-local executable/command-line and gateway-health verification. Never
  treat a listening port as proof of router identity.
- Keep CCR request logging off by default; body capture is sensitive project
  data when explicitly enabled for a bounded diagnostic.
- Use CCR only as a provider gateway. Remove all CCR agent profiles before save
  and do not expose its agent UI; `System default` / `CLI & APP` are incompatible
  with the folder-isolation invariant because they can write external app/user
  configuration.
- Retire and delete the operational Claudy fork, Codex login menu/flags and MCP
  bridge. Historical evidence remains evidence, not operational authority.

## Alternatives

- Keep Claudy: rejected because it is a profile launcher, not the required
  native Gemini/OpenAI/DeepSeek protocol transformer.
- Write a new proxy from scratch: rejected because streaming, tool-call IDs,
  protocol conversion, fallback and model discovery already have a maintained
  open-source implementation.
- Use provider CLIs: rejected because the owner requires one Claude CLI only.
- Install CCR globally: rejected because the folder must remain operationally
  independent.

## Consequences

- Provider configuration uses ignored project-local `setting.json`; account
  browser login uses `SIGN_ACCOUNT.bat`. The CCR agent UI is not an operating
  surface. Normal coding still occurs only in Claude CLI.
- The ignored `.ccr-local` and runtime can be large and sensitive.
- A provider/model name alone does not prove final egress; logs and configured
  upstream endpoint are required evidence.
- A first real provider call remains owner-controlled because it may consume
  quota.

## Verification and rollback

- `claude.router-local-layout` verifies the pinned runtime/layout offline.
- `claude.router-menu-selftest` verifies DPAPI, settings and Claude-only wiring.
- Both current gates enforce loopback-only/service-identity behavior before
  secret access and reject provider CLI/system-proxy/certificate interception
  in operational launcher files.
- Older Claudy gates remain recorded but disabled with explicit replacements.
- Rollback: restore a reviewed prior design through a new ADR and gates. No
  deleted Claudy runtime backup is retained because the owner explicitly
  requested deletion without backup.
