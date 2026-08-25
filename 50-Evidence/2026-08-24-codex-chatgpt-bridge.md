# Evidence — official Codex ChatGPT login bridge

---
observed_at: 2026-08-24
observer: codex
status: verified
---

## Baseline

- Codex CLI was discoverable on the Windows PATH.
- A Codex authentication-cache file existed, but its contents were not read.
- No account identifier, token, cookie, or credential value was printed or
  copied into this project.

## Implemented behavior

- The provider menu now has `[C] ChatGPT/Codex login`.
- The submenu invokes only the official Codex CLI commands: browser login,
  device-code login, login status, logout, and opening Codex.
- The launcher exposes `--codex-login`, `--codex-device-login`,
  `--codex-status`, `--codex-logout`, and `--codex`.
- Every generated Claude profile mode contains an ignored `.claude.json` with
  a local absolute Claudy MCP command and `CLAUDY_PROJECT_ONLY=1`.
- The bridge does not contain an API key or Codex auth data.

## Observed checks

1. Windows PowerShell self-test passed for DPAPI and project-local bridge
   generation.
2. The non-network menu smoke entered `[C]`, displayed the five Codex actions,
   returned to the provider menu, and exited normally.
3. Local Claudy MCP `initialize` and `tools/list` returned successfully. The
   tool list contained `ask_agent` and discovered `codex`; no `ask_agent` task
   was sent and no provider prompt was executed.
4. The existing global Claude JSON file was not a target of the new writer; the
   generated bridge was under the project's ignored mode directory.
5. Cumulative smoke gates passed 6/6 in run
   `20260824T070306Z-eba22755`.

## Boundary

The explicit Codex login route uses Codex's own shared app/CLI cache outside the
project because that is how the official app/CLI integration works. This is an
owner-triggered exception, not a hidden project dependency. Claude can delegate
selected tasks to Codex; ChatGPT/Codex does not become the provider for every
Claude prompt.

## Reproduction

- Double-click `RUN_CLAUDE.bat`, then choose `[C]`.
- Choose `[1]` and complete the browser/2FA flow yourself.
- In a Claude session, ask it to `Ask codex ...` for a delegated task.
- Use `[C]` option `[4]` or `RUN_CLAUDE.bat --codex-logout` before switching to
  another ChatGPT account.

No real provider session was run by this evidence item.
