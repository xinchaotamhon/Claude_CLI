# API profile menu and repository review evidence — 2026-08-24

## Scope

This is historical evidence for the superseded direct menu. The current
operational implementation is recorded in
[2026-08-24-claudy-integration.md](2026-08-24-claudy-integration.md).

Reviewed the eight user-supplied API/profile switcher candidates and completed
the local profile-menu implementation inside this project. No third-party
installer, global npm package, `PATH` edit, `System32` copy, or external
repository was installed. No real API key was entered or recorded.

## Local implementation checks

| Check | Expected | Observed | Verdict |
|---|---|---|---|
| `tools/claude_profile_menu.ps1 -SelfTest` under Windows PowerShell | DPAPI protects and recovers a fixed test value | `PASS: Windows DPAPI profile secret round-trip` | PASS |
| `tools/verify_local_setup.py .` | Required launcher, docs, menu, binary, and isolation markers exist | `PASS: local project layout is complete` | PASS |
| `RUN_CLAUDE.bat --version` | Use only `bin\claude.exe` and exit 0 | `2.1.241 (Claude Code)`; exit 0 | PASS |
| Smoke tier | Every enabled required gate passes | Six of six passed in run `20260823T171447Z-ac9239d8` | PASS |

The smoke logs are in
[gate-logs/20260823T171447Z-ac9239d8](gate-logs/20260823T171447Z-ac9239d8/).

## External review result

- `Claudy` is the strongest feature match for multi-provider routing, but its
  documented installer/configuration and plaintext `secrets.env` path do not
  satisfy this project's local secret boundary.
- `claude-switcher` is the best external candidate for a later Windows
  Credential Manager experiment, subject to release/source audit.
- `ccswap` is simple but writes the normal user-level Claude profile layout.
- `claudio` is a good 1Password-specific design, not a self-contained folder
  runtime.
- `cc-cli`, `zcs`, and the exact crates.io `cc-switch` candidate were not
  promoted because the exact source/release evidence was insufficient in this
  review.
- `claude-key-manager` was not promoted because its small project and mixed
  public packaging/source descriptions require an exact-revision audit.

Detailed comparison and source links are in
[docs/REPO_EVALUATION.md](../docs/REPO_EVALUATION.md).

## Remaining unknowns

Interactive login, provider reachability, account entitlement, rate limits,
and real Claude task execution were intentionally not tested. Those actions
require the Human owner to enter a real credential and approve network use.
