# Router candidate research — 2026-08-25

## Outcome

No new router or UI was downloaded, installed, authenticated or executed. The
current CCR runtime remains the rollback champion. The bounded challenger is
CLIProxyAPI core; EasyCLIProxyAPI is considered only after the core independently
passes project-local and Claude-protocol gates. ZeroLimit and Quotio Desktop
remain comparison candidates rather than first-pilot dependencies.

## Owner-supplied raw inputs

The four raw reports remain outside the project and were not copied into Git.
Their SHA-256 values establish which inputs were reviewed:

- `Claude_CLI_Architecture_Report.md`:
  `CCE525D1902623F28A181E7347ED5E3B5FADEEDC7C4010E11DC3172057642420`
- `Claude_Code_Proxy_Security_Review.md`:
  `EFC2AE34D89BCC1712E35A5B69CBE01CBF912BEE187ABDFD5F94533A4F95C1A0`
- `deepseek_markdown_20260825_8b6254.md`:
  `4CDF25B7AFCAC77A8741577F41AFF0FBA7ADC9B5E6DAE3A16E7D13CCDDD754C9`
- `deepseek_markdown_20260825_b84239.md`:
  `D96EBD833DE6E7DB236B795402FC5370EBBB64B757C2EED8DD446E2621527567`

## Reliability assessment

- The LiteLLM report proposed web-session adapters such as Clewd and
  go-chatgpt-api without source-linked proof. That increases credential and
  maintenance scope and is rejected for this project.
- Two security reports labelled broad ToS and source claims as `PROVEN` without
  direct primary evidence. One included placeholder/fabricated file and commit
  links. Their general cautions are useful; their factual labels are not
  adopted.
- The CLIProxyAPI-oriented report best matched the requested architecture, but
  several details were stale or wrong: Quotio Desktop is now a Windows/macOS/
  Linux Tauri port, EasyCLIProxyAPI exists as a maintained repository, and
  README feature claims do not prove project-local paths or session affinity.

## Primary observations

- OpenAI documentation confirms Codex clients support ChatGPT subscription
  login or API-key login, that file credential storage can be placed under
  `CODEX_HOME`, and that `/status`/the usage dashboard expose current limits.
  It does not by itself prove that an arbitrary third-party Claude harness is a
  supported Codex client.
- CLIProxyAPI is MIT licensed and advertises Claude-compatible endpoints,
  streaming, tools, multimodal input, Codex/Claude OAuth, API-key upstreams and
  multi-account round-robin. Its own README says built-in usage statistics were
  removed in v6.10.0, so account quota and locally observed request statistics
  must not be conflated.
- EasyCLIProxyAPI is a Tauri/React/Rust desktop manager from the same GitHub
  organization. It advertises OAuth, provider aggregation, quota inspection,
  version management and agent configuration. Automatic update and agent
  configuration are incompatible with this project's default isolation policy
  until disabled or fenced by source changes.
- ZeroLimit is a MIT cross-platform quota UI with portable Windows output, but
  it advertises automatic installation of updates. Quotio Desktop is also
  cross-platform and has broader scheduling/reset features. Each adds another
  supply-chain and global-configuration surface, so neither belongs in the
  first core pilot.
- Public CLIProxyAPI issues show real operational edge cases around exhausted
  account token refresh, account grouping and subscription metering. Therefore
  multi-account failover and quota display remain test subjects, not accepted
  capabilities.

Primary source locations reviewed:

- https://github.com/router-for-me/CLIProxyAPI
- https://github.com/router-for-me/EasyCLIProxyAPI
- https://github.com/0xtbug/zero-limit
- https://github.com/xiaocoss/quotio-desktop
- https://learn.chatgpt.com/docs/auth
- https://learn.chatgpt.com/docs/pricing

## Proposed bounded pilot requiring owner approval

### Phase 0 — source intake only

1. Clone CLIProxyAPI into an ignored nested repository on local branch
   `claude`; record upstream commit, tag, license and source hash in tracked
   metadata.
2. Do not run its installer, release binary, OAuth flow or provider request.
3. Inspect source for config/auth paths, listener binding, callback validation,
   telemetry, update logic, account selection and Anthropic translation.
4. Produce a patch series in the parent repository for any required local-path
   or provider-only changes; the nested checkout remains independently
   reviewable.

### Phase 1 — offline core runtime

1. Build or stage one pinned Windows core binary under an ignored runtime
   directory; verify version/hash and bind only to `127.0.0.1` on a port that
   does not conflict with CCR.
2. Use fake credentials and local fixture upstreams only. Do not open browser
   OAuth and do not consume provider quota.
3. Add focused gates for no writes outside the project, authenticated
   management, process identity, clean stop/restart, startup timing, Anthropic
   streaming and tool-call translation.
4. Keep `RUN_CLAUDE.bat` on CCR; expose the challenger only through a separate
   explicit pilot command.

### Phase 2 — one owner-authorized real account

Only after Phase 1 passes, use a fresh project-local OAuth home for one Codex
account. Prove login, refresh, fixed-account selection, Sol/Terra/Luna dynamic
entitlement, quota provenance and one minimal Claude turn. Do not enable
round-robin or automatic failover.

### Phase 3 — optional management UI

Evaluate EasyCLIProxyAPI first because it covers account/provider management
and quota in one component. Disable automatic update, agent reconfiguration,
system-default integration, global config discovery and non-loopback binding.
Add ZeroLimit or Quotio Desktop only if a named requirement remains missing and
the added component passes the same isolation gate.

## Acceptance and rollback

- Every existing required smoke gate must still pass.
- The challenger must not read or write global Codex, Claude, Gemini, AppData,
  registry, proxy or certificate state.
- Login must use the provider's browser page; no password, cookie or 2FA capture.
- Quota must be labelled `provider-reported`, `proxy-observed`, `estimated` or
  `unknown` and never merged into one misleading value.
- One Claude tool loop must remain on one account; failover is disabled until a
  deterministic session-affinity policy is proved.
- Rollback is stopping the challenger and continuing the existing CCR entry
  points and ignored state. CCR is not deleted during the pilot.

## Baseline

All nine enabled smoke gates passed under the owner Windows profile in
`20260825T125429Z-b9904aa4`. The CCR source fork patch was committed and pushed
on branch `claude` at
`ffc823b683861ad3f86c8dd38c0dbe61eef62f6c`.
