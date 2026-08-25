# Evidence — project-local Codex account import

Date: 2026-08-24
Scope: `D:\mydata\new-git-3\claude_CLI-V`

## Baseline

- Before implementation, all 7 enabled required smoke gates passed in run
  `20260824T102151Z-22edf786`.
- No real `setting.json`, Codex auth payload or CCR SQLite credential was read
  into evidence.

## Confirmed root cause

- CCR source `packages/core/src/agents/local-providers/codex.ts` resolves the
  candidate from `CCR_INTERNAL_HOME_DIR/.codex/auth.json` before falling back to
  the normal user home.
- Project launcher evidence shows `CCR_INTERNAL_HOME_DIR` is deliberately
  `provider_router/.ccr-local/home`.
- CCR UI source hides `LocalAgentProviderImportPanel` when the candidate list is
  empty. Therefore the screenshots showing only OpenAI/Anthropic/Gemini/custom
  presets are the expected symptom of isolation, not a missing button the user
  overlooked.

## Implemented behavior

- `SIGN_ACCOUNT.bat` enters the project account/API menu.
- Explicit option 1 stages only the fixed current-Windows-user Codex auth file,
  invokes CCR's authenticated native import RPC, creates unique provider/plugin
  identity, adds a secret-free local route and always removes staging.
- Import refuses to run while a verified Claude/router gateway is active.
- Imported account routes are combined with enabled `setting.json` routes by
  `RUN_CLAUDE.bat`; option 2 still opens CCR UI for API endpoints/keys.
- The wrapper never runs Codex CLI or prints/parses OAuth fields.

## Offline observations

- Router menu `-SelfTest`: PASS for fake multi-account plugin materialization,
  secret-free account-route round trip, prior setting merge, safe defaults and
  DPAPI. It made no management RPC or provider request.
- `tools/verify_setting_flow.py .`: PASS without reading real settings.
- `tools/verify_account_import_flow.py .`: PASS without reading real auth.
- Real account import/model request: intentionally not run in this change.

## Final gates

Final cumulative smoke run: `20260824T103149Z-275a88e5`; all 8 enabled
required gates passed on the same tree. Raw logs are under
`50-Evidence/gate-logs/20260824T103149Z-275a88e5/`.

## Rollback

Restore the prior launcher/menu files and remove only reviewed imported account
records. External Codex login files are read-only inputs and are never deleted
or changed by rollback.
