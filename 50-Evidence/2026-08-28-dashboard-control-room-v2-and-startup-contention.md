# Evidence — Control Room v2 and first-launch contention repair

- Date: 2026-08-28
- Scope: owner-facing route/account UX, truthful Google catalog state, and
  first-launch responsiveness
- Secret boundary: no ignored setting, credential, auth payload, account email,
  provider request body or Claude transcript was read or retained

## Baseline and accepted policy

- Branch `claude` started this slice synchronized with `origin/claude` at
  `5dcc2a2`.
- The previous owner screenshot proved that the native route `<select>` became
  a very long, ungrouped menu. Account cards also lacked a quick provider filter
  and Google cards did not explain why a completed login exposed zero routes.
- Automatic fallback remained disabled by owner decision. This slice did not
  add account rotation, provider retries or model-request traffic.
- Rollback is the preceding parent commit. Runtime/auth/session state is ignored
  and was not changed by the UI build or offline gates.

## UI/UX decision and implementation

- Fluent UI and Carbon were used only as design-system references: semantic
  tokens, visible focus, hierarchy, status feedback, density and progressive
  disclosure. No external component library, generated design source, CDN or
  browser dependency was added.
- The native route menu was replaced with an original project-owned picker that
  groups routes by provider, shows provider/model/account, supports text search,
  marks the current route, closes with Escape and becomes a bounded mobile
  panel at narrow widths.
- Account cards now have provider filters (`all`, Codex, Google, API) and local
  text search. A three-item status rail makes project isolation, fallback-off
  policy and update-candidate count visible without opening settings.
- Google cards expose sanitized catalog state. HTTP 401 is explained as an
  expired/unauthorized local OAuth context requiring deletion and re-login; an
  empty or failed catalog is never presented as a working model route.
- Launch now publishes an immediate pending notice. No success is reported
  until the existing terminal lifecycle acknowledgement is observed.

## First-launch root cause and repair

- The dashboard scheduled automatic account quota/catalog refresh 750 ms after
  server startup. Those helper probes could overlap the first owner launch with
  router/Claude cold start, creating avoidable process and network contention.
- The background start delay is now 15 seconds. An `activeLaunches` guard skips
  background refresh while any launch is awaiting acknowledgement; the normal
  five-minute refresh interval remains unchanged.
- This is containment of a proved local scheduling conflict, not a claim that
  all upstream API latency is eliminated. Provider cold starts, expired OAuth
  and upstream errors remain separate conditions and continue to fail visibly.

## Repository research disposition

- `microsoft/fluentui` and `carbon-design-system/carbon`: reference patterns
  adopted without runtime dependency.
- `vmware/clarity`: rejected as a dependency because the relevant Clarity Core
  repository is archived/unsupported.
- `assistant-ui`, `CopilotKit` and `vercel/ai`: held; they solve chat/agent
  runtime problems rather than this local control-room information hierarchy.
- `Sagargupta16/claude-cost-optimizer` and
  `nadimtuhin/claude-token-optimizer`: reference-only. Their broad instruction
  or ignore-file rewriting can hide required project memory and reduce quality.
- `edouard-claude/snip`: hold for a future offline golden-fixture pilot only;
  shell-output filtering can remove warnings or stack-trace context.
- `dongnh311/claude-context-saver`: rejected for this project because it
  overlaps existing session/codebase memory and expands MCP/log/build scope.
- No token optimizer was installed or vendored.

## Read-only update review on 2026-08-28

- Local Claude remains `2.1.247`; upstream `2.1.250` is a candidate. Release
  `2.1.248` includes a third-party `ANTHROPIC_BASE_URL` tool-use ID fix that is
  relevant to this multi-provider harness. No binary was downloaded or changed.
- Local CCR remains `3.0.21`; `3.0.22` stays HOLD because the published runtime
  did not preserve the exact project isolation patch anchors.
- Active CLIProxyAPI remains project-patched `7.2.143-local.1`; upstream
  `7.2.144` is a candidate for an exact-tag isolated pilot. Its release fixes
  Codex reasoning compatibility, websocket handling and Claude/Gemini mapping,
  but there is no evidence yet that it repairs this project's empty Google
  model catalog.
- The working Codex login helper remains `0.149.0-alpha.4.1`. Upstream stable
  `0.150.1` and alpha `0.151.0-alpha.8` contain no proved fix required by the
  current project flow, so the helper remains HOLD.

## Verification

- TypeScript no-emit check: pass.
- Node syntax check and dashboard self-test: pass.
- Vite production build: pass; 15 modules; tracked hashed CSS/JS regenerated.
- Focused verifiers passed for local dashboard security, account/catalog
  management, acknowledged action lifecycle, recoverable session trash and
  closed-terminal history cleanup. They made no provider/model request and did
  not read ignored auth/settings.
- All 22 enabled smoke gates passed under the owner Windows profile in run
  `20260828T065757Z-4d29afba`, including DPAPI and external Codex App isolation.
- The verified dashboard replacement then started on loopback with PID `10040`;
  ready-state hash matched the current `server.mjs` hash and `/health` returned
  success. Router and existing Claude terminals were not stopped.
- The in-app browser blocked loopback navigation with
  `ERR_BLOCKED_BY_CLIENT`. A fallback Chrome visual inspection was stopped when
  concurrent user input was detected; no UI action was forced. Therefore the
  build and semantic structure are proved here, while final owner visual taste
  remains an explicit human acceptance step.

## Bounded next actions

1. Owner refreshes `DASHBOARD.bat`, opens the route picker and judges the new
   hierarchy/search at normal window size.
2. Delete/re-login one stale Google slot from the dashboard, then run dynamic
   catalog sync. Do not hard-code screenshot model names.
3. Review Claude `2.1.250` and CLIProxyAPI `7.2.144` in isolated rollback
   pilots; promote only after the cumulative gates and one bounded live proof.
