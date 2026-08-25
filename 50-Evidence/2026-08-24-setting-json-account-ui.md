# Evidence — root setting.json and CCR account UI

Date: 2026-08-24
Scope: `D:\mydata\new-git-3\claude_CLI-V`

## Baseline

- Before change: 6/6 enabled required smoke gates passed in run
  `20260824T091145Z-00e36291`.
- Claude: `2.1.241`; CCR: `3.0.21`; local Node: `v24.12.0`.
- Parent and nested source repositories were on branch `claude`.

## Source finding

Pinned CCR documentation states that live config is SQLite and legacy
`config.json` is consumed only once as a migration source. Source inspection
confirmed authenticated `/api/ccr/rpc` methods `getConfig`, `saveConfig`,
`saveApiKeys`, `getServiceIdentity`, local-agent candidate scan/import, and the
`x-ccr-web-auth` management-token boundary.

Therefore root `setting.json` is a project-owned schema synchronized through
RPC; it is not presented as CCR's native live JSON config.

## Implemented behavior

- Created ignored `setting.json` with a disabled, key-empty sample.
- Created tracked secret-free `setting.example.json`.
- Created the initial UI-only `SIGN_ACCOUNT.bat`; its current Codex behavior is
  superseded by `2026-08-24-project-local-codex-account-import.md`.
- Removed interactive Add/Edit/Delete provider/profile/client-key flows from
  the RUN menu.
- Added schema validation for providers, credential pools, profiles, tier
  routes and Claude defaults.
- Added SHA-256 change detection and authenticated merge of only
  `local-setting--*` providers into CCR SQLite; non-managed account/UI providers
  are preserved and name collision fails.
- Added automatic CCR client key reuse/generation and Windows DPAPI storage.
- Synchronization enforces loopback gateway/management, proxy/system proxy/
  capture/request logs off and Codex built-in rule off.

## Observed checks

- PowerShell parser: PASS.
- Menu isolated self-test: PASS for setting schema/tier route, managed-provider
  merge, non-managed account preservation, safe network/log defaults and DPAPI.
- `tools/verify_setting_flow.py .`: PASS without reading real `setting.json`.
- `tools/verify_router_integration.py .`: PASS.
- Real local sync: `-SyncSettings` returned
  `Applied setting.json to the project-local CCR database.`
- Piped menu smoke selected `Q`: PASS; displayed only profile selection,
  reload, status, stop, updates and quit.
- Provider/model request: intentionally not run; no quota or endpoint success
  is claimed.

## Account conclusion

CCR 3.0.21 can offer imports when it detects usable local state for supported
integrations documented in the pinned source, including Claude Code, Codex,
ZCode and Kimi CLI. `SIGN_ACCOUNT.bat` exposes this CCR UI but does not invent a
generic OAuth flow, convert arbitrary ChatGPT/Google website sessions, or prove
that any specific account is currently importable.

## Final gates

Final cumulative smoke run: `20260824T093357Z-b322d2c7`; all 7 enabled
required gates passed. Raw logs are under
`50-Evidence/gate-logs/20260824T093357Z-b322d2c7/`.

## Rollback

Stop CCR, restore the prior menu decision, remove only generated setting hash /
DPAPI client-key files, and explicitly review `local-setting--*` providers.
Never delete preserved non-managed account/UI providers as an automatic
rollback step.
