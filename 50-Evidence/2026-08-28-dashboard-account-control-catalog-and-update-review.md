# Evidence — Dashboard account control, dynamic catalog and update review

- Date: 2026-08-28
- Scope: project-local UI/account controls, cold-start containment, dynamic
  Google model discovery and read-only dependency review
- Secret boundary: no password, 2FA, access token, refresh token, API key,
  provider account ID or session transcript is retained in this evidence

## Baseline

- Parent branch was `claude`, synchronized with `origin/claude` at
  `9944d39` before this change.
- All 21 then-enabled smoke gates passed in baseline run
  `20260827T174723Z-3276654e`.
- Runtime versions observed before update: Claude Code `2.1.241`, CCR
  `3.0.21`, project-patched CLIProxyAPI `7.2.141-local.4` and project-local
  Codex login helper `0.149.0-alpha.4.1`.

## Root causes and implemented controls

- Google account cards had an empty model list because the dashboard returned
  a literal empty array; no dynamic catalog adapter existed.
- The dashboard now requests Antigravity's model catalog for each completed
  project-local Google slot, normalizes only non-secret model metadata and
  caches it under ignored runtime state. No transient model name from a
  screenshot is hard-coded.
- A failed catalog refresh is now a failure, not a successful empty sync.
- Codex accounts, Google accounts and custom API providers have an owner-facing
  removal action. Removal is rejected while a relevant Claude terminal is
  running and moves project-local state into ignored recovery trash with a
  manifest; it does not permanently unlink credentials.
- CCR synchronization recognizes the local removed-account index so a removed
  Codex provider/plugin is not silently preserved in the router database.
- Dashboard startup performs one throttled hidden router warm-up. Repeated
  dashboard opens may use an exact PID/instance/server-hash identity cache;
  the first check for a new server instance still performs full verification.
- The UI is original project code using compact semantic design tokens,
  keyboard focus states, reduced-motion support and clearer account actions.
  Fluent UI design tokens were used as a reference; no third-party UI runtime
  or copied component source was introduced.

## Live Google catalog observation

- Four completed Google slots were discovered without exposing their auth
  payloads.
- Direct bounded catalog requests returned HTTP 401 for all four slots while
  the separate quota adapter remained usable.
- The exact reviewed `7.2.141-local.4` CLIProxyAPI binary loaded one sanitized
  test slot and returned HTTP 200 with an empty `/v1/models` list. The exact
  verified test process was stopped afterward.
- Therefore current Google OAuth state plus the old proxy build does not prove
  any launchable model. The dashboard deliberately shows no model rather than
  inventing the Antigravity screenshot catalog.

## Read-only dependency review

- Claude Code latest reviewed release: `2.1.247`. Relevant changes include
  recovery around large hook/background output, subagent first-call fallback
  and the official `/claude-api cost-optimize` command. Recommendation: update
  the closed binary only after the normal backup/gate checkpoint.
- CCR latest reviewed release: `3.0.22`. Relevant fixes include SSE multibyte
  handling and provider usage/meter preservation. Recommendation: exact-tag
  isolated pilot; do not merge the generated upstream `main` diff wholesale.
- CLIProxyAPI latest reviewed release: `7.2.143`. Its Antigravity/Gemini model,
  quota observation, tool-call and credential-rotation fixes directly overlap
  the current Google catalog failure. Recommendation: rebase the local isolation
  patch onto the exact tag, rebuild and run the challenger gates before any
  runtime promotion.
- Codex login helper latest reviewed release: `0.150.1`. The current helper
  completes project-local login/usage reads; recommendation: hold until a
  release fixes an observed helper problem.
- No dependency was downloaded, merged, rebuilt or promoted by this review.

## Token-optimizer disposition

- `edouard-claude/snip`: only plausible bounded future pilot. It rewrites shell
  output through hooks, so it requires a pinned project-local build, golden
  output fixtures and fail-open behavior before use.
- `Sagargupta16/claude-cost-optimizer`: primarily guidance/configuration and can
  trade quality for lower cost. Prefer Claude's reviewed official cost command.
- `nadimtuhin/claude-token-optimizer`: rejected for normal use because broad
  CLAUDE.md/.claudeignore rewriting can hide required project memory.
- `dongnh311/claude-context-saver`: rejected for this Windows project because
  of platform/maturity/log-retention concerns and overlap with existing
  project-local sessions and codebase memory.
- None of these repositories was installed.

## Fallback safety decision

- Automatic fallback remains disabled. Rotating multiple Free accounts after
  quota exhaustion can look like quota/rate-limit circumvention and increases
  account-policy risk.
- A future safer pilot may use a finite owner-approved cross-provider chain,
  one fallback hop, no parallel racing, no retry after streamed output or a
  tool side effect, and immediate stop on authentication/abuse/rate-limit
  signals. Same-provider account switching remains manual.

## Verification and rollback

- Offline account/catalog contract, Node syntax/self-test, TypeScript build,
  router self-test and the cumulative smoke suite are the promotion gates.
- The first cumulative run passed 21/22 gates and exposed a verifier boundary:
  the terminal-history gate sliced through the following recoverable account
  removal functions and therefore saw their `unlinkSync` marker. The cleanup
  function itself was unchanged and never touched a process, session or
  transcript. Its verifier was narrowed to that exact function.
- Final owner-profile run `20260827T182318Z-5de9b19c` passed all 22 enabled
  smoke gates, including DPAPI, external Codex App isolation, dynamic Google
  onboarding, dashboard lifecycle/session/history and account management.
- Rollback is the preceding parent commit plus ignored recovery trash. The
  existing CCR/runtime/provider auth state was not replaced by this change.
