# START HERE — Claude CLI Multi-Provider Local

This folder is an independent Windows runtime wrapper for one Claude Code CLI
harness. Claude remains the only interactive coding CLI. A project-local
Claude Code Router gateway may send model inference to Google Gemini, OpenAI,
DeepSeek, OpenRouter, Z.AI, Kimi, Ollama or another configured API endpoint.

This file is the stable local router for the project. It is not a credential,
runtime grant, update approval or factual replacement for the named state,
evidence and decision owners below. Resolve every relative path in this file
against the directory containing this file and set the working directory to
that root before running a local command. If a supplied local entry is missing,
stop with that exact path error; do not scan the machine or create a substitute
compatibility path.

## Project identity

- User surface: only `bin/claude.exe` and its normal Claude Code experience.
- Router: pinned `@musistudio/claude-code-router` running on loopback.
- Model route: `Provider/model`; the provider configured in the router owns the
  final upstream endpoint.
- Scope: local runtime, local configuration, encrypted launcher credentials,
  provider routing, provenance, update review and deterministic smoke gates.
- Non-goals: provider CLIs as coding harnesses, automatic quota rotation,
  password/2FA capture, decompiling Claude, bypassing provider authentication
  or silently changing software outside this root.

## Read order for every AI

1. [Project instructions](AGENTS.md)
2. [Project principles](00-Governance/PROJECT_PRINCIPLES.md)
3. [Information policy](00-Governance/INFORMATION_POLICY.md)
4. [Standard adoption receipt](00-Governance/STANDARD_ADOPTION.md)
5. [Machine-readable adoption receipt](00-Governance/STANDARD_ADOPTION.json)
6. [Adopted resources](10-Resources/RESOURCE_ADOPTIONS.json)
7. [Resource workflow](10-Resources/README.md)
8. [Verified state](40-State/CURRENT_STATE.md)
9. [Known failures](40-State/KNOWN_FAILURES.md)
10. [Resource candidates](40-State/RESOURCE_CANDIDATES.json)
11. [Next actions](40-State/NEXT_ACTIONS.md)
12. [Evidence index](50-Evidence/EVIDENCE_INDEX.md)
13. [Gate registry](gates/gates.json)
14. [ADR template](60-Decisions/ADR_TEMPLATE.md)
15. [Next AI handoff](80-Handoffs/NEXT_AI_PROMPT.md)

For runtime work, also read the [local router runbook](docs/ROUTER_LOCAL.md),
the [update policy](docs/ROUTER_UPDATES.md), the [repository evaluation](docs/REPO_EVALUATION.md)
the [new-machine reconstruction runbook](docs/RECONSTRUCT_ON_NEW_MACHINE.md) and
the [router adoption ADR](60-Decisions/ADR-2026-08-24-adopt-claude-code-router.md).

Routine continuation must be recoverable from this folder without chat history
or a parent directory. Prefer runtime evidence, then the canonical owner file.

## Folder map

- `bin/claude.exe`: proprietary local Claude Code binary; ignored by Git.
- `provider_router/package.json`: pinned open-source router dependency.
- `provider_router/SOURCE.json`: source, version, license and reviewed commit.
- `provider_router/runtime/node.exe`: project-local Node runtime; ignored.
- `provider_router/codex-login-runtime/codex.exe`: pinned project-local official
  Codex helper used for ChatGPT login and the read-only official app-server
  quota method; ignored and never used as the coding harness.
- `provider_router/CODEX_LOGIN_SOURCE.json`: tracked version, source and SHA-256
  provenance for that ignored login helper.
- `provider_router/node_modules/`: installed pinned router package; ignored.
- `provider_router/.ccr-local/`: provider config, API keys, client keys, logs and
  service state; ignored and sensitive.
- `claude-code-router_proxy/`: reviewable source fork on branch `claude`, with
  `origin` pointing to the owner's fork and `upstream` to musistudio. It is a
  separate nested Git repository and is ignored by the parent repository.
- `cli-proxy-api_core/`: ignored independent source checkout on branch
  `claude`. The reproducible parent-owned form is the pinned upstream commit
  plus tracked patches under `router_challenger/patches/`.
- `DASHBOARD.bat`: the single normal owner-facing entry point. It opens the
  authenticated loopback control room for accounts, quota, routes and new
  Claude terminals.
- `tools/RUN_CLAUDE_TECHNICAL.bat`: technical/rollback launcher; normal use is
  through the dashboard.
