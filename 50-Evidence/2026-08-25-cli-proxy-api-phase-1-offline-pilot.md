# CLIProxyAPI Phase 1 offline pilot — 2026-08-25

## Outcome

The bounded challenger passed an offline Windows pilot without replacing CCR.
`RUN_CLAUDE.bat`, `SIGN_ACCOUNT.bat`, the active CCR runtime and all real
provider/account state were left unchanged. No OAuth flow was opened and no
OpenAI, Google, Anthropic or other provider inference request was sent.

The new user-facing entry is `RUN_CHALLENGER_PILOT.bat`. It exposes only an
offline self-test, verified status and verified stop. It does not yet launch a
real Claude session or account login.

## Source and build identity

- Audited upstream: CLIProxyAPI `v7.2.141`, commit
  `dc3c3b1ec3ed04bb0917e76451eaf98c6842674d`.
- Local isolation patch commit:
  `d3177d8ecd1c99d566fbe6e6ca1ba19a2be7ddc4`; patched tree
  `4e8c65286d56f3e03b0a39696a931d75db126fd9`.
- Tracked patch SHA-256:
  `e45a879854608fdac862a418bdaa3b06d28252b7ca40aed5c2f58aef2601a209`.
- Project-local toolchain: official Go `1.26.7` Windows amd64 archive;
  SHA-256
  `f4f534a486e4bc3387fa18f08208f2f854b7aaea8a08f2a2d829a914a05abb11`.
- Ignored challenger binary: 65,937,920 bytes; SHA-256
  `830e9ff8f4526ec5d7ca9f620dc26881dd854023edea1b33452fcc3de17ad17e`.
- Ignored deterministic fixture binary: 8,830,976 bytes; SHA-256
  `f3205d4fa5102b2f8e1d4748dccc028929e84078b9911420116c35122aef48e2`.

`router_challenger/SOURCE.json` and `router_challenger/BUILD.json` are the
machine-readable owners. `tools/install_challenger_pilot.ps1` reconstructs
source/toolchain explicitly; neither normal launcher downloads anything.

## Isolation patch

The only CLIProxyAPI source change adds a pure decision function and guards the
two `StartAntigravityVersionUpdater` calls. With `--local-model`, both remote
model-catalog refreshes and the Antigravity version-manifest updater are now
suppressed. Default upstream behavior remains unchanged when the flag is not
used. `go test ./cmd/server` passed after formatting with the pinned toolchain.

## Runtime controls proved

The offline pilot creates one random ignored session directory under
`.runtime/challenger`, with an absolute auth path protected by a non-inherited
current-Windows-user-only ACL. It generates ephemeral local client,
management and fixture keys in memory/config, never commits them, and removes
the complete session after the test.

The candidate and deterministic upstream bind only to `127.0.0.1` on ports
18317 and 18442. The pilot verifies executable path and SHA-256 before reading
runtime state, verifies the PID executable before stopping it, checks listeners
with the owning PID and rejects any observed established non-loopback
connection. Control panel, panel updater, plugins, request/file logging, usage
statistics, retries, proxy inheritance and automatic failover are disabled.

Two complete runs proved:

- Anthropic `/v1/messages` non-stream translation.
- Anthropic SSE lifecycle and content translation.
- One Claude tool-use response followed by a tool-result completion.
- Clean verified stop and restart.
- First measured run: startup 521 ms, restart 519 ms.
- Reproducible rebuild run: startup 538 ms, restart 518 ms.

These results prove only deterministic local protocol behavior. They do not
prove OAuth refresh, provider entitlement, real Claude Code multi-tool sessions
or quota reporting.

The final cumulative run `20260825T151944Z-d9df7999` passed all 14 enabled
smoke gates. An immediately preceding run passed 13/14 and failed only because
the new pilot gate invoked legacy Windows PowerShell, where `Get-FileHash` was
not resolved; changing the gate to the same exact PowerShell 7 used by existing
project gates fixed the harness mismatch without changing runtime behavior.

## Quota contract

The tracked secret-free contract requires Google AI Pro to expose exactly two
independent usage groups: `gemini_models` and `claude_gpt_models`. Each group
requires weekly status, remaining percentage and reset time. A five-hour window
is optional. If a value is unknown/unavailable, percentage and reset must be
null and a reason is mandatory. Ten unit tests passed; secret-shaped fields are
rejected recursively.

No code currently scrapes or claims live Google quota. The screenshot supplied
by the owner is treated only as the desired display/data distinction. A future
provider adapter must prove the source and label values provider-reported,
proxy-observed, estimated or unknown.

The fallback contract is account-aware: every allowlisted account has its own
two Google usage groups, and each route resolves quota through its account.
Known five-hour depletion removes the route even if weekly quota remains. With
unknown/missing five-hour data, a primary route can still be selected, but a
fallback occurs only after an allowlisted quota/rate-limit signal and before
any upstream output/tool side effect. Chains are acyclic, finite and capped at
five attempts; the example uses two distinct accounts. Thirteen tests passed.

## Rollback

Stop only a PID that resolves to the pinned pilot executable, then remove the
ignored `.runtime/challenger`, `vendor/go`, `vendor/gomodcache`, `.cache/go-build`
and ignored `cli-proxy-api_core` directories if desired. Normal operation
continues through CCR and is unaffected. Do not delete CCR account/runtime
state as part of this rollback.
