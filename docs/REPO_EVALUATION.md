# Repository evaluation — Claude CLI multi-provider gateway

---
reviewed_at: 2026-08-24
status: adopted-pinned-local-runtime
---

## Outcome

The project adopted [Claude Code Router](https://github.com/musistudio/claude-code-router)
at package version 3.0.21 and source commit recorded in
`provider_router/SOURCE.json`. It supplies the missing Anthropic-facing gateway,
provider protocol conversion, model routing, streaming/tool handling, request
logs and a loopback management UI.

Claudy was retired. It was useful for choosing Anthropic-compatible profiles,
but one process-wide `ANTHROPIC_BASE_URL` did not meet the clarified requirement
for one Claude CLI to expose models backed by multiple native providers.

## Acceptance criteria

| Criterion | CCR result |
|---|---|
| One Claude CLI harness | Supported; launcher runs only local `bin/claude.exe` |
| Google/OpenAI/DeepSeek/custom APIs | Native/preset or custom provider protocols |
| Model-aware routing | `Provider/model`, routing rules and fallbacks |
| Streaming and tool conversion | Implemented by the gateway package |
| Windows | Node 22+ CLI supported; local copied Node runtime used here |
| Folder-local state | Supported through `CCR_INTERNAL_*` paths |
| Source review | MIT source repository and pinned commit |
| No global installation | Package and Node runtime live under `provider_router` |

## Boundaries

- API providers are declared in ignored root `setting.json` and synchronized
  through authenticated loopback RPC; tracked `setting.example.json` has no key.
- `DASHBOARD.bat` runs a pinned local official Codex helper for browser login
  and official read-only app-server quota snapshots, with a unique `CODEX_HOME`
  under project state for each account. It
  never reads a Windows/global Codex login or resolves an executable from PATH.
  Normal Add Provider remains for API keys/endpoints; arbitrary website sessions
  are not treated as model API auth.
- Management remains loopback-only.
- The package contains features for other agent surfaces, but this launcher does
  not invoke them; only Claude Code is an authorized harness in this project.
  CCR agent profiles are removed before save, and the launcher does not expose
  its agent UI because global/App scopes can modify external Codex/Claude state.
- No provider success is claimed until an owner-authorized real request verifies
  the configured endpoint/model and router log.
- Folder independence covers executable/config/auth/state paths. Browser login
  and upstream model APIs remain external network dependencies by design.

## Update review

`claude-code-router_proxy` is the owner's clean source fork at the same pinned
commit, on local branch `claude`, with the official repository configured as
`upstream`. `tools\RUN_CLAUDE_TECHNICAL.bat --fetch-router-source` fetches upstream and shows a
review diff; it never merges or changes the operational package. See
`docs/ROUTER_UPDATES.md`.