- `tools/RUN_CHALLENGER_PILOT_TECHNICAL.bat`: separate offline CLIProxyAPI
  fixture/status/stop surface; it is not a normal Claude launcher.
- `router_challenger/`: pinned CLIProxyAPI source/build metadata, tracked local
  isolation patch, deterministic fixture source and secret-free quota contract.
- `dashboard_easycli_source/`: ignored inspect-only EasyCLIProxyAPI source at a
  pinned tag. Missing license and unsafe integration surfaces block build/copy.
- `setting.json`: ignored local source of truth for API URL/key/model routes;
  it may contain plaintext secrets and must never be read into project memory.
- `setting.example.json`: tracked secret-free schema/example.
- `dashboard/`: original local-only React UI plus zero-dependency Node server.
  Built assets are tracked so normal startup does not install or build.
- `.runtime/claude-home/`: ignored common Claude config/session store used by
  dashboard launches. `.runtime/claude-sessions/index.json` is its local
  friendly index; neither belongs in Git.
- `DEPENDENCIES.lock.json` and `docs/RECONSTRUCT_ON_NEW_MACHINE.md`: exact
  machine-readable and human reconstruction routes for a fresh Windows clone.
- `tools/router_project_menu.ps1`: validates/synchronizes `setting.json` through
  CCR RPC, stores the generated client key with DPAPI and launches only Claude.
- `tools/install_router_runtime.ps1`: explicit reconstruction of the pinned
  project-local router runtime; it never runs during normal startup.
- `docs/ROUTER_LOCAL.md`: operation and provider/model setup.
- `docs/ROUTER_UPDATES.md`: closed Claude binary and open router review policy.
- `gates/`: cumulative deterministic checks.

## One-click operation

Use one canonical front door: double-click `DASHBOARD.bat`. Accounts, quota,
route/model selection and separate Claude terminals are all handled there.
The project root intentionally contains only this one BAT. Technical rollback
launchers live under `tools/`. The challenger technical launcher is only for
an isolated offline self-test and must not be described as account/model use.
Tool, provider or model availability never grants
permission to install, update, consume quota, expose data or change an external
account.

For a custom API, use the dashboard's **Mở setting.json** button, set the desired
provider/profile entries to `enabled: true`, then return to the dashboard. On first use or after a
file change, the launcher validates the whole file and merges only its managed
providers into CCR's SQLite database through authenticated loopback RPC. It
preserves account/providers managed in the CCR UI and automatically protects
the generated CCR client key with Windows DPAPI. The RUN menu never asks for a
new API key, URL or profile.

For a ChatGPT/Codex account, open `DASHBOARD.bat`, choose **Codex Free** or
**Codex Plus**, then complete password/2FA in the official browser
page. The wrapper runs only the pinned local login helper with a fresh
`CODEX_HOME` under `provider_router/.ccr-local/codex-accounts`, imports that
account into CCR, creates its dashboard routes and removes temporary CCR staging.
Free candidates are Terra/Luna; Plus candidates are Sol/Terra/Luna, but actual
entitlement is retained only after the bounded provider check. No global
Codex/App login is read or changed.

If a Claude/router session is already active, browser login is still saved in
that account's project-local home, but CCR configuration is deliberately left
untouched. Close active Claude terminals and click **Hoàn tất nhập tài khoản**;
the import resumes from the saved login without repeating browser/2FA while
that login remains valid.

Choose **Thêm tài khoản Google**. The dashboard allocates the next bounded slot
(up to 50); each slot stores its ignored
OAuth result under `.runtime/challenger/accounts/google`, invokes only the
hash-pinned local challenger binary, and binds its temporary OAuth callback to
`127.0.0.1` on a fixed per-slot port. The wrapper never asks for or parses the
password, 2FA or credential JSON. Configure DeepSeek/OpenRouter/custom API keys
and endpoints only in ignored `setting.json`.
The optional email field is only an OAuth `login_hint`; Google still displays
its own account chooser and owns password/2FA. The project never stores that
email as a credential.

After a route is selected and **Mở terminal** is pressed, the launcher starts
that exact route in a new terminal. Existing terminals keep their process-local
route; multiple terminals may share one account or use different accounts.
Every dashboard launch receives a UUID and optional friendly name. Use
**Mở lại công việc cũ** to resume it; Claude transcript files remain only under
ignored `.runtime/claude-home`. Legacy mode sessions are copied there once,
without reading content or deleting the original files.
The launcher may warm the router in a hidden
project-local process. Before the profile's DPAPI client key is read, route
selection still verifies that router state belongs to the exact local Node/CCR
process and that its loopback health endpoint succeeds. An unrelated process
on the same port is rejected; warmup failure falls back to synchronous verified
startup.

