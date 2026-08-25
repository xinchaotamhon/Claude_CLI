# Next AI Handoff

Read `START_HERE.md` and its complete local read order. Do not read ignored
`setting.json`, `.ccr-local`, account auth, SQLite or DPAPI data.

## Verified Baseline

- One harness only: project-local `bin/claude.exe` (Claude Code `2.1.241`).
- Router: local CCR `3.0.21` on Node `v24.12.0`; source fork branch `claude` at
  `ffc823b683861ad3f86c8dd38c0dbe61eef62f6c`, based on upstream
  `1347c868b493728a31c76098459584e0fcc23940`. Provider-only mode skips
  external Claude App/profile synchronization and uses a bounded configurable
  gateway acceptance timeout.
- `RUN_CLAUDE.bat` is selection-only; settings merge is authenticated,
  loopback-only and preserves non-file-managed providers.
- `SIGN_ACCOUNT.bat` option `[1]` runs only the pinned local Codex helper with a
  separate `CODEX_HOME`/`CODEX_SQLITE_HOME` under `.ccr-local/codex-accounts`.
  It does not inspect a global Codex App/CLI login or executable `PATH`.
- Local helper provenance: version `0.149.0-alpha.4.1`, SHA-256
  `73d6d4a082a7cad601a446a45b1b3fa9b77aff9d3996052b74d9003d7947d515`.
- Browser handles account password/2FA. Wrapper never requests, parses or prints
  them or auth payloads. Codex helper is login-only, never an agent/harness.
- Owner observed successful local browser login. CCR's sole built-in fallback
  `gpt-5-codex` then failed a real Claude request with HTTP 400 because it is
  unsupported for this ChatGPT Free account. Direct gateway checks proved
  Terra and Luna complete; legacy `gpt-5-codex` and Sol are hidden. `[R]`
  refreshes candidates without browser login, and each retained model is a
  separate RUN route. Current code also preserves `_`/`.` route IDs and
  correctly enumerates multiple account profiles.
- Owner next selected the visible account route and observed generic CCR exit 1.
  A local bounded diagnostic observed no gateway health before the command, exit
  1 from `start --gateway`, and HTTP 200 afterward. Current code uses
  `Invoke-CcrStartAndVerify`: a start error is diagnostic, exact verified
  process/loopback/health is authoritative, and unverified startup still fails
  closed before DPAPI access.
- Owner later showed that external Codex App displayed `Claude Code Router` and
  no Usage. This was proved to be a CCR Codex agent profile with `System
  default` / `CLI & APP`, which wrote the local gateway into the global Codex
  config. The global config has been restored from a clean, hash-matched CCR
  snapshot on disk. The running Codex App may cache the old provider until a
  full restart. Normal project flows now remove all CCR agent profiles, apply
  takeover cleanup and expose no CCR agent UI.
- After explicit owner authorization, the seven identified CCR files and one
  identified CCR directory under external `.codex` were deleted exactly. All
  eight targets are absent and the active config hash remains unchanged.
- Explicit repair installer is project-scoped; no normal auto-install/update.
- Pre-change baseline 8/8: `20260824T172947Z-7cb886ff`; sanitized pre-fix
  failure: `20260824T173222Z-32aa653f`; focused post-fix pass:
  `20260824T173312Z-a0cee41d`; extended reader-plus-mode-path pass:
  `20260824T173807Z-f32e0a0f`. Deterministic tests made no real browser/provider
  request and did not read ignored state.
- CLOVER's updated portable-entry pattern was reviewed by exact path/hash. Only
  local path anchoring, exact missing-entry failure, navigation/authority
  separation and one-front-door-per-outcome were adopted. CLOVER is not a
  runtime or routine-continuation dependency.
- Integrated cumulative smoke result: all 8 enabled gates passed in
  `20260824T173932Z-43d5c46b`.
- Verified-start cumulative smoke result: all 8 enabled gates passed in
  `20260824T175012Z-6f2f15a6`.
- External-app-isolation cumulative result: all 9 enabled gates passed in
  `20260825T043650Z-959db717`; active global Codex config still matched the clean
  snapshot after the run and no project router listener remained.
- Codex-Free-route cumulative result: all 9 enabled gates passed in
  `20260825T052438Z-21e21f26`, including owner-profile DPAPI and the separate
  Terra/Luna account-route regression.

## Allowed Next Work

1. Ask the owner to restart Codex App and confirm its normal label and Usage.
2. Add a second account and verify explicit account switching after quota
   exhaustion; do not claim automatic fallback unless separately implemented
   and proved.
3. Use `[R]` only when account model entitlement changes; it sends bounded real
   connectivity requests and does not repeat OAuth login.
4. Improve UX while preserving per-account homes, local binary pin/hash,
   prompt-free RUN, loopback-only networking and Claude-only harness behavior.
5. Review updates without automatic merge or binary replacement.

## Boundaries

- Never reintroduce `C:\Users\...\.codex\auth.json`, user-profile discovery,
  a global `codex` command or Codex App shared auth.
- Never expose CCR Connect agent UI or allow `System default` / `CLI & APP`;
  CCR is a provider gateway only in this project.
- Never use Codex helper for `exec` or agent work; only exact local `login` is
  authorized by this wrapper.
- Never read/print/commit settings, auth, OAuth, SQLite, DPAPI, cookies, request
  bodies or logs.
- Do not claim account/model/quota switching works until owner-run evidence
  proves it. Filesystem independence still requires provider network service.

## Definition of Done

- `tools/verify_router_integration.py .` passes.
- `tools/verify_setting_flow.py .` passes without reading `setting.json`.
- `tools/verify_account_import_flow.py .` passes without reading auth.
- `tools/verify_external_app_isolation.py .` passes without reading external
  config/auth.
- Menu `-SelfTest` passes under the owner Windows DPAPI profile.
- All enabled smoke gates pass on the final artifact.
- State/evidence/handoff remain current and secret-free.
