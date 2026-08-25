# Evidence — menu cleanup, fast startup, and Codex account switch

---
observed_at: 2026-08-24
observer: codex
status: verified
---

## Requested cleanup

- The old generated profile metadata identified exactly one profile,
  `legacy-qhieu`, under the project's ignored `.claudy-local` directory.
- Before deletion, the resolved targets were confirmed to be inside
  `claudy_provider-clitool/.claudy-local`:
  `profiles/profiles.json`, `profiles/secrets/legacy-qhieu.dpapi`, and
  `modes/legacy-qhieu`.
- The menu migration removed only that profile record, its DPAPI ciphertext,
  and its mode directory. It did not read or print the ciphertext, and did not
  touch any global Claude/Codex path.
- After migration, `profiles/profiles.json` is `[]`; the exact DPAPI file and
  mode directory are absent. New launches do not seed the retired profile.

## Menu and account behavior

- A normal no-argument launch now opens the provider menu without waiting for a
  network update check. `[U]` and `--check-updates` remain explicit update
  actions.
- The main menu is grouped into `CLAUDE PROVIDER PROFILES` and `ACTIONS`, with
  one action per line and a clear no-profile state.
- `[C]` now exposes six Codex actions: browser login, device-code login, status,
  account switch, sign out only, and open Codex CLI.
- `[C]` option `[4]`, or `RUN_CLAUDE.bat --codex-switch`, runs official Codex
  logout followed by browser login. This switches the one active account in
  the shared Codex/App cache; it does not create unofficial token slots or
  copy authentication data into the project.

## Verification

1. PowerShell parser: PASS.
2. `RUN_CLAUDE.bat --version`: PASS, `2.1.241 (Claude Code)`.
3. `RUN_CLAUDE.bat --claudy-version`: PASS, `claudy 0.8.0`.
4. `tools/verify_claudy_integration.py .`: PASS; no secrets read and no
   network used by the verifier.
5. Menu self-test: PASS for Windows DPAPI round-trip and project-local
   Claude-to-Codex MCP bridge generation.
6. Non-network menu smoke displayed the new layout, displayed `[C]` options
   `[1]`–`[6]`, returned to the main menu, and exited normally.
7. Cumulative smoke gates passed 6/6 in run
   `20260824T073736Z-966e74d4`.

## Owner usage

- Double-click `RUN_CLAUDE.bat` with no arguments to see the main menu.
- Press `[C]`, then `[3]` to inspect Codex status or `[4]` to switch to another
  ChatGPT account through browser/2FA.
- The direct `--codex-login` flag intentionally opens only the official Codex
  login flow; it does not render the provider menu. Use the no-argument file to
  render the menu.