Normal control flow:

```text
DASHBOARD.bat -> authenticated http://127.0.0.1:18320
  -> exact account/model route -> new terminal
  -> validate/sync changed setting.json to project-local CCR SQLite
  -> project-local router on 127.0.0.1:3456
  -> bin/claude.exe with ANTHROPIC_BASE_URL pointing to loopback
  -> router resolves Provider/model
  -> configured upstream API endpoint
```

An API key entered in `setting.json` is plaintext by owner choice, but the file
is ignored by Git; CCR also persists the synchronized provider credential in
its ignored SQLite data. The generated gateway client key is stored only as
Windows-user DPAPI ciphertext. None belongs in Git or documentation.

Useful explicit commands:

```text
DASHBOARD.bat
tools\RUN_CLAUDE_TECHNICAL.bat --version
tools\RUN_CLAUDE_TECHNICAL.bat --router-version
tools\RUN_CLAUDE_TECHNICAL.bat --router-stop
tools\RUN_CLAUDE_TECHNICAL.bat --check-updates
tools\RUN_CLAUDE_TECHNICAL.bat --fetch-router-source
tools\RUN_CLAUDE_TECHNICAL.bat --install-router
tools\RUN_CHALLENGER_PILOT_TECHNICAL.bat
```

`--install-router` is an explicit dependency operation, not a startup side
effect. Normal operation uses only the copied Node runtime and installed package
inside this folder. If the ignored Codex login binary is absent after cloning,
explicitly run `tools\install_codex_login_runtime.ps1`; normal dashboard startup
never downloads or updates it.

## Safety and Git boundary

- Never commit API keys, client keys, OAuth tokens, cookies, account exports,
  sessions, request bodies, router databases or provider logs.
- Never remove `/setting.json` from `.gitignore`; use `setting.example.json`
  when sharing schema or asking an AI for help.
- Never use consumer website credentials as provider API credentials.
- While a Claude/router session is active, account browser login may be saved,
  but provider import/config mutation must remain deferred until those sessions
  close.
- Never point `CODEX_HOME` at a user/global folder. Each account home must stay
  under `provider_router/.ccr-local/codex-accounts`.
- Never create a CCR `Connect agent` profile. In particular, `System default`
  and `CLI & APP` can modify `~/.codex`, `~/.claude` or an external desktop app.
  The launcher removes CCR agent profiles and does not expose the agent UI.
- Bind management and gateway services only to `127.0.0.1` unless a separate
  security decision explicitly authorizes remote access.
- A model name does not prove final egress. Confirm the provider name, endpoint
  and router request log before claiming a request went directly to Google,
  OpenAI, DeepSeek or another provider.
- Provider APIs can consume quota. Connectivity checks and real model tests
  require owner action.
- The closed Claude binary is reviewed by version, hash and release notes. The
  open router is reviewed by pinned package/source commit and source diff.
- No automatic update, merge, binary replacement or global npm installation.
- The dashboard's update button may read public GitHub release metadata only;
  it never fetches a working branch, merges or replaces an executable.
- `.gitignore` excludes the Claude binary, Node runtime, installed dependencies,
  local Codex login binary, `.ccr-local`, temporary review clones and
  secret-shaped files.

“Independent folder” here means normal runtime executables, configuration,
account state and temporary files are selected from this project only. Browser
login and model use still require the corresponding provider's network service;
the folder cannot make OpenAI/Google/other providers offline or self-hosted.
Git for Windows, PowerShell and a browser are explicit host dependencies. A
fresh clone is reconstructed from `DEPENDENCIES.lock.json` and
`docs/RECONSTRUCT_ON_NEW_MACHINE.md`; OAuth/API secrets and sessions are not
silently published as a portability shortcut.

## External authoritative references

- [Claude Code environment variables](https://code.claude.com/docs/en/env-vars)
- [Claude Code installation](https://code.claude.com/docs/en/installation)
- [Claude Code Router source](https://github.com/musistudio/claude-code-router)
- [OpenAI Codex authentication](https://learn.chatgpt.com/docs/auth)
- [OpenAI Codex environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables)

Stable navigation belongs here. Versions and current gate results belong in
state/evidence, not this file.
