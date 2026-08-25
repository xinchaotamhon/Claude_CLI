# CLIProxyAPI Phase 0 source audit — 2026-08-25

## Outcome

CLIProxyAPI is a useful challenger but is **not safe to run unchanged** under
this project's isolation contract. Source tag `v7.2.141` is retained only as an
ignored, independent nested checkout on local branch `claude`. No candidate
binary was built or started, no OAuth flow was opened, no credential was read,
and no provider inference request was sent. `RUN_CLAUDE.bat` still uses CCR.

The source intake used GitHub network access only to clone the public source.
The audit and source verifier are offline.

## Exact source identity

- Upstream: `https://github.com/router-for-me/CLIProxyAPI.git`
- Tag: `v7.2.141`
- Commit: `dc3c3b1ec3ed04bb0917e76451eaf98c6842674d`
- Tree: `320d4056873d7e8fd036c568db493acc0e565dc7`
- Commit date: `2026-08-24T16:35:18+08:00`
- License: MIT; `LICENSE` SHA-256
  `93df585e5fa07ead6d47a3ab2dbdf0255782a39fe830022c0274a70394223cc8`
- Required toolchain: Go `1.26.0`; no `go` executable was available on this
  machine at audit time.

Tracked `router_challenger/SOURCE.json` contains the remaining anchor hashes.
`tools/verify_cli_proxy_source.py` checks the metadata and, when the ignored
checkout exists, verifies its exact root, clean tree, branch, tag, commit, tree,
single upstream remote and source anchors without network access.

## Proven source behavior

### Isolation defaults fail closed only after local overrides

- `config.example.yaml` defaults `host` to empty, which binds all interfaces.
  The pilot must explicitly use `127.0.0.1`.
- `auth-dir` defaults to `~/.cli-proxy-api`; `ResolveAuthDir` expands it through
  the user home. The pilot must use an absolute directory inside this project.
- `.env` is loaded from the current working directory and the default
  `config.yaml` is also resolved from that directory. A launcher can contain
  both by setting its working directory explicitly.
- Management denies non-local clients when `allow-remote: false`, requires a
  management key even from localhost, and disappears when no key is set.
- Disabling the control panel prevents its GitHub asset updater. Using
  `--local-model` prevents both remote model-catalog updaters.
- A separate Antigravity version updater still starts unconditionally and
  immediately calls
  `antigravity-hub-auto-updater-974169037036.us-central1.run.app`, then repeats
  every three hours. `--local-model` does not stop it. This requires a bounded
  source patch before any offline runtime pilot.
- OAuth files are JSON. Direct file-store paths request directory mode `0700`
  and file mode `0600`, but the source contains no DPAPI/Windows credential
  encryption path. Windows mode bits do not by themselves prove a restrictive
  ACL. The runtime wrapper must create and verify a current-user-only ACL, and
  the UI must describe storage as project-local plaintext protected by ACL,
  not encrypted storage.
- Source scanning found no Sentry, PostHog or telemetry SDK integration; the
  sole telemetry string was a comment about filtering Claude client headers.
  This does not eliminate ordinary provider requests or the update checks
  described above.

### Claude harness and model routing

- The server registers `POST /v1/messages` and
  `POST /v1/messages/count_tokens`; `ClaudeMessages` routes streaming and
  non-streaming requests through the common authenticated execution path.
- Translation and sentinel tests cover Claude message/tool shapes, session ID
  extraction, provider-specific thinking signatures and Codex execution from
  Claude-format input. These are useful source signals, not an end-to-end proof
  of a complete Claude Code tool loop.
- Codex OAuth metadata carries `plan_type`. Embedded model catalogs currently
  expose:

  - Free: `gpt-5.4-mini`, `gpt-5.5`, `gpt-5.6-terra`, `gpt-5.6-luna`,
    `codex-auto-review`.
  - Plus: all of the above plus `gpt-5.3-codex-spark`, `gpt-5.4` and
    `gpt-5.6-sol`.

- Model registration is per auth ID and `authSupportsRouteModel` rejects an
  account that does not advertise the requested route model. Therefore the
  source design can keep Sol away from a recognized Free account and select a
  Plus/Pro/Team account that advertises Sol. This remains inferred for a live
  mixed Free+Plus login until Phase 2 proves it.

### Multiple accounts and quota

- Supported strategies are round-robin, weighted round-robin and fill-first.
  Session affinity binds a Claude session/model/provider tuple to one auth for
  one hour by default and reselects only when that auth becomes unavailable.
- Management can disable or enable an individual auth file. A project UI or
  wrapper could implement explicit account selection by enabling only the
  chosen auth, but no built-in fixed-account launcher was proved. That control
  must be tested before automatic failover is enabled.
- `GetAPIKeyUsage` reports local success/failure/recent-request counts only for
  API-key credentials. OAuth auth entries expose local status, cooldown and
  reset controls. Source searches found no 5-hour or weekly quota schema and no
  provider quota-fetch endpoint. The core therefore does **not** satisfy the
  owner's quota-dashboard requirement by itself.
- `ResetQuota` clears local cooldown/routing state; it does not reset a
  provider subscription quota. Any future UI must label this accurately.

## Root cause versus containment

The current CCR cold-start defect and CLIProxyAPI's isolation defaults are
different problems. CLIProxyAPI may replace CCR only after proving a faster,
stable runtime. Merely cloning it contains nothing. Current containment is to
leave CCR active and the challenger unbuilt/unstarted.

## Phase 1 changes requiring owner approval

1. Install or stage a pinned Go `1.26.x` toolchain inside this project; do not
   add system PATH entries.
2. Create a small source patch so `--local-model` also suppresses the
   Antigravity version updater. Keep the patch as a reviewable commit on the
   nested `claude` branch.
3. Build a pinned Windows binary into an ignored project runtime and record its
   hash. Bind only `127.0.0.1` on a non-CCR port.
4. Use an absolute project auth directory, disabled control panel, disabled
   panel update, local model catalogs, authenticated local management,
   file/request logging off and current-user-only Windows ACL.
5. Test only fake credentials and a local fixture upstream. Add isolation,
   startup-time, identity, stop/restart, Anthropic streaming and tool-loop
   gates. Keep the pilot behind a separate command; do not alter
   `RUN_CLAUDE.bat`.

Rollback is deleting the ignored candidate runtime and continuing CCR. The
nested source checkout and tracked audit metadata are not runtime dependencies.

## Unknowns retained

- Real Codex OAuth refresh, mixed Free/Plus model entitlement and automatic
  failover behavior.
- Provider-reported 5-hour/weekly quota, especially Google Pro and OpenAI.
- Full Claude Code multi-tool fidelity, cancellation and long streaming turns.
- Whether EasyCLIProxyAPI can be fenced from global agent configuration and
  automatic updates without a maintained local patch.

## Verification

- The first cumulative run, `20260825T133535Z-7097f80b`, passed 9 of 10 gates.
  `foundation.memory-routing` correctly rejected an example key string inside
  the ignored CLIProxyAPI README because its ignore set knew the older CCR
  source checkout but not the new equivalent checkout. No project credential
  was found.
- The memory auditor was extended by one exact ignored directory name,
  `cli-proxy-api_core`; tracked project documentation remains scanned.
- All 10 enabled smoke gates then passed in
  `20260825T133632Z-91288459`, including Windows DPAPI self-test, existing CCR
  isolation/account gates and the new offline source-pin gate.
