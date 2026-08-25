# Phase 2 account onboarding and warm start — 2026-08-25

## Scope and owner boundary

The owner authorized project-local account onboarding for Claude CLI and asked
for faster route launch. The owner later clarified that switching Codex App
accounts when its five-hour quota is exhausted is unrelated to this project.
No global Codex App authentication, account switching or quota UI was added.

No password, 2FA value, OAuth payload, API key, `setting.json`, CCR database or
real account auth file was read for this implementation or evidence record.

## Account contract

`router_challenger/account-batch.example.json` and its validator require exactly
seven secret-free slots in this order:

1. `codex_free_1` — Terra/Luna
2. `codex_free_2` — Terra/Luna
3. `codex_free_3` — Terra/Luna
4. `codex_plus_1` — Sol/Terra/Luna
5. `google_pro_1`
6. `google_pro_2`
7. `google_pro_3`

Every Google slot keeps `gemini_models` and `claude_gpt_models` as independent
usage groups. Duplicate IDs/labels, unknown fields, secret-shaped fields,
incorrect provider/plan bindings and automatic fallback are rejected. Twelve
positive/negative unit tests passed.

## Codex plan-aware login

`SIGN_ACCOUNT.bat` now offers separate Free and Plus login choices. Each browser
login still uses the pinned project-local Codex helper and a separate ignored
`CODEX_HOME`. The owner-declared plan is non-secret metadata used only to choose
the candidate set: Free excludes Sol; Plus probes Sol/Terra/Luna. Actual model
availability remains provider-controlled and is retained only after the bounded
existing route check. Accounts imported by older versions default to Free.

## Google OAuth isolation

The nested CLIProxyAPI source remains pinned to audited upstream `v7.2.141` and
now has this exact two-commit local series:

- `d3177d8ecd1c99d566fbe6e6ca1ba19a2be7ddc4`: suppress remote updater requests
  under `--local-model`.
- `3a3df12d068ac3a3bff2712db168ed1a7d31190a`: bind the Antigravity OAuth callback
  to IPv4 loopback only.

The patched tree is `37209cb0f5ba9a60e45a12742a8208fa7f49928d`.
Both format-patches, commits, order and SHA-256 values are verified from tracked
metadata. `go test ./sdk/auth ./cmd/server` passed.

The rebuilt ignored binary reports `7.2.141-local.2` and has SHA-256
`40f05398a6abac44698c2ecfa1d748869f37b2950ee2b98a1a58c97b4d4105ea`.

`tools/challenger_account_menu.ps1` provides three fixed Google slots under
ignored `.runtime/challenger/accounts/google`, with callback ports 51121–51123.
Before opening the official provider flow it verifies the binary hash, source
policy, tracked loopback patch, free callback port and current-user-only ACL.
It does not parse credential JSON and refuses to overwrite an occupied or
incomplete slot. Offline self-test/static verification opened no browser and
made no provider request. Real OAuth remains an owner-interactive next step.

## RUN warm start

After printing available routes, `tools/router_project_menu.ps1` starts a
hidden, project-local `-WarmRouter` child without reading settings, DPAPI,
account data or providers. If the warm process is still starting when a route
is selected, the parent waits for at most one second before using the original
synchronous verified start. Exact process identity, loopback management and
gateway HTTP health remain mandatory before DPAPI client-key access.

Seven focused warm-start tests passed. An already-running verified gateway took
987 ms through a fresh PowerShell `-WarmRouter` invocation. This measurement is
not a cold-start claim; live first-start latency remains owner-observable.

## Verification

- `tests/test_account_batch.py`: 12 passed.
- `tests/test_router_startup_optimization.py`: 7 passed.
- `tools/verify_account_import_flow.py`: passed.
- `tools/verify_challenger_account_flow.py`: passed without auth/network.
- `tools/verify_cli_proxy_source.py`: exact source/patch verification passed.
- JSON parsing for gates, source, build and account manifest: passed.
- First cumulative run `20260825T163959Z-1811586c`: 15/17 passed. The local
  layout verifier correctly rejected the newly added wrapper invocation because
  it had not yet been exact-whitelisted; DPAPI also hit the already known
  sandbox profile limitation.
- Final cumulative run `20260825T164115Z-8fc5f438`: all 17 enabled gates passed
  under the owner Windows profile after allowing only the exact project-local
  Google wrapper command. No broad process invocation rule was introduced.
- Documentation-integrated cumulative run `20260825T164233Z-42021e6c`: all 17
  enabled gates passed again under the owner Windows profile.

## Rollback

Revert the parent commit containing this evidence and the two local challenger
patches, then rebuild only through the explicit installer. Existing ignored CCR
and Codex account state is not deleted. Google slot removal, if later needed,
must target one exact resolved slot after the owner closes related processes;
never delete the project account root recursively by an unresolved variable.
