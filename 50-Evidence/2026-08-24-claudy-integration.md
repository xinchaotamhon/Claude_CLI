# Claudy local integration evidence — 2026-08-24

## Scope

Applied the owner fork at `claudy_provider-clitool` inside the active project
root, created/used local branch `claude`, built the patched Windows runtime,
and routed `RUN_CLAUDE.bat` through the project-local Claudy menu. No API key
value is recorded in this evidence.

## Source and runtime provenance

| Item | Observed |
|---|---|
| Fork path | `D:\mydata\new-git-3\claude_CLI-V\claudy_provider-clitool` |
| Fork branch | `claude` |
| Fork commit | `05cbdc9462124214a15b50473e12970a3af5f23a` |
| Upstream remote | `https://github.com/epicsagas/claudy.git` |
| Claudy build command | `cargo build --release --no-default-features` |
| Claudy runtime version | `claudy 0.8.0` |
| Claudy runtime SHA-256 | `10D674E2F36FBD0F838049A0A5311DF97F55FDBCB1ED32C4C9EACE7FC4970583` |
| Claude local version | `2.1.241 (Claude Code)` |
| Claude local SHA-256 | `C49A05922A787C33478067A5164002932235F6611948523B55AE1FBDB303AC1F` |

The Claudy runtime is generated/ignored; the source fork is the reviewable
artifact. The nested repository working tree was clean after the local commit.

## Source changes applied

- Added `CLAUDY_PROJECT_ONLY` detection and guards around global MCP/skill
  registration.
- Kept mode-local settings/skills available while skipping user-global writes.
- Added custom-provider model/tier overrides so the legacy Opus/Sonnet/Haiku
  values can route through a custom Anthropic-compatible endpoint.
- Made Unix-only symlink/agent tests platform-aware for Windows.
- Added a Windows deterministic layout test and a custom-tier resolver test.
- Added nested ignore rules for runtime output and `.claudy-local` state.

## Checks

| Check | Result |
|---|---|
| `cargo fmt --all -- --check` | PASS |
| `cargo test --no-default-features --lib --bins --tests` | PASS: 368 unit tests, 4 differential tests, 7 integration tests |
| `routing::resolver` regression group | PASS: 9 tests |
| `runtime\claudy.exe --version` | PASS: `claudy 0.8.0` |
| `tools\verify_claudy_integration.py .` | PASS; no secrets read |
| Claudy menu DPAPI self-test in Windows profile | PASS |
| Profile template/config generation with no credential | PASS; metadata/config/settings contain no key |
| `RUN_CLAUDE.bat --version` | PASS: local Claude `2.1.241` |
| `RUN_CLAUDE.bat --claudy-version` | PASS: local Claudy `0.8.0` |
| Custom legacy route with fake credential + `--version` | PASS: routed through Claudy to local Claude; no provider request |
| Cumulative smoke tier | PASS: 6/6 in run `20260824T070306Z-eba22755` |

Smoke logs: [gate-logs/20260824T070306Z-eba22755](gate-logs/20260824T070306Z-eba22755/).

## Update-check verification

The update checker successfully observed, with network permission:

- Claude official latest tag `v2.1.241`, matching the local version;
- Claudy official latest tag `v0.8.0`, local status `current`;
- local fork HEAD `05cbdc9...` differs from upstream main
  `89ff3f5...` because the local project-only/custom-tier patch is committed;
- `RUN_CLAUDE.bat --fetch-updates` fetched `upstream/main`, reported no commits
  available to merge, and displayed a nine-file diff stat without changing
  the working tree or merging.

The normal sandboxed check also handles TLS/network failure as `OFFLINE` and
continues without changing local files. No binary download, replacement,
automatic update, merge or push was performed.

## Secret and provider boundary

The old setting's non-secret values were parsed into a local legacy profile:
endpoint, model tiers, telemetry, permissions, effort and theme. The supplied
credential was not copied into source, JSON, Markdown, Git, or the runtime.
The first profile launch asks for it as hidden input and stores only a Windows
DPAPI ciphertext under ignored `.claudy-local` state.

OpenRouter alias routes can target compatible OpenAI/Gemini model IDs when
available. Claudy's `codex`/`agy` features are agent/handoff bridges, not direct
ChatGPT/Gemini provider authentication. No real provider request was made.
