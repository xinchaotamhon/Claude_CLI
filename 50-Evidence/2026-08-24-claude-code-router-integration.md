# Evidence — Claude Code Router integration

Date: 2026-08-24
Scope: `D:\mydata\new-git-3\claude_CLI-V`

## Accepted outcome

One project-local Claude Code CLI remains the only interactive harness. A
pinned Claude Code Router service translates/routes Claude requests to a
configured API provider over loopback. Provider CLIs, Codex delegation,
consumer-account rotation, system proxying and certificate interception are
outside this architecture.

## Provenance observed

- Claude: `bin/claude.exe`, `2.1.241 (Claude Code)`, `337745056` bytes; hash is
  recorded in `checksums/claude.exe.sha256`.
- Router package: `@musistudio/claude-code-router` `3.0.21`.
- Local runtime: Node `v24.12.0`.
- Reviewed source: `claude-code-router_proxy`, branch `claude`, commit
  `1347c868b493728a31c76098459584e0fcc23940`, MIT license.
- Source remotes: owner fork as `origin`; musistudio repository as `upstream`.
- Parent repository: initialized on unborn branch `claude`; nested source repo
  remains separate and ignored by the parent.

## Implementation evidence

- `RUN_CLAUDE.bat` resolves Claude, Node, CCR entry, update checker, installer
  and all three CCR internal data paths from this project root.
- Normal startup opens the local menu and performs no update/network check.
- Provider/profile state is under ignored `provider_router/.ccr-local`; the
  launcher stores CCR client keys as Windows DPAPI ciphertext.
- Model routes use exact `Provider/model` identifiers and support separate
  default/background/think/long-context selections.
- Before secret access, `Ensure-Router` invokes the pinned CCR start command and
  `Assert-VerifiedRouterService` checks the service JSON URL, PID, executable,
  command line and `http://127.0.0.1:3456/health`. An already-open port does not
  bypass identity verification.
- Static verification rejects non-loopback bind markers, provider CLI process
  invocation, system-proxy setup, certificate installation and MITM actions in
  operational launcher/menu files.
- Runtime reconstruction uses the committed lockfile with `npm ci --omit=dev`;
  npm is not required during normal startup.

## Cleanup performed by owner request

Deleted without backup:

- `claudy_provider-clitool/`
- `.claude-local/`
- obsolete Claudy/profile/bridge menu and verifier scripts
- obsolete Claudy/profile API documentation
- temporary source-review clones

Historical ADRs and evidence were retained and marked superseded because they
explain why the current architecture replaced them; they are not executable
dependencies.

## Reproducible focused checks

- `RUN_CLAUDE.bat --version` -> `2.1.241 (Claude Code)`.
- `RUN_CLAUDE.bat --router-version` -> `Claude Code Router 3.0.21`.
- `tools/verify_router_integration.py .` -> PASS; Node `v24.12.0`, router
  `3.0.21`, source fork/branch/commit and one-Claude-only boundary verified.
- `tools/router_project_menu.ps1 -Root . -SelfTest` -> PASS for DPAPI
  round-trip, route generation, local paths and service-identity hardening.
- Provider network/model request -> intentionally not run; no quota consumed or
  endpoint success claimed.

## Cumulative gates

Final enabled smoke run: `20260824T090422Z-7b63a04d`; all 6 enabled required
gates passed.

Raw logs are stored under
`50-Evidence/gate-logs/20260824T090422Z-7b63a04d/` and the append-only record is
`50-Evidence/events.jsonl`.

## Rollback

- A route/profile can be removed through `[D]`; upstream provider config is
  removed separately in `[M]`.
- CCR can be stopped with `[X]` or `RUN_CLAUDE.bat --router-stop`.
- Router upgrades are rollback-safe only when the previous reviewed pin/runtime
  is preserved before replacement. The deleted Claudy implementation has no
  backup by explicit owner instruction.
